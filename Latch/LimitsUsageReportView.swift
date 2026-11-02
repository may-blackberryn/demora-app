//
//  LimitsUsageReportView.swift
//  Hosts the LatchReport extension, which reports accurate per-limit usage
//  for today. The Context string must match LimitsUsageReport.context in the
//  extension. Report usage never leaves the extension's sandbox.
//

import SwiftUI
import DeviceActivity
import FamilyControls
import ManagedSettings

struct LimitsUsageReportView: View {
    /// Change the filter in place rather than deliberately discarding the
    /// report view. iOS still controls remote rendering and data delivery.
    let refreshedAt: Date
    let limits: [AppLimit]

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
        let end = max(refreshedAt, dayStart.addingTimeInterval(0.001))
        // Ask only for the union of configured limit selections, not the
        // user's entire application history. These are user-selected tokens,
        // not measured data exported from the report.
        let applications = limits.reduce(into: Set<ApplicationToken>()) {
            $0.formUnion($1.selection.applicationTokens)
        }
        let categories = limits.reduce(into: Set<ActivityCategoryToken>()) {
            $0.formUnion($1.selection.categoryTokens)
        }
        let domains = limits.reduce(into: Set<WebDomainToken>()) {
            $0.formUnion($1.selection.webDomainTokens)
        }
        return DeviceActivityFilter(segment: .daily(during: DateInterval(start: dayStart, end: end)),
                                    users: .all, devices: .all,
                                    applications: applications, categories: categories, webDomains: domains)
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
    @State private var onScreen = false
    @State private var refreshRequest: UUID?
    @State private var refreshPolicy = HomeReportRefreshPolicy(initialQueryUptime: ProcessInfo.processInfo.systemUptime)
    @State private var queryLimits: [AppLimit]
    let limitCount: Int
    let reloadRequest: UUID?

    init(limits: [AppLimit], reloadRequest: UUID? = nil) {
        limitCount = limits.count
        self.reloadRequest = reloadRequest
        _queryLimits = State(initialValue: limits)
    }

    private var canRefresh: Bool {
        onScreen && scenePhase == .active && model.selectedTab == 0
            && model.authorized && !model.inTutorial
    }

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
                Button { requestRefresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(tr("Refresh"))
            }
            LimitsUsageReportView(refreshedAt: refreshedAt, limits: queryLimits)
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
        .onAppear { onScreen = true; requestRefresh() }
        .onDisappear { onScreen = false; refreshRequest = nil }
        .onChange(of: canRefresh) { available in
            if available { requestRefresh() }
            else { refreshRequest = nil }
        }
        .onChange(of: appearanceRaw) { _ in requestRefresh() }
        .onChange(of: accentColorRaw) { _ in requestRefresh() }
        .onChange(of: model.language) { _ in requestRefresh() }
        .onChange(of: model.state.limits) { _ in requestRefresh() }
        .onChange(of: reloadRequest) { _ in requestRefresh() }
        .task(id: refreshRequest) {
            guard refreshRequest != nil, canRefresh else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(refreshPolicy.delay(at: ProcessInfo.processInfo.systemUptime) * 1_000_000_000))
                guard !Task.isCancelled, canRefresh else { return }
                refreshReport()
                // One bounded soft retry after foreground/tab return or a
                // manual request. No readiness signal, endless polling or
                // report recreation; hiding Home cancels pending work.
                try await Task.sleep(nanoseconds: UInt64(HomeReportRefreshPolicy.retryDelay * 1_000_000_000))
                guard !Task.isCancelled, canRefresh else { return }
                refreshReport()
            } catch { /* Cancellation is expected on hide/new requests. */ }
        }
    }

    private func requestRefresh() {
        guard canRefresh else { return }
        refreshRequest = UUID()
    }

    private func refreshReport() {
        // Report windows follow the actual clock, including backward changes.
        // Do not restart monitoring or touch budgets/credits/shields here.
        queryLimits = model.state.limits
        refreshedAt = Date()
        refreshPolicy.didQuery(at: ProcessInfo.processInfo.systemUptime)
    }
}
