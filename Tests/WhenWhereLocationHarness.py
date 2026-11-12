#!/usr/bin/env python3
"""When & where step 4: places, the one-shot location read and its permission.

Compiles the real Latch/RulesPresentation.swift with the real SharedModels and
SchedulePrecedence (as the other When & where harnesses do) and checks
(docs/conditional-sessions-redesign.md §5.5–§5.7, C8–C12):
- the trust rules from a CoreLocation-shaped sample to ✓/✗/?: simulated and
  accessory fixes, approximate location, stale or invalid fixes, denial and
  timeouts all fail closed; free time needs the whole uncertainty circle
  inside the place; a country is decided only by the lookup handed in
  (step 5: Tests/WhenWhereCountryHarness.py checks the real borders);
- when the sheet reads location (only when a place or country could change the answer,
  never for a check refreshed on its own), when it shows the permission card
  (never asked yet) and when it says location is off (no re-prompt);
- that the stamp built from a fix is exactly what the engine's own
  `ConditionalStart.plan` accepts, and refused when the fix said "not here";
- place math: sizes 100 m…2 km only, a centre only from a precise real fix
  good to 100 m (rounded to ~1 m), places copied from other rules as values.
Then source guards on the only CoreLocation file (one fix, While Using, no
background, monitoring, geocoder, map or logging; nothing saved), on who may
read location, and on the permission strings (Debug and Release build
settings identical, Info.plist, `InfoPlist.xcstrings` in all eight
languages), plus translations of the new in-app strings.

No iOS build, simulator, device, permission prompt or real fix is involved:
CoreLocation itself is not compiled here, so this cannot show that iOS
delivers a fix, how accurate it is, or how the prompts look.
"""
from pathlib import Path
import json
import os
import plistlib
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
    static func now() -> Date { fatalError("location presentation must not read the guarded clock") }
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
func at(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
    mx.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min, second: s))!
}
let none = FamilyActivitySelection()
let say: RuleText.Translate = { $0 }
func free(_ name: String, _ match: ConditionalMatch, _ conditions: [ConditionalCondition],
          max: Int = 60, uses: Int = 1) -> ConditionalRule {
    ConditionalRule(name: name, match: match, conditions: conditions,
                    outcome: .freeTime(kind: .free, selection: none, maxMinutes: max, usesPerDay: uses),
                    addedAt: at(11, 1))
}
func clock(_ wall: Date) -> ConditionalClockInput {
    ConditionalClockInput(guardedNow: wall, wallNow: wall, calendar: mx, recentTimeZoneIDs: ["America/Mexico_City"])
}
func stateWith(_ rules: [ConditionalRule]) -> LatchState {
    var s = LatchState(); s.conditionalRules = rules; return s
}
let home = ConditionalPlace(name: "Home", latitude: 19.43260, longitude: -99.13320, radiusMeters: 250)
let metresPerDegree = Double.pi / 180 * ConditionEvaluator.earthRadius
/// A point `north` metres north of home.
func north(_ metres: Double) -> (Double, Double) { (home.latitude + metres / metresPerDegree, home.longitude) }
let sundayNoon = at(11, 15, 12), mondayNoon = at(11, 16, 12)
check(mx.component(.weekday, from: sundayNoon) == 1, "15 Nov 2026 is a Sunday")
func sample(_ point: (Double, Double), accuracy: Double = 20, age: TimeInterval = 2, simulated: Bool = false,
            accessory: Bool = false, now: Date = sundayNoon) -> LocationSample {
    LocationSample(latitude: point.0, longitude: point.1, horizontalAccuracy: accuracy,
                   timestamp: now.addingTimeInterval(-age), isSimulated: simulated, isFromAccessory: accessory)
}
func read(_ s: LocationSample, precise: Bool = true) -> LocationReadOutcome { .sample(s, precise: precise) }
func input(_ o: LocationReadOutcome, now: Date = sundayNoon) -> ConditionalLocationInput {
    LocationTrust.checkInInput(o, wallNow: now, country: nil)
}

// MARK: Geometry: the distance the trust rules use
check(abs(ConditionEvaluator.distanceMeters(home.latitude, home.longitude, north(200).0, north(200).1) - 200) < 0.5,
      "200 m north is 200 m")

// MARK: Trust rules, sample → evaluation (free time: doubt fails)
let homeSunday = free("Sunday at home", .all, [.place(home), .days([1])])
func placeResult(_ o: LocationReadOutcome, rule: ConditionalRule = homeSunday, now: Date = sundayNoon) -> ConditionResult {
    ConditionEvaluator.evaluate(rule, clock: clock(now), location: input(o, now: now)).results[0]
}
check(placeResult(read(sample(north(0)))) == ConditionResult(status: .met, reason: .atPlace), "at the centre")
check(placeResult(read(sample(north(200), accuracy: 40))).status == .met, "200 + 40 ≤ 250: whole circle inside")
check(placeResult(read(sample(north(200), accuracy: 60))) == .unknown(.imprecise), "200 + 60 > 250: can't tell")
check(placeResult(read(sample(north(320), accuracy: 60))) == ConditionResult(status: .notMet, reason: .notAtPlace),
      "320 − 60 > 250: not there")
check(placeResult(read(sample(north(0), accuracy: 3000))) == .unknown(.imprecise), "a fix vaguer than the place never passes")
check(placeResult(read(sample(north(0), simulated: true))) == .unknown(.simulated), "simulated (Xcode, simulators): ?")
check(placeResult(read(sample(north(0), accessory: true))) == .unknown(.accessory), "accessory fix: ? for free time")
check(placeResult(read(sample(north(0)), precise: false)) == .unknown(.needsPrecise), "approximate location: needs precise")
check(placeResult(read(sample(north(0), age: 20))) == .unknown(.staleFix), "a fix older than 15 s")
check(placeResult(read(sample(north(0), accuracy: -1))) == .unknown(.noFix), "an invalid fix")
check(placeResult(read(sample((.nan, 0)))) == .unknown(.noFix), "no coordinates")
check(placeResult(.failed(.denied)) == .unknown(.locationOff), "denied while reading")
for failure in [LocationReadFailure.noFix, .timedOut, .cancelled] {
    check(placeResult(.failed(failure)) == .unknown(.noFix), "\(failure): couldn't get your location")
}
check(LocationTrust.timeout == 15, "one read waits 15 s at most")
// A country is decided only by the lookup handed in (step 5); without one it can't be told.
let mexicoAndHome = free("Mexico", .any, [.country("MX"), .place(home)])
check(ConditionEvaluator.evaluate(mexicoAndHome, clock: clock(sundayNoon), location: input(read(sample(north(5000)))))
      .results[0] == .unknown(.countryUnavailable), "no lookup: can't tell")
if case .fix(_, let country) = input(read(sample(north(0)))) { check(country == nil, "no lookup, no country") }
else { check(false, "a sample is a fix") }
var asked: [(Double, Double)] = []
let inMexico: LocationTrust.CountryAt = { lat, lon in
    asked.append((lat, lon)); return ConditionalCountryLookup(regionCode: "MX", borderDistanceMeters: 600_000)
}
if case .fix(let fix, let country) = LocationTrust.checkInInput(read(sample(north(0), accuracy: 30)), wallNow: sundayNoon,
                                                                 country: inMexico) {
    check(country?.regionCode == "MX" && asked.count == 1 && asked[0].0 == home.latitude, "the fix's point is looked up once")
    check(fix.horizontalAccuracy == 30 && fix.isPrecise, "precise: iOS's accuracy as it is")
} else { check(false, "a sample is a fix") }
check(ConditionEvaluator.evaluate(mexicoAndHome, clock: clock(mondayNoon),
      location: LocationTrust.checkInInput(read(sample(north(5000), now: mondayNoon)), wallNow: mondayNoon, country: inMexico))
      .results[0] == ConditionResult(status: .met, reason: .inCountry), "the lookup decides the country")
// Approximate Location: a country is judged as if the fix were at least 10 km vague.
if case .fix(let fix, _) = LocationTrust.checkInInput(read(sample(north(0), accuracy: 1_500), precise: false),
                                                       wallNow: sundayNoon, country: inMexico) {
    check(fix.horizontalAccuracy == 10_000 && !fix.isPrecise, "approximate: accuracy floored at 10 km")
} else { check(false, "a sample is a fix") }
asked = []
if case .fix(_, let country) = LocationTrust.checkInInput(read(sample((.nan, 0))), wallNow: sundayNoon, country: inMexico) {
    check(country == nil && asked.isEmpty, "no lookup for an unusable point")
} else { check(false, "a sample is a fix") }

// MARK: When the sheet reads, asks, or says location is off (C8)
func notRead(_ rule: ConditionalRule, _ now: Date) -> CheckInResult {
    CheckInResult.make(rule: rule, state: stateWith([rule]), clock: clock(now), location: .notRead)
}
let homeOrSunday = free("Home or Sunday", .any, [.place(home), .days([1])])
let mexicoSunday = free("Sunday in Mexico", .all, [.country("MX"), .days([1])])
let block = ConditionalRule(name: "Instagram at home", match: .any, conditions: [.place(home)],
    outcome: .block(mode: .blockSelected, selection: none, until: .time(7 * 60)), addedAt: at(11, 1))
let allowed = LocationPermission.allowed(precise: true)
func step(_ r: CheckInResult, permission: LocationPermission, sessions: [BlockSession] = []) -> CheckInLocationStep {
    ConditionalCheckIn.locationStep(r, permission: permission, sessions: sessions, now: sundayNoon)
}
check(step(notRead(homeSunday, sundayNoon), permission: allowed) == .read, "Sunday: read once")
check(step(notRead(homeSunday, sundayNoon), permission: .allowed(precise: false)) == .read,
      "approximate: read (iOS is asked for precise first)")
check(step(notRead(homeSunday, sundayNoon), permission: .notAsked) == .ask, "never asked: the card")
check(step(notRead(homeSunday, sundayNoon), permission: .denied) == .off, "denied: no prompt")
check(step(notRead(homeSunday, sundayNoon), permission: .restricted) == .off, "restricted: no prompt")
check(step(notRead(homeSunday, mondayNoon), permission: allowed) == .none,
      "all of: the day already fails, so no read and no prompt")
check(step(notRead(homeSunday, mondayNoon), permission: .notAsked) == .none, "…nor a card")
check(step(notRead(homeOrSunday, sundayNoon), permission: allowed) == .none,
      "any of: the day is enough, so no read")
check(step(notRead(homeOrSunday, mondayNoon), permission: allowed) == .read, "any of: only home could")
check(step(notRead(mexicoSunday, sundayNoon), permission: allowed) == .read,
      "a country one fix could decide: read once (step 5)")
check(step(notRead(mexicoSunday, mondayNoon), permission: allowed) == .none, "…never on a day that already fails")
check(!ConditionalCheckIn.wantsPrecise(mexicoSunday) && ConditionalCheckIn.wantsPrecise(homeSunday)
      && ConditionalCheckIn.wantsPrecise(mexicoAndHome), "temporary precise only when a place needs it")
check(step(notRead(mexicoAndHome, sundayNoon), permission: allowed) == .read,
      "any of country/home: home could decide")
let allThree = free("Mexico home Sunday", .all, [.country("MX"), .place(home), .days([1])])
check(step(notRead(allThree, sundayNoon), permission: allowed) == .read,
      "all of with a country and a place: one fix decides both")
check(step(notRead(block, sundayNoon), permission: allowed) == .none, "block check-ins: step 6")
let alreadyRead = CheckInResult.make(rule: homeSunday, state: stateWith([homeSunday]), clock: clock(sundayNoon),
                                     location: .unavailable(.noFix))
check(alreadyRead.readLocation && !notRead(homeSunday, sundayNoon).readLocation, "a check knows whether it read")
check(step(alreadyRead, permission: allowed) == .none, "a check that read never reads again by itself")
// Review fix: no read (and no card) when a fix couldn't change what the sheet says.
var spentState = stateWith([homeSunday])
spentState.conditionalUses = ConditionalUses.recording(ruleID: homeSunday.id, dayKeys: ["2026-11-15"], checkInID: UUID(),
                                                       at: sundayNoon.addingTimeInterval(-600), in: [])
let spent = CheckInResult.make(rule: homeSunday, state: spentState, clock: clock(sundayNoon), location: .notRead)
check(step(spent, permission: allowed) == .none && step(spent, permission: .notAsked) == .none, "used up: no read, no card")
check(ConditionalCheckIn.screen(check: spent, live: homeSunday, sessions: [], attempt: nil, now: sundayNoon, location: .idle)
      == .usedUp, "used up is said before asking for location")
var runningHome = BlockSession(name: "Sunday at home", kind: .free, selection: none,
                               startedAt: sundayNoon.addingTimeInterval(-60), endsAt: sundayNoon.addingTimeInterval(1800))
runningHome.conditionalRuleID = homeSunday.id
check(step(notRead(homeSunday, sundayNoon), permission: allowed, sessions: [runningHome]) == .none, "free time already on: no read")
var otherSession = runningHome; otherSession.conditionalRuleID = UUID()
check(step(notRead(homeSunday, sundayNoon), permission: allowed, sessions: [otherSession]) == .read, "another rule's session")
let unknownCount = CheckInResult.make(rule: homeSunday, state: stateWith([homeSunday]),
    clock: ConditionalClockInput(guardedNow: sundayNoon, wallNow: sundayNoon, calendar: mx,
                                 recentTimeZoneIDs: ["America/Mexico_City", "Not/AZone"]), location: .notRead)
check(unknownCount.used == nil && step(unknownCount, permission: allowed) == .none, "uses unknown: no read")

// MARK: Screens around the read
func screen(_ r: CheckInResult, phase: CheckInLocationPhase = .idle, now: Date = sundayNoon) -> CheckInScreen {
    ConditionalCheckIn.screen(check: r, live: r.rule, sessions: [], attempt: nil, now: now, location: phase)
}
check(screen(notRead(homeSunday, sundayNoon), phase: .asking) == .askPermission, "the card before iOS asks")
check(screen(notRead(homeSunday, sundayNoon), phase: .reading) == .locating, "Checking where you are")
check(screen(notRead(homeSunday, sundayNoon)) == .needsLocation, "a check refreshed on its own: check in again")
for s in [CheckInScreen.askPermission, .locating, .needsLocation, .arrivesLater(.block)] {
    check(!s.canStart, "\(s) never starts")
}
check(ConditionalCheckIn.detailKey(.askPermission)
      == "Demora checks where you are once, when you tap Check in. It doesn't save or send your location.", "card copy")
check(ConditionalCheckIn.detailKey(.needsLocation) == "Check in again to check where you are.", "expired copy")
check(screen(notRead(homeSunday, mondayNoon), phase: .reading) == .notMet, "Monday: not met, whatever the phase")
check(screen(notRead(mexicoSunday, sundayNoon)) == .needsLocation, "country: needs one fix")

// MARK: The stamp from a fix is what the engine accepts
func withFix(_ rule: ConditionalRule, _ o: LocationReadOutcome, now: Date = sundayNoon) -> CheckInResult {
    CheckInResult.make(rule: rule, state: stateWith([rule]), clock: clock(now), location: input(o, now: now))
}
func request(_ r: CheckInResult, minutes: Int) -> ConditionalStartRequest {
    ConditionalStartRequest(ruleID: r.rule.id, revision: r.rule.revision, minutes: minutes, stamp: r.stamp)
}
let atHome = withFix(homeSunday, read(sample(north(10))))
check(screen(atHome) == .met(cap: 60), "\(screen(atHome))")
check(atHome.stamp.results == [true, true], "stamp: one boolean per condition, no coordinates")
check(atHome.stamp.guardedAt == sundayNoon, "the stamp's time is the check's")
if case .success(let plan) = ConditionalStart.plan(request(atHome, minutes: 30), state: stateWith([homeSunday]),
                                                    clock: clock(sundayNoon.addingTimeInterval(20))) {
    check(plan.session.conditionalRuleID == homeSunday.id
          && plan.session.endsAt == sundayNoon.addingTimeInterval(20 + 1800), "the engine starts 30 min")
} else { check(false, "the engine accepts a met fix check") }
let away = withFix(homeSunday, read(sample(north(900))))
check(screen(away) == .notMet && away.stamp.results == [false, true], "away: not met")
if case .failure(let refusal) = ConditionalStart.plan(request(away, minutes: 30), state: stateWith([homeSunday]),
                                                       clock: clock(sundayNoon.addingTimeInterval(20))) {
    check(refusal == .conditionsNotMet, "engine refuses: \(refusal)")
} else { check(false, "the engine refuses a not-at-home stamp") }
let unread = notRead(homeSunday, sundayNoon)
check(unread.stamp.results == [false, true], "an unread place is never claimed as met")
if case .failure = ConditionalStart.plan(request(unread, minutes: 30), state: stateWith([homeSunday]), clock: clock(sundayNoon)) {
    check(true, "")
} else { check(false, "the engine refuses an unread place") }
let off = CheckInResult.make(rule: homeSunday, state: stateWith([homeSunday]), clock: clock(sundayNoon),
                             location: .unavailable(.locationOff))
check(screen(off) == .notMet, "location off: not met, Try again / Done only")
check(ConditionalCheckIn.reason(off.evaluation.results[0], condition: .place(home), translate: say, locale: gb, calendar: mx)
      == "Location is off for Demora. You can turn it on in Settings.", "words only, no redirect")
check(ConditionalCheckIn.reason(notRead(homeSunday, sundayNoon).evaluation.results[0], condition: .place(home), translate: say,
      locale: gb, calendar: mx) == "Not checked yet", "unread place row")
// Window caps still apply with a place: home at lunch, 12:00–12:30, at 12:20 → 10 min.
let lunchAtHome = free("Lunch at home", .all, [.place(home), .time(start: 12 * 60, end: 12 * 60 + 30)])
check(screen(withFix(lunchAtHome, read(sample(north(0), now: at(11, 15, 12, 20))), now: at(11, 15, 12, 20)),
             now: at(11, 15, 12, 20)) == .met(cap: 10), "a place doesn't lift the window end")
let viaHome = withFix(homeOrSunday, read(sample(north(0), now: mondayNoon)), now: mondayNoon)
check(screen(viaHome, now: mondayNoon) == .met(cap: 60) && viaHome.evaluation.windowEnd == nil,
      "any of, met by the place: capped by length only")
// Freshness: an aged location check is re-read (a new fix), and the fresh one may be sent.
check(ConditionalCheckIn.needsRecheck(atHome, live: homeSunday, clock: clock(sundayNoon.addingTimeInterval(111))), "aged")
let reread = withFix(homeSunday, read(sample(north(10), now: sundayNoon.addingTimeInterval(115))),
                     now: sundayNoon.addingTimeInterval(115))
check(ConditionalCheckIn.mayStartAfterRecheck(old: atHome, fresh: reread, live: homeSunday, sessions: [],
      now: sundayNoon.addingTimeInterval(115)), "a new fix at home: sent")
let refreshedAway = withFix(homeSunday, read(sample(north(900), now: sundayNoon.addingTimeInterval(115))),
                            now: sundayNoon.addingTimeInterval(115))
check(!ConditionalCheckIn.mayStartAfterRecheck(old: atHome, fresh: refreshedAway, live: homeSunday, sessions: [],
      now: sundayNoon.addingTimeInterval(115)), "walked away meanwhile: shown, never sent")
check(!ConditionalCheckIn.mayStartAfterRecheck(old: atHome, fresh: notRead(homeSunday, sundayNoon.addingTimeInterval(115)),
      live: homeSunday, sessions: [], now: sundayNoon.addingTimeInterval(115)), "refreshed without a fix: never sent")

// MARK: Today rows: a place one fix could make true opens the check-in (nothing is read for the row)
func rows(_ s: LatchState, _ wall: Date) -> [ConditionalAvailability.Row] {
    ConditionalAvailability.todayRows(state: s, used: Dictionary(uniqueKeysWithValues: s.conditionalRules.map { ($0.id, 0) }),
                                      clock: clock(wall)).rows
}
check(rows(stateWith([homeSunday]), sundayNoon).map(\.name) == ["Sunday at home"], "Sunday: a row")
check(rows(stateWith([homeSunday]), mondayNoon).isEmpty, "Monday: no row")
check(rows(stateWith([mexicoSunday, allThree]), sundayNoon).count == 2, "countries one fix could decide: rows (step 5)")
check(rows(stateWith([mexicoSunday, allThree]), mondayNoon).isEmpty, "…not on Monday")

// MARK: Place choices (C10, C11, C12)
check(PlaceChoices.sizes == [100, 250, 500, 1000, 2000] && PlaceChoices.sizes.max() == 2000, "five sizes, capped at 2 km")
check(PlaceChoices.sizes.contains(PlaceChoices.defaultRadius), "the default is one of them")
check(Set(PlaceChoices.sizes.map(PlaceChoices.sizeWordsKey)).count == 5, "words for each size")
let centre = PlaceCentre(latitude: 19.4326, longitude: -99.1332)
check(PlaceChoices.place(name: "  Home ", centre: centre, radius: 250)
      == ConditionalPlace(name: "Home", latitude: 19.4326, longitude: -99.1332, radiusMeters: 250), "trimmed name")
check(PlaceChoices.place(name: "Home", centre: centre, radius: 5000) == nil, "no 5 km place")
check(PlaceChoices.place(name: "Home", centre: centre, radius: 300) == nil, "no free entry")
check(PlaceChoices.place(name: " ", centre: centre, radius: 250) == nil, "needs a name")
check(PlaceChoices.place(name: "Home", centre: nil, radius: 250) == nil, "needs a centre")
check(PlaceChoices.place(name: String(repeating: "h", count: 81), centre: centre, radius: 250) == nil, "name length")
check(PlaceChoices.place(name: "Home", centre: PlaceCentre(latitude: 91, longitude: 0), radius: 250) == nil, "a real centre")
for radius in PlaceChoices.sizes {
    check(PlaceChoices.place(name: "P", centre: centre, radius: radius)?.isValid == true, "\(radius) m is valid")
}
// A centre only from a precise, real, fresh fix good to 100 m; rounded to ~1 m.
func centreFrom(_ o: LocationReadOutcome) -> Result<PlaceCentre, PlaceCentreProblem> { LocationTrust.centre(o, wallNow: sundayNoon) }
let raw = LocationSample(latitude: 19.4326077, longitude: -99.1332081, horizontalAccuracy: 12,
                         timestamp: sundayNoon.addingTimeInterval(-1), isSimulated: false, isFromAccessory: false)
check(centreFrom(read(raw)) == .success(PlaceCentre(latitude: 19.43261, longitude: -99.13321)), "\(centreFrom(read(raw)))")
func problem(_ o: LocationReadOutcome) -> ConditionalUnknownReason? {
    if case .failure(let p) = centreFrom(o) { return p.reason }; return nil
}
var vague = raw; vague.horizontalAccuracy = 150
check(problem(read(vague)) == .imprecise, "150 m: not precise enough here")
var edge = raw; edge.horizontalAccuracy = 100
check(problem(read(edge)) == nil, "100 m is enough")
var fake = raw; fake.isSimulated = true
check(problem(read(fake)) == .simulated, "simulated: refused")
var accessory = raw; accessory.isFromAccessory = true
check(problem(read(accessory)) == .accessory, "accessory: refused")
check(PlaceCentreProblem(reason: .accessory).messageKey == "Location from an accessory can't set a place", "accessory words")
check(problem(read(raw, precise: false)) == .needsPrecise, "approximate: refused")
var old = raw; old.timestamp = sundayNoon.addingTimeInterval(-60)
check(problem(read(old)) == .staleFix, "a minute-old fix: refused")
var invalid = raw; invalid.horizontalAccuracy = -1
check(problem(read(invalid)) == .noFix, "invalid: refused")
check(problem(.failed(.denied)) == .locationOff && problem(.failed(.timedOut)) == .noFix, "denied / timed out")
check(PlaceCentreProblem(reason: .locationOff).messageKey == ConditionalCheckIn.unknownKey(.locationOff), "same words as Check in")
check(LocationTrust.rounded(-99.1332081) == -99.13321 && LocationTrust.rounded(0.000004) == 0, "5 decimals")
// "Use a place from another rule": copies, deduplicated, never this rule's own, queued rules included.
let school = ConditionalPlace(name: "School", latitude: 19.3, longitude: -99.2, radiusMeters: 500)
var ruleA = free("A", .all, [.place(home)]), ruleB = free("B", .any, [.place(home), .days([7])])
let ruleC = free("C", .all, [.place(school), .days([2])])
var withOthers = stateWith([ruleA, ruleB])
withOthers.pending = [PendingChange(createdAt: sundayNoon, appliesAt: sundayNoon.addingTimeInterval(86_400), direction: .lenient,
                                    summary: "x", action: .addConditionalRule(ruleC))]
check(PlaceChoices.otherPlaces(state: withOthers, excluding: ruleA.id) == [home, school], "home once, then a queued rule's")
check(PlaceChoices.otherPlaces(state: withOthers, excluding: nil) == [home, school], "a new rule sees all")
check(PlaceChoices.otherPlaces(state: stateWith([ruleA]), excluding: ruleA.id).isEmpty, "never its own")
var copied = PlaceChoices.otherPlaces(state: withOthers, excluding: ruleA.id)[0]
copied.radiusMeters = 100
check(withOthers.conditionalRules[1].conditions[0] == .place(home), "a copy: editing it leaves the other rule alone (C11)")
ruleA.conditions = [.place(ConditionalPlace(name: "Bad", latitude: .nan, longitude: 0, radiusMeters: 250))]
check(PlaceChoices.otherPlaces(state: stateWith([ruleA]), excluding: nil).isEmpty, "an invalid place is never offered")
// Summary lines name the place and its size, never coordinates.
let line = ConditionalText.sheetLine(.place(home), translate: say, locale: gb, calendar: mx)
check(line.contains("Home") && line.contains("250") && !line.contains("19.4") && !line.contains("99.1"), line)
check(!ConditionalSummary.sentence(homeSunday, locale: gb, calendar: mx).contains("19.4"), "receipts: names only")
print("When & where location presentation passed: \(checks) checks")
'''

with tempfile.TemporaryDirectory(prefix='demora-whenwhere-location-') as directory:
    folder = Path(directory)
    (folder / 'Infrastructure.swift').write_text(infrastructure + '\n' + phrases)
    (folder / 'SharedModels.swift').write_text(models)
    (folder / 'SchedulePrecedence.swift').write_text(precedence)
    (folder / 'RulesPresentation.swift').write_text(portable(presentation))
    (folder / 'main.swift').write_text(driver)
    binary = folder / 'whenwhere-location'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5',
                    str(folder / 'Infrastructure.swift'), str(folder / 'SharedModels.swift'),
                    str(folder / 'SchedulePrecedence.swift'),
                    str(folder / 'RulesPresentation.swift'), str(folder / 'main.swift'),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, env={**os.environ, 'TZ': 'America/Mexico_City'})

# --- Source guards: the only CoreLocation file -----------------------------
locator = (ROOT / 'Latch/LocationCheck.swift').read_text()
code = '\n'.join(line for line in locator.split('\n') if not line.lstrip().startswith('//'))
for forbidden in ('startUpdatingLocation', 'startMonitoring', 'allowsBackgroundLocationUpdates',
                  'requestAlwaysAuthorization', 'CLMonitor', 'CLGeocoder', 'CLCircularRegion', 'CLBeacon',
                  'CLVisit', 'CLBackgroundActivitySession', 'CLServiceSession', 'showsBackgroundLocationIndicator',
                  'significant', 'MapKit', 'MKMap', 'URLSession', 'print(', 'NSLog', 'os_log', 'Logger',
                  'UserDefaults', 'AppStorage', 'SharedStore', 'FileManager', 'Keychain', 'write(', 'NotificationCenter'):
    assert forbidden not in code, ('one foreground fix, nothing kept, logged, sent or monitored', forbidden)
assert code.count('manager.requestLocation()') == 1, 'one fix per read'
assert code.count('manager.requestWhenInUseAuthorization()') == 1
permission_src = declaration(locator, 'func requestPermission() async')
assert 'guard manager.authorizationStatus == .notDetermined, permissionWaiter == nil else { return }' in permission_src, \
    'iOS is asked only if Demora never was (no re-prompt loop)'
# Review fix: with Location Services off for the whole iPhone, iOS shows no
# prompt and never answers; treat it as off instead of waiting forever.
assert code.count('locationServicesEnabled()') == 1 and \
    'await Task.detached { CLLocationManager.locationServicesEnabled() }.value' in permission_src, 'checked off the main thread'
assert permission_src.index('let token = readToken') < permission_src.index('locationServicesEnabled()') \
    < permission_src.index('guard token == readToken else { return }') < permission_src.index('requestWhenInUseAuthorization()'), \
    'a sheet closed during the services check gets no prompt'
assert permission_src.index('guard enabled else {\n            servicesOff = true\n            return') \
    < permission_src.index('manager.requestWhenInUseAuthorization()')
assert 'if servicesOff { return .denied }' in declaration(locator, 'var permission: LocationPermission {')
stop_src = declaration(locator, 'func stop()')
assert 'cancel()' in stop_src and 'waiter.resume()' in stop_src, 'closing a sheet ends a permission wait iOS may never answer'
read_src = declaration(locator, 'func readOnce(wantsPrecise: Bool) async -> LocationReadOutcome')
assert read_src.index('cancel()') < read_src.index('guard case .allowed(let precise) = permission else { return .failed(.denied) }') \
    < read_src.index('manager.requestLocation()'), 'one read at a time, only with permission'
assert 'LocationTrust.timeout' in read_src and 'self?.finish(.failed(.timedOut))' in read_src, '15 s timeout'
assert 'requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.precisePurposeKey)' in read_src
# Review fix: a read cancelled while iOS asked for precise location never starts its fix.
assert read_src.index('let token = readToken') \
    < read_src.index('requestTemporaryFullAccuracyAuthorization') \
    < read_src.index('guard token == readToken, !Task.isCancelled else { return .failed(.cancelled) }') \
    < read_src.index('manager.requestLocation()'), 'cancel during the precise prompt is honoured'
assert 'readToken += 1' in declaration(locator, 'func cancel()'), 'every cancel invalidates a pending read'
assert read_src.index('finish(.failed(.cancelled))\n            fixWaiter = waiter') > 0, 'never two fix waiters'
finish_src = declaration(locator, 'private func finish(_ outcome: LocationReadOutcome)')
assert finish_src.index('guard let waiter = fixWaiter else { return }') < finish_src.index('manager.stopUpdatingLocation()') \
    < finish_src.index('waiter.resume(returning: outcome)'), 'stopped as soon as it resolves; resumed once'
update_src = declaration(locator, 'nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations')
assert 'source?.isSimulatedBySoftware' in update_src and 'source?.isProducedByAccessory' in update_src, 'C9 source checks'
assert 'locations.last' in update_src
auth_src = declaration(locator, 'nonisolated func locationManagerDidChangeAuthorization')
assert 'let decided = manager.authorizationStatus != .notDetermined' in auth_src and 'guard decided' in auth_src, \
    'the creation callback ("not determined") does not end the wait'
assert re.search(r'case \.denied: return \.denied\s+@unknown default: return \.denied', locator), 'unknown status fails closed'
assert '@MainActor\nfinal class LocationCheck' in locator

# Only the check-in, place and country sheets read location, each with its own reader.
readers = {}
for directory in ('Latch', 'Shared', 'LatchMonitor', 'LatchReport', 'LatchWidgets', 'LatchShieldUI'):
    for path in (ROOT / directory).rglob('*.swift'):
        text = path.read_text()
        if path.name != 'LocationCheck.swift':
            for word in ('import CoreLocation', 'CLLocationManager', 'CLGeocoder', 'import MapKit'):
                assert word not in text, ('CoreLocation only in Latch/LocationCheck.swift', path, word)
            if 'LocationCheck' in text:
                readers[path.name] = text
assert set(readers) - {'RulesPresentation.swift'} == {'CheckInSheet.swift', 'PlaceEditor.swift', 'CountryPicker.swift'}, \
    sorted(readers)
for name in ('CheckInSheet.swift', 'PlaceEditor.swift', 'CountryPicker.swift'):
    text = readers[name]
    assert text.count('@StateObject private var locator = LocationCheck()') == 1, ('one reader per sheet, dropped with it', name)
    assert text.count('locator.requestPermission()') == 1, name
    assert 'locator.requestPermission()' in declaration(text, 'private func allowLocation()'), \
        ('iOS asks only after the in-sheet "Allow location" tap', name)
    assert 'locator.stop()' in text.split('.onDisappear {', 1)[1].split('}', 1)[0], ('closing stops the read and any wait', name)
    # Review fix: a second tap while iOS's prompt is up does nothing.
    allow = declaration(text, 'private func allowLocation()')
    assert allow.index('guard !requestingPermission else { return }') < allow.index('requestingPermission = true') \
        < allow.index('await locator.requestPermission()') < allow.index('requestingPermission = false'), name
    assert '.disabled(requestingPermission)' in text, name
    for forbidden in ('print(', 'NSLog', 'Logger', 'UserDefaults', 'AppStorage', 'SharedStore', 'openSettingsURLString',
                      'UIApplication.shared.open', 'openURL'):
        assert forbidden not in text, ('nothing logged or saved, no Settings redirect', name, forbidden)
for name in ('LatchApp.swift', 'AppModel.swift', 'AppDelegate.swift', 'HomeView.swift', 'TodayView.swift',
             'RulesView.swift', 'RuleSummarySheet.swift', 'OnboardingView.swift'):
    text = (ROOT / 'Latch' / name).read_text()
    assert 'LocationCheck' not in text and 'readOnce' not in text, ('never read at launch or while drawing', name)

sheet = readers['CheckInSheet.swift']
run_src = declaration(sheet, 'private func runCheck(_ state: LatchState, announce: Bool, userAsked: Bool = false)')
assert run_src.index('if userAsked {') < run_src.index('readLocation(announce: announce, precise: ConditionalCheckIn.wantsPrecise(rule))'), \
    'a read only when the user asked; precise only for a place'
assert 'sessions: state.sessions, now: Date())' in run_src, 'running sessions and uses decide too'
assert 'locationPhase = .asking' in run_src and "location: .unavailable(.locationOff))" in run_src
assert sheet.count('userAsked: true') == 3, 'opening the sheet, Try again, and the card'
assert '.onAppear { runCheck(model.state, announce: true, userAsked: true) }' in sheet
allow_src = declaration(sheet, 'private func allowLocation()')
assert 'runCheck(model.state, announce: true, userAsked: true)' in allow_src
try_again = sheet.split('primary(tr("Try again")) {', 1)[1].split('}', 1)[0]
# Review fix: Try again is the user's tap, so it may read a new fix (after a
# timeout or an aged check); denied stays "off" (locationStep), never re-prompted.
assert 'runCheck(model.state, announce: true, userAsked: true)' in try_again, try_again
read_location = declaration(sheet, 'private func readLocation(announce: Bool, precise: Bool)')
assert read_location.index('let outcome = await locator.readOnce(wantsPrecise: precise)') \
    < read_location.index('guard token == generation else { return }') \
    < read_location.index('let clock = ConditionalClockInput.current(for: state)') \
    < read_location.index('location: LocationTrust.checkInInput(outcome, wallNow: clock.wallNow,\n') \
    < read_location.index('country: Self.countryLookup(for: rule)))'), \
    'a late fix never replaces a newer check; the stamp is made on the clock read after the fix'
for state_line in re.findall(r'@State private var [^\n]+', sheet + readers['PlaceEditor.swift']
                             + readers['CountryPicker.swift']):
    for word in ('LocationSample', 'LocationReadOutcome', 'ConditionalLocationFix', 'ConditionalLocationInput',
                 'latitude', 'CLLocation'):
        assert word not in state_line, ('no fix is kept in view state', state_line)
result_src = declaration(presentation, 'struct CheckInResult: Equatable {')
for word in ('latitude', 'longitude', 'ConditionalLocationInput', 'LocationSample'):
    assert f'var {word}' not in result_src and f': {word}' not in result_src.split('static func make')[0], \
        ('a check keeps results, never the fix', word)
assert 'try again' not in sheet.lower().split('case .askpermission:')[1].split('default:')[0], \
    'the card offers Allow location or Not now, no loop'

place_editor = readers['PlaceEditor.swift']
assert 'LocationTrust.centre(outcome, wallNow: Date())' in place_editor
set_here = declaration(place_editor, 'private func setFromHere()')
assert 'case .notAsked:\n            asking = true' in set_here and 'case .denied, .restricted:' in set_here
assert 'ChoiceList(selection: $radius, options: PlaceChoices.sizes.map' in place_editor, 'only the fixed sizes'
assert 'PlaceChoices.otherPlaces(state: model.state, excluding: ruleID)' in place_editor
# Review fix: copying a place cancels a fix still on its way, so it can't
# replace the copied centre a moment later.
copy = place_editor.split('private var copyMenu: some View {', 1)[1].split('} label: {', 1)[0]
assert copy.index('generation += 1') < copy.index('locator.cancel()') < copy.index('centre = PlaceCentre('), copy
assert 'geocode' not in place_editor.lower() and 'Map(' not in place_editor, 'no address search or map (C12)'
print('When & where location source guards passed: one fix, While Using, host only, nothing kept or logged')

# --- Permission strings: build settings, Info.plist, InfoPlist.xcstrings ---
project = (ROOT / 'Latch.xcodeproj/project.pbxproj').read_text()
blocks = re.findall(r'buildSettings = \{(.*?)\n\t\t\t\};', project, re.S)
KEY = 'INFOPLIST_KEY_NSLocationWhenInUseUsageDescription'
host, others = [], []
for block in blocks:
    plist = re.search(r'^\s*INFOPLIST_FILE = ([^;]+);', block, re.M)
    if not plist:
        assert KEY not in block, 'only target settings carry it'
        continue
    (host if plist.group(1).strip() == 'Latch/Info.plist' else others).append(block)
assert len(host) == 2, ('Debug and Release host configurations', len(host))
values = [re.search(KEY + r' = "((?:[^"\\]|\\.)*)";', block) for block in host]
assert all(values) and values[0].group(1) == values[1].group(1), 'Debug and Release use the same purpose string'
when_in_use = values[0].group(1)
assert 'Check in' in when_in_use and "isn't sent" in when_in_use, when_in_use
for block in others:
    assert 'NSLocation' not in block, 'extensions never ask for location'
for word in ('NSLocationAlways', 'NSLocationUsageDescription', 'NSLocationAlwaysAndWhenInUse'):
    assert word not in project, ('While Using only', word)
info = plistlib.loads((ROOT / 'Latch/Info.plist').read_bytes())
assert info.get('UIBackgroundModes') == ['remote-notification', 'fetch'], ('no location background mode', info.get('UIBackgroundModes'))
temporary = info.get('NSLocationTemporaryUsageDescriptionDictionary')
assert isinstance(temporary, dict) and set(temporary) == {'CheckIn'}, temporary
assert 'static let precisePurposeKey = "CheckIn"' in locator, 'the purpose key matches Info.plist'
for key in info:
    assert not key.startswith('NSLocation') or key == 'NSLocationTemporaryUsageDescriptionDictionary', key
for extension in ('LatchMonitor', 'LatchReport', 'LatchWidgets', 'LatchShieldUI'):
    assert b'NSLocation' not in (ROOT / extension / 'Info.plist').read_bytes(), extension
for entitlements in (ROOT / 'Latch').glob('*.entitlements'):
    assert 'location' not in entitlements.read_text().lower(), entitlements.name
catalog = json.loads((ROOT / 'Latch/InfoPlist.xcstrings').read_text())
assert catalog['sourceLanguage'] == 'en'
# Never the display name: Debug ("dev demora") and Release ("demora") differ,
# and one catalog value would rename one of them.
assert set(catalog['strings']) == {'NSLocationWhenInUseUsageDescription', 'CheckIn'}, sorted(catalog['strings'])
LANGUAGES = ['en', 'es', 'de', 'fr', 'pt', 'pl', 'tr', 'hi']
assert sorted(info['CFBundleLocalizations']) == sorted(LANGUAGES)
expected_en = {'NSLocationWhenInUseUsageDescription': when_in_use, 'CheckIn': temporary['CheckIn']}
for key, entry in catalog['strings'].items():
    localizations = entry['localizations']
    assert sorted(localizations) == sorted(LANGUAGES), (key, sorted(localizations))
    for code, value in localizations.items():
        unit = value['stringUnit']
        assert unit['state'] == 'translated' and unit['value'].strip() and '%' not in unit['value'], (key, code)
    assert localizations['en']['stringUnit']['value'] == expected_en[key], ('English matches the plist', key)
    assert len({v['stringUnit']['value'] for v in localizations.values()}) == len(LANGUAGES), ('each language its own', key)
assert not re.search(r'[一-鿿]', json.dumps(catalog, ensure_ascii=False)), 'no stray CJK characters'
privacy = (ROOT / 'Latch/PrivacyInfo.xcprivacy').read_text()
assert 'Location' not in privacy, 'location is processed on the device only: no collected data type (logged decision)'
print('When & where permission strings passed: Debug = Release, While Using only, 2 strings × 8 languages')

# --- Translations of the new place words ------------------------------------
STRING = r'"((?:[^"\\]|\\.)*)"'
keys = set(re.findall(r'return ' + STRING, declaration(presentation, 'enum PlaceChoices {')))
keys.update(re.findall(r'return ' + STRING, declaration(presentation, 'struct PlaceCentreProblem: Error, Equatable {')))
for call in re.findall(r'\btr\((?:[^()"]|"(?:[^"\\]|\\.)*")*\)', place_editor):
    keys.update(re.findall(STRING, call))
keys.update(re.findall(r'return ' + STRING, declaration(presentation, 'var messageKey: String? {')))
keys.discard('')
assert len(keys) > 25, len(keys)
TABLES = {'es': '', 'de': '+German', 'fr': '+French', 'pt': '+Portuguese',
          'pl': '+Polish', 'tr': '+Turkish', 'hi': '+Hindi'}
entry = re.compile(r'^\s*' + STRING + r'\s*:\s*' + STRING + r',?\s*$', re.M)
obsolete = ['Needs your location — arrives in a later update.', 'Location checks arrive in a later update.']
for code, suffix in TABLES.items():
    source = (ROOT / f'Shared/Localization{suffix}.swift').read_text()
    pairs = entry.findall(source)
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
    for key in obsolete:
        assert f'"{key}"' not in source, (code, 'step-3 placeholder left', key)
for key in obsolete:
    assert key not in presentation, key
print(f'When & where location translations passed: {len(keys)} strings × 7 tables')
