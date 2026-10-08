#!/usr/bin/env python3
"""Compile/run the production Foundation-only insights algorithms with fake data.

No Xcode build, Screen Time query, raw-usage persistence, or host changes.
SwiftUI rendering and signed-device data delivery remain root/device checks.
"""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "LatchReport/UsageInsightsModel.swift"
report = (ROOT / "LatchReport/UsageInsightsReport.swift").read_text()
view = (ROOT / "LatchReport/UsageInsightsView.swift").read_text()
extension = (ROOT / "LatchReport/LatchReportExtension.swift").read_text()
model = MODEL.read_text()
presentation = (ROOT / "LatchReport/UsageDashboardPresentation.swift").read_text()

# This suite links the actual production model, not a Python translation.
driver = r'''
import Foundation

var checks = 0
func check(_ passed: @autoclosure () -> Bool, _ label: String) {
    precondition(passed(), label)
    checks += 1
}
func close(_ a: Double?, _ b: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) < 0.000001
}
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/New_York")!
let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 12))!
let today = calendar.startOfDay(for: now)
func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
func end(_ start: Date) -> Date { calendar.date(byAdding: .day, value: 1, to: start)! }
func add(_ accumulator: inout UsageInsightsAccumulator, _ offset: Int,
         seconds: Double, source: Int = 0, updatedAt: Date = now) {
    accumulator.add(source: source, start: day(offset), end: end(day(offset)),
                    seconds: seconds, updatedAt: updatedAt)
}
func config(_ accumulator: UsageInsightsAccumulator) -> UsageInsightsConfiguration {
    accumulator.configuration(baseline: nil)
}

var full = UsageInsightsAccumulator(now: now, calendar: calendar)
for offset in -28...0 {
    add(&full, offset, seconds: offset < -7 ? 120 : 60)
}
let all = config(full)
check(all.days.count == 29 && all.days.first!.date == day(-28)
      && all.days.last!.date == today, "28 completed calendar days plus today")
check(all.reportedDays == 29 && all.today!.seconds == 60, "actual reported coverage and today")
check(!all.today!.isComplete, "today is always partial")
check(all.lastSevenDays.start == day(-7) && all.lastSevenDays.end == today,
      "completed comparison excludes today")
check(all.previousSevenDays.start == day(-14) && all.previousSevenDays.end == day(-7),
      "previous completed seven days")
check(all.lastSevenDays.isComplete && all.previousSevenDays.isComplete,
      "both periods have full per-source coverage")
check(close(all.lastSevenDays.seconds, 420) && close(all.previousSevenDays.seconds, 840),
      "segment totals aggregate by day")
check(close(all.trend?.differenceMinutes, -7) && close(all.trend?.percentage, -50),
      "difference and comparable percentage")
check(all.weeks.count == 4 && all.weeks.allSatisfy(\.isComplete), "four complete weekly periods")
for index in 0..<4 {
    check(all.weeks[index].start == day(-28 + index * 7)
          && all.weeks[index].end == day(-21 + index * 7), "consecutive completed weekly totals")
}
check(close(all.weeks.last!.seconds, 420), "current partial week never replaces completed total")

// Identical or overlapping daily snapshots from one user/device must not add.
var duplicates = UsageInsightsAccumulator(now: now, calendar: calendar)
add(&duplicates, -1, seconds: 120)
add(&duplicates, -1, seconds: 120)
check(close(config(duplicates).days[27].seconds, 120), "duplicate exact interval not doubled")
add(&duplicates, -1, seconds: 180)
add(&duplicates, -1, seconds: 60)
check(close(config(duplicates).days[27].seconds, 180), "equal-version duplicates deterministic max")
add(&duplicates, -1, seconds: 240, updatedAt: now.addingTimeInterval(-60))
check(close(config(duplicates).days[27].seconds, 180), "stale snapshot never replaces current")
var ordered = UsageInsightsAccumulator(now: now, calendar: calendar)
add(&ordered, -1, seconds: 240, updatedAt: now.addingTimeInterval(-60))
add(&ordered, -1, seconds: 180)
check(close(config(ordered).days[27].seconds, 180), "fresh revision may correct usage down")
ordered.add(source: 0, start: day(-1), end: day(-1).addingTimeInterval(3_600),
            seconds: 60, updatedAt: now.addingTimeInterval(-120))
check(close(config(ordered).days[27].seconds, 180), "overlapping partial snapshot not summed")
add(&ordered, -1, seconds: 60, source: 1)
check(close(config(ordered).days[27].seconds, 240), "distinct sources with same interval are summed")
check(config(ordered).days[27].reportedSources == 2, "opaque source coverage")

var empty = UsageInsightsAccumulator(now: now, calendar: calendar)
let nothing = config(empty)
check(nothing.reportedDays == 0 && nothing.today!.seconds == nil,
      "empty results never fabricate zero")
check(nothing.days.allSatisfy { $0.seconds == nil && !$0.isComplete }, "missing bars retain nil")
check(nothing.lastSevenDays.seconds == nil && nothing.trend == nil, "no data is not a zero trend")

var missing = UsageInsightsAccumulator(now: now, calendar: calendar)
for offset in -14 ... -1 where offset != -3 { add(&missing, offset, seconds: 60) }
check(config(missing).lastSevenDays.reportedDays == 6
      && config(missing).lastSevenDays.completeDays == 6, "missing-day coverage explicit")
check(config(missing).trend == nil, "missing day never counted zero for trends")
check(close(config(missing).lastSevenDays.seconds, 360), "partial reported sum retained, not extrapolated")
var missingSource = full
missingSource.registerSource(1)
check(config(missingSource).reportedDays == 29 && config(missingSource).trend == nil,
      "present-but-empty source prevents full coverage claim")
check(config(missingSource).days[0].reportedSources == 1
      && config(missingSource).days[0].expectedSources == 2, "partial source coverage retained")
for offset in -28...0 { add(&missingSource, offset, seconds: 30, source: 1) }
check(config(missingSource).trend != nil && close(config(missingSource).lastSevenDays.seconds, 630),
      "all observed sources must report every completed day")

for invalid in [-1.0, Double.nan, Double.infinity, -Double.infinity, 100_000] {
    var bad = UsageInsightsAccumulator(now: now, calendar: calendar)
    add(&bad, -1, seconds: invalid)
    check(config(bad).reportedDays == 0 && config(bad).days[27].seconds == nil,
          "invalid duration excluded without zero placeholder")
}
var invalidBesideValid = full
add(&invalidBesideValid, -1, seconds: Double.nan)
check(config(invalidBesideValid).days[27].seconds == 60
      && !config(invalidBesideValid).days[27].isComplete
      && config(invalidBesideValid).trend == nil, "invalid same-day evidence suppresses confidence")
var clipped = UsageInsightsAccumulator(now: now, calendar: calendar)
clipped.add(source: 0, start: day(-1), end: day(-1).addingTimeInterval(3_600),
            seconds: 600, updatedAt: now)
check(config(clipped).days[27].seconds == 600 && !config(clipped).days[27].isComplete,
      "valid partial interval retained but never called complete")
var stale = full
// New separate source has old metadata before the past daily interval ended.
stale.add(source: 1, start: day(-1), end: today, seconds: 60,
          updatedAt: day(-1).addingTimeInterval(3_600))
check(!config(stale).days[27].isComplete, "lastUpdated before day end is not complete evidence")

var invalidIntervals = UsageInsightsAccumulator(now: now, calendar: calendar)
for (start, finish) in [
    (day(-1), day(-1)),
    (day(-1), end(today)),
    (day(-1).addingTimeInterval(1), today),
    (Date(timeIntervalSince1970: Double.infinity), today),
    (day(-1), Date(timeIntervalSince1970: Double.infinity))
] {
    invalidIntervals.add(source: 0, start: start, end: finish, seconds: 60, updatedAt: now)
}
check(config(invalidIntervals).reportedDays == 0, "invalid or cross-day intervals excluded")
add(&invalidIntervals, -29, seconds: 60)
add(&invalidIntervals, 1, seconds: 60)
check(config(invalidIntervals).reportedDays == 0, "outside 29-day window excluded")
add(&invalidIntervals, -1, seconds: 60, updatedAt: now.addingTimeInterval(1))
check(config(invalidIntervals).reportedDays == 0, "future update excluded")
var excessToday = UsageInsightsAccumulator(now: now, calendar: calendar)
add(&excessToday, 0, seconds: 13 * 3_600)
check(config(excessToday).today!.seconds == nil, "today duration cannot exceed elapsed day")

var zero = UsageInsightsAccumulator(now: now, calendar: calendar)
for offset in -14 ... -1 { add(&zero, offset, seconds: offset < -7 ? 0 : 60) }
let zeroConfig = config(zero)
check(zeroConfig.previousSevenDays.seconds == 0 && zeroConfig.previousSevenDays.isComplete,
      "explicit zero segments are valid reported coverage")
check(close(zeroConfig.trend?.differenceMinutes, 7) && zeroConfig.trend?.percentage == nil,
      "zero denominator gives minutes only, never infinity or percent")
for offset in -7 ... -1 {
    add(&zero, offset, seconds: 0, updatedAt: now.addingTimeInterval(-1))
}
check(close(config(zero).lastSevenDays.seconds, 420), "stale zero cannot erase current sample")
var allZero = UsageInsightsAccumulator(now: now, calendar: calendar)
for offset in -14 ... -1 { add(&allZero, offset, seconds: 0) }
check(config(allZero).trend?.differenceMinutes == 0 && config(allZero).trend?.percentage == nil,
      "zero versus zero is a zero-minute difference, not a percent")

// Calendar boundaries, not fixed 86400-second days, govern coverage.
for (month, number, hours) in [(3, 8, 23.0), (11, 1, 25.0)] {
    let dstDay = calendar.date(from: DateComponents(year: 2026, month: month, day: number))!
    let dstEnd = calendar.date(byAdding: .day, value: 1, to: dstDay)!
    let dstNow = dstEnd.addingTimeInterval(43_200)
    var dst = UsageInsightsAccumulator(now: dstNow, calendar: calendar)
    dst.add(source: 0, start: dstDay, end: dstEnd, seconds: hours * 3_600, updatedAt: dstNow)
    let matching = config(dst).days.first { $0.date == dstDay }!
    check(matching.isComplete && matching.seconds == hours * 3_600, "DST day uses real calendar duration")
    check(config(dst).weeks.last!.end == calendar.startOfDay(for: dstNow), "weekly boundary remains midnight")
}

// Baseline JSON comes only from a manual host input; it is not usage telemetry.
func baseline(_ minutes: String, recordedAt: Date) -> Data {
    Data("{\"weeklyMinutes\":\(minutes),\"recordedAt\":\(recordedAt.timeIntervalSinceReferenceDate)}".utf8)
}
let stamp = now.addingTimeInterval(-3_600)
for minutes in [0, 420, 10_080] {
    let decoded = UsageInsightsBaseline.decode(baseline(String(minutes), recordedAt: stamp), now: now)
    check(decoded?.weeklyMinutes == minutes && decoded?.recordedAt == stamp, "valid baseline preserves manual value/date")
}
for minutes in ["-1", "10081", "1.5", "\"60\"", "null", "true"] {
    check(UsageInsightsBaseline.decode(baseline(minutes, recordedAt: stamp), now: now) == nil,
          "invalid baseline minute type/range")
}
for stamp in [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: -1), now.addingTimeInterval(1)] {
    check(UsageInsightsBaseline.decode(baseline("420", recordedAt: stamp), now: now) == nil,
          "invalid baseline date")
}
for data in [Data(), Data("{}".utf8), Data("not json".utf8),
             Data("{\"weeklyMinutes\":420,\"recordedAt\":null}".utf8), Data(repeating: 32, count: 1_025)] {
    check(UsageInsightsBaseline.decode(data, now: now) == nil, "malformed or oversized baseline omitted")
}
check(UsageInsightsBaseline.decode(nil, now: now) == nil, "optional baseline missing")
check(UsageInsightsBaseline.decode(baseline("420", recordedAt: stamp),
      now: Date(timeIntervalSince1970: Double.infinity)) == nil, "invalid clock rejects baseline")
let manual = UsageInsightsBaseline.decode(baseline("420", recordedAt: stamp), now: now)!
check(full.configuration(baseline: manual).baseline?.weeklyMinutes == 420,
      "baseline retained as independent self-reported field")
check(full.configuration(baseline: manual).trend?.percentage == all.trend?.percentage,
      "manual estimate never changes measured aggregation/trend")
check(close(full.configuration(baseline: manual).baselineDifferenceMinutes, -413),
      "complete recent week can compare with a separately labelled manual estimate")
check(config(full).baselineDifferenceMinutes == nil,
      "no estimate means no estimate comparison")
var partialBaseline = UsageInsightsAccumulator(now: now, calendar: calendar)
add(&partialBaseline, -1, seconds: 60)
check(partialBaseline.configuration(baseline: manual).baselineDifferenceMinutes == nil,
      "partial measured week never compares with full manual estimate")

print("UsageInsights production algorithm checks passed: \(checks)")
'''

assert "UsageInsightsReport { configuration in" in extension
assert "nonisolated DeviceActivityReportScene" in report
assert '"app.demora.dev.usage-insights"' in report
assert '"app.demora.production.usage-insights"' in report
assert "segment.totalActivityDuration" in report
assert report.index('let now = Date()') > report.index('for await segment')
assert "case .daily = result.segmentInterval" in report
assert not re.search(r"segment\.(categories|applications)|\.appleID|\.device\.name", report)
assert "ScrollView {" in view and "maxHeight: .infinity" in view
assert "dynamicTypeSize.isAccessibilitySize" in view
assert "accessibilityElement(children: .combine)" in view
assert "accessibilityAddTraits(.isHeader)" in view
assert "insightsText(" in view
assert all(key in view for key in ["latch.language", "latch.appearance", "latch.accentColor"])
assert "Self-reported weekly baseline" in view and "not measured Screen Time or a goal" in view
assert "Shared/Localization" not in report + view + model

# Strip comments for guards so privacy documentation doesn't trigger itself.
production = "\n".join(line.split("//", 1)[0] for line in (report + view + model + presentation).splitlines())
for forbidden in [r"\bEncodable\b", r"\bCodable\b", r"\bJSONEncoder\b",
                  r"\bURLSession\b", r"\bURLRequest\b", r"\bFileManager\b",
                  r"\bNotificationCenter\b", r"\bOSLog\b", r"\bos_log\b",
                  r"\bprint\s*\(", r"\bNSLog\s*\(", r"\bLogger\b",
                  r"\bAppStorage\b", r"\.set\s*\(", r"\.write\s*\(",
                  r"\.synchronize\s*\(", r"\.removeObject\s*\("]:
    assert not re.search(forbidden, production), f"Forbidden report side effect: {forbidden}"

with tempfile.TemporaryDirectory(prefix="demora-usage-insights-") as temporary:
    work = Path(temporary)
    main = work / "main.swift"
    main.write_text(driver)
    executable = work / "usage-insights-tests"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", str(MODEL), str(main),
                    "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)

print("UsageInsights sandbox/context/accessibility source guards passed")
