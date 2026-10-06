#!/usr/bin/env python3
"""Exercise the actual random developer fixture and migration in local suites.

No App Group is opened. Only SwiftUI's observation wrapper and opaque Apple
tokens are stubbed. UI/source checks are structural, not device interaction.
Run: python3 Tests/DeveloperDemosHarness.py
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


demos = (ROOT / "Latch/DeveloperDemosView.swift").read_text()
onboarding = (ROOT / "Latch/OnboardingView.swift").read_text()
welcome = (ROOT / "Latch/RedesignWelcomeView.swift").read_text()
settings = (ROOT / "Latch/SettingsView.swift").read_text()
store = (ROOT / "Shared/SharedStore.swift").read_text()
models = (ROOT / "Shared/SharedModels.swift").read_text().replace(
    "import FamilyControls\n", ""
).replace("import ManagedSettings\n", "")
phrases = (ROOT / "Shared/PhraseWords.swift").read_text()
fixture = block(demos, "final class DeveloperMigrationSample").replace(
    ": ObservableObject", ""
).replace("@Published ", "")
migration = store[store.index("    static let redesignMigrationKey"):
                  store.index("    /// True only during the first-run tutorial.")]

assert demos.splitlines()[2] == "#if DEBUG" and demos.strip().endswith("#endif")
debug_settings = settings[settings.index("#if DEBUG"):settings.index("#endif")]
assert "DeveloperDemosView()" in debug_settings
assert "if !isDemo, model.state.delayPolicy.isValid" in onboarding
assert "guard !isDemo else { return }" in onboarding
assert "if let demo {\n                demo.onComplete" in onboarding
assert "if isDemo {\n                        demoSelection = true" in onboarding
assert "if isDemo {\n                if authTried" in onboarding
completion = block(welcome, "private func complete(")
demo_return = block(completion, "if demoState != nil")
assert "onComplete()" in demo_return and "return" in demo_return
assert completion.index(demo_return) < completion.index("model.selectedTab")
for forbidden in ["SharedStore.defaults", "SharedStore.save(", "ChangeEngine.",
                  "ShieldController.", "ContactsRelay.", "requestAuthorization(",
                  "debugFullReset(", "replayTutorial(", "completeInitialSetup("]:
    assert forbidden not in demos, forbidden
assert "preferences.disabled" not in onboarding[
    onboarding.index("if let demo {\n                        Button(\"Close\""):
    onboarding.index("} else {\n                        preferences.disabled")]

infrastructure = r'''
import Foundation
struct FamilyActivitySelection: Codable, Equatable {
    var applicationTokens: Set<String> = []
    var categoryTokens: Set<String> = []
    var webDomainTokens: Set<String> = []
}
func tr(_ key: String) -> String { key }
enum TimeGuard { static func now() -> Date { Date() } }
enum DemoraNotifications { static func rescheduleFreeBoundaries(state: LatchState) {} }
enum DemoraWidgetSnapshot { static func publish(state: LatchState) {} }
struct SharedStore {
    static let canarySuite = "demora-demo-tests-canary." + UUID().uuidString
    static let defaults = UserDefaults(suiteName: canarySuite)!
    static func loadState() -> LatchState { LatchState() }
'''

checks = r'''
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { print("FAIL: \(message)"); exit(1) }
}
SharedStore.defaults.set(Data("real setup canary".utf8), forKey: LatchConstants.stateKey)
SharedStore.defaults.set(["spent-limit"], forKey: LatchConstants.blockedKey)
SharedStore.defaults.set(false, forKey: SharedStore.redesignWelcomeKey)
let canary = SharedStore.defaults.persistentDomain(forName: SharedStore.canarySuite)!
var firstIDs = Set<UUID>()
var budgets = Set<Int>()
for index in 0..<200 {
    var sample: DeveloperMigrationSample? = DeveloperMigrationSample()
    let suite = sample!.suiteName
    check(suite != SharedStore.canarySuite && suite != LatchConstants.appGroupID, "suite isolation")
    check(sample!.error == nil && sample!.migrated == nil, "fixture creation \(index)")
    let storage = UserDefaults(suiteName: suite)!
    let original = storage.data(forKey: LatchConstants.stateKey)!
    let json = try JSONSerialization.jsonObject(with: original) as! [String: Any]
    check(json["delayMode"] == nil, "fixture isn't legacy")
    check(!storage.bool(forKey: SharedStore.redesignMigrationKey), "premature marker")
    firstIDs.insert(sample!.previous.limits[0].id)
    budgets.insert(sample!.previous.limits[0].minutesPerDay)
    sample!.migrate()
    check(sample!.error == nil && sample!.migrated != nil, "preservation checks \(index): \(sample!.error ?? "no state")")
    check(sample!.offersMathReplacement, "legacy math offer missing")
    check(sample!.offersDayNightSetup, "initial day/night offer missing")
    var dayNight = DayNightGroup(name: "Sample mornings")
    dayNight.scope.limitIDs = [sample!.migrated!.limits[0].id]
    let oldLimits = sample!.migrated!.limits
    let oldPending = sample!.migrated!.pending
    check(sample!.installDayNight([dayNight]), "initial day/night setup failed")
    check(!sample!.offersDayNightSetup && !sample!.installDayNight([dayNight]), "day/night allowance reused")
    check(sample!.migrated!.limits == oldLimits && sample!.migrated!.pending == oldPending,
          "initial day/night setup changed legacy settings")
    let phrase = PhrasePolicy(name: "Sample replacement", kind: .random(50),
        allowedErrors: 0, allowed: [.limitChanges])
    let expanded = PhrasePolicy(name: "Not a replacement", kind: .random(50),
        allowedErrors: 0, allowed: [.extraTime])
    check(!sample!.installReplacement([expanded]), "migration granted new extra-time permissions")
    check(sample!.installReplacement([phrase]), "sample phrase replacement failed")
    check(!sample!.offersMathReplacement && !sample!.installReplacement([phrase]), "sample waiver reused")
    check(sample!.migrated!.pending.count == 1, "obsolete pending edit retained")
    check(storage.data(forKey: LatchConstants.stateKey + ".preRedesign2") == original, "exact raw backup")
    let migrated = storage.data(forKey: LatchConstants.stateKey)
    check(SharedStore.prepareRedesignMigration(in: storage), "second migration failed")
    check(storage.data(forKey: LatchConstants.stateKey) == migrated, "second migration changed bytes")
    sample!.regenerate()
    check(sample!.migrated == nil && sample!.error == nil, "regeneration didn't reset preview")
    check(storage.data(forKey: LatchConstants.stateKey + ".preRedesign2") == nil, "stale backup reused")
    sample!.migrate()
    check(sample!.migrated != nil && sample!.error == nil, "regenerated migration failed")
    sample = nil
    check((storage.persistentDomain(forName: suite) ?? [:]).isEmpty, "sample suite not cleaned up")
    check(NSDictionary(dictionary: SharedStore.defaults.persistentDomain(forName: SharedStore.canarySuite)!)
        .isEqual(to: canary), "live-store canary changed")
}
check(firstIDs.count == 200 && budgets.count > 1, "fixtures weren't varied")
SharedStore.defaults.removePersistentDomain(forName: SharedStore.canarySuite)
print("Developer demos: 200 randomized migration/regeneration/isolation cases passed; source safety checks passed")
'''

source = infrastructure + migration + "\n}\n" + models + phrases + fixture + checks
with tempfile.TemporaryDirectory(prefix="demora-developer-demo-tests-") as directory:
    source_path = Path(directory) / "main.swift"
    binary_path = Path(directory) / "checks"
    source_path.write_text(source)
    subprocess.run(["xcrun", "swiftc", str(source_path), "-o", str(binary_path)], check=True)
    subprocess.run([str(binary_path)], check=True)
