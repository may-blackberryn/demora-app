#!/usr/bin/env python3
"""Actual display projections with fixtures; no live usage/preferences queries."""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
model = ROOT / 'LatchReport/UsageInsightsModel.swift'
presentation = ROOT / 'LatchReport/UsageDashboardPresentation.swift'
formatting = ROOT / 'LatchReport/UsageFormat.swift'
view = (ROOT / 'LatchReport/UsageInsightsView.swift').read_text()
trends = (ROOT / 'LatchReport/UsageTrendsView.swift').read_text()
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

// UsageFormat: hours and minutes, missing is "No data yet", never zero.
let en = UsageFormat(locale: Locale(identifier: "en_US"), translate: { $0 })
check(en.duration(0) == "0 min")
check(en.duration(59) == "0 min")
check(en.duration(59 * 60) == "59 min")
check(en.duration(60 * 60) == "1 h")
check(en.duration(61 * 60) == "1 h 1 min")
check(en.duration((23 * 60 + 59) * 60) == "23 h 59 min")
check(en.duration(21 * 3600) == "21 h")
for invalid in [nil, -1.0, Double.nan, Double.infinity] as [Double?] {
    check(en.duration(invalid) == "No data yet")
    check(en.compact(invalid) == "—")
}
check(en.compact(0) == "0 min")
check(en.signedDuration(minutes: -130) == "−2 h 10 min")
check(en.signedDuration(minutes: -130.9) == "−2 h 10 min")
check(en.signedDuration(minutes: 5.9) == "+5 min")
check(en.signedDuration(minutes: 0.4) == "0 min" && en.signedDuration(minutes: -0.9) == "0 min")
check(en.signedDuration(minutes: .nan) == "—")
check(en.percent(-9.4) == "(−9%)" && en.percent(12.5) == "(+13%)")
check(en.percent(0.4) == nil && en.percent(-0.49) == nil && en.percent(nil) == nil && en.percent(.nan) == nil)
let german = ["%@ h %@ min": "%@ Std. %@ Min.", "%@ h": "%@ Std.", "%@ min": "%@ Min."]
let de = UsageFormat(locale: Locale(identifier: "de_DE"), translate: { german[$0] ?? $0 })
check(de.duration(130 * 60) == "2 Std. 10 Min." && de.duration(1_000 * 3600) == "1.000 Std.")
check(de.format("Your heaviest day was %@: %@.", "Samstag", de.duration(42 * 60)) == "Your heaviest day was Samstag: 42 Min.")
let devanagari = UsageFormat(locale: Locale(identifier: "hi_IN@numbers=deva"), translate: { $0 })
check(devanagari.duration(130 * 60) == "२ h १० min")

// Segment state: app scope, selected week and day page survive every switch.
var selection = UsageInsightsSelection<String>()
check(selection.segment == .day && selection.showsMostUsed)
let pickedWeek = days[7].date
selection.scope(to: "opaque-app"); selection.selectWeek(pickedWeek)
selection.pageBack(dayCount: 29); selection.selectDay(days[3].date)
for segment in [UsageInsightsSegment.week, .trends, .day, .trends, .week, .day] {
    selection.show(segment)
    check(selection.segment == segment && selection.application == "opaque-app"
          && selection.week == pickedWeek && selection.page == 1 && selection.day == days[3].date)
    check(!selection.showsMostUsed)
}
selection.showAllApps()
check(selection.application == nil && selection.week == pickedWeek && selection.showsMostUsed)
selection.show(.trends); check(!selection.showsMostUsed)
selection.show(.week); check(selection.showsMostUsed)
selection.pageForward(); check(selection.page == 0 && selection.day == nil)
selection.pageForward(); check(selection.page == 0)
for _ in 0..<10 { selection.pageBack(dayCount: 29) }
check(selection.page == UsageDashboardPresentation.lastPage(dayCount: 29))
check(UsageInsightsSegment.allCases.map(\.key) == ["Day", "Week", "Trends"])

// Day hero: "Your daily average last week" only for a fully reported week.
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 15))!
let midnight = calendar.startOfDay(for: now)
var full = UsageInsightsAccumulator(now: now, calendar: calendar)
var partial = UsageInsightsAccumulator(now: now, calendar: calendar)
for offset in -14 ... -1 {
    let start = calendar.date(byAdding: .day, value: offset, to: midnight)!
    let finish = calendar.date(byAdding: .day, value: 1, to: start)!
    full.add(source: 0, start: start, end: finish, seconds: 3_600, updatedAt: now)
    if offset != -3 { partial.add(source: 0, start: start, end: finish, seconds: 3_600, updatedAt: now) }
}
check(UsageDashboardPresentation.lastWeekDailyAverage(full.configuration(baseline: nil)) == 3_600)
check(UsageDashboardPresentation.lastWeekDailyAverage(partial.configuration(baseline: nil)) == nil)
check(UsageDashboardPresentation.lastWeekDailyAverage(
    UsageInsightsAccumulator(now: now, calendar: calendar).configuration(baseline: nil)) == nil)
print("Usage dashboard display checks passed: \(checks)")
'''
# One Day · Week · Trends switch (I1); selections go through the tested model.
assert 'ForEach(UsageInsightsSegment.allCases' in view and 'segmentButton(item' in view
assert 'selection.show(item)' in view and '@State private var selection = UsageInsightsSelection<AnyHashable>()' in view
assert 'selection.selectDay(item.date)' in view and 'selection.selectWeek(item.start)' in view
assert 'accessibilityReduceMotion' in view and 'isSelected' in view
assert 'ScrollView(.horizontal' in view and 'count * (dynamicTypeSize.isAccessibilitySize ? 64 : 44)' in view
assert 'minWidth: dynamicTypeSize.isAccessibilitySize ? 64 : 44' in view  # every bar keeps a 44/64 pt target
assert 'UsageDashboardPresentation.barFraction' in view
assert 'fraction == 0' in view and 'dash: [2, 3]' in view  # zero is a hollow dot, missing is dashed
assert 'if !complete { Rectangle().fill(colors.paper' in view  # partial is never colour alone
assert 'ViewThatFits' in trends
# The report's expandable "Usage details" is gone (I4); measured counts live
# in Trends → How complete this is.
assert 'showingDetails' not in view and 'Usage details' not in view + trends
assert 'How complete this is' in trends and 'UsageTrendsModel.coverage(usage)' in trends
assert 'UsageWeekComparison.make(week, in: usage.weeks)' in view
# Neutral ink for less and more (I2); no green/brick grading.
assert 'loosen' not in view + trends and 'free' not in view + trends
# Only incomplete data is labelled (I8).
assert 'Full reported coverage' not in view + trends and 'Partial reported coverage' not in view + trends
assert 'Color(red:' not in view + trends, 'colours come from ReportTheme'
assert 'frame(maxWidth: 640)' in view
assert 'reader.scrollTo(id, anchor: .trailing)' in view
assert 'maxHeight: .infinity' in host and 'reportHeight' not in host
assert 'showingAbout' in host and 'showingDetails' not in host  # one About sheet (I4)
theme = (ROOT / 'Latch/Theme.swift').read_text()
report_theme = (ROOT / 'LatchReport/ReportTheme.swift').read_text()
pair = re.compile(r'static let (\w+)\s*=\s*\w+\(light: 0x([0-9A-Fa-f]{6}), dark: 0x([0-9A-Fa-f]{6})\)')
def block(source, start):
    return source.split(start, 1)[1].split('\n}\n', 1)[0]
app_palette = {n: (l.upper(), d.upper()) for n, l, d in pair.findall(block(theme, 'enum InkPalette {'))}
report_palette = {n: (l.upper(), d.upper()) for n, l, d in pair.findall(block(report_theme, 'enum ReportPalette {'))}
for name, values in report_palette.items():
    assert app_palette.get(name) == values, ('ReportTheme drifted from InkPalette', name)
for amount in ('tintLight', 'tintDark'):
    app_amount = re.search(r'static let ' + amount + r': Double = ([0-9.]+)', theme)
    copy_amount = re.search(r'static let ' + amount + r': Double = ([0-9.]+)', report_theme)
    if copy_amount:
        assert app_amount and app_amount.group(1) == copy_amount.group(1), ('tint amount drifted', amount)
assert {'paper', 'card', 'ink', 'inkSoft', 'hairline', 'accentBlue', 'accentRed', 'free'} <= report_palette.keys()
assert re.search(r'static let tintLight: Double', report_theme), 'tint amounts copied'
# Type scale: every ReportType case returns exactly DemoraType's font and tracking.
def cases(source, start):
    body = source.split(start, 1)[1].split('\n}\n', 1)[0]
    return re.findall(r'case \.(\w+):\s*return ([^\n]+)', body)
assert cases(theme, 'enum DemoraType {') == cases(report_theme, 'enum ReportType {'), 'ReportType drifted from DemoraType'
assert len(cases(report_theme, 'enum ReportType {')) >= 11
def blend(source):
    body = source.split('static func blend(', 1)[1].split('\n    }\n', 1)[0]
    return re.sub(r'\s+', ' ', body)
assert blend(theme) == blend(report_theme), 'tint blend drifted'
with tempfile.TemporaryDirectory(prefix='demora-dashboard-checks-') as temporary:
    work = Path(temporary)
    main = work / 'main.swift'
    main.write_text(driver)
    binary = work / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', str(model), str(presentation), str(formatting),
                    str(main), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print('Dashboard selection, accessibility, viewport and missing-data source checks passed')
