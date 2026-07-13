//
//  SharedStore.swift
//  Persistence via App Group UserDefaults so the app and both
//  extensions read/write the same state.
//

import Foundation

struct SharedStore {
    static let defaults = UserDefaults(suiteName: LatchConstants.appGroupID)!

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
            return try JSONDecoder().decode(LatchState.self, from: data)
        } catch {
            // Don't silently wipe a user's setup: log, and stash the unreadable
            // bytes so they're recoverable rather than overwritten by the blank
            // state we're forced to return.
            NSLog("Demora: state decode failed (%@). Preserved raw blob.",
                  String(describing: error))
            defaults.set(data, forKey: LatchConstants.stateKey + ".corrupt")
            return LatchState()
        }
    }

    static func save(_ state: LatchState) {
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: LatchConstants.stateKey)
        } catch {
            NSLog("Demora: state encode failed (%@). Kept previous state.",
                  String(describing: error))
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
    /// Debug only: wipe every Demora key in the App Group, returning the app to
    /// a fresh-install state (so we don't have to delete and reinstall to test
    /// onboarding).
    static func debugWipeAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("latch.") {
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

    static func clearUsageTracking() {
        saveFreeCreditByLimit([:])
        saveFreeWindowUsage([:])
        freeWindowStart = nil
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
