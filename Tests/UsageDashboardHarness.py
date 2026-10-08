#!/usr/bin/env python3
"""Actual display projections with fixtures; no live usage/preferences queries."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
model = ROOT / 'LatchReport/UsageInsightsModel.swift'
presentation = ROOT / 'LatchReport/UsageDashboardPresentation.swift'
view = (ROOT / 'LatchReport/UsageInsightsView.swift').read_text()
host = (ROOT / 'Latch/UsageInsightsView.swift').read_text()
driver = r'''
import Foundation
var checks = 0
func check(_ value: @autoclosure () -> Bool) { precondition(value()); checks += 1 }
var days: [UsageInsightsDay] = []
for index in 0..<29 {
    let stamp = Double(index + 1) * 86400.0
    let seconds: Double? = index == 0 ? nil : Double(index * 60)
    days.append(UsageInsightsDay(date: Date(timeIntervalSince1970: stamp),
        seconds: seconds, reportedSources: 1, expectedSources: 1, isComplete: index < 28))
}
check(UsageDashboardPresentation.window([], page: 0).isEmpty)
check(UsageDashboardPresentation.lastPage(dayCount: 0) == 0)
check(UsageDashboardPresentation.lastPage(dayCount: 29) == 4)
var dates = Set<Date>()
for page in 0...4 {
    let window = UsageDashboardPresentation.window(days, page: page)
    check(window.count == 7)
    check(Set(window.map(\.date)).count == 7)
    check(window.map(\.date) == window.map(\.date).sorted())
    dates.formUnion(window.map(\.date))
}
check(dates == Set(days.map(\.date)))
check(UsageDashboardPresentation.window(days, page: 0).last?.date == days.last?.date)
check(UsageDashboardPresentation.window(days, page: -1).last?.date == days.last?.date)
check(UsageDashboardPresentation.window(days, page: Int.max).first?.date == days.first?.date)
check(UsageDashboardPresentation.window(Array(days.prefix(2)), page: 0).count == 2)
check(UsageDashboardPresentation.barFraction(nil, maximum: 100) == nil)
check(UsageDashboardPresentation.barFraction(0, maximum: 100) == 0)
check(UsageDashboardPresentation.barFraction(50, maximum: 100) == 0.5)
check(UsageDashboardPresentation.barFraction(200, maximum: 100) == 1)
for invalid in [-1.0, Double.nan, Double.infinity] {
    check(UsageDashboardPresentation.barFraction(invalid, maximum: 100) == nil)
    check(UsageDashboardPresentation.barFraction(10, maximum: invalid) == nil)
}
check(UsageDashboardPresentation.barFraction(1, maximum: 0) == nil)
func period(_ complete: Int, _ seconds: Double?) -> UsageInsightsPeriod {
    UsageInsightsPeriod(start: days[0].date, end: days[7].date, expectedDays: 7,
        reportedDays: complete, completeDays: complete, seconds: seconds)
}
check(UsageDashboardPresentation.average(period(7, 420)) == 60)
check(UsageDashboardPresentation.average(period(7, 0)) == 0)
check(UsageDashboardPresentation.average(period(6, 420)) == nil)
check(UsageDashboardPresentation.average(period(7, nil)) == nil)
check(UsageDashboardPresentation.average(period(7, .infinity)) == nil)
check(UsageDashboardPresentation.average(period(7, -1)) == nil)
let firstWeek = period(7, 420)
let secondWeek = UsageInsightsPeriod(start: firstWeek.end, end: days[14].date, expectedDays: 7,
    reportedDays: 7, completeDays: 7, seconds: 840)
check(UsageDashboardPresentation.preceding(secondWeek, in: [firstWeek, secondWeek])?.start == firstWeek.start)
check(UsageDashboardPresentation.preceding(firstWeek, in: [firstWeek, secondWeek]) == nil)
print("Usage dashboard display checks passed: \(checks)")
'''
assert 'rangeButton("Daily"' in view and 'rangeButton("Weekly"' in view
assert 'selectedDay = item.date' in view and 'selectedWeek = item.start' in view
assert 'accessibilityReduceMotion' in view and 'isSelected' in view
assert 'ScrollView(.horizontal' in view and 'count * (dynamicTypeSize.isAccessibilitySize ? 64 : 44)' in view
assert 'UsageDashboardPresentation.barFraction' in view
assert 'fraction == 0' in view and 'dash: [2, 3]' in view
assert 'ViewThatFits' in view and 'showingDetails.toggle()' in view
assert 'UsageInsightsTrend.compare(comparisonCurrent, with: previous)' in view
assert 'reader.scrollTo(id, anchor: .trailing)' in view
assert 'maxHeight: .infinity' in host and 'reportHeight' not in host
assert 'showingUsageInfo' in host
with tempfile.TemporaryDirectory(prefix='demora-dashboard-checks-') as temporary:
    work = Path(temporary)
    main = work / 'main.swift'
    main.write_text(driver)
    binary = work / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', str(model), str(presentation),
                    str(main), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print('Dashboard selection, accessibility, viewport and missing-data source checks passed')
