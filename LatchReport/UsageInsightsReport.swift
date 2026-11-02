import DeviceActivity
import Foundation
import ManagedSettings
import SwiftUI

// Only the report view receives these tokens. The host sees neither tokens
// discovered from usage nor measured per-app durations.
struct UsageInsightsReportConfiguration {
    let usage: UsageInsightsConfiguration
    let applicationTokens: [Int: ApplicationToken]
}

// Match the existing iOS-16 report's nonisolated conformance pattern.
struct UsageInsightsReport: nonisolated DeviceActivityReportScene {
#if DEBUG
    let context: DeviceActivityReport.Context = .init("app.demora.dev.usage-insights")
#else
    let context: DeviceActivityReport.Context = .init("app.demora.production.usage-insights")
#endif
    let content: (UsageInsightsReportConfiguration) -> UsageInsightsView

    private struct Source: Hashable {
        let user: DeviceActivityData.User
        let device: DeviceActivityData.Device
    }
    private struct Snapshot {
        let source: Int
        let interval: DateInterval
        let seconds: TimeInterval
        let updatedAt: Date
        let applications: [Int: TimeInterval]
    }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> UsageInsightsReportConfiguration {
        // Opaque identities exist only while constructing this configuration.
        // Never inspect appleID, device names, bundle identifiers or websites.
        // Application tokens are used only for Apple's private activity labels.
        var sourceIDs: [Source: Int] = [:]
        var applicationIDs: [ApplicationToken: Int] = [:]
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
                var applications: [Int: TimeInterval] = [:]
                for await category in segment.categories {
                    for await activity in category.applications {
                        guard let token = activity.application.token else { continue }
                        let id: Int
                        if let existing = applicationIDs[token] { id = existing }
                        else { id = applicationIDs.count; applicationIDs[token] = id }
                        let seconds = activity.totalActivityDuration
                        if let previous = applications[id] {
                            // A token repeated in categories is not extra usage.
                            // Preserve invalid evidence for coverage validation.
                            applications[id] = previous.isFinite && seconds.isFinite && previous >= 0 && seconds >= 0
                                ? max(previous, seconds) : .nan
                        } else { applications[id] = seconds }
                    }
                }
                snapshots.append(Snapshot(source: source, interval: segment.dateInterval,
                    seconds: segment.totalActivityDuration, updatedAt: result.lastUpdatedDate,
                    applications: applications))
            }
        }
        // Results arrive asynchronously. A legitimate lastUpdatedDate can be
        // newer than the instant enumeration began; validate against its end.
        let now = Date()
        var accumulator = UsageInsightsAccumulator(now: now, calendar: .current)
        var appAccumulator = ApplicationUsageAccumulator(now: now, calendar: .current)
        for source in sourceIDs.values {
            accumulator.registerSource(source); appAccumulator.registerSource(source)
        }
        for snapshot in snapshots {
            accumulator.add(source: snapshot.source,
                start: snapshot.interval.start, end: snapshot.interval.end,
                seconds: snapshot.seconds, updatedAt: snapshot.updatedAt)
            appAccumulator.add(source: snapshot.source, start: snapshot.interval.start,
                end: snapshot.interval.end, updatedAt: snapshot.updatedAt,
                applications: snapshot.applications)
        }
        let baseline = UsageInsightsBaseline.decode(
            UserDefaults(suiteName: AppGroup.id)?.data(forKey: UsageInsightsBaseline.key),
            now: now)
        var usage = accumulator.configuration(baseline: baseline)
        usage.applications = appAccumulator.applications()
        return UsageInsightsReportConfiguration(usage: usage,
            applicationTokens: Dictionary(uniqueKeysWithValues: applicationIDs.map { ($0.value, $0.key) }))
    }
}
