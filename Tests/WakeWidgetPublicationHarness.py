#!/usr/bin/env python3
"""Compile the actual host snapshot publisher and WakeWidgetProjection.

Only this test is owned here. Codable rule shapes and owning wake APIs below
are thin fixtures, NOT production enforcement. WakeWidgetReadOnlyHarness.py
separately tests actual owning readers/taps. No live defaults/App Group access,
WidgetKit service, network, installation, or Xcode build occurs. The coordinator
is a deterministic single-process adapter: interleavings are NOT lock/IPC proof.
"""

import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def replace_once(source, old, new):
    assert source.count(old) == 1, f"fixture boundary drifted: {old!r}"
    return source.replace(old, new)


def isolated_source():
    source = (ROOT / "Shared/DemoraWidgetSnapshot.swift").read_text()
    # Keep ALL publisher/projection/presentation bodies. Replace infrastructure
    # only, including load(): it must never open either real App Group suite.
    source = replace_once(source, "import WidgetKit", "// WidgetCenter is a recording fixture below.")
    source = replace_once(source, "UserDefaults(suiteName: groupID)?.data(forKey: key)",
                          "SharedStore.defaults.data(forKey: key)")
    source, count = re.subn(
        r"FileManager\.default\.containerURL\(\s*forSecurityApplicationGroupIdentifier: groupID\)",
        "FixtureContainer.url(for: groupID)", source)
    assert count == 1, "container boundary drifted"
    source = replace_once(source, "NSFileCoordinator()", "FixtureCoordinator()")
    source = replace_once(source, "let now = Date()", "let now = FixtureClock.now")
    assert "UserDefaults(" not in source and "containerURL(" not in source
    assert "import WidgetKit" not in source and "URLSession" not in source
    assert "static func publish(state _: LatchState)" in source
    assert "enum WakeWidgetProjection" in source
    return source


FIXTURES = r'''
import Foundation

// Synchronous, single-process fixtures, deliberately not Swift 6 concurrency
// or real NSFileCoordinator implementations.
enum FixtureClock {
    static var now = ISO8601DateFormatter().date(from: "2026-10-05T10:00:00-04:00")!
    static var guardedOffset: TimeInterval = 0
}
final class FixtureDefaults {
    var values: [String: Data] = [:]
    var writes: [String] = []
    var rejectWrite = false
    var stateReads = 0
    func data(forKey key: String) -> Data? {
        if key == LatchConstants.stateKey {
            precondition(FixtureCoordinator.held, "publisher read saved rules outside coordination")
            stateReads += 1
        }
        return values[key]
    }
    func set(_ value: Data, forKey key: String) {
        precondition(FixtureCoordinator.held, "publication write outside coordination")
        writes.append(key)
        if !rejectWrite { values[key] = value }
    }
}
enum LatchConstants { static let stateKey = "fixture.saved.rules" }
enum SharedStore {
    static let defaults = FixtureDefaults()
    static var flagWrites = 0
    static var simulating = false { didSet { flagWrites += 1 } }
    static var stateRecoveryNeeded = false { didSet { flagWrites += 1 } }
    static var enforcementDegraded = false { didSet { flagWrites += 1 } }
    static var blocked: Set<UUID> = []
    static func loadBlockedLimitIDs() -> Set<UUID> { blocked }
}
enum FixtureContainer {
    static let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    static var available = true
    static var groups: [String] = []
    static func url(for group: String) -> URL? {
        groups.append(group)
        return available ? root : nil
    }
}
final class FixtureCoordinator {
    struct Options: OptionSet {
        let rawValue: Int
        static let forMerging = Options(rawValue: 1)
    }
    static var held = false
    static var fail = false
    static var calls = 0
    static var beforeAccessor: (() -> Void)?
    func coordinate(writingItemAt url: URL, options: Options,
                    error: inout NSError?, byAccessor body: (URL) -> Void) {
        precondition(url == FixtureContainer.root.appendingPathComponent("widgetProjection.lock"))
        precondition(options == .forMerging && !Self.held)
        Self.calls += 1
        if Self.fail { error = NSError(domain: "fixture.lock", code: 1); return }
        let hook = Self.beforeAccessor; Self.beforeAccessor = nil
        hook?() // Model a writer that wins before this accessor acquires its lock.
        Self.held = true
        defer { Self.held = false }
        body(url)
    }
}
final class WidgetCenter {
    static let shared = WidgetCenter()
    var reloads = 0
    func reloadAllTimelines() {
        precondition(!FixtureCoordinator.held, "WidgetKit reload inside coordination")
        reloads += 1
    }
}
func tr(_ text: String) -> String { text }

// Minimal Codable shapes needed by the actual publisher. This is NOT the
// production LatchState schema or its migration/validation implementation.
struct Recurrence: Codable {
    var weekdays: [Int] = Array(1...7)
    func matches(dayOf day: Date) -> Bool { weekdays.contains(Calendar.current.component(.weekday, from: day)) }
}
struct TimedRule: Codable {
    var name = "Schedule"
    var startMinutes = 480
    var endMinutes = 600
    var recurrence = Recurrence()
}
enum RuleKind: String, Codable { case block, free }
struct PlannedRule: Codable {
    var name = "Planned"
    var startsAt: Date
    var endsAt: Date
    var kind = RuleKind.block
}
struct SessionRule: Codable {
    var name = "Session"
    var startedAt: Date
    var endsAt: Date
    var kind = RuleKind.block
}
enum Direction: String, Codable { case stricter, lessStrict }
struct PendingRule: Codable {
    var summary = "Change"
    var appliesAt: Date
    var direction = Direction.lessStrict
}
struct Timing: Codable {
    var startMinutes = 0
    var latestMinutes: Int? = nil
}
struct WakeRule: Codable {
    var enabled = false
    var startHour = 0
    var latestMinutes: Int? = nil
    func latest(on _: Date) -> Int? { latestMinutes }
}
struct DayNightGroup: Codable {
    var id = UUID()
    var wakeEnabled = true
    var timing = Timing()
    func wakeTiming(on _: Date) -> Timing { timing }
}
struct LimitWakeSchedule: Codable {
    var value = Timing()
    func timing(on _: Date, defaultWait _: Int) -> Timing { value }
}
struct AppLimit: Codable {
    var id = UUID()
    var name = "Limit"
    var budget = 30
    var wakeDelayMinutes: Int? = nil
    var wakeSchedule: LimitWakeSchedule? = nil
    func minutes(on _: Date) -> Int { budget }
}
struct LatchState: Codable {
    var isSetUp = true
    var wakeRule = WakeRule()
    var dayNightGroups: [DayNightGroup] = []
    var limits: [AppLimit] = []
    var schedules: [TimedRule] = []
    var exemptions: [TimedRule] = []
    var planned: [PlannedRule] = []
    var sessions: [SessionRule] = []
    var pending: [PendingRule] = []
}
enum GlobalWakeStatus: Equatable { case inactive, needsTap, waiting(Date), awake }
enum WakeState { case notConfigured, needsTap, waiting(Date), awake }
enum FixtureReaders {
    struct Call { var key: String; var at: Date; var guarded: Date }
    static var answers: [String: (Date, Date) -> GlobalWakeStatus?] = [:]
    static var calls: [Call] = []
    static var duringRead: (() -> Void)?
    static func read(_ key: String, at: Date, guarded: Date) -> GlobalWakeStatus? {
        calls.append(Call(key: key, at: at, guarded: guarded))
        let hook = duringRead; duringRead = nil; hook?()
        return answers[key]?(at, guarded) ?? (answers[key] == nil ? .needsTap : nil)
    }
}
enum TimeGuard {
    static func nowForDisplay(at date: Date) -> Date {
        date.addingTimeInterval(FixtureClock.guardedOffset)
    }
}
enum GlobalWake {
    static func statusForDisplay(state _: LatchState, at: Date, guardedNow: Date) -> GlobalWakeStatus? {
        FixtureReaders.read("global", at: at, guarded: guardedNow)
    }
}
enum DayNightWake {
    static func statusForDisplay(group: DayNightGroup, at: Date, guardedNow: Date) -> GlobalWakeStatus? {
        FixtureReaders.read(group.id.uuidString, at: at, guarded: guardedNow)
    }
}
enum LimitFeatures {
    static func wakeStateForDisplay(for limit: AppLimit, at: Date, guardedNow: Date) -> WakeState? {
        switch FixtureReaders.read(limit.id.uuidString, at: at, guarded: guardedNow) {
        case .needsTap: return .needsTap
        case .waiting(let release): return .waiting(release)
        case .awake: return .awake
        case .inactive: return .notConfigured
        case nil: return nil
        }
    }
}
'''


CHECKS = r'''
var assertions = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    precondition(condition(), "FAIL: " + message)
}
func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
let monday = date("2026-10-05T10:00:00-04:00")
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "America/New_York")!
func reset(_ now: Date = monday) {
    FixtureClock.now = now; FixtureClock.guardedOffset = 0
    SharedStore.defaults.values = ["fixture.setup.marker": Data([1]), "fixture.runtime.deadline": Data([2, 3])]
    SharedStore.defaults.writes = []; SharedStore.defaults.rejectWrite = false
    SharedStore.defaults.stateReads = 0
    SharedStore.simulating = false; SharedStore.stateRecoveryNeeded = false
    SharedStore.enforcementDegraded = false; SharedStore.flagWrites = 0
    SharedStore.blocked = []; FixtureReaders.answers = [:]; FixtureReaders.calls = []
    FixtureReaders.duringRead = nil
    FixtureCoordinator.calls = 0; FixtureCoordinator.fail = false
    FixtureCoordinator.beforeAccessor = nil; FixtureContainer.available = true
    FixtureContainer.groups = []; WidgetCenter.shared.reloads = 0
}
func encoded<T: Encodable>(_ value: T) -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return try! encoder.encode(value)
}
func seed(_ state: LatchState) { SharedStore.defaults.values[LatchConstants.stateKey] = encoded(state) }
func snapshot() -> DemoraWidgetSnapshot { DemoraWidgetSnapshot.load()! }
func withoutWake(_ value: DemoraWidgetSnapshot) -> Data {
    var result = value; result.wakeDue = nil; return encoded(result)
}
func basic() -> LatchState {
    var state = LatchState(); state.wakeRule.enabled = true; state.wakeRule.startHour = 8
    state.planned = [PlannedRule(name: "Fresh persisted rule", startsAt: monday.addingTimeInterval(-60),
                                 endsAt: monday.addingTimeInterval(3600))]
    state.pending = [PendingRule(appliesAt: monday.addingTimeInterval(7200))]
    return state
}
// Every display publication is checked for writes to ANY unowned preference
// key, including saved rules, setup/runtime markers, and all flag setters.
func publish(_ label: String, _ action: () -> Void = { DemoraWidgetSnapshot.refresh() }) {
    let prefs = SharedStore.defaults.values.filter { $0.key != DemoraWidgetSnapshot.key }
    let flags = SharedStore.flagWrites
    let prior = SharedStore.defaults.writes.count
    action()
    check(prefs == SharedStore.defaults.values.filter { $0.key != DemoraWidgetSnapshot.key }, label + ": unowned bytes changed")
    check(SharedStore.defaults.writes.dropFirst(prior).allSatisfy { $0 == DemoraWidgetSnapshot.key }, label + ": unowned write attempted")
    check(flags == SharedStore.flagWrites, label + ": flag write attempted")
    check(!FixtureCoordinator.held, label + ": lock leaked")
}
func project(_ state: LatchState, at now: Date = monday) -> [DemoraWidgetSnapshot.WakeWindow]? {
    let prefs = SharedStore.defaults.values, writes = SharedStore.defaults.writes
    let flags = SharedStore.flagWrites, locks = FixtureCoordinator.calls, reloads = WidgetCenter.shared.reloads
    let result = WakeWidgetProjection.windows(state: state, at: now, calendar: cal)
    check(prefs == SharedStore.defaults.values && writes == SharedStore.defaults.writes, "projection wrote preferences")
    check(flags == SharedStore.flagWrites, "projection wrote flags")
    check(locks == FixtureCoordinator.calls && reloads == WidgetCenter.shared.reloads, "projection coordinated/reloaded")
    return result
}

// Caller cache must never win over fresh raw persisted state.
reset(); seed(basic())
var stale = basic(); stale.wakeRule.enabled = false; stale.planned[0].name = "STALE CACHE"
publish("stale caller") { DemoraWidgetSnapshot.publish(state: stale) }
check(snapshot().windows.first?.title == "Fresh persisted rule", "cached caller published")
check(snapshot().wakeDue?.count == 1, "fresh persisted wake ignored")
check(WidgetCenter.shared.reloads == 1 && SharedStore.defaults.stateReads >= 2, "publication not verified/reloaded")
let firstBytes = SharedStore.defaults.values[DemoraWidgetSnapshot.key]
FixtureClock.now = monday.addingTimeInterval(1)
publish("identical display ignores savedAt")
check(SharedStore.defaults.values[DemoraWidgetSnapshot.key] == firstBytes, "identical projection rewrote savedAt")
check(SharedStore.defaults.writes.count == 1 && WidgetCenter.shared.reloads == 1, "identical display failed dedup")
#if DEBUG
check(FixtureContainer.groups.allSatisfy { $0 == "group.com.may.screentimedelay.dev" }, "wrong Debug group argument")
#else
check(FixtureContainer.groups.allSatisfy { $0 == "group.com.may.screentimedelay" }, "wrong Release group argument")
#endif

// Deterministic accessor scheduling: a newer writer wins before this accessor.
reset(); seed(stale)
FixtureCoordinator.beforeAccessor = { seed(basic()) }
// The fixture's intentional rule save is outside the publish() mutation check.
DemoraWidgetSnapshot.publish(state: stale)
check(snapshot().windows.first?.title == "Fresh persisted rule", "state read before lock acquisition")
check(snapshot().wakeDue != nil && WidgetCenter.shared.reloads == 1, "latest accessor state not projected")

// Raw-byte compare, not semantic Codable equality. Change JSON whitespace
// during an owning reader, between initial read and final pre-write recheck.
for replacement in [encoded(stale), encoded(basic()) + Data(" \n".utf8)] {
    reset(); seed(basic())
    let oldRules = SharedStore.defaults.values[LatchConstants.stateKey]
    FixtureReaders.duringRead = { SharedStore.defaults.values[LatchConstants.stateKey] = replacement }
    DemoraWidgetSnapshot.refresh()
    check(oldRules != replacement, "race fixture did not change bytes")
    check(SharedStore.defaults.values[LatchConstants.stateKey] == replacement, "publisher overwrote racing rules")
    check(SharedStore.defaults.writes.isEmpty && WidgetCenter.shared.reloads == 0, "stale projection landed after raw-byte race")
    publish("winning writer follow-up")
    check(SharedStore.defaults.writes.count == 1 && WidgetCenter.shared.reloads == 1, "follow-up did not converge")
}
reset(); seed(basic()); publish("retained snapshot race seed")
let retainedBytes = SharedStore.defaults.values[DemoraWidgetSnapshot.key]
var intermediate = basic(); intermediate.planned[0].name = "Must not land"
seed(intermediate)
let winningBytes = encoded(stale)
FixtureReaders.duringRead = { SharedStore.defaults.values[LatchConstants.stateKey] = winningBytes }
DemoraWidgetSnapshot.refresh()
check(SharedStore.defaults.values[DemoraWidgetSnapshot.key] == retainedBytes, "racing stale projection replaced retained display")
check(SharedStore.defaults.values[LatchConstants.stateKey] == winningBytes, "racing save lost")
check(SharedStore.defaults.writes == [DemoraWidgetSnapshot.key] && WidgetCenter.shared.reloads == 1, "racing projection wrote/reloaded retained snapshot")
reset(); seed(basic())
FixtureReaders.duringRead = { SharedStore.stateRecoveryNeeded = true }
DemoraWidgetSnapshot.refresh()
check(SharedStore.defaults.writes.isEmpty && WidgetCenter.shared.reloads == 0, "recovery changed mid-read but published")
check(SharedStore.flagWrites == 1, "publisher added flag writes to injected recovery")

for reason in ["lock failure", "simulation", "no container", "simulation after acquisition"] {
    reset(); seed(basic())
    if reason == "lock failure" { FixtureCoordinator.fail = true }
    if reason == "simulation" { SharedStore.simulating = true }
    if reason == "no container" { FixtureContainer.available = false }
    if reason == "simulation after acquisition" {
        FixtureCoordinator.beforeAccessor = { SharedStore.simulating = true }
        DemoraWidgetSnapshot.refresh()
    } else { publish(reason) }
    check(SharedStore.defaults.writes.isEmpty && WidgetCenter.shared.reloads == 0, reason + ": published")
    check(SharedStore.defaults.stateReads == 0, reason + ": read rules despite guard")
}
reset(); seed(basic()); SharedStore.defaults.rejectWrite = true
publish("failed widget write")
check(DemoraWidgetSnapshot.load() == nil && WidgetCenter.shared.reloads == 0, "failed write reloaded")

// Missing/corrupt/not-set-up/recovery state may clear only an old wake claim.
// No synthesized setup, rule windows, pending changes, copy or timestamp.
for invalid in ["missing", "corrupt", "wrong shape", "not set up", "recovery"] {
    for prior in ["absent", "corrupt", "no wake", "wake"] {
        reset(); seed(basic()); publish("seed old display")
        let original = snapshot()
        switch prior {
        case "absent": SharedStore.defaults.values.removeValue(forKey: DemoraWidgetSnapshot.key)
        case "corrupt": SharedStore.defaults.values[DemoraWidgetSnapshot.key] = Data("bad snapshot".utf8)
        case "no wake": var value = original; value.wakeDue = nil
            SharedStore.defaults.values[DemoraWidgetSnapshot.key] = encoded(value)
        default: break
        }
        switch invalid {
        case "missing": SharedStore.defaults.values.removeValue(forKey: LatchConstants.stateKey)
        case "corrupt": SharedStore.defaults.values[LatchConstants.stateKey] = Data("not JSON".utf8)
        case "wrong shape": SharedStore.defaults.values[LatchConstants.stateKey] = Data("{}".utf8)
        case "not set up": var value = basic(); value.isSetUp = false; seed(value)
        default: SharedStore.stateRecoveryNeeded = true
        }
        let previous = SharedStore.defaults.values[DemoraWidgetSnapshot.key]
        let writes = SharedStore.defaults.writes.count, reloads = WidgetCenter.shared.reloads
        publish(invalid + "/" + prior)
        if prior == "wake" {
            check(snapshot().wakeDue == nil, "invalid rules retained positive wake claim")
            check(withoutWake(snapshot()) == withoutWake(original), "recovery altered non-wake fields")
            check(SharedStore.defaults.writes.count == writes + 1 && WidgetCenter.shared.reloads == reloads + 1, "wake clear not reloaded")
        } else {
            check(SharedStore.defaults.values[DemoraWidgetSnapshot.key] == previous, "invented/replaced snapshot on invalid state")
            check(SharedStore.defaults.writes.count == writes && WidgetCenter.shared.reloads == reloads, "invalid state wrote/reloaded without wake")
        }
        let count = SharedStore.defaults.writes.count
        publish("repeated invalid state")
        check(SharedStore.defaults.writes.count == count, "repeated invalid-state clear rewrote")
    }
}

// Actual projection dispatch/mapping for ALL three owning APIs. Responses are
// explicit API fixtures, not an invented enforcement implementation.
for owner in ["global", "named", "limit"] {
    for status: GlobalWakeStatus? in [.needsTap, .waiting(monday.addingTimeInterval(600)), .awake, .inactive, nil] {
        reset()
        var state = LatchState(), key = "global"
        if owner == "global" { state.wakeRule.enabled = true; state.wakeRule.startHour = 8 }
        if owner == "named" {
            let group = DayNightGroup(timing: Timing(startMinutes: 510))
            state.dayNightGroups = [group]; key = group.id.uuidString
        }
        if owner == "limit" {
            let limit = AppLimit(wakeDelayMinutes: 10,
                                 wakeSchedule: LimitWakeSchedule(value: Timing(startMinutes: 510)))
            state.limits = [limit]; key = limit.id.uuidString
        }
        FixtureReaders.answers[key] = { _, _ in status }
        FixtureClock.guardedOffset = -500
        let windows = project(state)
        check((windows != nil) == (status == .needsTap), owner + ": status mapping wrong")
        check(FixtureReaders.calls.count == 1 && FixtureReaders.calls[0].key == key, owner + ": wrong reader")
        check(FixtureReaders.calls[0].at == monday && FixtureReaders.calls[0].guarded == monday.addingTimeInterval(-500), "clock domain not forwarded")
        seed(state); publish(owner + " status")
        check(snapshot().wakeDue == windows, owner + ": host and direct projection differ")
    }
}

// Multiple disjoint/overlapping intervals, exact dedup and ceiling boundaries.
reset()
var multi = LatchState()
multi.wakeRule = WakeRule(enabled: true, startHour: 8, latestMinutes: 9 * 60)
let group = DayNightGroup(timing: Timing(startMinutes: 11 * 60 + 15, latestMinutes: 12 * 60))
multi.dayNightGroups = [group, DayNightGroup(timing: group.timing),
                       DayNightGroup(timing: Timing(startMinutes: 11 * 60 + 15, latestMinutes: 13 * 60))]
multi.limits = [AppLimit(wakeDelayMinutes: 0, wakeSchedule: LimitWakeSchedule(value: Timing(startMinutes: 15 * 60)))]
let morning = date("2026-10-05T07:00:00-04:00")
let windows = project(multi, at: morning)!
check(windows.count == 4, "intervals merged or exact duplicates retained")
check(windows.map(\.startsAt) == [date("2026-10-05T08:00:00-04:00"), date("2026-10-05T11:15:00-04:00"),
                                 date("2026-10-05T11:15:00-04:00"), date("2026-10-05T15:00:00-04:00")], "future TODAY starts/sort wrong")
check(windows[1].endsAt < windows[2].endsAt, "same-start ceiling sort wrong")
check(windows.last?.endsAt == date("2026-10-06T00:00:00-04:00"), "forecast beyond today's midnight")
check(FixtureReaders.calls.map(\.at) == [windows[0].startsAt, windows[1].startsAt, windows[1].startsAt,
                                       windows[2].startsAt, windows[3].startsAt], "future candidate not passed to reader")
for status: GlobalWakeStatus? in [.waiting(monday.addingTimeInterval(600)), .awake, .inactive, nil] {
    var future = LatchState(); future.dayNightGroups = [group]
    FixtureReaders.answers[group.id.uuidString] = { _, _ in status }
    check(project(future, at: morning) == nil, "future start invented untapped status over owning reader")
    check(FixtureReaders.calls.last?.at == date("2026-10-05T11:15:00-04:00"), "future status candidate not concrete TODAY start")
}
FixtureReaders.answers = [:]
FixtureClock.now = morning; seed(multi); publish("multiple windows")
for (clock, expected) in [("07:59:59", false), ("08:00:00", true), ("09:00:00", false),
                          ("11:14:59", false), ("11:15:00", true), ("12:59:59", true),
                          ("13:00:00", false), ("15:00:00", true), ("23:59:59", true)] {
    let at = date("2026-10-05T" + clock + "-04:00")
    check((WidgetPresentation.current(snapshot: snapshot(), at: at) == .wake) == expected, "gap/boundary " + clock)
}
check(WidgetPresentation.current(snapshot: snapshot(), at: date("2026-10-06T00:00:00-04:00")) != .wake, "wake leaked into tomorrow")
let transitions = snapshot().transitionDates(after: morning, through: date("2026-10-06T01:00:00-04:00"))
check(transitions == Array(Set(windows.flatMap { [$0.startsAt, $0.endsAt] })).sorted(), "wake transition dates not deduped")
check(project(multi, at: date("2026-10-05T13:00:00-04:00"))?.count == 1, "expired ceiling windows retained")

// Invalid starts/ceilings and disabled gates never manufacture a window.
for timing in [Timing(startMinutes: -1), Timing(startMinutes: 1440), Timing(startMinutes: 800, latestMinutes: 700),
               Timing(startMinutes: 480, latestMinutes: -1), Timing(startMinutes: 480, latestMinutes: 1440)] {
    var state = LatchState(); state.dayNightGroups = [DayNightGroup(timing: timing)]
    check(project(state) == nil, "invalid/expired clock timing made wake window")
}
var disabled = LatchState()
disabled.dayNightGroups = [DayNightGroup(wakeEnabled: false)]
disabled.limits = [AppLimit()]
check(project(disabled) == nil, "disabled/unconfigured gate published")

// Unknown owning metadata suppresses the whole positive claim. An unrelated
// monitor-health flag does NOT assert awake or erase valid owning-reader data.
reset(); seed(basic()); publish("healthy")
FixtureReaders.answers["global"] = { _, _ in nil }
publish("unknown owning runtime")
check(snapshot().wakeDue == nil, "unknown runtime retained wake claim")
FixtureReaders.answers = [:]; SharedStore.enforcementDegraded = true
publish("unrelated degraded monitor")
check(snapshot().wakeDue != nil && SharedStore.enforcementDegraded, "unrelated degraded flag erased valid needsTap")
var mixed = basic(); mixed.dayNightGroups = [group]
FixtureReaders.answers[group.id.uuidString] = { _, _ in nil }
check(project(mixed) == nil, "known gate hid unknown sibling")

// Calendar arithmetic across 23/25-hour days and repeated/skipped local starts.
for (dayText, endText, hours) in [
    ("2026-03-08T00:00:00-05:00", "2026-03-09T00:00:00-04:00", 23.0),
    ("2026-11-01T00:00:00-04:00", "2026-11-02T00:00:00-05:00", 25.0)
] {
    let day = date(dayText), end = date(endText)
    reset(day)
    var state = LatchState(); state.wakeRule.enabled = true
    let result = project(state, at: day)!
    check(result.count == 1 && result[0].startsAt == day && result[0].endsAt == end, "DST midnight projection wrong")
    check(end.timeIntervalSince(day) == hours * 3600, "DST fixture not transition day")
    FixtureClock.now = day; seed(state); publish("DST publisher")
    check(snapshot().wakeDue == result, "publisher DST differs")
    check(WidgetPresentation.current(snapshot: snapshot(), at: end) != .wake, "DST tomorrow prompt")
}
reset(date("2026-11-01T00:30:00-04:00"))
var repeated = LatchState()
repeated.dayNightGroups = [DayNightGroup(timing: Timing(startMinutes: 90))]
repeated.limits = [AppLimit(wakeDelayMinutes: 10, wakeSchedule: LimitWakeSchedule(value: Timing(startMinutes: 90)))]
for text in ["2026-11-01T00:30:00-04:00", "2026-11-01T01:30:00-04:00",
             "2026-11-01T01:00:00-05:00", "2026-11-01T01:30:00-05:00"] {
    let at = date(text)
    check(project(repeated, at: at) == nil, "ambiguous 01:30 start became continuous over rollback: " + text)
    FixtureClock.now = at; seed(repeated); publish("repeated 01:30")
    check(snapshot().wakeDue == nil, "host retained repeated-hour false prompt")
}
check(FixtureReaders.calls.isEmpty, "ambiguous repeated start was queried as unambiguous")
var capped = LatchState(); capped.wakeRule = WakeRule(enabled: true, latestMinutes: 90)
let capDay = date("2026-11-01T00:00:00-04:00")
check(project(capped, at: capDay)?.first?.endsAt == date("2026-11-01T01:30:00-04:00"), "ceiling used second repeated hour")
check(project(capped, at: date("2026-11-01T01:00:00-05:00")) == nil, "first repeated ceiling revived after rollback")
var spring = LatchState(); spring.wakeRule = WakeRule(enabled: true, startHour: 2)
check(project(spring, at: date("2026-03-08T00:00:00-05:00"))?.first?.startsAt == date("2026-03-08T03:00:00-04:00"), "missing spring hour not advanced by Calendar")

// Free period beats wake, while ending it restores the existing wake claim.
reset(); var free = basic()
free.sessions = [SessionRule(name: "Free", startedAt: monday.addingTimeInterval(-60),
                             endsAt: monday.addingTimeInterval(60), kind: .free)]
seed(free); publish("free wins")
check(snapshot().wakeDue != nil, "free period erased observation instead of presentation precedence")
check(snapshot().active(at: monday)?.style == "free", "free priority wrong")
if case .rule(let rule) = WidgetPresentation.current(snapshot: snapshot(), at: monday) {
    check(rule.style == "free", "wake overrode free")
} else { check(false, "free did not win") }
check(WidgetPresentation.current(snapshot: snapshot(), at: monday.addingTimeInterval(60)) == .wake, "wake not restored at free end")

// Post-tap API fixture, NOT an actual tap/enforcement test: refresh immediately
// removes the prompt while preserving externally seeded deadline and rules.
for wait in [0, 600] {
    reset(); seed(basic()); publish("pre-tap")
    check(WidgetPresentation.current(snapshot: snapshot(), at: monday) == .wake, "missing pre-tap prompt")
    let deadline = monday.addingTimeInterval(Double(wait))
    let deadlineBytes = encoded(deadline)
    SharedStore.defaults.values["fixture.runtime.deadline"] = deadlineBytes
    let rulesBytes = SharedStore.defaults.values[LatchConstants.stateKey]
    FixtureReaders.answers["global"] = { _, _ in wait == 0 ? .awake : .waiting(deadline) }
    publish("post-tap refresh")
    check(snapshot().wakeDue == nil, "post-tap refresh retained prompt")
    check(SharedStore.defaults.values["fixture.runtime.deadline"] == deadlineBytes, "display changed deadline")
    check(SharedStore.defaults.values[LatchConstants.stateKey] == rulesBytes, "display changed rules")
    check(WidgetPresentation.current(snapshot: snapshot(), at: monday) != .wake, "renderer retained post-tap prompt")
    check(WidgetCenter.shared.reloads == 2, "post-tap projection not reloaded")
    publish("post-tap duplicate")
    check(WidgetCenter.shared.reloads == 2, "post-tap duplicate reloaded")
}

print("Wake widget publication: \(assertions) assertions passed; actual host publisher/projection/presentation")
print("Limits: Codable state/API fixtures, in-memory preferences, temp container, deterministic coordinator; no enforcement, IPC-lock or WidgetKit/device proof")
'''


def main():
    source = FIXTURES + "\n" + isolated_source() + "\n" + CHECKS
    assert "UserDefaults(" not in source and "containerURL(" not in source
    with tempfile.TemporaryDirectory(prefix="demora-wake-publication-") as directory:
        root = Path(directory)
        runtime = root / "runtime"
        runtime.mkdir()
        swift = root / "main.swift"
        swift.write_text(source)
        for configuration, flags in [("Debug", ["-D", "DEBUG"]), ("Release", [])]:
            binary = root / configuration
            subprocess.run(["xcrun", "swiftc", *flags, str(swift), "-o", str(binary)], check=True)
            subprocess.run([str(binary), str(runtime)], check=True,
                           env={**os.environ, "TZ": "America/New_York"})
            print(f"{configuration} isolated publication checks passed", flush=True)


if __name__ == "__main__":
    main()
