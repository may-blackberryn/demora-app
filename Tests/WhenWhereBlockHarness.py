#!/usr/bin/env python3
"""When & where step 6: block check-ins, and proof that free time is unchanged.

Run: python3 Tests/WhenWhereBlockHarness.py

1. **Free time unchanged.** Two binaries run the same deterministic table of
   location checks: one compiles SharedModels.swift, CountryLookup.swift and
   RulesPresentation.swift (with SchedulePrecedence and PhraseWords) as they
   were at BASELINE (step 5, before step 6), the other the current files.
   For ~650 points near borders, enclaves and the sea (real bundled borders),
   11 kinds of fix and every free-time rule shape, each binary hashes the
   engine's evaluation, the check-in's stamp, the sheet's screen and its
   location decisions (read or not, precise or not, retry or not), and
   Today's rows. The two must agree point for point: step 6's "doubt favours
   the stricter result" reaches blocks only.
2. **Blocks** (spec §5.2, §5.6, C3, C4, Q1): the doubt rules on the real
   borders (near Mexico from San Ysidro, Baarle-Hertog, North Cyprus,
   approximate fixes), never a far country.

Only opaque Screen Time tokens and the guarded clock are substituted (the
clock is passed in). No iOS build, simulator, saved state, real location fix
or Screen Time data is involved: nothing here shows a screen or proves that a
block really starts on a phone.
"""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "830dd55"


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


def at_baseline(path):
    return subprocess.run(["git", "show", f"{BASELINE}:{path}"], cwd=ROOT, check=True,
                          capture_output=True, text=True).stdout


def sources(read):
    return {
        "SharedModels.swift": portable(read("Shared/SharedModels.swift")),
        "SchedulePrecedence.swift": portable(read("Shared/SchedulePrecedence.swift")),
        "RulesPresentation.swift": portable(read("Latch/RulesPresentation.swift")),
        "CountryLookup.swift": read("Latch/CountryLookup.swift"),
        "PhraseWords.swift": "import Foundation\n" + declaration(read("Shared/PhraseWords.swift"), "enum PhraseWords {"),
    }


current = sources(lambda path: (ROOT / path).read_text())
baseline = sources(at_baseline)

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
    static func now() -> Date { fatalError("check-in decisions must not read the guarded clock") }
}
'''

# --- 1. Free time unchanged --------------------------------------------------
# Only APIs that exist at BASELINE; free-time rules only.
equivalence_driver = r'''
import Foundation
let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
guard let borders = CountryBorders(data: data) else { print("FAIL: borders"); exit(1) }
var zone = Calendar(identifier: .gregorian)
zone.timeZone = TimeZone(identifier: "America/Mexico_City")!
let noon = zone.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12))!   // a Sunday
let clock = ConditionalClockInput(guardedNow: noon, wallNow: noon, calendar: zone,
                                  recentTimeZoneIDs: ["America/Mexico_City"])
let fixedID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C6")!
func apps(_ name: String) -> FamilyActivitySelection { var s = FamilyActivitySelection(); s.applicationTokens = [name]; return s }

/// FNV-1a over every line, per point, so a difference names its point.
struct Hash { var value: UInt64 = 0xcbf29ce484222325
    mutating func add(_ text: String) { for byte in text.utf8 { value = (value ^ UInt64(byte)) &* 0x100000001b3 }; value = (value ^ 10) &* 0x100000001b3 } }

var centres: [(Double, Double)] = [(32.53, -117.03), (51.44, 4.93), (35.20, 33.40), (47.56, 7.59), (41.90, 12.45),
                                   (48.58, 7.75), (-29.31, 27.48), (36.14, -5.35), (19.43, -99.13), (0.5, -30.0)]
var points: [(Double, Double)] = []
for (lat, lon) in centres { for i in -2...2 { for j in -2...2 { points.append((lat + Double(i) * 0.03, lon + Double(j) * 0.035)) } } }
var seed: UInt64 = 6
func next() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
for _ in 0..<80 { points.append((next() * 140 - 60, next() * 360 - 180)) }

let countries = ["MX", "US", "BE", "NL", "CY", "CH", "DE", "VA", "LS", "GI"]
let sunday = ConditionalCondition.days([1]), monday = ConditionalCondition.days([2])
let midday = ConditionalCondition.time(start: 11 * 60, end: 13 * 60)
var total = 0
for (index, point) in points.enumerated() {
    var hash = Hash()
    let lookup = borders.lookup(latitude: point.0, longitude: point.1)
    hash.add("lookup \(String(describing: lookup?.regionCode)) \(String(describing: lookup?.borderDistanceMeters))")
    let place = ConditionalPlace(name: "Here", latitude: point.0 + 0.002, longitude: point.1, radiusMeters: 500)
    var fixes: [(String, LocationReadOutcome)] = []
    for accuracy in [8.0, 400, 2_500] { for precise in [true, false] {
        fixes.append(("a\(accuracy) p\(precise)", .sample(LocationSample(latitude: point.0, longitude: point.1,
            horizontalAccuracy: accuracy, timestamp: noon.addingTimeInterval(-1), isSimulated: false,
            isFromAccessory: false), precise: precise)))
    } }
    fixes.append(("old", .sample(LocationSample(latitude: point.0, longitude: point.1, horizontalAccuracy: 8,
        timestamp: noon.addingTimeInterval(-20), isSimulated: false, isFromAccessory: false), precise: true)))
    fixes.append(("sim", .sample(LocationSample(latitude: point.0, longitude: point.1, horizontalAccuracy: 8,
        timestamp: noon, isSimulated: true, isFromAccessory: false), precise: true)))
    fixes.append(("acc", .sample(LocationSample(latitude: point.0, longitude: point.1, horizontalAccuracy: 8,
        timestamp: noon, isSimulated: false, isFromAccessory: true), precise: true)))
    fixes.append(("denied", .failed(.denied)))
    fixes.append(("timeout", .failed(.timedOut)))
    var rules: [ConditionalRule] = []
    for kind in [SessionKind.free, .unblock] {
        let outcome = ConditionalOutcome.freeTime(kind: kind, selection: kind == .free ? FamilyActivitySelection() : apps("a"),
                                                  maxMinutes: 60, usesPerDay: 2)
        func rule(_ match: ConditionalMatch, _ conditions: [ConditionalCondition]) -> ConditionalRule {
            ConditionalRule(id: fixedID, name: "R", match: match, conditions: conditions, outcome: outcome, addedAt: noon)
        }
        rules.append(rule(.all, [.place(place)]))
        rules.append(rule(.all, [.place(place), sunday]))
        rules.append(rule(.any, [.place(place), monday]))
        rules.append(rule(.all, [.place(place), .country(lookup?.regionCode ?? "MX")]))
        for code in countries {
            rules.append(rule(.all, [.country(code)]))
            rules.append(rule(.all, [.country(code), sunday, midday]))
            rules.append(rule(.any, [.country(code), monday]))
            rules.append(rule(.any, [.country(code), sunday]))
        }
    }
    // Every fix is at this point: look it up once (the lookup is the slow part).
    let country: LocationTrust.CountryAt = { lat, lon in
        lat == point.0 && lon == point.1 ? lookup : borders.lookup(latitude: lat, longitude: lon)
    }
    for rule in rules {
        var state = LatchState()
        state.conditionalRules = [rule]
        let unread = CheckInResult.make(rule: rule, state: state, clock: clock, location: .notRead, checkInID: fixedID)
        hash.add("rule \(rule.conditions) \(rule.outcome) \(rule.match)")
        hash.add("unread \(unread.evaluation) \(unread.stamp) \(String(describing: unread.used)) \(unread.readLocation)")
        hash.add("decide \(ConditionalCheckIn.fixCouldDecide(rule, evaluation: unread.evaluation)) precise \(ConditionalCheckIn.wantsPrecise(rule))")
        for permission in [LocationPermission.notAsked, .denied, .restricted, .allowed(precise: true), .allowed(precise: false)] {
            hash.add("step \(ConditionalCheckIn.locationStep(unread, permission: permission, sessions: [], now: noon))")
        }
        hash.add("screen \(ConditionalCheckIn.screen(check: unread, live: rule, sessions: [], attempt: nil, now: noon))")
        for (name, outcome) in fixes {
            let input = LocationTrust.checkInInput(outcome, wallNow: noon, country: country)
            let read = CheckInResult.make(rule: rule, state: state, clock: clock, location: input, checkInID: fixedID)
            hash.add("\(name) \(read.evaluation) \(read.stamp) \(read.readLocation)")
            for phase in [CheckInLocationPhase.idle, .reading] {
                hash.add("screen \(ConditionalCheckIn.screen(check: read, live: rule, sessions: [], attempt: nil, now: noon, location: phase))")
            }
            hash.add("retry \(ConditionalCheckIn.wantsPreciseRetry(read, outcome: outcome, country: country))")
            total += 1
        }
        let rows = ConditionalAvailability.todayRows(state: state, used: [rule.id: 0], clock: clock)
        hash.add("today \(rows.rows.map { "\($0.ruleID) \($0.name) \($0.left)" }) \(rows.more)")
    }
    print("\(index) \(String(hash.value, radix: 16))")
}
print("checks \(total)")
'''

block_driver = r'''
import Foundation
var checks = 0
func check(_ ok: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
    if !ok() { print("FAIL: " + message()); exit(1) }
    checks += 1
}
let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
guard let borders = CountryBorders(data: data) else { print("FAIL: borders"); exit(1) }
var mx = Calendar(identifier: .gregorian)
mx.timeZone = TimeZone(identifier: "America/Mexico_City")!
func at(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
    mx.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min, second: s))!
}
func apps(_ names: String...) -> FamilyActivitySelection {
    var s = FamilyActivitySelection(); s.applicationTokens = Set(names); return s
}
func clock(_ wall: Date, guarded: Date? = nil) -> ConditionalClockInput {
    ConditionalClockInput(guardedNow: guarded ?? wall, wallNow: wall, calendar: mx, recentTimeZoneIDs: ["America/Mexico_City"])
}
let sundayNoon = at(11, 15, 12)
let lookupAt: LocationTrust.CountryAt = { borders.lookup(latitude: $0, longitude: $1) }
func blockRule(_ match: ConditionalMatch, _ conditions: [ConditionalCondition],
               until: ConditionalBlockEnd = .time(7 * 60)) -> ConditionalRule {
    ConditionalRule(name: "Block", match: match, conditions: conditions,
                    outcome: .block(mode: .blockSelected, selection: apps("instagram"), until: until), addedAt: at(11, 1))
}
func freeRule(_ match: ConditionalMatch, _ conditions: [ConditionalCondition]) -> ConditionalRule {
    ConditionalRule(name: "Free", match: match, conditions: conditions,
                    outcome: .freeTime(kind: .free, selection: FamilyActivitySelection(), maxMinutes: 60, usesPerDay: 1),
                    addedAt: at(11, 1))
}
func sample(_ p: (Double, Double), accuracy: Double = 20, precise: Bool = true) -> LocationReadOutcome {
    .sample(LocationSample(latitude: p.0, longitude: p.1, horizontalAccuracy: accuracy,
                           timestamp: sundayNoon.addingTimeInterval(-1), isSimulated: false, isFromAccessory: false),
            precise: precise)
}
func row(_ rule: ConditionalRule, _ outcome: LocationReadOutcome) -> ConditionResult {
    ConditionEvaluator.evaluate(rule, clock: clock(sundayNoon),
        location: LocationTrust.checkInInput(outcome, wallNow: sundayNoon, country: lookupAt)).results[0]
}
let mexicoCity = (19.4326, -99.1332), sanYsidroNorth = (32.5560, -117.0300), sanDiego = (32.7157, -117.1611)
let chulaVista = (32.6050, -117.0500)
let baarle = (51.4390, 4.9260), northCyprus = (35.24, 33.6), madrid = (40.4168, -3.7038), losAngeles = (34.05, -118.25)
let inMexico = ConditionalCondition.country("MX")

// MARK: Doubt favours the stricter result, for blocks only (§5.6)
check(row(blockRule(.all, [inMexico]), sample(mexicoCity)) == ConditionResult(status: .met, reason: .inCountry), "Mexico City")
check(row(blockRule(.all, [inMexico]), sample(sanYsidroNorth)) == ConditionResult(status: .met, reason: .nearCountry),
      "San Ysidro, ~2 km into the US: a block can't rule Mexico out")
check(row(freeRule(.all, [inMexico]), sample(sanYsidroNorth)) == .unknown(.nearBorder), "free time still can't tell")
check(row(blockRule(.all, [inMexico]), sample(sanDiego)).status == .notMet, "San Diego (~20 km) is not near enough")
check(row(blockRule(.all, [inMexico]), sample(chulaVista)).status == .notMet
      && row(blockRule(.all, [inMexico]), sample(chulaVista, accuracy: 30, precise: false)).status == .met,
      "approximate location (≥ 10 km) ~7 km from the border: counts for a block, a precise fix doesn't")
check(row(blockRule(.all, [inMexico]), sample(losAngeles, precise: false)).status == .notMet,
      "approximate location far from Mexico: still not met")
check(row(blockRule(.all, [.country("CA")]), sample(sanYsidroNorth)).status == .notMet,
      "near a border only counts for the country across it")
check(row(blockRule(.all, [.country("BE")]), sample(baarle)) == ConditionResult(status: .met, reason: .nearCountry),
      "Baarle-Hertog (Belgian enclave the source leaves out) counts for a Belgium block")
check(row(blockRule(.all, [.country("NL")]), sample(baarle)).status == .met, "…and for a Netherlands block")
check(row(freeRule(.all, [.country("BE")]), sample(baarle)) == .unknown(.nearBorder), "free time: can't tell in Baarle")
check(row(blockRule(.all, [.country("CY")]), sample(northCyprus)).status == .met, "North Cyprus counts for a Cyprus block")
check(row(blockRule(.all, [.country("TR")]), sample(northCyprus)).status == .notMet, "…not for a Turkey block (~70 km)")
check(row(blockRule(.all, [.country("FR")]), sample(madrid)).status == .notMet, "Madrid is not near France")
check(row(blockRule(.all, [inMexico]), .failed(.denied)) == .unknown(.locationOff), "no fix: still can't tell")
let simulated = LocationReadOutcome.sample(LocationSample(latitude: mexicoCity.0, longitude: mexicoCity.1, horizontalAccuracy: 20,
    timestamp: sundayNoon, isSimulated: true, isFromAccessory: false), precise: true)
check(row(blockRule(.all, [inMexico]), simulated) == .unknown(.simulated), "a simulated fix is never doubt")
let near = borders.lookup(latitude: sanYsidroNorth.0, longitude: sanYsidroNorth.1)!
check(near.regionCode == "US" && near.nearbyMeters?["US"] == 0 && (near.nearbyMeters?["MX"] ?? .infinity) < 2_000,
      "the nearby list names the country across the border: \(near)")
check(borders.lookup(latitude: madrid.0, longitude: madrid.1)!.nearbyMeters == ["ES": 0],
      "Madrid: only Spain, nothing else within 100 km")
check(borders.lookup(latitude: northCyprus.0, longitude: northCyprus.1)!.nearbyMeters?["CY"] == 0,
      "an unnamed area: the country next to it may be the answer")
check(borders.rawLookup(latitude: sanYsidroNorth.0, longitude: sanYsidroNorth.1)!.nearbyMeters == nil,
      "the raw lookup has no nearby list")

// Places: a block takes an approximate fix (floored at 10 km by the host).
let home = ConditionalPlace(name: "Home", latitude: 19.43, longitude: -99.13, radiusMeters: 250)
let fiveKm = (19.43 + 5_000 / 111_195, -99.13), thirtyKm = (19.43 + 30_000 / 111_195, -99.13)
check(row(blockRule(.all, [.place(home)]), sample((19.43, -99.13), accuracy: 20)) == ConditionResult(status: .met, reason: .atPlace),
      "precise, inside: at Home")
check(row(blockRule(.all, [.place(home)]), sample(fiveKm, precise: false)) == ConditionResult(status: .met, reason: .nearPlace),
      "approximate, 5 km away: can't rule Home out")
check(row(freeRule(.all, [.place(home)]), sample((19.43, -99.13), precise: false)) == .unknown(.needsPrecise),
      "free time still needs precise location")
check(row(blockRule(.all, [.place(home)]), sample(thirtyKm, precise: false)).status == .notMet, "approximate, 30 km: not met")

// MARK: Saving block rules (the step-1 v1 limits, no "later" problem)
let instagram = blockRule(.any, [.place(home), .time(start: 22 * 60, end: 6 * 60)])
check(EditorValidation.conditional(instagram, existing: nil) == nil && instagram.isValid, "example 2 saves")
check(EditorValidation.conditional(blockRule(.any, [.time(start: 22 * 60, end: 6 * 60)]), existing: nil) == .blockNeedsPlace,
      "a block needs a place or country")
check(EditorValidation.conditional(blockRule(.any, [.place(home), .days([1])]), existing: nil) == .blockAnyOfDays,
      "any of: days can't run on their own")
check(EditorValidation.conditional(blockRule(.all, [.place(home), .days([2, 3, 4, 5, 6])]), existing: nil) == nil,
      "all of: days are fine")
var noApps = instagram
noApps.outcome = .block(mode: .blockSelected, selection: FamilyActivitySelection(), until: .time(420))
check(EditorValidation.conditional(noApps, existing: nil) == .apps, "a block needs apps")
var allExcept = instagram
allExcept.outcome = .block(mode: .blockAllExcept, selection: apps("a"), until: .time(420))
check(EditorValidation.conditional(allExcept, existing: nil) == .invalid && !allExcept.isValid, "v1: chosen apps only")
// Owned windows: under any of, the time runs on its own as a repeating block owned by the rule.
let owned = instagram.ownedSchedules()
check(owned.count == 1 && owned[0].ownerRuleID == instagram.id && owned[0].startMinutes == 22 * 60
      && owned[0].endMinutes == 6 * 60 && owned[0].selection == apps("instagram"), "example 2 owns 22:00–06:00")
check(blockRule(.all, [.place(home), .time(start: 8 * 60, end: 15 * 60)]).ownedSchedules().isEmpty, "all of owns nothing")

// MARK: The check-in sheet for blocks
func stateWith(_ rules: [ConditionalRule]) -> LatchState { var s = LatchState(); s.conditionalRules = rules; return s }
func fixAt(_ p: (Double, Double), precise: Bool = true, accuracy: Double = 20, wall: Date = sundayNoon) -> ConditionalLocationInput {
    LocationTrust.checkInInput(.sample(LocationSample(latitude: p.0, longitude: p.1, horizontalAccuracy: accuracy,
        timestamp: wall.addingTimeInterval(-1), isSimulated: false, isFromAccessory: false), precise: precise),
        wallNow: wall, country: lookupAt)
}
func checkIn(_ rule: ConditionalRule, _ wall: Date, _ location: ConditionalLocationInput, state: LatchState? = nil) -> CheckInResult {
    CheckInResult.make(rule: rule, state: state ?? stateWith([rule]), clock: clock(wall), location: location)
}
func screen(_ result: CheckInResult, state: LatchState? = nil, phase: CheckInLocationPhase = .idle,
            attempt: CheckInAttempt? = nil, wall: Date? = nil) -> CheckInScreen {
    let s = state ?? stateWith([result.rule])
    return ConditionalCheckIn.screen(check: result, live: s.conditionalRules.first { $0.id == result.rule.id },
                                     sessions: s.sessions, attempt: attempt, now: wall ?? result.stamp.guardedAt,
                                     location: phase, pending: s.pending)
}
let atHome = (19.43, -99.13), farAway = (19.43 + 3_000 / 111_195, -99.13)
// Met at home in the afternoon: Block 1 app until 07:00 tomorrow (the engine's own end).
let metHome = checkIn(instagram, sundayNoon, fixAt(atHome))
check(screen(metHome) == .blockMet(endsAt: at(11, 16, 7)) && screen(metHome).canStart, "met at home: until 07:00 → \(screen(metHome))")
check(ConditionalCheckIn.startCap(screen(metHome)) == 1, "a block sends no length of its own")
check(ConditionalCheckIn.blockQuestion(metHome, endsAt: "07:00", translate: { $0 }, locale: Locale(identifier: "en_GB"))
      == "Block 1 app until 07:00?", "the question")
// The stamp the sheet holds is what the engine's plan accepts, and it ends where the sheet says.
let request = ConditionalStartRequest(ruleID: instagram.id, revision: instagram.revision, minutes: 1, stamp: metHome.stamp)
if case .success(let plan) = ConditionalStart.plan(request, state: stateWith([instagram]), clock: clock(sundayNoon)) {
    check(plan.session.kind == .block && plan.session.endsAt == at(11, 16, 7) && plan.uses.isEmpty, "engine agrees")
} else { check(false, "the engine refused the sheet's block stamp") }
// Not at home, outside the window: not met; in the window but away: it blocks on its own, nothing to start.
check(screen(checkIn(instagram, sundayNoon, fixAt(farAway))) == .notMet, "away at noon")
let awayAtNight = checkIn(instagram, at(11, 15, 23), fixAt(farAway, wall: at(11, 15, 23)))
check(screen(awayAtNight) == .blockOnItsOwn(until: at(11, 16, 6)) && !screen(awayAtNight).canStart,
      "away at 23:00: the window already blocks until 06:00 → \(screen(awayAtNight))")
// At home at 23:00: the check-in block runs to 07:00, past the window's 06:00.
check(screen(checkIn(instagram, at(11, 15, 23), fixAt(atHome, wall: at(11, 15, 23)))) == .blockMet(endsAt: at(11, 16, 7)),
      "at home at night: until 07:00")
// Doubt counts for a block: approximate location 5 km away, near a border.
check(screen(checkIn(instagram, sundayNoon, fixAt(fiveKm, precise: false))).canStart, "approximate near home: can start")
let mexicoBlock = blockRule(.all, [inMexico], until: .duration(minutes: 180))
let nearMexico = checkIn(mexicoBlock, sundayNoon, fixAt(sanYsidroNorth))
check(screen(nearMexico).canStart && nearMexico.evaluation.results[0].reason == .nearCountry, "near the border: can start")
check(ConditionalCheckIn.reason(nearMexico.evaluation.results[0], condition: inMexico, translate: { $0 },
      locale: Locale(identifier: "en_GB"), calendar: mx) == "Close enough to Mexico to count for a block", "doubt reason")
check(ConditionalCheckIn.blockQuestion(nearMexico, endsAt: "15:00", translate: { $0 }, locale: Locale(identifier: "en_GB"))
      .hasPrefix("Block 1 app for "), "a whole duration reads 'for'")
// All of with a window: the end is capped at the window end, and the question says until.
let school = blockRule(.all, [.place(home), .time(start: 8 * 60, end: 15 * 60)], until: .duration(minutes: 600))
let atSchool = checkIn(school, at(11, 16, 14), fixAt(atHome, wall: at(11, 16, 14)))
check(screen(atSchool) == .blockMet(endsAt: at(11, 16, 15)) && !atSchool.blockRunsFullDuration, "capped at 15:00")
check(ConditionalCheckIn.blockQuestion(atSchool, endsAt: "15:00", translate: { $0 }, locale: Locale(identifier: "en_GB"))
      == "Block 1 app until 15:00?", "capped: until")
check(screen(checkIn(school, at(11, 16, 14, 59, 30), fixAt(atHome, wall: at(11, 16, 14, 59, 30)))) == .windowEnding,
      "under a minute left in the window")
check(screen(checkIn(school, at(11, 16, 16), .notRead)) == .notMet, "all of: after the window, no read can help")
// Before a read: under any of a place is never "not needed" for a block.
let unread = checkIn(instagram, at(11, 15, 23), .notRead)
check(screen(unread) == .needsLocation && screen(unread, phase: .asking) == .askPermission
      && screen(unread, phase: .reading) == .locating, "any of in its window: still asks for the place")
check(ConditionalCheckIn.shown(unread.evaluation.results[0], condition: instagram.conditions[0], rule: instagram)
      == .unknown(.notChecked), "the place row reads 'not checked yet', not 'not needed'")
let freeTwin = ConditionalRule(name: "Free", match: .any, conditions: instagram.conditions,
    outcome: .freeTime(kind: .free, selection: FamilyActivitySelection(), maxMinutes: 60, usesPerDay: 1), addedAt: at(11, 1))
let freeUnread = checkIn(freeTwin, at(11, 15, 23), .notRead)
check(ConditionalCheckIn.shown(freeUnread.evaluation.results[0], condition: freeTwin.conditions[0], rule: freeTwin)
      == freeUnread.evaluation.results[0], "free time rows unchanged")
// Location steps: a block reads once when asked, never asks for precise, never retries for precise.
let allowed = LocationPermission.allowed(precise: false)
check(ConditionalCheckIn.locationStep(unread, permission: allowed, sessions: [], now: at(11, 15, 23)) == .read, "reads once")
check(ConditionalCheckIn.locationStep(unread, permission: .notAsked, sessions: [], now: at(11, 15, 23)) == .ask, "card first")
check(ConditionalCheckIn.locationStep(unread, permission: .denied, sessions: [], now: at(11, 15, 23)) == .off, "denied: off")
check(!ConditionalCheckIn.wantsPrecise(instagram) && !ConditionalCheckIn.wantsPrecise(mexicoBlock), "a block never asks for precise")
let approxNear = LocationReadOutcome.sample(LocationSample(latitude: sanYsidroNorth.0, longitude: sanYsidroNorth.1,
    horizontalAccuracy: 50, timestamp: sundayNoon, isSimulated: false, isFromAccessory: false), precise: false)
check(!ConditionalCheckIn.wantsPreciseRetry(checkIn(mexicoBlock, sundayNoon,
      LocationTrust.checkInInput(approxNear, wallNow: sundayNoon, country: lookupAt)), outcome: approxNear, country: lookupAt),
      "no precise retry for a block")

// MARK: Running, waiting, refusals: a check-in never ends or shortens a block (Q1)
var running = BlockSession(name: "Block", kind: .block, selection: apps("instagram"),
                           startedAt: sundayNoon.addingTimeInterval(-60), endsAt: at(11, 16, 7))
running.conditionalRuleID = instagram.id
var withRunning = stateWith([instagram]); withRunning.sessions = [running]
check(screen(metHome, state: withRunning) == .blockRunning(until: at(11, 16, 7)), "running wins over a met check")
check(ConditionalCheckIn.locationStep(unread, permission: allowed, sessions: [running], now: at(11, 15, 23)) == .none,
      "no read while its block runs")
let shorter = ConditionalStartRequest(ruleID: instagram.id, revision: 0, minutes: 1, stamp: metHome.stamp)
if case .failure(let refusal) = ConditionalStart.plan(shorter, state: withRunning, clock: clock(sundayNoon)) {
    check(refusal == .alreadyRunning, "a second check-in can't replace (shorten) a running block: \(refusal)")
} else { check(false, "a check-in replaced a running block") }
for phase in [ConditionalStart.Phase.queue, .apply] {
    if case .success = ConditionalStart.plan(shorter, state: withRunning, clock: clock(sundayNoon), phase: phase) {
        check(false, "a check-in replaced a running block at \(phase)")
    }
}
let waitingChange = PendingChange(createdAt: sundayNoon, appliesAt: sundayNoon.addingTimeInterval(600), direction: .stricter,
                                  summary: "Start block: Block", action: .startConditionalSession(request))
var withWaiting = stateWith([instagram]); withWaiting.pending = [waitingChange]
check(screen(metHome, state: withWaiting) == .blockWaiting(startsAt: sundayNoon.addingTimeInterval(600)), "one waiting start")
check(ConditionalCheckIn.locationStep(unread, permission: allowed, sessions: [], now: at(11, 15, 23),
                                      pending: withWaiting.pending) == .none, "no read while a start waits")
check(screen(metHome, attempt: .waiting) == .blockMet(endsAt: at(11, 16, 7)), "a block attempt never reads as free time queued")
check(screen(metHome, attempt: .refused(.unavailable)) == .refused(.unavailable), "refusals shown")
check(ConditionalCheckIn.heroKey(.refused(.unavailable), block: true) == "The block didn't start."
      && ConditionalCheckIn.refusalKey(.unavailable, block: true).hasPrefix("The block")
      && ConditionalCheckIn.refusalKey(.alreadyRunning, block: true) == "A block from this rule is already on."
      && ConditionalCheckIn.detailKey(.clockChanged, block: true)!.contains("The block"), "block words")
check(ConditionalCheckIn.heroKey(.refused(.unavailable)) == "Free time didn't start.", "free words unchanged")
check(ConditionalCheckIn.checkedAgainKey(block: true) == "Checked again. Review it again to start.", "re-check words")
// Clock changed: nothing starts, the block says why.
let skewed = CheckInResult.make(rule: instagram, state: stateWith([instagram]),
                                clock: clock(sundayNoon, guarded: sundayNoon.addingTimeInterval(900)), location: fixAt(atHome))
check(screen(skewed) == .clockChanged, "clock changed: \(screen(skewed))")
// Re-check after a hold/Confirm on an aged check: only the same rule, day and zone, still met.
let later = checkIn(instagram, sundayNoon.addingTimeInterval(130), fixAt(atHome, wall: sundayNoon.addingTimeInterval(130)))
check(ConditionalCheckIn.needsRecheck(metHome, live: instagram, clock: clock(sundayNoon.addingTimeInterval(115))), "aged")
check(ConditionalCheckIn.mayStartAfterRecheck(old: metHome, fresh: later, live: instagram, sessions: [],
                                              now: sundayNoon.addingTimeInterval(130)), "re-checked at home: send")
check(!ConditionalCheckIn.mayStartAfterRecheck(old: metHome, fresh: later, live: instagram, sessions: [],
                                               now: sundayNoon.addingTimeInterval(130), pending: withWaiting.pending),
      "never a second start while one waits")
let awayLater = checkIn(instagram, sundayNoon.addingTimeInterval(130), fixAt(farAway, wall: sundayNoon.addingTimeInterval(130)))
check(!ConditionalCheckIn.mayStartAfterRecheck(old: metHome, fresh: awayLater, live: instagram, sessions: [],
                                               now: sundayNoon.addingTimeInterval(130)), "walked away: show, don't send")

// MARK: Today rows, card line
func todayRows(_ s: LatchState, _ wall: Date) -> [ConditionalAvailability.Row] {
    ConditionalAvailability.todayRows(state: s, used: [:], clock: clock(wall)).rows
}
check(todayRows(stateWith([instagram]), sundayNoon).map(\.startsBlock) == [true], "a block with a place: a row")
check(todayRows(stateWith([school]), at(11, 16, 9)).count == 1 && todayRows(stateWith([school]), at(11, 16, 16)).isEmpty,
      "all of: only inside its window")
check(todayRows(withRunning, sundayNoon).isEmpty && todayRows(withWaiting, sundayNoon).isEmpty, "not while one runs or waits")
check(todayRows(stateWith([blockRule(.all, [.place(home)], until: .time(420))]), sundayNoon).count == 1, "place only")
let index = RulePending.index(withWaiting.pending)
check(RulePending.ref(for: waitingChange) == nil, "a waiting start doesn't lock Edit / Remove")
check(RulePending.cardChange(for: .conditional(instagram.id), in: index, state: withWaiting, now: sundayNoon)?.id
      == waitingChange.id, "the card shows the waiting block")
check(RulePending.label(change: waitingChange, state: withWaiting) == .starts, "Starts in")
check(!RulePending.blocksEdit(of: .conditional(instagram.id), pending: withWaiting.pending), "edit stays available")
'''

# --- Build and run ----------------------------------------------------------
with tempfile.TemporaryDirectory(prefix="demora-whenwhere-block-") as directory:
    folder = Path(directory)
    data = ROOT / "Latch/CountryBorders.bin"
    outputs = {}
    # DEMORA_SKIP_EQUIVALENCE=1 skips part 1 while iterating; the full verify never sets it.
    skip = os.environ.get("DEMORA_SKIP_EQUIVALENCE") == "1"
    for name, files in (() if skip else (("baseline", baseline), ("current", current))):
        sub = folder / name
        sub.mkdir()
        (sub / "Infrastructure.swift").write_text(infrastructure)
        for file, text in files.items():
            (sub / file).write_text(text)
        (sub / "main.swift").write_text(equivalence_driver)
        binary = sub / "run"
        subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-O", *sorted(str(p) for p in sub.glob("*.swift")),
                        "-o", str(binary)], check=True)
        outputs[name] = subprocess.run([str(binary), str(data)], check=True, capture_output=True, text=True).stdout
    old_lines, new_lines = (outputs["baseline"].splitlines(), outputs["current"].splitlines()) if not skip else ([], [])
    if skip:
        print("SKIPPED: free-time equivalence (DEMORA_SKIP_EQUIVALENCE=1)")
    assert skip or (len(old_lines) == len(new_lines) and len(new_lines) > 300), (len(old_lines), len(new_lines))
    for old, new in zip(old_lines, new_lines):
        assert old == new, f"free time changed since {BASELINE} at point {old.split()[0]}: {old} vs {new}"
    compared = int(new_lines[-1].split()[1]) if new_lines else 0
    if not skip: print(f"Free time unchanged since {BASELINE}: {len(new_lines) - 1} points × every free rule shape, "
          f"{compared:,} location checks (evaluation, stamp, screen, read/precise/retry, Today rows) agree")

    sub = folder / "block"
    sub.mkdir()
    (sub / "Infrastructure.swift").write_text(infrastructure)
    for file, text in current.items():
        (sub / file).write_text(text)
    (sub / "main.swift").write_text(block_driver + '\nprint("When & where blocks passed: \\(checks) checks")\n')
    binary = sub / "run"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-O", *sorted(str(p) for p in sub.glob("*.swift")),
                    "-o", str(binary)], check=True)
    result = subprocess.run([str(binary), str(data)], capture_output=True, text=True)
    print(result.stdout.strip())
    if result.returncode != 0:
        print(result.stderr)
        raise SystemExit(1)

# --- Source guards ----------------------------------------------------------
models_now = (ROOT / "Shared/SharedModels.swift").read_text()
location_result = declaration(models_now, "static func locationResult(")
old_location_result = declaration(baseline["SharedModels.swift"], "static func locationResult(")
# The free-time lines of the evaluator are the same text as at the baseline.
for kept in ["if free && fix.isFromAccessory { return .unknown(.accessory) }",
             "if distance + accuracy <= radius { return ConditionResult(status: .met, reason: .atPlace) }",
             "if distance - accuracy > radius { return ConditionResult(status: .notMet, reason: .notAtPlace) }",
             "return .unknown(.imprecise)",
             "let clear = country.borderDistanceMeters > accuracy + borderMargin",
             "if inside && clear { return ConditionResult(status: .met, reason: .inCountry) }",
             "if !inside && clear { return ConditionResult(status: .notMet, reason: .notInCountry) }",
             "return .unknown(.nearBorder)"]:
    assert kept in location_result and kept in old_location_result, kept
assert "nearbyMeters" not in location_result.split("if !free {", 1)[0], "free time never reads the nearby list"
assert location_result.count("nearbyMeters") == 1
print("When & where block source guards passed: free-time evaluator lines unchanged; nearby list read only for blocks")

sheet = (ROOT / "Latch/CheckInSheet.swift").read_text()
receipt_src = (ROOT / "Latch/ChangeReceiptSheet.swift").read_text()
# Review → the receipt (stricter, its own wait) → the check-in's one start path.
review = declaration(sheet, "private func review(endsAt: Date, now: Date)")
assert "ChangeReceiptRequest(action: .startConditionalSession(request), note: note," in review
assert "perform: { start(cap: 1) })" in review, "Confirm goes through start (re-check, one request)"
assert sheet.count("startConditionalSessionOffMain(") == 1, "one start path for free time and blocks"
assert sheet.count(".changeReceipt($receipt)") == 1
assert "if let check, !starting, receipt == nil, locationPhase == .idle," in sheet, \
    "no refresh on its own while the receipt is open"
assert 'primary(tr("Review")) { review(endsAt: endsAt, now: now) }' in sheet
assert ".disabled(starting || receipt != nil)" in sheet
commit = declaration(receipt_src, "private func commit()")
assert commit.index("if let canQueue, !canQueue()") < commit.index("if let perform {") < commit.index("model.queue(action)"), \
    "the hand-off replaces the queue, after the same check"
handoff = commit[commit.index("if let perform {"):commit.index("model.queue(action)")]
assert "guard !handedOff else { return }" in handoff and "handedOff = true" in handoff and "return" in handoff
assert "perform: request.perform" in receipt_src
# The receipt shows the start's own direction and wait: nothing bypasses the stricter delay.
assert "let (direction, delay) = model.preview(action)" in declaration(receipt_src, "private func content(now: Date)")
summary = (ROOT / "Latch/RuleSummarySheet.swift").read_text()
assert "if let waiting = RulePending.waitingStart(of: id, in: state.pending) {" in summary
today = (ROOT / "Latch/TodayView.swift").read_text()
assert 'row.startsBlock ? tr("starts a block")' in today
# No "later update" copy is left for When & where anywhere.
for folder in ("Latch", "Shared"):
    for path in (ROOT / folder).glob("*.swift"):
        text = path.read_text()
        for gone in ("arrive in a later update", "arrives in a later update", "arrivesLater", "blockLater",
                     "This rule can't be checked yet.", "CheckInLater"):
            assert gone not in text, (gone, path.name)

# Every new string in all seven tables, placeholders kept.
keys = ["Close enough to %@ to count for a block", "The block didn't start.", "Block %@ until %@?", "Block %@ for %@?",
        "The block is on until %@.", "This block is on until %@.", "The block starts at %@.",
        "Checked again. Review it again to start.",
        "Your clock was changed recently. The block can start once it's set right again.",
        "Leaving doesn't end it. Ending it early waits like any looser change.",
        "Its time blocks on its own, without a check-in.",
        "It waits your stricter delay, like Block now. It's in Changes.", "A block from this rule is already on.",
        "The block couldn't start safely. iOS may not be able to track another session right now. Nothing changed.",
        "Review", "Then runs until %@.", "starts a block"]
presentation_now = current["RulesPresentation.swift"]
for key in keys:
    assert f'"{key}"' in presentation_now + sheet + today, f"unused key: {key}"
tables = ["Localization.swift", "Localization+German.swift", "Localization+French.swift", "Localization+Portuguese.swift",
          "Localization+Polish.swift", "Localization+Turkish.swift", "Localization+Hindi.swift"]
for table in tables:
    text = (ROOT / "Shared" / table).read_text()
    for key in keys:
        match = re.search(r'^    "' + re.escape(key.replace('"', '\\"')) + r'": "((?:\\.|[^"\\])*)",$', text, re.M)
        assert match, (table, key)
        assert match[1].count("%@") == key.count("%@") and match[1].count("%d") == key.count("%d"), (table, key)
        assert match[1] != key, (table, key, "untranslated")
    for gone in ("Blocks that start when you check in arrive in a later update. For now, use a repeating block or Block now.",
                 "Starting a block when you check in arrives in a later update.", "This rule can't be checked yet."):
        assert f'"{gone}"' not in text, (table, gone)
print(f"When & where block wiring passed: receipt hand-off, one start path, no later-update copy; "
      f"{len(keys)} strings × {len(tables)} tables")
