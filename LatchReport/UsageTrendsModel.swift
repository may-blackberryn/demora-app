import Foundation

// Derived, ephemeral report-only statistics. Missing/partial days never
// contribute to averages, extrema or comparable app changes.
struct UsageWeekdayPattern: Identifiable, Sendable {
    let weekday: Int
    let sampleCount: Int
    let averageSeconds: TimeInterval?
    var id: Int { weekday }
}
struct UsageAppChange: Identifiable, Sendable {
    let id: Int
    let current: UsageInsightsPeriod
    let previous: UsageInsightsPeriod
    let trend: UsageInsightsTrend
}
enum UsageTrendsModel {
    static func completedDays(_ usage: UsageInsightsConfiguration) -> [UsageInsightsDay] {
        let today = usage.calendar.startOfDay(for: usage.generatedAt)
        return usage.days.filter { day in
            guard day.date < today, day.isComplete, let seconds = day.seconds else { return false }
            return seconds.isFinite && seconds >= 0
        }
    }
    static func days(_ usage: UsageInsightsConfiguration, in period: UsageInsightsPeriod) -> [UsageInsightsDay] {
        usage.days.filter { $0.date >= period.start && $0.date < period.end }.sorted { $0.date < $1.date }
    }
    static func weekdayPatterns(_ usage: UsageInsightsConfiguration) -> [UsageWeekdayPattern] {
        let days = completedDays(usage)
        return (0..<7).map { offset in
            let weekday = (usage.calendar.firstWeekday - 1 + offset) % 7 + 1
            let samples = days.filter { usage.calendar.component(.weekday, from: $0.date) == weekday }.compactMap(\.seconds)
            let sum = samples.reduce(0, +)
            return UsageWeekdayPattern(weekday: weekday, sampleCount: samples.count,
                averageSeconds: samples.isEmpty || !sum.isFinite ? nil : sum / Double(samples.count))
        }
    }
    static func extremes(_ usage: UsageInsightsConfiguration, in period: UsageInsightsPeriod) -> (high: UsageInsightsDay?, low: UsageInsightsDay?) {
        let days = completedDays(usage).filter { $0.date >= period.start && $0.date < period.end }
            .sorted { $0.date < $1.date }
        // Ties consistently select the first calendar day, never "today".
        return (days.reduce(nil) { best, day in
            guard let best else { return day }; return day.seconds! > best.seconds! ? day : best
        }, days.reduce(nil) { best, day in
            guard let best else { return day }; return day.seconds! < best.seconds! ? day : best
        })
    }
    static func appChanges(_ applications: [UsageInsightsApplication], current: UsageInsightsPeriod,
                           previous: UsageInsightsPeriod?) -> [UsageAppChange] {
        guard let previous else { return [] }
        return applications.compactMap { app in
            guard let a = app.usage.weeks.first(where: { $0.start == current.start && $0.end == current.end }),
                  let b = app.usage.weeks.first(where: { $0.start == previous.start && $0.end == previous.end }),
                  let trend = UsageInsightsTrend.compare(a, with: b), trend.differenceMinutes != 0 else { return nil }
            return UsageAppChange(id: app.id, current: a, previous: b, trend: trend)
        }.sorted {
            let a = abs($0.trend.differenceMinutes), b = abs($1.trend.differenceMinutes)
            return a == b ? $0.id < $1.id : a > b
        }
    }
    static func coverage(_ usage: UsageInsightsConfiguration) -> (complete: Int, partial: Int, missing: Int) {
        let today = usage.calendar.startOfDay(for: usage.generatedAt)
        let days = usage.days.filter { $0.date < today }
        let complete = completedDays(usage).count
        let reported = days.filter { $0.seconds?.isFinite == true && ($0.seconds ?? -1) >= 0 }.count
        return (complete, max(0, reported - complete), days.count - reported)
    }
}
