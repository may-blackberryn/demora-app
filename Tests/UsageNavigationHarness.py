#!/usr/bin/env python3
"""Actual manual-estimate logic plus structural navigation/demo guards.
No real usage is read and no live App Group is accessed. Not a SwiftUI UI test.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def block(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]

usage = (ROOT / "Latch/UsageInsightsView.swift").read_text()
home = (ROOT / "Latch/HomeView.swift").read_text()
limits = (ROOT / "Latch/LimitsView.swift").read_text()
rules = (ROOT / "Latch/RulesView.swift").read_text()
root = block((ROOT / "Latch/LatchApp.swift").read_text(), "struct RootView:")
onboarding = (ROOT / "Latch/OnboardingView.swift").read_text()
welcome = (ROOT / "Latch/RedesignWelcomeView.swift").read_text()
settings = (ROOT / "Latch/SettingsView.swift").read_text()
ledger = block((ROOT / "Latch/ChangesLedgerView.swift").read_text(), "struct ChangesLedgerView:")
assert 'Button(selecting ? tr("Done") : tr("Select"))' in ledger
assert 'selection.formIntersection(pendingIDs)' in ledger
assert 'if pendingIDs.isEmpty { selecting = false }' in ledger
assert 'selecting' not in home, 'bulk selection belongs to Changes, not Today'
assert 'Label(tr("New rule"), systemImage: "plus")' in rules
assert 'Button { showChooser = true } label:' in rules and 'inTutorial' not in rules
assert 'LimitEditorView(existing: nil)' in rules and 'LimitEditorView(existing: nil)' in home
assert 'struct LimitsView:' not in limits, 'the obsolete tab is not an alternate add path'
assert 'UsageInsightsView()' not in home and 'HelpGuideView()' not in home and 'moreLinks' not in home
assert 'private enum TodayRoute: Hashable { case changes }' in home
assert 'UsageInsightsView()' in root and 'model.selectedTab == 2' in root
assert 'case 1: RulesView()' in root and 'case 3: YouView()' in root
assert 'model.inTutorial' not in root
can_refresh = block(usage, 'private var canRefresh: Bool')
assert 'onScreen && scenePhase == .active && model.selectedTab == 2' in can_refresh
assert '&& model.authorized' in can_refresh
assert 'value: -28' in usage and 'devices: devices' in usage
assert 'app.demora.dev.usage-insights' in usage and 'app.demora.production.usage-insights' in usage
assert '.id(' not in usage and 'SharedStore.loadState' not in usage
# The estimate editor is reachable only from About this data (I5): no pinned
# bottom button, one editor, pushed inside the About sheet's stack.
insights = block(usage, 'struct UsageInsightsView:')
assert 'Edit weekly estimate' not in usage and 'editingEstimate' not in usage
assert insights.count('WeeklyUsageEstimateDraft(') == 1
assert '.navigationDestination(for: AboutRoute.self) { _ in estimateEditor }' in insights
assert 'aboutPath.append(.startingPoint)' in block(insights, 'private var startingPointRow')
# Refresh: header button only, coalesced like Today, one soft retry, no loop.
assert insights.count('requestRefresh()') >= 5 and insights.count('try await Task.sleep') == 2
assert 'HomeReportRefreshPolicy' in insights and 'refreshPolicy.didQuery' in insights
# Without Screen Time access: a calm card that goes to Today. No prompt,
# no Settings redirect (Apple 5.1.1(iv)); Today owns the banner.
assert 'tr("Go to Today")' in insights and 'requestAuthorization' not in usage
assert 'openSettingsURLString' not in usage and 'ScreenTimeReauthBanner' not in usage
go_to_today = block(usage, 'private func goToToday()')
assert go_to_today.split('{', 1)[1].rsplit('}', 1)[0].strip() == 'model.selectedTab = 0', \
    'Go to Today only switches the tab; it must not dismiss the retained Root hierarchy'
tab_change = block(insights, '.onChange(of: model.selectedTab)')
modal_reset = block(tab_change, 'if tab != 2')
for reset in ('showingAbout = false', 'aboutPath = []', 'saveFailed = false'):
    assert reset in modal_reset, ('tab switch closes stale Insights modal/navigation/error state', reset)
assert 'dismiss(' not in tab_change and 'refreshedAt =' not in tab_change, \
    'a widget tab switch clears transient UI, not the report identity or query'
refresh = block(usage, 'private func refresh()')
assert 'refreshedAt = Date()' in refresh and 'max(' not in refresh
assert 'SetupEstimateDisclosure(enabled: $wantsUsageEstimate, minutes: $usageEstimateMinutes)' in onboarding
assert 'SetupEstimateDisclosure(enabled: $wantsUsageEstimate, minutes: $usageEstimateMinutes)' in welcome
disclosure = block(onboarding, 'struct SetupEstimateDisclosure:')
assert 'WeeklyUsageEstimateDraft(enabled: $enabled, minutes: $minutes)' in disclosure
assert '@State private var expanded = false' in disclosure
assert 'WeeklyUsageEstimate.save' not in disclosure, 'expansion only stages a local estimate'
setup = block(onboarding, 'private func continueSetup()')
assert setup.index('demo.onComplete') < setup.index('WeeklyUsageEstimate.save')
assert 'if saved, let chosenEstimate' in setup
complete = block(welcome, 'private func complete(')
assert complete.index('if demoState != nil') < complete.index('WeeklyUsageEstimate.save')
assert 'if wantsUsageEstimate' in complete
guide = settings.split('struct GuideView:', 1)[1].split('// MARK: - Language', 1)[0]
assert 'replayTutorial' not in guide and 'Replay walkthrough' not in guide

driver = '''
import Foundation
enum SharedStore {
    static let suite = "demora-usage-estimate-test." + UUID().uuidString
    static let defaults = UserDefaults(suiteName: suite)!
}
''' + block(usage, 'struct WeeklyUsageEstimate:') + '''
struct RefreshDriver {
    var refreshedAt: Date
    var canRefresh = true
''' + refresh.replace('private func', 'mutating func') + '''
}
''' + r'''
let beforeRefresh = Date()
var refreshDriver = RefreshDriver(refreshedAt: beforeRefresh.addingTimeInterval(86_400))
refreshDriver.refresh()
precondition(refreshDriver.refreshedAt >= beforeRefresh && refreshDriver.refreshedAt <= Date())
let lastVisibleQuery = refreshDriver.refreshedAt
refreshDriver.canRefresh = false
refreshDriver.refresh()
precondition(refreshDriver.refreshedAt == lastVisibleQuery)
let defaults = SharedStore.defaults
defer { defaults.removePersistentDomain(forName: SharedStore.suite) }
precondition(WeeklyUsageEstimate.load() == nil)
let originalRules = Data([1, 2, 3, 4])
defaults.set(originalRules, forKey: "latch.state.v1")
let date = Date(timeIntervalSince1970: 1790000000)
for minutes in [0, 1, 1260, 10080] {
    precondition(WeeklyUsageEstimate.save(minutes: minutes, at: date))
    precondition(WeeklyUsageEstimate.load() == WeeklyUsageEstimate(weeklyMinutes: minutes, recordedAt: date))
}
let before = defaults.data(forKey: WeeklyUsageEstimate.key)
for minutes in [-1, 10081, Int.max] {
    precondition(!WeeklyUsageEstimate.save(minutes: minutes, at: date))
    precondition(defaults.data(forKey: WeeklyUsageEstimate.key) == before)
}
for stamp in [Double.infinity, -Double.infinity, Double.nan, 0, -1] {
    precondition(!WeeklyUsageEstimate.save(minutes: 60, at: Date(timeIntervalSince1970: stamp)))
}
defaults.set(Data("corrupt".utf8), forKey: WeeklyUsageEstimate.key)
precondition(WeeklyUsageEstimate.load() == nil)
defaults.set(Data(repeating: 32, count: 1_025), forKey: WeeklyUsageEstimate.key)
precondition(WeeklyUsageEstimate.load() == nil)
let invalid = WeeklyUsageEstimate(weeklyMinutes: 10081, recordedAt: date)
defaults.set(try JSONEncoder().encode(invalid), forKey: WeeklyUsageEstimate.key)
precondition(WeeklyUsageEstimate.load() == nil)
precondition(WeeklyUsageEstimate.save(minutes: 42, at: date))
WeeklyUsageEstimate.remove()
precondition(WeeklyUsageEstimate.load() == nil)
precondition(defaults.data(forKey: "latch.state.v1") == originalRules)
print("Manual estimate passed: optional/roundtrip/bounds/corruption/removal; enforcement bytes unchanged")
'''
with tempfile.TemporaryDirectory(prefix="demora-usage-navigation-") as directory:
    source = Path(directory) / "main.swift"
    binary = Path(directory) / "checks"
    source.write_text(driver)
    subprocess.run(["xcrun", "swiftc", str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print("Usage navigation/source guards passed: four-tab destinations, visible New rule, Changes-only Select, active Insights refresh, tab-switch modal reset, Go to Today preserves Root, no replay entry, report isolation, optional staging/demo guards")
