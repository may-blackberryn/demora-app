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
        /// Stable display semantics; old snapshots have no style.
        var style: String? = nil
    }

    struct Pending: Codable, Equatable {
        var title: String
        var appliesAt: Date
        var direction: String? = nil
    }

    struct WakeWindow: Codable, Equatable {
        var startsAt: Date
        var endsAt: Date
    }

    struct Copy: Codable, Equatable {
        var untilFormat = "until %@"
        var nextFormat = "Next %@ · %@"
        var usedUp = "Used up today"
        // The projection does not include every permanent block. Do not claim
        // everything is unblocked when no timed window is represented.
        var nothingBlocked = "No timed rule active"
        var changesWaitHere = "Changes you make wait here."
        var wakeDue = "Good morning. Tap to wake up."
        var looser = "Looser"
        var stricter = "Stricter"
        var openDemora = "Open Demora"
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
    var copy: Copy? = nil
    /// Read-only host observation of this local day's untapped gates.
    /// Absent is unknown, not awake. The widget never reads runtime files.
    var wakeDue: [WakeWindow]? = nil

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
        }
        if let change = nextPending(at: date) {
            possibilities.append((change.title, change.appliesAt))
        }
        return possibilities.min { $0.1 < $1.1 }
    }

    func nextPending(at date: Date) -> Pending? {
        pending.filter { $0.appliesAt > date }.min { $0.appliesAt < $1.appliesAt }
    }

    func transitionDates(after date: Date, through end: Date) -> [Date] {
        let dates = windows.flatMap { [$0.startsAt, $0.endsAt] }
            + pending.map(\.appliesAt)
            + (wakeDue ?? []).flatMap { [$0.startsAt, $0.endsAt] }
        return Array(Set(dates.filter { $0 > date && $0 < end })).sorted()
    }

    #if !WIDGET_EXTENSION
    static func publish(state _: LatchState) { refresh() }

    /// Serialize projection writers separately from rule coordination. Every
    /// writer reads the latest saved bytes *inside* this lock, never a cached
    /// caller state. WidgetKit services run only after releasing the lock.
    static func refresh() {
        guard !SharedStore.simulating,
              let root = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupID) else { return }
        var changed = false
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: root.appendingPathComponent("widgetProjection.lock"),
                                       options: .forMerging, error: &error) { _ in
            changed = publishLatest()
        }
        if error == nil, changed { WidgetCenter.shared.reloadAllTimelines() }
    }

    private static func publishLatest() -> Bool {
        guard !SharedStore.simulating else { return false }
        let defaults = SharedStore.defaults
        guard !SharedStore.stateRecoveryNeeded,
              let saved = defaults.data(forKey: LatchConstants.stateKey),
              let state = try? JSONDecoder().decode(LatchState.self, from: saved),
              state.isSetUp else {
            // A recovery case cannot manufacture an empty rule set or reuse a
            // positive wake claim. Only clear our own optional display field.
            guard var old = load(), old.wakeDue != nil else { return false }
            old.wakeDue = nil
            guard let data = try? JSONEncoder().encode(old) else { return false }
            defaults.set(data, forKey: key)
            return defaults.data(forKey: key) == data
        }
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

        func recurring(_ name: String, kind: String, style: String, start: Int, end: Int,
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
                                      priority: priority, style: style))
            }
        }

        for (index, schedule) in state.schedules.enumerated() {
            recurring(schedule.name, kind: tr("Schedule"), style: "block",
                      start: schedule.startMinutes, end: schedule.endMinutes,
                      recurrence: schedule.recurrence, priority: 100 + index)
        }
        for (index, period) in state.exemptions.enumerated() {
            recurring(period.name, kind: tr("Free period"), style: "free",
                      start: period.startMinutes, end: period.endMinutes,
                      recurrence: period.recurrence, priority: 500 + index)
        }
        for (index, planned) in state.planned.enumerated() where planned.endsAt > now {
            windows.append(Window(title: planned.name,
                                  kind: planned.kind == .free
                                      ? tr("Free period") : tr("Planned window"),
                                  startsAt: planned.startsAt, endsAt: planned.endsAt,
                                  priority: planned.kind == .free ? 500 + index
                                      : 200 + index,
                                  style: planned.kind == .free ? "free" : "block"))
        }
        for (index, session) in state.sessions.enumerated() where session.endsAt > now {
            windows.append(Window(title: session.name,
                                  kind: session.kind == .free
                                      ? tr("Free period") : tr("Session"),
                                  startsAt: session.startedAt, endsAt: session.endsAt,
                                  priority: session.kind == .free ? 600 + index
                                      : 300 + index,
                                  style: session.kind == .free ? "free" : "block"))
        }
        let midnight = cal.date(byAdding: .day, value: 1, to: today) ?? now
        let blocked = SharedStore.loadBlockedLimitIDs()
        for limit in state.limits where blocked.contains(limit.id)
            || limit.minutes(on: now) == 0 {
            windows.append(Window(title: limit.name, kind: tr("Limit reached"),
                                  startsAt: today, endsAt: midnight, priority: 50, style: "spent"))
        }
        let snapshot = Self(
            windows: windows,
            pending: state.pending.map { Pending(title: $0.summary, appliesAt: $0.appliesAt,
                                                 direction: $0.direction.rawValue) }
                .sorted { $0.appliesAt < $1.appliesAt },
            savedAt: now,
            nowLabel: tr("Now"), nextLabel: tr("Next"),
            pendingLabel: tr("Changing soon"),
            noTimedRuleLabel: tr("No timed rule active"),
            noNextLabel: tr("Nothing coming up"),
            noPendingLabel: tr("No changes waiting"),
            copy: Copy(untilFormat: tr("until %@"), nextFormat: tr("Next %@ · %@"),
                       usedUp: tr("Used up today"),
                       nothingBlocked: tr("No timed rule active"),
                       changesWaitHere: tr("Changes you make wait here."),
                       wakeDue: tr("Good morning. Tap to wake up."),
                       looser: tr("Looser"), stricter: tr("Stricter"),
                       openDemora: tr("Open Demora")),
            // A reminder says the configured gate needs a tap, not that every
            // monitor is healthy. Unrelated degradation cannot imply awake.
            wakeDue: WakeWidgetProjection.windows(state: state, at: now, calendar: cal))
        // A rule save racing this projection will publish again after its
        // transaction. Never land a known-stale projection in the meantime.
        guard defaults.data(forKey: LatchConstants.stateKey) == saved,
              !SharedStore.stateRecoveryNeeded else { return false }
        if let old = load(), old.windows == snapshot.windows,
           old.pending == snapshot.pending,
           old.nowLabel == snapshot.nowLabel,
           old.nextLabel == snapshot.nextLabel,
           old.pendingLabel == snapshot.pendingLabel,
           old.noTimedRuleLabel == snapshot.noTimedRuleLabel,
           old.noNextLabel == snapshot.noNextLabel,
           old.noPendingLabel == snapshot.noPendingLabel,
           old.copy == snapshot.copy, old.wakeDue == snapshot.wakeDue {
            return false
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }
    #endif
}

#if !WIDGET_EXTENSION
/// Project only this day's gates from owning read-only APIs. No future-day tap
/// assumptions, private runtime formats, repairs, rule changes or monitor work.
enum WakeWidgetProjection {
    static func windows(state: LatchState, at now: Date,
                        calendar: Calendar) -> [DemoraWidgetSnapshot.WakeWindow]? {
        guard let day = calendar.dateInterval(of: .day, for: now) else { return nil }
        let guarded = TimeGuard.nowForDisplay(at: now)
        var windows: [DemoraWidgetSnapshot.WakeWindow] = []
        var unknown = false
        func append(startMinutes: Int, latestMinutes: Int?,
                    status: (Date) -> GlobalWakeStatus?) {
            guard (0..<1440).contains(startMinutes),
                  let start = calendar.date(bySettingHour: startMinutes / 60,
                    minute: startMinutes % 60, second: 0, of: day.start,
                    matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward),
                  let lastStart = calendar.date(bySettingHour: startMinutes / 60,
                    minute: startMinutes % 60, second: 0, of: day.start,
                    matchingPolicy: .nextTime, repeatedTimePolicy: .last, direction: .forward),
                  start == lastStart,
                  let end = WidgetPresentation.wakeExpiry(at: now,
                    latestMinutes: latestMinutes, calendar: calendar),
                  end > max(now, start) else { return }
            // Omit an ambiguous repeated-hour start: the existing engine's
            // minute predicate can become inactive during the rollback.
            // A same-day future start is safe to show only when the owning
            // reader confirms no tap/deadline for this cycle already exists.
            guard let value = status(max(now, start)) else { unknown = true; return }
            if value == .needsTap { windows.append(.init(startsAt: start, endsAt: end)) }
        }
        let global = state.wakeRule
        if global.enabled {
            append(startMinutes: global.startHour * 60, latestMinutes: global.latest(on: now)) {
                GlobalWake.statusForDisplay(state: state, at: $0, guardedNow: guarded)
            }
        }
        for group in state.dayNightGroups where group.wakeEnabled {
            let timing = group.wakeTiming(on: now)
            append(startMinutes: timing.startMinutes, latestMinutes: timing.latestMinutes) {
                DayNightWake.statusForDisplay(group: group, at: $0, guardedNow: guarded)
            }
        }
        for limit in state.limits where limit.wakeDelayMinutes != nil {
            let timing = (limit.wakeSchedule ?? LimitWakeSchedule())
                .timing(on: now, defaultWait: limit.wakeDelayMinutes ?? 0)
            append(startMinutes: timing.startMinutes, latestMinutes: timing.latestMinutes) { candidate in
                guard let value = LimitFeatures.wakeStateForDisplay(
                    for: limit, at: candidate, guardedNow: guarded) else { return nil }
                switch value {
                case .needsTap: return .needsTap
                case .waiting(let release): return .waiting(release)
                case .awake: return .awake
                case .notConfigured: return .inactive
                }
            }
        }
        guard !unknown else { return nil }
        // Identical groups need only one timeline interval.
        let unique = windows.reduce(into: [DemoraWidgetSnapshot.WakeWindow]()) { result, item in
            if !result.contains(item) { result.append(item) }
        }.sorted { $0.startsAt == $1.startsAt ? $0.endsAt < $1.endsAt : $0.startsAt < $1.startsAt }
        return unique.isEmpty ? nil : unique
    }
}
#endif

/// Pure display decisions shared with tests. No preference/state reads or
/// enforcement callbacks; wake observations never override a free period.
enum WidgetPresentation {
    enum Current: Equatable {
        case unpublished, wake, rule(DemoraWidgetSnapshot.Window), empty
    }

    static func copy(snapshot: DemoraWidgetSnapshot?) -> DemoraWidgetSnapshot.Copy {
        if let copy = snapshot?.copy { return copy }
        var fallback = DemoraWidgetSnapshot.Copy()
        if let snapshot { fallback.nothingBlocked = snapshot.noTimedRuleLabel }
        return fallback
    }

    static func current(snapshot: DemoraWidgetSnapshot?, at date: Date) -> Current {
        guard let snapshot else { return .unpublished }
        let active = snapshot.active(at: date)
        if let active, active.style == "free" { return .rule(active) }
        if (snapshot.wakeDue ?? []).contains(where: { $0.startsAt <= date && date < $0.endsAt }) {
            return .wake
        }
        return active.map(Current.rule) ?? .empty
    }

    /// Observation expires at the first concrete ceiling or next local day.
    /// No fixed 24-hour addition (DST), and no forecast of tomorrow's tap.
    static func wakeExpiry(at date: Date, latestMinutes: Int?, calendar: Calendar) -> Date? {
        guard let day = calendar.dateInterval(of: .day, for: date) else { return nil }
        guard let latestMinutes else { return day.end }
        guard (0..<1440).contains(latestMinutes),
              let ceiling = calendar.date(bySettingHour: latestMinutes / 60,
                minute: latestMinutes % 60, second: 0, of: day.start,
                matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        else { return nil }
        return min(day.end, ceiling)
    }
}

/// Bounded navigation only. Distinct schemes prevent a widget for one build
/// opening the other co-installed app. URLs contain no IDs or mutation data.
enum WidgetDestination: String, Equatable {
    case today, changes

    static var scheme: String {
        #if DEBUG
        "demora-dev"
        #else
        "demora"
        #endif
    }

    var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }

    static func parse(_ url: URL) -> Self? {
        guard url.absoluteString.utf8.count <= 80,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == scheme, let host = parts.host,
              parts.percentEncodedHost == host, parts.user == nil, parts.password == nil,
              parts.port == nil, parts.path.isEmpty, parts.query == nil, parts.fragment == nil
        else { return nil }
        return Self(rawValue: host)
    }
}
