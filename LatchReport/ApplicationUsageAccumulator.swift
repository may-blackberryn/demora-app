import Foundation

// Opaque integer IDs are allocated from Apple's tokens by the report scene.
// Whole daily app maps are replaced together: a newer snapshot that omits an
// app must never retain that app's stale minutes. Absence remains unknown.
struct ApplicationUsageAccumulator {
    private struct Snapshot {
        let end: Date
        let updatedAt: Date
        let values: [Int: TimeInterval]
        let reliable: Bool
    }
    let now: Date
    let calendar: Calendar
    private var sources: Set<Int> = []
    private var snapshots: [Date: [Int: Snapshot]] = [:]

    mutating func registerSource(_ source: Int) { sources.insert(source) }

    mutating func add(source: Int, start: Date, end: Date, updatedAt: Date,
                      applications: [Int: TimeInterval]) {
        registerSource(source)
        guard start.timeIntervalSince1970.isFinite else { return }
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -28, to: today)!
        let day = calendar.startOfDay(for: start)
        guard day >= first, day <= today else { return }
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
        // Untrustworthy revision timestamps cannot supersede a known snapshot.
        guard updatedAt.timeIntervalSince1970.isFinite,
              updatedAt >= start, updatedAt <= now else { return }
        let intervalValid = start == day && end.timeIntervalSince1970.isFinite
            && end > start && end <= dayEnd
        let elapsed = intervalValid ? min(end, min(now, updatedAt)).timeIntervalSince(start) : 0
        let valid = intervalValid
            ? applications.filter { $0.value.isFinite && $0.value >= 0 && $0.value <= elapsed } : [:]
        var candidate = Snapshot(end: end.timeIntervalSince1970.isFinite ? end : dayEnd,
            updatedAt: updatedAt, values: valid,
            reliable: intervalValid && valid.count == applications.count)
        if let old = snapshots[day]?[source] {
            if updatedAt < old.updatedAt { return }
            if updatedAt == old.updatedAt {
                if candidate.end < old.end { return }
                if candidate.end == old.end {
                    // Equal-version duplicates are one observation, not added.
                    // Contradictory maps retain known maxima but cannot claim
                    // complete coverage or generate an app trend.
                    var merged = old.values
                    for (id, seconds) in valid { merged[id] = max(merged[id] ?? seconds, seconds) }
                    candidate = Snapshot(end: candidate.end, updatedAt: updatedAt, values: merged,
                        reliable: old.reliable && candidate.reliable && old.values == valid)
                }
            }
        }
        snapshots[day, default: [:]][source] = candidate
    }

    func applications() -> [UsageInsightsApplication] {
        let ids = Set(snapshots.values.flatMap { $0.values.flatMap { $0.values.keys } })
        return ids.sorted().map { id in
            var accumulator = UsageInsightsAccumulator(now: now, calendar: calendar)
            for source in sources { accumulator.registerSource(source) }
            for (day, records) in snapshots {
                for (source, snapshot) in records {
                    if let seconds = snapshot.values[id] {
                        accumulator.add(source: source, start: day, end: snapshot.end,
                            seconds: seconds, updatedAt: snapshot.updatedAt)
                    }
                    if !snapshot.reliable {
                        // Only the winning revision's validity affects coverage.
                        accumulator.add(source: source, start: day, end: snapshot.end,
                            seconds: .nan, updatedAt: snapshot.updatedAt)
                    }
                }
            }
            return UsageInsightsApplication(id: id, usage: accumulator.configuration(baseline: nil))
        }
    }
}
