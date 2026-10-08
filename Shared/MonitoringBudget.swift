import Foundation

/// Pure planning: no monitor XPC, persistence, usage mutation or shield effects.
enum MonitoringBudget {
    static let maximum = 20

    struct Window: Equatable {
        var name: String
        var start: DateComponents
        var end: DateComponents
    }

    /// Weekdays are checked by windowActive, not by separate OS registrations.
    /// The extra callbacks on skipped days only reconcile the actual rules.
    static func windows(prefix: String, start: Int, end: Int,
                        recurrence: Recurrence) -> [Window] {
        let wraps = start >= end
        // A very late weekly start cannot be split before 23:59 while meeting
        // Apple's 15-minute minimum. Preserve its proven weekday-spanning
        // registration instead of losing the evening callback during upgrade.
        if case .weekly(let days) = recurrence, wraps, start > 1424 {
            return days.sorted().map { day in
                Window(name: "\(prefix)-w\(day)",
                    start: DateComponents(hour: start / 60, minute: start % 60, weekday: day),
                    end: DateComponents(hour: end / 60, minute: end % 60, weekday: day % 7 + 1))
            }
        }
        switch recurrence {
        case .daily, .weekly:
            if case .weekly(let days) = recurrence, days.isEmpty { return [] }
            let segments = wraps ? [(start, 1439), (0, end)] : [(start, end)]
            return segments.enumerated().compactMap { index, segment in
                let paddedEnd = min(max(segment.1, segment.0 + 15), 1439)
                guard paddedEnd - segment.0 >= 15 else { return nil }
                return Window(name: "\(prefix)-\(index)",
                    start: DateComponents(hour: segment.0 / 60, minute: segment.0 % 60),
                    end: DateComponents(hour: paddedEnd / 60, minute: paddedEnd % 60))
            }
        case .monthlyDay(let day):
            return [Window(name: "\(prefix)-m",
                start: DateComponents(day: day, hour: start / 60, minute: start % 60),
                end: DateComponents(day: day, hour: end / 60, minute: end % 60))]
        case .monthlyOrdinal(let weekday, let ordinal):
            return [Window(name: "\(prefix)-o",
                start: DateComponents(hour: start / 60, minute: start % 60,
                                      weekday: weekday, weekdayOrdinal: ordinal),
                end: DateComponents(hour: end / 60, minute: end % 60,
                                    weekday: weekday, weekdayOrdinal: ordinal))]
        }
    }

    static func windowNames(state: LatchState, at now: Date = Date()) -> Set<String> {
        var names = Set<String>()
        func add(_ prefix: String, _ start: Int, _ end: Int, _ recurrence: Recurrence) {
            names.formUnion(windows(prefix: prefix, start: start, end: end,
                                    recurrence: recurrence).map(\.name))
        }
        for rule in state.schedules {
            add("sched-\(rule.id.uuidString)", rule.startMinutes, rule.endMinutes, rule.recurrence)
        }
        for rule in state.exemptions {
            add("exempt-\(rule.id.uuidString)", rule.startMinutes, rule.endMinutes, rule.recurrence)
        }
        names.formUnion(state.planned.filter { $0.endsAt > now }.map(\.activityName))
        if state.wakeRule.enabled || state.sleepRule.enabled {
            add("global-wake-boundary", state.wakeRule.startHour * 60,
                state.wakeRule.startHour * 60 + 15, .daily)
        }
        if state.sleepRule.enabled {
            add("global-sleep-boundary", state.sleepRule.startMinutes,
                state.wakeRule.startHour * 60, .daily)
        }
        for minute in dayNightBoundaryMinutes(state: state) {
            add("day-night-boundary-\(minute)", minute, minute + 15, .daily)
        }
        return names
    }

    static func dayNightBoundaryMinutes(state: LatchState) -> Set<Int> {
        var minutes: Set<Int> = state.dayNightGroups.isEmpty ? [] : [0]
        for group in state.dayNightGroups {
            minutes.insert(group.defaultWakeStart)
            minutes.formUnion(group.weekdayWakeTimings.values.map(\.startMinutes))
            if group.wakeEnabled {
                if let latest = group.wakeLatestMinutes { minutes.insert(latest) }
                minutes.formUnion(group.weekdayWakeTimings.values.compactMap(\.latestMinutes))
            }
            if group.sleepEnabled { minutes.insert(group.sleepStartMinutes) }
        }
        for limit in state.limits where limit.wakeDelayMinutes != nil {
            if let schedule = limit.wakeSchedule {
                if schedule.startMinutes != 0 { minutes.insert(schedule.startMinutes) }
                minutes.formUnion(schedule.dayTimings.values.map(\.startMinutes).filter { $0 != 0 })
                if let latest = schedule.latestMinutes { minutes.insert(latest) }
                minutes.formUnion(schedule.dayTimings.values.compactMap(\.latestMinutes))
            }
        }
        if state.wakeRule.enabled {
            if let latest = state.wakeRule.latestMinutes { minutes.insert(latest) }
            minutes.formUnion(state.wakeRule.weekdayLatestMinutes?.values.map { $0 } ?? [])
        }
        return minutes
    }

    static func splitNames(state: LatchState) -> Set<String> {
        var names = Set<String>()
        func add(_ phase: String, _ start: Int, _ end: Int) {
            names.insert("limit-part-\(phase)-\(start)-\(end)")
        }
        for limit in state.limits {
            guard let split = limit.split else { continue }
            let first = split.cutoffMinutes / 60
            add("early", 0, first)
            if let second = split.secondCutoffMinutes {
                let end = second / 60
                add(split.carryUnused ? "middle-carry" : "middle",
                    split.carryUnused ? 0 : first, end)
                if !split.carryUnused { add("late", end, 23) }
            } else if !split.carryUnused { add("late", first, 23) }
        }
        return names
    }

    static func normalize(_ name: String) -> String {
        name.hasPrefix("day-night-release-") ? "day-night-release" : name
    }

    /// Include latent needs: tomorrow's wake waits or a later free period
    /// cannot depend on space being available by chance when it begins.
    static func profile(state: LatchState, at now: Date = Date()) -> Set<String> {
        var names = windowNames(state: state, at: now).union(splitNames(state: state))
        if !state.limits.isEmpty { names.insert(LatchConstants.dailyActivityName) }
        names.formUnion(state.sessions.filter { $0.endsAt > now }.map(\.activityName))
        let free = !state.exemptions.isEmpty
            || state.planned.contains { $0.kind == .free && $0.endsAt > now }
            || state.sessions.contains { $0.kind == .free && $0.endsAt > now }
        if free && state.limits.contains(where: {
            $0.minutesPerDay > 0 || $0.weekdayMinutes.values.contains { $0 > 0 }
        }) { names.insert("latch.freewin") }
        if state.wakeRule.enabled && state.wakeRule.waitMinutes > 0 {
            names.insert("global-wake-release")
        }
        if state.dayNightGroups.contains(where: { $0.wakeEnabled && ($0.waitMinutes > 0 || $0.weekdayWakeTimings.values.contains { $0.waitMinutes > 0 }) }) {
            names.insert("day-night-release")
        }
        for limit in state.limits {
            if limit.wakeDelayMinutes != nil && ((limit.wakeDelayMinutes ?? 0) > 0
                || limit.wakeSchedule?.dayTimings.values.contains(where: { $0.waitMinutes > 0 }) == true) {
                names.insert("limit-wake-release-\(limit.id.uuidString)")
            }
            if limit.extraTime?.effectiveSteps.contains(where: {
                $0.waitMinutes > 0 && !$0.contactRequired
                    && $0.passwordPolicyID == nil && $0.phrasePolicyID == nil
            }) == true { names.insert("limit-extra-release-\(limit.id.uuidString)") }
            // Normally nil (retired on init/decode). Remain conservative if a
            // future caller ever constructs a live pacing rule in memory.
            if limit.pacing != nil {
                for prefix in ["limit-pace-", "limit-pace-tick-", "limit-pace-release-"] {
                    names.insert(prefix + limit.id.uuidString)
                }
            }
        }
        return names
    }

    /// A projection never applies a rule, changes a deadline or writes usage.
    /// Removal projections are optional: pending removals cannot promise room
    /// because a trusted contact may approve other changes in a different order.
    static func project(_ action: ChangeAction, onto original: LatchState,
                        id: UUID = UUID(), at now: Date = Date(),
                        includeRemovals: Bool = true) -> LatchState {
        var state = original
        switch action {
        case .setGroupWakeSchedule(let id, let minutes, let schedule):
            if let index = state.limits.firstIndex(where: { $0.id == id }) {
                state.limits[index].wakeDelayMinutes = minutes
                state.limits[index].wakeSchedule = schedule
            }
        case .addLimit(let limit):
            if !state.limits.contains(where: { $0.id == limit.id }) { state.limits.append(limit) }
        case .configureLimit(let limit):
            if let index = state.limits.firstIndex(where: { $0.id == limit.id }) { state.limits[index] = limit }
        case .setGroupWakeDelay(let id, let minutes):
            if let index = state.limits.firstIndex(where: { $0.id == id }) { state.limits[index].wakeDelayMinutes = minutes }
        case .removeLimit(let id):
            if includeRemovals { state.limits.removeAll { $0.id == id } }
        case .addSchedule(let rule):
            if !state.schedules.contains(where: { $0.id == rule.id }) { state.schedules.append(rule) }
        case .removeSchedule(let id):
            if includeRemovals { state.schedules.removeAll { $0.id == id } }
        case .addExemption(let rule):
            if !state.exemptions.contains(where: { $0.id == rule.id }) { state.exemptions.append(rule) }
        case .removeExemption(let id):
            if includeRemovals { state.exemptions.removeAll { $0.id == id } }
        case .addPlanned(let rule):
            if !state.planned.contains(where: { $0.id == rule.id }) { state.planned.append(rule) }
        case .removePlanned(let id):
            if includeRemovals { state.planned.removeAll { $0.id == id } }
        case .setWakeRule(let rule): state.wakeRule = rule
        case .setSleepRule(let rule): state.sleepRule = rule
        case .upsertDayNightGroup(let group):
            state.dayNightGroups.removeAll { $0.id == group.id }
            state.dayNightGroups.append(group)
        case .removeDayNightGroup(let id):
            if includeRemovals { state.dayNightGroups.removeAll { $0.id == id } }
        case .startSession(let name, let kind, let selection, let minutes):
            var session = BlockSession(name: name, kind: kind, selection: selection,
                                       startedAt: now, endsAt: now.addingTimeInterval(TimeInterval(max(1, minutes)) * 60))
            session.id = id // stable reservation, one for each pending start
            state.sessions.append(session)
        case .endSessionEarly(let id):
            if includeRemovals { state.sessions.removeAll { $0.id == id } }
        case .updateLimitMinutes(let id, let minutes):
            if let index = state.limits.firstIndex(where: { $0.id == id }) { state.limits[index].minutesPerDay = minutes }
        case .updateLimit(let id, _, let minutes):
            if let index = state.limits.firstIndex(where: { $0.id == id }) { state.limits[index].minutesPerDay = minutes }
        default: break
        }
        return state
    }

    static func reservations(state: LatchState, at now: Date = Date(),
                             guardedNow: Date = TimeGuard.now()) -> Set<String> {
        var result = profile(state: state, at: now)
        var potential = state
        var hasFree = result.contains("latch.freewin") || !state.exemptions.isEmpty
            || state.planned.contains { $0.kind == .free && $0.endsAt > now }
            || state.sessions.contains { $0.kind == .free && $0.endsAt > now }
        var hasAllowance = state.limits.contains { $0.minutesPerDay > 0 || $0.weekdayMinutes.values.contains { $0 > 0 } }
        for change in state.pending.sorted(by: { $0.appliesAt < $1.appliesAt }) {
            if change.appliesAt > guardedNow { result.insert(change.activityName) }
            // Include individual projections AND their accumulated combination.
            // Union old/new names conservatively, even if an edit replaces them.
            let single = project(change.action, onto: state, id: change.id, at: now, includeRemovals: false)
            potential = project(change.action, onto: potential, id: change.id, at: now, includeRemovals: false)
            for snapshot in [single, potential] {
                result.formUnion(profile(state: snapshot, at: now))
                hasFree = hasFree || !snapshot.exemptions.isEmpty
                    || snapshot.planned.contains { $0.kind == .free && $0.endsAt > now }
                    || snapshot.sessions.contains { $0.kind == .free && $0.endsAt > now }
                hasAllowance = hasAllowance || snapshot.limits.contains {
                    $0.minutesPerDay > 0 || $0.weekdayMinutes.values.contains { $0 > 0 }
                }
            }
        }
        if hasFree && hasAllowance { result.insert("latch.freewin") }
        return result
    }

    static func required(state: LatchState, running: Set<String> = [],
                         at now: Date = Date(), guardedNow: Date = TimeGuard.now()) -> Int {
        var names = reservations(state: state, at: now, guardedNow: guardedNow)
        var actual = Set<String>()
        for name in running.filter({ !$0.hasPrefix("echo-") }).sorted() {
            let normalized = normalize(name)
            // One actual release satisfies the one logical reservation. Any
            // stale duplicates still occupy real OS slots until cleaned up.
            if !actual.insert(normalized).inserted { names.insert("occupied:" + name) }
            else { names.insert(normalized) }
        }
        return names.count
    }

    /// Only structurally reducing changes can escape admission on an already
    /// over-budget installation. A replacement with new bucket names cannot.
    static func isRepair(_ action: ChangeAction, state: LatchState, at now: Date = Date()) -> Bool {
        let before = profile(state: state, at: now)
        let after = profile(state: project(action, onto: state, at: now), at: now)
        guard after.isSubset(of: before) else { return false }
        // Removing one contributor to a shared split bucket may free no slot
        // yet. Still allow successive removals rather than trapping that user.
        switch action {
        case .setGroupWakeSchedule(let id, let minutes, _):
            return state.limits.contains { $0.id == id && $0.wakeDelayMinutes != nil } && minutes == nil
        case .removeLimit(let id): return state.limits.contains { $0.id == id }
        case .removeSchedule(let id): return state.schedules.contains { $0.id == id }
        case .removeExemption(let id): return state.exemptions.contains { $0.id == id }
        case .removePlanned(let id): return state.planned.contains { $0.id == id }
        case .removeDayNightGroup(let id): return state.dayNightGroups.contains { $0.id == id }
        case .endSessionEarly(let id): return state.sessions.contains { $0.id == id }
        case .setGroupWakeDelay(let id, let minutes):
            return state.limits.contains { $0.id == id && $0.wakeDelayMinutes != nil }
                && minutes == nil
        case .setWakeRule(let rule): return state.wakeRule.enabled && !rule.enabled
        case .setSleepRule(let rule): return state.sleepRule.enabled && !rule.enabled
        case .upsertDayNightGroup(let group):
            guard let old = state.dayNightGroups.first(where: { $0.id == group.id }) else { return false }
            return (old.wakeEnabled && !group.wakeEnabled) || (old.sleepEnabled && !group.sleepEnabled)
        case .configureLimit(let limit):
            guard let old = state.limits.first(where: { $0.id == limit.id }) else { return false }
            return (old.split != nil && limit.split == nil)
                || (old.wakeDelayMinutes != nil && limit.wakeDelayMinutes == nil)
                || (old.extraTime != nil && limit.extraTime == nil)
        default: return false
        }
    }
}
