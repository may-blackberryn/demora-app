//
//  LatchReportExtension.swift
//  LatchReport — a DeviceActivityReport extension.
//
//  Screen Time exposes no live "minutes used" API to the app, but a report
//  extension CAN read real per-app usage. This reads the user's limits from
//  the App Group and reports actual minutes used today vs each budget.
//
//  Self-contained on purpose: it decodes a minimal view of the saved state, so
//  no shared source files need to be added to this target. It only needs the
//  Family Controls capability + the App Group (group.com.may.screentimedelay)
//  in Signing & Capabilities.
//

import DeviceActivity
import ExtensionKit
import FamilyControls
import ManagedSettings
import SwiftUI
import ExtensionKit

@main
struct LatchReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        LimitsUsageReport { rows in
            LimitsUsageView(rows: rows)
        }
    }
}

// MARK: - Minimal state mirror (decoded from the App Group)

enum AppGroup {
    /// Matches the app's App Group, including the dev split (a `.dev` bundle id
    /// uses the `.dev` group). Kept in sync with LatchConstants.appGroupID.
    static let id: String = {
        let base = "group.com.may.screentimedelay"
        let bid = Bundle.main.bundleIdentifier ?? ""
        let isDev = bid.hasSuffix(".dev") || bid.contains(".dev.")
        return isDev ? base + ".dev" : base
    }()
    static let stateKey = "latch.state.v1"
}

/// Mirrors the app's `AppLimit` fields we need; extra keys in the JSON are
/// ignored, and the whole `LatchState` is read but only `limits` is decoded.
private struct MiniLimit: Decodable {
    var id: UUID
    var name: String
    var selection: FamilyActivitySelection
    var minutesPerDay: Int
}
private struct MiniState: Decodable {
    var limits: [MiniLimit]
}

// MARK: - Report scene

struct LimitUsageRow: Identifiable {
    let id: UUID
    let name: String
    let usedMinutes: Int
    let budget: Int
}

// `nonisolated` conformance: the extension's `body` is built off the main
// actor, but `LimitsUsageView` (a SwiftUI View) would otherwise make this
// conformance main-actor-isolated. Forcing it nonisolated lets the system use
// it from `body` and clears the Swift 6 isolated-conformance diagnostic.
struct LimitsUsageReport: nonisolated DeviceActivityReportScene {
    // Must match the Context the app passes to DeviceActivityReport(_:filter:).
    let context: DeviceActivityReport.Context = .init("Limits Usage")
    let content: ([LimitUsageRow]) -> LimitsUsageView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> [LimitUsageRow] {
        var perApp: [ApplicationToken: TimeInterval] = [:]
        var perCat: [ActivityCategoryToken: TimeInterval] = [:]

        for await each in data {
            for await segment in each.activitySegments {
                for await category in segment.categories {
                    if let ctok = category.category.token {
                        perCat[ctok, default: 0] += category.totalActivityDuration
                    }
                    for await app in category.applications {
                        if let atok = app.application.token {
                            perApp[atok, default: 0] += app.totalActivityDuration
                        }
                    }
                }
            }
        }

        return loadLimits().map { limit in
            var used: TimeInterval = 0
            for t in limit.selection.applicationTokens { used += perApp[t] ?? 0 }
            for t in limit.selection.categoryTokens { used += perCat[t] ?? 0 }
            return LimitUsageRow(id: limit.id, name: limit.name,
                                 usedMinutes: Int(used / 60),
                                 budget: limit.minutesPerDay)
        }
    }

    private func loadLimits() -> [MiniLimit] {
        guard let defaults = UserDefaults(suiteName: AppGroup.id),
              let data = defaults.data(forKey: AppGroup.stateKey),
              let state = try? JSONDecoder().decode(MiniState.self, from: data)
        else { return [] }
        return state.limits
    }
}
