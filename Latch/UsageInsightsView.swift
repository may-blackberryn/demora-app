import SwiftUI
import DeviceActivity
import UIKit

/// A user-written estimate, not measured Screen Time. Only the host writes it;
/// the report may read it. Actual usage must never travel in the other direction.
struct WeeklyUsageEstimate: Codable, Equatable {
    let weeklyMinutes: Int
    let recordedAt: Date
    static let key = "latch.usageBaseline.v1"
    var isValid: Bool {
        (0...10080).contains(weeklyMinutes) && recordedAt.timeIntervalSince1970.isFinite
            && recordedAt.timeIntervalSince1970 > 0
    }
    static func load() -> WeeklyUsageEstimate? {
        guard let data = SharedStore.defaults.data(forKey: key), data.count <= 1_024,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return nil }
        return value
    }
    @discardableResult
    static func save(minutes: Int, at date: Date = Date()) -> Bool {
        let value = Self(weeklyMinutes: minutes, recordedAt: date)
        guard value.isValid, let data = try? JSONEncoder().encode(value) else { return false }
        SharedStore.defaults.set(data, forKey: key)
        return SharedStore.defaults.data(forKey: key) == data
    }
    static func remove() { SharedStore.defaults.removeObject(forKey: key) }
}

struct WeeklyUsageEstimateDraft: View {
    @Binding var enabled: Bool
    @Binding var minutes: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DemoraSectionTitle(title: tr("Your starting point"), symbol: "chart.line.uptrend.xyaxis")
            Text(tr("About how much time do you spend on your phone each week?"))
                .font(.subheadline)
            Toggle(tr("Add an optional weekly estimate"), isOn: $enabled)
            if enabled {
                DurationPicker(minutes: $minutes, maxHours: 168, minMinutes: 0)
                Text(tr("Hours and minutes per week, not per day."))
                    .font(.caption).foregroundStyle(Ink.faint)
            }
            Text(tr("This is your estimate, not a measurement or a limit. It stays on your device. You can skip it or change it later in Home → Usage & trends."))
                .font(.footnote).foregroundStyle(Ink.faint)
        }
    }
}

struct UsageInsightsView: View {
    @AppAccent private var accent
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("latch.accentColor", store: SharedStore.defaults) private var accentRaw = "blue"
    @State private var showingUsageInfo = false
    @State private var refreshedAt = Date()
    @State private var estimate: WeeklyUsageEstimate?
    @State private var editingEstimate = false
    @State private var estimateEnabled = false
    @State private var estimateMinutes = 21 * 60
    @State private var saveFailed = false

#if DEBUG
    private let context = DeviceActivityReport.Context("app.demora.dev.usage-insights")
#else
    private let context = DeviceActivityReport.Context("app.demora.production.usage-insights")
#endif

    private var filter: DeviceActivityFilter {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: refreshedAt)
        // Four complete seven-day periods plus today's separate partial day.
        let start = calendar.date(byAdding: .day, value: -28, to: today) ?? today
        // Phone/tablet model, not a promise to identify a single physical device.
        let devices: DeviceActivityFilter.Devices = .init([
            UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        ])
        return .init(segment: .daily(during: DateInterval(start: start, end: max(refreshedAt, today.addingTimeInterval(1)))),
                     users: .all, devices: devices)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !model.authorized {
                ScrollView {
                    VStack(spacing: 24) {
                        Text(tr("Daily and weekly Screen Time, using the history iOS makes available. Complete weeks are compared; today's partial day is kept separate."))
                            .font(.subheadline).foregroundStyle(Ink.faint)
                        ScreenTimeReauthBanner()
                    }.padding(24)
                }
            } else {
                // Screen-bounded viewport, one scroll owned by the report.
                // No nested host scroller or report-size/readiness handshake.
                DeviceActivityReport(context, filter: filter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            }
            Button {
                estimateEnabled = estimate != nil
                estimateMinutes = estimate?.weeklyMinutes ?? 21 * 60
                saveFailed = false
                editingEstimate = true
            } label: {
                Label(tr("Edit weekly estimate"), systemImage: "flag")
                    .font(.caption.weight(.medium)).foregroundStyle(accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 16)
                    .background(accent.opacity(0.07), in: Capsule())
            }.buttonStyle(.plain).padding(.horizontal, 22).padding(.vertical, 10)
        }
        .paper().casedNavigationTitle(tr("Usage & trends"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingUsageInfo = true } label: {
                    Image(systemName: "info.circle").frame(width: 44, height: 44)
                }.accessibilityLabel(tr("Usage details"))
                Button { refresh() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }.accessibilityLabel(tr("Refresh"))
            }
        }
        .sheet(isPresented: $showingUsageInfo) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(tr("Daily and weekly Screen Time, using the history iOS makes available. Complete weeks are compared; today's partial day is kept separate."))
                        Text(tr("If the report looks empty, try Refresh. Missing data does not mean zero use. iCloud Screen Time sharing may include other devices of the same kind."))
                            .foregroundStyle(Ink.faint)
                        DemoraSectionTitle(title: tr("Your starting point"), symbol: "flag")
                        if let estimate {
                            Text(String(format: tr("Your estimate: %d hours %d minutes per week"), estimate.weeklyMinutes / 60, estimate.weeklyMinutes % 60))
                            Text(estimate.recordedAt, style: .date).font(.caption)
                        } else {
                            Text(tr("No weekly estimate added. Your report works without one."))
                        }
                    }.padding(24)
                }.paper().casedNavigationTitle(tr("Usage details"))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Done")) { showingUsageInfo = false } } }
            }
        }
        .onAppear { estimate = WeeklyUsageEstimate.load(); refresh() }
        .onChange(of: scenePhase) { if $0 == .active { estimate = WeeklyUsageEstimate.load(); refresh() } }
        .onChange(of: appearanceRaw) { _ in refresh() }
        .onChange(of: accentRaw) { _ in refresh() }
        .onChange(of: model.language) { _ in refresh() }
        .sheet(isPresented: $editingEstimate) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        WeeklyUsageEstimateDraft(enabled: $estimateEnabled, minutes: $estimateMinutes)
                        if saveFailed { Text(tr("Couldn't save your estimate. Try again.")).foregroundStyle(Ink.danger) }
                    }.padding(24)
                }
                .paper().casedNavigationTitle(tr("Your starting point"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(tr("Cancel")) { editingEstimate = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Save")) {
                            if estimateEnabled {
                                guard WeeklyUsageEstimate.save(minutes: estimateMinutes) else { saveFailed = true; return }
                            } else { WeeklyUsageEstimate.remove() }
                            estimate = WeeklyUsageEstimate.load()
                            editingEstimate = false
                            refresh()
                        }
                    }
                }
            }
        }
    }
    // Reporting uses actual calendar time, not enforcement's protected clock.
    // A backwards correction must move the query window backwards too.
    private func refresh() { refreshedAt = Date() }
}
