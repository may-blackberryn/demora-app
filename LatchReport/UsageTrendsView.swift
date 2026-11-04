import SwiftUI
import Foundation

// The Trends segment of the report (docs/insights-redesign.md §5.7): cards in
// the report's own scroll, drawn in its private process. Not a page: there's
// no back button and nothing here can drive host navigation. Today never
// counts; incomplete periods produce no trend, average or app change.
struct UsageTrendsView: View {
    let usage: UsageInsightsConfiguration
    let applications: [UsageInsightsApplication]
    let baseline: UsageInsightsBaseline?
    let isAppScope: Bool
    /// The week picked in the shared Four weeks card.
    let current: UsageInsightsPeriod
    let applicationLabel: (Int) -> AnyView
    let applicationIdentity: (Int) -> AnyHashable
    let colors: ReportColors
    let text: UsageFormat
    let locale: Locale
    let onSelectApp: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var coverageCellSize: CGFloat = 30
    @State private var selectedDay: Date?

    private var previous: UsageInsightsPeriod? { UsageDashboardPresentation.preceding(current, in: usage.weeks) }
    private var trend: UsageInsightsTrend? { previous.flatMap { UsageInsightsTrend.compare(current, with: $0) } }
    private var currentDays: [UsageInsightsDay] { UsageTrendsModel.days(usage, in: current) }
    private var priorDays: [UsageInsightsDay] { previous.map { UsageTrendsModel.days(usage, in: $0) } ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            comparisonCard
            dailyComparison
            extremeDays
            weekdayPatterns
            if !isAppScope { appChanges }
            if !isAppScope {
                if let baseline { baselineComparison(baseline) }
                else {
                    Text(insightsText("Want a starting point? Add an estimate in About this data (ⓘ at the top)."))
                        .reportType(.meta).foregroundStyle(colors.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
            }
            coverage
        }
        .onChange(of: current.start) { _ in selectedDay = nil }
    }

    // MARK: Compared with the week before

    private var comparisonCard: some View {
        card("Compared with the week before") {
            if let sentence = UsageComparisonText.make(trend: trend) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let symbol = sentence.symbol {
                        Image(systemName: symbol).font(.body.weight(.medium)).accessibilityHidden(true)
                    }
                    Text(sentence.sentence(text)).reportType(.body).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(colors.ink)
            } else {
                Text(insightsText("No trend yet")).reportType(.hero).foregroundStyle(colors.accent)
                Text(insightsText("A trend needs two weeks with full data.")).reportType(.body)
                    .foregroundStyle(colors.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) { periodFigures }
                VStack(alignment: .leading, spacing: 14) { periodFigures }
            }
            if let average = UsageDashboardPresentation.average(current) {
                let change = trend.map { " (" + text.signedDuration(minutes: $0.differenceMinutes / Double(current.expectedDays)) + ")" } ?? ""
                Text(text.format("Daily average: %@", text.duration(average)) + change)
                    .reportType(.meta).foregroundStyle(colors.inkSoft)
            }
            footnote("Today isn't included in trends.")
        }
    }
    @ViewBuilder private var periodFigures: some View {
        periodFigure(current)
        if let previous { periodFigure(previous) }
    }
    private func periodFigure(_ period: UsageInsightsPeriod) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name(period)).reportType(.meta).foregroundStyle(colors.inkSoft)
            Text(text.duration(period.seconds)).reportType(.time)
                .foregroundStyle(UsageFormat.wholeMinutes(period.seconds) == nil ? colors.inkSoft : colors.ink)
            if UsageCoverageLabel.isPartlyReported(period) { ReportChip(text: insightsText(UsageCoverageLabel.partly), colors: colors) }
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }

    // MARK: Day by day

    private var dailyComparison: some View {
        let a = currentDays, b = priorDays
        let maximum = max(1, (a + b).compactMap { UsageFormat.wholeMinutes($0.seconds) == nil ? nil : $0.seconds }.max() ?? 1)
        return card("Day by day") {
            Text(insightsText("Each day next to the same day the week before.")).reportType(.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                legend(name(current), faded: false)
                if let previous { legend(name(previous), faded: true) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(a.indices, id: \.self) { index in
                        dailyBar(a[index], prior: index < b.count ? b[index] : nil, maximum: maximum)
                    }
                }.padding(.bottom, 4)
            }
            if let index = a.firstIndex(where: { $0.date == selectedDay }) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) { selectedDayFigures(index, current: a, previous: b) }
                    VStack(alignment: .leading, spacing: 14) { selectedDayFigures(index, current: a, previous: b) }
                }
            }
        }
    }
    private func dailyBar(_ day: UsageInsightsDay, prior: UsageInsightsDay?, maximum: TimeInterval) -> some View {
        let value = name(current) + ": " + dayValue(day) + "; "
            + (previous.map(name) ?? "") + ": " + dayValue(prior)
        let selected = day.date == selectedDay
        return Button { selectedDay = day.date } label: {
            VStack(spacing: 8) {
                HStack(alignment: .bottom, spacing: 4) {
                    UsageBarStem(seconds: prior?.seconds, maximum: maximum, width: 13, height: 120,
                                 fill: colors.accent.opacity(0.3), complete: prior?.isComplete == true, colors: colors)
                    UsageBarStem(seconds: day.seconds, maximum: maximum, width: 13, height: 120,
                                 fill: colors.accent, complete: day.isComplete, colors: colors)
                }
                Text(date(day.date, template: "EEE")).reportType(.chip)
                    .foregroundStyle(selected ? colors.accent : colors.inkSoft).lineLimit(1)
            }.frame(minWidth: dynamicTypeSize.isAccessibilitySize ? 64 : 44, minHeight: 156).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(date(day.date, template: "EEEEMMMMd"))
            .accessibilityValue(value)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    /// "2 h 5 min", "No data yet", or "40 min, Partly reported".
    private func dayValue(_ day: UsageInsightsDay?) -> String {
        dayCoverage(day).map { text.duration(day?.seconds) + ", " + insightsText($0) } ?? text.duration(day?.seconds)
    }
    /// Only the incomplete case is named (I8); missing already reads "No data yet".
    private func dayCoverage(_ day: UsageInsightsDay?) -> String? {
        guard let day, UsageFormat.wholeMinutes(day.seconds) != nil, !day.isComplete else { return nil }
        return UsageCoverageLabel.partly
    }
    @ViewBuilder private func selectedDayFigures(_ index: Int, current days: [UsageInsightsDay], previous prior: [UsageInsightsDay]) -> some View {
        dayFigure(days[index], title: name(current))
        if index < prior.count, let previous { dayFigure(prior[index], title: name(previous)) }
    }
    private func dayFigure(_ day: UsageInsightsDay, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).reportType(.meta).foregroundStyle(colors.inkSoft)
            Text(text.duration(day.seconds)).reportType(.time)
            Text(date(day.date, template: "EEEMMMd")).reportType(.chip).foregroundStyle(colors.inkSoft)
            if dayCoverage(day) != nil { ReportChip(text: insightsText(UsageCoverageLabel.partly), colors: colors) }
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
    private func legend(_ title: String, faded: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(colors.accent.opacity(faded ? 0.3 : 1)).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(title)
        }.reportType(.chip).foregroundStyle(colors.inkSoft)
    }

    // MARK: Highs and lows

    private var extremeDays: some View {
        let values = UsageTrendsModel.extremes(usage, in: current)
        return card("Highs and lows") {
            if let high = values.high, let seconds = high.seconds {
                Text(text.format("Your heaviest day was %@: %@.", date(high.date, template: "EEEE"), text.duration(seconds)))
                    .reportType(.body).fixedSize(horizontal: false, vertical: true)
                if let low = values.low, let lowSeconds = low.seconds, low.date != high.date {
                    Text(text.format("Your lightest day was %@: %@.", date(low.date, template: "EEEE"), text.duration(lowSeconds)))
                        .reportType(.body).fixedSize(horizontal: false, vertical: true)
                }
                if !current.isComplete { footnote("Only fully reported days count.") }
            } else {
                Text(insightsText("Only fully reported days count.")).reportType(.body)
                    .foregroundStyle(colors.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Weekday patterns

    private var weekdayPatterns: some View {
        let patterns = UsageTrendsModel.weekdayPatterns(usage)
        let maximum = max(1, patterns.compactMap(\.averageSeconds).max() ?? 1)
        return card("Weekday patterns") {
            if let heaviest = UsageTrendsModel.heaviestWeekday(patterns) {
                Text(text.format("%@ tends to be your heaviest day.", weekday(heaviest.weekday)))
                    .reportType(.body).fixedSize(horizontal: false, vertical: true)
            }
            if let range = UsageTrendsModel.patternRange(usage) {
                Text(text.format("%@ – %@", date(range.start), date(range.end))).reportType(.meta).foregroundStyle(colors.inkSoft)
            }
            ForEach(patterns) { pattern in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(weekday(pattern.weekday)).reportType(.body)
                        Spacer(minLength: 8)
                        Text(text.compact(pattern.averageSeconds)).font(.system(.subheadline, design: .serif))
                            .monospacedDigit().foregroundStyle(colors.accent)
                        Text(text.format("%d days", pattern.sampleCount)).reportType(.chip).foregroundStyle(colors.inkSoft)
                    }
                    GeometryReader { geometry in
                        Capsule().fill(colors.accentTint)
                        if let fraction = UsageDashboardPresentation.barFraction(pattern.averageSeconds, maximum: maximum) {
                            Capsule().fill(colors.accent.opacity(0.55)).frame(width: geometry.size.width * fraction)
                        }
                    }.frame(height: 4).accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(weekday(pattern.weekday))
                .accessibilityValue(text.duration(pattern.averageSeconds) + ", " + text.format("%d days", pattern.sampleCount))
            }
            footnote("Averages use only days with full data.")
        }
    }

    // MARK: Biggest app changes

    private var appChanges: some View {
        let changes = Array(UsageTrendsModel.appChanges(applications, current: current, previous: previous).prefix(5))
        return card("Biggest app changes") {
            if changes.isEmpty {
                Text(insightsText("No comparable app changes yet.")).reportType(.body).foregroundStyle(colors.inkSoft)
            }
            ForEach(changes) { change in
                Button { onSelectApp(change.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            applicationLabel(change.id).id(applicationIdentity(change.id)).reportType(.body).labelStyle(.titleAndIcon)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(text.signedDuration(minutes: change.trend.differenceMinutes))
                                .font(.system(.subheadline, design: .serif)).monospacedDigit().foregroundStyle(colors.accent)
                        }
                        Text(text.duration(change.previous.seconds) + " → " + text.duration(change.current.seconds))
                            .reportType(.meta).foregroundStyle(colors.inkSoft)
                    }.frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 64 : 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityElement(children: .combine)
            }
            footnote("Only apps with full data in both weeks. App changes don't add up to your overall change.")
        }
    }

    // MARK: Your starting point

    /// A self-reported estimate, never measured history or time saved.
    private func baselineComparison(_ baseline: UsageInsightsBaseline) -> some View {
        card("Your starting point", fill: colors.accentTint) {
            Text(text.format("You estimated %@ a week before using Demora.", text.duration(Double(baseline.weeklyMinutes) * 60)))
                .reportType(.body).fixedSize(horizontal: false, vertical: true)
            Text(text.format("Recorded %@", date(baseline.recordedAt, template: "yMMMd")))
                .reportType(.meta).foregroundStyle(colors.inkSoft)
            if let difference = usage.baselineDifference(for: current),
               let sentence = UsageComparisonText.make(differenceMinutes: difference, percent: nil) {
                Text(sentence.estimateSentence(period: name(current), text)).reportType(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(insightsText("Needs a week with full data to compare.")).reportType(.meta)
                    .foregroundStyle(colors.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            footnote("This is your own estimate, not measured Screen Time. It doesn't measure time saved by Demora.")
        }
    }

    // MARK: How complete this is

    private var coverage: some View {
        let values = UsageTrendsModel.coverage(usage)
        let days = usage.days.filter { $0.date < usage.calendar.startOfDay(for: usage.generatedAt) }
        return card("How complete this is") {
            Text(text.format("%d of %d days have full data.", values.complete, values.complete + values.partial + values.missing))
                .reportType(.body)
            ScrollView(.horizontal, showsIndicators: false) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(coverageCellSize), spacing: 10), count: 7), spacing: 10) {
                ForEach(days) { day in
                    ZStack {
                        if UsageFormat.wholeMinutes(day.seconds) == nil {
                            Circle().stroke(colors.inkSoft.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        } else if day.isComplete { Circle().fill(colors.accent.opacity(0.8)) }
                        else { Circle().stroke(colors.accent, lineWidth: 1.5) }
                        Text(date(day.date, template: "d")).font(.caption2)
                            .foregroundStyle(day.isComplete && UsageFormat.wholeMinutes(day.seconds) != nil ? colors.card : colors.inkSoft)
                    }.frame(width: coverageCellSize, height: coverageCellSize).accessibilityElement(children: .ignore)
                        .accessibilityLabel(date(day.date, template: "EEEEMMMMd"))
                        .accessibilityValue(insightsText(coverageKey(day)))
                }
            }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { coverageFigures(values) }
                VStack(alignment: .leading, spacing: 12) { coverageFigures(values) }
            }
            footnote("Missing days aren't counted as zero.")
        }
    }
    private func coverageKey(_ day: UsageInsightsDay) -> String {
        guard UsageFormat.wholeMinutes(day.seconds) != nil else { return "No data" }
        return day.isComplete ? "Full data" : UsageCoverageLabel.partly
    }
    @ViewBuilder private func coverageFigures(_ values: (complete: Int, partial: Int, missing: Int)) -> some View {
        coverageFigure(values.complete, title: "Full data")
        coverageFigure(values.partial, title: "Partly reported")
        coverageFigure(values.missing, title: "No data")
    }
    private func coverageFigure(_ count: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text.number(Double(count))).reportType(.time).foregroundStyle(colors.accent)
            Text(insightsText(title)).reportType(.chip).foregroundStyle(colors.inkSoft)
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }

    // MARK: Pieces

    private func card<Content: View>(_ title: String, fill: Color? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ReportSectionHeader(title: insightsText(title), colors: colors)
            content()
        }
        .reportCard(colors, fill: fill)
    }
    private func footnote(_ key: String) -> some View {
        Text(insightsText(key)).reportType(.meta).foregroundStyle(colors.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }
    /// "Last 7 full days", "The week before", or the period's dates.
    private func name(_ period: UsageInsightsPeriod) -> String {
        UsagePeriodName.key(for: period, in: usage).map(insightsText) ?? range(period)
    }
    private func date(_ date: Date, template: String = "MMMd") -> String {
        let f = DateFormatter(); f.locale = locale; f.calendar = usage.calendar; f.timeZone = usage.calendar.timeZone
        f.setLocalizedDateFormatFromTemplate(template); return f.string(from: date)
    }
    private func weekday(_ day: Int) -> String {
        let f = DateFormatter(); f.locale = locale; f.calendar = usage.calendar
        let symbols = f.weekdaySymbols ?? []
        return symbols.indices.contains(day - 1) ? symbols[day - 1] : ""
    }
    private func range(_ period: UsageInsightsPeriod) -> String {
        text.format("%@ – %@", date(period.start), date(usage.calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.start))
    }
}
