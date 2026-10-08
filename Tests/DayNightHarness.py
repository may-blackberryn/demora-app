#!/usr/bin/env python3
"""Run: python3 Tests/DayNightHarness.py

Compile actual SharedModels, DayNightPolicy, DayNightWake and the two pure
initial-day/night migration helpers on macOS. Only framework imports and opaque
Apple tokens are adapted. Real Foundation UserDefaults uses a random temporary
suite behind a readback/write-failure adapter. State coordination and monitor
effects are stubs: this is NOT an NSFileCoordinator/cross-process durability,
ManagedSettings composition, protected-file, or DeviceActivity delivery test.
No live App Group, rule store, or selected apps are accessed.
"""
from pathlib import Path
import os
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def block(source, signature):
    """Extract an entire production declaration (same convention as peers)."""
    start = source.index(signature)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def portable(source):
    return source.replace("import FamilyControls\n", "").replace(
        "import ManagedSettings\n", ""
    ).replace("import DeviceActivity\n", "")


models = portable((ROOT / "Shared/SharedModels.swift").read_text())
policy = portable((ROOT / "Shared/DayNightPolicy.swift").read_text())
runtime = portable((ROOT / "Shared/DayNightWake.swift").read_text())
engine = (ROOT / "Shared/ChangeEngine.swift").read_text()
store = (ROOT / "Shared/SharedStore.swift").read_text()
phrases = (ROOT / "Shared/PhraseWords.swift").read_text()
budget = (ROOT / "Shared/MonitoringBudget.swift").read_text()
migration = "\n".join(block(store, signature) for signature in [
    "static func canSetUpInitialDayNight(in",
    "static func initialDayNightState(",
])

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
    static var date = Date()
    static func now() -> Date { date }
}
final class LocalDefaults {
    let suite = "demora-day-night-tests-" + UUID().uuidString
    let storage: UserDefaults
    var rejectWrites = false
    var failReadback = false
    var rejectKeys: Set<String> = []
    var failReadbackKeys: Set<String> = []
    var hideNextRead = false
    var writes = 0
    init() { storage = UserDefaults(suiteName: suite)! }
    func data(forKey key: String) -> Data? {
        if hideNextRead { hideNextRead = false; return nil }
        return storage.data(forKey: key)
    }
    func set(_ value: Any?, forKey key: String) {
        writes += 1
        if !rejectWrites && !rejectKeys.contains(key) { storage.set(value, forKey: key) }
        if failReadback || failReadbackKeys.contains(key) { hideNextRead = true }
    }
    func removeObject(forKey key: String) { storage.removeObject(forKey: key) }
    func reset() {
        storage.removePersistentDomain(forName: suite)
        rejectWrites = false; failReadback = false; hideNextRead = false; writes = 0
        rejectKeys = []; failReadbackKeys = []
    }
}
struct DeviceActivityName: Hashable {
    var rawValue: String
    init(_ text: String) { rawValue = text }
}
struct DeviceActivitySchedule {
    var intervalStart: DateComponents
    var intervalEnd: DateComponents
    var repeats: Bool
    var warningTime: DateComponents? = nil
}
enum MonitorFailure: Error { case injected }
// Registration policy has its own production-body harness. This adapter keeps
// these existing tests focused on wake state and injected monitor effects.
enum MonitorRegistration {
    static func start(_ name: DeviceActivityName, during schedule: DeviceActivitySchedule) throws {
        try DeviceActivityCenter().startMonitoring(name, during: schedule)
    }
}
struct DeviceActivityCenter {
    static var registered: [String: DeviceActivitySchedule] = [:]
    static var started: [String] = []
    static var stopped: [String] = []
    static var rejectStart = false
    var activities: [DeviceActivityName] { Self.registered.keys.map(DeviceActivityName.init) }
    func startMonitoring(_ name: DeviceActivityName, during schedule: DeviceActivitySchedule) throws {
        if Self.rejectStart { throw MonitorFailure.injected }
        Self.registered[name.rawValue] = schedule
        Self.started.append(name.rawValue)
    }
    func stopMonitoring(_ names: [DeviceActivityName]) {
        for name in names {
            Self.registered.removeValue(forKey: name.rawValue)
            Self.stopped.append(name.rawValue)
        }
    }
    static func reset() {
        registered = [:]; started = []; stopped = []; rejectStart = false
    }
}
enum SharedStore {
    static let defaults = LocalDefaults()
    static var state = LatchState()
    static var simulating = false
    static var stateRecoveryNeeded = false
    static var enforcementDegraded = false
    static var rejectCoordination = false
    static var coordinationCalls = 0
    static let redesignMigrationKey = "latch.redesign2.migrated"
    static let redesignWelcomeKey = "latch.redesign2.welcomeSeen"
    static func loadState() -> LatchState { state }
    // Deliberately a stub, not a substitute claim about NSFileCoordinator.
    static func coordinateStateMutation<T>(_ body: () -> T) -> T? {
        coordinationCalls += 1
        return rejectCoordination ? nil : body()
    }
    static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
'''

checks = r'''
var scenarios = 0
var assertions = 0
var failures: [String] = []
var scenarioName = ""
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
    assertions += 1
    do {
        if try !condition() { failures.append("\(scenarioName): \(message)") }
    } catch { failures.append("\(scenarioName): \(message): \(error)") }
}
func scenario(_ name: String, _ body: () throws -> Void) {
    scenarios += 1; scenarioName = name
    SharedStore.defaults.reset(); SharedStore.state = LatchState()
    SharedStore.simulating = false; SharedStore.stateRecoveryNeeded = false
    SharedStore.enforcementDegraded = false; SharedStore.rejectCoordination = false
    SharedStore.coordinationCalls = 0; DeviceActivityCenter.reset()
    TimeGuard.date = Date()
    do { try body() } catch { failures.append("\(name): \(error)") }
}
func tokens(_ apps: Set<String> = [], _ categories: Set<String> = [],
            _ webs: Set<String> = []) -> FamilyActivitySelection {
    FamilyActivitySelection(applicationTokens: apps, categoryTokens: categories,
                            webDomainTokens: webs)
}
func group(_ name: String, _ selection: FamilyActivitySelection = tokens(),
           mode: DayNightScopeMode = .selected, wake: Bool = true,
           sleep: Bool = false, wait: Int = 10) -> DayNightGroup {
    var value = DayNightGroup()
    value.name = name; value.startHour = 0; value.waitMinutes = wait
    value.wakeEnabled = wake; value.sleepEnabled = sleep
    value.scope.mode = mode; value.scope.selection = selection
    return value
}
func date(_ text: String) -> Date {
    let format = DateFormatter()
    format.locale = Locale(identifier: "en_US_POSIX")
    format.calendar = Calendar(identifier: .gregorian)
    format.timeZone = TimeZone.current
    format.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return format.date(from: text)!
}
// Explicit offsets disambiguate the first and second repeated hour without
// relying on DateFormatter's choice for an ambiguous local fixture.
func offsetDate(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}
let monday = date("2026-10-05 12:00:00")
let runtimeKey = "latch.dayNightWake.entries.v1"
let projectionKey = "latch.dayNightWake.projection.v1"
// Decode the private production cache's wire format for inspection/fault
// fixtures only. Production Projection encoding/decoding/comparison runs intact.
struct ProjectionSnapshot: Codable {
    var wallRelease: Date
    var zone: String
    var calendar: String
}
func projection() throws -> ProjectionSnapshot? {
    guard let data = SharedStore.defaults.storage.data(forKey: projectionKey) else { return nil }
    return try JSONDecoder().decode(ProjectionSnapshot.self, from: data)
}
func releaseName() -> String? {
    DeviceActivityCenter.registered.keys.first { $0.hasPrefix("day-night-release-") }
}
func entries() throws -> [String: DayNightWake.Entry] {
    guard let data = SharedStore.defaults.storage.data(forKey: runtimeKey) else { return [:] }
    return try JSONDecoder().decode([String: DayNightWake.Entry].self, from: data)
}
func blank(_ plan: DayNightShieldPlan) -> Bool {
    plan.blocked == tokens() && plan.allowed == nil && plan.freed == tokens()
}
func canonical<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return try encoder.encode(value)
}

scenario("checklist and extra tokens union without modifying limits") {
    let limit = AppLimit(name: "Saved limit", selection: tokens(["limit"], ["category"], ["limit.site"]),
                         minutesPerDay: 45, wakeDelayMinutes: 20)
    var named = group("Named", tokens(["extra"], [], ["extra.site"]))
    named.scope.limitIDs = [limit.id]
    var state = LatchState(); state.limits = [limit]; state.dayNightGroups = [named]
    let before = try canonical(state)
    let resolved = named.scope.resolved(limits: state.limits)
    expect(resolved == tokens(["limit", "extra"], ["category"], ["limit.site", "extra.site"]), "scope lost checklist or extra tokens")
    let plan = DayNightPolicy.plan(state: state, at: monday) { _ in .needsTap }
    expect(plan.blocked == resolved && plan.allowed == nil, "selected aggregate differs from resolved union")
    expect(try canonical(state) == before, "pure policy mutated legacy configuration")
    var edited = limit; edited.selection = tokens(["changed"])
    expect(named.scope.resolved(limits: [edited]).applicationTokens == ["changed", "extra"], "checklist isn't resolved from current limit membership")
}

scenario("independent wake statuses via production policy closure") {
    let a = group("Short", tokens(["short", "overlap"]), wait: 1)
    let b = group("Long", tokens(["long", "overlap"]), wait: 120)
    var state = LatchState(); state.dayNightGroups = [a, b]
    for status in [GlobalWakeStatus.needsTap, .waiting(monday.addingTimeInterval(600))] {
        let plan = DayNightPolicy.plan(state: state, at: monday) { $0.id == a.id ? .awake : status }
        expect(plan.blocked.applicationTokens == ["long", "overlap"], "finished short wait erased independent long block")
    }
    expect(blank(DayNightPolicy.plan(state: state, at: monday) { _ in .awake }), "completed gates still block")
    expect(blank(DayNightPolicy.plan(state: state, at: monday) { _ in .inactive }), "inactive gates block")
}

scenario("fallback automatically excludes only wake-enabled named groups") {
    let wake = group("Own wake", tokens(["own-wake"], [], ["own.site"]))
    let sleep = group("Own sleep", tokens(["sleep-only"]), wake: false, sleep: true)
    let fallback = group("Other", tokens(["explicit-exception"], [], ["exception.site"]), mode: .allOtherApps)
    var state = LatchState(); state.dayNightGroups = [wake, sleep, fallback]
    let plan = DayNightPolicy.plan(state: state, at: monday) { $0.id == fallback.id ? .needsTap : .awake }
    expect(plan.allowed?.applicationTokens == ["explicit-exception", "own-wake"], "wake fallback excludes wrong enabled dimensions")
    expect(plan.allowed?.webDomainTokens == ["exception.site", "own.site"], "fallback lost named domain exception")
    // An inactive own group is still independently assigned, not silently
    // absorbed into the fallback on its off-days/before its start time.
    let inactive = DayNightPolicy.plan(state: state, at: monday) { $0.id == fallback.id ? .needsTap : .inactive }
    expect(inactive.allowed == plan.allowed, "inactive named wake assignment absorbed into fallback")
}

scenario("fallback automatically excludes only sleep-enabled named groups") {
    let wake = group("Wake only", tokens(["wake-only"]))
    var sleep = group("Sleep only", tokens(["sleep-only"]), wake: false, sleep: true)
    sleep.startHour = 6
    var fallback = group("Sleep fallback", mode: .allOtherApps, wake: false, sleep: true)
    fallback.startHour = 6
    var state = LatchState(); state.dayNightGroups = [wake, sleep, fallback]
    let night = date("2026-10-05 23:00:00")
    let plan = DayNightPolicy.plan(state: state, at: night) { _ in .inactive }
    expect(plan.allowed?.applicationTokens == ["sleep-only"], "sleep fallback autoexcludes wake-only group")
    expect(plan.blocked.applicationTokens == ["sleep-only"], "fallback exceptions erased own sleep block")
}

scenario("fallback checklist exceptions don't erase explicit selected blocks") {
    let limit = AppLimit(name: "Excepted limit", selection: tokens(["same", "excepted"]), minutesPerDay: 0)
    let explicit = group("Selected", tokens(["same"], [], ["same.site"]))
    var fallback = group("Other", tokens(["same"], [], ["same.site"]), mode: .allOtherApps)
    fallback.scope.excludedLimitIDs = [limit.id]
    var state = LatchState(); state.limits = [limit]; state.dayNightGroups = [explicit, fallback]
    let plan = DayNightPolicy.plan(state: state, at: monday) { _ in .needsTap }
    expect(plan.allowed?.applicationTokens == ["same", "excepted"], "checklist fallback exceptions not resolved")
    expect(plan.blocked.applicationTokens == ["same"], "local exception cleared explicit group block")
    expect(plan.blocked.webDomainTokens == ["same.site"], "domain exception cleared explicit block")
    expect(state.limits == [limit], "day/night policy reset spent-limit configuration")
    // Real cross-store restriction/ordinary spent markers are device tests.
}

scenario("multiple restrictive fallbacks intersect even for invalid stored collection") {
    let a = group("A", tokens(["shared", "a"], [], ["shared.site", "a.site"]), mode: .allOtherApps)
    let b = group("B", tokens(["shared", "b"], [], ["shared.site", "b.site"]), mode: .allOtherApps)
    var state = LatchState(); state.dayNightGroups = [a, b]
    expect(!DayNightGroup.isValidCollection(state.dayNightGroups, limits: []), "multiple fallbacks accepted")
    let plan = DayNightPolicy.plan(state: state, at: monday) { _ in .needsTap }
    expect(plan.allowed == tokens(["shared"], [], ["shared.site"]), "fallbacks overwrite/union instead of intersect")
    var disjoint = b; disjoint.scope.selection = tokens(["none"])
    state.dayNightGroups = [a, disjoint]
    expect(DayNightPolicy.plan(state: state, at: monday) { _ in .needsTap }.allowed == tokens(), "empty intersection treated as no restriction")
}

scenario("category and fallback validation") {
    let category = group("Category", tokens([], ["games"]))
    let fallback = group("All others", mode: .allOtherApps)
    expect(category.isValid(limits: []), "selected category rejected")
    expect(fallback.isValid(limits: []), "empty all-other allowlist rejected")
    expect(!DayNightGroup.isValidCollection([category, fallback], limits: []), "category-wide automatic exemption promised")
    var mixed = fallback; mixed.scope.selection = tokens(["app"], ["games"])
    expect(!mixed.isValid(limits: []), "mixed app/category fallback exception accepted")
    let categoryLimit = AppLimit(name: "Category limit", selection: tokens([], ["games"]), minutesPerDay: 30)
    var excluded = fallback; excluded.scope.excludedLimitIDs = [categoryLimit.id]
    expect(!excluded.isValid(limits: [categoryLimit]), "category checklist exception accepted")
    var missing = category; missing.scope.limitIDs = [UUID()]
    expect(!missing.isValid(limits: []), "dangling checklist ID accepted")
    var empty = category; empty.scope.selection = tokens()
    expect(!empty.isValid(limits: []), "empty selected rule accepted")
    expect(!DayNightGroup.isValidCollection([category, category], limits: []), "duplicate rule IDs accepted")
    expect(!DayNightGroup.isValidCollection((0..<6).map { group("G\($0)", tokens(["app"])) }, limits: []), "group cap ignored")
    for minutes in [-1, 1441] {
        var invalid = category; invalid.waitMinutes = minutes
        expect(!invalid.isValid(limits: []), "out-of-range wait accepted")
    }
}

scenario("overnight sleep belongs to start weekday, ends at own wake hour") {
    var sleep = group("Monday night", tokens(["night"]), wake: false, sleep: true)
    sleep.startHour = 6; sleep.weekdays = [2]; sleep.sleepStartMinutes = 22 * 60
    var state = LatchState(); state.dayNightGroups = [sleep]
    for (text, blocked) in [("2026-10-05 21:59:59", false), ("2026-10-05 22:00:00", true),
                            ("2026-10-06 05:59:59", true), ("2026-10-06 06:00:00", false),
                            ("2026-10-06 23:00:00", false), ("2026-10-05 05:00:00", false)] {
        let plan = DayNightPolicy.plan(state: state, at: date(text)) { _ in .inactive }
        expect(plan.blocked.applicationTokens.contains("night") == blocked, "wrong overnight boundary at \(text)")
    }
}

scenario("referenced-limit edits cannot introduce unrepresentable fallback category exceptions") {
    let referenced = AppLimit(name: "Referenced", selection: tokens(["app"]), minutesPerDay: 45)
    let unrelated = AppLimit(name: "Unrelated", selection: tokens(["other"]), minutesPerDay: 30)
    var named = group("Named checklist")
    named.scope.limitIDs = [referenced.id]
    let fallback = group("Other apps", mode: .allOtherApps)
    let groups = [named, fallback]
    expect(DayNightGroup.isValidCollection(groups, limits: [referenced, unrelated]), "valid checklist/fallback rejected")
    expect(DayNightGroup.supportsLimitSelections(groups, limits: [referenced, unrelated]), "unchanged app selections rejected")
    var categoryEdit = referenced; categoryEdit.selection = tokens(["app"], ["games"])
    expect(!DayNightGroup.supportsLimitSelections(groups, limits: [categoryEdit, unrelated]), "referenced mixed category edit bypasses fallback guard")
    expect(!DayNightGroup.isValidCollection(groups, limits: [categoryEdit, unrelated]), "collection validation doesn't reuse referenced-limit guard")
    var categoryOnly = referenced; categoryOnly.selection = tokens([], ["games"])
    expect(!DayNightGroup.supportsLimitSelections(groups, limits: [categoryOnly, unrelated]), "referenced category-only edit accepted")
    var unrelatedEdit = unrelated; unrelatedEdit.selection = tokens([], ["games"])
    expect(DayNightGroup.supportsLimitSelections(groups, limits: [referenced, unrelatedEdit]), "unreferenced category edit unnecessarily rejected")
    expect(DayNightGroup.supportsLimitSelections([named], limits: [categoryEdit]), "category group without fallback rejected")
    var excluded = fallback; excluded.scope.excludedLimitIDs = [referenced.id]
    expect(!DayNightGroup.supportsLimitSelections([excluded], limits: [categoryEdit]), "explicit fallback checklist category edit accepted")
    var direct = fallback; direct.scope.selection = tokens(["app"], ["games"])
    expect(!DayNightGroup.supportsLimitSelections([direct], limits: []), "direct fallback mixed category exceptions accepted")
    var appEdit = referenced; appEdit.selection = tokens(["new"], [], ["new.site"])
    expect(DayNightGroup.supportsLimitSelections(groups, limits: [appEdit, unrelated]), "representable app/domain membership edit rejected")
}

scenario("spring DST overnight recurrence uses previous calendar day, not 86400 seconds") {
    expect(TimeZone.current.identifier == "America/New_York", "DST test process timezone not configured")
    var sleep = group("Sunday night", tokens(["night"]), wake: false, sleep: true)
    sleep.startHour = 6; sleep.weekdays = [1]; sleep.sleepStartMinutes = 22 * 60
    var state = LatchState(); state.dayNightGroups = [sleep]
    let afterShortSunday = date("2026-03-09 00:30:00")
    expect(Calendar.current.component(.weekday, from: afterShortSunday.addingTimeInterval(-86400)) == 7,
           "fixture doesn't expose old fixed-seconds Saturday anchor")
    expect(windowActive(at: afterShortSunday, start: 1320, end: 360, recurrence: .weekly([1])),
           "Sunday sleep lost after DST-short Sunday")
    expect(DayNightPolicy.plan(state: state, at: afterShortSunday) { _ in .inactive }
        .blocked.applicationTokens == ["night"], "sleep policy doesn't use calendar-day DST anchor")
    expect(!windowActive(at: date("2026-03-09 06:00:00"), start: 1320, end: 360, recurrence: .weekly([1])),
           "DST sleep survives its wake boundary")
    expect(windowActive(at: date("2026-11-02 00:30:00"), start: 1320, end: 360, recurrence: .weekly([1])),
           "fall DST Sunday night not retained")
}

scenario("recurring, planned and session free sources clear boundary plan only while active") {
    let named = group("Named", tokens(["app"], ["cat"], ["site"]))
    let fallback = group("Other", mode: .allOtherApps)
    for source in 0..<3 {
        var state = LatchState(); state.dayNightGroups = [named, fallback]
        if source == 0 {
            state.exemptions = [ExemptSchedule(name: "Free", startMinutes: 11 * 60,
                endMinutes: 13 * 60, recurrence: .weekly([2]))]
        } else if source == 1 {
            state.planned = [PlannedWindow(name: "Free", kind: .free, selection: tokens(),
                startsAt: monday.addingTimeInterval(-60), endsAt: monday.addingTimeInterval(60))]
        } else {
            state.sessions = [BlockSession(name: "Free", kind: .free, selection: tokens(),
                startedAt: monday.addingTimeInterval(-60), endsAt: monday.addingTimeInterval(60))]
        }
        expect(blank(DayNightPolicy.plan(state: state, at: monday) { _ in .needsTap }), "free source \(source) didn't clear all boundary buckets")
        expect(!blank(DayNightPolicy.plan(state: state, at: monday.addingTimeInterval(7200)) { _ in .needsTap }), "expired free source \(source) still clears boundary")
        if source != 0 {
            expect(!blank(DayNightPolicy.plan(state: state, at: monday.addingTimeInterval(-120)) { _ in .needsTap }), "future free source applied early")
        }
    }
}

scenario("specific unblock composes app/domain exceptions without clearing unrelated groups") {
    let named = group("Named", tokens(["unblock", "keep"], ["cat"], ["unblock.site", "keep.site"]))
    let fallback = group("Other", mode: .allOtherApps)
    var state = LatchState(); state.dayNightGroups = [named, fallback]
    state.sessions = [BlockSession(name: "Unblock", kind: .unblock,
        selection: tokens(["unblock"], [], ["unblock.site"]),
        startedAt: monday.addingTimeInterval(-60), endsAt: monday.addingTimeInterval(60))]
    let plan = DayNightPolicy.plan(state: state, at: monday) { _ in .needsTap }
    expect(plan.blocked == tokens(["keep"], ["cat"], ["keep.site"]), "unblock erased unrelated/category block")
    expect(plan.freed == tokens(["unblock"], [], ["unblock.site"]), "category-shield exception not recorded")
    expect(plan.allowed?.applicationTokens.contains("unblock") == true, "all-other unblock exception absent")
    expect(plan.allowed?.webDomainTokens.contains("unblock.site") == true, "all-other domain unblock absent")
    let expired = DayNightPolicy.plan(state: state, at: monday.addingTimeInterval(60)) { _ in .needsTap }
    expect(expired.blocked == named.scope.selection && expired.freed == tokens(), "unblock end failed to restore original blocks")
}

scenario("old state Codable defaults and new model/action roundtrip") {
    var old = LatchState(); old.isSetUp = true
    old.limits = [AppLimit(name: "Old", selection: tokens(["old"]), minutesPerDay: 45, wakeDelayMinutes: 10)]
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
    object.removeValue(forKey: "dayNightGroups"); object.removeValue(forKey: "dayNightSetupDone")
    let decoded = try JSONDecoder().decode(LatchState.self, from: JSONSerialization.data(withJSONObject: object))
    expect(decoded.dayNightGroups.isEmpty && !decoded.dayNightSetupDone, "old state missing keys doesn't default safely")
    expect(decoded.limits == old.limits && decoded.isSetUp, "old gates/setup changed during decode")
    let named = group("New", tokens(["app"]))
    var new = decoded; new.dayNightGroups = [named]; new.dayNightSetupDone = true
    let roundtrip = try JSONDecoder().decode(LatchState.self, from: JSONEncoder().encode(new))
    expect(roundtrip.dayNightGroups == [named] && roundtrip.dayNightSetupDone, "new group/epoch lost on Codable roundtrip")
    for action in [ChangeAction.upsertDayNightGroup(named), .removeDayNightGroup(id: named.id),
                   .setWakeRule(WakeBlockRule()), .setSleepRule(SleepBlockRule())] {
        expect(try JSONDecoder().decode(ChangeAction.self, from: JSONEncoder().encode(action)) == action, "new or legacy pending action failed roundtrip")
    }
}

scenario("one tap starts independent waits and preserves deadlines on repeated tap and wait edits") {
    let short = group("Short", tokens(["short"]), wait: 1)
    let long = group("Long", tokens(["long"]), wait: 120)
    let zero = group("Immediate", tokens(["zero"]), wait: 0)
    var off = group("Sleep only", tokens(["off"]), wake: false, sleep: true)
    off.startHour = 6
    SharedStore.state.dayNightGroups = [short, long, zero, off]
    let tappedAt = TimeGuard.date
    expect(DayNightWake.tapAll(), "first shared tap rejected")
    let first = try entries()
    expect(Set(first.keys) == Set([short.id, long.id, zero.id].map(\.uuidString)), "tap started ineligible gate or missed eligible gate")
    expect(first[short.id.uuidString]?.release == tappedAt.addingTimeInterval(60), "short wait incorrect")
    expect(first[long.id.uuidString]?.release == tappedAt.addingTimeInterval(7200), "long wait incorrect")
    expect(first[zero.id.uuidString]?.release == tappedAt, "zero wait incorrect")
    expect(DayNightWake.status(group: zero) == .awake, "zero wait isn't immediate after tap")
    TimeGuard.date = tappedAt.addingTimeInterval(60)
    expect(DayNightWake.status(group: short) == .awake, "short gate doesn't release at exact deadline")
    expect(DayNightWake.status(group: long) == .waiting(tappedAt.addingTimeInterval(7200)), "short release freed long gate")
    expect(!DayNightWake.tapAll(), "repeat tap accepted despite all eligible gates being started")
    expect(try entries() == first, "repeat tap mutated existing deadlines")
    var edited = long; edited.name = "Renamed"; edited.waitMinutes = 0
    SharedStore.state.dayNightGroups[1] = edited
    expect(DayNightWake.status(group: edited) == .waiting(tappedAt.addingTimeInterval(7200)), "wait/name edit recalculated current deadline")
    let added = group("Added later", tokens(["added"]), wait: 5)
    SharedStore.state.dayNightGroups.append(added)
    expect(DayNightWake.tapAll(), "new eligible gate wasn't started")
    let second = try entries()
    expect(second[long.id.uuidString] == first[long.id.uuidString], "new-gate tap shortened old gate")
    expect(second[added.id.uuidString]?.release == TimeGuard.date.addingTimeInterval(300), "added gate didn't use second tap time")
}

scenario("cycle/epoch isolation, inactive weekdays/start boundary, persisted reload") {
    var named = group("Gate", tokens(["app"]))
    named.startHour = 6; named.weekdays = [2]
    expect(DayNightWake.status(group: named, at: date("2026-10-05 05:59:59"), guardedNow: monday) == .inactive, "gate active before start")
    expect(DayNightWake.status(group: named, at: date("2026-10-05 06:00:00"), guardedNow: monday) == .needsTap, "gate not active at start")
    expect(DayNightWake.status(group: named, at: date("2026-10-06 12:00:00"), guardedNow: monday) == .inactive, "gate active on off weekday")
    let entry = DayNightWake.Entry(day: DayNightWake.cycle(group: named, at: monday), epoch: named.wakeEpoch,
                                  release: monday.addingTimeInterval(600))
    SharedStore.defaults.storage.set(try JSONEncoder().encode([named.id.uuidString: entry]), forKey: runtimeKey)
    let reloaded = try JSONDecoder().decode(DayNightGroup.self, from: JSONEncoder().encode(named))
    expect(DayNightWake.status(group: reloaded, at: monday, guardedNow: monday) == .waiting(entry.release), "persisted gate lost after model reload")
    expect(DayNightWake.status(group: reloaded, at: monday, guardedNow: entry.release) == .awake, "deadline equality didn't release")
    var movedStart = named; movedStart.startHour = 9
    expect(DayNightWake.cycle(group: movedStart, at: monday) == DayNightWake.cycle(group: named, at: monday),
           "start-hour edit changes current-day cycle key")
    expect(DayNightWake.status(group: movedStart, at: monday, guardedNow: monday) == .waiting(entry.release),
           "start-hour edit discarded today's persisted deadline")
    var reenabled = named; reenabled.wakeEpoch = UUID()
    expect(DayNightWake.status(group: reenabled, at: monday, guardedNow: monday) == .needsTap, "new enable epoch reused old tap")
    expect(DayNightWake.status(group: named, at: date("2026-10-12 12:00:00"), guardedNow: monday) == .needsTap, "next cycle reused previous day")
    var other = named; other.id = UUID()
    expect(DayNightWake.status(group: other, at: monday, guardedNow: monday) == .needsTap, "other group reused gate")
}

scenario("weekday minute starts and independent waits") {
    var named = group("Per day", tokens(["app"]))
    named.wakeStartMinutes = 7*60+30; named.waitMinutes = 15
    named.weekdayWakeTimings = [2: WakeDayTiming(startMinutes: 8*60+15, waitMinutes: 45),
                              7: WakeDayTiming(startMinutes: 10*60, waitMinutes: 0)]
    expect(named.isValid(limits: []), "valid per-day group rejected")
    expect(named.wakeTiming(on: monday).waitMinutes == 45, "Monday duration missed")
    expect(named.wakeTiming(on: date("2026-10-06 12:00:00")) == WakeDayTiming(startMinutes: 450, waitMinutes: 15), "default day missed")
    expect(DayNightWake.status(group: named, at: date("2026-10-05 08:14:59"), guardedNow: monday) == .inactive, "custom start early")
    expect(DayNightWake.status(group: named, at: date("2026-10-05 08:15:00"), guardedNow: monday) == .needsTap, "custom minute missed")
    expect(DayNightWake.status(group: named, at: date("2026-10-10 09:59:59"), guardedNow: monday) == .inactive, "Saturday start early")
    let today = Calendar.current.component(.weekday, from: Date())
    named.weekdayWakeTimings[today] = WakeDayTiming(startMinutes: 0, waitMinutes: 35)
    SharedStore.state.dayNightGroups = [named]
    let started = TimeGuard.date
    expect(DayNightWake.tapAll(), "weekday tap rejected")
    let installed = try entries()[named.id.uuidString]!
    expect(installed.release == started.addingTimeInterval(35*60), "tap ignored weekday wait")
    var moved = named
    moved.weekdays.remove(today)
    moved.weekdayWakeTimings[today] = WakeDayTiming(startMinutes: 1410, waitMinutes: 0)
    SharedStore.state.dayNightGroups = [moved]
    expect(DayNightWake.status(group: moved) == .waiting(installed.release), "day edit shortened existing wait")
    expect(!DayNightWake.tapAll(), "day edit allowed countdown reset")
    expect(try entries()[named.id.uuidString] == installed, "persisted deadline changed")
}
scenario("per-day sleep follows next morning, including DST") {
    var named = group("Night", tokens(["app"]), wake: false, sleep: true)
    named.weekdays = [2]; named.startHour = 6; named.sleepStartMinutes = 22*60
    named.weekdayWakeTimings[3] = WakeDayTiming(startMinutes: 9*60+30, waitMinutes: 10)
    expect(named.sleepIsActive(at: date("2026-10-06 09:29:59")), "Monday night lost Tuesday custom end")
    expect(!named.sleepIsActive(at: date("2026-10-06 09:30:00")), "sleep ended late")
    expect(!named.sleepIsActive(at: date("2026-10-06 22:00:00")), "off evening blocked")
    var state = LatchState(); state.dayNightGroups = [named]
    expect(DayNightPolicy.plan(state: state, at: date("2026-10-06 09:00:00"), wakeStatus: { _ in .inactive }).blocked.applicationTokens == ["app"], "policy ignores new sleep helper")
    named.weekdays = [7]; named.weekdayWakeTimings[1] = WakeDayTiming(startMinutes: 8*60+15, waitMinutes: 0)
    for dateText in ["2026-03-08 08:14:59", "2026-11-01 08:14:59"] {
        expect(named.sleepIsActive(at: date(dateText)), "DST overnight tail lost: \(dateText)")
    }
    for dateText in ["2026-03-08 08:15:00", "2026-11-01 08:15:00"] {
        expect(!named.sleepIsActive(at: date(dateText)), "DST end not exclusive: \(dateText)")
    }
}
scenario("old timing blobs decode without changing rules or epochs") {
    let named = group("Old", tokens(["app"]))
    let full = try JSONEncoder().encode(named)
    var object = try JSONSerialization.jsonObject(with: full) as! [String: Any]
    object.removeValue(forKey: "wakeStartMinutes"); object.removeValue(forKey: "weekdayWakeTimings")
    let legacy = try JSONDecoder().decode(DayNightGroup.self, from: JSONSerialization.data(withJSONObject: object))
    expect(legacy == named, "legacy group changed on decode")
    var item = AppLimit(name: "Old limit", selection: tokens(["app"]), minutesPerDay: 20, wakeDelayMinutes: 35)
    var limitJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as! [String: Any]
    limitJSON.removeValue(forKey: "wakeSchedule")
    let oldLimit = try JSONDecoder().decode(AppLimit.self, from: JSONSerialization.data(withJSONObject: limitJSON))
    expect(oldLimit == item, "legacy limit changed on decode")
    item.wakeSchedule = LimitWakeSchedule(startMinutes: 495, weekdays: [2,3], dayTimings: [3: WakeDayTiming(startMinutes: 600, waitMinutes: 60)])
    expect(try JSONDecoder().decode(AppLimit.self, from: JSONEncoder().encode(item)) == item, "limit timings don't roundtrip")
    var new = named; new.wakeStartMinutes = 480; new.weekdayWakeTimings[2] = WakeDayTiming(startMinutes: 600, waitMinutes: 45)
    expect(try JSONDecoder().decode(DayNightGroup.self, from: JSONEncoder().encode(new)) == new, "group timings don't roundtrip")
}
scenario("invalid day timings rejected before setup") {
    for test in 0..<5 {
        var named = group("Invalid", tokens(["app"]))
        switch test {
        case 0: named.wakeStartMinutes = -1
        case 1: named.wakeStartMinutes = 1411
        case 2: named.weekdayWakeTimings[0] = WakeDayTiming()
        case 3: named.weekdayWakeTimings[2] = WakeDayTiming(startMinutes: 60, waitMinutes: -1)
        default: named.sleepEnabled = true; named.weekdayWakeTimings[2] = WakeDayTiming(startMinutes: named.sleepStartMinutes, waitMinutes: 10)
        }
        expect(!named.isValid(limits: []), "invalid timing accepted: \(test)")
        expect(!DayNightGroup.isValidCollection([named], limits: []), "invalid collection accepted: \(test)")
    }
}
scenario("runtime rejected writes and failed coordination never report success") {
    let named = group("Gate", tokens(["app"]))
    SharedStore.state.dayNightGroups = [named]
    SharedStore.defaults.rejectWrites = true
    expect(!DayNightWake.tapAll(), "rejected runtime write reported success")
    expect(DayNightWake.status(group: named) == .needsTap, "failed write opened gate")
    expect(DeviceActivityCenter.started.isEmpty, "failed write scheduled release")
    SharedStore.defaults.rejectWrites = false; SharedStore.rejectCoordination = true
    expect(!DayNightWake.tapAll(), "failed coordination reported success")
    expect(try entries().isEmpty, "failed coordination mutated runtime")
}

scenario("readback failure reports failure without pretending accepted bytes were rolled back") {
    let named = group("Gate", tokens(["app"]))
    SharedStore.state.dayNightGroups = [named]
    SharedStore.defaults.failReadback = true
    expect(!DayNightWake.tapAll(), "unverified readback reported successful tap")
    expect(DeviceActivityCenter.started.isEmpty, "unverified tap immediately scheduled release")
    // A write can succeed while its verification read fails; do not assert
    // rollback/fail-closed semantics that production does not implement.
    expect(try entries()[named.id.uuidString] != nil, "fault adapter didn't retain accepted write")
    SharedStore.defaults.failReadback = false
    expect(!DayNightWake.tapAll(), "retry reset persisted but unverified deadline")
}

scenario("corrupt runtime retained, simulation/recovery taps rejected") {
    let named = group("Gate", tokens(["app"]))
    SharedStore.state.dayNightGroups = [named]
    let corrupt = Data("invalid JSON".utf8)
    SharedStore.defaults.storage.set(corrupt, forKey: runtimeKey)
    expect(DayNightWake.status(group: named) == .needsTap, "corrupt runtime opened gate")
    expect(SharedStore.enforcementDegraded, "corrupt runtime didn't surface diagnostic flag")
    expect(!DayNightWake.tapAll(), "corrupt runtime overwritten by tap")
    expect(SharedStore.defaults.storage.data(forKey: runtimeKey) == corrupt, "corrupt runtime not preserved")
    SharedStore.defaults.reset(); SharedStore.simulating = true
    expect(!DayNightWake.tapAll(), "simulation wrote real runtime")
    SharedStore.simulating = false; SharedStore.stateRecoveryNeeded = true
    expect(!DayNightWake.tapAll(), "recovery mode wrote runtime")
    expect(SharedStore.defaults.writes == 0, "ineligible tap touched storage")
}

scenario("deduplicated boundaries and shared earliest release advance without affecting daily monitor") {
    var a = group("A", tokens(["a"]), sleep: true, wait: 10)
    var b = group("B", tokens(["b"]), sleep: true, wait: 20)
    a.startHour = 6; b.startHour = 6
    var boundaryState = LatchState(); boundaryState.dayNightGroups = [a, b]
    expect(DayNightWake.boundaryMinutes(state: boundaryState) == [0, 360, 1320], "same boundaries consume duplicate activities")
    b.sleepStartMinutes = 1410; boundaryState.dayNightGroups = [a, b]
    expect(DayNightWake.boundaryMinutes(state: boundaryState) == [0, 360, 1320, 1410], "own sleep start omitted")
    expect(DayNightWake.boundaryMinutes(state: LatchState()).isEmpty, "empty config registers boundaries")
    a.startHour = 0; b.startHour = 0
    SharedStore.state.dayNightGroups = [a, b]
    DeviceActivityCenter.registered[LatchConstants.dailyActivityName] = DeviceActivitySchedule(
        intervalStart: DateComponents(hour: 0), intervalEnd: DateComponents(hour: 23, minute: 59), repeats: true)
    expect(DayNightWake.tapAll(), "shared release fixture tap failed")
    let persisted = try entries()
    let shortRelease = persisted[a.id.uuidString]!.release
    let longRelease = persisted[b.id.uuidString]!.release
    let releaseNames = DeviceActivityCenter.registered.keys.filter { $0.hasPrefix("day-night-release-") }
    expect(releaseNames.count == 1, "registered one release monitor per group")
    expect(releaseNames.first == "day-night-release-\(Int(shortRelease.timeIntervalSince1970))", "monitor isn't earliest release")
    let starts = DeviceActivityCenter.started.count
    DayNightWake.reconcile(state: SharedStore.state)
    expect(DeviceActivityCenter.started.count == starts, "unchanged earliest release restarted monitor")
    TimeGuard.date = shortRelease
    DayNightWake.reconcile(state: SharedStore.state)
    expect(DeviceActivityCenter.registered.keys.contains("day-night-release-\(Int(longRelease.timeIntervalSince1970))"), "release callback didn't advance to next group")
    TimeGuard.date = longRelease
    DayNightWake.reconcile(state: SharedStore.state)
    expect(DeviceActivityCenter.registered.keys.filter { $0.hasPrefix("day-night-release-") }.isEmpty, "expired release activity not cleaned up")
    expect(DeviceActivityCenter.registered[LatchConstants.dailyActivityName] != nil, "runtime stopped unrelated daily monitor")
}

scenario("monitor registration failure degrades without changing deadline") {
    let named = group("Gate", tokens(["app"]))
    SharedStore.state.dayNightGroups = [named]; DeviceActivityCenter.rejectStart = true
    expect(DayNightWake.tapAll(), "durable tap rejected solely because monitor failed")
    expect(SharedStore.enforcementDegraded, "registration failure not surfaced")
    let first = try entries()
    DeviceActivityCenter.rejectStart = false
    DayNightWake.reconcile(state: SharedStore.state)
    expect(try entries() == first, "monitor repair recalculated deadline")
    expect(DeviceActivityCenter.started.count == 1, "missing release monitor not repaired")
}

scenario("projection persisted after successful registration, healthy foreground and small drift reuse") {
    let named = group("Gate", tokens(["app"]), wait: 120)
    SharedStore.state.dayNightGroups = [named]
    expect(DayNightWake.tapAll(), "projection fixture tap failed")
    let firstEntries = try entries()
    let first = try projection()!
    let firstName = releaseName()!
    let starts = DeviceActivityCenter.started.count
    let stops = DeviceActivityCenter.stopped.count
    expect(first.calendar == String(describing: Calendar.current.identifier), "calendar identity absent")
    expect(first.zone == Calendar.current.timeZone.identifier + "-\(Calendar.current.timeZone.secondsFromGMT())", "zone/offset identity absent")
    expect(abs(first.wallRelease.timeIntervalSince(firstEntries[named.id.uuidString]!.release)) < 2,
           "initial wall projection incorrect")
    for _ in 0..<5 { DayNightWake.reconcile(state: SharedStore.state) }
    expect(DeviceActivityCenter.started.count == starts && DeviceActivityCenter.stopped.count == stops,
           "healthy foreground reconciliation restarted release monitor")
    TimeGuard.date = TimeGuard.date.addingTimeInterval(5)
    DayNightWake.reconcile(state: SharedStore.state)
    expect(DeviceActivityCenter.started.count == starts && releaseName() == firstName,
           "sub-tolerance guarded-clock drift restarted monitor")
    expect(try entries() == firstEntries, "projection reuse changed persisted deadlines")
}

scenario("material clock projection shift rearms same deadline once, then reuses") {
    let named = group("Gate", tokens(["app"]), wait: 120)
    SharedStore.state.dayNightGroups = [named]
    expect(DayNightWake.tapAll(), "clock-shift fixture tap failed")
    let firstEntries = try entries()
    let first = try projection()!
    let name = releaseName()!
    let starts = DeviceActivityCenter.started.count
    // Date()/Calendar remain actual Foundation APIs. Moving the injected
    // guarded clock changes the wall/guarded offset used by production.
    TimeGuard.date = TimeGuard.date.addingTimeInterval(300)
    DayNightWake.reconcile(state: SharedStore.state)
    let advanced = try projection()!
    expect(DeviceActivityCenter.started.count == starts + 1, "300-second projection shift didn't rearm")
    expect(releaseName() == name, "guarded deadline/name changed during clock reprojection")
    expect(abs(advanced.wallRelease.timeIntervalSince(first.wallRelease) + 300) < 2,
           "forward guarded-clock shift didn't move wall projection earlier")
    DayNightWake.reconcile(state: SharedStore.state)
    expect(DeviceActivityCenter.started.count == starts + 1, "stable shifted projection restarts each foreground")
    TimeGuard.date = TimeGuard.date.addingTimeInterval(-600)
    DayNightWake.reconcile(state: SharedStore.state)
    let delayed = try projection()!
    expect(DeviceActivityCenter.started.count == starts + 2, "backward guarded-clock shift didn't rearm")
    expect(abs(delayed.wallRelease.timeIntervalSince(advanced.wallRelease) - 600) < 2,
           "backward shift didn't project remaining wait later")
    expect(try entries() == firstEntries, "clock reprojection altered stored deadlines")
}

scenario("cached zone, offset and calendar identity mismatch rearm without changing deadline") {
    let named = group("Gate", tokens(["app"]), wait: 120)
    SharedStore.state.dayNightGroups = [named]
    expect(DayNightWake.tapAll(), "identity fixture tap failed")
    let firstEntries = try entries()
    for identity in ["zone", "offset", "calendar"] {
        var cached = try projection()!
        if identity == "zone" { cached.zone = "Europe/London-0" }
        if identity == "offset" { cached.zone = Calendar.current.timeZone.identifier + "-0" }
        if identity == "calendar" { cached.calendar = "buddhist" }
        // Simulates an old persisted fingerprint; does not claim a real iOS
        // time-zone notification or system calendar change was exercised.
        SharedStore.defaults.storage.set(try JSONEncoder().encode(cached), forKey: projectionKey)
        let starts = DeviceActivityCenter.started.count
        DayNightWake.reconcile(state: SharedStore.state)
        expect(DeviceActivityCenter.started.count == starts + 1, "\(identity) mismatch didn't rearm")
        let repaired = try projection()!
        expect(repaired.calendar == String(describing: Calendar.current.identifier), "calendar fingerprint not refreshed")
        expect(repaired.zone == Calendar.current.timeZone.identifier + "-\(Calendar.current.timeZone.secondsFromGMT())", "zone fingerprint not refreshed")
        DayNightWake.reconcile(state: SharedStore.state)
        expect(DeviceActivityCenter.started.count == starts + 1, "repaired \(identity) projection restarts again")
    }
    expect(try entries() == firstEntries, "identity repair changed deadlines")
}

scenario("early delivered one-shot consumed and rearmed without unlocking or retapping") {
    let named = group("Gate", tokens(["app"]), wait: 120)
    SharedStore.state.dayNightGroups = [named]
    expect(DayNightWake.tapAll(), "early-callback fixture tap failed")
    let firstEntries = try entries()
    let name = releaseName()!
    let starts = DeviceActivityCenter.started.count
    DayNightWake.receivedActivity(name)
    expect(releaseName() == nil, "delivered release activity not stopped")
    expect(SharedStore.defaults.storage.data(forKey: projectionKey) == nil, "delivered projection not cleared")
    expect(DayNightWake.status(group: named) == .waiting(firstEntries[named.id.uuidString]!.release),
           "premature callback unlocked gate")
    DayNightWake.reconcile(state: SharedStore.state)
    expect(releaseName() == name && DeviceActivityCenter.started.count == starts + 1,
           "early callback couldn't rearm same guarded deadline")
    expect(try projection() != nil, "rearmed projection not persisted")
    expect(try entries() == firstEntries, "early callback mutated gate deadline")
    let schedule = DeviceActivityCenter.registered[name]!
    expect(!schedule.repeats && schedule.warningTime?.minute == 5, "rearmed one-shot/warning shape changed")
    let start = Calendar.current.date(from: schedule.intervalStart)!
    let end = Calendar.current.date(from: schedule.intervalEnd)!
    expect(end.timeIntervalSince(start) >= 15 * 60, "rearmed monitor violates minimum interval")
}

scenario("due callbacks advance earliest deadline, final callback clears projection; unrelated/simulation ignored") {
    let short = group("Short", tokens(["short"]), wait: 10)
    let long = group("Long", tokens(["long"]), wait: 20)
    SharedStore.state.dayNightGroups = [short, long]
    expect(DayNightWake.tapAll(), "due-callback fixture tap failed")
    let firstEntries = try entries()
    let initialName = releaseName()!
    let initialProjection = SharedStore.defaults.storage.data(forKey: projectionKey)
    DayNightWake.receivedActivity(LatchConstants.dailyActivityName)
    expect(releaseName() == initialName && SharedStore.defaults.storage.data(forKey: projectionKey) == initialProjection,
           "unrelated callback consumed release projection")
    SharedStore.simulating = true
    DayNightWake.receivedActivity(initialName)
    expect(releaseName() == initialName, "simulation consumed real release monitor")
    SharedStore.simulating = false
    TimeGuard.date = firstEntries[short.id.uuidString]!.release
    DayNightWake.receivedActivity(initialName)
    DayNightWake.reconcile(state: SharedStore.state)
    expect(releaseName() == "day-night-release-\(Int(firstEntries[long.id.uuidString]!.release.timeIntervalSince1970))",
           "due callback didn't advance to next group's release")
    TimeGuard.date = firstEntries[long.id.uuidString]!.release
    DayNightWake.receivedActivity(releaseName()!)
    DayNightWake.reconcile(state: SharedStore.state)
    expect(releaseName() == nil && SharedStore.defaults.storage.data(forKey: projectionKey) == nil,
           "final callback left activity/projection armed")
    expect(try entries() == firstEntries, "callback cleanup erased completed cycle records")
}

scenario("failed registration never caches a successful-looking projection, repair retains deadlines") {
    let named = group("Gate", tokens(["app"]), wait: 120)
    SharedStore.state.dayNightGroups = [named]
    expect(DayNightWake.tapAll(), "registration-fault fixture tap failed")
    let firstEntries = try entries()
    TimeGuard.date = TimeGuard.date.addingTimeInterval(300)
    DeviceActivityCenter.rejectStart = true
    DayNightWake.reconcile(state: SharedStore.state)
    expect(SharedStore.enforcementDegraded, "failed reprojection registration not surfaced")
    expect(releaseName() == nil, "fault adapter registered rejected activity")
    expect(SharedStore.defaults.storage.data(forKey: projectionKey) == nil, "failed registration cached projection or retained stale cache")
    DeviceActivityCenter.rejectStart = false
    DayNightWake.reconcile(state: SharedStore.state)
    expect(try releaseName() != nil && projection() != nil, "missing activity/projection not repaired")
    expect(try entries() == firstEntries, "registration failure/repair recalculated deadlines")
}

scenario("missing/corrupt projection repaired without overwriting gate runtime") {
    let named = group("Gate", tokens(["app"]), wait: 120)
    SharedStore.state.dayNightGroups = [named]
    expect(DayNightWake.tapAll(), "projection-corruption fixture tap failed")
    let firstEntries = try entries()
    for corrupt in [false, true] {
        if corrupt { SharedStore.defaults.storage.set(Data("bad projection".utf8), forKey: projectionKey) }
        else { SharedStore.defaults.storage.removeObject(forKey: projectionKey) }
        let starts = DeviceActivityCenter.started.count
        DayNightWake.reconcile(state: SharedStore.state)
        expect(try DeviceActivityCenter.started.count == starts + 1 && projection() != nil,
               "missing/corrupt projection reused stale named monitor")
    }
    expect(try entries() == firstEntries, "projection repair mutated gate runtime")
}

scenario("projection cache rejected writes/readback failures surface degradation and retry safely") {
    let named = group("Gate", tokens(["app"]), wait: 120)
    SharedStore.state.dayNightGroups = [named]
    SharedStore.defaults.rejectKeys = [projectionKey]
    expect(DayNightWake.tapAll(), "verified gate write failed solely because projection cache was rejected")
    let firstEntries = try entries()
    expect(SharedStore.enforcementDegraded && releaseName() != nil, "projection write failure not surfaced with real registered monitor")
    expect(SharedStore.defaults.storage.data(forKey: projectionKey) == nil, "rejected cache write persisted")
    SharedStore.defaults.rejectKeys = []; SharedStore.enforcementDegraded = false
    DayNightWake.reconcile(state: SharedStore.state)
    expect(try projection() != nil, "rejected projection cache not repaired")
    TimeGuard.date = TimeGuard.date.addingTimeInterval(300)
    SharedStore.defaults.failReadbackKeys = [projectionKey]
    DayNightWake.reconcile(state: SharedStore.state)
    expect(SharedStore.enforcementDegraded, "projection readback failure not surfaced")
    // Accepted bytes may survive a failed verification read, as with entries.
    expect(try projection() != nil, "accepted projection write unexpectedly rolled back")
    SharedStore.defaults.failReadbackKeys = []
    let starts = DeviceActivityCenter.started.count
    DayNightWake.reconcile(state: SharedStore.state)
    expect(DeviceActivityCenter.started.count == starts, "verified surviving projection caused needless retry restart")
    expect(try entries() == firstEntries, "projection cache fault changed guarded deadlines")
}

let migrationSuite = "demora-day-night-migration-tests-" + UUID().uuidString
let migrationDefaults = UserDefaults(suiteName: migrationSuite)!
func eligibleLegacy() -> LatchState {
    migrationDefaults.removePersistentDomain(forName: migrationSuite)
    migrationDefaults.set(true, forKey: SharedStore.redesignMigrationKey)
    var state = LatchState(); state.isSetUp = true
    state.strictDelay = 600; state.lenientDelay = 3600
    let limit = AppLimit(name: "Legacy", selection: tokens(["legacy"], ["legacy-category"], ["legacy.site"]),
        minutesPerDay: 45, weekdayMinutes: [2: 30], wakeDelayMinutes: 20,
        split: LimitSplit(cutoffMinutes: 720, beforeMinutes: 15, carryUnused: true),
        extraTime: LimitExtraTime(minutesPerUse: 5, usesPerDay: 2, waitMinutes: 10))
    state.limits = [limit]
    state.wakeRule.enabled = true; state.wakeRule.waitMinutes = 90
    state.wakeRule.scope.selection = tokens(["global-wake"])
    state.sleepRule.enabled = true; state.sleepRule.scope.selection = tokens(["global-sleep"])
    state.preventUnlockAt = monday.addingTimeInterval(120)
    state.passwordViewUnlockAt = monday.addingTimeInterval(240)
    state.schedules = [BlockSchedule(name: "Old schedule", mode: .blockSelected, selection: tokens(["old"]),
        startMinutes: 1320, endMinutes: 360, recurrence: .weekly([2]))]
    state.pending = [PendingChange(createdAt: monday.addingTimeInterval(-300),
        appliesAt: monday.addingTimeInterval(1200), direction: .lenient, summary: "Old pending",
        action: .setGroupWakeDelay(id: limit.id, minutes: 5)),
        PendingChange(createdAt: monday, appliesAt: monday.addingTimeInterval(2400),
        direction: .lenient, summary: "Old singleton edit", action: .setWakeRule(state.wakeRule))]
    return state
}

scenario("actual initial migration is additive, one-shot, preserves all legacy fields and deadlines") {
    let legacy = eligibleLegacy()
    let proposed = [group("New group", tokens(["extra"]))]
    expect(SharedStore.canSetUpInitialDayNight(in: migrationDefaults, state: legacy), "eligible upgrade rejected")
    guard var updated = SharedStore.initialDayNightState(proposed, state: legacy, in: migrationDefaults) else {
        expect(false, "actual migration helper rejected eligible setup"); return
    }
    expect(updated.dayNightSetupDone && updated.dayNightGroups == proposed, "migration didn't consume setup in same state")
    expect(updated.pending == legacy.pending, "pending identity/direction/deadlines changed")
    expect(updated.limits == legacy.limits && updated.wakeRule == legacy.wakeRule
        && updated.sleepRule == legacy.sleepRule, "legacy limits or singleton gates changed")
    expect(!SharedStore.canSetUpInitialDayNight(in: migrationDefaults, state: updated), "one-shot eligibility remained open")
    expect(SharedStore.initialDayNightState(proposed, state: updated, in: migrationDefaults) == nil, "second immediate setup accepted")
    let reloaded = try JSONDecoder().decode(LatchState.self, from: JSONEncoder().encode(updated))
    expect(!SharedStore.canSetUpInitialDayNight(in: migrationDefaults, state: reloaded), "reload restored immediate setup allowance")
    updated.dayNightGroups = []; updated.dayNightSetupDone = false
    expect(try canonical(updated) == canonical(legacy), "migration mutated another legacy configuration field")
    expect(SharedStore.defaults.writes == 0 && DeviceActivityCenter.started.isEmpty,
           "pure helper touched runtime/monitors")
}

scenario("actual initial migration eligibility and collection validation") {
    let proposed = [group("New", tokens(["app"]))]
    for reason in ["fresh", "done", "existing", "unmigrated", "welcomed", "recovery"] {
        var state = eligibleLegacy()
        switch reason {
        case "fresh": state.isSetUp = false
        case "done": state.dayNightSetupDone = true
        case "existing": state.dayNightGroups = proposed
        case "unmigrated": migrationDefaults.set(false, forKey: SharedStore.redesignMigrationKey)
        case "welcomed": migrationDefaults.set(true, forKey: SharedStore.redesignWelcomeKey)
        default: migrationDefaults.set(true, forKey: "latch.stateRecoveryNeeded")
        }
        expect(!SharedStore.canSetUpInitialDayNight(in: migrationDefaults, state: state), "eligibility ignores \(reason)")
        expect(SharedStore.initialDayNightState(proposed, state: state, in: migrationDefaults) == nil, "immediate migration bypasses \(reason)")
    }
    let legacy = eligibleLegacy()
    expect(SharedStore.initialDayNightState([], state: legacy, in: migrationDefaults) == nil, "empty setup consumes one-shot")
    let invalid = group("Category", tokens([], ["cat"]))
    let fallback = group("Other", mode: .allOtherApps)
    expect(SharedStore.initialDayNightState([invalid, fallback], state: legacy, in: migrationDefaults) == nil, "migration bypasses category/fallback validation")
}

scenario("latest wake ceiling releases untapped and running gates independently by weekday") {
    var first = group("Morning", tokens(["app"]), wait: 240)
    first.wakeLatestMinutes = 12 * 60
    let before = date("2026-10-05 11:59:59"), noon = date("2026-10-05 12:00:00")
    expect(DayNightWake.status(group: first, at: before, guardedNow: before) == .needsTap, "ceiling released early")
    expect(DayNightWake.status(group: first, at: noon, guardedNow: noon) == .awake, "untapped gate didn't release")
    let later = noon.addingTimeInterval(4 * 3600)
    let entry = DayNightWake.Entry(day: SharedStore.dayKey(for: noon), epoch: first.wakeEpoch, release: later)
    SharedStore.defaults.set(try JSONEncoder().encode([first.id.uuidString: entry]), forKey: runtimeKey)
    expect(DayNightWake.status(group: first, at: before, guardedNow: before) == .waiting(later), "running wait shortened before ceiling")
    expect(DayNightWake.status(group: first, at: noon, guardedNow: noon) == .awake, "running wait ignored calendar ceiling")
    var second = first; second.id = UUID(); second.wakeLatestMinutes = 13 * 60
    expect(DayNightWake.status(group: second, at: noon, guardedNow: noon) == .needsTap, "other group's ceiling leaked")
    first.weekdayWakeTimings[2] = WakeDayTiming(startMinutes: 0, waitMinutes: 240, latestMinutes: 14 * 60)
    expect(DayNightWake.status(group: first, at: noon, guardedNow: noon) == .waiting(later), "weekday override ignored")
    let two = date("2026-10-05 14:00:00")
    expect(DayNightWake.status(group: first, at: two, guardedNow: two) == .awake, "weekday ceiling didn't release")
    var state = LatchState(); state.dayNightGroups = [first, second]
    expect(MonitoringBudget.dayNightBoundaryMinutes(state: state).isSuperset(of: [0, 720, 780, 840]), "cutoff background boundaries missing")
}
scenario("fall-back ceiling releases at first 01:30 and stays released at second 01:15") {
    expect(TimeZone.current.identifier == "America/New_York", "DST fixture zone not configured")
    let before = offsetDate("2026-11-01T01:29:59-04:00")
    let firstCap = offsetDate("2026-11-01T01:30:00-04:00")
    let secondQuarter = offsetDate("2026-11-01T01:15:00-05:00")
    expect(secondQuarter > firstCap, "repeated-hour fixture is not chronologically later")
    expect(Calendar.current.component(.hour, from: secondQuarter) == 1
        && Calendar.current.component(.minute, from: secondQuarter) == 15,
        "second-hour fixture does not display 01:15")
    let timing = WakeDayTiming(startMinutes: 0, waitMinutes: 240, latestMinutes: 90)
    expect(!timing.ceilingReached(on: before), "first 01:30 cap crossed early")
    expect(timing.ceilingReached(on: firstCap), "cap chose second 01:30 rather than first")
    expect(timing.ceilingReached(on: secondQuarter), "cap rolled back at second 01:15")
    var named = group("Repeated hour", tokens(["app"]), wait: 240)
    named.wakeLatestMinutes = 90
    for running in [false, true] {
        SharedStore.defaults.storage.removeObject(forKey: runtimeKey)
        let release = offsetDate("2026-11-01T04:00:00-05:00")
        if running {
            let entry = DayNightWake.Entry(day: DayNightWake.cycle(group: named, at: before),
                                          epoch: named.wakeEpoch, release: release)
            SharedStore.defaults.storage.set(try JSONEncoder().encode([named.id.uuidString: entry]),
                                            forKey: runtimeKey)
        }
        let raw = SharedStore.defaults.storage.data(forKey: runtimeKey)
        let writes = SharedStore.defaults.writes
        expect(DayNightWake.status(group: named, at: before, guardedNow: before)
            == (running ? .waiting(release) : .needsTap), "pre-cap status wrong (running=\(running))")
        for moment in [firstCap, secondQuarter] {
            expect(DayNightWake.status(group: named, at: moment, guardedNow: moment) == .awake,
                   "named gate reblocked/missed cap (running=\(running), at=\(moment))")
            expect(SharedStore.defaults.storage.data(forKey: runtimeKey) == raw,
                   "DST status changed saved runtime/deadline")
        }
        expect(SharedStore.defaults.writes == writes, "DST status performed preference writes")
    }
}

scenario("spring-forward skipped 02:30 ceiling releases at next valid 03:00") {
    let before = offsetDate("2026-03-08T01:59:59-05:00")
    let nextValid = offsetDate("2026-03-08T03:00:00-04:00")
    expect(nextValid.timeIntervalSince(before) == 1, "spring fixture did not skip the 02 hour")
    let timing = WakeDayTiming(startMinutes: 0, waitMinutes: 240, latestMinutes: 150)
    expect(!timing.ceilingReached(on: before), "missing 02:30 cap released before jump")
    expect(timing.ceilingReached(on: nextValid), "missing 02:30 cap did not use next valid time")
    var named = group("Skipped hour", tokens(["app"]), wait: 240)
    named.wakeLatestMinutes = 150
    for running in [false, true] {
        SharedStore.defaults.storage.removeObject(forKey: runtimeKey)
        let release = offsetDate("2026-03-08T06:00:00-04:00")
        if running {
            let entry = DayNightWake.Entry(day: DayNightWake.cycle(group: named, at: before),
                                          epoch: named.wakeEpoch, release: release)
            SharedStore.defaults.storage.set(try JSONEncoder().encode([named.id.uuidString: entry]),
                                            forKey: runtimeKey)
        }
        let raw = SharedStore.defaults.storage.data(forKey: runtimeKey)
        let writes = SharedStore.defaults.writes
        expect(DayNightWake.status(group: named, at: before, guardedNow: before)
            == (running ? .waiting(release) : .needsTap), "pre-jump status wrong (running=\(running))")
        for moment in [nextValid, nextValid.addingTimeInterval(15 * 60)] {
            expect(DayNightWake.status(group: named, at: moment, guardedNow: moment) == .awake,
                   "skipped-hour named ceiling not released (running=\(running))")
            expect(SharedStore.defaults.storage.data(forKey: runtimeKey) == raw,
                   "spring status changed saved runtime/deadline")
        }
        expect(SharedStore.defaults.writes == writes, "spring status performed preference writes")
    }
}

scenario("cutoff validation and loosening classification preserve old nil defaults") {
    var original = group("Original", tokens(["app"]))
    var capped = original; capped.wakeLatestMinutes = 720
    expect(capped.timingsAreValid && !capped.timingNoLooser(than: original), "adding a release ceiling wasn't looser")
    expect(original.timingNoLooser(than: capped), "removing a ceiling wasn't tighter")
    var invalid = capped; invalid.wakeLatestMinutes = 0
    expect(!invalid.timingsAreValid, "cutoff at/before start accepted")
    invalid.wakeLatestMinutes = 1439
    expect(!invalid.timingsAreValid, "cutoff without minimum callback span accepted")
    var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
    raw.removeValue(forKey: "wakeLatestMinutes")
    original = try JSONDecoder().decode(DayNightGroup.self, from: JSONSerialization.data(withJSONObject: raw))
    expect(original.wakeLatestMinutes == nil, "old group gained a cutoff")
    let oldTiming = try JSONDecoder().decode(WakeDayTiming.self, from: Data("{\"startMinutes\":0,\"waitMinutes\":10}".utf8))
    expect(oldTiming.latestMinutes == nil, "old weekday gained a cutoff")
}

SharedStore.defaults.storage.removePersistentDomain(forName: SharedStore.defaults.suite)
migrationDefaults.removePersistentDomain(forName: migrationSuite)
for failure in failures { print("FAIL: \(failure)") }
print("Day/night checks: \(scenarios) scenarios, \(assertions) assertions, \(failures.count) failures")
print("Actual model/policy/runtime/migration bodies; temporary UserDefaults; coordination, tokens, shields and monitor effects stubbed")
if !failures.isEmpty { exit(1) }
'''

source = "\n".join([infrastructure, migration, "}", models, phrases, budget,
                    block(engine, "enum GlobalWakeStatus:"), policy, runtime, checks])
with tempfile.TemporaryDirectory(prefix="demora-day-night-harness-") as directory:
    source_path = Path(directory) / "main.swift"
    binary_path = Path(directory) / "checks"
    source_path.write_text(source)
    subprocess.run(["xcrun", "swiftc", str(source_path), "-o", str(binary_path)], check=True)
    # Only this child process uses the DST fixture zone; the host setting is
    # untouched. Calendar.current and Date() otherwise remain production APIs.
    subprocess.run([str(binary_path)], check=True,
                   env={**os.environ, "TZ": "America/New_York"})
