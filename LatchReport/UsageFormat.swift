import Foundation

// Display text for measured durations and comparisons inside the report
// (docs/insights-redesign.md §7). Foundation-only and ephemeral: nothing here
// is stored, logged or sent. `translate` is the report's `insightsText` in the
// extension and a plain closure in tests, so the exact English can be checked.
struct UsageFormat {
    let locale: Locale
    let translate: (String) -> String

    /// Whole minutes of a measured duration; nil for missing or invalid
    /// values, which are unknown, never zero.
    static func wholeMinutes(_ seconds: TimeInterval?) -> Double? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        return floor(seconds / 60)
    }

    /// "2 h 10 min", "21 h", "45 min". Missing reads "No data yet".
    func duration(_ seconds: TimeInterval?) -> String {
        guard let minutes = Self.wholeMinutes(seconds) else { return translate("No data yet") }
        return magnitude(minutes)
    }

    /// The same, but a dash where there's no room for a sentence (chart
    /// captions). A dash means no data, never zero.
    func compact(_ seconds: TimeInterval?) -> String {
        guard let minutes = Self.wholeMinutes(seconds) else { return "—" }
        return magnitude(minutes)
    }

    /// A signed change in minutes: "−2 h 10 min", "+5 min", "0 min".
    /// Partial minutes are dropped towards zero, as in `duration`.
    func signedDuration(minutes: Double) -> String {
        guard minutes.isFinite else { return "—" }
        let whole = floor(abs(minutes))
        guard whole > 0 else { return magnitude(0) }
        return (minutes < 0 ? "−" : "+") + magnitude(whole)
    }

    /// "(−9%)", or nil when the rounded change is under one percent.
    func percent(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        let rounded = value.rounded()
        guard abs(rounded) >= 1 else { return nil }
        return format("(%@%%)", (rounded < 0 ? "−" : "+") + number(abs(rounded)))
    }

    func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }

    /// A sentence that ends on an abbreviated unit ("… 42 Min." + ".")
    /// keeps one full stop.
    func format(_ key: String, _ values: CVarArg...) -> String {
        String(format: translate(key), locale: locale, arguments: values)
            .replacingOccurrences(of: "..", with: ".")
    }

    private func magnitude(_ minutes: Double) -> String {
        if minutes < 60 { return format("%@ min", number(minutes)) }
        let hours = floor(minutes / 60)
        let rest = minutes - hours * 60
        if rest == 0 { return format("%@ h", number(hours)) }
        return format("%@ h %@ min", number(hours), number(rest))
    }
}

/// "↓ 2 h 10 min less than the week before (−9%)" (decisions I2, I3): the
/// change in hours and minutes first, the percentage second, in neutral ink.
/// The arrow is an SF Symbol the view draws and hides from VoiceOver.
struct UsageComparisonText: Equatable {
    enum Direction: Equatable { case less, more, same }
    let direction: Direction
    /// Whole minutes of the change, always positive (0 for `.same`).
    let minutes: Double
    /// The signed percentage, or nil when the period before was zero or the
    /// two are about the same.
    let percent: Double?

    /// Nil when there's no trend: a period isn't complete or there's no
    /// earlier period. Within one minute either way reads "About the same".
    static func make(trend: UsageInsightsTrend?) -> UsageComparisonText? {
        guard let trend, trend.differenceMinutes.isFinite else { return nil }
        return make(differenceMinutes: trend.differenceMinutes, percent: trend.percentage)
    }

    static func make(differenceMinutes: Double, percent: Double?) -> UsageComparisonText? {
        guard differenceMinutes.isFinite else { return nil }
        let whole = floor(abs(differenceMinutes))
        guard whole >= 1 else { return Self(direction: .same, minutes: 0, percent: nil) }
        return Self(direction: differenceMinutes < 0 ? .less : .more, minutes: whole,
                    percent: percent?.isFinite == true ? percent : nil)
    }

    /// Symbol for the arrow in front of the sentence; nil for "About the same".
    var symbol: String? {
        switch direction {
        case .less: return "arrow.down"
        case .more: return "arrow.up"
        case .same: return nil
        }
    }

    /// The comparison with the period before.
    func sentence(_ format: UsageFormat) -> String {
        switch direction {
        case .same: return format.translate("About the same as the week before")
        case .less, .more:
            let amount = format.duration(minutes * 60)
            let text = direction == .less ? format.format("%@ less than the week before", amount)
                                          : format.format("%@ more than the week before", amount)
            return format.percent(percent).map { text + " " + $0 } ?? text
        }
    }

    /// The comparison with the self-reported starting estimate. It names the
    /// period and never speaks of time saved.
    func estimateSentence(period: String, _ format: UsageFormat) -> String {
        switch direction {
        case .same: return format.format("%@: about the same as your estimate.", period)
        case .less: return format.format("%@: %@ less than your estimate.", period, format.duration(minutes * 60))
        case .more: return format.format("%@: %@ more than your estimate.", period, format.duration(minutes * 60))
        }
    }
}

/// What the Week hero says under its total (§5.5).
enum UsageWeekComparison: Equatable {
    case sentence(UsageComparisonText)
    /// One of the two periods isn't fully reported.
    case needsFullData
    /// The oldest period: there's nothing before it in the report.
    case noEarlierWeek

    static func make(_ period: UsageInsightsPeriod, in weeks: [UsageInsightsPeriod]) -> Self {
        guard let previous = UsageDashboardPresentation.preceding(period, in: weeks) else { return .noEarlierWeek }
        guard let text = UsageComparisonText.make(trend: UsageInsightsTrend.compare(period, with: previous)) else {
            return .needsFullData
        }
        return .sentence(text)
    }

    var key: String? {
        switch self {
        case .sentence: return nil
        case .needsFullData: return "No comparison yet: both weeks need full data."
        case .noEarlierWeek: return "No earlier week to compare."
        }
    }
}

/// Only what's incomplete gets a label (decision I8); full data carries none.
enum UsageCoverageLabel {
    static let partly = "Partly reported"

    /// A past day iOS reported only part of. Today never gets the chip: its
    /// label already says "so far". Missing days read "No data yet" instead.
    static func isPartlyReported(_ day: UsageInsightsDay?, today: Date?) -> Bool {
        guard let day, UsageFormat.wholeMinutes(day.seconds) != nil else { return false }
        return !day.isComplete && day.date != today
    }

    /// A period with some reported data but not every day complete.
    static func isPartlyReported(_ period: UsageInsightsPeriod) -> Bool {
        UsageFormat.wholeMinutes(period.seconds) != nil && !period.isComplete
    }

    /// The VoiceOver note for a bar or calendar day: nil when it's complete.
    static func accessibilityKey(_ day: UsageInsightsDay?, today: Date?) -> String? {
        guard let day, UsageFormat.wholeMinutes(day.seconds) != nil else { return "No data" }
        return isPartlyReported(day, today: today) ? partly : nil
    }
}

/// Weeks are rolling seven-day periods ending yesterday (decision I10), so
/// they're named by position or by their dates, never "This week".
enum UsagePeriodName {
    /// "Last 7 full days", "The week before", or nil: use the date range.
    static func key(for period: UsageInsightsPeriod, in usage: UsageInsightsConfiguration) -> String? {
        if same(period, usage.lastSevenDays) { return "Last 7 full days" }
        if same(period, usage.previousSevenDays) { return "The week before" }
        return nil
    }

    /// What a Week hero says without a total: before any full day has been
    /// reported there's no week yet; otherwise this period simply has no data.
    static func emptyKey(_ usage: UsageInsightsConfiguration) -> String {
        let today = usage.calendar.startOfDay(for: usage.generatedAt)
        let anyPastDay = usage.days.contains { $0.date < today && UsageFormat.wholeMinutes($0.seconds) != nil }
        if anyPastDay { return "No data yet" }
        return "No full week yet"
    }

    private static func same(_ a: UsageInsightsPeriod, _ b: UsageInsightsPeriod) -> Bool {
        a.start == b.start && a.end == b.end
    }
}
