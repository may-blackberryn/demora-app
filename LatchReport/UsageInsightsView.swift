import SwiftUI
import Foundation

struct UsageInsightsView: View {
    let configuration: UsageInsightsConfiguration
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 56
    @State private var weekly = false
    @State private var page = 0
    @State private var selectedDay: Date?
    @State private var selectedWeek: Date?
    @State private var showingDetails = false

    init(configuration: UsageInsightsConfiguration, initiallyWeekly: Bool = false) {
        self.configuration = configuration
        _weekly = State(initialValue: initiallyWeekly)
    }

    // Read-only preferences. Selection, layout and measured values stay here.
    private var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.id) }
    private var locale: Locale {
        let supported = ["en", "es", "de", "fr", "pt", "pl", "tr", "hi"]
        if let saved = defaults?.string(forKey: "latch.language"), supported.contains(saved) { return Locale(identifier: saved) }
        let preferred = Locale.preferredLanguages.first ?? "en"
        let code = Locale(identifier: preferred).language.languageCode?.identifier ?? String(preferred.prefix(2))
        return Locale(identifier: supported.contains(code) ? code : "en")
    }
    private var scheme: ColorScheme {
        switch defaults?.string(forKey: "latch.appearance") {
        case "light": return .light
        case "dark": return .dark
        default: return systemScheme
        }
    }
    private var accent: Color {
        if defaults?.string(forKey: "latch.accentColor") == "red" {
            return scheme == .dark ? Color(red: 0.85, green: 0.53, blue: 0.48) : Color(red: 0.64, green: 0.23, blue: 0.18)
        }
        return scheme == .dark ? Color(red: 0.63, green: 0.77, blue: 0.85) : Color(red: 0.20, green: 0.37, blue: 0.47)
    }
    private var ink: Color { scheme == .dark ? Color(red: 0.94, green: 0.93, blue: 0.90) : Color(red: 0.15, green: 0.18, blue: 0.20) }
    private var muted: Color { scheme == .dark ? Color(red: 0.65, green: 0.69, blue: 0.69) : Color(red: 0.40, green: 0.43, blue: 0.43) }
    private var paper: Color { scheme == .dark ? Color(red: 0.10, green: 0.11, blue: 0.11) : Color(red: 0.965, green: 0.953, blue: 0.922) }
    private var window: [UsageInsightsDay] { UsageDashboardPresentation.window(configuration.days, page: page) }
    private var day: UsageInsightsDay? { window.first { $0.date == selectedDay } ?? window.last }
    private var week: UsageInsightsPeriod { configuration.weeks.first { $0.start == selectedWeek } ?? configuration.lastSevenDays }
    private var comparisonCurrent: UsageInsightsPeriod { weekly ? week : configuration.lastSevenDays }
    private var comparisonPrevious: UsageInsightsPeriod? {
        weekly ? UsageDashboardPresentation.preceding(week, in: configuration.weeks) : configuration.previousSevenDays
    }
    private var comparisonTrend: UsageInsightsTrend? {
        guard let previous = comparisonPrevious else { return nil }
        return UsageInsightsTrend.compare(comparisonCurrent, with: previous)
    }

    var body: some View {
        // A single report-owned dashboard. No usage, height or readiness export.
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                rangeControl
                if configuration.reportedDays == 0 { emptyState }
                else { usageHero; chartSection; comparison }
                if let baseline = configuration.baseline { baselineSummary(baseline) }
                details
            }
            .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 24)
            .frame(maxWidth: 740).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(paper).foregroundStyle(ink)
        .environment(\.colorScheme, scheme).environment(\.locale, locale)
    }

    private var rangeControl: some View {
        HStack(spacing: 4) {
            rangeButton("Daily", isWeekly: false)
            rangeButton("Weekly", isWeekly: true)
        }
        .padding(4).background(accent.opacity(scheme == .dark ? 0.12 : 0.08), in: Capsule())
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 300)
        .frame(maxWidth: .infinity)
    }
    private func rangeButton(_ title: String, isWeekly: Bool) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { weekly = isWeekly }
        } label: {
            Text(insightsText(title)).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 10)
                .foregroundStyle(weekly == isWeekly ? paper : muted)
                .background(weekly == isWeekly ? accent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityAddTraits(weekly == isWeekly ? .isSelected : [])
    }

    private var usageHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(weekly ? dateRange(week) : date(day?.date ?? configuration.generatedAt, template: "EEEE, MMMd"))
                .font(.subheadline.weight(.medium)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            Text(duration(weekly ? week.seconds : day?.seconds))
                .font(.system(size: min(figureSize, 90), weight: .regular, design: .serif))
                .tracking(-1.8).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(accent).accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(accent).frame(width: 5, height: 5).padding(.top, 5).accessibilityHidden(true)
                Text(insightsText(weekly ? (week.isComplete ? "Full reported coverage" : "Partial reported coverage")
                    : (day?.date == configuration.today?.date ? "Today so far"
                        : (day?.isComplete == true ? "Full reported coverage" : "Partial reported coverage"))))
                    .font(.caption).foregroundStyle(muted)
            }
            if weekly, let average = UsageDashboardPresentation.average(week) {
                HStack(spacing: 8) {
                    Text(insightsText("Average per day")).foregroundStyle(muted)
                    Text(duration(average)).foregroundStyle(accent)
                }.font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                heading(weekly ? "Weekly totals" : "Daily usage")
                Spacer(minLength: 4)
                if !weekly {
                    pageButton("Previous week", symbol: "chevron.left", enabled: page < UsageDashboardPresentation.lastPage(dayCount: configuration.days.count)) {
                        page += 1; selectedDay = nil
                    }
                    pageButton("Next week", symbol: "chevron.right", enabled: page > 0) { page -= 1; selectedDay = nil }
                }
            }
            Text(weekly ? insightsText("Four completed seven-day periods; today is shown separately.") : windowRange)
                .font(.caption).foregroundStyle(muted)
            chart
            Text(insightsText(weekly ? "Tap a bar to see that week." : "Tap a bar to see that day."))
                .font(.caption).foregroundStyle(muted)
        }
    }
    private func pageButton(_ key: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption.weight(.semibold)).frame(width: 44, height: 44)
                .background(accent.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain).foregroundStyle(accent).disabled(!enabled).opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(insightsText(key))
    }

    private var chart: some View {
        let values = weekly ? configuration.weeks.compactMap(\.seconds) : window.compactMap(\.seconds)
        let maximum = max(1, values.max() ?? 1)
        let count = weekly ? configuration.weeks.count : window.count
        return GeometryReader { geometry in
            // Narrow screens can scroll horizontally; every target stays >=44pt.
            ZStack(alignment: .topLeading) {
            ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .top) {
                    VStack {
                        Rectangle().fill(muted.opacity(0.14)).frame(height: 0.5)
                            .frame(height: 22, alignment: .bottom); Spacer()
                        Rectangle().fill(muted.opacity(0.14)).frame(height: 0.5); Spacer()
                        Rectangle().fill(muted.opacity(0.14)).frame(height: 0.5)
                    }.frame(height: 154).accessibilityHidden(true)
                    HStack(alignment: .bottom, spacing: 6) {
                        if weekly {
                            ForEach(configuration.weeks) { item in
                                bar(seconds: item.seconds, maximum: maximum, selected: week.start == item.start,
                                    label: date(item.start), accessibility: dateRange(item), complete: item.isComplete) {
                                    selectedWeek = item.start
                                }
                                .id(item.start)
                            }
                        } else {
                            ForEach(window) { item in
                                bar(seconds: item.seconds, maximum: maximum, selected: day?.date == item.date,
                                    label: date(item.date, template: "EEEd"), accessibility: date(item.date, template: "EEEEMMMMd"),
                                    complete: item.isComplete) { selectedDay = item.date }
                                    .id(item.date)
                            }
                        }
                    }.padding(.top, 20)
                }
                .frame(width: max(geometry.size.width, CGFloat(count * (dynamicTypeSize.isAccessibilitySize ? 64 : 44) + max(0, count - 1) * 6)))
            }
            .onAppear { if let id = chartSelectionID { reader.scrollTo(id, anchor: .trailing) } }
            .onChange(of: chartSelectionID) { id in if let id { reader.scrollTo(id, anchor: .trailing) } }
            }
            Text(duration(maximum)).font(.system(size: 9, design: .monospaced))
                .foregroundStyle(muted).accessibilityHidden(true).allowsHitTesting(false)
            }
        }.frame(height: dynamicTypeSize.isAccessibilitySize ? 295 : 215)
    }
    private var chartSelectionID: Date? { weekly ? week.start : day?.date }
    private func bar(seconds: TimeInterval?, maximum: TimeInterval, selected: Bool, label: String,
                     accessibility: String, complete: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                ZStack(alignment: .bottom) {
                    Color.clear
                    if let fraction = UsageDashboardPresentation.barFraction(seconds, maximum: maximum) {
                        if fraction == 0 { Circle().stroke(accent, lineWidth: 1.5).frame(width: 6, height: 6) }
                        else {
                            RoundedRectangle(cornerRadius: 6).fill(selected ? accent : accent.opacity(complete ? 0.34 : 0.18))
                                .frame(width: weekly ? 34 : 22, height: max(1.5, fraction * 132))
                                .overlay(alignment: .top) {
                                    if !complete { Rectangle().fill(paper.opacity(0.65)).frame(height: 2).padding(.top, 4) }
                                }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 5).stroke(muted.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                            .frame(width: weekly ? 34 : 22, height: 18)
                    }
                }.frame(height: 134)
                Text(label).font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? accent : muted).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Circle().fill(selected ? accent : Color.clear).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 185, alignment: .top).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(accessibility)
        .accessibilityValue(duration(seconds) + ", " + insightsText(seconds == nil ? "— No data" : (complete ? "Full reported coverage" : "Partial reported coverage")))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Compared with the previous week")
            if let trend = comparisonTrend {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: trend.differenceMinutes == 0 ? "arrow.right" : (trend.differenceMinutes < 0 ? "arrow.down.right" : "arrow.up.right"))
                        .font(.system(size: 28, weight: .light)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trend.percentage.map { format("Change: %@%%", signedNumber($0)) }
                            ?? format("Change: %@", signedMinutes(trend.differenceMinutes)))
                            .font(.system(.title2, design: .serif)).monospacedDigit()
                        if trend.percentage != nil { Text(format("Change: %@", signedMinutes(trend.differenceMinutes))).font(.caption) }
                    }
                }.foregroundStyle(accent).accessibilityElement(children: .combine)
            } else {
                Text(insightsText("No trend yet")).font(.system(.title2, design: .serif))
                Text(insightsText("A trend needs full reported coverage for both completed periods.")).font(.caption).foregroundStyle(muted)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { comparisonFigures }
                VStack(alignment: .leading, spacing: 18) { comparisonFigures }
            }
            Text(insightsText("Today is not included in this comparison.")).font(.caption).foregroundStyle(muted)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(scheme == .dark ? 0.08 : 0.045), in: RoundedRectangle(cornerRadius: 24))
    }
    @ViewBuilder private var comparisonFigures: some View {
        comparisonFigure(comparisonCurrent, title: weekly ? "Week" : "Last seven completed days")
        if let previous = comparisonPrevious {
            comparisonFigure(previous, title: weekly ? "Previous week" : "Previous seven completed days")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(insightsText("Previous week")).font(.caption).foregroundStyle(muted)
                Text(insightsText("— No data")).font(.system(.title3, design: .serif))
            }
        }
    }
    private func comparisonFigure(_ period: UsageInsightsPeriod, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(insightsText(title)).font(.caption).foregroundStyle(muted)
            Text(duration(period.seconds)).font(.system(.title3, design: .serif)).monospacedDigit()
            Text(dateRange(period)).font(.caption2).foregroundStyle(muted)
            if !period.isComplete { Text(insightsText("Partial reported coverage")).font(.caption2).foregroundStyle(muted) }
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
    private func baselineSummary(_ baseline: UsageInsightsBaseline) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Rectangle().fill(accent.opacity(0.5)).frame(width: 2)
            VStack(alignment: .leading, spacing: 9) {
                heading("Self-reported weekly baseline")
                Text(duration(Double(baseline.weeklyMinutes) * 60)).font(.system(.title2, design: .serif)).foregroundStyle(accent)
                Text(format("Recorded on %@", date(baseline.recordedAt, template: "yMMMd"))).font(.caption).foregroundStyle(muted)
                Text(insightsText("Your estimate, not measured Screen Time or a goal.")).font(.caption).foregroundStyle(muted)
                if let difference = configuration.baselineDifferenceMinutes {
                    Text(format("Compared with your estimate: %@", signedMinutes(difference))).font(.subheadline).foregroundStyle(accent)
                    Text(insightsText("Your estimate is self-reported; this comparison does not measure time saved by Demora.")).font(.caption).foregroundStyle(muted)
                }
            }
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 46, weight: .ultraLight)).foregroundStyle(accent)
            Text(insightsText("— No data")).font(.system(.largeTitle, design: .serif))
            Text(insightsText("No usage data was reported for this period. This does not mean zero use.")).font(.subheadline).foregroundStyle(muted)
        }.padding(.vertical, 35)
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { showingDetails.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle"); Text(insightsText("Usage details")); Spacer()
                    Image(systemName: showingDetails ? "minus" : "plus").font(.caption)
                }.font(.subheadline).foregroundStyle(muted).frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityValue(showingDetails ? insightsText("Expanded") : insightsText("Compact"))
            if showingDetails {
                Text(insightsText("28 completed days plus today"))
                Text(format("%d of %d days reported", configuration.reportedDays, configuration.days.count))
                Text(insightsText("Screen Time may report incomplete or delayed data. Missing days are not counted as zero."))
                Text(insightsText("Each bar shows reported minutes. A dash means no data, not zero."))
                Text(format("%d of %d days with full reported coverage", comparisonCurrent.completeDays, comparisonCurrent.expectedDays))
                if comparisonTrend?.percentage == nil && comparisonPrevious?.isComplete == true && comparisonPrevious?.seconds == 0 {
                    Text(insightsText("No percentage: the previous period reported zero minutes."))
                }
            }
        }.font(.caption).foregroundStyle(muted)
    }
    private func heading(_ key: String) -> some View { Text(insightsText(key)).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader) }
    private var windowRange: String {
        guard let first = window.first, let last = window.last else { return insightsText("— No data") }
        return format("%@ – %@", date(first.date), date(last.date))
    }
    private func format(_ key: String, _ values: CVarArg...) -> String { String(format: insightsText(key), locale: locale, arguments: values) }
    private func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return insightsText("— No data") }
        let minutes = floor(seconds / 60)
        if minutes < 60 { return format("%@ min", number(minutes)) }
        return format("%@ h %@ min", number(floor(minutes / 60)), number(minutes.truncatingRemainder(dividingBy: 60)))
    }
    private func signedMinutes(_ minutes: Double) -> String { format("%@ min", signedNumber(minutes)) }
    private func signedNumber(_ value: Double) -> String { (value > 0 ? "+" : "") + number(value) }
    private func number(_ value: Double) -> String {
        let formatter = NumberFormatter(); formatter.locale = locale; formatter.numberStyle = .decimal; formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }
    private func date(_ date: Date, template: String = "MMMd") -> String {
        let formatter = DateFormatter(); formatter.calendar = configuration.calendar; formatter.timeZone = configuration.calendar.timeZone; formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template); return formatter.string(from: date)
    }
    private func dateRange(_ period: UsageInsightsPeriod) -> String {
        let lastDay = configuration.calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.start
        return format("%@ – %@", date(period.start), date(lastDay))
    }
}
