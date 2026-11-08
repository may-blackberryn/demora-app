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

/// Non-blocking heads-up when a stored code doesn't look like a Screen Time
/// passcode (exactly 4 digits). Deliberately not enforced — just in case
/// Apple's format ever differs — so it only warns.
struct PasscodeFormatWarning: View {
    let code: String

    private var looksOff: Bool {
        let t = code.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && !(t.count == 4 && t.allSatisfy(\.isNumber))
    }

    var body: some View {
        if looksOff {
            Label(tr("Screen Time usually only allows a 4-digit passcode — are you sure this is correct?"),
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}

/// The actual how-to steps. Reused by the onboarding intro (with the inline
/// passcode-store section) and the Help guide (without it — the passcode has
/// its own screen there).
struct PreventDisablingContent: View {
    @AppAccent private var accent
    @EnvironmentObject var model: AppModel
    var showsPasscodeStore = true
    @State private var codeDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Demora can't stop you from turning off its Screen Time access in iOS Settings — but a friend can. If Screen Time itself is locked with someone else's passcode, iOS blocks any change to Demora's access, while Demora keeps doing all the blocking."))
                .font(.subheadline).foregroundStyle(.secondary)

            Label(tr("Takes about 2 minutes, and you need a second person physically with you."),
                  systemImage: "person.2.fill")
                .font(.footnote.weight(.medium)).foregroundStyle(accent)

            step(1, tr("Open Settings → Screen Time on this iPhone. If it's off, turn it on."))
            step(2, tr("Tap “Lock Screen Time Settings” (or “Use Screen Time Passcode”)."))
            step(3, tr("Hand your phone to your friend. Have THEM enter a 4-digit passcode you don't see — don't watch."))
            step(4, tr("When asked for Screen Time Passcode Recovery, your friend signs in with THEIR OWN Apple ID — not yours. That's what stops you from resetting the passcode on your own."))
            step(5, tr("Done. Now you can't disable Demora's access — or change the passcode — without your friend. To undo it later, your friend enters the passcode and turns it off."))

            Label(tr("Pick someone you trust and can reach. If the passcode and its recovery Apple ID are both lost, removing it may require erasing the device."),
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)

            if showsPasscodeStore {
                Divider().padding(.vertical, 4)

                // Onboarding only: a place for the friend to stash the passcode
                // they set. In Help this lives on its own gated screen instead.
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
                    PasscodeFormatWarning(code: codeDraft)
                    if !model.screenTimeCode.isEmpty {
                        Text(String(format: tr("Saved passcode: %@"), model.screenTimeCode))
                            .font(.footnote.monospaced()).foregroundStyle(accent)
                    }
                }
                .onAppear { codeDraft = model.screenTimeCode }
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.headline).foregroundStyle(accent)
                .frame(width: 20, alignment: .trailing)
            Text(text).font(.subheadline)
        }
    }
}

/// Enter/replace the stored passcode. The saved value changes ONLY when Save
/// is tapped — cancelling or swiping the sheet away keeps the old one. The
/// field is never prefilled with the current code: that would reveal it and
/// bypass the view-passcode delay.
struct PasscodeEntrySheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DemoraPageTitle(title: tr("Screen Time passcode"))
                    VStack(alignment: .leading, spacing: 12) {
                    TextField(tr("Passcode"), text: $draft)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled()
                        .font(.title2.monospaced())
                        .multilineTextAlignment(.center)
                    PasscodeFormatWarning(code: draft)
                    Text(tr("The friend who set the Screen Time passcode can store it here so it isn't lost. Going back without saving keeps the current one."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    .demoraSurface()
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Screen Time passcode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Save")) {
                        model.setScreenTimeCode(draft)
                        dismiss()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
