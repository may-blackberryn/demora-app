import Foundation

#if !WIDGET_EXTENSION
import WidgetKit
#endif

/// A small, read-only projection of Demora's rules. The widget never decodes
/// FamilyControls tokens or mutates the real rule store.
struct DemoraWidgetSnapshot: Codable {
    struct Window: Codable, Equatable {
        var title: String
        var kind: String
        var startsAt: Date
        var endsAt: Date
        var priority: Int
    }

    struct Pending: Codable, Equatable {
        var title: String
        var appliesAt: Date
    }

    var windows: [Window]
    var pending: [Pending]
    var savedAt: Date
    var nowLabel: String
    var nextLabel: String
    var pendingLabel: String
    var noTimedRuleLabel: String
    var noNextLabel: String
    var noPendingLabel: String

    static let key = "latch.widgetSnapshot.v1"

    static func load() -> Self? {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    private static var groupID: String {
        #if DEBUG
        "group.com.may.screentimedelay.dev"
        #else
        "group.com.may.screentimedelay"
        #endif
    }

    func active(at date: Date) -> Window? {
        windows.filter { $0.startsAt <= date && date < $0.endsAt }
            .max { $0.priority < $1.priority }
    }

    func next(at date: Date) -> (String, Date)? {
        var possibilities: [(String, Date)] = []
        for window in windows {
            if window.startsAt > date {
                possibilities.append((window.title, window.startsAt))
            }
            if window.startsAt <= date && window.endsAt > date {
                possibilities.append((window.title, window.endsAt))
            }
        }
        if let change = pending.first(where: { $0.appliesAt > date }) {
            possibilities.append((change.title, change.appliesAt))
        }
        return possibilities.min { $0.1 < $1.1 }
    }

    func nextPending(at date: Date) -> Pending? {
        pending.first { $0.appliesAt > date }
    }

    func transitionDates(after date: Date, through end: Date) -> [Date] {
        let dates = windows.flatMap { [$0.startsAt, $0.endsAt] }
            + pending.map(\.appliesAt)
        return Array(Set(dates.filter { $0 > date && $0 < end })).sorted()
    }

    #if !WIDGET_EXTENSION
    static func publish(state: LatchState) {
        guard !SharedStore.simulating else { return }
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        var windows: [Window] = []

        func wallDate(day: Date, minute: Int) -> Date? {
            guard let targetDay = cal.date(byAdding: .day, value: minute / 1440,
                                           to: day) else { return nil }
            let clockMinute = minute % 1440
            return cal.date(bySettingHour: clockMinute / 60,
                            minute: clockMinute % 60, second: 0, of: targetDay)
        }

        func recurring(_ name: String, kind: String, start: Int, end: Int,
                       recurrence: Recurrence, priority: Int) {
            guard start != end else { return }
            // Include yesterday for an overnight window still active today.
            for offset in -1..<35 {
                guard let day = cal.date(byAdding: .day, value: offset, to: today),
                      recurrence.matches(dayOf: day),
                      let startDate = wallDate(day: day, minute: start),
                      let endDate = wallDate(day: day,
                                             minute: end + (end <= start ? 1440 : 0)),
                      endDate > now
                else { continue }
                windows.append(Window(title: name, kind: kind,
                                      startsAt: startDate, endsAt: endDate,
                                      priority: priority))
            }
        }

        for (index, schedule) in state.schedules.enumerated() {
            recurring(schedule.name, kind: tr("Schedule"),
                      start: schedule.startMinutes, end: schedule.endMinutes,
                      recurrence: schedule.recurrence, priority: 100 + index)
        }
        for (index, period) in state.exemptions.enumerated() {
            recurring(period.name, kind: tr("Free period"),
                      start: period.startMinutes, end: period.endMinutes,
                      recurrence: period.recurrence, priority: 500 + index)
        }
        for (index, planned) in state.planned.enumerated() where planned.endsAt > now {
            windows.append(Window(title: planned.name,
                                  kind: planned.kind == .free
                                      ? tr("Free period") : tr("Planned window"),
                                  startsAt: planned.startsAt, endsAt: planned.endsAt,
                                  priority: planned.kind == .free ? 500 + index
                                      : 200 + index))
        }
        for (index, session) in state.sessions.enumerated() where session.endsAt > now {
            windows.append(Window(title: session.name,
                                  kind: session.kind == .free
                                      ? tr("Free period") : tr("Session"),
                                  startsAt: session.startedAt, endsAt: session.endsAt,
                                  priority: session.kind == .free ? 600 + index
                                      : 300 + index))
        }
        let midnight = cal.date(byAdding: .day, value: 1, to: today) ?? now
        let blocked = SharedStore.loadBlockedLimitIDs()
        for limit in state.limits where blocked.contains(limit.id)
            || limit.minutes(on: now) == 0 {
            windows.append(Window(title: limit.name, kind: tr("Limit reached"),
                                  startsAt: today, endsAt: midnight, priority: 50))
        }
        let snapshot = Self(
            windows: windows,
            pending: state.pending.map { Pending(title: $0.summary, appliesAt: $0.appliesAt) }
                .sorted { $0.appliesAt < $1.appliesAt },
            savedAt: now,
            nowLabel: tr("Now"), nextLabel: tr("Next"),
            pendingLabel: tr("Pending change"),
            noTimedRuleLabel: tr("No timed rule active"),
            noNextLabel: tr("Nothing coming up"),
            noPendingLabel: tr("No pending changes"))
        if let old = load(), old.windows == snapshot.windows,
           old.pending == snapshot.pending,
           old.nowLabel == snapshot.nowLabel,
           old.nextLabel == snapshot.nextLabel,
           old.pendingLabel == snapshot.pendingLabel,
           old.noTimedRuleLabel == snapshot.noTimedRuleLabel,
           old.noNextLabel == snapshot.noNextLabel,
           old.noPendingLabel == snapshot.noPendingLabel {
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: groupID)?.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
    #endif
}
