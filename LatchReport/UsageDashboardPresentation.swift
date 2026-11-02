import Foundation

// Display-only projections. Never infer missing data or change aggregation.
enum UsageDashboardPresentation {
    static func unavailable(_ configuration: UsageInsightsConfiguration) -> UsageInsightsConfiguration {
        UsageInsightsAccumulator(now: configuration.generatedAt, calendar: configuration.calendar)
            .configuration(baseline: nil)
    }
    static func appSeconds(_ app: UsageInsightsApplication, day: Date?, week: Date?) -> TimeInterval? {
        let seconds: TimeInterval?
        if let week { seconds = app.usage.weeks.first { $0.start == week }?.seconds }
        else { seconds = app.usage.days.first { $0.date == day }?.seconds }
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }
    static func rankedApplications(_ applications: [UsageInsightsApplication], day: Date?, week: Date?) -> [UsageInsightsApplication] {
        applications.filter { appSeconds($0, day: day, week: week) != nil }.sorted {
            let lhs = appSeconds($0, day: day, week: week)!
            let rhs = appSeconds($1, day: day, week: week)!
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }
    }
    static func lastPage(dayCount: Int) -> Int { max(0, (dayCount - 1) / 7) }
    static func window(_ days: [UsageInsightsDay], page: Int) -> [UsageInsightsDay] {
        guard !days.isEmpty else { return [] }
        let page = min(max(0, page), lastPage(dayCount: days.count))
        let start = max(0, days.count - (page + 1) * 7)
        return Array(days[start..<min(days.count, start + 7)])
    }
    static func barFraction(_ seconds: TimeInterval?, maximum: TimeInterval) -> Double? {
        guard let seconds, seconds.isFinite, seconds >= 0,
              maximum.isFinite, maximum > 0 else { return nil }
        return min(1, seconds / maximum)
    }
    static func average(_ period: UsageInsightsPeriod) -> TimeInterval? {
        guard period.isComplete, let seconds = period.seconds,
              seconds.isFinite, seconds >= 0 else { return nil }
        return seconds / Double(period.expectedDays)
    }
    static func preceding(_ period: UsageInsightsPeriod, in periods: [UsageInsightsPeriod]) -> UsageInsightsPeriod? {
        periods.first { $0.end == period.start }
    }
}
