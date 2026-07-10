//
//  PreventDisablingView.swift
//  The friend-assisted Screen Time lock — the only real way to stop yourself
//  from turning off Demora's Screen Time access. Demora can't block that in iOS
//  Settings, but a second person holding the Screen Time passcode (with their
//  own recovery Apple ID) can. Shown inline during onboarding and behind a
//  delayed, one-time gate under Help.
//

import SwiftUI
import Combine

/// The actual how-to steps. Reusesd by the onboarding intro and the Help gate.
struct PreventDisablingContent: View {
    @EnvironmentObject var model: AppModel
    @State private var codeDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Demora can't stop you from turning off its Screen Time access in iOS Settings — but a friend can. If Screen Time itself is locked with someone else's passcode, iOS blocks any change to Demora's access, while Demora keeps doing all the blocking."))
                .font(.subheadline).foregroundStyle(.secondary)

            Label(tr("Takes about 2 minutes, and you need a second person physically with you."),
                  systemImage: "person.2.fill")
                .font(.footnote.weight(.medium)).foregroundStyle(Ink.accent)

            step(1, tr("Open Settings → Screen Time on this iPhone. If it's off, turn it on."))
            step(2, tr("Tap “Lock Screen Time Settings” (or “Use Screen Time Passcode”)."))
            step(3, tr("Hand your phone to your friend. Have THEM enter a 4-digit passcode you don't see — don't watch."))
            step(4, tr("When asked for Screen Time Passcode Recovery, your friend signs in with THEIR OWN Apple ID — not yours. That's what stops you from resetting the passcode on your own."))
            step(5, tr("Done. Now you can't disable Demora's access — or change the passcode — without your friend. To undo it later, your friend enters the passcode and turns it off."))

            Label(tr("Pick someone you trust and can reach. If the passcode and its recovery Apple ID are both lost, removing it may require erasing the device."),
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)

            Divider().padding(.vertical, 4)

            // A place for the friend to stash the passcode they set. Viewing it
            // lives behind the same delay gate as this page, so it can't be
            // pulled up on impulse to turn Demora off.
            VStack(alignment: .leading, spacing: 8) {
                Label(tr("Store the Screen Time passcode"), systemImage: "key.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.ink)
                Text(tr("Friend: save the passcode here so it isn't lost. It's only shown from this page, which is behind your delay."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField(tr("Passcode"), text: $codeDraft)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled()
                    Button(tr("Save")) { model.setScreenTimeCode(codeDraft) }
                        .buttonStyle(.bordered)
                        .disabled(codeDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !model.screenTimeCode.isEmpty {
                    Text(String(format: tr("Saved passcode: %@"), model.screenTimeCode))
                        .font(.footnote.monospaced()).foregroundStyle(Ink.accent)
                }
            }
            .onAppear { codeDraft = model.screenTimeCode }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.headline).foregroundStyle(Ink.accent)
                .frame(width: 20, alignment: .trailing)
            Text(text).font(.subheadline)
        }
    }
}

/// Help entry: access is gated behind the less-strict delay and good for a
/// single open, so you can't impulsively look it up to undo your own lock.
struct PreventDisablingGateView: View {
    @EnvironmentObject var model: AppModel
    @State private var showContent = false
    @State private var storeDraft = ""
    @State private var savedFlash = false
    // Drives a re-render each second so the countdown→ready transition shows
    // without leaving the screen.
    @State private var refresh = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(tr("Make Demora impossible to disable"))
                    .font(.title3.bold())

                // Storing the passcode is free; viewing it is gated below.
                VStack(alignment: .leading, spacing: 8) {
                    Label(tr("Store the Screen Time passcode"), systemImage: "key.fill")
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        TextField(tr("Passcode"), text: $storeDraft)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .autocorrectionDisabled()
                        Button(tr("Save")) {
                            model.setScreenTimeCode(storeDraft)
                            storeDraft = ""; savedFlash = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(storeDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if savedFlash {
                        Text(tr("Saved ✓")).font(.caption2).foregroundStyle(.green)
                    } else if !model.screenTimeCode.isEmpty {
                        Text(tr("A passcode is saved. Open the guide below to view it."))
                            .font(.caption2).foregroundStyle(Ink.accent)
                    }
                }
                Divider()

                if model.preventReady {
                    Text(tr("Your one-time access is ready."))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button(tr("Open the guide")) {
                        model.consumePreventAccess()   // spend the single open
                        showContent = true
                    }
                    .buttonStyle(.borderedProminent)
                } else if model.preventPending {
                    Label(tr("Opening this is delayed on purpose — so you can't impulsively look up how to undo your own lock."),
                          systemImage: "clock")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(tr("Access requested. It unlocks after your less-strict delay — track it on the Home tab, where you can also use an override to skip the wait."))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text(tr("This guide is behind your less-strict delay: request it, wait out the delay, and you get one open. After you view it, it locks again."))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button(tr("Request access")) { model.requestPreventAccess() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20).frame(maxWidth: 600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Prevent disabling"))
        .onReceive(ticker) { _ in refresh &+= 1 }
        .sheet(isPresented: $showContent) {
            NavigationStack {
                ScrollView {
                    PreventDisablingContent()
                        .padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
                }
                .background(Ink.paper.ignoresSafeArea())
                .casedNavigationTitle(tr("Prevent disabling"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Done")) { showContent = false }
                    }
                }
            }
        }
    }
}
