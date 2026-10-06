#!/usr/bin/env python3
"""Run real wake runtime reads/writes against a temporary file on macOS.

Opaque Apple tokens and monitor/shield effects are stubbed. File coordination,
JSON decoding, readback verification and the production wake methods are real.
This does not test iOS protected-file or DeviceActivity delivery behavior.
"""
from pathlib import Path
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
struct DeviceActivityCenter {
    static var stopped: [String] = []
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
func check(_ value: Bool, _ message: String) {
    if !value { print("FAIL: \(message)"); exit(1) }
}
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
SharedStore.state.limits = [limit]
try LimitFeatures.corrupt()
check(!LimitFeatures.wakeUp(limitID: id), "tap on unreadable runtime reported success")
try FileManager.default.removeItem(at: LimitFeatures.root)
SharedStore.defaults.removePersistentDomain(forName: SharedStore.suite)
print("Wake runtime checks passed: accounting, corrupt reads, 4 waits, repeated taps, weekday overrides, minute start, skipped day, active deadline edits and rollover")
'''

source = infrastructure + models + phrases + budget + types + driver + logic + "\n}\n" + checks
with tempfile.TemporaryDirectory(prefix="demora-wake-runtime-tests-") as directory:
    source_path = Path(directory) / "main.swift"
    binary_path = Path(directory) / "checks"
    source_path.write_text(source)
    subprocess.run(["xcrun", "swiftc", str(source_path), "-o", str(binary_path)], check=True)
    subprocess.run([str(binary_path)], check=True)
