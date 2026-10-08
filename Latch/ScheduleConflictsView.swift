import SwiftUI

private func localizedScheduleName(_ key: String, state: LatchState) -> String {
    let name = SchedulePrecedence.displayName(key: key, state: state) ?? tr("Schedule")
    return key == "global-wake" || key == "global-sleep" ? tr(name) : name
}

struct ScheduleConflictsView: View {
    @EnvironmentObject private var model: AppModel
    private var entries: [SchedulePrecedence.Entry] {
        let now = Date()
        return SchedulePrecedence.entries(state: model.state, from: now,
            through: Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now)
    }
    private var conflicts: [SchedulePrecedence.Overlap] {
        SchedulePrecedence.conflicts(entries: entries, prioritizedKeys: model.state.prioritizedScheduleKeys)
    }
    private var keys: [String] {
        SchedulePrecedence.configuredKeys(state: model.state).sorted {
            let a = SchedulePrecedence.displayName(key: $0, state: model.state) ?? $0
            let b = SchedulePrecedence.displayName(key: $1, state: model.state) ?? $1
            return a == b ? $0 < $1 : a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DemoraPageTitle(title: tr("Schedule conflicts"))
                Text(tr("Default order: wake-up → recurring → planned → sessions."))
                    .font(.subheadline).foregroundStyle(Ink.faint)
                Text(tr("Priority changes follow your less-strict delay."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                Text(tr("When several rules are prioritized, the last one promoted is applied last."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                DemoraSectionTitle(title: tr("Potential overlaps"), symbol: "arrow.triangle.branch")
                Text(tr("These rules overlap in time. Apple hides category membership, so some app overlaps cannot be confirmed."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                Text(tr("Wake-up overlaps are estimates until you tap Wake up. Allowlisted apps still obey other specific blocks and daily limits."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                let found = conflicts
                if found.isEmpty {
                    Text(tr("No conflicting schedules found."))
                        .foregroundStyle(Ink.faint)
                } else {
                    // A week of repeating windows can have many overlaps. Show
                    // a bounded list; the full calendar remains in Calendar.
                    ForEach(Array(found.prefix(40).enumerated()), id: \.offset) { _, overlap in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(localizedScheduleName(overlap.lowerPriority.key, state: model.state)
                                 + " · " + localizedScheduleName(overlap.higherPriority.key, state: model.state))
                                .font(.system(.title3, design: .serif))
                            Text(overlap.start.formatted(date: .abbreviated, time: .shortened)
                                 + " → " + overlap.end.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.monospaced()).foregroundStyle(Ink.faint)
                            Text(tr("Applies last") + ": " + localizedScheduleName(overlap.higherPriority.key, state: model.state))
                                .font(.subheadline)
                            if overlap.scope == .possibleOverlap || overlap.isConservativeWakeWindow {
                                Label(tr("Possible overlap"), systemImage: "questionmark.circle")
                                    .font(.caption).foregroundStyle(Ink.faint)
                            }
                            HStack {
                                priorityLink(overlap.lowerPriority.key)
                                Spacer()
                                priorityLink(overlap.higherPriority.key)
                            }
                        }
                        .padding(.vertical, 16)
                        Divider()
                    }
                }
                DemoraSectionTitle(title: tr("Priority"), symbol: "list.number")
                ForEach(keys, id: \.self) { key in
                    NavigationLink {
                        SchedulePriorityEditor(key: key)
                    } label: {
                        GridCard(symbol: model.state.prioritizedScheduleKeys.contains(key) ? "arrow.up" : "line.3.horizontal",
                            title: localizedScheduleName(key, state: model.state),
                            subtitle: model.state.prioritizedScheduleKeys.contains(key) ? tr("Prioritized") : tr("Default priority"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(26).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .paper().casedNavigationTitle(tr("Schedule conflicts"))
    }

    private func priorityLink(_ key: String) -> some View {
        NavigationLink { SchedulePriorityEditor(key: key) } label: {
            Text(localizedScheduleName(key, state: model.state)).font(.caption.weight(.semibold)).lineLimit(2)
        }
    }
}

private struct SchedulePriorityEditor: View {
    let key: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private var prioritized: Bool { model.state.prioritizedScheduleKeys.contains(key) }
    private var action: ChangeAction { .setSchedulePriority(key: key, prioritized: !prioritized) }
    private var pending: Bool { model.state.pending.contains { ChangeEngine.conflictKey($0.action) == "schedulePriority" } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DemoraPageTitle(title: localizedScheduleName(key, state: model.state))
                Text(tr("Default order: wake-up → recurring → planned → sessions."))
                    .foregroundStyle(Ink.faint)
                Text(tr("When several rules are prioritized, the last one promoted is applied last."))
                    .font(.footnote).foregroundStyle(Ink.faint)
                let (_, delay) = model.preview(action)
                Text(String(format: tr("%@ — takes effect in %@"), tr("Less strict"), delay.shortDelayLabel))
                    .font(.subheadline).foregroundStyle(Ink.faint)
                if pending {
                    Text(tr("A change for this setting is already pending. Cancel it on the Home tab first if you want something different."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                }
                Button(tr(prioritized ? "Restore default priority" : "Prioritize this")) {
                    if model.queue(action) != nil { dismiss() }
                }
                .buttonStyle(DemoraPrimaryButtonStyle())
                .disabled(pending || !SchedulePrecedence.configuredKeys(state: model.state).contains(key))
            }
            .padding(26).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .paper().casedNavigationTitle(tr("Priority"))
    }
}
