//
//  LimitsView.swift
//  Active app limits. Adding, editing, and removing all go through
//  the change engine (and therefore through a delay).
//

import SwiftUI
import FamilyControls
import ManagedSettings

struct LimitsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @State private var showAdd = false
    @State private var editTarget: AppLimit?
    // Soft refresh: bumping this date changes the report's filter, which
    // re-runs the extension's query in place — no process teardown, so it
    // can't trip the system's extension-launch throttle. Used for foreground
    // returns and appearance changes.
    @State private var reportRefreshedAt = Date()
    // Hard rebuild (kills + respawns the extension) — reserved for the manual
    // reload button and the one-time cold-start warm-up. Rapid rebuilds are
    // what made the report render blank.
    @State private var reportID = 0
    @State private var reportAppearance: String?
    @State private var didWarmReport = false
    // When false, the report view is removed entirely for a beat so the next
    // render builds a brand-new DeviceActivityReport (and re-runs the extension)
    // instead of reusing a stale one.
    @State private var showReport = true
    // Coalesces overlapping hard rebuilds — tearing down an extension that a
    // previous rebuild just spawned is exactly what caused the flakiness.
    @State private var reloadInFlight = false
    // Dismissible informational notes. Once dismissed they stay hidden here but
    // remain available under Help → Limitations.
    @AppStorage("limits.usageNoteDismissed") private var usageNoteDismissed = false
    @AppStorage("limits.countingNoteDismissed") private var countingNoteDismissed = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if model.enforcementDegraded {
                    Section { EnforcementBanner() }
                }
                if #unavailable(iOS 17.4) {
                    if !countingNoteDismissed {
                        Section {
                            DismissibleNote(
                                text: tr("Heads up: on your iOS version, a limit only counts screen time from the moment you add it — time you already spent earlier today isn't included. Update to iOS 17.4 or later for exact daily counting."),
                                onDismiss: { countingNoteDismissed = true })
                        }
                    }
                }
                if !model.state.limits.isEmpty {
                    Section {
                        if showReport {
                            LimitsUsageReportView(refreshedAt: reportRefreshedAt)
                                .id(reportID)
                                .frame(minHeight: CGFloat(model.state.limits.count) * 66 + 12)
                                .listRowInsets(EdgeInsets())
                        } else {
                            HStack { Spacer(); ProgressView(); Spacer() }
                                .frame(minHeight: CGFloat(model.state.limits.count) * 66 + 12)
                        }
                    } header: {
                        HStack {
                            Text(tr("Today's usage"))
                            Spacer()
                            Button { reloadReport() } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.plain).foregroundStyle(.tint)
                        }
                    } footer: {
                        if !usageNoteDismissed {
                            DismissibleNote(
                                text: tr("Today's usage is reported by iOS Screen Time, which can be slow to load or briefly show nothing. If it looks empty, tap the refresh arrow a couple of times."),
                                onDismiss: { usageNoteDismissed = true })
                        }
                    }
                }
                Section {
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
                        Button { editTarget = limit } label: {
                            LimitRow(limit: limit)
                        }
                        .tint(.primary)
                        .tutorialHighlight(model.tutorial == .removeLimit
                                           && model.tutorialScreen == "limits")
                    }
                } header: {
                    if !model.state.limits.isEmpty { Text(tr("Manage")) }
                }
            }
            .paper()
            .casedNavigationTitle(tr("Limits"))
            .onAppear {
                if model.inTutorial && model.selectedTab == 1 { model.tutorialScreen = "limits" }
                // Re-render the report if the appearance changed since we last
                // showed Limits — a filter bump is enough for the extension to
                // pick up the new scheme; no need to kill it.
                if let last = reportAppearance, last != appearanceRaw { refreshReport() }
                reportAppearance = appearanceRaw
                // The DeviceActivityReport often renders blank on a cold first
                // load (the extension isn't warm yet). Fully rebuild it once,
                // shortly after first appear, so it fills in without a relaunch.
                if !didWarmReport {
                    didWarmReport = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        reloadReport()
                    }
                    // The extension can take a few seconds to warm up, so a
                    // single rebuild often still lands blank. Nudge the query a
                    // couple more times as it warms — these are SOFT refreshes
                    // (filter bumps only), which never relaunch the extension and
                    // so can't trip the blank-inducing launch throttle. Saves the
                    // user from manually tapping refresh several times.
                    for delay in [1.8, 3.5] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            refreshReport()
                        }
                    }
                }
            }
            .onChange(of: scenePhase) { phase in
                // Returning to the foreground: refresh the query in place so
                // the counter isn't stale. (This also fires at launch, which is
                // why it must not tear the extension down — that used to stack
                // with the warm-up rebuild and blank the report.)
                if phase == .active { refreshReport() }
            }
            .toolbar {
                if !model.inTutorial {
                    ToolbarItem(placement: .navigationBarLeading) {
                        NavigationLink { HelpHubView() } label: {
                            Image(systemName: "questionmark.circle")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .sheet(isPresented: $showAdd) { LimitEditorView(existing: nil) }
            .sheet(item: $editTarget) { LimitEditorView(existing: $0) }
        }
    }

    /// Soft refresh: bump the filter date so the extension re-runs its query
    /// in place. Never kills the extension, so it's safe to call freely.
    private func refreshReport() {
        reportRefreshedAt = Date()
    }

    /// Hard rebuild: remove the view entirely, then re-add it with a fresh id
    /// (and fresh filter) a beat later, recreating the DeviceActivityReport and
    /// its extension from scratch. Only for the manual reload button and the
    /// one-time warm-up — overlapping calls coalesce, because tearing down an
    /// extension mid-spawn is what made the report go blank.
    private func reloadReport() {
        guard !reloadInFlight else { return }
        reloadInFlight = true
        showReport = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            reportID += 1
            reportRefreshedAt = Date()
            showReport = true
            reloadInFlight = false
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
    let limit: AppLimit

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(limit.name).font(.headline)
                Text(String(format: tr("%d apps, %d categories"),
                            limit.selection.applicationTokens.count,
                            limit.selection.categoryTokens.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(limitMinutesLabel(limit.minutesPerDay))
                .foregroundStyle(.secondary)
        }
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

struct LimitEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let existing: AppLimit?
    @State private var name = ""
    @State private var selection = FamilyActivitySelection()
    @State private var minutes = 30
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Section(tr("Name")) {
                        TextField(tr("e.g. Instagram"), text: $name)
                    }
                }
                Section(tr("Apps")) {
                    if existing == nil {
                        Button {
                            showPicker = true
                        } label: {
                            HStack {
                                Text(tr("Choose apps"))
                                Spacer()
                                Text(String(format: tr("%d selected"),
                                            selection.applicationTokens.count
                                            + selection.categoryTokens.count))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    SelectedAppsView(selection: selection)
                }
                Section {
                    DurationPicker(minutes: $minutes, maxHours: 12, minMinutes: 0)
                } header: {
                    Text(tr("Daily limit"))
                } footer: {
                    Text(minutes == 0
                         ? tr("0 minutes — this app stays blocked all day, every day.")
                         : String(format: tr("%d min/day"), minutes))
                }

                if let existing {
                    delayHint(.updateLimitMinutes(id: existing.id, minutes: minutes))
                    Section {
                        Button(tr("Remove this limit"), role: .destructive) {
                            model.queue(.removeLimit(id: existing.id))
                            dismiss()
                        }
                        .tutorialHighlight(model.tutorial == .removeLimit
                                           && model.tutorialScreen == "limitEditor")
                        delayHintText(.removeLimit(id: existing.id))
                    }
                } else {
                    delayHint(.addLimit(draftLimit))
                }
            }
            .paper()
            .casedNavigationTitle(existing == nil ? tr("New limit") : existing!.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Queue change")) {
                        if let existing {
                            model.queue(.updateLimitMinutes(id: existing.id,
                                                            minutes: minutes))
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
                }
                if model.inTutorial { model.tutorialScreen = "limitEditor" }
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

    private var draftLimit: AppLimit {
        AppLimit(name: name.isEmpty ? tr("Limit") : name,
                 selection: selection, minutesPerDay: minutes)
    }

    private var isValid: Bool {
        if let existing { return minutes != existing.minutesPerDay }
        return !name.isEmpty && !(selection.applicationTokens.isEmpty
                                  && selection.categoryTokens.isEmpty)
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
