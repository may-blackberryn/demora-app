#!/usr/bin/env python3
"""Compile real display-clock/wake APIs and their original status/tap readers.

Run: python3 Tests/WakeWidgetReadOnlyHarness.py
Only this file is owned by this harness work. No Xcode build, live preferences,
App Group, network, permissions, or enforcement. Preferences are in memory;
container resolution is redirected to TemporaryDirectory BEFORE Swift executes.
Apple tokens, coordination, monitors and shields are counted fakes. Date()/uptime
inputs are injected, not the production decision logic. Runtime types, keys,
filenames, JSON encoders/decoders and status bodies come from owning sources.
This is not protected-file, cross-process locking, WidgetKit or device delivery QA.
"""
from pathlib import Path
import difflib
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "da9b6d3889b11fff8919a8a8470300069e08c930"


def span(source, signature):
    """Balanced Swift declaration; ignore comments and quoted string braces."""
    start = source.index(signature)
    opening = source.index("{", start)
    token = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"""[\s\S]*?"""|"(?:\\.|[^"\\])*"|[{}]')
    depth = 0
    for match in token.finditer(source, opening):
        if match[0] == "{":
            depth += 1
        elif match[0] == "}":
            depth -= 1
            if depth == 0:
                return start, match.end()
    raise AssertionError(f"Unclosed declaration: {signature}")


def block(source, signature):
    start, end = span(source, signature)
    return source[start:end]


def addition_lines(source, start, end):
    """Include only attached documentation and the separator after an addition."""
    lines = source.splitlines(keepends=True)
    first = source.count("\n", 0, start)
    last = source.count("\n", 0, end) + 1
    while first and lines[first - 1].lstrip().startswith("//"):
        first -= 1
    if last < len(lines) and not lines[last].strip():
        last += 1
    return first, last


def without_when_where_insertions(old, restored):
    """The owner-approved When & where engine (docs/conditional-sessions-
    redesign.md, step 1) adds new ChangeAction cases and helpers to the
    engine. Accept them only as pure line insertions that name When & where
    symbols; any edited or deleted original line still fails the guard."""
    matcher = difflib.SequenceMatcher(None, old.splitlines(keepends=True), restored, autojunk=False)
    result = []
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        chunk = "".join(restored[j1:j2])
        if tag == "insert":
            assert re.search(r"[Cc]onditional|TimeZone", chunk), "unapproved engine insertion:\n" + chunk
            continue
        result.extend(restored[j1:j2])
    return result


def guard_originals():
    """All changed structural ranges must be approved insertions, never edits."""
    specs = {
        "TimeGuard.swift": "static func nowForDisplay(",
        "ChangeEngine.swift": "static func statusForDisplay(",
        "DayNightWake.swift": "static func statusForDisplay(",
        "LimitFeatures.swift": "static func wakeStateForDisplay(",
    }
    sources = {}
    for name, signature in specs.items():
        path = "Shared/" + name
        old = subprocess.check_output(["git", "show", BASELINE + ":" + path], cwd=ROOT, text=True)
        new = (ROOT / path).read_text()
        allowed = [addition_lines(new, *span(new, signature))]
        if name == "ChangeEngine.swift":
            hook = "                DemoraWidgetSnapshot.refresh()\n"
            assert new.count(hook) == 1, "Expected exactly one approved wake publication hook"
            start = new.index(hook)
            owner_start, owner_end = span(new, "static func wakeUpAllOffMain()")
            assert owner_start < start < owner_end
            first, last = addition_lines(new, start, start + len(hook) - 1)
            # Hook comments may vary; surrounding executable statements may not.
            lines = new.splitlines(keepends=True)
            assert lines[first - 1].strip() == "ShieldController.refresh()"
            assert lines[last].strip() == "continuation.resume(returning: changed)"
            allowed.append((first, last))
        # Repeated lines in the two status readers can confuse a diff's
        # alignment. Remove only the known additive declarations, then require
        # exact original bytes, rather than guessing insertion boundaries.
        restored = new.splitlines(keepends=True)
        for a, b in sorted(allowed, reverse=True):
            del restored[a:b]
        if name == "ChangeEngine.swift":
            restored = without_when_where_insertions(old, restored)
        assert "".join(restored) == old, f"{path}: removal did not exactly restore baseline\n" + "".join(
            difflib.unified_diff(old.splitlines(True), restored))
        sources[name] = new
    print("Source guard: four engine files exactly match verified baseline after approved additions are removed", flush=True)
    return sources


def portable(source):
    for module in ("FamilyControls", "ManagedSettings", "DeviceActivity"):
        source = source.replace(f"import {module}\n", "")
    return source


def inputs(source):
    # Boundary substitutions only. In particular no status/clock algorithm is
    # copied into a fake and none of the display bodies is replaced.
    return (source.replace("Date()", "TestClock.wall")
            .replace("ProcessInfo.processInfo.systemUptime", "TestClock.uptime")
            .replace("FileManager.default.containerURL(", "TestContainer.containerURL(")
            .replace("NSFileCoordinator()", "TestCoordinator()"))


INFRASTRUCTURE = r'''
import Foundation
struct FamilyActivitySelection: Codable, Equatable {
    var includeEntireCategory = false
    var applicationTokens: Set<String> = []
    var categoryTokens: Set<String> = []
    var webDomainTokens: Set<String> = []
}
func tr(_ value: String) -> String { value }
enum TestClock { static var wall = Date(timeIntervalSince1970: 1_800_000_000); static var uptime: TimeInterval = 10000 }
final class MemoryDefaults {
    var values: [String: Any] = [:]
    var writes = 0
    func object(forKey key: String) -> Any? { values[key] }
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func string(forKey key: String) -> String? { values[key] as? String }
    func double(forKey key: String) -> Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
    func set(_ value: Any?, forKey key: String) { writes += 1; values[key] = value }
    func removeObject(forKey key: String) { writes += 1; values.removeValue(forKey: key) }
}
enum Effects {
    static var monitorStarts = 0, monitorStops = 0, shields = 0, coordinates = 0, flags = 0
    static var counts: [Int] { [monitorStarts, monitorStops, shields, coordinates, flags] }
}
enum TestContainer {
    static let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    static var available = true
    static func containerURL(forSecurityApplicationGroupIdentifier _: String) -> URL? {
        available ? root : nil
    }
}
struct TestCoordinator {
    func coordinate(writingItemAt url: URL, options: [Int], error: inout NSError?,
                    byAccessor body: (URL) -> Void) {
        Effects.coordinates += 1; body(url)
    }
}
struct DeviceActivityName {
    let rawValue: String
    init(_ value: String) { rawValue = value }
}
struct DeviceActivitySchedule {
    var intervalStart: DateComponents
    var intervalEnd: DateComponents
    var repeats: Bool
    var warningTime: DateComponents? = nil
}
enum MonitorRegistration {
    static func start(_ name: DeviceActivityName, during schedule: DeviceActivitySchedule) throws {
        Effects.monitorStarts += 1
    }
}
struct DeviceActivityCenter {
    var activities: [DeviceActivityName] { [] }
    func stopMonitoring(_ names: [DeviceActivityName]) { Effects.monitorStops += 1 }
}
enum ShieldController { static func refresh() { Effects.shields += 1 } }
enum SharedStore {
    static let defaults = MemoryDefaults()
    static var state = LatchState()
    static var simulating = false
    static var enforcementDegraded = false { didSet { Effects.flags += 1 } }
    static var stateRecoveryNeeded = false { didSet { Effects.flags += 1 } }
    static func loadState() -> LatchState { state }
    static func coordinateStateMutation<T>(_ body: () -> T) -> T? {
        Effects.coordinates += 1; return body()
    }
'''

# These test-only extensions access actual private keys/types in the same Swift
# file. No duplicated wire structs, key strings or alternate runtime JSON schema.
BRIDGES = r'''
extension TimeGuard {
    static func seed(wall: Date, uptime: Double) {
        SharedStore.defaults.set(wall.timeIntervalSince1970, forKey: anchorWallKey)
        SharedStore.defaults.set(uptime, forKey: anchorUptimeKey)
    }
}
extension GlobalWake {
    static func seed(day: Any?, release: Any?) {
        SharedStore.defaults.set(day, forKey: dayKey)
        SharedStore.defaults.set(release, forKey: releaseKey)
    }
}
extension DayNightWake {
    static func seed(_ value: Any?) { SharedStore.defaults.set(value, forKey: key) }
    static func seed(group: DayNightGroup, day: String, release: Date, epoch: UUID? = nil) throws {
        seed(try JSONEncoder().encode([group.id.uuidString:
            Entry(day: day, epoch: epoch ?? group.wakeEpoch, release: release)]))
    }
}
extension LimitFeatures {
    static var testURL: URL { fileURL }
    static func seed(limit: AppLimit, day: String, release: Date?) throws {
        var value = LimitFeatureEntry(day: day)
        value.wakeReleaseAt = release
        value.earlyBlocked = true; value.middleBlocked = true; value.lateBlocked = true
        value.earlyFreeCredit = 7; value.middleFreeCredit = 8; value.lateFreeCredit = 9
        value.extraRequests = 2; value.extraActiveTier = 1; value.extraReachedTier = 1
        value.extraReleaseAt = TestClock.wall.addingTimeInterval(600)
        value.extraLastRequestID = UUID()
        try JSONEncoder().encode([limit.id: value]).write(to: fileURL)
        SharedStore.defaults.set(true, forKey: splitReadyKey)
    }
}
'''

CHECKS = r'''
var assertions = 0
func check(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
    assertions += 1
    if try !value() { fatalError("FAIL: \(message)") }
}
func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
func reset(_ wall: Date) throws {
    SharedStore.defaults.values = [:]; SharedStore.defaults.writes = 0
    SharedStore.enforcementDegraded = false; SharedStore.stateRecoveryNeeded = false
    SharedStore.state = LatchState(); TestContainer.available = true
    TestClock.wall = wall; TestClock.uptime = 10000
    TimeGuard.seed(wall: wall, uptime: TestClock.uptime)
    for url in try FileManager.default.contentsOfDirectory(at: TestContainer.root,
                                                          includingPropertiesForKeys: nil) {
        try FileManager.default.removeItem(at: url)
    }
}
func files() throws -> [String: Data] {
    var result: [String: Data] = [:]
    for url in try FileManager.default.contentsOfDirectory(at: TestContainer.root,
                                                          includingPropertiesForKeys: nil) {
        result[url.lastPathComponent] = try Data(contentsOf: url)
        // Detect an identical-byte rewrite too, not only changed deadlines.
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        result[url.lastPathComponent + ".mtime"] = try JSONEncoder().encode(attrs[.modificationDate] as? Date)
    }
    return result
}
func readOnly(_ label: String, _ body: () throws -> Void) throws {
    let prefs = SharedStore.defaults.values as NSDictionary
    let writes = SharedStore.defaults.writes, effects = Effects.counts
    let disk = try files()
    let degraded = SharedStore.enforcementDegraded, recovery = SharedStore.stateRecoveryNeeded
    for _ in 0..<3 { try body() }
    check(SharedStore.defaults.values as NSDictionary == prefs, label + ": preference bytes changed")
    check(SharedStore.defaults.writes == writes, label + ": preference write attempted")
    check(Effects.counts == effects, label + ": monitor/shield/coordination/flag mutation")
    check(SharedStore.enforcementDegraded == degraded && SharedStore.stateRecoveryNeeded == recovery,
          label + ": flags changed")
    try check(files() == disk, label + ": runtime file/deadline/accounting changed")
}
let monday = date("2026-10-05T12:00:00-04:00")
var base = LatchState(); base.wakeRule.enabled = true
base.wakeRule.startHour = 8; base.wakeRule.waitMinutes = 10; base.wakeRule.weekdays = [2]
var named = DayNightGroup(); named.name = "Named"
named.wakeStartMinutes = 8 * 60 + 30; named.waitMinutes = 10; named.weekdays = [2]
var legacy = AppLimit(name: "Legacy", selection: FamilyActivitySelection(),
                      minutesPerDay: 30, wakeDelayMinutes: 10)
legacy.wakeSchedule = LimitWakeSchedule(startMinutes: 8 * 60 + 30, weekdays: [2])

func compare(_ label: String, _ state: LatchState, _ group: DayNightGroup, _ limit: AppLimit,
             wall: Date, guarded: Date, global: GlobalWakeStatus,
             dayNight: GlobalWakeStatus, limitStatus: WakeState) throws {
    TestClock.wall = guarded
    TimeGuard.seed(wall: guarded, uptime: TestClock.uptime)
    // The original methods are protected byte-for-byte by guard_originals().
    let g = GlobalWake.status(state: state, at: wall)
    let d = DayNightWake.status(group: group, at: wall, guardedNow: guarded)
    let l = LimitFeatures.wakeState(for: limit, at: wall, guardedNow: guarded)
    check(g == global && d == dayNight && l == limitStatus, label + ": original fixture status wrong")
    try readOnly(label) {
        check(GlobalWake.statusForDisplay(state: state, at: wall, guardedNow: guarded) == g,
              label + ": global differs from original")
        check(DayNightWake.statusForDisplay(group: group, at: wall, guardedNow: guarded) == d,
              label + ": named differs from original")
        check(LimitFeatures.wakeStateForDisplay(for: limit, at: wall, guardedNow: guarded) == l,
              label + ": limit differs from original")
    }
}

// Healthy eligibility, minute boundary, optional ceilings and weekday overrides.
for (text, g, d, l) in [
    ("2026-10-05T07:59:59-04:00", GlobalWakeStatus.inactive, GlobalWakeStatus.inactive, WakeState.notConfigured),
    ("2026-10-05T08:00:00-04:00", .needsTap, .inactive, .notConfigured),
    ("2026-10-05T08:29:59-04:00", .needsTap, .inactive, .notConfigured),
    ("2026-10-05T08:30:00-04:00", .needsTap, .needsTap, .needsTap),
    ("2026-10-06T12:00:00-04:00", .inactive, .inactive, .notConfigured)
] {
    let wall = date(text); try reset(wall)
    try compare(text, base, named, legacy, wall: wall, guarded: wall, global: g, dayNight: d, limitStatus: l)
}
try reset(monday)
var disabled = base; disabled.wakeRule.enabled = false
var disabledNamed = named; disabledNamed.wakeEnabled = false
var disabledLimit = legacy; disabledLimit.wakeDelayMinutes = nil
try compare("disabled", disabled, disabledNamed, disabledLimit, wall: monday, guarded: monday,
            global: .inactive, dayNight: .inactive, limitStatus: .notConfigured)
for tapped in [false, true] {
    for phase in ["waiting", "exact deadline", "elapsed", "edited start", "edited weekday", "edited wait", "combined", "yesterday", "epoch"] {
        try reset(monday)
        var state = base, group = named, limit = legacy
        let release = monday.addingTimeInterval(600)
        var day = SharedStore.dayKey(for: monday)
        if phase == "yesterday" { day = SharedStore.dayKey(for: monday.addingTimeInterval(-86400)) }
        if tapped {
            GlobalWake.seed(day: day, release: release)
            try DayNightWake.seed(group: group, day: day, release: release,
                                  epoch: phase == "epoch" ? UUID() : nil)
            try LimitFeatures.seed(limit: limit, day: day, release: release)
        }
        if ["edited start", "combined"].contains(phase) {
            state.wakeRule.startHour = 18; group.wakeStartMinutes = 18 * 60
            limit.wakeSchedule!.startMinutes = 18 * 60
        }
        if ["edited weekday", "combined"].contains(phase) {
            state.wakeRule.weekdays = [3]; group.weekdays = [3]; limit.wakeSchedule!.weekdays = [3]
        }
        if ["edited wait", "combined"].contains(phase) {
            state.wakeRule.waitMinutes = 0; group.waitMinutes = 0; limit.wakeDelayMinutes = 0
        }
        let guarded = phase == "exact deadline" ? release : phase == "elapsed" ? release.addingTimeInterval(1) : monday
        let active = tapped && phase != "yesterday"
        let eligible = !["edited start", "edited weekday", "combined"].contains(phase)
        let g: GlobalWakeStatus = active ? (guarded < release ? .waiting(release) : .awake) : eligible ? .needsTap : .inactive
        let d: GlobalWakeStatus = phase == "epoch" ? .needsTap : g
        let l: WakeState = active ? (guarded < release ? .waiting(release) : .awake) : eligible ? .needsTap : .notConfigured
        try compare("\(phase), tapped=\(tapped)", state, group, limit, wall: monday, guarded: guarded,
                    global: g, dayNight: d, limitStatus: l)
    }
}
for override in [false, true] {
    for running in [false, true] {
        for minute in [719, 720, 779, 780] {
            let wall = monday.addingTimeInterval(Double(minute - 720) * 60)
            try reset(wall)
            var state = base, group = named, limit = legacy
            state.wakeRule.latestMinutes = 720; group.wakeLatestMinutes = 720
            limit.wakeSchedule!.latestMinutes = 720
            if override {
                state.wakeRule.weekdayLatestMinutes = [2: 780]
                group.weekdayWakeTimings[2] = WakeDayTiming(startMinutes: 510, waitMinutes: 35, latestMinutes: 780)
                limit.wakeSchedule!.dayTimings[2] = WakeDayTiming(startMinutes: 510, waitMinutes: 35, latestMinutes: 780)
            }
            let release = monday.addingTimeInterval(4 * 3600)
            if running {
                let day = SharedStore.dayKey(for: wall)
                GlobalWake.seed(day: day, release: release)
                try DayNightWake.seed(group: group, day: day, release: release)
                try LimitFeatures.seed(limit: limit, day: day, release: release)
            }
            let capped = minute >= (override ? 780 : 720)
            try compare("ceiling \(minute), override=\(override), running=\(running)", state, group, limit,
                        wall: wall, guarded: wall, global: capped ? .awake : running ? .waiting(release) : .needsTap,
                        dayNight: capped ? .awake : running ? .waiting(release) : .needsTap,
                        limitStatus: capped ? .awake : running ? .waiting(release) : .needsTap)
        }
    }
}

// Real taps at zero and positive waits, not hand-invented post-tap metadata.
for wait in [0, 10, 120] {
    try reset(monday)
    var state = base, group = named, limit = legacy
    state.wakeRule.waitMinutes = wait; group.waitMinutes = wait; limit.wakeDelayMinutes = wait
    SharedStore.state = state; SharedStore.state.dayNightGroups = [group]; SharedStore.state.limits = [limit]
    check(GlobalWake.tap(), "global actual tap rejected")
    check(DayNightWake.tapAll(), "named actual tap rejected")
    check(LimitFeatures.wakeUp(limitID: limit.id), "limit actual tap rejected")
    let release = monday.addingTimeInterval(Double(wait * 60))
    try compare("actual tap wait=\(wait)", state, group, limit, wall: monday, guarded: monday,
                global: wait == 0 ? .awake : .waiting(release),
                dayNight: wait == 0 ? .awake : .waiting(release),
                limitStatus: wait == 0 ? .awake : .waiting(release))
    check(!GlobalWake.tap() && !DayNightWake.tapAll() && !LimitFeatures.wakeUp(limitID: limit.id),
          "repeated tap accepted")
}

// Corrupt metadata is unknown; no flags, splitReady, clock anchor, accounting,
// monitor calls or runtime repair, even when already degraded/recovering.
for bad in [Data("not json".utf8), Data("{\"broken\":{}}".utf8)] {
    for degraded in [false, true] {
        try reset(monday)
        SharedStore.defaults.values = [:] // missing clock must not anchor during reads
        SharedStore.enforcementDegraded = degraded; SharedStore.stateRecoveryNeeded = degraded
        DayNightWake.seed(bad)
        try bad.write(to: LimitFeatures.testURL)
        try readOnly("corrupt runtime, degraded=\(degraded)") {
            check(DayNightWake.statusForDisplay(group: named, at: monday, guardedNow: monday) == nil, "corrupt named not nil")
            check(LimitFeatures.wakeStateForDisplay(for: legacy, at: monday, guardedNow: monday) == nil, "corrupt limit not nil")
            check(TimeGuard.nowForDisplay(at: monday, uptime: 10000) == monday, "missing display anchor not wall")
        }
    }
}
// UUID-keyed dictionaries legitimately encode as [] when empty. Do not call
// that canonical runtime encoding corrupt.
try reset(monday)
try JSONEncoder().encode([UUID: LimitFeatureEntry]()).write(to: LimitFeatures.testURL)
try readOnly("canonical empty limit runtime") {
    check(LimitFeatures.wakeStateForDisplay(for: legacy, at: monday, guardedNow: monday) == .needsTap,
          "valid empty UUID map is an untapped cycle")
}
try reset(monday)
DayNightWake.seed("wrong preference type")
try readOnly("wrong named type") {
    check(DayNightWake.statusForDisplay(group: named, at: monday, guardedNow: monday) == nil, "wrong named type not nil")
}
for (day, release) in [(42 as Any?, monday as Any?), (SharedStore.dayKey(for: monday) as Any?, "bad" as Any?),
                       (SharedStore.dayKey(for: monday) as Any?, nil), (nil, monday as Any?)] {
    try reset(monday); GlobalWake.seed(day: day, release: release)
    try readOnly("corrupt global") {
        check(GlobalWake.statusForDisplay(state: base, at: monday, guardedNow: monday) == nil, "corrupt global not nil")
    }
}
try reset(monday)
TestContainer.available = false
try readOnly("unavailable container") {
    check(LimitFeatures.wakeStateForDisplay(for: legacy, at: monday, guardedNow: monday) == nil, "missing container not nil")
}
TestContainer.available = true
try FileManager.default.createDirectory(at: LimitFeatures.testURL, withIntermediateDirectories: false)
// An unreadable path is not the same as an absent file (works even as root).
// files() intentionally reads files, so capture just preferences/counters here.
let pathWrites = SharedStore.defaults.writes, pathEffects = Effects.counts
check(LimitFeatures.wakeStateForDisplay(for: legacy, at: monday, guardedNow: monday) == nil, "directory runtime not nil")
check(pathWrites == SharedStore.defaults.writes && pathEffects == Effects.counts, "unreadable path mutated runtime")
try FileManager.default.removeItem(at: LimitFeatures.testURL)

// Actual TimeGuard now()/nowForDisplay decision bodies, with identical injected
// wall/uptime inputs. +/-300 is inclusive; just outside uses derived time.
for delta in [-301.0, -300.001, -300, -299.999, 0, 299.999, 300, 300.001, 301] {
    try reset(monday)
    let derived = monday.addingTimeInterval(-delta)
    TimeGuard.seed(wall: derived.addingTimeInterval(-100), uptime: 9900)
    let expected = abs(delta) > 300 ? derived : monday
    try readOnly("clock threshold \(delta)") {
        check(abs(TimeGuard.nowForDisplay(at: monday, uptime: 10000).timeIntervalSince(expected)) < 0.00001,
              "threshold derivation wrong")
        check(TimeGuard.nowForDisplay(at: monday, uptime: 10000) == TimeGuard.now(), "display clock differs from original")
    }
}
for reason in ["missing", "reboot", "invalid anchor"] {
    try reset(monday)
    if reason == "missing" { SharedStore.defaults.values = [:] }
    if reason == "reboot" { TimeGuard.seed(wall: monday.addingTimeInterval(-500), uptime: 20000) }
    if reason == "invalid anchor" { TimeGuard.seed(wall: Date(timeIntervalSince1970: 0), uptime: 9900) }
    try readOnly("clock \(reason)") {
        check(TimeGuard.nowForDisplay(at: monday, uptime: 10000) == monday, "unusable anchor not wall")
    }
    let writes = SharedStore.defaults.writes
    check(TimeGuard.now() == monday, "original fallback clock not wall")
    check(SharedStore.defaults.writes == writes + 2, "original anchoring positive control failed")
}
// Positive controls: prove the fakes detect original repair behavior.
try reset(monday)
DayNightWake.seed(Data("bad".utf8))
_ = DayNightWake.status(group: named, at: monday, guardedNow: monday)
check(SharedStore.enforcementDegraded, "named repair flag counter not exercised")
try Data("bad".utf8).write(to: LimitFeatures.testURL)
let repairWrites = SharedStore.defaults.writes
_ = LimitFeatures.wakeState(for: legacy, at: monday, guardedNow: monday)
check(SharedStore.defaults.writes > repairWrites && Effects.flags > 0, "limit splitReady repair positive control failed")
check(Effects.shields > 0, "actual tap shield adapter never exercised")
print("Wake widget read-only: \(assertions) assertions passed; actual API/status/tap bodies, in-memory preferences, temporary files")
print("Limits: fake Apple tokens/monitors/shields/coordination; no WidgetKit, locking race, protected-file or signed-device proof")
'''


def main():
    sources = guard_originals()
    clock = sources["TimeGuard.swift"]
    # Exclude the network method entirely; preserve the actual clock constants,
    # both derivations and original anchoring implementation.
    clock = "enum TimeGuard {\n" + "\n".join(re.findall(r"    private static let [^\n]+", clock)) + "\n" + "\n".join(
        block(clock, sig) for sig in ["static func now()", "static func nowForDisplay(", "private static func anchor("]
    ) + "\n}"
    features = sources["LimitFeatures.swift"]
    limit_prefix = features[features.index("enum LimitFeatures {"):features.index("    /// Enabling a previously disabled group gate")]
    limits = limit_prefix + block(features, "static func wakeUp(") + r'''
    private static func scheduleWake(for id: UUID, at date: Date) { Effects.monitorStarts += 1 }
}
'''
    engine = sources["ChangeEngine.swift"]
    pieces = [INFRASTRUCTURE,
              block((ROOT / "Shared/SharedStore.swift").read_text(), "static func dayKey(for"), "}",
              portable((ROOT / "Shared/SharedModels.swift").read_text()),
              (ROOT / "Shared/PhraseWords.swift").read_text(),
              (ROOT / "Shared/MonitoringBudget.swift").read_text(),
              clock, block(engine, "enum GlobalWakeStatus:"), block(engine, "enum GlobalWake {"),
              portable(sources["DayNightWake.swift"]), block(features, "enum WakeState:"),
              block(features, "private struct LimitFeatureEntry:"), limits]
    source = inputs("\n".join(pieces)) + BRIDGES + CHECKS
    assert "containerURL(" not in source.replace("TestContainer.containerURL(", "").replace("func containerURL(", "")
    assert "URLSession" not in source and "UserDefaults(" not in source
    with tempfile.TemporaryDirectory(prefix="demora-wake-read-only-") as directory:
        root = Path(directory)
        runtime = root / "runtime"
        runtime.mkdir()
        path = root / "main.swift"
        path.write_text(source)
        for configuration, flags in [("Debug", ["-D", "DEBUG"]), ("Release", [])]:
            binary = root / configuration
            subprocess.run(["xcrun", "swiftc", *flags, str(path), "-o", str(binary)], check=True)
            subprocess.run([str(binary), str(runtime)], check=True,
                           env={**os.environ, "TZ": "America/New_York"})
            print(f"{configuration} isolated checks passed", flush=True)


if __name__ == "__main__":
    main()
