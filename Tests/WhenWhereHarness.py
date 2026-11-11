#!/usr/bin/env python3
"""Run: python3 Tests/WhenWhereHarness.py

When & where rules, step 1 (docs/conditional-sessions-redesign.md, C15):
model, condition evaluator, check-in starts, per-day uses, capacity and the
change-engine path. Compiles the real SharedModels, MonitoringBudget,
SchedulePrecedence and PhraseWords sources plus the complete production
ChangeEngine methods (classify, summary, conflict keys, queue, queue
validation, apply, applyDueChanges and the new check-in entry point) on macOS.
Only opaque Screen Time tokens, storage, the guarded clock, file coordination
and monitor/notification XPC are substituted. No production branch is
rewritten.

A second binary compiles the SharedModels.swift of the commit before this
step (b188742) and decodes blobs written by the new code, to show what an
older build can still read.

Stubs cannot prove DeviceActivity delivery, iOS capacity, real location fixes
or callback timing on a device.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "b188742"
engine = (ROOT / "Shared/ChangeEngine.swift").read_text()
models_source = (ROOT / "Shared/SharedModels.swift").read_text()
phrases = (ROOT / "Shared/PhraseWords.swift").read_text()
budget = (ROOT / "Shared/MonitoringBudget.swift").read_text()
precedence = (ROOT / "Shared/SchedulePrecedence.swift").read_text().replace("import FamilyControls\n", "")
registration = (ROOT / "Shared/MonitorRegistration.swift").read_text()


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


models = portable(models_source)

# --- Source-level guards -------------------------------------------------
section = models_source[models_source.index("// MARK: - When & where rules"):]
code_only = re.sub(r"//[^\n]*", "", section)
for forbidden in ["CoreLocation", "CLLocation", "SharedStore.", "UserDefaults", "DeviceActivity",
                  "NSLog", "print("]:
    assert forbidden not in code_only, f"pure When & where code must not use {forbidden}"
# Every new LatchState field is optional storage: legacy-shaped state must
# encode exactly as before.
for stored in ["private(set) var conditionalRuleStore: [ConditionalRule]? = nil",
               "private(set) var conditionalUseStore: [ConditionalUseRecord]? = nil",
               "var timeZoneEvidence: TimeZoneEvidence? = nil",
               "var ownerRuleID: UUID? = nil", "var conditionalRuleID: UUID? = nil"]:
    assert stored in models_source, stored
# The free-time start has exactly one zero-delay path, reached only from
# queue validation after the check-in plan passed for a free-time rule.
queue_body = block(engine, "private static func queueCoordinated(")
assert "let delay = state.delayPolicy.delay(for: direction)" in queue_body
dispatch = block(queue_body, "if case .startConditionalSession(let request) = action {")
assert dispatch.index("case .success = ConditionalStart.plan(") < dispatch.index("if rule.isFreeTime {") \
    < dispatch.index("appliesAt: now, direction: .lenient")
assert "MonitorRegistration.admit(state: state, running: running)" in dispatch
assert engine.count("appliesAt: now,") == 1
apply_body = block(engine, "private static func apply(")
assert "phase: .apply" in apply_body

# --- Translations: every new key, all seven tables, matching placeholders --
STRING = r'"((?:[^"\\]|\\.)*)"'
keys = set()
summary_body = block(engine, "static func summary(")
conditional_summary = summary_body[summary_body.index("case .addConditionalRule"):]
for text in [section, conditional_summary]:
    for call in re.findall(r'\btr\((?:[^()"]|"(?:[^"\\]|\\.)*")*\)', text):
        keys.update(re.findall(STRING, call))
assert len(keys) >= 22, sorted(keys)
TABLES = {'es': '', 'de': '+German', 'fr': '+French', 'pt': '+Portuguese',
          'pl': '+Polish', 'tr': '+Turkish', 'hi': '+Hindi'}
entry = re.compile(r'(?:^|,)\s*' + STRING + r'\s*:\s*' + STRING + r'\s*(?=,|$)', re.M)
for language, suffix in TABLES.items():
    pairs = entry.findall((ROOT / f'Shared/Localization{suffix}.swift').read_text())
    seen = [k for k, _ in pairs]
    duplicates = sorted({k for k in seen if seen.count(k) > 1})
    assert not duplicates, (language, duplicates)
    table = dict(pairs)
    missing = sorted(k for k in keys if k not in table)
    assert not missing, (language, 'untranslated', missing)
    for key in keys:
        for spec in ('%@', '%d'):
            assert key.count(spec) == table[key].count(spec), (language, key, spec)
print(f"When & where strings: {len(keys)} keys × 7 tables, no duplicates, placeholders match")

# --- Compiled checks -------------------------------------------------------
infrastructure = r'''
import Foundation
struct FamilyActivitySelection: Codable, Equatable {
    var applicationTokens: Set<String> = []
    var categoryTokens: Set<String> = []
    var webDomainTokens: Set<String> = []
}
func tr(_ key: String) -> String { key }
enum TimeGuard {
    /// Offset from the real wall clock, so `Date()` and the guarded clock
    /// agree unless a scenario says otherwise.
    static var offset: TimeInterval = 0
    static func now() -> Date { Date().addingTimeInterval(offset) }
}
struct TestDefaults {
    static var values: [String: Any] = [:]
    func stringArray(forKey key: String) -> [String]? { Self.values[key] as? [String] }
    func string(forKey key: String) -> String? { Self.values[key] as? String }
    func set(_ value: Any?, forKey key: String) { Self.values[key] = value }
}
enum SharedStore {
    static var state = LatchState()
    static var simulating = false
    static var enforcementDegraded = false
    static var stateRecoveryNeeded = false
    static var saves = 0
    static var blockedIDs: Set<UUID> = []
    static var coordinated = false
    static func coordinateStateMutation<T>(_ body: () -> T) -> T? {
        if coordinated { return body() }
        coordinated = true
        defer { coordinated = false }
        return body()
    }
    static let defaults = TestDefaults()
    static func loadState() -> LatchState { state }
    @discardableResult static func save(_ value: LatchState) -> Bool {
        guard !stateRecoveryNeeded else { return false }
        saves += 1; state = value; return true
    }
    static func mutateBlockedLimitIDs(_ edit: (inout Set<UUID>) -> Void) { edit(&blockedIDs) }
    static func loadBlockedLimitIDs() -> Set<UUID> { blockedIDs }
    static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    static func loadFreeCreditByLimit() -> [UUID: Int] { [:] }
}
struct DeviceActivityName: Equatable {
    var rawValue: String
    init(_ value: String) { rawValue = value }
}
struct DeviceActivityCenter {
    static var running: Set<String> = []
    static var stopped: [String] = []
    var activities: [DeviceActivityName] {
        precondition(!SharedStore.coordinated, "monitor XPC under state coordination")
        return Self.running.sorted().map(DeviceActivityName.init)
    }
    func stopMonitoring(_ names: [DeviceActivityName]) {
        Self.stopped += names.map(\.rawValue)
        Self.running.subtract(names.map(\.rawValue))
    }
}
enum ShieldController { static func refresh() {} }
struct UNUserNotificationCenter {
    static func current() -> Self { Self() }
    func removePendingNotificationRequests(withIdentifiers ids: [String]) {}
}
enum GlobalWake { static func clearTap() {} }
enum LimitFeatures {
    static func prepareNewWakeGates(_ ids: Set<UUID>) -> Bool { true }
    static func resetEditedLimits(_ ids: Set<UUID>) {}
    static func clearSplitMarkers(for ids: Set<UUID>) {}
    static func reconfigureSplitMonitoring(state: LatchState) {}
    static func reconcile(state: LatchState) {}
}
'''

driver = r'''
    static var scheduledApplyIDs: [UUID] = []
    static var notifiedIDs: [UUID] = []
    static var cleanupActivities: [String] = []
    static var windowReconfigurations = 0
    static func scheduleApplyActivity(for change: PendingChange) {
        precondition(!SharedStore.coordinated, "registration under state lock")
        scheduledApplyIDs.append(change.id)
    }
    static func scheduleNotification(for change: PendingChange) {
        precondition(!SharedStore.coordinated, "notification under state lock")
        notifiedIDs.append(change.id)
    }
    private static let deviceActivityWorkQueue = DispatchQueue(label: "test-serialized-enforcement")
    private static let trackedLimitSelectionsKey = "test-tracked"
    private static let freeWindowActivityName = "latch.freewin"
    private static let dailyMonitorFingerprintKey = "latch.dailyMonitorFingerprint.v2"
    static func limitSelectionDigest(_ selection: FamilyActivitySelection) -> String {
        (selection.applicationTokens.sorted() + selection.categoryTokens.sorted()
            + selection.webDomainTokens.sorted()).joined(separator: ",")
    }
    static func prepareUsageCreditForSelectionEdit(ids: Set<UUID>, state: LatchState) -> Bool { false }
    static func isFreeWindowActive() -> Bool { false }
    static func startFreeWindowTracking() {}
    static func startSessionCleanupActivity(_ session: BlockSession) {
        precondition(!SharedStore.coordinated)
        cleanupActivities.append(session.activityName)
        DeviceActivityCenter.running.insert(session.activityName)
    }
    static func reconcileFreeWindow() {}
    static func reconfigureDailyMonitoring(state: LatchState) {}
    static func reconfigureWindowMonitoring(state: LatchState) { windowReconfigurations += 1 }
    static func startForTest(_ request: ConditionalStartRequest) -> ConditionalStartResult {
        startConditionalSession(request)
    }
    static func applyForTest(_ action: ChangeAction, state: inout LatchState) {
        apply(action, to: &state)
    }
'''

methods = "\n".join(block(engine, signature) for signature in [
    "enum ConditionalStartResult",
    "static func startConditionalSessionOffMain(",
    "private static func startConditionalSession(",
    "static func observeTimeZone(",
    "static func pruneConditionalUses(",
    "static func overrideCapability(",
    "static func hasOverride(",
    "static func classify(",
    "static func summary(",
    "static func conflictKey(",
    "static func queue(",
    "private static func queueCoordinated(",
    "private static func isValidLimit(",
    "private static func apply(",
    "static func normalizeDomain(",
    "static func hasUnappliedDueChanges(",
    "static func applyDueChanges(",
    "private static func preserveDailyMonitoringForWakeEdit(",
    "private static func dailyMonitorFingerprint(",
])

admission = "\nenum MonitorRegistration {\n" + "\n".join(
    block(registration, signature) for signature in [
        "static func clearRejection()", "static func reject(required:", "static func admit(",
    ]) + '\nprivate static let rejectionKey = "test-capacity-rejection"\n}\n'

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
    SharedStore.state = LatchState(); SharedStore.simulating = false
    SharedStore.stateRecoveryNeeded = false; SharedStore.saves = 0
    SharedStore.enforcementDegraded = false; SharedStore.blockedIDs = []
    DeviceActivityCenter.running = []; DeviceActivityCenter.stopped = []
    TestDefaults.values = [:]; TimeGuard.offset = 0
    ChangeEngine.scheduledApplyIDs = []; ChangeEngine.notifiedIDs = []
    ChangeEngine.cleanupActivities = []; ChangeEngine.windowReconfigurations = 0
    do { try body() } catch { failures.append("\(name): unexpected error \(error)") }
}

// Fixtures ------------------------------------------------------------------
let apps = FamilyActivitySelection(applicationTokens: ["opaque-instagram"])
let iso = ISO8601DateFormatter()
func date(_ text: String) -> Date { iso.date(from: text)! }
func calendar(_ zone: String) -> Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: zone)!
    return value
}
func clock(_ text: String, zone: String = "Europe/Madrid", recent: [String] = [],
           wallOffset: TimeInterval = 0) -> ConditionalClockInput {
    let now = date(text)
    return ConditionalClockInput(guardedNow: now, wallNow: now.addingTimeInterval(wallOffset),
                                 calendar: calendar(zone), recentTimeZoneIDs: [zone] + recent)
}
let home = ConditionalPlace(name: "Home", latitude: 40.41680, longitude: -3.70380, radiusMeters: 250)
let mexico = ConditionalCondition.country("MX")
func free(_ minutes: Int = 60, uses: Int = 1, kind: SessionKind = .free) -> ConditionalOutcome {
    .freeTime(kind: kind, selection: kind == .free ? FamilyActivitySelection() : apps,
              maxMinutes: minutes, usesPerDay: uses)
}
let blockUntilSeven = ConditionalOutcome.block(mode: .blockSelected, selection: apps, until: .time(7 * 60))
func rule(_ conditions: [ConditionalCondition], _ match: ConditionalMatch = .all,
          outcome: ConditionalOutcome = free(), name: String = "Rule") -> ConditionalRule {
    ConditionalRule(name: name, match: match, conditions: conditions, outcome: outcome,
                    addedAt: Date(timeIntervalSince1970: 1_700_000_000))
}
/// A fix `meters` north of Home.
func fix(north meters: Double, accuracy: Double = 10, age: TimeInterval = 1,
         precise: Bool = true, simulated: Bool = false, accessory: Bool = false,
         country: ConditionalCountryLookup? = nil) -> ConditionalLocationInput {
    let latitude = home.latitude + meters / 111_195
    return .fix(ConditionalLocationFix(latitude: latitude, longitude: home.longitude,
                                       horizontalAccuracy: accuracy, age: age, isPrecise: precise,
                                       isSimulated: simulated, isFromAccessory: accessory),
                country: country)
}
func statuses(_ evaluation: ConditionalEvaluation) -> [ConditionStatus] { evaluation.results.map(\.status) }
let sunday = ConditionalCondition.days([1])
let weekend = ConditionalCondition.days([1, 7])
let night = ConditionalCondition.time(start: 22 * 60, end: 6 * 60)
func encoded(_ value: LatchState) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

// Decoding and saved-state shape --------------------------------------------
scenario("legacy state decodes unchanged and re-encodes without new keys") {
    let raw = #"{"isSetUp":true,"strictDelay":300,"lenientDelay":900,"schedules":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Night","mode":"blockSelected","selection":{"applicationTokens":["a"],"categoryTokens":[],"webDomainTokens":[]},"startMinutes":1320,"endMinutes":360}],"sessions":[{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Focus","kind":"block","selection":{"applicationTokens":["a"],"categoryTokens":[],"webDomainTokens":[]},"startedAt":800000000,"endsAt":800003600}]}"#
    let state = try JSONDecoder().decode(LatchState.self, from: Data(raw.utf8))
    expect(state.isSetUp && state.schedules.count == 1 && state.sessions.count == 1, "legacy rules lost")
    expect(state.conditionalRules.isEmpty && state.conditionalUses.isEmpty && state.timeZoneEvidence == nil,
           "new fields not empty by default")
    expect(state.schedules[0].ownerRuleID == nil && state.sessions[0].conditionalRuleID == nil,
           "legacy schedule/session gained an owner")
    expect(state.sessions[0].activityName == "session-7F9619FF-8B86-D011-B42D-00C04FC964FF",
           "legacy session activity name changed")
    let text = try encoded(state)
    for key in ["conditionalRuleStore", "conditionalUseStore", "timeZoneEvidence", "ownerRuleID",
                "conditionalRuleID"] {
        expect(!text.contains(key), "legacy-shaped state now encodes \(key)")
    }
    // Same top-level keys as the state this build encoded before the step
    // (set element order is not stable across instances, so compare keys).
    let baselineKeys: Set<String> = ["isSetUp", "mathPhraseReplacementDone", "strictDelay", "lenientDelay",
        "delayMode", "limits", "overrides", "wakeRule", "sleepRule", "dayNightGroups", "dayNightSetupDone",
        "prioritizedScheduleKeys", "pending", "schedules", "exemptions", "sessions", "planned", "blockAppRemoval",
        "blockAdultWebsites", "blockedDomains", "screenTimeCode"]
    let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    expect(Set(object?.keys.map { $0 } ?? []) == baselineKeys,
           "legacy-shaped state keys changed: \(Set(object?.keys.map { $0 } ?? []).symmetricDifference(baselineKeys))")
}
scenario("new fields round-trip; rule decode tolerates missing revision/addedAt") {
    var state = LatchState()
    var stored = rule([.place(home), sunday, night], .any, outcome: blockUntilSeven)
    stored.revision = 3
    state.conditionalRules = [stored]
    state.conditionalUses = [ConditionalUseRecord(ruleID: stored.id, day: "2026-11-15", count: 1,
                                                  lastUsedAt: date("2026-11-15T10:00:00Z"),
                                                  checkInIDs: [UUID()])]
    state.timeZoneEvidence = TimeZoneEvidence(currentID: "Europe/Madrid",
                                              lastSeen: ["America/Mexico_City": date("2026-11-15T09:00:00Z")])
    var session = BlockSession(name: "Rule", kind: .free, selection: FamilyActivitySelection(),
                               startedAt: Date(), endsAt: Date().addingTimeInterval(600))
    session.conditionalRuleID = stored.id
    state.sessions = [session]
    state.schedules = stored.ownedSchedules()
    let back = try JSONDecoder().decode(LatchState.self, from: Data(try encoded(state).utf8))
    expect(back.conditionalRules == state.conditionalRules, "rules lost")
    expect(back.conditionalUses == state.conditionalUses, "uses lost")
    expect(back.timeZoneEvidence == state.timeZoneEvidence, "evidence lost")
    expect(back.sessions == state.sessions && back.sessions[0].activityName == stored.sessionActivityName,
           "conditional session lost its rule")
    expect(back.schedules == state.schedules && back.schedules.allSatisfy { $0.ownerRuleID == stored.id },
           "owned schedule lost its owner")
    let minimal = #"{"id":"8F9619FF-8B86-D011-B42D-00C04FC964FF","name":"R","match":"all","conditions":[{"days":{"_0":[1]}}],"outcome":{"freeTime":{"kind":"free","selection":{"applicationTokens":[],"categoryTokens":[],"webDomainTokens":[]},"maxMinutes":60,"usesPerDay":1}}}"#
    let decoded = try JSONDecoder().decode(ConditionalRule.self, from: Data(minimal.utf8))
    expect(decoded.revision == 0 && decoded.addedAt == .distantPast && decoded.isValid, "tolerant rule decode")
}

// Validation ----------------------------------------------------------------
scenario("rule validation") {
    expect(rule([mexico, sunday]).isValid, "example 1 invalid")
    expect(rule([.place(home), night], .any, outcome: blockUntilSeven).isValid, "example 2 invalid")
    expect(rule([.place(home), weekend], outcome: free(30, uses: 2)).isValid, "example 3 invalid")
    expect(!rule([]).isValid, "no conditions accepted")
    expect(!rule([sunday, sunday, sunday, sunday, sunday]).isValid, "five conditions accepted")
    var wide = home; wide.radiusMeters = 5000
    expect(!rule([.place(wide)]).isValid, "free radius accepted")
    expect(!rule([.country("mx")]).isValid && !rule([.country("MEX")]).isValid, "bad region code")
    expect(!rule([.days([])]).isValid && !rule([.days([8])]).isValid, "bad weekdays")
    expect(!rule([.time(start: 600, end: 600)]).isValid && !rule([.time(start: 0, end: 1440)]).isValid,
           "bad time window")
    let first = ConditionalDay(year: 2026, month: 12, day: 27), last = ConditionalDay(year: 2026, month: 12, day: 20)
    expect(!rule([.dates(first: first, last: last)]).isValid, "dates backwards")
    expect(!rule([.dates(first: ConditionalDay(year: 2026, month: 2, day: 30), last: first)]).isValid, "impossible day")
    expect(!rule([sunday], outcome: free(4)).isValid && !rule([sunday], outcome: free(241)).isValid, "length bounds")
    expect(!rule([sunday], outcome: free(60, uses: 6)).isValid && !rule([sunday], outcome: free(60, uses: 0)).isValid,
           "uses bounds")
    expect(!rule([sunday], outcome: .freeTime(kind: .unblock, selection: FamilyActivitySelection(),
                                             maxMinutes: 60, usesPerDay: 1)).isValid, "unblock without apps")
    expect(!rule([sunday], outcome: .freeTime(kind: .block, selection: apps, maxMinutes: 60, usesPerDay: 1)).isValid,
           "free time of kind block")
    expect(!rule([sunday, night], .any, outcome: blockUntilSeven).isValid, "block without a place")
    expect(!rule([.place(home), sunday], .any, outcome: blockUntilSeven).isValid,
           "standalone days branch accepted for a block (v1: only time windows run on their own)")
    expect(rule([.place(home), sunday], .all, outcome: blockUntilSeven).isValid, "all-of block with days")
    expect(!rule([.place(home)], outcome: .block(mode: .blockAllExcept, selection: apps, until: .time(420))).isValid,
           "block all-except accepted (a check-in block is a Block now session)")
    expect(!rule([.place(home)], outcome: .block(mode: .blockSelected, selection: FamilyActivitySelection(),
                                                until: .time(420))).isValid, "block without apps")
    var longName = rule([sunday]); longName.name = String(repeating: "a", count: 81)
    expect(!longName.isValid && !rule([sunday], name: "  ").isValid, "name bounds")
}

// Evaluator -----------------------------------------------------------------
scenario("all of / any of truth table, location only when it can change the answer") {
    let sundayNoon = clock("2026-11-15T12:00:00+01:00"), mondayNoon = clock("2026-11-16T12:00:00+01:00")
    // All of: a failed day means don't read location.
    var e = ConditionEvaluator.evaluate(rule([.place(home), sunday]), clock: mondayNoon, location: .notRead)
    expect(!e.isMet && !e.locationCouldChangeVerdict && statuses(e) == [.notNeeded, .notMet], "all-of fail read location")
    // All of: day passes, location still needed.
    e = ConditionEvaluator.evaluate(rule([.place(home), sunday]), clock: sundayNoon, location: .notRead)
    expect(!e.isMet && e.locationCouldChangeVerdict && statuses(e) == [.unknown, .met], "all-of pass did not need location")
    // Any of: a passed time branch means location is not needed.
    let anyRule = rule([.place(home), .time(start: 11 * 60, end: 13 * 60)], .any)
    e = ConditionEvaluator.evaluate(anyRule, clock: sundayNoon, location: .notRead)
    expect(e.isMet && !e.locationCouldChangeVerdict && statuses(e) == [.notNeeded, .met], "any-of pass read location")
    // Any of: time fails, location could still make it true.
    e = ConditionEvaluator.evaluate(anyRule, clock: clock("2026-11-15T20:00:00+01:00"), location: .notRead)
    expect(!e.isMet && e.locationCouldChangeVerdict, "any-of fail did not ask for location")
    // With a fix inside Home.
    e = ConditionEvaluator.evaluate(rule([.place(home), sunday]), clock: sundayNoon, location: fix(north: 0))
    expect(e.isMet && statuses(e) == [.met, .met], "all-of met")
    e = ConditionEvaluator.evaluate(anyRule, clock: clock("2026-11-15T20:00:00+01:00"), location: fix(north: 0))
    expect(e.isMet && statuses(e) == [.met, .notMet], "any-of location branch")
    e = ConditionEvaluator.evaluate(anyRule, clock: clock("2026-11-15T20:00:00+01:00"), location: fix(north: 5000))
    expect(!e.isMet, "any-of with nothing met")
    // Unknown fails closed in both modes.
    e = ConditionEvaluator.evaluate(rule([.place(home), sunday]), clock: sundayNoon, location: .unavailable(.locationOff))
    expect(!e.isMet && e.results[0].reason == .unknown(.locationOff), "denied location passed all-of")
    e = ConditionEvaluator.evaluate(rule([.place(home)], .any), clock: sundayNoon, location: .unavailable(.noFix))
    expect(!e.isMet, "unknown passed any-of")
}
scenario("place geometry: whole circle inside for free time, touching for a block") {
    let noon = clock("2026-11-15T12:00:00+01:00")
    let freeRule = rule([.place(home)]), blockRule = rule([.place(home)], outcome: blockUntilSeven)
    func status(_ r: ConditionalRule, _ input: ConditionalLocationInput) -> ConditionStatus {
        ConditionEvaluator.evaluate(r, clock: noon, location: input).results[0].status
    }
    expect(status(freeRule, fix(north: 200, accuracy: 40)) == .met, "inside not met")
    expect(status(freeRule, fix(north: 200, accuracy: 60)) == .unknown, "straddling circle met free time")
    expect(status(freeRule, fix(north: 400, accuracy: 100)) == .notMet, "clearly outside")
    expect(status(blockRule, fix(north: 300, accuracy: 60)) == .met, "touching circle did not start block")
    expect(status(blockRule, fix(north: 400, accuracy: 100)) == .notMet, "far circle started block")
    expect(status(freeRule, fix(north: 0, simulated: true)) == .unknown, "simulated fix accepted")
    expect(status(blockRule, fix(north: 0, simulated: true)) == .unknown, "simulated fix accepted for block")
    expect(status(freeRule, fix(north: 0, accessory: true)) == .unknown, "accessory fix accepted for free time")
    expect(status(blockRule, fix(north: 0, accessory: true)) == .met, "accessory fix refused for a block")
    expect(status(freeRule, fix(north: 0, age: 16)) == .unknown, "stale fix accepted")
    expect(status(freeRule, fix(north: 0, age: -30)) == .unknown, "future fix accepted")
    expect(status(freeRule, fix(north: 0, accuracy: -1)) == .unknown, "invalid accuracy accepted")
    expect(status(freeRule, fix(north: 0, accuracy: 0)) == .unknown, "zero accuracy accepted")
    expect(status(freeRule, fix(north: 0, precise: false)) == .unknown, "approximate fix accepted for a place")
    let d = ConditionEvaluator.distanceMeters(19.4326, -99.1332, 32.5149, -117.0382)
    expect(abs(d - 2_300_000) < 60_000, "haversine distance off: \(d)")
}
scenario("country: border margin for free time, inside is enough for a block") {
    let noon = clock("2026-11-15T12:00:00+01:00")
    func status(_ outcome: ConditionalOutcome, _ lookup: ConditionalCountryLookup?, precise: Bool = true,
                accuracy: Double = 50) -> ConditionStatus {
        ConditionEvaluator.evaluate(rule([mexico], outcome: outcome), clock: noon,
            location: fix(north: 0, accuracy: accuracy, precise: precise, country: lookup)).results[0].status
    }
    let cityCentre = ConditionalCountryLookup(regionCode: "MX", borderDistanceMeters: 600_000)
    let tijuana = ConditionalCountryLookup(regionCode: "MX", borderDistanceMeters: 1_500)
    let sanDiego = ConditionalCountryLookup(regionCode: "US", borderDistanceMeters: 1_000)
    let sea = ConditionalCountryLookup(regionCode: nil, borderDistanceMeters: 80_000)
    expect(status(free(), cityCentre) == .met, "Mexico City not in Mexico")
    expect(status(free(), cityCentre, precise: false, accuracy: 3_000) == .met, "approximate fix refused for a country")
    expect(status(free(), tijuana) == .unknown, "near border passed free time")
    expect(status(free(), ConditionalCountryLookup(regionCode: "MX", borderDistanceMeters: 2_100), accuracy: 200) == .unknown,
           "accuracy not added to the margin")
    expect(status(free(), sanDiego) == .unknown, "near border on the wrong side not doubtful")
    expect(status(free(), sea) == .notMet, "open sea met")
    expect(status(free(), ConditionalCountryLookup(regionCode: "US", borderDistanceMeters: 900_000)) == .notMet, "far outside met")
    let block = ConditionalOutcome.block(mode: .blockSelected, selection: apps, until: .duration(minutes: 60))
    expect(status(block, tijuana) == .met, "inside near border refused a block")
    expect(status(block, sanDiego) == .notMet, "outside started a block")
    expect(status(free(), nil) == .unknown, "missing lookup passed")
    expect(status(free(), ConditionalCountryLookup(regionCode: "MX", borderDistanceMeters: .nan)) == .unknown, "NaN border")
}
scenario("each clock condition, midnight wrap, dates") {
    let r = rule([night])
    var e = ConditionEvaluator.evaluate(r, clock: clock("2026-11-15T23:30:00+01:00"), location: .notRead)
    expect(e.isMet && e.windowEnd == date("2026-11-16T06:00:00+01:00"), "23:30 inside 22:00–06:00")
    e = ConditionEvaluator.evaluate(r, clock: clock("2026-11-16T05:59:00+01:00"), location: .notRead)
    expect(e.isMet && e.windowEnd == date("2026-11-16T06:00:00+01:00"), "05:59 inside")
    e = ConditionEvaluator.evaluate(r, clock: clock("2026-11-16T06:00:00+01:00"), location: .notRead)
    expect(!e.isMet && e.results[0].reason == .outsideWindow(minute: 360), "06:00 end not exclusive")
    e = ConditionEvaluator.evaluate(r, clock: clock("2026-11-15T21:59:00+01:00"), location: .notRead)
    expect(!e.isMet, "21:59 inside")
    e = ConditionEvaluator.evaluate(rule([sunday]), clock: clock("2026-11-15T23:50:00+01:00"), location: .notRead)
    expect(e.isMet && e.windowEnd == date("2026-11-16T00:00:00+01:00") && e.results[0].reason == .onDay(weekday: 1),
           "Sunday ends at midnight")
    e = ConditionEvaluator.evaluate(rule([weekend]), clock: clock("2026-11-14T23:50:00+01:00"), location: .notRead)
    expect(e.windowEnd == date("2026-11-16T00:00:00+01:00"), "Sat+Sun run not joined")
    e = ConditionEvaluator.evaluate(rule([.days(Set(1...7))]), clock: clock("2026-11-14T23:50:00+01:00"), location: .notRead)
    expect(e.isMet && e.windowEnd == nil, "every day capped")
    e = ConditionEvaluator.evaluate(rule([sunday]), clock: clock("2026-11-16T00:00:00+01:00"), location: .notRead)
    expect(!e.isMet && e.results[0].reason == .notOnDay(weekday: 2), "Monday met Sunday")
    let trip = ConditionalCondition.dates(first: ConditionalDay(year: 2026, month: 12, day: 20),
                                          last: ConditionalDay(year: 2026, month: 12, day: 27))
    e = ConditionEvaluator.evaluate(rule([trip]), clock: clock("2026-12-27T12:00:00+01:00"), location: .notRead)
    expect(e.isMet && e.windowEnd == date("2026-12-28T00:00:00+01:00"), "last trip day")
    e = ConditionEvaluator.evaluate(rule([trip]), clock: clock("2026-12-19T23:59:00+01:00"), location: .notRead)
    expect(!e.isMet && e.results[0].reason == .outsideDates, "before the trip")
    e = ConditionEvaluator.evaluate(rule([trip]), clock: clock("2026-12-28T00:00:00+01:00"), location: .notRead)
    expect(!e.isMet, "after the trip")
}
scenario("DST: spring gap and repeated fall hour") {
    // Madrid 2026-03-29 02:00 → 03:00. A window ending 02:30 ends at 03:00.
    var e = ConditionEvaluator.evaluate(rule([.time(start: 60, end: 150)]), clock: clock("2026-03-29T01:30:00+01:00"),
                                        location: .notRead)
    expect(e.isMet && e.windowEnd == date("2026-03-29T03:00:00+02:00"), "spring gap end \(String(describing: e.windowEnd))")
    // A 23-hour Sunday ends at Monday's midnight.
    e = ConditionEvaluator.evaluate(rule([sunday]), clock: clock("2026-03-29T12:00:00+02:00"), location: .notRead)
    expect(e.windowEnd == date("2026-03-30T00:00:00+02:00"), "spring Sunday end")
    // Madrid 2026-10-25 03:00 → 02:00. First 02:15 ends at the first 02:30;
    // the repeated 02:15 ends at the second 02:30, never in the past.
    let overnight = rule([.time(start: 22 * 60, end: 150)])
    e = ConditionEvaluator.evaluate(overnight, clock: clock("2026-10-25T02:15:00+02:00"), location: .notRead)
    expect(e.isMet && e.windowEnd == date("2026-10-25T02:30:00+02:00"), "first fall 02:15")
    e = ConditionEvaluator.evaluate(overnight, clock: clock("2026-10-25T02:15:00+01:00"), location: .notRead)
    expect(e.isMet && e.windowEnd == date("2026-10-25T02:30:00+01:00"), "repeated fall 02:15")
    e = ConditionEvaluator.evaluate(rule([sunday]), clock: clock("2026-10-25T23:00:00+01:00"), location: .notRead)
    expect(e.windowEnd == date("2026-10-26T00:00:00+01:00"), "25-hour Sunday end")
    e = ConditionEvaluator.evaluate(overnight, clock: clock("2026-10-24T23:00:00+02:00"), location: .notRead)
    expect(e.windowEnd == date("2026-10-25T02:30:00+02:00"), "overnight across fall change")
}
scenario("guarded clock and time-zone change in the last 12 hours") {
    var e = ConditionEvaluator.evaluate(rule([sunday, .place(home)]), clock: clock("2026-11-15T12:00:00+01:00", wallOffset: 301),
                                        location: fix(north: 0))
    expect(!e.isMet && e.results[0].reason == .unknown(.clockChanged) && e.results[1].status == .met,
           "changed clock passed day condition or blocked location")
    e = ConditionEvaluator.evaluate(rule([sunday]), clock: clock("2026-11-15T12:00:00+01:00", wallOffset: 299),
                                    location: .notRead)
    expect(e.isMet, "within tolerance refused")
    // Arriving in Mexico on Sunday: Madrid is also Sunday → still works.
    e = ConditionEvaluator.evaluate(rule([sunday]), clock: clock("2026-11-15T10:00:00-06:00", zone: "America/Mexico_City",
                                                                    recent: ["Europe/Madrid"]), location: .notRead)
    expect(e.isMet, "real travel on the same weekday refused")
    // "After 22:00" made true by switching zone: must hold in both.
    let late = rule([.time(start: 22 * 60, end: 23 * 60 + 59)])
    e = ConditionEvaluator.evaluate(late, clock: clock("2026-11-15T22:30:00-06:00", zone: "America/Mexico_City",
                                                         recent: ["Europe/Madrid"]), location: .notRead)
    expect(!e.isMet && e.results[0].reason == .unknown(.timeZoneChanged), "zone switch passed a time window")
    e = ConditionEvaluator.evaluate(late, clock: clock("2026-11-15T22:30:00-06:00", zone: "America/Mexico_City",
                                                         recent: ["Not/AZone"]), location: .notRead)
    expect(!e.isMet && e.results[0].reason == .unknown(.timeZoneUnknown), "unknown zone passed")
    // Both zones hold: the earlier end wins.
    e = ConditionEvaluator.evaluate(rule([.days([1, 2])]), clock: clock("2026-11-16T10:00:00-06:00", zone: "America/Mexico_City",
                                                                          recent: ["Europe/Madrid"]), location: .notRead)
    expect(e.isMet && e.windowEnd == date("2026-11-17T00:00:00+01:00"), "earliest zone end not used")
}
scenario("time-zone evidence") {
    let t0 = date("2026-11-15T08:00:00Z")
    var evidence = TimeZoneEvidence.observing(nil, zoneID: "Europe/Madrid", at: t0)!
    expect(evidence.lastSeen.isEmpty && TimeZoneEvidence.recentZoneIDs(evidence, current: "Europe/Madrid", at: t0) == ["Europe/Madrid"],
           "first record invented a previous zone")
    expect(TimeZoneEvidence.observing(evidence, zoneID: "Europe/Madrid", at: t0) == nil, "unchanged zone writes")
    let t1 = t0.addingTimeInterval(3600)
    evidence = TimeZoneEvidence.observing(evidence, zoneID: "America/Mexico_City", at: t1)!
    expect(TimeZoneEvidence.recentZoneIDs(evidence, current: "America/Mexico_City", at: t1) == ["America/Mexico_City", "Europe/Madrid"],
           "change not remembered")
    expect(TimeZoneEvidence.recentZoneIDs(evidence, current: "America/Mexico_City", at: t1.addingTimeInterval(12 * 3600))
           == ["America/Mexico_City", "Europe/Madrid"], "12 h boundary not inclusive")
    expect(TimeZoneEvidence.recentZoneIDs(evidence, current: "America/Mexico_City", at: t1.addingTimeInterval(12 * 3600 + 1))
           == ["America/Mexico_City"], "old zone kept after 12 h")
    // A change nobody observed yet counts as just now.
    expect(TimeZoneEvidence.recentZoneIDs(evidence, current: "Asia/Tokyo", at: t1.addingTimeInterval(86_400))
           == ["Asia/Tokyo", "America/Mexico_City"], "unobserved change ignored")
    // A clock moved back keeps the entry (doubt favours the stricter check).
    expect(TimeZoneEvidence.recentZoneIDs(evidence, current: "America/Mexico_City", at: t0.addingTimeInterval(-86_400))
           .count == 2, "future-dated entry dropped")
    var many: TimeZoneEvidence? = evidence
    for (index, zone) in ["Asia/Tokyo", "Europe/Paris", "Europe/Berlin", "Europe/Rome", "Europe/Oslo",
                          "Europe/Lisbon", "Europe/Dublin", "Europe/Warsaw", "Europe/Vienna", "Europe/Prague"].enumerated() {
        many = TimeZoneEvidence.observing(many, zoneID: zone, at: t1.addingTimeInterval(Double(index + 1)))
    }
    expect(many!.lastSeen.count == TimeZoneEvidence.maximumEntries, "evidence not bounded")
}
scenario("session caps: all of takes the earliest end, any of the latest, places only length") {
    let c = clock("2026-11-15T23:00:00+01:00")
    var e = ConditionEvaluator.evaluate(rule([sunday, night]), clock: c, location: .notRead)
    expect(e.windowEnd == date("2026-11-16T00:00:00+01:00"), "all-of not earliest")
    e = ConditionEvaluator.evaluate(rule([sunday, night], .any), clock: c, location: .notRead)
    expect(e.windowEnd == date("2026-11-16T06:00:00+01:00"), "any-of not latest")
    e = ConditionEvaluator.evaluate(rule([.place(home), night], .any), clock: c, location: fix(north: 0))
    expect(e.isMet && e.windowEnd == nil, "met place branch capped by a window")
    e = ConditionEvaluator.evaluate(rule([.place(home), sunday]), clock: c, location: fix(north: 0))
    expect(e.windowEnd == date("2026-11-16T00:00:00+01:00"), "all-of with a place lost the day cap")
}

// Uses ----------------------------------------------------------------------
scenario("per-day uses: monotonic, never refunded, pruned only when old") {
    let id = UUID(), first = UUID(), second = UUID()
    let now = date("2026-11-15T12:00:00Z")
    var records = ConditionalUses.recording(ruleID: id, dayKeys: ["2026-11-15"], checkInID: first, at: now, in: [])
    records = ConditionalUses.recording(ruleID: id, dayKeys: ["2026-11-15", "2026-11-16"], checkInID: second,
                                        at: now.addingTimeInterval(60), in: records)
    expect(ConditionalUses.used(ruleID: id, dayKeys: ["2026-11-15"], in: records) == 2, "count not monotonic")
    expect(ConditionalUses.used(ruleID: id, dayKeys: ["2026-11-16", "2026-11-15"], in: records) == 2, "max across keys")
    expect(ConditionalUses.used(ruleID: UUID(), dayKeys: ["2026-11-15"], in: records) == 0, "other rule counted")
    expect(ConditionalUses.checkInUsed(second, ruleID: id, in: records), "check-in not remembered")
    expect(ConditionalUses.pruned(records, at: now.addingTimeInterval(71 * 3600)) == records, "pruned too early")
    expect(ConditionalUses.pruned(records, at: now.addingTimeInterval(73 * 3600)).isEmpty, "never pruned")
    expect(ConditionalUses.pruned(records, at: now.addingTimeInterval(-86_400)) == records, "future record pruned")
    expect(ConditionalUses.dayKey(for: date("2026-11-15T23:30:00Z"), calendar: calendar("Europe/Madrid")) == "2026-11-16",
           "day key not local")
}

// Check-in start plan --------------------------------------------------------
func planState(_ r: ConditionalRule) -> LatchState { var s = LatchState(); s.conditionalRules = [r]; return s }
func request(_ r: ConditionalRule, _ c: ConditionalClockInput, minutes: Int = 60,
             results: [Bool]? = nil, location: ConditionalLocationInput = .notRead,
             checkInID: UUID = UUID()) -> ConditionalStartRequest {
    let evaluation = ConditionEvaluator.evaluate(r, clock: c, location: location)
    var stamp = ConditionalCheckInStamp.make(evaluation, clock: c, checkInID: checkInID)
    if let results { stamp.results = results }
    return ConditionalStartRequest(ruleID: r.id, revision: r.revision, minutes: minutes, stamp: stamp)
}
func refusal(_ result: Result<ConditionalStartPlan, ConditionalStartRefusal>) -> ConditionalStartRefusal? {
    if case .failure(let value) = result { return value }
    return nil
}
scenario("plan: a Sunday session at 23:50 ends at midnight and counts one use") {
    let r = rule([sunday], outcome: free(60))
    let c = clock("2026-11-15T23:50:00+01:00")
    let result = ConditionalStart.plan(request(r, c), state: planState(r), clock: c)
    guard case .success(let plan) = result else { expect(false, "refused \(String(describing: refusal(result)))"); return }
    expect(plan.session.endsAt == date("2026-11-16T00:00:00+01:00"), "not capped at midnight")
    expect(plan.session.startedAt == c.wallNow && plan.session.kind == .free
           && plan.session.selection == FamilyActivitySelection(), "session shape")
    expect(plan.session.conditionalRuleID == r.id && plan.session.activityName == r.sessionActivityName, "activity name")
    expect(ConditionalUses.used(ruleID: r.id, dayKeys: ["2026-11-15"], in: plan.uses) == 1, "use not counted")
    let c2 = clock("2026-11-16T10:00:00+01:00")
    let r2 = rule([.place(home)], outcome: free(60))
    guard case .success(let placePlan) = ConditionalStart.plan(request(r2, c2, minutes: 45, location: fix(north: 0)),
                                                               state: planState(r2), clock: c2) else {
        expect(false, "place-only start refused"); return
    }
    expect(placePlan.session.endsAt == c2.wallNow.addingTimeInterval(45 * 60), "place-only start not by length")
}
scenario("plan refusals: stale, wrong day/zone/revision, not met, length, running, uses, window") {
    let r = rule([sunday, .place(home)], outcome: free(60, uses: 1))
    let c = clock("2026-11-15T12:00:00+01:00")
    let good = request(r, c, location: fix(north: 0))
    let state = planState(r)
    expect(refusal(ConditionalStart.plan(good, state: state, clock: c)) == nil, "valid start refused")
    func at(_ seconds: TimeInterval) -> ConditionalClockInput {
        var value = c; value.guardedNow = c.guardedNow.addingTimeInterval(seconds)
        value.wallNow = value.guardedNow; return value
    }
    expect(refusal(ConditionalStart.plan(good, state: state, clock: at(121))) == .stampStale, "stale stamp")
    expect(refusal(ConditionalStart.plan(good, state: state, clock: at(-30))) == .stampStale, "future stamp")
    expect(refusal(ConditionalStart.plan(good, state: state, clock: at(120))) == nil, "2-minute stamp refused")
    var wrongDay = good; wrongDay.stamp.dayKey = "2026-11-14"
    expect(refusal(ConditionalStart.plan(wrongDay, state: state, clock: c)) == .wrongDay, "wrong day key")
    var wrongZone = good; wrongZone.stamp.timeZoneID = "America/Mexico_City"
    expect(refusal(ConditionalStart.plan(wrongZone, state: state, clock: c)) == .timeZoneMoved, "zone moved")
    var oldRevision = good; oldRevision.revision = 1
    expect(refusal(ConditionalStart.plan(oldRevision, state: state, clock: c)) == .ruleChanged, "old revision")
    expect(refusal(ConditionalStart.plan(good, state: LatchState(), clock: c)) == .ruleMissing, "missing rule")
    var tampered = c; tampered.wallNow = c.guardedNow.addingTimeInterval(400)
    expect(refusal(ConditionalStart.plan(good, state: state, clock: tampered)) == .clockChanged, "clock changed")
    let notAtHome = request(r, c, location: fix(north: 5000))
    expect(refusal(ConditionalStart.plan(notAtHome, state: state, clock: c)) == .conditionsNotMet, "not at home started")
    let forged = request(r, clock("2026-11-16T12:00:00+01:00"), results: [true, true])
    expect(refusal(ConditionalStart.plan(forged, state: state, clock: clock("2026-11-16T12:00:00+01:00"))) == .conditionsNotMet,
           "Monday started a Sunday rule from a forged stamp")
    var short = good; short.stamp.results = [true]
    expect(refusal(ConditionalStart.plan(short, state: state, clock: c)) == .conditionsNotMet, "result count")
    for minutes in [0, 61, -5] {
        var bad = good; bad.minutes = minutes
        expect(refusal(ConditionalStart.plan(bad, state: state, clock: c)) == .invalidLength, "length \(minutes)")
    }
    var running = state
    var session = BlockSession(name: "Rule", kind: .free, selection: FamilyActivitySelection(),
                               startedAt: c.wallNow, endsAt: c.wallNow.addingTimeInterval(60))
    session.conditionalRuleID = r.id
    running.sessions = [session]
    expect(refusal(ConditionalStart.plan(good, state: running, clock: c)) == .alreadyRunning, "second running session")
    running.sessions[0].endsAt = c.wallNow
    guard case .success(let replaced) = ConditionalStart.plan(good, state: running, clock: c) else {
        expect(false, "finished session blocked a new one"); return
    }
    expect(replaced.replacedSessionIDs == [session.id], "finished same-rule session not replaced")
    var spent = state
    spent.conditionalUses = [ConditionalUseRecord(ruleID: r.id, day: "2026-11-15", count: 1, lastUsedAt: c.guardedNow)]
    expect(refusal(ConditionalStart.plan(good, state: spent, clock: c)) == .noUsesLeft, "cap passed")
    var reused = state
    reused.conditionalUses = [ConditionalUseRecord(ruleID: r.id, day: "2026-11-14", count: 1,
                                                   lastUsedAt: c.guardedNow, checkInIDs: [good.stamp.checkInID])]
    expect(refusal(ConditionalStart.plan(good, state: reused, clock: c)) == .checkInUsed, "check-in reused")
    let late = rule([sunday], outcome: free(60))
    let lateClock = clock("2026-11-15T23:59:30+01:00")
    expect(refusal(ConditionalStart.plan(request(late, lateClock), state: planState(late), clock: lateClock)) == .windowEnded,
           "30-second start spent a use")
}
scenario("per-day cap across midnight and across a time-zone switch; no refund") {
    let r = rule([.place(home)], outcome: free(30, uses: 1))
    var state = planState(r)
    let evening = clock("2026-11-15T23:00:00+01:00")
    guard case .success(let plan) = ConditionalStart.plan(request(r, evening, minutes: 30, location: fix(north: 0)),
                                                           state: state, clock: evening) else { expect(false, "first use"); return }
    state.conditionalUses = plan.uses
    state.sessions = [plan.session]
    // Ending early (session removed) refunds nothing.
    state.sessions = []
    let beforeMidnight = clock("2026-11-15T23:59:00+01:00")
    expect(refusal(ConditionalStart.plan(request(r, beforeMidnight, minutes: 30, location: fix(north: 0)),
                                         state: state, clock: beforeMidnight)) == .noUsesLeft, "refund after ending early")
    let afterMidnight = clock("2026-11-16T00:01:00+01:00")
    expect(refusal(ConditionalStart.plan(request(r, afterMidnight, minutes: 30, location: fix(north: 0)),
                                         state: state, clock: afterMidnight)) == nil, "new day still spent")
    // Switch to Mexico, where it is still Sunday: both zones' days count.
    let mexicoSunday = clock("2026-11-15T17:01:00-06:00", zone: "America/Mexico_City", recent: ["Europe/Madrid"])
    var madridMonday = state
    guard case .success(let mondayPlan) = ConditionalStart.plan(request(r, afterMidnight, minutes: 30, location: fix(north: 0)),
                                                                state: state, clock: afterMidnight) else { return }
    madridMonday.conditionalUses = mondayPlan.uses
    expect(refusal(ConditionalStart.plan(request(r, mexicoSunday, minutes: 30, location: fix(north: 0)),
                                         state: madridMonday, clock: mexicoSunday)) == .noUsesLeft,
           "time-zone switch reopened a spent day")
}
scenario("block plan: until time, window cap, not stale after its stricter wait") {
    let r = rule([.place(home), .time(start: 8 * 60, end: 15 * 60)], .all,
                 outcome: .block(mode: .blockSelected, selection: apps, until: .time(17 * 60)))
    let c = clock("2026-11-16T14:00:00+01:00")
    let req = request(r, c, location: fix(north: 0))
    guard case .success(let plan) = ConditionalStart.plan(req, state: planState(r), clock: c) else {
        expect(false, "block refused"); return
    }
    expect(plan.session.kind == .block && plan.session.selection == apps, "block session shape")
    expect(plan.session.endsAt == date("2026-11-16T15:00:00+01:00"), "block not capped at the window end")
    expect(plan.uses.isEmpty, "block counted a free-time use")
    let later = clock("2026-11-16T14:30:00+01:00")
    expect(refusal(ConditionalStart.plan(req, state: planState(r), clock: later, phase: .apply)) == nil,
           "block dropped as stale after waiting its stricter delay")
    expect(refusal(ConditionalStart.plan(req, state: planState(r), clock: later)) == .stampStale, "queue accepted stale stamp")
    let past = clock("2026-11-16T15:30:00+01:00")
    expect(refusal(ConditionalStart.plan(req, state: planState(r), clock: past, phase: .apply)) == .conditionsNotMet,
           "block started after its window ended")
    let anyRule = rule([.place(home), night], .any, outcome: blockUntilSeven)
    let evening = clock("2026-11-16T20:00:00+01:00")
    guard case .success(let anyPlan) = ConditionalStart.plan(request(anyRule, evening, location: fix(north: 0)),
                                                             state: planState(anyRule), clock: evening) else {
        expect(false, "any-of block refused"); return
    }
    expect(anyPlan.session.endsAt == date("2026-11-17T07:00:00+01:00"), "until 07:00 not the next 07:00")
    let freeRule = rule([sunday], outcome: free())
    let freeReq = request(freeRule, clock("2026-11-15T12:00:00+01:00"))
    expect(refusal(ConditionalStart.plan(freeReq, state: planState(freeRule), clock: clock("2026-11-15T12:03:00+01:00"),
                                         phase: .apply)) == .stampStale, "free time not revalidated at apply")
}

// Owned block windows and capacity -------------------------------------------
scenario("owned windows: stable IDs, only any-of time branches") {
    let r = rule([.place(home), night], .any, outcome: blockUntilSeven)
    let owned = r.ownedSchedules()
    expect(owned.count == 1 && owned[0].startMinutes == 22 * 60 && owned[0].endMinutes == 6 * 60
           && owned[0].mode == .blockSelected && owned[0].selection == apps && owned[0].ownerRuleID == r.id
           && owned[0].recurrence == .daily && owned[0].addedAt == r.addedAt, "owned window shape")
    expect(owned[0].id == r.ownedSchedules()[0].id && owned[0].id != r.id, "owned ID not stable")
    expect(rule([.place(home), night], .all, outcome: blockUntilSeven).ownedSchedules().isEmpty, "all-of owns windows")
    expect(rule([.place(home), night], .any).ownedSchedules().isEmpty, "free-time rule owns windows")
}
scenario("capacity: latent session and free window reserved, start adds nothing, five rules bounded") {
    var state = LatchState()
    state.limits = [AppLimit(name: "Budget", selection: apps, minutesPerDay: 30)]
    let base = MonitoringBudget.profile(state: state)
    let r = rule([sunday], outcome: free())
    var withRule = state; withRule.conditionalRules = [r]
    let profile = MonitoringBudget.profile(state: withRule)
    expect(profile.subtracting(base) == [r.sessionActivityName, "latch.freewin"], "free rule reservations: \(profile.subtracting(base))")
    var unblock = state; unblock.conditionalRules = [rule([sunday], outcome: free(kind: .unblock))]
    expect(!MonitoringBudget.profile(state: unblock).contains("latch.freewin"), "unblock rule reserved the free window")
    let c = ConditionalClockInput.current(for: withRule)
    let start = ChangeAction.startConditionalSession(request(r, c))
    let projected = MonitoringBudget.project(start, onto: withRule)
    expect(MonitoringBudget.profile(state: projected) == profile, "start needs a slot beyond the reservation")
    let block = rule([.place(home), night], .any, outcome: blockUntilSeven)
    var blocked = state; blocked = MonitoringBudget.project(.addConditionalRule(block), onto: blocked)
    expect(MonitoringBudget.profile(state: blocked).subtracting(base)
           == Set([block.sessionActivityName] + MonitoringBudget.windows(prefix: "sched-\(block.ownedSchedules()[0].id.uuidString)",
                                                                        start: 22 * 60, end: 6 * 60, recurrence: .daily).map(\.name)),
           "block rule reservations")
    var five = state
    for index in 0..<4 { five.conditionalRules.append(rule([sunday], outcome: free(), name: "Free \(index)")) }
    five = MonitoringBudget.project(.addConditionalRule(block), onto: five)
    let added = MonitoringBudget.profile(state: five).subtracting(base).count
    expect(added == 8, "five-rule worst case: \(added) names")
    expect(MonitoringBudget.isRepair(.removeConditionalRule(id: block.id), state: five), "removal not a repair")
    expect(!MonitoringBudget.isRepair(.removeConditionalRule(id: UUID()), state: five), "unknown removal repair")
    let removed = MonitoringBudget.project(.removeConditionalRule(id: block.id), onto: five)
    expect(!removed.schedules.contains { $0.ownerRuleID == block.id }, "owned window survived removal projection")
    let kept = MonitoringBudget.project(.removeConditionalRule(id: block.id), onto: five, includeRemovals: false)
    expect(kept.conditionalRules.count == 5, "pending removal borrowed capacity")
}

// Real engine ---------------------------------------------------------------
func engineState(strict: TimeInterval = 300, lenient: TimeInterval = 900) -> LatchState {
    var state = LatchState()
    state.isSetUp = true
    state.delayPolicy = DelayPolicy(mode: .separate, strictDelay: strict, lenientDelay: lenient)
    return state
}
let todayRule = { (outcome: ConditionalOutcome) -> ConditionalRule in
    rule([.days(Set(1...7))], outcome: outcome, name: "Any day")
}
func liveRequest(_ r: ConditionalRule, minutes: Int = 30, location: ConditionalLocationInput = .notRead,
                 results: [Bool]? = nil) -> ConditionalStartRequest {
    let c = ConditionalClockInput.current(for: SharedStore.state)
    return request(r, c, minutes: minutes, results: results, location: location)
}
scenario("classification, capabilities and conflict keys") {
    let state = engineState()
    let freeRule = rule([sunday]), blockRule = rule([.place(home)], outcome: blockUntilSeven)
    var both = state; both.conditionalRules = [freeRule, blockRule]
    expect(ChangeEngine.classify(.addConditionalRule(freeRule), state: state) == .lenient, "add free")
    expect(ChangeEngine.classify(.addConditionalRule(blockRule), state: state) == .stricter, "add block")
    expect(ChangeEngine.classify(.updateConditionalRule(blockRule), state: both) == .lenient, "update block")
    expect(ChangeEngine.classify(.updateConditionalRule(freeRule), state: both) == .lenient, "update free")
    expect(ChangeEngine.classify(.removeConditionalRule(id: freeRule.id), state: both) == .stricter, "remove free")
    expect(ChangeEngine.classify(.removeConditionalRule(id: blockRule.id), state: both) == .lenient, "remove block")
    expect(ChangeEngine.classify(.removeConditionalRule(id: UUID()), state: both) == .lenient, "remove unknown")
    let c = ConditionalClockInput.current(for: both)
    expect(ChangeEngine.classify(.startConditionalSession(request(freeRule, c)), state: both) == .lenient, "start free")
    expect(ChangeEngine.classify(.startConditionalSession(request(blockRule, c)), state: both) == .stricter, "start block")
    for action in [ChangeAction.addConditionalRule(freeRule), .updateConditionalRule(freeRule),
                   .removeConditionalRule(id: freeRule.id)] {
        expect(ChangeEngine.overrideCapability(for: action) == .scheduleChanges, "rule capability")
        expect(ChangeEngine.conflictKey(action) == "conditional-\(freeRule.id.uuidString)", "rule conflict key")
    }
    let start = ChangeAction.startConditionalSession(request(freeRule, c))
    expect(ChangeEngine.overrideCapability(for: start) == .sessionChanges, "start capability")
    expect(ChangeEngine.conflictKey(start) == "conditionalStart-\(freeRule.id.uuidString)", "start conflict key")
}
scenario("summaries read the rule back, names only") {
    var mx = rule([mexico, sunday], outcome: free(60), name: "Sunday in Mexico")
    mx.conditions = [mexico, sunday]
    let english = Locale(identifier: "en_US")
    var english_calendar = Calendar(identifier: .gregorian); english_calendar.locale = english
    expect(ConditionalSummary.sentence(mx, locale: english, calendar: english_calendar)
           == "If in Mexico and on Sun: 60 min free, once a day.",
           "sentence: \(ConditionalSummary.sentence(mx, locale: english, calendar: english_calendar))")
    let homeRule = rule([.place(home), night], .any, outcome: blockUntilSeven, name: "Instagram at home")
    expect(ConditionalSummary.sentence(homeRule, locale: english, calendar: english_calendar)
           == "If at Home or 22:00–06:00: block until 07:00.", "any-of sentence")
    let school = rule([.place(home), weekend], outcome: free(30, uses: 2))
    expect(ConditionalSummary.sentence(school, locale: english, calendar: english_calendar)
           == "If at Home and on weekends: 30 min free, 2 times a day.", "uses sentence")
    let summary = ChangeEngine.summary(for: .addConditionalRule(homeRule), state: engineState())
    expect(summary.hasPrefix("Add When & where rule: Instagram at home. If at Home or 22:00–06:00"), "add summary: \(summary)")
    for forbidden in ["40.4", "-3.70", "250"] { expect(!summary.contains(forbidden), "summary leaks \(forbidden)") }
    var state = engineState(); state.conditionalRules = [homeRule]
    expect(ChangeEngine.summary(for: .removeConditionalRule(id: homeRule.id), state: state)
           == "Remove When & where rule: Instagram at home", "remove summary")
}
scenario("adding a free-time rule waits the looser delay and records the time zone") {
    SharedStore.state = engineState()
    let r = todayRule(free())
    let change = ChangeEngine.queue(.addConditionalRule(r))
    expect(change?.direction == .lenient && change?.appliesAt == change.map { $0.createdAt.addingTimeInterval(900) },
           "free-time rule not on the looser delay")
    expect(SharedStore.state.conditionalRules.isEmpty, "rule applied early")
    expect(ChangeEngine.queue(.addConditionalRule(r)) == nil, "second pending change for the same rule")
    TimeGuard.offset = 899; ChangeEngine.applyDueChanges()
    expect(SharedStore.state.conditionalRules.isEmpty, "rule applied a second early")
    TimeGuard.offset = 901
    ChangeEngine.applyDueChanges()
    TimeGuard.offset = 0
    expect(SharedStore.state.conditionalRules == [r], "rule not applied")
    expect(SharedStore.state.timeZoneEvidence?.currentID == TimeZone.current.identifier, "zone not recorded with the rule")
    expect(ChangeEngine.windowReconfigurations == 0, "free-time rule restarted window monitors")
}
scenario("block rule: stricter to add, owns its window, edits and removal") {
    SharedStore.state = engineState(strict: 300, lenient: 900)
    let r = rule([.place(home), night], .any, outcome: blockUntilSeven, name: "Instagram at home")
    let change = ChangeEngine.queue(.addConditionalRule(r))!
    expect(change.direction == .stricter && change.appliesAt == change.createdAt.addingTimeInterval(300), "block add delay")
    TimeGuard.offset = 301; ChangeEngine.applyDueChanges(); TimeGuard.offset = 0
    let owned = SharedStore.state.schedules
    expect(owned.count == 1 && owned[0].ownerRuleID == r.id && owned[0].id == r.ownedSchedules()[0].id, "owned window missing")
    expect(ChangeEngine.windowReconfigurations == 1, "owned window not registered")
    // Owned windows change only with their rule.
    expect(ChangeEngine.queue(.removeSchedule(id: owned[0].id)) == nil, "owned window removed directly")
    expect(ChangeEngine.queue(.updateScheduleSelection(id: owned[0].id, selection: FamilyActivitySelection(applicationTokens: ["x"]))) == nil,
           "owned window edited directly")
    var forged = BlockSchedule(name: "Forged", mode: .blockSelected, selection: apps, startMinutes: 60, endMinutes: 120)
    forged.ownerRuleID = r.id
    expect(ChangeEngine.queue(.addSchedule(forged)) == nil, "schedule claimed an owner")
    // Same configuration is not an edit.
    expect(ChangeEngine.queue(.updateConditionalRule(r)) == nil, "no-op edit queued")
    // Selection-only edit: looser, keeps ID/addedAt, bumps revision, no window restart.
    var edited = r; edited.outcome = .block(mode: .blockSelected, selection: FamilyActivitySelection(applicationTokens: ["y"]),
                                            until: .time(420)); edited.addedAt = Date(); edited.revision = 99
    let edit = ChangeEngine.queue(.updateConditionalRule(edited))!
    expect(edit.direction == .lenient && edit.appliesAt == edit.createdAt.addingTimeInterval(900), "edit not looser")
    TimeGuard.offset = 901; ChangeEngine.applyDueChanges(); TimeGuard.offset = 0
    let applied = SharedStore.state.conditionalRules[0]
    expect(applied.revision == 1 && applied.addedAt == r.addedAt && applied.id == r.id, "edit identity")
    expect(SharedStore.state.schedules.count == 1 && SharedStore.state.schedules[0].selection.applicationTokens == ["y"]
           && SharedStore.state.schedules[0].id == owned[0].id, "owned window not replaced in place")
    expect(ChangeEngine.windowReconfigurations == 1, "selection-only edit restarted window monitors")
    // A running check-in session survives the rule's removal (C14).
    var session = BlockSession(name: r.name, kind: .block, selection: apps, startedAt: Date(),
                               endsAt: Date().addingTimeInterval(3600))
    session.conditionalRuleID = r.id
    SharedStore.state.sessions = [session]
    let removal = ChangeEngine.queue(.removeConditionalRule(id: r.id))!
    expect(removal.direction == .lenient, "removing a block rule not looser")
    TimeGuard.offset = 901; ChangeEngine.applyDueChanges(); TimeGuard.offset = 0
    expect(SharedStore.state.conditionalRules.isEmpty && SharedStore.state.schedules.isEmpty, "removal left the rule or window")
    expect(SharedStore.state.sessions == [session], "removal ended the running session")
    expect(ChangeEngine.windowReconfigurations == 2, "removal did not stop the owned window")
}
scenario("validation in the queue: invalid rules, five-rule cap including pending additions") {
    SharedStore.state = engineState()
    expect(ChangeEngine.queue(.addConditionalRule(rule([]))) == nil, "invalid rule queued")
    expect(ChangeEngine.queue(.removeConditionalRule(id: UUID())) == nil, "unknown removal queued")
    expect(ChangeEngine.queue(.updateConditionalRule(rule([sunday]))) == nil, "unknown edit queued")
    for index in 0..<3 { SharedStore.state.conditionalRules.append(rule([sunday], name: "R\(index)")) }
    expect(ChangeEngine.queue(.addConditionalRule(rule([sunday], name: "Fourth"))) != nil, "fourth refused")
    expect(ChangeEngine.queue(.addConditionalRule(rule([sunday], name: "Fifth"))) != nil, "fifth refused")
    expect(ChangeEngine.queue(.addConditionalRule(rule([sunday], name: "Sixth"))) == nil, "sixth (pending) accepted")
    expect(SharedStore.state.pending.count == 2, "rejection changed pending")
}
scenario("check-in free time starts at once, counts one use, registers the rule's activity") {
    SharedStore.state = engineState(lenient: 86_400)
    let r = todayRule(free(60, uses: 1))
    SharedStore.state.conditionalRules = [r]
    let req = liveRequest(r, minutes: 30)
    let result = ChangeEngine.startForTest(req)
    guard case .started(let session) = result else { expect(false, "not started: \(result)"); return }
    expect(session.conditionalRuleID == r.id && session.kind == .free, "session shape")
    expect(abs(session.endsAt.timeIntervalSince(session.startedAt) - 1800) < 1 || session.endsAt <= session.startedAt.addingTimeInterval(1800),
           "length not honoured")
    expect(SharedStore.state.pending.isEmpty, "free start left a pending change")
    expect(ChangeEngine.scheduledApplyIDs.isEmpty && ChangeEngine.notifiedIDs.isEmpty, "free start waited")
    expect(ChangeEngine.cleanupActivities == [r.sessionActivityName], "cleanup activity not the rule's name")
    expect(ConditionalUses.used(ruleID: r.id, dayKeys: [ConditionalUses.dayKey(for: TimeGuard.now(), calendar: .current)],
                                in: SharedStore.state.conditionalUses) == 1, "use not counted")
    expect(SharedStore.state.timeZoneEvidence?.currentID == TimeZone.current.identifier, "check-in did not observe the zone")
    // While running: refused. After it ends: no uses left today, no refund.
    expect(ChangeEngine.startForTest(liveRequest(r)) == .refused(.alreadyRunning), "second session while running")
    SharedStore.state.sessions[0].endsAt = Date().addingTimeInterval(-1)
    expect(ChangeEngine.startForTest(liveRequest(r)) == .refused(.noUsesLeft), "past the daily cap")
    // The same check-in can never start twice, even with uses left.
    var two = todayRule(free(60, uses: 2)); two.id = r.id; two.revision = r.revision
    SharedStore.state.conditionalRules = [two]
    expect(ChangeEngine.startForTest(req) == .refused(.checkInUsed), "check-in replayed")
}
scenario("a failed check-in never falls back to a delayed or overridable start") {
    SharedStore.state = engineState(lenient: 900)
    let r = rule([.place(home)], outcome: free())
    SharedStore.state.conditionalRules = [r]
    let saves = SharedStore.saves
    expect(ChangeEngine.startForTest(liveRequest(r, location: fix(north: 5000))) == .refused(.conditionsNotMet), "not met started")
    expect(ChangeEngine.queue(.startConditionalSession(liveRequest(r, location: fix(north: 5000)))) == nil,
           "direct queue accepted a failed check-in")
    expect(SharedStore.state.pending.isEmpty && SharedStore.state.sessions.isEmpty, "failed check-in left something behind")
    expect(ChangeEngine.scheduledApplyIDs.isEmpty, "failed check-in scheduled a delayed start")
    expect(SharedStore.saves - saves <= 1, "failed check-in wrote state beyond the zone record")
    // Due changes must land first.
    SharedStore.state.pending = [PendingChange(createdAt: Date(), appliesAt: Date().addingTimeInterval(-5), direction: .stricter,
                                               summary: "Due", action: .setBlockAdultWebsites(true))]
    expect(ChangeEngine.queue(.startConditionalSession(liveRequest(r, location: fix(north: 0)))) == nil,
           "start queued while a due change was unapplied")
    // In recovery nothing starts.
    SharedStore.state.pending = []
    SharedStore.stateRecoveryNeeded = true
    expect(ChangeEngine.startForTest(liveRequest(r, location: fix(north: 0))) == .refused(.unavailable), "started in recovery")
}
scenario("a stale pending start is dropped at apply, nothing counted") {
    SharedStore.state = engineState()
    let r = todayRule(free())
    SharedStore.state.conditionalRules = [r]
    var req = liveRequest(r)
    req.stamp.guardedAt = TimeGuard.now().addingTimeInterval(-180)
    SharedStore.state.pending = [PendingChange(createdAt: Date().addingTimeInterval(-180), appliesAt: Date().addingTimeInterval(-180),
                                               direction: .lenient, summary: "Stale", action: .startConditionalSession(req))]
    ChangeEngine.applyDueChanges()
    expect(SharedStore.state.pending.isEmpty && SharedStore.state.sessions.isEmpty
           && SharedStore.state.conditionalUses.isEmpty, "stale start applied")
    // A pending start for an edited rule is stale too.
    let fresh = liveRequest(r)
    SharedStore.state.conditionalRules[0].revision = 1
    var copy = SharedStore.state
    ChangeEngine.applyForTest(.startConditionalSession(fresh), state: &copy)
    expect(copy.sessions.isEmpty, "start for an old revision applied")
}
scenario("check-in block follows the stricter wait (C4); instant when the policy tightens at once") {
    SharedStore.state = engineState(strict: 600, lenient: 900)
    let r = rule([.place(home)], outcome: .block(mode: .blockSelected, selection: apps, until: .duration(minutes: 90)))
    SharedStore.state.conditionalRules = [r]
    let result = ChangeEngine.startForTest(liveRequest(r, location: fix(north: 0)))
    guard case .waiting(let change) = result else { expect(false, "block did not wait: \(result)"); return }
    expect(change.direction == .stricter && change.appliesAt == change.createdAt.addingTimeInterval(600), "block delay")
    expect(ChangeEngine.scheduledApplyIDs == [change.id], "block wait not scheduled")
    TimeGuard.offset = 601; ChangeEngine.applyDueChanges(); TimeGuard.offset = 0
    expect(SharedStore.state.sessions.count == 1 && SharedStore.state.sessions[0].kind == .block
           && SharedStore.state.sessions[0].conditionalRuleID == r.id, "block not started after its wait")
    expect(SharedStore.state.conditionalUses.isEmpty, "block counted a use")
    SharedStore.state = engineState(strict: 600, lenient: 900)
    SharedStore.state.delayPolicy = DelayPolicy(mode: .lenientOnly, strictDelay: 0, lenientDelay: 900)
    SharedStore.state.conditionalRules = [r]
    guard case .started(let session) = ChangeEngine.startForTest(liveRequest(r, location: fix(north: 0))) else {
        expect(false, "instant tightening did not start the block"); return
    }
    expect(session.kind == .block, "instant block kind")
}
scenario("capacity admission: a rule that doesn't fit is refused; removal is a repair") {
    SharedStore.state = engineState()
    SharedStore.state.limits = [AppLimit(name: "Budget", selection: apps, minutesPerDay: 30)]
    SharedStore.state.schedules = (0..<16).map {
        BlockSchedule(name: "S\($0)", mode: .blockSelected, selection: apps, startMinutes: 600, endMinutes: 660)
    }
    // 16 windows + daily = 17; a free rule needs its pending wake, its latent
    // session and latch.freewin = 20. A second one needs two more.
    let first = rule([sunday], outcome: free(), name: "First")
    expect(ChangeEngine.queue(.addConditionalRule(first)) != nil, "a fitting rule refused")
    let before = try encoded(SharedStore.state)
    expect(ChangeEngine.queue(.addConditionalRule(rule([sunday], outcome: free(), name: "Second"))) == nil,
           "over-capacity rule admitted")
    let after = try encoded(SharedStore.state)
    expect(after == before, "refusal changed saved state")
    SharedStore.state.pending = []
    SharedStore.state.conditionalRules = [first]
    SharedStore.state.schedules += [BlockSchedule(name: "Over", mode: .blockSelected, selection: apps,
                                                  startMinutes: 700, endMinutes: 760)]
    expect(ChangeEngine.queue(.removeConditionalRule(id: first.id)) != nil, "removal blocked on an over-budget install")
}
scenario("time-zone observation writes only on change and only with rules") {
    SharedStore.state = engineState()
    ChangeEngine.observeTimeZone()
    expect(SharedStore.saves == 0 && SharedStore.state.timeZoneEvidence == nil, "observed without rules")
    SharedStore.state.conditionalRules = [rule([sunday])]
    ChangeEngine.observeTimeZone()
    expect(SharedStore.saves == 1 && SharedStore.state.timeZoneEvidence?.currentID == TimeZone.current.identifier,
           "first observation not recorded")
    ChangeEngine.observeTimeZone()
    expect(SharedStore.saves == 1, "unchanged zone wrote state")
    SharedStore.state.timeZoneEvidence = TimeZoneEvidence(currentID: "Asia/Tokyo")
    ChangeEngine.observeTimeZone()
    expect(SharedStore.state.timeZoneEvidence?.lastSeen["Asia/Tokyo"] != nil, "change not recorded")
}
scenario("rollover prune: old use records only") {
    SharedStore.state = engineState()
    let id = UUID()
    let recent = ConditionalUseRecord(ruleID: id, day: "a", count: 1, lastUsedAt: TimeGuard.now().addingTimeInterval(-3600))
    let old = ConditionalUseRecord(ruleID: id, day: "b", count: 1, lastUsedAt: TimeGuard.now().addingTimeInterval(-80 * 3600))
    SharedStore.state.conditionalUses = [recent]
    ChangeEngine.pruneConditionalUses()
    expect(SharedStore.saves == 0, "nothing to prune but state written")
    SharedStore.state.conditionalUses = [recent, old]
    ChangeEngine.pruneConditionalUses()
    expect(SharedStore.state.conditionalUses == [recent], "prune wrong")
}

for failure in failures { print("FAIL: \(failure)") }
print("When & where checks: \(scenarios) scenarios, \(assertions) assertions, \(failures.count) failures")
print("Real models/evaluator/plan, budget, queue/apply/due dispatcher; stubbed storage, clock, monitors and tokens")
if !failures.isEmpty { exit(1) }

// Blobs for the older-build decode check.
let outDir = CommandLine.arguments[1]
var compatible = engineState()
let blockRule = rule([.place(home), night], .any, outcome: blockUntilSeven)
compatible.conditionalRules = [blockRule, rule([sunday])]
compatible.schedules = blockRule.ownedSchedules()
compatible.conditionalUses = [ConditionalUseRecord(ruleID: blockRule.id, day: "2026-11-15", count: 1, lastUsedAt: Date())]
compatible.timeZoneEvidence = TimeZoneEvidence(currentID: "Europe/Madrid", lastSeen: ["Asia/Tokyo": Date()])
var conditionalSession = BlockSession(name: "Rule", kind: .free, selection: FamilyActivitySelection(),
                                      startedAt: Date(), endsAt: Date().addingTimeInterval(600))
conditionalSession.conditionalRuleID = blockRule.id
compatible.sessions = [conditionalSession]
try! JSONEncoder().encode(compatible).write(to: URL(fileURLWithPath: outDir + "/compatible.json"))
var withPending = compatible
withPending.pending = [PendingChange(createdAt: Date(), appliesAt: Date().addingTimeInterval(900), direction: .lenient,
                                     summary: "Add", action: .addConditionalRule(rule([sunday])))]
try! JSONEncoder().encode(withPending).write(to: URL(fileURLWithPath: outDir + "/pending.json"))
'''

old_checks = r'''
let dir = CommandLine.arguments[1]
let compatible = try! Data(contentsOf: URL(fileURLWithPath: dir + "/compatible.json"))
let state = try! JSONDecoder().decode(LatchState.self, from: compatible)
precondition(state.isSetUp && state.schedules.count == 1 && state.sessions.count == 1,
             "older build lost rules from a state with When & where data")
let pending = try! Data(contentsOf: URL(fileURLWithPath: dir + "/pending.json"))
let unreadable = (try? JSONDecoder().decode(LatchState.self, from: pending)) == nil
precondition(unreadable, "expected: an older build cannot decode a pending When & where change")
print("Older build (\(CommandLine.arguments[2])): decodes saved When & where data (ignores new keys); a pending When & where change sends it to the existing recovery state")
'''

baseline_models = subprocess.run(["git", "show", f"{BASELINE}:Shared/SharedModels.swift"], cwd=ROOT,
                                 check=True, capture_output=True, text=True).stdout
old_infrastructure = r'''
import Foundation
struct FamilyActivitySelection: Codable, Equatable {
    var applicationTokens: Set<String> = []
    var categoryTokens: Set<String> = []
    var webDomainTokens: Set<String> = []
}
func tr(_ key: String) -> String { key }
enum TimeGuard { static func now() -> Date { Date() } }
'''

source = (infrastructure + models + phrases + budget + precedence + admission
          + block(engine, "func mathStrictnessScore(")
          + "\nenum ChangeEngine {\n" + methods + driver + "\n}\n" + checks)
old_source = old_infrastructure + portable(baseline_models) + subprocess.run(
    ["git", "show", f"{BASELINE}:Shared/PhraseWords.swift"], cwd=ROOT, check=True,
    capture_output=True, text=True).stdout + old_checks
with tempfile.TemporaryDirectory(prefix="demora-when-where-") as directory:
    path = Path(directory)
    (path / "new.swift").write_text(source)
    (path / "old.swift").write_text(old_source)
    subprocess.run(["xcrun", "swiftc", str(path / "new.swift"), "-o", str(path / "new")], check=True)
    subprocess.run(["xcrun", "swiftc", str(path / "old.swift"), "-o", str(path / "old")], check=True)
    env = {**os.environ, "TZ": "Europe/Madrid"}
    subprocess.run([str(path / "new"), directory], check=True, env=env)
    subprocess.run([str(path / "old"), directory, BASELINE], check=True, env=env)
