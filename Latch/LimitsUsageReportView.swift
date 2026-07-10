//
//  LimitsUsageReportView.swift
//  Hosts the LatchReport extension, which reports accurate per-limit usage
//  for today. The Context string must match LimitsUsageReport.context in the
//  extension. If the extension target isn't set up yet this renders empty.
//

import SwiftUI
import DeviceActivity

struct LimitsUsageReportView: View {
    /// Bump this to refresh: a changed filter re-runs the extension's query
    /// in place, WITHOUT killing the extension process (tearing the view down
    /// and respawning it trips the system's report-extension launch throttle,
    /// which is what renders blank).
    let refreshedAt: Date

    private let context = DeviceActivityReport.Context("Limits Usage")

    private var filter: DeviceActivityFilter {
        // Start of day → now, so every refresh produces a genuinely different
        // filter (a fixed full-day interval would compare equal and be ignored).
        let dayStart = Calendar.current.startOfDay(for: refreshedAt)
        let end = max(refreshedAt, dayStart.addingTimeInterval(60))
        return DeviceActivityFilter(segment: .daily(during: DateInterval(start: dayStart, end: end)),
                                    users: .all, devices: .all)
    }

    var body: some View {
        DeviceActivityReport(context, filter: filter)
    }
}
