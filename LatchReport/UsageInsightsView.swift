import SwiftUI
import Foundation

struct UsageInsightsView: View {
    let configuration: UsageInsightsConfiguration
    let applicationLabel: (Int) -> AnyView
    let applicationIdentity: (Int) -> AnyHashable
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 56
    @State private var weekly = false
    @State private var page = 0
    @State private var selectedDay: Date?
    @State private var selectedWeek: Date?
    @State private var showingDetails = false
    @State private var selectedApplication: AnyHashable?
    @State private var selectedApplicationLabel: AnyView?
    @State private var showingAllApplications = false
    @State private var showingTrends = false

    init(configuration: UsageInsightsConfiguration, initiallyWeekly: Bool = false,
         initiallySelectedApplication: Int? = nil, initiallyShowingTrends: Bool = false,
         applicationLabel: @escaping (Int) -> AnyView = { _ in AnyView(Image(systemName: "app")) },
         applicationIdentity: @escaping (Int) -> AnyHashable = { AnyHashable($0) }) {
        self.configuration = configuration
        self.applicationLabel = applicationLabel
        self.applicationIdentity = applicationIdentity
        _weekly = State(initialValue: initiallyWeekly)
        _selectedApplication = State(initialValue: initiallySelectedApplication.map(applicationIdentity))
        _selectedApplicationLabel = State(initialValue: initiallySelectedApplication.map(applicationLabel))
        _showingTrends = State(initialValue: initiallyShowingTrends)
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
    private var usage: UsageInsightsConfiguration {
        guard selectedApplication != nil else { return configuration }
        return configuration.applications.first { applicationIdentity($0.id) == selectedApplication }?.usage
            ?? UsageDashboardPresentation.unavailable(configuration)
    }
    private var selectedApplicationID: Int? {
        configuration.applications.first { applicationIdentity($0.id) == selectedApplication }?.id
    }
    private var window: [UsageInsightsDay] { UsageDashboardPresentation.window(usage.days, page: page) }
    private var day: UsageInsightsDay? { window.first { $0.date == selectedDay } ?? window.last }
    private var week: UsageInsightsPeriod { usage.weeks.first { $0.start == selectedWeek } ?? usage.lastSevenDays }
    private var comparisonCurrent: UsageInsightsPeriod { weekly ? week : usage.lastSevenDays }
    private var comparisonPrevious: UsageInsightsPeriod? {
        weekly ? UsageDashboardPresentation.preceding(week, in: usage.weeks) : usage.previousSevenDays
    }
    private var comparisonTrend: UsageInsightsTrend? {
        guard let previous = comparisonPrevious else { return nil }
        return UsageInsightsTrend.compare(comparisonCurrent, with: previous)
    }

    var body: some View {
        Group {
            if showingTrends {
                UsageTrendsView(usage: usage, applications: configuration.applications,
                    baseline: selectedApplication == nil ? configuration.baseline : nil,
                    scopeLabel: scopeLabel, applicationLabel: applicationLabel, applicationIdentity: applicationIdentity,
                    accent: accent, ink: ink, muted: muted, paper: paper, locale: locale,
                    selectedPeriod: weekly ? week.start : usage.lastSevenDays.start,
                    onBack: { showingTrends = false },
                    onAllApps: { selectedApplication = nil; selectedApplicationLabel = nil },
                    onSelectApp: selectApplication)
            } else { dashboard }
        }.background(paper).environment(\.colorScheme, scheme).environment(\.locale, locale)
    }
    private var dashboard: some View {
        // A single report-owned dashboard. No usage, height or readiness export.
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                rangeControl.id("usageTop")
                if selectedApplication != nil { applicationScope }
                if usage.reportedDays == 0 { emptyState }
                else { usageHero; chartSection }
                trendsEntry
                if configuration.reportedDays > 0 || !configuration.applications.isEmpty { mostUsedApplications }
                details
            }
            .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 24)
            .frame(maxWidth: 740).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(paper).foregroundStyle(ink)
        .environment(\.colorScheme, scheme).environment(\.locale, locale)
        .onChange(of: selectedApplication) { _ in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                reader.scrollTo("usageTop", anchor: .top)
            }
        }
        }
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
                    : (day?.date == usage.today?.date ? "Today so far"
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
                    pageButton("Previous week", symbol: "chevron.left", enabled: page < UsageDashboardPresentation.lastPage(dayCount: usage.days.count)) {
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
        let values = weekly ? usage.weeks.compactMap(\.seconds) : window.compactMap(\.seconds)
        let maximum = max(1, values.max() ?? 1)
        let count = weekly ? usage.weeks.count : window.count
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
                            ForEach(usage.weeks) { item in
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

    private var applicationScope: some View {
        HStack(alignment: .center, spacing: 14) {
            if let scopeLabel { scopeLabel.font(.headline).labelStyle(.titleAndIcon).frame(maxWidth: .infinity, alignment: .leading) }
            Button { selectedApplication = nil; selectedApplicationLabel = nil } label: {
                Text(insightsText("All apps")).font(.caption.weight(.semibold))
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(accent.opacity(0.08), in: Capsule())
            }.buttonStyle(.plain).foregroundStyle(accent)
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
        selectedApplication = applicationIdentity(id)
    }
    private var trendsEntry: some View {
        Button { showingTrends = true } label: {
            HStack(spacing: 16) {
                Image(systemName: "chart.xyaxis.line").font(.system(size: 25, weight: .light))
                    .frame(width: 46, height: 46).background(accent.opacity(0.08), in: Circle()).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(insightsText("Explore trends")).font(.system(.title3, design: .serif))
                    Text(insightsText("A closer look at patterns, changes and reported coverage.")).font(.caption).foregroundStyle(muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right").font(.title3).accessibilityHidden(true)
            }.foregroundStyle(accent).frame(minHeight: 72).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var rankedApplications: [UsageInsightsApplication] {
        UsageDashboardPresentation.rankedApplications(configuration.applications,
            day: day?.date, week: weekly ? week.start : nil)
    }
    private var mostUsedApplications: some View {
        let applications = rankedApplications
        let maximum = applications.first.flatMap { applicationSeconds($0) } ?? 1
        return VStack(alignment: .leading, spacing: 18) {
            heading("Most used apps")
            Text(weekly ? dateRange(week) : date(day?.date ?? configuration.generatedAt, template: "EEEEMMMMd"))
                .font(.caption).foregroundStyle(muted)
            if applications.isEmpty {
                Text(insightsText("No app usage reported for this period."))
                    .font(.subheadline).foregroundStyle(muted)
            } else {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(showingAllApplications ? applications : Array(applications.prefix(5))) { app in
                        applicationRow(app, maximum: max(1, maximum))
                    }
                }
                if applications.count > 5 {
                    Button { showingAllApplications.toggle() } label: {
                        Text(insightsText(showingAllApplications ? "Show fewer apps" : "See all apps"))
                            .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    }.buttonStyle(.plain).foregroundStyle(accent)
                }
                Text(insightsText("Tap an app to see its daily and weekly usage."))
                    .font(.caption).foregroundStyle(muted)
            }
            Text(insightsText("App totals may not add up to overall screen time."))
                .font(.caption).foregroundStyle(muted)
        }
    }
    private func applicationSeconds(_ app: UsageInsightsApplication) -> TimeInterval? {
        UsageDashboardPresentation.appSeconds(app, day: day?.date, week: weekly ? week.start : nil)
    }
    private func applicationComplete(_ app: UsageInsightsApplication) -> Bool {
        if weekly { return app.usage.weeks.first { $0.start == week.start }?.isComplete == true }
        return app.usage.days.first { $0.date == day?.date }?.isComplete == true
    }
    private func applicationRow(_ app: UsageInsightsApplication, maximum: TimeInterval) -> some View {
        let seconds = applicationSeconds(app)
        let selected = selectedApplication == applicationIdentity(app.id)
        return Button { selectApplication(app.id) } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 12) {
                    applicationLabel(app.id).id(applicationIdentity(app.id)).font(.subheadline).labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(duration(seconds)).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(accent)
                    Image(systemName: selected ? "checkmark" : "chevron.right").font(.caption).foregroundStyle(muted)
                        .accessibilityHidden(true)
                }
                GeometryReader { geometry in
                    Capsule().fill(accent.opacity(0.08))
                    Capsule().fill(accent.opacity(selected ? 1 : 0.45))
                        .frame(width: max(0, geometry.size.width * (UsageDashboardPresentation.barFraction(seconds, maximum: maximum) ?? 0)))
                }.frame(height: 3).accessibilityHidden(true)
                if !applicationComplete(app) {
                    Text(insightsText(day?.date == usage.today?.date && !weekly ? "Today so far" : "Partial reported coverage"))
                        .font(.caption2).foregroundStyle(muted)
                }
            }.frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 64 : 44)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
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
                Text(format("%d of %d days reported", usage.reportedDays, usage.days.count))
                Text(insightsText("Screen Time may report incomplete or delayed data. Missing days are not counted as zero."))
                Text(insightsText("Each bar shows reported minutes. A dash means no data, not zero."))
                Text(insightsText("Per-app usage is reported by iOS; missing days are not counted as zero."))
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
