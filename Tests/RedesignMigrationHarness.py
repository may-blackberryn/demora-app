#!/usr/bin/env python3
"""Run: python3 Tests/RedesignMigrationHarness.py

Compile the actual redesign migration, load/save/replay-backup methods, models,
initial-setup gate and legacy-passcode redactor. UserDefaults uses a random local suite (never an App
Group); a thin adapter can reject writes to exercise read-back failures.
Notifications, widgets, opaque Screen Time tokens and monitor work are stubs.
This proves single-process method behavior, not App Group durability, app launch
ordering, real token compatibility, or cross-process migration serialization.
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


store = (ROOT / "Shared/SharedStore.swift").read_text()
models = (ROOT / "Shared/SharedModels.swift").read_text().replace(
    "import FamilyControls\n", ""
).replace("import ManagedSettings\n", "")
app = (ROOT / "Latch/AppModel.swift").read_text()
engine = (ROOT / "Shared/ChangeEngine.swift").read_text()
phrases = (ROOT / "Shared/PhraseWords.swift").read_text()
budget = (ROOT / "Shared/MonitoringBudget.swift").read_text()

if "static func prepareRedesignMigration()" not in store:
    raise SystemExit("Missing actual SharedStore.prepareRedesignMigration; no mock migration is tested")

# Keep the complete relevant sections, including attributes and any private
# helper declarations. Exclude only the real App Group defaults and unrelated
# file-coordinated usage stores, whose platform behavior is not under test.
store_logic = (
    store[store.index("    static let redesignMigrationKey"):
          store.index("    // MARK: - Tutorial replay backup")]
    + store[store.index("    private static let backupKey"):
            store.index("    #if DEBUG")]
)
# The fault-injection adapter implements the same defaults operations; retain
# the actual migration body while adapting its explicit storage parameter.
store_logic = store_logic.replace("in defaults: UserDefaults", "in defaults: LocalDefaults")
# Replace only the App Group URL with this test suite's local lock location.
store_logic = store_logic.replace(block(store, "private static var stateCoordinationURL: URL?"),
    'private static var stateCoordinationURL: URL? { FileManager.default.temporaryDirectory.appendingPathComponent(defaults.suite + ".lock") }')

infrastructure = r'''
import Foundation
struct FamilyActivitySelection: Codable, Equatable {
    var applicationTokens: Set<String> = []
    var categoryTokens: Set<String> = []
    var webDomainTokens: Set<String> = []
}
func tr(_ key: String) -> String { key }
enum TimeGuard { static func now() -> Date { Date(timeIntervalSince1970: 2_000_000_000) } }
enum Effects {
    static var notifications = 0
    static var widgets = 0
    static var monitoring = 0
    static var publishedUnderLock = false
    static func reset() { notifications = 0; widgets = 0; monitoring = 0; publishedUnderLock = false }
}
enum DemoraNotifications {
    static func rescheduleFreeBoundaries(state: LatchState) {
        Effects.notifications += 1
        Effects.publishedUnderLock = Effects.publishedUnderLock || Thread.current.threadDictionary["demora.stateMutation.coordinating"] as? Bool == true
    }
}
enum DemoraWidgetSnapshot {
    static func publish(state: LatchState) {
        Effects.widgets += 1
        Effects.publishedUnderLock = Effects.publishedUnderLock || Thread.current.threadDictionary["demora.stateMutation.coordinating"] as? Bool == true
    }
}
// All successful storage calls reach real Foundation UserDefaults. Faults are
// confined to this adapter, not inserted into the production method bodies.
final class LocalDefaults {
    let suite = "demora-migration-tests-" + UUID().uuidString
    let storage: UserDefaults
    var rejectWrites: Set<String> = []
    var writes: [String] = []
    init() { storage = UserDefaults(suiteName: suite)! }
    func data(forKey key: String) -> Data? { storage.data(forKey: key) }
    func bool(forKey key: String) -> Bool { storage.bool(forKey: key) }
    func set(_ value: Any?, forKey key: String) {
        writes.append(key)
        if !rejectWrites.contains(key) { storage.set(value, forKey: key) }
    }
    func removeObject(forKey key: String) { storage.removeObject(forKey: key) }
    func reset() {
        storage.removePersistentDomain(forName: suite)
        rejectWrites = []; writes = []; Effects.reset()
        Keychain.value = nil; Keychain.rejectWrite = false; Keychain.writes = 0
    }
}
enum Keychain {
    static var value: String?
    static var rejectWrite = false
    static var writes = 0
    static func getString(for key: String) -> String? { value }
    static func setString(_ text: String, for key: String) {
        writes += 1
        if !rejectWrite { value = text }
    }
}
enum SharedStore {
    static let defaults = LocalDefaults()
    static func saveBlockedLimitIDs(_ ids: Set<UUID>) { Effects.monitoring += 1 }
'''

app_stub = r'''
// Real admission is covered separately; monitor work remains an effect stub.
enum MonitorRegistration {
    static func clearRejection() {}
    static func admit(state: LatchState, running: Set<String>, repair: Bool = false) -> Bool {
        MonitoringBudget.required(state: state, running: running) <= MonitoringBudget.maximum || repair
    }
}
struct DeviceActivityName { var rawValue: String }
struct DeviceActivityCenter { var activities: [DeviceActivityName] { [] } }
enum ChangeEngine {
    static func ensureMonitoringOffMain() async { Effects.monitoring += 1 }
    static func reconfigureDailyMonitoring(state: LatchState) { Effects.monitoring += 1 }
    static func reconfigureWindowMonitoring(state: LatchState) { Effects.monitoring += 1 }
}
enum LimitFeatures {
    static func reconfigureSplitMonitoring(state: LatchState) { Effects.monitoring += 1 }
    static func reconcile(state: LatchState) { Effects.monitoring += 1 }
}
enum ShieldController { static func refresh() { Effects.monitoring += 1 } }
final class AppModel {
    var setupStorageUnavailable = false
    var state = LatchState()
    var selectedTab = 0
    var tutorial: Int? = 1
    var isReplay = true
    static let screenTimeCodeKey = "latch.screenTimeCode"
    func migrateCodeForTest() { migrateScreenTimeCodeToKeychain() }
    func restoreForTest() { restoreFromReplay() }
'''

app_stub = app_stub.replace("enum ChangeEngine {", "enum ChangeEngine {\n"
    + 'private static let deviceActivityWorkQueue = DispatchQueue(label: "demora.migration-install-test")\n'
    + block(engine, "static func replaceLegacyMathOffMain("), 1)

checks = r'''
var cases = 0
var failures: [String] = []
var caseName = ""
let stateKey = LatchConstants.stateKey
let backupKey = stateKey + ".preRedesign2"
let recoveryKey = "latch.stateRecoveryNeeded"
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append("\(caseName): \(message)") }
}
func scenario(_ name: String, _ body: () throws -> Void) {
    SharedStore.defaults.reset(); cases += 1; caseName = name
    do { try body() } catch { failures.append("\(name): \(error)") }
}
let limitID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
let contactID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
let scheduleID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
let selection = FamilyActivitySelection(applicationTokens: ["legacy-app"],
    categoryTokens: ["legacy-category"], webDomainTokens: ["legacy-site"])
let limit = AppLimit(id: limitID, name: "Preserve budget", selection: selection,
    minutesPerDay: 45, weekdayMinutes: [1: 15, 6: 90], wakeDelayMinutes: 20,
    split: LimitSplit(cutoffMinutes: 720, beforeMinutes: 10, carryUnused: true),
    extraTime: LimitExtraTime(minutesPerUse: 5, usesPerDay: 3, waitMinutes: 7))
let contact = TrustedContact(id: contactID, name: "Legacy contact", kind: .email("test@example.invalid"))
var schedule = BlockSchedule(name: "Night", mode: .blockSelected,
    selection: selection, startMinutes: 1320, endMinutes: 420,
    recurrence: .weekly([2, 4]), addedAt: Date(timeIntervalSince1970: 123))
schedule.id = scheduleID
let actions: [ChangeAction] = [.setStrictDelay(600), .setLenientDelay(1200),
    .configureLimit(limit), .removeSchedule(id: scheduleID),
    .setMathOverride(enabled: true, difficulty: .high, count: 5, wrong: .nothing),
    .setPasswordOverride(enabled: true, passwordHash: "retired")]
let pending = actions.enumerated().map { index, action in
    PendingChange(id: UUID(uuidString: String(format: "44444444-4444-4444-8444-%012d", index + 1))!,
        createdAt: Date(timeIntervalSince1970: 1_999_999_000 + Double(index)),
        appliesAt: Date(timeIntervalSince1970: 2_000_005_000 + Double(index)),
        direction: index == 0 ? .stricter : .lenient, summary: "old \(index)", action: action)
}
func legacyRaw() throws -> Data {
    var state = LatchState()
    state.isSetUp = true; state.strictDelay = 300; state.lenientDelay = 900
    state.limits = [limit]; state.schedules = [schedule]; state.pending = pending
    state.overrides.contactsEnabled = true; state.overrides.contacts = [contact]
    state.blockAppRemoval = true; state.blockAdultWebsites = true
    state.blockedDomains = ["example.invalid"]
    state.preventUnlockAt = Date(timeIntervalSince1970: 2_000_003_000)
    state.passwordViewUnlockAt = Date(timeIntervalSince1970: 2_000_004_000)
    state.screenTimeCode = ""
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
    json.removeValue(forKey: "delayMode")
    var overrides = json["overrides"] as! [String: Any]
    overrides.removeValue(forKey: "passwordPolicies"); overrides.removeValue(forKey: "phrasePolicies")
    overrides["mathEnabled"] = true; overrides["passwordEnabled"] = true
    overrides["passwordHash"] = "original-readable-legacy-hash"
    var contacts = overrides["contacts"] as! [[String: Any]]
    contacts[0].removeValue(forKey: "allowed"); contacts[0].removeValue(forKey: "accepted")
    overrides["contacts"] = contacts; json["overrides"] = overrides
    var limits = json["limits"] as! [[String: Any]]
    limits[0]["pacing"] = ["usageMinutes": 5, "intervalMinutes": 20, "cooldownMinutes": 15]
    json["limits"] = limits
    var queued = json["pending"] as! [[String: Any]]
    var action = queued[2]["action"] as! [String: Any]
    var configure = action["configureLimit"] as! [String: Any]
    var queuedLimit = configure["_0"] as! [String: Any]
    queuedLimit["pacing"] = ["usageMinutes": 5, "intervalMinutes": 20, "cooldownMinutes": 15]
    configure["_0"] = queuedLimit; action["configureLimit"] = configure
    queued[2]["action"] = action; json["pending"] = queued
    // Unknown legacy data must survive in the raw backup even if the decoder
    // intentionally ignores it in the active representation.
    json["retiredRawEvidence"] = "keep exact spaces, ordering, and unknown fields"
    return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
}
func assertPreserved(_ state: LatchState) {
    check(state.isSetUp && state.delayMode == .separate && state.strictDelay == 300 && state.lenientDelay == 900,
          "setup or delays changed")
    check(state.limits == [limit], "limit identity, tokens, weekday/split/wake/extra budgets changed")
    check(state.limits.first?.extraTime?.effectiveSteps == Array(repeating: LimitExtraStep(minutes: 5, waitMinutes: 7), count: 3),
          "legacy uniform extra time changed")
    check(state.schedules == [schedule], "schedule identity/recurrence/metadata changed")
    check(state.overrides.contactsEnabled && state.overrides.contacts == [contact], "legacy contact identity/permission migration")
    check(!state.overrides.contacts[0].allowed.contains(.extraTime), "legacy contact gained extra-time permission")
    check(state.pending == Array(pending.prefix(4)), "pending IDs, actions, direction, summary, creation or deadline changed")
    check(state.blockAppRemoval && state.blockAdultWebsites && state.blockedDomains == ["example.invalid"], "protections lost")
    check(state.preventUnlockAt == Date(timeIntervalSince1970: 2_000_003_000)
        && state.passwordViewUnlockAt == Date(timeIntervalSince1970: 2_000_004_000)
        && state.screenTimeCode.isEmpty, "unlock deadlines/redacted passcode changed")
    check(state.limits.first?.pacing == nil && !state.overrides.mathEnabled
        && !state.overrides.passwordEnabled && state.overrides.passwordHash == nil, "retired policies survived")
}
scenario("fresh install") {
    check(SharedStore.prepareRedesignMigration(), "fresh migration failed")
    check(SharedStore.defaults.data(forKey: stateKey) == nil && SharedStore.defaults.data(forKey: backupKey) == nil,
          "fresh migration invented state/backup")
    check(!SharedStore.defaults.bool(forKey: SharedStore.redesignMigrationKey), "fresh install marked legacy-migrated")
}
scenario("exact raw backup and preserved state") {
    let raw = try legacyRaw(); SharedStore.defaults.set(raw, forKey: stateKey)
    check(SharedStore.prepareRedesignMigration(), "migration failed")
    check(SharedStore.defaults.data(forKey: backupKey) == raw, "backup not byte-for-byte original")
    check(SharedStore.defaults.bool(forKey: SharedStore.redesignMigrationKey), "marker missing")
    check(!SharedStore.stateRecoveryNeeded, "healthy state marked recovery")
    assertPreserved(SharedStore.loadState())
    check(SharedStore.defaults.data(forKey: stateKey) != raw, "legacy bytes never reencoded")
}
scenario("idempotence including later edits") {
    let raw = try legacyRaw(); SharedStore.defaults.set(raw, forKey: stateKey)
    check(SharedStore.prepareRedesignMigration(), "first migration")
    let committed = SharedStore.defaults.data(forKey: stateKey)
    check(SharedStore.prepareRedesignMigration(), "second migration")
    check(SharedStore.defaults.data(forKey: stateKey) == committed, "idempotent migration rewrote active bytes")
    var state = SharedStore.loadState(); state.limits[0].minutesPerDay = 33
    SharedStore.save(state)
    let edited = SharedStore.defaults.data(forKey: stateKey)
    check(SharedStore.prepareRedesignMigration(), "post-edit migration")
    check(SharedStore.defaults.data(forKey: stateKey) == edited && SharedStore.defaults.data(forKey: backupKey) == raw,
          "later edit rolled back or original backup overwritten")
}
scenario("interrupted migration with existing original backup") {
    let raw = try legacyRaw(); SharedStore.defaults.set(raw, forKey: backupKey)
    let decoded = try JSONDecoder().decode(LatchState.self, from: raw)
    SharedStore.defaults.set(try JSONEncoder().encode(decoded), forKey: stateKey)
    check(SharedStore.prepareRedesignMigration(), "resume failed")
    check(SharedStore.defaults.data(forKey: backupKey) == raw, "resume replaced original backup")
    assertPreserved(SharedStore.loadState())
}
scenario("usage side stores untouched") {
    SharedStore.defaults.set(try legacyRaw(), forKey: stateKey)
    let evidence: [String: Data] = [LatchConstants.blockedKey: Data("spent IDs".utf8),
        "latch.splitMonitorEpoch.v1": Data("split monitor epoch".utf8),
        "latch.freeCreditByLimit.v1": Data("free credit".utf8),
        "latch.lastResetDay": Data("2026-10-2".utf8)]
    for (key, value) in evidence { SharedStore.defaults.set(value, forKey: key) }
    check(SharedStore.prepareRedesignMigration(), "migration failed")
    for (key, value) in evidence { check(SharedStore.defaults.data(forKey: key) == value, "side state changed: \(key)") }
}
scenario("new scoped contacts and three-portion budgets preserved") {
    var state = try JSONDecoder().decode(LatchState.self, from: legacyRaw())
    state.overrides.contacts[0].accepted = false
    state.overrides.contacts[0].inviteId = "existing-invite"
    state.overrides.contacts[0].allowed = [.scheduleChanges, .extraTime]
    state.limits[0].split = LimitSplit(cutoffMinutes: 720, beforeMinutes: 10, carryUnused: false,
        secondCutoffMinutes: 1080, middleMinutes: 15)
    let raw = try JSONEncoder().encode(state); SharedStore.defaults.set(raw, forKey: stateKey)
    check(SharedStore.prepareRedesignMigration(), "migration failed")
    let migrated = SharedStore.loadState()
    check(migrated.overrides.contacts == state.overrides.contacts && migrated.limits == state.limits,
          "existing scopes, acceptance/invite identity or three-portion budgets changed")
    check(migrated.pending == state.pending && SharedStore.defaults.data(forKey: backupKey) == raw,
          "deadlines or original bytes changed")
}
scenario("unfinished tutorial not marked migrated") {
    var state = LatchState(); state.strictDelay = 12; state.pending = [pending[0]]
    let raw = try JSONEncoder().encode(state); SharedStore.defaults.set(raw, forKey: stateKey)
    check(SharedStore.prepareRedesignMigration(), "unfinished state failed")
    check(SharedStore.defaults.data(forKey: stateKey) == raw && SharedStore.defaults.data(forKey: backupKey) == nil,
          "unfinished state rewritten/backed up")
    check(!SharedStore.defaults.bool(forKey: SharedStore.redesignMigrationKey), "tutorial marked migrated")
}
for raw in [Data("not-json".utf8), Data(#"{"isSetUp":true,"limits":"wrong type"}"#.utf8),
            Data(#"{"isSetUp":true,"delayMode":"unknown-future-mode"}"#.utf8)] {
    for marked in [false, true] {
        scenario("corrupt migration, marker=\(marked), \(String(decoding: raw, as: UTF8.self))") {
            SharedStore.defaults.set(raw, forKey: stateKey)
            SharedStore.defaults.set(marked, forKey: SharedStore.redesignMigrationKey)
            check(!SharedStore.prepareRedesignMigration(), "corruption reported success")
            check(SharedStore.stateRecoveryNeeded, "corruption missing recovery fence")
            check(SharedStore.defaults.data(forKey: stateKey) == raw
                && SharedStore.defaults.data(forKey: stateKey + ".corrupt") == raw, "corrupt bytes lost")
            check(SharedStore.defaults.data(forKey: backupKey) == nil, "corruption promoted to legacy backup")
            SharedStore.save(LatchState())
            check(SharedStore.defaults.data(forKey: stateKey) == raw, "blank save wiped corrupt setup")
            check(Effects.notifications == 0 && Effects.widgets == 0, "refused save emitted effects")
        }
    }
}
scenario("loadState recovery fence and explicit repaired bytes") {
    let raw = Data("broken".utf8); SharedStore.defaults.set(raw, forKey: stateKey)
    _ = SharedStore.loadState()
    check(SharedStore.stateRecoveryNeeded, "load failure missing fence")
    SharedStore.save(LatchState())
    check(SharedStore.defaults.data(forKey: stateKey) == raw, "load-then-save wiped setup")
    SharedStore.defaults.set(try legacyRaw(), forKey: stateKey)
    check(SharedStore.prepareRedesignMigration() && !SharedStore.stateRecoveryNeeded, "repair cannot resume migration")
    assertPreserved(SharedStore.loadState())
}
for rejected in [backupKey, stateKey, SharedStore.redesignMigrationKey] {
    scenario("migration read-back failure \(rejected)") {
        let raw = try legacyRaw(); SharedStore.defaults.set(raw, forKey: stateKey)
        SharedStore.defaults.rejectWrites = [rejected]
        let succeeded = SharedStore.prepareRedesignMigration()
        check(!succeeded, "failed storage write reported migration success")
        if rejected != SharedStore.redesignMigrationKey {
            check(SharedStore.defaults.data(forKey: stateKey) == raw, "failed write changed original active data")
        }
        check(!SharedStore.defaults.bool(forKey: SharedStore.redesignMigrationKey), "failed migration committed marker")
        if rejected == backupKey {
            SharedStore.defaults.rejectWrites = []
            SharedStore.save(LatchState())
            check(SharedStore.defaults.data(forKey: stateKey) == raw, "failed backup leaves save unfenced")
            let loaded = SharedStore.loadState()
            SharedStore.save(loaded)
            check(SharedStore.defaults.data(forKey: stateKey) == raw,
                  "loadState clears backup-failure fence; save reencodes legacy state without verified backup")
        }
    }
}
scenario("tutorial backup does not collide with migration backup") {
    let raw = try legacyRaw(); SharedStore.defaults.set(raw, forKey: stateKey)
    check(SharedStore.prepareRedesignMigration(), "migration failed")
    let state = SharedStore.loadState()
    check(SharedStore.saveBackup(state), "tutorial backup failed")
    SharedStore.isReplaying = true
    check(SharedStore.isReplaying && SharedStore.loadBackup()?.limits == state.limits, "replay backup unavailable")
    SharedStore.clearBackup(); SharedStore.isReplaying = false
    check(SharedStore.defaults.data(forKey: backupKey) == raw, "clearing replay erased original migration backup")
}
scenario("save encode failure retains last state") {
    let raw = try legacyRaw(); SharedStore.defaults.set(raw, forKey: stateKey)
    var invalid = LatchState(); invalid.lenientDelay = .nan
    SharedStore.save(invalid)
    check(SharedStore.defaults.data(forKey: stateKey) == raw, "failed encode overwrote state")
    check(Effects.notifications == 0 && Effects.widgets == 0, "failed encode emitted effects")
}
scenario("legacy secret refuses raw backup") {
    var object = try JSONSerialization.jsonObject(with: legacyRaw()) as! [String: Any]
    object["screenTimeCode"] = "1234"
    let raw = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    SharedStore.defaults.set(raw, forKey: stateKey)
    check(!SharedStore.prepareRedesignMigration(), "legacy secret backed up")
    check(SharedStore.defaults.data(forKey: stateKey) == raw && SharedStore.defaults.data(forKey: backupKey) == nil,
          "refused secret backup altered raw bytes or copied plaintext")
    check(!SharedStore.defaults.bool(forKey: SharedStore.redesignMigrationKey), "refused secret marked migrated")
}
for kind in ["new", "canonical", "keychainFailure", "redactionFailure"] {
    scenario("actual passcode migration \(kind)") {
        var object = try JSONSerialization.jsonObject(with: legacyRaw()) as! [String: Any]
        object["screenTimeCode"] = "1234"
        let raw = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        SharedStore.defaults.set(raw, forKey: stateKey)
        if kind == "canonical" { Keychain.value = "9876" }
        if kind == "keychainFailure" { Keychain.rejectWrite = true }
        if kind == "redactionFailure" { SharedStore.defaults.rejectWrites = [stateKey] }
        AppModel().migrateCodeForTest()
        if kind == "keychainFailure" || kind == "redactionFailure" {
            check(SharedStore.defaults.data(forKey: stateKey) == raw, "failed passcode migration lost original")
            check(!SharedStore.prepareRedesignMigration(), "failed passcode migration allowed plaintext backup")
            check(SharedStore.defaults.data(forKey: backupKey) == nil, "plaintext secret copied into backup")
        } else {
            check(Keychain.value == (kind == "canonical" ? "9876" : "1234"), "canonical Keychain overwritten/passcode lost")
            check(Keychain.writes == (kind == "canonical" ? 0 : 1), "unexpected Keychain write")
            guard let redacted = SharedStore.defaults.data(forKey: stateKey) else {
                check(false, "redaction erased state"); return
            }
            let after = try JSONSerialization.jsonObject(with: redacted) as! [String: Any]
            object["screenTimeCode"] = ""
            check(NSDictionary(dictionary: after).isEqual(to: object), "redactor changed keys other than secret")
            check(SharedStore.prepareRedesignMigration(), "redacted migration failed")
            check(SharedStore.defaults.data(forKey: backupKey) == redacted, "backup not exact redacted raw bytes")
            if let backup = SharedStore.defaults.data(forKey: backupKey) {
                let backed = try JSONSerialization.jsonObject(with: backup) as! [String: Any]
                check((backed["screenTimeCode"] as? String) == "" && backed["retiredRawEvidence"] != nil,
                      "secret persisted or unknown field lost in backup")
            }
            assertPreserved(SharedStore.loadState())
        }
    }
}
for kind in ["normal", "missingBackup", "corruptBackup", "recoveryFence", "writeFailure"] {
    scenario("actual replay restoration \(kind)") {
        let real = try JSONDecoder().decode(LatchState.self, from: legacyRaw())
        if kind != "missingBackup" {
            check(SharedStore.saveBackup(real), "fixture backup failed")
        }
        if kind == "corruptBackup" {
            SharedStore.defaults.set(Data("broken original backup".utf8), forKey: "latch.state.backup")
        }
        let originalBackup = SharedStore.defaults.data(forKey: "latch.state.backup")
        let tutorialRaw = try JSONEncoder().encode(LatchState())
        SharedStore.defaults.set(tutorialRaw, forKey: stateKey)
        SharedStore.isReplaying = true; SharedStore.simulating = true
        if kind == "recoveryFence" { SharedStore.defaults.set(true, forKey: recoveryKey) }
        if kind == "writeFailure" { SharedStore.defaults.rejectWrites = [stateKey] }
        AppModel().restoreForTest()
        if kind == "normal" {
            assertPreserved(SharedStore.loadState())
            check(SharedStore.defaults.data(forKey: "latch.state.backup") == nil
                && !SharedStore.isReplaying && !SharedStore.simulating, "successful replay not finalized")
        } else {
            check(SharedStore.defaults.data(forKey: "latch.state.backup") == originalBackup,
                  "failed restore deleted recoverable original backup")
            check(SharedStore.isReplaying, "failed restore marked replay complete; startup can reset tutorial as fresh")
            check(SharedStore.defaults.data(forKey: stateKey) == tutorialRaw, "failed restore unexpectedly changed state")
        }
    }
}
scenario("one-time math replacement preserves rules and rejects stale writer") {
    SharedStore.defaults.set(try legacyRaw(), forKey: stateKey)
    check(SharedStore.prepareRedesignMigration(), "migration failed")
    let original = SharedStore.loadState()
    let phrase = PhrasePolicy(name: "Replacement", kind: .random(50), allowedErrors: 0,
        allowed: [.limitChanges, .scheduleChanges])
    check(SharedStore.canReplaceLegacyMath, "enabled math wasn't offered a replacement")
    let replacement = SharedStore.mathReplacementState([phrase], state: original, in: SharedStore.defaults)!
    check(replacement.pending == original.pending && replacement.limits == original.limits
          && replacement.schedules == original.schedules && replacement.overrides.contacts == original.overrides.contacts,
          "replacement changed rules, contacts, deadlines or budgets")
    check(SharedStore.coordinateStateMutation { SharedStore.save(replacement) } == true,
          "nested coordinated save failed")
    check(!Effects.publishedUnderLock && Effects.notifications == 1 && Effects.widgets == 1,
          "service effects ran while coordinated or weren't published once")
    // Simulate an extension/UI that read before the migration committed.
    var stale = original; stale.pending = []
    check(!SharedStore.save(stale), "stale writer undid replacement or pending state")
    check(SharedStore.loadState().overrides.phrasePolicies == [phrase], "replacement overwritten")
    check(!SharedStore.canReplaceLegacyMath, "committed waiver still available")
    check(SharedStore.mathReplacementState([phrase], state: SharedStore.loadState(), in: SharedStore.defaults) == nil,
          "waiver reused")
}
for kind in ["seen", "consumed", "fresh", "noMath", "recovery", "failedMigration"] {
    scenario("math replacement eligibility \(kind)") {
        SharedStore.defaults.set(try legacyRaw(), forKey: stateKey)
        check(SharedStore.prepareRedesignMigration(), "migration failed")
        switch kind {
        case "seen": SharedStore.defaults.set(true, forKey: SharedStore.redesignWelcomeKey)
        case "consumed": SharedStore.defaults.set(true, forKey: SharedStore.mathReplacementConsumedKey)
        case "noMath": SharedStore.defaults.set(false, forKey: SharedStore.mathReplacementEligibleKey)
        case "fresh": var state = SharedStore.loadState(); state.isSetUp = false; _ = SharedStore.save(state)
        case "recovery": SharedStore.defaults.set(true, forKey: recoveryKey)
        default: SharedStore.defaults.set(true, forKey: "latch.redesign2.migrationUnverified")
        }
        check(!SharedStore.canReplaceLegacyMath, "ineligible waiver available")
    }
}
scenario("math replacement validates batch and does not broaden permissions") {
    SharedStore.defaults.set(try legacyRaw(), forKey: stateKey)
    check(SharedStore.prepareRedesignMigration(), "migration failed")
    let original = SharedStore.loadState()
    let phrase = PhrasePolicy(name: "Replacement", kind: .random(50), allowedErrors: 0, allowed: [.limitChanges])
    for batch in [[], [phrase, phrase], Array(repeating: phrase, count: 6),
        [PhrasePolicy(name: "New scope", kind: .random(50), allowedErrors: 0, allowed: [.extraTime])],
        [PhrasePolicy(name: "", kind: .random(50), allowedErrors: 0, allowed: [.limitChanges])]] {
        check(SharedStore.mathReplacementState(batch, state: original, in: SharedStore.defaults) == nil,
              "invalid replacement batch accepted")
    }
    check(SharedStore.loadState().overrides.phrasePolicies.isEmpty, "validation committed a draft")
}
scenario("math replacement failed save leaves original grant available") {
    SharedStore.defaults.set(try legacyRaw(), forKey: stateKey)
    check(SharedStore.prepareRedesignMigration(), "migration failed")
    let original = SharedStore.loadState()
    let phrase = PhrasePolicy(name: "Replacement", kind: .random(50), allowedErrors: 0, allowed: [.limitChanges])
    let replacement = SharedStore.mathReplacementState([phrase], state: original, in: SharedStore.defaults)!
    SharedStore.defaults.rejectWrites = [stateKey]
    check(!SharedStore.save(replacement), "rejected write reported success")
    check(SharedStore.canReplaceLegacyMath && SharedStore.loadState().overrides.phrasePolicies.isEmpty,
          "failed save consumed grant")
}
scenario("initial day/night commit prevents stale waiver reopening") {
    SharedStore.defaults.set(try legacyRaw(), forKey: stateKey)
    check(SharedStore.prepareRedesignMigration(), "migration failed")
    let original = SharedStore.loadState()
    var group = DayNightGroup(name: "Mornings")
    group.scope.limitIDs = [original.limits[0].id]
    let updated = SharedStore.initialDayNightState([group], state: original, in: SharedStore.defaults)!
    check(SharedStore.save(updated), "initial day/night save failed")
    check(!SharedStore.canSetUpInitialDayNight, "verified flag didn't consume initial setup")
    check(!SharedStore.save(original), "stale writer reopened initial setup")
    let saved = SharedStore.loadState()
    check(saved.dayNightGroups == [group] && saved.dayNightSetupDone, "stale writer replaced groups")
    check(saved.limits == original.limits && saved.pending == original.pending
          && saved.wakeRule == original.wakeRule && saved.sleepRule == original.sleepRule,
          "additive setup changed legacy rules or deadlines")
}
scenario("failed initial day/night commit retains the allowance") {
    SharedStore.defaults.set(try legacyRaw(), forKey: stateKey)
    check(SharedStore.prepareRedesignMigration(), "migration failed")
    let original = SharedStore.loadState()
    let before = SharedStore.defaults.data(forKey: stateKey)
    var group = DayNightGroup(name: "Mornings")
    group.scope.limitIDs = [original.limits[0].id]
    let updated = SharedStore.initialDayNightState([group], state: original, in: SharedStore.defaults)!
    SharedStore.defaults.rejectWrites = [stateKey]
    check(!SharedStore.save(updated), "failed group write reported success")
    check(SharedStore.canSetUpInitialDayNight && SharedStore.defaults.data(forKey: stateKey) == before,
          "failed write consumed allowance or changed original")
}
func initialSetupChecks() async {
    for kind in ["fresh", "dayNight", "overrides", "existing", "replaying", "recovery", "unavailable", "corrupt", "invalid", "writeFailure",
                 "acceptedContact", "duplicateContact", "duplicateInvite", "missingInvite", "invalidEmail", "invalidCode", "blankContact", "disabledContacts",
                 "badHash", "blankPassword", "passwordNoScope", "duplicatePassword", "invalidPhrase", "duplicatePhrase", "legacyPassword", "legacyMath"] {
        SharedStore.defaults.reset(); cases += 1; caseName = "initial setup \(kind)"
        let model = AppModel()
        do {
            if kind == "existing" { SharedStore.defaults.set(try legacyRaw(), forKey: stateKey) }
            if kind == "corrupt" { SharedStore.defaults.set(Data("broken".utf8), forKey: stateKey) }
            if kind == "replaying" { SharedStore.isReplaying = true }
            if kind == "recovery" { SharedStore.defaults.set(true, forKey: recoveryKey) }
            if kind == "unavailable" { model.setupStorageUnavailable = true }
            if kind == "writeFailure" { SharedStore.defaults.rejectWrites = [stateKey] }
            let before = SharedStore.defaults.data(forKey: stateKey)
            let policy = DelayPolicy(mode: .shared, strictDelay: 300, lenientDelay: kind == "invalid" ? 0 : 900)
            var group = DayNightGroup(name: "Mornings")
            group.scope.limitIDs = [limit.id]
            let groups = kind == "dayNight" ? [group] : []
            var overrides = OverridesConfig()
            if kind != "fresh" && kind != "dayNight" {
                overrides.contactsEnabled = true
                overrides.contacts = [
                    TrustedContact(name: "Alex", kind: .email("alex@example.invalid"),
                                   accepted: false, inviteId: UUID().uuidString, allowed: [.limitChanges]),
                    TrustedContact(name: "Sam", kind: .latchUser(code: "SAM123"),
                                   accepted: false, inviteId: UUID().uuidString, allowed: [.sessionChanges, .extraTime])]
                overrides.passwordPolicies = [PasswordPolicy(name: "Backup", hash: String(repeating: "a", count: 64), allowed: [.limitChanges, .extraTime])]
                overrides.phrasePolicies = [PhrasePolicy(name: "Pause", kind: .random(100), allowedErrors: 1, allowed: [.scheduleChanges]),
                    PhrasePolicy(name: "Custom", kind: .custom("stop and think"), allowedErrors: nil, allowed: [.extraTime])]
            }
            switch kind {
            case "acceptedContact": overrides.contacts[0].accepted = true
            case "duplicateContact":
                var duplicate = overrides.contacts[0]; duplicate.id = UUID(); duplicate.inviteId = UUID().uuidString
                duplicate.kind = .email("ALEX@example.invalid"); overrides.contacts.append(duplicate)
            case "duplicateInvite": overrides.contacts[1].inviteId = overrides.contacts[0].inviteId
            case "missingInvite": overrides.contacts[0].inviteId = ""
            case "invalidEmail": overrides.contacts[0].kind = .email("not an email")
            case "invalidCode": overrides.contacts[1].kind = .latchUser(code: "X")
            case "blankContact": overrides.contacts[0].name = "  "
            case "disabledContacts": overrides.contactsEnabled = false
            case "badHash": overrides.passwordPolicies[0].hash = "plaintext-password"
            case "blankPassword": overrides.passwordPolicies[0].name = " "
            case "passwordNoScope": overrides.passwordPolicies[0].allowed = []
            case "duplicatePassword": overrides.passwordPolicies.append(overrides.passwordPolicies[0])
            case "invalidPhrase": overrides.phrasePolicies[0].kind = .random(51)
            case "duplicatePhrase": overrides.phrasePolicies.append(overrides.phrasePolicies[0])
            case "legacyPassword": overrides.passwordEnabled = true
            case "legacyMath": overrides.mathEnabled = true
            default: break
            }
            let accepted = await model.completeInitialSetup(policy: policy, firstLimit: limit, dayNightGroups: groups, overrides: overrides)
            let shouldAccept = ["fresh", "dayNight", "overrides"].contains(kind)
            check(accepted == shouldAccept, "wrong setup acceptance")
            if shouldAccept {
                let state = SharedStore.loadState()
                check(state.isSetUp && state.delayPolicy == policy.normalized && state.limits == [limit], "new setup not saved")
                check(state.dayNightGroups == groups && state.dayNightSetupDone, "fresh day/night drafts or completion flag lost")
                check(state.overrides == overrides && state.pending.isEmpty, "override drafts changed or became pending changes")
                check(state.overrides.contacts.allSatisfy { !$0.isUsable }, "setup bypassed contact consent")
                check(!state.overrides.mathEnabled && !state.overrides.passwordEnabled, "legacy override enabled")
                let savedBytes = SharedStore.defaults.data(forKey: stateKey)!
                check(!String(decoding: savedBytes, as: UTF8.self).contains("plaintext-password"), "plaintext secret saved")
                let second = await model.completeInitialSetup(policy: policy, firstLimit: nil, overrides: OverridesConfig())
                check(!second && SharedStore.defaults.data(forKey: stateKey) == savedBytes, "setup could be reused to reset policies")
                check(Effects.monitoring == 1 && SharedStore.defaults.bool(forKey: SharedStore.redesignMigrationKey), "setup side effects missing")
            } else {
                check(SharedStore.defaults.data(forKey: stateKey) == before, "rejected setup changed original bytes")
                check(Effects.monitoring == 0 && !SharedStore.defaults.bool(forKey: SharedStore.redesignMigrationKey), "rejected setup committed flags/monitors")
            }
        } catch { failures.append("\(caseName): \(error)") }
    }
}
let finished = DispatchSemaphore(value: 0)
Task.detached {
    await initialSetupChecks()
    SharedStore.defaults.reset(); cases += 1; caseName = "actual async replacement with failed redundant marker"
    do {
        SharedStore.defaults.set(try legacyRaw(), forKey: stateKey)
        check(SharedStore.prepareRedesignMigration(), "migration failed")
        SharedStore.defaults.rejectWrites = [SharedStore.mathReplacementConsumedKey]
        let phrase = PhrasePolicy(name: "Committed", kind: .random(50), allowedErrors: 0, allowed: [.limitChanges])
        let installed = await ChangeEngine.replaceLegacyMathOffMain(with: [phrase])
        check(installed && SharedStore.loadState().overrides.phrasePolicies == [phrase], "verified install reported failure")
        check(!SharedStore.canReplaceLegacyMath, "failed redundant marker allowed waiver reuse")
        check(!Effects.publishedUnderLock, "service work under state lock")
    } catch { failures.append("\(caseName): \(error)") }
    finished.signal()
}
if finished.wait(timeout: .now() + 10) != .success { failures.append("initial setup deadlock") }
print("Redesign migration checks: \(cases) scenarios, \(failures.count) failures")
for failure in failures { print("FAIL: \(failure)") }
SharedStore.defaults.reset()
if !failures.isEmpty { exit(1) }
'''

source = (infrastructure + store_logic + "\n}\n" + models + phrases + budget
          + app_stub + block(app, "func completeInitialSetup(")
          + "\n" + block(app, "private func migrateScreenTimeCodeToKeychain()")
          + "\n" + block(app, "private func restoreFromReplay()") + "\n}\n" + checks)
with tempfile.TemporaryDirectory(prefix="demora-migration-tests-") as directory:
    source_path = Path(directory) / "main.swift"
    binary_path = Path(directory) / "checks"
    source_path.write_text(source)
    subprocess.run(["xcrun", "swiftc", str(source_path), "-o", str(binary_path)], check=True)
    subprocess.run([str(binary_path)], check=True)
