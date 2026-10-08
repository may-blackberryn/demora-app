import Foundation

// Foundation-only, ephemeral projections. None of these types is Encodable:
// Screen Time data must never leave this extension or be persisted.
struct UsageInsightsDay: Identifiable, Sendable {
    let date: Date
    let seconds: TimeInterval?
    let reportedSources: Int
    let expectedSources: Int
    let isComplete: Bool
    var id: Date { date }
}

struct UsageInsightsPeriod: Identifiable, Sendable {
    let start: Date
    let end: Date
    let expectedDays: Int
    let reportedDays: Int
    let completeDays: Int
    let seconds: TimeInterval?
    var id: Date { start }
    var isComplete: Bool { completeDays == expectedDays && expectedDays > 0 }
}

struct UsageInsightsTrend: Sendable {
    let differenceMinutes: Double
    let percentage: Double?

    static func compare(_ current: UsageInsightsPeriod,
                        with previous: UsageInsightsPeriod) -> Self? {
        guard current.isComplete, previous.isComplete,
              current.expectedDays == previous.expectedDays,
              let currentSeconds = current.seconds, let previousSeconds = previous.seconds,
              currentSeconds.isFinite, previousSeconds.isFinite,
              currentSeconds >= 0, previousSeconds >= 0 else { return nil }
        let difference = currentSeconds - previousSeconds
        let percentage = previousSeconds > 0 ? difference / previousSeconds * 100 : nil
        return Self(differenceMinutes: difference / 60,
                    percentage: percentage?.isFinite == true ? percentage : nil)
    }
}

struct UsageInsightsBaseline: Decodable, Sendable {
    static let key = "latch.usageBaseline.v1"
    let weeklyMinutes: Int
    let recordedAt: Date

    // Host contract: JSONEncoder's default Date representation (seconds since
    // 2001), stored as Data. No derived Screen Time value is written back.
    static func decode(_ data: Data?, now: Date) -> Self? {
        guard let data, data.count <= 1_024,
              now.timeIntervalSince1970.isFinite,
              let value = try? JSONDecoder().decode(Self.self, from: data),
              (0...10_080).contains(value.weeklyMinutes),
              value.recordedAt.timeIntervalSince1970.isFinite,
              value.recordedAt > Date(timeIntervalSince1970: 0),
              value.recordedAt <= now else { return nil }
        return value
    }
}

struct UsageInsightsConfiguration: Sendable {
    let generatedAt: Date
    let calendar: Calendar
    let days: [UsageInsightsDay]
    let lastSevenDays: UsageInsightsPeriod
    let previousSevenDays: UsageInsightsPeriod
    let weeks: [UsageInsightsPeriod]
    let baseline: UsageInsightsBaseline?
    var today: UsageInsightsDay? { days.last }
    var reportedDays: Int { days.filter { $0.seconds != nil }.count }
    var trend: UsageInsightsTrend? {
        UsageInsightsTrend.compare(lastSevenDays, with: previousSevenDays)
    }
    /// A comparison with a manual estimate, never proof of time saved.
    /// Do not compare an incomplete measured period with a full-week estimate.
    var baselineDifferenceMinutes: Double? {
        guard let baseline, lastSevenDays.isComplete,
              let seconds = lastSevenDays.seconds, seconds.isFinite else { return nil }
        return seconds / 60 - Double(baseline.weeklyMinutes)
    }
}

struct UsageInsightsAccumulator {
    private struct Sample {
        let end: Date
        let seconds: TimeInterval
        let updatedAt: Date
    }

    let now: Date
    let calendar: Calendar
    private let today: Date
    private let firstDay: Date
    private var sources: Set<Int> = []
    private var samples: [Date: [Int: Sample]] = [:]
    private var invalidDays: Set<Date> = []

    init(now: Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        firstDay = calendar.date(byAdding: .day, value: -28, to: today)!
    }

    mutating func registerSource(_ source: Int) { sources.insert(source) }

    // One daily snapshot per opaque source/day, not category/app sums. Repeated
    // intervals never add time: newest lastUpdatedDate wins, then longest daily
    // interval, then largest duration for an equal-version duplicate. All inputs
    // must start at local midnight; a clipped/cross-day input cannot be apportioned
    // truthfully and is excluded. Calendar arithmetic preserves 23/25-hour days.
    mutating func add(source: Int, start: Date, end: Date,
                      seconds: TimeInterval, updatedAt: Date) {
        registerSource(source)
        guard start.timeIntervalSince1970.isFinite else { return }
        let day = calendar.startOfDay(for: start)
        guard day >= firstDay, day <= today else { return }
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
        guard start == day, end.timeIntervalSince1970.isFinite,
              end > start, end <= dayEnd,
              updatedAt.timeIntervalSince1970.isFinite,
              updatedAt >= start, updatedAt <= now,
              seconds.isFinite, seconds >= 0,
              seconds <= min(end, min(now, updatedAt)).timeIntervalSince(start)
        else {
            invalidDays.insert(day)
            return
        }
        let candidate = Sample(end: end, seconds: seconds, updatedAt: updatedAt)
        if let old = samples[day]?[source] {
            if candidate.updatedAt < old.updatedAt { return }
            if candidate.updatedAt == old.updatedAt {
                if candidate.end < old.end { return }
                if candidate.end == old.end && candidate.seconds <= old.seconds { return }
            }
        }
        samples[day, default: [:]][source] = candidate
    }

    func configuration(baseline: UsageInsightsBaseline?) -> UsageInsightsConfiguration {
        let days = (0..<29).map { offset -> UsageInsightsDay in
            let day = calendar.date(byAdding: .day, value: offset, to: firstDay)!
            let end = calendar.date(byAdding: .day, value: 1, to: day)!
            let values = Array((samples[day] ?? [:]).values)
            let sum = values.reduce(0) { $0 + $1.seconds }
            let finite = sum.isFinite
            // "Complete" means a full daily segment reported for every source
            // present in this result, after that day ended. It is not a guarantee
            // of Apple's sync accuracy, nor proof that an absent source had zero use.
            let complete = day < today && !sources.isEmpty
                && values.count == sources.count && !invalidDays.contains(day)
                && finite && values.allSatisfy { $0.end == end && $0.updatedAt >= end }
            return UsageInsightsDay(date: day,
                seconds: values.isEmpty || !finite ? nil : sum,
                reportedSources: values.count, expectedSources: sources.count,
                isComplete: complete)
        }
        func period(start: Date) -> UsageInsightsPeriod {
            let end = calendar.date(byAdding: .day, value: 7, to: start)!
            let included = days.filter { $0.date >= start && $0.date < end }
            let reported = included.compactMap(\.seconds)
            let sum = reported.reduce(0, +)
            return UsageInsightsPeriod(start: start, end: end, expectedDays: 7,
                reportedDays: reported.count,
                completeDays: included.filter(\.isComplete).count,
                seconds: reported.isEmpty || !sum.isFinite ? nil : sum)
        }
        // Four completed seven-day periods, anchored to today's local midnight.
        // Never compare a partial current calendar week with a completed week.
        let weeks = (0..<4).map { index in
            period(start: calendar.date(byAdding: .day, value: (index - 4) * 7,
                                        to: today)!)
        }
        return UsageInsightsConfiguration(generatedAt: now, calendar: calendar,
            days: days,
            lastSevenDays: period(start: calendar.date(byAdding: .day, value: -7, to: today)!),
            previousSevenDays: period(start: calendar.date(byAdding: .day, value: -14, to: today)!),
            weeks: weeks, baseline: baseline)
    }
}
