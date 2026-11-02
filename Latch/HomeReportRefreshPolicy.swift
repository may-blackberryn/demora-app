import Foundation

/// Query scheduling metadata only, never usage or render-completion state.
/// Uptime keeps cooldowns stable through clock changes; queries use real Date.
struct HomeReportRefreshPolicy {
    static let coalescingDelay: TimeInterval = 0.35
    static let minimumSpacing: TimeInterval = 2
    static let retryDelay: TimeInterval = 3
    private(set) var lastQueryUptime: TimeInterval

    init(initialQueryUptime: TimeInterval) { lastQueryUptime = initialQueryUptime }

    func delay(at uptime: TimeInterval) -> TimeInterval {
        max(Self.coalescingDelay, lastQueryUptime + Self.minimumSpacing - uptime)
    }

    mutating func didQuery(at uptime: TimeInterval) { lastQueryUptime = uptime }
}
