#!/usr/bin/env python3
"""F1 regression: compile the real TimeGuard and run sleep, tamper, reboot and
migration scenarios natively on macOS.

Run: python3 Tests/TimeGuardHarness.py
Compiled unchanged: Shared/TimeGuard.swift (current), the 2.0 TimeGuard from
BASELINE as a positive control (renamed LegacyTimeGuard; it is what wrote the
anchors the new clock migrates), ApplyActivityTiming from ChangeEngine.swift
and CountdownProjection/ClockReading from DemoraComponents.swift.
Only the boundaries are substituted: wall clock, CLOCK_MONOTONIC_RAW,
systemUptime and SharedStore.defaults (in memory, values round-tripped
through a binary property list like UserDefaults). No network, App Group,
DeviceActivity or Xcode build. This cannot prove how a real iPhone's clocks
behave while it sleeps; that needs the phone (lock it across a deadline).
"""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "81757bb14890f80ff46e3bbf9dfbcf84db14eb50"  # 2.0 TimeGuard (unchanged since July)


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
                return source[start:match.end()]
    raise AssertionError(f"Unclosed declaration: {signature}")


def inputs(source):
    """Boundary substitutions only; no decision logic is rewritten."""
    for old, new in [("clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)", "TestClock.continuousNanos"),
                     ("ProcessInfo.processInfo.systemUptime", "TestClock.uptime"),
                     ("sysctlbyname(", "TestClock.sysctlbyname("),
                     ("Date.now", "TestClock.wall"),
                     ("Date()", "TestClock.wall")]:
        source = source.replace(old, new)
    return source


timeguard = (ROOT / "Shared/TimeGuard.swift").read_text()
legacy = subprocess.check_output(["git", "show", f"{BASELINE}:Shared/TimeGuard.swift"],
                                 cwd=ROOT, text=True)
engine = (ROOT / "Shared/ChangeEngine.swift").read_text()
components = (ROOT / "Latch/DemoraComponents.swift").read_text()
app_model = (ROOT / "Latch/AppModel.swift").read_text()
monitor = (ROOT / "LatchMonitor/DeviceActivityMonitorExtension.swift").read_text()

# --- Source guards -----------------------------------------------------------
assert "clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)" in timeguard, "sleep-inclusive raw clock"
assert "CLOCK_MONOTONIC)" not in timeguard, "not the wall-derived CLOCK_MONOTONIC"
assert "systemUptime" not in span(timeguard, "static func continuousTime()"), "elapsed time includes sleep"
assert timeguard.count("SharedStore.defaults.set(") == 4, "only the v2 record, the marker (2 sites) and lastSync"
for key in ("legacyAnchorWallKey", "legacyAnchorUptimeKey"):
    assert f"forKey: {key})" not in timeguard.replace("double(forKey: " + key + ")", ""), \
        ("the 2.0 anchor is read, never written", key)
schedule = span(engine, "private static func scheduleApplyActivity(")
assert "ApplyActivityTiming.start(appliesAt: change.appliesAt, guardedNow: guardedNow," in schedule
assert "max(change.appliesAt" not in schedule, "raw guarded deadline no longer scheduled as wall time"
house = span(engine, "static func housekeeping()")
assert house.index("applyDueChanges()") < house.index("rescheduleApplyActivities(state: SharedStore.loadState())"), \
    "reschedule only what is still waiting after applying due changes"
resched = span(engine, "static func rescheduleApplyActivities(")
assert "$0.appliesAt > guardedNow" in resched and "startMonitoring" not in resched, \
    "only waiting changes, through the one registration path (scheduleApplyActivity)"
assert "max(1, change.appliesAt.timeIntervalSince(TimeGuard.now()))" in span(engine, "private static func scheduleNotification("), \
    "the ready notification uses guarded remaining time"
# 2.0.1: the override defers display publishing and calls this handler.
assert "DisplayPublishing.deferring { handleIntervalDidStart(activity) }" in span(monitor, "override func intervalDidStart(")
did_start = span(monitor, "private func handleIntervalDidStart(")
assert did_start.index("ChangeEngine.applyDueChanges()") < did_start.index("raw.hasPrefix(LatchConstants.applyActivityPrefix)") \
    < did_start.index("ChangeEngine.rescheduleApplyActivities("), "an early apply callback re-registers"
tick = span(app_model, "func tick()")
# Review fix 7: housekeeping never waits on the network; what a forced sync
# makes due applies right after it.
first, sync, second = (tick.index("await ChangeEngine.housekeepingOffMain()"),
                       tick.index("await TimeGuard.syncWithNetwork(force: true)"),
                       tick.rindex("await ChangeEngine.housekeepingOffMain()"))
assert tick.index("forcedTimeSync.begin(") < first < sync < tick.index("guard synced else { return }") < second
assert "self.forcedTimeSync.finish(succeeded: synced," in tick
queue = span(engine, "private static func queueCoordinated(")
assert "let start = direction == .lenient ? TimeGuard.looseningStart(guarded: guardedNow) : guardedNow" in queue
assert "createdAt: start,\n            appliesAt: start.addingTimeInterval(delay)," in queue, "both from the same start"
assert "let now = TimeGuard.now()\n                let change = PendingChange(createdAt: now, appliesAt: now, direction: .lenient," in queue, \
    "the zero-delay free-time start stays immediately due on the guarded clock"
assert "scheduleNotification(for: change)" in resched, "review fix 8: the ready notification follows the reschedule"
print("TimeGuard source guards passed: raw continuous clock, wall-time apply schedule, reschedule, tick order")

INFRASTRUCTURE = r'''
import Foundation
import Darwin

enum TestClock {
    static var wall = Date(timeIntervalSince1970: 2_000_000_000)
    static var continuous: TimeInterval = 50_000   // CLOCK_MONOTONIC_RAW seconds
    static var uptime: TimeInterval = 20_000       // systemUptime seconds
    static var continuousNanos: UInt64 { UInt64(continuous * 1_000_000_000) }
    /// kern.bootsessionuuid; nil = the OS won't let us read it (fallback path).
    static var boot: String? = nil
    static var bootReads = 0
    /// Same contract as Darwin's sysctlbyname for a string value.
    static func sysctlbyname(_ name: String, _ old: UnsafeMutableRawPointer?, _ size: UnsafeMutablePointer<Int>?,
                             _ new: UnsafeMutableRawPointer?, _ newSize: Int) -> Int32 {
        bootReads += 1
        guard name == "kern.bootsessionuuid", let boot, let size else { return -1 }
        let bytes = Array(boot.utf8) + [0]
        if let old {
            guard size.pointee >= bytes.count else { return -1 }
            old.copyMemory(from: bytes, byteCount: bytes.count)
        }
        size.pointee = bytes.count
        return 0
    }
    /// Real time passes: both elapsed clocks and the wall clock move.
    static func awake(_ seconds: TimeInterval) { wall += seconds; continuous += seconds; uptime += seconds }
    /// The phone sleeps: real time and CLOCK_MONOTONIC_RAW move, uptime barely does.
    static func asleep(_ seconds: TimeInterval, uptime awake: TimeInterval) {
        wall += seconds; continuous += seconds; uptime += awake
    }
}

/// UserDefaults stand-in. Values round-trip through a binary property list, so
/// reads return NSNumber/NSDictionary like the real store.
final class MemoryDefaults {
    var values: [String: Any] = [:]
    var writes: [String] = []
    func object(forKey key: String) -> Any? { values[key] }
    func double(forKey key: String) -> Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
    func removeObject(forKey key: String) { writes.append(key); values.removeValue(forKey: key) }
    func set(_ value: Any?, forKey key: String) {
        writes.append(key)
        guard let value else { values.removeValue(forKey: key); return }
        let data = try! PropertyListSerialization.data(fromPropertyList: ["v": value], format: .binary, options: 0)
        let plist = try! PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        values[key] = plist["v"]
    }
}
enum SharedStore { static let defaults = MemoryDefaults() }
'''

BRIDGES = r'''
// Test-only access to the real private keys and helpers (same file).
extension TimeGuard {
    static var recordKey: String { anchorKey }
    static var legacyKeys: [String] { [legacyAnchorWallKey, legacyAnchorUptimeKey] }
    static var markerKey: String { migratedKey }
    static var syncKey: String { lastSyncKey }
    static var record: [String: Any]? { SharedStore.defaults.object(forKey: anchorKey) as? [String: Any] }
    static func field(_ name: String) -> Double? { (record?[name] as? NSNumber)?.doubleValue }
    static func testAdopt(_ date: Date) { adopt(networkDate: date) }
    static func testShouldSync(force: Bool, wall: TimeInterval, lastSync: TimeInterval) -> Bool {
        shouldSync(force: force, wall: wall, lastSync: lastSync)
    }
}
'''

CHECKS = r'''
var assertions = 0
func check(_ ok: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !ok() { print("FAIL: " + message); exit(1) }
}
func near(_ a: Date, _ b: Date, _ slack: TimeInterval = 0.000_5) -> Bool { abs(a.timeIntervalSince(b)) <= slack }
let start = Date(timeIntervalSince1970: 2_000_000_000)
func reset() {
    SharedStore.defaults.values = [:]; SharedStore.defaults.writes = []
    TestClock.wall = start; TestClock.continuous = 50_000; TestClock.uptime = 20_000
    TestClock.boot = nil
}
let bootA = "036D18B8-1B31-4284-AAB6-398CC9F35AA5", bootB = "7F1C2E54-90AB-4C1D-8E2F-3A4B5C6D7E8F"
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "America/New_York")!

// 1. Sleep (the owner's report). Wall +40 min, continuous +40 min, uptime +2 min.
reset()
check(TimeGuard.now() == start, "first run anchors on the wall clock")
check(SharedStore.defaults.writes == [TimeGuard.recordKey, TimeGuard.markerKey], "one atomic record + marker, no 2.0 keys")
let appliesAt = TimeGuard.now().addingTimeInterval(30 * 60)   // queued with a 30 min wait
TestClock.asleep(40 * 60, uptime: 2 * 60)
let woke = TimeGuard.now()
check(woke == TestClock.wall, "now() follows real time through sleep")
check(woke >= appliesAt, "the change counts as due after sleeping past its deadline")
check(TimeGuard.nowForDisplay() == woke, "display clock agrees")
check(!TimeGuard.clocksDisagree(guarded: woke), "no forced re-sync needed")
check(SharedStore.defaults.writes.count == 2, "sleep needs no re-anchor")
// Positive control: the 2.0 clock on identical inputs reproduces the bug.
reset()
check(LegacyTimeGuard.now() == start, "2.0 anchors on the wall clock")
TestClock.asleep(40 * 60, uptime: 2 * 60)
let legacyWoke = LegacyTimeGuard.now()
check(near(legacyWoke, start.addingTimeInterval(2 * 60)), "2.0 counted only awake time")
check(legacyWoke < appliesAt, "2.0 left the change pending (fixture reproduces the bug)")
// Longer and repeated sleeps keep tracking real time.
reset(); _ = TimeGuard.now()
for _ in 0..<12 { TestClock.asleep(3 * 3600, uptime: 30); TestClock.awake(45) }
check(TimeGuard.now() == TestClock.wall, "a night of naps still tracks real time")

// 2. A wall-clock jump forward with no real elapsed time is still rejected.
for jump: TimeInterval in [600, 2 * 3600, 3 * 86_400] {
    reset(); _ = TimeGuard.now()
    let due = start.addingTimeInterval(30 * 60)
    TestClock.wall += jump
    check(TimeGuard.now() == start, "jump +\(jump) s rejected")
    check(TimeGuard.now() < due, "jump +\(jump) s does not make a change due")
    check(TimeGuard.clocksDisagree(guarded: TimeGuard.now()), "jump forces a re-sync on the next tick")
    TestClock.continuous += 10; TestClock.uptime += 10
    check(TimeGuard.now() == start.addingTimeInterval(10), "only real elapsed time counts after a jump")
    TestClock.asleep(40 * 60, uptime: 60)
    check(TimeGuard.now() == start.addingTimeInterval(10 + 40 * 60), "jump then sleep: real time only")
    check(SharedStore.defaults.writes.count == 2, "a jump never re-anchors (no creeping)")
}
for (delta, wallWins) in [(-301.0, false), (-300.001, false), (-300, true), (-299, true), (0, true),
                          (299, true), (300, true), (300.001, false), (301, false)] {
    reset(); _ = TimeGuard.now()
    TestClock.wall += delta
    let expected = wallWins ? TestClock.wall : start
    check(near(TimeGuard.now(), expected), "tolerance boundary \(delta) inclusive at 300 s")
    check(near(TimeGuard.nowForDisplay(), expected), "display boundary \(delta)")
}
reset(); _ = TimeGuard.now(); TestClock.wall -= 2 * 3600
check(TimeGuard.now() == start, "clock set back: derived time wins (no new-day reset)")

// 3. Reboot: an elapsed clock restarted below its anchor value.
for (label, continuous, uptime) in [("both restarted", 100.0, 90.0),
                                    ("continuous caught up, uptime not", 60_000.0, 500.0),
                                    ("uptime caught up, continuous not", 40_000.0, 25_000.0)] {
    reset(); _ = TimeGuard.now()
    TestClock.wall = start.addingTimeInterval(86_400); TestClock.continuous = continuous; TestClock.uptime = uptime
    check(TimeGuard.nowForDisplay() == TestClock.wall, "\(label): display falls back to wall without writing")
    check(SharedStore.defaults.writes.count == 2, "\(label): display read wrote nothing")
    check(TimeGuard.now() == TestClock.wall, "\(label): reboot falls back to wall")
    check(TimeGuard.field("continuous") == continuous && TimeGuard.field("uptime") == uptime,
          "\(label): re-anchored on this boot's clocks")
    TestClock.awake(60)
    check(TimeGuard.now() == TestClock.wall, "\(label): counts normally after the reboot")
}
// Documented residual: a reboot nobody saw until both clocks passed the anchor.
// The clock runs behind (waits longer, never shorter) until a network sync.
reset(); TestClock.continuous = 600; TestClock.uptime = 500; _ = TimeGuard.now()
TestClock.wall += 5 * 86_400; TestClock.continuous = 900; TestClock.uptime = 800
check(TimeGuard.now() < TestClock.wall, "missed reboot errs late, never early")
check(TimeGuard.clocksDisagree(guarded: TimeGuard.now()), "and the app re-syncs on its next tick")

// 4. Migration from 2.0 anchors: once, starting where the old clock reads.
reset()
_ = LegacyTimeGuard.now()                                   // 2.0 wrote its anchor
let legacyBefore = TimeGuard.legacyKeys.map { SharedStore.defaults.values[$0] as? NSNumber }
let oldDeadline = LegacyTimeGuard.now().addingTimeInterval(45 * 60)
TestClock.asleep(2263, uptime: 0)                           // 37 min 43 s asleep
let oldReads = LegacyTimeGuard.now()
check(oldReads == start, "2.0 fell 37:43 behind")
SharedStore.defaults.writes = []
check(TimeGuard.nowForDisplay() == oldReads, "display before migration reads 2.0's clock, read-only")
check(SharedStore.defaults.writes.isEmpty, "display never migrates")
let migrated = TimeGuard.now()
check(migrated == oldReads, "migration starts exactly where 2.0 reads: no deadline moves earlier")
check(oldDeadline.timeIntervalSince(migrated) == oldDeadline.timeIntervalSince(oldReads), "same remaining wait")
check(SharedStore.defaults.writes == [TimeGuard.recordKey, TimeGuard.markerKey], "migration writes one v2 record + marker only")
check(TimeGuard.legacyKeys.map { SharedStore.defaults.values[$0] as? NSNumber } == legacyBefore, "2.0 keys untouched")
check(TimeGuard.field("version") == 2 && TimeGuard.field("wall") == oldReads.timeIntervalSince1970,
      "versioned record anchored on the old guarded time")
TestClock.asleep(10 * 60, uptime: 0)
check(TimeGuard.now() == migrated.addingTimeInterval(10 * 60), "after migration, sleep counts")
check(TimeGuard.clocksDisagree(guarded: TimeGuard.now()), "inherited lag forces a re-sync")
SharedStore.defaults.values[TimeGuard.legacyKeys[0]] = NSNumber(value: 9_000_000_000.0)
check(TimeGuard.now() == migrated.addingTimeInterval(10 * 60), "migration ran once; 2.0 keys ignored after")
TimeGuard.testAdopt(TestClock.wall)                         // the forced network sync
check(TimeGuard.now() == TestClock.wall && !TimeGuard.clocksDisagree(guarded: TimeGuard.now()),
      "a network sync clears the inherited lag")
check(TimeGuard.now() >= oldDeadline, "the 2.0 deadline lands at its real time after the sync")
// Other 2.0 states.
reset(); _ = LegacyTimeGuard.now(); TestClock.awake(120)
check(TimeGuard.now() == TestClock.wall, "2.0 within tolerance: migrates on the wall clock")
reset(); _ = LegacyTimeGuard.now(); TestClock.wall += 86_400; TestClock.continuous = 50; TestClock.uptime = 40
check(TimeGuard.now() == TestClock.wall, "rebooted since 2.0's anchor: wall, like 2.0")
reset(); _ = LegacyTimeGuard.now(); TestClock.wall += 3600
check(TimeGuard.now() == start, "2.0 had caught a clock change: migration keeps rejecting it")
reset()
check(TimeGuard.now() == start && TimeGuard.record != nil, "fresh install: wall, new record")
// Review fix 3: an unreadable record is never trusted and never sends us
// back to months-old 2.0 keys; it re-anchors like a reboot.
for bad in ["text" as Any, ["version": 1.0, "wall": 1.0, "continuous": 1.0, "uptime": 1.0] as Any,
            ["version": 3.0, "wall": 1.0, "continuous": 1.0, "uptime": 1.0] as Any,
            ["version": 2.0, "wall": 1.0, "continuous": 1.0] as Any,
            ["version": 2.0, "wall": "x", "continuous": 1.0, "uptime": 1.0] as Any] {
    reset(); _ = LegacyTimeGuard.now(); TestClock.asleep(3600, uptime: 0)
    SharedStore.defaults.set(bad, forKey: TimeGuard.recordKey)
    check(TimeGuard.nowForDisplay() == TestClock.wall, "display: bad record reads wall, not 2.0 keys")
    check(TimeGuard.now() == TestClock.wall, "bad record ignored; 2.0 keys not reused")
    check(TimeGuard.field("version") == 2, "bad record replaced by a valid one")
}

// 5. Network re-sync rate limit.
check(TimeGuard.testShouldSync(force: true, wall: 1_000, lastSync: 999), "force skips the hourly limit")
check(!TimeGuard.testShouldSync(force: false, wall: 1_000, lastSync: 999), "hourly limit otherwise")
check(TimeGuard.testShouldSync(force: false, wall: 5_000, lastSync: 1_000), "after an hour")
check(TimeGuard.testShouldSync(force: false, wall: 500, lastSync: 1_000), "clock set before the last sync")
reset(); SharedStore.defaults.writes = []
TimeGuard.testAdopt(start.addingTimeInterval(3600))
check(SharedStore.defaults.writes == [TimeGuard.recordKey, TimeGuard.markerKey, TimeGuard.syncKey],
      "network sync writes one record, the marker once, and lastSync")
check(TimeGuard.now() == start.addingTimeInterval(3600), "network date wins past tolerance")

// 6. Apply activity on the wall clock (owner's numbers: 37:43 behind, 1:44 left).
let wallNow = cal.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 11, minute: 55, second: 0))!
let guardedNow = wallNow.addingTimeInterval(-2263)
let deadline = guardedNow.addingTimeInterval(104)
let due = ApplyActivityTiming.wallDue(appliesAt: deadline, guardedNow: guardedNow, wallNow: wallNow)
check(due == wallNow.addingTimeInterval(104), "guarded deadline converted to wall time")
let begin = ApplyActivityTiming.start(appliesAt: deadline, guardedNow: guardedNow, wallNow: wallNow, calendar: cal)
check(begin >= due && begin.timeIntervalSince(due) < 60, "rounded up, at or after the wall landing")
check(cal.component(.second, from: begin) == 0, "whole minute")
let oldStart = cal.date(from: cal.dateComponents([.year, .month, .day, .hour, .minute], from: deadline))!
    .addingTimeInterval(60)                                  // 2.0: ceil of the raw guarded deadline
check(oldStart < due, "2.0's registration fired before the change was due")
check(ApplyActivityTiming.needsReschedule(registeredStart: oldStart, appliesAt: deadline,
      guardedNow: guardedNow, wallNow: wallNow, calendar: cal), "early registration is replaced")
check(ApplyActivityTiming.needsReschedule(registeredStart: nil, appliesAt: deadline,
      guardedNow: guardedNow, wallNow: wallNow, calendar: cal), "missing registration is replaced")
check(!ApplyActivityTiming.needsReschedule(registeredStart: begin, appliesAt: deadline,
      guardedNow: guardedNow, wallNow: wallNow, calendar: cal), "a healthy registration is left alone")
for later in [1.0, 30, 59, 100] {   // both clocks advance together while waiting: no churn
    check(!ApplyActivityTiming.needsReschedule(registeredStart: begin, appliesAt: deadline,
          guardedNow: guardedNow.addingTimeInterval(later), wallNow: wallNow.addingTimeInterval(later),
          calendar: cal), "no churn \(later) s later")
}
check(ApplyActivityTiming.needsReschedule(registeredStart: begin.addingTimeInterval(660), appliesAt: deadline,
      guardedNow: guardedNow, wallNow: wallNow, calendar: cal), "eleven minutes late is replaced")
check(!ApplyActivityTiming.needsReschedule(registeredStart: begin.addingTimeInterval(300), appliesAt: deadline,
      guardedNow: guardedNow, wallNow: wallNow, calendar: cal), "five minutes late is tolerated (hysteresis)")
// Review fix 4: a registration whose interval already started is spent, even
// when it started within a second of the landing.
for offset in [-0.5, 0.0] {
    let spent = wallNow.addingTimeInterval(offset)
    check(ApplyActivityTiming.needsReschedule(registeredStart: spent, appliesAt: wallNow.addingTimeInterval(0.4),
          guardedNow: wallNow, wallNow: wallNow, calendar: cal), "started registration \(offset) s is replaced")
}
// Review fix 5: clocks hovering at the tolerance flip the guarded time by
// ~300 s; at most one re-registration, not one per flip.
do {
    let target = wallNow.addingTimeInterval(3600)
    var registered = ApplyActivityTiming.start(appliesAt: target, guardedNow: wallNow, wallNow: wallNow, calendar: cal)
    var registrations = 0
    for flip in 0..<20 {
        let wall = wallNow.addingTimeInterval(Double(flip) * 30)
        let guarded = flip % 2 == 0 ? wall : wall.addingTimeInterval(-301)
        if ApplyActivityTiming.needsReschedule(registeredStart: registered, appliesAt: target,
                                               guardedNow: guarded, wallNow: wall, calendar: cal) {
            registrations += 1
            registered = ApplyActivityTiming.start(appliesAt: target, guardedNow: guarded, wallNow: wall, calendar: cal)
        }
        check(registered >= ApplyActivityTiming.wallDue(appliesAt: target, guardedNow: guarded, wallNow: wall),
              "never left firing before the change is due")
    }
    check(registrations == 1, "hysteresis: \(registrations) re-registrations over 20 flips")
}
let soon = ApplyActivityTiming.start(appliesAt: guardedNow.addingTimeInterval(5), guardedNow: guardedNow,
                                     wallNow: wallNow, calendar: cal)
check(soon >= wallNow.addingTimeInterval(60), "at least a minute ahead")
let agree = ApplyActivityTiming.start(appliesAt: wallNow.addingTimeInterval(1800), guardedNow: wallNow,
                                      wallNow: wallNow, calendar: cal)
check(agree == wallNow.addingTimeInterval(1800), "clocks agree: same start as before F1")

// 8. Review fix 1: a loosening queued while the guarded clock is behind keeps
// its full real wait after a sync corrects the clock.
reset(); TestClock.continuous = 600; TestClock.uptime = 500; _ = TimeGuard.now()   // early-boot anchor
TestClock.wall += 86_400; TestClock.continuous = 900; TestClock.uptime = 800         // missed reboot, a day later
let lagging = TimeGuard.now()
check(TestClock.wall.timeIntervalSince(lagging) > 80_000, "fixture: guarded clock about a day behind")
let delay: TimeInterval = 24 * 3600
let looseStart = TimeGuard.looseningStart(guarded: lagging)
let looseDeadline = looseStart.addingTimeInterval(delay)
let oldDeadline2 = lagging.addingTimeInterval(delay)                                  // before the fix
TestClock.awake(5)
TimeGuard.testAdopt(TestClock.wall)                                                   // back online
let corrected = TimeGuard.now()
check(corrected == TestClock.wall, "sync corrects the clock")
check(looseDeadline.timeIntervalSince(corrected) >= delay - 5, "real wait still ≥ the delay (minus the 5 s that passed)")
check(oldDeadline2.timeIntervalSince(corrected) < 600, "positive control: a guarded-based 24 h wait would end within minutes")
check(TimeGuard.looseningStart(guarded: start, wall: start.addingTimeInterval(-3600)) == start,
      "clock set back: the guarded clock is later")
check(TimeGuard.looseningStart(guarded: start, wall: start.addingTimeInterval(7200)) == start.addingTimeInterval(7200),
      "clock set forward: only delays the user's own loosening")
check(TimeGuard.looseningStart(guarded: start, wall: start) == start, "clocks agree: unchanged")
// Stricter changes keep the guarded clock: a clock set forward can't postpone tightening.
reset(); _ = TimeGuard.now(); TestClock.wall += 7200
check(TimeGuard.now() == start, "forged +2 h rejected; stricter deadline = guarded now + delay")

// 9. Review fix 1 (also): boot identity in the anchor, when readable.
reset(); TestClock.boot = bootA; TestClock.continuous = 600; TestClock.uptime = 500; _ = TimeGuard.now()
check(TimeGuard.record?["boot"] as? String == bootA, "anchor records the boot")
TestClock.boot = bootB; TestClock.wall += 86_400; TestClock.continuous = 900; TestClock.uptime = 800
check(TimeGuard.nowForDisplay() == TestClock.wall, "another boot is a reboot even when both clocks caught up")
check(TimeGuard.now() == TestClock.wall && TimeGuard.record?["boot"] as? String == bootB, "re-anchored on the new boot")
reset(); TestClock.boot = bootA; _ = TimeGuard.now(); TestClock.boot = nil; TestClock.continuous = 10; TestClock.uptime = 9
check(TimeGuard.now() == TestClock.wall, "identity unreadable later: falls back to the clock check")
reset(); TestClock.boot = nil; _ = TimeGuard.now(); TestClock.boot = bootA; TestClock.awake(60)
check(TimeGuard.now() == TestClock.wall, "old record without identity: clock check, no crash")
for bad in ["not-a-uuid", "", String(repeating: "A", count: 200)] {
    reset(); TestClock.boot = bad
    check(TimeGuard.bootSession() == nil, "unusable identity \(bad.count) chars is ignored")
}
reset(); TestClock.boot = bootA
check(TimeGuard.bootSession() == bootA, "identity read through sysctl's size-then-value calls")

// 10. Review fix 2: an anchor written between our clock sample and our read
// (another process syncing while the clock is forged) is not a reboot.
for identity in [nil, bootA] as [String?] {
    reset(); TestClock.boot = identity; _ = TimeGuard.now()
    TestClock.wall += 7200                                    // forged +2 h
    let sampled = (continuous: TestClock.continuous - 0.5, uptime: TestClock.uptime - 0.5)
    check(TimeGuard.nowForDisplay(at: TestClock.wall, continuous: sampled.continuous, uptime: sampled.uptime,
                                  boot: identity) == start, "race: forged clock not adopted (boot \(identity ?? "nil"))")
    check(TimeGuard.nowForDisplay(at: TestClock.wall, continuous: TestClock.continuous - 0.5,
                                  uptime: TestClock.uptime - 5, boot: identity) == (identity == nil ? TestClock.wall : start),
          "beyond the 1 s slack without identity is a reboot; with the same identity it never is")
}
reset(); _ = TimeGuard.now()
SharedStore.defaults.removeObject(forKey: TimeGuard.recordKey)
SharedStore.defaults.values[TimeGuard.legacyKeys[0]] = NSNumber(value: start.timeIntervalSince1970 - 9_999)
SharedStore.defaults.values[TimeGuard.legacyKeys[1]] = NSNumber(value: 1)
check(TimeGuard.now() == start, "record gone after migration: wall, never the 2.0 keys again")

// 11. Review fix 7: forced sync policy.
var policy = ForcedTimeSyncPolicy()
check(!policy.begin(offset: 299, uptime: 0), "no forced sync while the clocks agree")
check(policy.begin(offset: 2263, uptime: 0), "disagreeing: sync")
check(!policy.begin(offset: 2263, uptime: 30), "claimed: a second tick can't start another")
var waits: [TimeInterval] = []
var clock: TimeInterval = 0
for _ in 0..<7 {
    policy.finish(succeeded: false, offsetAfter: 2263, uptime: clock)
    waits.append(policy.nextAttempt - clock)
    clock = policy.nextAttempt
    check(!policy.begin(offset: 2263, uptime: clock - 1) && policy.begin(offset: 2263, uptime: clock), "backoff respected")
}
check(waits == [60, 120, 240, 480, 900, 900, 900], "offline backs off to 15 min: \(waits)")
policy.finish(succeeded: true, offsetAfter: 7200, uptime: clock)
check(policy.settledOffset == 7200 && !policy.begin(offset: 7230, uptime: clock + 3600), "wall itself wrong: no repeat")
check(policy.begin(offset: 7300, uptime: clock + 3600), "the offset moved: sync again")
policy.finish(succeeded: true, offsetAfter: 2, uptime: clock + 3600)
check(policy.settledOffset == nil && policy.failures == 0, "agreeing after a sync clears the state")

// 7. Changes card: landing time, group and countdown share one reading.
let reading = ClockReading(guarded: guardedNow, system: wallNow)
let landing = reading.landing(of: deadline)
let countdown = CountdownProjection.interval(until: deadline, guardedNow: reading.guarded, systemNow: reading.system)
check(landing == due, "landing time is when it lands on the system clock (11:56:44, not 11:19)")
check(near(countdown.upperBound, landing), "countdown ends at the landing time shown")
check(reading.landing(of: guardedNow.addingTimeInterval(-60)) < wallNow, "a due change keeps a past time")
reset(); _ = TimeGuard.now()
let live = ClockReading.current()
check(live.guarded == start && live.system == start && live.landing(of: start.addingTimeInterval(9)) == start.addingTimeInterval(9),
      "clocks agree: landing is the stored deadline")
print("TimeGuard: \(assertions) assertions passed (sleep, jumps, tolerance, reboot, migration, sync limit, apply timing, card clock, review fixes 1-5 and 7)")
print("Not covered: a real iPhone's clocks while asleep, DeviceActivity delivery, cfprefsd cross-process timing")
'''


def main():
    current = inputs(timeguard)
    old = inputs(legacy).replace("enum TimeGuard {", "enum LegacyTimeGuard {", 1)
    old = old.replace("import Foundation\n", "")
    timing = span(engine, "enum ApplyActivityTiming {")
    projection = span(components, "enum CountdownProjection {")
    reading = inputs(span(components, "struct ClockReading {"))
    source = "\n".join([INFRASTRUCTURE, current.replace("import Foundation\nimport Darwin\n", ""),
                        old, timing, projection, reading, BRIDGES, CHECKS])
    assert "URLSession.shared.data" in source  # the real network method compiles, but is never called
    with tempfile.TemporaryDirectory(prefix="demora-timeguard-") as directory:
        path = Path(directory) / "main.swift"
        binary = Path(directory) / "timeguard"
        path.write_text(source)
        subprocess.run(["xcrun", "swiftc", str(path), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
        # The real boot-identity read, unmocked, on this Mac. iOS may refuse
        # it (then nil and the clock check is used); that needs the phone.
        real = Path(directory) / "boot.swift"
        real.write_text("import Foundation\nimport Darwin\nenum Real {\n" + span(timeguard, "static func bootSession()")
                        + "\n}\nlet id = Real.bootSession()\nguard let id, UUID(uuidString: id) != nil, id == Real.bootSession() "
                        + "else { print(\"FAIL: no stable boot identity on macOS\"); exit(1) }\n"
                        + "print(\"Boot identity read on macOS: stable UUID\")\n")
        subprocess.run(["xcrun", "swiftc", str(real), "-o", str(binary) + "-boot"], check=True)
        subprocess.run([str(binary) + "-boot"], check=True)


if __name__ == "__main__":
    main()
