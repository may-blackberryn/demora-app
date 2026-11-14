//
//  TimeGuard.swift
//  Tamper-resistant clock. Delay countdowns must not be skippable by
//  changing the system clock in Settings, so "now" is derived from elapsed
//  device time relative to a saved anchor whenever possible, and the anchor
//  is refreshed from network time when the app is online.
//
//  Clock domain (F1, docs/fixes-2.0-batch.md): elapsed time is
//  CLOCK_MONOTONIC_RAW (mach_continuous_time). It keeps counting while the
//  iPhone sleeps, restarts at boot and cannot be set by the user.
//  - Not ProcessInfo.systemUptime (mach_absolute_time): it stops while the
//    phone sleeps, so locked time never counted and waits landed late by the
//    time spent asleep (2.0 and earlier).
//  - Not CLOCK_MONOTONIC: on Darwin it is gettimeofday() minus kern.boottime,
//    i.e. derived from the very wall clock this type guards.
//  systemUptime is still stored as a second reboot signal and read once to
//  migrate the old anchor. kern.bootsessionuuid, when the OS lets us read it,
//  names the boot outright.
//
//  Residual gaps (documented):
//  - Change the clock forward AND reboot AND stay offline: the anchor resets
//    to the forged wall clock until the next successful network sync.
//  - Without a readable boot identity, a reboot is missed if neither elapsed
//    clock has fallen below its anchor value by the first read after it. The
//    guarded clock then runs behind until a network sync; new loosening waits
//    start at the later clock (`looseningStart`), so they still never end
//    early when the sync corrects it.
//  - The raw clock is not frequency-corrected (seconds per day; ≈9 s over
//    36 h measured on a Mac). Within the 5-minute tolerance the wall clock
//    wins. After roughly 50+ days with no network sync it can pass the
//    tolerance; if the raw clock runs fast, the derived time then runs ahead
//    of real time and a wait can end early by that drift (minutes). The app
//    syncs hourly whenever it is opened online, so this needs weeks offline
//    without opening it.
//

import Foundation
import Darwin

enum TimeGuard {
    /// 2.0-and-earlier anchor: guarded wall time + systemUptime. Read only for
    /// the very first migration; never written again.
    private static let legacyAnchorWallKey = "latch.time.anchorWall"
    private static let legacyAnchorUptimeKey = "latch.time.anchorUptime"
    /// Set once the v2 anchor exists, so the 2.0 keys are never read again.
    private static let migratedKey = "latch.time.anchor.migrated"
    /// One record, so another process never reads a torn wall/clock pair.
    private static let anchorKey = "latch.time.anchor"
    private static let anchorVersion: Double = 2
    private static let lastSyncKey = "latch.time.lastSync"

    /// Tolerated disagreement between wall clock and elapsed-time-derived time
    /// (NTP nudges, raw clock drift) before the wall clock is considered
    /// manipulated. Also the "clocks disagree" threshold (5 min).
    static let tolerance: TimeInterval = 300

    /// Apparent backwards elapsed time still read as "same boot": another
    /// thread or process can anchor between our clock sample and our read.
    private static let raceSlack: TimeInterval = 1

    /// Guarded time at a moment, with both elapsed clocks read at that moment.
    private struct Anchor {
        var wall: TimeInterval        // seconds since 1970, guarded
        var continuous: TimeInterval  // CLOCK_MONOTONIC_RAW, includes sleep
        var uptime: TimeInterval      // systemUptime, excludes sleep
        var boot: String? = nil       // kern.bootsessionuuid, when readable
    }

    /// Seconds since boot, including sleep. Resets on reboot.
    static func continuousTime() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }

    /// This boot's identity, or nil when the OS doesn't let us read it (then
    /// reboot detection falls back to the elapsed clocks). Never traps.
    static func bootSession() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0,
              (2...128).contains(size) else { return nil }
        var buffer = [CChar](repeating: 0, count: size + 1)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0,
              size < buffer.count else { return nil }
        buffer[size] = 0
        let value = String(cString: buffer)
        return UUID(uuidString: value) == nil ? nil : value
    }

    /// Best available estimate of the true current time.
    static func now() -> Date {
        // Read the anchor before sampling the clocks, so an anchor written in
        // between by another thread/process is never newer than our sample.
        let raw = SharedStore.defaults.object(forKey: anchorKey)
        let migrated = SharedStore.defaults.object(forKey: migratedKey) != nil
        let boot = bootSession()
        let wall = Date()
        let continuous = continuousTime()
        let uptime = ProcessInfo.processInfo.systemUptime
        if let stored = decode(raw), let guarded = derive(wall: wall, continuous: continuous,
                                                        uptime: uptime, boot: boot, from: stored) {
            return guarded
        }
        // No usable anchor. The first migration from 2.0's anchor starts
        // exactly where the old clock reads now, so no deadline gets closer
        // than it was; from here on elapsed time includes sleep. A first run,
        // a reboot since the anchor, or an unreadable record falls back to
        // the wall clock (never to months-old 2.0 keys), and the next network
        // sync corrects any forgery.
        let firstMigration = raw == nil && !migrated
        let start = (firstMigration ? legacyNow(wall: wall, uptime: uptime) : nil) ?? wall
        anchor(Anchor(wall: start.timeIntervalSince1970, continuous: continuous,
                      uptime: uptime, boot: boot))
        if !migrated { SharedStore.defaults.set(true, forKey: migratedKey) }
        return start
    }

    /// Display-only estimate: read the existing anchor without creating,
    /// migrating or refreshing it. Same answer `now()` gives for these inputs.
    static func nowForDisplay(at wall: Date = Date(),
                              continuous: TimeInterval = continuousTime(),
                              uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
                              boot: String? = bootSession()) -> Date {
        let raw = SharedStore.defaults.object(forKey: anchorKey)
        if raw != nil {
            return decode(raw).flatMap {
                derive(wall: wall, continuous: continuous, uptime: uptime, boot: boot, from: $0)
            } ?? wall
        }
        guard SharedStore.defaults.object(forKey: migratedKey) == nil else { return wall }
        return legacyNow(wall: wall, uptime: uptime) ?? wall
    }

    /// True when the wall clock and the guarded clock disagree by more than
    /// the tolerance (5 min): either the clock was changed or the guarded
    /// clock is behind (an anchor migrated from 2.0's sleep-blind clock, a
    /// missed reboot). Only a network sync can tell which.
    static func clocksDisagree(wall: Date = Date(), guarded: Date) -> Bool {
        abs(wall.timeIntervalSince(guarded)) > tolerance
    }

    /// Start of a new loosening wait: the later of the guarded and wall
    /// clocks. If the guarded clock is behind real time, a wait based on it
    /// would end early once a sync corrects it; the later clock can only
    /// lengthen the wait (a clock set forward only delays the user's own
    /// loosening). Stricter changes keep `now()`, so setting the clock forward
    /// can't postpone tightening.
    static func looseningStart(guarded: Date = TimeGuard.now(), wall: Date = Date()) -> Date {
        max(guarded, wall)
    }

    /// nil when the anchor is unusable: invalid, or the device rebooted since
    /// (another boot identity, or an elapsed clock restarted below its anchor
    /// value when no identity can be compared).
    private static func derive(wall: Date, continuous: TimeInterval, uptime: TimeInterval,
                               boot: String?, from anchor: Anchor) -> Date? {
        guard anchor.wall > 0 else { return nil }
        if let boot, let anchored = anchor.boot {
            guard boot == anchored else { return nil }
            // Same boot for certain: elapsed time can't really be negative.
        } else {
            guard continuous >= anchor.continuous - raceSlack,
                  uptime >= anchor.uptime - raceSlack else { return nil }
        }
        let elapsed = max(0, continuous - anchor.continuous)
        let derived = Date(timeIntervalSince1970: anchor.wall + elapsed)
        // Within tolerance the wall clock is authoritative. Outside it, the
        // clock was changed (or this anchor is behind): the derived time wins,
        // so a clock change never shortens a wait.
        return clocksDisagree(wall: wall, guarded: derived) ? derived : wall
    }

    /// 2.0's guarded time from its own anchor, unchanged, or nil when absent
    /// or rebooted since.
    private static func legacyNow(wall: Date, uptime: TimeInterval) -> Date? {
        let defaults = SharedStore.defaults
        let anchorWall = defaults.double(forKey: legacyAnchorWallKey)
        let anchorUptime = defaults.double(forKey: legacyAnchorUptimeKey)
        guard anchorWall > 0, uptime >= anchorUptime else { return nil }
        let derived = Date(timeIntervalSince1970: anchorWall + (uptime - anchorUptime))
        return abs(wall.timeIntervalSince(derived)) > tolerance ? derived : wall
    }

    private static func decode(_ raw: Any?) -> Anchor? {
        func number(_ value: Any?) -> Double? {
            guard let value = (value as? NSNumber)?.doubleValue, value.isFinite else { return nil }
            return value
        }
        guard let record = raw as? [String: Any],
              number(record["version"]) == anchorVersion,
              let wall = number(record["wall"]), let continuous = number(record["continuous"]),
              let uptime = number(record["uptime"])
        else { return nil }
        let boot = record["boot"] as? String
        guard record["boot"] == nil || boot != nil else { return nil }
        return Anchor(wall: wall, continuous: continuous, uptime: uptime, boot: boot)
    }

    private static func anchor(_ anchor: Anchor) {
        var record: [String: Any] = ["version": anchorVersion, "wall": anchor.wall,
                                     "continuous": anchor.continuous, "uptime": anchor.uptime]
        if let boot = anchor.boot { record["boot"] = boot }
        SharedStore.defaults.set(record, forKey: anchorKey)
    }

    /// Re-anchor on a trusted network date, read with both elapsed clocks.
    private static func adopt(networkDate: Date) {
        anchor(Anchor(wall: networkDate.timeIntervalSince1970, continuous: continuousTime(),
                      uptime: ProcessInfo.processInfo.systemUptime, boot: bootSession()))
        if SharedStore.defaults.object(forKey: migratedKey) == nil {
            SharedStore.defaults.set(true, forKey: migratedKey)
        }
        SharedStore.defaults.set(networkDate.timeIntervalSince1970, forKey: lastSyncKey)
    }

    /// Hourly — but also immediately if the wall clock now reads *before* the
    /// last sync (it was set backward, the exact tampering this guards
    /// against), or when the caller forces it because the clocks disagree.
    private static func shouldSync(force: Bool, wall: TimeInterval, lastSync: TimeInterval) -> Bool {
        force || wall - lastSync > 3600 || wall < lastSync
    }
}

extension TimeGuard {
    /// Re-anchor from a trusted network date (HTTP Date header). Called
    /// opportunistically from the app; rate-limited to once an hour unless
    /// `force` (the caller saw the clocks disagree, `clocksDisagree`).
    /// Returns true when the anchor was replaced.
    @discardableResult
    static func syncWithNetwork(force: Bool = false) async -> Bool {
        let lastSync = SharedStore.defaults.double(forKey: lastSyncKey)
        guard shouldSync(force: force, wall: Date().timeIntervalSince1970,
                         lastSync: lastSync) else { return false }

        var request = URLRequest(url: URL(string: "https://www.apple.com")!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              let header = http.value(forHTTPHeaderField: "Date")
        else { return false }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let networkDate = formatter.date(from: header) else { return false }

        adopt(networkDate: networkDate)
        return true
    }
}

/// When the app may force a time sync outside the hourly limit (F1). Pure and
/// process-local; times are uptime seconds, offsets are wall − guarded.
/// - Only while the clocks disagree by more than the tolerance.
/// - At most once a minute; failures (offline) back off to 15 minutes.
/// - After a sync that worked but left them disagreeing (the wall clock itself
///   is wrong), not again until that offset moves by more than a minute.
struct ForcedTimeSyncPolicy {
    private(set) var nextAttempt: TimeInterval = -.infinity
    private(set) var failures = 0
    private(set) var settledOffset: TimeInterval?

    /// Claims an attempt (so a second tick can't start another) when allowed.
    mutating func begin(offset: TimeInterval, uptime: TimeInterval) -> Bool {
        guard abs(offset) > TimeGuard.tolerance, uptime >= nextAttempt else { return false }
        if let settled = settledOffset, abs(offset - settled) <= 60 { return false }
        nextAttempt = uptime + 60
        return true
    }

    mutating func finish(succeeded: Bool, offsetAfter: TimeInterval, uptime: TimeInterval) {
        if succeeded {
            failures = 0
            nextAttempt = uptime + 60
            settledOffset = abs(offsetAfter) > TimeGuard.tolerance ? offsetAfter : nil
        } else {
            failures += 1
            nextAttempt = uptime + min(900, 60 * pow(2, Double(min(failures, 5) - 1)))
        }
    }
}
