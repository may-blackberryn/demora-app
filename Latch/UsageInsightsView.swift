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
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("latch.accentColor", store: SharedStore.defaults) private var accentRaw = "blue"
    @State private var showingAbout = false
    @State private var aboutPath: [AboutRoute] = []
    @State private var refreshedAt = Date()
    @State private var refreshRequest: UUID?
    @State private var refreshPolicy = HomeReportRefreshPolicy(initialQueryUptime: ProcessInfo.processInfo.systemUptime)
    @State private var estimate: WeeklyUsageEstimate?
    @State private var estimateEnabled = false
    @State private var estimateMinutes = 21 * 60
    @State private var saveFailed = false
    @State private var onScreen = false

    private enum AboutRoute: Hashable { case startingPoint }

    // Until the four-tab switch Insights is pushed from Today (tab 0); the
    // switch replaces this with the Insights tab's identity (spec §5.1).
    private var canRefresh: Bool {
        onScreen && scenePhase == .active && model.selectedTab == 0
            && model.authorized && !model.inTutorial
    }

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
            header
            if model.authorized {
                Rectangle().fill(Ink.hairline).frame(height: 1)
                // Screen-bounded viewport, one scroll owned by the report.
                // No nested host scroller or report-size/readiness handshake:
                // the line behind it is covered once iOS draws the report's
                // opaque paper, and nothing is signalled back (I9).
                ZStack {
                    Text(tr("Loading your usage… If this stays empty, tap Refresh."))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DemoraSpace.xxl)
                        .accessibilityHidden(true)
                    DeviceActivityReport(context, filter: filter)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Today owns the permission banner; no prompt or Settings
                // redirect here (Apple 5.1.1(iv); I11).
                ScrollView {
                    EmptyStateView(title: tr("Insights needs Screen Time access."),
                                   systemImage: "hourglass",
                                   description: tr("You can turn it on from Today."),
                                   actionTitle: tr("Go to Today"),
                                   action: goToToday)
                        .padding(.horizontal, DemoraSpace.pageGutter)
                        .padding(.top, DemoraSpace.m)
                        .frame(maxWidth: DemoraSpace.maxContentWidth)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Ink.paper.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAbout) { aboutSheet }
        .onAppear { onScreen = true; estimate = WeeklyUsageEstimate.load(); requestRefresh() }
        .onDisappear { onScreen = false; refreshRequest = nil }
        .onChange(of: canRefresh) { visible in
            if visible { estimate = WeeklyUsageEstimate.load(); requestRefresh() }
            else { refreshRequest = nil }
        }
        .onChange(of: appearanceRaw) { _ in requestRefresh() }
        .onChange(of: accentRaw) { _ in requestRefresh() }
        .onChange(of: model.language) { _ in requestRefresh() }
        .task(id: refreshRequest) {
            guard refreshRequest != nil, canRefresh else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(refreshPolicy.delay(at: ProcessInfo.processInfo.systemUptime) * 1_000_000_000))
                guard !Task.isCancelled, canRefresh else { return }
                refresh()
                refreshPolicy.didQuery(at: ProcessInfo.processInfo.systemUptime)
                // One bounded soft retry, as on Today. No readiness signal,
                // polling loop or report recreation.
                try await Task.sleep(nanoseconds: UInt64(HomeReportRefreshPolicy.retryDelay * 1_000_000_000))
                guard !Task.isCancelled, canRefresh else { return }
                refresh()
                refreshPolicy.didQuery(at: ProcessInfo.processInfo.systemUptime)
            } catch { /* Cancellation is expected on hide/new requests. */ }
        }
    }

    // MARK: Header

    /// A fixed row, not a large navigation title: the scroll belongs to the
    /// report process, so a large title would never collapse (§5.1).
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DemoraSpace.xs) {
            Text(tr("Insights"))
                .demoraType(.pageTitle)
                .foregroundStyle(Ink.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DemoraSpace.xs)
            if model.authorized {
                headerButton("arrow.clockwise", label: tr("Refresh")) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    requestRefresh()
                }
            }
            headerButton("info.circle", label: tr("About this data")) {
                estimate = WeeklyUsageEstimate.load()
                aboutPath = []
                showingAbout = true
            }
        }
        .padding(.horizontal, DemoraSpace.pageGutter)
        .padding(.top, DemoraSpace.xs)
        .padding(.bottom, DemoraSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Ink.inkSoft)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func goToToday() {
        // Pushed from Today for now: going back lands on Today. After the
        // four-tab switch the tab change does the work.
        model.selectedTab = 0
        dismiss()
    }

    // MARK: About this data

    /// One host sheet with static explanations (I4). Measured numbers stay in
    /// the report (Trends → How complete this is); the estimate's value is
    /// shown once, in Trends, so the row here shows none (I5).
    private var aboutSheet: some View {
        NavigationStack(path: $aboutPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                    aboutSection(tr("What you see"), tr("Your Screen Time from the last 28 days plus today, as iOS reports it. Today is shown on its own and never counts in weekly comparisons."))
                    aboutSection(tr("Missing isn't zero"), tr("iOS sometimes reports late or only part of a day. Days without data are marked, never counted as zero. If Insights looks empty, tap Refresh."))
                    aboutSection(tr("Apps and totals"), tr("App times overlap, so they won't add up to your total screen time."))
                    aboutSection(tr("Other devices"), tr("If Screen Time is shared over iCloud, other devices of the same kind may be included."))
                    aboutSection(tr("Private by design"), tr("Your usage stays inside Apple's Screen Time report. Demora can't read, save or send it."))
                    startingPointRow
                }
                .padding(DemoraSpace.xl)
                .frame(maxWidth: DemoraSpace.maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.cardRaised.ignoresSafeArea())
            .casedNavigationTitle(tr("About this data"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { showingAbout = false }
                }
            }
            .navigationDestination(for: AboutRoute.self) { _ in estimateEditor }
        }
        .presentationDetents([.medium, .large])
    }

    private func aboutSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            SectionHeader(title)
            Text(body)
                .demoraType(.body)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var startingPointRow: some View {
        Button {
            estimateEnabled = estimate != nil
            estimateMinutes = estimate?.weeklyMinutes ?? 21 * 60
            saveFailed = false
            aboutPath.append(.startingPoint)
        } label: {
            HStack(spacing: DemoraSpace.s) {
                Text(tr("Your starting point"))
                    .demoraType(.cardTitle)
                    .foregroundStyle(Ink.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(estimate == nil ? tr("Add") : tr("Edit"))
                    .demoraType(.meta)
                    .foregroundStyle(accent)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(Ink.hairline).frame(height: 1) }
    }

    /// The existing estimate editor, pushed inside the sheet. Save, verify,
    /// remove and "Couldn't save" behave as before.
    private var estimateEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WeeklyUsageEstimateDraft(enabled: $estimateEnabled, minutes: $estimateMinutes)
                if saveFailed { Text(tr("Couldn't save your estimate. Try again.")).foregroundStyle(Ink.danger) }
            }.padding(24)
        }
        .background(Ink.cardRaised.ignoresSafeArea())
        .casedNavigationTitle(tr("Your starting point"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("Cancel")) { aboutPath = [] } }
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("Save")) {
                    if estimateEnabled {
                        guard WeeklyUsageEstimate.save(minutes: estimateMinutes) else { saveFailed = true; return }
                    } else { WeeklyUsageEstimate.remove() }
                    estimate = WeeklyUsageEstimate.load()
                    aboutPath = []
                    requestRefresh()
                }
            }
        }
    }

    // MARK: Refresh

    /// Coalesced like Today's report: one request at a time, at least two
    /// seconds apart, one soft retry (HomeReportRefreshPolicy).
    private func requestRefresh() {
        guard canRefresh else { return }
        refreshRequest = UUID()
    }

    // Reporting uses actual calendar time, not enforcement's protected clock.
    // A backwards correction must move the query window backwards too.
    private func refresh() {
        guard canRefresh else { return }
        refreshedAt = Date()
    }
}
