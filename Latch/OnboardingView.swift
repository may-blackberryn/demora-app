//
//  OnboardingView.swift
//  Setup flow: language → what the app is → how delays work → features →
//  authorization → set delays → optional overrides → done.
//  Setup choices apply instantly; delays only gate changes afterwards.
//

import SwiftUI
import FamilyControls
import UIKit

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var authTried = false
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("textCasing") private var textCasingRaw = TextCasing.lower.rawValue
    @State private var step = 0
    @State private var showPreventSteps = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0:  dictionaryStep
                case 1:  authStep
                case 2:  preventIntroStep
                default: welcomeStartStep
                }
            }
            // Fill the screen before painting paper, so steps without
            // expanding spacers (like the done page) don't leave gaps.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .paper()
            .casedNavigationTitle(tr("Setup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("Back")) { step -= 1 }
                    }
                }
            }
        }
    }

    // MARK: Step 0 — the dictionary entry (with the language toggle)

    private var dictionaryStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 20) {
                Spacer()
                Button(model.language == .english ? "english" : "español") {
                    model.language = model.language == .english
                        ? .spanish : .english
                }
                Button((Appearance(rawValue: appearanceRaw) ?? .system)
                        .label.lowercased()) {
                    // Cycle system → light → dark → system.
                    let all = Appearance.allCases
                    let current = Appearance(rawValue: appearanceRaw) ?? .system
                    let next = all[(all.firstIndex(of: current)! + 1) % all.count]
                    appearanceRaw = next.rawValue
                }
                Button((TextCasing(rawValue: textCasingRaw) ?? .lower)
                        .label.lowercased()) {
                    // Toggle lowercase ⇄ regular.
                    let all = TextCasing.allCases
                    let current = TextCasing(rawValue: textCasingRaw) ?? .lower
                    let next = all[(all.firstIndex(of: current)! + 1) % all.count]
                    textCasingRaw = next.rawValue
                }
            }
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(Ink.faint)
            Spacer()
            Wordmark(size: 58)
            Text(tr("/ de·mo·ra /  noun, Spanish"))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(Ink.faint)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 18) {
                definition("1.", tr("a delay; the time that passes before something takes effect."))
                definition("2.", tr("an iPhone app that protects your screen-time rules with definition 1 instead of a password."))
            }
            .padding(.top, 32)
            Spacer()
            Spacer()
            Button(tr("Continue")) { step = 1 }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding(28)
        .frame(maxWidth: 600)
        .background(Ink.paper.ignoresSafeArea())
    }

    private func definition(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .italic()
                .foregroundStyle(Ink.faint)
            Text(text)
                .font(.body)
        }
    }

    // MARK: Step 1 — authorization

    private var authStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60)).foregroundStyle(.tint)
            Text(tr("Permissions")).font(.title2.bold())
            Text(tr("Demora needs Screen Time access to set limits and block apps, and notifications to tell you when a pending change is ready. iOS will ask for each."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(model.authorized ? tr("Authorized ✓") : tr("Continue")) {
                Task {
                    await model.requestAuthorization()
                    authTried = true
                    if model.authorized { step = 2 }
                }
            }
            .buttonStyle(.borderedProminent)
            if model.authorized {
                Button(tr("Continue")) { step = 2 }
            } else if authTried {
                // The user declined. Respect the choice — don't redirect to
                // Settings. They can continue; blocking simply stays inactive
                // until Screen Time is enabled later, in their own time.
                Text(tr("That's okay. Without Screen Time access Demora can't block apps, but you can continue and turn it on later."))
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(tr("Continue")) { step = 2 }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: 600)
    }

    // MARK: Step 2 — prevent-disabling (optional, second person needed)

    private var preventIntroStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56)).foregroundStyle(.tint)
                Text(tr("One more safeguard")).font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(tr("There's a way to make Demora impossible to turn off — with a friend's help. It takes about 2 minutes and needs a second person physically with you."))
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)

                if showPreventSteps {
                    PreventDisablingContent()
                        .padding(.top, 4)
                } else {
                    Button(tr("Show me how")) {
                        withAnimation { showPreventSteps = true }
                    }
                    .buttonStyle(.bordered)
                }

                Text(tr("You can always find this later under Help — but there it's behind a delay."))
                    .font(.footnote).multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button(tr("Continue")) { step = 3 }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
            .padding().frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
    }

    // MARK: Step 3 — welcome → start the guided tour

    private var welcomeStartStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 56)).foregroundStyle(.tint)
            Text(tr("Welcome to Demora")).font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(tr("Demora can be a lot at first, so let's set up your first limit together — a quick, hands-on walkthrough of how delays and overrides actually feel. It takes about a minute."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text(tr("Everything here is just a sample — nothing is saved and nothing is actually blocked. It's only to show how the app works."))
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button(tr("Add my first limit")) { model.beginTutorial() }
                .buttonStyle(.borderedProminent)
            Button(tr("Skip and set up manually")) { model.skipTutorial() }
                .font(.footnote).padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: 600)
    }

}

/// Hours + minutes wheel for picking a delay duration.
struct DelayPicker: View {
    let title: String
    @Binding var seconds: TimeInterval

    private var hours: Binding<Int> {
        Binding(get: { Int(seconds) / 3600 },
                set: { seconds = TimeInterval($0 * 3600 + (Int(seconds) % 3600)) })
    }
    private var minutes: Binding<Int> {
        Binding(get: { (Int(seconds) % 3600) / 60 },
                set: { seconds = TimeInterval((Int(seconds) / 3600) * 3600 + $0 * 60) })
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.subheadline)
            HStack {
                Picker(tr("Hours"), selection: hours) {
                    ForEach(0..<73, id: \.self) {
                        Text(String(format: tr("%d hr"), $0)).tag($0)
                    }
                }
                .pickerStyle(.wheel)
                Picker(tr("Minutes"), selection: minutes) {
                    ForEach(0..<60, id: \.self) {
                        Text(String(format: tr("%d min"), $0)).tag($0)
                    }
                }
                .pickerStyle(.wheel)
            }
            .frame(height: 110)
        }
    }
}

// MARK: - Onboarding override config sheet

/// Which override card is being configured during setup.
enum OverrideSheetKind: Int, Identifiable {
    case math, password, contacts
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .math:     return tr("Math override")
        case .password: return tr("Password")
        case .contacts: return tr("Trusted contacts")
        }
    }
}

/// Configures one override against the local setup state (no delays yet —
/// setup choices apply instantly; delays only gate changes afterwards).
struct OnboardingOverrideSheet: View {
    let kind: OverrideSheetKind
    @Binding var overrides: OverridesConfig
    @Binding var password: String
    @Binding var passwordConfirm: String
    @Environment(\.dismiss) private var dismiss
    @State private var showAddContact = false

    var body: some View {
        NavigationStack {
            Form {
                switch kind {
                case .math:     mathSection
                case .password: passwordSection
                case .contacts: contactsSection
                }
            }
            .paper()
            .casedNavigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { dismiss() }.disabled(!canDone)
                }
            }
            .sheet(isPresented: $showAddContact) {
                AddContactView { overrides.contacts.append($0) }
            }
        }
    }

    /// Block leaving a half-set password override.
    private var canDone: Bool {
        guard kind == .password, overrides.passwordEnabled else { return true }
        return !password.isEmpty && password == passwordConfirm
    }

    @ViewBuilder private var mathSection: some View {
        Section {
            Toggle(tr("Enable math override"), isOn: $overrides.mathEnabled)
            if overrides.mathEnabled {
                Picker(tr("Difficulty"), selection: Binding(
                    get: { overrides.mathDifficulty ?? .elementary },
                    set: { overrides.mathDifficulty = $0 })) {
                    ForEach(MathDifficulty.allCases) { Text($0.label).tag($0) }
                }
                Picker(tr("Problems to solve"), selection: $overrides.mathQuestionCount) {
                    ForEach(mathQuestionCountOptions, id: \.self) {
                        Text("\($0)").tag($0)
                    }
                }
                Picker(tr("If an answer is wrong"), selection: $overrides.mathWrongBehavior) {
                    ForEach(MathWrongBehavior.allCases) { Text($0.label).tag($0) }
                }
            }
        } footer: {
            Text(tr("Solve math problems to skip a countdown."))
        }
    }

    @ViewBuilder private var passwordSection: some View {
        Section {
            Toggle(tr("Enable password override"), isOn: $overrides.passwordEnabled)
            if overrides.passwordEnabled {
                SecureField(tr("Password"), text: $password)
                SecureField(tr("Confirm password"), text: $passwordConfirm)
                if !password.isEmpty && password != passwordConfirm {
                    Text(tr("Passwords don't match")).font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        } footer: {
            Text(tr("Enter a password to skip a countdown."))
        }
    }

    @ViewBuilder private var contactsSection: some View {
        Section {
            Toggle(tr("Enable trusted-contact override"),
                   isOn: $overrides.contactsEnabled)
            if overrides.contactsEnabled {
                ForEach(overrides.contacts) { contact in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(contact.name)
                            Text(contact.detail)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            overrides.contacts.removeAll { $0.id == contact.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button { showAddContact = true } label: {
                    Label(tr("Add contact…"), systemImage: "person.badge.plus")
                }
            }
        } footer: {
            Text(tr("A person you choose approves skipping a countdown — by email code or from their own Demora app. You can also add more later in Settings → Trusted contacts."))
        }
    }
}

// MARK: - Tutorial coaching callout

/// Floating instruction shown above the tab bar during the guided tour.
struct TutorialCallout: View {
    @EnvironmentObject var model: AppModel

    private var message: String? {
        switch model.tutorial {
        case .addLimit:
            return tr("Tap ‘Add your first limit’, choose an app or two and a daily budget, then queue the change.")
        case .addSchedule:
            return tr("Now a schedule. Tap ‘Add a recurring schedule’, pick a time window and some apps, then queue it.")
        case .applyBoth:
            return tr("Two changes are waiting, and you can't wait them out. Tap Select, choose both, Apply — then use the password override. The password is: test")
        case .exploreCalendar:
            return tr("Open Calendar to see everything laid out by day.")
        case .removeSchedule:
            return tr("Now tidy up: open Recurring and remove the schedule you made.")
        case .removeLimit:
            return tr("And the limit: tap it, then Remove this limit.")
        case .addContact:
            return tr("Let's add a backup approver. Open Rules → Overrides → Trusted contacts and add a sample contact.")
        case .applyViaContact:
            return tr("Two removals are pending. Tap Select, choose both, Apply — then approve with your trusted contact instead of the password.")
        case .configure, .none:
            return nil
        }
    }

    var body: some View {
        if let message {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(Ink.accent)
                    Text(message).font(.subheadline).foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // The walkthrough is always optional — never trap anyone behind
                // the locked tab bar. A replay restores the real setup; a first
                // run jumps to the final setup screen.
                if !model.isReplay {
                    Text(tr("Onboarding demo — you can skip below. It's always available again in Settings → Help."))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                }
                Button(model.isReplay ? tr("Skip walkthrough")
                                      : tr("Skip — set up manually")) {
                    model.skipTutorial()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Ink.accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(Ink.accent.opacity(0.4), lineWidth: 1))
            .padding(.horizontal, 16)
            // Sit at the bottom (just clearing the tab bar) so it doesn't cover
            // the pending changes; lift only when the multi-select "Apply" bar
            // is actually on screen.
            .padding(.bottom, model.applyBarVisible ? 150 : 56)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Tutorial finish (real delays + overrides)

/// Final tutorial screen: the user picks their real delays and overrides,
/// then enters the app for real.
struct TutorialFinishView: View {
    @EnvironmentObject var model: AppModel
    @State private var strictDelay: TimeInterval = 0
    @State private var lenientDelay: TimeInterval = 0
    @State private var overrides = OverridesConfig()
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var blockDeletion = false
    @State private var blockWebsites = false
    @State private var editingOverride: OverrideSheetKind?

    private var passwordValid: Bool {
        !overrides.passwordEnabled || (!password.isEmpty && password == passwordConfirm)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                  if model.isReplay {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44)).foregroundStyle(Ink.accent)
                    Text(tr("That's the whole loop. Your real limits, schedules, and settings are still here — nothing changed."))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(tr("Done")) { model.finishReplay() }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                  } else {
                    Text(tr("Nice work — that's the whole loop. Now set the delays and overrides that will actually protect you."))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(tr("Delay for STRICTER changes"))
                        .font(.caption.smallCaps()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DelayPicker(title: tr("More-strict delay"), seconds: $strictDelay)
                    Text(tr("Delay for LOOSER changes"))
                        .font(.caption.smallCaps()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DelayPicker(title: tr("Less-strict delay"), seconds: $lenientDelay)

                    Text(tr("Overrides"))
                        .font(.caption.smallCaps()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LazyVGrid(columns: gridCols, spacing: 14) {
                        Button { editingOverride = .math } label: {
                            GridCard(symbol: "function", title: tr("Math problems"),
                                     subtitle: overrides.mathEnabled
                                        ? (overrides.mathDifficulty?.label ?? tr("On")) : tr("Off"))
                        }
                        Button { editingOverride = .password } label: {
                            GridCard(symbol: "key", title: tr("Password"),
                                     subtitle: overrides.passwordEnabled ? tr("On") : tr("Off"))
                        }
                        Button { editingOverride = .contacts } label: {
                            GridCard(symbol: "person.2", title: tr("Trusted contacts"),
                                     subtitle: overrides.contactsEnabled
                                        ? String(overrides.contacts.count) : tr("Off"))
                        }
                    }
                    .buttonStyle(.plain)

                    Text(tr("Protection"))
                        .font(.caption.smallCaps()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle(tr("Block app deletion"), isOn: $blockDeletion)
                        .tint(Ink.accent)
                    Toggle(tr("Block adult websites"), isOn: $blockWebsites)
                        .tint(Ink.accent)
                    Text(tr("You can change these any time under General blocking. Each change then goes through your delays."))
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(tr("Finish setup")) {
                        if overrides.mathEnabled && overrides.mathDifficulty == nil {
                            overrides.mathDifficulty = .elementary
                        }
                        if overrides.passwordEnabled {
                            overrides.passwordHash = AppModel.hash(password)
                        }
                        model.finishTutorial(strictDelay: strictDelay,
                                             lenientDelay: lenientDelay,
                                             overrides: overrides,
                                             blockAppRemoval: blockDeletion,
                                             blockAdultWebsites: blockWebsites)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(strictDelay <= 0 || lenientDelay <= 0 || !passwordValid)
                    .padding(.top, 8)
                  }
                }
                .padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Almost done"))
            .onAppear {
                // Pre-fill sensible defaults so Finish is never stuck disabled
                // (especially when the walkthrough was skipped straight here).
                if strictDelay <= 0 { strictDelay = 5 * 60 }
                if lenientDelay <= 0 { lenientDelay = 15 * 60 }
            }
            .sheet(item: $editingOverride) { kind in
                OnboardingOverrideSheet(kind: kind, overrides: $overrides,
                                        password: $password, passwordConfirm: $passwordConfirm)
            }
        }
    }
}
