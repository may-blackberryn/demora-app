#!/usr/bin/env python3
"""Compiles the real Latch/RulesPresentation.swift with the real SharedModels,
SchedulePrecedence and a native driver.

Checks the Rules catalog, pending lines, live state chips, summary lines and
facts, the New rule chooser, editor validation and the draft overlap note
(docs/rules-redesign.md §5, §7), including midnight, monthly and daylight
saving. The lifted pieces (next start, window activity, editor validity) are
checked for equivalence against frozen copies of the old view code.
Only opaque Screen Time tokens and the guarded clock are substituted. No iOS
build, simulator, saved state or Screen Time data is involved.
"""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]


def declaration(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def portable(source):
    return source.replace("import FamilyControls\n", "").replace("import ManagedSettings\n", "")


presentation = (ROOT / 'Latch/RulesPresentation.swift').read_text()
for forbidden in ('import SwiftUI', 'UserDefaults', 'SharedStore', 'TimeGuard', 'tr(',
                  'ChangeEngine', 'FileManager', 'Calendar.current', 'Date()', 'Date.now',
                  'LimitFeatures', 'DayNightWake', 'GlobalWake'):
    assert forbidden not in presentation, ('pure presentation must not use', forbidden)

models = portable((ROOT / 'Shared/SharedModels.swift').read_text())
precedence = portable((ROOT / 'Shared/SchedulePrecedence.swift').read_text())
phrases = declaration((ROOT / 'Shared/PhraseWords.swift').read_text(), 'enum PhraseWords {')

infrastructure = r'''
import Foundation
struct FamilyActivitySelection: Codable, Equatable {
    var includeEntireCategory = false
    var applicationTokens: Set<String> = []
    var categoryTokens: Set<String> = []
    var webDomainTokens: Set<String> = []
}
func tr(_ text: String) -> String { text }
enum TimeGuard {
    static func now() -> Date { fatalError("Rules presentation must not read the guarded clock") }
}
'''

driver = r'''
import Foundation
var checks = 0
func check(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { print("FAIL: " + message); exit(1) }
    checks += 1
}
// The process runs with TZ=America/New_York so Calendar.current is the same
// calendar the lifted view code used.
var ny = Calendar(identifier: .gregorian)
ny.timeZone = TimeZone(identifier: "America/New_York")!
ny.locale = Locale(identifier: "en_US_POSIX")
check(Calendar.current.timeZone.identifier == "America/New_York", "harness time zone")
func at(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    ny.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
}
func apps(_ names: String...) -> FamilyActivitySelection {
    var s = FamilyActivitySelection(); s.applicationTokens = Set(names); return s
}
let en = Locale(identifier: "en_GB")
let us = Locale(identifier: "en_US")
let id = { (s: String) in s }
func change(_ action: ChangeAction, _ direction: ChangeDirection = .lenient,
            applies: Date = at(11, 3, 9)) -> PendingChange {
    PendingChange(createdAt: at(11, 2, 9), appliesAt: applies, direction: direction,
                  summary: "x", action: action)
}

// MARK: Fixtures
var state = LatchState()
let social = AppLimit(name: "Social", selection: { var s = apps("a", "b", "c", "d"); s.categoryTokens = ["c1"]; return s }(),
                      minutesPerDay: 30)
var games = AppLimit(name: "Games", selection: apps("g"), minutesPerDay: 20)
games.weekdayMinutes = [1: 60, 7: 60]
var zero = AppLimit(name: "Zero", selection: apps("z"), minutesPerDay: 0)
var evening = BlockSchedule(name: "Evening block", mode: .blockSelected, selection: apps("x", "y", "z"),
                            startMinutes: 18 * 60, endMinutes: 21 * 60, recurrence: .weekly(Set(2...6)))
var night = BlockSchedule(name: "Night", mode: .blockAllExcept, selection: apps("p", "q"),
                          startMinutes: 22 * 60, endMinutes: 7 * 60, recurrence: .daily)
var monthly = BlockSchedule(name: "Monthly", mode: .blockSelected, selection: apps("m"),
                            startMinutes: 9 * 60, endMinutes: 12 * 60, recurrence: .monthlyDay(15))
let lunch = ExemptSchedule(name: "Lunch", startMinutes: 13 * 60, endMinutes: 14 * 60)
var group = DayNightGroup(); group.name = "Morning"; group.wakeStartMinutes = 7 * 60
group.waitMinutes = 20; group.sleepEnabled = true; group.sleepStartMinutes = 23 * 60
group.scope.limitIDs = [social.id]
let trip = PlannedWindow(name: "Trip", kind: .blockSelected, selection: apps("t"),
                         startsAt: at(11, 7, 9), endsAt: at(11, 8, 18))
let past = PlannedWindow(name: "Past", kind: .free, selection: FamilyActivitySelection(),
                         startsAt: at(11, 1, 9), endsAt: at(11, 1, 10))
let focus = BlockSession(name: "Focus", kind: .block, selection: apps("f"),
                         startedAt: at(11, 2, 16), endsAt: at(11, 2, 18))
let breakSession = BlockSession(name: "Break", kind: .unblock, selection: apps("f"),
                                startedAt: at(11, 2, 16), endsAt: at(11, 2, 17, 30))
let now = at(11, 2, 17)   // Monday 17:00

// MARK: RulePending.index — every rule action maps to its rule
let newLimit = AppLimit(name: "New", selection: apps("n"), minutesPerDay: 10)
let mapped: [(ChangeAction, RuleRef?)] = [
    (.addLimit(newLimit), .limit(newLimit.id)),
    (.configureLimit(social), .limit(social.id)),
    (.updateLimitMinutes(id: social.id, minutes: 5), .limit(social.id)),
    (.updateLimit(id: social.id, selection: apps("a"), minutes: 5), .limit(social.id)),
    (.setGroupWakeDelay(id: social.id, minutes: 5), .limit(social.id)),
    (.setGroupWakeSchedule(id: social.id, minutes: 5, schedule: LimitWakeSchedule()), .limit(social.id)),
    (.removeLimit(id: social.id), .limit(social.id)),
    (.setDelayPolicy(DelayPolicy()), .waits), (.setStrictDelay(60), .waits), (.setLenientDelay(60), .waits),
    (.setWakeRule(WakeBlockRule()), .legacyWake), (.setSleepRule(SleepBlockRule()), .legacySleep),
    (.upsertDayNightGroup(group), .dayNight(group.id)), (.removeDayNightGroup(id: group.id), .dayNight(group.id)),
    (.addSchedule(evening), .schedule(evening.id)),
    (.updateScheduleSelection(id: evening.id, selection: apps("a")), .schedule(evening.id)),
    (.removeSchedule(id: evening.id), .schedule(evening.id)),
    (.addExemption(lunch), .exemption(lunch.id)), (.removeExemption(id: lunch.id), .exemption(lunch.id)),
    (.addPlanned(trip), .planned(trip.id)), (.removePlanned(id: trip.id), .planned(trip.id)),
    (.endSessionEarly(id: focus.id), .session(focus.id)),
    (.setBlockAppRemoval(true), .appDeletion), (.setBlockAdultWebsites(false), .adultWebsites),
    (.addBlockedDomain("a.com"), .websites), (.removeBlockedDomain("a.com"), .websites),
    (.setSchedulePriority(key: "k", prioritized: true), nil),
    (.setMathOverride(enabled: false, difficulty: nil, count: 1, wrong: .nothing), nil),
    (.setPasswordOverride(enabled: false, passwordHash: nil), nil),
    (.removePasswordPolicy(id: UUID()), nil), (.removePhrasePolicy(id: UUID()), nil),
    (.setContactsOverride(enabled: true), nil), (.removeContact(id: UUID()), nil),
    (.setContactPermissions(id: UUID(), allowed: []), nil),
    (.unlockPreventGuide, nil), (.unlockPasswordView, nil),
]
for (action, ref) in mapped {
    check(RulePending.ref(for: change(action)) == ref, "ref for \(action)")
}
let start = change(.startSession(name: "Deep", kind: .block, selection: apps("a"), minutes: 30))
check(RulePending.ref(for: start) == .queuedSession(start.id), "a queued session is its own card")
let early = change(.addBlockedDomain("a.com"), applies: at(11, 3, 8))
let lateDomain = change(.removeBlockedDomain("b.com"), applies: at(11, 3, 10))
let index = RulePending.index([lateDomain, early, change(.removeLimit(id: social.id))])
check(index[.websites]?.id == early.id, "several website changes: the first to land")
check(index[.limit(social.id)] != nil && index.count == 2, "one entry per rule")
check(RulePending.domains([early, lateDomain]).keys.sorted() == ["a.com", "b.com"], "per-domain lines")

// Labels: add vs edit vs remove; day & night upsert of an existing vs a new id.
state.dayNightGroups = [group]
var newGroup = DayNightGroup(); newGroup.name = "Late"
check(RulePending.label(change: change(.removeLimit(id: social.id)), state: state) == .removed, "remove")
check(RulePending.label(change: change(.endSessionEarly(id: focus.id)), state: state) == .removed, "end early")
check(RulePending.label(change: change(.addLimit(newLimit), .stricter), state: state) == .added, "add")
check(RulePending.label(change: start, state: state) == .starts, "session start")
check(RulePending.label(change: change(.configureLimit(social), .lenient), state: state) == .loosens, "looser edit")
check(RulePending.label(change: change(.configureLimit(social), .stricter), state: state) == .tightens, "stricter edit")
check(RulePending.label(change: change(.upsertDayNightGroup(group), .stricter), state: state) == .tightens,
      "existing group: an edit")
check(RulePending.label(change: change(.upsertDayNightGroup(newGroup), .stricter), state: state) == .added,
      "new group: an addition")
check(RulePending.labelKey(.removed) == "Removed in", "label words")
// Edit / Remove blocked by a waiting change (same conflict key; any day & night change).
check(RulePending.blocksEdit(of: .limit(social.id), pending: [change(.setGroupWakeSchedule(
    id: social.id, minutes: 5, schedule: LimitWakeSchedule()))]), "limit: wake edit shares the key")
check(!RulePending.blocksEdit(of: .limit(games.id), pending: [change(.removeLimit(id: social.id))]), "other limit")
check(RulePending.blocksEdit(of: .dayNight(group.id), pending: [change(.upsertDayNightGroup(newGroup))]),
      "day & night: any collection change")
check(RulePending.blocksEdit(of: .legacyWake, pending: [change(.setSleepRule(SleepBlockRule()))]),
      "legacy wake and sleep wait for each other")

// MARK: Catalog
state = LatchState()
check(RuleCatalog.isFirstUse(RuleCatalog.sections(state: state, now: now)), "first use: only Always on")
check(RuleCatalog.sections(state: state, now: now).map(\.section) == [.alwaysOn], "Always on always shown")
state.limits = [social, games]
state.schedules = [night, evening]
state.exemptions = [lunch]
state.dayNightGroups = [group]
state.planned = [trip, past]
state.sessions = [focus, breakSession]
let queuedSchedule = BlockSchedule(name: "Queued", mode: .blockSelected, selection: apps("q"),
                                   startMinutes: 60, endMinutes: 120)
state.pending = [change(.addLimit(newLimit), .stricter), change(.addSchedule(queuedSchedule), .stricter),
                 change(.upsertDayNightGroup(newGroup), .stricter), start]
var sections = RuleCatalog.sections(state: state, now: now)
check(sections.map(\.section) == [.limits, .schedules, .dayNight, .planned, .alwaysOn], "section order")
check(sections[0].cards.map(\.name) == ["Social", "Games", "New"] && sections[0].cards[2].isAddition,
      "limits in saved order, then additions")
check(sections[1].cards.map(\.name) == ["Evening block", "Night", "Lunch", "Queued"],
      "blocks by start, then free periods, then additions")
check(sections[2].cards.map(\.name) == ["Morning", "Late"], "groups, then the new one; no legacy cards")
check(sections[3].cards.map(\.ref) == [.session(breakSession.id), .session(focus.id), .planned(trip.id),
                                       .queuedSession(start.id)], "sessions ending soonest, planned by start, past hidden")
check(!RuleCatalog.isFirstUse(sections), "not first use")
state.wakeRule.enabled = true
sections = RuleCatalog.sections(state: state, now: now)
check(sections[2].cards.suffix(1).map(\.ref) == [.legacyWake], "legacy wake only when not default")
state.sleepRule.startMinutes = 21 * 60
sections = RuleCatalog.sections(state: state, now: now)
check(sections[2].cards.suffix(2).map(\.ref) == [.legacyWake, .legacySleep], "legacy sleep also shows wake")
state.wakeRule = WakeBlockRule(); state.sleepRule = SleepBlockRule()
state.pending.append(change(.setWakeRule(WakeBlockRule())))
check(RuleCatalog.sections(state: state, now: now)[2].cards.last?.ref == .legacyWake, "a pending wake edit keeps its card")
state.pending.removeLast()
var onlyOne = LatchState(); onlyOne.limits = [social]
check(RuleCatalog.sections(state: onlyOne, now: now).map(\.section) == [.limits, .alwaysOn], "one rule, one section")
check(RuleCatalog.source(of: .limit(newLimit.id), state: state) == .waiting(state.pending[0]), "queued addition: waiting")
check(RuleCatalog.source(of: .limit(social.id), state: state) == .live, "saved rule: live")
check(RuleCatalog.source(of: .limit(UUID()), state: state) == .gone, "removed rule: gone")
check(RuleCatalog.source(of: .queuedSession(UUID()), state: state) == .gone, "applied session start: gone")

// MARK: Live chips
func chip(_ ref: RuleRef, at date: Date = now, blocked: Set<UUID> = [], wake: [RuleRef: Date] = [:]) -> RuleChip? {
    RuleChip.live(ref: ref, state: state, blockedLimitIDs: blocked, wakeOpens: wake, now: date, calendar: ny)
}
check(chip(.limit(social.id), blocked: [social.id]) == .blocked, "spent limit: Blocked")
check(chip(.limit(social.id)) == nil, "limit otherwise: no chip (no minutes)")
state.limits.append(zero)
check(chip(.limit(zero.id)) == .blocked, "0-minute limit: Blocked")
check(chip(.limit(games.id), at: at(11, 1, 12)) == nil && chip(.limit(games.id)) == nil, "weekday budgets")
check(chip(.schedule(evening.id), at: at(11, 2, 19)) == .onUntil(at(11, 2, 21)), "block on until")
check(chip(.schedule(evening.id)) == .startsIn(at(11, 2, 18)), "starts within 24 h")
check(chip(.schedule(evening.id), at: at(11, 6, 21, 30)) == nil, "Friday night: next start Monday, no chip")
check(chip(.schedule(night.id), at: at(11, 3, 2)) == .onUntil(at(11, 3, 7)), "midnight-wrapping window")
check(chip(.schedule(night.id), at: at(11, 2, 23)) == .onUntil(at(11, 3, 7)), "evening part of a wrap")
state.schedules.append(monthly)
check(chip(.schedule(monthly.id), at: at(11, 15, 10)) == .onUntil(at(11, 15, 12)), "monthly on its day")
check(chip(.schedule(monthly.id), at: at(11, 14, 10)) == .startsIn(at(11, 15, 9)), "monthly: tomorrow")
check(chip(.schedule(monthly.id), at: at(11, 2, 10)) == nil, "monthly: far away")
check(chip(.exemption(lunch.id), at: at(11, 2, 13, 30)) == .freeUntil(at(11, 2, 14)), "free until")
check(chip(.session(focus.id)) == .onUntil(at(11, 2, 18)), "block session on until")
check(chip(.session(breakSession.id), at: at(11, 2, 16, 30)) == .freeUntil(at(11, 2, 17, 30)),
      "unblock session counts as free")
check(chip(.session(breakSession.id), at: at(11, 2, 17, 45)) == nil, "finished session")
check(chip(.planned(trip.id), at: at(11, 6, 12)) == .startsIn(at(11, 7, 9)), "planned within 24 h")
check(chip(.planned(trip.id), at: at(11, 7, 12)) == .onUntil(at(11, 8, 18)), "planned on")
check(chip(.planned(trip.id)) == nil, "planned far away")
check(chip(.dayNight(group.id), wake: [.dayNight(group.id): at(11, 2, 17, 42)]) == .opens(at(11, 2, 17, 42)),
      "wake gate waiting: Opens")
check(chip(.dayNight(group.id), at: at(11, 3, 1)) == .onUntil(at(11, 3, 7)), "sleep on until wake")
check(chip(.dayNight(group.id)) == .startsIn(at(11, 2, 23)), "sleep starts in")
check(chip(.appDeletion) == .off && chip(.websites) == .off, "always on: Off")
state.blockAppRemoval = true; state.blockedDomains = ["a.com"]
check(chip(.appDeletion) == .on && chip(.websites) == .on, "always on: On")
// Daylight saving: 2026-03-08 is 23 hours in New York.
let dst = BlockSchedule(name: "DST", mode: .blockSelected, selection: apps("d"),
                        startMinutes: 22 * 60, endMinutes: 6 * 60, recurrence: .daily)
state.schedules.append(dst)
let dstNight = chip(.schedule(dst.id), at: at(3, 8, 3, 30))
check(dstNight == .onUntil(at(3, 8, 6)), "spring forward night ends at 6:00 (\(String(describing: dstNight)))")
check(chip(.schedule(dst.id), at: at(3, 8, 21)) == .startsIn(at(3, 8, 22)), "starts in on a DST day")

// MARK: Lifted pieces are equivalent to the old view code
// Old "Coming up" loop (SchedulesView.upcomingItems), frozen copy.
func oldNextStart(_ start: Int, _ recurrence: Recurrence, _ now: Date) -> Date? {
    let cal = Calendar.current
    let weekEnd = cal.date(byAdding: .day, value: 7, to: now) ?? now
    for offset in 0...7 {
        guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
        guard recurrence.matches(dayOf: day) else { continue }
        guard let s = cal.date(bySettingHour: start / 60, minute: start % 60, second: 0, of: day),
              s > now, s < weekEnd else { continue }
        return s
    }
    return nil
}
let recurrences: [Recurrence] = [.daily, .weekly([2, 4, 6]), .weekly([1]), .monthlyDay(3), .monthlyDay(31),
                                 .monthlyOrdinal(weekday: 2, ordinal: 1), .monthlyOrdinal(weekday: 6, ordinal: 4)]
var compared = 0
for recurrence in recurrences {
    for startMinute in [0, 30, 6 * 60, 12 * 60 + 15, 22 * 60, 23 * 60 + 45] {
        for endMinute in [0, 7 * 60, 13 * 60, 23 * 60 + 59] {
            for hour in stride(from: 0, to: 24 * 40, by: 7) {
                let moment = at(2, 25).addingTimeInterval(TimeInterval(hour * 3600 + 17 * 60))
                if endMinute == 0 {
                    check(NextStart.after(now: moment, start: startMinute, recurrence: recurrence, calendar: ny)
                          == oldNextStart(startMinute, recurrence, moment), "next start equivalence")
                }
                check(RuleTimes.matches(recurrence, day: moment, calendar: ny) == recurrence.matches(dayOf: moment),
                      "matches equivalence")
                check((RuleTimes.current(start: startMinute, end: endMinute, recurrence: recurrence,
                                         at: moment, calendar: ny) != nil)
                      == windowActive(at: moment, start: startMinute, end: endMinute, recurrence: recurrence),
                      "window activity equivalence \(recurrence) \(startMinute)-\(endMinute) at \(moment)")
                compared += 1
            }
        }
    }
}

// Old editor predicates (LimitsView / SchedulesView isValid), frozen copies.
func oldLimitValid(name: String, existing: AppLimit?, draft: AppLimit, minutes: Int,
                   extraEnabled: Bool, extraSteps: [LimitExtraStep], o: OverridesConfig) -> Bool {
    let selection = draft.selection
    let hasSelection = !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        || !selection.webDomainTokens.isEmpty
    if extraEnabled && (extraSteps.isEmpty
        || minutes + extraSteps.reduce(0, { $0 + $1.minutes }) > 1439
        || extraSteps.contains(where: { step in
            if [step.passwordPolicyID != nil, step.phrasePolicyID != nil,
                step.contactRequired].filter({ $0 }).count > 1 { return true }
            if step.contactRequired {
                return !o.contactsEnabled || !o.contacts.contains(where: { $0.isUsable && $0.allowed.contains(.extraTime) })
            }
            if let id = step.passwordPolicyID {
                return !o.passwordPolicies.contains(where: { $0.id == id && $0.allowed.contains(.extraTime) })
            }
            if let id = step.phrasePolicyID {
                return !o.phrasePolicies.contains(where: { $0.id == id && $0.allowed.contains(.extraTime) })
            }
            return false
        })) { return false }
    if let existing { return hasSelection && draft != existing }
    return !name.isEmpty && hasSelection
}
var overrides = OverridesConfig()
let pass = PasswordPolicy(name: "Home", hash: "h", allowed: [.extraTime])
let narrow = PasswordPolicy(name: "Other", hash: "h", allowed: [])
overrides.passwordPolicies = [pass, narrow]
var contactOverrides = overrides; contactOverrides.contactsEnabled = true
contactOverrides.contacts = [TrustedContact(name: "Alex", kind: .email("a@b.c"))]
let stepSets: [[LimitExtraStep]] = [
    [], [LimitExtraStep(minutes: 20, waitMinutes: 5)],
    [LimitExtraStep(minutes: 1400, waitMinutes: 5)],
    [LimitExtraStep(minutes: 10, waitMinutes: 5, passwordPolicyID: pass.id)],
    [LimitExtraStep(minutes: 10, waitMinutes: 5, passwordPolicyID: narrow.id)],
    [LimitExtraStep(minutes: 10, waitMinutes: 5, passwordPolicyID: pass.id, contactRequired: true)],
    [LimitExtraStep(minutes: 10, waitMinutes: 5, contactRequired: true)],
    [LimitExtraStep(minutes: 10, waitMinutes: 5, phrasePolicyID: UUID())],
]
var limitCases = 0
for o in [overrides, contactOverrides] {
    for existing in [nil, social] as [AppLimit?] {
        for name in ["", "Name"] {
            for selection in [FamilyActivitySelection(), apps("a"), { var s = FamilyActivitySelection(); s.webDomainTokens = ["w"]; return s }()] {
                for minutes in [0, 30, 50] {
                    for extraEnabled in [false, true] {
                        for steps in stepSets {
                            var draft = existing ?? AppLimit(name: name, selection: selection, minutesPerDay: minutes)
                            draft.selection = selection; draft.minutesPerDay = minutes
                            let problem = EditorValidation.limit(name: name, existing: existing, draft: draft,
                                minutes: minutes, extraEnabled: extraEnabled, extraSteps: steps, overrides: o)
                            check((problem == nil) == oldLimitValid(name: name, existing: existing, draft: draft,
                                minutes: minutes, extraEnabled: extraEnabled, extraSteps: steps, o: o),
                                  "limit validity equivalence")
                            limitCases += 1
                        }
                    }
                }
            }
        }
    }
}
check(EditorValidation.limit(name: "", existing: nil, draft: AppLimit(name: "", selection: FamilyActivitySelection(), minutesPerDay: 5),
      minutes: 5, extraEnabled: false, extraSteps: [], overrides: overrides) == .name, "first problem: the name")
check(EditorValidation.limit(name: "A", existing: nil, draft: AppLimit(name: "A", selection: FamilyActivitySelection(), minutesPerDay: 5),
      minutes: 5, extraEnabled: false, extraSteps: [], overrides: overrides) == .apps, "then the apps")
check(EditorValidation.limit(name: "", existing: social, draft: social, minutes: 30, extraEnabled: false,
      extraSteps: [], overrides: overrides) == .unchanged, "unchanged is not a problem to explain")
check(EditorProblem.unchanged.messageKey == nil && EditorProblem.apps.messageKey == "Choose at least one app.",
      "messages")

func oldScheduleValid(name: String, start: Int, end: Int, recurrence: Recurrence, isFree: Bool,
                      draft: BlockSchedule) -> Bool {
    var monthly = false
    if case .monthlyDay = recurrence { monthly = true }
    if case .monthlyOrdinal = recurrence { monthly = true }
    guard !name.isEmpty, start != end, !(monthly && start >= end) else { return false }
    if case .weekly(let days) = recurrence, days.isEmpty { return false }
    if isFree { return true }
    return draft.acceptsSelection(draft.selection)
}
var scheduleCases = 0
for name in ["", "N"] {
    for (s, e) in [(60, 60), (60, 120), (22 * 60, 60), (0, 0)] {
        for recurrence in recurrences + [.weekly([])] {
            for isFree in [false, true] {
                for mode in ScheduleMode.allCases {
                    for selection in [FamilyActivitySelection(), apps("a")] {
                        let draft = BlockSchedule(name: name, mode: mode, selection: selection,
                                                  startMinutes: s, endMinutes: e, recurrence: recurrence)
                        check((EditorValidation.repeating(name: name, start: s, end: e, recurrence: recurrence,
                                                          isFree: isFree, draft: draft) == nil)
                              == oldScheduleValid(name: name, start: s, end: e, recurrence: recurrence,
                                                  isFree: isFree, draft: draft), "repeating validity equivalence")
                        scheduleCases += 1
                    }
                }
            }
        }
    }
}
check(EditorValidation.repeating(name: "N", start: 60, end: 120, recurrence: .weekly([]), isFree: true,
      draft: queuedSchedule) == .noDays, "no days")
check(EditorValidation.repeating(name: "N", start: 22 * 60, end: 60, recurrence: .monthlyDay(1), isFree: true,
      draft: queuedSchedule) == .monthlyMidnight, "monthly across midnight")

func oldPlannedValid(name: String, kind: PlannedKind, selection: FamilyActivitySelection, s: Date, e: Date) -> Bool {
    guard !name.isEmpty, e > s else { return false }
    return kind != .blockSelected || !(selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty)
}
let webOnly: FamilyActivitySelection = { var x = FamilyActivitySelection(); x.webDomainTokens = ["w"]; return x }()
for name in ["", "N"] {
    for kind in PlannedKind.allCases {
        for selection in [FamilyActivitySelection(), apps("a"), webOnly] {
            for (s, e) in [(at(11, 3), at(11, 4)), (at(11, 4), at(11, 3)), (at(11, 3), at(11, 3))] {
                check((EditorValidation.planned(name: name, kind: kind, selection: selection, startsAt: s, endsAt: e) == nil)
                      == oldPlannedValid(name: name, kind: kind, selection: selection, s: s, e: e),
                      "planned validity equivalence")
            }
        }
    }
}
for kind in [SessionKind.block, .unblock, .free] {
    for selection in [FamilyActivitySelection(), apps("a"), webOnly] {
        let oldDisabled = kind != .free && selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty
        check((EditorValidation.session(kind: kind, selection: selection) != nil) == oldDisabled,
              "session validity equivalence")
    }
}

// MARK: Summary lines
func line(_ ref: RuleRef, _ locale: Locale = en) -> String {
    var calendar = ny; calendar.locale = locale
    return RuleSummaryLine.text(RuleSummaryLine.parts(for: ref, state: state), translate: id,
                                locale: locale, calendar: calendar)
}
check(line(.limit(social.id)) == "30 min a day · 4 apps, 1 category", "limit line (\(line(.limit(social.id))))")
check(line(.limit(games.id)) == "20–60 min a day · 1 app", "weekday range (\(line(.limit(games.id))))")
check(line(.limit(zero.id)) == "Blocked all day · 1 app", "0 minutes")
var richer = social; richer.split = LimitSplit(cutoffMinutes: 720, beforeMinutes: 10, carryUnused: false)
richer.extraTime = LimitExtraTime(minutesPerUse: 10, usesPerDay: 1, waitMinutes: 5)
check(RuleSummaryLine.limitParts(richer).suffix(2) == [.split, .extraTime], "split and extra-time suffixes")
check(line(.schedule(evening.id)) == "Weekdays 18:00–21:00 · only 3 apps", "weekday block (\(line(.schedule(evening.id))))")
let seven = RuleText.clock(7 * 60, locale: en)
check(line(.schedule(night.id)) == "Every day 22:00–\(seven) · all except 2 apps", "all except (\(line(.schedule(night.id))))")
check(line(.schedule(monthly.id)) == "Day 15 of every month \(RuleText.clock(9 * 60, locale: en))–12:00 · only 1 app", "monthly (\(line(.schedule(monthly.id))))")
check(line(.exemption(lunch.id)) == "Every day 13:00–14:00 · free period", "free period")
check(line(.schedule(evening.id), us).contains("6:00") && line(.schedule(evening.id), us).contains("PM"),
      "12-hour locale (\(line(.schedule(evening.id), us)))")
check(line(.dayNight(group.id)) == "Wake \(seven) + \(RuleText.minutes(20, locale: en)) · Sleep 23:00 · Every day", "day & night (\(line(.dayNight(group.id))))")
check(line(.planned(trip.id)).hasPrefix("Sat 7 Nov") && line(.planned(trip.id)).contains("→ Sun")
      && line(.planned(trip.id)).hasSuffix("· only 1 app"), "planned (\(line(.planned(trip.id))))")
check(line(.session(focus.id)) == "Block · 1 app", "session")
check(line(.appDeletion) == "Any app" && line(.adultWebsites) == "Apple's filter" && line(.websites) == "1 site",
      "always on")
check(RuleText.counts(RuleCounts(apps: 2, categories: 0, sites: 3), translate: id) == "2 apps, 3 sites", "counts")
check(RuleText.counts(RuleCounts(), translate: id) == "Nothing selected", "no counts")
check(line(.limit(newLimit.id)) == "10 min a day · 1 app", "queued addition reads its queued action")
var weekCal = ny; weekCal.locale = en; weekCal.firstWeekday = 2
check(RuleText.days(.some([1, 4, 6]), translate: id, calendar: weekCal) == "Wed, Fri, Sun", "app week start orders days")
check(RuleText.days(.weekends, translate: id, calendar: weekCal) == "Weekends", "weekends")

// MARK: Facts
func kinds(_ ref: RuleRef) -> [String] { RuleSummaryFacts.make(ref: ref, state: state).map(\.labelKey) }
check(kinds(.limit(social.id)) == ["How much", "What"], "plain limit facts")
state.limits[0] = richer
check(kinds(.limit(social.id)) == ["How much", "What", "Split", "Extra time"], "split and extra time rows")
var waking = games; waking.wakeDelayMinutes = 10
state.limits[1] = waking
check(kinds(.limit(games.id)).last == "Wake-up", "per-limit wake only when set (R7)")
check(kinds(.schedule(evening.id)) == ["When", "Days", "What"], "weekly block shows day chips")
check(kinds(.schedule(night.id)) == ["When", "What"], "daily block: no chips")
check(kinds(.exemption(lunch.id)) == ["When"], "free period")
check(kinds(.planned(trip.id)) == ["When", "What"], "planned")
check(kinds(.dayNight(group.id)) == ["Wake-up", "Sleep", "Days", "What"], "day & night")
check(kinds(.appDeletion).isEmpty, "always on: explanation only")
if case .what(.dayNight(let except, let names, _)) = RuleSummaryFacts.make(ref: .dayNight(group.id), state: state).last {
    check(!except && names == ["Social"], "day & night names its limits")
} else { check(false, "day & night what") }
check(RuleSummaryFacts.portions(LimitSplit(cutoffMinutes: 720, beforeMinutes: 10, carryUnused: false,
      secondCutoffMinutes: 1080, middleMinutes: 5), total: 30)
      == [.init(untilMinutes: 720, minutes: 10), .init(untilMinutes: 1080, minutes: 5), .init(untilMinutes: nil, minutes: 15)],
      "three portions")
check(RuleSummaryFacts.portions(LimitSplit(cutoffMinutes: 720, beforeMinutes: 50, carryUnused: true), total: 30)
      == [.init(untilMinutes: 720, minutes: 30), .init(untilMinutes: nil, minutes: 0)], "portions clamp")
let phrase = PhrasePolicy(name: "Calm", kind: .random(5), allowed: [.extraTime])
overrides.phrasePolicies = [phrase]
let gates = [LimitExtraStep(minutes: 20, waitMinutes: 5),
             LimitExtraStep(minutes: 10, waitMinutes: 5, passwordPolicyID: pass.id),
             LimitExtraStep(minutes: 10, waitMinutes: 5, phrasePolicyID: phrase.id),
             LimitExtraStep(minutes: 10, waitMinutes: 5, contactRequired: true)]
    .map { ExtraUseBuilder.use($0, overrides: overrides) }
check(gates.map(\.gate) == [.wait(5), .password("Home"), .phrase("Calm"), .contact], "gate kinds")
let words = gates.map { RuleSummaryFacts.gateText($0.gate, translate: id, locale: en) }
check(words[0].hasPrefix("after a 5 min") && words[0].hasSuffix("wait"), "wait wording (\(words[0]))")
check(words[1] == "with the password “Home”" && words[2] == "with the phrase “Calm”"
      && words[3] == "with a trusted contact", "gate wording")
check(RuleSummaryFacts.extraUseText(0, gates[0], translate: id, locale: en).hasPrefix("Use 1 · 20 min"), "use line")

// MARK: Chooser, waits
var full = LatchState()
check(NewRuleKind.allCases.allSatisfy { NewRuleKind.disabledReason($0, state: full) == nil }, "all open")
full.dayNightGroups = (0..<5).map { _ in DayNightGroup() }
check(NewRuleKind.disabledReason(.dayNight, state: full) == "You can have up to five day & night groups.", "five groups")
full.dayNightGroups = []
full.pending = [change(.removeDayNightGroup(id: UUID()))]
check(NewRuleKind.disabledReason(.dayNight, state: full) == "Wait for the day & night change that's already waiting.",
      "a day & night change waits")
check(NewRuleKind.disabledReason(.dailyLimit, state: full) == nil, "others stay open")
let separate = DelayPolicy(mode: .separate, strictDelay: 300, lenientDelay: 86_400)
check(RuleText.waits(separate, translate: id, locale: en) == "Stricter: 5 min · Looser: 1 day",
      "separate (\(RuleText.waits(separate, translate: id, locale: en)))")
check(RuleText.waits(DelayPolicy(mode: .shared, strictDelay: 0, lenientDelay: 86_400), translate: id, locale: en)
      == "Every change: 1 day", "shared")
check(RuleText.waits(DelayPolicy(mode: .lenientOnly, strictDelay: 300, lenientDelay: 3600), translate: id, locale: en)
      == "Stricter: right away · Looser: 1 hr", "lenient only")

// MARK: Draft overlap
var overlapState = LatchState()
overlapState.schedules = [evening]
// Same-kind blocks don't conflict (as on the Conflicts page); an all-except draft does.
let draft = BlockSchedule(name: "Draft", mode: .blockAllExcept, selection: apps("p"),
                          startMinutes: 20 * 60, endMinutes: 22 * 60, recurrence: .weekly([2, 4]))
let notes = DraftOverlap.notes(state: overlapState, draft: draft, now: at(11, 1, 12), calendar: ny)
check(notes.count == 1 && notes[0].name == "Evening block" && notes[0].weekdays == [2, 4],
      "overlaps with Evening block on Mon, Wed (\(notes))")
let apart = BlockSchedule(name: "Apart", mode: .blockAllExcept, selection: apps("x"),
                          startMinutes: 6 * 60, endMinutes: 7 * 60)
check(DraftOverlap.notes(state: overlapState, draft: apart, now: at(11, 1, 12), calendar: ny).isEmpty, "no overlap")
let freeDraft = ExemptSchedule(name: "Free", startMinutes: 19 * 60, endMinutes: 20 * 60)
check(DraftOverlap.notes(state: overlapState, draft: freeDraft, now: at(11, 1, 12), calendar: ny).first?.name
      == "Evening block", "free period draft overlap")

print("Rules presentation passed: \(checks) checks — \(compared) next-start/window comparisons, \(limitCases) limit, \(scheduleCases) repeating drafts; catalog, pending, chips, lines, facts, chooser, waits, overlap")
'''

with tempfile.TemporaryDirectory(prefix='demora-rules-') as directory:
    folder = Path(directory)
    (folder / 'Infrastructure.swift').write_text(infrastructure + '\n' + phrases)
    (folder / 'SharedModels.swift').write_text(models)
    (folder / 'SchedulePrecedence.swift').write_text(precedence)
    (folder / 'RulesPresentation.swift').write_text(portable(presentation))
    (folder / 'main.swift').write_text(driver)
    binary = folder / 'rules'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5',
                    str(folder / 'Infrastructure.swift'), str(folder / 'SharedModels.swift'),
                    str(folder / 'SchedulePrecedence.swift'),
                    str(folder / 'RulesPresentation.swift'), str(folder / 'main.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, env={**os.environ, 'TZ': 'America/New_York'})
