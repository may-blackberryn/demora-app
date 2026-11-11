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
    @AppStorage("textCasing") private var textCasingRaw = TextCasing.fallback.rawValue
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
    @State private var showDayNight = false
    @State private var showOverrides = false

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
                    DemoraWelcomeProgress(step: step, total: 5)
                    Group {
                        switch step {
                        case 0: purposeStep
                        case 1: delayStep
                        case 2: authStep
                        case 3: firstLimitStep
                        default: makeYoursStep
                        }
                    }
                }
                .padding(DemoraSpace.pageGutter)
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
                            Text(step == 4 ? tr("Start using Demora") : tr("Continue"))
                        }
                    }
                    .buttonStyle(DemoraPrimaryButtonStyle())
                    .disabled(isCompleting || isRequestingAuthorization
                              || (step == 1 && !policy.isValid)
                              || (step == 3 && wantsLimit && !hasSelection)
                              || (step >= 4 && !dayNightValid)
                              || (step == 4 && !overrides.isValidInitialSetup)
                              || (step == 4 && (!policy.isValid || (wantsLimit && !hasSelection))))
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
                .padding(.horizontal, DemoraSpace.pageGutter).padding(.vertical, 14)
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
            .sheet(isPresented: $showDayNight) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DemoraSpace.l) {
                            #if DEBUG
                            if isDemo { DeveloperDemoNotice() }
                            #endif
                            dayNightStep
                        }
                        .padding(DemoraSpace.pageGutter)
                    }
                    .paper()
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Done")) { showDayNight = false }
                    } }
                }
            }
            .sheet(isPresented: $showOverrides) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DemoraSpace.l) {
                            #if DEBUG
                            if isDemo { DeveloperDemoNotice() }
                            #endif
                            overridesStep
                        }
                        .padding(DemoraSpace.pageGutter)
                    }
                    .paper()
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Done")) { showOverrides = false }
                    } }
                }
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
            Text(tr("Make room for what matters.")).demoraType(.pageTitle)
            Text(tr("Choose your boundaries now. Give yourself time before changing them later."))
                .font(.title3).foregroundStyle(Ink.faint)
            VStack(alignment: .leading, spacing: 22) {
                DemoraWelcomeEntry(symbol: "slider.horizontal.3", title: tr("Decide with a clear head"),
                                   detail: tr("Set limits for an app or a group, and plan time away."))
                DemoraWelcomeEntry(symbol: "hourglass", title: tr("Let the impulse pass"),
                                   detail: tr("A change can wait without taking away your ability to choose."))
            }
            .paperCard()
            Text(tr("Free. No account, ads, or analytics. Your app choices and usage stay on this device."))
                .demoraType(.meta).foregroundStyle(Ink.inkSoft)
        }
    }

    private var delayStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(tr("A pause, on your terms.")).demoraType(.pageTitle)
            Text(tr("Choose separate waits, one shared wait, or a wait only when loosening rules."))
                .foregroundStyle(Ink.faint)
            DelayPolicyPicker(policy: $policy)
            Text(tr("These are your starting settings. Later changes to rules and delay settings follow your delay policy."))
                .font(.footnote).foregroundStyle(Ink.faint)
        }
    }

    private var authStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(tr("Permissions")).demoraType(.pageTitle)
            Image(systemName: "checkmark.shield")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(accent)
                .frame(width: 96, height: 96)
                .background(accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
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
                StateChip(kind: .free, text: tr("Allowed"))
            } else if authTried {
                Text(tr("That's okay. Without Screen Time access Demora can't block apps, but you can continue and turn it on later."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                    .paperCard()
            }
        }
    }

    private var firstLimitStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(tr("Start with one boundary.")).demoraType(.pageTitle)
            Text(isDemo ? "Choose the sample group and a daily allowance. This limit only exists in the preview."
                 : tr("Optional. This is a real limit, not a demo."))
                .demoraType(.meta).foregroundStyle(Ink.inkSoft)
            if accessGranted || (wantsLimit && hasSelection) {
                VStack(alignment: .leading, spacing: DemoraSpace.m) {
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
                    FactRow(label: tr("Apps"), value: hasSelection
                            ? String(format: tr("%d items"), selectedItemCount) : tr("Choose"), chevron: true)
                }
                .buttonStyle(.plain)
                .disabled(!accessGranted)
                if !accessGranted {
                    Text(tr("That's okay. Without Screen Time access Demora can't block apps, but you can continue and turn it on later."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
                    Rectangle().fill(Ink.hairline).frame(height: 1).accessibilityHidden(true)
                    HStack {
                        Text(tr("Name")).demoraType(.meta).foregroundStyle(Ink.inkSoft)
                        TextField(tr("My first limit"), text: $limitName)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .multilineTextAlignment(.trailing)
                    }
                    Rectangle().fill(Ink.hairline).frame(height: 1).accessibilityHidden(true)
                        Stepper(value: $minutes, in: 5...720, step: 5) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(tr("Each day")).demoraType(.meta).foregroundStyle(Ink.inkSoft)
                                Text(String(format: tr("%d min"), minutes))
                                    .demoraType(.time)
                            }
                        }
                        Text(tr("The selected apps share this allowance."))
                            .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                }
                .paperCard()
            } else {
                Text(tr("You can add a limit after enabling Screen Time access. For now, continue without one."))
                    .foregroundStyle(Ink.inkSoft).paperCard()
            }
        }
    }

    private var selectedItemCount: Int {
        #if DEBUG
        if isDemo { return demoSelection ? 1 : 0 }
        #endif
        return selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    private var overridesSummary: String {
        [(tr("Trusted contacts"), overrides.contacts.count),
         (tr("Phrases"), overrides.phrasePolicies.count),
         (tr("Passwords"), overrides.passwordPolicies.count)]
            .filter { $0.1 > 0 }
            .map { $0.0 + ": " + $0.1.formatted() }
            .joined(separator: " · ")
    }

    private var makeYoursStep: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
            Text(tr("Make it yours.")).demoraType(.pageTitle)
            Text(tr("Both are optional. You can add them now without waiting."))
                .demoraType(.meta).foregroundStyle(Ink.inkSoft)
            SetupOptionalCard(title: tr("Mornings & nights"), symbol: "sun.horizon",
                detail: dayNightGroups.isEmpty
                    ? tr("One Wake up tap starts all eligible groups together. Give each group its own wait and sleep time.")
                    : dayNightGroups.map(\.name).joined(separator: " · "),
                actionTitle: dayNightGroups.isEmpty ? tr("Set up") : tr("Edit")) { showDayNight = true }
            if !dayNightValid {
                Text(tr("Review your day/night groups after changing your limits."))
                    .demoraType(.meta).foregroundStyle(Ink.danger)
            }
            SetupOptionalCard(title: tr("Ways to skip a wait"), symbol: "person.2",
                detail: overrides.contacts.isEmpty && overrides.phrasePolicies.isEmpty && overrides.passwordPolicies.isEmpty
                    ? tr("A trusted contact, a phrase, or a password. You choose what each can approve.") : overridesSummary,
                actionTitle: overrides.contacts.isEmpty && overrides.phrasePolicies.isEmpty && overrides.passwordPolicies.isEmpty
                    ? tr("Set up") : tr("Edit")) { showOverrides = true }
            VStack(alignment: .leading, spacing: DemoraSpace.m) {
                SectionHeader(tr("Your setup"))
                FactRow(label: tr("Waits"), value: policySummary)
                FactRow(label: tr("First limit"), value: firstLimit.map {
                    $0.name + " · " + String(format: tr("%d min a day"), $0.minutesPerDay)
                } ?? tr("Not yet"))
                FactRow(label: tr("Mornings & nights"), value: dayNightGroups.isEmpty
                        ? tr("Not yet") : dayNightGroups.map(\.name).joined(separator: " · "))
                FactRow(label: tr("Ways to skip a wait"), value: overridesSummary.isEmpty ? tr("Not yet") : overridesSummary)
            }
            .paperCard()
            if !accessGranted {
                Text(tr("That's okay. Without Screen Time access Demora can't block apps, but you can continue and turn it on later."))
                    .demoraType(.meta).foregroundStyle(Ink.inkSoft)
            }
            SetupEstimateDisclosure(enabled: $wantsUsageEstimate, minutes: $usageEstimateMinutes)
            Text(tr("How Demora works is in You → Help & guide."))
                .demoraType(.meta).foregroundStyle(Ink.inkSoft)
        }
    }

    private var dayNightStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(tr("Make room for your mornings and nights.")).demoraType(.pageTitle)
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
            Text(tr("A backup, if you want one.")).demoraType(.pageTitle)
            Text(tr("Optional: add a trusted contact, a phrase, or a password. Choose exactly what each can approve or unlock."))
                .foregroundStyle(Ink.faint)
            OnboardingOverridesDraftView(overrides: $overrides, isDemo: isDemo)
            Text(tr("These choices apply when you finish setup. Later additions and permission changes follow your delays."))
                .font(.footnote).foregroundStyle(Ink.faint)
            Text(tr("Contact invitations are sent after setup. Contacts must confirm before they can approve; manage them in You → Ways to skip a wait."))
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
            if step == 2 || step == 4 { return }
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
                if saved { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            }
        }
    }
}

/// Shared editorial furniture for first-run setup and the read-only 2.0 welcome.
struct DemoraWelcomeProgress: View {
    @AppAccent private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let step: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            GeometryReader { geometry in
                Capsule().fill(Ink.hairline)
                    .overlay(alignment: .leading) {
                        Capsule().fill(accent)
                            .frame(width: geometry.size.width * CGFloat(min(total, max(1, step + 1))) / CGFloat(max(1, total)))
                    }
            }
            .frame(height: 4)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
            Text(String(format: tr("Step %d of %d"), step + 1, total))
                .demoraType(.label).foregroundStyle(Ink.inkSoft)
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
                Text(title).demoraType(.cardTitle).foregroundStyle(Ink.ink)
                Text(detail).demoraType(.meta).foregroundStyle(Ink.inkSoft)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Optional setup choices stay visible without looking like required steps.
struct SetupOptionalCard: View {
    @AppAccent private var accent
    let title: String
    let symbol: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.m) {
            DemoraWelcomeEntry(symbol: symbol, title: title, detail: detail)
            Button(actionTitle, action: action)
                .buttonStyle(.plain)
                .font(DemoraType.button).foregroundStyle(accent)
                .frame(minHeight: 44)
        }
        .paperCard()
    }
}

/// Merely expands a local draft; no preference is saved until setup succeeds.
struct SetupEstimateDisclosure: View {
    @Binding var enabled: Bool
    @Binding var minutes: Int
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            WeeklyUsageEstimateDraft(enabled: $enabled, minutes: $minutes)
                .padding(.top, DemoraSpace.s)
        } label: {
            VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                Text(tr("Your starting point")).demoraType(.cardTitle)
                Text(tr("Add a rough weekly estimate")).demoraType(.meta).foregroundStyle(Ink.inkSoft)
            }
        }
        .paperCard()
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
