//
//  RedesignWelcomeView.swift
//  Existing-user welcome; rules stay intact. Eligible legacy math users can
//  explicitly stage a one-time, delay-free phrase replacement. No access prompts.
//

import SwiftUI

struct RedesignWelcomeView: View {
    @AppAccent private var accent
    @EnvironmentObject var model: AppModel
    let onComplete: () -> Void
    #if DEBUG
    var demoState: LatchState? = nil
    var demoMathOffer = false
    var demoInstallPhrases: (([PhrasePolicy]) -> Bool)? = nil
    var demoDayNightOffer = false
    var demoInstallDayNight: (([DayNightGroup]) -> Bool)? = nil
    #endif
    @State private var step = 0
    @State private var completed = false
    @State private var showPhraseReplacement = false
    @State private var phrasesReplaced = false
    @State private var dayNightGroups: [DayNightGroup] = []
    @State private var dayNightSaved = false
    @State private var savingDayNight = false
    @State private var dayNightSaveError = false

    private var offersDayNight: Bool {
        guard !dayNightSaved else { return false }
        #if DEBUG
        if demoState != nil { return demoDayNightOffer }
        #endif
        return SharedStore.canSetUpInitialDayNight
    }

    private var offersMathReplacement: Bool {
        guard !phrasesReplaced else { return false }
        #if DEBUG
        if demoState != nil { return demoMathOffer }
        #endif
        return SharedStore.canReplaceLegacyMath
    }

    private var displayedState: LatchState {
        #if DEBUG
        if let demoState { return demoState }
        #endif
        return model.state
    }

    private var isDemo: Bool {
        #if DEBUG
        return demoState != nil
        #else
        return false
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    #if DEBUG
                    if demoState != nil { DeveloperDemoNotice() }
                    #endif
                    DemoraWelcomeProgress(step: step, total: 4)
                    Group {
                        switch step {
                        case 0: navigationPage
                        case 1: limitsPage
                        case 2: dayNightPage
                        default: contactsPage
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .id(step)
            .paper()
            .casedNavigationTitle(tr("Demora 2.0"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if DEBUG
                if demoState != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Close") { complete() }
                    }
                }
                #endif
                if step > 0 {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("Back")) { step -= 1 }
                            .disabled(completed || savingDayNight)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    Button(step == 3 ? tr("Welcome back") : tr("Continue"), action: continueWelcome)
                    .buttonStyle(DemoraPrimaryButtonStyle())
                    if step == 3 {
                        Button(tr("Open my limits")) { complete(openLimits: true) }
                            .font(.subheadline).foregroundStyle(accent)
                            .frame(minHeight: 44)
                    } else {
                        Button(tr("Done")) { complete() }
                            .font(.subheadline).foregroundStyle(Ink.faint)
                            .frame(minHeight: 44)
                    }
                }
                .disabled(completed || savingDayNight)
                .padding(.horizontal, 24).padding(.vertical, 14)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .background(Ink.paper)
            }
        }
        .sheet(isPresented: $showPhraseReplacement) {
            MathPhraseMigrationView(isDemo: isDemo) { policies in
                #if DEBUG
                if demoState != nil {
                    let saved = demoInstallPhrases?(policies) ?? false
                    phrasesReplaced = saved
                    return saved
                }
                #endif
                let saved = await ChangeEngine.replaceLegacyMathOffMain(with: policies)
                if saved {
                    model.state = SharedStore.loadState()
                    phrasesReplaced = true
                }
                return saved
            }
        }
        .alert(tr("Setup couldn't be saved"), isPresented: $dayNightSaveError) {
            Button(tr("OK"), role: .cancel) { }
            Button(tr("Discard day/night drafts"), role: .destructive) { dayNightGroups = [] }
        } message: {
            Text((isDemo ? nil : MonitorRegistration.rejectionMessage)
                 ?? tr("Your choices are still here. Please try again."))
        }
    }

    private var navigationPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            DemoraPageTitle(title: tr("A clearer place for your intentions."))
            Text(tr("A new layout. The same idea: your considered choices deserve time to hold."))
                .font(.title3).foregroundStyle(Ink.faint)
            mathReplacementOffer
            VStack(alignment: .leading, spacing: 22) {
                DemoraWelcomeEntry(symbol: "house", title: tr("Home"),
                                   detail: tr("See what's active, what's next, and which changes are waiting."))
                DemoraWelcomeEntry(symbol: "hourglass", title: tr("Delays & overrides"),
                                   detail: tr("Your waits and trusted contacts now have their own place."))
                DemoraWelcomeEntry(symbol: "slider.horizontal.3", title: tr("Three ways to wait"),
                                   detail: tr("Keep separate waits, use one shared wait, or wait only when loosening rules. Your current delay mode and durations stay unchanged."))
                DemoraWelcomeEntry(symbol: "calendar", title: tr("Limits & schedules"),
                                   detail: tr("Daily boundaries in Limits. Recurring and planned time in Schedules."))
            }
            .demoraSurface()
            preservedRules
        }
    }

    private var preservedRules: some View {
        VStack(alignment: .leading, spacing: 14) {
            DemoraSectionTitle(title: tr("Carried with you"), symbol: "checkmark")
            // Configuration counts, not usage, streaks, or made-up outcomes.
            countRow(tr("Limits"), count: displayedState.limits.count)
            countRow(tr("Recurring schedules"), count: displayedState.schedules.count)
            countRow(tr("Free periods"), count: displayedState.exemptions.count)
            countRow(tr("Planned windows"), count: displayedState.planned.count)
            countRow(tr("Pending changes"), count: displayedState.pending.count)
            Text(tr("Your saved rules and pending changes are retained. Your existing delay settings are unchanged."))
                .font(.footnote).foregroundStyle(Ink.faint)
        }
        .demoraSurface()
    }

    private var limitsPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            DemoraPageTitle(title: tr("Give your day a little shape."))
            Text(tr("Keep a simple daily allowance, or make a limit fit the way your day unfolds."))
                .font(.title3).foregroundStyle(Ink.faint)
            VStack(alignment: .leading, spacing: 22) {
                DemoraWelcomeEntry(symbol: "calendar", title: tr("Different days, different budgets"),
                                   detail: tr("Set weekday allowances. Manage wake-up and sleep in Schedules → Day & night."))
                DemoraWelcomeEntry(symbol: "sun.max", title: tr("One budget, three portions"),
                                   detail: tr("Split an allowance across your day, with optional carryover."))
                DemoraWelcomeEntry(symbol: "plus.circle", title: tr("Extra time with intention"),
                                   detail: tr("Plan ordered extra-time steps, each with its own wait or approval method."))
            }
            .demoraSurface()
            mathReplacementOffer
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("A note about older features"))
                    .font(.system(.title3, design: .serif))
                Text(tr("Legacy usage-burst pacing and math overrides have been removed. Daily limits remain. Split budgets and extra-time steps are optional alternatives, not automatic replacements."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                Text(tr("Review a limit when you're ready; edits still follow your delays."))
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
            .demoraSurface()
        }
    }

    @ViewBuilder
    private var mathReplacementOffer: some View {
            if offersMathReplacement {
                VStack(alignment: .leading, spacing: 14) {
                    Text(tr("From math to phrases"))
                        .font(.system(.title3, design: .serif))
                    Text(tr("Math problems have been replaced with phrases. Since you used math overrides, you can add replacement phrases now without waiting."))
                        .foregroundStyle(Ink.faint)
                    Button(tr("Add replacement phrases")) { showPhraseReplacement = true }
                        .buttonStyle(DemoraPrimaryButtonStyle())
                    Text(tr("Optional. After this welcome, adding phrases follows your delay settings."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
                .demoraSurface()
            } else if phrasesReplaced {
                Label(tr("Your replacement phrases are ready."), systemImage: "checkmark.circle")
            }
    }

    private var contactsPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            DemoraPageTitle(title: tr("Trust, with clear boundaries."))
            Text(tr("Choose what each trusted contact can approve, instead of giving everyone the same permissions."))
                .font(.title3).foregroundStyle(Ink.faint)
            VStack(alignment: .leading, spacing: 22) {
                DemoraWelcomeEntry(symbol: "person.2", title: tr("Permission by person"),
                                   detail: tr("Scope approvals to the pending changes you choose. Extra-time approval is a separate opt-in."))
                DemoraWelcomeEntry(symbol: "hourglass", title: tr("No silent new permissions"),
                                   detail: tr("Existing contacts keep their pending-change permissions. They don't automatically gain extra-time access."))
                DemoraWelcomeEntry(symbol: "lock", title: tr("Changes still wait"),
                                   detail: tr("Editing override permissions follows your delays. This welcome doesn't change them."))
            }
            .demoraSurface()
            countRow(tr("Trusted contacts"), count: displayedState.overrides.contacts.count)
            Text(tr("You're ready. Your rules are still yours."))
                .font(.system(.title2, design: .serif))
            Text(tr("The optional walkthrough is always in Settings → Help."))
                .font(.footnote).foregroundStyle(Ink.faint)
        }
    }

    private func countRow(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Ink.faint)
            Spacer(minLength: 12)
            Text(count, format: .number)
                .font(.system(.body, design: .monospaced)).foregroundStyle(accent)
        }
        .accessibilityElement(children: .combine)
    }

    private var dayNightPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            DemoraPageTitle(title: tr("Make room for your mornings and nights."))
            Text(tr("One Wake up tap starts all eligible groups together. Give each group its own wait and sleep time."))
                .foregroundStyle(Ink.faint)
            if offersDayNight {
                Text(tr("You can add your initial day/night groups now without waiting. Existing rules and wake-up countdowns stay unchanged. Later changes follow your delays."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                DayNightSetupDraftView(limits: displayedState.limits, groups: $dayNightGroups,
                                       isDemo: isDemo, canChooseApps: model.authorized)
                    .disabled(savingDayNight)
            } else {
                Text(dayNightSaved ? tr("Your day/night groups are ready.")
                     : tr("You can change this later in Schedules → Day & night. Later changes follow your delays."))
                    .foregroundStyle(Ink.faint)
                if !dayNightGroups.isEmpty {
                    Button(tr("Discard day/night drafts"), role: .destructive) { dayNightGroups = [] }
                        .disabled(savingDayNight)
                }
            }
        }
    }

    @MainActor private func saveDayNightIfNeeded() async -> Bool {
        guard !dayNightGroups.isEmpty, !dayNightSaved else { return true }
        let saved: Bool
        #if DEBUG
        if isDemo {
            saved = demoInstallDayNight?(dayNightGroups) ?? false
        } else {
            saved = await ChangeEngine.setUpInitialDayNightOffMain(dayNightGroups)
        }
        #else
        saved = await ChangeEngine.setUpInitialDayNightOffMain(dayNightGroups)
        #endif
        if saved {
            dayNightSaved = true
            if !isDemo { model.state = SharedStore.loadState() }
            dayNightGroups = []
        } else { dayNightSaveError = true }
        return saved
    }

    private func continueWelcome() {
        guard !savingDayNight, !completed else { return }
        if step == 3 { complete(); return }
        if step != 2 { step += 1; return }
        savingDayNight = true
        Task { @MainActor in
            if await saveDayNightIfNeeded() { step += 1 }
            savingDayNight = false
        }
    }

    private func complete(openLimits: Bool = false) {
        guard !completed, !savingDayNight else { return }
        savingDayNight = true
        Task { @MainActor in
            guard await saveDayNightIfNeeded() else { savingDayNight = false; return }
            completed = true
            savingDayNight = false
            #if DEBUG
            if demoState != nil {
                onComplete()
                return
            }
            #endif
            if openLimits { model.selectedTab = 1 }
            onComplete()
        }
    }
}
