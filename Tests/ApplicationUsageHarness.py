#!/usr/bin/env python3
"""Actual per-app report algorithms, with synthetic data only."""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
driver = r'''
import Foundation
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message); checks += 1
}
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "America/New_York")!
let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12))!
let today = cal.startOfDay(for: now)
func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }
func end(_ date: Date) -> Date { cal.date(byAdding: .day, value: 1, to: date)! }
func add(_ value: inout ApplicationUsageAccumulator, _ offset: Int, _ apps: [Int: Double],
         source: Int = 0, stamp: Date = now) {
    value.add(source: source, start: day(offset), end: end(day(offset)), updatedAt: stamp, applications: apps)
}
func app(_ value: ApplicationUsageAccumulator, _ id: Int) -> UsageInsightsConfiguration? {
    value.applications().first { $0.id == id }?.usage
}
func seconds(_ value: ApplicationUsageAccumulator, _ id: Int, _ offset: Int) -> Double? {
    app(value, id)?.days.first { $0.date == day(offset) }?.seconds
}
var empty = ApplicationUsageAccumulator(now: now, calendar: cal)
check(empty.applications().isEmpty, "empty reports don't fabricate apps")
add(&empty, -1, [:])
check(empty.applications().isEmpty, "empty map doesn't fabricate zeros")
var full = ApplicationUsageAccumulator(now: now, calendar: cal)
for offset in -28...0 { add(&full, offset, [10: offset < -7 ? 1200 : 600, 20: 0]) }
check(full.applications().map(\.id) == [10, 20], "deterministic opaque IDs")
check(app(full, 10)?.reportedDays == 29, "actual daily history retained")
check(seconds(full, 10, 0) == 600, "today's real app duration")
check(app(full, 10)?.today?.isComplete == false, "today never complete")
check(app(full, 10)?.lastSevenDays.seconds == 4200, "seven completed days sum")
check(app(full, 10)?.trend?.percentage == -50, "comparable app-only trend")
check(app(full, 20)?.lastSevenDays.seconds == 0, "explicit zero remains zero")
check(app(full, 20)?.lastSevenDays.isComplete == true, "explicit zero valid coverage")
var revisions = full
add(&revisions, -1, [10: .nan, 20: 0], stamp: now.addingTimeInterval(-60))
check(app(revisions, 10)?.lastSevenDays.isComplete == true, "stale invalid revision does not poison winning coverage")
check(app(revisions, 10)?.trend?.percentage == -50, "stale invalid revision does not suppress trend")
var correction = ApplicationUsageAccumulator(now: now, calendar: cal)
for offset in -14 ... -1 {
    add(&correction, offset, [10: offset == -1 ? .nan : 600, 20: 0], stamp: now.addingTimeInterval(-60))
}
check(app(correction, 10)?.lastSevenDays.isComplete == false, "winning invalid revision suppresses coverage")
add(&correction, -1, [10: 600, 20: 0])
check(app(correction, 10)?.lastSevenDays.isComplete == true, "newer corrected revision restores coverage")
check(app(correction, 10)?.trend?.differenceMinutes == 0, "corrected revision restores valid trend")
check(app(full, 10)?.baseline == nil && app(full, 10)?.applications.isEmpty == true,
      "app histories never inherit overall manual estimate or recursive breakdowns")
var duplicate = ApplicationUsageAccumulator(now: now, calendar: cal)
add(&duplicate, -1, [10: 1200])
add(&duplicate, -1, [10: 1200])
check(seconds(duplicate, 10, -1) == 1200, "duplicate snapshot not doubled")
add(&duplicate, -1, [10: 1800])
add(&duplicate, -1, [10: 600])
check(seconds(duplicate, 10, -1) == 1800, "equal version maxima deterministic")
check(app(duplicate, 10)?.days[27].isComplete == false, "contradictory versions suppress trend")
var fresh = ApplicationUsageAccumulator(now: now, calendar: cal)
add(&fresh, -1, [10: 1800, 20: 120], stamp: now.addingTimeInterval(-60))
add(&fresh, -1, [10: 600])
check(seconds(fresh, 10, -1) == 600, "newest revision can correct down")
check(app(fresh, 20) == nil, "new revision omission removes stale app")
add(&fresh, -1, [10: 2400, 20: 180], stamp: now.addingTimeInterval(-120))
check(seconds(fresh, 10, -1) == 600 && app(fresh, 20) == nil, "stale revision cannot restore app")
var short = ApplicationUsageAccumulator(now: now, calendar: cal)
short.add(source: 0, start: day(-1), end: day(-1).addingTimeInterval(3600), updatedAt: now,
          applications: [10: 600, 20: 120])
add(&short, -1, [10: 900])
check(seconds(short, 10, -1) == 900 && app(short, 20) == nil, "full interval replaces shorter map")
check(app(short, 10)?.days[27].isComplete == true, "full segment coverage")
short.add(source: 0, start: day(-1), end: day(-1).addingTimeInterval(3600), updatedAt: now,
          applications: [10: 1800, 20: 120])
check(seconds(short, 10, -1) == 900 && app(short, 20) == nil, "shorter equal version ignored")
var multiple = full
multiple.registerSource(1)
check(app(multiple, 10)?.lastSevenDays.isComplete == false, "missing source not zero")
for offset in -28...0 { add(&multiple, offset, [10: 300], source: 1) }
check(seconds(multiple, 10, -1) == 900, "same app on distinct sources sums")
check(app(multiple, 10)?.lastSevenDays.isComplete == true, "all sources required for full coverage")
check(app(multiple, 20)?.lastSevenDays.isComplete == false, "omitted app in other source not zero")
var missing = full
add(&missing, -3, [20: 0], stamp: now.addingTimeInterval(0))
// Equal-version contradiction retains known max but suppresses confidence.
check(app(missing, 10)?.trend == nil, "contradiction never makes trend")
var omitted = ApplicationUsageAccumulator(now: now, calendar: cal)
for offset in -14 ... -1 { add(&omitted, offset, offset == -3 ? [:] : [10: 600]) }
check(seconds(omitted, 10, -3) == nil, "absent day unknown not zero")
check(app(omitted, 10)?.lastSevenDays.seconds == 3600, "partial actual sum not extrapolated")
check(app(omitted, 10)?.lastSevenDays.reportedDays == 6, "coverage counts")
check(app(omitted, 10)?.trend == nil, "incomplete app periods never trend")
for invalid in [-1.0, Double.nan, Double.infinity, -Double.infinity, 100000] {
    var bad = ApplicationUsageAccumulator(now: now, calendar: cal)
    add(&bad, -1, [10: invalid, 20: 60])
    check(app(bad, 10) == nil, "invalid app value never appears")
    check(seconds(bad, 20, -1) == 60 && app(bad, 20)?.days[27].isComplete == false,
          "invalid evidence suppresses full-day confidence")
}
var intervals = ApplicationUsageAccumulator(now: now, calendar: cal)
for (start, finish) in [(day(-1), day(-1)), (day(-1), end(today)),
                        (day(-1).addingTimeInterval(1), today),
                        (day(-1), Date(timeIntervalSince1970: .infinity))] {
    intervals.add(source: 0, start: start, end: finish, updatedAt: now, applications: [10: 60])
}
add(&intervals, -29, [10: 60]); add(&intervals, 1, [10: 60])
add(&intervals, -1, [10: 60], stamp: now.addingTimeInterval(1))
check(intervals.applications().isEmpty, "invalid clipped future or outside intervals excluded")
var excess = ApplicationUsageAccumulator(now: now, calendar: cal)
add(&excess, 0, [10: 13 * 3600])
check(excess.applications().isEmpty, "today bounded by elapsed time")
for (month, number, hours) in [(3, 8, 23.0), (11, 1, 25.0)] {
    let date = cal.date(from: DateComponents(year: 2026, month: month, day: number))!
    let finish = end(date)
    var dst = ApplicationUsageAccumulator(now: finish.addingTimeInterval(43200), calendar: cal)
    dst.add(source: 0, start: date, end: finish, updatedAt: finish, applications: [10: hours * 3600])
    check(app(dst, 10)?.days.first { $0.date == date }?.seconds == hours * 3600, "23/25-hour app day")
    check(app(dst, 10)?.days.first { $0.date == date }?.isComplete == true, "DST complete")
}
let apps = full.applications()
check(UsageDashboardPresentation.rankedApplications(apps, day: today, week: nil).map(\.id) == [10, 20], "rank by actual day")
check(UsageDashboardPresentation.rankedApplications(apps, day: nil, week: app(full, 10)!.lastSevenDays.start).map(\.id) == [10, 20], "rank same selected week")
check(UsageDashboardPresentation.rankedApplications(apps, day: day(-29), week: nil).isEmpty, "unknown period empty")
check(UsageDashboardPresentation.appSeconds(apps[0], day: today, week: day(-29)) == nil, "unknown week never falls back to day")
check(UsageDashboardPresentation.rankedApplications([], day: today, week: nil).isEmpty, "no ranking placeholders")
let unavailable = UsageDashboardPresentation.unavailable(app(full, 10)!)
check(unavailable.reportedDays == 0 && unavailable.days.allSatisfy { $0.seconds == nil },
      "disappeared selection retains an unknown scope, not overall usage")
check(unavailable.baseline == nil && unavailable.trend == nil, "unknown app has no estimate or trend")
check(unavailable.today?.date == today && unavailable.weeks.count == 4, "unknown scope keeps calendar navigation")
// "See all N apps" counts the ranked list; apps with no reported time aren't in it.
let ranked = UsageDashboardPresentation.rankedApplications(apps, day: today, week: nil)
check(UsageDashboardPresentation.visibleApplications(ranked, expanded: false).count == ranked.count, "two apps all shown")
let many = Array(0..<14)
check(UsageDashboardPresentation.visibleApplications(many, expanded: false) == [0, 1, 2, 3, 4], "top five")
check(UsageDashboardPresentation.visibleApplications(many, expanded: true) == many, "See all expands in place")
check(UsageDashboardPresentation.visibleApplications([Int](), expanded: false).isEmpty, "no placeholder rows")
let unknownDay = UsageDashboardPresentation.rankedApplications(apps, day: day(-29), week: nil)
check(unknownDay.isEmpty, "unknown apps never counted as zero-minute rows")
var scoped = UsageInsightsSelection<Int>()
check(scoped.showsMostUsed, "all apps shows Most used")
scoped.scope(to: 10)
for segment in UsageInsightsSegment.allCases {
    scoped.show(segment); check(!scoped.showsMostUsed, "app scope hides Most used in every segment")
}
scoped.showAllApps(); scoped.show(.day)
check(scoped.showsMostUsed && scoped.application == nil, "All apps brings it back")
print("Application usage algorithm checks passed: \(checks)")
'''
report = (ROOT / 'LatchReport/UsageInsightsReport.swift').read_text()
view = (ROOT / 'LatchReport/UsageInsightsView.swift').read_text()
extension = (ROOT / 'LatchReport/LatchReportExtension.swift').read_text()
assert 'max(previous, seconds)' in report  # duplicate categories don't add
assert 'segment.totalActivityDuration' in report
assert 'applicationTokens: Dictionary' in report
assert 'AnyView(Label(token))' in extension and 'AnyHashable(token)' in extension
assert '@State private var selection = UsageInsightsSelection<AnyHashable>()' in view
assert 'private var selectedApplication: AnyHashable? { selection.application }' in view
assert 'applicationIdentity($0.id) == selectedApplication' in view
assert 'selection.scope(to: applicationIdentity(id))' in view
assert 'selection.showAllApps(); selectedApplicationLabel = nil' in view
assert 'reader.scrollTo("usageTop", anchor: .top)' in view
assert 'app.usage.weeks.first' in view and 'app.usage.days.first' in view
assert 'baseline: selectedApplication == nil ? configuration.baseline : nil' in view
assert 'UsageDashboardPresentation.unavailable(configuration)' in view
assert 'else if let selectedApplicationLabel' in view
assert 'applicationLabel(id).id(selectedApplication)' in view
assert 'selectedApplicationLabel.id(selectedApplication)' in view
assert 'rankedApplications' in view and 'visibleApplications(applications, expanded:' in view and 'LazyVStack' in view
assert 'if selection.showsMostUsed { mostUsedApplications(colors) }' in view
assert 'text.format("See all %d apps", applications.count)' in view
for file in ['ApplicationUsageAccumulator.swift', 'UsageInsightsReport.swift', 'UsageInsightsModel.swift', 'UsageInsightsView.swift', 'UsageTrendsView.swift', 'UsageTrendsModel.swift', 'UsageFormat.swift', 'ReportTheme.swift', 'UsageDashboardPresentation.swift']:
    code = re.sub(r'//[^\n]*', '', (ROOT / 'LatchReport' / file).read_text())
    assert not re.search(r'\b(?:Encodable|Codable|JSONEncoder|URLSession|FileManager|OSLog|Logger)\b|\.set\s*\(|\.write\s*\(|\b(?:print|NSLog)\s*\(', code)
with tempfile.TemporaryDirectory(prefix='demora-app-usage-') as temporary:
    work = Path(temporary)
    main = work / 'main.swift'
    main.write_text(driver)
    binary = work / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5',
                    str(ROOT / 'LatchReport/UsageInsightsModel.swift'),
                    str(ROOT / 'LatchReport/ApplicationUsageAccumulator.swift'),
                    str(ROOT / 'LatchReport/UsageDashboardPresentation.swift'), str(main), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print('Application usage private-label, selection, missing-data and no-side-effect guards passed')
