// Actual snapshot/presentation code is compiled with WIDGET_EXTENSION in both
// Debug and Release. Synthetic dates only: never call snapshot.load().
import Foundation

@main
struct WidgetPresentationChecks {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
            checks += 1
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func window(_ title: String, _ priority: Int, _ style: String?,
                    start: Double = -60, end: Double = 600) -> DemoraWidgetSnapshot.Window {
            .init(title: title, kind: "Synthetic", startsAt: now.addingTimeInterval(start),
                  endsAt: now.addingTimeInterval(end), priority: priority, style: style)
        }
        var snapshot = DemoraWidgetSnapshot(windows: [], pending: [], savedAt: now,
            nowLabel: "Now", nextLabel: "Next", pendingLabel: "Changing soon",
            noTimedRuleLabel: "No timed rule active", noNextLabel: "Nothing coming up",
            noPendingLabel: "No changes waiting")
        check(WidgetPresentation.current(snapshot: nil, at: now) == .unpublished, "fresh install")
        check(WidgetPresentation.current(snapshot: snapshot, at: now) == .empty, "empty projection")
        check(WidgetPresentation.copy(snapshot: nil).nothingBlocked == "No timed rule active", "no unsupported global-unblock claim")
        let block = window("Evening", 100, "block")
        let spent = window("Games", 50, "spent")
        let free = window("Lunch", 600, "free")
        snapshot.windows = [block, spent]
        check(snapshot.active(at: now) == block, "overlap priority")
        snapshot.windows.append(window("Reading", 300, "block", start: 1200, end: 1800))
        check(snapshot.next(at: now)?.0 == "Reading", "next starts a new rule, not duplicate current end")
        snapshot.windows.removeLast()
        check(snapshot.next(at: now) == nil, "current until is already displayed")
        check(WidgetPresentation.current(snapshot: snapshot, at: now) == .rule(block), "current rule")
        snapshot.wakeDue = [.init(startsAt: now, endsAt: now.addingTimeInterval(300))]
        check(WidgetPresentation.current(snapshot: snapshot, at: now) == .wake, "wake at boundary")
        check(WidgetPresentation.current(snapshot: snapshot, at: now.addingTimeInterval(-1)) == .rule(block), "future wake not due")
        check(WidgetPresentation.current(snapshot: snapshot, at: now.addingTimeInterval(300)) == .rule(block), "wake expires")
        snapshot.windows.append(free)
        check(WidgetPresentation.current(snapshot: snapshot, at: now) == .rule(free), "free beats wake")
        snapshot.windows = [spent]; snapshot.wakeDue = nil
        check(WidgetPresentation.current(snapshot: snapshot, at: now) == .rule(spent), "spent is not fabricated minutes")
        snapshot.windows = [window("Ends now", 100, "block", end: 0)]
        check(snapshot.active(at: now) == nil, "exclusive end")
        snapshot.windows = [window("Starts now", 100, "block", start: 0)]
        check(snapshot.active(at: now)?.title == "Starts now", "inclusive start")
        snapshot.pending = (1...50).reversed().map { offset in
            .init(title: "Change \(offset)", appliesAt: now.addingTimeInterval(Double(offset * 60)),
                  direction: offset.isMultiple(of: 2) ? "stricter" : "lenient")
        }
        check(snapshot.nextPending(at: now)?.title == "Change 1", "unsorted fifty changes")
        check(snapshot.next(at: now)?.1 == now.addingTimeInterval(60), "next includes pending")
        snapshot.pending.insert(.init(title: "Due", appliesAt: now), at: 0)
        check(snapshot.nextPending(at: now)?.title == "Change 1", "due deadline not a negative timer")
        snapshot.wakeDue = [.init(startsAt: now.addingTimeInterval(60), endsAt: now.addingTimeInterval(90))]
        let transitions = snapshot.transitionDates(after: now, through: now.addingTimeInterval(120))
        check(transitions == [now.addingTimeInterval(60), now.addingTimeInterval(90)], "unique bounded transitions include wake")

        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        legacy.removeValue(forKey: "copy"); legacy.removeValue(forKey: "wakeDue")
        legacy["windows"] = (legacy["windows"] as! [[String: Any]]).map { row in
            var row = row; row.removeValue(forKey: "style"); return row
        }
        legacy["pending"] = (legacy["pending"] as! [[String: Any]]).map { row in
            var row = row; row.removeValue(forKey: "direction"); return row
        }
        let decoded = try JSONDecoder().decode(DemoraWidgetSnapshot.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        check(decoded.copy == nil && decoded.wakeDue == nil, "legacy optional projection fields")
        check(decoded.windows.first?.style == nil, "legacy style absent")
        check(decoded.pending.allSatisfy { $0.direction == nil }, "legacy directions absent, no guessed chip")
        check(WidgetPresentation.current(snapshot: decoded, at: now) != .wake, "no invented legacy wake status")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        for (month, day, hours) in [(3, 8, 23), (11, 1, 25)] {
            let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 0))!
            let expiry = WidgetPresentation.wakeExpiry(at: date, latestMinutes: nil, calendar: calendar)!
            check(Int(expiry.timeIntervalSince(date)) == hours * 3600, "calendar midnight respects DST")
            check(calendar.component(.hour, from: expiry) == 0, "ends at midnight")
        }
        let repeatedDay = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let ceiling = WidgetPresentation.wakeExpiry(at: repeatedDay, latestMinutes: 90, calendar: calendar)!
        check(ceiling.timeIntervalSince(repeatedDay) == 90 * 60, "first repeated ceiling occurrence")
        check(WidgetPresentation.wakeExpiry(at: now, latestMinutes: -1, calendar: calendar) == nil, "invalid ceiling not extended")

        for route in [WidgetDestination.today, .changes] {
            check(WidgetDestination.parse(route.url) == route, "own scheme roundtrip")
        }
        #if DEBUG
        let otherScheme = "demora"
        check(WidgetDestination.scheme == "demora-dev", "development scheme")
        #else
        let otherScheme = "demora-dev"
        check(WidgetDestination.scheme == "demora", "production scheme")
        #endif
        for bad in ["\(otherScheme)://today", "https://today", "\(WidgetDestination.scheme)://apply",
                    "\(WidgetDestination.scheme)://changes?id=123", "\(WidgetDestination.scheme)://today#skip",
                    "\(WidgetDestination.scheme)://today/path", "\(WidgetDestination.scheme)://me@today",
                    "\(WidgetDestination.scheme)://today:42", "\(WidgetDestination.scheme)://%74oday"] {
            if let url = URL(string: bad) { check(WidgetDestination.parse(url) == nil, "reject nonnavigation input") }
        }
        print("Widget snapshot/display checks passed: \(checks)")
    }
}
