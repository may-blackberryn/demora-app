//
//  TimeGuard.swift
//  Tamper-resistant clock. Delay countdowns must not be skippable by
//  changing the system clock in Settings, so "now" is derived from the
//  device's uptime relative to a saved anchor whenever possible, and the
//  anchor is refreshed from network time when the app is online.
//
//  Residual gap (documented): change clock forward AND reboot AND stay
//  offline — the anchor resets to the forged wall clock until the next
//  successful network sync corrects it.
//

import Foundation

enum TimeGuard {
    private static let anchorWallKey = "latch.time.anchorWall"
    private static let anchorUptimeKey = "latch.time.anchorUptime"
    private static let lastSyncKey = "latch.time.lastSync"

    /// Tolerated disagreement between wall clock and uptime-derived time
    /// (NTP nudges, suspend drift) before the wall clock is considered
    /// manipulated.
    private static let tolerance: TimeInterval = 300

    /// Best available estimate of the true current time.
    static func now() -> Date {
        let wall = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        let defaults = SharedStore.defaults
        let anchorWall = defaults.double(forKey: anchorWallKey)
        let anchorUptime = defaults.double(forKey: anchorUptimeKey)

        guard anchorWall > 0, uptime >= anchorUptime else {
            // First run, or the device rebooted since the anchor was set
            // (uptime restarted) — fall back to the wall clock, re-anchor,
            // and let the next network sync correct any forgery.
            anchor(wall: wall, uptime: uptime)
            return wall
        }

        let derived = Date(timeIntervalSince1970:
            anchorWall + (uptime - anchorUptime))
        // Within tolerance the wall clock is authoritative (it tracks real
        // time through deep sleep better than uptime). Outside it, the
        // clock was changed — the uptime-derived time wins.
        return abs(wall.timeIntervalSince(derived)) > tolerance ? derived : wall
    }

    private static func anchor(wall: Date, uptime: TimeInterval) {
        SharedStore.defaults.set(wall.timeIntervalSince1970, forKey: anchorWallKey)
        SharedStore.defaults.set(uptime, forKey: anchorUptimeKey)
    }

    /// Re-anchor from a trusted network date (HTTP Date header). Called
    /// opportunistically from the app; rate-limited to once an hour.
    static func syncWithNetwork() async {
        let lastSync = SharedStore.defaults.double(forKey: lastSyncKey)
        let now = Date().timeIntervalSince1970
        // Re-sync hourly — but also immediately if the wall clock now reads
        // *before* the last sync, which means it was set backward (the exact
        // tampering this guards against). Otherwise a clock set back would sit
        // below the hourly threshold and never re-anchor.
        guard now - lastSync > 3600 || now < lastSync else { return }

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

        anchor(wall: networkDate, uptime: ProcessInfo.processInfo.systemUptime)
        SharedStore.defaults.set(networkDate.timeIntervalSince1970,
                                 forKey: lastSyncKey)
    }
}
