//
//  RulesPresentation.swift
//  Pure decisions for the Rules tab, the rule summary sheet, the New rule
//  chooser and the editors (docs/rules-redesign.md §5, §7). Foundation and
//  the saved rule models only, so Tests/RulesPresentationHarness.py compiles
//  this file with the real SharedModels and no app (FamilyControls only for
//  the selection type, which the harness stands in for).
//  Presentation only: nothing here reads or writes saved state, reads a
//  guarded clock, starts a monitor or decides enforcement. Words come from a
//  `translate` closure the views pass in (the app's `tr`).
//

import Foundation
import FamilyControls

// MARK: - Rule references

/// One rule as Rules, the summary sheet and Today point at it. The IDs are the
/// saved rules' own IDs; a queued addition already carries the ID it will
/// have, except a session start, which only gets one when it applies.
enum RuleRef: Hashable {
    case limit(UUID)
    case schedule(UUID)
    case exemption(UUID)
    case planned(UUID)
    case session(UUID)
    /// A queued "Block now" session, by its pending change's ID.
    case queuedSession(UUID)
    case dayNight(UUID)
    case legacyWake, legacySleep
    case appDeletion, adultWebsites, websites
    /// The delay policy (Your waits), so its pending change has a home too.
    case waits
    /// A When & where rule (docs/conditional-sessions-redesign.md §5.3).
    case conditional(UUID)

    var kind: RuleKind {
        switch self {
        case .limit: return .limit
        case .schedule: return .repeatingBlock
        case .exemption: return .freePeriod
        case .planned: return .planned
        case .session, .queuedSession: return .session
        case .dayNight, .legacyWake, .legacySleep: return .dayNight
        case .appDeletion, .adultWebsites, .websites: return .alwaysOn
        case .waits: return .waits
        case .conditional: return .conditional
        }
    }
}

extension RuleRef {
    /// The rule behind one of Today's items (`HomeDaySources` IDs), so the Now
    /// card and the day thread open the same summary sheet.
    init?(todayItemID id: String) {
        func uuid(_ prefix: String) -> UUID? {
            id.hasPrefix(prefix) ? UUID(uuidString: String(id.dropFirst(prefix.count))) : nil
        }
        if id == "global-sleep" { self = .legacySleep }
        else if id == "wake-global" { self = .legacyWake }
        else if let value = uuid("day-night-sleep-") { self = .dayNight(value) }
        else if let value = uuid("wake-day-night-") { self = .dayNight(value) }
        else if let value = uuid("wake-limit-") { self = .limit(value) }
        else if let value = uuid("session-") { self = .session(value) }
        else if let value = uuid("planned-") { self = .planned(value) }
        else if let value = uuid("schedule-") { self = .schedule(value) }
        else if let value = uuid("exemption-") { self = .exemption(value) }
        else { return nil }
    }
}

enum RuleKind: Equatable {
    case limit, repeatingBlock, freePeriod, dayNight, planned, session, alwaysOn, waits
    case conditional
}

// MARK: - Pending changes per rule

enum RulePending {
    /// The rule a pending change belongs to. Exhaustive on purpose: a new
    /// `ChangeAction` fails to compile until it is mapped here. Overrides,
    /// contacts and one-shot unlocks are not rules and map to nil.
    static func ref(for change: PendingChange) -> RuleRef? {
        switch change.action {
        case .addLimit(let limit), .configureLimit(let limit):
            return .limit(limit.id)
        case .updateLimitMinutes(let id, _), .updateLimit(let id, _, _),
             .setGroupWakeDelay(let id, _), .setGroupWakeSchedule(let id, _, _),
             .removeLimit(let id):
            return .limit(id)
        case .setDelayPolicy, .setStrictDelay, .setLenientDelay:
            return .waits
        case .setWakeRule:
            return .legacyWake
        case .setSleepRule:
            return .legacySleep
        case .upsertDayNightGroup(let group):
            return .dayNight(group.id)
        case .removeDayNightGroup(let id):
            return .dayNight(id)
        case .addSchedule(let schedule):
            return .schedule(schedule.id)
        case .updateScheduleSelection(let id, _), .removeSchedule(let id):
            return .schedule(id)
        case .addExemption(let exemption):
            return .exemption(exemption.id)
        case .removeExemption(let id):
            return .exemption(id)
        case .addPlanned(let window):
            return .planned(window.id)
        case .removePlanned(let id):
            return .planned(id)
        case .startSession:
            return .queuedSession(change.id)
        case .endSessionEarly(let id):
            return .session(id)
        case .setBlockAppRemoval:
            return .appDeletion
        case .setBlockAdultWebsites:
            return .adultWebsites
        case .addBlockedDomain, .removeBlockedDomain:
            return .websites
        case .setSchedulePriority,
             .setMathOverride, .setPasswordOverride,
             .upsertPasswordPolicy, .removePasswordPolicy,
             .upsertPhrasePolicy, .removePhrasePolicy,
             .setContactsOverride, .addContact, .removeContact, .setContactPermissions,
             .unlockPreventGuide, .unlockPasswordView:
            return nil
        case .addConditionalRule(let rule), .updateConditionalRule(let rule):
            return .conditional(rule.id)
        case .removeConditionalRule(let id):
            return .conditional(id)
        case .startConditionalSession:
            // A check-in start is not a change to the rule: free time starts
            // at once, and its conflict key differs from the rule's, so it must
            // not lock the rule's Edit and Remove. A check-in block waiting
            // its stricter delay shows on the rule's card (`cardChange`).
            return nil
        }
    }

    /// One pass over the pending list. When a rule has several changes (only
    /// the website list can), the one that lands first is kept.
    static func index(_ pending: [PendingChange]) -> [RuleRef: PendingChange] {
        var result: [RuleRef: PendingChange] = [:]
        for change in pending {
            guard let ref = ref(for: change) else { continue }
            if let kept = result[ref], kept.appliesAt <= change.appliesAt { continue }
            result[ref] = change
        }
        return result
    }

    enum Label: Equatable { case loosens, tightens, removed, added, starts }

    /// The change a card shows: its own, else (a When & where rule) a waiting
    /// End early of its running check-in session, which has no card of its own,
    /// else a check-in block waiting its stricter delay ("Starts in").
    static func cardChange(for ref: RuleRef, in index: [RuleRef: PendingChange],
                           state: LatchState, now: Date) -> PendingChange? {
        if let own = index[ref] { return own }
        guard case .conditional(let id) = ref else { return nil }
        if let ending = state.sessions.filter({ $0.conditionalRuleID == id && $0.endsAt > now })
            .compactMap({ index[.session($0.id)] }).min(by: { $0.appliesAt < $1.appliesAt }) {
            return ending
        }
        return waitingStart(of: id, in: state.pending)
    }

    /// A check-in start of this rule that waits (only a block's can).
    static func waitingStart(of ruleID: UUID, in pending: [PendingChange]) -> PendingChange? {
        pending.filter {
            if case .startConditionalSession(let request) = $0.action { return request.ruleID == ruleID }
            return false
        }.min { $0.appliesAt < $1.appliesAt }
    }

    /// "Removed in", "Added in", "Starts in", otherwise by direction.
    static func label(change: PendingChange, state: LatchState) -> Label {
        switch change.action {
        case .removeLimit, .removeSchedule, .removeExemption, .removePlanned,
             .removeDayNightGroup, .endSessionEarly, .removeConditionalRule:
            return .removed
        case .startSession, .startConditionalSession:
            return .starts
        case .addLimit, .addSchedule, .addExemption, .addPlanned, .addConditionalRule:
            return .added
        case .upsertDayNightGroup(let group)
            where !state.dayNightGroups.contains(where: { $0.id == group.id }):
            return .added
        default:
            return change.direction == .lenient ? .loosens : .tightens
        }
    }

    static func labelKey(_ label: Label) -> String {
        switch label {
        case .loosens: return "Loosens in"
        case .tightens: return "Tightens in"
        case .removed: return "Removed in"
        case .added: return "Added in"
        case .starts: return "Starts in"
        }
    }

    /// The edit or removal a rule's summary sheet would make conflicts with a
    /// waiting change. Same keys as the engine; day & night groups share one.
    static func blocksEdit(of target: RuleRef, pending: [PendingChange]) -> Bool {
        switch target {
        case .dayNight:
            return pending.contains {
                switch $0.action {
                case .upsertDayNightGroup, .removeDayNightGroup: return true
                default: return false
                }
            }
        case .legacyWake, .legacySleep:
            return pending.contains {
                switch $0.action {
                case .setWakeRule, .setSleepRule: return true
                default: return false
                }
            }
        case .websites, .queuedSession:
            return false
        default:
            return pending.contains { ref(for: $0) == target }
        }
    }
}

// MARK: - Times

enum RuleTimes {
    /// `Recurrence.matches(dayOf:)` in a given calendar.
    static func matches(_ recurrence: Recurrence, day: Date, calendar: Calendar) -> Bool {
        switch recurrence {
        case .daily:
            return true
        case .weekly(let days):
            return days.contains(calendar.component(.weekday, from: day))
        case .monthlyDay(let value):
            return calendar.component(.day, from: day) == value
        case .monthlyOrdinal(let weekday, let ordinal):
            return calendar.component(.weekday, from: day) == weekday
                && calendar.component(.weekdayOrdinal, from: day) == ordinal
        }
    }

    /// Wall-clock windows of a repeating rule whose start day is between
    /// yesterday and `days` days ahead. A window that wraps midnight belongs
    /// to the day it starts, as `windowActive` reads it.
    static func occurrences(start: Int, end: Int, recurrence: Recurrence, around now: Date,
                            days: Int = 8, calendar: Calendar) -> [DateInterval] {
        guard start != end else { return [] }
        let today = calendar.startOfDay(for: now)
        var result: [DateInterval] = []
        for offset in -1...days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  matches(recurrence, day: day, calendar: calendar),
                  let startsAt = calendar.date(bySettingHour: start / 60, minute: start % 60,
                                               second: 0, of: day),
                  let endDay = calendar.date(byAdding: .day, value: start > end ? 1 : 0, to: day),
                  let endsAt = calendar.date(bySettingHour: end / 60, minute: end % 60,
                                             second: 0, of: endDay),
                  endsAt > startsAt else { continue }
            result.append(DateInterval(start: startsAt, end: endsAt))
        }
        return result
    }

    /// The window running at `now`, if any.
    static func current(start: Int, end: Int, recurrence: Recurrence, at now: Date,
                        calendar: Calendar) -> DateInterval? {
        occurrences(start: start, end: end, recurrence: recurrence, around: now, days: 0,
                    calendar: calendar)
            .first { $0.start <= now && now < $0.end }
    }

    /// Sleep from the evening start to that night's wake-up time, as
    /// `DayNightGroup.sleepIsActive` reads it.
    static func sleep(_ group: DayNightGroup, around now: Date, days: Int = 1,
                      calendar: Calendar) -> [DateInterval] {
        guard group.sleepEnabled else { return [] }
        let today = calendar.startOfDay(for: now)
        func wakeStart(on day: Date) -> Int {
            group.weekdayWakeTimings[calendar.component(.weekday, from: day)]?.startMinutes
                ?? group.defaultWakeStart
        }
        var result: [DateInterval] = []
        for offset in -1...days {
            guard let anchor = calendar.date(byAdding: .day, value: offset, to: today),
                  group.weekdays.contains(calendar.component(.weekday, from: anchor)),
                  let startsAt = calendar.date(bySettingHour: group.sleepStartMinutes / 60,
                    minute: group.sleepStartMinutes % 60, second: 0, of: anchor) else { continue }
            let endDay = wakeStart(on: anchor) > group.sleepStartMinutes ? anchor
                : (calendar.date(byAdding: .day, value: 1, to: anchor) ?? anchor)
            let endMinute = wakeStart(on: endDay)
            guard let endsAt = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60,
                                             second: 0, of: endDay),
                  endsAt > startsAt else { continue }
            result.append(DateInterval(start: startsAt, end: endsAt))
        }
        return result
    }

    /// Legacy sleep: from its start to the wake-up hour, on the evenings chosen.
    static func legacySleep(_ rule: SleepBlockRule, wakeHour: Int, around now: Date,
                            calendar: Calendar) -> [DateInterval] {
        guard rule.enabled else { return [] }
        return occurrences(start: rule.startMinutes, end: wakeHour * 60,
                           recurrence: .weekly(rule.weekdays), around: now, days: 1,
                           calendar: calendar)
    }
}

/// The next start of a repeating window, lifted from the old Schedules
/// "Coming up" list: the first start after `now` on a matching day, at most
/// seven days ahead.
enum NextStart {
    static func after(now: Date, start: Int, recurrence: Recurrence,
                      calendar: Calendar) -> Date? {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset,
                                          to: calendar.startOfDay(for: now)),
                  matches(recurrence, day, calendar),
                  let startsAt = calendar.date(bySettingHour: start / 60, minute: start % 60,
                                               second: 0, of: day),
                  startsAt > now, startsAt < weekEnd else { continue }
            return startsAt
        }
        return nil
    }

    private static func matches(_ recurrence: Recurrence, _ day: Date, _ calendar: Calendar) -> Bool {
        RuleTimes.matches(recurrence, day: day, calendar: calendar)
    }
}

// MARK: - Live state chip

enum RuleChip: Equatable {
    case blocked
    case onUntil(Date)
    case freeUntil(Date)
    case opens(Date)
    case startsIn(Date)
    case on, off
    /// When & where free time: uses left today (never "conditions met").
    case usesLeft(Int)
    case noneLeft

    static let upcomingWindow: TimeInterval = 24 * 3600

    /// One chip per card (spec §5.4). `blockedLimitIDs` is the monitor's spent
    /// list and `wakeOpens` the projected wake releases, both read by the view
    /// in event callbacks.
    /// `conditionalUsed` is today's uses per free-time rule, read by the view in
    /// events on the guarded clock; a rule missing from it shows no count.
    static func live(ref: RuleRef, state: LatchState, blockedLimitIDs: Set<UUID>,
                     wakeOpens: [RuleRef: Date] = [:], conditionalUsed: [UUID: Int] = [:],
                     now: Date, calendar: Calendar) -> RuleChip? {
        func upcoming(_ date: Date?) -> RuleChip? {
            guard let date, date > now, date.timeIntervalSince(now) <= upcomingWindow else { return nil }
            return .startsIn(date)
        }
        switch ref {
        case .limit(let id):
            guard let limit = state.limits.first(where: { $0.id == id }) else { return nil }
            let today = limit.weekdayMinutes[calendar.component(.weekday, from: now)]
                ?? limit.minutesPerDay
            return blockedLimitIDs.contains(id) || today <= 0 ? .blocked : nil
        case .schedule(let id):
            guard let rule = state.schedules.first(where: { $0.id == id }) else { return nil }
            if let window = RuleTimes.current(start: rule.startMinutes, end: rule.endMinutes,
                                              recurrence: rule.recurrence, at: now, calendar: calendar) {
                return .onUntil(window.end)
            }
            return upcoming(NextStart.after(now: now, start: rule.startMinutes,
                                            recurrence: rule.recurrence, calendar: calendar))
        case .exemption(let id):
            guard let rule = state.exemptions.first(where: { $0.id == id }) else { return nil }
            if let window = RuleTimes.current(start: rule.startMinutes, end: rule.endMinutes,
                                              recurrence: rule.recurrence, at: now, calendar: calendar) {
                return .freeUntil(window.end)
            }
            return upcoming(NextStart.after(now: now, start: rule.startMinutes,
                                            recurrence: rule.recurrence, calendar: calendar))
        case .planned(let id):
            guard let window = state.planned.first(where: { $0.id == id }) else { return nil }
            if window.startsAt <= now && now < window.endsAt {
                return window.kind == .free ? .freeUntil(window.endsAt) : .onUntil(window.endsAt)
            }
            return upcoming(window.startsAt)
        case .session(let id):
            guard let session = state.sessions.first(where: { $0.id == id }),
                  session.startedAt <= now, now < session.endsAt else { return nil }
            return session.kind == .block ? .onUntil(session.endsAt) : .freeUntil(session.endsAt)
        case .dayNight(let id):
            guard let group = state.dayNightGroups.first(where: { $0.id == id }) else { return nil }
            if let opens = wakeOpens[ref], opens > now { return .opens(opens) }
            let nights = RuleTimes.sleep(group, around: now, calendar: calendar)
            if let night = nights.first(where: { $0.start <= now && now < $0.end }) {
                return .onUntil(night.end)
            }
            return upcoming(nights.map(\.start).filter { $0 > now }.min())
        case .legacyWake:
            if let opens = wakeOpens[ref], opens > now { return .opens(opens) }
            return nil
        case .legacySleep:
            let nights = RuleTimes.legacySleep(state.sleepRule, wakeHour: state.wakeRule.startHour,
                                               around: now, calendar: calendar)
            if let night = nights.first(where: { $0.start <= now && now < $0.end }) {
                return .onUntil(night.end)
            }
            return upcoming(nights.map(\.start).filter { $0 > now }.min())
        case .appDeletion:
            return state.blockAppRemoval ? .on : .off
        case .adultWebsites:
            return state.blockAdultWebsites ? .on : .off
        case .websites:
            return state.blockedDomains.isEmpty ? .off : .on
        case .queuedSession, .waits:
            return nil
        case .conditional(let id):
            guard let rule = state.conditionalRules.first(where: { $0.id == id }) else { return nil }
            if let session = state.sessions.first(where: {
                $0.conditionalRuleID == id && $0.startedAt <= now && now < $0.endsAt
            }) {
                return session.kind == .block ? .onUntil(session.endsAt) : .freeUntil(session.endsAt)
            }
            switch rule.outcome {
            case .block:
                // A time branch running on its own (an owned repeating block).
                let ends = state.schedules.filter { $0.ownerRuleID == id }.compactMap {
                    RuleTimes.current(start: $0.startMinutes, end: $0.endMinutes,
                                      recurrence: $0.recurrence, at: now, calendar: calendar)?.end
                }
                return ends.max().map { .onUntil($0) }
            case .freeTime(_, _, _, let usesPerDay):
                guard let used = ConditionalText.usedForToday(rule, used: conditionalUsed[id],
                                                              now: now, calendar: calendar) else { return nil }
                let left = max(0, usesPerDay - used)
                return left > 0 ? .usesLeft(left) : .noneLeft
            }
        }
    }
}

// MARK: - Catalog

enum RuleSection: Equatable, CaseIterable {
    case limits, schedules, conditional, dayNight, planned, alwaysOn

    var titleKey: String {
        switch self {
        case .limits: return "Limits"
        case .schedules: return "Schedules"
        case .conditional: return "When & where"
        case .dayNight: return "Day & night"
        case .planned: return "Planned"
        case .alwaysOn: return "Always on"
        }
    }
}

struct RuleCard: Equatable, Identifiable {
    let ref: RuleRef
    /// The rule's own name; empty for built-in rules, which the view names.
    let name: String
    /// Queued but not saved yet: drawn dashed, opens the sheet in waiting mode.
    var isAddition = false
    var id: RuleRef { ref }
}

struct RuleSectionModel: Equatable {
    let section: RuleSection
    let cards: [RuleCard]
}

enum RuleCatalog {
    /// Sections in the spec's order (§5.3); empty ones are dropped, except
    /// Always on, whose switches are always real.
    static func sections(state: LatchState, now: Date) -> [RuleSectionModel] {
        var additions: [RuleSection: [RuleCard]] = [:]
        for change in state.pending {
            switch change.action {
            case .addLimit(let limit) where !state.limits.contains(where: { $0.id == limit.id }):
                additions[.limits, default: []].append(RuleCard(ref: .limit(limit.id), name: limit.name, isAddition: true))
            case .addSchedule(let rule):
                additions[.schedules, default: []].append(RuleCard(ref: .schedule(rule.id), name: rule.name, isAddition: true))
            case .addExemption(let rule):
                additions[.schedules, default: []].append(RuleCard(ref: .exemption(rule.id), name: rule.name, isAddition: true))
            case .upsertDayNightGroup(let group) where !state.dayNightGroups.contains(where: { $0.id == group.id }):
                additions[.dayNight, default: []].append(RuleCard(ref: .dayNight(group.id), name: group.name, isAddition: true))
            case .addPlanned(let window):
                additions[.planned, default: []].append(RuleCard(ref: .planned(window.id), name: window.name, isAddition: true))
            case .startSession(let name, _, _, _):
                additions[.planned, default: []].append(RuleCard(ref: .queuedSession(change.id), name: name, isAddition: true))
            case .addConditionalRule(let rule) where !state.conditionalRules.contains(where: { $0.id == rule.id }):
                additions[.conditional, default: []].append(RuleCard(ref: .conditional(rule.id), name: rule.name, isAddition: true))
            default:
                continue
            }
        }

        let limits = state.limits.map { RuleCard(ref: .limit($0.id), name: $0.name) }
        // A When & where rule's own windows show under that rule, not here.
        let blocks = state.schedules.filter { $0.ownerRuleID == nil }.enumerated()
            .sorted { ($0.element.startMinutes, $0.offset) < ($1.element.startMinutes, $1.offset) }
            .map { RuleCard(ref: .schedule($0.element.id), name: $0.element.name) }
        let free = state.exemptions.enumerated()
            .sorted { ($0.element.startMinutes, $0.offset) < ($1.element.startMinutes, $1.offset) }
            .map { RuleCard(ref: .exemption($0.element.id), name: $0.element.name) }
        var dayNight = state.dayNightGroups.map { RuleCard(ref: .dayNight($0.id), name: $0.name) }
        dayNight += additions[.dayNight] ?? []
        if hasLegacyWake(state) { dayNight.append(RuleCard(ref: .legacyWake, name: "")) }
        if hasLegacySleep(state) { dayNight.append(RuleCard(ref: .legacySleep, name: "")) }
        // A check-in session shows on its When & where rule (chip, End early),
        // not twice; once its rule is removed (C14) it shows here again.
        let running = state.sessions.filter { session in
            guard session.endsAt > now else { return false }
            guard let owner = session.conditionalRuleID else { return true }
            return !state.conditionalRules.contains { $0.id == owner }
        }
            .enumerated().sorted { ($0.element.endsAt, $0.offset) < ($1.element.endsAt, $1.offset) }
            .map { RuleCard(ref: .session($0.element.id), name: $0.element.name) }
        let planned = state.planned.filter { $0.endsAt > now }
            .enumerated().sorted { ($0.element.startsAt, $0.offset) < ($1.element.startsAt, $1.offset) }
            .map { RuleCard(ref: .planned($0.element.id), name: $0.element.name) }

        let all: [(RuleSection, [RuleCard])] = [
            (.limits, limits + (additions[.limits] ?? [])),
            (.schedules, blocks + free + (additions[.schedules] ?? [])),
            (.conditional, state.conditionalRules.map { RuleCard(ref: .conditional($0.id), name: $0.name) }
                + (additions[.conditional] ?? [])),
            (.dayNight, dayNight),
            (.planned, running + planned + (additions[.planned] ?? [])),
            (.alwaysOn, [RuleCard(ref: .appDeletion, name: ""),
                         RuleCard(ref: .adultWebsites, name: ""),
                         RuleCard(ref: .websites, name: "")]),
        ]
        return all.filter { $0.0 == .alwaysOn || !$0.1.isEmpty }
            .map { RuleSectionModel(section: $0.0, cards: $0.1) }
    }

    /// First use: nothing but the Always on switches.
    static func isFirstUse(_ sections: [RuleSectionModel]) -> Bool {
        sections.allSatisfy { $0.section == .alwaysOn }
    }

    /// Same tests as the old Day & night page's legacy links.
    static func hasLegacyWake(_ state: LatchState) -> Bool {
        state.wakeRule != WakeBlockRule() || hasLegacySleep(state)
            || state.pending.contains { if case .setWakeRule = $0.action { return true }; return false }
    }

    static func hasLegacySleep(_ state: LatchState) -> Bool {
        state.sleepRule != SleepBlockRule()
            || state.pending.contains { if case .setSleepRule = $0.action { return true }; return false }
    }

    /// A queued session start becomes a session with a new ID when it
    /// applies. Given the queued change the sheet remembered, follow it to
    /// that session (same name, kind and apps, started after it was queued).
    /// Every other ref is itself.
    static func resolve(_ ref: RuleRef, state: LatchState, remembered: PendingChange?) -> RuleRef {
        // An owned window (Today's thread, the Calendar) opens its rule.
        if case .schedule(let id) = ref,
           let owner = state.schedules.first(where: { $0.id == id })?.ownerRuleID {
            return .conditional(owner)
        }
        // So does a check-in session (the Now card, the thread), while its rule exists.
        if case .session(let id) = ref,
           let owner = state.sessions.first(where: { $0.id == id })?.conditionalRuleID,
           state.conditionalRules.contains(where: { $0.id == owner }) {
            return .conditional(owner)
        }
        guard case .queuedSession(let changeID) = ref,
              !state.pending.contains(where: { $0.id == changeID }),
              let remembered, remembered.id == changeID,
              case .startSession(let name, let kind, let selection, _) = remembered.action,
              let started = state.sessions.last(where: {
                  $0.name == name && $0.kind == kind && $0.selection == selection
                      && $0.startedAt >= remembered.createdAt
              })
        else { return ref }
        return .session(started.id)
    }

    /// The saved or queued rule behind a ref, for the summary sheet. Nil means
    /// it no longer exists (removed while the sheet was open).
    enum Source: Equatable { case live, waiting(PendingChange), gone }

    static func source(of ref: RuleRef, state: LatchState) -> Source {
        func queued(_ match: (ChangeAction) -> Bool) -> Source {
            state.pending.first { match($0.action) }.map { .waiting($0) } ?? .gone
        }
        switch ref {
        case .limit(let id):
            if state.limits.contains(where: { $0.id == id }) { return .live }
            return queued { if case .addLimit(let l) = $0 { return l.id == id }; return false }
        case .schedule(let id):
            if state.schedules.contains(where: { $0.id == id }) { return .live }
            return queued { if case .addSchedule(let s) = $0 { return s.id == id }; return false }
        case .exemption(let id):
            if state.exemptions.contains(where: { $0.id == id }) { return .live }
            return queued { if case .addExemption(let e) = $0 { return e.id == id }; return false }
        case .planned(let id):
            if state.planned.contains(where: { $0.id == id }) { return .live }
            return queued { if case .addPlanned(let w) = $0 { return w.id == id }; return false }
        case .session(let id):
            return state.sessions.contains(where: { $0.id == id }) ? .live : .gone
        case .queuedSession(let changeID):
            return state.pending.first { $0.id == changeID }.map { .waiting($0) } ?? .gone
        case .dayNight(let id):
            if state.dayNightGroups.contains(where: { $0.id == id }) { return .live }
            return queued { if case .upsertDayNightGroup(let g) = $0 { return g.id == id }; return false }
        case .legacyWake:
            return hasLegacyWake(state) ? .live : .gone
        case .legacySleep:
            return hasLegacySleep(state) ? .live : .gone
        case .appDeletion, .adultWebsites, .websites, .waits:
            return .live
        case .conditional(let id):
            if state.conditionalRules.contains(where: { $0.id == id }) { return .live }
            return queued { if case .addConditionalRule(let r) = $0 { return r.id == id }; return false }
        }
    }
}

// MARK: - Words

/// Counts of what a rule covers: apps, categories, websites.
struct RuleCounts: Equatable {
    var apps = 0, categories = 0, sites = 0
    var total: Int { apps + categories + sites }

    init(apps: Int = 0, categories: Int = 0, sites: Int = 0) {
        self.apps = apps; self.categories = categories; self.sites = sites
    }

    init(_ selection: FamilyActivitySelection) {
        self.init(apps: selection.applicationTokens.count,
                  categories: selection.categoryTokens.count,
                  sites: selection.webDomainTokens.count)
    }
}

enum RuleDays: Equatable {
    case everyDay, weekdays, weekends
    case some(Set<Int>)
    case monthlyDay(Int)
    case monthlyOrdinal(weekday: Int, ordinal: Int)

    init(_ recurrence: Recurrence) {
        switch recurrence {
        case .daily: self = .everyDay
        case .weekly(let days): self = RuleDays(weekdays: days)
        case .monthlyDay(let day): self = .monthlyDay(day)
        case .monthlyOrdinal(let weekday, let ordinal): self = .monthlyOrdinal(weekday: weekday, ordinal: ordinal)
        }
    }

    init(weekdays days: Set<Int>) {
        if days == Set(1...7) { self = .everyDay }
        else if days == Set(2...6) { self = .weekdays }
        else if days == [1, 7] { self = .weekends }
        else { self = .some(days) }
    }
}

enum RuleText {
    typealias Translate = (String) -> String

    /// "18:00" or "6:00 PM", by the locale's clock.
    static func clock(_ minutes: Int, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1,
                                                      hour: minutes / 60, minute: minutes % 60))!
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                               calendar: calendar, timeZone: calendar.timeZone))
    }

    /// "5 min", "1 hr, 15 min", "1 day". Rounded up to the minute.
    static func duration(_ seconds: TimeInterval, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        let minutes = max(1, (seconds / 60).rounded(.up))
        return formatter.string(from: minutes * 60) ?? ""
    }

    static func minutes(_ value: Int, locale: Locale) -> String {
        duration(TimeInterval(value * 60), locale: locale)
    }

    static func counts(_ counts: RuleCounts, translate: Translate) -> String {
        var parts: [String] = []
        if counts.apps > 0 {
            parts.append(counts.apps == 1 ? translate("1 app") : String(format: translate("%d apps"), counts.apps))
        }
        if counts.categories > 0 {
            parts.append(counts.categories == 1 ? translate("1 category")
                         : String(format: translate("%d categories"), counts.categories))
        }
        if counts.sites > 0 {
            parts.append(counts.sites == 1 ? translate("1 website") : String(format: translate("%d websites"), counts.sites))
        }
        return parts.isEmpty ? translate("Nothing selected") : parts.joined(separator: ", ")
    }

    static func days(_ days: RuleDays, translate: Translate, calendar: Calendar) -> String {
        switch days {
        case .everyDay: return translate("Every day")
        case .weekdays: return translate("Weekdays")
        case .weekends: return translate("Weekends")
        case .some(let set):
            let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
            return order.filter(set.contains).map { calendar.shortWeekdaySymbols[$0 - 1] }
                .joined(separator: ", ")
        case .monthlyDay(let day):
            return String(format: translate("Day %d of every month"), day)
        case .monthlyOrdinal(let weekday, let ordinal):
            return String(format: translate("%@ #%d of every month"),
                          calendar.weekdaySymbols[weekday - 1], ordinal)
        }
    }

    /// "Sat 9 Nov 09:00 → Sun 18:00": the end carries only what differs.
    static func range(_ start: Date, _ end: Date, locale: Locale, calendar: Calendar) -> String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                    calendar: calendar, timeZone: calendar.timeZone)
        let first = start.formatted(time.weekday(.abbreviated).day().month(.abbreviated))
        let last = calendar.isDate(start, inSameDayAs: end) ? end.formatted(time)
            : end.formatted(time.weekday(.abbreviated))
        return "\(first) → \(last)"
    }

    /// "Stricter: 5 min · Looser: 1 day" by delay mode (spec §5.2).
    static func waits(_ policy: DelayPolicy, translate: Translate, locale: Locale) -> String {
        let policy = policy.normalized
        let looser = duration(policy.lenientDelay, locale: locale)
        switch policy.mode {
        case .separate:
            return String(format: translate("Stricter: %@ · Looser: %@"),
                          duration(policy.strictDelay, locale: locale), looser)
        case .shared:
            return String(format: translate("Every change: %@"), looser)
        case .lenientOnly:
            return String(format: translate("Stricter: %@ · Looser: %@"), translate("right away"), looser)
        }
    }
}

// MARK: - Summary line

enum RuleSummaryLine {
    enum Part: Equatable {
        case minutesADay(Int)
        case minutesRange(Int, Int)
        case blockedAllDay
        case counts(RuleCounts)
        case split, extraTime
        case window(RuleDays, start: Int, end: Int)
        case only(RuleCounts)
        case allExcept(RuleCounts)
        case freePeriod
        case wake(start: Int, wait: Int)
        case sleep(Int)
        case days(RuleDays)
        case range(Date, Date)
        case session(SessionKind, RuleCounts)
        case anyApp, appleFilter
        case sites(Int)
        /// Legacy wake-up: from its hour, wait after the tap.
        case legacyWake(hour: Int, wait: Int)
        case conditions(ConditionalMatch, [ConditionalCondition])
        case conditionalOutcome(ConditionalOutcome)
    }

    /// What one card says under its name (spec §5.4). Queued additions read
    /// from their queued action.
    static func parts(for ref: RuleRef, state: LatchState) -> [Part] {
        switch ref {
        case .limit(let id):
            guard let limit = state.limits.first(where: { $0.id == id })
                ?? queued(state, { if case .addLimit(let l) = $0, l.id == id { return l }; return nil })
            else { return [] }
            return limitParts(limit)
        case .schedule(let id):
            guard let rule = state.schedules.first(where: { $0.id == id })
                ?? queued(state, { if case .addSchedule(let s) = $0, s.id == id { return s }; return nil })
            else { return [] }
            let counts = RuleCounts(rule.selection)
            return [.window(RuleDays(rule.recurrence), start: rule.startMinutes, end: rule.endMinutes),
                    rule.mode == .blockSelected ? .only(counts) : .allExcept(counts)]
        case .exemption(let id):
            guard let rule = state.exemptions.first(where: { $0.id == id })
                ?? queued(state, { if case .addExemption(let e) = $0, e.id == id { return e }; return nil })
            else { return [] }
            return [.window(RuleDays(rule.recurrence), start: rule.startMinutes, end: rule.endMinutes), .freePeriod]
        case .planned(let id):
            guard let window = state.planned.first(where: { $0.id == id })
                ?? queued(state, { if case .addPlanned(let w) = $0, w.id == id { return w }; return nil })
            else { return [] }
            let counts = RuleCounts(window.selection)
            switch window.kind {
            case .blockSelected: return [.range(window.startsAt, window.endsAt), .only(counts)]
            case .blockAllExcept: return [.range(window.startsAt, window.endsAt), .allExcept(counts)]
            case .free: return [.range(window.startsAt, window.endsAt), .freePeriod]
            }
        case .session(let id):
            guard let session = state.sessions.first(where: { $0.id == id }) else { return [] }
            return [.session(session.kind, RuleCounts(session.selection))]
        case .queuedSession(let changeID):
            guard let change = state.pending.first(where: { $0.id == changeID }),
                  case .startSession(_, let kind, let selection, _) = change.action else { return [] }
            return [.session(kind, RuleCounts(selection))]
        case .dayNight(let id):
            guard let group = state.dayNightGroups.first(where: { $0.id == id })
                ?? queued(state, { if case .upsertDayNightGroup(let g) = $0, g.id == id { return g }; return nil })
            else { return [] }
            var parts: [Part] = []
            if group.wakeEnabled { parts.append(.wake(start: group.defaultWakeStart, wait: group.waitMinutes)) }
            if group.sleepEnabled { parts.append(.sleep(group.sleepStartMinutes)) }
            parts.append(.days(RuleDays(weekdays: group.weekdays)))
            return parts
        case .legacyWake:
            let rule = state.wakeRule
            return rule.enabled ? [.legacyWake(hour: rule.startHour, wait: rule.waitMinutes),
                                   .days(RuleDays(weekdays: rule.weekdays))] : []
        case .legacySleep:
            let rule = state.sleepRule
            return rule.enabled ? [.sleep(rule.startMinutes), .days(RuleDays(weekdays: rule.weekdays))] : []
        case .appDeletion: return [.anyApp]
        case .adultWebsites: return [.appleFilter]
        case .websites: return [.sites(state.blockedDomains.count)]
        case .waits: return []
        case .conditional(let id):
            guard let rule = ConditionalText.rule(id, state: state) else { return [] }
            return [.conditions(rule.match, rule.conditions), .conditionalOutcome(rule.outcome)]
        }
    }

    static func limitParts(_ limit: AppLimit) -> [Part] {
        let budgets = (1...7).map { max(0, limit.weekdayMinutes[$0] ?? limit.minutesPerDay) }
        var parts: [Part]
        let low = budgets.min() ?? 0, high = budgets.max() ?? 0
        if high == 0 { parts = [.blockedAllDay] }
        else if low == high { parts = [.minutesADay(low)] }
        else { parts = [.minutesRange(low, high)] }
        parts.append(.counts(RuleCounts(limit.selection)))
        if limit.split != nil { parts.append(.split) }
        if limit.extraTime != nil { parts.append(.extraTime) }
        return parts
    }

    static func text(_ parts: [Part], translate: RuleText.Translate, locale: Locale,
                     calendar: Calendar) -> String {
        parts.map { part -> String in
            switch part {
            case .minutesADay(let value):
                return String(format: translate("%d min a day"), value)
            case .minutesRange(let low, let high):
                return String(format: translate("%d–%d min a day"), low, high)
            case .blockedAllDay:
                return translate("Blocked all day")
            case .counts(let counts):
                return RuleText.counts(counts, translate: translate)
            case .split:
                return translate("split")
            case .extraTime:
                return translate("extra time")
            case .window(let days, let start, let end):
                return RuleText.days(days, translate: translate, calendar: calendar) + " "
                    + RuleText.clock(start, locale: locale) + "–" + RuleText.clock(end, locale: locale)
            case .only(let counts):
                return counts.total == 0 ? translate("Nothing selected")
                    : String(format: translate("only %@"), RuleText.counts(counts, translate: translate))
            case .allExcept(let counts):
                return counts.total == 0 ? translate("every app")
                    : String(format: translate("all except %@"), RuleText.counts(counts, translate: translate))
            case .freePeriod:
                return translate("free period")
            case .wake(let start, let wait):
                return String(format: translate("Wake %@ + %@"), RuleText.clock(start, locale: locale),
                              RuleText.minutes(wait, locale: locale))
            case .legacyWake(let hour, let wait):
                return String(format: translate("Wake %@ + %@"), RuleText.clock(hour * 60, locale: locale),
                              RuleText.minutes(wait, locale: locale))
            case .sleep(let start):
                return String(format: translate("Sleep %@"), RuleText.clock(start, locale: locale))
            case .days(let days):
                return RuleText.days(days, translate: translate, calendar: calendar)
            case .range(let start, let end):
                return RuleText.range(start, end, locale: locale, calendar: calendar)
            case .session(let kind, let counts):
                switch kind {
                case .block: return translate("Block") + " · " + RuleText.counts(counts, translate: translate)
                case .unblock: return translate("Unblock") + " · " + RuleText.counts(counts, translate: translate)
                case .free: return translate("Free period")
                }
            case .anyApp:
                return translate("Any app")
            case .appleFilter:
                return translate("Apple's filter")
            case .sites(let count):
                return count == 0 ? translate("No sites yet")
                    : RuleText.counts(RuleCounts(sites: count), translate: translate)
            case .conditions(let match, let conditions):
                return ConditionalText.line(match, conditions, translate: translate,
                                            locale: locale, calendar: calendar)
            case .conditionalOutcome(let outcome):
                return ConditionalText.outcomeShort(outcome, translate: translate, locale: locale)
            }
        }
        .joined(separator: " · ")
    }

    private static func queued<T>(_ state: LatchState, _ match: (ChangeAction) -> T?) -> T? {
        for change in state.pending { if let value = match(change.action) { return value } }
        return nil
    }
}

// MARK: - Summary sheet facts

enum RuleFact: Equatable {
    enum What: Equatable {
        case only(RuleCounts), allExcept(RuleCounts), covers(RuleCounts)
        /// Day & night: "chosen limits and apps" or "everything except".
        case dayNight(everythingExcept: Bool, limitNames: [String], extra: RuleCounts)
    }
    enum Gate: Equatable { case wait(Int), password(String), phrase(String), contact }
    struct ExtraUse: Equatable { let minutes: Int; let gate: Gate }
    struct Portion: Equatable { let untilMinutes: Int?; let minutes: Int }

    case howMuch(daily: Int, perDay: [Int: Int])
    case window(RuleDays, start: Int, end: Int)
    case range(Date, Date)
    case until(Date)
    case days(Set<Int>)
    case what(What)
    case split([Portion], carryUnused: Bool)
    case extraTime([ExtraUse], left: Int?)
    case wakeUp(start: Int, wait: Int, latest: Int?)
    case sleep(Int)
    /// When & where: "If (all of)" with one line per condition, "Then", and
    /// today's uses for free time.
    case conditions(ConditionalMatch, [ConditionalCondition])
    case then(ConditionalOutcome)
    case usesToday(left: Int, of: Int)

    var labelKey: String {
        switch self {
        case .howMuch: return "How much"
        case .window, .range, .until: return "When"
        case .days: return "Days"
        case .what: return "What"
        case .split: return "Split"
        case .extraTime: return "Extra time"
        case .wakeUp: return "Wake-up"
        case .sleep: return "Sleep"
        case .conditions(let match, _): return match == .all ? "If (all of)" : "If (any of)"
        case .then: return "Then"
        case .usesToday: return "Today"
        }
    }
}

enum RuleSummaryFacts {
    /// The sheet's fact rows, only those that apply (spec §5.6). `extraLeft` is
    /// today's remaining extra-time uses, read by the view in an event callback.
    /// `conditionalUsed` is a When & where rule's uses today, already passed
    /// through `ConditionalText.usedForToday` (nil = unknown or not today).
    static func make(ref: RuleRef, state: LatchState, extraLeft: Int? = nil,
                     conditionalUsed: Int? = nil) -> [RuleFact] {
        switch ref {
        case .limit(let id):
            guard let limit = state.limits.first(where: { $0.id == id })
                ?? state.pending.lazy.compactMap({ change -> AppLimit? in
                    if case .addLimit(let l) = change.action, l.id == id { return l }; return nil }).first
            else { return [] }
            var facts: [RuleFact] = [
                .howMuch(daily: limit.minutesPerDay,
                         perDay: limit.weekdayMinutes.filter { $0.value != limit.minutesPerDay }),
                .what(.covers(RuleCounts(limit.selection))),
            ]
            if let split = limit.split { facts.append(.split(portions(split, total: limit.minutesPerDay),
                                                              carryUnused: split.carryUnused)) }
            if let extra = limit.extraTime {
                facts.append(.extraTime(extra.effectiveSteps.map { ExtraUseBuilder.use($0, overrides: state.overrides) },
                                        left: extraLeft))
            }
            // Per-limit wake-up only where it is already set (R7).
            if let wait = limit.wakeDelayMinutes {
                let schedule = limit.wakeSchedule ?? LimitWakeSchedule()
                facts.append(.wakeUp(start: schedule.startMinutes, wait: wait, latest: schedule.latestMinutes))
            }
            return facts
        case .schedule(let id):
            guard let rule = state.schedules.first(where: { $0.id == id })
                ?? state.pending.lazy.compactMap({ change -> BlockSchedule? in
                    if case .addSchedule(let s) = change.action, s.id == id { return s }; return nil }).first
            else { return [] }
            let counts = RuleCounts(rule.selection)
            var facts: [RuleFact] = [.window(RuleDays(rule.recurrence), start: rule.startMinutes, end: rule.endMinutes)]
            if case .weekly(let days) = rule.recurrence { facts.append(.days(days)) }
            facts.append(.what(rule.mode == .blockSelected ? .only(counts) : .allExcept(counts)))
            return facts
        case .exemption(let id):
            guard let rule = state.exemptions.first(where: { $0.id == id })
                ?? state.pending.lazy.compactMap({ change -> ExemptSchedule? in
                    if case .addExemption(let e) = change.action, e.id == id { return e }; return nil }).first
            else { return [] }
            var facts: [RuleFact] = [.window(RuleDays(rule.recurrence), start: rule.startMinutes, end: rule.endMinutes)]
            if case .weekly(let days) = rule.recurrence { facts.append(.days(days)) }
            return facts
        case .planned(let id):
            guard let window = state.planned.first(where: { $0.id == id })
                ?? state.pending.lazy.compactMap({ change -> PlannedWindow? in
                    if case .addPlanned(let w) = change.action, w.id == id { return w }; return nil }).first
            else { return [] }
            let counts = RuleCounts(window.selection)
            switch window.kind {
            case .blockSelected: return [.range(window.startsAt, window.endsAt), .what(.only(counts))]
            case .blockAllExcept: return [.range(window.startsAt, window.endsAt), .what(.allExcept(counts))]
            case .free: return [.range(window.startsAt, window.endsAt)]
            }
        case .session(let id):
            guard let session = state.sessions.first(where: { $0.id == id }) else { return [] }
            let counts = RuleCounts(session.selection)
            switch session.kind {
            case .block: return [.until(session.endsAt), .what(.only(counts))]
            case .unblock: return [.until(session.endsAt), .what(.covers(counts))]
            case .free: return [.until(session.endsAt)]
            }
        case .queuedSession(let changeID):
            guard let change = state.pending.first(where: { $0.id == changeID }),
                  case .startSession(_, let kind, let selection, _) = change.action,
                  kind != .free else { return [] }
            return [.what(kind == .block ? .only(RuleCounts(selection)) : .covers(RuleCounts(selection)))]
        case .dayNight(let id):
            guard let group = state.dayNightGroups.first(where: { $0.id == id })
                ?? state.pending.lazy.compactMap({ change -> DayNightGroup? in
                    if case .upsertDayNightGroup(let g) = change.action, g.id == id { return g }; return nil }).first
            else { return [] }
            var facts: [RuleFact] = []
            if group.wakeEnabled {
                facts.append(.wakeUp(start: group.defaultWakeStart, wait: group.waitMinutes,
                                     latest: group.wakeLatestMinutes))
            }
            if group.sleepEnabled { facts.append(.sleep(group.sleepStartMinutes)) }
            facts.append(.days(group.weekdays))
            let except = group.scope.mode == .allOtherApps
            let ids = except ? group.scope.excludedLimitIDs : group.scope.limitIDs
            facts.append(.what(.dayNight(everythingExcept: except,
                                         limitNames: state.limits.filter { ids.contains($0.id) }.map(\.name),
                                         extra: RuleCounts(group.scope.selection))))
            return facts
        case .legacyWake:
            let rule = state.wakeRule
            guard rule.enabled else { return [] }
            return [.wakeUp(start: rule.startHour * 60, wait: rule.waitMinutes, latest: rule.latestMinutes),
                    .days(rule.weekdays)]
        case .legacySleep:
            let rule = state.sleepRule
            guard rule.enabled else { return [] }
            return [.sleep(rule.startMinutes), .days(rule.weekdays)]
        case .appDeletion, .adultWebsites, .websites, .waits:
            return []
        case .conditional(let id):
            guard let rule = ConditionalText.rule(id, state: state) else { return [] }
            var facts: [RuleFact] = [.conditions(rule.match, rule.conditions), .then(rule.outcome)]
            // Today only for a saved free-time rule whose uses could be read.
            if case .freeTime(_, _, _, let uses) = rule.outcome, let used = conditionalUsed,
               state.conditionalRules.contains(where: { $0.id == id }) {
                facts.append(.usesToday(left: max(0, uses - used), of: uses))
            }
            return facts
        }
    }

    /// The day's portions in order, with the same clamps the editor saves.
    static func portions(_ split: LimitSplit, total: Int) -> [RuleFact.Portion] {
        let first = min(split.beforeMinutes, total)
        if let second = split.secondCutoffMinutes {
            let middle = min(split.middleMinutes ?? 0, max(0, total - first))
            return [.init(untilMinutes: split.cutoffMinutes, minutes: first),
                    .init(untilMinutes: second, minutes: middle),
                    .init(untilMinutes: nil, minutes: max(0, total - first - middle))]
        }
        return [.init(untilMinutes: split.cutoffMinutes, minutes: first),
                .init(untilMinutes: nil, minutes: max(0, total - first))]
    }

    static func gateText(_ gate: RuleFact.Gate, translate: RuleText.Translate, locale: Locale) -> String {
        switch gate {
        case .wait(let minutes):
            return String(format: translate("after a %@ wait"), RuleText.minutes(minutes, locale: locale))
        case .password(let name):
            return String(format: translate("with the password “%@”"), name)
        case .phrase(let name):
            return String(format: translate("with the phrase “%@”"), name)
        case .contact:
            return translate("with a trusted contact")
        }
    }

    static func extraUseText(_ index: Int, _ use: RuleFact.ExtraUse,
                             translate: RuleText.Translate, locale: Locale) -> String {
        String(format: translate("Use %d"), index + 1) + " · "
            + RuleText.minutes(use.minutes, locale: locale) + " · "
            + gateText(use.gate, translate: translate, locale: locale)
    }
}

enum ExtraUseBuilder {
    static func use(_ step: LimitExtraStep, overrides: OverridesConfig) -> RuleFact.ExtraUse {
        if step.contactRequired { return .init(minutes: step.minutes, gate: .contact) }
        if let id = step.passwordPolicyID {
            return .init(minutes: step.minutes,
                         gate: .password(overrides.passwordPolicies.first { $0.id == id }?.name ?? ""))
        }
        if let id = step.phrasePolicyID {
            return .init(minutes: step.minutes,
                         gate: .phrase(overrides.phrasePolicies.first { $0.id == id }?.name ?? ""))
        }
        return .init(minutes: step.minutes, gate: .wait(step.waitMinutes))
    }
}

// MARK: - New rule chooser

enum NewRuleKind: CaseIterable, Equatable {
    case dailyLimit, blockNow, repeating, planned, dayNight, website, whenWhere

    /// Why a row can't be chosen, as a translation key; nil when it can.
    static func disabledReason(_ kind: NewRuleKind, state: LatchState) -> String? {
        if kind == .whenWhere {
            // Same count as the engine: saved rules plus queued additions.
            let queued = state.pending.filter {
                if case .addConditionalRule = $0.action { return true }
                return false
            }.count
            return state.conditionalRules.count + queued >= ConditionalRule.maximumRules
                ? "You can have up to five When & where rules." : nil
        }
        guard kind == .dayNight else { return nil }
        if state.dayNightGroups.count >= 5 { return "You can have up to five day & night groups." }
        let waiting = state.pending.contains {
            switch $0.action {
            case .upsertDayNightGroup, .removeDayNightGroup: return true
            default: return false
            }
        }
        return waiting ? "Wait for the day & night change that's already waiting." : nil
    }
}

// MARK: - Editor validation

/// The first thing stopping an editor's Review change (R12). The accept set
/// is exactly the old editors' `isValid`; the harness checks both on a table.
enum EditorProblem: Equatable {
    case name, apps, noDays, sameTimes, monthlyMidnight, endBeforeStart
    case extraTooLong, extraGate
    /// When & where (`EditorValidation.conditional`).
    case nameTooLong, noConditions, tooManyConditions, datesOrder
    case blockNeedsPlace, blockAnyOfDays, invalid
    /// Not a problem to explain: the draft equals the saved rule.
    case unchanged

    var messageKey: String? {
        switch self {
        case .name: return "Give it a name."
        case .apps: return "Choose at least one app."
        case .noDays: return "Choose at least one day."
        case .sameTimes: return "Start and end can't be the same time."
        case .monthlyMidnight: return "Monthly schedules can't cross midnight — set the end time after the start time."
        case .endBeforeStart: return "End after it starts."
        case .extraTooLong: return "The limit and its extra time must fit in one day."
        case .extraGate: return "Choose a way to unlock each extra-time use that's still available."
        case .nameTooLong: return "Use a shorter name."
        case .noConditions: return "Add at least one condition."
        case .tooManyConditions: return "Use at most four conditions."
        case .datesOrder: return "The last day can't be before the first."
        case .blockNeedsPlace: return "Use a repeating block for rules without a place."
        case .blockAnyOfDays: return "With “any of”, a block can use times, places and countries, not days or dates."
        case .invalid: return "Check this rule's settings."
        case .unchanged: return nil
        }
    }
}

enum EditorValidation {
    static func hasSelection(_ selection: FamilyActivitySelection) -> Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    /// Daily limit. `draft` is the editor's `draftLimit`.
    static func limit(name: String, existing: AppLimit?, draft: AppLimit, minutes: Int,
                      extraEnabled: Bool, extraSteps: [LimitExtraStep],
                      overrides: OverridesConfig) -> EditorProblem? {
        if existing == nil && name.isEmpty { return .name }
        if !hasSelection(draft.selection) { return .apps }
        if extraEnabled {
            if extraSteps.isEmpty || minutes + extraSteps.reduce(0, { $0 + $1.minutes }) > 1439 {
                return .extraTooLong
            }
            if extraSteps.contains(where: { !extraGateAvailable($0, overrides: overrides) }) {
                return .extraGate
            }
        }
        if let existing, draft == existing { return .unchanged }
        return nil
    }

    static func extraGateAvailable(_ step: LimitExtraStep, overrides: OverridesConfig) -> Bool {
        if [step.passwordPolicyID != nil, step.phrasePolicyID != nil,
            step.contactRequired].filter({ $0 }).count > 1 { return false }
        if step.contactRequired {
            return overrides.contactsEnabled
                && overrides.contacts.contains { $0.isUsable && $0.allowed.contains(.extraTime) }
        }
        if let id = step.passwordPolicyID {
            return overrides.passwordPolicies.contains { $0.id == id && $0.allowed.contains(.extraTime) }
        }
        if let id = step.phrasePolicyID {
            return overrides.phrasePolicies.contains { $0.id == id && $0.allowed.contains(.extraTime) }
        }
        return true
    }

    static func isMonthly(_ recurrence: Recurrence) -> Bool {
        switch recurrence {
        case .monthlyDay, .monthlyOrdinal: return true
        case .daily, .weekly: return false
        }
    }

    /// Repeating block or free period (new only).
    static func repeating(name: String, start: Int, end: Int, recurrence: Recurrence,
                          isFree: Bool, draft: BlockSchedule) -> EditorProblem? {
        if name.isEmpty { return .name }
        if start == end { return .sameTimes }
        if isMonthly(recurrence) && start >= end { return .monthlyMidnight }
        if case .weekly(let days) = recurrence, days.isEmpty { return .noDays }
        if isFree { return nil }
        return draft.acceptsSelection(draft.selection) ? nil : .apps
    }

    /// Plan a block. Like the old editor, website-only selections don't count (§11).
    static func planned(name: String, kind: PlannedKind, selection: FamilyActivitySelection,
                        startsAt: Date, endsAt: Date) -> EditorProblem? {
        if name.isEmpty { return .name }
        if endsAt <= startsAt { return .endBeforeStart }
        if kind == .blockSelected && selection.applicationTokens.isEmpty
            && selection.categoryTokens.isEmpty { return .apps }
        return nil
    }

    /// When & where (R12, spec §5.10). Names the first problem in the order
    /// the page reads; `ConditionalRule.isValid` (the engine's own check) is
    /// the last word, so nil here always means the engine accepts the draft.
    static func conditional(_ draft: ConditionalRule, existing: ConditionalRule?) -> EditorProblem? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .name }
        if draft.name.count > ConditionalRule.maximumNameLength { return .nameTooLong }
        if draft.conditions.isEmpty { return .noConditions }
        if draft.conditions.count > ConditionalRule.maximumConditions { return .tooManyConditions }
        for condition in draft.conditions {
            switch condition {
            case .days(let days) where days.isEmpty: return .noDays
            case .time(let start, let end) where start == end: return .sameTimes
            case .dates(let first, let last) where first.isValid && last.isValid && last < first:
                return .datesOrder
            default:
                if !condition.isValid { return .invalid }
            }
        }
        switch draft.outcome {
        case .freeTime(let kind, let selection, _, _):
            if kind == .unblock && !hasSelection(selection) { return .apps }
        case .block(_, let selection, _):
            // Say first what no choice of apps can fix (v1 limits).
            if !draft.hasLocationCondition { return .blockNeedsPlace }
            if draft.match == .any && draft.conditions.contains(where: {
                switch $0 {
                case .days, .dates: return true
                case .place, .country, .time: return false
                }
            }) { return .blockAnyOfDays }
            if !hasSelection(selection) { return .apps }
        }
        if !draft.isValid { return .invalid }
        if let existing, draft.sameConfiguration(as: existing) { return .unchanged }
        return nil
    }

    /// Block now. A free period needs no apps; block and unblock do.
    static func session(kind: SessionKind, selection: FamilyActivitySelection) -> EditorProblem? {
        kind != .free && selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty
            ? .apps : nil
    }
}

// MARK: - When & where words

/// Card line, summary sheet lines and editor defaults for When & where rules
/// (docs/conditional-sessions-redesign.md §5.3, §5.4, §5.10). Place and
/// country names only: never coordinates or distances, except a place's
/// chosen size on the summary sheet.
enum ConditionalText {
    /// The saved rule, or a queued addition's.
    static func rule(_ id: UUID, state: LatchState) -> ConditionalRule? {
        if let saved = state.conditionalRules.first(where: { $0.id == id }) { return saved }
        for change in state.pending {
            if case .addConditionalRule(let rule) = change.action, rule.id == id { return rule }
        }
        return nil
    }

    /// An "all of" rule whose days or dates exclude today, or whose same-day
    /// time window has already ended, can't hold again today, so neither the
    /// card nor the sheet counts uses (the summary line carries the days).
    /// Read in the Gregorian calendar, as the evaluator reads it. Display
    /// only: the wall clock and current zone, never a verdict (the check-in
    /// re-evaluates on the guarded clock in every recent zone).
    static func ruledOutToday(_ rule: ConditionalRule, now: Date, calendar: Calendar) -> Bool {
        guard rule.match == .all else { return false }
        let gregorian = ConditionalDay.gregorian(in: calendar.timeZone)
        let weekday = gregorian.component(.weekday, from: now)
        let today = ConditionalDay.of(now, in: calendar.timeZone)
        let clock = gregorian.dateComponents([.hour, .minute], from: now)
        let minute = (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
        return rule.conditions.contains { condition in
            switch condition {
            case .days(let days): return !days.contains(weekday)
            case .dates(let first, let last): return today < first || last < today
            // A window that wraps midnight can still open tonight.
            case .time(let start, let end): return start < end && minute >= end
            case .place, .country: return false
            }
        }
    }

    /// Today's uses to show for a free-time rule: nil when unknown or when
    /// the rule can't hold again today. One rule for the chip and the sheet.
    static func usedForToday(_ rule: ConditionalRule, used: Int?, now: Date, calendar: Calendar) -> Int? {
        guard rule.isFreeTime, let used, !ruledOutToday(rule, now: now, calendar: calendar) else { return nil }
        return used
    }

    /// "at Home", "in Mexico", "on weekends", "22:00–06:00", "20 Dec to 27 Dec".
    static func condition(_ condition: ConditionalCondition, translate: RuleText.Translate,
                          locale: Locale, calendar: Calendar) -> String {
        switch condition {
        case .place(let place):
            return String(format: translate("at %@"), place.name)
        case .country(let code):
            return String(format: translate("in %@"), countryName(code, locale: locale))
        case .days(let days):
            switch RuleDays(weekdays: days) {
            case .everyDay: return translate("every day")
            case .weekdays: return translate("on weekdays")
            case .weekends: return translate("on weekends")
            default:
                return String(format: translate("on %@"),
                              RuleText.days(.some(days), translate: translate, calendar: calendar))
            }
        case .time(let start, let end):
            return RuleText.clock(start, locale: locale) + "–" + RuleText.clock(end, locale: locale)
        case .dates(let first, let last):
            if first == last { return date(first, locale: locale, calendar: calendar) }
            return String(format: translate("%@ to %@"), date(first, locale: locale, calendar: calendar),
                          date(last, locale: locale, calendar: calendar))
        }
    }

    static func countryName(_ code: String, locale: Locale) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }

    static func date(_ day: ConditionalDay, locale: Locale, calendar: Calendar) -> String {
        guard let value = ConditionalDay.gregorian(in: calendar.timeZone)
                .date(from: DateComponents(year: day.year, month: day.month, day: day.day))
        else { return "\(day.year)-\(day.month)-\(day.day)" }
        return value.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale,
                                                calendar: calendar, timeZone: calendar.timeZone))
    }

    /// Upper-cases only the first letter, in the language's own rules.
    static func capitalizedFirst(_ text: String, locale: Locale) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased(with: locale) + text.dropFirst()
    }

    /// The card's condition part: "In Mexico, on Sun" / "At Home, or 22:00–06:00".
    static func line(_ match: ConditionalMatch, _ conditions: [ConditionalCondition],
                     translate: RuleText.Translate, locale: Locale, calendar: Calendar) -> String {
        let parts = conditions.map { condition($0, translate: translate, locale: locale, calendar: calendar) }
        guard var result = parts.first else { return String() }
        for part in parts.dropFirst() {
            result = match == .all ? result + ", " + part
                : String(format: translate("%@, or %@"), result, part)
        }
        return capitalizedFirst(result, locale: locale)
    }

    /// The card's outcome part: "1 hr free", "2 × 30 min free", "blocks 1 app".
    static func outcomeShort(_ outcome: ConditionalOutcome, translate: RuleText.Translate,
                             locale: Locale) -> String {
        switch outcome {
        case .freeTime(let kind, _, let minutes, let uses):
            let length = RuleText.minutes(minutes, locale: locale)
            if kind == .unblock {
                return uses == 1 ? String(format: translate("%@ unblocked"), length)
                    : String(format: translate("%d × %@ unblocked"), uses, length)
            }
            return uses == 1 ? String(format: translate("%@ free"), length)
                : String(format: translate("%d × %@ free"), uses, length)
        case .block(_, let selection, _):
            return String(format: translate("blocks %@"),
                          RuleText.counts(RuleCounts(selection), translate: translate))
        }
    }

    /// One summary-sheet line per condition: "At Home · within 250 m".
    static func sheetLine(_ condition: ConditionalCondition, translate: RuleText.Translate,
                          locale: Locale, calendar: Calendar) -> String {
        let text = capitalizedFirst(self.condition(condition, translate: translate, locale: locale,
                                                   calendar: calendar), locale: locale)
        if case .place(let place) = condition {
            return text + " · " + String(format: translate("within %@"), radius(place.radiusMeters, locale: locale))
        }
        return text
    }

    static func radius(_ meters: Int, locale: Locale) -> String {
        let measurement = meters >= 1000
            ? Measurement(value: Double(meters) / 1000, unit: UnitLength.kilometers)
            : Measurement(value: Double(meters), unit: UnitLength.meters)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .asProvided).locale(locale))
    }

    /// The summary sheet's "Then" in two lines.
    static func outcomeLines(_ outcome: ConditionalOutcome, translate: RuleText.Translate,
                             locale: Locale) -> [String] {
        switch outcome {
        case .freeTime(let kind, let selection, let minutes, let uses):
            let times = uses == 1 ? translate("Once a day") : String(format: translate("%d times a day"), uses)
            let what = kind == .unblock
                ? String(format: translate("only %@"), RuleText.counts(RuleCounts(selection), translate: translate))
                : translate("everything unblocked")
            return [String(format: translate("Free time, up to %@"), RuleText.minutes(minutes, locale: locale)),
                    times + " · " + what]
        case .block(_, let selection, let until):
            let end: String
            switch until {
            case .time(let minute): end = String(format: translate("Until %@"), RuleText.clock(minute, locale: locale))
            case .duration(let minutes): end = String(format: translate("For %@"), RuleText.minutes(minutes, locale: locale))
            }
            return [String(format: translate("Block only %@"),
                           RuleText.counts(RuleCounts(selection), translate: translate)), end]
        }
    }

    static func symbol(_ condition: ConditionalCondition) -> String {
        ConditionKind.of(condition).symbol
    }
}

/// The editor's Add condition chooser (spec §5.10, Google Home).
enum ConditionKind: CaseIterable, Equatable {
    case place, country, days, time, dates

    static func of(_ condition: ConditionalCondition) -> ConditionKind {
        switch condition {
        case .place: return .place
        case .country: return .country
        case .days: return .days
        case .time: return .time
        case .dates: return .dates
        }
    }

    /// SF Symbols, not words (spec §5.4).
    var symbol: String { Self.symbols[self] ?? "circle" }
    private static let symbols: [ConditionKind: String] = [
        .place: "mappin", .country: "globe", .days: "calendar",
        .time: "clock", .dates: "calendar.badge.clock",
    ]

    var titleKey: String {
        switch self {
        case .place: return "Place"
        case .country: return "Country"
        case .days: return "Days"
        case .time: return "Time"
        case .dates: return "Dates"
        }
    }

    var exampleKey: String {
        switch self {
        case .place: return "Like home or school"
        case .country: return "Like Mexico"
        case .days: return "Like weekends"
        case .time: return "Like after 22:00"
        case .dates: return "Like a trip"
        }
    }

    /// Why a row can't be chosen, as a translation key: only the four-condition cap.
    static func disabledReason(_ kind: ConditionKind, conditionCount: Int) -> String? {
        conditionCount >= ConditionalRule.maximumConditions ? "You can add up to four conditions." : nil
    }

    /// A new condition's starting value: weekends, 22:00–00:00 ("after
    /// 22:00"), or the coming seven days. Nil for a place (it needs a centre
    /// from the place editor first) and a country (chosen in its picker).
    static func defaultCondition(_ kind: ConditionKind, now: Date, calendar: Calendar) -> ConditionalCondition? {
        switch kind {
        case .place, .country:
            return nil
        case .days:
            return .days([1, 7])
        case .time:
            return .time(start: 22 * 60, end: 0)
        case .dates:
            let gregorian = ConditionalDay.gregorian(in: calendar.timeZone)
            let last = gregorian.date(byAdding: .day, value: 6, to: now) ?? now
            return .dates(first: ConditionalDay.of(now, in: calendar.timeZone),
                          last: ConditionalDay.of(last, in: calendar.timeZone))
        }
    }
}

// MARK: - Draft overlap

enum DraftOverlap {
    struct Note: Equatable {
        let name: String
        /// Weekdays (1 = Sunday) of the coming week the two overlap.
        let weekdays: Set<Int>
    }

    /// Rules the draft would overlap in the next seven days. Informational:
    /// it never blocks saving. Built on `SchedulePrecedence.conflicts`.
    static func notes(state: LatchState, draft: BlockSchedule, now: Date,
                      calendar: Calendar) -> [Note] {
        var preview = state
        preview.schedules.append(draft)
        return notes(preview: preview, key: "schedule-\(draft.id.uuidString)", now: now, calendar: calendar)
    }

    static func notes(state: LatchState, draft: ExemptSchedule, now: Date,
                      calendar: Calendar) -> [Note] {
        var preview = state
        preview.exemptions.append(draft)
        return notes(preview: preview, key: "exemption-\(draft.id.uuidString)", now: now, calendar: calendar)
    }

    private static func notes(preview: LatchState, key: String, now: Date,
                              calendar: Calendar) -> [Note] {
        guard let end = calendar.date(byAdding: .day, value: 7, to: now) else { return [] }
        let entries = SchedulePrecedence.entries(state: preview, from: now, through: end)
        var days: [String: Set<Int>] = [:]
        var order: [String] = []
        for overlap in SchedulePrecedence.conflicts(entries: entries,
                                                    prioritizedKeys: preview.prioritizedScheduleKeys) {
            let other: SchedulePrecedence.Entry
            if overlap.lowerPriority.key == key { other = overlap.higherPriority }
            else if overlap.higherPriority.key == key { other = overlap.lowerPriority }
            else { continue }
            if days[other.name] == nil { order.append(other.name) }
            days[other.name, default: []].insert(calendar.component(.weekday, from: overlap.start))
        }
        return order.map { Note(name: $0, weekdays: days[$0] ?? []) }
    }
}

// MARK: - When & where check-in (spec §5.3, §5.5; C15 step 3)

/// What one check found: the rule version it checked, the evaluation, the
/// stamp a start sends, and today's uses, all on one clock read. Built in
/// events from a clock the view read (`ConditionalClockInput.current`), so
/// nothing here reads the guarded clock. Kept only while the sheet is open.
struct CheckInResult: Equatable {
    var rule: ConditionalRule
    var evaluation: ConditionalEvaluation
    var stamp: ConditionalCheckInStamp
    var clockAgrees: Bool
    /// The engine's own count over every recent zone's day key; nil when the
    /// zones can't be resolved (a start would be refused).
    var used: Int?
    /// Guarded minus wall time at the check, to place the window end on the
    /// wall clock that sessions use.
    var guardedOffset: TimeInterval
    /// True when this check used a location read (a fix or "unavailable").
    /// Such a check is never refreshed without reading again (C8, C9).
    var readLocation = false
    /// A met block check (step 6): when the block would end, from the
    /// engine's own `ConditionalStart.plan` for this check's stamp, run where
    /// the engine runs it: now to queue, then again when the stricter wait
    /// ends (review fix: a block that waits is planned from when it lands, so
    /// "until 07:00" checked in at 06:30 with a 1 h wait runs until 07:00 the
    /// next day). Or why the engine would refuse it.
    var blockEnd: Date? = nil
    var blockRefusal: ConditionalStartRefusal? = nil
    /// The block runs for the rule's whole duration (not cut by a window end).
    var blockRunsFullDuration = false
    /// The stricter wait the block's start would follow (C4), from saved state.
    var blockWait: TimeInterval = 0

    /// `location` is what this check read: `.notRead` unless the sheet read
    /// one fix in the foreground for it (C8). The stamp comes from this very
    /// evaluation, so a start can only claim what this check found. Only the
    /// per-condition results are kept, never the coordinates.
    static func make(rule: ConditionalRule, state: LatchState, clock: ConditionalClockInput,
                     location: ConditionalLocationInput, checkInID: UUID = UUID()) -> CheckInResult {
        let evaluation = ConditionEvaluator.evaluate(rule, clock: clock, location: location)
        let used = clock.dayKeys.map {
            ConditionalUses.used(ruleID: rule.id, dayKeys: $0,
                                 in: ConditionalUses.pruned(state.conditionalUses, at: clock.guardedNow))
        }
        var readLocation = true
        if case .notRead = location { readLocation = false }
        let stamp = ConditionalCheckInStamp.make(evaluation, clock: clock, checkInID: checkInID)
        var result = CheckInResult(rule: rule, evaluation: evaluation, stamp: stamp,
                                   clockAgrees: clock.clockAgrees, used: used,
                                   guardedOffset: clock.guardedNow.timeIntervalSince(clock.wallNow),
                                   readLocation: readLocation)
        if case .block(_, _, let until) = rule.outcome, evaluation.isMet {
            let request = ConditionalStartRequest(ruleID: rule.id, revision: rule.revision, minutes: 1, stamp: stamp)
            let wait = state.delayPolicy.delay(for: .stricter)
            result.blockWait = wait
            var landing = clock
            landing.guardedNow = clock.guardedNow.addingTimeInterval(wait)
            landing.wallNow = clock.wallNow.addingTimeInterval(wait)
            // Queued now (fresh), then applied when the wait ends.
            let queued = ConditionalStart.plan(request, state: state, clock: clock)
            let applied = wait > 0 ? ConditionalStart.plan(request, state: state, clock: landing, phase: .apply) : queued
            switch (queued, applied) {
            case (.failure(let refusal), _):
                result.blockRefusal = refusal
            case (.success, .failure):
                // Its window closes before the wait ends: the engine would drop it.
                result.blockRefusal = .windowEnded
            case (.success, .success(let plan)):
                result.blockEnd = plan.session.endsAt
                if case .duration(let minutes) = until {
                    result.blockRunsFullDuration = plan.session.endsAt.timeIntervalSince(plan.session.startedAt)
                        >= TimeInterval(minutes) * 60 - 1
                }
            }
        }
        return result
    }

    /// The window end on the wall clock; nil = only the length caps it.
    var wallWindowEnd: Date? { evaluation.windowEnd.map { $0.addingTimeInterval(-guardedOffset) } }
}

/// How the last start went, as the sheet keeps it (mapped from the engine's
/// `ConditionalStartResult`, which the presentation harness doesn't compile).
enum CheckInAttempt: Equatable {
    case started(until: Date)
    case waiting
    case refused(ConditionalStartRefusal)
}

/// What the check-in sheet says (spec §5.5 step 6). Only `.met` offers a start.
enum CheckInScreen: Equatable {
    case checking
    case gone
    /// The rule changed after this check (an edit landed): check again.
    case changed
    case running(until: Date)
    /// Only a fix could decide it and this check didn't read one (it was
    /// refreshed on its own): Check in again reads where you are.
    case needsLocation
    /// Waiting for the user's yes on the in-sheet card before iOS asks.
    case askPermission
    /// Reading one fix ("Checking where you are").
    case locating
    case clockChanged
    case notMet
    case unknownUses
    case usedUp
    /// Less than a minute is left in the window that allows it.
    case windowEnding
    /// Free time can start now, for at most `cap` minutes.
    case met(cap: Int)
    case refused(ConditionalStartRefusal)
    case queued
    /// Blocks (step 6; spec §5.2, C3, C4). A block can start: Review → the
    /// receipt with its stricter wait. `endsAt` is the end if it started now.
    case blockMet(endsAt: Date)
    case blockRunning(until: Date)
    /// Under "any of", the rule's own time window blocks now on its own and
    /// no place or country is met: nothing to start.
    case blockOnItsOwn(until: Date)
    /// A check-in block of this rule waits its stricter delay.
    case blockWaiting(startsAt: Date)
    /// Met, but the engine would drop the block when its wait ends (review fix).
    case blockWontWait(BlockWaitProblem)

    var canStart: Bool {
        switch self {
        case .met, .blockMet: return true
        default: return false
        }
    }
}

/// Why a met block can't be started, or a waiting one won't start (review fix).
enum BlockWaitProblem: Equatable {
    /// Its all-of window closes before the stricter wait ends.
    case windowCloses
    /// A waiting edit or removal of the rule lands first, which drops the start.
    case ruleChangesFirst
    /// A waiting start was made for an older version of the rule.
    case staleWaiting
}

/// Where the sheet is in its one location read; held by the view, never saved.
enum CheckInLocationPhase: Equatable { case idle, asking, reading }

/// What a check needs next, decided before any read (C8: location only when
/// it can change the answer, the system prompt only after the in-sheet card).
enum CheckInLocationStep: Equatable {
    /// The answer doesn't depend on a fix (or no fix could decide it yet).
    case none
    /// Never asked: show the card; iOS asks only after "Allow location".
    case ask
    /// Denied or restricted: check again with "location off", never re-prompt.
    case off
    case read
}

enum ConditionalCheckIn {
    /// On since the countries step (C15 step 5): a fix decides countries
    /// through the bundled offline lookup (`CountryBorders`).
    static let countryLookupAvailable = true
    /// A check older than this is run again before a start: a margin under
    /// the engine's own 2-minute stamp lifetime.
    static let freshness: TimeInterval = ConditionalStart.stampLifetime - 10

    /// `live` is the saved rule now; `sessions` saved state's sessions;
    /// `now` the wall clock (sessions end on it).
    static func screen(check: CheckInResult?, live: ConditionalRule?, sessions: [BlockSession],
                       attempt: CheckInAttempt?, now: Date,
                       location: CheckInLocationPhase = .idle,
                       pending: [PendingChange] = []) -> CheckInScreen {
        guard let live else { return .gone }
        // Only saved state says free time is on: a start that was ended
        // elsewhere (housekeeping, another process) no longer reads as running.
        // What runs is the session's own kind (review fix: an edit can switch
        // the rule's outcome while a session of it keeps running).
        if let running = sessions.filter({ $0.conditionalRuleID == live.id && $0.endsAt > now })
            .max(by: { $0.endsAt < $1.endsAt }) {
            return running.kind == .block ? .blockRunning(until: running.endsAt) : .running(until: running.endsAt)
        }
        // A check-in block waiting its stricter delay: one at a time (C4).
        if let waiting = RulePending.waitingStart(of: live.id, in: pending) {
            if case .startConditionalSession(let request) = waiting.action, request.revision != live.revision {
                return .blockWontWait(.staleWaiting)
            }
            if !live.isFreeTime { return .blockWaiting(startsAt: waiting.appliesAt) }
        }
        switch attempt {
        case .refused(let refusal)?: return .refused(refusal)
        // A block that waits shows from saved state (above); otherwise the
        // fresh check after the attempt decides.
        case .waiting?: if live.isFreeTime { return .queued }
        case .started?, nil: break
        }
        guard let check else { return .checking }
        guard check.rule.revision == live.revision, check.rule.sameConfiguration(as: live)
        else { return .changed }
        guard case .freeTime(_, _, let maxMinutes, let usesPerDay) = live.outcome else {
            let screen = blockScreen(check, location: location)
            // Review fix: a waiting edit or removal of this rule that lands
            // before the block would makes the engine drop the start.
            if case .blockMet = screen, let change = RulePending.index(pending)[.conditional(live.id)],
               change.appliesAt <= check.stamp.guardedAt.addingTimeInterval(check.blockWait) {
                return .blockWontWait(.ruleChangesFirst)
            }
            return screen
        }
        guard check.clockAgrees else { return .clockChanged }
        let evaluation = check.evaluation
        if !evaluation.isMet {
            // Only a check that didn't read location can still be waiting for it.
            guard evaluation.locationCouldChangeVerdict else { return .notMet }
            guard fixCouldDecide(check.rule, evaluation: evaluation) else { return .notMet }
            // A fix couldn't help: say so before asking for location.
            guard let used = check.used else { return .unknownUses }
            guard used < usesPerDay else { return .usedUp }
            switch location {
            case .asking: return .askPermission
            case .reading: return .locating
            case .idle: return .needsLocation
            }
        }
        guard let used = check.used else { return .unknownUses }
        guard used < usesPerDay else { return .usedUp }
        guard let cap = lengthCap(maxMinutes: maxMinutes, windowEnd: check.wallWindowEnd, now: now)
        else { return .windowEnding }
        return .met(cap: cap)
    }

    /// A block's check-in (spec §5.2, C3): met when every condition holds
    /// under "all of", or a place/country does under "any of" (a time alone
    /// already blocks on its own, as the rule's own window). The end shown
    /// is the engine's own plan for a start now.
    private static func blockScreen(_ check: CheckInResult, location: CheckInLocationPhase) -> CheckInScreen {
        guard check.clockAgrees else { return .clockChanged }
        let rule = check.rule, evaluation = check.evaluation
        guard evaluation.results.count == rule.conditions.count else { return .notMet }
        let pairs = Array(zip(rule.conditions, evaluation.results))
        let placeMet = pairs.contains { $0.0.usesLocation && $0.1.status == .met }
        if evaluation.isMet && (rule.match == .all || placeMet) {
            if let end = check.blockEnd { return .blockMet(endsAt: end) }
            guard check.blockRefusal == .windowEnded else { return .notMet }
            return check.blockWait > 0 ? .blockWontWait(.windowCloses) : .windowEnding
        }
        if !check.readLocation, fixCouldDecide(rule, evaluation: evaluation) {
            switch location {
            case .asking: return .askPermission
            case .reading: return .locating
            case .idle: return .needsLocation
            }
        }
        if rule.match == .any, let end = pairs.compactMap({ pair -> Date? in
            guard case .time = pair.0, pair.1.status == .met else { return nil }
            return pair.1.windowEnd
        }).max() {
            return .blockOnItsOwn(until: end.addingTimeInterval(-check.guardedOffset))
        }
        return .notMet
    }

    /// Could one fix make this unread check met? Places and countries decide
    /// with a fix (countries through the offline lookup). Day/time/date
    /// results stay as they are. A block's check-in is for its place or
    /// country, so under "any of" a fix can decide it even while a time
    /// branch already blocks on its own.
    static func fixCouldDecide(_ rule: ConditionalRule, evaluation: ConditionalEvaluation,
                               countryLookupAvailable: Bool = countryLookupAvailable) -> Bool {
        if !rule.isFreeTime {
            guard rule.hasLocationCondition, evaluation.results.count == rule.conditions.count else { return false }
            let best: [ConditionStatus] = zip(rule.conditions, evaluation.results).map { condition, result in
                condition.usesLocation ? .met : result.status
            }
            return ConditionEvaluator.verdict(rule, statuses: best,
                                              windowEnds: evaluation.results.map(\.windowEnd)).isMet
        }
        guard rule.isFreeTime, evaluation.locationCouldChangeVerdict,
              evaluation.results.count == rule.conditions.count else { return false }
        let best: [ConditionStatus] = zip(rule.conditions, evaluation.results).map { condition, result in
            switch condition {
            case .place: return .met
            case .country: return countryLookupAvailable ? .met : .unknown
            case .days, .time, .dates: return result.status
            }
        }
        return ConditionEvaluator.verdict(rule, statuses: best,
                                          windowEnds: evaluation.results.map(\.windowEnd)).isMet
    }

    /// What to do after the clock-only check the sheet always runs first.
    /// Never when a fix couldn't change what the sheet says: today's uses
    /// are spent or unknown, or this rule's free time is already on (C8).
    static func locationStep(_ check: CheckInResult, permission: LocationPermission,
                             sessions: [BlockSession], now: Date,
                             pending: [PendingChange] = []) -> CheckInLocationStep {
        if !check.rule.isFreeTime {
            // A block: not while one of this rule runs or waits, nor while
            // the clock is off (the sheet says so first).
            guard !check.readLocation, check.clockAgrees, fixCouldDecide(check.rule, evaluation: check.evaluation),
                  !sessions.contains(where: { $0.conditionalRuleID == check.rule.id && $0.endsAt > now }),
                  RulePending.waitingStart(of: check.rule.id, in: pending) == nil
            else { return .none }
            return permissionStep(permission)
        }
        guard !check.readLocation, fixCouldDecide(check.rule, evaluation: check.evaluation),
              case .freeTime(_, _, _, let usesPerDay) = check.rule.outcome,
              let used = check.used, used < usesPerDay,
              !sessions.contains(where: { $0.conditionalRuleID == check.rule.id && $0.endsAt > now })
        else { return .none }
        return permissionStep(permission)
    }

    private static func permissionStep(_ permission: LocationPermission) -> CheckInLocationStep {
        switch permission {
        case .notAsked: return .ask
        case .denied, .restricted: return .off
        case .allowed: return .read
        }
    }

    /// Only a free-time place needs precise location: a country check never
    /// asks iOS for temporary precise location unless a place in the same
    /// rule does, and a block never does (an approximate fix decides it:
    /// doubt favours the stricter result, spec §5.6).
    static func wantsPrecise(_ rule: ConditionalRule) -> Bool {
        rule.isFreeTime && rule.conditions.contains { if case .place = $0 { return true }; return false }
    }

    /// One more read, asking iOS for temporary precise location, when an
    /// approximate fix left a country "too close to tell" and no place had
    /// asked for precise already (review fix): the same tap, at most once,
    /// and only when a precise fix there could pass (the point is in a
    /// country and more than the 2 km margin from any other).
    static func wantsPreciseRetry(_ result: CheckInResult, outcome: LocationReadOutcome,
                                  country: LocationTrust.CountryAt?) -> Bool {
        guard result.rule.isFreeTime, case .sample(let sample, precise: false) = outcome, !wantsPrecise(result.rule),
              !result.evaluation.isMet, result.evaluation.results.count == result.rule.conditions.count,
              LocationTrust.preciseCouldDecide(sample, country: country) else { return false }
        return zip(result.rule.conditions, result.evaluation.results).contains { condition, row in
            if case .country = condition { return row.reason == .unknown(.nearBorder) }
            return false
        }
    }

    /// Whole minutes a session started now may last: the rule's maximum,
    /// never past the window end. Nil when less than a minute is left (the
    /// engine refuses those starts rather than spend a use).
    static func lengthCap(maxMinutes: Int, windowEnd: Date?, now: Date) -> Int? {
        guard let windowEnd else { return maxMinutes > 0 ? maxMinutes : nil }
        let left = Int(windowEnd.timeIntervalSince(now) / 60)
        let cap = min(maxMinutes, left)
        return cap >= 1 ? cap : nil
    }

    /// When a session of `minutes` started now would end (display only; the
    /// engine sets the real end the same way).
    static func endsAt(minutes: Int, windowEnd: Date?, now: Date) -> Date {
        let end = now.addingTimeInterval(TimeInterval(minutes) * 60)
        guard let windowEnd else { return end }
        return min(end, windowEnd)
    }

    /// The length a start sends: the chosen minutes, within 1…cap.
    static func requestMinutes(chosen: Int, cap: Int) -> Int { max(1, min(chosen, cap)) }

    /// A check is run again, never sent, when it's older than its freshness,
    /// from another day or time zone, or for a rule that changed since.
    static func needsRecheck(_ check: CheckInResult, live: ConditionalRule?,
                             clock: ConditionalClockInput) -> Bool {
        guard let live, live.revision == check.rule.revision, live.sameConfiguration(as: check.rule)
        else { return true }
        let age = clock.guardedNow.timeIntervalSince(check.stamp.guardedAt)
        guard age >= -5, age <= freshness else { return true }
        // The window that allowed it has closed since: the ✓ rows are out of date.
        if let end = check.evaluation.windowEnd, end <= clock.guardedNow { return true }
        return check.stamp.timeZoneID != clock.calendar.timeZone.identifier
            || check.stamp.dayKey != ConditionalUses.dayKey(for: clock.guardedNow, calendar: clock.calendar)
    }

    /// A hold on a check that only aged past its freshness may send the
    /// check run in its place: same rule version, same day and zone, and met
    /// again now. Anything else (midnight, a zone change, an edit) is shown
    /// and needs a new hold.
    static func mayStartAfterRecheck(old: CheckInResult, fresh: CheckInResult, live: ConditionalRule?,
                                     sessions: [BlockSession], now: Date,
                                     pending: [PendingChange] = []) -> Bool {
        fresh.rule.revision == old.rule.revision && fresh.rule.sameConfiguration(as: old.rule)
            && fresh.stamp.dayKey == old.stamp.dayKey && fresh.stamp.timeZoneID == old.stamp.timeZoneID
            && screen(check: fresh, live: live, sessions: sessions, attempt: nil, now: now,
                      pending: pending).canStart
    }

    /// The row a condition shows. A block's place or country is never "not
    /// needed": its check-in is for them, even while a time already holds.
    static func shown(_ result: ConditionResult, condition: ConditionalCondition,
                      rule: ConditionalRule) -> ConditionResult {
        guard !rule.isFreeTime, condition.usesLocation, result.status == .notNeeded else { return result }
        return .unknown(.notChecked)
    }

    /// The length cap a start sends for a screen that can start: free time's
    /// chosen-length cap; 1 for a block (its length is the rule's end).
    static func startCap(_ screen: CheckInScreen) -> Int? {
        switch screen {
        case .met(let cap): return cap
        case .blockMet: return 1
        default: return nil
        }
    }

    // MARK: Words (translation keys and formatted lines)

    static func needsLine(_ rule: ConditionalRule) -> String {
        switch (rule.isFreeTime, rule.match) {
        case (true, .all): return "Free time needs all of these."
        case (true, .any): return "Free time needs any of these."
        case (false, .all): return "The block needs all of these."
        case (false, .any): return "The block needs any of these."
        }
    }

    /// The sentence at the top of the sheet; `until` is already formatted.
    /// `block`: the rule's outcome is a block (refusals say "The block …").
    static func heroKey(_ screen: CheckInScreen, block: Bool = false) -> String {
        switch screen {
        case .checking: return "Checking…"
        case .gone: return "This rule has been removed."
        case .changed: return "This rule changed. Check in again."
        case .running: return "Free time is on until %@."
        case .needsLocation, .askPermission: return "This rule needs your location."
        case .locating: return "Checking…"
        case .met: return "You can have free time now."
        case .usedUp: return "You've used today's free time."
        case .refused, .queued: return block ? "The block didn't start." : "Free time didn't start."
        case .clockChanged, .notMet, .unknownUses, .windowEnding: return "Not right now."
        case .blockMet: return "Block %@ until %@?"
        case .blockRunning: return "The block is on until %@."
        case .blockOnItsOwn: return "This block is on until %@."
        case .blockWaiting: return "The block starts at %@."
        case .blockWontWait(.staleWaiting): return "This block won't start."
        case .blockWontWait: return "Not right now."
        }
    }

    /// The met block's question: "Block 1 app until 07:00?" or, when it runs
    /// its whole length, "Block 1 app for 3 hr?" (true whenever its stricter
    /// wait ends). `endsAt` is already formatted.
    static func blockQuestion(_ check: CheckInResult, endsAt: String, translate: RuleText.Translate,
                              locale: Locale) -> String {
        guard case .block(_, let selection, let until) = check.rule.outcome else { return String() }
        let what = RuleText.counts(RuleCounts(selection), translate: translate)
        if case .duration(let minutes) = until, check.blockRunsFullDuration {
            return String(format: translate("Block %@ for %@?"), what, RuleText.minutes(minutes, locale: locale))
        }
        return String(format: translate("Block %@ until %@?"), what, endsAt)
    }

    /// Under the sheet's sentence after a hold or Confirm landed on a check
    /// that had to be run again.
    static func checkedAgainKey(block: Bool) -> String {
        block ? "Checked again. Review it again to start." : "Checked again. Hold again to start."
    }

    /// One line under the sentence, when the rows don't already say why.
    static func detailKey(_ screen: CheckInScreen, block: Bool = false) -> String? {
        switch screen {
        case .needsLocation: return "Check in again to check where you are."
        case .askPermission: return "Demora checks where you are once, when you tap Check in. It doesn't save or send your location."
        case .clockChanged:
            return block ? "Your clock was changed recently. The block can start once it's set right again."
                : "Your clock was changed recently. Free time can start once it's set right again."
        case .unknownUses: return "Couldn't count today's uses. Try again."
        case .usedUp: return "Resets at midnight"
        case .windowEnding: return "Less than a minute is left in this window."
        case .refused(let refusal): return refusalKey(refusal, block: block)
        case .queued: return "It's waiting in Changes instead."
        case .blockMet, .blockRunning: return "Leaving doesn't end it. Ending it early waits like any looser change."
        case .blockOnItsOwn: return "Its time blocks on its own, without a check-in."
        case .blockWaiting: return "It waits your stricter delay, like Block now. It's in Changes."
        case .blockWontWait(.windowCloses): return "This window closes before your stricter wait ends."
        case .blockWontWait(.ruleChangesFirst): return "A change to this rule lands first. Check in after it lands."
        case .blockWontWait(.staleWaiting): return "Its rule changed while it waited. Cancel it in Changes, then check in again."
        case .checking, .gone, .changed, .running, .met, .notMet, .locating: return nil
        }
    }

    /// Plain copy for every engine refusal (nothing ever reads as success).
    static func refusalKey(_ refusal: ConditionalStartRefusal, block: Bool = false) -> String {
        switch refusal {
        case .ruleMissing: return "This rule has been removed."
        case .ruleChanged: return "This rule changed. Check in again."
        case .clockChanged:
            return block ? "Your clock was changed recently. The block can start once it's set right again."
                : "Your clock was changed recently. Free time can start once it's set right again."
        case .stampStale: return "This check is more than two minutes old. Check in again."
        case .wrongDay: return "A new day started. Check in again."
        case .timeZoneMoved: return "Your time zone changed. Check in again."
        case .conditionsNotMet: return "The conditions aren't met any more."
        case .invalidLength: return "Choose a length this rule allows."
        case .alreadyRunning: return block ? "A block from this rule is already on." : "Free time from this rule is already on."
        case .checkInUsed: return "This check-in was already used. Check in again."
        case .noUsesLeft: return "You've used today's free time."
        case .windowEnded: return "Less than a minute is left in this window."
        case .dueChanges: return "A change is still being applied. Try again in a moment."
        case .unavailable:
            return block ? "The block couldn't start safely. iOS may not be able to track another session right now. Nothing changed."
                : "Free time couldn't start safely. iOS may not be able to track another session right now. Nothing changed."
        }
    }

    /// The reason line under one condition (✓ / ✗ / ? / not needed).
    static func reason(_ result: ConditionResult, condition: ConditionalCondition,
                       translate: RuleText.Translate, locale: Locale, calendar: Calendar) -> String {
        func weekday(_ value: Int) -> String {
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.locale = locale
            let symbols = gregorian.standaloneWeekdaySymbols
            return symbols.indices.contains(value - 1) ? symbols[value - 1] : "\(value)"
        }
        switch result.reason {
        case .atPlace, .notAtPlace:
            guard case .place(let place) = condition else { return String() }
            return String(format: translate(result.reason == .atPlace ? "You're at %@" : "You're not at %@"), place.name)
        case .inCountry, .notInCountry:
            guard case .country(let code) = condition else { return String() }
            return String(format: translate(result.reason == .inCountry ? "You're in %@" : "You're not in %@"),
                          ConditionalText.countryName(code, locale: locale))
        case .onDay(let day), .notOnDay(let day):
            return String(format: translate("It's %@"), weekday(day))
        case .inWindow:
            guard case .time(_, let end) = condition else { return String() }
            return String(format: translate("Until %@"), RuleText.clock(end, locale: locale))
        case .outsideWindow(let minute):
            guard case .time(let start, _) = condition else { return String() }
            return String(format: translate("It's %@; this starts at %@"),
                          RuleText.clock(minute, locale: locale), RuleText.clock(start, locale: locale))
        case .nearPlace:
            guard case .place(let place) = condition else { return String() }
            return String(format: translate("Close enough to %@ to count for a block"), place.name)
        case .nearCountry:
            guard case .country(let code) = condition else { return String() }
            return String(format: translate("Close enough to %@ to count for a block"),
                          ConditionalText.countryName(code, locale: locale))
        case .inDates: return translate("Today is one of these dates")
        case .outsideDates: return translate("Today isn't one of these dates")
        case .notNeeded: return translate("Not needed")
        case .unknown(let why): return translate(unknownKey(why))
        }
    }

    static func unknownKey(_ reason: ConditionalUnknownReason) -> String {
        switch reason {
        case .notChecked: return "Not checked yet"
        case .clockChanged: return "Your clock was changed recently"
        case .timeZoneChanged: return "Your time zone changed recently"
        case .timeZoneUnknown: return "Couldn't read your time zone"
        case .locationOff: return "Location is off for Demora. You can turn it on in Settings."
        case .noFix, .staleFix: return "Couldn't get your location. Try again outside or near a window."
        case .imprecise: return "Location isn't precise enough here"
        case .needsPrecise: return "Needs precise location"
        case .simulated: return "This location looks simulated"
        case .accessory: return "Location from an accessory can't start free time"
        case .nearBorder: return "Too close to a border to tell"
        case .countryUnavailable: return "Couldn't tell which country you're in"
        }
    }

    /// VoiceOver's word for a row's mark.
    static func statusKey(_ status: ConditionStatus) -> String {
        switch status {
        case .met: return "Met"
        case .notMet: return "Not met"
        case .unknown: return "Can't tell"
        case .notNeeded: return "Not needed"
        }
    }
}

// MARK: - Today's Check in rows (spec §5.3)

/// The clock a view read in an event (guarded minus wall, recent zones), so a
/// TimelineView can build a check-in clock each minute without reading the
/// guarded clock while drawing. Display only; the sheet checks for real.
struct ConditionalClockRead: Equatable {
    var guardedOffset: TimeInterval
    var recentTimeZoneIDs: [String]

    func clock(at wallNow: Date, calendar: Calendar) -> ConditionalClockInput {
        ConditionalClockInput(guardedNow: wallNow.addingTimeInterval(guardedOffset), wallNow: wallNow,
                              calendar: calendar, recentTimeZoneIDs: recentTimeZoneIDs)
    }
}

enum ConditionalAvailability {
    struct Row: Equatable {
        let ruleID: UUID
        let name: String
        /// Free time: uses left today. 0 for a block (it has no uses).
        let left: Int
        /// A block rule's row: checking in starts its block (step 6).
        var startsBlock = false
    }

    static let maximumRows = 3

    /// Free-time rules a check-in could start now: uses left (the engine's
    /// count in `used`; unknown → no row), nothing of theirs running, and
    /// either met on day/time/dates alone or a place that one fix could
    /// make true (nothing is read here: the row only opens the check-in), a
    /// country included. Block rules with a place or country get a row when
    /// a fix could start their block now and nothing of theirs runs or waits
    /// (step 6). Rules order; at most three, with how many more.
    static func todayRows(state: LatchState, used: [UUID: Int], clock: ConditionalClockInput,
                          countryLookupAvailable: Bool = ConditionalCheckIn.countryLookupAvailable)
        -> (rows: [Row], more: Int) {
        let rows = state.conditionalRules.compactMap { rule -> Row? in
            if !rule.isFreeTime {
                guard rule.isValid,
                      !state.sessions.contains(where: { $0.conditionalRuleID == rule.id && $0.endsAt > clock.wallNow }),
                      RulePending.waitingStart(of: rule.id, in: state.pending) == nil,
                      ConditionalCheckIn.fixCouldDecide(
                          rule, evaluation: ConditionEvaluator.evaluate(rule, clock: clock, location: .notRead))
                else { return nil }
                return Row(ruleID: rule.id, name: rule.name, left: 0, startsBlock: true)
            }
            guard case .freeTime(_, _, _, let usesPerDay) = rule.outcome, rule.isValid,
                  let count = used[rule.id], count < usesPerDay,
                  !state.sessions.contains(where: { $0.conditionalRuleID == rule.id && $0.endsAt > clock.wallNow })
            else { return nil }
            let evaluation = ConditionEvaluator.evaluate(rule, clock: clock, location: .notRead)
            guard evaluation.isMet || ConditionalCheckIn.fixCouldDecide(
                rule, evaluation: evaluation, countryLookupAvailable: countryLookupAvailable) else { return nil }
            if evaluation.isMet,
               ConditionalCheckIn.lengthCap(maxMinutes: 1, windowEnd: evaluation.windowEnd,
                                            now: clock.guardedNow) == nil { return nil }
            return Row(ruleID: rule.id, name: rule.name, left: usesPerDay - count)
        }
        return (Array(rows.prefix(maximumRows)), max(0, rows.count - maximumRows))
    }
}

// MARK: - When & where location: permission, one fix, trust rules (C8, C9; C15 step 4)

/// Demora's location permission as the check-in and place editor need it.
/// "While Using" only; Demora never asks for Always.
enum LocationPermission: Equatable {
    case notAsked
    case denied
    /// Parental controls or a profile: Settings can't change it here.
    case restricted
    /// `precise` is false under Approximate Location.
    case allowed(precise: Bool)
}

/// One fix as CoreLocation delivered it, before any trust rule. Lives only
/// in memory for the moment it's turned into results or a centre.
struct LocationSample: Equatable {
    var latitude: Double
    var longitude: Double
    /// Metres; iOS reports a negative value for an invalid fix.
    var horizontalAccuracy: Double
    /// When iOS took the fix (wall clock).
    var timestamp: Date
    /// `CLLocationSourceInformation.isSimulatedBySoftware`.
    var isSimulated: Bool
    /// `CLLocationSourceInformation.isProducedByAccessory`.
    var isFromAccessory: Bool
}

enum LocationReadFailure: Equatable {
    case denied, noFix, timedOut, cancelled
}

enum LocationReadOutcome: Equatable {
    case sample(LocationSample, precise: Bool)
    case failed(LocationReadFailure)
}

enum LocationTrust {
    /// One read waits at most this long (spec §5.5 step 4).
    static let timeout: TimeInterval = 15
    /// A place's centre needs a fix at least this good: the smallest place
    /// is 100 m, so a centre can't be off by more than its own size.
    static let maximumCentreAccuracy: Double = 100

    /// Under Approximate Location iOS moves the point by up to several
    /// kilometres; a country is judged as if the fix were at least this
    /// vague, so it can't be told within about 12 km of a border.
    static let approximateAccuracyFloor: Double = 10_000

    /// The offline lookup for one point (`CountryBorders.lookup`), or nil
    /// when the rule has no country (or the bundled borders couldn't load).
    typealias CountryAt = (_ latitude: Double, _ longitude: Double) -> ConditionalCountryLookup?

    /// The accuracy the trust rules use: iOS's own, never better than the
    /// approximate floor when precise location is off.
    static func trustedAccuracy(_ sample: LocationSample, precise: Bool) -> Double {
        precise ? sample.horizontalAccuracy : max(sample.horizontalAccuracy, approximateAccuracyFloor)
    }

    /// The check-in's evaluation input. The engine applies the rest of C9
    /// (age, simulated, accessory, precise, the whole circle inside the
    /// place, accuracy + 2 km from any border for a country). The country is
    /// looked up only for a usable point; the coordinates go no further.
    static func checkInInput(_ outcome: LocationReadOutcome, wallNow: Date,
                             country: CountryAt?) -> ConditionalLocationInput {
        switch outcome {
        case .failed(.denied): return .unavailable(.locationOff)
        case .failed(.noFix), .failed(.timedOut), .failed(.cancelled): return .unavailable(.noFix)
        case .sample(let sample, let precise):
            let usable = sample.latitude.isFinite && sample.longitude.isFinite
                && (-90...90).contains(sample.latitude) && (-180...180).contains(sample.longitude)
            return .fix(ConditionalLocationFix(latitude: sample.latitude, longitude: sample.longitude,
                                               horizontalAccuracy: trustedAccuracy(sample, precise: precise),
                                               age: wallNow.timeIntervalSince(sample.timestamp),
                                               isPrecise: precise, isSimulated: sample.isSimulated,
                                               isFromAccessory: sample.isFromAccessory),
                        country: usable ? country?(sample.latitude, sample.longitude) : nil)
        }
    }

    /// "Use the country I'm in" (spec §5.7): a fresh, real fix (precise not
    /// needed) whose point is clearly inside one country, by the same margin
    /// free time needs (accuracy + 2 km from any border). Anything else is
    /// refused with the check-in's words; nothing is kept but the code.
    static func countryHere(_ outcome: LocationReadOutcome, wallNow: Date,
                            country: CountryAt?) -> Result<String, CountryHereProblem> {
        func refuse(_ reason: ConditionalUnknownReason) -> Result<String, CountryHereProblem> {
            .failure(CountryHereProblem(reason: reason))
        }
        let sample: LocationSample, precise: Bool
        switch outcome {
        case .failed(.denied): return refuse(.locationOff)
        case .failed: return refuse(.noFix)
        case .sample(let value, let isPrecise): sample = value; precise = isPrecise
        }
        let accuracy = trustedAccuracy(sample, precise: precise)
        guard accuracy.isFinite, accuracy > 0, sample.latitude.isFinite, sample.longitude.isFinite,
              (-90...90).contains(sample.latitude), (-180...180).contains(sample.longitude)
        else { return refuse(.noFix) }
        let age = wallNow.timeIntervalSince(sample.timestamp)
        guard age.isFinite, age >= -5, age <= ConditionEvaluator.maximumFixAge else { return refuse(.staleFix) }
        guard !sample.isSimulated else { return refuse(.simulated) }
        guard !sample.isFromAccessory else { return refuse(.accessory) }
        guard let found = country?(sample.latitude, sample.longitude), found.borderDistanceMeters.isFinite,
              found.borderDistanceMeters >= 0 else { return refuse(.countryUnavailable) }
        let clear = found.borderDistanceMeters > accuracy + ConditionEvaluator.borderMargin
        guard let code = found.regionCode else { return refuse(clear ? .countryUnavailable : .nearBorder) }
        return clear ? .success(code) : refuse(.nearBorder)
    }

    /// "Use the country I'm in" reads once more with precise location when
    /// an approximate fix was too close to a border to tell and a precise
    /// one there could pass (review fix).
    static func countryHereWantsPrecise(_ outcome: LocationReadOutcome, result: Result<String, CountryHereProblem>,
                                        country: CountryAt?) -> Bool {
        guard case .sample(let sample, precise: false) = outcome, case .failure(let problem) = result,
              problem.reason == .nearBorder else { return false }
        return preciseCouldDecide(sample, country: country)
    }

    /// A precise fix at this point could clear the margin: it is inside a
    /// country and farther than 2 km from any other (Baarle, North Cyprus or
    /// a point right on a border never get iOS's precise prompt).
    static func preciseCouldDecide(_ sample: LocationSample, country: CountryAt?) -> Bool {
        guard let found = country?(sample.latitude, sample.longitude), found.regionCode != nil else { return false }
        return found.borderDistanceMeters > ConditionEvaluator.borderMargin
    }

    /// A place's centre from "Set to where I am now" (C12): a fresh, precise,
    /// real fix good to 100 m, rounded to 5 decimals (about 1 m). Anything
    /// else is refused with the reason the check-in would give.
    static func centre(_ outcome: LocationReadOutcome, wallNow: Date) -> Result<PlaceCentre, PlaceCentreProblem> {
        let sample: LocationSample, precise: Bool
        switch outcome {
        case .failed(.denied): return .failure(PlaceCentreProblem(reason: .locationOff))
        case .failed: return .failure(PlaceCentreProblem(reason: .noFix))
        case .sample(let value, let isPrecise): sample = value; precise = isPrecise
        }
        let accuracy = sample.horizontalAccuracy
        guard accuracy.isFinite, accuracy > 0, sample.latitude.isFinite, sample.longitude.isFinite,
              (-90...90).contains(sample.latitude), (-180...180).contains(sample.longitude)
        else { return .failure(PlaceCentreProblem(reason: .noFix)) }
        let age = wallNow.timeIntervalSince(sample.timestamp)
        guard age.isFinite, age >= -5, age <= ConditionEvaluator.maximumFixAge
        else { return .failure(PlaceCentreProblem(reason: .staleFix)) }
        guard !sample.isSimulated else { return .failure(PlaceCentreProblem(reason: .simulated)) }
        guard !sample.isFromAccessory else { return .failure(PlaceCentreProblem(reason: .accessory)) }
        guard precise else { return .failure(PlaceCentreProblem(reason: .needsPrecise)) }
        guard accuracy <= maximumCentreAccuracy else { return .failure(PlaceCentreProblem(reason: .imprecise)) }
        return .success(PlaceCentre(latitude: rounded(sample.latitude), longitude: rounded(sample.longitude)))
    }

    static func rounded(_ degrees: Double) -> Double { (degrees * 100_000).rounded() / 100_000 }
}

struct PlaceCentre: Equatable {
    var latitude: Double
    var longitude: Double
}

/// Why "Use the country I'm in" set nothing; same words as the check-in's "?" lines.
struct CountryHereProblem: Error, Equatable {
    var reason: ConditionalUnknownReason

    var messageKey: String {
        switch reason {
        case .accessory: return "Location from an accessory can't set a country"
        default: return ConditionalCheckIn.unknownKey(reason)
        }
    }
}

struct PlaceCentreProblem: Error, Equatable {
    var reason: ConditionalUnknownReason

    /// Same words as the check-in's "?" lines, plus one for the accessory case.
    var messageKey: String {
        switch reason {
        case .accessory: return "Location from an accessory can't set a place"
        default: return ConditionalCheckIn.unknownKey(reason)
        }
    }
}

/// The place editor's choices (spec §5.7, C10–C12).
enum PlaceChoices {
    static let defaultRadius = 250
    /// The only sizes; nothing larger than 2 km (C10).
    static let sizes = ConditionalPlace.radiusChoices

    static func sizeWordsKey(_ meters: Int) -> String {
        switch meters {
        case ...100: return "About a house and its street"
        case ...250: return "A building and its grounds"
        case ...500: return "A campus or a few blocks"
        case ...1000: return "A neighbourhood"
        default: return "A small town centre"
        }
    }

    /// Places in the user's other When & where rules, saved or waiting to be
    /// added or edited, to copy into this one (C11: a copy, never shared).
    /// Same name, centre and size listed once; Rules order.
    static func otherPlaces(state: LatchState, excluding ruleID: UUID?) -> [ConditionalPlace] {
        var rules = state.conditionalRules
        for change in state.pending {
            switch change.action {
            case .addConditionalRule(let rule), .updateConditionalRule(let rule): rules.append(rule)
            default: continue
            }
        }
        var result: [ConditionalPlace] = []
        for rule in rules where rule.id != ruleID {
            for case .place(let place) in rule.conditions where place.isValid && !result.contains(place) {
                result.append(place)
            }
        }
        return result
    }

    /// The editor's place: the name trimmed, a size from the list (C10).
    /// Nil until it has a name and a centre.
    static func place(name: String, centre: PlaceCentre?, radius: Int) -> ConditionalPlace? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let centre, !trimmed.isEmpty, sizes.contains(radius) else { return nil }
        let place = ConditionalPlace(name: trimmed, latitude: centre.latitude, longitude: centre.longitude,
                                     radiusMeters: radius)
        return place.isValid ? place : nil
    }
}

/// The country picker's rows (spec §5.7, Q4): the codes the bundled borders
/// can answer with, named by iOS in the app's language (never by the
/// dataset); a code iOS can't name is left out. Sorted and searched the way
/// the language sorts and matches, ignoring case and accents.
enum CountryChoices {
    struct Choice: Equatable, Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }

    static func list(codes: [String], locale: Locale, query: String = "") -> [Choice] {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let choices = Set(codes).compactMap { code -> Choice? in
            guard code.count == 2, let name = locale.localizedString(forRegionCode: code),
                  !name.isEmpty, name != code else { return nil }
            return Choice(code: code, name: name)
        }
        let matching = wanted.isEmpty ? choices : choices.filter {
            $0.name.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
                || $0.code == wanted.uppercased()
        }
        return matching.sorted {
            let order = $0.name.compare($1.name, options: [.caseInsensitive, .diacriticInsensitive],
                                        range: nil, locale: locale)
            return order == .orderedSame ? $0.code < $1.code : order == .orderedAscending
        }
    }
}
