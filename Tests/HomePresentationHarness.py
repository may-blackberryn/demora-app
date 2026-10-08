#!/usr/bin/env python3
"""Run the actual Foundation-only Home projection plus focused source guards.

No Xcode build, Screen Time query, or interactive SwiftUI rendering is performed.
Status mocks verify presentation routing, not the enforcement engine itself.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
home = (ROOT / "Latch/HomeView.swift").read_text()
host = (ROOT / "Latch/LimitsUsageReportView.swift").read_text()
report = (ROOT / "LatchReport/LimitsUsageView.swift").read_text()

projection = home.split("// MARK: - Home day projection", 1)[1].split(
    "// MARK: - Home day drawing", 1)[0]
projection = projection.split("\n", 1)[1]
# Expose file-private types to the generated test driver's top-level variables;
# the production function bodies remain unchanged.
projection = projection.replace("private ", "")
refresh = home.split("    private func refreshWakePresentation(state: LatchState) {", 1)[1]
refresh = "    func refreshWakePresentation(state: LatchState) {" + refresh.split(
    "    /// Sent requests", 1)[0]

driver = r'''
import Foundation
'''+projection+r'''

func check(_ passed: @autoclosure () -> Bool, _ label: String) {
    precondition(passed(), label)
}
func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.00001 }
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/New_York")!
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day,
                                      hour: hour, minute: minute))!
}
func interval(_ start: Date) -> DateInterval {
    DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
}
let day = interval(date(2026, 10, 6))
let spanning = HomeDayProjection.segment(name: "overnight", kind: .block,
    start: date(2026, 10, 5, 23), end: date(2026, 10, 6, 2), day: day)!
check(close(spanning.start, 0) && close(spanning.end, 2.0 / 24), "overnight clipped")
let full = HomeDayProjection.segment(name: "full", kind: .free,
    start: date(2026, 10, 5), end: date(2026, 10, 8), day: day)!
check(full.start == 0 && full.end == 1, "multi-day clipped")
check(HomeDayProjection.segment(name: "old", kind: .block,
    start: date(2026, 10, 5), end: day.start, day: day) == nil, "past excluded")
check(HomeDayProjection.segment(name: "future", kind: .block,
    start: day.end, end: date(2026, 10, 8), day: day) == nil, "next day excluded")
check(HomeDayProjection.segment(name: "bad", kind: .block,
    start: date(2026, 10, 6, 3), end: date(2026, 10, 6, 2), day: day) == nil,
    "reversed excluded")
let tap = HomeDayProjection.segment(name: "tap", kind: .wake,
    start: date(2026, 10, 6, 6), end: date(2026, 10, 6, 6), day: day, needsTap: true)!
check(tap.start == tap.end && tap.needsTap, "boundary tap point retained")
let awaiting = HomeDayProjection.segment(name: "tap", kind: .wake,
    start: date(2026, 10, 6, 6), end: date(2026, 10, 6, 9), day: day, needsTap: true)!
check(close(awaiting.end, 9.0 / 24), "unstarted gate stops now")
let wait = HomeDayProjection.segment(name: "wait", kind: .wake,
    start: date(2026, 10, 6, 23), end: date(2026, 10, 7, 2), day: day)!
check(wait.end == 1 && !wait.needsTap, "running wait clips at midnight")

let tails = HomeDayProjection.recurring(start: 22 * 60, end: 2 * 60,
    day: day, calendar: calendar,
    matches: { calendar.component(.weekday, from: $0) == 2 })
check(tails.count == 1 && tails[0].start == date(2026, 10, 5, 22)
      && tails[0].end == date(2026, 10, 6, 2), "Monday tail on Tuesday")
check(HomeDayProjection.recurring(start: 22 * 60, end: 2 * 60,
    day: day, calendar: calendar, matches: { _ in false }).isEmpty, "skipped weekday")
let daytime = HomeDayProjection.recurring(start: 10 * 60, end: 11 * 60,
    day: day, calendar: calendar, matches: { _ in true })
check(daytime.count == 1 && daytime[0].start == date(2026, 10, 6, 10), "no old daytime tail")
for (month, number, hours) in [(3, 8, 23.0), (11, 1, 25.0)] {
    let dst = interval(date(2026, month, number))
    check(dst.duration == hours * 3600, "actual DST day length")
    let evening = date(2026, month, number, 22)
    check(close(HomeDayProjection.fraction(evening, in: dst),
                evening.timeIntervalSince(dst.start) / dst.duration), "DST marker and interval share axis")
    let overnight = HomeDayProjection.recurring(start: 22 * 60, end: 6 * 60,
        day: dst, calendar: calendar, matches: { _ in true })
    check(overnight.count == 2, "DST previous tail and next evening")
}
check(HomeDayProjection.fraction(date(2026, 10, 5), in: day) == 0
      && HomeDayProjection.fraction(date(2026, 10, 8), in: day) == 1, "fraction bounded")
let wall = date(2026, 10, 6, 9), guarded = date(2026, 10, 6, 7)
check(HomeDayProjection.projectedRelease(until: guarded.addingTimeInterval(7200),
    wall: wall, guarded: guarded, latestMinutes: 600, calendar: calendar) == date(2026, 10, 6, 10),
    "earlier wall-clock ceiling")
check(HomeDayProjection.projectedRelease(until: guarded.addingTimeInterval(600),
    wall: wall, guarded: guarded, latestMinutes: 600, calendar: calendar) == date(2026, 10, 6, 9, 10),
    "earlier guarded wait")
check(HomeDayProjection.projectedRelease(until: guarded.addingTimeInterval(7200),
    wall: wall, guarded: guarded, latestMinutes: nil, calendar: calendar) == date(2026, 10, 6, 11),
    "legacy nil ceiling preserves wait")

// Match only the APIs consumed by the actual event-side snapshot function.
enum GlobalWakeStatus { case inactive, needsTap, waiting(Date), awake }
enum WakeState { case notConfigured, needsTap, waiting(Date), awake }
struct Timing { var startMinutes: Int; var latestMinutes: Int? = nil }
struct Group {
    var id = UUID(); var name: String; var start: Int; var status: GlobalWakeStatus
    func wakeTiming(on date: Date) -> Timing { Timing(startMinutes: start) }
}
struct LimitWakeSchedule {
    var startMinutes = 0
    func timing(on date: Date, defaultWait: Int) -> Timing { Timing(startMinutes: startMinutes) }
}
struct Limit {
    var id = UUID(); var name: String; var wakeDelayMinutes: Int?
    var wakeSchedule: LimitWakeSchedule?; var status: WakeState
}
struct WakeRule {
    var startHour = 6; var latestMinutes: Int? = nil
    func latest(on date: Date) -> Int? { latestMinutes }
}
struct LatchState {
    var wakeRule = WakeRule(); var dayNightGroups: [Group] = []; var limits: [Limit] = []
}
enum TimeGuard { static var clock = Date().addingTimeInterval(-7200); static func now() -> Date { clock } }
enum GlobalWake {
    static var value = GlobalWakeStatus.inactive
    static var reads = 0
    static func status(state: LatchState, at date: Date) -> GlobalWakeStatus { reads += 1; return value }
}
enum DayNightWake {
    static func status(group: Group, at date: Date, guardedNow: Date) -> GlobalWakeStatus { group.status }
}
enum LimitFeatures {
    static func wakeState(for limit: Limit, at date: Date, guardedNow: Date) -> WakeState { limit.status }
}
func tr(_ text: String) -> String { text }
final class Model { var inTutorial = false }
final class Snapshot {
    var model = Model()
    var wakePresentation: [HomeWakePresentation] = []
'''+refresh+r'''
}
let snapshot = Snapshot()
var state = LatchState()
GlobalWake.value = .needsTap
state.dayNightGroups = [
    Group(name: "running", start: 1200, status: .waiting(TimeGuard.clock.addingTimeInterval(600))),
    Group(name: "future", start: 1200, status: .inactive),
    Group(name: "done", start: 0, status: .awake)]
state.limits = [
    Limit(name: "legacy", wakeDelayMinutes: 999, wakeSchedule: nil,
          status: .waiting(TimeGuard.clock.addingTimeInterval(300))),
    Limit(name: "tap", wakeDelayMinutes: 5, wakeSchedule: LimitWakeSchedule(startMinutes: 360),
          status: .needsTap),
    Limit(name: "off", wakeDelayMinutes: nil, wakeSchedule: nil, status: .notConfigured)]
let before = Date()
snapshot.refreshWakePresentation(state: state)
check(snapshot.wakePresentation.count == 4, "global/new/legacy eligible gates only")
check(snapshot.wakePresentation.filter { $0.wallRelease == nil }.count == 2,
      "needsTap has no projected release")
for (name, seconds) in [("running", 600.0), ("legacy", 300.0)] {
    let release = snapshot.wakePresentation.first { $0.name == name }!.wallRelease!
    check(abs(release.timeIntervalSince(before) - seconds) < 2,
          "guarded remaining wait, not current configured wait")
}
snapshot.model.inTutorial = true
let reads = GlobalWake.reads
snapshot.refreshWakePresentation(state: state)
check(snapshot.wakePresentation.isEmpty && GlobalWake.reads == reads, "tutorial avoids real status")
print("Home projection passed: day clipping, points, recurring anchors, DST, guarded waits/ceiling projection, tutorial isolation")
'''

with tempfile.TemporaryDirectory(prefix="demora-home-presentation-") as directory:
    source = Path(directory) / "HomeProjection.swift"
    binary = Path(directory) / "HomeProjection"
    source.write_text(driver)
    subprocess.run(["swiftc", str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

home_view = home.split("struct HomeView: View", 1)[1].split(
    "    /// Status helpers", 1)[0]
# Event callbacks may invoke the snapshot function; body evaluation does not
# invoke helpers that can repair preferences or read guarded clock anchors.
for forbidden in ("GlobalWake.status(", "DayNightWake.status(",
                  "ChangeEngine.wakeState(", "LimitFeatures.wakeState(", "TimeGuard.now()"):
    assert forbidden not in home_view, forbidden
assert "await ChangeEngine.wakeUpAllOffMain()" in home_view
assert ".buttonStyle(.plain).disabled(startingWake)" in home_view
assert "minHeight: 116" in home_view and '.font(.system(.largeTitle, design: .serif))' in home_view
assert "if model.inTutorial {\n                                DemoraDayLine" in home_view
assert "CompactHomeUsageReport(limitCount:" in home_view
assert all(token in home_view for token in ("model.tutorial == .applyBoth",
    "model.tutorial == .applyViaContact", "frozenRemaining:", "syncApplyBar()"))

for forbidden in (".id(", "showReport", "reportID", "DispatchQueue", "Timer.publish",
                  "usedMinutes", "usedSeconds", "makeConfiguration", "NotificationCenter"):
    assert forbidden not in host, forbidden
assert "min(480, expandedHeight)" in host and "min(240, compactHeight" in host
assert "limitCount) *" not in host  # no unlimited row-count reservation
assert "expanded.toggle()" in host and "refreshedAt.addingTimeInterval(0.001)" in host
assert "an empty report does not mean zero usage" in host
assert '"app.demora.dev.limits-usage"' in host
assert '"app.demora.production.limits-usage"' in host
assert "ScrollView { reportContent }" in report
assert "alignment: .topLeading" in report
assert "Spacer()" in report  # horizontal label spacer remains
assert ".frame(height: 10)" in report  # bounded progress GeometryReader
assert "let shown = max(0, r.usedMinutes)" in report
for forbidden in (".set(", "removeObject", "NotificationCenter", "FileManager",
                  "PreferenceKey", ".onAppear", ".task"):
    assert forbidden not in report, forbidden
print("Home/report source guards passed: centered wake action, tutorial routing, bounded viewport, stable refresh identity, no report-side writes or usage export")
