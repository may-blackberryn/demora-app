//
//  SchedulesView.swift
//  Recurring blocking schedules (daily/weekly/monthly), free periods,
//  one-off planned windows, and immediate sessions. All delay-gated.
//

import SwiftUI
import FamilyControls

struct SchedulesView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAddSchedule = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    overviewSection
                        .tutorialHighlight(model.tutorial == .exploreCalendar
                                           && model.calendarFocusNowNext
                                           && model.tutorialScreen == "schedulesRoot")
                    if model.tutorial == .addSchedule
                        && model.tutorialScreen == "schedulesRoot" {
                        Button { showAddSchedule = true } label: {
                            Label(tr("Add a recurring schedule"), systemImage: "repeat")
                                .font(.headline).frame(maxWidth: .infinity).padding(16)
                                .background(Ink.ink.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: 16)
                                    .stroke(Ink.rule, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .tutorialHighlight(true)
                    }
                    typeGrid
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Schedules"))
            .onAppear {
                if model.inTutorial && model.selectedTab == 2 {
                    model.tutorialScreen = "schedulesRoot"
                }
            }
            .refreshable { model.tick() }
            .sheet(isPresented: $showAddSchedule) { ScheduleEditorView() }
            .toolbar {
                if !model.inTutorial {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink { HelpHubView() } label: {
                            Image(systemName: "questionmark.circle")
                        }
                    }
                }
            }
        }
    }

    // MARK: Now & next overview

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("now & next"))
                .font(.system(.title3, design: .serif)).bold()
            let active = activeItems
            let upcoming = upcomingItems
            if active.isEmpty && upcoming.isEmpty {
                Text(tr("Nothing scheduled right now."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                if !active.isEmpty {
                    overviewGroup(tr("Active now"), active, active: true)
                }
                if !upcoming.isEmpty {
                    overviewGroup(tr("Coming up"), upcoming, active: false)
                }
            }
        }
    }

    private func overviewGroup(_ title: String, _ items: [OverviewItem],
                               active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.smallCaps()).foregroundStyle(.secondary)
            ForEach(items) { item in
                NavigationLink {
                    ScheduledItemDetailView(title: item.name, summary: item.summary,
                                            timing: item.detail, appsTitle: item.appsTitle,
                                            selection: item.selection)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.symbol)
                            .font(.callout)
                            .foregroundStyle(item.color)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.subheadline).foregroundStyle(Ink.ink)
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(Ink.faint)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var activeItems: [OverviewItem] {
        var out: [OverviewItem] = []
        for s in model.state.sessions where s.isActive {
            out.append(.init(id: "sess-\(s.id)",
                             symbol: s.kind == .block ? "nosign"
                                : s.kind == .free ? "leaf" : "checkmark.circle",
                             name: s.name,
                             detail: String(format: tr("until %@"),
                                            s.endsAt.formatted(date: .omitted, time: .shortened)),
                             color: SchedPalette.sessions,
                             summary: s.kind == .block
                                ? tr("Blocking the selected apps")
                                : s.kind == .free
                                ? tr("Free period — nothing is blocked")
                                : tr("Unblocking the selected apps"),
                             appsTitle: s.kind == .free ? nil
                                : (s.kind == .block
                                   ? tr("Apps blocked") : tr("Apps unblocked")),
                             selection: s.kind == .free ? nil : s.selection))
        }
        for sch in model.state.schedules where sch.isActive() {
            out.append(.init(id: "sch-\(sch.id)", symbol: "calendar",
                             name: sch.name,
                             detail: String(format: tr("until %@"),
                                            minutesLabel(sch.endMinutes)),
                             color: SchedPalette.recurring,
                             summary: sch.mode.label,
                             appsTitle: sch.mode == .blockAllExcept
                                ? tr("Apps that stay usable") : tr("Apps to block"),
                             selection: sch.selection))
        }
        for w in model.state.planned where w.isActive {
            out.append(.init(id: "pl-\(w.id)",
                             symbol: w.kind == .free ? "leaf" : "nosign",
                             name: w.name,
                             detail: String(format: tr("until %@"),
                                            w.endsAt.formatted(date: .omitted, time: .shortened)),
                             color: SchedPalette.planned,
                             summary: w.kind.label,
                             appsTitle: w.kind == .free ? nil
                                : (w.kind == .blockAllExcept
                                   ? tr("Apps that stay usable") : tr("Apps to block")),
                             selection: w.kind == .free ? nil : w.selection))
        }
        for ex in model.state.exemptions where ex.isActive() {
            out.append(.init(id: "ex-\(ex.id)", symbol: "leaf",
                             name: ex.name,
                             detail: String(format: tr("until %@"),
                                            minutesLabel(ex.endMinutes)),
                             color: SchedPalette.recurring,
                             summary: tr("Free period")))
        }
        return out
    }

    private var upcomingItems: [OverviewItem] {
        let now = Date()
        let nowMin = minutesOfDay(now)
        let cal = Calendar.current
        var dated: [(Date, OverviewItem)] = []
        for w in model.state.planned where w.startsAt > now {
            let detail = "\(w.startsAt.formatted(date: .abbreviated, time: .shortened)) → \(w.endsAt.formatted(date: .omitted, time: .shortened))"
            dated.append((w.startsAt,
                          OverviewItem(id: "upl-\(w.id)",
                                       symbol: w.kind == .free ? "leaf" : "nosign",
                                       name: w.name, detail: detail,
                                       color: SchedPalette.planned,
                                       summary: w.kind.label,
                                       appsTitle: w.kind == .free ? nil
                                          : (w.kind == .blockAllExcept
                                             ? tr("Apps that stay usable") : tr("Apps to block")),
                                       selection: w.kind == .free ? nil : w.selection)))
        }
        for sch in model.state.schedules
        where !sch.isActive() && sch.recurrence.matches(dayOf: now)
            && sch.startMinutes > nowMin {
            let start = cal.date(bySettingHour: sch.startMinutes / 60,
                                 minute: sch.startMinutes % 60, second: 0,
                                 of: now) ?? now
            let detail = String(format: tr("today %@–%@"),
                                minutesLabel(sch.startMinutes),
                                minutesLabel(sch.endMinutes))
            dated.append((start,
                          OverviewItem(id: "usch-\(sch.id)", symbol: "calendar",
                                       name: sch.name, detail: detail,
                                       color: SchedPalette.recurring,
                                       summary: sch.mode.label,
                                       appsTitle: sch.mode == .blockAllExcept
                                          ? tr("Apps that stay usable") : tr("Apps to block"),
                                       selection: sch.selection)))
        }
        for ex in model.state.exemptions
        where !ex.isActive() && ex.recurrence.matches(dayOf: now)
            && ex.startMinutes > nowMin {
            let start = cal.date(bySettingHour: ex.startMinutes / 60,
                                 minute: ex.startMinutes % 60, second: 0,
                                 of: now) ?? now
            let detail = String(format: tr("today %@–%@"),
                                minutesLabel(ex.startMinutes),
                                minutesLabel(ex.endMinutes))
            dated.append((start,
                          OverviewItem(id: "uex-\(ex.id)", symbol: "leaf",
                                       name: ex.name, detail: detail,
                                       color: SchedPalette.recurring,
                                       summary: tr("Free period"))))
        }
        // Soonest first, capped at three.
        return dated.sorted { $0.0 < $1.0 }.prefix(3).map { $0.1 }
    }

    // MARK: Type grid

    private var typeGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)], spacing: 14) {
            NavigationLink { SessionsListView() } label: {
                TypeCard(symbol: "play.circle", title: tr("Sessions"),
                         count: model.state.sessions.filter(\.isActive).count,
                         activeCount: model.state.sessions.filter(\.isActive).count,
                         color: SchedPalette.sessions)
            }
            NavigationLink { PlannedListView() } label: {
                TypeCard(symbol: "calendar.badge.clock", title: tr("Planned"),
                         count: model.state.planned.count,
                         activeCount: model.state.planned.filter(\.isActive).count,
                         color: SchedPalette.planned)
            }
            NavigationLink { RecurringListView() } label: {
                TypeCard(symbol: "repeat", title: tr("Recurring"),
                         count: model.state.schedules.count + model.state.exemptions.count,
                         activeCount: model.state.schedules.filter { $0.isActive() }.count
                                    + model.state.exemptions.filter { $0.isActive() }.count,
                         color: SchedPalette.recurring)
            }
            .tutorialHighlight(model.tutorial == .removeSchedule
                               && model.tutorialScreen == "schedulesRoot")
            NavigationLink { CalendarView() } label: {
                GridCard(symbol: "calendar", title: tr("Calendar"),
                         subtitle: tr("month"))
            }
            .tutorialHighlight(model.tutorial == .exploreCalendar
                               && !model.calendarFocusNowNext
                               && model.tutorialScreen == "schedulesRoot")
        }
    }

}

// MARK: - Overview model

/// One shared accent for every schedule group — icons and calendar marks all
/// use the same color.
enum SchedPalette {
    static let sessions = Ink.accent
    static let planned = Ink.accent
    static let recurring = Ink.accent
}

private struct OverviewItem: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let detail: String
    var color: Color = Ink.accent
    var summary: String = ""
    var appsTitle: String? = nil
    var selection: FamilyActivitySelection? = nil
}

/// Pushed when you tap a scheduled item (now & next, or a calendar day) —
/// shows what it does, when, and the apps it covers.
struct ScheduledItemDetailView: View {
    let title: String
    let summary: String
    let timing: String
    var appsTitle: String? = nil
    var selection: FamilyActivitySelection? = nil

    private var hasApps: Bool {
        guard let s = selection else { return false }
        return !(s.applicationTokens.isEmpty
                 && s.categoryTokens.isEmpty
                 && s.webDomainTokens.isEmpty)
    }

    var body: some View {
        List {
            Section {
                if !summary.isEmpty {
                    Text(summary).font(.headline)
                }
                Text(timing).font(.subheadline).foregroundStyle(.secondary)
            }
            if hasApps, let appsTitle, let selection {
                Section(appsTitle) { SelectedAppsView(selection: selection) }
            }
        }
        .paper()
        .casedNavigationTitle(title)
    }
}

// MARK: - Type card

struct TypeCard: View {
    let symbol: String
    let title: String
    let count: Int
    let activeCount: Int
    var color: Color = Ink.accent

    private var subtitle: String {
        if count == 0 { return tr("none") }
        if activeCount > 0 { return String(format: tr("%d · %d active"), count, activeCount) }
        return String(format: tr("%d total"), count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color)
            Spacer(minLength: 12)
            Text(title).font(.headline).foregroundStyle(Ink.ink)
            Text(subtitle).font(.caption).foregroundStyle(Ink.faint)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .padding(16)
        .background(Ink.ink.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Ink.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ActiveBadge: View {
    var body: some View {
        Text(tr("ACTIVE")).font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.green.opacity(0.2))
            .clipShape(Capsule())
    }
}

// MARK: - Per-type detail lists

struct SessionsListView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAdd = false

    var body: some View {
        List {
            Section {
                if model.state.sessions.filter(\.isActive).isEmpty {
                    Text(tr("No active sessions")).foregroundStyle(.secondary)
                }
                ForEach(model.state.sessions.filter(\.isActive)) { session in
                    VStack(alignment: .leading, spacing: 6) {
                        NavigationLink { detailView(for: session) } label: {
                            HStack {
                                Text(session.kind == .block ? "⛔️"
                                     : session.kind == .free ? "🌴" : "✅")
                                Text(session.name).font(.headline)
                                    .foregroundStyle(Ink.ink)
                                Spacer()
                                Text(timerInterval: Date.now...max(session.endsAt, Date.now.addingTimeInterval(1)),
                                     countsDown: true)
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(Ink.ink)
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(Ink.faint)
                            }
                        }
                        .buttonStyle(.plain)
                        Button(tr("End early…")) {
                            model.queue(.endSessionEarly(id: session.id))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
                Button { showAdd = true } label: {
                    Label(tr("New session…"), systemImage: "play.circle.fill")
                }
            } footer: {
                Text(String(format: tr("One-off and unplanned, but still delay-gated. A block session waits %@; an unblock session waits %@. Ending early flips the rule (or use an override)."),
                            model.state.strictDelay.shortDelayLabel,
                            model.state.lenientDelay.shortDelayLabel))
            }
        }
        .paper()
        .casedNavigationTitle(tr("Sessions"))
        .refreshable { model.tick() }
        .sheet(isPresented: $showAdd) { SessionStartView() }
    }

    /// Same session-info page the "now & next" rows push — shows what the
    /// session does and which apps it covers.
    private func detailView(for s: BlockSession) -> ScheduledItemDetailView {
        ScheduledItemDetailView(
            title: s.name,
            summary: s.kind == .block ? tr("Blocking the selected apps")
                   : s.kind == .free ? tr("Free period — nothing is blocked")
                   : tr("Unblocking the selected apps"),
            timing: String(format: tr("until %@"),
                           s.endsAt.formatted(date: .omitted, time: .shortened)),
            appsTitle: s.kind == .free ? nil
                     : (s.kind == .block ? tr("Apps blocked") : tr("Apps unblocked")),
            selection: s.kind == .free ? nil : s.selection)
    }
}

struct PlannedListView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAdd = false

    var body: some View {
        List {
            Section {
                if model.state.planned.isEmpty {
                    Text(tr("Nothing planned")).foregroundStyle(.secondary)
                }
                ForEach(model.state.planned.sorted { $0.startsAt < $1.startsAt }) { w in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(w.kind == .free ? "🌴" : "⛔️")
                            Text(w.name).font(.headline)
                            if w.isActive { ActiveBadge() }
                            Spacer()
                        }
                        Text("\(w.startsAt.formatted(date: .abbreviated, time: .shortened)) → \(w.endsAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(w.kind.label)
                            .font(.caption).foregroundStyle(.secondary)
                        if w.kind != .free
                            && !(w.selection.applicationTokens.isEmpty
                                 && w.selection.categoryTokens.isEmpty
                                 && w.selection.webDomainTokens.isEmpty) {
                            DisclosureGroup(w.kind == .blockAllExcept
                                            ? tr("Apps that stay usable") : tr("Apps to block")) {
                                SelectedAppsView(selection: w.selection)
                            }
                            .font(.caption)
                        }
                        Button(tr("Remove…"), role: .destructive) {
                            model.queue(.removePlanned(id: w.id))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
                Button { showAdd = true } label: {
                    Label(tr("Plan a window…"), systemImage: "calendar.badge.plus")
                }
            } footer: {
                Text(tr("Plan ahead for specific dates — a trip, a weekend, an exam. Doesn't repeat. Planning a block is stricter; planning a free period is less strict."))
            }
        }
        .paper()
        .casedNavigationTitle(tr("Planned"))
        .refreshable { model.tick() }
        .sheet(isPresented: $showAdd) { PlannedEditorView() }
    }
}

struct RecurringListView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAdd = false

    var body: some View {
        List {
            Section {
                if model.state.schedules.isEmpty {
                    Text(tr("No schedules")).foregroundStyle(.secondary)
                }
                ForEach(model.state.schedules) { sched in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(sched.name).font(.headline)
                            if sched.isActive() { ActiveBadge() }
                            Spacer()
                            Text(sched.windowLabel).foregroundStyle(.secondary)
                        }
                        Text("\(sched.recurrence.label) · \(sched.mode.label)")
                            .font(.caption).foregroundStyle(.secondary)
                        if !(sched.selection.applicationTokens.isEmpty
                             && sched.selection.categoryTokens.isEmpty
                             && sched.selection.webDomainTokens.isEmpty) {
                            DisclosureGroup(sched.mode == .blockAllExcept
                                            ? tr("Apps that stay usable") : tr("Apps to block")) {
                                SelectedAppsView(selection: sched.selection)
                            }
                            .font(.caption)
                        }
                        Button(tr("Remove…"), role: .destructive) {
                            model.queue(.removeSchedule(id: sched.id))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .tutorialHighlight(model.tutorial == .removeSchedule
                                           && model.tutorialScreen == "recurring")
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(tr("Blocks"))
            }

            Section {
                if model.state.exemptions.isEmpty {
                    Text(tr("No free periods")).foregroundStyle(.secondary)
                }
                ForEach(model.state.exemptions) { ex in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(ex.name).font(.headline)
                            if ex.isActive() { ActiveBadge() }
                            Spacer()
                            Text(ex.windowLabel).foregroundStyle(.secondary)
                        }
                        Text("\(ex.recurrence.label) · \(tr("Free period"))")
                            .font(.caption).foregroundStyle(.secondary)
                        Button(tr("Remove…"), role: .destructive) {
                            model.queue(.removeExemption(id: ex.id))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .tutorialHighlight(model.tutorial == .removeSchedule
                                           && model.tutorialScreen == "recurring")
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(tr("Free periods"))
            } footer: {
                Text(String(format: tr("Repeating windows: every day, chosen weekdays, or monthly patterns. Adding waits %@; removing waits %@."),
                            model.state.strictDelay.shortDelayLabel,
                            model.state.lenientDelay.shortDelayLabel))
            }
        }
        .paper()
        .casedNavigationTitle(tr("Recurring"))
        .onAppear { if model.inTutorial { model.tutorialScreen = "recurring" } }
        .refreshable { model.tick() }
        .toolbar {
            if !model.inTutorial {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { ScheduleEditorView() }
    }
}

struct ExemptionsListView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAdd = false

    var body: some View {
        List {
            Section {
                if model.state.exemptions.isEmpty {
                    Text(tr("No free periods")).foregroundStyle(.secondary)
                }
                ForEach(model.state.exemptions) { ex in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(ex.name).font(.headline)
                            if ex.isActive() { ActiveBadge() }
                            Spacer()
                            Text(ex.windowLabel).foregroundStyle(.secondary)
                        }
                        Text(ex.recurrence.label)
                            .font(.caption).foregroundStyle(.secondary)
                        Button(tr("Remove…"), role: .destructive) {
                            model.queue(.removeExemption(id: ex.id))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
                Button { showAdd = true } label: {
                    Label(tr("Add free period…"), systemImage: "cup.and.saucer")
                }
            } footer: {
                Text(tr("During a free period, limits don't block and usage inside the window doesn't count toward them — time used before the window still does."))
            }
        }
        .paper()
        .casedNavigationTitle(tr("Free periods"))
        .refreshable { model.tick() }
        .sheet(isPresented: $showAdd) { ExemptionEditorView() }
    }
}

// MARK: - Recurrence picker

struct RecurrencePicker: View {
    @Binding var recurrence: Recurrence
    /// Monthly rules can't wrap midnight; the editor passes this in.
    let allowWrap: Bool

    enum Mode: String, CaseIterable, Identifiable {
        case daily, weekly, monthlyDay, monthlyOrdinal
        var id: String { rawValue }
        var label: String {
            switch self {
            case .daily:          return tr("Every day")
            case .weekly:         return tr("Weekdays")
            case .monthlyDay:     return tr("Day of month")
            case .monthlyOrdinal: return tr("Nth weekday")
            }
        }
    }

    @State private var mode: Mode = .daily
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var monthDay = 1
    @State private var ordinal = 1
    @State private var ordinalWeekday = 2

    var body: some View {
        Picker(tr("Repeats"), selection: $mode) {
            ForEach(Mode.allCases) { Text($0.label).tag($0) }
        }
        .onChange(of: mode) { _ in push() }

        switch mode {
        case .daily:
            EmptyView()
        case .weekly:
            HStack {
                ForEach(1...7, id: \.self) { day in
                    let symbol = Calendar.current.veryShortWeekdaySymbols[day - 1]
                    Button {
                        if weekdays.contains(day) { weekdays.remove(day) }
                        else { weekdays.insert(day) }
                        push()
                    } label: {
                        Text(symbol)
                            .font(.caption.bold())
                            .frame(width: 32, height: 32)
                            .background(weekdays.contains(day)
                                        ? Color.accentColor
                                        : Color.secondary.opacity(0.15))
                            .foregroundStyle(weekdays.contains(day)
                                             ? .white : .primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .monthlyDay:
            Stepper(String(format: tr("Day %d of every month"), monthDay),
                    value: $monthDay, in: 1...31)
                .onChange(of: monthDay) { _ in push() }
        case .monthlyOrdinal:
            Picker(tr("Which one"), selection: $ordinal) {
                ForEach(1...4, id: \.self) { Text("#\($0)").tag($0) }
            }
            .onChange(of: ordinal) { _ in push() }
            Picker(tr("Weekday"), selection: $ordinalWeekday) {
                ForEach(1...7, id: \.self) { day in
                    Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                }
            }
            .onChange(of: ordinalWeekday) { _ in push() }
        }
    }

    private func push() {
        switch mode {
        case .daily:          recurrence = .daily
        case .weekly:         recurrence = .weekly(weekdays)
        case .monthlyDay:     recurrence = .monthlyDay(monthDay)
        case .monthlyOrdinal: recurrence = .monthlyOrdinal(weekday: ordinalWeekday,
                                                           ordinal: ordinal)
        }
    }

    var isMonthly: Bool { mode == .monthlyDay || mode == .monthlyOrdinal }
    var isValid: Bool { mode != .weekly || !weekdays.isEmpty }
}

// MARK: - Schedule editor

struct ScheduleEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var mode: ScheduleMode = .blockAllExcept
    @State private var selection = FamilyActivitySelection()
    @State private var start = defaultTime(hour: 22)
    @State private var end = defaultTime(hour: 7)
    @State private var recurrence: Recurrence = .daily
    @State private var showPicker = false
    @State private var isFree = false

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Name")) {
                    TextField(tr("e.g. Bedtime"), text: $name)
                }
                Section {
                    Picker(tr("Type"), selection: $isFree) {
                        Text(tr("Block")).tag(false)
                        Text(tr("Free period")).tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if isFree {
                        Text(tr("Limits won't block and usage won't count during this window."))
                    }
                }
                if !isFree {
                    Section {
                        Picker(tr("Mode"), selection: $mode) {
                            ForEach(ScheduleMode.allCases) { Text($0.label).tag($0) }
                        }
                        Button {
                            showPicker = true
                        } label: {
                            HStack {
                                Text(mode == .blockAllExcept
                                     ? tr("Apps that stay usable") : tr("Apps to block"))
                                Spacer()
                                Text(String(format: tr("%d selected"),
                                            selection.applicationTokens.count
                                            + selection.categoryTokens.count))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        SelectedAppsView(selection: selection)
                    } footer: {
                        Text(mode == .blockAllExcept
                             ? tr("Everything on the iPhone is blocked during the window except the apps picked here.")
                             : tr("Only the apps picked here are blocked during the window."))
                    }
                }
                Section(tr("Window")) {
                    DatePicker(tr("Start"), selection: $start,
                               displayedComponents: .hourAndMinute)
                    DatePicker(tr("End"), selection: $end,
                               displayedComponents: .hourAndMinute)
                    RecurrencePicker(recurrence: $recurrence, allowWrap: true)
                }
                if monthlyWrapProblem {
                    Section {
                        Text(tr("Monthly schedules can't cross midnight — set the end time after the start time."))
                            .font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    let (dir, delay) = model.preview(scheduleAction)
                    Label(String(format: tr("%@ — takes effect in %@"),
                                 dir.label, delay.shortDelayLabel),
                          systemImage: "clock")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .paper()
            .casedNavigationTitle(tr("New recurring"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Queue change")) {
                        model.queue(scheduleAction)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showPicker) {
                AppPickerSheet(selection: $selection)
            }
        }
    }

    private var scheduleAction: ChangeAction {
        isFree ? .addExemption(exemptDraft) : .addSchedule(draft)
    }
    private var draft: BlockSchedule {
        BlockSchedule(name: name.isEmpty ? tr("Schedule") : name,
                      mode: mode,
                      selection: selection,
                      startMinutes: minutesOfDay(start),
                      endMinutes: minutesOfDay(end),
                      recurrence: recurrence)
    }
    private var exemptDraft: ExemptSchedule {
        ExemptSchedule(name: name.isEmpty ? tr("Free period") : name,
                       startMinutes: minutesOfDay(start),
                       endMinutes: minutesOfDay(end),
                       recurrence: recurrence)
    }
    private var isMonthly: Bool {
        if case .monthlyDay = recurrence { return true }
        if case .monthlyOrdinal = recurrence { return true }
        return false
    }
    private var monthlyWrapProblem: Bool {
        isMonthly && minutesOfDay(start) >= minutesOfDay(end)
    }
    private var isValid: Bool {
        guard !name.isEmpty,
              minutesOfDay(start) != minutesOfDay(end),
              !monthlyWrapProblem else { return false }
        if case .weekly(let days) = recurrence, days.isEmpty { return false }
        if isFree { return true }
        return mode == .blockAllExcept
            || !(selection.applicationTokens.isEmpty
                 && selection.categoryTokens.isEmpty)
    }
}

// MARK: - Free-period editor

struct ExemptionEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var start = defaultTime(hour: 13)
    @State private var end = defaultTime(hour: 14)
    @State private var recurrence: Recurrence = .daily

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Name")) {
                    TextField(tr("e.g. Lunch break"), text: $name)
                }
                Section(tr("Window")) {
                    DatePicker(tr("Start"), selection: $start,
                               displayedComponents: .hourAndMinute)
                    DatePicker(tr("End"), selection: $end,
                               displayedComponents: .hourAndMinute)
                    RecurrencePicker(recurrence: $recurrence, allowWrap: true)
                }
                if monthlyWrapProblem {
                    Section {
                        Text(tr("Monthly schedules can't cross midnight — set the end time after the start time."))
                            .font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    let (dir, delay) = model.preview(.addExemption(draft))
                    Label(String(format: tr("%@ — takes effect in %@"),
                                 dir.label, delay.shortDelayLabel),
                          systemImage: "clock")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .paper()
            .casedNavigationTitle(tr("New free period"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Queue change")) {
                        model.queue(.addExemption(draft))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var draft: ExemptSchedule {
        ExemptSchedule(name: name.isEmpty ? tr("Free period") : name,
                       startMinutes: minutesOfDay(start),
                       endMinutes: minutesOfDay(end),
                       recurrence: recurrence)
    }
    private var isMonthly: Bool {
        if case .monthlyDay = recurrence { return true }
        if case .monthlyOrdinal = recurrence { return true }
        return false
    }
    private var monthlyWrapProblem: Bool {
        isMonthly && minutesOfDay(start) >= minutesOfDay(end)
    }
    private var isValid: Bool {
        guard !name.isEmpty,
              minutesOfDay(start) != minutesOfDay(end),
              !monthlyWrapProblem else { return false }
        if case .weekly(let days) = recurrence, days.isEmpty { return false }
        return true
    }
}

// MARK: - Planned one-off editor

struct PlannedEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: PlannedKind = .free
    @State private var selection = FamilyActivitySelection()
    @State private var startsAt = Date().addingTimeInterval(3600)
    @State private var endsAt = Date().addingTimeInterval(3 * 3600)
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Name")) {
                    TextField(tr("e.g. Airport, weekend trip"), text: $name)
                }
                Section {
                    Picker(tr("Type"), selection: $kind) {
                        ForEach(PlannedKind.allCases) { Text($0.label).tag($0) }
                    }
                    if kind != .free {
                        Button {
                            showPicker = true
                        } label: {
                            HStack {
                                Text(kind == .blockAllExcept
                                     ? tr("Apps that stay usable")
                                     : tr("Apps to block"))
                                Spacer()
                                Text(String(format: tr("%d selected"),
                                            selection.applicationTokens.count
                                            + selection.categoryTokens.count))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        SelectedAppsView(selection: selection)
                    }
                } footer: {
                    if kind == .free {
                        Text(tr("Limits won't block and usage won't count during this window."))
                    }
                }
                Section(tr("When")) {
                    DatePicker(tr("Starts"), selection: $startsAt,
                               in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                    DatePicker(tr("Ends"), selection: $endsAt,
                               in: startsAt...,
                               displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    let (dir, delay) = model.preview(.addPlanned(draft))
                    Label(String(format: tr("%@ — takes effect in %@"),
                                 dir.label, delay.shortDelayLabel),
                          systemImage: "clock")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .paper()
            .casedNavigationTitle(tr("Plan a window"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Queue change")) {
                        model.queue(.addPlanned(draft))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showPicker) {
                AppPickerSheet(selection: $selection)
            }
        }
    }

    private var draft: PlannedWindow {
        PlannedWindow(name: name.isEmpty ? tr("Planned window") : name,
                      kind: kind, selection: selection,
                      startsAt: startsAt, endsAt: endsAt)
    }
    private var isValid: Bool {
        guard !name.isEmpty, endsAt > startsAt else { return false }
        return kind != .blockSelected
            || !(selection.applicationTokens.isEmpty
                 && selection.categoryTokens.isEmpty)
    }
}

// MARK: - Immediate session

struct SessionStartView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: SessionKind = .block
    @State private var selection = FamilyActivitySelection()
    @State private var minutes = 60
    @State private var showPicker = false

    private var draft: ChangeAction {
        let fallback = kind == .free ? kind.label : "\(kind.label) session"
        return .startSession(name: name.isEmpty ? fallback : name,
                             kind: kind,
                             // A free period frees everything, so its selection
                             // is irrelevant — don't carry stray picks into it.
                             selection: kind == .free ? FamilyActivitySelection() : selection,
                             minutes: minutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Name")) {
                    TextField(tr("e.g. Deep work"), text: $name)
                }
                Section {
                    Picker(tr("Type"), selection: $kind) {
                        Text(tr("Block")).tag(SessionKind.block)
                        Text(tr("Unblock")).tag(SessionKind.unblock)
                        Text(tr("Free")).tag(SessionKind.free)
                    }
                    .pickerStyle(.segmented)
                    if kind != .free {
                        Button {
                            showPicker = true
                        } label: {
                            HStack {
                                Text(kind == .block
                                     ? tr("Apps to block") : tr("Apps to unblock"))
                                Spacer()
                                Text(String(format: tr("%d selected"),
                                            selection.applicationTokens.count
                                            + selection.categoryTokens.count))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    if kind == .unblock {
                        Text(tr("Temporarily lifts limits, schedules, and block sessions for the chosen apps."))
                    } else if kind == .free {
                        Text(tr("Temporarily lifts everything — no app blocks apply, and usage during the free period doesn't count toward your limits."))
                    }
                }
                Section {
                    DurationPicker(minutes: $minutes, maxHours: 24)
                } header: {
                    Text(tr("Duration"))
                }
                Section {
                    let (dir, delay) = model.preview(draft)
                    Label(String(format: tr("%@ — session starts in %@, then runs %d min"),
                                 dir.label, delay.shortDelayLabel, minutes),
                          systemImage: "clock")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .paper()
            .casedNavigationTitle(tr("New session"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Queue change")) {
                        model.queue(draft)
                        dismiss()
                    }
                    // A free period needs no app selection; block/unblock do.
                    .disabled(kind != .free
                              && selection.applicationTokens.isEmpty
                              && selection.categoryTokens.isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) {
                AppPickerSheet(selection: $selection)
            }
        }
    }
}

// MARK: - Time helpers

func minutesOfDay(_ date: Date) -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

func defaultTime(hour: Int) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: 0, second: 0,
                          of: Date()) ?? Date()
}

// MARK: - Calendar (month)

struct CalendarView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("weekStartMonday") private var weekStartMonday = false
    @State private var anchor = Date()
    @State private var selected = Calendar.current.startOfDay(for: Date())

    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = weekStartMonday ? 2 : 1
        return c
    }
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(periodTitle).font(.headline)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }

                LazyVGrid(columns: cols, spacing: 4) {
                    // Index the labels, not the strings — weekday symbols repeat
                    // ("T", "S"), which would collapse under id: \.self.
                    ForEach(orderedWeekdaySymbols.indices, id: \.self) { i in
                        Text(orderedWeekdaySymbols[i])
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: cols, spacing: 4) {
                    ForEach(monthDays, id: \.self) { day in
                        dayCell(day, faded: !cal.isDate(day, equalTo: anchor,
                                                        toGranularity: .month))
                    }
                }

                dayEvents
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Calendar"))
        .onAppear {
            if model.inTutorial { model.tutorialScreen = "calendar" }
            model.tutorialDidOpenCalendar()
        }
    }

    private func dayCell(_ day: Date, faded: Bool) -> some View {
        let isSel = cal.isDate(day, inSameDayAs: selected)
        let isToday = cal.isDateInToday(day)
        let count = events(on: day).count
        return Button { selected = day } label: {
            VStack(spacing: 1) {
                Text("\(cal.component(.day, from: day))")
                    .font(.callout)
                    .foregroundStyle(faded ? Ink.faint : Ink.ink)
                // Small count of things scheduled that day. Blank space is
                // reserved so the day numbers stay aligned across the grid.
                Text(count > 0 ? "\(count)" : " ")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Ink.accent)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(isSel ? Ink.accent.opacity(0.15) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(isToday ? Ink.accent : Color.clear, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var dayEvents: some View {
        let evs = events(on: selected)
        return VStack(alignment: .leading, spacing: 10) {
            Text(selected.formatted(date: .complete, time: .omitted))
                .font(.subheadline.bold())
            if evs.isEmpty {
                Text(tr("Nothing on this day."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(evs) { e in
                    NavigationLink {
                        ScheduledItemDetailView(title: e.name, summary: e.summary,
                                                timing: e.detail, appsTitle: e.appsTitle,
                                                selection: e.selection)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: e.symbol).foregroundStyle(e.color)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.name).font(.subheadline).foregroundStyle(Ink.ink)
                                Text(e.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(Ink.faint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    struct DayEvent: Identifiable {
        let id = UUID()
        let symbol: String
        let name: String
        let detail: String
        let color: Color
        var summary: String = ""
        var appsTitle: String? = nil
        var selection: FamilyActivitySelection? = nil
    }

    private func events(on day: Date) -> [DayEvent] {
        var out: [DayEvent] = []
        for s in model.state.schedules where s.recurrence.matches(dayOf: day) {
            out.append(DayEvent(symbol: "repeat", name: s.name,
                detail: "\(minutesLabel(s.startMinutes))–\(minutesLabel(s.endMinutes)) · \(s.mode.label)",
                color: SchedPalette.recurring,
                summary: s.mode.label,
                appsTitle: s.mode == .blockAllExcept
                    ? tr("Apps that stay usable") : tr("Apps to block"),
                selection: s.selection))
        }
        for e in model.state.exemptions where e.recurrence.matches(dayOf: day) {
            out.append(DayEvent(symbol: "leaf", name: e.name,
                detail: "\(minutesLabel(e.startMinutes))–\(minutesLabel(e.endMinutes)) · \(tr("Free period"))",
                color: SchedPalette.recurring,
                summary: tr("Free period")))
        }
        for w in model.state.planned
        where cal.isDate(w.startsAt, inSameDayAs: day)
            || (w.startsAt < cal.startOfDay(for: day) && w.endsAt > day) {
            out.append(DayEvent(symbol: w.kind == .free ? "leaf" : "calendar.badge.clock",
                name: w.name,
                detail: "\(w.startsAt.formatted(date: .omitted, time: .shortened)) → \(w.endsAt.formatted(date: .omitted, time: .shortened))",
                color: SchedPalette.planned,
                summary: w.kind.label,
                appsTitle: w.kind == .free ? nil
                    : (w.kind == .blockAllExcept
                       ? tr("Apps that stay usable") : tr("Apps to block")),
                selection: w.kind == .free ? nil : w.selection))
        }
        if cal.isDateInToday(day) {
            for s in model.state.sessions where s.isActive {
                out.append(DayEvent(symbol: "play.circle", name: s.name,
                    detail: String(format: tr("until %@"),
                                   s.endsAt.formatted(date: .omitted, time: .shortened)),
                    color: SchedPalette.sessions,
                    summary: s.kind == .block
                        ? tr("Blocking the selected apps")
                        : tr("Unblocking the selected apps"),
                    appsTitle: s.kind == .block
                        ? tr("Apps blocked") : tr("Apps unblocked"),
                    selection: s.selection))
            }
        }
        return out
    }

    private func shift(_ dir: Int) {
        if let d = cal.date(byAdding: .month, value: dir, to: anchor) { anchor = d }
    }

    private var periodTitle: String {
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"
        return f.string(from: anchor)
    }

    private var orderedWeekdaySymbols: [String] {
        let syms = cal.veryShortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(syms[first...] + syms[..<first])
    }

    private var monthDays: [Date] {
        guard let monthInterval = cal.dateInterval(of: .month, for: anchor),
              let firstWeek = cal.dateInterval(of: .weekOfYear, for: monthInterval.start)
        else { return [] }
        var days: [Date] = []
        var d = firstWeek.start
        for _ in 0..<42 {
            days.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return days
    }
}
