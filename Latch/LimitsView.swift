//
//  LimitsView.swift
//  The legacy tutorial's Limits screen (Rules replaced it for everyone
//  else; docs/rules-redesign.md §8, R10), plus shared limit pieces: the
//  legacy wake/sleep editors, the duration wheels, selected-apps list,
//  app picker and extra-time password gate. The tutorial screens retire at
//  the four-tab switch.
//

import SwiftUI
import FamilyControls
import ManagedSettings

struct LimitsView: View {
    @AppAccent private var accent
    @EnvironmentObject var model: AppModel
    @State private var showAdd = false
    @State private var editTarget: AppLimit?
    @AppStorage("limits.countingNoteDismissed") private var countingNoteDismissed = false
    @State private var recheckInFlight = false
    @State private var recheckMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    DemoraPageTitle(title: tr("Limits & blocks"))
                    Spacer()
                    if !model.inTutorial {
                        NavigationLink {
                            HelpGuideView().toolbar(.visible, for: .navigationBar)
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .accessibilityLabel(tr("Help"))
                    }
                }
                if !model.inTutorial {
                    Button { showAdd = true } label: {
                        Label(tr("New limit"), systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(DemoraPrimaryButtonStyle())
                }
                if model.enforcementDegraded {
                    EnforcementBanner().demoraSurface()
                }
                if #unavailable(iOS 17.4) {
                    if !countingNoteDismissed {
                        DismissibleNote(
                            text: tr("Heads up: on your iOS version, a limit only counts screen time from the moment you add it — time you already spent earlier today isn't included. Update to iOS 17.4 or later for exact daily counting."),
                            onDismiss: { countingNoteDismissed = true })
                            .demoraSurface()
                    }
                }
                if !model.state.limits.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Button { beginLimitRecheck() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.shield")
                                Text(tr(recheckInFlight
                                    ? "Takes around 30 seconds"
                                    : "Recheck blocked limits"))
                                Spacer()
                                if recheckInFlight { ProgressView() }
                            }
                        }
                        .disabled(recheckInFlight)
                        Text(tr("Recheck keeps current blocks in place while iOS verifies today's usage. Limits iOS confirms stay blocked."))
                            .font(.caption).italic().foregroundStyle(Ink.faint)
                    }
                    .demoraSurface()
                }
                VStack(alignment: .leading, spacing: 14) {
                    DemoraSectionTitle(title: tr("Your limits"),
                                       symbol: "chart.bar.xaxis")
                    if model.tutorial == .addLimit && model.tutorialScreen == "limits" {
                        Button { showAdd = true } label: {
                            Label(tr("Add your first limit"), systemImage: "plus.circle.fill")
                                .font(.headline)
                        }
                        .tutorialHighlight(true)
                    } else if model.state.limits.isEmpty {
                        EmptyStateView(
                            title: tr("No limits yet"),
                            systemImage: "apps.iphone",
                            description: String(format: tr("Add a daily time limit. It activates after your 'more strict' delay (%@)."),
                                                model.state.strictDelay.shortDelayLabel)
                        )
                    }
                    // Extra time lives on Today, under the usage report (T5).
                    ForEach(model.state.limits) { limit in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { editTarget = limit } label: {
                                LimitRow(limit: limit)
                            }
                            .tint(.primary)
                            .tutorialHighlight(model.tutorial == .removeLimit
                                               && model.tutorialScreen == "limits")
                        }
                        .demoraSurface()
                    }
                }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if model.inTutorial && model.selectedTab == 1 { model.tutorialScreen = "limits" }
            }
            .sheet(isPresented: $showAdd) { TutorialLimitEditorView(existing: nil) }
            .sheet(item: $editTarget) { TutorialLimitEditorView(existing: $0) }
            .alert(tr("Limit recheck"), isPresented: Binding(
                get: { recheckMessage != nil },
                set: { if !$0 { recheckMessage = nil } }
            )) {
                Button(tr("OK"), role: .cancel) {}
            } message: {
                Text(recheckMessage ?? "")
            }
        }
    }

    private func beginLimitRecheck() {
        guard !recheckInFlight else { return }
        recheckInFlight = true
        Task {
            let result = await ChangeEngine.recheckBlockedLimits()
            switch result {
            case .completed(let released, let confirmed):
                if released > 0 {
                    recheckMessage = String(
                        format: tr("Released %d stale limit blocks. %d limits were freshly confirmed by iOS."),
                        released, confirmed)
                } else {
                    recheckMessage = tr("iOS freshly confirmed all current limit blocks.")
                }
            case .noBlockedLimits:
                recheckMessage = tr("No blocked limits need to be rechecked.")
            case .splitBlocksNotRecheckable:
                recheckMessage = tr("Split-budget blocks cannot be manually rechecked. They remain until their scheduled boundary.")
            case .freeWindowActive:
                recheckMessage = tr("Wait until the active free period ends, then recheck again.")
            case .cooldown(let remaining):
                recheckMessage = String(
                    format: tr("You can recheck again in %@."),
                    remaining.shortDelayLabel)
            case .unsupportedVersion:
                recheckMessage = tr("Safe limit rechecking requires iOS 17.4 or later. No blocks were changed.")
            case .monitorUnavailable:
                recheckMessage = tr("iOS couldn't complete the verification safely. No blocks were changed. Try again later.")
            case .cancelled:
                recheckMessage = tr("The recheck was interrupted. No blocks were changed.")
            }
            recheckInFlight = false
            model.tick()
        }
    }

}


private struct BoundaryScopeEditor: View {
    @AppAccent private var accent
    @EnvironmentObject var model: AppModel
    @Binding var scope: BoundaryBlockScope
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(BoundaryBlockMode.allCases) { mode in
                Button {
                    scope.mode = mode
                } label: {
                    HStack {
                        Image(systemName: scope.mode == mode
                              ? "largecircle.fill.circle" : "circle")
                        Text(mode.label)
                        Spacer()
                    }
                    .padding(10)
                    .background(scope.mode == mode ? accent.opacity(0.12)
                                : Ink.ink.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            if scope.mode == .blockGroups {
                if model.state.limits.isEmpty {
                    Text(tr("Add a limit group first."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
                ForEach(model.state.limits) { limit in
                    Toggle(limit.name, isOn: Binding(
                        get: { scope.groupIDs.contains(limit.id) },
                        set: { enabled in
                            if enabled { scope.groupIDs.insert(limit.id) }
                            else { scope.groupIDs.remove(limit.id) }
                        }))
                }
            } else {
                Button(tr("Choose apps")) { showPicker = true }
                    .buttonStyle(.bordered)
                SelectedAppsView(selection: scope.selection)
                if scope.mode == .blockAllExcept {
                    Text(tr("Selected apps stay usable; other apps are blocked."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
            }
            if !model.state.limits.isEmpty {
                Text(tr("Exclude limit groups from this boundary"))
                    .font(.subheadline.weight(.semibold))
                Text(tr("An excluded group still keeps its normal daily limit."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                ForEach(model.state.limits) { limit in
                    Toggle(limit.name, isOn: Binding(
                        get: { scope.excludedLimitIDs.contains(limit.id) },
                        set: { enabled in
                            if enabled { scope.excludedLimitIDs.insert(limit.id) }
                            else { scope.excludedLimitIDs.remove(limit.id) }
                        }))
                    .disabled(scope.mode == .blockAllExcept
                              && !limit.selection.categoryTokens.isEmpty
                              && !scope.excludedLimitIDs.contains(limit.id))
                }
                if scope.mode == .blockAllExcept {
                    Text(tr("iOS cannot exempt an entire app category from 'block except'; category-based groups cannot be excluded here."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            AppPickerSheet(selection: $scope.selection)
        }
    }
}

/// Legacy wake-up, reachable only from its card. All guards are the old
/// editor's: one wake/sleep change at a time, wake ≠ sleep start, `isValid`.
struct WakeBlockEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var presentation: EditorPresentation = .pushed
    @State private var rule = WakeBlockRule()
    @State private var loaded = false
    @State private var receipt: ChangeReceiptRequest?

    private func localizedWeekday(_ day: Int) -> String {
        var calendar = Calendar.current
        calendar.locale = AppLanguage.current.locale
        return calendar.weekdaySymbols[day - 1]
    }

    private var boundaryChangePending: Bool {
        RulePending.blocksEdit(of: .legacyWake, pending: model.state.pending)
    }

    private var clashesWithSleep: Bool {
        model.state.sleepRule.enabled && model.state.sleepRule.startMinutes == rule.startHour * 60
    }

    /// Why `isValid` fails, checked in the order the rule's own test reads.
    private var problem: String? {
        if clashesWithSleep { return tr("Wake-up time must differ from when sleep begins.") }
        guard !rule.isValid(in: model.state) else { return nil }
        let start = rule.startHour * 60
        let latest = [rule.latestMinutes].compactMap { $0 } + Array((rule.weekdayLatestMinutes ?? [:]).values)
        if latest.contains(where: { $0 <= start || $0 > 1410 }) {
            return tr("Choose a latest time after the wake-up day begins.")
        }
        return tr("Choose at least one app.")
    }

    var body: some View {
        RuleEditorPage(title: tr("Wake up"), presentation: presentation,
                       isDirty: loaded && rule != model.state.wakeRule,
                       problem: problem,
                       canReview: loaded && rule != model.state.wakeRule && problem == nil,
                       waiting: boundaryChangePending,
                       onReview: { receipt = ChangeReceiptRequest(action: .setWakeRule(rule)) }) {
            EditorSection(tr("Wake-up")) {
                Toggle(tr("Enable wake-up blocking"), isOn: $rule.enabled).frame(minHeight: 44)
                Text(tr("Wake-up day begins")).demoraType(.body).foregroundStyle(Ink.ink)
                Picker(tr("Wake-up day begins"), selection: $rule.startHour) {
                    ForEach([0, 3, 6, 9], id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
                .pickerStyle(.segmented)
                EditorNote(text: tr("Sleep blocking ends at this time, even if the wake-up tap is off."))
                if rule.enabled {
                    Text(tr("Wait after tapping Wake up")).demoraType(.body).foregroundStyle(Ink.ink)
                    DurationControl(minutes: $rule.waitMinutes, range: 0...1440)
                    WakeCeilingPicker(latestMinutes: $rule.latestMinutes,
                                      startMinutes: rule.startHour * 60)
                }
            }
            if rule.enabled {
                EditorSection(tr("Days")) {
                    DayChips(selection: $rule.weekdays)
                    EditorRow(title: tr("Different times per day"),
                              value: tr((rule.weekdayLatestMinutes ?? [:]).isEmpty ? "Off" : "On")) {
                        EditorSubPage(title: tr("Customize wake-up by day")) {
                            EditorSection(tr("Wake-up")) { perDay }
                        }
                    }
                }
                EditorSection(tr("What")) {
                    BoundaryScopeEditor(scope: $rule.scope)
                }
            }
        }
        .changeReceipt($receipt) { dismiss() }
        .onAppear {
            guard !loaded else { return }
            rule = model.state.wakeRule
            loaded = true
        }
    }

    @ViewBuilder private var perDay: some View {
        ForEach(rule.weekdays.sorted(), id: \.self) { day in
            VStack(alignment: .leading, spacing: 10) {
                Toggle(localizedWeekday(day), isOn: Binding(
                    get: { rule.weekdayLatestMinutes?[day] != nil },
                    set: { enabled in
                        if enabled {
                            var overrides = rule.weekdayLatestMinutes ?? [:]
                            overrides[day] = rule.latestMinutes ?? min(1410, max(720, rule.startHour * 60 + 30))
                            rule.weekdayLatestMinutes = overrides
                        } else { rule.weekdayLatestMinutes?.removeValue(forKey: day) }
                    }))
                if rule.weekdayLatestMinutes?[day] != nil {
                    WakeCeilingPicker(latestMinutes: Binding(
                        get: { rule.weekdayLatestMinutes?[day] },
                        set: { value in rule.weekdayLatestMinutes?[day] = value }),
                        startMinutes: rule.startHour * 60)
                }
            }.padding(.vertical, 8)
        }
    }
}

/// Legacy sleep, reachable only from its card. Guards unchanged.
struct SleepBlockEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var presentation: EditorPresentation = .pushed
    @State private var rule = SleepBlockRule()
    @State private var loaded = false
    @State private var receipt: ChangeReceiptRequest?

    private var boundaryChangePending: Bool {
        RulePending.blocksEdit(of: .legacySleep, pending: model.state.pending)
    }

    private var hour: Binding<Int> {
        Binding(get: { rule.startMinutes / 60 },
                set: { rule.startMinutes = $0 * 60
                    + min(rule.startMinutes % 60, $0 == 23 ? 30 : 45) })
    }
    private var minute: Binding<Int> {
        Binding(get: { rule.startMinutes % 60 },
                set: { rule.startMinutes = (rule.startMinutes / 60) * 60 + $0 })
    }

    private var valid: Bool {
        rule.isValid(in: model.state, wakeHour: model.state.wakeRule.startHour)
    }

    /// Why `isValid` fails: the start can't be the wake-up hour; otherwise
    /// it's the apps this blocks.
    private var problem: String? {
        guard !valid else { return nil }
        if rule.enabled && rule.startMinutes == model.state.wakeRule.startHour * 60 {
            return tr("Wake-up time must differ from when sleep begins.")
        }
        return tr("Choose at least one app.")
    }

    var body: some View {
        RuleEditorPage(title: tr("Sleep"), presentation: presentation,
                       isDirty: loaded && rule != model.state.sleepRule,
                       problem: problem,
                       canReview: loaded && rule != model.state.sleepRule && valid,
                       waiting: boundaryChangePending,
                       onReview: { receipt = ChangeReceiptRequest(action: .setSleepRule(rule)) }) {
            EditorSection(tr("Sleep")) {
                Toggle(tr("Enable sleep blocking"), isOn: $rule.enabled).frame(minHeight: 44)
                if rule.enabled {
                    Text(tr("Sleep begins")).demoraType(.body).foregroundStyle(Ink.ink)
                    HStack {
                        Picker(tr("Hour"), selection: hour) {
                            ForEach(0..<24, id: \.self) {
                                Text(String(format: "%02d", $0)).tag($0)
                            }
                        }
                        Picker(tr("Minute"), selection: minute) {
                            ForEach(rule.startMinutes / 60 == 23
                                    ? [0, 15, 30] : [0, 15, 30, 45], id: \.self) {
                                Text(String(format: "%02d", $0)).tag($0)
                            }
                        }
                    }
                    EditorNote(text: String(format: tr("Ends at %02d:00, when the wake-up day begins."),
                                            model.state.wakeRule.startHour))
                }
            }
            if rule.enabled {
                EditorSection(tr("Days")) {
                    DayChips(selection: $rule.weekdays)
                }
                EditorSection(tr("What")) {
                    BoundaryScopeEditor(scope: $rule.scope)
                }
            }
        }
        .changeReceipt($receipt) { dismiss() }
        .onAppear {
            guard !loaded else { return }
            rule = model.state.sleepRule
            loaded = true
        }
    }
}

/// Shown on Limits and Home when iOS couldn't schedule all background monitors
/// (too many limits/schedules for the ~20-activity cap), so a user knows some
/// blocking may not run in the background instead of it failing silently.
struct EnforcementBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Background blocking may be incomplete"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.ink)
                Text(tr("iOS limits how many limits and schedules can run in the background at once. Removing a few restores full enforcement."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

/// A limit row in the manage list (usage is shown by the report above).
struct LimitRow: View {
    @AppAccent private var accent
    let limit: AppLimit

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hourglass")
                .font(.system(size: 22, weight: .ultraLight))
                .foregroundStyle(accent)
                .frame(width: 30, height: 42)
            VStack(alignment: .leading, spacing: 5) {
                Text(limit.name)
                    .font(.system(.title2, design: .serif))
                    .foregroundStyle(Ink.ink)
                Text(String(format: tr("%d apps, %d categories"),
                            limit.selection.applicationTokens.count,
                            limit.selection.categoryTokens.count))
                    .font(.caption).foregroundStyle(Ink.faint)
            }
            Spacer(minLength: 6)
            Text(limitMinutesLabel(limit.minutes(on: Date())))
                .font(.system(.body, design: .serif))
                .foregroundStyle(accent)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Ink.faint)
        }
        .padding(.vertical, 3)
    }
}

/// "Blocked all day" for a 0-minute limit, otherwise "N min/day".
func limitMinutesLabel(_ minutes: Int) -> String {
    minutes == 0 ? tr("Blocked all day")
                 : String(format: tr("%d min/day"), minutes)
}

/// Hours + minutes wheels for choosing a duration in minutes, from 1 minute up
/// to a cap. Replaces coarse steppers so any length is selectable without
/// endless tapping.
struct DurationPicker: View {
    @Binding var minutes: Int
    var maxHours: Int
    /// Lowest selectable total minutes. Limits allow 0 (block all day);
    /// sessions keep a floor of 1.
    var minMinutes: Int = 1

    private var cap: Int { maxHours * 60 }
    private func clamp(_ v: Int) -> Int { Swift.min(cap, Swift.max(minMinutes, v)) }

    private var hours: Binding<Int> {
        Binding(get: { Swift.min(minutes, cap) / 60 },
                set: { minutes = clamp($0 * 60 + minutes % 60) })
    }
    private var mins: Binding<Int> {
        Binding(get: { Swift.min(minutes, cap) % 60 },
                set: { minutes = clamp((minutes / 60) * 60 + $0) })
    }

    var body: some View {
        HStack {
            Picker(tr("Hours"), selection: hours) {
                ForEach(0...maxHours, id: \.self) {
                    Text(String(format: tr("%d hr"), $0)).tag($0)
                }
            }
            .pickerStyle(.wheel)
            Picker(tr("Minutes"), selection: mins) {
                ForEach(0..<60, id: \.self) {
                    Text(String(format: tr("%d min"), $0)).tag($0)
                }
            }
            .pickerStyle(.wheel)
        }
        .frame(height: 110)
    }
}

/// Lists the apps, categories, and web domains in a selection with their real
/// system icons and names. The tokens are opaque (no readable names for
/// privacy), but `Label(token)` renders each through Screen Time.
struct SelectedAppsView: View {
    let selection: FamilyActivitySelection

    var body: some View {
        let apps = Array(selection.applicationTokens)
        let cats = Array(selection.categoryTokens)
        let webs = Array(selection.webDomainTokens)
        if apps.isEmpty && cats.isEmpty && webs.isEmpty {
            Text(tr("Nothing selected"))
                .font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(cats, id: \.self) { Label($0).font(.system(.subheadline, design: .serif)) }
            ForEach(apps, id: \.self) { Label($0).font(.system(.subheadline, design: .serif)) }
            ForEach(webs, id: \.self) { Label($0).font(.system(.subheadline, design: .serif)) }
        }
    }
}

/// The limit editor the legacy tutorial's steps were written for (they
/// highlight its Remove button and queue directly). Everyone else uses
/// `LimitEditorView` (RuleEditors.swift). Retired with the tutorial (R10).
struct TutorialLimitEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let existing: AppLimit?
    @State private var name = ""
    @State private var selection = FamilyActivitySelection()
    @State private var minutes = 30
    @State private var weekdayEnabled = false
    @State private var weekdayMinutes: [Int: Int] = [:]
    @State private var splitEnabled = false
    @State private var splitCutoffHour = 12
    @State private var splitBeforeMinutes = 15
    @State private var splitThreePortions = true
    @State private var splitSecondCutoffHour = 18
    @State private var splitMiddleMinutes = 10
    @State private var splitCarryUnused = false
    @State private var extraEnabled = false
    @State private var extraSteps = [LimitExtraStep(minutes: 20, waitMinutes: 5),
                                      LimitExtraStep(minutes: 10, waitMinutes: 15)]
    @State private var showPicker = false
    // Disclosure state is presentation-only; closing a section never clears its draft.
    @State private var showWeekdaySettings = false
    @State private var showSplitSettings = false
    @State private var showExtraSettings = false
    @State private var receipt: ChangeReceiptRequest?

    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(alignment: .leading, spacing: 16) {
                if existing == nil {
                    Section(tr("Name")) {
                        TextField(tr("e.g. Instagram"), text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    .demoraSurface()
                }
                Section(tr("Apps")) {
                    if existing == nil || !model.inTutorial {
                        Button {
                            showPicker = true
                        } label: {
                            HStack {
                                Text(tr(existing == nil ? "Choose apps" : "Edit apps"))
                                Spacer()
                                Text(String(format: tr("%d selected"),
                                            selection.applicationTokens.count
                                            + selection.categoryTokens.count
                                            + selection.webDomainTokens.count))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    SelectedAppsView(selection: selection)
                }
                .demoraSurface()
                Section {
                    DurationPicker(minutes: $minutes, maxHours: 12, minMinutes: 0)
                } header: {
                    Text(tr("Daily limit"))
                } footer: {
                    Text(minutes == 0
                         ? tr("0 minutes — this app stays blocked all day, every day.")
                         : String(format: tr("%d min/day"), minutes))
                }
                .demoraSurface()

                if !model.inTutorial {
                    weekdaySettings
                    splitBudgetSettings
                    extraTimeSettings
                    if showSplitSettings || showExtraSettings {
                        Section {
                            Text(tr("iOS Screen Time callbacks can arrive late. Wake-up, split, and extra-time boundaries may not switch at the exact minute."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .demoraSurface()
                    }
                }

                // Outside the legacy tutorial the receipt explains the wait,
                // so the inline hints only stay for the tutorial's steps.
                if let existing {
                    if model.inTutorial { delayHint(.configureLimit(draftLimit)) }
                    Section {
                        Button(tr("Remove this limit"), role: .destructive) {
                            submit(.removeLimit(id: existing.id))
                        }
                        .tutorialHighlight(model.tutorial == .removeLimit
                                           && model.tutorialScreen == "limitEditor")
                        if model.inTutorial { delayHintText(.removeLimit(id: existing.id)) }
                    }
                    .demoraSurface()
                } else if model.inTutorial {
                    delayHint(.addLimit(draftLimit))
                }
              }
              .padding(20)
              .frame(maxWidth: 640)
              .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(existing == nil ? tr("New limit") : existing!.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Queue change")) {
                        submit(existing != nil ? .configureLimit(draftLimit) : .addLimit(draftLimit))
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showPicker) {
                AppPickerSheet(selection: $selection)
            }
            .changeReceipt($receipt) { dismiss() }
            .onAppear {
                if let existing {
                    minutes = existing.minutesPerDay
                    selection = existing.selection
                    weekdayEnabled = !existing.weekdayMinutes.isEmpty
                    weekdayMinutes = existing.weekdayMinutes
                    splitEnabled = existing.split != nil
                    if let split = existing.split {
                        splitCutoffHour = min(22, max(1, split.cutoffMinutes / 60))
                        splitBeforeMinutes = split.beforeMinutes
                        splitThreePortions = split.secondCutoffMinutes != nil
                        splitSecondCutoffHour = split.secondCutoffMinutes.map { $0 / 60 }
                            ?? min(23, max(18, splitCutoffHour + 1))
                        splitMiddleMinutes = split.middleMinutes ?? 10
                        splitCarryUnused = split.carryUnused
                    }
                    extraEnabled = existing.extraTime != nil
                    if let extra = existing.extraTime {
                        extraSteps = extra.effectiveSteps
                    }
                }
                if model.inTutorial { model.tutorialScreen = "limitEditor" }
            }
            .onChange(of: minutes) { budget in
                splitBeforeMinutes = min(splitBeforeMinutes, budget)
                splitMiddleMinutes = min(
                    splitMiddleMinutes, max(0, budget - splitBeforeMinutes))
            }
            .onDisappear {
                // If they cancelled (still on a Limits step, same tab), restore
                // the Limits screen so the blocker stays active and tabs locked.
                if model.inTutorial && model.selectedTab == 1 {
                    model.tutorialScreen = "limits"
                }
            }
        }
    }

    private var weekdaySettings: some View {
        DisclosureGroup(isExpanded: $showWeekdaySettings) {
            Section {
                Toggle(tr("Different limits by weekday"), isOn: $weekdayEnabled)
                if weekdayEnabled {
                    ForEach(1...7, id: \.self) { day in
                        Stepper(value: weekdayBinding(for: day), in: 0...720) {
                            HStack {
                                Text(localizedWeekdays[day - 1])
                                Spacer()
                                Text(limitMinutesLabel(weekdayMinutes[day] ?? minutes))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text(tr("Each weekday's budget replaces the daily limit for that day."))
            }
            .onChange(of: weekdayEnabled) { enabled in
                if enabled && weekdayMinutes.isEmpty {
                    weekdayMinutes = Dictionary(uniqueKeysWithValues:
                        (1...7).map { ($0, minutes) })
                }
            }
        } label: {
            advancedSettingsLabel(tr("Different limits by weekday"), enabled: weekdayEnabled)
        }
        .demoraSurface()
    }

    private var splitBudgetSettings: some View {
        DisclosureGroup(isExpanded: $showSplitSettings) {
            Section {
                Toggle(tr("Split daily budget"), isOn: $splitEnabled)
                if splitEnabled {
                    Toggle(tr("Three time portions"), isOn: $splitThreePortions)
                        .onChange(of: splitThreePortions) { enabled in
                            if enabled {
                                splitCutoffHour = min(splitCutoffHour, 21)
                                splitSecondCutoffHour = max(
                                    splitCutoffHour + 1, splitSecondCutoffHour)
                                splitMiddleMinutes = min(
                                    splitMiddleMinutes,
                                    max(0, minutes - splitBeforeMinutes))
                            }
                        }
                    Picker(tr("First cutoff"), selection: $splitCutoffHour) {
                        ForEach(1...(splitThreePortions ? 21 : 22), id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .onChange(of: splitCutoffHour) { hour in
                        splitSecondCutoffHour = max(splitSecondCutoffHour, hour + 1)
                    }
                    Stepper(value: $splitBeforeMinutes,
                            in: 0...min(720, minutes)) {
                        Text(String(format: tr("First portion: %d minutes"),
                                    splitBeforeMinutes))
                    }
                    .onChange(of: splitBeforeMinutes) { first in
                        splitMiddleMinutes = min(
                            splitMiddleMinutes, max(0, minutes - first))
                    }
                    if splitThreePortions {
                        Picker(tr("Second cutoff"), selection: $splitSecondCutoffHour) {
                            ForEach((splitCutoffHour + 1)...23, id: \.self) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour)
                            }
                        }
                        Stepper(value: $splitMiddleMinutes,
                                in: 0...max(0, minutes - splitBeforeMinutes)) {
                            Text(String(format: tr("Middle portion: %d minutes"),
                                               splitMiddleMinutes))
                        }
                    }
                    Text(String(format: tr("Final portion: %d minutes"),
                                max(0, minutes - splitBeforeMinutes
                                    - (splitThreePortions ? splitMiddleMinutes : 0))))
                        .foregroundStyle(.secondary)
                    Toggle(tr("Carry unused early minutes forward"),
                           isOn: $splitCarryUnused)
                }
            } footer: {
                Text(tr("Divide today's usage into time-of-day portions. Unused minutes can carry into later portions if you choose."))
            }
        } label: {
            advancedSettingsLabel(tr("Split daily budget"), enabled: splitEnabled)
        }
        .demoraSurface()
    }

    private var extraTimeSettings: some View {
        DisclosureGroup(isExpanded: $showExtraSettings) {
            Section {
                Toggle(tr("Manual extra time"), isOn: $extraEnabled)
                if extraEnabled {
                    ForEach(extraSteps.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(format: tr("Use %d"), index + 1))
                                    .font(.headline)
                                Spacer()
                                if extraSteps.count > 1 {
                                    Button(role: .destructive) {
                                        extraSteps.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                }
                            }
                            Stepper(value: Binding(
                                get: { extraSteps[index].minutes },
                                set: { extraSteps[index].minutes = $0 }),
                                in: 1...120) {
                                Text(String(format: tr("Extra usage: %d minutes"),
                                                   extraSteps[index].minutes))
                            }
                            Menu {
                                Button(tr("Wait")) {
                                    extraSteps[index].passwordPolicyID = nil
                                    extraSteps[index].phrasePolicyID = nil
                                    extraSteps[index].contactRequired = false
                                }
                                ForEach(model.state.overrides.passwordPolicies.filter {
                                    $0.allowed.contains(.extraTime)
                                }) { policy in
                                    Button(policy.name) {
                                        extraSteps[index].passwordPolicyID = policy.id
                                        extraSteps[index].phrasePolicyID = nil
                                        extraSteps[index].contactRequired = false
                                    }
                                }
                                ForEach(model.state.overrides.phrasePolicies.filter {
                                    $0.allowed.contains(.extraTime)
                                }) { policy in
                                    Button(policy.name) {
                                        extraSteps[index].phrasePolicyID = policy.id
                                        extraSteps[index].passwordPolicyID = nil
                                        extraSteps[index].contactRequired = false
                                    }
                                }
                                if model.state.overrides.contactsEnabled
                                    && model.state.overrides.contacts.contains(where: {
                                        $0.isUsable && $0.allowed.contains(.extraTime)
                                    }) {
                                    Button(tr("Ask a trusted contact")) {
                                        extraSteps[index].contactRequired = true
                                        extraSteps[index].passwordPolicyID = nil
                                        extraSteps[index].phrasePolicyID = nil
                                    }
                                }
                            } label: {
                                let passwordName = model.state.overrides.passwordPolicies.first {
                                    $0.id == extraSteps[index].passwordPolicyID
                                }?.name
                                let phraseName = model.state.overrides.phrasePolicies.first {
                                    $0.id == extraSteps[index].phrasePolicyID
                                }?.name
                                Label(extraSteps[index].contactRequired
                                      ? tr("Ask a trusted contact")
                                      : passwordName ?? phraseName ?? tr("Wait"),
                                      systemImage: "chevron.down")
                            }
                            if extraSteps[index].passwordPolicyID == nil
                                && extraSteps[index].phrasePolicyID == nil
                                && !extraSteps[index].contactRequired {
                                Stepper(value: Binding(
                                    get: { extraSteps[index].waitMinutes },
                                    set: { extraSteps[index].waitMinutes = $0 }),
                                    in: 1...1440) {
                                    Text(String(format: tr("Wait: %d minutes"),
                                                       extraSteps[index].waitMinutes))
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    if extraSteps.count < 5 {
                        Button {
                            extraSteps.append(LimitExtraStep(minutes: 10,
                                                             waitMinutes: 15))
                        } label: {
                            Label(tr("Add another use"), systemImage: "plus.circle")
                        }
                    }
                }
            } footer: {
                Text(tr("Set the usage minutes and gate for each use. Extra time is available only after the full daily limit is spent, and resets at midnight."))
            }
        } label: {
            advancedSettingsLabel(tr("Manual extra time"), enabled: extraEnabled)
        }
        .demoraSurface()
    }

    private func advancedSettingsLabel(_ title: String, enabled: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(tr(enabled ? "On" : "Off"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var draftLimit: AppLimit {
        var draft = existing ?? AppLimit(name: name.isEmpty ? tr("Limit") : name,
                                         selection: selection, minutesPerDay: minutes)
        draft.selection = selection
        draft.minutesPerDay = minutes
        draft.weekdayMinutes = weekdayEnabled ? weekdayMinutes : [:]
        // Wake-up settings now belong to Schedules. Keep legacy gates until migration.
        draft.wakeDelayMinutes = existing?.wakeDelayMinutes
        draft.split = splitEnabled
            ? LimitSplit(cutoffMinutes: splitCutoffHour * 60,
                         beforeMinutes: min(splitBeforeMinutes, minutes),
                         carryUnused: splitCarryUnused,
                         secondCutoffMinutes: splitThreePortions
                            ? max(splitCutoffHour + 1, splitSecondCutoffHour) * 60 : nil,
                         middleMinutes: splitThreePortions
                            ? min(splitMiddleMinutes,
                                  max(0, minutes - splitBeforeMinutes)) : nil)
            : nil
        draft.pacing = nil
        if extraEnabled, let first = extraSteps.first {
            draft.extraTime = LimitExtraTime(minutesPerUse: first.minutes,
                                             usesPerDay: extraSteps.count,
                                             waitMinutes: first.waitMinutes,
                                             steps: extraSteps)
        } else {
            draft.extraTime = nil
        }
        return draft
    }

    private var isValid: Bool {
        let hasSelection = !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
        if extraEnabled && (extraSteps.isEmpty
            || minutes + extraSteps.reduce(0, { $0 + $1.minutes }) > 1439
            || extraSteps.contains(where: { step in
                if [step.passwordPolicyID != nil, step.phrasePolicyID != nil,
                    step.contactRequired].filter({ $0 }).count > 1 { return true }
                if step.contactRequired {
                    return !model.state.overrides.contactsEnabled
                        || !model.state.overrides.contacts.contains(where: {
                            $0.isUsable && $0.allowed.contains(.extraTime)
                        })
                }
                if let id = step.passwordPolicyID {
                    return !model.state.overrides.passwordPolicies.contains(where: {
                        $0.id == id && $0.allowed.contains(.extraTime)
                    })
                }
                if let id = step.phrasePolicyID {
                    return !model.state.overrides.phrasePolicies.contains(where: {
                        $0.id == id && $0.allowed.contains(.extraTime)
                    })
                }
                return false
            })) {
            return false
        }
        if let existing {
            return hasSelection && draftLimit != existing
        }
        return !name.isEmpty && hasSelection
    }

    private func weekdayBinding(for day: Int) -> Binding<Int> {
        Binding(get: { weekdayMinutes[day] ?? minutes },
                set: { weekdayMinutes[day] = $0 })
    }

    private var localizedWeekdays: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLanguage.current.locale
        return calendar.weekdaySymbols
    }

    /// Saving and removing end on the change receipt, which queues the change
    /// and then closes this editor. The legacy tutorial queues directly, as
    /// its steps expect.
    private func submit(_ action: ChangeAction) {
        if model.inTutorial {
            model.queue(action)
            dismiss()
        } else {
            receipt = ChangeReceiptRequest(action: action)
        }
    }

    @ViewBuilder
    private func delayHint(_ action: ChangeAction) -> some View {
        Section {
            delayHintText(action)
        }
    }

    private func delayHintText(_ action: ChangeAction) -> some View {
        let (dir, delay) = model.preview(action)
        return Label(
            String(format: tr("%@ — takes effect in %@"),
                   dir.label, delay.shortDelayLabel),
            systemImage: "clock"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

struct ExtraTimePasswordGate: View {
    let limitID: UUID
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var working = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(tr("Enter the password for this extra-time use."))
                    SecureField(tr("Password"), text: $password)
                        .textContentType(.password)
                    if failed {
                        Text(tr("Wrong password or this extra-time use is no longer available."))
                            .font(.footnote).foregroundStyle(.red)
                    }
                    Button(working ? tr("Checking…") : tr("Get extra time")) {
                        guard !working else { return }
                        working = true
                        let hash = AppModel.hash(password)
                        Task {
                            let started = await ChangeEngine.requestExtraTimeOffMain(
                                limitID: limitID, candidateHash: hash)
                            password = ""
                            working = false
                            model.tick()
                            if started { dismiss() } else { failed = true }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty || working)
                }
                .demoraSurface()
                .padding(20)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Extra time"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close")) { dismiss() }
                }
            }
        }
    }
}

/// Hosts FamilyActivityPicker in its own sheet with an explicit Done button.
/// The .familyActivityPicker modifier is unstable on iOS 17/18 — the
/// system picker runs out-of-process, and when it crashes it dismisses the
/// whole sheet stack, losing the user's edits. With this wrapper the picker
/// crash only closes this sheet; the selection binding keeps whatever was
/// already tapped and the editor underneath survives.
struct AppPickerSheet: View {
    @Binding var selection: FamilyActivitySelection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FamilyActivityPicker(selection: $selection)
                .casedNavigationTitle(tr("Choose apps"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Done")) { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Dismissible note

/// A small italic informational note with an X to dismiss it. Dismissing only
/// hides it where it appears; the same notes stay available under
/// Help → Limitations.
struct DismissibleNote: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.caption).italic().foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(tr("Dismiss"))
            }
            .buttonStyle(.plain)
        }
    }
}
