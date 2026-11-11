#!/usr/bin/env python3
"""Run the actual Foundation-only Home projection plus focused source guards.

No Xcode build, Screen Time query, or interactive SwiftUI rendering is performed.
Status mocks verify presentation routing, not the enforcement engine itself.
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


home = (ROOT / "Latch/HomeView.swift").read_text()
host = (ROOT / "Latch/LimitsUsageReportView.swift").read_text()
report = (ROOT / "LatchReport/LimitsUsageView.swift").read_text()

projection = home.split("// MARK: - Home day projection", 1)[1].split(
    "// MARK: - Today's items", 1)[0]
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
    let overnight = HomeDayProjection.recurring(start: 22 * 60, end: 6 * 60,
        day: dst, calendar: calendar, matches: { _ in true })
    check(overnight.count == 2, "DST previous tail and next evening")
}
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
struct Timing { var startMinutes: Int; var waitMinutes = 0; var latestMinutes: Int? = nil }
struct Group {
    var id = UUID(); var name: String; var start: Int; var status: GlobalWakeStatus
    func wakeTiming(on date: Date) -> Timing { Timing(startMinutes: start, waitMinutes: 45) }
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
    var startHour = 6; var waitMinutes = 120; var latestMinutes: Int? = nil
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
final class Snapshot {
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
check(snapshot.wakePresentation.first { $0.id == "global" }?.waitMinutes == 120,
      "the wait a tap starts reaches the Now card")
check(snapshot.wakePresentation.first { $0.name == "running" }?.waitMinutes == 45,
      "group wait from its timing for the day")
for (name, seconds) in [("running", 600.0), ("legacy", 300.0)] {
    let release = snapshot.wakePresentation.first { $0.name == name }!.wallRelease!
    check(abs(release.timeIntervalSince(before) - seconds) < 2,
          "guarded remaining wait, not current configured wait")
}
let reads = GlobalWake.reads
snapshot.refreshWakePresentation(state: state)
check(snapshot.wakePresentation.count == 4 && GlobalWake.reads == reads + 1,
      "a normal event refresh re-reads status without tutorial gating")
GlobalWake.value = .awake
state.dayNightGroups = []
state.limits = []
snapshot.refreshWakePresentation(state: state)
check(snapshot.wakePresentation.isEmpty && GlobalWake.reads == reads + 2,
      "a later released/removed gate does not leave a stale snapshot")
print("Home projection passed: recurring anchors, DST, guarded waits/ceiling projection, wake waits, event refresh replaces stale gates")
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
assert "startingWake: startingWake" in home_view and "onWakeUp: wakeUp" in home_view
today_view = (ROOT / "Latch/TodayView.swift").read_text()
now_card = today_view.split("struct NowCard: View {", 1)[1].split("\n}\n", 1)[0]
assert "if summary.action == .wakeUp {" in now_card and ".disabled(startingWake)" in now_card
for retired in ("inTutorial", "legacyHome", "PendingChangeRow(", "tutorialRemaining",
                "frozenRemaining:", "syncApplyBar()", "applyBarVisible", "moreLinks"):
    assert retired not in home, ("retired Home path", retired)
assert "NavigationStack(path: $todayPath)" in home_view
assert "private enum TodayRoute: Hashable { case changes }" in home_view
assert "ChangeRow(" in home_view and "onCancel: { model.cancel(change) }" in home_view
assert "onOverride: { skipTarget = .changes([change]) }" in home_view
assert "onDebugApply: { model.applyNow(change) }" in home_view
assert "onOpenRequest: { openRequest(waiting) }" in home_view
assert "CompactHomeUsageReport(limits:" in home_view

# Today owns a cancellable poll only while it is the visible, active tab.
# Root's retained hierarchy/badge lifetime is tested by the lead's harness.
visible = block(home, "private var inboxVisible: Bool")
assert "model.selectedTab == 0 && scenePhase == .active" in visible
poll = block(home, ".task(id: inboxVisible)")
assert "guard inboxVisible else { return }" in poll
assert "while !Task.isCancelled" in poll
assert poll.index("await loadInbox()") < poll.index("guard !Task.isCancelled, inboxVisible") \
    < poll.index("loadOutgoing()") < poll.index("try await Task.sleep(nanoseconds: 30_000_000_000)")
assert "catch {\n                        return" in poll, "cancellation exits without retrying"
assert home.count(".task(id: inboxVisible)") == 1
loader = block(home, "private func loadInbox() async")
assert loader.count("guard !Task.isCancelled, inboxVisible else { return }") == 2
assert loader.index("inbox = incoming") < loader.index("onInboxCountChanged(inbox.count)")
failed_load = loader.split("} catch {", 1)[1]
assert "inbox =" not in failed_load and "onInboxCountChanged(" not in failed_load
respond = block(home, "private func respond(to request:")
assert respond.index("try await ContactsRelay.respond") < respond.index("inbox.removeAll") \
    < respond.index("onInboxCountChanged(inbox.count)")
assert "inbox.removeAll" not in respond.split("} catch {", 1)[1], "failed response keeps the request"

# Execute the real visibility predicate and inbox loader with a controllable
# in-memory relay. Suspended responses are resumed explicitly: no live network,
# polling delays, defaults, tokens, or SwiftUI rendering enter this fixture.
inbox_driver = r'''
import Foundation
struct IncomingRequest: Equatable { let id: Int }
enum ScenePhase { case active, inactive, background }
final class Model { var selectedTab = 0 }
enum FixtureError: Error { case offline }
@MainActor enum ContactsRelay {
    enum Mode { case success, failure, suspended }
    static var mode = Mode.success
    static var incoming = [IncomingRequest(id: 1), IncomingRequest(id: 2)]
    static var calls = 0
    static var onFetch: (() -> Void)?
    static var response: CheckedContinuation<[IncomingRequest], Error>?
    static func pendingRequestsForMe() async throws -> [IncomingRequest] {
        calls += 1
        switch mode {
        case .success: return incoming
        case .failure: throw FixtureError.offline
        case .suspended:
            return try await withCheckedThrowingContinuation { continuation in
                response = continuation
                let started = onFetch
                onFetch = nil
                started?()
            }
        }
    }
}
@MainActor final class InboxSnapshot {
    let model = Model()
    var scenePhase = ScenePhase.active
    var inbox: [IncomingRequest] = []
    var callbacks: [Int] = []
    func onInboxCountChanged(_ count: Int) { callbacks.append(count) }
    func loadForTest() async { await loadInbox() }
''' + visible + "\n" + loader + r'''
}
@main struct InboxChecks {
    @MainActor static func main() async {
        var checks = 0
        func check(_ ok: @autoclosure () -> Bool, _ message: String) {
            precondition(ok(), message)
            checks += 1
        }
        let snapshot = InboxSnapshot()
        snapshot.model.selectedTab = 1
        await snapshot.loadForTest()
        check(ContactsRelay.calls == 0 && snapshot.callbacks.isEmpty, "hidden tab does not fetch")
        snapshot.model.selectedTab = 0
        for phase in [ScenePhase.inactive, .background] {
            snapshot.scenePhase = phase
            await snapshot.loadForTest()
            check(ContactsRelay.calls == 0 && snapshot.callbacks.isEmpty, "inactive scene does not fetch")
        }
        snapshot.scenePhase = .active
        await snapshot.loadForTest()
        check(snapshot.inbox == ContactsRelay.incoming && snapshot.callbacks == [2],
              "visible success publishes rows and exactly one count")
        ContactsRelay.mode = .failure
        await snapshot.loadForTest()
        check(snapshot.inbox.count == 2 && snapshot.callbacks == [2],
              "transient error retains rows and badge")
        let calls = ContactsRelay.calls
        let cancelled = Task { await snapshot.loadForTest() }
        cancelled.cancel()
        await cancelled.value
        check(ContactsRelay.calls == calls && snapshot.callbacks == [2],
              "cancelled task does not begin a fetch")

        for interruption in ["tab", "background", "cancel"] {
            ContactsRelay.mode = .suspended
            var pending: Task<Void, Never>?
            await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
                ContactsRelay.onFetch = { started.resume() }
                pending = Task { await snapshot.loadForTest() }
            }
            if interruption == "tab" { snapshot.model.selectedTab = 2 }
            if interruption == "background" { snapshot.scenePhase = .background }
            if interruption == "cancel" { pending!.cancel() }
            let response = ContactsRelay.response!
            ContactsRelay.response = nil
            response.resume(returning: [])
            await pending!.value
            check(snapshot.inbox.count == 2 && snapshot.callbacks == [2],
                  "late response after \(interruption) cannot publish stale rows/count")
            snapshot.model.selectedTab = 0
            snapshot.scenePhase = .active
        }
        ContactsRelay.mode = .success
        ContactsRelay.incoming = []
        await snapshot.loadForTest()
        check(snapshot.inbox.isEmpty && snapshot.callbacks == [2, 0],
              "a successful empty inbox publishes zero rather than retaining a stale badge")
        check(ContactsRelay.response == nil && ContactsRelay.onFetch == nil,
              "all synthetic continuations finished")
        print("Home inbox passed: \(checks) checks — visible/active reads, errors, cancellation, late response fences, exact count callbacks")
    }
}
'''
with tempfile.TemporaryDirectory(prefix="demora-home-inbox-") as directory:
    source = Path(directory) / "Inbox.swift"
    binary = Path(directory) / "Inbox"
    source.write_text(inbox_driver)
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", str(source),
                    "-o", str(binary)], check=True, timeout=60)
    subprocess.run([str(binary)], check=True, timeout=15)

for forbidden in (".id(", "showReport", "reportID", "DispatchQueue", "Timer.publish",
                  "usedMinutes", "usedSeconds", "makeConfiguration", "NotificationCenter"):
    assert forbidden not in host, forbidden
assert "min(480, expandedHeight)" in host and "min(240, compactHeight" in host
assert "limitCount) *" not in host  # no unlimited row-count reservation
assert "expanded.toggle()" in host and "refreshedAt = Date()" in host
assert "HomeReportRefreshPolicy" in host and ".task(id: refreshRequest)" in host
assert "queryLimits = model.state.limits" in host
assert "an empty report does not mean zero usage" in host
assert '"app.demora.dev.limits-usage"' in host
assert '"app.demora.production.limits-usage"' in host
assert "ScrollView { reportContent }" in report
assert "alignment: .topLeading" in report
assert "Spacer()" in report  # horizontal label spacer remains
assert ".frame(height: 6)" in report  # bounded 6-pt bar GeometryReader (Today §5.5)
assert "let shown = max(0, r.usedMinutes)" in report
for forbidden in (".set(", "removeObject", "NotificationCenter", "FileManager",
                  "PreferenceKey", ".onAppear", ".task"):
    assert forbidden not in report, forbidden
print("Home/report source guards passed: Today-only routing, visible cancellable inbox poll/count callbacks, bounded viewport, stable refresh identity, no report-side writes or usage export")
