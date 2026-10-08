//
//  OnboardingView.swift
//  Real setup, one decision at a time. Help provides the current 2.0 guide.
//  Draft choices are committed together by AppModel, never by a demo reset.
//

import SwiftUI
import FamilyControls
import UIKit

struct OnboardingView: View {
    #if DEBUG
    var demo: OnboardingDemo? = nil
    @State private var demoAuthorized = false
    @State private var demoAllowsAccess = true
    @State private var demoSelection = false
    #endif
    @AppAccent private var accent
    @EnvironmentObject var model: AppModel
    @State private var authTried = false
    @State private var isRequestingAuthorization = false
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("textCasing") private var textCasingRaw = TextCasing.lower.rawValue
    @AppStorage("latch.accentColor", store: SharedStore.defaults)
    private var accentRaw = "blue"
    @State private var step = 0
    @State private var showLanguageBetaNotice = false
    @State private var noticedBetaLanguages: Set<AppLanguage> = []
    @State private var policy = DelayPolicy()
    @State private var loadedPolicy = false
    @State private var selection = FamilyActivitySelection()
    @State private var showAppPicker = false
    @State private var wantsLimit = false
    @State private var limitName = ""
    @State private var minutes = 30
    @State private var firstLimitID = UUID()
    @State private var isCompleting = false
    @State private var showCompletionError = false
    @State private var dayNightGroups: [DayNightGroup] = []
    @State private var overrides = OverridesConfig()
    @State private var wantsUsageEstimate = false
    @State private var usageEstimateMinutes = 21 * 60

    private var dayNightLimits: [AppLimit] { firstLimit.map { [$0] } ?? [] }
    private var dayNightValid: Bool {
        DayNightGroup.isValidCollection(dayNightGroups, limits: dayNightLimits)
    }

    private var isDemo: Bool {
        #if DEBUG
        return demo != nil
        #else
        return false
        #endif
    }

    private var accessGranted: Bool {
        #if DEBUG
        if isDemo { return demoAuthorized }
        #endif
        return model.authorized
    }

    private var hasSelection: Bool {
        #if DEBUG
        if isDemo { return demoSelection }
        #endif
        return !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    private var firstLimit: AppLimit? {
        guard wantsLimit, hasSelection else { return nil }
        let name = limitName.trimmingCharacters(in: .whitespacesAndNewlines)
        return AppLimit(id: firstLimitID, name: name.isEmpty ? tr("My first limit") : name,
                        selection: selection, minutesPerDay: minutes)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    #if DEBUG
                    if isDemo { DeveloperDemoNotice() }
                    #endif
                    DemoraWelcomeProgress(step: step, total: 7)
                    Group {
                        switch step {
                        case 0: purposeStep
                        case 1: delayStep
                        case 2: authStep
                        case 3: firstLimitStep
                        case 4: dayNightStep
                        case 5: overridesStep
                        default: readyStep
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .id(step)
            .paper()
            .casedNavigationTitle(tr("Setup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("Back")) { move(to: step - 1) }
                            .disabled(isRequestingAuthorization || isCompleting)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    #if DEBUG
                    if let demo {
                        Button("Close", action: demo.onClose)
                    } else {
                        preferences.disabled(isRequestingAuthorization || isCompleting)
                    }
                    #else
                    preferences.disabled(isRequestingAuthorization || isCompleting)
                    #endif
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 12) {
                    Button(action: continueSetup) {
                        HStack(spacing: 10) {
                            if isCompleting || isRequestingAuthorization { ProgressView().tint(Ink.buttonText) }
                            Text(step == 6 ? tr("Start using Demora") : tr("Continue"))
                        }
                    }
                    .buttonStyle(DemoraPrimaryButtonStyle())
                    .disabled(isCompleting || isRequestingAuthorization
                              || (step == 1 && !policy.isValid)
                              || (step == 3 && wantsLimit && !hasSelection)
                              || (step >= 4 && !dayNightValid)
                              || (step >= 5 && !overrides.isValidInitialSetup)
                              || (step == 6 && (!policy.isValid || (wantsLimit && !hasSelection))))
                    if step == 3 {
                        Button(tr("Set a limit later")) {
                            wantsLimit = false
                            move(to: 4)
                        }
                        .font(.subheadline)
                        .foregroundStyle(accent)
                        .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .background(Ink.paper)
            }
            .onAppear {
                guard !loadedPolicy else { return }
                loadedPolicy = true
                if !isDemo, model.state.delayPolicy.isValid { policy = model.state.delayPolicy }
            }
            .onChange(of: model.authorized) { authorized in
                guard !isDemo else { return }
                // An empty picker draft must not become a hidden required choice
                // when access goes away. A real chosen limit remains visible and
                // can be saved with the explicit inactive-blocking explanation.
                if !authorized && !hasSelection { wantsLimit = false }
            }
            .sheet(isPresented: $showAppPicker) {
                AppPickerSheet(selection: $selection)
            }
        }
        .interactiveDismissDisabled(isCompleting || isRequestingAuthorization)
        .alert(tr("Translation in beta"),
               isPresented: $showLanguageBetaNotice) {
            Button(tr("OK"), role: .cancel) { }
        } message: {
            Text(tr("This language is in beta. Please report any mistranslations or unclear phrasing to hello@getdemora.app."))
        }
        .alert(tr("Setup couldn't be saved"), isPresented: $showCompletionError) {
            Button(tr("OK"), role: .cancel) { }
        } message: {
            Text((isDemo ? nil : MonitorRegistration.rejectionMessage)
                 ?? tr("Your choices are still here. Please try again."))
        }
    }

    private var preferences: some View {
        Menu {
            Picker(tr("Language"), selection: Binding(get: { model.language }, set: { model.language = $0 })) {
                ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
            }
            Picker(tr("Appearance"), selection: $appearanceRaw) {
                ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Picker(tr("Text case"), selection: $textCasingRaw) {
                ForEach(TextCasing.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Picker(tr("App color"), selection: $accentRaw) {
                Text(tr("Blue")).tag("blue")
                Text(tr("Red")).tag("red")
            }
        } label: {
            Image(systemName: "textformat")
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(tr("Language & appearance"))
        }
    }

    private var purposeStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            DemoraPageTitle(title: tr("Make room for what matters."))
            Text(tr("Choose your boundaries now. Give yourself time before changing them later."))
                .font(.title3).foregroundStyle(Ink.faint)
            VStack(alignment: .leading, spacing: 22) {
                DemoraWelcomeEntry(symbol: "slider.horizontal.3", title: tr("Decide with a clear head"),
                                   detail: tr("Set limits for an app or a group, and plan time away."))
                DemoraWelcomeEntry(symbol: "hourglass", title: tr("Let the impulse pass"),
                                   detail: tr("A change can wait without taking away your ability to choose."))
            }
            .demoraSurface()
            Text(tr("Free. No account, ads, or analytics. Your app choices and usage stay on your device."))
                .font(.footnote).foregroundStyle(Ink.faint)
        }
    }

    private var delayStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            DemoraPageTitle(title: tr("A pause, on your terms."))
            Text(tr("Choose separate waits, one shared wait, or a wait only when loosening rules."))
                .foregroundStyle(Ink.faint)
            DelayPolicyPicker(policy: $policy)
            Text(tr("These are your starting settings. Later changes to rules and delay settings follow your delay policy."))
                .font(.footnote).foregroundStyle(Ink.faint)
        }
    }

    private var authStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            DemoraPageTitle(title: tr("Permissions"))
            Image(systemName: "checkmark.shield")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(accent).accessibilityHidden(true)
            // Approved permission copy: retain verbatim, including after denial.
            Text(tr("Demora needs Screen Time access to set limits and block apps, and notifications to tell you when a pending change is ready. iOS will ask for each."))
                .foregroundStyle(Ink.faint)
            #if DEBUG
            if isDemo {
                Picker("Simulate permission response", selection: $demoAllowsAccess) {
                    Text("Allow").tag(true)
                    Text("Don't Allow").tag(false)
                }
                .pickerStyle(.segmented)
                Text("Continue simulates this choice. No system permissions are requested.")
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
            #endif
            if accessGranted {
                Label(tr("Authorized ✓"), systemImage: "checkmark")
                    .foregroundStyle(accent)
            } else if authTried {
                Text(tr("That's okay. Without Screen Time access Demora can't block apps, but you can continue and turn it on later."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                    .demoraSurface()
            }
        }
    }

    private var firstLimitStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            DemoraPageTitle(title: tr("Start with one boundary."))
            Text(isDemo ? "Choose the sample group and a daily allowance. This limit only exists in the preview."
                 : tr("Optional: choose an app or a group and a daily allowance. This will be a real limit, not a demo."))
                .foregroundStyle(Ink.faint)
            if accessGranted || (wantsLimit && hasSelection) {
                Button {
                    wantsLimit = true
                    #if DEBUG
                    if isDemo {
                        demoSelection = true
                        if limitName.isEmpty { limitName = "Sample games" }
                        return
                    }
                    #endif
                    showAppPicker = true
                } label: {
                    GridCard(symbol: "app.badge", title: tr("Choose apps"),
                             subtitle: hasSelection ? tr("Edit your selection") : tr("One app or a shared group"))
                }
                .buttonStyle(.plain)
                .disabled(!accessGranted)
                if !accessGranted {
                    Text(tr("That's okay. Without Screen Time access Demora can't block apps, but you can continue and turn it on later."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
                if wantsLimit && hasSelection {
                    VStack(alignment: .leading, spacing: 18) {
                        TextField(tr("Limit name"), text: $limitName)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                        Stepper(value: $minutes, in: 5...720, step: 5) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(tr("Daily allowance")).foregroundStyle(Ink.faint)
                                Text(String(format: tr("%d min"), minutes))
                                    .font(.system(.title, design: .serif))
                            }
                        }
                        Text(tr("The selected apps share this allowance. You can fine-tune it later in Limits & blocks."))
                            .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    .demoraSurface()
                }
            } else {
                Text(tr("You can add a limit after enabling Screen Time access. For now, continue without one."))
                    .foregroundStyle(Ink.faint).demoraSurface()
            }
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            DemoraPageTitle(title: tr("Your next chapter."))
            DemoraWelcomeEntry(symbol: "hourglass", title: tr("Your delay policy"), detail: policySummary)
                .demoraSurface()
            if !dayNightGroups.isEmpty {
                DemoraWelcomeEntry(symbol: "sun.max", title: tr("Day & night"),
                                   detail: dayNightGroups.map(\.name).joined(separator: " · "))
            }
            if !overrides.contacts.isEmpty {
                DemoraWelcomeEntry(symbol: "person.2", title: tr("Trusted contacts"),
                                   detail: overrides.contacts.map(\.name).joined(separator: " · "))
            }
            if !overrides.phrasePolicies.isEmpty {
                DemoraWelcomeEntry(symbol: "text.cursor", title: tr("Phrases"),
                                   detail: overrides.phrasePolicies.map(\.name).joined(separator: " · "))
            }
            if !overrides.passwordPolicies.isEmpty {
                DemoraWelcomeEntry(symbol: "key", title: tr("Passwords"),
                                   detail: overrides.passwordPolicies.map(\.name).joined(separator: " · "))
            }
            if let limit = firstLimit {
                DemoraWelcomeEntry(symbol: "app.badge", title: limit.name,
                                   detail: String(format: tr("Daily allowance: %d min"), limit.minutesPerDay))
                Text(isDemo ? "Finishing shows your sample choices without saving them."
                     : tr("This limit will be saved when you start. Your initial setup doesn't need to wait."))
                    .font(.footnote).foregroundStyle(Ink.faint)
            } else {
                Text(tr("No limit yet. Add one whenever you're ready in Limits & blocks."))
                    .foregroundStyle(Ink.faint)
            }
            if !accessGranted {
                Text(tr("That's okay. Without Screen Time access Demora can't block apps, but you can continue and turn it on later."))
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
            WeeklyUsageEstimateDraft(enabled: $wantsUsageEstimate, minutes: $usageEstimateMinutes)
                .demoraSurface()
            Text(tr("Find practical instructions and troubleshooting in Settings → Help → Guide."))
                .font(.footnote).foregroundStyle(Ink.faint).demoraSurface()
        }
    }

    private var dayNightStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            DemoraPageTitle(title: tr("Make room for your mornings and nights."))
            Text(tr("Optional: choose your limit groups and extra apps, then give each day/night group its own timing. One Wake up tap starts all eligible waits."))
                .foregroundStyle(Ink.faint)
            DayNightSetupDraftView(limits: dayNightLimits, groups: $dayNightGroups,
                                   isDemo: isDemo, canChooseApps: accessGranted)
            if !dayNightValid {
                Text(tr("Review your day/night groups after changing your limits."))
                    .font(.footnote).foregroundStyle(Ink.danger)
            }
            Text(tr("You can change this later in Schedules → Day & night. Later changes follow your delays."))
                .font(.footnote).foregroundStyle(Ink.faint)
        }
    }

    private var overridesStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            DemoraPageTitle(title: tr("A backup, if you want one."))
            Text(tr("Optional: add a trusted contact, a phrase, or a password. Choose exactly what each can approve or unlock."))
                .foregroundStyle(Ink.faint)
            OnboardingOverridesDraftView(overrides: $overrides, isDemo: isDemo)
            Text(tr("These choices apply when you finish setup. Later additions and permission changes follow your delays."))
                .font(.footnote).foregroundStyle(Ink.faint)
            Text(tr("Contact invitations are sent after setup. Contacts must confirm before they can approve; manage them in Delays → Trusted contacts."))
                .font(.footnote).foregroundStyle(Ink.faint)
        }
    }

    private var policySummary: String {
        let p = policy.normalized
        switch p.mode {
        case .separate:
            return String(format: tr("Tightening: %@ · Loosening: %@"),
                          p.strictDelay.shortDelayLabel, p.lenientDelay.shortDelayLabel)
        case .shared:
            return String(format: tr("One wait for all changes: %@"), p.lenientDelay.shortDelayLabel)
        case .lenientOnly:
            return String(format: tr("Tightening is immediate · Loosening: %@"), p.lenientDelay.shortDelayLabel)
        }
    }

    private func move(to newStep: Int) {
        // No implicit animation: respects Reduce Motion and avoids moving controls.
        step = newStep
    }

    private func continueSetup() {
        guard !isCompleting, !isRequestingAuthorization else { return }
        let language = model.language
        if language.isBetaTranslation, !noticedBetaLanguages.contains(language) {
            noticedBetaLanguages.insert(language)
            showLanguageBetaNotice = true
            // Reading the notice and opening a system authorization sheet must
            // be separate actions. Also don't dismiss setup before a late notice
            // can be read. The next Continue proceeds without repeating it.
            if step == 2 || step == 6 { return }
        }
        switch step {
        case 0:
            move(to: 1)
        case 1:
            guard policy.isValid else { return }
            move(to: 2)
        case 2:
            #if DEBUG
            if isDemo {
                if authTried { move(to: 3) }
                else {
                    authTried = true
                    demoAuthorized = demoAllowsAccess
                    if demoAuthorized { move(to: 3) }
                }
                return
            }
            #endif
            if authTried {
                move(to: 3)
            } else {
                isRequestingAuthorization = true
                Task { @MainActor in
                    await model.requestAuthorization()
                    isRequestingAuthorization = false
                    authTried = true
                    if model.authorized { move(to: 3) }
                    // Denial leaves the explanation visible with a plain Continue.
                }
            }
        case 3:
            guard !wantsLimit || hasSelection else { return }
            move(to: 4)
        case 4:
            guard dayNightValid else { return }
            move(to: 5)
        case 5:
            guard overrides.isValidInitialSetup else { return }
            move(to: 6)
        default:
            guard policy.isValid, dayNightValid, overrides.isValidInitialSetup,
                  !wantsLimit || hasSelection else { return }
            #if DEBUG
            if let demo {
                demo.onComplete(policy.normalized, firstLimit, dayNightGroups, overrides)
                return
            }
            #endif
            isCompleting = true
            let chosenPolicy = policy.normalized
            let chosenLimit = firstLimit
            let chosenDayNight = dayNightGroups
            let chosenOverrides = overrides
            let chosenEstimate = wantsUsageEstimate ? usageEstimateMinutes : nil
            Task { @MainActor in
                let saved = await model.completeInitialSetup(policy: chosenPolicy, firstLimit: chosenLimit,
                                                            dayNightGroups: chosenDayNight,
                                                            overrides: chosenOverrides)
                isCompleting = false
                if saved, let chosenEstimate { WeeklyUsageEstimate.save(minutes: chosenEstimate) }
                if !saved { showCompletionError = true }
            }
        }
    }
}

/// Shared editorial furniture for first-run setup and the read-only 2.0 welcome.
struct DemoraWelcomeProgress: View {
    @AppAccent private var accent
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Rectangle().fill(index <= step ? accent : Ink.rule).frame(height: 2)
            }
            Text(String(format: tr("%d of %d"), step + 1, total))
                .font(.system(.caption, design: .monospaced)).foregroundStyle(Ink.faint)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: tr("Step %d of %d"), step + 1, total))
    }
}

struct DemoraWelcomeEntry: View {
    @AppAccent private var accent
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light))
                .foregroundStyle(accent).frame(width: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(.title3, design: .serif)).foregroundStyle(Ink.ink)
                Text(detail).font(.subheadline).foregroundStyle(Ink.faint)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
    case contacts
    var id: Int { rawValue }
    var title: String { tr("Trusted contacts") }
}

/// Configures one override against the local setup state (no delays yet —
/// setup choices apply instantly; delays only gate changes afterwards).
struct OnboardingOverrideSheet: View {
    let kind: OverrideSheetKind
    @Binding var overrides: OverridesConfig
    @Environment(\.dismiss) private var dismiss
    @State private var showAddContact = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DemoraPageTitle(title: kind.title)
                    contactsSection
                        .demoraSurface()
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showAddContact) {
                AddContactView(onAdd: { overrides.contacts.append($0) },
                               existingContacts: overrides.contacts)
            }
        }
    }

    @ViewBuilder private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            Text(tr("A person you choose approves skipping a countdown — by email code or from their own Demora app. You can also add more later in Settings → Trusted contacts."))
                .font(.footnote).foregroundStyle(Ink.faint)
        }
    }
}

// MARK: - Tutorial coaching callout

/// Floating instruction shown above the tab bar during the guided tour.
struct TutorialCallout: View {
    @AppAccent private var accent
    @EnvironmentObject var model: AppModel

    private var message: String? {
        switch model.tutorial {
        case .addLimit:
            return tr("Tap ‘Add your first limit’, choose an app or two and a daily budget, then queue the change.")
        case .addSchedule:
            return tr("Now a schedule. Tap ‘Add a recurring schedule’, pick a time window and some apps, then queue it.")
        case .applyBoth:
            return tr("Two changes are waiting. Tap Select, choose both, Apply — then ask your sample trusted contact to approve them.")
        case .exploreCalendar:
            return tr("Open Calendar to see everything laid out by day.")
        case .removeSchedule:
            return tr("Now tidy up: open Recurring and remove the schedule you made.")
        case .removeLimit:
            return tr("And the limit: tap it, then Remove this limit.")
        case .addContact:
            return tr("Let's add a backup approver. Open Rules → Overrides → Trusted contacts and add a sample contact.")
        case .applyViaContact:
            return tr("Two removals are pending. Tap Select, choose both, Apply — then ask your trusted contact again.")
        case .configure, .none:
            return nil
        }
    }

    var body: some View {
        if let message {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(accent)
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
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.4), lineWidth: 1))
            .padding(.horizontal, 16)
            // Sit at the bottom (just clearing the tab bar) so it doesn't cover
            // the pending changes; lift only when the multi-select "Apply" bar
            // is actually on screen.
            .padding(.bottom, model.applyBarVisible ? 150 : 56)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Persistent banner pinned to the top of the screen throughout the guided
/// tour, so it's always obvious the walkthrough runs on sample data.
struct TutorialDemoBanner: View {
    var body: some View {
        Text(tr("This is a demo — nothing you do here is saved or actually blocked."))
            .font(.caption.weight(.bold))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.yellow)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.black.opacity(0.15)).frame(height: 1)
            }
    }
}

// MARK: - Tutorial finish (real delays + overrides)

/// Final tutorial screen: the user picks their real delays and overrides,
/// then enters the app for real.
struct TutorialFinishView: View {
    @AppAccent private var accent
    @EnvironmentObject var model: AppModel
    @State private var policy = DelayPolicy()
    @State private var overrides = OverridesConfig()
    @State private var blockDeletion = false
    @State private var blockWebsites = false
    @State private var editingOverride: OverrideSheetKind?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                  if model.isReplay {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44)).foregroundStyle(accent)
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

                    DelayPolicyPicker(policy: $policy)

                    Text(tr("Overrides"))
                        .font(.caption.smallCaps()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
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
                        .tint(accent)
                    Toggle(tr("Block adult websites"), isOn: $blockWebsites)
                        .tint(accent)
                    Text(tr("You can change these any time under General blocking. Each change then goes through your delays."))
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(tr("Finish setup")) {
                        guard policy.isValid else { return }
                        let chosenPolicy = policy.normalized
                        model.finishTutorial(strictDelay: chosenPolicy.strictDelay,
                                             lenientDelay: chosenPolicy.lenientDelay,
                                             overrides: overrides,
                                             blockAppRemoval: blockDeletion,
                                             blockAdultWebsites: blockWebsites,
                                             delayMode: chosenPolicy.mode)
                    }
                    .buttonStyle(DemoraPrimaryButtonStyle())
                    .disabled(!policy.isValid)
                    .padding(.top, 8)
                  }
                }
                .padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Almost done"))
            .sheet(item: $editingOverride) { kind in
                OnboardingOverrideSheet(kind: kind, overrides: $overrides)
            }
        }
    }
}
