//
//  LimitsUsageReportView.swift
//  Hosts the LatchReport extension, which reports accurate per-limit usage
//  for today. The Context string must match LimitsUsageReport.context in the
//  extension. Report usage never leaves the extension's sandbox.
//

import SwiftUI
import DeviceActivity

struct LimitsUsageReportView: View {
    /// Bump this to refresh: a changed filter re-runs the extension's query
    /// in place, WITHOUT killing the extension process (tearing the view down
    /// and respawning it trips the system's report-extension launch throttle,
    /// which is what renders blank).
    let refreshedAt: Date

    // DeviceActivity report extensions can remain alive and cached after their
    // containing app leaves the foreground. Dev and production must therefore
    // use different contexts; sharing "Limits Usage" allowed iOS to reuse the
    // dev report while rendering the production Limits screen.
#if DEBUG
    private let context = DeviceActivityReport.Context(
        "app.demora.dev.limits-usage")
#else
    private let context = DeviceActivityReport.Context(
        "app.demora.production.limits-usage")
#endif

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// No supported render-completion signal is used here. A blank report is not
/// evidence of zero usage (or a failed query). Keep its default footprint bounded,
/// with scrolling in the extension and an explicit larger viewport if wanted.
/// Unlike the legacy HomeUsageCard, refresh never removes/recreates the report.
struct CompactHomeUsageReport: View {
    @AppAccent private var accent
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var compactHeight: CGFloat = 112
    @ScaledMetric(relativeTo: .body) private var expandedHeight: CGFloat = 340
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("latch.accentColor", store: SharedStore.defaults)
    private var accentColorRaw = "blue"
    @AppStorage("limits.usageNoteDismissed") private var usageNoteDismissed = false
    @State private var refreshedAt = Date()
    @State private var expanded = false
    let limitCount: Int

    /// Bounded for any row count: 30 limits or a missing extension cannot leave
    /// several screens of blank space. At accessibility sizes, scroll the rows.
    private var viewportHeight: CGFloat {
        expanded ? min(480, expandedHeight)
            : min(240, compactHeight * (limitCount == 1 ? 1 : 1.5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DemoraSectionTitle(title: tr("Today's usage"), symbol: "chart.bar.fill")
                Button { refreshReport() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(tr("Refresh"))
            }
            LimitsUsageReportView(refreshedAt: refreshedAt)
                .frame(height: viewportHeight, alignment: .topLeading)
                .clipped()
            HStack {
                Text("\(tr("Limits")) · \(limitCount)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Ink.faint)
                Spacer()
                Button {
                    expanded.toggle()
                } label: {
                    Label(tr(expanded ? "Collapse" : "Expand"),
                          systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityValue(tr(expanded ? "Expanded" : "Compact"))
            }
            if !usageNoteDismissed {
                DismissibleNote(
                    text: tr("Usage stays in the Screen Time report. Scroll to see more groups. If it looks empty, try Refresh; an empty report does not mean zero usage."),
                    onDismiss: { usageNoteDismissed = true })
            }
        }
        .demoraSurface()
        .onAppear { refreshReport() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { refreshReport() }
        }
        .onChange(of: appearanceRaw) { _ in refreshReport() }
        .onChange(of: accentColorRaw) { _ in refreshReport() }
        .onChange(of: model.state.limits) { _ in refreshReport() }
    }

    private func refreshReport() {
        // Even rapid manual retries change the filter; preserve view identity
        // so a valid report is not torn down or subjected to launch throttling.
        refreshedAt = max(Date(), refreshedAt.addingTimeInterval(0.001))
    }
}
