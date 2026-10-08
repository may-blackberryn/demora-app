import Foundation
import DeviceActivity

/// One user action, independent persisted deadlines. Only elapsed waits use
/// TimeGuard; calendar boundaries and DeviceActivity use local wall time.
enum DayNightWake {
    struct Entry: Codable, Equatable {
        var day: String
        var epoch: UUID
        var release: Date
    }
    private static let key = "latch.dayNightWake.entries.v1"
    private static let prefix = "day-night-release-"
    private static let projectionKey = "latch.dayNightWake.projection.v1"
    private struct Projection: Codable {
        var wallRelease: Date
        var zone: String
        var calendar: String
    }

    static func status(group: DayNightGroup, at date: Date = Date(),
                       guardedNow: Date = TimeGuard.now()) -> GlobalWakeStatus {
        guard group.wakeEnabled else { return .inactive }
        // A deliberate, delay-gated calendar ceiling ends only this wake gate,
        // including an already-running wait. It never clears usage or sleep.
        if group.wakeTiming(on: date).ceilingReached(on: date) { return .awake }
        if let entries = loadEntries(), let entry = entries[group.id.uuidString],
           entry.day == cycle(group: group, at: date), entry.epoch == group.wakeEpoch {
            // Moving a start or removing today's weekday cannot shorten a wait.
            if guardedNow < entry.release { return .waiting(entry.release) }
            return .awake
        }
        let clock = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard group.weekdays.contains(Calendar.current.component(.weekday, from: date)),
              (clock.hour ?? 0) * 60 + (clock.minute ?? 0) >= group.wakeTiming(on: date).startMinutes
        else { return .inactive }
        return .needsTap
    }

    static func cycle(group: DayNightGroup, at date: Date) -> String {
        // Editing a boundary hour must not discard today's existing wait.
        // Re-enabling a gate uses a fresh epoch instead of changing its cycle.
        SharedStore.dayKey(for: date)
    }

    private static func loadEntries() -> [String: Entry]? {
        guard let data = SharedStore.defaults.data(forKey: key) else { return [:] }
        guard let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            // Preserve the unreadable data and the block, but don't leave a
            // nonfunctional wake action without a visible enforcement warning.
            SharedStore.enforcementDegraded = true
            return nil
        }
        return entries
    }

    @discardableResult
    static func tapAll() -> Bool {
        guard !SharedStore.simulating, !SharedStore.stateRecoveryNeeded else { return false }
        let saved = SharedStore.coordinateStateMutation {
            let state = SharedStore.loadState()
            guard !SharedStore.stateRecoveryNeeded, var entries = loadEntries() else { return false }
            let wall = Date(), guarded = TimeGuard.now()
            var changed = false
            for group in state.dayNightGroups {
                guard status(group: group, at: wall, guardedNow: guarded) == .needsTap else { continue }
                entries[group.id.uuidString] = Entry(day: cycle(group: group, at: wall),
                    epoch: group.wakeEpoch,
                    release: guarded.addingTimeInterval(TimeInterval(group.wakeTiming(on: wall).waitMinutes) * 60))
                changed = true
            }
            guard changed else { return false }
            entries = entries.filter { pair in
                state.dayNightGroups.contains { $0.id.uuidString == pair.key }
            }
            guard let data = try? JSONEncoder().encode(entries) else { return false }
            SharedStore.defaults.set(data, forKey: key)
            return SharedStore.defaults.data(forKey: key) == data
        } ?? false
        if saved { reconcile(state: SharedStore.loadState()) }
        return saved
    }

    static func boundaryMinutes(state: LatchState) -> Set<Int> {
        MonitoringBudget.dayNightBoundaryMinutes(state: state)
    }

    /// Consume a delivered one-shot before reconciling. A premature callback
    /// must be able to rearm the same guarded deadline, not reuse its stale name.
    static func receivedActivity(_ raw: String) {
        guard !SharedStore.simulating, raw.hasPrefix(prefix) else { return }
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(raw)])
        SharedStore.defaults.removeObject(forKey: projectionKey)
    }

    /// One release monitor for the earliest outstanding wait, not one/group.
    /// Callback reconciliation advances to the next distinct deadline.
    static func reconcile(state: LatchState, running: Set<String>? = nil) {
        guard !SharedStore.simulating else { return }
        let center = DeviceActivityCenter()
        let current = (running ?? Set(center.activities.map(\.rawValue)))
            .filter { $0.hasPrefix(prefix) }
        let releases = state.dayNightGroups.compactMap { group -> Date? in
            if case .waiting(let release) = status(group: group) { return release }
            return nil
        }
        guard let release = releases.min() else {
            if !current.isEmpty { center.stopMonitoring(current.map { DeviceActivityName($0) }) }
            SharedStore.defaults.removeObject(forKey: projectionKey)
            return
        }
        let name = prefix + String(Int(release.timeIntervalSince1970))
        let calendar = Calendar.current
        let wallRelease = Date().addingTimeInterval(max(0, release.timeIntervalSince(TimeGuard.now())))
        let projection = Projection(wallRelease: wallRelease,
            zone: calendar.timeZone.identifier + "-\(calendar.timeZone.secondsFromGMT())",
            calendar: String(describing: calendar.identifier))
        if current == [name], let data = SharedStore.defaults.data(forKey: projectionKey),
           let previous = try? JSONDecoder().decode(Projection.self, from: data),
           previous.zone == projection.zone, previous.calendar == projection.calendar,
           abs(previous.wallRelease.timeIntervalSince(wallRelease)) <= 10 { return }
        if !current.isEmpty { center.stopMonitoring(current.map { DeviceActivityName($0) }) }
        SharedStore.defaults.removeObject(forKey: projectionKey)
        let future = max(wallRelease, Date().addingTimeInterval(60))
        let floor = calendar.date(from: calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: future)) ?? future
        let start = floor >= future ? floor : floor.addingTimeInterval(60)
        let end = start.addingTimeInterval(16 * 60)
        do {
            try MonitorRegistration.start(DeviceActivityName(name), during: DeviceActivitySchedule(
                intervalStart: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start),
                intervalEnd: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: end),
                repeats: false, warningTime: DateComponents(minute: 5)))
            if let data = try? JSONEncoder().encode(projection) {
                SharedStore.defaults.set(data, forKey: projectionKey)
                if SharedStore.defaults.data(forKey: projectionKey) != data {
                    SharedStore.enforcementDegraded = true
                }
            }
        } catch {
            SharedStore.enforcementDegraded = true
            NSLog("Demora: day/night release monitor failed: %@", String(describing: error))
        }
    }
}
