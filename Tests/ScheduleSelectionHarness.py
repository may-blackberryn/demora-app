#!/usr/bin/env python3
"""Run: python3 Tests/ScheduleSelectionHarness.py

Compile the real models and complete relevant ChangeEngine methods on macOS.
Only opaque Screen Time tokens, storage, clock and notification/monitor effects
are substituted. No production branch is rewritten. Phrase proofs and extra-time
authorization use the real implementation as well.
The real due-change dispatcher is compiled too; latency hooks stand in for its
cleanup XPC and the extra-time monitor/file-coordination boundaries.
"""
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
engine = (ROOT / "Shared/ChangeEngine.swift").read_text()
models = (ROOT / "Shared/SharedModels.swift").read_text()
features = (ROOT / "Shared/LimitFeatures.swift").read_text()
phrases = (ROOT / "Shared/PhraseWords.swift").read_text()
budget = (ROOT / "Shared/MonitoringBudget.swift").read_text()
precedence = (ROOT / "Shared/SchedulePrecedence.swift").read_text().replace("import FamilyControls\n", "")
registration = (ROOT / "Shared/MonitorRegistration.swift").read_text()


def block(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


models = models.replace("import FamilyControls\n", "").replace(
    "import ManagedSettings\n", ""
)
methods = "\n".join(block(engine, signature) for signature in [
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
    "static func requestExtraTimeOffMain(",
    "static func applyNowWithPasswordOffMain(",
    "static func applyNowWithPhraseOffMain(",
    "static func applyNowWithContactOffMain(",
    "private static func contactPermitted(",
    "static func grantContactExtraTimeOffMain(",
    "private static func applyNow(changeIDs:",
    "static func hasUnappliedDueChanges(",
    "static func applyDueChanges(",
    "private static func preserveDailyMonitoringForWakeEdit(",
    "private static func dailyMonitorFingerprint(",
])

infrastructure = r'''
import Foundation
struct FamilyActivitySelection: Codable, Equatable {
    var includeEntireCategory = false
    var applicationTokens: Set<String> = []
    var categoryTokens: Set<String> = []
    var webDomainTokens: Set<String> = []
}
func tr(_ key: String) -> String { key }
enum TimeGuard {
    static var date = Date(timeIntervalSince1970: 2_000_000_000)
    static func now() -> Date { date }
}
enum Latency {
    static var cleanup: (() -> Void)?
    static var monitor: (() -> Void)?
    static var coordination: (() -> Void)?
    static var onLoad: ((Int) -> Void)?
    static var reads = 0
    static var cleanupCalls = 0
    static func reset() {
        cleanup = nil; monitor = nil; coordination = nil; onLoad = nil
        reads = 0; cleanupCalls = 0
    }
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
    static var rejectSave = false
    static var blockedIDs: Set<UUID> = []
    static var usageResetCalls = 0
    static var coordinated = false
    static func coordinateStateMutation<T>(_ body: () -> T) -> T? {
        precondition(!coordinated)
        coordinated = true
        defer { coordinated = false }
        return body()
    }
    static let defaults = TestDefaults()
    static func loadState() -> LatchState {
        Latency.reads += 1
        Latency.onLoad?(Latency.reads)
        return state
    }
    @discardableResult static func save(_ value: LatchState) -> Bool {
        if rejectSave { return false }
        state = value; return true
    }
    static func mutateBlockedLimitIDs(_ edit: (inout Set<UUID>) -> Void) {
        usageResetCalls += 1; edit(&blockedIDs)
    }
    static func loadBlockedLimitIDs() -> Set<UUID> { blockedIDs }
    static func dayKey(for date: Date) -> String { String(Int(date.timeIntervalSince1970 / 86400)) }
    static func loadFreeCreditByLimit() -> [UUID: Int] { [:] }
}
struct DeviceActivityName: Equatable {
    var rawValue: String
    init(_ value: String) { rawValue = value }
}
struct DeviceActivityCenter {
    static var running: Set<String> = [LatchConstants.dailyActivityName]
    var activities: [DeviceActivityName] {
        precondition(!SharedStore.coordinated, "monitor XPC under state coordination")
        let hook = Latency.monitor; Latency.monitor = nil; hook?()
        return Self.running.map(DeviceActivityName.init)
    }
    func stopMonitoring(_ names: [DeviceActivityName]) {
        Latency.cleanupCalls += 1
        let hook = Latency.cleanup; Latency.cleanup = nil; hook?()
    }
}
enum ShieldController { static func refresh() {} }
struct UNUserNotificationCenter {
    static func current() -> Self { Self() }
    func removePendingNotificationRequests(withIdentifiers ids: [String]) {}
}
enum GlobalWake { static func clearTap() {} }
'''

driver = r'''
    static var scheduledApplyIDs: [UUID] = []
    static var notifiedIDs: [UUID] = []
    static func scheduleApplyActivity(for change: PendingChange) {
        precondition(!SharedStore.coordinated, "registration under state lock")
        scheduledApplyIDs.append(change.id)
    }
    static func scheduleNotification(for change: PendingChange) {
        precondition(!SharedStore.coordinated, "notification under state lock")
        notifiedIDs.append(change.id)
    }
    static func applyForTest(_ action: ChangeAction, state: inout LatchState) {
        apply(action, to: &state)
    }
    static func wakeState(for limit: AppLimit) -> WakeState { .awake }
    private static let deviceActivityWorkQueue = DispatchQueue(label: "test-serialized-enforcement")
    private static let trackedLimitSelectionsKey = "test-tracked"
    private static let freeWindowActivityName = "test-free"
    private static let dailyMonitorFingerprintKey = "latch.dailyMonitorFingerprint.v2"
    static func fingerprintForTest(_ state: LatchState) -> String { dailyMonitorFingerprint(state: state) }
    static func limitSelectionDigest(_ selection: FamilyActivitySelection) -> String {
        (selection.applicationTokens.sorted() + selection.categoryTokens.sorted()
            + selection.webDomainTokens.sorted()).joined(separator: ",")
    }
    static func prepareUsageCreditForSelectionEdit(ids: Set<UUID>, state: LatchState) -> Bool { false }
    static func isFreeWindowActive() -> Bool { false }
    static func startFreeWindowTracking() {}
    static func startSessionCleanupActivity(_ session: BlockSession) {}
    static func reconcileFreeWindow() {}
    static func reconfigureDailyMonitoring(state: LatchState) {}
    static func reconfigureWindowMonitoring(state: LatchState) {}
'''

monitor_checks = "\n".join(
    "static func " + method + "(_ due: [PendingChange]) -> Bool {\n"
    + ("let state = SharedStore.loadState()\n" if variable == "windowMonitoringChanged" else "")
    + block(engine, "let " + variable + " = due.contains")
    + "\nreturn " + variable + "\n}"
    for method, variable in [
        ("changesWindows", "windowMonitoringChanged"),
        ("changesDailyLimits", "dailyLimitsChanged"),
    ]
)

feature_driver = r'''
enum LimitFeatures {
    private static var values: [UUID: LimitFeatureEntry] = [:]
    private static let extraReleasePrefix = "limit-extra-release-"
    static func resetForTest() { values = [:] }
    static func requestsForTest(_ id: UUID) -> Int { entry(id).extraRequests }
    private static func entry(_ id: UUID, at date: Date = Date()) -> LimitFeatureEntry {
        values[id] ?? LimitFeatureEntry(day: SharedStore.dayKey(for: date))
    }
    private static func mutate(_ edit: (inout [UUID: LimitFeatureEntry]) -> Void) {
        let hook = Latency.coordination; Latency.coordination = nil; hook?()
        edit(&values)
    }
    private static func scheduleWake(for id: UUID, at date: Date, prefix: String) {}
    static func resetEditedLimits(_ ids: Set<UUID>) {
        if !ids.isEmpty { SharedStore.usageResetCalls += 1 }
    }
    static func prepareNewWakeGates(_ ids: Set<UUID>) -> Bool { true }
    static func clearSplitMarkers(for ids: Set<UUID>) {}
    static func reconfigureSplitMonitoring(state: LatchState) {}
    static func reconcile(state: LatchState) {}
'''
feature_logic = "\n".join(block(features, signature) for signature in [
    "enum WakeState:", "enum ExtraTimeState:", "private struct LimitFeatureEntry:",
]) + feature_driver + "\n".join(block(features, signature) for signature in [
    "static func extraTimeState(", "static func requestExtraTime(",
    "private static func extraTimeAuthorized(",
]) + "\n}\n"

checks = r'''
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
let app = FamilyActivitySelection(applicationTokens: ["A", "B"])
let added = FamilyActivitySelection(applicationTokens: ["A", "B", "C"])
let reduced = FamilyActivitySelection(applicationTokens: ["A"])
let replaced = FamilyActivitySelection(applicationTokens: ["C"])
let category = FamilyActivitySelection(categoryTokens: ["category"])
let website = FamilyActivitySelection(webDomainTokens: ["website"])
let empty = FamilyActivitySelection()
let recurrences: [Recurrence] = [.daily, .weekly([2, 4]), .monthlyDay(15),
                               .monthlyOrdinal(weekday: 2, ordinal: 3)]
var count = 0
for mode in ScheduleMode.allCases {
    for recurrence in recurrences {
        for selection in [added, reduced, replaced, category, website, empty] {
            let schedule = BlockSchedule(name: "Original", mode: mode, selection: app,
                startMinutes: 22 * 60, endMinutes: 7 * 60, recurrence: recurrence,
                addedAt: Date(timeIntervalSince1970: 123))
            var state = LatchState()
            state.strictDelay = 10
            state.lenientDelay = 600
            state.schedules = [schedule]
            SharedStore.save(state)
            let action = ChangeAction.updateScheduleSelection(id: schedule.id, selection: selection)
            expect(ChangeEngine.classify(action, state: state) == .lenient, "selection direction")
            expect(ChangeEngine.overrideCapability(for: action) == .scheduleChanges, "schedule scope")
            expect(ChangeEngine.summary(for: action, state: state) == "Change apps in Original", "summary")
            expect(ChangeEngine.conflictKey(action) == ChangeEngine.conflictKey(.removeSchedule(id: schedule.id)), "remove conflict")
            if selection == empty && mode == .blockSelected {
                expect(ChangeEngine.queue(action) == nil, "reject empty blocklist")
                ChangeEngine.applyForTest(action, state: &state)
                expect(state.schedules == [schedule], "persisted invalid edit is ignored")
                continue
            }
            guard let queued = ChangeEngine.queue(action) else { fatalError("valid edit rejected") }
            expect(queued.direction == .lenient, "queued direction")
            expect(queued.appliesAt == TimeGuard.now().addingTimeInterval(600), "lenient deadline")
            expect(SharedStore.state.schedules == [schedule], "queue changed active selection")
            expect(ChangeEngine.queue(action) == nil, "duplicate edit")
            expect(ChangeEngine.queue(.removeSchedule(id: schedule.id)) == nil, "edit conflicts with remove")
            expect(!ChangeEngine.changesWindows([queued]), "selection edit restarts window monitors")
            expect(!ChangeEngine.changesDailyLimits([queued]), "selection edit restarts daily monitors")
            let data = try JSONEncoder().encode(SharedStore.state)
            SharedStore.state = try JSONDecoder().decode(LatchState.self, from: data)
            expect(SharedStore.state.pending.first?.action == action, "pending action round trip")
            TimeGuard.date = queued.appliesAt.addingTimeInterval(-1)
            ChangeEngine.applyDueChanges()
            expect(SharedStore.state.schedules == [schedule], "edit applied early")
            TimeGuard.date = queued.appliesAt
            ChangeEngine.applyDueChanges()
            var expected = schedule
            expected.selection = selection
            expect(SharedStore.state.schedules == [expected], "identity/metadata or selection changed incorrectly")
            expect(SharedStore.state.pending.isEmpty, "due edit not consumed")
            ChangeEngine.applyDueChanges()
            expect(SharedStore.state.schedules == [expected], "repeat apply not idempotent")
            count += 1
        }
    }
}

var state = LatchState()
let schedule = BlockSchedule(name: "Conflict", mode: .blockSelected, selection: app,
                            startMinutes: 60, endMinutes: 120)
state.schedules = [schedule]
state.lenientDelay = 100
SharedStore.save(state)
let action = ChangeAction.updateScheduleSelection(id: schedule.id, selection: website)
expect(ChangeEngine.queue(.updateScheduleSelection(id: schedule.id, selection: app)) == nil, "unchanged selection queued")
expect(ChangeEngine.queue(.removeSchedule(id: schedule.id)) != nil, "remove rejected")
expect(ChangeEngine.queue(action) == nil, "remove conflicts with edit")
state.pending = []
SharedStore.save(state)
guard let pending = ChangeEngine.queue(action) else { fatalError("missing queued edit") }
SharedStore.state.schedules = [] // Deleted after queueing, before applying.
let persisted = try JSONEncoder().encode(SharedStore.state)
SharedStore.state = try JSONDecoder().decode(LatchState.self, from: persisted)
TimeGuard.date = pending.appliesAt
ChangeEngine.applyDueChanges()
expect(SharedStore.state.schedules.isEmpty, "stale edit resurrected deleted schedule")
expect(SharedStore.state.pending.isEmpty, "stale edit not consumed")
expect(ChangeEngine.queue(action) == nil, "missing schedule edit queued")
expect(ChangeEngine.summary(for: action, state: SharedStore.state) == "Change apps in schedule", "missing summary fallback")
state.overrides.passwordPolicies = [PasswordPolicy(name: "Schedule only", hash: "hash", allowed: [.scheduleChanges])]
expect(ChangeEngine.hasOverride(for: [pending], state: state), "schedule permission cannot override edit")
state.overrides.passwordPolicies[0].allowed = [.limitChanges]
expect(!ChangeEngine.hasOverride(for: [pending], state: state), "limit permission overrides schedule edit")
state.overrides.passwordPolicies = []
state.overrides.phrasePolicies = [PhrasePolicy(name: "Schedule phrase", kind: .custom("test"), allowedErrors: 0, allowed: [.scheduleChanges])]
expect(ChangeEngine.hasOverride(for: [pending], state: state), "phrase schedule permission")
state.overrides.phrasePolicies[0].allowed = [.sessionChanges]
expect(!ChangeEngine.hasOverride(for: [pending], state: state), "session permission overrides schedule edit")
state.overrides.phrasePolicies = []
state.overrides.contactsEnabled = true
state.overrides.contacts = [TrustedContact(name: "Schedule contact", kind: .email("test@example.invalid"), allowed: [.scheduleChanges])]
expect(ChangeEngine.hasOverride(for: [pending], state: state), "contact schedule permission")
state.overrides.contacts[0].allowed = [.limitChanges]
expect(!ChangeEngine.hasOverride(for: [pending], state: state), "contact limit permission overrides schedule edit")
state.overrides.contacts = []
state.schedules = [schedule]
state.lenientDelay = 0
SharedStore.save(state)
expect(ChangeEngine.queue(action) != nil, "zero-delay edit rejected")
expect(SharedStore.state.schedules.first?.selection == website, "zero-delay edit not applied")
let legacy = ChangeAction.removeSchedule(id: schedule.id)
let decodedLegacy = try JSONDecoder().decode(ChangeAction.self, from: JSONEncoder().encode(legacy))
expect(decodedLegacy == legacy, "legacy action round trip")
print("Schedule selection checks passed: \(count) queued mode/recurrence/token combinations plus validation, conflicts, persistence, scopes, stale deletion and zero delay")
'''

authorization_checks = r'''
func phraseProof(_ policy: PhrasePolicy, scope: PhraseChallenges.Scope) -> UUID {
    guard let challenge = PhraseChallenges.start(policy: policy, scope: scope),
          case .completed(let id) = PhraseChallenges.submit(word: "test", to: challenge.id)
    else { fatalError("phrase proof") }
    return id
}
func pendingPolicy(_ action: ChangeAction, due: Bool = true,
                   offset: TimeInterval? = nil) -> PendingChange {
    PendingChange(createdAt: TimeGuard.now(),
        appliesAt: TimeGuard.now().addingTimeInterval(offset ?? (due ? -1 : 1000)),
        direction: .lenient, summary: "test", action: action)
}
func baseAuthorizationState() -> (LatchState, PendingChange) {
    var state = LatchState()
    let schedule = BlockSchedule(name: "Authorization", mode: .blockSelected,
        selection: app, startMinutes: 60, endMinutes: 120)
    state.schedules = [schedule]
    let target = pendingPolicy(.updateScheduleSelection(id: schedule.id, selection: website), due: false)
    state.pending = [target]
    return (state, target)
}
func assertDeniedTarget(_ id: UUID, dueID: UUID) {
    expect(SharedStore.state.pending.contains { $0.id == id }, "unauthorized target applied")
    expect(!SharedStore.state.pending.contains { $0.id == dueID }, "overdue policy not reconciled")
    expect(SharedStore.state.schedules.first?.selection == app, "unauthorized selection applied")
}
func asyncAuthorizationChecks() async {
    var checked = 0
    // A control before the deadline and at/after the deadline, for both
    // approval transports and both pending-change/extra-time authorization.
    for relay in [false, true] {
        let contact = TrustedContact(name: "Approver",
            kind: relay ? .latchUser(code: "relay-code") : .email("test@example.invalid"),
            allowed: [.scheduleChanges, .extraTime])
        let source: ChangeEngine.ContactApprovalSource = relay
            ? .relay(contactIDs: [contact.id], approvedCodes: ["relay-code"])
            : .email(contactIDs: [contact.id])
        let revocations: [ChangeAction] = [
            .setContactPermissions(id: contact.id, allowed: [.limitChanges]),
            .removeContact(id: contact.id), .setContactsOverride(enabled: false)
        ]
        for revoke in revocations {
            for offset: TimeInterval in [1000, 0, -1] {
                let due = offset <= 0
                var (state, target) = baseAuthorizationState()
                state.overrides.contactsEnabled = true
                state.overrides.contacts = [contact]
                let policy = pendingPolicy(revoke, offset: offset)
                state.pending.append(policy)
                SharedStore.save(state)
                let result = await ChangeEngine.applyNowWithContactOffMain(changeIDs: [target.id], source: source)
                expect(result == (due ? 0 : 1), "contact overdue policy authorization")
                if due { assertDeniedTarget(target.id, dueID: policy.id) }

                (state, _) = baseAuthorizationState()
                state.overrides.contactsEnabled = true
                state.overrides.contacts = [contact]
                let step = LimitExtraStep(minutes: 5, waitMinutes: 0, contactRequired: true)
                let limit = AppLimit(name: "Spent", selection: app, minutesPerDay: 0,
                    extraTime: LimitExtraTime(minutesPerUse: 5, usesPerDay: 1, waitMinutes: 0, steps: [step]))
                state.limits = [limit]
                state.pending.append(policy)
                SharedStore.save(state)
                LimitFeatures.resetForTest()
                let context = ExtraContactContext(requestID: "test", limitID: limit.id,
                    day: SharedStore.dayKey(for: TimeGuard.now()), stepIndex: 0,
                    step: step, limitName: limit.name)
                let granted = await ChangeEngine.grantContactExtraTimeOffMain(context: context, source: source)
                expect(granted == !due, "contact extra-time overdue policy authorization")
                expect(LimitFeatures.requestsForTest(limit.id) == (due ? 0 : 1), "unauthorized extra-time state")
                if due { expect(!SharedStore.state.pending.contains { $0.id == policy.id }, "contact grant skipped due reconciliation") }
                checked += 2
            }
        }
    }
    let password = PasswordPolicy(name: "Password", hash: String(repeating: "a", count: 64),
                                  allowed: [.scheduleChanges, .extraTime])
    let phrase = PhrasePolicy(name: "Phrase", kind: .custom("test"), allowedErrors: 0,
                              allowed: [.scheduleChanges, .extraTime])
    for phraseMode in [false, true] {
        for removal in [false, true] {
            for offset: TimeInterval in [1000, 0, -1] {
                let due = offset <= 0
                var (state, target) = baseAuthorizationState()
                state.overrides.passwordPolicies = [password]
                state.overrides.phrasePolicies = [phrase]
                var narrowedPassword = password
                narrowedPassword.allowed = [.limitChanges]
                var narrowedPhrase = phrase
                narrowedPhrase.allowed = [.limitChanges]
                let revoke: ChangeAction = phraseMode
                    ? (removal ? .removePhrasePolicy(id: phrase.id) : .upsertPhrasePolicy(narrowedPhrase))
                    : (removal ? .removePasswordPolicy(id: password.id) : .upsertPasswordPolicy(narrowedPassword))
                let policy = pendingPolicy(revoke, offset: offset)
                state.pending.append(policy)
                SharedStore.save(state)
                let result: Int
                if phraseMode {
                    let proof = phraseProof(phrase, scope: .changes([target.id]))
                    result = await ChangeEngine.applyNowWithPhraseOffMain(changeIDs: [target.id], policyID: phrase.id, proofID: proof)
                } else {
                    result = await ChangeEngine.applyNowWithPasswordOffMain(changeIDs: [target.id], policyID: password.id, candidateHash: password.hash)
                }
                expect(result == (due ? 0 : 1), "password/phrase overdue authorization")
                if due { assertDeniedTarget(target.id, dueID: policy.id) }

                (state, _) = baseAuthorizationState()
                state.overrides.passwordPolicies = [password]
                state.overrides.phrasePolicies = [phrase]
                let step = LimitExtraStep(minutes: 5, waitMinutes: 0,
                    passwordPolicyID: phraseMode ? nil : password.id,
                    phrasePolicyID: phraseMode ? phrase.id : nil)
                let limit = AppLimit(name: "Spent", selection: app, minutesPerDay: 0,
                    extraTime: LimitExtraTime(minutesPerUse: 5, usesPerDay: 1, waitMinutes: 0, steps: [step]))
                state.limits = [limit]
                state.pending.append(policy)
                SharedStore.save(state)
                LimitFeatures.resetForTest()
                let proof = phraseMode ? phraseProof(phrase, scope: .extraTime(limitID: limit.id,
                    day: SharedStore.dayKey(for: TimeGuard.now()), step: 0)) : nil
                let granted = await ChangeEngine.requestExtraTimeOffMain(limitID: limit.id,
                    candidateHash: phraseMode ? nil : password.hash, phraseProofID: proof)
                expect(granted == !due, "password/phrase extra-time overdue authorization")
                expect(LimitFeatures.requestsForTest(limit.id) == (due ? 0 : 1), "unauthorized password/phrase extra-time state")
                if due { expect(!SharedStore.state.pending.contains { $0.id == policy.id }, "extra-time request skipped due reconciliation") }
                checked += 2
            }
        }
    }
    print("Overdue authorization checks passed: \(checked) contact/password/phrase pending-change and extra-time cases, before, at and after the policy deadline")
}
'''

latency_checks = r'''
struct GateFixture {
    var state: LatchState
    let target: PendingChange
    let gate: Int // email, relay, password, phrase
    let contact: TrustedContact
    let password = PasswordPolicy(name: "Password", hash: String(repeating: "b", count: 64),
                                  allowed: [.scheduleChanges, .extraTime])
    let phrase = PhrasePolicy(name: "Phrase", kind: .custom("test"), allowedErrors: 0,
                              allowed: [.scheduleChanges, .extraTime])
    init(_ gate: Int) {
        self.gate = gate
        (state, target) = baseAuthorizationState()
        contact = TrustedContact(name: "Contact",
            kind: gate == 1 ? .latchUser(code: "original-code") : .email("one@example.invalid"),
            allowed: [.scheduleChanges, .extraTime])
        state.overrides.contactsEnabled = true
        state.overrides.contacts = [contact]
        state.overrides.passwordPolicies = [password]
        state.overrides.phrasePolicies = [phrase]
    }
    var source: ChangeEngine.ContactApprovalSource {
        gate == 1 ? .relay(contactIDs: [contact.id], approvedCodes: ["original-code"])
                  : .email(contactIDs: [contact.id])
    }
    func approve(_ ids: [UUID]? = nil) async -> Int {
        let requested = ids ?? [target.id]
        if gate < 2 {
            return await ChangeEngine.applyNowWithContactOffMain(changeIDs: requested, source: source)
        }
        if gate == 2 {
            return await ChangeEngine.applyNowWithPasswordOffMain(changeIDs: requested,
                policyID: password.id, candidateHash: password.hash)
        }
        let proof = phraseProof(phrase, scope: .changes(requested.sorted { $0.uuidString < $1.uuidString }))
        return await ChangeEngine.applyNowWithPhraseOffMain(changeIDs: requested, policyID: phrase.id, proofID: proof)
    }
    mutating func addExtraLimit() -> AppLimit {
        let step = LimitExtraStep(minutes: 5, waitMinutes: 0,
            passwordPolicyID: gate == 2 ? password.id : nil,
            phrasePolicyID: gate == 3 ? phrase.id : nil, contactRequired: gate < 2)
        let limit = AppLimit(name: "Spent", selection: app, minutesPerDay: 0,
            extraTime: LimitExtraTime(minutesPerUse: 5, usesPerDay: 1, waitMinutes: 0, steps: [step]))
        state.limits = [limit]
        return limit
    }
    func extra(_ limit: AppLimit, source override: ChangeEngine.ContactApprovalSource? = nil) async -> Bool {
        if gate < 2 {
            let context = ExtraContactContext(requestID: "latency", limitID: limit.id,
                day: SharedStore.dayKey(for: TimeGuard.now()), stepIndex: 0,
                step: limit.extraTime!.effectiveSteps[0], limitName: limit.name)
            return await ChangeEngine.grantContactExtraTimeOffMain(context: context, source: override ?? source)
        }
        let proof = gate == 3 ? phraseProof(phrase, scope: .extraTime(limitID: limit.id,
            day: SharedStore.dayKey(for: TimeGuard.now()), step: 0)) : nil
        return await ChangeEngine.requestExtraTimeOffMain(limitID: limit.id,
            candidateHash: gate == 2 ? password.hash : nil, phraseProofID: proof)
    }
    var revocations: [ChangeAction] {
        if gate < 2 {
            return [.setContactPermissions(id: contact.id, allowed: [.limitChanges]),
                    .removeContact(id: contact.id), .setContactsOverride(enabled: false)]
        }
        if gate == 2 {
            var narrowed = password; narrowed.allowed = [.limitChanges]
            return [.upsertPasswordPolicy(narrowed), .removePasswordPolicy(id: password.id)]
        }
        var narrowed = phrase; narrowed.allowed = [.limitChanges]
        return [.upsertPhrasePolicy(narrowed), .removePhrasePolicy(id: phrase.id)]
    }
}
func resetLatency() {
    Latency.reset()
    LimitFeatures.resetForTest()
    // Start well away from midnight; explicit rollover cases move the clock.
    TimeGuard.date = Date(timeIntervalSince1970: 2_000_000_000)
}
func asyncLatencyChecks() async {
    var checked = 0
    for gate in 0..<4 {
        for revokeIndex in 0..<(gate < 2 ? 3 : 2) {
            for advance in [false, true] {
                for boundary in ["cleanup", "pendingCommit", "monitor", "coordination"] {
                    resetLatency()
                    var fixture = GateFixture(gate)
                    let extra = boundary != "pendingCommit"
                    let limit = extra ? fixture.addExtraLimit() : nil
                    let revoke = pendingPolicy(fixture.revocations[revokeIndex], offset: 1)
                    fixture.state.pending.append(revoke)
                    // A genuinely due harmless change triggers real applyDueChanges cleanup.
                    fixture.state.pending.append(pendingPolicy(.setBlockAdultWebsites(false)))
                    SharedStore.save(fixture.state)
                    let hook = { if advance { TimeGuard.date += 2 } }
                    switch boundary {
                    case "cleanup": Latency.cleanup = hook
                    case "monitor": Latency.monitor = hook
                    case "coordination": Latency.coordination = hook
                    default:
                        Latency.onLoad = { reads in
                            if reads == 3 { hook() } // Final applyNow reload, after preflight.
                        }
                    }
                    if let limit {
                        let granted = await fixture.extra(limit)
                        expect(granted == !advance, "late extra-time gate: \(gate)/\(boundary)")
                        expect(LimitFeatures.requestsForTest(limit.id) == (advance ? 0 : 1), "stale extra-time commit")
                    } else {
                        let result = await fixture.approve()
                        expect(result == (advance ? 0 : 1), "late pending-change commit: \(gate)")
                    }
                    if advance {
                        expect(SharedStore.state.pending.contains { $0.id == revoke.id }, "late fence did unbounded maintenance")
                        expect(SharedStore.state.pending.contains { $0.id == fixture.target.id }, "late fence applied target")
                        expect(Latency.cleanupCalls == 1, "late fence reran reconciliation")
                    }
                    checked += 1
                }
                // Also cover pending approvals directly after slow cleanup.
                resetLatency()
                var fixture = GateFixture(gate)
                let revoke = pendingPolicy(fixture.revocations[revokeIndex], offset: 1)
                fixture.state.pending += [revoke, pendingPolicy(.setBlockAdultWebsites(false))]
                SharedStore.save(fixture.state)
                Latency.cleanup = { if advance { TimeGuard.date += 2 } }
                let result = await fixture.approve()
                expect(result == (advance ? 0 : 1), "late cleanup pending approval")
                checked += 1
            }
        }
    }
    // Immediate state changes while XPC/coordination waits: not just queued
    // revocations. Policy identity/content, rule/step and day must stay stable.
    for gate in 0..<4 {
        for boundary in ["monitor", "coordination"] {
            for mutation in ["remove", "policy", "rule", "step", "day"] {
                resetLatency()
                var fixture = GateFixture(gate)
                let limit = fixture.addExtraLimit()
                fixture.state.pending = []
                SharedStore.save(fixture.state)
                let hook = {
                    switch mutation {
                    case "day": TimeGuard.date += 86400
                    case "rule": SharedStore.state.limits[0].minutesPerDay = 1
                    case "step": SharedStore.state.limits[0].extraTime!.steps![0].minutes = 9
                    case "remove":
                        if gate < 2 { SharedStore.state.overrides.contacts = [] }
                        else if gate == 2 { SharedStore.state.overrides.passwordPolicies = [] }
                        else { SharedStore.state.overrides.phrasePolicies = [] }
                    default:
                        if gate < 2 { SharedStore.state.overrides.contacts[0].allowed = [.limitChanges] }
                        else if gate == 2 { SharedStore.state.overrides.passwordPolicies[0].name += " changed" }
                        else { SharedStore.state.overrides.phrasePolicies[0].allowedErrors = 1 }
                    }
                }
                if boundary == "monitor" { Latency.monitor = hook }
                else { Latency.coordination = hook }
                let granted = await fixture.extra(limit)
                expect(!granted, "live state/day commit fence: \(gate)/\(boundary)/\(mutation)")
                checked += 1
            }
        }
    }
    // Identity/code pairing and all-email-recipient rules, for both kinds of grant.
    for scenario in ["relayMismatch", "readded", "emailRevoked"] {
        resetLatency()
        var fixture = GateFixture(scenario == "emailRevoked" ? 0 : 1)
        let limit = fixture.addExtraLimit()
        let other = TrustedContact(name: "Other", kind: .latchUser(code: "other-code"),
                                   allowed: [.scheduleChanges, .extraTime])
        let source: ChangeEngine.ContactApprovalSource
        if scenario == "relayMismatch" {
            fixture.state.overrides.contacts.append(other)
            source = .relay(contactIDs: [fixture.contact.id], approvedCodes: ["other-code"])
        } else if scenario == "readded" {
            fixture.state.overrides.contacts = [TrustedContact(name: "Replacement",
                kind: .latchUser(code: "original-code"), allowed: [.scheduleChanges, .extraTime])]
            source = fixture.source
        } else {
            let revoked = TrustedContact(name: "Revoked", kind: .email("two@example.invalid"), allowed: [.limitChanges])
            fixture.state.overrides.contacts.append(revoked)
            source = .email(contactIDs: [fixture.contact.id, revoked.id])
        }
        SharedStore.save(fixture.state)
        let result = await ChangeEngine.applyNowWithContactOffMain(changeIDs: [fixture.target.id], source: source)
        expect(result == 0, "invalid source authorized pending batch")
        let granted = await fixture.extra(limit, source: source)
        expect(!granted, "invalid source authorized extra time")
        checked += 2
    }
    // Sources that passed preflight must remain valid at the final boundaries.
    for scenario in ["relayMismatch", "readded", "emailRevoked"] {
        for boundary in ["pendingCommit", "coordination"] {
            resetLatency()
            var fixture = GateFixture(scenario == "emailRevoked" ? 0 : 1)
            let limit = fixture.addExtraLimit()
            let second = TrustedContact(name: "Second", kind: .email("two@example.invalid"),
                                        allowed: [.scheduleChanges, .extraTime])
            let source: ChangeEngine.ContactApprovalSource
            if scenario == "emailRevoked" {
                fixture.state.overrides.contacts.append(second)
                source = .email(contactIDs: [fixture.contact.id, second.id])
            } else { source = fixture.source }
            SharedStore.save(fixture.state)
            let hook = {
                switch scenario {
                case "relayMismatch":
                    SharedStore.state.overrides.contacts[0].kind = .latchUser(code: "other-code")
                    SharedStore.state.overrides.contacts.append(TrustedContact(name: "Other ID",
                        kind: .latchUser(code: "original-code"), allowed: [.scheduleChanges, .extraTime]))
                case "readded":
                    SharedStore.state.overrides.contacts = [TrustedContact(name: "Replacement",
                        kind: .latchUser(code: "original-code"), allowed: [.scheduleChanges, .extraTime])]
                default: SharedStore.state.overrides.contacts[1].allowed = [.limitChanges]
                }
            }
            if boundary == "pendingCommit" {
                Latency.onLoad = { if $0 == 3 { hook() } }
                let result = await ChangeEngine.applyNowWithContactOffMain(changeIDs: [fixture.target.id], source: source)
                expect(result == 0, "source changed at pending commit was trusted")
            } else {
                Latency.coordination = hook
                let granted = await fixture.extra(limit, source: source)
                expect(!granted && LimitFeatures.requestsForTest(limit.id) == 0,
                       "source changed during coordinated wait was trusted")
            }
            expect(SharedStore.state.pending.contains { $0.id == fixture.target.id }, "identity fence applied target")
            checked += 1
        }
    }
    // No self-override of scope policies and no authorized subset of a mixed batch.
    for gate in 0..<4 {
        for scenario in ["scope", "mixedScope", "mixed", "missing"] {
            resetLatency()
            var fixture = GateFixture(gate)
            let otherAction: ChangeAction = scenario == "scope" || scenario == "mixedScope"
                ? (gate < 2 ? .setContactPermissions(id: fixture.contact.id, allowed: [.scheduleChanges])
                   : gate == 2 ? .upsertPasswordPolicy(fixture.password) : .upsertPhrasePolicy(fixture.phrase))
                : .setLenientDelay(50)
            let other = pendingPolicy(otherAction, due: false)
            if scenario != "missing" { fixture.state.pending.append(other) }
            SharedStore.save(fixture.state)
            let result = await fixture.approve(scenario == "scope" ? [other.id] : [fixture.target.id, other.id])
            expect(result == 0, "self-policy/mixed/missing batch authorized")
            expect(SharedStore.state.pending.contains { $0.id == fixture.target.id }, "partial unauthorized batch applied")
            checked += 1
        }
    }
    resetLatency()
    print("Grant latency/source checks passed: \(checked) cases; real due cleanup, monitor and coordination clock changes, fresh policies/rules/steps/day, source pairing, self-scope and mixed batches")
}
let finished = DispatchSemaphore(value: 0)
Task.detached {
    await asyncAuthorizationChecks()
    await asyncLatencyChecks()
    finished.signal()
}
expect(finished.wait(timeout: .now() + 20) == .success, "serialized authorization queue deadlock")
'''

delay_checks = r'''
// Collect failures so the original 272 cases still run even if a new
// contract is not implemented yet. Counts are scenarios, not assertions.
var delayCases = 0
var delayFailures: [String] = []
var delayCaseName = ""
func delayExpect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { delayFailures.append("\(delayCaseName): \(message)") }
}
func delayCase(_ name: String, _ check: () throws -> Void) {
    delayCases += 1; delayCaseName = name
    Latency.reset()
    TimeGuard.date = Date(timeIntervalSince1970: 2_000_000_000)
    do { try check() } catch { delayFailures.append("\(name): \(error)") }
}
func expectedWait(_ policy: DelayPolicy, _ direction: ChangeDirection) -> TimeInterval {
    if direction == .lenient { return policy.lenientDelay }
    switch policy.mode {
    case .separate: return policy.strictDelay
    case .shared: return policy.lenientDelay
    case .lenientOnly: return 0
    }
}
func delayState(_ mode: DelayMode) -> LatchState {
    var state = LatchState()
    state.isSetUp = true
    state.delayPolicy = DelayPolicy(mode: mode, strictDelay: 300, lenientDelay: 900)
    return state
}
delayCase("fresh and legacy state decoding") {
    let fresh = LatchState()
    let empty = try JSONDecoder().decode(LatchState.self, from: Data("{}".utf8))
    let legacy = try JSONDecoder().decode(LatchState.self,
        from: Data(#"{"isSetUp":true,"strictDelay":300,"lenientDelay":900}"#.utf8))
    delayExpect(fresh.delayMode == .separate && empty.delayMode == .separate,
                "missing mode must default to separate")
    delayExpect(legacy.delayPolicy == DelayPolicy(mode: .separate, strictDelay: 300, lenientDelay: 900),
                "legacy waits changed")
}
for mode in DelayMode.allCases {
    delayCase("\(mode) normalization and persistence") {
        var state = delayState(mode)
        let normalized = state.delayPolicy.normalized
        delayExpect(state.strictDelay == expectedWait(normalized, .stricter), "setter not normalized")
        let restored = try JSONDecoder().decode(LatchState.self, from: JSONEncoder().encode(state))
        delayExpect(restored.delayMode == mode && restored.delayPolicy == normalized, "policy round trip")
        // Noncanonical raw fields can come from a previous writer or stored JSON.
        state.strictDelay = 777
        delayExpect(state.delayPolicy == state.delayPolicy.normalized, "getter not normalized")
        let raw = Data("{\"delayMode\":\"\(mode.rawValue)\",\"strictDelay\":777,\"lenientDelay\":900}".utf8)
        let decoded = try JSONDecoder().decode(LatchState.self, from: raw)
        delayExpect(decoded.delayPolicy == decoded.delayPolicy.normalized, "decoded getter not normalized")
    }
    for stricter in [false, true] {
        delayCase("\(mode) ordinary \(stricter ? "strict" : "lenient") timing") {
            let state = delayState(mode)
            SharedStore.save(state)
            let action: ChangeAction = .setBlockAppRemoval(stricter)
            let direction: ChangeDirection = stricter ? .stricter : .lenient
            let wait = expectedWait(state.delayPolicy, direction)
            guard let queued = ChangeEngine.queue(action) else {
                delayExpect(false, "action rejected"); return
            }
            delayExpect(queued.direction == direction && queued.appliesAt == queued.createdAt.addingTimeInterval(wait),
                        "wrong effective wait")
            if wait == 0 {
                delayExpect(mode == .lenientOnly && stricter, "unexpected instant change")
                delayExpect(SharedStore.state.blockAppRemoval && SharedStore.state.pending.isEmpty,
                            "lenientOnly tightening not applied immediately")
            } else {
                TimeGuard.date = queued.appliesAt.addingTimeInterval(-0.001)
                ChangeEngine.applyDueChanges()
                delayExpect(SharedStore.state.pending.contains { $0.id == queued.id }, "applied early")
                TimeGuard.date = queued.appliesAt
                ChangeEngine.applyDueChanges()
                delayExpect(SharedStore.state.pending.isEmpty && SharedStore.state.blockAppRemoval == stricter,
                            "did not apply at deadline")
            }
        }
    }
    // All mode transitions, increases, decreases, and mixed edits. The oracle
    // uses the public contract, not DelayPolicy.direction/delay itself.
    for targetMode in DelayMode.allCases {
        for waits in [(600.0, 1200.0), (60.0, 120.0), (60.0, 1200.0), (600.0, 120.0)] {
            delayCase("\(mode) -> \(targetMode) \(waits)") {
                let state = delayState(mode)
                let target = DelayPolicy(mode: targetMode, strictDelay: waits.0, lenientDelay: waits.1)
                let direction: ChangeDirection = expectedWait(target, .stricter) < expectedWait(state.delayPolicy, .stricter)
                    || expectedWait(target, .lenient) < expectedWait(state.delayPolicy, .lenient) ? .lenient : .stricter
                SharedStore.save(state)
                let action = ChangeAction.setDelayPolicy(target)
                delayExpect(ChangeEngine.classify(action, state: state) == direction, "wrong direction")
                delayExpect(ChangeEngine.overrideCapability(for: action) == .delayChanges, "wrong override scope")
                guard let queued = ChangeEngine.queue(action) else {
                    delayExpect(false, "valid policy rejected"); return
                }
                let wait = expectedWait(state.delayPolicy, direction)
                delayExpect(queued.appliesAt == queued.createdAt.addingTimeInterval(wait), "used target instead of current wait")
                SharedStore.state = try JSONDecoder().decode(LatchState.self, from: JSONEncoder().encode(SharedStore.state))
                if wait > 0 {
                    delayExpect(SharedStore.state.delayPolicy == state.delayPolicy, "policy changed before wait")
                    TimeGuard.date = queued.appliesAt.addingTimeInterval(-0.001)
                    ChangeEngine.applyDueChanges()
                    delayExpect(SharedStore.state.delayPolicy == state.delayPolicy, "policy applied early")
                }
                TimeGuard.date = queued.appliesAt
                ChangeEngine.applyDueChanges()
                delayExpect(SharedStore.state.delayPolicy == target.normalized && SharedStore.state.pending.isEmpty,
                            "policy not applied/normalized")
                ChangeEngine.applyDueChanges()
                delayExpect(SharedStore.state.delayPolicy == target.normalized, "repeat apply changed policy")
                delayExpect(ChangeEngine.queue(action) == nil, "unchanged normalized policy queued")
            }
        }
    }
    let actions: [ChangeAction] = [.setStrictDelay(600), .setLenientDelay(1200),
        .setDelayPolicy(DelayPolicy(mode: .shared, strictDelay: 600, lenientDelay: 1200))]
    for (i, old) in actions.enumerated() {
        for (j, new) in actions.enumerated() {
            delayCase("\(mode) legacy/new conflict \(i)/\(j)") {
                var state = delayState(mode)
                let existing = PendingChange(createdAt: TimeGuard.now(), appliesAt: TimeGuard.now().addingTimeInterval(5000),
                    direction: .stricter, summary: "old", action: old)
                state.pending = [existing]
                SharedStore.save(state)
                delayExpect(ChangeEngine.conflictKey(old) == "delayPolicy" && ChangeEngine.conflictKey(new) == "delayPolicy",
                            "delay actions have different conflict keys")
                delayExpect(ChangeEngine.queue(new) == nil, "conflicting policy queued")
                delayExpect(SharedStore.state.pending == [existing], "existing deadline/action changed")
            }
        }
    }
    for oldAction in [ChangeAction.setStrictDelay(600), .setLenientDelay(1200)] {
        delayCase("\(mode) persisted legacy application \(oldAction)") {
            var state = delayState(mode)
            let queued = PendingChange(createdAt: TimeGuard.now(), appliesAt: TimeGuard.now().addingTimeInterval(700),
                direction: .lenient, summary: "legacy", action: oldAction)
            state.pending = [queued]
            SharedStore.save(try JSONDecoder().decode(LatchState.self, from: JSONEncoder().encode(state)))
            delayExpect(SharedStore.state.pending == [queued], "legacy action/deadline not preserved")
            TimeGuard.date = queued.appliesAt.addingTimeInterval(-1)
            ChangeEngine.applyDueChanges()
            delayExpect(SharedStore.state.delayPolicy == state.delayPolicy, "legacy edit applied early")
            TimeGuard.date = queued.appliesAt
            ChangeEngine.applyDueChanges()
            var expected = state.delayPolicy
            switch oldAction {
            case .setStrictDelay(let value):
                if mode == .shared { expected.lenientDelay = value; expected.strictDelay = value }
                else if mode == .separate { expected.strictDelay = value }
            case .setLenientDelay(let value):
                expected.lenientDelay = value
                if mode == .shared { expected.strictDelay = value }
            default: fatalError("fixture")
            }
            delayExpect(SharedStore.state.delayPolicy == expected.normalized, "legacy action violates selected mode")
        }
    }
    delayCase("\(mode) switching cannot bypass existing deadline") {
        var state = delayState(mode)
        let existing = PendingChange(createdAt: TimeGuard.now().addingTimeInterval(-100),
            appliesAt: TimeGuard.now().addingTimeInterval(5000), direction: .lenient,
            summary: "do not retime", action: .setBlockAppRemoval(false))
        state.blockAppRemoval = true; state.pending = [existing]
        SharedStore.save(state)
        let target = DelayPolicy(mode: .lenientOnly, strictDelay: 0, lenientDelay: 60)
        guard let queued = ChangeEngine.queue(.setDelayPolicy(target)) else {
            delayExpect(false, "mode change rejected"); return
        }
        delayExpect(queued.appliesAt == queued.createdAt.addingTimeInterval(900), "reduction bypassed old wait")
        TimeGuard.date = queued.appliesAt
        ChangeEngine.applyDueChanges()
        SharedStore.state = try JSONDecoder().decode(LatchState.self, from: JSONEncoder().encode(SharedStore.state))
        delayExpect(SharedStore.state.pending == [existing] && SharedStore.state.blockAppRemoval,
                    "switch changed existing ID/action/deadline or applied it")
        TimeGuard.date = existing.appliesAt.addingTimeInterval(-1)
        ChangeEngine.applyDueChanges()
        delayExpect(SharedStore.state.blockAppRemoval, "old pending applied early after switch")
        TimeGuard.date = existing.appliesAt
        ChangeEngine.applyDueChanges()
        delayExpect(!SharedStore.state.blockAppRemoval && SharedStore.state.pending.isEmpty, "old pending lost")
    }
}
for mode in DelayMode.allCases {
    for bad in [0.0, -1.0, 59.0, Double.nan, Double.infinity, -Double.infinity, 366.0 * 86400 + 1] {
        for strictField in [false, true] where !strictField || mode == .separate {
            delayCase("invalid \(mode) \(strictField ? "strict" : "lenient") \(bad)") {
                var target = DelayPolicy(mode: mode, strictDelay: 300, lenientDelay: 900)
                if strictField { target.strictDelay = bad } else { target.lenientDelay = bad }
                let original = delayState(.separate)
                SharedStore.save(original)
                delayExpect(!target.isValid, "invalid active wait accepted")
                delayExpect(ChangeEngine.queue(.setDelayPolicy(target)) == nil, "invalid policy queued")
                var state = original
                ChangeEngine.applyForTest(.setDelayPolicy(target), state: &state)
                delayExpect(state.delayPolicy == original.delayPolicy, "persisted invalid policy applied")
                delayExpect(SharedStore.state.pending.isEmpty, "invalid policy mutated pending")
            }
        }
    }
    for boundary in [60.0, 366.0 * 86400] {
        delayCase("valid \(mode) boundary \(boundary)") {
            let policy = DelayPolicy(mode: mode, strictDelay: boundary, lenientDelay: boundary)
            delayExpect(policy.isValid, "valid endpoint rejected")
        }
    }
}
for mode in [DelayMode.shared, .lenientOnly] {
    delayCase("\(mode) inactive nonfinite field must not poison persistence") {
        for bad in [Double.nan, Double.infinity, -Double.infinity, -1, 366.0 * 86400 + 1] {
            SharedStore.save(delayState(.separate))
            let target = DelayPolicy(mode: mode, strictDelay: bad, lenientDelay: 1200)
            delayExpect(!target.isValid, "invalid inactive strict field accepted: \(bad)")
            if ChangeEngine.queue(.setDelayPolicy(target)) != nil {
                delayExpect(false, "invalid inactive strict field queued: \(bad)")
                delayExpect((try? JSONEncoder().encode(SharedStore.state)) != nil,
                            "accepted nonfinite payload cannot be saved")
            }
        }
        delayExpect(DelayPolicy(mode: mode, strictDelay: 0, lenientDelay: 1200).isValid,
                    "normalized zero placeholder rejected")
    }
}
for mode in DelayMode.allCases {
    delayCase("priority promotion/restoration remains delayed in \(mode)") {
        var state = delayState(mode)
        let rule = BlockSchedule(name: "Recurring", mode: .blockSelected, selection: app,
                                 startMinutes: 600, endMinutes: 660)
        state.schedules = [rule]
        let key = "schedule-" + rule.id.uuidString
        let action = ChangeAction.setSchedulePriority(key: key, prioritized: true)
        SharedStore.rejectSave = false
        DeviceActivityCenter.running = [LatchConstants.dailyActivityName]
        SharedStore.save(state)
        let queued = ChangeEngine.queue(action)
        delayExpect(queued != nil, "valid promotion rejected")
        guard let queued else { return }
        delayExpect(queued.direction == .lenient && queued.appliesAt == TimeGuard.date.addingTimeInterval(900), "wrong current-policy delay")
        delayExpect(SharedStore.state.prioritizedScheduleKeys.isEmpty, "promotion applied on queue")
        delayExpect(ChangeEngine.queue(.setSchedulePriority(key: key, prioritized: false)) == nil, "second priority edit accepted")
        TimeGuard.date = queued.appliesAt.addingTimeInterval(-1)
        ChangeEngine.applyDueChanges()
        delayExpect(SharedStore.state.prioritizedScheduleKeys.isEmpty, "promotion applied early")
        TimeGuard.date = queued.appliesAt
        ChangeEngine.applyDueChanges()
        delayExpect(SharedStore.state.prioritizedScheduleKeys == [key], "due promotion not persisted")
        let restored = try JSONDecoder().decode(LatchState.self, from: JSONEncoder().encode(SharedStore.state))
        delayExpect(restored.prioritizedScheduleKeys == [key], "promotion lost after restart")
        let reset = ChangeEngine.queue(.setSchedulePriority(key: key, prioritized: false))
        delayExpect(reset?.direction == .lenient && reset?.appliesAt == TimeGuard.date.addingTimeInterval(900), "restoration bypassed wait")
        var removed = restored; removed.schedules = []; removed.prioritizedScheduleKeys = []
        ChangeEngine.applyForTest(action, state: &removed)
        delayExpect(removed.prioritizedScheduleKeys.isEmpty && removed.schedules.isEmpty, "stale promotion resurrected removed rule")
    }
}
delayCase("invalid/no-op priority keys are rejected without resetting usage") {
    var state = delayState(.separate)
    let rule = BlockSchedule(name: "Schedule", mode: .blockSelected, selection: app, startMinutes: 600, endMinutes: 660)
    state.schedules = [rule]; SharedStore.save(state)
    let resets = SharedStore.usageResetCalls
    delayExpect(ChangeEngine.queue(.setSchedulePriority(key: "missing", prioritized: true)) == nil, "unknown key queued")
    delayExpect(ChangeEngine.queue(.setSchedulePriority(key: "schedule-" + rule.id.uuidString, prioritized: false)) == nil, "no-op queued")
    delayExpect(SharedStore.usageResetCalls == resets && SharedStore.state.pending.isEmpty, "invalid priority modified usage/pending")
}
print("Delay policy checks: \(delayCases) scenarios, \(delayFailures.count) failures")
for failure in delayFailures { print("FAIL: \(failure)") }
'''

wake_checks = r'''
var wakeCases = 0
let wakeApp = FamilyActivitySelection(applicationTokens: ["wake-app"])
let waits: [Int?] = [nil, 0, 10, 120, 1440]
for old in waits {
    for new in waits {
        wakeCases += 1
        Latency.reset(); TestDefaults.values = [:]
        TimeGuard.date = Date(timeIntervalSince1970: 2_000_000_000)
        var state = LatchState()
        state.isSetUp = true; state.delayPolicy = DelayPolicy()
        let limit = AppLimit(name: "Wake group", selection: wakeApp, minutesPerDay: 45,
            weekdayMinutes: [1: 90], wakeDelayMinutes: old,
            split: LimitSplit(cutoffMinutes: 720, beforeMinutes: 10, carryUnused: true),
            extraTime: LimitExtraTime(minutesPerUse: 5, usesPerDay: 3, waitMinutes: 2))
        state.limits = [limit]
        SharedStore.save(state)
        let action = ChangeAction.setGroupWakeDelay(id: limit.id, minutes: new)
        expect(ChangeEngine.overrideCapability(for: action) == .limitChanges, "group wake approval scope")
        expect(ChangeEngine.conflictKey(action) == ChangeEngine.conflictKey(.removeLimit(id: limit.id)), "group wake conflict")
        if old == new {
            expect(ChangeEngine.queue(action) == nil, "wake no-op queued")
            continue
        }
        let direction: ChangeDirection = new == nil || (old != nil && new! < old!) ? .lenient : .stricter
        expect(ChangeEngine.classify(action, state: state) == direction, "group wake direction")
        let fingerprintKey = "latch.dailyMonitorFingerprint.v2"
        SharedStore.defaults.set(ChangeEngine.fingerprintForTest(state), forKey: fingerprintKey)
        let queued = ChangeEngine.queue(action)!
        expect(queued.direction == direction, "queued wake direction")
        expect(!ChangeEngine.changesDailyLimits([queued]) && !ChangeEngine.changesWindows([queued]), "wake edit rebuilds usage/window monitors")
        expect(ChangeEngine.queue(.configureLimit(limit)) == nil, "wake edit allows conflicting limit edit")
        SharedStore.state = try JSONDecoder().decode(LatchState.self, from: JSONEncoder().encode(SharedStore.state))
        TimeGuard.date = queued.appliesAt.addingTimeInterval(-1)
        ChangeEngine.applyDueChanges()
        expect(SharedStore.state.limits == [limit], "wake edit applied early")
        TimeGuard.date = queued.appliesAt
        ChangeEngine.applyDueChanges()
        var expected = limit; expected.wakeDelayMinutes = new
        expect(SharedStore.state.limits == [expected], "wake edit changed other group fields")
        expect(SharedStore.state.pending.isEmpty, "wake edit not consumed")
        expect(SharedStore.defaults.string(forKey: fingerprintKey) == ChangeEngine.fingerprintForTest(SharedStore.state), "healthy fingerprint wasn't rebased")
    }
}
for invalid in [-1, 1441] {
    wakeCases += 1
    var state = LatchState()
    let limit = AppLimit(name: "Invalid", selection: wakeApp, minutesPerDay: 20)
    state.limits = [limit]; SharedStore.save(state)
    expect(ChangeEngine.queue(.setGroupWakeDelay(id: limit.id, minutes: invalid)) == nil, "invalid wake wait queued")
    ChangeEngine.applyForTest(.setGroupWakeDelay(id: limit.id, minutes: invalid), state: &state)
    expect(state.limits == [limit], "persisted invalid wake wait applied")
}
for cached in ["stale fingerprint", ""] {
    wakeCases += 1
    var state = LatchState(); state.delayPolicy = DelayPolicy()
    let limit = AppLimit(name: "Stale monitor", selection: wakeApp, minutesPerDay: 20, wakeDelayMinutes: 10)
    state.limits = [limit]; SharedStore.save(state)
    SharedStore.defaults.set(cached, forKey: "latch.dailyMonitorFingerprint.v2")
    let queued = ChangeEngine.queue(.setGroupWakeDelay(id: limit.id, minutes: 15))!
    TimeGuard.date = queued.appliesAt; ChangeEngine.applyDueChanges()
    expect(SharedStore.defaults.string(forKey: "latch.dailyMonitorFingerprint.v2") == cached, "stale fingerprint blessed")
}
var scheduledWakeCases = 0
for test in 0..<9 {
    scheduledWakeCases += 1
    Latency.reset(); TestDefaults.values = [:]; SharedStore.rejectSave = false
    SharedStore.usageResetCalls = 0
    DeviceActivityCenter.running = [LatchConstants.dailyActivityName]
    TimeGuard.date = Date(timeIntervalSince1970: 2_000_000_000)
    var old = AppLimit(name: "Scheduled wake", selection: wakeApp, minutesPerDay: 45,
        weekdayMinutes: [2: 90], wakeDelayMinutes: 10,
        split: LimitSplit(cutoffMinutes: 720, beforeMinutes: 10, carryUnused: true),
        extraTime: LimitExtraTime(minutesPerUse: 5, usesPerDay: 2, waitMinutes: 3))
    old.wakeSchedule = LimitWakeSchedule(startMinutes: 480)
    var state = LatchState(); state.isSetUp = true; state.limits = [old]; state.delayPolicy = DelayPolicy()
    SharedStore.save(state)
    var schedule = old.wakeSchedule!, wait: Int? = 10
    let direction: ChangeDirection
    switch test {
    case 0: schedule.startMinutes = 420; direction = .stricter
    case 1: schedule.startMinutes = 540; direction = .lenient
    case 2: schedule.weekdays = [2,3,4,5,6]; direction = .lenient
    case 3: schedule.dayTimings[2] = WakeDayTiming(startMinutes: 480, waitMinutes: 5); direction = .lenient
    case 4: schedule.dayTimings[2] = WakeDayTiming(startMinutes: 480, waitMinutes: 20); direction = .stricter
    case 5: schedule.dayTimings[2] = WakeDayTiming(startMinutes: 540, waitMinutes: 20); direction = .lenient
    case 6: wait = nil; direction = .lenient
    case 7: wait = 30; direction = .stricter
    default: direction = .stricter
    }
    let action = ChangeAction.setGroupWakeSchedule(id: old.id, minutes: wait, schedule: schedule)
    expect(ChangeEngine.overrideCapability(for: action) == .limitChanges, "scheduled wake approval scope")
    expect(ChangeEngine.conflictKey(action) == ChangeEngine.conflictKey(.configureLimit(old)), "scheduled wake conflict key")
    if test == 8 {
        expect(ChangeEngine.queue(action) == nil, "unchanged schedule queued")
        continue
    }
    expect(ChangeEngine.classify(action, state: state) == direction, "scheduled wake direction \(test)")
    let key = "latch.dailyMonitorFingerprint.v2"
    SharedStore.defaults.set(ChangeEngine.fingerprintForTest(state), forKey: key)
    let change = ChangeEngine.queue(action)!
    expect(!ChangeEngine.changesDailyLimits([change]), "scheduled wake restarts daily usage")
    expect(ChangeEngine.changesWindows([change]) == [0,1,5,6].contains(test), "wake boundary change mismatch in case \(test): \(ChangeEngine.changesWindows([change]))")
    expect(ChangeEngine.queue(.setGroupWakeDelay(id: old.id, minutes: 60)) == nil, "legacy action conflicts bypassed")
    expect(SharedStore.state.limits == [old], "scheduled wake applied before delay")
    let roundTrip = try JSONDecoder().decode(LatchState.self, from: JSONEncoder().encode(SharedStore.state))
    expect(roundTrip.pending == SharedStore.state.pending && roundTrip.limits == [old], "new action failed to roundtrip")
    TimeGuard.date = change.appliesAt.addingTimeInterval(-1); ChangeEngine.applyDueChanges()
    expect(SharedStore.state.limits == [old], "scheduled wake applied early")
    TimeGuard.date = change.appliesAt; ChangeEngine.applyDueChanges()
    var expected = old; expected.wakeDelayMinutes = wait; expected.wakeSchedule = schedule
    expect(SharedStore.state.limits == [expected], "scheduled wake changed budgets/selections/features")
    expect(SharedStore.usageResetCalls == 0, "scheduled wake reset spent usage")
    expect(SharedStore.defaults.string(forKey: key) == ChangeEngine.fingerprintForTest(SharedStore.state), "scheduled wake daily fingerprint not rebased")
}
for test in 0..<6 {
    scheduledWakeCases += 1
    var schedule = LimitWakeSchedule(), wait: Int? = 10
    switch test {
    case 0: schedule.startMinutes = -1
    case 1: schedule.startMinutes = 1411
    case 2: schedule.weekdays = []
    case 3: schedule.dayTimings[8] = WakeDayTiming()
    case 4: schedule.dayTimings[2] = WakeDayTiming(startMinutes: 0, waitMinutes: 1441)
    default: wait = -1
    }
    var state = LatchState()
    let old = AppLimit(name: "Invalid timing", selection: wakeApp, minutesPerDay: 20, wakeDelayMinutes: 10)
    state.limits = [old]; SharedStore.save(state)
    let action = ChangeAction.setGroupWakeSchedule(id: old.id, minutes: wait, schedule: schedule)
    expect(ChangeEngine.queue(action) == nil, "invalid wake schedule queued")
    ChangeEngine.applyForTest(action, state: &state)
    expect(state.limits == [old], "invalid persisted timing applied")
}
for test in 0..<4 {
    scheduledWakeCases += 1
    var old = DayNightGroup(name: "Named wake")
    old.scope.selection = wakeApp; old.wakeStartMinutes = 480; old.waitMinutes = 20
    if test == 3 { old.sleepEnabled = true }
    var changed = old
    let expected: ChangeDirection
    switch test {
    case 0: changed.weekdayWakeTimings[2] = WakeDayTiming(startMinutes: 480, waitMinutes: 30); expected = .stricter
    case 1: changed.weekdayWakeTimings[2] = WakeDayTiming(startMinutes: 480, waitMinutes: 10); expected = .lenient
    case 2: changed.weekdayWakeTimings[2] = WakeDayTiming(startMinutes: 540, waitMinutes: 30); expected = .lenient
    default: changed.weekdayWakeTimings[2] = WakeDayTiming(startMinutes: 420, waitMinutes: 30); expected = .lenient
    }
    var state = LatchState(); state.dayNightGroups = [old]
    let action = ChangeAction.upsertDayNightGroup(changed)
    expect(ChangeEngine.classify(action, state: state) == expected, "named per-day direction incorrect")
    ChangeEngine.applyForTest(action, state: &state)
    expect(state.dayNightGroups == [changed], "named timing apply lost epoch or day settings")
}
do {
    scheduledWakeCases += 1
    var a = AppLimit(name: "A", selection: wakeApp, minutesPerDay: 20, wakeDelayMinutes: 10)
    a.wakeSchedule = LimitWakeSchedule(startMinutes: 480)
    var b = a; b.id = UUID(); b.name = "B"
    var state = LatchState(); state.limits = [a,b]; SharedStore.save(state)
    let changes = [a,b].map {
        PendingChange(createdAt: TimeGuard.now(), appliesAt: TimeGuard.now().addingTimeInterval(600), direction: .lenient,
                      summary: "Disable", action: .setGroupWakeSchedule(id: $0.id, minutes: nil, schedule: $0.wakeSchedule!))
    }
    expect(!ChangeEngine.changesWindows([changes[0]]), "one shared contributor unnecessarily restarts boundary")
    expect(ChangeEngine.changesWindows(changes), "batch removal left a shared sentinel stale")
}
print("Focused group wake checks passed: \(wakeCases) original plus \(scheduledWakeCases) per-day scheduling/classification/persistence cases")
'''

admission = "\nenum MonitorRegistration {\n" + "\n".join(
    block(registration, signature) for signature in [
        "static func clearRejection()", "static func reject(required:", "static func admit(",
    ]) + '\nprivate static let rejectionKey = "test-capacity-rejection"\n}\n'

budget_checks = r'''
var queueBudgetCases = 0
func budgetFixture(_ count: Int) -> LatchState {
    Latency.reset(); TestDefaults.values = [:]
    SharedStore.rejectSave = false; SharedStore.stateRecoveryNeeded = false
    SharedStore.enforcementDegraded = false; SharedStore.usageResetCalls = 0
    ChangeEngine.scheduledApplyIDs = []; ChangeEngine.notifiedIDs = []
    DeviceActivityCenter.running = []
    var state = LatchState(); state.delayPolicy = DelayPolicy()
    state.schedules = (0..<count).map {
        BlockSchedule(name: "Budget \($0)", mode: .blockSelected, selection: app,
                      startMinutes: 600, endMinutes: 660)
    }
    SharedStore.blockedIDs = [UUID()]
    SharedStore.save(state)
    return state
}
func budgetBytes(_ state: LatchState) -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return try! encoder.encode(state)
}
do {
    queueBudgetCases += 1
    let original = budgetFixture(18)
    let added = BlockSchedule(name: "Fits", mode: .blockSelected, selection: app,
                              startMinutes: 600, endMinutes: 660)
    let blocked = SharedStore.blockedIDs
    let change = ChangeEngine.queue(.addSchedule(added))
    expect(change != nil, "20-slot real queue rejected")
    expect(SharedStore.state.schedules == original.schedules, "queue applied before delay")
    expect(SharedStore.state.pending.map(\.id) == [change!.id], "pending not committed")
    expect(ChangeEngine.scheduledApplyIDs == [change!.id] && ChangeEngine.notifiedIDs == [change!.id], "post-save effects not scheduled")
    expect(SharedStore.blockedIDs == blocked && SharedStore.usageResetCalls == 0, "queue reset usage")
    TimeGuard.date = change!.appliesAt.addingTimeInterval(-1)
    ChangeEngine.applyDueChanges()
    expect(SharedStore.state.schedules == original.schedules && SharedStore.state.pending.count == 1,
           "warning/foreground applied one second early")
    TimeGuard.date = change!.appliesAt
    ChangeEngine.applyDueChanges()
    expect(SharedStore.state.schedules == original.schedules + [added] && SharedStore.state.pending.isEmpty,
           "due budgeted rule failed to apply")
}
for reason in ["21slots", "saveFailure", "recovery", "staleRuntime"] {
    queueBudgetCases += 1
    let original = budgetFixture(reason == "21slots" ? 19 : 18)
    let before = budgetBytes(original), blocked = SharedStore.blockedIDs
    if reason == "saveFailure" { SharedStore.rejectSave = true }
    if reason == "recovery" { SharedStore.stateRecoveryNeeded = true }
    if reason == "staleRuntime" { DeviceActivityCenter.running = ["stale-enforcement"] }
    let added = BlockSchedule(name: "Reject", mode: .blockSelected, selection: app,
                              startMinutes: 600, endMinutes: 660)
    expect(ChangeEngine.queue(.addSchedule(added)) == nil, "\(reason) unexpectedly queued")
    expect(budgetBytes(SharedStore.state) == before, "\(reason) changed state/deadline")
    expect(ChangeEngine.scheduledApplyIDs.isEmpty && ChangeEngine.notifiedIDs.isEmpty, "\(reason) effects before verified save")
    expect(SharedStore.blockedIDs == blocked && SharedStore.usageResetCalls == 0, "\(reason) reset usage")
    expect(Latency.cleanupCalls == 0, "\(reason) stopped existing monitor")
    SharedStore.rejectSave = false; SharedStore.stateRecoveryNeeded = false
}
do {
    queueBudgetCases += 1
    let original = budgetFixture(21), blocked = SharedStore.blockedIDs
    let change = ChangeEngine.queue(.removeSchedule(id: original.schedules[0].id))
    expect(change != nil, "overbudget user trapped; repair cannot queue")
    expect(SharedStore.state.schedules == original.schedules, "repair bypassed loosening wait")
    expect(change!.appliesAt == change!.createdAt.addingTimeInterval(original.lenientDelay), "repair deadline changed")
    expect(SharedStore.blockedIDs == blocked && SharedStore.usageResetCalls == 0, "repair queue reset usage")
    TimeGuard.date = change!.appliesAt.addingTimeInterval(-1); ChangeEngine.applyDueChanges()
    expect(SharedStore.state.schedules == original.schedules, "repair applied early")
}
do {
    queueBudgetCases += 1
    _ = budgetFixture(17)
    let first = BlockSchedule(name: "First", mode: .blockSelected, selection: app,
                              startMinutes: 600, endMinutes: 660)
    let firstChange = ChangeEngine.queue(.addSchedule(first))!
    let preserved = budgetBytes(SharedStore.state)
    let second = BlockSchedule(name: "Second", mode: .blockSelected, selection: app,
                               startMinutes: 600, endMinutes: 660)
    expect(ChangeEngine.queue(.addSchedule(second)) == nil, "pending conjunction oversubscribed")
    expect(budgetBytes(SharedStore.state) == preserved, "rejection changed older pending deadline")
    expect(ChangeEngine.scheduledApplyIDs == [firstChange.id], "rejection schedules another activity")
}
SharedStore.blockedIDs = []; DeviceActivityCenter.running = [LatchConstants.dailyActivityName]
print("Real queue budget checks passed: \(queueBudgetCases) cases; 20/21, save failure, recovery, stale occupancy, delay-safe repairs and pending conjunction")
'''

source = (infrastructure + models + phrases + budget + precedence + admission + feature_logic
          + block(engine, "func mathStrictnessScore(")
          + "\nenum ChangeEngine {\n" + block(engine, "enum ContactApprovalSource")
          + "\n" + methods + driver + monitor_checks + "\n}\n" + checks + delay_checks
          + authorization_checks + latency_checks + wake_checks + budget_checks
          + '\nif !delayFailures.isEmpty { exit(1) }\n')
with tempfile.TemporaryDirectory(prefix="demora-schedule-tests-") as directory:
    source_path = Path(directory) / "main.swift"
    binary_path = Path(directory) / "checks"
    source_path.write_text(source)
    subprocess.run(["xcrun", "swiftc", str(source_path), "-o", str(binary_path)], check=True)
    subprocess.run([str(binary_path)], check=True)
