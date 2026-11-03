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
        }
    }
}

enum RuleKind: Equatable {
    case limit, repeatingBlock, freePeriod, dayNight, planned, session, alwaysOn, waits
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

    /// Pending add or remove per website, by lowercased domain.
    static func domains(_ pending: [PendingChange]) -> [String: PendingChange] {
        var result: [String: PendingChange] = [:]
        for change in pending {
            switch change.action {
            case .addBlockedDomain(let domain), .removeBlockedDomain(let domain):
                result[domain.lowercased()] = change
            default:
                continue
            }
        }
        return result
    }

    enum Label: Equatable { case loosens, tightens, removed, added, starts }

    /// "Removed in", "Added in", "Starts in", otherwise by direction.
    static func label(change: PendingChange, state: LatchState) -> Label {
        switch change.action {
        case .removeLimit, .removeSchedule, .removeExemption, .removePlanned,
             .removeDayNightGroup, .endSessionEarly:
            return .removed
        case .startSession:
            return .starts
        case .addLimit, .addSchedule, .addExemption, .addPlanned:
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

    static let upcomingWindow: TimeInterval = 24 * 3600

    /// One chip per card (spec §5.4). `blockedLimitIDs` is the monitor's spent
    /// list and `wakeOpens` the projected wake releases, both read by the view
    /// in event callbacks.
    static func live(ref: RuleRef, state: LatchState, blockedLimitIDs: Set<UUID>,
                     wakeOpens: [RuleRef: Date] = [:], now: Date, calendar: Calendar) -> RuleChip? {
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
        }
    }
}

// MARK: - Catalog

enum RuleSection: Equatable, CaseIterable {
    case limits, schedules, dayNight, planned, alwaysOn

    var titleKey: String {
        switch self {
        case .limits: return "Limits"
        case .schedules: return "Schedules"
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
            default:
                continue
            }
        }

        let limits = state.limits.map { RuleCard(ref: .limit($0.id), name: $0.name) }
        let blocks = state.schedules.enumerated()
            .sorted { ($0.element.startMinutes, $0.offset) < ($1.element.startMinutes, $1.offset) }
            .map { RuleCard(ref: .schedule($0.element.id), name: $0.element.name) }
        let free = state.exemptions.enumerated()
            .sorted { ($0.element.startMinutes, $0.offset) < ($1.element.startMinutes, $1.offset) }
            .map { RuleCard(ref: .exemption($0.element.id), name: $0.element.name) }
        var dayNight = state.dayNightGroups.map { RuleCard(ref: .dayNight($0.id), name: $0.name) }
        dayNight += additions[.dayNight] ?? []
        if hasLegacyWake(state) { dayNight.append(RuleCard(ref: .legacyWake, name: "")) }
        if hasLegacySleep(state) { dayNight.append(RuleCard(ref: .legacySleep, name: "")) }
        let running = state.sessions.filter { $0.endsAt > now }
            .enumerated().sorted { ($0.element.endsAt, $0.offset) < ($1.element.endsAt, $1.offset) }
            .map { RuleCard(ref: .session($0.element.id), name: $0.element.name) }
        let planned = state.planned.filter { $0.endsAt > now }
            .enumerated().sorted { ($0.element.startsAt, $0.offset) < ($1.element.startsAt, $1.offset) }
            .map { RuleCard(ref: .planned($0.element.id), name: $0.element.name) }

        let all: [(RuleSection, [RuleCard])] = [
            (.limits, limits + (additions[.limits] ?? [])),
            (.schedules, blocks + free + (additions[.schedules] ?? [])),
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
        }
    }
}

enum RuleSummaryFacts {
    /// The sheet's fact rows, only those that apply (spec §5.6). `extraLeft` is
    /// today's remaining extra-time uses, read by the view in an event callback.
    static func make(ref: RuleRef, state: LatchState, extraLeft: Int? = nil) -> [RuleFact] {
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
    case dailyLimit, blockNow, repeating, planned, dayNight, website

    /// Why a row can't be chosen, as a translation key; nil when it can.
    static func disabledReason(_ kind: NewRuleKind, state: LatchState) -> String? {
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

    /// Block now. A free period needs no apps; block and unblock do.
    static func session(kind: SessionKind, selection: FamilyActivitySelection) -> EditorProblem? {
        kind != .free && selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty
            ? .apps : nil
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
