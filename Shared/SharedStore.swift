//
//  SharedStore.swift
//  Persistence via App Group UserDefaults so the app and both
//  extensions read/write the same state.
//

import Foundation

struct SharedStore {  
    static let defaults = UserDefaults(suiteName: LatchConstants.appGroupID)!
    static let redesignMigrationKey = "latch.redesign2.migrated"
    static let redesignWelcomeKey = "latch.redesign2.welcomeSeen"
    static let redesignIntroKey = "latch.redesign2.introSeen"
    static var canSetUpInitialDayNight: Bool {
        guard !stateRecoveryNeeded else { return false }
        return canSetUpInitialDayNight(in: defaults, state: loadState())
    }

    static func canSetUpInitialDayNight(in defaults: UserDefaults, state: LatchState) -> Bool {
        state.isSetUp && !state.dayNightSetupDone && state.dayNightGroups.isEmpty
            && defaults.bool(forKey: redesignMigrationKey)
            && !defaults.bool(forKey: redesignWelcomeKey)
            && !defaults.bool(forKey: "latch.stateRecoveryNeeded")
            && !defaults.bool(forKey: "latch.redesign2.migrationUnverified")
    }

    /// Additive, one-shot welcome allowance. Never edits an existing gate.
    static func initialDayNightState(_ groups: [DayNightGroup], state: LatchState,
                                     in defaults: UserDefaults) -> LatchState? {
        guard canSetUpInitialDayNight(in: defaults, state: state), !groups.isEmpty,
              DayNightGroup.isValidCollection(groups, limits: state.limits) else { return nil }
        var updated = state
        updated.dayNightGroups = groups
        updated.dayNightSetupDone = true
        return updated
    }
    static let mathReplacementEligibleKey = "latch.redesign2.mathReplacement.eligible"
    static let mathReplacementCapturedKey = "latch.redesign2.mathReplacement.captured"
    static let mathReplacementConsumedKey = "latch.redesign2.mathReplacement.consumed"

    static var canReplaceLegacyMath: Bool {
        guard !stateRecoveryNeeded else { return false }
        return canReplaceLegacyMath(in: defaults, state: loadState())
    }

    static func canReplaceLegacyMath(in defaults: UserDefaults, state: LatchState) -> Bool {
        state.isSetUp && !state.mathPhraseReplacementDone
            && !defaults.bool(forKey: mathReplacementConsumedKey)
            && defaults.bool(forKey: redesignMigrationKey)
            && defaults.bool(forKey: mathReplacementEligibleKey)
            && !defaults.bool(forKey: redesignWelcomeKey)
            && !defaults.bool(forKey: "latch.stateRecoveryNeeded")
            && !defaults.bool(forKey: "latch.redesign2.migrationUnverified")
    }

    /// Only the original math gate's pending-change permissions can be
    /// replaced. Extra-time access is a new feature and still delay-gated.
    static func mathReplacementState(_ policies: [PhrasePolicy], state: LatchState,
                                     in defaults: UserDefaults) -> LatchState? {
        let legacyScope = Set(OverrideCapability.allCases.filter { $0 != .extraTime })
        guard canReplaceLegacyMath(in: defaults, state: state),
              (1...5).contains(policies.count),
              Set(policies.map(\.id)).count == policies.count,
              policies.allSatisfy({ policy in
                  PhraseWords.isValid(policy) && policy.allowed.isSubset(of: legacyScope)
                      && !state.overrides.phrasePolicies.contains(where: { $0.id == policy.id })
              }) else { return nil }
        var replacement = state
        replacement.overrides.phrasePolicies.append(contentsOf: policies)
        replacement.mathPhraseReplacementDone = true
        return replacement
    }

    private static var stateCoordinationURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: LatchConstants.appGroupID)?
            .appendingPathComponent("stateMutation.lock")
    }

    /// Shared by app and monitor writers. Nested saves stay on the same
    /// transaction rather than trying to acquire the coordination a second time.
    static func coordinateStateMutation<T>(_ body: () -> T) -> T? {
        let threadKey = "demora.stateMutation.coordinating"
        if Thread.current.threadDictionary[threadKey] as? Bool == true { return body() }
        guard let url = stateCoordinationURL else { return nil }
        var result: T?
        var error: NSError?
        var publish = false
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &error) { _ in
            Thread.current.threadDictionary[threadKey] = true
            defer { Thread.current.threadDictionary.removeObject(forKey: threadKey) }
            result = body()
            publish = Thread.current.threadDictionary["demora.stateMutation.publish"] as? Bool == true
            Thread.current.threadDictionary.removeObject(forKey: "demora.stateMutation.publish")
        }
        if error != nil { return nil }
        // Notification and WidgetKit services run only after coordination is
        // released. Project the latest saved state, not a stale caller snapshot.
        if publish {
            let state = loadState()
            DemoraNotifications.rescheduleFreeBoundaries(state: state)
            DemoraWidgetSnapshot.publish(state: state)
        }
        return result
    }
    static var stateRecoveryNeeded: Bool {
        defaults.bool(forKey: "latch.stateRecoveryNeeded")
            || defaults.bool(forKey: "latch.redesign2.migrationUnverified")
    }

    /// Back up the exact legacy bytes before committing the tolerant decoded
    /// representation. Decoding changes retire only the documented legacy
    /// features; they do not recalculate IDs, deadlines, budgets, or usage.
    /// Never substitute a blank setup if migration cannot be verified.
    @discardableResult
    static func prepareRedesignMigration() -> Bool {
        prepareRedesignMigration(in: defaults)
    }

    /// The same migration can run against an isolated developer-preview suite.
    /// Only this explicit store is touched: no monitors, widgets or live usage.
    @discardableResult
    static func prepareRedesignMigration(in defaults: UserDefaults) -> Bool {
        guard let raw = defaults.data(forKey: LatchConstants.stateKey) else { return true }
        do {
            let state = try JSONDecoder().decode(LatchState.self, from: raw)
            if defaults.bool(forKey: "latch.stateRecoveryNeeded") {
                defaults.set(false, forKey: "latch.stateRecoveryNeeded")
            }
            guard state.isSetUp else { return true }
            // Capture before tolerant decoding retires the old switches. An
            // existing redesign backup also supports installations that ran
            // the migration before this replacement offer was introduced.
            if !defaults.bool(forKey: mathReplacementCapturedKey) {
                let legacy = defaults.data(forKey: LatchConstants.stateKey + ".preRedesign2") ?? raw
                let json = try JSONSerialization.jsonObject(with: legacy) as? [String: Any]
                let overrides = json?["overrides"] as? [String: Any]
                let eligible = overrides?["mathEnabled"] as? Bool ?? false
                defaults.set(eligible, forKey: mathReplacementEligibleKey)
                defaults.set(true, forKey: mathReplacementCapturedKey)
                guard defaults.bool(forKey: mathReplacementCapturedKey),
                      defaults.bool(forKey: mathReplacementEligibleKey) == eligible else {
                    defaults.set(true, forKey: "latch.redesign2.migrationUnverified")
                    return false
                }
            }
            if defaults.bool(forKey: redesignMigrationKey) {
                defaults.set(false, forKey: "latch.redesign2.migrationUnverified")
                return true
            }
            // The app migrates a legacy passcode into Keychain first. Never
            // create a durable plain-text copy of that secret in this backup.
            guard state.screenTimeCode.isEmpty else { return false }
            let backupKey = LatchConstants.stateKey + ".preRedesign2"
            if defaults.data(forKey: backupKey) == nil {
                defaults.set(raw, forKey: backupKey)
                guard defaults.data(forKey: backupKey) == raw else {
                    defaults.set(true, forKey: "latch.redesign2.migrationUnverified")
                    return false
                }
            }
            let migrated = try JSONEncoder().encode(state)
            defaults.set(migrated, forKey: LatchConstants.stateKey)
            guard defaults.data(forKey: LatchConstants.stateKey) == migrated else {
                defaults.set(true, forKey: "latch.redesign2.migrationUnverified")
                return false
            }
            defaults.set(true, forKey: redesignMigrationKey)
            guard defaults.bool(forKey: redesignMigrationKey) else {
                defaults.set(true, forKey: "latch.redesign2.migrationUnverified")
                return false
            }
            defaults.set(false, forKey: "latch.redesign2.migrationUnverified")
            return true
        } catch {
            defaults.set(raw, forKey: LatchConstants.stateKey + ".corrupt")
            defaults.set(true, forKey: "latch.stateRecoveryNeeded")
            NSLog("Demora: migration could not decode saved setup; original retained.")
            return false
        }
    }

    /// True only during the first-run tutorial. While set, no real Screen Time
    /// shields or monitors are applied — the app goes through the motions but
    /// nothing is actually blocked (so a user can't lock themselves out, even
    /// out of Demora, mid-tutorial).
    static var simulating: Bool {
        get { defaults.bool(forKey: "latch.simulating") }
        set { defaults.set(newValue, forKey: "latch.simulating") }
    }

    /// True when a DeviceActivity `startMonitoring` call failed on the last
    /// setup — usually because there are more limits/schedules than iOS will
    /// monitor at once. Surfaced to the user so background blocking degrading
    /// isn't silent. Cleared by a clean reconfigure.
    static var enforcementDegraded: Bool {
        get { defaults.bool(forKey: "latch.enforcementDegraded") }
        set { defaults.set(newValue, forKey: "latch.enforcementDegraded") }
    }

    static func loadState() -> LatchState {
        guard let data = defaults.data(forKey: LatchConstants.stateKey) else {
            return LatchState()   // genuinely fresh install
        }
        do {
            let state = try JSONDecoder().decode(LatchState.self, from: data)
            // Healthy reads must not publish preferences changes. SwiftUI
            // observes this suite, so writing even an unchanged false value
            // from a view's read path can keep invalidating its render graph.
            // A genuinely repaired blob still clears recovery once.
            if defaults.bool(forKey: "latch.stateRecoveryNeeded") {
                defaults.set(false, forKey: "latch.stateRecoveryNeeded")
            }
            return state
        } catch {
            // Don't silently wipe a user's setup: log, and stash the unreadable
            // bytes so they're recoverable rather than overwritten by the blank
            // state we're forced to return.
            let corruptKey = LatchConstants.stateKey + ".corrupt"
            if defaults.data(forKey: corruptKey) != data {
                NSLog("Demora: state decode failed (%@). Preserved raw blob.",
                      String(describing: error))
                defaults.set(data, forKey: corruptKey)
            }
            if !defaults.bool(forKey: "latch.stateRecoveryNeeded") {
                defaults.set(true, forKey: "latch.stateRecoveryNeeded")
            }
            return LatchState()
        }
    }

    @discardableResult
    static func save(_ state: LatchState) -> Bool {
        coordinateStateMutation {
            let saved = saveCoordinated(state)
            if saved { Thread.current.threadDictionary["demora.stateMutation.publish"] = true }
            return saved
        } ?? false
    }

    private static func saveCoordinated(_ state: LatchState) -> Bool {
        guard !stateRecoveryNeeded else {
            NSLog("Demora: refusing to overwrite an unreadable saved setup.")
            return false
        }
        // A stale UI/replay snapshot cannot undo the consumed migration grant.
        let previousState = defaults.data(forKey: LatchConstants.stateKey)
            .flatMap { try? JSONDecoder().decode(LatchState.self, from: $0) }
        let previousReplacementDone = previousState?.mathPhraseReplacementDone ?? false
        if previousState?.dayNightSetupDone == true, !state.dayNightSetupDone {
            NSLog("Demora: refusing stale state that would undo initial day/night setup.")
            return false
        }
        if (defaults.bool(forKey: mathReplacementConsumedKey) || previousReplacementDone),
           !state.mathPhraseReplacementDone {
            NSLog("Demora: refusing stale state that would undo a completed phrase replacement.")
            return false
        }
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: LatchConstants.stateKey)
            guard defaults.data(forKey: LatchConstants.stateKey) == data else {
                NSLog("Demora: state save could not be verified; kept recoverable backups.")
                return false
            }
            return true
        } catch {
            NSLog("Demora: state encode failed (%@). Kept previous state.",
                  String(describing: error))
            return false
        }
    }

    // MARK: - Tutorial replay backup
    //
    // Replaying the walkthrough runs the tour over sample data. We stash the
    // user's real state first and restore it when the replay ends (or on a
    // relaunch after the replay was interrupted), so nothing is lost.

    private static let backupKey = "latch.state.backup"
    private static let replayingKey = "latch.replaying"

    static var isReplaying: Bool {
        get { defaults.bool(forKey: replayingKey) }
        set { defaults.set(newValue, forKey: replayingKey) }
    }
    /// Stash the real state before a replay. Returns whether the backup was
    /// written AND reads back byte-for-byte — a replay must never start unless we
    /// can prove the real setup is safely recoverable.
    @discardableResult
    static func saveBackup(_ state: LatchState) -> Bool {
        guard let data = try? JSONEncoder().encode(state) else { return false }
        defaults.set(data, forKey: backupKey)
        guard let check = defaults.data(forKey: backupKey), check == data else {
            return false
        }
        return true
    }
    static func loadBackup() -> LatchState? {
        guard let data = defaults.data(forKey: backupKey),
              let state = try? JSONDecoder().decode(LatchState.self, from: data)
        else { return nil }
        return state
    }
    static func clearBackup() { defaults.removeObject(forKey: backupKey) }

    #if DEBUG
    /// Debug only: wipe Demora configuration in the App Group, returning the
    /// app to fresh setup. Retain only the named-shield cleanup manifest so the
    /// next refresh can retire settings from the old debug configuration.
    static func debugWipeAll() {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("latch.") && !key.hasPrefix("latch.scheduleCategoryStores.") {
            defaults.removeObject(forKey: key)
        }
    }
    #endif

    private static var blockedLimitsFileURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: LatchConstants.appGroupID)!
            .appendingPathComponent("blockedLimits.json")
    }

    /// Limit IDs whose daily threshold has been reached today (written by the
    /// monitor extension, read by ShieldController).
    static func loadBlockedLimitIDs() -> Set<UUID> {
        guard let raw = defaults.array(forKey: LatchConstants.blockedKey) as? [String] else { return [] }
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    static func saveBlockedLimitIDs(_ ids: Set<UUID>) {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: blockedLimitsFileURL, options: [], error: &error) { url in
            if let data = try? JSONEncoder().encode(ids.map(\.uuidString)) {
                do {
                    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    defaults.set(ids.map(\.uuidString), forKey: LatchConstants.blockedKey)
                } catch {
                    NSLog("Demora: Failed to write blocked limits: \(error)")
                }
            }
        }
        DemoraWidgetSnapshot.publish(state: loadState())
    }

    /// Safely load, modify, and save the blocked limit IDs with an atomic lock
    /// across the app and extension processes.
    /// WARNING: Do not call loadBlockedLimitIDs() or saveBlockedLimitIDs() inside
    /// the mutation closure, as nested coordination on the same file will deadlock.
    static func mutateBlockedLimitIDs(_ mutation: (inout Set<UUID>) -> Void) {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: blockedLimitsFileURL, options: [], error: &error) { url in
            var ids = Set<UUID>()
            if let data = try? Data(contentsOf: url),
               let raw = try? JSONDecoder().decode([String].self, from: data) {
                ids = Set(raw.compactMap(UUID.init(uuidString:)))
            } else if let raw = defaults.array(forKey: LatchConstants.blockedKey) as? [String] {
                ids = Set(raw.compactMap(UUID.init(uuidString:)))
            }

            mutation(&ids)

            if let data = try? JSONEncoder().encode(ids.map(\.uuidString)) {
                do {
                    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    defaults.set(ids.map(\.uuidString), forKey: LatchConstants.blockedKey)
                } catch {
                    NSLog("Demora: Failed to write mutated blocked limits: \(error)")
                }
            }
        }
        DemoraWidgetSnapshot.publish(state: loadState())
    }

    // MARK: - Limit threshold verification

    /// Latest genuine (non-free-window) threshold callback received for each
    /// limit. A manual recheck compares these timestamps with its start time so
    /// it never blindly clears every block: limits iOS freshly confirms remain
    /// blocked, while unconfirmed stale markers can be released.
    private static let thresholdCallbackTimesKey =
        "latch.limitThresholdCallbackTimes.v1"
    private static let lastLimitRecheckKey = "latch.lastLimitRecheck.v1"
    private static let confirmedRecheckControlKey =
        "latch.confirmedLimitRecheckControl.v1"

    static func recordLimitThresholdCallback(_ id: UUID, at date: Date = Date()) {
        var values = defaults.dictionary(forKey: thresholdCallbackTimesKey)
            as? [String: Double] ?? [:]
        values[id.uuidString] = date.timeIntervalSince1970
        defaults.set(values, forKey: thresholdCallbackTimesKey)
    }

    static func limitsConfirmedSince(_ date: Date,
                                     among ids: Set<UUID>) -> Set<UUID> {
        let values = defaults.dictionary(forKey: thresholdCallbackTimesKey)
            as? [String: Double] ?? [:]
        return Set(ids.filter {
            (values[$0.uuidString] ?? 0) >= date.timeIntervalSince1970
        })
    }

    static var lastLimitRecheckAt: Date? {
        get {
            let value = defaults.double(forKey: lastLimitRecheckKey)
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set {
            defaults.set(newValue?.timeIntervalSince1970 ?? 0,
                         forKey: lastLimitRecheckKey)
        }
    }

    static func clearLimitThresholdCallbacks() {
        defaults.removeObject(forKey: thresholdCallbackTimesKey)
    }

    static func recordLimitRecheckControl(_ id: UUID) {
        defaults.set(id.uuidString, forKey: confirmedRecheckControlKey)
    }

    static func wasLimitRecheckControlConfirmed(_ id: UUID) -> Bool {
        defaults.string(forKey: confirmedRecheckControlKey) == id.uuidString
    }

    // MARK: - Free-period credit (per limit, per day, in minutes)
    //
    // DeviceActivity never reports "minutes used", so while a free window is
    // active a dedicated one-shot activity fires silent per-limit checkpoint
    // events ("fw-<limitID>-<minutes>") at rising rungs. The highest rung a
    // limit reached is (a floor on) its real usage inside the window. At
    // window end that amount is credited to that limit's daily threshold —
    // so time spent in a free period never counts against the real limit,
    // and limits whose apps weren't touched get no windfall. Reset daily.

    private static let freeCreditKey = "latch.freeCreditByLimit.v1"
    private static let freeWindowUsageKey = "latch.freeWindowUsage.v1"
    private static let freeWindowStartKey = "latch.freeWindowStart.v1"
    private static let freeWindowTrackingEpochKey = "latch.freeWindowTrackingEpoch.v1"
    private static let freeWindowBlockedSnapshotKey = "latch.freeWindowBlockedSnapshot.v1"
    private static let freeWindowSuppressedLimitsKey = "latch.freeWindowSuppressedLimits.v1"

    private static func loadDict(_ key: String) -> [UUID: Int] {
        guard let raw = defaults.dictionary(forKey: key) as? [String: Int]
        else { return [:] }
        var out: [UUID: Int] = [:]
        for (k, v) in raw { if let id = UUID(uuidString: k) { out[id] = v } }
        return out
    }
    private static func saveDict(_ dict: [UUID: Int], _ key: String) {
        defaults.set(Dictionary(uniqueKeysWithValues:
            dict.map { ($0.key.uuidString, $0.value) }), forKey: key)
    }

    /// Minutes credited back to each limit today for usage inside ended
    /// free windows.
    static func loadFreeCreditByLimit() -> [UUID: Int] { loadDict(freeCreditKey) }
    static func saveFreeCreditByLimit(_ d: [UUID: Int]) { saveDict(d, freeCreditKey) }

    /// Highest checkpoint each limit reached inside the currently-active free
    /// window (written by the monitor extension as "fw-…" events fire).
    static func loadFreeWindowUsage() -> [UUID: Int] { loadDict(freeWindowUsageKey) }
    static func saveFreeWindowUsage(_ d: [UUID: Int]) { saveDict(d, freeWindowUsageKey) }

    /// When the currently-active free window began (nil if none active).
    static var freeWindowStart: Date? {
        get {
            let t = defaults.double(forKey: freeWindowStartKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: freeWindowStartKey) }
    }

    /// Distinguishes callbacks from the current free-window monitor from
    /// delayed callbacks after a limit's selection changed and tracking was
    /// rearmed with different app tokens.
    static var freeWindowTrackingEpoch: String? {
        get { defaults.string(forKey: freeWindowTrackingEpochKey) }
        set { defaults.set(newValue, forKey: freeWindowTrackingEpochKey) }
    }

    /// The limits that were genuinely blocked before the current free window.
    /// An optional distinguishes "the snapshot was empty" from older installs
    /// that began a free window before this bookkeeping existed.
    static var freeWindowBlockedSnapshot: Set<UUID>? {
        get {
            guard let raw = defaults.array(forKey: freeWindowBlockedSnapshotKey)
                    as? [String]
            else { return nil }
            return Set(raw.compactMap(UUID.init(uuidString:)))
        }
        set {
            if let newValue {
                defaults.set(newValue.map(\.uuidString),
                             forKey: freeWindowBlockedSnapshotKey)
            } else {
                defaults.removeObject(forKey: freeWindowBlockedSnapshotKey)
            }
        }
    }

    /// Daily-limit callbacks delivered while a free window was active. They
    /// must not block immediately because all usage in that window is exempt,
    /// but their events need rearming when the window closes.
    static func loadFreeWindowSuppressedLimitIDs() -> Set<UUID> {
        guard let raw = defaults.array(forKey: freeWindowSuppressedLimitsKey)
                as? [String]
        else { return [] }
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    static func recordFreeWindowSuppressedLimitID(_ id: UUID) {
        var ids = loadFreeWindowSuppressedLimitIDs()
        ids.insert(id)
        defaults.set(ids.map(\.uuidString), forKey: freeWindowSuppressedLimitsKey)
    }

    static func clearFreeWindowSuppressedLimitIDs() {
        defaults.removeObject(forKey: freeWindowSuppressedLimitsKey)
    }

    static func clearUsageTracking() {
        saveFreeCreditByLimit([:])
        saveFreeWindowUsage([:])
        freeWindowStart = nil
        freeWindowTrackingEpoch = nil
        freeWindowBlockedSnapshot = nil
        clearFreeWindowSuppressedLimitIDs()
        clearLimitThresholdCallbacks()
    }

    // MARK: - Daily reset bookkeeping
    //
    // Restarting the daily DeviceActivity (to apply reduced thresholds mid-day)
    // re-fires `intervalDidStart`. Without a date guard that callback wipes
    // today's blocks/usage as if it were a new day. We record the day we last
    // reset so a mid-day restart is told apart from a real midnight rollover.

    private static let lastResetDayKey = "latch.lastResetDay"

    static var lastResetDay: String {
        get { defaults.string(forKey: lastResetDayKey) ?? "" }
        set { defaults.set(newValue, forKey: lastResetDayKey) }
    }

    /// "yyyy-M-d" in the device's current calendar — the unit of a "day".
    static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
