#!/usr/bin/env python3
"""Actual scheduling/filter projections and native synthetic Home lifetime checks.

No live Screen Time query, saved app state, blocking change, or report data export.
The macOS SwiftUI fixture proves hierarchy retention, not iOS remote rendering.
"""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
host = (ROOT / 'Latch/LimitsUsageReportView.swift').read_text()
home = (ROOT / 'Latch/HomeView.swift').read_text()
root = (ROOT / 'Latch/LatchApp.swift').read_text()
insights = (ROOT / 'Latch/UsageInsightsView.swift').read_text()
policy = ROOT / 'Latch/HomeReportRefreshPolicy.swift'
filter_body = host.split('    private var filter: DeviceActivityFilter {', 1)[1].split('    var body:', 1)[0]
driver = r'''
import Foundation
typealias ApplicationToken = Int
typealias ActivityCategoryToken = Int
typealias WebDomainToken = Int
struct Selection {
    var applicationTokens: Set<Int> = []
    var categoryTokens: Set<Int> = []
    var webDomainTokens: Set<Int> = []
}
struct AppLimit { var selection: Selection }
struct DeviceActivityFilter {
    enum Segment { case daily(during: DateInterval) }
    enum Users { case all }
    enum Devices { case all }
    let segment: Segment
    let users: Users
    let devices: Devices
    let applications: Set<Int>
    let categories: Set<Int>
    let webDomains: Set<Int>
}
struct Query {
    let refreshedAt: Date
    let limits: [AppLimit]
    var filter: DeviceActivityFilter {
'''+filter_body+r'''
}
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ reason: String) {
    precondition(value(), reason); checks += 1
}
var scheduler = HomeReportRefreshPolicy(initialQueryUptime: 100)
check(scheduler.delay(at: 100) == 2, "cold query gets time to settle")
check(scheduler.delay(at: 100.5) == 1.5, "coalesced requests preserve spacing")
check(scheduler.delay(at: 103) == 0.35, "settled foreground/manual request debounced")
check(HomeReportRefreshPolicy.retryDelay == 3, "one delayed retry spacing")
scheduler.didQuery(at: 104)
check(scheduler.lastQueryUptime == 104 && scheduler.delay(at: 104.5) == 1.5, "new query updates cooldown")
for uptime in [104.0, 104.1, 104.9, 105.9, 106.0, 110.0] {
    let delay = scheduler.delay(at: uptime)
    check(delay >= 0.35 && uptime + delay >= 106, "rapid manual requests bounded")
}
scheduler.didQuery(at: 107)
check(scheduler.delay(at: 109) == 0.35, "bounded retry does not create future cooldown drift")
let now = Date()
let start = Calendar.current.startOfDay(for: now)
let limits = [AppLimit(selection: Selection(applicationTokens: [1, 2], categoryTokens: [10], webDomainTokens: [100])),
              AppLimit(selection: Selection(applicationTokens: [2, 3], categoryTokens: [10, 11], webDomainTokens: [100, 101]))]
let query = Query(refreshedAt: now, limits: limits).filter
check(query.applications == [1, 2, 3], "selected apps union, no duplicate tokens")
check(query.categories == [10, 11], "category limits preserved")
check(query.webDomains == [100, 101], "website selections preserved")
if case let .daily(interval) = query.segment {
    check(interval.start == start && interval.end == max(now, start.addingTimeInterval(0.001)), "today's real clock window")
}
let first = Query(refreshedAt: start.addingTimeInterval(1), limits: limits).filter
let second = Query(refreshedAt: start.addingTimeInterval(2), limits: limits).filter
if case let .daily(a) = first.segment, case let .daily(b) = second.segment {
    check(a.end < b.end, "refresh not frozen for first minute after midnight")
}
if case let .daily(interval) = Query(refreshedAt: start, limits: limits).filter.segment {
    check(interval.duration > 0 && interval.duration < 1, "midnight interval valid, no future minute")
}
let backward = Query(refreshedAt: now.addingTimeInterval(-300), limits: limits).filter
if case let .daily(interval) = backward.segment {
    check(interval.end < now, "wall-clock correction never clamped to stale future query")
}
let websiteOnly = Query(refreshedAt: now, limits: [AppLimit(selection: Selection(webDomainTokens: [77]))]).filter
check(websiteOnly.applications.isEmpty && websiteOnly.categories.isEmpty && websiteOnly.webDomains == [77], "site-only rule scoped")
print("Home report schedule/filter checks passed: \(checks)")
'''

main_view = root.split('    private var mainTabView: some View {', 1)[1].split('    private var homeSelected:', 1)[0]
home_selection = root.split('    private var homeSelected: Bool {', 1)[1].split('\n', 1)[0]
tabs = root.split('    @ViewBuilder private var currentTab: some View {', 1)[1].split('    /// The single screen', 1)[0]
lifetime_driver = r'''
import AppKit
import SwiftUI
@MainActor final class Model: ObservableObject {
    @Published var selectedTab = 0
    @Published var inTutorial = false
    let state = StateStub()
    let incomingInviteCount = 0
}
struct StateStub { let pending: [Int] = [] }
enum Ink { static let paper = Color.white }
struct DemoraTabBar: View {
    @Binding var selection: Int
    let locked: Bool
    let pendingCount: Int
    let inviteCount: Int
    var body: some View { Text("tabs").frame(height: 56) }
}
@MainActor final class Lifetime: ObservableObject {
    static var created = 0
    let number: Int
    init() { Self.created += 1; number = Self.created }
}
struct HomeView: View {
    @StateObject var lifetime = Lifetime()
    var body: some View { Text("home \(lifetime.number)") }
}
struct LimitsView: View { var body: some View { Text("limits") } }
struct RulesView: View { var body: some View { Text("rules") } }
struct SchedulesView: View { var body: some View { Text("schedules") } }
struct SettingsView: View { var body: some View { Text("settings") } }
struct DelaysOverridesTabView: View { var body: some View { Text("delays") } }
struct RetainedRoot: View {
    @EnvironmentObject var model: Model
    var body: some View { mainTabView }
    private var mainTabView: some View {
'''+main_view+r'''
    private var homeSelected: Bool {
'''+home_selection+r'''
    @ViewBuilder private var currentTab: some View {
'''+tabs+r'''
}
@main struct Runner {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = Model()
        let host = NSHostingView(rootView: RetainedRoot().environmentObject(model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 800),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        func settle() {
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        settle()
        precondition(Lifetime.created == 1, "initial Home")
        for tab in [1, 2, 3, 4, 0, 2, 0] {
            model.selectedTab = tab; settle()
            precondition(Lifetime.created == 1, "tab switches preserve Home state")
        }
        model.inTutorial = true; model.selectedTab = 0; settle()
        let legacyHome = Lifetime.created
        model.selectedTab = 1; settle()
        model.selectedTab = 0; settle()
        precondition(Lifetime.created > legacyHome, "legacy tutorial retains its original routing")
        print("Native synthetic Home lifetime passed: seven normal tab switches retain Home; legacy tutorial remains separate")
    }
}
'''
assert '.opacity(homeSelected ? 1 : 0)' in root
assert '.allowsHitTesting(homeSelected)' in root and '.accessibilityHidden(!homeSelected)' in root
assert 'model.selectedTab == 0 && selecting' in home
assert '.task(id: model.selectedTab == 0)' in home
assert 'guard !Task.isCancelled, model.selectedTab == 0 else { return }' in home
assert 'usageRefreshRequest = UUID()' in home and 'reloadRequest: usageRefreshRequest' in home
assert '.onChange(of: reloadRequest)' in host
assert 'onScreen && scenePhase == .active && model.selectedTab == 0' in insights
assert '.onChange(of: canRefresh)' in insights
assert 'guard canRefresh else { return }' in insights
assert 'onScreen && scenePhase == .active && model.selectedTab == 0' in host
assert 'model.authorized && !model.inTutorial' in host
assert '.task(id: refreshRequest)' in host and 'refreshRequest = nil' in host
assert host.count('guard !Task.isCancelled, canRefresh') == 2
assert host.count('try await Task.sleep') == 2  # one coalesced query, one retry, no loop
assert 'queryLimits = model.state.limits' in host and 'limits: queryLimits' in host
assert 'LimitsUsageReportView(refreshedAt: refreshedAt, limits: model.state.limits)' not in host
for forbidden in ['.id(', 'showReport', 'reportID', 'Timer.publish', 'makeConfiguration',
                  'usedMinutes', 'usedSeconds', 'ChangeEngine.', 'ShieldController.', 'startMonitoring', 'stopMonitoring']:
    assert forbidden not in host, forbidden
assert '.set(' not in policy.read_text()
with tempfile.TemporaryDirectory(prefix='demora-home-report-checks-') as temporary:
    work = Path(temporary)
    main = work / 'main.swift'
    main.write_text(driver)
    executable = work / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', str(policy), str(main), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
    lifetime = work / 'Lifetime.swift'
    lifetime.write_text(lifetime_driver)
    native = work / 'lifetime'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', str(lifetime), '-o', str(native)], check=True)
    subprocess.run([str(native)], check=True)
print('Home report hidden/cancellation/privacy/enforcement-isolation source guards passed')
