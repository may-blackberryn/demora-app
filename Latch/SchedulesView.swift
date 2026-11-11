//
//  SchedulesView.swift
//  Shared recurrence/time helpers and the Rules calendar.
//

import SwiftUI
import FamilyControls

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
    @State private var summary: RuleSummaryRequest?
    @ScaledMetric(relativeTo: .body) private var dayControlSize: CGFloat = 44
    /// Opens a waiting change in Changes. Without a callback,
    /// "See in Changes" goes to Today, where Changing soon lists it.
    let onSeeChange: ((PendingChange.ID) -> Void)?

    init(onSeeChange: ((PendingChange.ID) -> Void)? = nil) {
        self.onSeeChange = onSeeChange
    }

    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = weekStartMonday ? 2 : 1
        return c
    }
    private var cols: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: max(44, dayControlSize)),
                                  spacing: DemoraSpace.xxs), count: 7)
    }

    var body: some View {
        ScrollView {
            calendarContents
                .padding(DemoraSpace.pageGutter)
                .frame(maxWidth: DemoraSpace.maxContentWidth)
                .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Calendar"))
        .ruleSummary($summary) { id in
            if let onSeeChange { onSeeChange(id) } else { model.selectedTab = 0 }
        }
    }

    private var calendarContents: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
            VStack(spacing: DemoraSpace.s) {
                HStack(spacing: DemoraSpace.xs) {
                    Button { shift(-1) } label: {
                        Image(systemName: "chevron.left")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(tr("Back"))
                    Text(periodTitle)
                        .demoraType(.cardTitle)
                        .foregroundStyle(Ink.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                    Button { shift(1) } label: {
                        Image(systemName: "chevron.right")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(tr("Next"))
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)

                // Preserve full touch targets on narrow screens and at large
                // text sizes rather than squeezing seven days into tiny cells.
                ViewThatFits(in: .horizontal) {
                    monthGrid
                    ScrollView(.horizontal) {
                        monthGrid
                    }
                }
            }
            .paperCard()

            dayEvents
        }
    }

    private var monthGrid: some View {
        VStack(spacing: DemoraSpace.xs) {
            LazyVGrid(columns: cols, spacing: DemoraSpace.xxs) {
                // Index the labels, not the strings — weekday symbols repeat
                // ("T", "S"), which would collapse under id: \.self.
                ForEach(orderedWeekdaySymbols.indices, id: \.self) { i in
                    Text(orderedWeekdaySymbols[i])
                        .demoraType(.label)
                        .foregroundStyle(Ink.inkSoft)
                }
            }

            LazyVGrid(columns: cols, spacing: DemoraSpace.xxs) {
                ForEach(monthDays, id: \.self) { day in
                    dayCell(day, faded: !cal.isDate(day, equalTo: anchor,
                                                    toGranularity: .month))
                }
            }
        }
        .frame(minWidth: max(44, dayControlSize) * 7 + DemoraSpace.xxs * 6)
    }

    private func dayCell(_ day: Date, faded: Bool) -> some View {
        let isSel = cal.isDate(day, inSameDayAs: selected)
        let isToday = cal.isDateInToday(day)
        let count = events(on: day).count
        return Button { selected = day } label: {
            VStack(spacing: DemoraSpace.xxs) {
                Text("\(cal.component(.day, from: day))")
                    .demoraType(.time)
                    .foregroundStyle(faded ? Ink.inkSoft : Ink.ink)
                // Small count of things scheduled that day. Blank space is
                // reserved so the day numbers stay aligned across the grid.
                Text(count > 0 ? "\(count)" : " ")
                    .demoraType(.chip)
                    .foregroundStyle(accent)
            }
            .padding(.vertical, DemoraSpace.xxs)
            .frame(maxWidth: .infinity, minHeight: max(44, dayControlSize))
            .background(isSel ? accent.opacity(InkPalette.tintLight) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: DemoraSpace.xs)
                .stroke(isToday ? accent : Color.clear, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: DemoraSpace.xs))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(count > 0 ? "\(count)" : "")
        .accessibilityAddTraits(isSel ? [.isSelected] : [])
    }

    private var dayEvents: some View {
        let evs = events(on: selected)
        return VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
            Text(selected.formatted(date: .complete, time: .omitted))
                .demoraType(.cardTitle)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if evs.isEmpty {
                Text(tr("Nothing on this day."))
                    .demoraType(.body).foregroundStyle(Ink.inkSoft)
            } else {
                VStack(spacing: 0) {
                    ForEach(evs) { e in
                        Button { summary = RuleSummaryRequest(ref: e.ref) } label: {
                            eventRow(e)
                        }
                        .buttonStyle(.plain)
                        if e.id != evs.last?.id {
                            Rectangle().fill(Ink.hairline).frame(height: 1)
                        }
                    }
                }
                .paperCard(padding: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventRow(_ e: DayEvent) -> some View {
        HStack(spacing: DemoraSpace.s) {
            Image(systemName: e.symbol).foregroundStyle(e.color)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                Text(e.name).demoraType(.cardTitle).foregroundStyle(Ink.ink)
                Text(e.detail).demoraType(.meta).foregroundStyle(Ink.inkSoft)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(Ink.inkSoft)
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.leading)
        .padding(DemoraSpace.cardPadding)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
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
        let ref: RuleRef
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
                selection: s.selection, scheduleID: s.id, ref: .schedule(s.id)))
        }
        for e in model.state.exemptions where e.recurrence.matches(dayOf: day) {
            out.append(DayEvent(symbol: "leaf", name: e.name,
                detail: "\(minutesLabel(e.startMinutes))–\(minutesLabel(e.endMinutes)) · \(tr("Free period"))",
                color: accent,
                summary: tr("Free period"), ref: .exemption(e.id)))
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
                selection: w.kind == .free ? nil : w.selection, ref: .planned(w.id)))
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
                    selection: s.selection, ref: .session(s.id)))
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
