import SwiftUI
import Foundation

// A distinct page inside the report's private process, not a host data export.
struct UsageTrendsView: View {
    let usage: UsageInsightsConfiguration
    let applications: [UsageInsightsApplication]
    let baseline: UsageInsightsBaseline?
    let scopeLabel: AnyView?
    let applicationLabel: (Int) -> AnyView
    let applicationIdentity: (Int) -> AnyHashable
    let accent: Color
    let ink: Color
    let muted: Color
    let paper: Color
    let locale: Locale
    let onBack: () -> Void
    let onAllApps: () -> Void
    let onSelectApp: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 64
    @ScaledMetric(relativeTo: .caption2) private var coverageCellSize: CGFloat = 30
    @State private var selectedStart: Date?
    @State private var selectedDay: Date?

    init(usage: UsageInsightsConfiguration, applications: [UsageInsightsApplication],
         baseline: UsageInsightsBaseline?, scopeLabel: AnyView?,
         applicationLabel: @escaping (Int) -> AnyView, applicationIdentity: @escaping (Int) -> AnyHashable,
         accent: Color, ink: Color, muted: Color, paper: Color, locale: Locale,
         selectedPeriod: Date?, onBack: @escaping () -> Void,
         onAllApps: @escaping () -> Void, onSelectApp: @escaping (Int) -> Void) {
        self.usage = usage; self.applications = applications; self.baseline = baseline
        self.scopeLabel = scopeLabel; self.applicationLabel = applicationLabel; self.applicationIdentity = applicationIdentity
        self.accent = accent; self.ink = ink; self.muted = muted; self.paper = paper; self.locale = locale
        self.onBack = onBack; self.onAllApps = onAllApps; self.onSelectApp = onSelectApp
        _selectedStart = State(initialValue: selectedPeriod)
    }
    private var current: UsageInsightsPeriod { usage.weeks.first { $0.start == selectedStart } ?? usage.lastSevenDays }
    private var previous: UsageInsightsPeriod? { UsageDashboardPresentation.preceding(current, in: usage.weeks) }
    private var trend: UsageInsightsTrend? { previous.flatMap { UsageInsightsTrend.compare(current, with: $0) } }
    private var currentDays: [UsageInsightsDay] { UsageTrendsModel.days(usage, in: current) }
    private var priorDays: [UsageInsightsDay] { previous.map { UsageTrendsModel.days(usage, in: $0) } ?? [] }

    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                pageHeader.id("trendsTop")
                hero
                weekChart
                dailyComparison
                weekdayPatterns
                extremeDays
                if scopeLabel == nil { appChanges }
                if let baseline { baselineComparison(baseline) }
                coverage
            }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 32)
                .frame(maxWidth: 740).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(paper).foregroundStyle(ink).environment(\.locale, locale)
            .onChange(of: scopeLabel == nil) { _ in
                reader.scrollTo("trendsTop", anchor: .top)
            }
        }
    }
    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 22) {
            Button(action: onBack) {
                HStack(spacing: 9) { Image(systemName: "arrow.left"); Text(insightsText("Back to usage")) }
                    .font(.subheadline).foregroundStyle(accent).frame(minHeight: 44)
            }.buttonStyle(.plain)
            Text(insightsText("Trends")).font(.system(.largeTitle, design: .serif)).accessibilityAddTraits(.isHeader)
            Text(insightsText("Your time, in perspective.")).font(.subheadline).foregroundStyle(muted)
            if let scopeLabel {
                HStack(spacing: 12) {
                    scopeLabel.font(.headline).labelStyle(.titleAndIcon).frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: onAllApps) {
                        Text(insightsText("All apps")).font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).frame(minHeight: 44).background(accent.opacity(0.08), in: Capsule())
                    }.buttonStyle(.plain).foregroundStyle(accent)
                }
            } else { Text(insightsText("All apps")).font(.caption.weight(.semibold)).foregroundStyle(accent) }
        }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Compared with the previous week")
            if let trend {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(trend.percentage.map { signed($0) + "%" } ?? signedDuration(trend.differenceMinutes))
                        .font(.system(size: min(heroSize, 100), design: .serif)).tracking(-2)
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.45)
                    Image(systemName: trend.differenceMinutes == 0 ? "arrow.right" : (trend.differenceMinutes < 0 ? "arrow.down.right" : "arrow.up.right"))
                        .font(.system(size: 24, weight: .light)).accessibilityHidden(true)
                }.foregroundStyle(accent)
                Text(format("Change: %@", signedDuration(trend.differenceMinutes))).font(.subheadline).foregroundStyle(muted)
                Text(format("Daily average change: %@", signedDuration(trend.differenceMinutes / Double(current.expectedDays))))
                    .font(.caption).foregroundStyle(muted)
            } else {
                Text(insightsText("No trend yet")).font(.system(.largeTitle, design: .serif)).foregroundStyle(accent)
                Text(insightsText("A trend needs full reported coverage for both completed periods.")).font(.subheadline).foregroundStyle(muted)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) { periodFigures }
                VStack(alignment: .leading, spacing: 18) { periodFigures }
            }
            if let average = UsageDashboardPresentation.average(current) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(duration(average)).font(.system(.title, design: .serif)).foregroundStyle(accent)
                    Text(insightsText("Average per day")).font(.caption).foregroundStyle(muted)
                }.accessibilityElement(children: .combine)
            }
            Text(insightsText("Today is excluded from trends.")).font(.caption).foregroundStyle(muted)
        }
        .padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { rule }
        .overlay(alignment: .bottom) { rule }
    }
    @ViewBuilder private var periodFigures: some View {
        periodFigure(current, title: "This period")
        if let previous { periodFigure(previous, title: "Previous period") }
        else { VStack(alignment: .leading, spacing: 7) { Text(insightsText("Previous period")).font(.caption); Text(insightsText("— No data")).font(.title3) }.foregroundStyle(muted) }
    }
    private func periodFigure(_ period: UsageInsightsPeriod, title: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(insightsText(title)).font(.caption).foregroundStyle(muted)
            Text(duration(period.seconds)).font(.system(.title2, design: .serif)).monospacedDigit()
            Text(range(period)).font(.caption2).foregroundStyle(muted)
            if !period.isComplete { Text(insightsText("Partial reported coverage")).font(.caption2).foregroundStyle(muted) }
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
    private var weekChart: some View {
        let maximum = max(1, usage.weeks.compactMap(\.seconds).max() ?? 1)
        return VStack(alignment: .leading, spacing: 18) {
            heading("Four-week picture")
            Text(insightsText("Tap a week to explore it.")).font(.caption).foregroundStyle(muted)
            ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(usage.weeks) { week in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                                selectedStart = week.start; selectedDay = nil
                            }
                        } label: {
                            VStack(spacing: 10) {
                                Text(duration(week.seconds)).font(.caption2).monospacedDigit().foregroundStyle(muted)
                                stem(week.seconds, maximum: maximum, width: 34, color: accent.opacity(week.start == current.start ? 1 : 0.30), complete: week.isComplete)
                                    .frame(height: 125)
                                Text(date(week.start)).font(.caption2).foregroundStyle(week.start == current.start ? accent : muted)
                                Circle().fill(week.start == current.start ? accent : .clear).frame(width: 4, height: 4)
                            }.frame(minWidth: dynamicTypeSize.isAccessibilitySize ? 70 : 66, minHeight: 175)
                        }.buttonStyle(.plain).id(week.start).accessibilityLabel(range(week))
                            .accessibilityValue(duration(week.seconds) + ", " + insightsText(week.isComplete ? "Full reported coverage" : "Partial reported coverage"))
                            .accessibilityAddTraits(week.start == current.start ? .isSelected : [])
                    }
                }.padding(.bottom, 4)
            }
            .onAppear { reader.scrollTo(current.start, anchor: .trailing) }
            .onChange(of: current.start) { start in reader.scrollTo(start, anchor: .trailing) }
            }
            Text(range(current)).font(.caption).foregroundStyle(muted)
        }
    }
    private var dailyComparison: some View {
        let a = currentDays, b = priorDays
        let maximum = max(1, (a + b).compactMap(\.seconds).max() ?? 1)
        return VStack(alignment: .leading, spacing: 18) {
            heading("Your week, day by day")
            HStack(spacing: 18) { legend("This period", faded: false); legend("Previous period", faded: true) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(a.indices, id: \.self) { index in
                        dailyBar(a[index], prior: index < b.count ? b[index] : nil, maximum: maximum)
                    }
                }.padding(.bottom, 4)
            }
            if let index = a.firstIndex(where: { $0.date == selectedDay }) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) { selectedDayFigures(index, current: a, previous: b) }
                    VStack(alignment: .leading, spacing: 18) { selectedDayFigures(index, current: a, previous: b) }
                }
            }
            Text(insightsText("Each bar shows reported minutes. A dash means no data, not zero.")).font(.caption).foregroundStyle(muted)
        }
    }
    private func dailyBar(_ day: UsageInsightsDay, prior: UsageInsightsDay?, maximum: TimeInterval) -> some View {
        let value = insightsText("This period") + ": " + duration(day.seconds)
            + ", " + dayCoverage(day)
            + "; " + insightsText("Previous period") + ": " + duration(prior?.seconds)
            + ", " + dayCoverage(prior)
        return Button { selectedDay = day.date } label: {
            VStack(spacing: 10) {
                HStack(alignment: .bottom, spacing: 4) {
                    stem(prior?.seconds, maximum: maximum, width: 13, color: accent.opacity(0.28), complete: prior?.isComplete == true)
                    stem(day.seconds, maximum: maximum, width: 13, color: accent, complete: day.isComplete)
                }.frame(height: 125)
                Text(date(day.date, template: "EEE")).font(.caption2).foregroundStyle(muted)
                Circle().fill(day.date == selectedDay ? accent : .clear).frame(width: 4, height: 4)
            }.frame(minWidth: dynamicTypeSize.isAccessibilitySize ? 64 : 44, minHeight: 165)
        }.buttonStyle(.plain).accessibilityLabel(date(day.date, template: "EEEEMMMMd"))
            .accessibilityValue(value)
            .accessibilityAddTraits(day.date == selectedDay ? .isSelected : [])
    }
    @ViewBuilder private func selectedDayFigures(_ index: Int, current: [UsageInsightsDay], previous: [UsageInsightsDay]) -> some View {
        dayFigure(current[index], title: "This period")
        if index < previous.count { dayFigure(previous[index], title: "Previous period") }
    }
    private func legend(_ key: String, faded: Bool) -> some View {
        HStack(spacing: 6) { Circle().fill(accent.opacity(faded ? 0.28 : 1)).frame(width: 6, height: 6); Text(insightsText(key)) }
            .font(.caption).foregroundStyle(muted)
    }
    private func stem(_ seconds: TimeInterval?, maximum: TimeInterval, width: CGFloat, color: Color, complete: Bool) -> some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if let fraction = UsageDashboardPresentation.barFraction(seconds, maximum: maximum) {
                if fraction == 0 { Circle().stroke(color, lineWidth: 1.5).frame(width: 5, height: 5) }
                else {
                    RoundedRectangle(cornerRadius: 5).fill(color.opacity(complete ? 1 : 0.55))
                        .frame(width: width, height: max(1.5, fraction * 120))
                        .overlay(alignment: .top) { if !complete { Rectangle().fill(paper).frame(height: 2).padding(.top, 3) } }
                }
            } else {
                RoundedRectangle(cornerRadius: 4).stroke(muted.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .frame(width: width, height: 14)
            }
        }.frame(width: max(width, 16), height: 125).accessibilityHidden(true)
    }
    private var weekdayPatterns: some View {
        let patterns = UsageTrendsModel.weekdayPatterns(usage)
        let maximum = max(1, patterns.compactMap(\.averageSeconds).max() ?? 1)
        return VStack(alignment: .leading, spacing: 20) {
            heading("Weekday patterns")
            Text(format("%@ – %@", date(usage.weeks.first?.start ?? current.start),
                date(usage.calendar.date(byAdding: .day, value: -1, to: usage.calendar.startOfDay(for: usage.generatedAt))!)))
                .font(.caption).foregroundStyle(muted)
            ForEach(patterns) { pattern in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(weekday(pattern.weekday)).font(.subheadline)
                        Spacer(minLength: 8)
                        Text(duration(pattern.averageSeconds)).font(.subheadline).monospacedDigit().foregroundStyle(accent)
                        Text(format("%d days", pattern.sampleCount)).font(.caption2).foregroundStyle(muted)
                    }
                    GeometryReader { geometry in
                        Capsule().fill(accent.opacity(0.07))
                        if let fraction = UsageDashboardPresentation.barFraction(pattern.averageSeconds, maximum: maximum) {
                            Capsule().fill(accent.opacity(0.55)).frame(width: geometry.size.width * fraction)
                        }
                    }.frame(height: 4).accessibilityHidden(true)
                }.accessibilityElement(children: .combine)
            }
            Text(insightsText("Averages use only fully reported days.")).font(.caption).foregroundStyle(muted)
        }
    }
    private var extremeDays: some View {
        let values = UsageTrendsModel.extremes(usage, in: current)
        return VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 32) { extremeFigures(values) }
                VStack(alignment: .leading, spacing: 24) { extremeFigures(values) }
            }
            Text(insightsText("Among fully reported days in this period.")).font(.caption).foregroundStyle(muted)
        }.padding(.vertical, 24).overlay(alignment: .top) { rule }.overlay(alignment: .bottom) { rule }
    }
    @ViewBuilder private func extremeFigures(_ values: (high: UsageInsightsDay?, low: UsageInsightsDay?)) -> some View {
        dayFigure(values.high, title: "Most used day")
        dayFigure(values.low, title: "Least used day")
    }
    private func dayFigure(_ day: UsageInsightsDay?, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insightsText(title)).font(.caption).foregroundStyle(muted)
            Text(duration(day?.seconds)).font(.system(.title2, design: .serif)).foregroundStyle(accent)
            if let day {
                Text(date(day.date, template: "EEEMMMd")).font(.caption2).foregroundStyle(muted)
                if !day.isComplete { Text(insightsText("Partial reported coverage")).font(.caption2).foregroundStyle(muted) }
            }
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
    private var appChanges: some View {
        let changes = Array(UsageTrendsModel.appChanges(applications, current: current, previous: previous).prefix(5))
        return VStack(alignment: .leading, spacing: 20) {
            heading("Biggest app changes")
            if changes.isEmpty { Text(insightsText("No comparable app changes yet.")).font(.subheadline).foregroundStyle(muted) }
            ForEach(changes) { change in
                Button { onSelectApp(change.id) } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 12) {
                            applicationLabel(change.id).id(applicationIdentity(change.id)).labelStyle(.titleAndIcon)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(signedDuration(change.trend.differenceMinutes)).monospacedDigit().foregroundStyle(accent)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(muted).accessibilityHidden(true)
                        }.font(.subheadline)
                        Text(duration(change.previous.seconds) + " → " + duration(change.current.seconds)).font(.caption).foregroundStyle(muted)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityElement(children: .combine)
            }
            Text(insightsText("Only apps with full coverage in both periods.")).font(.caption).foregroundStyle(muted)
            Text(insightsText("These app changes do not add up to the overall difference.")).font(.caption).foregroundStyle(muted)
        }
    }
    private func baselineComparison(_ baseline: UsageInsightsBaseline) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Compared with your starting estimate")
            Text(duration(Double(baseline.weeklyMinutes) * 60)).font(.system(.title, design: .serif)).foregroundStyle(accent)
            Text(format("Recorded on %@", date(baseline.recordedAt, template: "yMMMd"))).font(.caption).foregroundStyle(muted)
            Text(insightsText("Your estimate, not measured Screen Time or a goal.")).font(.caption).foregroundStyle(muted)
            if current.isComplete, let seconds = current.seconds {
                Text(format("Compared with your estimate: %@", signedDuration(seconds / 60 - Double(baseline.weeklyMinutes)))).font(.subheadline)
                Text(insightsText("Your estimate is self-reported; this comparison does not measure time saved by Demora.")).font(.caption).foregroundStyle(muted)
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
    }
    private var coverage: some View {
        let values = UsageTrendsModel.coverage(usage)
        let days = usage.days.filter { $0.date < usage.calendar.startOfDay(for: usage.generatedAt) }
        return VStack(alignment: .leading, spacing: 18) {
            heading("Report coverage")
            ScrollView(.horizontal, showsIndicators: false) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(coverageCellSize), spacing: 10), count: 7), spacing: 10) {
                ForEach(days) { day in
                    ZStack {
                        if day.seconds == nil { Circle().stroke(muted.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 3])) }
                        else if day.isComplete { Circle().fill(accent.opacity(0.75)) }
                        else { Circle().stroke(accent, lineWidth: 1.5) }
                        Text(date(day.date, template: "d")).font(.caption2).foregroundStyle(day.isComplete ? paper : muted)
                    }.frame(width: coverageCellSize, height: coverageCellSize).accessibilityElement(children: .ignore)
                        .accessibilityLabel(date(day.date, template: "EEEEMMMMd"))
                        .accessibilityValue(insightsText(day.seconds == nil ? "Missing days" : (day.isComplete ? "Complete days" : "Partial days")))
                }
            }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { coverageFigures(values) }
                VStack(alignment: .leading, spacing: 14) { coverageFigures(values) }
            }
            Text(insightsText("Screen Time may report incomplete or delayed data. Missing days are not counted as zero.")).font(.caption).foregroundStyle(muted)
            Text(insightsText("Today is excluded from trends.")).font(.caption).foregroundStyle(muted)
        }
    }
    private func dayCoverage(_ day: UsageInsightsDay?) -> String {
        guard let day, let seconds = day.seconds, seconds.isFinite, seconds >= 0 else { return insightsText("Missing days") }
        return insightsText(day.isComplete ? "Full reported coverage" : "Partial reported coverage")
    }
    @ViewBuilder private func coverageFigures(_ values: (complete: Int, partial: Int, missing: Int)) -> some View {
        coverageFigure(values.complete, title: "Complete days")
        coverageFigure(values.partial, title: "Partial days")
        coverageFigure(values.missing, title: "Missing days")
    }
    private func coverageFigure(_ count: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(number(Double(count))).font(.system(.title, design: .serif)).foregroundStyle(accent)
            Text(insightsText(title)).font(.caption).foregroundStyle(muted)
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
    private var rule: some View { Rectangle().fill(muted.opacity(0.18)).frame(height: 0.5) }
    private func heading(_ key: String) -> some View { Text(insightsText(key)).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader) }
    private func format(_ key: String, _ values: CVarArg...) -> String { String(format: insightsText(key), locale: locale, arguments: values) }
    private func number(_ value: Double) -> String {
        let f = NumberFormatter(); f.locale = locale; f.numberStyle = .decimal; f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: value)) ?? "—"
    }
    private func signed(_ value: Double) -> String { (value > 0 ? "+" : "") + number(value) }
    private func signedDuration(_ minutes: Double) -> String { format("%@ min", signed(minutes)) }
    private func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return insightsText("— No data") }
        let minutes = floor(seconds / 60)
        return minutes < 60 ? format("%@ min", number(minutes)) : format("%@ h %@ min", number(floor(minutes / 60)), number(minutes.truncatingRemainder(dividingBy: 60)))
    }
    private func date(_ date: Date, template: String = "MMMd") -> String {
        let f = DateFormatter(); f.locale = locale; f.calendar = usage.calendar; f.timeZone = usage.calendar.timeZone
        f.setLocalizedDateFormatFromTemplate(template); return f.string(from: date)
    }
    private func weekday(_ day: Int) -> String {
        let f = DateFormatter(); f.locale = locale; return f.weekdaySymbols[day - 1]
    }
    private func range(_ period: UsageInsightsPeriod) -> String {
        format("%@ – %@", date(period.start), date(usage.calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.start))
    }
}
