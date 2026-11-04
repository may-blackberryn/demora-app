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
    /// The Day hero's "Your daily average last week": only when the last
    /// seven full days are completely reported; nothing is invented otherwise.
    static func lastWeekDailyAverage(_ usage: UsageInsightsConfiguration) -> TimeInterval? {
        average(usage.lastSevenDays)
    }
    /// Most used apps shows the top five until "See all N apps" is tapped.
    /// N is the ranked list, so apps with no reported time are never counted.
    static let mostUsedLimit = 5
    static func visibleApplications<T>(_ ranked: [T], expanded: Bool) -> [T] {
        expanded ? ranked : Array(ranked.prefix(mostUsedLimit))
    }
}

/// The report's one view switch (decision I1): Trends is a segment, not a
/// pushed page with its own back button.
enum UsageInsightsSegment: CaseIterable, Hashable, Sendable {
    case day, week, trends
    var key: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .trends: return "Trends"
        }
    }
}

/// What the person has picked inside the report. It lives only in the
/// report's view state: never stored, exported or sent to the host.
/// Switching segments keeps the app scope, the selected week (shared by Week
/// and Trends) and the day pager page (§5.3).
struct UsageInsightsSelection<App: Hashable> {
    var segment: UsageInsightsSegment = .day
    /// The opaque app identity the whole view is scoped to; nil = all apps.
    var application: App?
    /// Start of the selected rolling week; nil = the last seven full days.
    var week: Date?
    var page = 0
    var day: Date?
    var showingAllApplications = false

    mutating func show(_ segment: UsageInsightsSegment) { self.segment = segment }
    mutating func scope(to application: App) { self.application = application }
    mutating func showAllApps() { application = nil }
    mutating func selectWeek(_ start: Date) { week = start }
    mutating func selectDay(_ date: Date) { day = date }
    /// Older days. The selected day resets to that page's latest day.
    mutating func pageBack(dayCount: Int) {
        guard page < UsageDashboardPresentation.lastPage(dayCount: dayCount) else { return }
        page += 1; day = nil
    }
    mutating func pageForward() {
        guard page > 0 else { return }
        page -= 1; day = nil
    }
    /// Most used apps belongs to Day and Week, and only for all apps: under
    /// an app scope it would list that one app.
    var showsMostUsed: Bool { segment != .trends && application == nil }
}
