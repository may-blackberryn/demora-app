import Foundation
import UserNotifications

/// Notification preferences live in the App Group because threshold warnings
/// arrive in the DeviceActivity monitor, not in the foreground app.
enum DemoraNotifications {
    private static let limitKey = "latch.notifications.limitFiveMinutes.v1"
    private static let freeKey = "latch.notifications.freeBoundary.v1"
    private static let freeIDsKey = "latch.notifications.freeBoundaryIDs.v1"
    private static let freeFingerprintKey = "latch.notifications.freeBoundaryFingerprint.v1"
    private static let warnedLimitsKey = "latch.notifications.warnedLimits.v1"

    static var limitWarningsEnabled: Bool {
        get { SharedStore.defaults.object(forKey: limitKey) as? Bool ?? true }
        set { SharedStore.defaults.set(newValue, forKey: limitKey) }
    }

    static var freeBoundaryWarningsEnabled: Bool {
        get { SharedStore.defaults.bool(forKey: freeKey) }
        set { SharedStore.defaults.set(newValue, forKey: freeKey) }
    }

    /// Called only by iOS's warning for the actual per-limit usage event.
    /// Never estimates Screen Time usage in the app or a widget.
    static func limitAlmostSpent(id: UUID) {
        guard limitWarningsEnabled, !SharedStore.simulating,
              SharedStore.freeWindowStart == nil,
              !ChangeEngine.isFreeWindowActive(),
              !SharedStore.loadBlockedLimitIDs().contains(id),
              let limit = SharedStore.loadState().limits.first(where: { $0.id == id }),
              limit.minutes(on: Date()) > 5
        else { return }

        let today = SharedStore.dayKey(for: Date())
        var warned = SharedStore.defaults.dictionary(forKey: warnedLimitsKey)
            as? [String: String] ?? [:]
        guard warned[id.uuidString] != today else { return }
        warned = warned.filter { $0.value == today }
        warned[id.uuidString] = today
        SharedStore.defaults.set(warned, forKey: warnedLimitsKey)

        let content = UNMutableNotificationContent()
        content.title = tr("5 minutes left")
        content.body = String(format: tr("About 5 minutes remain for %@ today."),
                              limit.name)
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "limit-five-\(today)-\(id.uuidString)",
            content: content, trigger: nil))
    }

    /// Keep a bounded rolling set of notifications for *actual* free-period
    /// boundaries. DeviceActivity's interval warnings may describe padded or
    /// split intervals, so they are not suitable for user-facing times.
    static func rescheduleFreeBoundaries(state: LatchState) {
        let center = UNUserNotificationCenter.current()
        let oldIDs = SharedStore.defaults.stringArray(forKey: freeIDsKey) ?? []
        guard freeBoundaryWarningsEnabled, !SharedStore.simulating, state.isSetUp else {
            if !oldIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: oldIDs)
            }
            SharedStore.defaults.set([String](), forKey: freeIDsKey)
            SharedStore.defaults.removeObject(forKey: freeFingerprintKey)
            return
        }

        let now = Date()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let horizon = cal.date(byAdding: .day, value: 62, to: today) ?? now
        typealias Candidate = (id: String, fire: Date, name: String,
                               starts: Bool, repeats: Bool, weekly: Bool)
        var recurring: [Candidate] = []
        var oneOff: [Candidate] = []
        var seenRepeating = Set<String>()

        func wallDate(day: Date, minute: Int) -> Date? {
            guard let targetDay = cal.date(byAdding: .day, value: minute / 1440,
                                           to: day) else { return nil }
            let clockMinute = minute % 1440
            return cal.date(bySettingHour: clockMinute / 60,
                            minute: clockMinute % 60, second: 0, of: targetDay)
        }

        func add(_ id: String, _ boundary: Date, _ name: String,
                 starts: Bool, repeats: Bool = false, weekly: Bool = false) {
            let fire = boundary.addingTimeInterval(-5 * 60)
            guard fire > now.addingTimeInterval(20), fire < horizon else { return }
            let key = "free-five-\(id)"
            if repeats {
                guard seenRepeating.insert(key).inserted else { return }
                recurring.append((key, fire, name, starts, true, weekly))
            } else {
                oneOff.append(("\(key)-\(Int(boundary.timeIntervalSince1970))",
                               fire, name, starts, false, false))
            }
        }

        for period in state.exemptions where period.startMinutes != period.endMinutes {
            let repeats: Bool
            let weekly: Bool
            switch period.recurrence {
            case .daily: repeats = true; weekly = false
            case .weekly: repeats = true; weekly = true
            case .monthlyDay, .monthlyOrdinal: repeats = false; weekly = false
            }
            for offset in 0..<(repeats ? 8 : 62) {
                guard let day = cal.date(byAdding: .day, value: offset, to: today),
                      period.recurrence.matches(dayOf: day),
                      let start = wallDate(day: day, minute: period.startMinutes),
                      let end = wallDate(day: day, minute: period.endMinutes
                          + (period.endMinutes <= period.startMinutes ? 1440 : 0))
                else { continue }
                let dayTag = weekly ? "-w\(cal.component(.weekday, from: day))" : ""
                add(period.id.uuidString + "-start" + dayTag,
                    start, period.name, starts: true,
                    repeats: repeats, weekly: weekly)
                add(period.id.uuidString + "-end" + dayTag,
                    end, period.name, starts: false,
                    repeats: repeats, weekly: weekly)
            }
        }
        for window in state.planned where window.kind == .free {
            add(window.id.uuidString + "-start", window.startsAt, window.name, starts: true)
            add(window.id.uuidString + "-end", window.endsAt, window.name, starts: false)
        }
        for session in state.sessions where session.kind == .free {
            add(session.id.uuidString + "-end", session.endsAt, session.name, starts: false)
        }

        // iOS keeps at most 64 pending local notifications per app. Leave room
        // for pending-change alerts and the midnight-reset nudge.
        let selected = Array(recurring.sorted { $0.fire < $1.fire }.prefix(24))
            + Array(oneOff.sorted { $0.fire < $1.fire }
                .prefix(max(0, 24 - recurring.count)))
        let fingerprint = ([AppLanguage.current.rawValue, TimeZone.current.identifier]
            + selected.map { "\($0.id)|\($0.fire.timeIntervalSince1970)|\($0.name)|\($0.starts)" })
            .joined(separator: "\n")
        guard SharedStore.defaults.string(forKey: freeFingerprintKey) != fingerprint else {
            return
        }
        if !oldIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: oldIDs)
        }
        SharedStore.defaults.set(selected.map(\.id), forKey: freeIDsKey)
        SharedStore.defaults.set(fingerprint, forKey: freeFingerprintKey)
        for item in selected {
            let content = UNMutableNotificationContent()
            content.title = item.starts ? tr("Free period starts in 5 minutes")
                                        : tr("Free period ends in 5 minutes")
            content.body = item.name
            content.sound = .default
            let components: DateComponents
            if item.repeats {
                components = cal.dateComponents(item.weekly
                    ? [.weekday, .hour, .minute] : [.hour, .minute],
                    from: item.fire)
            } else {
                components = cal.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: item.fire)
            }
            center.add(UNNotificationRequest(
                identifier: item.id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components,
                                                       repeats: item.repeats)))
        }
    }
}
