#!/usr/bin/env python3
"""When & where step 3: the check-in sheet's decisions and Today's Check in rows.

Compiles the real Latch/RulesPresentation.swift with the real SharedModels and
SchedulePrecedence (as Tests/WhenWhereRulesHarness.py does) and checks
(docs/conditional-sessions-redesign.md §5.3, §5.5, §5.6):
- what the sheet says for every state: met (with its length cap), not met,
  needs location, clock changed, used up, window ending, running, changed,
  removed, and every engine refusal (never shown as success);
- that the stamp the sheet builds is exactly what the engine's own
  `ConditionalStart.plan` accepts, and that the sheet re-checks (never sends)
  a check that is stale, from before midnight, from another zone, or for a
  rule that changed;
- a reason line for every `ConditionReason` and unknown reason;
- `ConditionalAvailability.todayRows` and the Planned/session mapping.
Then source guards (one start in flight, no override path, no location, Check
in on, End early through the receipt) and the translations of every new
string in the seven tables.

Only opaque Screen Time tokens and the guarded clock are substituted (the
clock is passed in, as the views read it in events). No iOS build, simulator,
saved state, location or Screen Time data is involved, so nothing here shows
how the sheet looks or that a session really starts on a phone.
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
    static func now() -> Date { fatalError("check-in presentation must not read the guarded clock") }
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
let gb = Locale(identifier: "en_GB")
var mxText = mx
mxText.locale = gb
func at(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
    mx.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min, second: s))!
}
func apps(_ names: String...) -> FamilyActivitySelection {
    var s = FamilyActivitySelection(); s.applicationTokens = Set(names); return s
}
let say: RuleText.Translate = { $0 }
let none = FamilyActivitySelection()
func free(_ name: String, _ match: ConditionalMatch, _ conditions: [ConditionalCondition],
          max: Int = 60, uses: Int = 1) -> ConditionalRule {
    ConditionalRule(name: name, match: match, conditions: conditions,
                    outcome: .freeTime(kind: .free, selection: none, maxMinutes: max, usesPerDay: uses),
                    addedAt: at(11, 1))
}
func clock(_ wall: Date, guarded: Date? = nil, zones: [String] = ["America/Mexico_City"]) -> ConditionalClockInput {
    ConditionalClockInput(guardedNow: guarded ?? wall, wallNow: wall, calendar: mx, recentTimeZoneIDs: zones)
}
func stateWith(_ rules: [ConditionalRule]) -> LatchState {
    var s = LatchState(); s.conditionalRules = rules; return s
}
func screen(_ rule: ConditionalRule, _ wall: Date, state: LatchState? = nil, guarded: Date? = nil,
            attempt: CheckInAttempt? = nil, live: ConditionalRule?? = nil) -> CheckInScreen {
    let s = state ?? stateWith([rule])
    let result = CheckInResult.make(rule: rule, state: s, clock: clock(wall, guarded: guarded), location: .notRead)
    return ConditionalCheckIn.screen(check: result, live: live ?? rule, sessions: s.sessions,
                                     attempt: attempt, now: wall)
}
let home = ConditionalPlace(name: "Home", latitude: 19.43, longitude: -99.13, radiusMeters: 250)
let sundays = free("Sundays", .all, [.days([1])])
let everyDayRule = free("Every day", .all, [.days(Set(1...7))])
let lateSunday = free("Late Sunday", .all, [.days([1]), .time(start: 22 * 60, end: 0)])
let mexicoSunday = free("Sunday in Mexico", .all, [.country("MX"), .days([1])])
let mexicoOrSunday = free("Mexico or Sunday", .any, [.country("MX"), .days([1])])
let block = ConditionalRule(name: "Instagram at home", match: .any,
    conditions: [.place(home), .time(start: 22 * 60, end: 6 * 60)],
    outcome: .block(mode: .blockSelected, selection: apps("instagram"), until: .time(7 * 60)), addedAt: at(11, 1))
let sundayNoon = at(11, 15, 12), mondayNoon = at(11, 16, 12)
check(mx.component(.weekday, from: sundayNoon) == 1, "15 Nov 2026 is a Sunday")

// MARK: Met → the engine's own plan accepts the sheet's stamp
check(screen(sundays, sundayNoon) == .met(cap: 60), "\(screen(sundays, sundayNoon))")
let sundayState = stateWith([sundays])
let met = CheckInResult.make(rule: sundays, state: sundayState, clock: clock(sundayNoon), location: .notRead)
check(met.used == 0 && met.clockAgrees && met.evaluation.isMet, "check facts")
check(met.stamp.results == [true] && met.stamp.dayKey == "2026-11-15", "stamp: booleans and day only")
func request(_ r: CheckInResult, minutes: Int) -> ConditionalStartRequest {
    ConditionalStartRequest(ruleID: r.rule.id, revision: r.rule.revision, minutes: minutes, stamp: r.stamp)
}
if case .success(let plan) = ConditionalStart.plan(request(met, minutes: 45), state: sundayState,
                                                    clock: clock(sundayNoon.addingTimeInterval(30))) {
    check(plan.session.endsAt == sundayNoon.addingTimeInterval(30 + 45 * 60), "45 min from the start")
    check(plan.session.conditionalRuleID == sundays.id && plan.session.kind == .free, "a free session of this rule")
} else { check(false, "the engine accepts a fresh met check") }
// A length above the cap is clamped before it's sent (DurationPicker can overshoot).
check(ConditionalCheckIn.requestMinutes(chosen: 90, cap: 60) == 60 && ConditionalCheckIn.requestMinutes(chosen: 0, cap: 60) == 1,
      "request length within 1…cap")

// Window caps: a Sunday 22:00–00:00 rule at 23:30 caps at 30 min and ends at midnight.
check(screen(lateSunday, at(11, 15, 23, 30)) == .met(cap: 30), "\(screen(lateSunday, at(11, 15, 23, 30)))")
let late = CheckInResult.make(rule: lateSunday, state: stateWith([lateSunday]), clock: clock(at(11, 15, 23, 30)), location: .notRead)
check(ConditionalCheckIn.endsAt(minutes: 60, windowEnd: late.wallWindowEnd, now: at(11, 15, 23, 30)) == at(11, 16),
      "ends at the window end, not after it")
check(ConditionalCheckIn.endsAt(minutes: 10, windowEnd: late.wallWindowEnd, now: at(11, 15, 23, 30)) == at(11, 15, 23, 40),
      "a shorter choice ends on its own")
check(screen(lateSunday, at(11, 15, 23, 59, 30)) == .windowEnding, "under a minute left: no start")
check(screen(lateSunday, at(11, 15, 21)) == .notMet, "before the window")
check(ConditionalCheckIn.lengthCap(maxMinutes: 60, windowEnd: nil, now: sundayNoon) == 60, "no window: the maximum")
check(ConditionalCheckIn.lengthCap(maxMinutes: 60, windowEnd: sundayNoon.addingTimeInterval(59), now: sundayNoon) == nil,
      "under a minute: nil")
check(ConditionalCheckIn.lengthCap(maxMinutes: 60, windowEnd: sundayNoon.addingTimeInterval(125), now: sundayNoon) == 2,
      "whole minutes, rounded down")
// The window end is placed on the wall clock (guarded 90 s ahead).
let skewed = CheckInResult.make(rule: lateSunday, state: stateWith([lateSunday]),
                                clock: clock(at(11, 15, 23, 30), guarded: at(11, 15, 23, 31, 30)), location: .notRead)
check(skewed.wallWindowEnd == at(11, 15, 23, 58, 30), "window end on the wall clock")

// MARK: Not met, needs location, clock changed, used up
check(screen(sundays, mondayNoon) == .notMet, "Monday")
let monday = CheckInResult.make(rule: sundays, state: sundayState, clock: clock(mondayNoon), location: .notRead)
check(ConditionalCheckIn.reason(monday.evaluation.results[0], condition: .days([1]), translate: say,
      locale: gb, calendar: mxText) == "It's Monday", "✗ It's Monday")
check(ConditionalCheckIn.reason(met.evaluation.results[0], condition: .days([1]), translate: say,
      locale: gb, calendar: mxText) == "It's Sunday", "✓ It's Sunday")
check(screen(mexicoSunday, sundayNoon) == .arrivesLater(.country), "all of: day met, country unchecked until step 5")
let mexico = CheckInResult.make(rule: mexicoSunday, state: stateWith([mexicoSunday]), clock: clock(sundayNoon), location: .notRead)
check(mexico.evaluation.results.map(\.status) == [.unknown, .met], "country ?, day ✓")
check(ConditionalCheckIn.reason(mexico.evaluation.results[0], condition: .country("MX"), translate: say,
      locale: gb, calendar: mxText) == "Arrives in a later update.", "country later (step 5)")
check(screen(mexicoSunday, mondayNoon) == .notMet, "all of: the day already fails, location not needed")
let mexicoMonday = CheckInResult.make(rule: mexicoSunday, state: stateWith([mexicoSunday]), clock: clock(mondayNoon), location: .notRead)
check(ConditionalCheckIn.reason(mexicoMonday.evaluation.results[0], condition: .country("MX"), translate: say,
      locale: gb, calendar: mxText) == "Not needed", "not needed")
check(screen(mexicoOrSunday, sundayNoon) == .met(cap: 60), "any of: the day is enough")
check(screen(mexicoOrSunday, mondayNoon) == .arrivesLater(.country), "any of: only the country could make it true")
check(screen(block, at(11, 15, 23)) == .arrivesLater(.block), "a block's check-in arrives later, even inside its window")
check(!ConditionalCheckIn.countryLookupAvailable, "countries arrive in step 5")
check(screen(sundays, sundayNoon, guarded: sundayNoon.addingTimeInterval(-400)) == .clockChanged, "clock changed")
if case .failure(let refusal) = ConditionalStart.plan(
    request(CheckInResult.make(rule: sundays, state: sundayState, clock: clock(sundayNoon, guarded: sundayNoon.addingTimeInterval(-400)), location: .notRead), minutes: 30),
    state: sundayState, clock: clock(sundayNoon, guarded: sundayNoon.addingTimeInterval(-400))) {
    check(refusal == .clockChanged, "engine agrees: \(refusal)")
} else { check(false, "engine refuses a changed clock") }
var spent = sundayState
spent.conditionalUses = ConditionalUses.recording(ruleID: sundays.id, dayKeys: ["2026-11-15"], checkInID: UUID(),
                                                  at: sundayNoon.addingTimeInterval(-600), in: [])
check(screen(sundays, sundayNoon, state: spent) == .usedUp, "used up")
check(screen(sundays, mondayNoon, state: spent) == .notMet, "not met beats used up")
let twice = free("Twice", .all, [.days([1])], max: 30, uses: 2)
var once = stateWith([twice])
once.conditionalUses = ConditionalUses.recording(ruleID: twice.id, dayKeys: ["2026-11-15"], checkInID: UUID(),
                                                 at: sundayNoon.addingTimeInterval(-3600), in: [])
check(screen(twice, sundayNoon, state: once) == .met(cap: 30), "second of two")
check(CheckInResult.make(rule: twice, state: once, clock: clock(sundayNoon), location: .notRead).used == 1, "one used")
let badZones = CheckInResult.make(rule: sundays, state: sundayState,
                                  clock: clock(sundayNoon, zones: ["America/Mexico_City", "Not/AZone"]), location: .notRead)
check(badZones.used == nil, "unresolvable zones: uses unknown")
check(ConditionalCheckIn.screen(check: badZones, live: sundays, sessions: [], attempt: nil, now: sundayNoon) == .notMet,
      "…and the day reads ?, so not met: \(ConditionalCheckIn.screen(check: badZones, live: sundays, sessions: [], attempt: nil, now: sundayNoon))")

// MARK: Running, removed, changed
var running = BlockSession(name: "Sundays", kind: .free, selection: none,
                           startedAt: sundayNoon, endsAt: sundayNoon.addingTimeInterval(3600))
running.conditionalRuleID = sundays.id
var withSession = spent; withSession.sessions = [running]
check(screen(sundays, sundayNoon.addingTimeInterval(60), state: withSession) == .running(until: running.endsAt), "running")
check(screen(sundays, sundayNoon.addingTimeInterval(3700), state: withSession) == .usedUp, "after it ended")
var blockNow = running; blockNow.id = UUID(); blockNow.conditionalRuleID = nil
var unrelated = sundayState; unrelated.sessions = [blockNow]
check(screen(sundays, sundayNoon.addingTimeInterval(60), state: unrelated) == .met(cap: 60), "another session isn't this rule's")
check(ConditionalCheckIn.screen(check: met, live: nil, sessions: [], attempt: nil, now: sundayNoon) == .gone, "removed")
check(ConditionalCheckIn.screen(check: nil, live: sundays, sessions: [], attempt: nil, now: sundayNoon) == .checking, "not checked yet")
var edited = sundays; edited.revision = 1
check(ConditionalCheckIn.screen(check: met, live: edited, sessions: [], attempt: nil, now: sundayNoon) == .changed,
      "an edit that landed makes the check stale")
var renamed = sundays; renamed.name = "Sundays!"
check(ConditionalCheckIn.screen(check: met, live: renamed, sessions: [], attempt: nil, now: sundayNoon) == .changed, "same revision, other config")

// MARK: Attempts: a refusal is never success
let refusals: [ConditionalStartRefusal] = [.ruleMissing, .ruleChanged, .clockChanged, .stampStale, .wrongDay,
    .timeZoneMoved, .conditionsNotMet, .invalidLength, .alreadyRunning, .checkInUsed, .noUsesLeft,
    .windowEnded, .dueChanges, .unavailable]
for refusal in refusals {
    let s = ConditionalCheckIn.screen(check: met, live: sundays, sessions: [], attempt: .refused(refusal), now: sundayNoon)
    check(s == .refused(refusal) && !s.canStart, "refused \(refusal) → \(s)")
    check(ConditionalCheckIn.heroKey(s) == "Free time didn't start.", "hero for \(refusal)")
    check(ConditionalCheckIn.detailKey(s) == ConditionalCheckIn.refusalKey(refusal) && !ConditionalCheckIn.refusalKey(refusal).isEmpty,
          "detail for \(refusal)")
}
check(Set(refusals.map(ConditionalCheckIn.refusalKey)).count >= 12, "refusals read differently")
check(ConditionalCheckIn.screen(check: met, live: sundays, sessions: [], attempt: .waiting, now: sundayNoon) == .queued,
      "an unexpected queued start isn't shown as free time")
check(ConditionalCheckIn.heroKey(.queued) == "Free time didn't start.", "queued wording")
let until = sundayNoon.addingTimeInterval(1800)
// Review fix: only saved state says free time is on (a start ended elsewhere doesn't linger).
var started = running; started.endsAt = until
check(ConditionalCheckIn.screen(check: met, live: sundays, sessions: [started], attempt: .started(until: until), now: sundayNoon)
      == .running(until: until), "started and saved")
check(ConditionalCheckIn.screen(check: met, live: sundays, sessions: [], attempt: .started(until: until), now: sundayNoon)
      != .running(until: until), "started but no longer in saved state: not shown as running")
check(ConditionalCheckIn.screen(check: met, live: sundays, sessions: [], attempt: .started(until: until),
      now: until.addingTimeInterval(1)) == .met(cap: 60), "an ended start no longer reads as running")
check(ConditionalCheckIn.screen(check: met, live: nil, sessions: [], attempt: .started(until: until), now: sundayNoon) == .gone,
      "a removed rule wins")

// MARK: Freshness: stale, after midnight, other zone, changed rule → check again, never send
check(!ConditionalCheckIn.needsRecheck(met, live: sundays, clock: clock(sundayNoon.addingTimeInterval(100))), "fresh at 100 s")
check(ConditionalCheckIn.needsRecheck(met, live: sundays, clock: clock(sundayNoon.addingTimeInterval(111))), "stale at 111 s")
check(ConditionalCheckIn.freshness < ConditionalStart.stampLifetime, "re-check before the engine's lifetime")
check(ConditionalCheckIn.needsRecheck(met, live: sundays, clock: clock(sundayNoon.addingTimeInterval(-30))), "a future stamp")
check(ConditionalCheckIn.needsRecheck(met, live: edited, clock: clock(sundayNoon)), "edited rule")
check(ConditionalCheckIn.needsRecheck(met, live: nil, clock: clock(sundayNoon)), "removed rule")
let beforeMidnight = CheckInResult.make(rule: sundays, state: sundayState, clock: clock(at(11, 15, 23, 59, 30)), location: .notRead)
check(beforeMidnight.evaluation.isMet, "met at 23:59:30")
check(ConditionalCheckIn.needsRecheck(beforeMidnight, live: sundays, clock: clock(at(11, 16, 0, 0, 20))),
      "a check from before midnight is never sent after it")
if case .failure(let refusal) = ConditionalStart.plan(request(beforeMidnight, minutes: 30), state: sundayState,
                                                       clock: clock(at(11, 16, 0, 0, 20))) {
    check(refusal == .wrongDay || refusal == .conditionsNotMet, "engine refuses it too: \(refusal)")
} else { check(false, "engine refuses yesterday's check") }
// Review fix: a check whose window has closed since is run again (its ✓ rows are out of date).
let lunch = free("Lunch", .all, [.days([1]), .time(start: 12 * 60, end: 12 * 60 + 30)])
let lunchCheck = CheckInResult.make(rule: lunch, state: stateWith([lunch]), clock: clock(at(11, 15, 12, 29, 30)), location: .notRead)
check(lunchCheck.evaluation.isMet, "met at 12:29:30")
check(!ConditionalCheckIn.needsRecheck(lunchCheck, live: lunch, clock: clock(at(11, 15, 12, 29, 50))), "still inside")
check(ConditionalCheckIn.needsRecheck(lunchCheck, live: lunch, clock: clock(at(11, 15, 12, 30, 10))), "window closed: re-check")
// Review fix: a hold on a check that only aged sends the re-run check; midnight, an edit or a new verdict never do.
let aged = CheckInResult.make(rule: sundays, state: sundayState, clock: clock(sundayNoon.addingTimeInterval(115)), location: .notRead)
check(ConditionalCheckIn.mayStartAfterRecheck(old: met, fresh: aged, live: sundays, sessions: [],
      now: sundayNoon.addingTimeInterval(115)), "aged only: send the fresh check")
check(aged.stamp.checkInID != met.stamp.checkInID, "with a new stamp")
let afterMidnight = CheckInResult.make(rule: everyDayRule, state: stateWith([everyDayRule]), clock: clock(at(11, 16, 0, 0, 30)), location: .notRead)
let beforeMidnightEvery = CheckInResult.make(rule: everyDayRule, state: stateWith([everyDayRule]), clock: clock(at(11, 15, 23, 59, 30)), location: .notRead)
check(afterMidnight.evaluation.isMet && beforeMidnightEvery.evaluation.isMet, "every day: met on both sides")
check(!ConditionalCheckIn.mayStartAfterRecheck(old: beforeMidnightEvery, fresh: afterMidnight, live: everyDayRule, sessions: [],
      now: at(11, 16, 0, 0, 30)), "after midnight: shown, needs a new hold")
let editedFresh = CheckInResult.make(rule: edited, state: stateWith([edited]), clock: clock(sundayNoon.addingTimeInterval(115)), location: .notRead)
check(!ConditionalCheckIn.mayStartAfterRecheck(old: met, fresh: editedFresh, live: edited, sessions: [],
      now: sundayNoon.addingTimeInterval(115)), "edited: needs a new hold")
let mondayFresh = CheckInResult.make(rule: sundays, state: sundayState, clock: clock(mondayNoon), location: .notRead)
check(!ConditionalCheckIn.mayStartAfterRecheck(old: met, fresh: mondayFresh, live: sundays, sessions: [], now: mondayNoon),
      "not met any more: never")
check(!ConditionalCheckIn.mayStartAfterRecheck(old: met, fresh: aged, live: sundays, sessions: [running],
      now: sundayNoon.addingTimeInterval(115)), "already running: never")
var madrid = mx; madrid.timeZone = TimeZone(identifier: "Europe/Madrid")!
check(ConditionalCheckIn.needsRecheck(met, live: sundays,
      clock: ConditionalClockInput(guardedNow: sundayNoon, wallNow: sundayNoon, calendar: madrid,
                                   recentTimeZoneIDs: ["Europe/Madrid", "America/Mexico_City"])), "another zone")

// MARK: Reason copy for every reason
let place = ConditionalCondition.place(home), country = ConditionalCondition.country("MX")
func reason(_ r: ConditionReason, _ c: ConditionalCondition, _ s: ConditionStatus = .met) -> String {
    ConditionalCheckIn.reason(ConditionResult(status: s, reason: r), condition: c, translate: say, locale: gb, calendar: mxText)
}
check(reason(.atPlace, place) == "You're at Home" && reason(.notAtPlace, place, .notMet) == "You're not at Home", "place")
check(reason(.inCountry, country) == "You're in Mexico" && reason(.notInCountry, country, .notMet) == "You're not in Mexico", "country")
let c = { (m: Int) in RuleText.clock(m, locale: gb) }
check(reason(.inWindow, .time(start: 1320, end: 360)) == "Until \(c(360))", reason(.inWindow, .time(start: 1320, end: 360)))
check(reason(.outsideWindow(minute: 845), .time(start: 1320, end: 360), .notMet) == "It's \(c(845)); this starts at \(c(1320))",
      reason(.outsideWindow(minute: 845), .time(start: 1320, end: 360), .notMet))
let trip = ConditionalCondition.dates(first: ConditionalDay(year: 2026, month: 12, day: 20),
                                      last: ConditionalDay(year: 2026, month: 12, day: 27))
check(reason(.inDates, trip) == "Today is one of these dates" && reason(.outsideDates, trip, .notMet) == "Today isn't one of these dates", "dates")
check(reason(.onDay(weekday: 7), .days([7])) == "It's Saturday", "Saturday")
check(ConditionalCheckIn.reason(ConditionResult(status: .met, reason: .onDay(weekday: 1)), condition: .days([1]), translate: say,
      locale: Locale(identifier: "es_MX"), calendar: mxText) == "It's domingo", "weekday in the app's language")
check(!reason(.atPlace, .country("MX")).contains("%"), "a mismatched condition never prints a format")
let unknowns: [ConditionalUnknownReason] = [.notChecked, .clockChanged, .timeZoneChanged, .timeZoneUnknown, .locationOff,
    .noFix, .staleFix, .imprecise, .needsPrecise, .simulated, .accessory, .nearBorder, .countryUnavailable]
for u in unknowns {
    check(!ConditionalCheckIn.unknownKey(u).isEmpty && reason(.unknown(u), place, .unknown) == ConditionalCheckIn.unknownKey(u), "unknown \(u)")
}
check(ConditionalCheckIn.unknownKey(.locationOff) == "Location is off for Demora. You can turn it on in Settings.", "no Settings redirect, words only")
// Time zone moved in the last 12 h and the day differs there → "?" with a reason.
let fromTokyo = CheckInResult.make(rule: sundays, state: sundayState,
                                   clock: clock(at(11, 15, 20), zones: ["America/Mexico_City", "Asia/Tokyo"]), location: .notRead)
check(fromTokyo.evaluation.results[0].status == .unknown && !fromTokyo.evaluation.isMet, "must hold in both zones")
check(reason(fromTokyo.evaluation.results[0].reason, .days([1]), .unknown) == "Your time zone changed recently", "zone reason")
for s in [ConditionStatus.met, .notMet, .unknown, .notNeeded] { check(!ConditionalCheckIn.statusKey(s).isEmpty, "status \(s)") }
check(ConditionalCheckIn.needsLine(sundays) == "Free time needs all of these."
      && ConditionalCheckIn.needsLine(mexicoOrSunday) == "Free time needs any of these.", "needs lines")
let screens: [CheckInScreen] = [.checking, .gone, .changed, .running(until: until), .needsLocation, .askPermission,
    .locating, .arrivesLater(.country), .arrivesLater(.block), .clockChanged, .notMet,
    .unknownUses, .usedUp, .windowEnding, .met(cap: 5), .refused(.wrongDay), .queued]
for s in screens {
    check(!ConditionalCheckIn.heroKey(s).isEmpty, "hero \(s)")
    check(s.canStart == (s == .met(cap: 5)), "only met can start: \(s)")
}
check(ConditionalCheckIn.heroKey(.met(cap: 5)) == "You can have free time now." && ConditionalCheckIn.heroKey(.notMet) == "Not right now.", "verdicts")

// MARK: Today's Check in rows (spec §5.3)
func rows(_ s: LatchState, _ wall: Date, used: [UUID: Int]? = nil) -> (rows: [ConditionalAvailability.Row], more: Int) {
    let counts = used ?? Dictionary(uniqueKeysWithValues: s.conditionalRules.map { ($0.id, 0) })
    return ConditionalAvailability.todayRows(state: s, used: counts, clock: clock(wall))
}
let four = (0..<4).map { i in free("R\(i)", .all, [.days([1])]) }
let fourRows = rows(stateWith(four), sundayNoon)
check(fourRows.rows.map(\.name) == ["R0", "R1", "R2"] && fourRows.more == 1, "three rows, then All in Rules")
check(fourRows.rows.allSatisfy { $0.left == 1 }, "1 left today")
check(rows(stateWith(four), mondayNoon).rows.isEmpty, "Monday: none could be used")
check(rows(stateWith([sundays]), sundayNoon, used: [sundays.id: 1]).rows.isEmpty, "used up: no row")
check(rows(stateWith([sundays]), sundayNoon, used: [:]).rows.isEmpty, "unknown count: no row, never a guess")
check(rows(stateWith([twice]), sundayNoon, used: [twice.id: 1]).rows.first?.left == 1, "2 a day, 1 used")
check(rows(withSession, sundayNoon.addingTimeInterval(60), used: [sundays.id: 0]).rows.isEmpty, "running: the Now card shows it")
check(rows(stateWith([mexicoSunday]), sundayNoon).rows.isEmpty, "a country rule: no row until its lookup (step 5)")
check(ConditionalAvailability.todayRows(state: stateWith([mexicoSunday]), used: [mexicoSunday.id: 0], clock: clock(sundayNoon),
      countryLookupAvailable: true).rows.count == 1, "with the lookup (step 5) it gets a row")
let homeSunday = free("Sunday at home", .all, [.place(home), .days([1])])
check(rows(stateWith([homeSunday]), sundayNoon).rows.count == 1, "a place one fix could make true: a row (step 4)")
check(rows(stateWith([homeSunday]), mondayNoon).rows.isEmpty, "…but not on a day that already fails")
check(rows(stateWith([mexicoOrSunday]), sundayNoon).rows.count == 1, "any of: the day alone")
check(rows(stateWith([block]), at(11, 15, 23)).rows.isEmpty, "block rows arrive with their check-in")
check(rows(stateWith([lateSunday]), at(11, 15, 23, 59, 30)).rows.isEmpty, "under a minute left: no row")
check(rows(stateWith([lateSunday]), at(11, 15, 22, 30)).rows.count == 1, "inside the window")
let read = ConditionalClockRead(guardedOffset: 90, recentTimeZoneIDs: ["America/Mexico_City"])
check(read.clock(at: sundayNoon, calendar: mx).guardedNow == sundayNoon.addingTimeInterval(90)
      && read.clock(at: sundayNoon, calendar: mx).wallNow == sundayNoon, "clock from an event read")

// MARK: Running check-in sessions live on their rule, not under Planned
var planned = stateWith([sundays]); planned.sessions = [running, blockNow]
let catalog = RuleCatalog.sections(state: planned, now: sundayNoon.addingTimeInterval(60))
let plannedCards = catalog.first { $0.section == .planned }?.cards.map(\.ref) ?? []
check(plannedCards == [.session(blockNow.id)], "only Block now under Planned: \(plannedCards)")
var orphan = LatchState(); orphan.sessions = [running]
check(RuleCatalog.sections(state: orphan, now: sundayNoon.addingTimeInterval(60)).first { $0.section == .planned }?.cards.map(\.ref)
      == [.session(running.id)], "a removed rule's session (C14) shows under Planned with End early")
check(RuleCatalog.resolve(.session(running.id), state: planned, remembered: nil) == .conditional(sundays.id),
      "Now card and thread open the rule")
check(RuleCatalog.resolve(.session(running.id), state: orphan, remembered: nil) == .session(running.id), "orphan stays a session")
check(RuleCatalog.resolve(.session(blockNow.id), state: planned, remembered: nil) == .session(blockNow.id), "Block now stays itself")
check(RuleChip.live(ref: .conditional(sundays.id), state: planned, blockedLimitIDs: [], conditionalUsed: [sundays.id: 1],
                    now: sundayNoon.addingTimeInterval(60), calendar: mx) == .freeUntil(running.endsAt), "card chip: Free until")
// Review fix: a waiting End early of a check-in session shows on its rule's card.
var ending = planned
let endEarly = PendingChange(createdAt: sundayNoon, appliesAt: sundayNoon.addingTimeInterval(600), direction: .lenient,
                             summary: "x", action: .endSessionEarly(id: running.id))
ending.pending = [endEarly]
let index = RulePending.index(ending.pending)
check(RulePending.cardChange(for: .conditional(sundays.id), in: index, state: ending, now: sundayNoon.addingTimeInterval(60))?.id
      == endEarly.id, "the card shows the waiting End early")
check(RulePending.cardChange(for: .conditional(sundays.id), in: index, state: ending, now: running.endsAt.addingTimeInterval(1)) == nil,
      "not after the session ended")
var editedChange = sundays; editedChange.name = "Sundays 2"
let own = PendingChange(createdAt: sundayNoon, appliesAt: sundayNoon.addingTimeInterval(9000), direction: .lenient,
                        summary: "y", action: .updateConditionalRule(editedChange))
ending.pending.append(own)
check(RulePending.cardChange(for: .conditional(sundays.id), in: RulePending.index(ending.pending), state: ending,
      now: sundayNoon.addingTimeInterval(60))?.id == own.id, "the rule's own change first")
check(RulePending.cardChange(for: .limit(UUID()), in: index, state: ending, now: sundayNoon) == nil, "other refs: their own only")
print("When & where check-in presentation passed: \(checks) checks")
'''

with tempfile.TemporaryDirectory(prefix='demora-whenwhere-checkin-') as directory:
    folder = Path(directory)
    (folder / 'Infrastructure.swift').write_text(infrastructure + '\n' + phrases)
    (folder / 'SharedModels.swift').write_text(models)
    (folder / 'SchedulePrecedence.swift').write_text(precedence)
    (folder / 'RulesPresentation.swift').write_text(portable(presentation))
    (folder / 'main.swift').write_text(driver)
    binary = folder / 'whenwhere-checkin'
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


sheet = (ROOT / 'Latch/CheckInSheet.swift').read_text()
for forbidden in ('CoreLocation', 'CLLocation', 'requestLocation', 'model.queue(', 'applyNow', 'SkipWait',
                  'skipTarget', 'Override', 'override', 'ContactsRelay', 'UserDefaults', 'SharedStore'):
    assert forbidden not in sheet, ('no location, override, queue or storage in the check-in', forbidden)
start = declaration(sheet, 'private func start(cap: Int)')
send = declaration(sheet, 'private func send(_ check: CheckInResult, cap: Int)')
recheck = declaration(sheet, 'private func recheckWithLocation(old: CheckInResult)')
assert send.count('ChangeEngine.startConditionalSessionOffMain(request)') == 1
assert sheet.count('startConditionalSessionOffMain(') == 1, 'one start path'
assert sheet.count('send(') == 3, 'send is called from start and the location re-check only'
assert send.index('guard !starting else { return }') < send.index('starting = true') < send.index('Task {'), \
    'the in-flight flag is set on the main actor before the request leaves it (double tap)'
assert start.index('guard !starting, var check else { return }') < start.index('send(check, cap: cap)')
assert '.canStart else { return }' in start, 'only a met screen sends'
assert start.index('ConditionalCheckIn.needsRecheck(check, live: live') < start.index('send(check, cap: cap)'), \
    'a stale check (midnight, edit, 2 min) is run again, never sent'
assert 'ConditionalCheckIn.mayStartAfterRecheck(old: check, fresh: fresh' in start
assert start.index('checkedAgain = true\n                return') < start.index('send(check, cap: cap)'), 'a re-check that changed is shown, not sent'
# Step 4: an aged check that read location is never re-run without a new fix.
assert start.index('if check.readLocation {\n                // Its fix is too old to trust: read where you are again first.\n'
                   '                recheckWithLocation(old: check)\n                return') \
    < start.index('let fresh = CheckInResult.make(rule: rule, state: state, clock: clock, location: .notRead)'), \
    'a location check is re-read, not refreshed from the clock alone'
assert recheck.index('starting = true') < recheck.index('Task {') < recheck.index('locator.readOnce(wantsPrecise: true)'), \
    'the hold that triggered the re-read can\'t send a second request meanwhile'
assert recheck.index('ConditionalCheckIn.mayStartAfterRecheck(old: old, fresh: fresh') \
    < recheck.index('checkedAgain = true') < recheck.index('send(fresh, cap: freshCap)'), 'sent only if still met'
assert 'location: LocationTrust.checkInInput(outcome, wallNow: clock.wallNow))' in recheck, 'the stamp comes from the new fix'
assert 'stamp: check.stamp' in send and 'revision: check.rule.revision' in send, 'the shown check, its rule version'
assert 'ConditionalCheckIn.requestMinutes(chosen: minutes, cap: cap)' in send
assert 'case .refused(let refusal):\n                attempt = .refused(refusal)' in send
assert '.disabled(starting)' in sheet
assert 'ConditionalClockInput.current(for: state)' in sheet
assert 'location: ConditionalLocationInput, checkInID: UUID = UUID()) -> CheckInResult' in presentation, \
    'every check names what location it used (no default)'
assert 'needsRecheck(check, live: live,\n                                                   clock:' in sheet, 'periodic re-check'
periodic = section(sheet, '.onChange(of: context.date) { _ in', '\n            }\n')
assert 'locationPhase == .idle' in periodic and 'runCheck(model.state, announce: false)' in periodic \
    and 'userAsked' not in periodic, 'a re-check on its own never reads location or asks'
receive = section(sheet, '.onReceive(model.$state) { state in', '\n        }\n')
assert 'runCheck(state, announce: false)' in receive and 'attempt = nil' in receive, 'an edit re-checks'
assert 'userAsked' not in receive, 'a state change never reads location'

summary = (ROOT / 'Latch/RuleSummarySheet.swift').read_text()
actions = section(summary, 'case .conditional(let id):\n                if let rule', 'case .queuedSession, .waits:')
assert 'primary(tr("Check in")) { editor = .checkIn(id) }' in actions and '.disabled(true)' not in actions, 'Check in is on'
assert 'case .checkIn(let id): CheckInSheet(ruleID: id)' in summary
running_src = declaration(summary, 'private func runningSession(of ruleID: UUID')
assert 'receipt = ChangeReceiptRequest(action: .endSessionEarly(id: session.id))' in running_src, 'End early waits, as any session'
assert 'pendingBlock(ending' in running_src and 'Date()' not in running_src, 'End early follows the sheet clock'
assert 'RulePending.cardChange(for: card.ref, in: pending, state: state, now: now)' in (ROOT / 'Latch/RulesView.swift').read_text()
assert 'model.state.conditionalRules.contains(where: { $0.id == owner })' in summary

home = (ROOT / 'Latch/HomeView.swift').read_text()
snapshot = declaration(home, 'private func refreshSnapshot(state: LatchState)')
assert 'RuleLiveReads.conditionalUsed(state: state, guardedNow: guarded, wallNow: now)' in snapshot, 'counts read in events'
assert 'let guarded = TimeGuard.now()' in snapshot
rows_src = declaration(home, '@ViewBuilder private func checkInRows(at now: Date)')
assert 'TimeGuard' not in rows_src and 'ConditionalAvailability.todayRows(' in rows_src, 'no guarded read while drawing'
assert '.sheet(item: $checkIn) { request in CheckInSheet(ruleID: request.ruleID) }' in home
assert 'checkIn = nil' in declaration(home, 'private func consumeWidgetDestination()')
for name in ('Latch', 'Shared'):
    for path in (ROOT / name).glob('*.swift'):
        text = path.read_text()
        assert 'Check in arrives in a later update.' not in text, path.name
        # Step 4: location is confined to the host's one-shot reader
        # (Tests/WhenWhereLocationHarness.py checks it in depth).
        if path.name != 'LocationCheck.swift':
            assert 'import CoreLocation' not in text and 'CLLocationManager' not in text, \
                ('CoreLocation only in Latch/LocationCheck.swift', path.name)
project = (ROOT / 'Latch.xcodeproj/project.pbxproj').read_text()
assert 'NSLocationAlways' not in project and 'NSLocationAlways' not in (ROOT / 'Latch/Info.plist').read_text(), \
    'While Using only, never Always'
print('When & where check-in source guards passed: one start in flight, re-check before send (with a new fix), '
      'no override, location only through LocationCheck')

# --- Translations of every new string ------------------------------------
keys = set()
today = section((ROOT / 'Latch/TodayView.swift').read_text(), 'struct CheckInRows: View {', '\n}\n')
editor = (ROOT / 'Latch/ConditionalRuleEditor.swift').read_text()
row = section(editor, 'struct ConditionRow: View {', '\n}\n')
for text in (sheet, today, row, editor):
    for call in re.findall(r'\btr\((?:[^()"]|"(?:[^"\\]|\\.)*")*\)', text):
        keys.update(re.findall(STRING, call))
checkin = section(presentation, 'enum ConditionalCheckIn {', '\n}\n')
keys.update(re.findall(r'return ' + STRING, checkin))
keys.update(re.findall(r'translate\(' + STRING + r'\)', checkin))
keys.update(["You're at %@", "You're not at %@", "You're in %@", "You're not in %@"])
keys.discard('')
assert len(keys) > 70, len(keys)
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
print(f'When & where check-in translations passed: {len(keys)} strings × 7 tables')
