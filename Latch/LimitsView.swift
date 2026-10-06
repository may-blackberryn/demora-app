//
//  LimitsView.swift
//  Active app limits. Adding, editing, and removing all go through
//  the change engine (and therefore through a delay).
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
    @State private var extraTimeMessage: String?
    @State private var extraPasswordTarget: AppLimit?
    @State private var extraPhraseTarget: AppLimit?
    @State private var extraContactTarget: ExtraContactContext?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    DemoraPageTitle(title: tr("Limits & blocks"))
                    Spacer()
                    if !model.inTutorial {
                        NavigationLink {
                            HelpHubView().toolbar(.visible, for: .navigationBar)
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .accessibilityLabel(tr("Help"))
                        Button { showAdd = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(tr("New limit"))
                    }
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
                    ForEach(model.state.limits) { limit in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { editTarget = limit } label: {
                                LimitRow(limit: limit)
                            }
                            .tint(.primary)
                            .tutorialHighlight(model.tutorial == .removeLimit
                                               && model.tutorialScreen == "limits")
                            if limit.extraTime != nil && !model.inTutorial {
                                extraTimeControl(for: limit)
                            }
                        }
                        .demoraSurface()
                    }
                }
                if !model.inTutorial {
                    VStack(alignment: .leading, spacing: 12) {
                        DemoraSectionTitle(title: tr("General blocks"),
                                           symbol: "shield.lefthalf.filled")
                        GeneralBlockingCards()
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
            .sheet(isPresented: $showAdd) { LimitEditorView(existing: nil) }
            .sheet(item: $editTarget) { LimitEditorView(existing: $0) }
            .sheet(item: $extraPasswordTarget) { limit in
                ExtraTimePasswordGate(limitID: limit.id)
            }
            .sheet(item: $extraPhraseTarget) { limit in
                ExtraTimePhraseGate(limitID: limit.id)
            }
            .sheet(item: $extraContactTarget) { context in
                ContactGateView(changes: [], extraContext: context,
                                onSuccess: { model.tick() })
            }
            .alert(tr("Limit recheck"), isPresented: Binding(
                get: { recheckMessage != nil },
                set: { if !$0 { recheckMessage = nil } }
            )) {
                Button(tr("OK"), role: .cancel) {}
            } message: {
                Text(recheckMessage ?? "")
            }
            .alert(tr("Extra time"), isPresented: Binding(
                get: { extraTimeMessage != nil },
                set: { if !$0 { extraTimeMessage = nil } }
            )) {
                Button(tr("OK"), role: .cancel) {}
            } message: {
                Text(extraTimeMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func extraTimeControl(for limit: AppLimit) -> some View {
        switch LimitFeatures.extraTimeState(for: limit) {
        case .notConfigured:
            EmptyView()
        case .notNeeded(let remaining):
            Text(String(format: tr("Extra-time requests left today: %d"), remaining))
                .font(.caption).foregroundStyle(.secondary)
        case .ready(let remaining):
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    let id = limit.id
                    if let pending = ContactsRelay.pendingExtraRequest(for: id) {
                        extraContactTarget = pending
                        return
                    }
                    if let steps = limit.extraTime?.effectiveSteps,
                       steps.indices.contains(steps.count - remaining) {
                        let step = steps[steps.count - remaining]
                        if step.contactRequired {
                            extraContactTarget = ExtraContactContext(
                                requestID: UUID().uuidString, limitID: id,
                                day: SharedStore.dayKey(for: TimeGuard.now()),
                                stepIndex: steps.count - remaining,
                                step: step, limitName: limit.name)
                            return
                        }
                        if step.passwordPolicyID != nil {
                            extraPasswordTarget = limit
                            return
                        }
                        if step.phrasePolicyID != nil {
                            extraPhraseTarget = limit
                            return
                        }
                    }
                    Task {
                        let started = await ChangeEngine.requestExtraTimeOffMain(limitID: id)
                        model.tick()
                        if !started {
                            extraTimeMessage = tr("Extra time could not be started safely. Your limit is still in place; try again later.")
                        }
                    }
                } label: {
                    Label(ContactsRelay.pendingExtraRequest(for: limit.id) != nil
                          ? tr("Waiting for a trusted contact")
                          : String(format: tr("Request extra time (%d left)"), remaining),
                          systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                if let steps = limit.extraTime?.effectiveSteps,
                   steps.indices.contains(steps.count - remaining) {
                    let step = steps[steps.count - remaining]
                    if step.contactRequired {
                        Text(String(format: tr("Next use: %d usage minutes after contact approval"),
                                    step.minutes))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let policyID = step.passwordPolicyID {
                        let name = model.state.overrides.passwordPolicies.first {
                            $0.id == policyID
                        }?.name ?? tr("Unavailable password")
                        Text(String(format: tr("Next use: %d usage minutes after entering %@"),
                                    step.minutes, name))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let policyID = step.phrasePolicyID {
                        let name = model.state.overrides.phrasePolicies.first {
                            $0.id == policyID
                        }?.name ?? tr("Unavailable phrase")
                        Text(String(format: tr("Next use: %d usage minutes after typing %@"),
                                    step.minutes, name))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(String(format: tr("Next use: %d usage minutes after a %d-minute wait"),
                                    step.minutes, step.waitMinutes))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        case .waiting(let until, let remaining):
            let seconds = max(1, until.timeIntervalSince(TimeGuard.now()))
            HStack {
                Text(tr("Extra time available in"))
                Text(timerInterval: Date.now...Date.now.addingTimeInterval(seconds),
                     countsDown: true)
                    .monospacedDigit()
                Text(String(format: tr("(%d requests left)"), remaining))
            }
            .font(.caption).foregroundStyle(.secondary)
        case .active(let remaining):
            Text(String(format: tr("Extra usage active · %d requests left"), remaining))
                .font(.caption).foregroundStyle(accent)
        case .exhausted:
            Text(tr("No extra-time requests left today"))
                .font(.caption).foregroundStyle(.secondary)
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

/// The Screen Time extension is shown on Home, while Limits only lists rules.
/// Keep refresh state here so changing tabs does not couple the report to edits.
struct HomeUsageCard: View {
    @AppAccent private var accent
    let limitCount: Int
    @ScaledMetric(relativeTo: .body) private var reportRowHeight: CGFloat = 120
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("latch.accentColor", store: SharedStore.defaults)
    private var accentColorRaw = "blue"
    @AppStorage("limits.usageNoteDismissed") private var usageNoteDismissed = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var refreshedAt = Date()
    @State private var reportID = 0
    @State private var didWarmReport = false
    @State private var showReport = true
    @State private var reloadInFlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                DemoraSectionTitle(title: tr("Today's usage"),
                                   symbol: "chart.bar.fill")
                Spacer()
                Button { reloadReport() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(tr("Refresh"))
            }
            if showReport {
                LimitsUsageReportView(refreshedAt: refreshedAt)
                    .id(reportID)
                    .frame(minHeight: max(132, CGFloat(limitCount) * reportRowHeight + 16))
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .frame(minHeight: max(132, CGFloat(limitCount) * reportRowHeight + 16))
            }
            if !usageNoteDismissed {
                DismissibleNote(
                    text: tr("Today's usage is reported by iOS Screen Time, which can be slow to load or briefly show nothing. If it looks empty, tap the refresh arrow a couple of times."),
                    onDismiss: { usageNoteDismissed = true })
            }
        }
        .demoraSurface()
        .onAppear {
            refreshReport()
            if !didWarmReport {
                didWarmReport = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { reloadReport() }
                for delay in [1.8, 3.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        refreshReport()
                    }
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { refreshReport() }
        }
        .onChange(of: appearanceRaw) { _ in refreshReport() }
        .onChange(of: accentColorRaw) { _ in refreshReport() }
    }

    private func refreshReport() { refreshedAt = Date() }

    private func reloadReport() {
        guard !reloadInFlight else { return }
        reloadInFlight = true
        showReport = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            reportID += 1
            refreshedAt = Date()
            showReport = true
            reloadInFlight = false
        }
    }
}

private struct BoundaryWeekdaysEditor: View {
    @AppAccent private var accent
    @Binding var weekdays: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Days")).font(.headline)
            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { day in
                    Button {
                        if weekdays.contains(day) { weekdays.remove(day) }
                        else { weekdays.insert(day) }
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(weekdays.contains(day) ? .white : Ink.ink)
                            .background(weekdays.contains(day) ? accent
                                        : Ink.ink.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .demoraSurface()
    }
}

private struct BoundaryScopeEditor: View {
    @AppAccent private var accent
    @EnvironmentObject var model: AppModel
    @Binding var scope: BoundaryBlockScope
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("What to block")).font(.headline)
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
        .demoraSurface()
        .sheet(isPresented: $showPicker) {
            AppPickerSheet(selection: $scope.selection)
        }
    }
}

struct WakeBlockEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var rule = WakeBlockRule()

    private var boundaryChangePending: Bool {
        model.state.pending.contains {
            switch $0.action {
            case .setWakeRule, .setSleepRule: return true
            default: return false
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(tr("Enable wake-up blocking"), isOn: $rule.enabled)
                    .demoraSurface()
                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("Wake-up day begins")).font(.headline)
                    Picker(tr("Wake-up day begins"), selection: $rule.startHour) {
                        ForEach([0, 3, 6, 9], id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(tr("Sleep blocking ends at this time, even if the wake-up tap is off."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
                .demoraSurface()
                if rule.enabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("Wait after tapping Wake up"))
                            .font(.subheadline.weight(.semibold))
                        DurationPicker(minutes: $rule.waitMinutes,
                                       maxHours: 24, minMinutes: 0)
                    }
                    .demoraSurface()
                    BoundaryWeekdaysEditor(weekdays: $rule.weekdays)
                    BoundaryScopeEditor(scope: $rule.scope)
                }
                if rule != model.state.wakeRule {
                    if boundaryChangePending {
                        Text(tr("Wait for the pending wake/sleep change before editing another."))
                            .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    if model.state.sleepRule.enabled
                        && model.state.sleepRule.startMinutes == rule.startHour * 60 {
                        Text(tr("Wake-up time must differ from when sleep begins."))
                            .font(.footnote).foregroundStyle(Ink.danger)
                    }
                    let (direction, delay) = model.preview(.setWakeRule(rule))
                    Label(String(format: tr("%@ — takes effect in %@"),
                                 direction.label, delay.shortDelayLabel),
                          systemImage: "clock")
                        .font(.footnote).foregroundStyle(Ink.faint)
                    Button(tr("Queue change")) {
                        if model.queue(.setWakeRule(rule)) != nil { dismiss() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(boundaryChangePending || !rule.isValid(in: model.state)
                              || (model.state.sleepRule.enabled
                                  && model.state.sleepRule.startMinutes
                                     == rule.startHour * 60))
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Wake up"))
        .onAppear { rule = model.state.wakeRule }
    }
}

struct SleepBlockEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var rule = SleepBlockRule()

    private var boundaryChangePending: Bool {
        model.state.pending.contains {
            switch $0.action {
            case .setWakeRule, .setSleepRule: return true
            default: return false
            }
        }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(tr("Enable sleep blocking"), isOn: $rule.enabled)
                    .demoraSurface()
                if rule.enabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("Sleep begins")).font(.headline)
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
                        Text(String(format: tr("Ends at %02d:00, when the wake-up day begins."),
                                    model.state.wakeRule.startHour))
                            .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    .demoraSurface()
                    BoundaryWeekdaysEditor(weekdays: $rule.weekdays)
                    BoundaryScopeEditor(scope: $rule.scope)
                }
                if rule != model.state.sleepRule {
                    if boundaryChangePending {
                        Text(tr("Wait for the pending wake/sleep change before editing another."))
                            .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    let (direction, delay) = model.preview(.setSleepRule(rule))
                    Label(String(format: tr("%@ — takes effect in %@"),
                                 direction.label, delay.shortDelayLabel),
                          systemImage: "clock")
                        .font(.footnote).foregroundStyle(Ink.faint)
                    Button(tr("Queue change")) {
                        if model.queue(.setSleepRule(rule)) != nil { dismiss() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(boundaryChangePending
                              || !rule.isValid(in: model.state,
                                            wakeHour: model.state.wakeRule.startHour))
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Sleep"))
        .onAppear { rule = model.state.sleepRule }
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

struct LimitEditorView: View {
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

                if let existing {
                    delayHint(.configureLimit(draftLimit))
                    Section {
                        Button(tr("Remove this limit"), role: .destructive) {
                            model.queue(.removeLimit(id: existing.id))
                            dismiss()
                        }
                        .tutorialHighlight(model.tutorial == .removeLimit
                                           && model.tutorialScreen == "limitEditor")
                        delayHintText(.removeLimit(id: existing.id))
                    }
                    .demoraSurface()
                } else {
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
                        if existing != nil {
                            model.queue(.configureLimit(draftLimit))
                        } else {
                            model.queue(.addLimit(draftLimit))
                        }
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showPicker) {
                AppPickerSheet(selection: $selection)
            }
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
