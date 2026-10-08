import Foundation
import FamilyControls

/// Deterministic schedule composition, independent of persistence/Apple XPC.
/// Daily usage forms the baseline. Only explicit free/unblock rules lift it;
/// an allowlist is never a fresh daily allowance.
struct ScheduleShieldPlan {
    var blocked = FamilyActivitySelection()
    var allowed: FamilyActivitySelection? = nil
    var freed = FamilyActivitySelection()
    // Each category cohort has its own explicit app/site exceptions. A later
    // category block resets only that category, never an unrelated category.
    private(set) var categoryShields: [FamilyActivitySelection] = []

    init(blocked: FamilyActivitySelection = FamilyActivitySelection()) {
        self.blocked = blocked
        if !blocked.categoryTokens.isEmpty {
            var categories = FamilyActivitySelection()
            categories.categoryTokens = blocked.categoryTokens
            categoryShields = [categories]
        }
    }

    private mutating func mergeCategoryShields() {
        var merged: [FamilyActivitySelection] = []
        for cohort in categoryShields where !cohort.categoryTokens.isEmpty {
            if let index = merged.firstIndex(where: {
                $0.applicationTokens == cohort.applicationTokens && $0.webDomainTokens == cohort.webDomainTokens
            }) {
                merged[index].categoryTokens.formUnion(cohort.categoryTokens)
            } else { merged.append(cohort) }
        }
        categoryShields = merged
    }

    mutating func apply(_ entry: SchedulePrecedence.Entry) {
        let selection = entry.selection
        switch entry.kind {
        case .blockSelected:
            blocked.applicationTokens.formUnion(selection.applicationTokens)
            blocked.categoryTokens.formUnion(selection.categoryTokens)
            blocked.webDomainTokens.formUnion(selection.webDomainTokens)
            freed.applicationTokens.subtract(selection.applicationTokens)
            freed.webDomainTokens.subtract(selection.webDomainTokens)
            for index in categoryShields.indices {
                categoryShields[index].applicationTokens.subtract(selection.applicationTokens)
                categoryShields[index].webDomainTokens.subtract(selection.webDomainTokens)
                categoryShields[index].categoryTokens.subtract(selection.categoryTokens)
            }
            if !selection.categoryTokens.isEmpty {
                var categories = FamilyActivitySelection()
                categories.categoryTokens = selection.categoryTokens
                categoryShields.append(categories)
            }
            mergeCategoryShields()
        case .blockAllExcept:
            if entry.layer == .boundary, var existing = allowed {
                // Independent wake/sleep groups remain restrictive together.
                existing.applicationTokens.formIntersection(selection.applicationTokens)
                existing.webDomainTokens.formIntersection(selection.webDomainTokens)
                allowed = existing
            } else {
                allowed = selection
            }
        case .unblock:
            blocked.applicationTokens.subtract(selection.applicationTokens)
            blocked.categoryTokens.subtract(selection.categoryTokens)
            blocked.webDomainTokens.subtract(selection.webDomainTokens)
            freed.applicationTokens.formUnion(selection.applicationTokens)
            freed.webDomainTokens.formUnion(selection.webDomainTokens)
            for index in categoryShields.indices {
                categoryShields[index].categoryTokens.subtract(selection.categoryTokens)
                categoryShields[index].applicationTokens.formUnion(selection.applicationTokens)
                categoryShields[index].webDomainTokens.formUnion(selection.webDomainTokens)
            }
            mergeCategoryShields()
            if allowed != nil {
                allowed!.applicationTokens.formUnion(selection.applicationTokens)
                allowed!.webDomainTokens.formUnion(selection.webDomainTokens)
            }
        case .free:
            blocked = FamilyActivitySelection()
            allowed = nil
            freed = FamilyActivitySelection()
            categoryShields = []
        }
    }

    static func build(state: LatchState, baseline: FamilyActivitySelection, at date: Date,
                      globalWakeActive: Bool,
                      limitWakeActive: (AppLimit) -> Bool,
                      groupWakeActive: (DayNightGroup) -> Bool) -> ScheduleShieldPlan {
        // Enforce actual local-clock predicates, not inspector intervals. A
        // repeated DST hour can be active in both occurrences of the hour.
        var entries: [SchedulePrecedence.Entry] = []
        let ranks = SchedulePrecedence.recurringRanks(state: state)
        func active(_ key: String, _ name: String, _ layer: SchedulePrecedence.Layer,
                    _ kind: SchedulePrecedence.Kind, _ selection: FamilyActivitySelection, _ order: Int) {
            entries.append(.init(key: key, name: name, layer: layer, start: date,
                end: date.addingTimeInterval(1), kind: kind, selection: selection, tieOrder: order))
        }
        for rule in state.schedules where rule.isActive(at: date) {
            let key = "schedule-\(rule.id.uuidString)"
            active(key, rule.name, .recurring, rule.mode == .blockAllExcept ? .blockAllExcept : .blockSelected,
                   rule.selection, ranks[key] ?? 0)
        }
        for rule in state.exemptions where rule.isActive(at: date) {
            let key = "exemption-\(rule.id.uuidString)"
            active(key, rule.name, .recurring, .free, FamilyActivitySelection(), ranks[key] ?? 0)
        }
        for (index, rule) in state.planned.enumerated() where date >= rule.startsAt && date < rule.endsAt {
            let kind: SchedulePrecedence.Kind = rule.kind == .free ? .free
                : (rule.kind == .blockAllExcept ? .blockAllExcept : .blockSelected)
            active("planned-\(rule.id.uuidString)", rule.name, .planned, kind, rule.selection, index)
        }
        for (index, rule) in state.sessions.enumerated() where date >= rule.startedAt && date < rule.endsAt {
            let kind: SchedulePrecedence.Kind = rule.kind == .free ? .free : (rule.kind == .block ? .blockSelected : .unblock)
            active("session-\(rule.id.uuidString)", rule.name, .session, kind, rule.selection, index)
        }
        // Real persisted statuses, not the inspector's conservative wake windows,
        // decide enforcement. An edited start cannot discard an existing wait.
        func boundary(_ key: String, _ name: String, _ kind: SchedulePrecedence.Kind,
                      _ selection: FamilyActivitySelection, _ order: Int) {
            entries.append(.init(key: key, name: name, layer: .boundary,
                start: date, end: date.addingTimeInterval(1), kind: kind,
                selection: selection, tieOrder: order))
        }
        if globalWakeActive {
            let scope = SchedulePrecedence.boundaryScope(state.wakeRule.scope, limits: state.limits)
            boundary("global-wake", "Wake up", scope.kind, scope.selection, 0)
        }
        if state.sleepRule.enabled, windowActive(at: date, start: state.sleepRule.startMinutes,
            end: state.wakeRule.startHour * 60, recurrence: .weekly(state.sleepRule.weekdays)) {
            let scope = SchedulePrecedence.boundaryScope(state.sleepRule.scope, limits: state.limits)
            boundary("global-sleep", "Sleep", scope.kind, scope.selection, 1)
        }
        for (index, limit) in state.limits.enumerated() where limitWakeActive(limit) {
            boundary("limit-wake-\(limit.id.uuidString)", limit.name, .blockSelected,
                     limit.selection, index + 2)
        }
        for (index, group) in state.dayNightGroups.enumerated() {
            let kind: SchedulePrecedence.Kind = group.scope.mode == .allOtherApps ? .blockAllExcept : .blockSelected
            if groupWakeActive(group) {
                boundary("day-night-\(group.id.uuidString)", group.name, kind,
                    SchedulePrecedence.dayNightSelection(group, wake: true, state: state), state.limits.count + index + 2)
            }
            if group.sleepIsActive(at: date) {
                boundary("day-night-\(group.id.uuidString)", group.name, kind,
                    SchedulePrecedence.dayNightSelection(group, wake: false, state: state), state.limits.count + index + 2)
            }
        }
        var result = ScheduleShieldPlan(blocked: baseline)
        for entry in SchedulePrecedence.ordered(entries: entries, prioritizedKeys: state.prioritizedScheduleKeys) {
            result.apply(entry)
        }
        return result
    }
}
