#!/usr/bin/env python3
"""When & where step 5: countries from the bundled offline borders.

Checks (docs/conditional-sessions-redesign.md §5.6, §5.7; C5, C9, Q4):
- the bundled `Latch/CountryBorders.bin`: size budget (≤ 1 MB), header, its
  SHA-256 and the pinned Natural Earth source recorded in
  `Latch/COUNTRY_BORDERS_ATTRIBUTION.md` and the generator, which never
  downloads anything;
- an independent Python decode of the same file (point count, codes, and
  point-in-polygon at the test points) agreeing with the Swift lookup;
- the real `Latch/CountryLookup.swift` on the real file, compiled with the
  real SharedModels and RulesPresentation: Mexico City and a Sunday-in-Mexico
  rule all the way to `ConditionalStart.plan`; Tijuana / San Diego and other
  points near a border "can't tell"; open sea none; Fiji and Russia across
  the antimeridian; the Lesotho enclave; disputed areas; tripoints; the
  decoder refusing damaged data; "Use the country I'm in" and the picker's
  names (iOS's, in the app's language);
- source guards: no network, geocoder, map or logging in the lookup, the
  picker or the check-in; the data only in the host app; the credit in You.

No device, simulator or real fix: this shows the lookup's answers for given
points, not how accurate a fix iOS delivers abroad.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'Latch/CountryBorders.bin'
ATTRIBUTION = ROOT / 'Latch/COUNTRY_BORDERS_ATTRIBUTION.md'
GENERATOR = ROOT / 'Tests/GenerateCountryBorders.py'
SIZE_BUDGET = 1_000_000

# --- The bundled file, its source and its credit ---------------------------
blob = DATA.read_bytes()
digest = hashlib.sha256(blob).hexdigest()
assert len(blob) <= SIZE_BUDGET, ('bundled borders over the 1 MB budget', len(blob))
attribution = ATTRIBUTION.read_text()
generator = GENERATOR.read_text()
assert f'Bundled file SHA-256: {digest}' in attribution, ('attribution records the bundled checksum', digest)
assert f'{len(blob):,} bytes' in attribution, 'attribution records the size'
source_sha = re.search(r"'sha256': '([0-9a-f]{64})'", generator).group(1)
source_url = re.search(r"'url': '([^']+)'\s*\n\s*'([^']+)'", generator)
source_url = source_url.group(1) + source_url.group(2)
version = re.search(r"'version': '([^']+)'", generator).group(1)
assert f'Source SHA-256: {source_sha}' in attribution and source_url in attribution, 'source pinned in both places'
assert source_url.startswith('https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v' + version + '/'), \
    'the official Natural Earth repository, at the pinned release'
assert f'version {version}' in attribution and 'public domain' in attribution and 'Natural Earth' in attribution
for word in ('urllib', 'requests', 'http.client', 'socket', 'subprocess', 'urlopen'):
    assert word not in generator.split('"""', 2)[2], ('the generator never downloads', word)

# Independent decode (format version 1, Tests/GenerateCountryBorders.py).
assert blob[:4] == b'DMCB' and blob[4] == 1
units, count = struct.unpack_from('<IH', blob, 5)
offset = 11


def varint():
    global offset
    value = shift = 0
    while True:
        byte = blob[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value
        shift += 7


entries = {}
points = 0
for _ in range(count):
    code = blob[offset:offset + 2].decode('ascii')
    offset += 2
    rings = []
    for _ in range(varint()):
        n = varint()
        x = y = 0
        ring = []
        for _ in range(n):
            dx, dy = varint(), varint()
            x += (dx >> 1) ^ -(dx & 1)
            y += (dy >> 1) ^ -(dy & 1)
            ring.append((x / units, y / units))
        rings.append(ring)
        points += n
    entries[code] = rings
assert offset == len(blob), 'no trailing bytes'
codes = sorted(c for c in entries if c != '~~')
assert '~~' in entries and len(codes) == len(entries) - 1
for code in ('MX', 'US', 'FJ', 'RU', 'LS', 'ZA', 'VA', 'XK', 'GI', 'CY', 'AQ'):
    assert code in entries, code
assert f'{len(entries)} entries, {points:,} points' in attribution, (len(entries), points)


def python_contains(lat, lon):
    found = []
    for code, rings in entries.items():
        inside = False
        for ring in rings:
            j = len(ring) - 1
            for i in range(len(ring)):
                xi, yi = ring[i]
                xj, yj = ring[j]
                if (yi > lat) != (yj > lat) and lon < xi + (lat - yi) * (xj - xi) / (yj - yi):
                    inside = not inside
                j = i
        if inside:
            found.append(code)
    return found


PROBES = {  # name: (lat, lon) — also used by the Swift driver below
    'mexicoCity': (19.4326, -99.1332), 'tijuanaSouth': (32.4900, -117.0300), 'tijuanaCentre': (32.5149, -117.0382),
    'sanYsidroSouth': (32.5330, -117.0300), 'sanYsidroNorth': (32.5560, -117.0300), 'sanDiego': (32.7157, -117.1611),
    'suva': (-18.1416, 178.4419), 'taveuniWest': (-16.83, 179.99), 'taveuniEast': (-16.83, -179.99),
    'chukotkaWest': (67.0, 178.0), 'chukotkaEast': (67.0, -178.0), 'wrangelWest': (71.25, 179.9),
    'wrangelEast': (71.25, -179.9), 'lesotho': (-29.6, 28.2), 'bloemfontein': (-29.12, 26.21),
    'maseru': (-29.31, 27.48), 'vatican': (41.9029, 12.4534), 'northCyprus': (35.24, 33.6), 'paphos': (34.775, 32.42),
    'pristina': (42.6629, 21.1655), 'gibraltar': (36.14, -5.35), 'madrid': (40.4168, -3.7038),
}
python_inside = {name: python_contains(*point) for name, point in PROBES.items()}

# Review fix: enclaves Natural Earth leaves out are "can't tell" zones.
enclaves = [(name[1:-1], lat, lon, radius) for name, lat, lon, radius in re.findall(
    r"""\(("[^"]+"|'[^']+'), (-?[\d.]+), (-?[\d.]+), ([\d_]+)\)""",
    generator.split('MISSING_ENCLAVES = (', 1)[1].split('\n)', 1)[0])]
assert len(enclaves) == 8, enclaves
assert any('Baarle' in name for name, *_ in enclaves) and any('Büsingen' in name for name, *_ in enclaves)
assert 'eight small enclaves the dataset leaves out' in attribution

# Review fix: an independent distance for sampled points near land borders.
# Python measures each edge on a plane local to the point; Swift's lower
# bound must never report more than that (a wrong country with a "clear"
# distance), and not grossly less.
import math
import random
METRES = math.pi / 180 * 6_371_000
ring_boxes = [(code, ring, min(x for x, _ in ring), max(x for x, _ in ring), min(y for _, y in ring), max(y for _, y in ring))
              for code, rings in entries.items() for ring in rings]
shared = {}
for code, rings in entries.items():
    for ring in rings:
        for point in ring:
            shared.setdefault(point, set()).add(code)
border_points = sorted(p for p, owners in shared.items() if len(owners) > 1 and '~~' not in owners)
coast_points = sorted(p for p, owners in shared.items() if len(owners) == 1 and '~~' not in owners)
rng = random.Random(5)
samples = []
for lon, lat in rng.sample(border_points, 160) + rng.sample(coast_points, 80):
    angle, r = rng.random() * 2 * math.pi, 1_000 + 4_000 * rng.random()
    samples.append((lat + r * math.sin(angle) / METRES, lon + r * math.cos(angle) / (METRES * math.cos(math.radians(lat)))))


def python_distances(lat, lon, window=60_000):
    inside, near = {}, {}
    pad = window / METRES
    scale = math.cos(math.radians(lat))
    for code, ring, x0, x1, y0, y1 in ring_boxes:
        if not (y0 - pad <= lat <= y1 + pad and x0 - pad / max(scale, 0.01) <= lon <= x1 + pad / max(scale, 0.01)):
            continue
        j = len(ring) - 1
        best = near.get(code, math.inf)
        crossing = False
        for i in range(len(ring)):
            (xi, yi), (xj, yj) = ring[i], ring[j]
            if (yi > lat) != (yj > lat) and lon < xi + (lat - yi) * (xj - xi) / (yj - yi):
                crossing = not crossing
            ax, ay, bx, by = (xj - lon) * scale, yj - lat, (xi - lon) * scale, yi - lat
            dx, dy = bx - ax, by - ay
            t = 0 if dx == dy == 0 else max(0, min(1, -(ax * dx + ay * dy) / (dx * dx + dy * dy)))
            best = min(best, math.hypot(ax + t * dx, ay + t * dy) * METRES)
            j = i
        near[code] = best
        if crossing:
            inside[code] = not inside.get(code, False)
    return [c for c, v in inside.items() if v], near


python_samples = []
for lat, lon in samples:
    inside, near = python_distances(lat, lon)
    if len(inside) == 1 and inside[0] != '~~':
        others = [v for c, v in near.items() if c != inside[0]]
        if others and min(others) < 50_000:
            python_samples.append((lat, lon, inside[0], min(others)))
assert len(python_samples) > 120, len(python_samples)
expected_inside = {'mexicoCity': ['MX'], 'tijuanaSouth': ['MX'], 'tijuanaCentre': ['MX'], 'sanYsidroSouth': ['MX'],
                   'sanYsidroNorth': ['US'], 'sanDiego': ['US'], 'suva': ['FJ'], 'chukotkaWest': ['RU'],
                   'chukotkaEast': ['RU'], 'lesotho': ['LS'], 'bloemfontein': ['ZA'], 'maseru': ['LS'],
                   'vatican': ['VA'], 'northCyprus': ['~~'], 'paphos': ['CY'], 'pristina': ['XK'],
                   'gibraltar': ['GI'], 'madrid': ['ES']}
for name, want in expected_inside.items():
    assert python_inside[name] == want, (name, python_inside[name], want)
print(f'Country borders data passed: {len(blob):,} bytes (budget {SIZE_BUDGET:,}), {len(entries)} entries, '
      f'{points:,} points, sha256 {digest[:12]}…, Natural Earth {version}, public domain')


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
lookup_source = (ROOT / 'Latch/CountryLookup.swift').read_text()
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
    static func now() -> Date { fatalError("the country lookup must not read the guarded clock") }
}
'''

probes = '\n'.join(f'let {name} = ({lat}, {lon})' for name, (lat, lon) in PROBES.items())
driver = r'''
import Foundation
var checks = 0
func check(_ ok: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
    if !ok() { print("FAIL: " + message()); exit(1) }
    checks += 1
}
''' + probes + r'''
let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let sampleLines = try! String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8).split(separator: "\n")
let loadStart = Date()
guard let borders = CountryBorders(data: data) else { print("FAIL: the bundled borders don't decode"); exit(1) }
let loadSeconds = Date().timeIntervalSince(loadStart)
check(borders.pointCount == ''' + str(points) + r''', "same point count as the Python decode")
check(borders.regionCodes == [''' + ', '.join(f'"{c}"' for c in codes) + r'''], "same codes, no unidentified entry")
func at(_ p: (Double, Double)) -> ConditionalCountryLookup { borders.lookup(latitude: p.0, longitude: p.1)! }
// The answer free time reads (region and border distance); the nearby list is
// for block check-ins (step 6) and is checked in Tests/WhenWhereBlockHarness.py.
infix operator ==~: ComparisonPrecedence
func ==~ (l: ConditionalCountryLookup, r: ConditionalCountryLookup) -> Bool {
    l.regionCode == r.regionCode && l.borderDistanceMeters == r.borderDistanceMeters
}
func raw(_ p: (Double, Double)) -> ConditionalCountryLookup { borders.rawLookup(latitude: p.0, longitude: p.1)! }
let allowance = CountryBorders.datasetAllowanceMeters
check(allowance == 1_000 && CountryBorders.coastBandMeters == 2_000, "1 km dataset allowance, 2 km coast band")

// MARK: Rules and the engine with the real lookup
var mx = Calendar(identifier: .gregorian)
mx.timeZone = TimeZone(identifier: "America/Mexico_City")!
let gb = Locale(identifier: "en_GB")
let say: RuleText.Translate = { $0 }
func day(_ m: Int, _ d: Int, _ h: Int) -> Date { mx.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))! }
let sundayNoon = day(11, 15, 12), mondayNoon = day(11, 16, 12)
check(mx.component(.weekday, from: sundayNoon) == 1, "15 Nov 2026 is a Sunday")
func clock(_ wall: Date) -> ConditionalClockInput {
    ConditionalClockInput(guardedNow: wall, wallNow: wall, calendar: mx, recentTimeZoneIDs: ["America/Mexico_City"])
}
let none = FamilyActivitySelection()
func free(_ name: String, _ match: ConditionalMatch, _ conditions: [ConditionalCondition]) -> ConditionalRule {
    ConditionalRule(name: name, match: match, conditions: conditions,
                    outcome: .freeTime(kind: .free, selection: none, maxMinutes: 60, usesPerDay: 1), addedAt: day(11, 1, 9))
}
func stateWith(_ rule: ConditionalRule) -> LatchState { var s = LatchState(); s.conditionalRules = [rule]; return s }
let realLookup: LocationTrust.CountryAt = { borders.lookup(latitude: $0, longitude: $1) }
func sample(_ p: (Double, Double), accuracy: Double = 20, simulated: Bool = false, accessory: Bool = false,
            now: Date = sundayNoon) -> LocationSample {
    LocationSample(latitude: p.0, longitude: p.1, horizontalAccuracy: accuracy, timestamp: now.addingTimeInterval(-2),
                   isSimulated: simulated, isFromAccessory: accessory)
}
func checkIn(_ rule: ConditionalRule, _ s: LocationSample, precise: Bool = true, now: Date = sundayNoon) -> CheckInResult {
    CheckInResult.make(rule: rule, state: stateWith(rule), clock: clock(now),
                       location: LocationTrust.checkInInput(.sample(s, precise: precise), wallNow: now, country: realLookup))
}
func countryRow(_ rule: ConditionalRule, _ s: LocationSample, precise: Bool = true, now: Date = sundayNoon) -> ConditionResult {
    checkIn(rule, s, precise: precise, now: now).evaluation.results[0]
}
let mexicoSunday = free("Sunday in Mexico", .all, [.country("MX"), .days([1])])
let inMexico = free("In Mexico", .all, [.country("MX")])
let inUS = free("In the US", .all, [.country("US")])

// Mexico City: ✓ in Mexico, met on a Sunday, and the engine starts it.
check(at(mexicoCity).regionCode == "MX" && at(mexicoCity).borderDistanceMeters > 400_000, "Mexico City: deep in Mexico")
let sunday = checkIn(mexicoSunday, sample(mexicoCity))
check(sunday.evaluation.results.map(\.status) == [.met, .met] && sunday.evaluation.isMet, "Sunday in Mexico: met")
check(ConditionalCheckIn.reason(sunday.evaluation.results[0], condition: .country("MX"), translate: say, locale: gb,
      calendar: mx) == "You're in Mexico", "✓ You're in Mexico (iOS's name)")
check(sunday.stamp.results == [true, true], "stamp: booleans only")
check(ConditionalCheckIn.screen(check: sunday, live: mexicoSunday, sessions: [], attempt: nil, now: sundayNoon) == .met(cap: 60),
      "the sheet offers free time")
if case .success(let plan) = ConditionalStart.plan(
    ConditionalStartRequest(ruleID: mexicoSunday.id, revision: mexicoSunday.revision, minutes: 60, stamp: sunday.stamp),
    state: stateWith(mexicoSunday), clock: clock(sundayNoon.addingTimeInterval(10))) {
    check(plan.session.conditionalRuleID == mexicoSunday.id, "the engine starts the Sunday-in-Mexico session")
} else { check(false, "the engine accepts a met country check") }
check(!checkIn(mexicoSunday, sample(mexicoCity, now: mondayNoon), now: mondayNoon).evaluation.isMet, "Monday: not met")
// Approximate Location: Mexico City is still clearly Mexico (10 km floor).
check(countryRow(inMexico, sample(mexicoCity, accuracy: 3_000), precise: false).status == .met, "approximate: deep inside passes")
check(!ConditionalCheckIn.wantsPrecise(mexicoSunday), "a country never asks for temporary precise location")

// Tijuana / San Diego: inside each country, but within the margin → can't tell.
check(at(sanYsidroSouth).regionCode == "MX" && at(sanYsidroNorth).regionCode == "US", "each side of the border")
for p in [sanYsidroSouth, sanYsidroNorth, tijuanaCentre] {
    check(at(p).borderDistanceMeters < 2_000, "near the border: \(at(p))")
    check(countryRow(inMexico, sample(p)) == .unknown(.nearBorder), "Mexico within the margin: can't tell \(p)")
    check(countryRow(inUS, sample(p)) == .unknown(.nearBorder), "US within the margin: can't tell \(p)")
}
check(ConditionalCheckIn.reason(countryRow(inMexico, sample(tijuanaCentre)), condition: .country("MX"), translate: say,
      locale: gb, calendar: mx) == "Too close to a border to tell", "the words")
check(raw(tijuanaCentre).borderDistanceMeters > 2_000 && at(tijuanaCentre).borderDistanceMeters < 2_000,
      "the allowance turns a 2.5 km dataset distance into doubt")
check(countryRow(inMexico, sample(tijuanaSouth)).status == .met, "5 km into Mexico, a good fix: in Mexico")
check(countryRow(inMexico, sample(tijuanaSouth, accuracy: 2_500)) == .unknown(.nearBorder), "…but not with a vague fix")
check(countryRow(inMexico, sample(tijuanaSouth, accuracy: 1_500), precise: false) == .unknown(.nearBorder),
      "…nor under Approximate Location")
check(countryRow(inMexico, sample(sanDiego)) == ConditionResult(status: .notMet, reason: .notInCountry), "San Diego: not in Mexico")
check(countryRow(inUS, sample(sanDiego)).status == .met, "San Diego: in the US")

// Open sea: no country, and far from any.
for p in [(0.0, -140.0), (30.0, -40.0), (-16.5, 0.0), (-45.0, 90.0)] {
    let r = at(p)
    check(r.regionCode == nil && r.borderDistanceMeters > 300_000, "open sea \(p): none, far (\(r))")
    check(countryRow(inMexico, sample(p)) == ConditionResult(status: .notMet, reason: .notInCountry), "open sea: not in Mexico")
}
// Coast: a beach whose fix falls at sea next to one country counts as that country.
check(at((21.10, -86.76)).regionCode == "MX" && countryRow(inMexico, sample((21.10, -86.76))).status == .met, "Cancún beach")
check(at((-22.9711, -43.1822)).regionCode == "BR", "Copacabana beach")

// Antimeridian: Fiji and Russia on both sides of ±180°, never a wrapped edge across the globe.
for p in [suva, taveuniWest, taveuniEast] {
    check(at(p).regionCode == "FJ" && at(p).borderDistanceMeters > 100_000, "Fiji \(p): \(at(p))")
}
for p in [chukotkaWest, chukotkaEast, wrangelWest, wrangelEast] {
    check(at(p).regionCode == "RU" && at(p).borderDistanceMeters > 100_000, "Russia \(p): \(at(p))")
}
check(abs(at(taveuniWest).borderDistanceMeters - at(taveuniEast).borderDistanceMeters) < 20_000, "same answer across 180°")
check(at((-16.83, 180.0)).regionCode == "FJ" && at((-16.83, -180.0)).regionCode == "FJ", "exactly on ±180°")
check(CountryBorders.wrap(359) == -1 && CountryBorders.wrap(-181) == 179 && CountryBorders.wrap(180) == 180, "wrap")
// An edge on the far side of the globe (St Lawrence Island at ~-170°, the antipode of Norway's 10°E) must not
// unwrap into a line through the point: Norway stays far from any other country.
check(at((63.43, 10.0)).regionCode == "NO" && at((63.43, 10.0)).borderDistanceMeters > 50_000, "antipodal edge: \(at((63.43, 10.0)))")

// Enclaves, microstates, disputed areas.
check(at(lesotho).regionCode == "LS" && at(lesotho).borderDistanceMeters > 20_000, "inside Lesotho")
check(at(bloemfontein).regionCode == "ZA", "South Africa around it (the hole is not South Africa)")
check(countryRow(free("In South Africa", .all, [.country("ZA")]), sample(lesotho))
      == ConditionResult(status: .notMet, reason: .notInCountry), "Lesotho is not South Africa")
check(countryRow(free("In Lesotho", .all, [.country("LS")]), sample(maseru)) == .unknown(.nearBorder), "Maseru: on the river border")
check(at(vatican).regionCode == "VA" && countryRow(free("Vatican", .all, [.country("VA")]), sample(vatican)) == .unknown(.nearBorder),
      "the Vatican is never clear of Italy")
check(at(gibraltar).regionCode == "GI" && countryRow(free("Spain", .all, [.country("ES")]), sample(gibraltar)) == .unknown(.nearBorder),
      "Gibraltar: can't tell")
check(at(northCyprus) ==~ ConditionalCountryLookup(regionCode: nil, borderDistanceMeters: 0), "disputed area: no name, on a border")
check(countryRow(free("Cyprus", .all, [.country("CY")]), sample(northCyprus)) == .unknown(.nearBorder), "Q4: can't tell, never ✗")
check(at(paphos).regionCode == "CY" && countryRow(free("Cyprus", .all, [.country("CY")]), sample(paphos)).status == .met, "Paphos")
check(at(pristina).regionCode == "XK", "Kosovo (iOS names it)")
check(at(madrid).regionCode == "ES" && at(madrid).borderDistanceMeters > 200_000, "Madrid")
// Tripoints: the dataset's border passes close by.
check(raw((47.5899, 7.5891)).borderDistanceMeters < 500, "Basel tripoint (CH/DE/FR)")
check(raw((50.7547, 6.0208)).borderDistanceMeters < 2_000 && at((50.7547, 6.0208)).borderDistanceMeters < 1_000,
      "Vaalserberg (NL/DE/BE): Natural Earth's tripoint is ~1.9 km off, inside the allowance + margin")

// Invalid points, the trust rules.
check(borders.lookup(latitude: .nan, longitude: 0) == nil && borders.lookup(latitude: 91, longitude: 0) == nil
      && borders.lookup(latitude: 0, longitude: 181) == nil, "invalid points: no answer")
check(countryRow(inMexico, sample(mexicoCity, simulated: true)) == .unknown(.simulated), "simulated: ?")
check(countryRow(inMexico, sample(mexicoCity, accessory: true)) == .unknown(.accessory), "accessory: ? for free time")
check(countryRow(inMexico, LocationSample(latitude: 19.4326, longitude: -99.1332, horizontalAccuracy: 20,
      timestamp: sundayNoon.addingTimeInterval(-30), isSimulated: false, isFromAccessory: false)) == .unknown(.staleFix), "stale")
check(CheckInResult.make(rule: inMexico, state: stateWith(inMexico), clock: clock(sundayNoon),
      location: LocationTrust.checkInInput(.sample(sample(mexicoCity), precise: true), wallNow: sundayNoon, country: nil))
      .evaluation.results[0] == .unknown(.countryUnavailable), "borders missing: couldn't tell, fail closed")

// "Use the country I'm in".
func here(_ s: LocationSample, precise: Bool = true) -> Result<String, CountryHereProblem> {
    LocationTrust.countryHere(.sample(s, precise: precise), wallNow: sundayNoon, country: realLookup)
}
check(here(sample(mexicoCity)) == .success("MX"), "Mexico City → MX")
check(here(sample(mexicoCity, accuracy: 4_000), precise: false) == .success("MX"), "approximate is enough deep inside")
check(here(sample(tijuanaCentre)) == .failure(CountryHereProblem(reason: .nearBorder)), "Tijuana: too close to tell")
check(here(sample(northCyprus)) == .failure(CountryHereProblem(reason: .nearBorder)), "disputed: too close to tell")
check(here(sample((0, -140))) == .failure(CountryHereProblem(reason: .countryUnavailable)), "open sea: couldn't tell")
check(here(sample(mexicoCity, simulated: true)) == .failure(CountryHereProblem(reason: .simulated)), "simulated refused")
check(here(sample(mexicoCity, accessory: true)) == .failure(CountryHereProblem(reason: .accessory))
      && CountryHereProblem(reason: .accessory).messageKey == "Location from an accessory can't set a country", "accessory refused")
check(LocationTrust.countryHere(.failed(.denied), wallNow: sundayNoon, country: realLookup)
      == .failure(CountryHereProblem(reason: .locationOff)), "denied")
check(LocationTrust.countryHere(.sample(sample(mexicoCity), precise: true), wallNow: sundayNoon, country: nil)
      == .failure(CountryHereProblem(reason: .countryUnavailable)), "no borders: refused")

// The picker: iOS's names in the app's language, sorted and searched that way.
let english = CountryChoices.list(codes: borders.regionCodes, locale: gb)
check(english.count >= borders.regionCodes.count - 5, "iOS names (almost) every dataset code: \(english.count)")
check(english.contains(CountryChoices.Choice(code: "MX", name: "Mexico")), "Mexico in English")
check(CountryChoices.list(codes: borders.regionCodes, locale: Locale(identifier: "es_MX"), query: "mexico").map(\.code) == ["MX"],
      "México found without its accent")
check(CountryChoices.list(codes: borders.regionCodes, locale: gb, query: "MX").map(\.code) == ["MX"], "by code")
check(CountryChoices.list(codes: borders.regionCodes, locale: gb, query: "zzzz").isEmpty, "no match")
check(english == english.sorted { $0.name.compare($1.name, options: [.caseInsensitive, .diacriticInsensitive],
                                                 range: nil, locale: gb) != .orderedDescending }, "sorted by name")
check(!english.contains { $0.code == "~~" } && Set(english.map(\.code)).count == english.count, "no unnamed or duplicate rows")
let german = CountryChoices.list(codes: ["DE", "AT", "CH"], locale: Locale(identifier: "de_DE")).map(\.name)
check(german == ["Deutschland", "Österreich", "Schweiz"], "German names and order: \(german)")
check(ConditionKind.disabledReason(.country, conditionCount: 0) == nil && ConditionalCheckIn.countryLookupAvailable, "countries on")

// A small synthetic map: overlap, a hole filled by another entry, the coast band, an unnamed area.
func encode(_ list: [(String, [[(Double, Double)]])]) -> Data {
    var out = Data("DMCB".utf8) + Data([1, 0x10, 0x27, 0, 0, UInt8(list.count), 0])
    func varint(_ v: UInt64) { var v = v; repeat { let b = UInt8(v & 0x7F); v >>= 7; out.append(v == 0 ? b : b | 0x80) } while v != 0 }
    func zigzag(_ v: Int64) -> UInt64 { UInt64(bitPattern: (v << 1) ^ (v >> 63)) }
    for (code, rings) in list {
        out.append(contentsOf: Array(code.utf8)); varint(UInt64(rings.count))
        for ring in rings {
            varint(UInt64(ring.count)); var last: (Int64, Int64) = (0, 0)
            for (lon, lat) in ring {
                let q = (Int64((lon * 10_000).rounded()), Int64((lat * 10_000).rounded()))
                varint(zigzag(q.0 - last.0)); varint(zigzag(q.1 - last.1)); last = q
            }
        }
    }
    return out
}
func square(_ lon: Double, _ lat: Double, _ size: Double) -> [(Double, Double)] {
    [(lon, lat), (lon + size, lat), (lon + size, lat + size), (lon, lat + size)]
}
let synthetic = CountryBorders(data: encode([
    ("AA", [square(0, 0, 1)]), ("BB", [square(0.5, 0, 1)]),
    ("CC", [square(10, 10, 2), square(10.5, 10.5, 1)]), ("DD", [square(10.5, 10.5, 1)]),
    ("~~", [square(20, 20, 1)]), ("EE", [square(30, 0, 1)]),
]))!
func syn(_ lat: Double, _ lon: Double) -> ConditionalCountryLookup { synthetic.lookup(latitude: lat, longitude: lon)! }
let km = Double.pi / 180 * ConditionEvaluator.earthRadius / 1000
check(synthetic.regionCodes == ["AA", "BB", "CC", "DD", "EE"], "synthetic codes")
check(syn(0.75, 0.75) ==~ ConditionalCountryLookup(regionCode: nil, borderDistanceMeters: 0), "overlap: no name, on a border")
check(syn(0.5, 0.25).regionCode == "AA" && abs(syn(0.5, 0.25).borderDistanceMeters - (0.25 * km * 1000 - allowance)) < 50,
      "inside one: distance to the other, less the allowance: \(syn(0.5, 0.25))")
check(syn(11, 11).regionCode == "DD" && syn(10.2, 10.2).regionCode == "CC", "a hole belongs to the entry that fills it")
check(syn(20.5, 20.5) ==~ ConditionalCountryLookup(regionCode: nil, borderDistanceMeters: 0), "unnamed area: on a border")
let off1 = 1.0 / km, off3 = 3.0 / km
check(syn(0.5, 30 + 1 + off1).regionCode == "EE", "1 km off EE's coast: EE (coast band)")
check(syn(0.5, 30 + 1 + off3).regionCode == nil && abs(syn(0.5, 30 + 1 + off3).borderDistanceMeters - 2_000) < 20,
      "3 km off: at sea, 3 km less the allowance from land")
check(synthetic.rawLookup(latitude: 0.5, longitude: 30.5)!.borderDistanceMeters == CountryBorders.distanceCapMeters,
      "3,000 km from any other: capped at 1,000 km")

// Review fix: enclaves the dataset leaves out read as "can't tell" (generator's MISSING_ENCLAVES).
ENCLAVE_CHECKS
check(countryRow(free("Netherlands", .all, [.country("NL")]), sample((51.4419, 4.9285))) == .unknown(.nearBorder),
      "Baarle-Hertog (BE) is never ✓ Netherlands")
check(at((51.5555, 5.0913)).regionCode == "NL" && at((51.5555, 5.0913)).borderDistanceMeters > 5_000, "Tilburg still clearly NL")
check(at((47.5596, 7.5886)).regionCode == "CH", "Basel still Switzerland")
// Lugano centre stays Switzerland, outside Campione's zone (it was swallowed by the first, wider
// zone); it is still within the doubt band (~1.85 km after the allowance), logged as a limit.
check(at((46.0037, 8.9511)).regionCode == "CH" && at((46.0037, 8.9511)).borderDistanceMeters > 1_500,
      "Lugano: Switzerland, outside Campione's zone: \(at((46.0037, 8.9511)))")

// Review fix: approximate Location near a border asks once more, with precise.
func outcome(_ p: (Double, Double), precise: Bool, accuracy: Double = 1_500) -> LocationReadOutcome {
    .sample(sample(p, accuracy: accuracy), precise: precise)
}
func viaApproximate(_ rule: ConditionalRule, _ p: (Double, Double), precise: Bool) -> Bool {
    let o = outcome(p, precise: precise)
    let r = CheckInResult.make(rule: rule, state: stateWith(rule), clock: clock(sundayNoon),
                               location: LocationTrust.checkInInput(o, wallNow: sundayNoon, country: realLookup))
    return ConditionalCheckIn.wantsPreciseRetry(r, outcome: o, country: realLookup)
}
check(viaApproximate(mexicoSunday, tijuanaSouth, precise: false), "approximate, too close: read again with precise")
check(!viaApproximate(mexicoSunday, tijuanaSouth, precise: true), "precise already: no second read")
check(!viaApproximate(mexicoSunday, mexicoCity, precise: false), "approximate but clear: no second read")
check(!viaApproximate(mexicoSunday, (0, -140), precise: false), "at sea, clearly not Mexico: no second read")
check(!viaApproximate(mexicoSunday, tijuanaCentre, precise: false), "within the margin even when precise: no prompt")
check(!viaApproximate(free("Cyprus", .all, [.country("CY")]), northCyprus, precise: false), "disputed area: no prompt")
check(!viaApproximate(free("Belgium", .all, [.country("BE")]), (51.4419, 4.9285), precise: false), "Baarle: no prompt")
let homeInMexico = free("Home in Mexico", .all, [.country("MX"), .place(ConditionalPlace(name: "Home", latitude: 32.49,
                        longitude: -117.03, radiusMeters: 250))])
check(!viaApproximate(homeInMexico, tijuanaSouth, precise: false), "a place already asked for precise: no second read")
func hereRetry(_ p: (Double, Double), precise: Bool) -> Bool {
    LocationTrust.countryHereWantsPrecise(outcome(p, precise: precise),
        result: LocationTrust.countryHere(outcome(p, precise: precise), wallNow: sundayNoon, country: realLookup),
        country: realLookup)
}
check(hereRetry(tijuanaSouth, precise: false), "the country I'm in: approximate and too close → once more with precise")
check(!hereRetry(tijuanaSouth, precise: true), "…not when precise")
check(!hereRetry(tijuanaCentre, precise: false) && !hereRetry(northCyprus, precise: false), "…not where precise can't help")
check(!LocationTrust.countryHereWantsPrecise(outcome(mexicoCity, precise: false), result: .success("MX"), country: realLookup),
      "…not when found")

// Review fix: Swift's distances never exceed an independent measurement.
var compared = 0, worstOver = -Double.infinity, worstUnder = 0.0
for line in sampleLines {
    let f = line.split(separator: " ")
    let lat = Double(f[0])!, lon = Double(f[1])!, code = String(f[2]), python = Double(f[3])!
    let r = borders.rawLookup(latitude: lat, longitude: lon)!
    check(r.regionCode == code, "same country as Python at \(lat), \(lon): \(r)")
    worstOver = max(worstOver, r.borderDistanceMeters - python)
    worstUnder = max(worstUnder, python - r.borderDistanceMeters)
    compared += 1
}
check(worstOver <= 1, "Swift never reports more than the independent distance (worst +\(worstOver) m)")
check(worstUnder <= 1_000, "…nor grossly less (worst −\(worstUnder) m)")
print("Independent distances compared at \(compared) points near land borders and coasts: worst +\(Int(worstOver.rounded())) m, −\(Int(worstUnder.rounded())) m")

// Damaged data is refused, never half-read.
check(CountryBorders(data: data.prefix(data.count - 1)) == nil, "truncated")
check(CountryBorders(data: data + Data([0])) == nil, "trailing byte")
var badMagic = data; badMagic[0] = 0x58
check(CountryBorders(data: badMagic) == nil, "bad magic")
var badVersion = data; badVersion[4] = 2
check(CountryBorders(data: badVersion) == nil, "unknown version")
check(CountryBorders(data: Data()) == nil, "empty")

// Speed: the load and a lookup are cheap enough for a tap.
let speedStart = Date()
for i in 0..<300 { _ = borders.lookup(latitude: Double(i % 120) - 55, longitude: Double((i * 37) % 360) - 180) }
let perLookup = Date().timeIntervalSince(speedStart) / 300
check(loadSeconds < 1 && perLookup < 0.05, "load \(loadSeconds) s, lookup \(perLookup) s")
print(String(format: "When & where countries passed: %d checks (load %.0f ms, lookup %.2f ms)", checks,
             loadSeconds * 1000, perLookup * 1000))
print("SWIFT_INSIDE " + [''' + ', '.join(f'("{n}", {n})' for n in PROBES) + r'''].map { name, p in
    "\(name)=\(raw(p).regionCode ?? "-")" }.joined(separator: ","))
'''

with tempfile.TemporaryDirectory(prefix='demora-whenwhere-country-') as directory:
    folder = Path(directory)
    (folder / 'Infrastructure.swift').write_text(infrastructure + '\n' + phrases)
    (folder / 'SharedModels.swift').write_text(models)
    (folder / 'SchedulePrecedence.swift').write_text(precedence)
    (folder / 'RulesPresentation.swift').write_text(portable(presentation))
    (folder / 'CountryLookup.swift').write_text(lookup_source)
    enclave_checks = '\n'.join(
        f'check(at(({lat}, {lon})) ==~ ConditionalCountryLookup(regionCode: nil, borderDistanceMeters: 0), '
        f'"{name}: can\'t tell")' for name, lat, lon, _ in enclaves)
    (folder / 'main.swift').write_text(driver.replace('ENCLAVE_CHECKS', enclave_checks))
    (folder / 'samples.txt').write_text(''.join(f'{lat} {lon} {code} {d}\n' for lat, lon, code, d in python_samples))
    binary = folder / 'whenwhere-country'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-O',
                    *(str(folder / name) for name in ('Infrastructure.swift', 'SharedModels.swift',
                                                      'SchedulePrecedence.swift', 'RulesPresentation.swift',
                                                      'CountryLookup.swift', 'main.swift')),
                    '-o', str(binary)], check=True)
    run = subprocess.run([str(binary), str(DATA), str(folder / 'samples.txt')], capture_output=True, text=True,
                         env={**os.environ, 'TZ': 'America/Mexico_City'})
    if run.returncode:
        print(run.stdout + run.stderr)
        sys.exit(1)
    output = run.stdout.strip().split('\n')
    for line in output:
        if not line.startswith('SWIFT_INSIDE '):
            print(line)
    swift_inside = dict(item.split('=') for item in output[-1].removeprefix('SWIFT_INSIDE ').split(','))
# The Swift lookup's containing country agrees with the independent Python decode.
for name, inside in python_inside.items():
    if len(inside) == 1 and inside[0] != '~~':
        assert swift_inside[name] == inside[0], (name, swift_inside[name], inside)
    elif not inside:
        assert swift_inside[name] in ('-', ) or swift_inside[name] in entries, (name, swift_inside[name])
assert swift_inside['northCyprus'] == '-', 'disputed: no name'
print(f'Country lookup agrees with an independent decode at {len(python_inside)} points')

# --- Source guards: offline, nothing kept, host only, credited -------------
def code_only(text):
    return '\n'.join(line for line in text.split('\n') if not line.lstrip().startswith('//'))


lookup_code = code_only(lookup_source)
assert re.findall(r'^import (\w+)', lookup_source, re.M) == ['Foundation'], 'the lookup imports Foundation only'
for word in ('URLSession', 'URLRequest', 'http', 'CLGeocoder', 'CoreLocation', 'MapKit', 'Network', 'print(',
             'NSLog', 'Logger', 'os_log', 'UserDefaults', 'SharedStore', 'FileManager', 'write(', 'TimeGuard'):
    assert word not in lookup_code, ('the lookup is offline and keeps nothing', word)
assert lookup_code.count('Bundle.main.url(forResource: resourceName, withExtension: resourceExtension)') == 1
picker = (ROOT / 'Latch/CountryPicker.swift').read_text()
sheet = (ROOT / 'Latch/CheckInSheet.swift').read_text()
for name, text in (('CountryPicker.swift', picker), ('CheckInSheet.swift', sheet),
                   ('RulesPresentation.swift', presentation), ('ConditionalRuleEditor.swift',
                                                               (ROOT / 'Latch/ConditionalRuleEditor.swift').read_text())):
    code = code_only(text)
    for word in ('URLSession', 'URLRequest', 'CLGeocoder', 'reverseGeocode', 'MKLocalSearch', 'import MapKit',
                 'import Network', 'NWConnection', 'print(', 'NSLog'):
        assert word not in code, ('no network, geocoder or logging', name, word)
assert 'private func read(precise: Bool = false)' in picker and 'locator.readOnce(wantsPrecise: precise)' in picker \
    and picker.count('read(precise: true)') == 1, "the country I'm in asks for precise only on its one retry"
assert picker.count('locator.readOnce(') == 1, 'one read per tap'
read_src = declaration(picker, 'private func read(precise: Bool = false)')
assert 'LocationTrust.countryHere(outcome, wallNow: Date(), country: lookup)' in read_src
assert 'selected = code' in read_src and 'latitude' not in read_src.replace('lookup(latitude:', ''), 'only the code is kept'
row_src = declaration(picker, 'private func row(_ choice: CountryChoices.Choice)')
assert row_src.index('generation += 1') < row_src.index('locator.cancel()') < row_src.index('selected = choice.code'), \
    'a pick by hand cancels a read on its way (review fix)'
assert read_src.index('LocationTrust.countryHereWantsPrecise(outcome, result: result, country: lookup)') < read_src.index('read(precise: true)') \
    < read_src.index('switch result {'), 'one more read with precise before showing "too close"'
sheet_read = declaration(sheet, 'private func readLocation(announce: Bool, precise: Bool)')
assert sheet_read.index('if !precise, ConditionalCheckIn.wantsPreciseRetry(result, outcome: outcome,') \
    < sheet_read.index('readLocation(announce: announce, precise: true)') < sheet_read.index('check = result'), \
    'the sheet retries once with precise before showing the result'
for state_line in re.findall(r'@State private var [^\n]+', picker):
    for word in ('LocationSample', 'LocationReadOutcome', 'latitude', 'ConditionalCountryLookup'):
        assert word not in state_line, ('no fix or lookup kept in view state', state_line)
assert 'CountryBorders.bundled' not in declaration(picker, 'private var choices'), 'never loaded while drawing'
assert 'await Task.detached(priority: .userInitiated)' in declaration(picker, 'var body: some View'), \
    'the picker loads the borders off the main thread'
lookup_fn = declaration(sheet, 'private static func countryLookup(for rule: ConditionalRule)')
assert 'guard hasCountry(rule), let borders = CountryBorders.bundled else { return nil }' in lookup_fn, \
    'a place-only rule never loads the borders'
for directory in ('LatchMonitor', 'LatchReport', 'LatchWidgets', 'LatchShieldUI', 'Shared'):
    for path in (ROOT / directory).rglob('*'):
        assert path.name not in ('CountryBorders.bin', 'CountryLookup.swift', 'CountryPicker.swift'), \
            ('borders only in the host app', path)
        if path.suffix == '.swift':
            assert 'CountryBorders' not in path.read_text(), ('no extension or shared code reads the borders', path)
project = (ROOT / 'Latch.xcodeproj/project.pbxproj').read_text()
assert 'CountryBorders.bin' not in project, 'the host folder is synchronised: no hand-made membership'
you = (ROOT / 'Latch/YouView.swift').read_text()
credits = declaration(you, 'struct CreditsView: View {')
assert 'resource: "COUNTRY_BORDERS_ATTRIBUTION"' in credits and 'resource: "WORDLIST_ATTRIBUTION"' in credits
assert 'Button(tr("Credits")) { model.youPath.append(.credits) }' in you and 'Word list credits' not in you
assert 'Natural Earth' in credits, 'a credit even if the file is missing'

# --- Translations of the new strings ---------------------------------------
STRING = r'"((?:[^"\\]|\\.)*)"'
keys = set()
for text in (picker, credits):
    for call in re.findall(r'\btr\((?:[^()"]|"(?:[^"\\]|\\.)*")*\)', text):
        keys.update(re.findall(STRING, call))
keys.update(re.findall(r'titleKey: ' + STRING, credits))
keys.update(['Change country', "Location from an accessory can't set a country", 'Credits'])
assert {'Use the country I\'m in', 'Search countries', 'Use this country', 'Word list', 'Country borders'} <= keys, keys
TABLES = {'es': '', 'de': '+German', 'fr': '+French', 'pt': '+Portuguese',
          'pl': '+Polish', 'tr': '+Turkish', 'hi': '+Hindi'}
entry = re.compile(r'^\s*' + STRING + r'\s*:\s*' + STRING + r',?\s*$', re.M)
for code, suffix in TABLES.items():
    pairs = entry.findall((ROOT / f'Shared/Localization{suffix}.swift').read_text())
    seen = [k for k, _ in pairs]
    duplicates = sorted({k for k in seen if seen.count(k) > 1})
    assert not duplicates, (code, duplicates)
    table = dict(pairs)
    missing = sorted(k for k in keys if k not in table or not table[k].strip())
    assert not missing, (code, 'untranslated', missing)
    for gone in ('Word list credits', 'Arrives in a later update.',
                 "Checking which country you're in arrives in a later update."):
        assert gone not in table, (code, 'retired key still translated', gone)
print(f'When & where country source guards passed: offline, one read, nothing kept, host only, credited; '
      f'{len(keys)} strings × 7 tables')
