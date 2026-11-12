import SwiftUI

private func localizedScheduleName(_ key: String, state: LatchState) -> String {
    let name = SchedulePrecedence.displayName(key: key, state: state) ?? tr("Schedule")
    return key == "global-wake" || key == "global-sleep" ? tr(name) : name
}

/// A When & where rule's own window: it changes only with its rule, so it has
/// no priority of its own here (a promotion would be lost when the rule's
/// times change, because the window's ID changes with them).
private func isRuleOwned(_ key: String, state: LatchState) -> Bool {
    state.schedules.contains { $0.ownerRuleID != nil && "schedule-\($0.id.uuidString)" == key }
}

struct ScheduleConflictsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showHelp = false
    private var entries: [SchedulePrecedence.Entry] {
        let now = Date()
        return SchedulePrecedence.entries(state: model.state, from: now,
            through: Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now)
    }
    private var conflicts: [SchedulePrecedence.Overlap] {
        SchedulePrecedence.conflicts(entries: entries, prioritizedKeys: model.state.prioritizedScheduleKeys)
    }
    private var keys: [String] {
        SchedulePrecedence.configuredKeys(state: model.state)
            .filter { !isRuleOwned($0, state: model.state) }.sorted {
            let a = SchedulePrecedence.displayName(key: $0, state: model.state) ?? $0
            let b = SchedulePrecedence.displayName(key: $1, state: model.state) ?? $1
            return a == b ? $0 < $1 : a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                VStack(alignment: .leading, spacing: DemoraSpace.xs) {
                    Text(tr("Conflicts"))
                        .demoraType(.pageTitle)
                        .foregroundStyle(Ink.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(tr("Rules that overlap in the next 7 days."))
                        .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                }
                let found = conflicts
                VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
                    if found.isEmpty {
                        EmptyStateView(title: tr("No conflicting schedules found."),
                                       systemImage: "checkmark.circle",
                                       description: tr("Default order: wake-up → recurring → planned → sessions."))
                    }
                    // A week of repeating windows can have many overlaps. Show
                    // a bounded list; the full calendar remains in Calendar.
                    ForEach(Array(found.prefix(40).enumerated()), id: \.offset) { _, overlap in
                        overlapCard(overlap)
                    }
                }
                VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
                    SectionHeader(tr("Priority"))
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(keys, id: \.self) { key in
                            NavigationLink {
                                SchedulePriorityEditor(key: key)
                            } label: {
                                HStack {
                                    Text(localizedScheduleName(key, state: model.state))
                                        .demoraType(.body).foregroundStyle(Ink.ink)
                                    Spacer(minLength: DemoraSpace.xs)
                                    Text(model.state.prioritizedScheduleKeys.contains(key)
                                         ? tr("Prioritized") : tr("Default priority"))
                                        .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold)).foregroundStyle(Ink.inkSoft)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .paperCard()
                }
            }
            .padding(.horizontal, DemoraSpace.pageGutter)
            .padding(.vertical, DemoraSpace.l)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Schedule conflicts"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
                    .accessibilityLabel(tr("Help"))
            }
        }
        .sheet(isPresented: $showHelp) {
            EditorHelpSheet(title: tr("Conflicts"), paragraphs: [
                tr("Default order: wake-up → recurring → planned → sessions."),
                tr("Priority changes follow your less-strict delay."),
                tr("When several rules are prioritized, the last one promoted is applied last."),
                tr("These rules overlap in time. Apple hides category membership, so some app overlaps cannot be confirmed."),
                tr("Wake-up overlaps are estimates until you tap Wake up. Allowlisted apps still obey other specific blocks and daily limits."),
            ])
        }
    }

    private func overlapCard(_ overlap: SchedulePrecedence.Overlap) -> some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(localizedScheduleName(overlap.lowerPriority.key, state: model.state)
                     + " · " + localizedScheduleName(overlap.higherPriority.key, state: model.state))
                    .demoraType(.cardTitle).foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DemoraSpace.xs)
                if overlap.scope == .possibleOverlap || overlap.isConservativeWakeWindow {
                    StateChip(kind: .neutral, text: tr("Possible overlap"))
                }
            }
            Text(overlap.start.formatted(date: .abbreviated, time: .shortened)
                 + " → " + overlap.end.formatted(date: .abbreviated, time: .shortened))
                .font(.system(.subheadline, design: .serif).monospacedDigit())
                .foregroundStyle(Ink.inkSoft)
            Text(tr("Applies last") + ": " + localizedScheduleName(overlap.higherPriority.key, state: model.state))
                .demoraType(.meta).foregroundStyle(Ink.ink)
            HStack {
                priorityLink(overlap.lowerPriority.key)
                Spacer()
                priorityLink(overlap.higherPriority.key)
            }
        }
        .paperCard()
    }

    @ViewBuilder private func priorityLink(_ key: String) -> some View {
        if isRuleOwned(key, state: model.state) {
            Text(localizedScheduleName(key, state: model.state))
                .demoraType(.meta).lineLimit(2)
                .foregroundStyle(Ink.inkSoft)
                .frame(minHeight: 44)
        } else {
            NavigationLink { SchedulePriorityEditor(key: key) } label: {
                Text(localizedScheduleName(key, state: model.state))
                    .demoraType(.meta).lineLimit(2)
                    .frame(minHeight: 44)
            }
        }
    }
}

private struct SchedulePriorityEditor: View {
    let key: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var receipt: ChangeReceiptRequest?
    private var prioritized: Bool { model.state.prioritizedScheduleKeys.contains(key) }
    private var action: ChangeAction { .setSchedulePriority(key: key, prioritized: !prioritized) }
    private var pending: Bool { model.state.pending.contains { ChangeEngine.conflictKey($0.action) == "schedulePriority" } }
    var body: some View {
        RuleEditorPage(title: localizedScheduleName(key, state: model.state), presentation: .pushed,
                       canReview: !pending && SchedulePrecedence.configuredKeys(state: model.state).contains(key)
                           && !isRuleOwned(key, state: model.state),
                       waiting: pending,
                       reviewTitle: tr(prioritized ? "Restore default priority" : "Prioritize this"),
                       onReview: { receipt = ChangeReceiptRequest(action: action) }) {
            EditorSection(tr("Priority")) {
                FactRow(label: tr("Priority"), value: prioritized ? tr("Prioritized") : tr("Default priority"))
                EditorNote(text: tr("Default order: wake-up → recurring → planned → sessions."))
            }
        }
        .changeReceipt($receipt) { dismiss() }
    }
}
