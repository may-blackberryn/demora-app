//
//  LimitsView.swift
//  Shared limit pieces: the legacy wake/sleep editors, duration wheels,
//  selected-apps list and app picker. Rules owns the top-level screen.
//

import SwiftUI
import FamilyControls
import ManagedSettings

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
