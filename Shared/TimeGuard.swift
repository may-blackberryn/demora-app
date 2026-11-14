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
//  migrate the old anchor.
//
//  Residual gaps (documented):
//  - Change the clock forward AND reboot AND stay offline: the anchor resets
//    to the forged wall clock until the next successful network sync.
//  - A reboot is missed if neither elapsed clock has fallen below its anchor
//    value by the first read after the reboot; the guarded clock then runs
//    behind (waits get longer, never shorter) until a network sync.
//  - The raw clock is not frequency-corrected (seconds per day). Within the
//    5-minute tolerance the wall clock wins; beyond it the app re-syncs.
//

import Foundation
import Darwin

enum TimeGuard {
    /// 2.0-and-earlier anchor: guarded wall time + systemUptime. Read only to
    /// migrate; never written again.
    private static let legacyAnchorWallKey = "latch.time.anchorWall"
    private static let legacyAnchorUptimeKey = "latch.time.anchorUptime"
    /// One record, so another process never reads a torn wall/clock pair.
    private static let anchorKey = "latch.time.anchor"
    private static let anchorVersion: Double = 2
    private static let lastSyncKey = "latch.time.lastSync"

    /// Tolerated disagreement between wall clock and elapsed-time-derived time
    /// (NTP nudges, raw clock drift) before the wall clock is considered
    /// manipulated.
    private static let tolerance: TimeInterval = 300

    /// Guarded time at a moment, with both elapsed clocks read at that moment.
    private struct Anchor {
        var wall: TimeInterval        // seconds since 1970, guarded
        var continuous: TimeInterval  // CLOCK_MONOTONIC_RAW, includes sleep
        var uptime: TimeInterval      // systemUptime, excludes sleep
    }

    /// Seconds since boot, including sleep. Resets on reboot.
    static func continuousTime() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }

    /// Best available estimate of the true current time.
    static func now() -> Date {
        let wall = Date()
        let continuous = continuousTime()
        let uptime = ProcessInfo.processInfo.systemUptime
        let stored = storedAnchor()
        if let stored, let guarded = derive(wall: wall, continuous: continuous,
                                             uptime: uptime, from: stored) {
            return guarded
        }
        // No usable anchor. Migrating from 2.0's anchor starts exactly where
        // the old clock reads now, so no deadline gets closer than it was;
        // from here on elapsed time includes sleep. A first run or a reboot
        // since the anchor falls back to the wall clock, and the next network
        // sync corrects any forgery.
        let start = (stored == nil ? legacyNow(wall: wall, uptime: uptime) : nil) ?? wall
        anchor(Anchor(wall: start.timeIntervalSince1970, continuous: continuous, uptime: uptime))
        return start
    }

    /// Display-only estimate: read the existing anchor without creating,
    /// migrating or refreshing it. Same answer `now()` gives for these inputs.
    static func nowForDisplay(at wall: Date = Date(),
                              continuous: TimeInterval = continuousTime(),
                              uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Date {
        if let stored = storedAnchor() {
            return derive(wall: wall, continuous: continuous, uptime: uptime, from: stored) ?? wall
        }
        return legacyNow(wall: wall, uptime: uptime) ?? wall
    }

    /// True when the wall clock and the guarded clock disagree by more than
    /// the tolerance (5 min): either the clock was changed or the guarded
    /// clock is behind (an anchor migrated from 2.0's sleep-blind clock, a
    /// missed reboot). Only a network sync can tell which.
    static func clocksDisagree(wall: Date = Date(), guarded: Date) -> Bool {
        abs(wall.timeIntervalSince(guarded)) > tolerance
    }

    /// nil when the anchor is unusable: invalid, or the device rebooted since
    /// (an elapsed clock restarted below its anchor value).
    private static func derive(wall: Date, continuous: TimeInterval, uptime: TimeInterval,
                               from anchor: Anchor) -> Date? {
        guard anchor.wall > 0, continuous >= anchor.continuous, uptime >= anchor.uptime
        else { return nil }
        let derived = Date(timeIntervalSince1970: anchor.wall + (continuous - anchor.continuous))
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

    private static func storedAnchor() -> Anchor? {
        guard let record = SharedStore.defaults.object(forKey: anchorKey) as? [String: Double],
              record["version"] == anchorVersion,
              let wall = record["wall"], let continuous = record["continuous"],
              let uptime = record["uptime"],
              wall.isFinite, continuous.isFinite, uptime.isFinite
        else { return nil }
        return Anchor(wall: wall, continuous: continuous, uptime: uptime)
    }

    private static func anchor(_ anchor: Anchor) {
        SharedStore.defaults.set(["version": anchorVersion, "wall": anchor.wall,
                                  "continuous": anchor.continuous, "uptime": anchor.uptime],
                                 forKey: anchorKey)
    }

    /// Re-anchor on a trusted network date, read with both elapsed clocks.
    private static func adopt(networkDate: Date) {
        anchor(Anchor(wall: networkDate.timeIntervalSince1970, continuous: continuousTime(),
                      uptime: ProcessInfo.processInfo.systemUptime))
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
    static func syncWithNetwork(force: Bool = false) async {
        let lastSync = SharedStore.defaults.double(forKey: lastSyncKey)
        guard shouldSync(force: force, wall: Date().timeIntervalSince1970,
                         lastSync: lastSync) else { return }

        var request = URLRequest(url: URL(string: "https://www.apple.com")!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              let header = http.value(forHTTPHeaderField: "Date")
        else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let networkDate = formatter.date(from: header) else { return }

        adopt(networkDate: networkDate)
    }
}
