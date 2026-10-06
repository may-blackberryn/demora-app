#!/usr/bin/env python3
"""Run production monitoring planner and registration bodies on macOS.

Only Apple framework types/opaque tokens, clock and XPC are substituted. The
registration adapter models occupancy, replacement, capacity races and explicit
OS errors, not DeviceActivity delivery or the device's actual cap. Defaults use
a disposable random local suite, never an App Group. No Xcode build is run.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def portable(source):
    for framework in ["FamilyControls", "ManagedSettings", "DeviceActivity"]:
        source = source.replace(f"import {framework}\n", "")
    return source


def block(source, signature):
    """Extract the complete production declaration without rewriting branches."""
    start = source.index(signature)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


infrastructure = r'''
import Foundation
struct FamilyActivitySelection: Codable, Equatable {
    var includeEntireCategory = false
    var applicationTokens: Set<String> = []
    var categoryTokens: Set<String> = []
    var webDomainTokens: Set<String> = []
}
func tr(_ value: String) -> String { value }
enum TimeGuard {
    static var date = Date()
    static func now() -> Date { date }
}
enum SharedStore {
    static var state = LatchState()
    static var enforcementDegraded = false
    static var simulating = false
    static let suite = "demora-monitoring-budget-tests-" + UUID().uuidString
    static let defaults = UserDefaults(suiteName: suite)!
    static func loadState() -> LatchState { state }
}
struct DeviceActivityName: Hashable {
    var rawValue: String
    init(_ value: String) { rawValue = value }
}
struct DeviceActivitySchedule {
    var intervalStart: DateComponents
    var intervalEnd: DateComponents
    var repeats: Bool
    var warningTime: DateComponents? = nil
}
struct DeviceActivityEvent {
    struct Name: Hashable {
        var rawValue: String
        init(_ value: String) { rawValue = value }
    }
}
struct DeviceActivityCenter {
    enum MonitoringError: Error {
        case excessiveActivities, unauthorized, intervalTooShort, invalidDateComponents
    }
    static var running: Set<String> = []
    static var stopped: [String] = []
    static var attempts: [String] = []
    static var faults: [MonitoringError] = []
    static var beforeStart: (() -> Void)?
    static var events: [String: [DeviceActivityEvent.Name: DeviceActivityEvent]] = [:]
    var activities: [DeviceActivityName] { Self.running.sorted().map(DeviceActivityName.init) }
    func stopMonitoring(_ names: [DeviceActivityName]) {
        Self.stopped += names.map(\.rawValue)
        Self.running.subtract(names.map(\.rawValue))
    }
    func startMonitoring(_ name: DeviceActivityName, during schedule: DeviceActivitySchedule,
                         events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]) throws {
        Self.attempts.append(name.rawValue)
        let hook = Self.beforeStart; Self.beforeStart = nil; hook?()
        if !Self.faults.isEmpty { throw Self.faults.removeFirst() }
        guard Self.running.contains(name.rawValue) || Self.running.count < 20
        else { throw MonitoringError.excessiveActivities }
        Self.running.insert(name.rawValue); Self.events[name.rawValue] = events
    }
    static func reset() {
        running = []; stopped = []; attempts = []; faults = []; beforeStart = nil; events = [:]
    }
}
'''

checks = r'''
var scenarios = 0, assertions = 0
var failures: [String] = []
var label = ""
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !condition() { failures.append("\(label): \(message)") }
}
func scenario(_ name: String, _ body: () throws -> Void) {
    label = name; scenarios += 1
    DeviceActivityCenter.reset(); SharedStore.state = LatchState()
    SharedStore.enforcementDegraded = false
    SharedStore.simulating = false
    SharedStore.defaults.removePersistentDomain(forName: SharedStore.suite)
    TimeGuard.date = Date()
    do { try body() } catch { failures.append("\(name): unexpected error \(error)") }
}
let apps = FamilyActivitySelection(applicationTokens: ["opaque-app"])
let now = Date()
func schedule(_ name: String = "Rule", start: Int = 600, end: Int = 660,
              recurrence: Recurrence = .daily) -> BlockSchedule {
    BlockSchedule(name: name, mode: .blockSelected, selection: apps,
                  startMinutes: start, endMinutes: end, recurrence: recurrence)
}
func limit(_ split: LimitSplit? = nil, wake: Int? = nil,
           extra: LimitExtraTime? = nil, minutes: Int = 30) -> AppLimit {
    AppLimit(name: "Budget", selection: apps, minutesPerDay: minutes,
             wakeDelayMinutes: wake, split: split, extraTime: extra)
}
func pending(_ action: ChangeAction, offset: TimeInterval = 600) -> PendingChange {
    PendingChange(createdAt: now, appliesAt: now.addingTimeInterval(offset),
                  direction: .stricter, summary: "Test", action: action)
}
func stateWithSchedules(_ count: Int) -> LatchState {
    var value = LatchState(); value.schedules = (0..<count).map { schedule("Rule \($0)") }
    return value
}
func required(_ state: LatchState, running: Set<String> = []) -> Int {
    MonitoringBudget.required(state: state, running: running, at: now, guardedNow: now)
}
func encoded(_ state: LatchState) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return try encoder.encode(state)
}
func parsed(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
let activitySchedule = DeviceActivitySchedule(intervalStart: DateComponents(hour: 1),
    intervalEnd: DateComponents(hour: 2), repeats: true)

scenario("20 accepted, 21 rejected, notice lifecycle") {
    let twenty = stateWithSchedules(20), twentyOne = stateWithSchedules(21)
    expect(required(twenty) == 20, "20 count")
    expect(MonitorRegistration.admit(state: twenty, running: []), "20 rejected")
    expect(!MonitorRegistration.admit(state: twentyOne, running: []), "21 admitted")
    expect(MonitorRegistration.rejectionMessage?.contains("21") == true, "missing capacity detail")
    expect(!SharedStore.enforcementDegraded, "admission rejection claimed broken enforcement")
    MonitorRegistration.clearRejection()
    expect(MonitorRegistration.rejectionMessage == nil, "notice not cleared")
}
scenario("weekly consolidation and exact registration bounds") {
    let daily = MonitoringBudget.windows(prefix: "w", start: 600, end: 660, recurrence: .daily)
    let weekly = MonitoringBudget.windows(prefix: "w", start: 600, end: 660, recurrence: .weekly([1,2,3,4,5,6,7]))
    expect(daily == weekly && daily.count == 1, "weekday multiplication")
    expect(daily.first?.start == DateComponents(hour: 10, minute: 0), "start drift")
    expect(daily.first?.end == DateComponents(hour: 11, minute: 0), "end drift")
    expect(MonitoringBudget.windows(prefix: "w", start: 600, end: 660, recurrence: .weekly([])).isEmpty,
           "empty weekdays consume a slot")
    expect(MonitoringBudget.windows(prefix: "w", start: 600, end: 601, recurrence: .daily).first?.end.minute == 15,
           "short window not padded to OS minimum")
}
scenario("overnight anchors and skipped weekdays") {
    let rule = schedule(start: 22*60, end: 7*60, recurrence: .weekly([2]))
    let windows = MonitoringBudget.windows(prefix: "w", start: rule.startMinutes,
                                           end: rule.endMinutes, recurrence: rule.recurrence)
    expect(windows.count == 2, "overnight not two shared activities")
    expect(windows.allSatisfy { $0.start.weekday == nil && $0.end.weekday == nil }, "OS weekday-specific windows")
    expect(rule.isActive(at: parsed("2026-10-05T22:00:00-04:00")), "Monday start not active")
    expect(rule.isActive(at: parsed("2026-10-06T06:59:00-04:00")), "Tuesday tail lost Monday anchor")
    expect(!rule.isActive(at: parsed("2026-10-06T07:00:00-04:00")), "end applied late")
    expect(!rule.isActive(at: parsed("2026-10-06T22:00:00-04:00")), "skipped weekday callback activates rule")
    expect(!rule.isActive(at: parsed("2026-10-05T21:59:00-04:00")), "warning applies early")
}
scenario("DST spring and repeated fall hour use calendar anchors") {
    let rule = schedule(start: 22*60, end: 7*60, recurrence: .weekly([7]))
    for date in ["2026-03-08T03:30:00-04:00", "2026-11-01T01:30:00-04:00", "2026-11-01T01:30:00-05:00"] {
        expect(rule.isActive(at: parsed(date)), "overnight inactive at \(date)")
    }
    expect(!rule.isActive(at: parsed("2026-03-08T07:00:00-04:00")), "spring end not exclusive")
    expect(!rule.isActive(at: parsed("2026-11-01T07:00:00-05:00")), "fall end not exclusive")
}
scenario("monthly shapes preserve calendar components") {
    let day = MonitoringBudget.windows(prefix: "m", start: 60, end: 120, recurrence: .monthlyDay(15))
    let ordinal = MonitoringBudget.windows(prefix: "m", start: 60, end: 120,
                                           recurrence: .monthlyOrdinal(weekday: 2, ordinal: 3))
    expect(day.count == 1 && day[0].start.day == 15 && day[0].end.day == 15, "monthly day lost")
    expect(ordinal.count == 1 && ordinal[0].start.weekday == 2 && ordinal[0].end.weekdayOrdinal == 3,
           "ordinal lost")
}
scenario("late weekly overnight retains weekday-spanning registration") {
    let windows = MonitoringBudget.windows(prefix: "late", start: 23*60+50, end: 6*60,
                                           recurrence: .weekly([2, 6]))
    expect(Set(windows.map(\.name)) == ["late-w2", "late-w6"], "late weekday names not retained")
    for window in windows {
        let day = window.name == "late-w2" ? 2 : 6
        expect(window.start.weekday == day && window.end.weekday == day % 7 + 1, "late window doesn't span next weekday")
        expect(window.start.hour == 23 && window.start.minute == 50 && window.end.hour == 6 && window.end.minute == 0,
               "late overnight bounds drift")
    }
    var state = LatchState(); state.schedules = [schedule(start: 1430, end: 360, recurrence: .weekly([2,6]))]
    expect(required(state) == 2, "late weekly budget differs from actual registrations")
    state.schedules[0].recurrence = .weekly(Set(1...7))
    expect(required(state) == 7, "late weekly all-days count omitted")
}
scenario("shared split buckets and distinct configurations") {
    let two = LimitSplit(cutoffMinutes: 720, beforeMinutes: 10, carryUnused: false)
    let three = LimitSplit(cutoffMinutes: 720, beforeMinutes: 10, carryUnused: false,
                           secondCutoffMinutes: 1080, middleMinutes: 10)
    var state = LatchState(); state.limits = [limit(two), limit(two)]
    expect(MonitoringBudget.splitNames(state: state) == ["limit-part-early-0-12", "limit-part-late-12-23"],
           "identical limits don't share buckets")
    state.limits.append(limit(three))
    expect(MonitoringBudget.splitNames(state: state).count == 4, "three portion buckets")
    var carry = three; carry.carryUnused = true
    state.limits.append(limit(carry))
    expect(MonitoringBudget.splitNames(state: state).contains("limit-part-middle-carry-0-18"), "carry bucket missing")
    expect(MonitoringBudget.splitNames(state: state).count == 5, "carry duplicates early/late")
    expect(required(state) == 6, "daily monitor not shared")
    expect(LimitFeatures.expectedSplitActivityNames(state: state) == MonitoringBudget.splitNames(state: state),
           "production expected split names differ")
}
scenario("latent wake extra-time and free tracking") {
    let extra = LimitExtraTime(minutesPerUse: 5, usesPerDay: 3, waitMinutes: 10)
    let item = limit(wake: 10, extra: extra)
    var state = LatchState(); state.limits = [item]
    state.exemptions = [ExemptSchedule(name: "Tomorrow", startMinutes: 600, endMinutes: 660, recurrence: .weekly([2]))]
    state.wakeRule.enabled = true; state.wakeRule.waitMinutes = 10
    var group = DayNightGroup(name: "Morning"); group.waitMinutes = 10
    state.dayNightGroups = [group, group]
    let names = MonitoringBudget.profile(state: state, at: now)
    for name in ["latch.freewin", "global-wake-release", "day-night-release",
                 "limit-wake-release-" + item.id.uuidString, "limit-extra-release-" + item.id.uuidString] {
        expect(names.contains(name), "latent slot missing: \(name)")
    }
    expect(names.filter { $0.hasPrefix("day-night-release") }.count == 1, "shared day/night release duplicated")
    expect(names.filter { $0.hasPrefix("day-night-boundary-") }.count == 2, "day/night boundaries not deduplicated")
    expect(DayNightWake.boundaryMinutes(state: state) == MonitoringBudget.dayNightBoundaryMinutes(state: state),
           "runtime/planner day/night boundaries diverge")
}
scenario("authenticated extra time needs no wait monitor") {
    for step in [LimitExtraStep(minutes: 5, waitMinutes: 10, passwordPolicyID: UUID()),
                 LimitExtraStep(minutes: 5, waitMinutes: 10, phrasePolicyID: UUID()),
                 LimitExtraStep(minutes: 5, waitMinutes: 10, contactRequired: true),
                 LimitExtraStep(minutes: 5, waitMinutes: 0)] {
        var extra = LimitExtraTime(minutesPerUse: 5, usesPerDay: 1, waitMinutes: 10); extra.steps = [step]
        var state = LatchState(); state.limits = [limit(extra: extra)]
        expect(!MonitoringBudget.profile(state: state).contains(where: { $0.hasPrefix("limit-extra-release-") }),
               "authenticated/instant grant reserves timer")
    }
}
scenario("weekday-only allowance still reserves free tracking") {
    var item = limit(minutes: 0); item.weekdayMinutes = [2: 10]
    var state = LatchState(); state.limits = [item]
    state.exemptions = [ExemptSchedule(name: "Free", startMinutes: 60, endMinutes: 120)]
    expect(MonitoringBudget.profile(state: state).contains("latch.freewin"), "weekday allowance missed")
    state.limits[0].weekdayMinutes = [:]
    expect(!MonitoringBudget.profile(state: state).contains("latch.freewin"), "zero allowance needs tracking")
}
scenario("pending add conjunction and reordered approvals") {
    let addLimit = pending(.addLimit(limit()))
    let addFree = pending(.addExemption(ExemptSchedule(name: "Free", startMinutes: 60, endMinutes: 120)), offset: 1200)
    var state = LatchState(); state.pending = [addLimit, addFree]
    let reserved = MonitoringBudget.reservations(state: state, at: now, guardedNow: now)
    expect(reserved.contains("latch.freewin"), "conjunction not reserved")
    expect(reserved.contains(addLimit.activityName) && reserved.contains(addFree.activityName), "pending timer missing")
    for order in [[addLimit, addFree], [addFree, addLimit]] {
        var applied = LatchState()
        for change in order {
            applied = MonitoringBudget.project(change.action, onto: applied, id: change.id, at: now)
            expect(MonitoringBudget.profile(state: applied, at: now).isSubset(of: reserved), "approval order exceeds reservation")
        }
    }
    state.pending.reverse()
    expect(MonitoringBudget.reservations(state: state, at: now, guardedNow: now) == reserved, "input order changes reservations")
}
scenario("removal cannot promise room for early add approval") {
    var state = stateWithSchedules(19)
    let remove = pending(.removeSchedule(id: state.schedules[0].id), offset: 60)
    let add = pending(.addSchedule(schedule("Future")), offset: 120)
    state.pending = [remove, add]
    expect(required(state) == 22, "pending removal credited capacity early")
    expect(!MonitorRegistration.admit(state: state, running: []), "overbudget conjunction admitted")
}
scenario("due timers not reserved, projected sessions have stable identity") {
    let change = pending(.startSession(name: "Free", kind: .free, selection: apps, minutes: 30), offset: 0)
    var state = LatchState(); state.limits = [limit()]; state.pending = [change]
    let reserved = MonitoringBudget.reservations(state: state, at: now, guardedNow: now)
    expect(!reserved.contains(change.activityName), "already-due timer consumes slot")
    expect(reserved.contains("session-" + change.id.uuidString), "session identity unstable")
    expect(reserved.contains("latch.freewin"), "future session tracking omitted")
    expect(MonitoringBudget.reservations(state: state, at: now, guardedNow: now) == reserved, "random session reservation")
}
scenario("pending replacement preserves old and new split buckets") {
    let old = limit(LimitSplit(cutoffMinutes: 720, beforeMinutes: 10, carryUnused: false))
    var new = old; new.split!.cutoffMinutes = 600
    var state = LatchState(); state.limits = [old]; state.pending = [pending(.configureLimit(new))]
    let names = MonitoringBudget.reservations(state: state, at: now, guardedNow: now)
    expect(MonitoringBudget.splitNames(state: state).isSubset(of: names), "old buckets released early")
    let projected = MonitoringBudget.project(.configureLimit(new), onto: state)
    expect(MonitoringBudget.splitNames(state: projected).isSubset(of: names), "new buckets not reserved")
    expect(!MonitoringBudget.isRepair(.configureLimit(new), state: state), "bucket replacement bypasses admission")
}
scenario("malformed zero-minute pending session still reserves cleanup") {
    let change = pending(.startSession(name: "Zero", kind: .block, selection: apps, minutes: 0))
    var state = LatchState(); state.pending = [change]
    let names = MonitoringBudget.reservations(state: state, at: now, guardedNow: now)
    expect(names.contains(change.activityName), "zero session loses pending wake")
    expect(names.contains("session-" + change.id.uuidString), "zero duration loses actual cleanup slot")
    expect(names.count == 2, "zero duration count disagrees with actual registrations")
}
scenario("stale runtime names count, echoes optional, release generations normalize") {
    var state = LatchState(); state.limits = [limit()]
    expect(required(state, running: ["stale-enforcement", "echo-0", "echo-1"]) == 2, "stale enforcement omitted/echo counted")
    expect(required(state, running: ["day-night-release-a"]) == 2, "one release reservation missing")
    expect(required(state, running: ["day-night-release-a", "day-night-release-b"]) == 3, "duplicate release occupancy omitted")
    expect(required(state, running: [LatchConstants.dailyActivityName]) == 1, "runtime/profile overlap counted twice")
}
scenario("expired planned and session entries consume no slots") {
    var state = LatchState(); state.limits = [limit()]
    state.planned = [PlannedWindow(name: "Past", kind: .free, selection: apps,
                                 startsAt: now.addingTimeInterval(-600), endsAt: now)]
    state.sessions = [BlockSession(name: "Past", kind: .free, selection: apps,
                                  startedAt: now.addingTimeInterval(-600), endsAt: now)]
    expect(required(state) == 1, "expired entries retained")
    state.planned[0].endsAt = now.addingTimeInterval(600)
    expect(required(state) == 3, "future planned free/tracking not reserved")
}
scenario("shared contributors can repair equal profile; missing targets cannot") {
    let split = LimitSplit(cutoffMinutes: 720, beforeMinutes: 10, carryUnused: false)
    var state = stateWithSchedules(21); state.limits = [limit(split), limit(split)]
    let action = ChangeAction.removeLimit(id: state.limits[0].id)
    expect(MonitoringBudget.isRepair(action, state: state), "shared contributor trapped")
    expect(MonitorRegistration.admit(state: state, running: [], repair: MonitoringBudget.isRepair(action, state: state)), "repair rejected")
    for action in [ChangeAction.removeLimit(id: UUID()), .removeSchedule(id: UUID()), .removeExemption(id: UUID()),
                   .removePlanned(id: UUID()), .endSessionEarly(id: UUID()), .removeDayNightGroup(id: UUID())] {
        expect(!MonitoringBudget.isRepair(action, state: state), "missing target qualifies as repair")
    }
    expect(!MonitoringBudget.isRepair(.addSchedule(schedule()), state: state), "addition is repair")
    expect(!MonitoringBudget.isRepair(.updateLimitMinutes(id: state.limits[0].id, minutes: 0), state: state), "budget change bypasses admission")
}
scenario("explicit disable repairs only when no new monitor names") {
    let old = limit(LimitSplit(cutoffMinutes: 720, beforeMinutes: 10, carryUnused: false), wake: 10,
                    extra: LimitExtraTime(minutesPerUse: 5, usesPerDay: 1, waitMinutes: 10))
    var state = LatchState(); state.limits = [old]
    for field in ["split", "wake", "extra"] {
        var changed = old
        switch field { case "split": changed.split = nil; case "wake": changed.wakeDelayMinutes = nil
        default: changed.extraTime = nil }
        expect(MonitoringBudget.isRepair(.configureLimit(changed), state: state), "\(field) disable rejected")
    }
    var mixed = old; mixed.wakeDelayMinutes = nil; mixed.split!.cutoffMinutes = 600
    expect(!MonitoringBudget.isRepair(.configureLimit(mixed), state: state), "disable with replacement gets repair bypass")
    expect(MonitoringBudget.isRepair(.setGroupWakeDelay(id: old.id, minutes: nil), state: state), "focused disable rejected")
}
scenario("weekday boundary dedup and latent custom waits") {
    var item = limit(wake: 0)
    item.wakeSchedule = LimitWakeSchedule(startMinutes: 480,
        dayTimings: [2: WakeDayTiming(startMinutes: 540, waitMinutes: 20)])
    var group = DayNightGroup(name: "Timed")
    group.waitMinutes = 0; group.wakeStartMinutes = 480
    group.weekdayWakeTimings[7] = WakeDayTiming(startMinutes: 540, waitMinutes: 35)
    group.scope.selection = apps
    var state = LatchState(); state.limits = [item]; state.dayNightGroups = [group]
    expect(MonitoringBudget.dayNightBoundaryMinutes(state: state) == [0,480,540], "duplicate per-day/group starts use extra slots")
    let names = MonitoringBudget.profile(state: state, at: now)
    expect(names.contains("day-night-release"), "zero default missed positive per-day group wait")
    expect(names.contains("limit-wake-release-" + item.id.uuidString), "zero default missed positive per-day limit wait")
    expect(names.filter { $0.hasPrefix("day-night-boundary-") }.count == 3, "boundary plan doesn't match starts")
    var changed = item.wakeSchedule!; changed.dayTimings[4] = WakeDayTiming(startMinutes: 600, waitMinutes: 0)
    let action = ChangeAction.setGroupWakeSchedule(id: item.id, minutes: 0, schedule: changed)
    state.pending = [pending(action)]
    expect(MonitoringBudget.reservations(state: state, at: now, guardedNow: now).contains("day-night-boundary-600-0"), "pending daily start not reserved")
    expect(!MonitoringBudget.isRepair(action, state: state), "new boundary bypasses admission")
    expect(MonitoringBudget.isRepair(.setGroupWakeSchedule(id: item.id, minutes: nil, schedule: changed), state: state), "focused disable trapped overbudget user")
}
scenario("planner never writes defaults, applies pending or mutates state") {
    var state = stateWithSchedules(2); state.limits = [limit(wake: 10)]
    state.pending = [pending(.removeLimit(id: state.limits[0].id))]
    let before = try encoded(state)
    SharedStore.defaults.set("sentinel", forKey: "usage")
    let defaultsBefore = SharedStore.defaults.dictionaryRepresentation()
    _ = MonitoringBudget.profile(state: state); _ = required(state)
    _ = MonitoringBudget.project(state.pending[0].action, onto: state)
    _ = MonitoringBudget.isRepair(state.pending[0].action, state: state)
    let after = try encoded(state)
    expect(after == before, "planner mutated state/deadlines")
    expect(NSDictionary(dictionary: SharedStore.defaults.dictionaryRepresentation()).isEqual(to: defaultsBefore), "planner persisted effects")
    expect(DeviceActivityCenter.attempts.isEmpty && DeviceActivityCenter.stopped.isEmpty, "planner performs XPC")
}
scenario("actual window registration matches planner and expected helper") {
    for recurrence in [Recurrence.daily, .weekly([2,4]), .weekly([]), .monthlyDay(15),
                       .monthlyOrdinal(weekday: 2, ordinal: 3)] {
        for (start, end) in [(600,660), (1320,420), (1430,360)] {
            DeviceActivityCenter.reset()
            let rule = schedule(start: start, end: end, recurrence: recurrence)
            var state = LatchState(); state.schedules = [rule]
            let expected = MonitoringBudget.windowNames(state: state, at: now)
            ChangeEngine.registerForTest(rule)
            expect(DeviceActivityCenter.running == expected, "registered names differ from planner")
            expect(ChangeEngine.expectedForTest(state) == expected, "repair expected helper differs")
            expect(!SharedStore.enforcementDegraded, "fitting registration degraded")
        }
    }
}

scenario("echo reserved capacity yields before OS call") {
    SharedStore.state = stateWithSchedules(20)
    do { try MonitorRegistration.start(.init("echo-0"), during: activitySchedule)
         expect(false, "echo consumed reserved slot") } catch {}
    expect(DeviceActivityCenter.attempts.isEmpty, "denied echo called OS")
    expect(!SharedStore.enforcementDegraded, "optional echo degrades enforcement")
}
scenario("echo last available slot, replacement not extra slot") {
    SharedStore.state = stateWithSchedules(19)
    try MonitorRegistration.start(.init("echo-0"), during: activitySchedule)
    do { try MonitorRegistration.start(.init("echo-1"), during: activitySchedule)
         expect(false, "second echo oversubscribes reservation") } catch {}
    try MonitorRegistration.start(.init("echo-0"), during: activitySchedule)
    expect(DeviceActivityCenter.attempts == ["echo-0", "echo-0"], "replacement not allowed")
}
scenario("enforcement capacity retry evicts echoes only") {
    DeviceActivityCenter.running = Set((0..<19).map { "enforcement-\($0)" }).union(["echo-0"])
    try MonitorRegistration.start(.init("required-new"), during: activitySchedule)
    expect(DeviceActivityCenter.stopped == ["echo-0"], "non-echo eviction")
    expect(DeviceActivityCenter.running.contains("required-new") && DeviceActivityCenter.running.count == 20, "registration failed")
    expect(!SharedStore.enforcementDegraded, "successful retry marked degraded")
}
scenario("full enforcement cannot evict enforcement") {
    DeviceActivityCenter.running = Set((0..<20).map { "enforcement-\($0)" })
    let before = DeviceActivityCenter.running
    do { try MonitorRegistration.start(.init("required-new"), during: activitySchedule)
         expect(false, "21st enforcement admitted") } catch {}
    expect(DeviceActivityCenter.running == before && DeviceActivityCenter.stopped.isEmpty, "enforcement eviction")
    expect(SharedStore.enforcementDegraded, "OS/cap failure not visible")
}
scenario("at-cap replacement forwards events without stopping anything") {
    DeviceActivityCenter.running = Set((0..<20).map { "enforcement-\($0)" })
    let event = DeviceActivityEvent.Name("real-threshold")
    try MonitorRegistration.start(.init("enforcement-0"), during: activitySchedule, events: [event: DeviceActivityEvent()])
    expect(DeviceActivityCenter.running.count == 20 && DeviceActivityCenter.stopped.isEmpty, "replacement evicts")
    expect(DeviceActivityCenter.events["enforcement-0"]?[event] != nil, "events lost")
}
for fault in [DeviceActivityCenter.MonitoringError.unauthorized, .intervalTooShort, .invalidDateComponents] {
    scenario("noncapacity fault \(fault) never evicts echo") {
        DeviceActivityCenter.running = Set((0..<19).map { "enforcement-\($0)" }).union(["echo-0"])
        DeviceActivityCenter.faults = [fault]
        do { try MonitorRegistration.start(.init("required-new"), during: activitySchedule)
             expect(false, "fault reported success") } catch {}
        expect(DeviceActivityCenter.stopped.isEmpty && DeviceActivityCenter.running.contains("echo-0"), "fault destroyed redundancy")
        expect(DeviceActivityCenter.attempts.count == 1, "noncapacity fault retried")
        expect(SharedStore.enforcementDegraded, "OS failure not degraded")
    }
}
scenario("OS capacity race retries once against fresh occupancy") {
    DeviceActivityCenter.running = Set((0..<18).map { "enforcement-\($0)" }).union(["echo-0"])
    DeviceActivityCenter.beforeStart = { DeviceActivityCenter.running.insert("racing-enforcement") }
    try MonitorRegistration.start(.init("required-new"), during: activitySchedule)
    expect(DeviceActivityCenter.attempts.count == 2, "capacity race not retried once")
    expect(DeviceActivityCenter.stopped == ["echo-0"], "fresh optional activity not evicted")
    expect(DeviceActivityCenter.running.contains("racing-enforcement"), "race evicted enforcement")
}
scenario("failed retry is bounded and visibly degraded") {
    DeviceActivityCenter.running = Set((0..<18).map { "enforcement-\($0)" }).union(["echo-0", "echo-1"])
    DeviceActivityCenter.faults = [.excessiveActivities, .excessiveActivities, .excessiveActivities]
    do { try MonitorRegistration.start(.init("required-new"), during: activitySchedule)
         expect(false, "permanent capacity fault succeeded") } catch {}
    expect(DeviceActivityCenter.attempts.count == 2, "retry loop not bounded")
    expect(DeviceActivityCenter.stopped.allSatisfy { $0.hasPrefix("echo-") }, "failed retry stops enforcement")
    expect(SharedStore.enforcementDegraded, "retry exhaustion not degraded")
}
scenario("optional OS error does not degrade or evict") {
    DeviceActivityCenter.faults = [.unauthorized]
    do { try MonitorRegistration.start(.init("echo-0"), during: activitySchedule)
         expect(false, "echo fault succeeded") } catch {}
    expect(!SharedStore.enforcementDegraded && DeviceActivityCenter.stopped.isEmpty, "optional fault has enforcement effects")
}
scenario("prior degraded signal is not cleared by success or optional failure") {
    SharedStore.enforcementDegraded = true
    try MonitorRegistration.start(.init("required"), during: activitySchedule)
    expect(SharedStore.enforcementDegraded, "success hides earlier corruption/failure")
    DeviceActivityCenter.faults = [.unauthorized]
    do { try MonitorRegistration.start(.init("echo-0"), during: activitySchedule) } catch {}
    expect(SharedStore.enforcementDegraded, "optional error cleared warning")
}
scenario("actual pending-wake capacity failure retains rules and original deadline") {
    var state = stateWithSchedules(20)
    let change = pending(.removeSchedule(id: state.schedules[0].id))
    state.pending = [change]; SharedStore.state = state
    DeviceActivityCenter.running = MonitoringBudget.windowNames(state: state, at: now)
    let stateBefore = try encoded(state), runningBefore = DeviceActivityCenter.running
    ChangeEngine.scheduleForTest(change)
    let stateAfter = try encoded(SharedStore.state)
    expect(stateAfter == stateBefore, "failed repair wake dropped pending/rules/deadline")
    expect(DeviceActivityCenter.running == runningBefore && DeviceActivityCenter.stopped.isEmpty,
           "failed repair wake evicted enforcement")
    expect(SharedStore.enforcementDegraded, "failed repair wake not surfaced")
}
SharedStore.defaults.removePersistentDomain(forName: SharedStore.suite)
for failure in failures { print("FAIL: \(failure)") }
print("Monitoring budget checks: \(scenarios) scenarios, \(assertions) assertions, \(failures.count) failures")
print("Actual planner/models/registration; isolated defaults; opaque tokens and fault-injected XPC adapter")
if !failures.isEmpty { exit(1) }
'''

engine = (ROOT / "Shared/ChangeEngine.swift").read_text()
features = (ROOT / "Shared/LimitFeatures.swift").read_text()
day_night = (ROOT / "Shared/DayNightWake.swift").read_text()
helpers = (
    "enum ChangeEngine {\n"
    + block(engine, "private static func startWindowActivities(") + "\n"
    + block(engine, "private static func expectedWindowActivityNames(")
    + "\n" + block(engine, "private static func scheduleApplyActivity(")
    + "\n" + block(engine, "private static func ceilToMinute(")
    + r'''
    private static let boundaryWarning = DateComponents(minute: 5)
    static func expectedForTest(_ state: LatchState) -> Set<String> {
        expectedWindowActivityNames(state: state)
    }
    static func scheduleForTest(_ change: PendingChange) { scheduleApplyActivity(for: change) }
    static func registerForTest(_ rule: BlockSchedule) {
        startWindowActivities(prefix: "sched-" + rule.id.uuidString,
                              start: rule.startMinutes, end: rule.endMinutes,
                              recurrence: rule.recurrence)
    }
}
'''
    + "enum LimitFeatures {\n" + block(features, "static func expectedSplitActivityNames(") + "\n}\n"
    + "enum DayNightWake {\n" + block(day_night, "static func boundaryMinutes(") + "\n}\n"
)
source = "\n".join([
    infrastructure,
    portable((ROOT / "Shared/SharedModels.swift").read_text()),
    (ROOT / "Shared/PhraseWords.swift").read_text(),
    (ROOT / "Shared/MonitoringBudget.swift").read_text(),
    portable((ROOT / "Shared/MonitorRegistration.swift").read_text()),
    helpers,
    checks,
])
with tempfile.TemporaryDirectory(prefix="demora-monitoring-budget-") as directory:
    path = Path(directory)
    source_path, binary_path = path / "main.swift", path / "checks"
    source_path.write_text(source)
    subprocess.run(["xcrun", "swiftc", str(source_path), "-o", str(binary_path)], check=True)
    subprocess.run([str(binary_path)], check=True,
                   env={**os.environ, "TZ": "America/New_York"})
