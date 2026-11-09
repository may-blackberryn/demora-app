//
//  RedesignWelcomeView.swift
//  Existing-user welcome; rules stay intact. Eligible legacy math users can
//  explicitly stage a one-time, delay-free phrase replacement. Delay-policy
//  edits use the ordinary queued editor, never a migration waiver. No access prompts.
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
    @State private var page: WelcomePage = .rules
    @State private var completed = false
    @State private var showPhraseReplacement = false
    @State private var phrasesReplaced = false
    @State private var dayNightGroups: [DayNightGroup] = []
    @State private var dayNightSaved = false
    @State private var savingDayNight = false
    @State private var dayNightSaveError = false
    @State private var wantsUsageEstimate = false
    @State private var usageEstimateMinutes = 21 * 60

    private var offersDayNight: Bool {
        guard !dayNightSaved else { return false }
        #if DEBUG
        if demoState != nil { return demoDayNightOffer }
        #endif
        // Presentation uses the already-published model snapshot. Never
        // decode/write the shared blob while SwiftUI computes this body.
        // The actual save revalidates the latest persisted state under lock.
        return SharedStore.canSetUpInitialDayNight(in: SharedStore.defaults,
                                                  state: displayedState)
    }

    private var offersMathReplacement: Bool {
        guard !phrasesReplaced else { return false }
        #if DEBUG
        if demoState != nil { return demoMathOffer }
        #endif
        return SharedStore.canReplaceLegacyMath(in: SharedStore.defaults,
                                                state: displayedState)
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

    private var pages: [WelcomePage] {
        WelcomePages.make(offersMath: offersMathReplacement, offersDayNight: offersDayNight)
    }

    private var pageIndex: Int { pages.firstIndex(of: page) ?? pages.count - 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    #if DEBUG
                    if demoState != nil { DeveloperDemoNotice() }
                    #endif
                    DemoraWelcomeProgress(step: pageIndex, total: pages.count)
                    Group {
                        switch page {
                        case .rules: navigationPage
                        case .dayNight: dayNightPage
                        case .changes: changesPage
                        }
                    }
                }
                .padding(DemoraSpace.pageGutter)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .id(page)
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
                if let previous = WelcomePages.previous(before: page, in: pages) {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("Back")) { page = previous }
                            .disabled(completed || savingDayNight)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    Button(page == .changes ? tr("Open Today") : tr("Continue"), action: continueWelcome)
                    .buttonStyle(DemoraPrimaryButtonStyle())
                    Button(tr("Skip")) { complete() }
                        .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                        .frame(minHeight: 44)
                }
                .disabled(completed || savingDayNight)
                .padding(.horizontal, DemoraSpace.pageGutter).padding(.vertical, 14)
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
            Text(tr("A clearer place for your intentions.")).demoraType(.pageTitle)
            Text(tr("A new layout. The same idea: your considered choices deserve time to hold."))
                .font(.title3).foregroundStyle(Ink.faint)
            preservedRules
            mathReplacementOffer
            VStack(alignment: .leading, spacing: 22) {
                // The four-tab names land with the tab switch, not before it.
                SectionHeader(tr("Your setup"))
                DemoraWelcomeEntry(symbol: "house", title: tr("Home"),
                                   detail: tr("See what's active, what's next, and which changes are waiting."))
                DemoraWelcomeEntry(symbol: "hourglass", title: tr("Delays & overrides"),
                                   detail: tr("Your waits and trusted contacts now have their own place."))
                DemoraWelcomeEntry(symbol: "calendar", title: tr("Limits & schedules"),
                                   detail: tr("Daily boundaries in Limits. Recurring and planned time in Schedules."))
            }
            .paperCard()
        }
    }

    private var delaySetupOffer: some View {
        VStack(alignment: .leading, spacing: 14) {
            DemoraSectionTitle(title: tr("Three ways to wait"), symbol: "slider.horizontal.3")
            Text(tr("Optional. Keep separate waits, use one shared wait, or tighten immediately and wait only when loosening rules. If you skip this, your delay settings stay unchanged."))
                .font(.subheadline).foregroundStyle(Ink.faint)
            Text(tr("Changing your delay mode follows your current delays. Countdowns already running keep their original deadline."))
                .font(.footnote).foregroundStyle(Ink.faint)
            #if DEBUG
            if isDemo {
                // Never expose the live model's queueing editor in a demo.
                NavigationLink {
                    MigrationDelayPreviewView(policy: displayedState.delayPolicy)
                } label: {
                    Label(tr("How changes wait"), systemImage: "hourglass")
                }
            } else {
                DelayPolicyNavigationRows()
            }
            #else
            DelayPolicyNavigationRows()
            #endif
        }
        .paperCard()
    }

    private var preservedRules: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(tr("Carried with you"))
            // Configuration counts, not usage, streaks, or made-up outcomes.
            countRow(tr("Limits"), count: displayedState.limits.count)
            countRow(tr("Recurring schedules"), count: displayedState.schedules.count)
            countRow(tr("Free periods"), count: displayedState.exemptions.count)
            countRow(tr("Planned windows"), count: displayedState.planned.count)
            countRow(tr("Pending changes"), count: displayedState.pending.count)
            Text(tr("Your saved rules and pending changes are retained. Unless you queue a change, your existing delay settings stay unchanged."))
                .font(.footnote).foregroundStyle(Ink.faint)
            Text(tr("Legacy usage-burst pacing and math overrides have been removed. Daily limits remain. Split budgets and extra-time steps are optional alternatives, not automatic replacements."))
                .demoraType(.meta).foregroundStyle(Ink.inkSoft)
        }
        .paperCard()
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
                .paperCard()
            } else if phrasesReplaced {
                Label(tr("Your replacement phrases are ready."), systemImage: "checkmark.circle")
            }
    }

    private var changesPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(tr("Changes still wait")).demoraType(.pageTitle)
            delaySetupOffer
            Text(tr("Existing contacts keep their permissions. They don't gain extra-time approval automatically."))
                .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                .paperCard()
            SetupEstimateDisclosure(enabled: $wantsUsageEstimate, minutes: $usageEstimateMinutes)
            Text(tr("You're ready. Your rules are still yours."))
                .demoraType(.hero)
            Text(tr("How Demora works is always in You → Help & guide."))
                .font(.footnote).foregroundStyle(Ink.faint)
        }
    }

    private func countRow(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Ink.faint)
            Spacer(minLength: 12)
            Text(count, format: .number)
                .demoraType(.time).foregroundStyle(accent)
        }
        .accessibilityElement(children: .combine)
    }

    private var dayNightPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(tr("Make room for your mornings and nights.")).demoraType(.pageTitle)
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
        if page == .changes { complete(); return }
        if page != .dayNight {
            if let next = WelcomePages.next(after: page, in: pages) { page = next }
            return
        }
        savingDayNight = true
        Task { @MainActor in
            if await saveDayNightIfNeeded() { page = .changes }
            savingDayNight = false
        }
    }

    private func complete() {
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
            if wantsUsageEstimate { WeeklyUsageEstimate.save(minutes: usageEstimateMinutes) }
            model.selectedTab = 0
            onComplete()
        }
    }
}

#if DEBUG
/// A local draft only: no AppModel, persistence, queueing, or service calls.
private struct MigrationDelayPreviewView: View {
    @State private var policy: DelayPolicy

    init(policy: DelayPolicy) {
        _policy = State(initialValue: policy)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DeveloperDemoNotice()
                DemoraPageTitle(title: tr("How changes wait"))
                Text(tr("Demo only. Try the delay choices here; nothing is queued or saved. Go back to keep exploring the welcome."))
                    .font(.subheadline).foregroundStyle(Ink.faint)
                DelayPolicyPicker(policy: $policy)
            }
            .padding(26).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Delays"))
    }
}
#endif
