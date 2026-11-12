#!/usr/bin/env python3
"""When & where step 2: Rules card, summary sheet and editor presentation.

Compiles the real Latch/RulesPresentation.swift with the real SharedModels and
SchedulePrecedence (as Tests/RulesPresentationHarness.py does) and checks the
When & where parts (docs/conditional-sessions-redesign.md §5.3, §5.4, §5.10):
the pending mapping, the Rules section and its hidden owned windows, the
summary line, the live chip, the summary sheet facts, the New rule and Add
condition choosers, and the editor's first-problem mapping, which must accept
exactly what `ConditionalRule.isValid` (the engine's own check) accepts.
Then source guards for the editor, sheet, Calendar and Conflicts, and the
translations of every new string in the seven tables.

Only opaque Screen Time tokens and the guarded clock are substituted. No iOS
build, simulator, saved state, location or Screen Time data is involved, so
nothing here shows how the screens look on a phone.
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
func check(_ ok: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
    if !ok() { print("FAIL: " + message()); exit(1) }
    checks += 1
}
var mx = Calendar(identifier: .gregorian)
mx.timeZone = TimeZone(identifier: "America/Mexico_City")!
mx.locale = Locale(identifier: "en_GB")
let gb = Locale(identifier: "en_GB")
func at(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    mx.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
}
func apps(_ names: String...) -> FamilyActivitySelection {
    var s = FamilyActivitySelection(); s.applicationTokens = Set(names); return s
}
let say: RuleText.Translate = { $0 }
func change(_ action: ChangeAction, applies: Date = at(11, 20)) -> PendingChange {
    PendingChange(createdAt: at(11, 1), appliesAt: applies, direction: .lenient, summary: "x", action: action)
}
let home = ConditionalPlace(name: "Home", latitude: 19.43, longitude: -99.13, radiusMeters: 250)
let school = ConditionalPlace(name: "School", latitude: 19.40, longitude: -99.10, radiusMeters: 500)

// The owner's three examples (spec §0).
let sunday = ConditionalRule(name: "Sunday in Mexico", match: .all,
    conditions: [.country("MX"), .days([1])],
    outcome: .freeTime(kind: .free, selection: FamilyActivitySelection(), maxMinutes: 60, usesPerDay: 1),
    addedAt: at(11, 1))
let instagram = ConditionalRule(name: "Instagram at home", match: .any,
    conditions: [.place(home), .time(start: 22 * 60, end: 6 * 60)],
    outcome: .block(mode: .blockSelected, selection: apps("instagram"), until: .time(7 * 60)),
    addedAt: at(11, 1))
let weekendSchool = ConditionalRule(name: "School weekend", match: .all,
    conditions: [.place(school), .days([1, 7])],
    outcome: .freeTime(kind: .unblock, selection: apps("a", "b"), maxMinutes: 30, usesPerDay: 2),
    addedAt: at(11, 1))
check(sunday.isValid && instagram.isValid && weekendSchool.isValid, "examples are valid rules")

// MARK: Pending mapping (the three rule actions; a check-in start is not the rule's change)
let edited = { () -> ConditionalRule in var r = sunday; r.name = "Sundays"; return r }()
check(RulePending.ref(for: change(.addConditionalRule(sunday))) == .conditional(sunday.id), "add maps to the rule")
check(RulePending.ref(for: change(.updateConditionalRule(edited))) == .conditional(sunday.id), "update maps to the rule")
check(RulePending.ref(for: change(.removeConditionalRule(id: sunday.id))) == .conditional(sunday.id), "remove maps to the rule")
let stamp = ConditionalCheckInStamp(checkInID: UUID(), guardedAt: at(11, 15, 12), dayKey: "2026-11-15",
                                    timeZoneID: "America/Mexico_City", results: [true, true])
let startRequest = ConditionalStartRequest(ruleID: sunday.id, revision: 0, minutes: 30, stamp: stamp)
check(RulePending.ref(for: change(.startConditionalSession(startRequest))) == nil, "a check-in start has no rule card line")
check(RuleRef.conditional(sunday.id).kind == .conditional, "kind")

var state = LatchState()
state.conditionalRules = [sunday]
check(RulePending.label(change: change(.addConditionalRule(weekendSchool)), state: state) == .added, "add label")
check(RulePending.label(change: change(.removeConditionalRule(id: sunday.id)), state: state) == .removed, "remove label")
check(RulePending.label(change: change(.updateConditionalRule(edited)), state: state) == .loosens, "an edit loosens")
check(RulePending.blocksEdit(of: .conditional(sunday.id), pending: [change(.updateConditionalRule(edited))]), "own edit waits")
check(!RulePending.blocksEdit(of: .conditional(sunday.id), pending: [change(.removeConditionalRule(id: weekendSchool.id))]),
      "another rule's change doesn't lock this one (spec §5.3)")
check(!RulePending.blocksEdit(of: .conditional(sunday.id), pending: [change(.startConditionalSession(startRequest))]),
      "a waiting check-in doesn't lock Edit (different conflict key)")

// MARK: Catalog: section after Schedules, owned windows hidden, queued additions dashed
var catalog = LatchState()
catalog.schedules = [BlockSchedule(name: "Evening", mode: .blockSelected, selection: apps("x"),
                                   startMinutes: 19 * 60, endMinutes: 21 * 60)]
catalog.conditionalRules = [instagram]
catalog.schedules += instagram.ownedSchedules()
check(instagram.ownedSchedules().count == 1, "the any-of time branch is owned")
catalog.pending = [change(.addConditionalRule(sunday))]
let sections = RuleCatalog.sections(state: catalog, now: at(11, 16, 12))
check(sections.map(\.section) == [.schedules, .conditional, .alwaysOn], "order: \(sections.map(\.section))")
check(sections[0].cards.map(\.name) == ["Evening"], "owned window hidden from Schedules: \(sections[0].cards.map(\.name))")
check(sections[1].cards == [RuleCard(ref: .conditional(instagram.id), name: "Instagram at home"),
                            RuleCard(ref: .conditional(sunday.id), name: "Sunday in Mexico", isAddition: true)],
      "saved card then the dashed addition")
var onlyOwned = LatchState()
onlyOwned.conditionalRules = [instagram]
onlyOwned.schedules = instagram.ownedSchedules()
check(RuleCatalog.sections(state: onlyOwned, now: at(11, 16)).map(\.section) == [.conditional, .alwaysOn],
      "a rule's own window never makes a Schedules section")
check(RuleSection.conditional.titleKey == "When & where", "section title")
let ownedID = instagram.ownedSchedules()[0].id
check(RuleCatalog.resolve(.schedule(ownedID), state: onlyOwned, remembered: nil) == .conditional(instagram.id),
      "Today's thread and the Calendar open the owning rule")
check(RuleCatalog.resolve(.schedule(catalog.schedules[0].id), state: catalog, remembered: nil)
      == .schedule(catalog.schedules[0].id), "an ordinary block stays itself")
check(RuleCatalog.source(of: .conditional(instagram.id), state: catalog) == .live, "live")
if case .waiting(let c) = RuleCatalog.source(of: .conditional(sunday.id), state: catalog) {
    check(c.id == catalog.pending[0].id, "waiting addition")
} else { check(false, "queued addition is waiting") }
check(RuleCatalog.source(of: .conditional(UUID()), state: catalog) == .gone, "gone")

// MARK: Summary line (spec §5.3): names only, never distances
func line(_ rule: ConditionalRule, locale: Locale = gb) -> String {
    var s = LatchState(); s.conditionalRules = [rule]
    return RuleSummaryLine.text(RuleSummaryLine.parts(for: .conditional(rule.id), state: s),
                                translate: say, locale: locale, calendar: mx)
}
check(line(sunday) == "In Mexico, on Sun · 1 hr free", line(sunday))
let c = { (m: Int) in RuleText.clock(m, locale: gb) }
check(line(instagram) == "At Home, or \(c(1320))–\(c(360)) · blocks 1 app", line(instagram))
check(line(weekendSchool) == "At School, on weekends · 2 × 30 min unblocked", line(weekendSchool))
check(!line(instagram).contains("250") && !line(instagram).contains("19."), "no size or coordinates on the card")
var everyDay = sunday; everyDay.conditions = [.days(Set(1...7)), .time(start: 9 * 60, end: 17 * 60)]
check(line(everyDay) == "Every day, \(c(540))–\(c(1020)) · 1 hr free", line(everyDay))
var trip = sunday
trip.conditions = [.dates(first: ConditionalDay(year: 2026, month: 12, day: 20),
                          last: ConditionalDay(year: 2026, month: 12, day: 27))]
check(line(trip) == "20 Dec 2026 to 27 Dec 2026 · 1 hr free", line(trip))
check(line(sunday, locale: Locale(identifier: "es_MX")).hasPrefix("In México"), "country name in the app's language")
var queuedOnly = LatchState(); queuedOnly.pending = [change(.addConditionalRule(sunday))]
check(!RuleSummaryLine.parts(for: .conditional(sunday.id), state: queuedOnly).isEmpty, "a queued addition reads its draft")

// MARK: Live chip (spec §5.3): never "conditions met"
func chip(_ rule: ConditionalRule, _ now: Date, used: [UUID: Int], extra: (inout LatchState) -> Void = { _ in }) -> RuleChip? {
    var s = LatchState(); s.conditionalRules = [rule]; s.schedules = rule.ownedSchedules(); extra(&s)
    return RuleChip.live(ref: .conditional(rule.id), state: s, blockedLimitIDs: [], conditionalUsed: used,
                         now: now, calendar: mx)
}
let sundayNoon = at(11, 15, 12), mondayNoon = at(11, 16, 12)
check(mx.component(.weekday, from: sundayNoon) == 1, "15 Nov 2026 is a Sunday")
check(chip(sunday, sundayNoon, used: [sunday.id: 0]) == .usesLeft(1), "1 left today")
check(chip(sunday, sundayNoon, used: [sunday.id: 1]) == .noneLeft, "none left")
check(chip(sunday, sundayNoon, used: [sunday.id: 3]) == .noneLeft, "never negative")
check(chip(sunday, mondayNoon, used: [sunday.id: 0]) == nil, "an all-of day rule that can't hold today shows nothing")
check(chip(sunday, sundayNoon, used: [:]) == nil, "unknown uses show no count, never a guess")
check(chip(weekendSchool, sundayNoon, used: [weekendSchool.id: 1]) == .usesLeft(1), "2 a day, 1 used")
var anyDays = sunday; anyDays.match = .any
check(chip(anyDays, mondayNoon, used: [sunday.id: 0]) == .usesLeft(1), "any-of: the country could still hold")
check(chip(trip, at(11, 15), used: [trip.id: 0]) == nil, "dates not yet")
// Review fix: a same-day window that has ended can't hold again today; one
// that wraps midnight can.
var morning = sunday; morning.conditions = [.days([1]), .time(start: 9 * 60, end: 10 * 60)]
check(chip(morning, at(11, 15, 9, 30), used: [morning.id: 0]) == .usesLeft(1), "inside the window")
check(chip(morning, at(11, 15, 8), used: [morning.id: 0]) == .usesLeft(1), "before it: still today")
check(chip(morning, at(11, 15, 15), used: [morning.id: 0]) == nil, "after a same-day window: nothing")
var night = sunday; night.conditions = [.time(start: 22 * 60, end: 6 * 60)]
check(chip(night, at(11, 15, 15), used: [night.id: 0]) == .usesLeft(1), "a window across midnight is still ahead")
check(ConditionalText.usedForToday(sunday, used: 0, now: mondayNoon, calendar: mx) == nil, "not today: no count for the sheet")
check(ConditionalText.usedForToday(sunday, used: 0, now: sundayNoon, calendar: mx) == 0, "today: the count")
check(ConditionalText.usedForToday(sunday, used: nil, now: sundayNoon, calendar: mx) == nil, "unknown stays unknown")
check(ConditionalText.usedForToday(instagram, used: 0, now: sundayNoon, calendar: mx) == nil, "a block has no uses")
check(chip(trip, at(12, 21, 9), used: [trip.id: 0]) == .usesLeft(1), "inside the dates")
var running = BlockSession(name: "Sunday in Mexico", kind: .free, selection: FamilyActivitySelection(),
                           startedAt: at(11, 15, 12), endsAt: at(11, 15, 13))
running.conditionalRuleID = sunday.id
check(chip(sunday, at(11, 15, 12, 30), used: [sunday.id: 1]) { $0.sessions = [running] } == .freeUntil(at(11, 15, 13)),
      "running free time")
check(chip(sunday, at(11, 15, 13, 1), used: [sunday.id: 1]) { $0.sessions = [running] } == .noneLeft, "after it ended")
var other = running; other.conditionalRuleID = nil
check(chip(sunday, at(11, 15, 12, 30), used: [sunday.id: 0]) { $0.sessions = [other] } == .usesLeft(1),
      "a Block now session isn't this rule's")
check(chip(instagram, at(11, 16, 23), used: [:]) == .onUntil(at(11, 17, 6)), "its night window runs on its own")
check(chip(instagram, at(11, 17, 5), used: [:]) == .onUntil(at(11, 17, 6)), "after midnight, same window")
check(chip(instagram, at(11, 16, 12), used: [:]) == nil, "between windows: nothing (place unknown)")
check(RuleChip.live(ref: .conditional(UUID()), state: LatchState(), blockedLimitIDs: [], now: sundayNoon,
                    calendar: mx) == nil, "gone rule")

// MARK: Summary sheet facts (spec §5.4)
var factState = LatchState(); factState.conditionalRules = [sunday, instagram]
check(RuleSummaryFacts.make(ref: .conditional(sunday.id), state: factState, conditionalUsed: 0)
      == [.conditions(.all, sunday.conditions), .then(sunday.outcome), .usesToday(left: 1, of: 1)], "free facts")
check(RuleSummaryFacts.make(ref: .conditional(sunday.id), state: factState)
      == [.conditions(.all, sunday.conditions), .then(sunday.outcome)], "unknown uses: no Today row")
check(RuleSummaryFacts.make(ref: .conditional(instagram.id), state: factState, conditionalUsed: 0)
      == [.conditions(.any, instagram.conditions), .then(instagram.outcome)], "a block has no Today row")
check(RuleSummaryFacts.make(ref: .conditional(sunday.id), state: queuedOnly, conditionalUsed: 0).count == 2,
      "a waiting addition has no uses yet")
check(RuleFact.conditions(.all, []).labelKey == "If (all of)" && RuleFact.conditions(.any, []).labelKey == "If (any of)"
      && RuleFact.then(sunday.outcome).labelKey == "Then" && RuleFact.usesToday(left: 0, of: 1).labelKey == "Today", "labels")
check(ConditionalText.sheetLine(.place(home), translate: say, locale: gb, calendar: mx) == "At Home · within 250 m",
      ConditionalText.sheetLine(.place(home), translate: say, locale: gb, calendar: mx))
check(ConditionalText.sheetLine(.place(ConditionalPlace(name: "Town", latitude: 0, longitude: 0, radiusMeters: 2000)),
      translate: say, locale: gb, calendar: mx) == "At Town · within 2 km", "km")
check(ConditionalText.sheetLine(.country("MX"), translate: say, locale: gb, calendar: mx) == "In Mexico", "country line")
check(ConditionalText.outcomeLines(sunday.outcome, translate: say, locale: gb)
      == ["Free time, up to 1 hr", "Once a day · everything unblocked"], "\(ConditionalText.outcomeLines(sunday.outcome, translate: say, locale: gb))")
check(ConditionalText.outcomeLines(weekendSchool.outcome, translate: say, locale: gb)
      == ["Free time, up to 30 min", "2 times a day · only 2 apps"], "only these apps")
check(ConditionalText.outcomeLines(instagram.outcome, translate: say, locale: gb) == ["Block only 1 app", "Until \(c(420))"], "block until")
check(ConditionalText.outcomeLines(.block(mode: .blockSelected, selection: apps("a"), until: .duration(minutes: 180)),
      translate: say, locale: gb) == ["Block only 1 app", "For \(RuleText.minutes(180, locale: gb))"], "block for")
check(ConditionKind.allCases.map { ConditionKind.of(ConditionKind.defaultCondition($0, now: sundayNoon, calendar: mx)
      ?? .place(home)) } == [.place, .place, .days, .time, .dates], "defaults round-trip")
check(Set(ConditionKind.allCases.map(\.symbol)) == ["mappin", "globe", "calendar", "clock", "calendar.badge.clock"], "symbols")

// MARK: New rule chooser (spec §5.3): five rules, pending additions count
check(NewRuleKind.allCases.last == .whenWhere, "seventh row")
var four = LatchState()
four.conditionalRules = (0..<4).map { i in var r = sunday; r.id = UUID(); r.name = "R\(i)"; return r }
check(NewRuleKind.disabledReason(.whenWhere, state: four) == nil, "four rules: open")
four.pending = [change(.addConditionalRule(weekendSchool))]
check(NewRuleKind.disabledReason(.whenWhere, state: four) == "You can have up to five When & where rules.", "4 + 1 queued")
check(NewRuleKind.disabledReason(.dailyLimit, state: four) == nil, "others stay open")

// MARK: Add condition chooser: places open (step 4), countries explained, four at most
check(ConditionKind.disabledReason(.place, conditionCount: 0) == nil, "places can be added (step 4)")
check(ConditionKind.disabledReason(.country, conditionCount: 0) == "Arrives in a later update.", "countries later (step 5)")
check([ConditionKind.place, .days, .time, .dates].allSatisfy { ConditionKind.disabledReason($0, conditionCount: 3) == nil }, "open")
check(ConditionKind.allCases.allSatisfy { ConditionKind.disabledReason($0, conditionCount: 4) == "You can add up to four conditions." }, "full")
check(ConditionKind.defaultCondition(.place, now: sundayNoon, calendar: mx) == nil
      && ConditionKind.defaultCondition(.country, now: sundayNoon, calendar: mx) == nil,
      "a place starts in the place editor (it needs a centre); no country yet")
check(ConditionKind.defaultCondition(.days, now: sundayNoon, calendar: mx) == .days([1, 7]), "weekends")
check(ConditionKind.defaultCondition(.time, now: sundayNoon, calendar: mx) == .time(start: 1320, end: 0), "after 22:00")
check(ConditionKind.defaultCondition(.dates, now: at(12, 28, 23, 30), calendar: mx)
      == .dates(first: ConditionalDay(year: 2026, month: 12, day: 28), last: ConditionalDay(year: 2027, month: 1, day: 3)),
      "a week across the year end")
check(ConditionKind.allCases.allSatisfy { k in
    ConditionKind.defaultCondition(k, now: sundayNoon, calendar: mx).map(\.isValid) ?? true }, "defaults are valid")

// MARK: Editor validation (R12): first problem, and exactly the engine's accept set
func problem(_ r: ConditionalRule, existing: ConditionalRule? = nil) -> EditorProblem? {
    EditorValidation.conditional(r, existing: existing)
}
func with(_ base: ConditionalRule, _ change: (inout ConditionalRule) -> Void) -> ConditionalRule {
    var r = base; change(&r); return r
}
check(problem(sunday) == nil, "valid")
check(problem(with(sunday) { $0.name = "  " }) == .name, "name")
check(problem(with(sunday) { $0.name = String(repeating: "a", count: 81) }) == .nameTooLong, "long name")
check(problem(with(sunday) { $0.name = ""; $0.conditions = [] }) == .name, "name comes first")
check(problem(with(sunday) { $0.conditions = [] }) == .noConditions, "no conditions")
check(problem(with(sunday) { $0.conditions = Array(repeating: .days([1]), count: 5) }) == .tooManyConditions, "five")
check(problem(with(sunday) { $0.conditions = [.days([])] }) == .noDays, "no days")
check(problem(with(sunday) { $0.conditions = [.time(start: 600, end: 600)] }) == .sameTimes, "same times")
check(problem(with(sunday) { $0.conditions = [.dates(first: ConditionalDay(year: 2026, month: 12, day: 27),
                                                     last: ConditionalDay(year: 2026, month: 12, day: 20))] }) == .datesOrder, "dates order")
check(problem(with(sunday) { $0.conditions = [.dates(first: ConditionalDay(year: 2026, month: 2, day: 30),
                                                     last: ConditionalDay(year: 2026, month: 3, day: 2))] }) == .invalid, "impossible day")
check(problem(with(sunday) { $0.conditions = [.time(start: -5, end: 60)] }) == .invalid, "out-of-range time")
check(problem(with(sunday) { $0.outcome = .freeTime(kind: .unblock, selection: FamilyActivitySelection(), maxMinutes: 60, usesPerDay: 1) }) == .apps, "only these apps needs apps")
// Step 4: places exist, but a block's check-in start is step 6, so a block rule can't be saved yet.
check(problem(instagram) == .blockLater, "a block with a place waits for step 6")
check(problem(with(instagram) { $0.outcome = .block(mode: .blockSelected, selection: FamilyActivitySelection(), until: .time(420)) }) == .blockLater,
      "…with or without apps")
let dayBlock = with(instagram) { $0.conditions = [.time(start: 1320, end: 360)] }
check(problem(dayBlock) == .blockNeedsPlace, "v1: a block needs a place or country")
// Review fix: what no choice of apps can fix is said first.
check(problem(with(dayBlock) { $0.outcome = .block(mode: .blockSelected, selection: FamilyActivitySelection(), until: .time(420)) })
      == .blockNeedsPlace, "no place before no apps")
check(problem(with(instagram) { $0.conditions.append(.days([1]))
    $0.outcome = .block(mode: .blockSelected, selection: FamilyActivitySelection(), until: .time(420)) }) == .blockAnyOfDays,
      "any-of days before no apps")
check(problem(with(instagram) { $0.conditions.append(.days([1])) }) == .blockAnyOfDays, "v1: any-of block, no days")
check(problem(with(instagram) { $0.match = .all; $0.conditions.append(.days([1])) }) == .blockLater, "all-of block may use days (step 6)")
check(problem(with(instagram) { $0.outcome = .block(mode: .blockAllExcept, selection: apps("a"), until: .time(420)) }) == .blockLater,
      "v1: no all-except block (step 6 says why)")
check(EditorProblem.blockNeedsPlace.messageKey == "Use a repeating block for rules without a place.", "spec §5.10 wording")
check(problem(edited, existing: sunday) == nil, "a real edit")
check(problem(with(sunday) { $0.revision = 4; $0.addedAt = at(1, 1) }, existing: sunday) == .unchanged, "no-op edit")
check(EditorProblem.unchanged.messageKey == nil, "unchanged is not explained")
for p in [EditorProblem.nameTooLong, .noConditions, .tooManyConditions, .datesOrder, .blockNeedsPlace, .blockAnyOfDays, .invalid,
          .blockLater] {
    check(p.messageKey != nil, "message for \(p)")
}

// Exhaustive table: nil ⇔ the engine's isValid.
let d = { (y: Int, m: Int, day: Int) in ConditionalDay(year: y, month: m, day: day) }
let pool: [ConditionalCondition] = [
    .days([1]), .days([]), .days(Set(1...7)), .days([0, 8]), .time(start: 1320, end: 0), .time(start: 600, end: 600),
    .time(start: -1, end: 5), .time(start: 0, end: 1440), .dates(first: d(2026, 12, 20), last: d(2026, 12, 27)),
    .dates(first: d(2026, 12, 27), last: d(2026, 12, 20)), .dates(first: d(2026, 2, 30), last: d(2026, 3, 1)),
    .place(home), .place(ConditionalPlace(name: "X", latitude: 0, longitude: 0, radiusMeters: 300)),
    .place(ConditionalPlace(name: " ", latitude: 0, longitude: 0, radiusMeters: 100)),
    .country("MX"), .country("mx"),
]
var lists: [[ConditionalCondition]] = [[], Array(repeating: .days([1]), count: 4), Array(repeating: .days([1]), count: 5)]
for a in pool { lists.append([a]); for b in pool { lists.append([a, b]) } }
let outcomes: [ConditionalOutcome] = [
    .freeTime(kind: .free, selection: FamilyActivitySelection(), maxMinutes: 60, usesPerDay: 1),
    .freeTime(kind: .free, selection: apps("a"), maxMinutes: 240, usesPerDay: 5),
    .freeTime(kind: .unblock, selection: FamilyActivitySelection(), maxMinutes: 60, usesPerDay: 1),
    .freeTime(kind: .unblock, selection: apps("a"), maxMinutes: 5, usesPerDay: 2),
    .freeTime(kind: .free, selection: FamilyActivitySelection(), maxMinutes: 4, usesPerDay: 1),
    .freeTime(kind: .free, selection: FamilyActivitySelection(), maxMinutes: 60, usesPerDay: 6),
    .freeTime(kind: .block, selection: apps("a"), maxMinutes: 60, usesPerDay: 1),
    .block(mode: .blockSelected, selection: apps("a"), until: .time(420)),
    .block(mode: .blockSelected, selection: FamilyActivitySelection(), until: .time(420)),
    .block(mode: .blockAllExcept, selection: apps("a"), until: .time(420)),
    .block(mode: .blockSelected, selection: apps("a"), until: .duration(minutes: 0)),
    .block(mode: .blockSelected, selection: apps("a"), until: .duration(minutes: 180)),
    .block(mode: .blockSelected, selection: apps("a"), until: .time(1440)),
]
var table = 0, accepted = 0
for name in ["", "Sunday", String(repeating: "n", count: 81)] {
    for match in [ConditionalMatch.all, .any] {
        for conditions in lists {
            for outcome in outcomes {
                let draft = ConditionalRule(name: name, match: match, conditions: conditions, outcome: outcome, addedAt: at(11, 1))
                let p = problem(draft)
                // Step 4: block rules can't be saved until their check-in (step 6).
                if (p == nil) != (draft.isValid && draft.isFreeTime) { print("FAIL: mismatch \(name.count) \(match) \(conditions) \(outcome) → \(String(describing: p))"); exit(1) }
                if p == nil { accepted += 1 }
                table += 1
            }
        }
    }
}
check(table > 20_000 && accepted > 200, "table \(table), accepted \(accepted) (free time only in step 4)")
print("When & where Rules presentation passed: \(checks) checks; validation table \(table) drafts (\(accepted) accepted) matches ConditionalRule.isValid")
'''

with tempfile.TemporaryDirectory(prefix='demora-whenwhere-rules-') as directory:
    folder = Path(directory)
    (folder / 'Infrastructure.swift').write_text(infrastructure + '\n' + phrases)
    (folder / 'SharedModels.swift').write_text(models)
    (folder / 'SchedulePrecedence.swift').write_text(precedence)
    (folder / 'RulesPresentation.swift').write_text(portable(presentation))
    (folder / 'main.swift').write_text(driver)
    binary = folder / 'whenwhere-rules'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5',
                    str(folder / 'Infrastructure.swift'), str(folder / 'SharedModels.swift'),
                    str(folder / 'SchedulePrecedence.swift'),
                    str(folder / 'RulesPresentation.swift'), str(folder / 'main.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, env={**os.environ, 'TZ': 'America/Mexico_City'})

# --- Source guards --------------------------------------------------------
STRING = r'"((?:[^"\\]|\\.)*)"'


def section(text, start, end):
    assert start in text, ('missing', start)
    return text.split(start, 1)[1].split(end, 1)[0]


editor = (ROOT / 'Latch/ConditionalRuleEditor.swift').read_text()
for forbidden in ('model.queue(', 'ChangeEngine.', 'SharedStore', 'TimeGuard', 'CoreLocation', 'CLLocation',
                  'requestLocation', 'UserDefaults', 'LocationCheck', 'readOnce'):
    assert forbidden not in editor, ('the editor only drafts; it never queues, reads location or storage', forbidden)
# Step 4: a place is set in its own sheet, which alone reads location; the
# editor only receives the finished place.
assert 'PlaceEditor(initial: request.place, ruleID: ruleID)' in editor
add = declaration(editor, 'private func addChosen()')
assert add.index('if kind == .place {\n            placeEditing = PlaceEditRequest(conditionID: nil, place: nil)') \
    < add.index('ConditionKind.defaultCondition(kind'), 'a new place opens the place editor'
set_place = declaration(editor, 'private func setPlace(_ place: ConditionalPlace, conditionID: UUID?)')
assert 'guard let index = conditions.firstIndex(where: { $0.id == conditionID }) else { return }' in set_place, \
    'a card removed while its place editor was open stays removed'
assert 'conditions.count < ConditionalRule.maximumConditions' in set_place
review = declaration(editor, 'private func review()')
assert 'guard canReview else { return }' in review
assert ('ChangeReceiptRequest(action: existing == nil ? .addConditionalRule(draft)\n'
        '                                                               : .updateConditionalRule(draft))') in review, review
assert '_addedAt = State(initialValue: Date())' in editor
assert 'addedAt: existing?.addedAt ?? addedAt, revision: existing?.revision ?? 0' in editor
assert 'problem == nil && !waiting && !changedUnderneath && (existing == nil || current != nil)' in editor, 'stale or waiting edits never review'
assert 'EditorValidation.conditional(draft, existing: current ?? existing)' in editor
assert 'waiting: waiting, onReview: review' in editor
# Review fixes: bindings by ID (no index-based ForEach($conditions)), a stale
# editor can't silently revert a landed edit, Cancel asks for every change.
assert 'ForEach($conditions)' not in editor and 'ConditionEditorCard(condition: binding(for: item.id), onEditPlace:' in editor
binding_src = declaration(editor, 'private func binding(for id: UUID)')
assert 'guard let index = conditions.firstIndex(where: { $0.id == id }) else { return }' in binding_src
assert '!changedUnderneath' in editor and 'return !current.sameConfiguration(as: existing)' in editor
assert "match != .all" in editor and 'endChoice != .time' in editor
assert 'ConditionKind.defaultCondition(kind' in editor and 'conditions.count < ConditionalRule.maximumConditions' in editor

sheet = (ROOT / 'Latch/RuleSummarySheet.swift').read_text()
actions = section(sheet, 'case .conditional(let id):\n                if let rule', 'case .queuedSession, .waits:')
# Step 3 switched Check in on (Tests/WhenWhereCheckInHarness.py checks the flow).
assert 'primary(tr("Check in")) { editor = .checkIn(id) }' in actions and '.disabled(true)' not in actions, 'Check in is on'
assert 'secondary(tr("Edit")) { editor = .conditional(rule) }.disabled(blocked)' in actions
assert 'receipt = ChangeReceiptRequest(action: .removeConditionalRule(id: id)) }\n                        .disabled(blocked)' in actions
assert 'case .conditional(let rule): ConditionalRuleEditor(existing: rule)' in sheet
# Review fixes: the sheet counts like the chip, follows an owned window's rule
# across a time edit, and both screens re-read uses when the day changes.
assert 'ConditionalText.usedForToday(rule, used: conditionalUsed[id], now: now, calendar: calendar)' in sheet
assert 'if case .schedule = requested, let owner = rememberedOwner { return .conditional(owner) }' in sheet
assert 'rememberedOwner = owner' in sheet
rules_view = (ROOT / 'Latch/RulesView.swift').read_text()
assert 'case .whenWhere: ConditionalRuleEditor(existing: nil)' in rules_view
reads = section(rules_view, 'enum RuleLiveReads {', '\n}\n')
assert 'ConditionalClockInput.current(for: state, guardedNow: guarded, wallNow: now).dayKeys' in reads
assert 'ConditionalUses.used(ruleID: rule.id, dayKeys: keys' in reads, 'the engine’s own count'
assert 'conditionalUsed: conditionalUsed' in rules_view and 'conditionalUsed: conditionalUsed' in sheet
for source in (rules_view, sheet):
    assert '.onChange(of: ConditionalUses.dayKey(for: context.date, calendar: .current))' in source
    assert 'readDay = ConditionalUses.dayKey(for: Date(), calendar: .current)' in source
conflicts = (ROOT / 'Latch/ScheduleConflictsView.swift').read_text()
assert '.filter { !isRuleOwned($0, state: model.state) }' in conflicts, 'owned windows have no priority row'
assert '&& !isRuleOwned(key, state: model.state)' in conflicts, 'nor a reviewable priority change'
calendar_src = (ROOT / 'Latch/SchedulesView.swift').read_text()
assert 'ref: s.ownerRuleID.map { RuleRef.conditional($0) } ?? .schedule(s.id)' in calendar_src
# Step 4: CoreLocation is confined to the host's one-shot reader, used only
# by the check-in and place sheets (Tests/WhenWhereLocationHarness.py).
for path in (ROOT / 'Latch').glob('*.swift'):
    text = path.read_text()
    if path.name != 'LocationCheck.swift':
        assert 'import CoreLocation' not in text, ('CoreLocation only in LocationCheck.swift', path.name)
    if path.name not in ('LocationCheck.swift', 'CheckInSheet.swift', 'PlaceEditor.swift'):
        assert 'LocationCheck()' not in text, ('location is read only from Check in or Set to where I am now', path.name)
print('When & where source guards passed: receipt-only editor, places through the place sheet, Check in on, owned windows')

# --- Translations of every When & where string ---------------------------
keys = set()
for name in ('Latch/ConditionalRuleEditor.swift', 'Latch/RuleSummarySheet.swift', 'Latch/RulesView.swift',
             'Latch/PlaceEditor.swift'):
    for call in re.findall(r'\btr\((?:[^()"]|"(?:[^"\\]|\\.)*")*\)', (ROOT / name).read_text()):
        keys.update(re.findall(STRING, call))
kinds = section(presentation, 'enum ConditionKind: CaseIterable, Equatable {', '\n}\n')
keys.update(k for k in re.findall(r'return ' + STRING, kinds))
words = section(presentation, 'enum ConditionalText {', '\n}\n')
keys.update(re.findall(r'translate\(' + STRING + r'\)', words))
problems = section(presentation, 'var messageKey: String? {', '\n    }\n')
keys.update(re.findall(r'return ' + STRING, problems))
keys.update(['If (all of)', 'If (any of)', 'Then', 'When & where', 'Check in',
             'Remove rule', '%d of %d left', 'None left today', '%d left today',
             'Free time or a block that depends on place, day or time', 'You can have up to five When & where rules.'])
for key in ('If (all of)', 'If (any of)', 'None left today'):
    assert f'"{key}"' in presentation + sheet + rules_view, key
assert len(keys) > 60, len(keys)
TABLES = {'es': '', 'de': '+German', 'fr': '+French', 'pt': '+Portuguese',
          'pl': '+Polish', 'tr': '+Turkish', 'hi': '+Hindi'}
entry = re.compile(r'^\s*' + STRING + r'\s*:\s*' + STRING + r',?\s*$', re.M)
for code, suffix in TABLES.items():
    pairs = entry.findall((ROOT / f'Shared/Localization{suffix}.swift').read_text())
    seen = [k for k, _ in pairs]
    duplicates = sorted({k for k in seen if seen.count(k) > 1})
    assert not duplicates, (code, 'duplicate keys crash the dictionary literal', duplicates)
    table = dict(pairs)
    missing = sorted(k for k in keys if k not in table)
    assert not missing, (code, 'untranslated', missing)
    for key in keys:
        for spec in ('%@', '%d'):
            assert key.count(spec) == table[key].count(spec), (code, key, spec)
        assert table[key].strip(), (code, key, 'empty')
hindi = (ROOT / 'Shared/Localization+Hindi.swift').read_text()
assert not re.search(r'[一-鿿]', hindi), 'no stray CJK characters in the Hindi table'
print(f'When & where translations passed: {len(keys)} strings × 7 tables')
