#!/usr/bin/env python3
"""Run real wake runtime reads/writes against a temporary file on macOS.

Opaque Apple tokens and monitor/shield effects are stubbed. File coordination,
JSON decoding, readback verification and the production wake methods are real.
GlobalWake is also compiled intact against temporary UserDefaults. The full
ChangeEngine application path is not linked; its setWakeRule tap-clearing
condition has a separate narrow source assertion, not a runtime claim.
This does not test iOS protected-file or DeviceActivity delivery behavior.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def block(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


features = (ROOT / "Shared/LimitFeatures.swift").read_text()
engine = (ROOT / "Shared/ChangeEngine.swift").read_text()
global_wake = block(engine, "enum GlobalWakeStatus:") + "\n" + block(engine, "enum GlobalWake {")
# Full ChangeEngine.apply needs unrelated enforcement/notification machinery.
# Keep this coverage explicitly structural rather than reimplementing apply.
apply = block(engine, "private static func apply(")
wake_apply = apply.split("case .setWakeRule(let rule):", 1)[1].split("case .setSleepRule", 1)[0]
assert wake_apply.index("let wasEnabled = state.wakeRule.enabled") < wake_apply.index("state.wakeRule = rule")
assert wake_apply.count("GlobalWake.clearTap()") == 1
assert re.search(r"if\s+!rule\.enabled\s*\|\|\s*!wasEnabled\s*\{\s*GlobalWake\.clearTap\(\)\s*\}", wake_apply)
models = (ROOT / "Shared/SharedModels.swift").read_text().replace(
    "import FamilyControls\n", ""
).replace("import ManagedSettings\n", "")
phrases = (ROOT / "Shared/PhraseWords.swift").read_text()
budget = (ROOT / "Shared/MonitoringBudget.swift").read_text()
logic = "\n".join(block(features, signature) for signature in [
    "private static func loadAll()", "private static func mutate(",
    "private static func entry(", "static func wakeState(",
    "static func prepareNewWakeGates(", "static func wakeUp(",
])
types = block(features, "enum WakeState:") + "\n" + block(features, "private struct LimitFeatureEntry:").replace("private struct", "struct", 1)

infrastructure = r'''
import Foundation
struct FamilyActivitySelection: Codable, Equatable {
    var applicationTokens: Set<String> = []
    var categoryTokens: Set<String> = []
    var webDomainTokens: Set<String> = []
}
func tr(_ text: String) -> String { text }
enum TimeGuard { static var date = Date(); static func now() -> Date { date } }
enum SharedStore {
    static var state = LatchState()
    static var simulating = false
    static var enforcementDegraded = false
    static let suite = "demora-wake-runtime-test." + UUID().uuidString
    static let defaults = UserDefaults(suiteName: suite)!
    static func loadState() -> LatchState { state }
    static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year!)-\(components.month!)-\(components.day!)"
    }
}
struct DeviceActivityName { let rawValue: String; init(_ name: String) { rawValue = name } }
struct DeviceActivitySchedule {
    var intervalStart: DateComponents
    var intervalEnd: DateComponents
    var repeats: Bool
}
enum MonitorRegistration {
    static func start(_ name: DeviceActivityName, during schedule: DeviceActivitySchedule) throws {}
}
struct DeviceActivityCenter {
    static var stopped: [String] = []
    var activities: [DeviceActivityName] { [] }
    func stopMonitoring(_ names: [DeviceActivityName]) { Self.stopped += names.map(\.rawValue) }
}
enum ShieldController { static func refresh() {} }
'''

driver = r'''
enum LimitFeatures {
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("demora-wake-runtime." + UUID().uuidString)
    private static var fileURL: URL { root.appendingPathComponent("runtime.json") }
    private static let splitReadyKey = "test-split-ready"
    private static let wakeReleasePrefix = "limit-wake-release-"
    static var scheduled: [(UUID, Date)] = []
    private static func scheduleWake(for id: UUID, at date: Date) { scheduled.append((id, date)) }
    static func seed(_ entries: [UUID: LimitFeatureEntry]) throws {
        try JSONEncoder().encode(entries).write(to: fileURL)
    }
    static func read(_ id: UUID) -> LimitFeatureEntry? { loadAll()[id] }
    static func corrupt() throws { try Data("invalid JSON".utf8).write(to: fileURL) }
    static func raw() throws -> Data { try Data(contentsOf: fileURL) }
'''

checks = r'''
var assertions = 0
func check(_ value: Bool, _ message: String) {
    assertions += 1
    if !value { print("FAIL: \(message)"); exit(1) }
}
func offsetDate(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
try FileManager.default.createDirectory(at: LimitFeatures.root, withIntermediateDirectories: true)
let id = UUID(), otherID = UUID()
var original = LimitFeatureEntry(day: SharedStore.dayKey(for: Date()))
original.wakeReleaseAt = Date().addingTimeInterval(-3600)
original.earlyBlocked = true; original.middleBlocked = true; original.lateBlocked = true
original.earlyFreeCredit = 7; original.middleFreeCredit = 8; original.lateFreeCredit = 9
original.extraRequests = 2; original.extraActiveTier = 1; original.extraReachedTier = 1
original.extraReleaseAt = Date().addingTimeInterval(600)
original.extraLastRequestID = UUID()
try LimitFeatures.seed([id: original, otherID: original])
check(LimitFeatures.prepareNewWakeGates([id]), "new gate cleanup failed")
var expected = original; expected.wakeReleaseAt = nil
let stored = LimitFeatures.read(id)!
let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
check(try encoder.encode(stored) == encoder.encode(expected), "wake reset changed unrelated accounting")
check(try encoder.encode(LimitFeatures.read(otherID)!) == encoder.encode(original), "other group changed")
check(DeviceActivityCenter.stopped == ["limit-wake-release-" + id.uuidString], "unrelated monitors stopped")
try LimitFeatures.corrupt()
let corrupt = try LimitFeatures.raw()
check(!LimitFeatures.prepareNewWakeGates([id]), "failed read counted as success")
check(try LimitFeatures.raw() == corrupt, "corrupt runtime was overwritten")
for minutes in [0, 10, 120, 1440] {
    var state = LatchState()
    let limit = AppLimit(id: id, name: "Wake test", selection: FamilyActivitySelection(), minutesPerDay: 20, wakeDelayMinutes: minutes)
    state.limits = [limit]; SharedStore.state = state
    try LimitFeatures.seed([:]); TimeGuard.date = Date()
    check(LimitFeatures.wakeState(for: limit) == .needsTap, "fresh gate isn't waiting for a tap")
    check(LimitFeatures.wakeUp(limitID: id), "tap rejected")
    let first = LimitFeatures.read(id)!.wakeReleaseAt!
    check(first == TimeGuard.date.addingTimeInterval(Double(minutes * 60)), "wrong persisted wait")
    TimeGuard.date = TimeGuard.date.addingTimeInterval(1)
    check(!LimitFeatures.wakeUp(limitID: id), "repeat tap accepted")
    check(LimitFeatures.read(id)!.wakeReleaseAt == first, "repeat tap shortened wait")
    TimeGuard.date = first
    check(LimitFeatures.wakeState(for: limit) == .awake, "deadline didn't release")
}
// New schedules resolve the local weekday, but keep persisted elapsed waits.
let calendarDay = Calendar.current.component(.weekday, from: Date())
let otherDay = calendarDay % 7 + 1
var timed = AppLimit(id: id, name: "Per-day gate", selection: FamilyActivitySelection(), minutesPerDay: 20, wakeDelayMinutes: 10)
timed.wakeSchedule = LimitWakeSchedule(startMinutes: 0, weekdays: [calendarDay],
    dayTimings: [calendarDay: WakeDayTiming(startMinutes: 0, waitMinutes: 35)])
SharedStore.state.limits = [timed]; try LimitFeatures.seed([:]); TimeGuard.date = Date()
check(LimitFeatures.wakeUp(limitID: id), "per-day tap rejected")
let release = LimitFeatures.read(id)!.wakeReleaseAt!
check(release == TimeGuard.date.addingTimeInterval(35*60), "per-day duration not used")
timed.wakeSchedule!.weekdays = [otherDay]
timed.wakeSchedule!.dayTimings[calendarDay] = WakeDayTiming(startMinutes: 1410, waitMinutes: 0)
SharedStore.state.limits = [timed]
check(LimitFeatures.wakeState(for: timed) == .waiting(release), "schedule edit shortened today's active wait")
check(!LimitFeatures.wakeUp(limitID: id), "edited schedule permitted a second tap")
check(LimitFeatures.read(id)!.wakeReleaseAt == release, "edited schedule reset countdown")
TimeGuard.date = release
check(LimitFeatures.wakeState(for: timed) == .awake, "original deadline did not finish")
try LimitFeatures.seed([:]); TimeGuard.date = Date()
check(LimitFeatures.wakeState(for: timed) == .notConfigured, "skipped weekday still blocks")
check(!LimitFeatures.wakeUp(limitID: id), "skipped weekday accepted tap")
var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
c.hour = 8; c.minute = 29
let before = Calendar.current.date(from: c)!
timed.wakeSchedule = LimitWakeSchedule(startMinutes: 8*60+30)
check(LimitFeatures.wakeState(for: timed, at: before, guardedNow: before) == .notConfigured, "gate starts early")
check(LimitFeatures.wakeState(for: timed, at: before.addingTimeInterval(60), guardedNow: before.addingTimeInterval(60)) == .needsTap,
      "minute-granular gate misses start")
var yesterday = LimitFeatureEntry(day: SharedStore.dayKey(for: before.addingTimeInterval(-86400)))
yesterday.wakeReleaseAt = before.addingTimeInterval(7200)
try LimitFeatures.seed([id: yesterday])
check(LimitFeatures.wakeState(for: timed, at: before.addingTimeInterval(60), guardedNow: before) == .needsTap,
      "yesterday's tap leaked into new day")
let limit = AppLimit(id: id, name: "Corrupt gate", selection: FamilyActivitySelection(), minutesPerDay: 20, wakeDelayMinutes: 10)
// A wall-clock ceiling never mutates the runtime's usage/extra-time accounting.
timed.wakeSchedule = LimitWakeSchedule(startMinutes: 0, latestMinutes: 720)
c.hour = 12; c.minute = 0
let noon = Calendar.current.date(from: c)!
try LimitFeatures.seed([:])
check(LimitFeatures.wakeState(for: timed, at: noon.addingTimeInterval(-1), guardedNow: noon) == .needsTap, "legacy ceiling released early")
check(LimitFeatures.wakeState(for: timed, at: noon, guardedNow: noon) == .awake, "legacy untapped ceiling didn't release")
var ongoing = original; ongoing.day = SharedStore.dayKey(for: noon); ongoing.wakeReleaseAt = noon.addingTimeInterval(7200)
try LimitFeatures.seed([id: ongoing]); let runtimeBefore = try LimitFeatures.raw()
check(LimitFeatures.wakeState(for: timed, at: noon, guardedNow: noon) == .awake, "legacy running wait ignored cutoff")
check(try LimitFeatures.raw() == runtimeBefore, "cutoff changed usage accounting")
timed.wakeSchedule!.dayTimings[calendarDay] = WakeDayTiming(startMinutes: 0, waitMinutes: 10, latestMinutes: 780)
check(LimitFeatures.wakeState(for: timed, at: noon, guardedNow: noon) == .waiting(ongoing.wakeReleaseAt!), "weekday legacy cutoff ignored")
check(!timed.wakeSchedule!.noLooser(than: LimitWakeSchedule(), wait: 10, oldWait: 10), "legacy cutoff addition not classified looser")
SharedStore.state.limits = [limit]
try LimitFeatures.corrupt()
check(!LimitFeatures.wakeUp(limitID: id), "tap on unreadable runtime reported success")

// Actual limit and global status bodies: no replacement ceiling/status logic.
let dstAssertionsBefore = assertions
check(TimeZone.current.identifier == "America/New_York", "DST fixture timezone not configured")
let globalDayKey = "latch.globalWake.day.v1", globalReleaseKey = "latch.globalWake.release.v1"
for (name, cap, beforeText, capText, laterText, releaseText) in [
    ("fall-back", 90, "2026-11-01T01:29:59-04:00", "2026-11-01T01:30:00-04:00",
     "2026-11-01T01:15:00-05:00", "2026-11-01T04:00:00-05:00"),
    ("spring-forward", 150, "2026-03-08T01:59:59-05:00", "2026-03-08T03:00:00-04:00",
     "2026-03-08T03:15:00-04:00", "2026-03-08T06:00:00-04:00")
] {
    let before = offsetDate(beforeText), ceiling = offsetDate(capText)
    let later = offsetDate(laterText), release = offsetDate(releaseText)
    check(later > ceiling, "\(name): chronological fixture order wrong")
    if name == "fall-back" {
        check(Calendar.current.component(.hour, from: later) == 1
            && Calendar.current.component(.minute, from: later) == 15, "second 01:15 fixture wrong")
    } else {
        check(ceiling.timeIntervalSince(before) == 1, "spring fixture did not skip 02 hour")
    }
    var capped = limit
    capped.wakeSchedule = LimitWakeSchedule(startMinutes: 0, latestMinutes: cap)
    var global = LatchState()
    global.wakeRule.enabled = true; global.wakeRule.startHour = 0
    global.wakeRule.waitMinutes = 240; global.wakeRule.latestMinutes = cap
    for running in [false, true] {
        var fixture = original; fixture.day = SharedStore.dayKey(for: before)
        fixture.wakeReleaseAt = running ? release : nil
        try LimitFeatures.seed([id: fixture, otherID: fixture])
        let bytesBefore = try LimitFeatures.raw()
        SharedStore.defaults.removeObject(forKey: globalDayKey)
        SharedStore.defaults.removeObject(forKey: globalReleaseKey)
        if running {
            SharedStore.defaults.set(SharedStore.dayKey(for: before), forKey: globalDayKey)
            SharedStore.defaults.set(release, forKey: globalReleaseKey)
        }
        let preferencesBefore = SharedStore.defaults.persistentDomain(forName: SharedStore.suite)! as NSDictionary
        TimeGuard.date = before
        check(LimitFeatures.wakeState(for: capped, at: before, guardedNow: before)
            == (running ? .waiting(release) : .needsTap), "\(name): limit pre-cap wrong")
        check(GlobalWake.status(state: global, at: before)
            == (running ? .waiting(release) : .needsTap), "\(name): global pre-cap wrong")
        for moment in [ceiling, later] {
            TimeGuard.date = moment
            check(LimitFeatures.wakeState(for: capped, at: moment, guardedNow: moment) == .awake,
                  "\(name): limit missed cap or reblocked (running=\(running))")
            check(GlobalWake.status(state: global, at: moment) == .awake,
                  "\(name): global missed cap or reblocked (running=\(running))")
            check(try LimitFeatures.raw() == bytesBefore, "\(name): cutoff mutated limit deadline/accounting")
            check(SharedStore.defaults.persistentDomain(forName: SharedStore.suite)! as NSDictionary
                == preferencesBefore, "\(name): cutoff mutated global preferences/deadline")
        }
    }
}
print("DST regression runtime: \(assertions - dstAssertionsBefore) assertions passed (limits and global; untapped and running)")

let globalAssertionsBefore = assertions
let wall = offsetDate("2026-10-05T12:00:00-04:00")
let globalRelease = wall.addingTimeInterval(4 * 3600)
TimeGuard.date = wall
var base = LatchState()
base.wakeRule.enabled = true; base.wakeRule.startHour = 0; base.wakeRule.waitMinutes = 240
SharedStore.defaults.set(SharedStore.dayKey(for: wall), forKey: globalDayKey)
SharedStore.defaults.set(globalRelease, forKey: globalReleaseKey)
let globalBefore = SharedStore.defaults.persistentDomain(forName: SharedStore.suite)! as NSDictionary
check(GlobalWake.status(state: base, at: wall) == .waiting(globalRelease), "global persisted wait fixture wrong")
for edit in ["cap-only", "start", "weekday", "wait", "combined"] {
    var edited = base
    switch edit {
    case "cap-only": edited.wakeRule.latestMinutes = 13 * 60
    case "start": edited.wakeRule.startHour = 18
    case "weekday": edited.wakeRule.weekdays = [3] // wall is Monday (2)
    case "wait": edited.wakeRule.waitMinutes = 0
    default:
        edited.wakeRule.startHour = 18; edited.wakeRule.weekdays = [3]
        edited.wakeRule.waitMinutes = 0; edited.wakeRule.latestMinutes = 20 * 60
    }
    TimeGuard.date = wall
    check(GlobalWake.status(state: edited, at: wall) == .waiting(globalRelease),
          "global \(edit) edit discarded/recalculated same-day wait")
    check(SharedStore.defaults.object(forKey: globalReleaseKey) as? Date == globalRelease,
          "global \(edit) edit mutated stored deadline")
    check(SharedStore.defaults.persistentDomain(forName: SharedStore.suite)! as NSDictionary == globalBefore,
          "global \(edit) status wrote preferences")
    TimeGuard.date = globalRelease
    check(GlobalWake.status(state: edited, at: wall) == .awake,
          "global \(edit) edit missed preserved guarded deadline")
}
var capEdit = base; capEdit.wakeRule.latestMinutes = 13 * 60
let capWall = wall.addingTimeInterval(3600)
TimeGuard.date = capWall
check(GlobalWake.status(state: capEdit, at: capWall) == .awake, "global cap-only edit did not release at cap")
check(SharedStore.defaults.object(forKey: globalReleaseKey) as? Date == globalRelease,
      "cap-only release rewrote original global deadline")
capEdit.wakeRule.latestMinutes = nil
check(GlobalWake.status(state: capEdit, at: capWall) == .waiting(globalRelease),
      "removing cap lost original global running wait")
var disabled = base; disabled.wakeRule.enabled = false
check(GlobalWake.status(state: disabled, at: wall) == .inactive, "disabled global gate still blocks")
check(SharedStore.defaults.persistentDomain(forName: SharedStore.suite)! as NSDictionary == globalBefore,
      "status-only edits mutated persisted global runtime")
SharedStore.defaults.set(SharedStore.dayKey(for: wall.addingTimeInterval(-86400)), forKey: globalDayKey)
var untapped = base; untapped.wakeRule.startHour = 18
TimeGuard.date = wall
check(GlobalWake.status(state: untapped, at: wall) == .inactive, "yesterday's deadline bypassed start eligibility")
untapped.wakeRule.startHour = 0; untapped.wakeRule.weekdays = [3]
check(GlobalWake.status(state: untapped, at: wall) == .inactive, "yesterday's deadline bypassed weekday eligibility")
print("Global same-day edit runtime: \(assertions - globalAssertionsBefore) assertions passed (cap/start/weekday/wait/combined; original persisted deadline unchanged)")
try FileManager.default.removeItem(at: LimitFeatures.root)
SharedStore.defaults.removePersistentDomain(forName: SharedStore.suite)
print("Wake runtime checks passed: \(assertions) assertions, 0 failures; accounting, corrupt reads, 4 waits, repeated taps, weekday overrides, DST caps, active deadline edits and rollover")
'''

source = "\n".join([infrastructure, models, phrases, budget, types,
                    global_wake, driver, logic, "}", checks])
with tempfile.TemporaryDirectory(prefix="demora-wake-runtime-tests-") as directory:
    source_path = Path(directory) / "main.swift"
    binary_path = Path(directory) / "checks"
    source_path.write_text(source)
    subprocess.run(["xcrun", "swiftc", str(source_path), "-o", str(binary_path)], check=True)
    subprocess.run([str(binary_path)], check=True,
                   env={**os.environ, "TZ": "America/New_York"})
print("setWakeRule clearTap: narrow source assertion passed; full ChangeEngine.apply not runtime-executed")
