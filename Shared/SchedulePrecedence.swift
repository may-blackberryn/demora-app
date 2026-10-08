import Foundation
import FamilyControls

/// Pure ordering and inspection, not shield composition. Entries are applied
/// lowest-first; the last applicable policy has highest priority. A winner in
/// an overlap finding is pairwise, not a claim that it overrides unrelated apps,
/// spent limits, or every other policy active at that time.
enum SchedulePrecedence {
    enum Layer: Int { case boundary, recurring, planned, session }
    enum Kind: String { case blockSelected, blockAllExcept, unblock, free }

    struct Entry {
        var key: String
        var name: String
        var layer: Layer
        var start: Date
        var end: Date
        var kind: Kind
        /// Selected targets, or exceptions for blockAllExcept; unused for free.
        var selection: FamilyActivitySelection
        var tieOrder: Int
        /// Inspection cannot know whether a wake tap/wait already released it.
        var isConservativeWakeWindow = false

        init(key: String, name: String, layer: Layer, start: Date, end: Date,
             kind: Kind, selection: FamilyActivitySelection, tieOrder: Int = 0,
             isConservativeWakeWindow: Bool = false) {
            self.key = key; self.name = name; self.layer = layer
            self.start = start; self.end = end; self.kind = kind
            self.selection = selection; self.tieOrder = tieOrder
            self.isConservativeWakeWindow = isConservativeWakeWindow
        }
    }

    enum ScopeOverlap: String {
        case knownOverlap
        case possibleOverlap // Opaque category/app/site membership cannot be resolved.
        case disjoint        // Only explicit, comparable token sets prove this.
    }

    struct Overlap {
        var lowerPriority: Entry
        var higherPriority: Entry
        var start: Date
        var end: Date
        var scope: ScopeOverlap
        var isPotentialConflict: Bool
        var higherPriorityIsPromoted: Bool
        var winnerKey: String? { isPotentialConflict ? higherPriority.key : nil }
        var isConservativeWakeWindow: Bool {
            lowerPriority.isConservativeWakeWindow || higherPriority.isConservativeWakeWindow
        }
        /// Presentation hint only; consumers may localize using the typed fields.
        var label: String {
            guard isPotentialConflict else { return "Time overlap" }
            let uncertainty = scope == .possibleOverlap ? " · scope uncertain" : ""
            let wake = isConservativeWakeWindow ? " · wake estimate" : ""
            let priority = higherPriorityIsPromoted ? "chosen priority" : "default order"
            return "Potential conflict: \(higherPriority.name) (\(priority))\(uncertainty)\(wake)"
        }
    }

    /// Unknown/stale priority keys are harmless. Duplicate keys use their last
    /// promotion. Equal priorities use layer, tieOrder, key and occurrence time;
    /// otherwise-identical entries retain their input order.
    static func ordered(entries: [Entry], prioritizedKeys: [String]) -> [Entry] {
        var promotions: [String: Int] = [:]
        for (index, key) in prioritizedKeys.enumerated() { promotions[key] = index }
        return entries.enumerated().sorted { left, right in
            let a = left.element, b = right.element
            let ap = promotions[a.key] ?? -1, bp = promotions[b.key] ?? -1
            if ap != bp { return ap < bp }
            if a.layer.rawValue != b.layer.rawValue { return a.layer.rawValue < b.layer.rawValue }
            if a.tieOrder != b.tieOrder { return a.tieOrder < b.tieOrder }
            if a.key != b.key { return a.key < b.key }
            if a.start != b.start { return a.start < b.start }
            if a.end != b.end { return a.end < b.end }
            if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
            if a.name != b.name { return a.name < b.name }
            return left.offset < right.offset
        }.map(\.element)
    }

    /// All half-open temporal overlaps, including same-effect/disjoint pairs.
    /// blockAllExcept is a whole-policy scope (both allow and block decisions),
    /// not merely its blocked complement. Free is global, even with no tokens.
    static func overlaps(entries: [Entry], prioritizedKeys: [String]) -> [Overlap] {
        let sorted = ordered(entries: entries, prioritizedKeys: prioritizedKeys)
        let promoted = Set(prioritizedKeys)
        var result: [Overlap] = []
        for (index, a) in sorted.enumerated() where a.start < a.end {
            for b in sorted.dropFirst(index + 1) where b.start < b.end && a.key != b.key {
                let start = max(a.start, b.start), end = min(a.end, b.end)
                guard start < end else { continue }
                let scope = scopeOverlap(a, b)
                let differs = a.kind != b.kind || (a.kind == .blockAllExcept
                    && !sameTokens(a.selection, b.selection))
                result.append(Overlap(lowerPriority: a, higherPriority: b, start: start,
                    end: end, scope: scope, isPotentialConflict: differs && scope != .disjoint,
                    higherPriorityIsPromoted: promoted.contains(b.key)))
            }
        }
        return result
    }

    static func conflicts(entries: [Entry], prioritizedKeys: [String]) -> [Overlap] {
        overlaps(entries: entries, prioritizedKeys: prioritizedKeys).filter(\.isPotentialConflict)
    }

    static func recurringRanks(state: LatchState) -> [String: Int] {
        let blocks: [(Date, String)] = state.schedules.map { ($0.addedAt, "schedule-\($0.id.uuidString)") }
        let exemptions: [(Date, String)] = state.exemptions.map { ($0.addedAt, "exemption-\($0.id.uuidString)") }
        let recurring = (blocks + exemptions).sorted {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            return $0.1 < $1.1
        }
        var ranks: [String: Int] = [:]
        for (index, item) in recurring.enumerated() { ranks[item.1] = index }
        return ranks
    }

    /// Configured rules independent of the inspection horizon (e.g. monthly
    /// windows absent this week). Disabled wake/sleep gates have no active key.
    static func configuredKeys(state: LatchState) -> Set<String> {
        var keys = Set(state.schedules.map { "schedule-\($0.id.uuidString)" })
        keys.formUnion(state.exemptions.map { "exemption-\($0.id.uuidString)" })
        keys.formUnion(state.planned.map { "planned-\($0.id.uuidString)" })
        keys.formUnion(state.sessions.map { "session-\($0.id.uuidString)" })
        keys.formUnion(state.dayNightGroups.filter { $0.wakeEnabled || $0.sleepEnabled }
            .map { "day-night-\($0.id.uuidString)" })
        keys.formUnion(state.limits.filter { $0.wakeDelayMinutes != nil }.map { "limit-wake-\($0.id.uuidString)" })
        if state.wakeRule.enabled { keys.insert("global-wake") }
        if state.sleepRule.enabled { keys.insert("global-sleep") }
        return keys
    }

    /// User names are verbatim; global names are English localization keys.
    /// Localizing here would read persisted language preferences via tr().
    static func displayName(key: String, state: LatchState) -> String? {
        guard configuredKeys(state: state).contains(key) else { return nil }
        if key == "global-wake" { return "Wake up" }
        if key == "global-sleep" { return "Sleep" }
        if let group = state.dayNightGroups.first(where: { "day-night-\($0.id.uuidString)" == key }) { return group.name }
        if let limit = state.limits.first(where: { "limit-wake-\($0.id.uuidString)" == key }) { return limit.name }
        if let rule = state.schedules.first(where: { "schedule-\($0.id.uuidString)" == key }) { return rule.name }
        if let rule = state.exemptions.first(where: { "exemption-\($0.id.uuidString)" == key }) { return rule.name }
        if let rule = state.planned.first(where: { "planned-\($0.id.uuidString)" == key }) { return rule.name }
        return state.sessions.first(where: { "session-\($0.id.uuidString)" == key })?.name
    }

    /// Read-only projection of configured windows, bounded to seven calendar
    /// days. Actual recurrence/window helpers are authoritative. No Date(),
    /// TimeGuard, runtime tap state, persistence, pending changes or network I/O.
    /// Wake is conservatively start-to-cutoff (nil: midnight), NOT start+wait.
    static func entries(state: LatchState, from: Date, through: Date) -> [Entry] {
        let calendar = Calendar.current
        guard from < through,
              let ceiling = calendar.date(byAdding: .day, value: 7, to: from),
              let first = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: from))
        else { return [] }
        let horizon = min(through, ceiling)
        var result: [Entry] = []
        func add(_ key: String, _ name: String, _ layer: Layer, _ start: Date,
                 _ end: Date, _ kind: Kind, _ selection: FamilyActivitySelection,
                 _ tie: Int, conservativeWake: Bool = false) {
            guard start < end, start < horizon, end > from else { return }
            result.append(Entry(key: key, name: name, layer: layer, start: start,
                end: end, kind: kind, selection: selection, tieOrder: tie,
                isConservativeWakeWindow: conservativeWake))
        }
        func clock(_ day: Date, _ minutes: Int) -> Date? {
            guard (0..<1440).contains(minutes) else { return nil }
            return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                 second: 0, of: day)
        }
        // Same ranking as runtime, across blocks AND exemptions.
        let ranks = recurringRanks(state: state)
        var day = first
        while day < horizon {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            func window(_ key: String, _ name: String, _ startMinute: Int, _ endMinute: Int,
                        _ recurrence: Recurrence, _ kind: Kind, _ selection: FamilyActivitySelection,
                        layer: Layer = .recurring, tie: Int = 0) {
                guard startMinute != endMinute, recurrence.matches(dayOf: day),
                      let start = clock(day, startMinute),
                      let end = clock(startMinute < endMinute ? day : next, endMinute),
                      windowActive(at: start, start: startMinute, end: endMinute, recurrence: recurrence)
                else { return }
                add(key, name, layer, start, end, kind, selection, ranks[key] ?? tie)
            }
            func wake(_ key: String, _ name: String, _ timing: WakeDayTiming,
                      _ weekdays: Set<Int>, _ kind: Kind, _ selection: FamilyActivitySelection, _ tie: Int) {
                guard weekdays.contains(calendar.component(.weekday, from: day)),
                      timing.isValid,
                      let start = clock(day, timing.startMinutes) else { return }
                let end = timing.latestMinutes.flatMap { clock(day, $0) } ?? next
                add(key, name, .boundary, start, end, kind, selection, tie, conservativeWake: true)
            }
            for schedule in state.schedules {
                window("schedule-\(schedule.id.uuidString)", schedule.name, schedule.startMinutes,
                    schedule.endMinutes, schedule.recurrence,
                    schedule.mode == .blockAllExcept ? .blockAllExcept : .blockSelected, schedule.selection)
            }
            for exemption in state.exemptions {
                window("exemption-\(exemption.id.uuidString)", exemption.name, exemption.startMinutes,
                    exemption.endMinutes, exemption.recurrence, .free, FamilyActivitySelection())
            }
            if state.wakeRule.enabled {
                let rule = state.wakeRule
                let scope = boundaryScope(rule.scope, limits: state.limits)
                wake("global-wake", "Wake up", WakeDayTiming(startMinutes: rule.startHour * 60,
                    waitMinutes: rule.waitMinutes, latestMinutes: rule.latest(on: day)), rule.weekdays,
                    scope.kind, scope.selection, 0)
            }
            if state.sleepRule.enabled {
                let rule = state.sleepRule, scope = boundaryScope(state.sleepRule.scope, limits: state.limits)
                window("global-sleep", "Sleep", rule.startMinutes, state.wakeRule.startHour * 60,
                    .weekly(rule.weekdays), scope.kind, scope.selection, layer: .boundary, tie: 1)
            }
            for (index, limit) in state.limits.enumerated() {
                guard let wait = limit.wakeDelayMinutes else { continue }
                let schedule = limit.wakeSchedule ?? LimitWakeSchedule()
                wake("limit-wake-\(limit.id.uuidString)", limit.name,
                    schedule.timing(on: day, defaultWait: wait), schedule.weekdays,
                    .blockSelected, limit.selection, index + 2)
            }
            for (index, group) in state.dayNightGroups.enumerated() {
                let key = "day-night-\(group.id.uuidString)", tie = state.limits.count + index + 2
                let kind: Kind = group.scope.mode == .allOtherApps ? .blockAllExcept : .blockSelected
                if group.wakeEnabled {
                    wake(key, group.name, group.wakeTiming(on: day), group.weekdays, kind,
                         dayNightSelection(group, wake: true, state: state), tie)
                }
                if group.sleepEnabled, group.weekdays.contains(calendar.component(.weekday, from: day)),
                   let start = clock(day, group.sleepStartMinutes), group.sleepIsActive(at: start) {
                    let endDay = group.wakeTiming(on: day).startMinutes > group.sleepStartMinutes ? day : next
                    if let end = clock(endDay, group.wakeTiming(on: endDay).startMinutes) {
                        add(key, group.name, .boundary, start, end, kind,
                            dayNightSelection(group, wake: false, state: state), tie)
                    }
                }
            }
            day = next
        }
        for (index, planned) in state.planned.enumerated() {
            let kind: Kind
            switch planned.kind {
            case .blockSelected: kind = .blockSelected
            case .blockAllExcept: kind = .blockAllExcept
            case .free: kind = .free
            }
            add("planned-\(planned.id.uuidString)", planned.name, .planned, planned.startsAt,
                planned.endsAt, kind, planned.selection, index)
        }
        for (index, session) in state.sessions.enumerated() {
            let kind: Kind
            switch session.kind {
            case .block: kind = .blockSelected
            case .unblock: kind = .unblock
            case .free: kind = .free
            }
            add("session-\(session.id.uuidString)", session.name, .session, session.startedAt,
                session.endsAt, kind, session.selection, index)
        }
        return ordered(entries: result, prioritizedKeys: state.prioritizedScheduleKeys)
    }

    static func dayNightSelection(_ group: DayNightGroup, wake: Bool,
                                  state: LatchState) -> FamilyActivitySelection {
        var selection = group.scope.resolved(limits: state.limits)
        if group.scope.mode == .allOtherApps {
            // Same boundary-specific automatic exceptions as DayNightPolicy.
            for other in state.dayNightGroups where other.scope.mode == .selected
                && (wake ? other.wakeEnabled : other.sleepEnabled) {
                let explicit = other.scope.resolved(limits: state.limits)
                selection.applicationTokens.formUnion(explicit.applicationTokens)
                selection.webDomainTokens.formUnion(explicit.webDomainTokens)
            }
            // Valid fallback configurations contain no category exceptions.
            // Do not fabricate category membership from opaque tokens.
            selection.categoryTokens = []
        }
        return selection
    }

    static func boundaryScope(_ scope: BoundaryBlockScope, limits: [AppLimit])
        -> (kind: Kind, selection: FamilyActivitySelection) {
        var selection = scope.mode == .blockGroups ? FamilyActivitySelection() : scope.selection
        for limit in limits {
            if scope.mode == .blockGroups {
                if scope.groupIDs.contains(limit.id) && !scope.excludedLimitIDs.contains(limit.id) {
                    selection.applicationTokens.formUnion(limit.selection.applicationTokens)
                    selection.categoryTokens.formUnion(limit.selection.categoryTokens)
                    selection.webDomainTokens.formUnion(limit.selection.webDomainTokens)
                }
            } else if scope.excludedLimitIDs.contains(limit.id) {
                if scope.mode == .blockAllExcept {
                    selection.applicationTokens.formUnion(limit.selection.applicationTokens)
                    selection.webDomainTokens.formUnion(limit.selection.webDomainTokens)
                } else {
                    selection.applicationTokens.subtract(limit.selection.applicationTokens)
                    selection.categoryTokens.subtract(limit.selection.categoryTokens)
                    selection.webDomainTokens.subtract(limit.selection.webDomainTokens)
                }
            }
        }
        return (scope.mode == .blockAllExcept ? .blockAllExcept : .blockSelected, selection)
    }

    private static func sameTokens(_ a: FamilyActivitySelection, _ b: FamilyActivitySelection) -> Bool {
        a.applicationTokens == b.applicationTokens && a.categoryTokens == b.categoryTokens
            && a.webDomainTokens == b.webDomainTokens
    }

    private static func scopeOverlap(_ a: Entry, _ b: Entry) -> ScopeOverlap {
        func global(_ entry: Entry) -> Bool { entry.kind == .free || entry.kind == .blockAllExcept }
        func empty(_ s: FamilyActivitySelection) -> Bool {
            s.applicationTokens.isEmpty && s.categoryTokens.isEmpty && s.webDomainTokens.isEmpty
        }
        if (!global(a) && empty(a.selection)) || (!global(b) && empty(b.selection)) { return .disjoint }
        if global(a) || global(b) { return .knownOverlap }
        let x = a.selection, y = b.selection
        if !x.applicationTokens.isDisjoint(with: y.applicationTokens)
            || !x.categoryTokens.isDisjoint(with: y.categoryTokens)
            || !x.webDomainTokens.isDisjoint(with: y.webDomainTokens) { return .knownOverlap }
        if !x.categoryTokens.isEmpty || !y.categoryTokens.isEmpty { return .possibleOverlap }
        // An app and a website may describe the same usage; tokens do not tell
        // us which app visits a website (including embedded browser views).
        if (!x.applicationTokens.isEmpty && !y.webDomainTokens.isEmpty)
            || (!y.applicationTokens.isEmpty && !x.webDomainTokens.isEmpty) { return .possibleOverlap }
        return .disjoint
    }
}
