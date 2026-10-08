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
onboarding = (ROOT / "Latch/OnboardingView.swift").read_text()
welcome = (ROOT / "Latch/RedesignWelcomeView.swift").read_text()
settings = (ROOT / "Latch/SettingsView.swift").read_text()
header = home.split('title: tr("Pending changes")', 1)[0]
assert 'Button(selecting ? tr("Done") : tr("Select"))' not in header
assert 'Button(selecting ? tr("Done") : tr("Select"))' in home.split('title: tr("Pending changes")', 1)[1]
assert 'selection.formIntersection(pendingIDs)' in home
assert 'if pendingIDs.isEmpty { selecting = false }' in home
assert 'Label(tr("New limit"), systemImage: "plus")' in limits
assert '.frame(maxWidth: .infinity, minHeight: 48)' in limits
assert 'UsageInsightsView()' in home and 'if !model.inTutorial' in home
assert 'value: -28' in usage and 'devices: devices' in usage
assert 'app.demora.dev.usage-insights' in usage and 'app.demora.production.usage-insights' in usage
assert '.id(' not in usage and 'SharedStore.loadState' not in usage
refresh = block(usage, 'private func refresh()')
assert 'refreshedAt = Date()' in refresh and 'max(' not in refresh
assert 'WeeklyUsageEstimateDraft' in onboarding and 'WeeklyUsageEstimateDraft' in welcome
setup = block(onboarding, 'private func continueSetup()')
assert setup.index('demo.onComplete') < setup.index('WeeklyUsageEstimate.save')
assert 'if saved, let chosenEstimate' in setup
complete = block(welcome, 'private func complete(')
assert complete.index('if demoState != nil') < complete.index('WeeklyUsageEstimate.save')
assert 'if wantsUsageEstimate' in complete
guide = settings.split('struct GuideView:', 1)[1].split('// MARK: - Contact', 1)[0]
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
''' + refresh.replace('private func', 'mutating func') + '''
}
''' + r'''
let beforeRefresh = Date()
var refreshDriver = RefreshDriver(refreshedAt: beforeRefresh.addingTimeInterval(86_400))
refreshDriver.refresh()
precondition(refreshDriver.refreshedAt >= beforeRefresh && refreshDriver.refreshedAt <= Date())
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
print("Usage navigation/source guards passed: visible add, scoped Select, no replay entry, report isolation, optional staging/demo guards")
