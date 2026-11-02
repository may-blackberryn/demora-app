#!/usr/bin/env python3
"""Compile the actual private-report trend projections with synthetic data only."""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
driver = r'''
import Foundation
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ reason: String) {
    precondition(value(), reason); checks += 1
}
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "America/New_York")!
cal.firstWeekday = 2
let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12))!
let today = cal.startOfDay(for: now)
func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }
func add(_ value: inout UsageInsightsAccumulator, _ offset: Int, seconds: Double) {
    value.add(source: 0, start: day(offset), end: cal.date(byAdding: .day, value: 1, to: day(offset))!,
        seconds: seconds, updatedAt: now)
}
var full = UsageInsightsAccumulator(now: now, calendar: cal)
for offset in -28...0 { add(&full, offset, seconds: offset == 0 ? 43200 : Double(-offset * 60)) }
let usage = full.configuration(baseline: nil)
check(UsageTrendsModel.completedDays(usage).count == 28, "exclude current day")
let patterns = UsageTrendsModel.weekdayPatterns(usage)
check(patterns.map(\.weekday) == [2, 3, 4, 5, 6, 7, 1], "locale calendar first weekday")
for pattern in patterns {
    let sample = usage.days.filter { $0.date < today && cal.component(.weekday, from: $0.date) == pattern.weekday }
    let average = sample.compactMap(\.seconds).reduce(0, +) / Double(sample.count)
    check(pattern.sampleCount == 4 && pattern.averageSeconds == average, "weekday means use four real samples")
}
let week = usage.lastSevenDays
check(UsageTrendsModel.days(usage, in: week).map(\.date) == (-7 ... -1).map(day), "ordered exclusive calendar period")
let extremes = UsageTrendsModel.extremes(usage, in: week)
check(extremes.high?.date == day(-7) && extremes.low?.date == day(-1), "period high and low")
let coverage = UsageTrendsModel.coverage(usage)
check(coverage.complete == 28 && coverage.partial == 0 && coverage.missing == 0, "complete coverage excludes today")
let unknown = UsageDashboardPresentation.unavailable(usage)
check(UsageTrendsModel.completedDays(unknown).isEmpty, "unknown days stay unknown")
check(UsageTrendsModel.weekdayPatterns(unknown).allSatisfy { $0.sampleCount == 0 && $0.averageSeconds == nil }, "no invented weekday averages")
check(UsageTrendsModel.extremes(unknown, in: week).high == nil, "no invented extreme")
check(UsageTrendsModel.coverage(unknown).missing == 28, "unknown coverage")

var zero = UsageInsightsAccumulator(now: now, calendar: cal)
for offset in -7 ... -1 { add(&zero, offset, seconds: 0) }
let zeros = zero.configuration(baseline: nil)
let zeroExtreme = UsageTrendsModel.extremes(zeros, in: week)
check(zeroExtreme.high?.date == day(-7) && zeroExtreme.low?.date == day(-7), "ties choose earliest day, explicit zero valid")
check(UsageTrendsModel.weekdayPatterns(zeros).allSatisfy { $0.averageSeconds == 0 && $0.sampleCount == 1 }, "zero is a measured sample")
check(UsageTrendsModel.coverage(zeros).complete == 7 && UsageTrendsModel.coverage(zeros).missing == 21, "zero not missing")

var partial = UsageInsightsAccumulator(now: now, calendar: cal)
add(&partial, -1, seconds: 60)
partial.add(source: 0, start: day(-2), end: day(-2).addingTimeInterval(3600), seconds: 180,
    updatedAt: now)
let short = partial.configuration(baseline: nil)
check(UsageTrendsModel.completedDays(short).map(\.date) == [day(-1)], "partial days excluded from statistics")
check(UsageTrendsModel.coverage(short).complete == 1 && UsageTrendsModel.coverage(short).partial == 1
    && UsageTrendsModel.coverage(short).missing == 26, "partial reported coverage retained")
check(UsageTrendsModel.extremes(short, in: week).high?.seconds == 60, "partial large sample not a maximum")
// Direct invalid configuration protects the projections in addition to producer validation.
for invalid in [-1.0, Double.nan, Double.infinity] {
    var poisoned = usage
    let replacement = UsageInsightsDay(date: day(-1), seconds: invalid, reportedSources: 1, expectedSources: 1, isComplete: true)
    poisoned = UsageInsightsConfiguration(generatedAt: now, calendar: cal,
        days: usage.days.map { $0.date == day(-1) ? replacement : $0 }, lastSevenDays: week,
        previousSevenDays: usage.previousSevenDays, weeks: usage.weeks, baseline: nil)
    check(UsageTrendsModel.completedDays(poisoned).count == 27, "invalid complete sample rejected")
    check(UsageTrendsModel.coverage(poisoned).missing == 1, "invalid duration treated unknown")
    check(UsageTrendsModel.extremes(poisoned, in: week).low?.date == day(-2), "invalid duration never extreme")
}
var sunday = cal; sunday.firstWeekday = 1
let sundayUsage = UsageInsightsConfiguration(generatedAt: now, calendar: sunday, days: usage.days,
    lastSevenDays: week, previousSevenDays: usage.previousSevenDays, weeks: usage.weeks, baseline: nil)
check(UsageTrendsModel.weekdayPatterns(sundayUsage).map(\.weekday) == [1, 2, 3, 4, 5, 6, 7], "Sunday-first calendar")
for (month, number, hours) in [(3, 8, 23.0), (11, 1, 25.0)] {
    let start = cal.date(from: DateComponents(year: 2026, month: month, day: number))!
    let end = cal.date(byAdding: .day, value: 1, to: start)!
    let stamp = end.addingTimeInterval(43200)
    var dst = UsageInsightsAccumulator(now: stamp, calendar: cal)
    dst.add(source: 0, start: start, end: end, seconds: hours * 3600, updatedAt: stamp)
    let config = dst.configuration(baseline: nil)
    check(UsageTrendsModel.completedDays(config).first?.seconds == hours * 3600, "DST uses calendar day, not 24h")
    check(UsageTrendsModel.extremes(config, in: config.lastSevenDays).high?.date == start, "DST period membership")
}

var apps = ApplicationUsageAccumulator(now: now, calendar: cal)
for offset in -28...0 {
    apps.add(source: 0, start: day(offset), end: cal.date(byAdding: .day, value: 1, to: day(offset))!,
        updatedAt: now, applications: [10: offset < -7 ? 120 : 60, 20: offset < -7 ? 0 : 180,
            30: 60, 40: offset < -7 ? 60 : 120])
}
let allApps = apps.applications()
let changes = UsageTrendsModel.appChanges(allApps, current: week, previous: usage.previousSevenDays)
check(changes.map(\.id) == [20, 10, 40], "magnitude sorted, zero excluded, tied ID stable")
check(changes.first?.trend.percentage == nil && changes.first?.trend.differenceMinutes == 21, "zero baseline gives finite minutes, no percentage")
check(changes[1].trend.percentage == -50 && changes[1].trend.differenceMinutes == -7, "signed decrease")
check(UsageTrendsModel.appChanges(allApps, current: week, previous: nil).isEmpty, "oldest period has no invented comparison")
check(UsageTrendsModel.appChanges([], current: week, previous: usage.previousSevenDays).isEmpty, "no app placeholder")
let wrong = UsageInsightsPeriod(start: week.start, end: week.end.addingTimeInterval(1), expectedDays: 7,
    reportedDays: 7, completeDays: 7, seconds: week.seconds)
check(UsageTrendsModel.appChanges(allApps, current: wrong, previous: usage.previousSevenDays).isEmpty, "exact period boundaries required")
let incomplete = UsageInsightsApplication(id: 90, usage: short)
check(UsageTrendsModel.appChanges([incomplete], current: week, previous: usage.previousSevenDays).isEmpty, "partial app periods never comparable")
for current in usage.weeks {
    let previous = UsageDashboardPresentation.preceding(current, in: usage.weeks)
    let results = UsageTrendsModel.appChanges(allApps, current: current, previous: previous)
    check(results.allSatisfy { $0.current.start == current.start && $0.current.end == current.end }, "selected period app comparisons")
}
print("Usage trends algorithm checks passed: \(checks)")
'''
view = (ROOT / 'LatchReport/UsageInsightsView.swift').read_text()
trends = (ROOT / 'LatchReport/UsageTrendsView.swift').read_text()
host = (ROOT / 'Latch/UsageInsightsView.swift').read_text()
assert 'if showingTrends' in view and 'UsageTrendsView(' in view
assert 'onBack: { showingTrends = false }' in view
assert 'showingTrends = true' in view and 'Explore trends' in view
assert 'applicationLabel(id).id(selectedApplication)' in view
assert 'selectedApplicationLabel.id(selectedApplication)' in view
assert 'applicationLabel(app.id).id(applicationIdentity(app.id))' in view
assert 'applicationLabel(change.id).id(applicationIdentity(change.id))' in trends
assert 'baseline: selectedApplication == nil ? configuration.baseline : nil' in view
assert 'Today is excluded from trends.' in trends
assert 'These app changes do not add up to the overall difference.' in trends
assert 'time saved by Demora' in trends and 'not measured Screen Time or a goal' in trends
assert 'accessibilityReduceMotion' in trends and 'accessibilityValue' in trends and 'ViewThatFits' in trends
assert 'dayCoverage(day)' in trends and 'dayCoverage(prior)' in trends
assert '@ScaledMetric(relativeTo: .caption2) private var coverageCellSize' in trends
assert 'GridItem(.fixed(coverageCellSize)' in trends
assert 'selectedStart = week.start; selectedDay = nil' in trends
# The host's existing refresh identifier is unchanged; no app selection exported into it.
assert 'selectedApplication' not in host and 'UsageTrends' not in host
for name in ['UsageTrendsModel.swift', 'UsageTrendsView.swift']:
    source = re.sub(r'//[^\n]*', '', (ROOT / 'LatchReport' / name).read_text())
    assert not re.search(r'\b(?:Encodable|Codable|JSONEncoder|URLSession|FileManager|Logger|OSLog|AppStorage)\b|\.set\s*\(|\.write\s*\(|\b(?:print|NSLog)\s*\(', source)
with tempfile.TemporaryDirectory(prefix='demora-trends-checks-') as temporary:
    work = Path(temporary)
    main = work / 'main.swift'
    main.write_text(driver)
    executable = work / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5',
        str(ROOT / 'LatchReport/UsageInsightsModel.swift'),
        str(ROOT / 'LatchReport/ApplicationUsageAccumulator.swift'),
        str(ROOT / 'LatchReport/UsageDashboardPresentation.swift'),
        str(ROOT / 'LatchReport/UsageTrendsModel.swift'), str(main), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
print('Trends navigation, scoped-label identity, coverage and no-export guards passed')
