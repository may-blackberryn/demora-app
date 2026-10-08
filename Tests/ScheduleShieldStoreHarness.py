#!/usr/bin/env python3
"""Compile actual ShieldController, ScheduleShieldPlan and precedence/model code.

Run: python3 Tests/ScheduleShieldStoreHarness.py
Only framework imports are removed. ManagedSettings named stores, defaults,
coordination and wake/usage inputs are in-memory adapters; production rendering
algorithms are unchanged. This does NOT prove Apple store limits, cross-process
locking, disk durability, XPC delivery or real category membership.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def declaration(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def portable(source):
    return source.replace("import FamilyControls\n", "").replace("import ManagedSettings\n", "")


sources = [portable((ROOT / "Shared" / name).read_text()) for name in [
    "SharedModels.swift", "SchedulePrecedence.swift", "ScheduleShieldPlan.swift", "ShieldController.swift"
]]
phrases = declaration((ROOT / "Shared/PhraseWords.swift").read_text(), "enum PhraseWords {")
debug_wipe = declaration((ROOT / "Shared/SharedStore.swift").read_text(), "static func debugWipeAll()")

adapters = r'''
import Foundation
struct FamilyActivitySelection: Codable, Equatable {
    var includeEntireCategory = false
    var applicationTokens: Set<String> = []
    var categoryTokens: Set<String> = []
    var webDomainTokens: Set<String> = []
}
func tr(_ text: String) -> String { text }
enum TimeGuard { static func now() -> Date { fatalError("No runtime clock expected") } }
enum Trace {
    static var events: [String] = []
    static var writeDepths: [Int] = []
    static var onMutation: ((String) -> Void)? = nil
    static func record(_ event: String) {
        events.append(event); writeDepths.append(SharedStore.coordinationDepth)
        onMutation?(event)
    }
}
enum CategoryPolicy: Equatable {
    case all(except: Set<String>)
    case specific(Set<String>, except: Set<String> = [])
}
struct WebDomain: Hashable { var domain: String }
enum WebPolicy { case auto(Set<WebDomain>, except: Set<WebDomain>) }
final class ShieldSettings {
    let name: String
    init(_ name: String) { self.name = name }
    var applications: Set<String>? = nil { didSet { Trace.record("selected-apps:" + name) } }
    var webDomains: Set<String>? = nil { didSet { Trace.record("selected-sites:" + name) } }
    var applicationCategories: CategoryPolicy? = nil {
        didSet { Trace.record("apps:" + name) }
    }
    var webDomainCategories: CategoryPolicy? = nil {
        didSet { Trace.record("sites:" + name) }
    }
}
final class ApplicationSettings {
    var denyAppRemoval: Bool? = nil { didSet { Trace.record("app-removal") } }
}
final class WebSettings {
    var blockedByFilter: WebPolicy? = nil { didSet { Trace.record("web-filter") } }
}
final class StoreData {
    let shield: ShieldSettings
    let application = ApplicationSettings()
    let webContent = WebSettings()
    init(_ name: String) { shield = ShieldSettings(name) }
}
final class ManagedSettingsStore {
    struct Name { var rawValue: String; init(_ value: String) { rawValue = value } }
    static var registry: [String: StoreData] = [:]
    let name: String
    let data: StoreData
    var shield: ShieldSettings { data.shield }
    var application: ApplicationSettings { data.application }
    var webContent: WebSettings { data.webContent }
    init(named name: Name) {
        self.name = name.rawValue
        if let existing = Self.registry[self.name] { data = existing }
        else { data = StoreData(self.name); Self.registry[self.name] = data }
    }
    func clearAllSettings() {
        Trace.record("clear:" + name)
        shield.applications = nil; shield.webDomains = nil
        shield.applicationCategories = nil; shield.webDomainCategories = nil
        application.denyAppRemoval = nil; webContent.blockedByFilter = nil
    }
    static func reset() {
        // Keep data identity: actual controller static stores retain handles.
        for name in registry.keys { ManagedSettingsStore(named: .init(name)).clearAllSettings() }
        Trace.events = []; Trace.writeDepths = []
    }
}
final class MemoryDefaults {
    var values: [String: Any] = [:]
    var writes = 0
    var rejectWrites = false
    var rejectSynchronize = false
    var corruptWrittenValue = false
    func object(forKey key: String) -> Any? {
        SharedStore.recordRuntimeRead(); return values[key]
    }
    func bool(forKey key: String) -> Bool { object(forKey: key) as? Bool ?? false }
    func dictionaryRepresentation() -> [String: Any] { values }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    func set(_ value: Any, forKey key: String) {
        Trace.record("manifest:" + key)
        if !rejectWrites {
            values[key] = corruptWrittenValue && key == "latch.scheduleCategoryStores.v1" ? "bad-readback" : value
        }
        writes += 1
    }
    @discardableResult func synchronize() -> Bool {
        Trace.events.append("synchronize"); return !rejectSynchronize
    }
}
enum GlobalWakeStatus { case inactive, awake, needsTap, waiting(Date) }
enum GlobalWake {
    static var current: GlobalWakeStatus = .inactive
    static func status(state: LatchState, at date: Date) -> GlobalWakeStatus {
        SharedStore.recordRuntimeRead(); return current
    }
}
enum DayNightWake {
    static func status(group: DayNightGroup, at date: Date) -> GlobalWakeStatus {
        SharedStore.recordRuntimeRead(); return .inactive
    }
}
enum LimitFeatures {
    enum WakeState { case notConfigured, awake, needsTap, waiting(Date) }
    static func blockedFeatureIDs(state: LatchState, at date: Date, includeWake: Bool) -> Set<UUID> {
        SharedStore.recordRuntimeRead(); return []
    }
    static func extraUnblockedIDs(state: LatchState, at date: Date) -> Set<UUID> {
        SharedStore.recordRuntimeRead(); return []
    }
    static func wakeState(for limit: AppLimit, at date: Date) -> WakeState {
        SharedStore.recordRuntimeRead(); return .notConfigured
    }
}
enum SharedStore {
    static let defaults = MemoryDefaults()
    static var state = LatchState()
    static var blockedIDs: Set<UUID> = []
    static var isReplaying = false
    static var simulating = false
    static var enforcementDegraded = false
    static var rejectCoordination = false
    static var coordinationCalls = 0
    static var coordinationDepth = 0
    static var nestedCalls = 0
    static var runtimeReadDepths: [Int] = []
    static var beforeOuterBody: (() -> Void)? = nil
    static func recordRuntimeRead() { runtimeReadDepths.append(coordinationDepth) }
    static func coordinateStateMutation<T>(_ body: () -> T) -> T? {
        coordinationCalls += 1
        if coordinationDepth > 0 { nestedCalls += 1; return body() }
        guard !rejectCoordination else { return nil }
        coordinationDepth += 1
        defer { coordinationDepth -= 1 }
        let hook = beforeOuterBody; beforeOuterBody = nil; hook?()
        return body()
    }
    static func loadBackup() -> LatchState? { recordRuntimeRead(); return nil }
    static func loadState() -> LatchState { recordRuntimeRead(); return state }
    static func loadBlockedLimitIDs() -> Set<UUID> { recordRuntimeRead(); return blockedIDs }
    static func saveBlockedLimitIDs(_ ids: Set<UUID>) { blockedIDs = ids }
    static func clearUsageTracking() {}
}
enum ChangeEngine { static func cancelResetNudge() {} }
// Same-file extension only exposes private entry points to tests. It changes
// no production rendering body or visibility in the actual source file.
extension ShieldController {
    static func renderForHarness(_ groups: [FamilyActivitySelection]) -> Bool { applyCategoryShields(groups) }
    static func applyForHarness(_ state: LatchState) { apply(state: state) }
}
'''

checks = r'''
var assertions = 0
var failures: [String] = []
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !condition() { failures.append(message) }
}
func selection(_ cats: Set<String>, apps: Set<String> = [], sites: Set<String> = []) -> FamilyActivitySelection {
    var result = FamilyActivitySelection()
    result.categoryTokens = cats; result.applicationTokens = apps; result.webDomainTokens = sites
    return result
}
func named(_ index: Int) -> ManagedSettingsStore {
    ManagedSettingsStore(named: .init("latch.schedule.category.\(index)"))
}
func reset() {
    Trace.onMutation = nil
    ManagedSettingsStore.reset()
    SharedStore.defaults.values = [:]; SharedStore.defaults.writes = 0
    SharedStore.defaults.rejectWrites = false; SharedStore.defaults.rejectSynchronize = false
    SharedStore.defaults.corruptWrittenValue = false
    SharedStore.enforcementDegraded = false; SharedStore.rejectCoordination = false
    SharedStore.coordinationCalls = 0; SharedStore.state = LatchState(); SharedStore.blockedIDs = []
    SharedStore.coordinationDepth = 0; SharedStore.nestedCalls = 0
    SharedStore.runtimeReadDepths = []; SharedStore.beforeOuterBody = nil
    GlobalWake.current = .inactive
}
let manifest = "latch.scheduleCategoryStores.v1"
let unverified = "latch.scheduleCategoryStores.unverified.v1"
reset()
let spentC = selection(["C"], apps: ["A"], sites: ["site-A"])
let newD = selection(["D"])
expect(ShieldController.renderForHarness([spentC, newD]), "renderer reports successful coordination")
expect(named(0).shield.applicationCategories == .specific(["C"], except: ["A"]), "actual app renderer preserves C's exception")
expect(named(0).shield.webDomainCategories == .specific(["C"], except: ["site-A"]), "actual website renderer preserves C's exception")
expect(named(1).shield.applicationCategories == .specific(["D"], except: []), "D renderer does not inherit global freed apps")
expect(named(1).shield.webDomainCategories == .specific(["D"], except: []), "D renderer does not inherit global freed websites")
expect(SharedStore.defaults.object(forKey: manifest) as? Int == 2, "manifest tracks allocated cohort count")
expect(Trace.events.first == "manifest:" + unverified, "unverified flag is set before metadata growth and cohort writes")
expect(Trace.events.firstIndex(of: "manifest:" + manifest)! < Trace.events.firstIndex(of: "apps:latch.schedule.category.0")!,
       "manifest is published before first cohort writes")
expect(!SharedStore.defaults.bool(forKey: unverified), "successful publication clears unverified flag")
expect(SharedStore.defaults.writes == 3, "growth writes unverified true, count, then unverified false")
Trace.events = []
expect(ShieldController.renderForHarness([spentC, newD]), "repeat renderer succeeds")
expect(SharedStore.defaults.writes == 3, "healthy repeat does not rewrite manifest or flag")
expect(!Trace.events.contains(where: { $0.hasPrefix("clear:") }), "repeat renderer does not clear active cohorts")
Trace.events = []
expect(ShieldController.renderForHarness([newD]), "smaller cohort set succeeds")
expect(named(1).shield.applicationCategories == nil && named(1).shield.webDomainCategories == nil, "obsolete app and website cohort cleared")
expect(SharedStore.defaults.object(forKey: manifest) as? Int == 2 && SharedStore.defaults.writes == 3,
       "manifest high water is retained without shrink writes")
expect(Trace.events.firstIndex(of: "sites:latch.schedule.category.0")!
    < Trace.events.firstIndex(of: "clear:latch.schedule.category.1")!, "replacement installed before obsolete cohort cleanup")
expect(ShieldController.renderForHarness([]), "free cleanup succeeds")
expect(named(0).shield.applicationCategories == nil && named(0).shield.webDomainCategories == nil, "free clears remaining app and website cohorts")
expect(SharedStore.defaults.writes == 3, "empty cleanup retains manifest without write")

// Coordination failure must leave existing cohort stores and manifest intact.
reset()
expect(ShieldController.renderForHarness([spentC]), "failure fixture initial cohort installed")
SharedStore.rejectCoordination = true; Trace.events = []
expect(!ShieldController.renderForHarness([newD]), "renderer reports nil coordination as failure")
expect(named(0).shield.applicationCategories == .specific(["C"], except: ["A"])
    && named(0).shield.webDomainCategories == .specific(["C"], except: ["site-A"]), "failed coordination preserves old cohorts")
expect(Trace.events.isEmpty && SharedStore.defaults.writes == 3, "failed coordination cannot update stores or manifest")

// ACTUAL controller apply uses category cohorts, not plan.freed. Use a promoted
// planned block (wall-clock interval, no recurring-clock fixture assumptions).
reset()
var state = LatchState()
let now = Date()
let cLimit = AppLimit(name: "Spent C", selection: selection(["C"]), minutesPerDay: 0)
state.limits = [cLimit]
let dBlock = PlannedWindow(name: "D", kind: .blockSelected, selection: selection(["D"]),
    startsAt: now.addingTimeInterval(-60), endsAt: now.addingTimeInterval(3600))
state.planned = [dBlock]
state.sessions = [BlockSession(name: "A", kind: .unblock, selection: selection([], apps: ["A"], sites: ["site-A"]),
    startedAt: now.addingTimeInterval(-60), endsAt: now.addingTimeInterval(3600))]
state.prioritizedScheduleKeys = ["planned-\(dBlock.id.uuidString)"]
ShieldController.applyForHarness(state)
expect(named(0).shield.applicationCategories == .specific(["C"], except: ["A"])
    && named(1).shield.applicationCategories == .specific(["D"]), "actual controller renders separate category app exceptions")
expect(named(0).shield.webDomainCategories == .specific(["C"], except: ["site-A"])
    && named(1).shield.webDomainCategories == .specific(["D"]), "actual controller renders separate category website exceptions")
expect(ShieldController.store.shield.applicationCategories == nil && ShieldController.store.shield.webDomainCategories == nil,
       "main store does not collapse cohorts using global freed tracking")
let oldCApp = named(0).shield.applicationCategories, oldCSite = named(0).shield.webDomainCategories
SharedStore.rejectCoordination = true
var failing = LatchState()
failing.limits = [AppLimit(name: "New E", selection: selection(["E"]), minutesPerDay: 0)]
let legacySelected = ManagedSettingsStore(named: .init("latch.dayNight.selected"))
let legacyOther = ManagedSettingsStore(named: .init("latch.dayNight.other"))
legacyOther.shield.applicationCategories = .all(except: ["old-exception"])
Trace.events = []
ShieldController.applyForHarness(failing)
expect(named(0).shield.applicationCategories == oldCApp && named(0).shield.webDomainCategories == oldCSite,
       "actual apply preserves old cohorts on coordination failure")
expect(legacySelected.shield.applicationCategories == .specific(["E"])
    && legacySelected.shield.webDomainCategories == .specific(["E"]), "coordination failure installs no-exception app/site fallback")
expect(legacyOther.shield.applicationCategories == .all(except: ["old-exception"]), "failure does not clear legacy other restrictions")
expect(SharedStore.enforcementDegraded, "coordination failure flags degraded enforcement")
expect(!Trace.events.contains(where: { $0.hasPrefix("clear:") }), "coordination failure retires no old restriction stores")
SharedStore.rejectCoordination = false; Trace.events = []
ShieldController.applyForHarness(failing)
expect(named(0).shield.applicationCategories == .specific(["E"]) && named(1).shield.applicationCategories == nil,
       "recovery installs current cohort and clears obsolete category")
expect(legacySelected.shield.applicationCategories == nil && legacyOther.shield.applicationCategories == nil,
       "successful recovery retires legacy fallback stores")
expect(Trace.events.firstIndex(of: "sites:latch.schedule.category.0")!
    < Trace.events.firstIndex(of: "clear:latch.dayNight.selected")!, "current cohorts installed before retiring conservative fallback")
failing.sessions = [BlockSession(name: "Free", kind: .free, selection: selection([]),
    startedAt: now.addingTimeInterval(-60), endsAt: now.addingTimeInterval(3600))]
ShieldController.applyForHarness(failing)
expect(named(0).shield.applicationCategories == nil && named(0).shield.webDomainCategories == nil, "actual free apply clears app/site cohort stores")

// Failed synchronize may leave the larger count in process memory. The true
// unverified flag must force a retry rather than trust that cached oldCount.
reset()
expect(ShieldController.renderForHarness([spentC]), "cached-count retry fixture installed")
SharedStore.defaults.rejectSynchronize = true
expect(!ShieldController.renderForHarness([spentC, newD]), "failed growth aborts renderer")
expect(SharedStore.defaults.object(forKey: manifest) as? Int == 2 && SharedStore.defaults.bool(forKey: unverified),
       "failed growth leaves cached larger count explicitly unverified")
Trace.events = []
expect(!ShieldController.renderForHarness([spentC, newD]), "same-sized retry cannot trust unverified cached count")
expect(Trace.events.contains("manifest:" + manifest) && Trace.events.contains("synchronize"),
       "unverified retry republishes count and synchronizes despite no growth")
expect(named(1).shield.applicationCategories == nil && named(1).shield.webDomainCategories == nil,
       "repeated failed verification never installs new cohort")
expect(SharedStore.defaults.bool(forKey: unverified), "repeated failure retains unverified flag")
SharedStore.defaults.rejectSynchronize = false; Trace.events = []
expect(ShieldController.renderForHarness([spentC, newD]), "retry recovers after successful verification")
expect(!SharedStore.defaults.bool(forKey: unverified), "successful cached-count retry clears unverified flag")
expect(named(1).shield.applicationCategories == .specific(["D"])
    && named(1).shield.webDomainCategories == .specific(["D"]), "new cohort installed only after successful verification")
let healthyWrites = SharedStore.defaults.writes
expect(ShieldController.renderForHarness([spentC, newD]) && SharedStore.defaults.writes == healthyWrites,
       "healthy verified retry stops redundant metadata writes")

// Observe category protection after EVERY setter, as if the process died at
// that boundary. A conservative old/new union bridge must precede slot reuse.
func coverage(sites: Bool) -> Set<String> {
    var result: Set<String> = []
    for data in ManagedSettingsStore.registry.values {
        let policy = sites ? data.shield.webDomainCategories : data.shield.applicationCategories
        if case .specific(let cats, _) = policy { result.formUnion(cats) }
    }
    return result
}
reset()
expect(ShieldController.renderForHarness([spentC, newD]), "transition fixture installed")
var transitionFailures: [String] = []
var observedSlotWrites = 0
Trace.onMutation = { event in
    if event.hasPrefix("apps:latch.schedule.category.") || event.hasPrefix("sites:latch.schedule.category.") {
        observedSlotWrites += 1
        if !coverage(sites: false).isSuperset(of: ["C", "D", "E"])
            || !coverage(sites: true).isSuperset(of: ["C", "D", "E"]) { transitionFailures.append(event) }
    }
}
expect(ShieldController.renderForHarness([selection(["E"], apps: ["E-app"], sites: ["E-site"]), newD, spentC]),
       "slot reorder/expansion succeeds")
expect(observedSlotWrites == 6 && transitionFailures.isEmpty, "no app/site category drop at any reordered-slot setter")
expect(legacySelected.shield.applicationCategories == .specific(["C", "D", "E"])
    && legacySelected.shield.webDomainCategories == .specific(["C", "D", "E"]),
       "bridge covers old plus new categories without exceptions")
Trace.onMutation = { event in
    if event.hasPrefix("apps:latch.schedule.category.") || event.hasPrefix("sites:latch.schedule.category.") {
        if !coverage(sites: false).isSuperset(of: ["C", "D", "E"])
            || !coverage(sites: true).isSuperset(of: ["C", "D", "E"]) { transitionFailures.append(event) }
    }
    if event == "clear:latch.dayNight.selected" {
        if named(0).shield.applicationCategories != .specific(["C"], except: ["A"])
            || named(0).shield.webDomainCategories != .specific(["C"], except: ["site-A"])
            || named(1).shield.applicationCategories != .specific(["D"])
            || named(2).shield.applicationCategories != nil { transitionFailures.append("bridge retired before complete install") }
    }
}
ShieldController.applyForHarness(state)
Trace.onMutation = nil
expect(transitionFailures.isEmpty, "bridge remains through overwrites and surplus cleanup, retired only after complete install")
expect(legacySelected.shield.applicationCategories == nil && legacySelected.shield.webDomainCategories == nil,
       "successful caller removes no-exception bridge to restore intended exceptions")
expect(coverage(sites: false) == ["C", "D"] && coverage(sites: true) == ["C", "D"],
       "completed transition has exactly new categories, no stranded E restriction")

// The actual public refresh must acquire coordination BEFORE reading saved
// state/runtime and hold it across every main/cohort/legacy store setter.
reset()
SharedStore.state.limits = [AppLimit(name: "Stale", selection: selection(["stale-cat"], apps: ["stale-app"]), minutesPerDay: 0)]
var latest = LatchState()
let latestLimit = AppLimit(name: "Latest", selection: selection(["latest-cat"], apps: ["latest-app"], sites: ["latest-site"]), minutesPerDay: 10)
latest.limits = [latestLimit]
latest.wakeRule.enabled = true; latest.wakeRule.scope.selection = selection([], apps: ["wake-app"])
var inactiveGroup = DayNightGroup(); inactiveGroup.name = "Inactive"
inactiveGroup.scope.selection = selection([], apps: ["inactive-app"]); latest.dayNightGroups = [inactiveGroup]
SharedStore.beforeOuterBody = {
    SharedStore.state = latest; SharedStore.blockedIDs = [latestLimit.id]; GlobalWake.current = .needsTap
}
ShieldController.refresh()
expect(ShieldController.store.shield.applications == ["latest-app", "wake-app"], "refresh reads newest state and usage markers after lock acquisition")
expect(ShieldController.store.shield.webDomains == ["latest-site"], "latest website baseline rendered in same transaction")
expect(!SharedStore.runtimeReadDepths.isEmpty && SharedStore.runtimeReadDepths.allSatisfy { $0 > 0 },
       "all configuration/runtime/metadata reads happen within coordination")
expect(!Trace.writeDepths.isEmpty && Trace.writeDepths.allSatisfy { $0 > 0 },
       "all main/cohort/legacy/manifest/app-removal/web-filter writes happen within coordination")
expect(SharedStore.nestedCalls == 1 && SharedStore.coordinationDepth == 0, "category helper reuses outer transaction and releases it afterward")
let beforeRejectedApps = ShieldController.store.shield.applications
let beforeRejectedCategory = named(0).shield.applicationCategories
SharedStore.rejectCoordination = true; SharedStore.state = LatchState()
Trace.events = []; Trace.writeDepths = []; SharedStore.runtimeReadDepths = []
ShieldController.refresh()
expect(Trace.events.isEmpty && SharedStore.runtimeReadDepths.isEmpty, "failed outer coordination does not read stale state or mutate any store")
expect(ShieldController.store.shield.applications == beforeRejectedApps && named(0).shield.applicationCategories == beforeRejectedCategory,
       "failed outer refresh preserves existing enforcement")
expect(SharedStore.enforcementDegraded, "failed outer refresh reports degraded enforcement")
SharedStore.rejectCoordination = false; SharedStore.simulating = true
Trace.writeDepths = []; ShieldController.refresh()
expect(!Trace.writeDepths.isEmpty && Trace.writeDepths.allSatisfy { $0 > 0 }, "simulated setup cleanup also performs every setter inside coordination")
expect(named(0).shield.applicationCategories == nil && ShieldController.store.shield.applications == nil,
       "coordinated setup cleanup clears cohort and main settings")
SharedStore.simulating = false

// A failed manifest write/synchronize/readback must abort before NEW settings.
// Exercise direct renderer and actual caller independently from the same saved
// one-cohort fixture; no claim about a failed synchronize's disk durability.
for failureMode in 0..<3 {
    reset()
    expect(ShieldController.renderForHarness([spentC]), "publish-failure fixture installed")
    SharedStore.defaults.rejectWrites = failureMode == 0
    SharedStore.defaults.rejectSynchronize = failureMode == 1
    SharedStore.defaults.corruptWrittenValue = failureMode == 2
    Trace.events = []
    expect(!ShieldController.renderForHarness([spentC, newD]), "failed manifest publish returns false (mode \(failureMode))")
    expect(named(0).shield.applicationCategories == .specific(["C"], except: ["A"])
        && named(0).shield.webDomainCategories == .specific(["C"], except: ["site-A"]), "publish failure preserves old cohort")
    expect(named(1).shield.applicationCategories == nil && named(1).shield.webDomainCategories == nil,
           "publish failure cannot apply unrecorded new cohort")
    expect(!Trace.events.contains(where: { $0.hasPrefix("apps:") || $0.hasPrefix("sites:") || $0.hasPrefix("clear:") }),
           "failed metadata guard precedes every cohort store mutation")
    SharedStore.defaults.values[manifest] = 1 // independent actual-caller fixture
    Trace.events = []
    ShieldController.applyForHarness(state)
    expect(named(1).shield.applicationCategories == nil && named(1).shield.webDomainCategories == nil,
           "actual apply cannot install new cohorts after failed publish")
    expect(legacySelected.shield.applicationCategories == .specific(["C", "D"])
        && legacySelected.shield.webDomainCategories == .specific(["C", "D"]),
           "failed manifest publish uses no-exception category fallback")
    expect(SharedStore.enforcementDegraded, "failed manifest publish flags degraded enforcement")
    expect(!Trace.events.contains(where: { $0.hasPrefix("clear:") }), "failed publish does not retire old cohorts")
}

// Pathological >46-cohort input cannot silently omit blocked categories.
reset()
let overflowGroups = (0..<48).map { selection(["cat-\($0)"], apps: ["app-\($0)"], sites: ["site-\($0)"]) }
expect(ShieldController.renderForHarness(overflowGroups), "overflow renderer succeeds conservatively")
expect(SharedStore.defaults.object(forKey: manifest) as? Int == 46, "overflow stays within declared cohort capacity")
expect(named(44).shield.applicationCategories == .specific(["cat-44"], except: ["app-44"]), "non-overflow cohort keeps exceptions")
expect(named(45).shield.applicationCategories == .specific(["cat-45", "cat-46", "cat-47"]), "overflow preserves all categories without app exceptions")
expect(named(45).shield.webDomainCategories == .specific(["cat-45", "cat-46", "cat-47"]), "overflow website fallback has no exceptions")
expect(SharedStore.enforcementDegraded, "overflow reports conservative degradation")

// Unreadable/out-of-range manifest conservatively sweeps all allocated slots.
for corrupt: Any in ["unreadable", -1, 1000] {
    reset()
    SharedStore.defaults.values[manifest] = corrupt
    named(45).shield.applicationCategories = .specific(["stale"])
    named(45).shield.webDomainCategories = .specific(["stale-site"])
    expect(ShieldController.renderForHarness([spentC]), "corrupt manifest recovery succeeds")
    expect(named(45).shield.applicationCategories == nil && named(45).shield.webDomainCategories == nil,
           "corrupt manifest cannot strand last cohort")
    expect(named(0).shield.applicationCategories == .specific(["C"], except: ["A"]), "corrupt manifest preserves current cohort")
}
// Actual debug wipe keeps cleanup metadata, but no latch configuration.
reset()
SharedStore.defaults.values = [manifest: 2, unverified: true, "latch.state": "old configuration",
    "latch.language": "es", "latch.blocked": ["spent"], "latch.selectedTokens": ["private-token"], "other.setting": true]
SharedStore.debugWipeAll()
expect(SharedStore.defaults.object(forKey: manifest) as? Int == 2 && SharedStore.defaults.bool(forKey: unverified),
       "actual debug wipe preserves count and unverified cleanup metadata")
expect(SharedStore.defaults.values.keys.filter { $0.hasPrefix("latch.") }.sorted() == [manifest, unverified].sorted(),
       "debug wipe preserves no latch state, tokens, usage or language settings")
expect(SharedStore.defaults.object(forKey: "other.setting") as? Bool == true, "debug wipe remains limited to latch namespace")
for failure in failures { print("FAIL: \(failure)") }
print("Schedule shield stores: \(assertions) assertions, \(failures.count) failures")
print("Actual controller/plan/models; in-memory named-store/defaults/coordination/status adapters; no Apple XPC or live persistence")
if !failures.isEmpty { exit(1) }
'''

with tempfile.TemporaryDirectory(prefix="demora-shield-store-harness-") as directory:
    source_path = Path(directory) / "main.swift"
    binary_path = Path(directory) / "checks"
    source_path.write_text("\n".join([adapters, "extension SharedStore {", debug_wipe, "}", *sources, phrases, checks]))
    subprocess.run(["xcrun", "swiftc", str(source_path), "-o", str(binary_path)], check=True)
    subprocess.run([str(binary_path)], check=True, env={**os.environ, "TZ": "America/New_York"})
