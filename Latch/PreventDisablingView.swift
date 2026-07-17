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
    @EnvironmentObject var model: AppModel
    var showsPasscodeStore = true
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
                            .font(.footnote.monospaced()).foregroundStyle(Ink.accent)
                    }
                }
                .onAppear { codeDraft = model.screenTimeCode }
            }
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

/// Help entry hub: two squares — the guide (delayed, one-time open) and the
/// stored Screen Time passcode (its own screen with its own gate).
struct PreventDisablingGateView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridCols, spacing: 14) {
                NavigationLink { PreventGuideGateView() } label: {
                    GridCard(symbol: "book", title: tr("Guide"),
                             subtitle: tr("how to lock it with a friend"))
                }
                NavigationLink { PasscodeHubView() } label: {
                    GridCard(symbol: "key.fill", title: tr("Screen Time passcode"),
                             subtitle: model.screenTimeCode.isEmpty
                                ? tr("none saved") : tr("saved"))
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Prevent disabling"))
    }
}

/// The guide behind the less-strict delay, good for a single open — so you
/// can't impulsively look up how to undo your own lock.
struct PreventGuideGateView: View {
    @EnvironmentObject var model: AppModel
    @State private var showContent = false
    // Drives a re-render each second so the countdown→ready transition shows
    // without leaving the screen.
    @State private var refresh = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(tr("Make Demora impossible to disable"))
                    .font(.title3.bold())

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
        .casedNavigationTitle(tr("Guide"))
        .onReceive(ticker) { _ in refresh &+= 1 }
        .sheet(isPresented: $showContent) {
            NavigationStack {
                ScrollView {
                    // No passcode-store section here — the passcode has its own
                    // gated screen in Help.
                    PreventDisablingContent(showsPasscodeStore: false)
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

/// The stored passcode's own hub. No code saved → one square to enter it.
/// Code saved → change (warned, irreversible) and view (delay-gated).
struct PasscodeHubView: View {
    @EnvironmentObject var model: AppModel
    @State private var showEntry = false
    @State private var confirmChange = false

    private var hasCode: Bool { !model.screenTimeCode.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("The friend who set the Screen Time passcode can store it here so it isn't lost. Going back without saving keeps the current one."))
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: gridCols, spacing: 14) {
                    if hasCode {
                        Button { confirmChange = true } label: {
                            GridCard(symbol: "pencil", title: tr("Change passcode"),
                                     subtitle: tr("replaces the saved one"))
                        }
                        NavigationLink { PasscodeViewGateView() } label: {
                            GridCard(symbol: "eye", title: tr("View passcode"),
                                     subtitle: tr("behind your delay"))
                        }
                    } else {
                        Button { showEntry = true } label: {
                            GridCard(symbol: "key.fill", title: tr("Enter passcode"),
                                     subtitle: tr("save it here so it isn't lost"))
                        }
                    }
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Screen Time passcode"))
        .alert(tr("Change the passcode?"), isPresented: $confirmChange) {
            Button(tr("Cancel"), role: .cancel) {}
            Button(tr("Change passcode")) { showEntry = true }
        } message: {
            Text(tr("Are you sure? There is no way to undo this — the saved passcode is replaced only when you save a new one."))
        }
        .sheet(isPresented: $showEntry) { PasscodeEntrySheet() }
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
            Form {
                Section {
                    TextField(tr("Passcode"), text: $draft)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled()
                        .font(.title2.monospaced())
                        .multilineTextAlignment(.center)
                    PasscodeFormatWarning(code: draft)
                } footer: {
                    Text(tr("The friend who set the Screen Time passcode can store it here so it isn't lost. Going back without saving keeps the current one."))
                }
            }
            .paper()
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

/// Viewing the stored passcode: its own delayed, single-use gate, mirroring
/// the guide — request → wait (or override) → one look → locks again.
struct PasscodeViewGateView: View {
    @EnvironmentObject var model: AppModel
    @State private var revealed: String?
    // Re-render each second so the countdown→ready transition shows live.
    @State private var refresh = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let revealed {
                    Label(String(format: tr("Saved passcode: %@"), revealed),
                          systemImage: "key.fill")
                        .font(.title3.monospaced().bold())
                        .foregroundStyle(Ink.accent)
                    Text(tr("Access is spent — viewing it again needs a new request."))
                        .font(.footnote).foregroundStyle(.secondary)
                } else if model.passwordViewReady {
                    Text(tr("Your one-time access is ready."))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button(tr("View passcode")) {
                        model.consumePasswordViewAccess()   // spend the single look
                        revealed = model.screenTimeCode
                    }
                    .buttonStyle(.borderedProminent)
                } else if model.passwordViewPending {
                    Label(tr("Opening this is delayed on purpose — so you can't impulsively look up how to undo your own lock."),
                          systemImage: "clock")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(tr("Access requested. It unlocks after your less-strict delay — track it on the Home tab, where you can also use an override to skip the wait."))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text(tr("Viewing the stored passcode is behind your less-strict delay: request it, wait out the delay, and you get one look. After that it locks again."))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button(tr("Request access")) { model.requestPasswordViewAccess() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20).frame(maxWidth: 600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("View passcode"))
        .onReceive(ticker) { _ in refresh &+= 1 }
    }
}
