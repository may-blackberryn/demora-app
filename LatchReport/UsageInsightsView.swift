import SwiftUI
import Foundation

// The Insights report (docs/insights-redesign.md §5.3–5.7). One view switch,
// Day · Week · Trends, drawn entirely inside the report's private process.
// No usage, selection, height or readiness value is exported to the host.
struct UsageInsightsView: View {
    let configuration: UsageInsightsConfiguration
    let applicationLabel: (Int) -> AnyView
    let applicationIdentity: (Int) -> AnyHashable
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 52
    @State private var selection = UsageInsightsSelection<AnyHashable>()
    @State private var selectedApplicationLabel: AnyView?

    init(configuration: UsageInsightsConfiguration, initialSegment: UsageInsightsSegment = .day,
         initiallySelectedApplication: Int? = nil,
         applicationLabel: @escaping (Int) -> AnyView = { _ in AnyView(Image(systemName: "app")) },
         applicationIdentity: @escaping (Int) -> AnyHashable = { AnyHashable($0) }) {
        self.configuration = configuration
        self.applicationLabel = applicationLabel
        self.applicationIdentity = applicationIdentity
        var selection = UsageInsightsSelection<AnyHashable>()
        selection.segment = initialSegment
        selection.application = initiallySelectedApplication.map(applicationIdentity)
        _selection = State(initialValue: selection)
        _selectedApplicationLabel = State(initialValue: initiallySelectedApplication.map(applicationLabel))
    }

    // Read-only preferences. Selection, layout and measured values stay here.
    private var preferences: ReportPreferences { ReportPreferences.read(system: systemScheme) }
    private var colors: ReportColors {
        let preferences = preferences
        return ReportColors(scheme: preferences.scheme, accentValue: preferences.accentValue)
    }
    private var locale: Locale { preferences.locale }
    private var text: UsageFormat { UsageFormat(locale: locale, translate: insightsText) }

    private var selectedApplication: AnyHashable? { selection.application }
    private var segment: UsageInsightsSegment { selection.segment }
    private var usage: UsageInsightsConfiguration {
        guard selectedApplication != nil else { return configuration }
        return configuration.applications.first { applicationIdentity($0.id) == selectedApplication }?.usage
            ?? UsageDashboardPresentation.unavailable(configuration)
    }
    private var selectedApplicationID: Int? {
        configuration.applications.first { applicationIdentity($0.id) == selectedApplication }?.id
    }
    private var window: [UsageInsightsDay] { UsageDashboardPresentation.window(usage.days, page: selection.page) }
    private var day: UsageInsightsDay? { window.first { $0.date == selection.day } ?? window.last }
    private var week: UsageInsightsPeriod { usage.weeks.first { $0.start == selection.week } ?? usage.lastSevenDays }
    private var isToday: Bool { day?.date == usage.today?.date }

    var body: some View {
        let colors = colors
        // A single report-owned scroll. No usage, height or readiness export.
        return ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                segmentControl(colors).id("usageTop")
                if selectedApplication != nil { applicationScope(colors) }
                Group {
                    switch segment {
                    case .day: daySegment(colors)
                    case .week: weekSegment(colors)
                    case .trends: trendsSegment(colors)
                    }
                }
                .transition(.opacity)
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 32)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.paper).foregroundStyle(colors.ink)
        .environment(\.colorScheme, colors.scheme).environment(\.locale, locale)
        .onChange(of: selectedApplication) { _ in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                reader.scrollTo("usageTop", anchor: .top)
            }
        }
        }
    }

    // MARK: View switch (§5.3)

    private func segmentControl(_ colors: ReportColors) -> some View {
        HStack(spacing: 4) {
            ForEach(UsageInsightsSegment.allCases, id: \.self) { item in
                segmentButton(item, colors)
            }
        }
        .padding(.horizontal, 4).background(colors.accentTint, in: Capsule())
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 360)
        .frame(maxWidth: .infinity)
    }
    private func segmentButton(_ item: UsageInsightsSegment, _ colors: ReportColors) -> some View {
        let selected = segment == item
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selection.show(item) }
        } label: {
            Text(insightsText(item.key)).font(.subheadline.weight(.medium))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 56 : 36)
                .padding(.horizontal, 8)
                .foregroundStyle(selected ? colors.card : colors.accent)
                .background(selected ? colors.accent : Color.clear, in: Capsule())
                // 36 pt pill in a 44 pt track (64 at accessibility sizes).
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func applicationScope(_ colors: ReportColors) -> some View {
        HStack(alignment: .center, spacing: 14) {
            if let scopeLabel {
                scopeLabel.reportType(.cardTitle).labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else { Spacer(minLength: 0) }
            Button { selection.showAllApps(); selectedApplicationLabel = nil } label: {
                Text(insightsText("All apps")).reportType(.chip)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(colors.accentTint, in: Capsule())
            }.buttonStyle(.plain).foregroundStyle(colors.accent)
        }
    }
    private var scopeLabel: AnyView? {
        if let id = selectedApplicationID {
            // Recreate only Apple's embedded label when its opaque app changes.
            // Never reset DeviceActivityReport or its measured configuration.
            return AnyView(applicationLabel(id).id(selectedApplication))
        } else if let selectedApplicationLabel {
            return AnyView(selectedApplicationLabel.id(selectedApplication))
        }
        return nil
    }
    private func selectApplication(_ id: Int) {
        selectedApplicationLabel = applicationLabel(id)
        selection.scope(to: applicationIdentity(id))
    }

    // MARK: Day (§5.4)

    @ViewBuilder private func daySegment(_ colors: ReportColors) -> some View {
        dayHero(colors)
        dayChart(colors)
        if selection.showsMostUsed { mostUsedApplications(colors) }
    }

    private func dayHero(_ colors: ReportColors) -> some View {
        let seconds = day?.seconds
        return VStack(alignment: .leading, spacing: 10) {
            Text(isToday ? insightsText("Today so far") : date(day?.date ?? configuration.generatedAt, template: "EEEEdMMMM"))
                .reportType(.label).foregroundStyle(colors.inkSoft).fixedSize(horizontal: false, vertical: true)
            heroTotal(seconds, colors)
            if UsageFormat.wholeMinutes(seconds) == nil {
                Text(insightsText("iOS hasn't reported any usage for this period. That doesn't mean zero use."))
                    .reportType(.meta).foregroundStyle(colors.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            if let average = UsageDashboardPresentation.lastWeekDailyAverage(usage) {
                Text(text.format("Your daily average last week: %@", text.duration(average)))
                    .reportType(.meta).foregroundStyle(colors.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            if UsageCoverageLabel.isPartlyReported(day, today: usage.today?.date) {
                ReportChip(text: insightsText(UsageCoverageLabel.partly), colors: colors)
            }
        }
        .reportCard(colors, padding: 20)
        .accessibilityElement(children: .combine)
    }

    /// The hero total in `timeLarge`, or "No data yet" in `hero` (§5.4).
    @ViewBuilder private func heroTotal(_ seconds: TimeInterval?, _ colors: ReportColors, emptyKey: String = "No data yet") -> some View {
        if UsageFormat.wholeMinutes(seconds) != nil {
            Text(text.duration(seconds))
                .font(.system(size: min(figureSize, 84), weight: .regular, design: .serif))
                .tracking(-1).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(colors.accent).accessibilityAddTraits(.isHeader)
        } else {
            Text(insightsText(emptyKey)).reportType(.hero).foregroundStyle(colors.inkSoft)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func dayChart(_ colors: ReportColors) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                pageButton("Previous week", symbol: "chevron.left", colors: colors,
                           enabled: selection.page < UsageDashboardPresentation.lastPage(dayCount: usage.days.count)) {
                    selection.pageBack(dayCount: usage.days.count)
                }
                Text(windowRange).reportType(.meta).foregroundStyle(colors.inkSoft)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                pageButton("Next week", symbol: "chevron.right", colors: colors, enabled: selection.page > 0) {
                    selection.pageForward()
                }
            }
            dayBars(colors)
        }
        .reportCard(colors)
    }
    private func pageButton(_ key: String, symbol: String, colors: ReportColors, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.medium)).frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(colors.inkSoft).disabled(!enabled).opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(insightsText(key))
    }

    private func dayBars(_ colors: ReportColors) -> some View {
        let values = window.compactMap { item in UsageFormat.wholeMinutes(item.seconds) == nil ? nil : item.seconds }
        let maximum = max(1, values.max() ?? 1)
        let count = window.count
        return GeometryReader { geometry in
            // Narrow screens can scroll horizontally; every target stays >=44pt.
            ZStack(alignment: .topLeading) {
            ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        Rectangle().fill(colors.hairline).frame(height: 1).padding(.top, 20)
                        Spacer()
                        Rectangle().fill(colors.hairline).frame(height: 1)
                    }.frame(height: 155).accessibilityHidden(true)
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(window) { item in
                            dayBar(item, maximum: maximum, selected: day?.date == item.date, colors: colors)
                                .id(item.date)
                        }
                    }.padding(.top, 20)
                }
                .frame(width: max(geometry.size.width, CGFloat(count * (dynamicTypeSize.isAccessibilitySize ? 64 : 44))))
            }
            .onAppear { if let id = day?.date { reader.scrollTo(id, anchor: .trailing) } }
            .onChange(of: day?.date) { id in if let id { reader.scrollTo(id, anchor: .trailing) } }
            }
            // The top hairline carries the scale.
            if !values.isEmpty {
                Text(text.compact(maximum)).reportType(.chip)
                    .foregroundStyle(colors.inkSoft).accessibilityHidden(true).allowsHitTesting(false)
            }
            }
        }.frame(height: dynamicTypeSize.isAccessibilitySize ? 250 : 180)
    }

    private func dayBar(_ item: UsageInsightsDay, maximum: TimeInterval, selected: Bool, colors: ReportColors) -> some View {
        let note = UsageCoverageLabel.accessibilityKey(item, today: usage.today?.date)
        let complete = !UsageCoverageLabel.isPartlyReported(item, today: usage.today?.date)
        return Button { selection.selectDay(item.date) } label: {
            VStack(spacing: 8) {
                UsageBarStem(seconds: item.seconds, maximum: maximum, width: 22, height: 132,
                             fill: selected ? colors.accent : colors.accent.opacity(complete ? 0.34 : 0.18),
                             complete: complete, colors: colors)
                Text(date(item.date, template: "EEE")).reportType(.chip)
                    .foregroundStyle(selected ? colors.accent : colors.inkSoft)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? 64 : 44, maxWidth: .infinity, minHeight: 160, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(date(item.date, template: "EEEEMMMMd"))
        // Missing already reads "No data yet"; only partial adds a note.
        .accessibilityValue(note == UsageCoverageLabel.partly
                            ? text.duration(item.seconds) + ", " + insightsText(UsageCoverageLabel.partly)
                            : text.duration(item.seconds))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Week (§5.5)

    @ViewBuilder private func weekSegment(_ colors: ReportColors) -> some View {
        weekHero(colors)
        fourWeeks(colors)
        if selection.showsMostUsed { mostUsedApplications(colors) }
    }

    private func weekHero(_ colors: ReportColors) -> some View {
        let comparison = UsageWeekComparison.make(week, in: usage.weeks)
        return VStack(alignment: .leading, spacing: 10) {
            Text(periodTitle(week, withRange: true))
                .reportType(.label).foregroundStyle(colors.inkSoft).fixedSize(horizontal: false, vertical: true)
            heroTotal(week.seconds, colors, emptyKey: UsagePeriodName.emptyKey(usage))
            if let average = UsageDashboardPresentation.average(week) {
                Text(text.format("%@ a day", text.duration(average)))
                    .reportType(.meta).foregroundStyle(colors.inkSoft)
            }
            switch comparison {
            case .sentence(let sentence):
                // Neutral ink for less and more alike (decision I2).
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let symbol = sentence.symbol {
                        Image(systemName: symbol).font(.body.weight(.medium)).accessibilityHidden(true)
                    }
                    Text(sentence.sentence(text)).reportType(.body).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(colors.ink)
            case .needsFullData, .noEarlierWeek:
                Text(insightsText(comparison.key ?? "")).reportType(.meta).foregroundStyle(colors.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if UsageCoverageLabel.isPartlyReported(week) {
                ReportChip(text: insightsText(UsageCoverageLabel.partly), colors: colors)
            }
        }
        .reportCard(colors, padding: 20)
        .accessibilityElement(children: .combine)
    }

    /// The four rolling weeks; tapping one selects it for the hero, Most used
    /// apps and Trends (shared by Week and Trends).
    private func fourWeeks(_ colors: ReportColors) -> some View {
        let maximum = max(1, usage.weeks.compactMap { UsageFormat.wholeMinutes($0.seconds) != nil ? $0.seconds : nil }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            ReportSectionHeader(title: insightsText("Four weeks"), colors: colors)
            ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(usage.weeks) { item in
                        let selected = item.start == week.start
                        let complete = !UsageCoverageLabel.isPartlyReported(item)
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { selection.selectWeek(item.start) }
                        } label: {
                            VStack(spacing: 8) {
                                Text(text.compact(item.seconds)).reportType(.chip).monospacedDigit()
                                    .foregroundStyle(selected ? colors.accent : colors.inkSoft)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                UsageBarStem(seconds: item.seconds, maximum: maximum, width: 34, height: 110,
                                             fill: selected ? colors.accent : colors.accent.opacity(complete ? 0.34 : 0.18),
                                             complete: complete, colors: colors)
                                Text(date(item.start)).reportType(.chip)
                                    .foregroundStyle(selected ? colors.accent : colors.inkSoft).lineLimit(1)
                            }
                            .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? 76 : 66, maxWidth: .infinity, minHeight: 170)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).id(item.start)
                        .accessibilityLabel(range(item))
                        .accessibilityValue(UsageCoverageLabel.isPartlyReported(item)
                            ? text.duration(item.seconds) + ", " + insightsText(UsageCoverageLabel.partly)
                            : text.duration(item.seconds))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }.frame(maxWidth: .infinity)
            }
            .onAppear { reader.scrollTo(week.start, anchor: .trailing) }
            .onChange(of: week.start) { start in reader.scrollTo(start, anchor: .trailing) }
            }
        }
        .reportCard(colors)
    }

    // MARK: Most used apps (§5.6)

    private var rankedApplications: [UsageInsightsApplication] {
        UsageDashboardPresentation.rankedApplications(configuration.applications,
            day: day?.date, week: segment == .week ? week.start : nil)
    }
    private func mostUsedApplications(_ colors: ReportColors) -> some View {
        let applications = rankedApplications
        let maximum = applications.first.flatMap { applicationSeconds($0) } ?? 1
        let visible = UsageDashboardPresentation.visibleApplications(applications, expanded: selection.showingAllApplications)
        return VStack(alignment: .leading, spacing: 10) {
            ReportSectionHeader(title: insightsText("Most used apps"), colors: colors)
            VStack(alignment: .leading, spacing: 12) {
                if applications.isEmpty {
                    Text(segment == .week ? insightsText("No app times reported for these 7 days.")
                                          : insightsText("No app times reported for this day."))
                        .reportType(.meta).foregroundStyle(colors.inkSoft).fixedSize(horizontal: false, vertical: true)
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(visible) { app in
                            applicationRow(app, maximum: max(1, maximum), colors: colors)
                        }
                    }
                    if applications.count > UsageDashboardPresentation.mostUsedLimit {
                        Button { selection.showingAllApplications.toggle() } label: {
                            Text(selection.showingAllApplications ? insightsText("Show fewer")
                                 : text.format("See all %d apps", applications.count))
                                .reportType(.meta).frame(minHeight: 44)
                        }.buttonStyle(.plain).foregroundStyle(colors.accent)
                    }
                }
            }
            .reportCard(colors)
            Text(insightsText("App times overlap, so they won't add up to your total."))
                .reportType(.meta).foregroundStyle(colors.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func applicationSeconds(_ app: UsageInsightsApplication) -> TimeInterval? {
        UsageDashboardPresentation.appSeconds(app, day: day?.date, week: segment == .week ? week.start : nil)
    }
    private func applicationPartlyReported(_ app: UsageInsightsApplication) -> Bool {
        if segment == .week {
            return app.usage.weeks.first { $0.start == week.start }.map(UsageCoverageLabel.isPartlyReported) ?? false
        }
        return UsageCoverageLabel.isPartlyReported(app.usage.days.first { $0.date == day?.date }, today: usage.today?.date)
    }
    private func applicationRow(_ app: UsageInsightsApplication, maximum: TimeInterval, colors: ReportColors) -> some View {
        let seconds = applicationSeconds(app)
        let partly = applicationPartlyReported(app)
        return Button { selectApplication(app.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    applicationLabel(app.id).id(applicationIdentity(app.id)).reportType(.body).labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(text.duration(seconds)).font(.system(.subheadline, design: .serif)).monospacedDigit()
                        .foregroundStyle(colors.accent)
                }
                GeometryReader { geometry in
                    Capsule().fill(colors.accentTint)
                    Capsule().fill(colors.accent.opacity(0.45))
                        .frame(width: max(0, geometry.size.width * (UsageDashboardPresentation.barFraction(seconds, maximum: maximum) ?? 0)))
                }.frame(height: 4).accessibilityHidden(true)
                if partly { ReportChip(text: insightsText(UsageCoverageLabel.partly), colors: colors) }
            }.frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 64 : 44)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityElement(children: .combine)
    }

    // MARK: Trends (§5.7)

    @ViewBuilder private func trendsSegment(_ colors: ReportColors) -> some View {
        fourWeeks(colors)
        UsageTrendsView(usage: usage, applications: configuration.applications,
            baseline: selectedApplication == nil ? configuration.baseline : nil,
            isAppScope: selectedApplication != nil, current: week,
            applicationLabel: applicationLabel, applicationIdentity: applicationIdentity,
            colors: colors, text: text, locale: locale,
            onSelectApp: selectApplication)
    }

    // MARK: Text

    /// "LAST 7 FULL DAYS · 26 OCT – 1 NOV", or the dates alone for older weeks.
    private func periodTitle(_ period: UsageInsightsPeriod, withRange: Bool) -> String {
        guard let key = UsagePeriodName.key(for: period, in: usage) else { return range(period) }
        return withRange ? insightsText(key) + " · " + range(period) : insightsText(key)
    }
    private var windowRange: String {
        guard let first = window.first, let last = window.last else { return "—" }
        return text.format("%@ – %@", date(first.date), date(last.date))
    }
    private func date(_ date: Date, template: String = "MMMd") -> String {
        let formatter = DateFormatter(); formatter.calendar = configuration.calendar; formatter.timeZone = configuration.calendar.timeZone; formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template); return formatter.string(from: date)
    }
    private func range(_ period: UsageInsightsPeriod) -> String {
        let lastDay = configuration.calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.start
        return text.format("%@ – %@", date(period.start), date(lastDay))
    }
}

/// One bar: a filled stem for reported time, a hollow dot for a reported
/// zero, a dashed outline for missing data. Partly reported stems carry a
/// paper notch, so partial is never shown by colour alone.
struct UsageBarStem: View {
    let seconds: TimeInterval?
    let maximum: TimeInterval
    let width: CGFloat
    let height: CGFloat
    let fill: Color
    let complete: Bool
    let colors: ReportColors

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if let fraction = UsageDashboardPresentation.barFraction(seconds, maximum: maximum) {
                if fraction == 0 { Circle().stroke(fill, lineWidth: 1.5).frame(width: 6, height: 6) }
                else {
                    RoundedRectangle(cornerRadius: 6).fill(fill)
                        .frame(width: width, height: max(1.5, fraction * (height - 2)))
                        .overlay(alignment: .top) {
                            if !complete { Rectangle().fill(colors.paper.opacity(0.75)).frame(height: 2).padding(.top, 4) }
                        }
                }
            } else {
                RoundedRectangle(cornerRadius: 5).stroke(colors.inkSoft.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .frame(width: width, height: 16)
            }
        }
        .frame(width: max(width, 16), height: height).accessibilityHidden(true)
    }
}
