#!/usr/bin/env python3
"""Run: python3 Tests/LegacyReplayRecoveryHarness.py

Compile and execute the unchanged, extracted restoreFromReplay method with
in-memory storage and monitor spies. No app modules, UserDefaults, App Groups,
network, real monitors, Screen Time tokens, or live state are used. The fixture
state is deliberately synthetic; this is control-flow/source-regression evidence,
not a claim about device callback delivery or cross-process storage durability.

The source gate compares against the fixed pre-removal commit, NOT moving HEAD.
Only the two retired UI assignments may differ inside restoreFromReplay.
"""

from pathlib import Path
import difflib
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
BASELINE = "27328835aa2ed75b8f5741ba4dd57738cd1dfe96"
APP_PATH = "Latch/AppModel.swift"


def block(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def equal_source(actual, expected, label):
    if actual != expected:
        diff = "".join(difflib.unified_diff(
            expected.splitlines(keepends=True), actual.splitlines(keepends=True),
            fromfile=f"{BASELINE[:7]} {label}", tofile=f"working {label}"))
        raise AssertionError(f"Unexpected source change:\n{diff}")


def source_checks(app, baseline):
    signature = "private func restoreFromReplay()"
    original = block(baseline, signature)
    expected = original
    for assignment in ("        tutorial = nil\n", "        isReplay = false\n"):
        assert expected.count(assignment) == 1, "Baseline UI assignment changed"
        expected = expected.replace(assignment, "", 1)
    actual = block(app, signature)
    equal_source(actual, expected, "restoreFromReplay")

    retired = (
        "TutorialStep", "tutorial", "inTutorial", "isReplay", "replayFailed",
        "calendarFocusNowNext", "tutorialScreen", "applyBarVisible",
        "advanceTutorial", "tutorialDidOpenCalendar", "tutorialFreezeStart",
        "freezePending", "tutorialRemaining", "finishReplay", "skipTutorial",
        "finishTutorial",
    )
    code = "\n".join(line.split("//", 1)[0] for line in app.splitlines())
    for name in retired:
        assert not re.search(rf"\b{re.escape(name)}\b", code), f"Retired symbol remains: {name}"

    # Every surviving method besides these four is byte-for-byte identical.
    # This covers setup/reset, migration, retry recovery, authorization, timing,
    # accounting access, and the actual asynchronous delayed-apply path.
    exceptions = {"queue", "refreshAfterExternalApply", "restoreFromReplay", "debugFullReset"}
    unchanged = 0
    for match in re.finditer(r"^    (?:(?:private|nonisolated|static) )*func (\w+)\(",
                             baseline, re.MULTILINE):
        name = match.group(1)
        if name in retired or name in exceptions:
            continue
        opening = baseline.index("{", match.start())
        signature = baseline[match.start():opening]
        equal_source(block(app, signature), block(baseline, signature), name)
        unchanged += 1

    # The DEBUG-only reset stays for the owner's fresh-install testing; only its
    # two retired tutorial assignments may go.
    original_reset = block(baseline, "func debugFullReset()")
    expected_reset = original_reset
    for assignment in ("        tutorial = nil\n", "        isReplay = false\n"):
        assert expected_reset.count(assignment) == 1, "Baseline reset assignment changed"
        expected_reset = expected_reset.replace(assignment, "", 1)
    equal_source(block(app, "func debugFullReset()"), expected_reset, "debugFullReset (retired references only)")
    reset_at = app.index("func debugFullReset()")
    assert app.rfind("#if DEBUG", 0, reset_at) > app.rfind("#endif", 0, reset_at), "reset stays DEBUG-only"

    original_init = block(baseline, "    init()")
    expected_init = original_init.replace("        isReplay = SharedStore.isReplaying\n", "", 1)
    expected_init = expected_init.replace(" && tutorial == nil", "", 1)
    equal_source(block(app, "    init()"), expected_init, "init (retired references only)")
    assert original_init.count("restoreFromReplay()") == 1
    assert block(app, "func retrySetupStorage()").count("restoreFromReplay()") == 1

    original_queue = block(baseline, "func queue(")
    tour_start = original_queue.index("            // Tutorial:")
    tour_branch = block(original_queue, "            if let step = tutorial")
    tour_end = original_queue.index(tour_branch) + len(tour_branch) + 1
    expected_queue = original_queue[:tour_start] + original_queue[tour_end:]
    expected_queue = expected_queue.replace("if let change {", "if change != nil {", 1)
    equal_source(block(app, "func queue("), expected_queue, "queue (tutorial branch only)")
    original_refresh = block(baseline, "func refreshAfterExternalApply()")
    expected_refresh = original_refresh[:original_refresh.index("        // Tutorial:")] + "    }"
    equal_source(block(app, "func refreshAfterExternalApply()"), expected_refresh,
                 "refreshAfterExternalApply (tutorial branch only)")
    print(f"PASS source: exact recovery equivalence to {BASELINE[:7]} minus two UI assignments; "
          f"{unchanged} surviving methods unchanged", flush=True)
    return actual


INFRASTRUCTURE = r'''
import Foundation

// Synthetic payload: there are no FamilyControls imports or real tokens.
struct LatchState: Codable, Equatable {
    var rules: [String]
    var pendingDeadlines: [Int]
    var budgets: [Int]
    var waits: [Int]
    var protections: [Bool]
    var isSetUp: Bool
}
let saved = LatchState(rules: ["limit-A", "schedule-B", "free-period-C"],
    pendingDeadlines: [2_000_000_100, 2_000_000_900], budgets: [15, 45],
    waits: [300, 900], protections: [true, false], isSetUp: true)
let practice = LatchState(rules: ["practice-only"], pendingDeadlines: [9],
    budgets: [1], waits: [1, 1], protections: [false, false], isSetUp: false)

enum Spy {
    static var events: [String] = []
    static var monitorStates: [LatchState] = []
    static var coherentMonitorState = true
    static var activeModel: AppModel?
    static func monitor(_ name: String, state: LatchState) {
        events.append(name)
        monitorStates.append(state)
        coherentMonitorState = coherentMonitorState
            && SharedStore.persisted == saved && SharedStore.backupBytes == nil
            && !SharedStore.replayValue && !SharedStore.simulationValue
            && activeModel?.state == saved && SharedStore.blockedIDs.isEmpty
    }
}

enum SharedStore {
    static var recovery = false
    static var backupBytes: Data?
    static var persisted = practice
    static var rejectSave = false
    static var rejectReplayClear = false
    static var replayValue = true
    static var simulationValue = true
    static var blockedIDs: Set<UUID> = [UUID(uuidString: "11111111-1111-4111-8111-111111111111")!]
    // Unrelated accounting must never be reset by the recovery method.
    static var accounting = ["spent": 43, "split-credit": 7, "extra-time": 12, "wake-deadline": 999]
    static var stateRecoveryNeeded: Bool {
        Spy.events.append("readRecovery")
        return recovery
    }
    static func loadBackup() -> LatchState? {
        Spy.events.append("loadBackup")
        guard let backupBytes else { return nil }
        return try? JSONDecoder().decode(LatchState.self, from: backupBytes)
    }
    static func save(_ value: LatchState) -> Bool {
        Spy.events.append("save")
        if rejectSave { return false }
        persisted = value
        return true
    }
    static var isReplaying: Bool {
        get { Spy.events.append("readReplay"); return replayValue }
        set {
            Spy.events.append("setReplay")
            if !rejectReplayClear { replayValue = newValue }
        }
    }
    static func clearBackup() {
        Spy.events.append("clearBackup")
        precondition(persisted == saved && !replayValue, "Backup cleared before verified restore")
        backupBytes = nil
    }
    static var simulating: Bool {
        get { simulationValue }
        set { Spy.events.append("setSimulation"); simulationValue = newValue }
    }
    static func saveBlockedLimitIDs(_ ids: Set<UUID>) {
        Spy.events.append("saveBlockedIDs")
        blockedIDs = ids
    }
}
enum ChangeEngine {
    static func reconfigureDailyMonitoring(state: LatchState) { Spy.monitor("daily", state: state) }
    static func reconfigureWindowMonitoring(state: LatchState) { Spy.monitor("windows", state: state) }
}
enum LimitFeatures {
    static func reconfigureSplitMonitoring(state: LatchState) { Spy.monitor("split", state: state) }
    static func reconcile(state: LatchState) { Spy.monitor("reconcile", state: state) }
}
enum ShieldController {
    static func refresh() { Spy.monitor("shields", state: Spy.activeModel!.state) }
}
final class AppModel {
    var state = practice { didSet { Spy.events.append("publishState") } }
    var selectedTab = 3 { didSet { Spy.events.append("selectTab") } }
    var setupStorageUnavailable = false { didSet { Spy.events.append("storageUnavailable") } }
    func restoreForTest() { restoreFromReplay() }
'''


CHECKS = r'''
var assertions = 0
var scenarios = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !value() { fatalError(message + " events=" + Spy.events.joined(separator: ",")) }
}
let initialBlockedIDs = SharedStore.blockedIDs
let initialAccounting = SharedStore.accounting
let encodedBackup = try JSONEncoder().encode(saved)
let successEvents = ["readRecovery", "loadBackup", "save", "setReplay", "readReplay",
    "clearBackup", "setSimulation", "publishState", "saveBlockedIDs", "daily",
    "split", "reconcile", "windows", "shields", "selectTab"]

func freshModel() -> AppModel {
    SharedStore.recovery = false
    SharedStore.backupBytes = encodedBackup
    SharedStore.persisted = practice
    SharedStore.rejectSave = false
    SharedStore.rejectReplayClear = false
    SharedStore.replayValue = true
    SharedStore.simulationValue = true
    SharedStore.blockedIDs = initialBlockedIDs
    SharedStore.accounting = initialAccounting
    Spy.events = []; Spy.monitorStates = []; Spy.coherentMonitorState = true
    let model = AppModel()
    Spy.activeModel = model
    scenarios += 1
    return model
}

func failed(_ model: AppModel, backup: Data?, persisted: LatchState,
            events: [String]) {
    check(model.setupStorageUnavailable, "Recovery failure did not close setup")
    check(SharedStore.backupBytes == backup, "Recoverable backup was lost or rewritten")
    check(SharedStore.persisted == persisted, "Unexpected saved-state mutation")
    check(SharedStore.replayValue, "Failure cleared the replay marker")
    check(SharedStore.simulationValue, "Failure left simulation before verified recovery")
    check(model.state == practice && model.selectedTab == 3, "Failure published state/navigation")
    check(SharedStore.blockedIDs == initialBlockedIDs, "Failure changed blocked IDs")
    check(SharedStore.accounting == initialAccounting, "Failure reset accounting")
    check(Spy.monitorStates.isEmpty, "Failure invoked monitor/shield restoration")
    check(Spy.events == events + ["storageUnavailable"], "Failure effects/order changed")
}

do {
    let model = freshModel()
    SharedStore.backupBytes = nil
    model.restoreForTest()
    failed(model, backup: nil, persisted: practice, events: ["readRecovery", "loadBackup"])
}
for bytes in [Data("corrupt backup".utf8), Data("{}".utf8)] {
    let model = freshModel()
    SharedStore.backupBytes = bytes
    model.restoreForTest()
    failed(model, backup: bytes, persisted: practice, events: ["readRecovery", "loadBackup"])
}
do {
    let model = freshModel()
    SharedStore.recovery = true
    model.restoreForTest()
    failed(model, backup: encodedBackup, persisted: practice, events: ["readRecovery"])
}
do {
    let model = freshModel()
    SharedStore.rejectSave = true
    model.restoreForTest()
    failed(model, backup: encodedBackup, persisted: practice,
           events: ["readRecovery", "loadBackup", "save"])
}
do {
    let model = freshModel()
    SharedStore.rejectReplayClear = true
    model.restoreForTest()
    // Saving succeeded, but read-back of the replay marker failed. Keep the
    // backup, practice UI and simulation intact; do not touch the monitors.
    failed(model, backup: encodedBackup, persisted: saved,
           events: ["readRecovery", "loadBackup", "save", "setReplay", "readReplay"])
}
for simulation in [true, false] {
    let model = freshModel()
    SharedStore.simulationValue = simulation
    model.restoreForTest()
    check(!model.setupStorageUnavailable, "Success marked storage unavailable")
    check(SharedStore.persisted == saved && model.state == saved, "Saved rules/deadlines changed")
    check(SharedStore.backupBytes == nil && !SharedStore.replayValue, "Success retained replay data")
    check(!SharedStore.simulationValue, "Success remained simulated")
    check(SharedStore.blockedIDs.isEmpty && model.selectedTab == 0, "Success finalization changed")
    check(SharedStore.accounting == initialAccounting, "Success reset accounting side stores")
    check(Spy.monitorStates == Array(repeating: saved, count: 5), "Monitor restoration state changed")
    check(Spy.coherentMonitorState, "Monitors ran before coherent persistence/publication")
    check(Spy.events == successEvents, "Success effects/order changed")
}
// An interrupted recovery can retry the same backup without a fresh setup.
for failure in ["save", "marker"] {
    let model = freshModel()
    SharedStore.rejectSave = failure == "save"
    SharedStore.rejectReplayClear = failure == "marker"
    model.restoreForTest()
    check(model.setupStorageUnavailable && SharedStore.backupBytes == encodedBackup,
          "Failed attempt lost retry evidence")
    SharedStore.rejectSave = false; SharedStore.rejectReplayClear = false
    Spy.events = []
    model.restoreForTest()
    check(Spy.events == successEvents, "Retry restoration order changed")
    check(SharedStore.persisted == saved && model.state == saved, "Retry lost real rules")
    check(SharedStore.backupBytes == nil && !SharedStore.replayValue, "Retry did not finalize")
    check(SharedStore.accounting == initialAccounting, "Retry reset accounting")
    // The original method deliberately leaves clearing the recovery UI flag
    // to retrySetupStorage after migration; don't silently change that behavior.
    check(model.setupStorageUnavailable, "Restore changed the retry caller's recovery flag")
}
print("PASS runtime: \(scenarios) scenarios, \(assertions) assertions (actual restoreFromReplay body)")
'''


def main():
    app = (ROOT / APP_PATH).read_bytes().decode("utf-8")
    baseline = subprocess.run(
        ["git", "show", f"{BASELINE}:{APP_PATH}"], cwd=ROOT,
        check=True, capture_output=True).stdout.decode("utf-8")
    method = source_checks(app, baseline)
    swift = INFRASTRUCTURE + method + "\n}\n" + CHECKS
    with tempfile.TemporaryDirectory(prefix="demora-legacy-recovery-") as directory:
        source = Path(directory) / "main.swift"
        executable = Path(directory) / "recovery-test"
        source.write_text(swift)
        subprocess.run(["swiftc", str(source), "-o", str(executable)], check=True, timeout=60)
        subprocess.run([str(executable)], check=True, timeout=30)


if __name__ == "__main__":
    main()
