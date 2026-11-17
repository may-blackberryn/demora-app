//
//  BlockingDiagnosticsView.swift
//  2.0.1: what Demora's background blocking is doing right now — which
//  background monitors are running and which recorded failures are behind the
//  "Background blocking may be incomplete" warning. Opened from that warning.
//
//  Read-only except "Try again", which runs the same idempotent repair the app
//  runs when it comes to the foreground. Shows activity names and error text,
//  never usage, app names or tokens.
//

import SwiftUI
import DeviceActivity

struct BlockingDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var failures: [SharedStore.EnforcementFailure] = []
    @State private var limits: [LimitRow] = []
    @State private var freeSince: Date?
    @State private var rulesUnreadable = false

    /// Demora's own enforcement state per limit (2.0.1). `blockedNow` uses the
    /// same baseline test as ShieldController.apply (spent or 0-minute day,
    /// minus running extra time, plus split/wake blocks); a free period or an
    /// unblock session can still lift it, shown separately. No usage.
    struct LimitRow: Identifiable, Sendable {
        let id: UUID
        let name: String
        let blockedNow: Bool
        let reachedAt: Date?
        let credit: Int
        let extraRunning: Bool
    }

    private struct Snapshot: Sendable {
        var monitors: [String]
        var limits: [LimitRow]
        var unreadable: Bool
    }
    @State private var monitors: [String] = []
    @State private var loaded = false
    @State private var retrying = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                    problems
                    limitsSection
                    running
                    Button {
                        retry()
                    } label: {
                        Text(tr("Try again"))
                    }
                    .buttonStyle(DemoraPrimaryButtonStyle())
                    .disabled(retrying)
                }
                .padding(.horizontal, DemoraSpace.pageGutter)
                .padding(.vertical, DemoraSpace.l)
                .frame(maxWidth: DemoraSpace.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Background blocking"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
            .task { await reload() }
        }
    }

    private var problems: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            DemoraSectionTitle(title: tr("Problems"))
            if loaded && failures.isEmpty {
                Text(tr("Everything is set up."))
                    .demoraType(.body)
                    .foregroundStyle(Ink.ink)
            }
            ForEach(failures, id: \.key) { failure in
                VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                    Text(failure.key)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Ink.ink)
                        .textSelection(.enabled)
                    Text(failure.detail)
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Text(failure.at.appFormatted(date: .abbreviated, time: .shortened))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .paperCard()
            }
        }
    }

    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            DemoraSectionTitle(title: tr("Limits"))
            if rulesUnreadable {
                Text(tr("Check this rule's settings."))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.ink)
            }
            if let freeSince {
                Text(String(format: tr("Free time running since %@"),
                            freeSince.appFormatted(date: .omitted, time: .shortened)))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.ink)
            }
            ForEach(limits) { row in
                VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                    Text(row.name)
                        .demoraType(.body)
                        .foregroundStyle(Ink.ink)
                    Text(row.blockedNow ? tr("Blocked now") : tr("Not blocked"))
                        .demoraType(.meta)
                        .foregroundStyle(row.blockedNow ? Ink.ink : Ink.inkSoft)
                    Text(row.reachedAt.map {
                        String(format: tr("Limit reached at %@"),
                               $0.appFormatted(date: .omitted, time: .shortened))
                    } ?? tr("No limit-reached signal today"))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                    if row.extraRunning {
                        Text(tr("Extra time running"))
                            .demoraType(.meta)
                            .foregroundStyle(Ink.inkSoft)
                    }
                    if row.credit > 0 {
                        Text(String(format: tr("Free-time credit: %ld min"), row.credit))
                            .demoraType(.meta)
                            .foregroundStyle(Ink.inkSoft)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            DemoraSectionTitle(title: String(format: tr("Running monitors: %d of %d"),
                                             monitors.count, MonitoringBudget.maximum))
            VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                ForEach(monitors, id: \.self) { name in
                    Text(name)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Ink.inkSoft)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .textSelection(.enabled)
        }
    }

    /// Screen Time's activity list is synchronous XPC: read it off the main
    /// actor.
    /// Screen Time's activity list and the extra-time check are synchronous
    /// XPC: read everything off the main actor.
    private func reload() async {
        let snapshot = await Task.detached(priority: .userInitiated) { () -> Snapshot in
            let names = DeviceActivityCenter().activities.map(\.rawValue).sorted()
            guard let state = SharedStore.loadStateForEnforcement() else {
                return Snapshot(monitors: names, limits: [], unreadable: true)
            }
            let now = Date()
            let spent = SharedStore.loadBlockedLimitIDs()
            let reached = SharedStore.limitThresholdCallbackTimes()
            let credit = SharedStore.loadFreeCreditByLimit()
            let extra = LimitFeatures.extraUnblockedIDs(state: state, at: now)
            let feature = LimitFeatures.blockedFeatureIDs(state: state, at: now, includeWake: false)
            let rows = state.limits.map { limit in
                let baseline = (limit.minutes(on: now) == 0 || spent.contains(limit.id))
                    && !extra.contains(limit.id)
                return LimitRow(id: limit.id, name: limit.name,
                                blockedNow: baseline || feature.contains(limit.id),
                                reachedAt: reached[limit.id], credit: credit[limit.id] ?? 0,
                                extraRunning: extra.contains(limit.id))
            }
            return Snapshot(monitors: names, limits: rows, unreadable: false)
        }.value
        failures = SharedStore.enforcementFailures
        limits = snapshot.limits
        rulesUnreadable = snapshot.unreadable
        freeSince = SharedStore.freeWindowStart
        monitors = snapshot.monitors
        loaded = true
    }

    private func retry() {
        retrying = true
        Task {
            await ChangeEngine.ensureMonitoringOffMain()
            await ChangeEngine.housekeepingOffMain()
            model.refreshEnforcementStatus()
            await reload()
            retrying = false
        }
    }
}
