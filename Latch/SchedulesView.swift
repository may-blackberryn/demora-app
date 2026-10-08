//
//  SchedulesView.swift
//  Recurring blocking schedules (daily/weekly/monthly), free periods,
//  one-off planned windows, and immediate sessions. All delay-gated.
//

import SwiftUI
import FamilyControls

struct SchedulesView: View {
    @AppAccent private var accent
    @EnvironmentObject var model: AppModel
    @State private var showAddSchedule = false
    @State private var newSession: NewSessionKind?

    private enum NewSessionKind: String, Identifiable {
        case now, planned, recurring
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .bottom) {
                        DemoraPageTitle(title: tr("Schedules"))
                        Spacer()
                        if !model.inTutorial {
                            NavigationLink {
                                HelpHubView().toolbar(.visible, for: .navigationBar)
                            } label: {
                                Image(systemName: "questionmark.circle")
                            }
                            .accessibilityLabel(tr("Help"))
                        }
                    }
                    overviewSection
                        .demoraSurface()
                        .tutorialHighlight(model.tutorial == .exploreCalendar
                                           && model.calendarFocusNowNext
                                           && model.tutorialScreen == "schedulesRoot")
                    if !model.inTutorial {
                        Menu {
                            Button(tr("Now"), systemImage: "play.circle") {
                                newSession = .now
                            }
                            Button(tr("Planned"), systemImage: "calendar.badge.clock") {
                                newSession = .planned
                            }
                            Button(tr("Recurring"), systemImage: "repeat") {
                                newSession = .recurring
                            }
                        } label: {
                            Label(tr("New session"), systemImage: "plus")
                        }
                        .buttonStyle(DemoraPrimaryButtonStyle())
                    }
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
                    if model.inTutorial {
                        // Keep the practice walkthrough's existing highlighted
                        // Recurring/Calendar actions directly reachable.
                        sessionsIndex
                        calendarIndex
                    } else {
                        scheduleDestinations
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if model.inTutorial && model.selectedTab == 2 {
                    model.tutorialScreen = "schedulesRoot"
                }
            }
            .refreshable { model.tick() }
            .sheet(isPresented: $showAddSchedule) { ScheduleEditorView() }
            .sheet(item: $newSession) { kind in
                switch kind {
                case .now: SessionStartView()
                case .planned: PlannedEditorView()
                case .recurring: ScheduleEditorView()
                }
            }
        }
    }

    // MARK: Now & next overview

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DemoraSectionTitle(title: tr("now & next"), symbol: "calendar.badge.clock")
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
                    HStack {
                        Text(tr("This week")).font(.caption.smallCaps())
                            .foregroundStyle(.secondary)
                        Spacer()
                        NavigationLink {
                            UpcomingWeekView(items: upcoming)
                                .toolbar(.visible, for: .navigationBar)
                        } label: {
                            Text(tr("See all")).font(.caption.weight(.semibold))
                        }
                    }
                    overviewGroup(tr("Coming up"), Array(upcoming.prefix(3)), active: false)
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
                                            selection: item.selection,
                                            scheduleID: item.scheduleID)
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.system(.title3, design: .serif))
                                .foregroundStyle(Ink.ink)
                            Text(item.detail).font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Ink.faint)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(Ink.faint)
                    }
                    .padding(.vertical, 12).padding(.leading, 28)
                    .overlay(alignment: .leading) {
                        DemoraTimelineMark(color: active ? item.color : Ink.faint)
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
                             color: accent,
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
                             color: accent,
                             summary: sch.mode.label,
                             appsTitle: sch.mode == .blockAllExcept
                                ? tr("Apps that stay usable") : tr("Apps to block"),
                             selection: sch.selection, scheduleID: sch.id))
        }
        for w in model.state.planned where w.isActive {
            out.append(.init(id: "pl-\(w.id)",
                             symbol: w.kind == .free ? "leaf" : "nosign",
                             name: w.name,
                             detail: String(format: tr("until %@"),
                                            w.endsAt.formatted(date: .omitted, time: .shortened)),
                             color: accent,
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
                             color: accent,
                             summary: tr("Free period")))
        }
        return out
    }

    private var upcomingItems: [OverviewItem] {
        let now = Date()
        let cal = Calendar.current
        let weekEnd = cal.date(byAdding: .day, value: 7, to: now) ?? now
        var dated: [(Date, OverviewItem)] = []
        for w in model.state.planned where w.startsAt > now && w.startsAt < weekEnd {
            let detail = "\(w.startsAt.formatted(date: .abbreviated, time: .shortened)) → \(w.endsAt.formatted(date: .omitted, time: .shortened))"
            dated.append((w.startsAt,
                          OverviewItem(id: "upl-\(w.id)",
                                       symbol: w.kind == .free ? "leaf" : "nosign",
                                       name: w.name, detail: detail,
                                       color: accent,
                                       summary: w.kind.label,
                                       appsTitle: w.kind == .free ? nil
                                          : (w.kind == .blockAllExcept
                                             ? tr("Apps that stay usable") : tr("Apps to block")),
                                       selection: w.kind == .free ? nil : w.selection)))
        }
        var nextRecurringIDs = Set<UUID>()
        var nextFreeIDs = Set<UUID>()
        for offset in 0...7 {
            guard let day = cal.date(byAdding: .day, value: offset,
                                     to: cal.startOfDay(for: now)) else { continue }
            for sch in model.state.schedules where sch.recurrence.matches(dayOf: day) {
                guard !nextRecurringIDs.contains(sch.id) else { continue }
                guard let start = cal.date(bySettingHour: sch.startMinutes / 60,
                                           minute: sch.startMinutes % 60,
                                           second: 0, of: day),
                      start > now, start < weekEnd else { continue }
                nextRecurringIDs.insert(sch.id)
                let detail = "\(start.formatted(date: .abbreviated, time: .shortened))–\(minutesLabel(sch.endMinutes))"
                dated.append((start,
                              OverviewItem(id: "usch-\(sch.id)-\(offset)",
                                           symbol: "calendar", name: sch.name,
                                           detail: detail, color: accent,
                                           summary: sch.mode.label,
                                           appsTitle: sch.mode == .blockAllExcept
                                              ? tr("Apps that stay usable") : tr("Apps to block"),
                                           selection: sch.selection, scheduleID: sch.id)))
            }
            for ex in model.state.exemptions where ex.recurrence.matches(dayOf: day) {
                guard !nextFreeIDs.contains(ex.id) else { continue }
                guard let start = cal.date(bySettingHour: ex.startMinutes / 60,
                                           minute: ex.startMinutes % 60,
                                           second: 0, of: day),
                      start > now, start < weekEnd else { continue }
                nextFreeIDs.insert(ex.id)
                let detail = "\(start.formatted(date: .abbreviated, time: .shortened))–\(minutesLabel(ex.endMinutes))"
                dated.append((start,
                              OverviewItem(id: "uex-\(ex.id)-\(offset)",
                                           symbol: "leaf", name: ex.name,
                                           detail: detail, color: accent,
                                           summary: tr("Free period"))))
            }
        }
        return dated.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    // MARK: Destinations on the same Schedules page (not inner tabs)

    private var scheduleDestinations: some View {
        VStack(spacing: 0) {
            NavigationLink {
                schedulePage(title: tr("Sessions")) { sessionsIndex }
            } label: {
                GridCard(symbol: "play.circle", title: tr("Sessions"),
                         subtitle: [tr("Now"), tr("Planned"), tr("Recurring")]
                            .joined(separator: " · "))
            }
            NavigationLink {
                DayNightSchedulesView().toolbar(.visible, for: .navigationBar)
            } label: {
                GridCard(symbol: "sun.max", title: tr("Day & night"),
                         subtitle: tr("Wake up") + " · " + tr("Sleep"))
            }
            calendarIndex
            NavigationLink {
                ScheduleConflictsView().toolbar(.visible, for: .navigationBar)
            } label: {
                GridCard(symbol: "arrow.triangle.branch", title: tr("Schedule conflicts"),
                         subtitle: tr("See overlapping rules"))
            }
        }
        .buttonStyle(.plain)
    }

    private func schedulePage<Content: View>(title: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DemoraPageTitle(title: title)
                content()
            }
            .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(title)
        .toolbar(.visible, for: .navigationBar)
    }

    private var sessionsIndex: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                SessionsListView().toolbar(.visible, for: .navigationBar)
            } label: {
                TypeCard(symbol: "play.circle", title: tr("Now"),
                         count: model.state.sessions.filter(\.isActive).count,
                         activeCount: model.state.sessions.filter(\.isActive).count,
                         color: accent)
            }
            NavigationLink {
                PlannedListView().toolbar(.visible, for: .navigationBar)
            } label: {
                TypeCard(symbol: "calendar.badge.clock", title: tr("Planned"),
                         count: model.state.planned.count,
                         activeCount: model.state.planned.filter(\.isActive).count,
                         color: accent)
            }
            NavigationLink {
                RecurringListView().toolbar(.visible, for: .navigationBar)
            } label: {
                TypeCard(symbol: "repeat", title: tr("Recurring"),
                         count: model.state.schedules.count + model.state.exemptions.count,
                         activeCount: model.state.schedules.filter { $0.isActive() }.count
                                    + model.state.exemptions.filter { $0.isActive() }.count,
                         color: accent)
            }
            .tutorialHighlight(model.tutorial == .removeSchedule
                               && model.tutorialScreen == "schedulesRoot")
        }
        .buttonStyle(.plain)
    }

    private var calendarIndex: some View {
        NavigationLink {
            CalendarView().toolbar(.visible, for: .navigationBar)
        } label: {
            GridCard(symbol: "calendar", title: tr("Calendar"),
                     subtitle: tr("month"))
        }
        .tutorialHighlight(model.tutorial == .exploreCalendar
                           && !model.calendarFocusNowNext
                           && model.tutorialScreen == "schedulesRoot")
        .buttonStyle(.plain)
    }

}

// MARK: - Overview model

struct OverviewItem: Identifiable {
    let id: String
    let symbol: String
    let name: String
    let detail: String
    var color: Color
    var summary: String = ""
    var appsTitle: String? = nil
    var selection: FamilyActivitySelection? = nil
    var scheduleID: UUID? = nil
}

private struct UpcomingWeekView: View {
    let items: [OverviewItem]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    NavigationLink {
                        ScheduledItemDetailView(title: item.name, summary: item.summary,
                                                timing: item.detail,
                                                appsTitle: item.appsTitle,
                                                selection: item.selection,
                                                scheduleID: item.scheduleID)
                    } label: {
                        HStack {
                            Image(systemName: item.symbol).foregroundStyle(item.color)
                            VStack(alignment: .leading) {
                                Text(item.name).font(.headline)
                                Text(item.detail).font(.caption).foregroundStyle(Ink.faint)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .demoraSurface()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("This week"))
    }
}

/// Pushed when you tap a scheduled item (now & next, or a calendar day) —
/// shows what it does, when, and the apps it covers.
struct ScheduledItemDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showEditSelection = false
    let title: String
    let summary: String
    let timing: String
    var appsTitle: String? = nil
    var selection: FamilyActivitySelection? = nil
    var scheduleID: UUID? = nil

    private var currentSchedule: BlockSchedule? {
        model.state.schedules.first { $0.id == scheduleID }
    }

    private var displayedSelection: FamilyActivitySelection? {
        scheduleID == nil ? selection : currentSchedule?.selection
    }

    private var hasApps: Bool {
        guard let s = displayedSelection else { return false }
        return !(s.applicationTokens.isEmpty
                 && s.categoryTokens.isEmpty
                 && s.webDomainTokens.isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DemoraPageTitle(title: title)
                VStack(alignment: .leading, spacing: 10) {
                if !summary.isEmpty {
                    Text(summary).font(.system(.headline, design: .serif))
                }
                Label(timing, systemImage: "clock")
                    .font(.subheadline).foregroundStyle(Ink.faint)
                }
                .demoraSurface()
            if hasApps, let appsTitle, let selection = displayedSelection {
                VStack(alignment: .leading, spacing: 12) {
                    DemoraSectionTitle(title: appsTitle)
                    SelectedAppsView(selection: selection)
                }
                .demoraSurface()
            }
                if let schedule = currentSchedule, !model.inTutorial {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(tr("Edit apps")) { showEditSelection = true }
                            .disabled(scheduleChangePending(schedule.id, in: model.state))
                        Button(tr("Remove…"), role: .destructive) {
                            model.queue(.removeSchedule(id: schedule.id))
                        }
                        .disabled(scheduleChangePending(schedule.id, in: model.state))
                        if scheduleChangePending(schedule.id, in: model.state) {
                            Text(tr("A change for this setting is already pending. Cancel it on the Home tab first if you want something different."))
                                .font(.footnote).foregroundStyle(Ink.faint)
                        }
                    }
                    .demoraSurface()
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(title)
        .sheet(isPresented: $showEditSelection) {
            if let schedule = currentSchedule {
                ScheduleSelectionEditorView(schedule: schedule)
            }
        }
    }
}

// MARK: - Type card

struct TypeCard: View {
    @AppAccent private var accent
    let symbol: String
    let title: String
    let count: Int
    let activeCount: Int
    var color: Color? = nil

    private var subtitle: String {
        if count == 0 { return tr("none") }
        if activeCount > 0 { return String(format: tr("%d · %d active"), count, activeCount) }
        return String(format: tr("%d total"), count)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .light))
                    .foregroundStyle(color ?? accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(.title3, design: .serif)).foregroundStyle(Ink.ink)
                    Text(subtitle).font(.subheadline).foregroundStyle(Ink.faint)
                }
                Spacer()
                Text("\(count)")
                    .font(.system(.title2, design: .serif).monospacedDigit())
                    .foregroundStyle(accent)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Ink.faint)
            }
            .padding(.vertical, 22)
            Rectangle().fill(Ink.rule).frame(height: 1)
        }
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DemoraPageTitle(title: tr("Sessions"))
                if model.state.sessions.filter(\.isActive).isEmpty {
                    Text(tr("No active sessions"))
                        .foregroundStyle(Ink.faint).demoraSurface()
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
                    .demoraSurface()
                }
                Button { showAdd = true } label: {
                    Label(tr("New session…"), systemImage: "play.circle.fill")
                }
                .buttonStyle(DemoraPrimaryButtonStyle())
                Text(String(format: tr("One-off and unplanned, but still delay-gated. A block session waits %@; an unblock session waits %@. Ending early flips the rule (or use an override)."),
                            model.state.strictDelay.shortDelayLabel,
                            model.state.lenientDelay.shortDelayLabel))
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DemoraPageTitle(title: tr("Planned"))
                if model.state.planned.isEmpty {
                    Text(tr("Nothing planned"))
                        .foregroundStyle(Ink.faint).demoraSurface()
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
                    .demoraSurface()
                }
                Button { showAdd = true } label: {
                    Label(tr("Plan a window…"), systemImage: "calendar.badge.plus")
                }
                .buttonStyle(DemoraPrimaryButtonStyle())
                Text(tr("Plan ahead for specific dates — a trip, a weekend, an exam. Doesn't repeat. Planning a block is stricter; planning a free period is less strict."))
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Planned"))
        .refreshable { model.tick() }
        .sheet(isPresented: $showAdd) { PlannedEditorView() }
    }
}

struct RecurringListView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAdd = false
    @State private var editingSchedule: BlockSchedule?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DemoraPageTitle(title: tr("Recurring"))
                DemoraSectionTitle(title: tr("Blocks"), symbol: "shield")
                if model.state.schedules.isEmpty {
                    Text(tr("No schedules"))
                        .foregroundStyle(Ink.faint).demoraSurface()
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
                        if !model.inTutorial {
                            Button(tr("Edit apps")) { editingSchedule = sched }
                                .disabled(scheduleChangePending(sched.id, in: model.state))
                        }
                        Button(tr("Remove…"), role: .destructive) {
                            model.queue(.removeSchedule(id: sched.id))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(scheduleChangePending(sched.id, in: model.state))
                        .tutorialHighlight(model.tutorial == .removeSchedule
                                           && model.tutorialScreen == "recurring")
                        if scheduleChangePending(sched.id, in: model.state) {
                            Text(tr("A change for this setting is already pending. Cancel it on the Home tab first if you want something different."))
                                .font(.footnote).foregroundStyle(Ink.faint)
                        }
                    }
                    .demoraSurface()
                }
                DemoraSectionTitle(title: tr("Free periods"), symbol: "leaf")
                if model.state.exemptions.isEmpty {
                    Text(tr("No free periods"))
                        .foregroundStyle(Ink.faint).demoraSurface()
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
                    .demoraSurface()
                }
                Text(String(format: tr("Repeating windows: every day, chosen weekdays, or monthly patterns. Adding waits %@; removing waits %@."),
                            model.state.strictDelay.shortDelayLabel,
                            model.state.lenientDelay.shortDelayLabel))
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Recurring"))
        .onAppear { if model.inTutorial { model.tutorialScreen = "recurring" } }
        .refreshable { model.tick() }
        .toolbar {
            if !model.inTutorial {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { ScheduleEditorView() }
        .sheet(item: $editingSchedule) { ScheduleSelectionEditorView(schedule: $0) }
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

// MARK: - Schedule selection editing

private func scheduleChangePending(_ id: UUID, in state: LatchState) -> Bool {
    let key = ChangeEngine.conflictKey(.removeSchedule(id: id))
    return state.pending.contains { ChangeEngine.conflictKey($0.action) == key }
}

/// Only the selection is editable. Read the current rule for validation so a
/// stale sheet cannot recreate a deleted schedule or overwrite other fields.
private struct ScheduleSelectionEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let schedule: BlockSchedule
    @State private var selection: FamilyActivitySelection
    @State private var showPicker = false

    init(schedule: BlockSchedule) {
        self.schedule = schedule
        _selection = State(initialValue: schedule.selection)
    }

    private var current: BlockSchedule? {
        model.state.schedules.first { $0.id == schedule.id }
    }

    private var action: ChangeAction {
        .updateScheduleSelection(id: schedule.id, selection: selection)
    }

    private var isValid: Bool {
        guard let current else { return false }
        return current.selection != selection
            && current.acceptsSelection(selection)
            && !scheduleChangePending(schedule.id, in: model.state)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DemoraPageTitle(title: tr("Edit apps"))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(current?.name ?? schedule.name)
                            .font(.system(.headline, design: .serif))
                        Text("\(schedule.recurrence.label) · \(schedule.windowLabel) · \(schedule.mode.label)")
                            .font(.subheadline).foregroundStyle(Ink.faint)
                    }
                    .demoraSurface()
                    VStack(alignment: .leading, spacing: 12) {
                        DemoraSectionTitle(title: schedule.mode == .blockAllExcept
                                           ? tr("Apps that stay usable") : tr("Apps to block"))
                        Button { showPicker = true } label: {
                            HStack {
                                Text(tr("Choose apps"))
                                Spacer()
                                Text(String(format: tr("%d selected"),
                                            selection.applicationTokens.count
                                            + selection.categoryTokens.count
                                            + selection.webDomainTokens.count))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        SelectedAppsView(selection: selection)
                    }
                    .demoraSurface()
                    VStack(alignment: .leading, spacing: 8) {
                        let (direction, delay) = model.preview(action)
                        Label(String(format: tr("%@ — takes effect in %@"),
                                     direction.label, delay.shortDelayLabel),
                              systemImage: "clock")
                        Text(tr("Changing apps, categories, or websites always uses the less-strict delay. The current schedule stays in effect until the change applies."))
                        if scheduleChangePending(schedule.id, in: model.state) {
                            Text(tr("A change for this setting is already pending. Cancel it on the Home tab first if you want something different."))
                        }
                    }
                    .font(.footnote).foregroundStyle(Ink.faint)
                    .demoraSurface()
                }
                .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Edit apps"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Queue change")) {
                        if model.queue(action) != nil { dismiss() }
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showPicker) { AppPickerSheet(selection: $selection) }
        }
    }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DemoraPageTitle(title: tr("New recurring"))
                    VStack(alignment: .leading, spacing: 12) {
                        DemoraSectionTitle(title: tr("Name"))
                        TextField(tr("e.g. Bedtime"), text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(.title3, design: .serif))
                    }
                    .demoraSurface()
                    VStack(alignment: .leading, spacing: 14) {
                        DemoraSectionTitle(title: tr("Type"))
                    Picker(tr("Type"), selection: $isFree) {
                        Text(tr("Block")).tag(false)
                        Text(tr("Free period")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    if isFree {
                        Text(tr("Limits won't block and usage won't count during this window."))
                            .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    }
                    .demoraSurface()
                if !isFree {
                    VStack(alignment: .leading, spacing: 14) {
                        DemoraSectionTitle(title: tr("Apps"))
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
                                            + selection.categoryTokens.count
                                            + selection.webDomainTokens.count))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        SelectedAppsView(selection: selection)
                        Text(mode == .blockAllExcept
                             ? tr("Everything on the iPhone is blocked during the window except the apps picked here.")
                             : tr("Only the apps picked here are blocked during the window."))
                            .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    .demoraSurface()
                }
                    VStack(alignment: .leading, spacing: 12) {
                        DemoraSectionTitle(title: tr("Window"))
                    DatePicker(tr("Start"), selection: $start,
                               displayedComponents: .hourAndMinute)
                    DatePicker(tr("End"), selection: $end,
                               displayedComponents: .hourAndMinute)
                    RecurrencePicker(recurrence: $recurrence, allowWrap: true)
                    }
                    .demoraSurface()
                if monthlyWrapProblem {
                        Text(tr("Monthly schedules can't cross midnight — set the end time after the start time."))
                            .font(.footnote).foregroundStyle(Ink.danger)
                            .demoraSurface()
                }
                    VStack(alignment: .leading, spacing: 8) {
                    let (dir, delay) = model.preview(scheduleAction)
                    Label(String(format: tr("%@ — takes effect in %@"),
                                 dir.label, delay.shortDelayLabel),
                          systemImage: "clock")
                        .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    .demoraSurface()
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
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
        return draft.acceptsSelection(selection)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DemoraPageTitle(title: tr("New free period"))
                    VStack(alignment: .leading, spacing: 12) {
                        DemoraSectionTitle(title: tr("Name"))
                        TextField(tr("e.g. Lunch break"), text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(.title3, design: .serif))
                    }
                    .demoraSurface()
                    VStack(alignment: .leading, spacing: 12) {
                        DemoraSectionTitle(title: tr("Window"))
                    DatePicker(tr("Start"), selection: $start,
                               displayedComponents: .hourAndMinute)
                    DatePicker(tr("End"), selection: $end,
                               displayedComponents: .hourAndMinute)
                    RecurrencePicker(recurrence: $recurrence, allowWrap: true)
                    }
                    .demoraSurface()
                if monthlyWrapProblem {
                        Text(tr("Monthly schedules can't cross midnight — set the end time after the start time."))
                            .font(.footnote).foregroundStyle(Ink.danger)
                            .demoraSurface()
                }
                    VStack(alignment: .leading, spacing: 8) {
                    let (dir, delay) = model.preview(.addExemption(draft))
                    Label(String(format: tr("%@ — takes effect in %@"),
                                 dir.label, delay.shortDelayLabel),
                          systemImage: "clock")
                        .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    .demoraSurface()
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DemoraPageTitle(title: tr("Plan a window"))
                    VStack(alignment: .leading, spacing: 12) {
                        DemoraSectionTitle(title: tr("Name"))
                        TextField(tr("e.g. Airport, weekend trip"), text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(.title3, design: .serif))
                    }
                    .demoraSurface()
                    VStack(alignment: .leading, spacing: 14) {
                        DemoraSectionTitle(title: tr("Type"))
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
                    if kind == .free {
                        Text(tr("Limits won't block and usage won't count during this window."))
                            .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    }
                    .demoraSurface()
                    VStack(alignment: .leading, spacing: 12) {
                        DemoraSectionTitle(title: tr("When"))
                    DatePicker(tr("Starts"), selection: $startsAt,
                               in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                    DatePicker(tr("Ends"), selection: $endsAt,
                               in: startsAt...,
                               displayedComponents: [.date, .hourAndMinute])
                    }
                    .demoraSurface()
                    VStack(alignment: .leading, spacing: 8) {
                    let (dir, delay) = model.preview(.addPlanned(draft))
                    Label(String(format: tr("%@ — takes effect in %@"),
                                 dir.label, delay.shortDelayLabel),
                          systemImage: "clock")
                        .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    .demoraSurface()
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DemoraPageTitle(title: tr("New session"))
                    VStack(alignment: .leading, spacing: 12) {
                        DemoraSectionTitle(title: tr("Name"))
                        TextField(tr("e.g. Deep work"), text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(.title3, design: .serif))
                    }
                    .demoraSurface()
                    VStack(alignment: .leading, spacing: 14) {
                        DemoraSectionTitle(title: tr("Type"))
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
                    if kind == .unblock {
                        Text(tr("Temporarily lifts limits, schedules, and block sessions for the chosen apps."))
                            .font(.footnote).foregroundStyle(Ink.faint)
                    } else if kind == .free {
                        Text(tr("Temporarily lifts everything — no app blocks apply, and usage during the free period doesn't count toward your limits."))
                            .font(.footnote).foregroundStyle(Ink.faint)
                    }
                }
                    .demoraSurface()
                    VStack(alignment: .leading, spacing: 12) {
                        DemoraSectionTitle(title: tr("Duration"))
                        DurationPicker(minutes: $minutes, maxHours: 24)
                    }
                    .demoraSurface()
                    VStack(alignment: .leading, spacing: 8) {
                    let (dir, delay) = model.preview(draft)
                    Label(String(format: tr("%@ — session starts in %@, then runs %d min"),
                                 dir.label, delay.shortDelayLabel, minutes),
                          systemImage: "clock")
                        .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    .demoraSurface()
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
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
    @AppAccent private var accent
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
            calendarContents
                .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Calendar"))
        .onAppear {
            if model.inTutorial { model.tutorialScreen = "calendar" }
            model.tutorialDidOpenCalendar()
        }
    }

    private var calendarContents: some View {
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
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(isSel ? accent.opacity(0.15) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(isToday ? accent : Color.clear, lineWidth: 1))
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
                                                selection: e.selection,
                                                scheduleID: e.scheduleID)
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
        var scheduleID: UUID? = nil
    }

    private func events(on day: Date) -> [DayEvent] {
        var out: [DayEvent] = []
        for s in model.state.schedules where s.recurrence.matches(dayOf: day) {
            out.append(DayEvent(symbol: "repeat", name: s.name,
                detail: "\(minutesLabel(s.startMinutes))–\(minutesLabel(s.endMinutes)) · \(s.mode.label)",
                color: accent,
                summary: s.mode.label,
                appsTitle: s.mode == .blockAllExcept
                    ? tr("Apps that stay usable") : tr("Apps to block"),
                selection: s.selection, scheduleID: s.id))
        }
        for e in model.state.exemptions where e.recurrence.matches(dayOf: day) {
            out.append(DayEvent(symbol: "leaf", name: e.name,
                detail: "\(minutesLabel(e.startMinutes))–\(minutesLabel(e.endMinutes)) · \(tr("Free period"))",
                color: accent,
                summary: tr("Free period")))
        }
        for w in model.state.planned
        where cal.isDate(w.startsAt, inSameDayAs: day)
            || (w.startsAt < cal.startOfDay(for: day) && w.endsAt > day) {
            out.append(DayEvent(symbol: w.kind == .free ? "leaf" : "calendar.badge.clock",
                name: w.name,
                detail: "\(w.startsAt.formatted(date: .omitted, time: .shortened)) → \(w.endsAt.formatted(date: .omitted, time: .shortened))",
                color: accent,
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
                    color: accent,
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
