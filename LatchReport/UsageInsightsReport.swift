import DeviceActivity
import Foundation
import SwiftUI

// Match the existing iOS-16 report's nonisolated conformance pattern.
struct UsageInsightsReport: nonisolated DeviceActivityReportScene {
#if DEBUG
    let context: DeviceActivityReport.Context = .init("app.demora.dev.usage-insights")
#else
    let context: DeviceActivityReport.Context = .init("app.demora.production.usage-insights")
#endif
    let content: (UsageInsightsConfiguration) -> UsageInsightsView

    private struct Source: Hashable {
        let user: DeviceActivityData.User
        let device: DeviceActivityData.Device
    }
    private struct Snapshot {
        let source: Int
        let interval: DateInterval
        let seconds: TimeInterval
        let updatedAt: Date
    }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> UsageInsightsConfiguration {
        // Opaque identities exist only while constructing this configuration.
        // Never inspect appleID, device names, application tokens or websites.
        var sourceIDs: [Source: Int] = [:]
        var snapshots: [Snapshot] = []
        for await result in data {
            // The host selects the current device's model family (iPhone/iPad),
            // not its physical identity. Preserve all returned same-kind sources.
            guard case .daily = result.segmentInterval else { continue }
            let identity = Source(user: result.user, device: result.device)
            let source: Int
            if let existing = sourceIDs[identity] {
                source = existing
            } else {
                source = sourceIDs.count
                sourceIDs[identity] = source
            }
            for await segment in result.activitySegments {
                snapshots.append(Snapshot(source: source, interval: segment.dateInterval,
                    seconds: segment.totalActivityDuration, updatedAt: result.lastUpdatedDate))
            }
        }
        // Results arrive asynchronously. A legitimate lastUpdatedDate can be
        // newer than the instant enumeration began; validate against its end.
        let now = Date()
        var accumulator = UsageInsightsAccumulator(now: now, calendar: .current)
        for source in sourceIDs.values { accumulator.registerSource(source) }
        for snapshot in snapshots {
            accumulator.add(source: snapshot.source,
                start: snapshot.interval.start, end: snapshot.interval.end,
                seconds: snapshot.seconds, updatedAt: snapshot.updatedAt)
        }
        let baseline = UsageInsightsBaseline.decode(
            UserDefaults(suiteName: AppGroup.id)?.data(forKey: UsageInsightsBaseline.key),
            now: now)
        return accumulator.configuration(baseline: baseline)
    }
}
