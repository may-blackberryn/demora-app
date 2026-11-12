//
//  TodayView.swift
//  The pieces of the Today tab (docs/today-redesign.md §5): header, attention
//  card, Now card, inbox, extra-time rows and the day thread. HomeView
//  composes them and owns their state; decisions live in TodayPresentation.
//

import SwiftUI

// MARK: - Sentences with highlighted values

/// Builds a sentence from a translated format, styling each `%@` value.
/// Values are the user's rule names (bold) and times (state ink).
enum TodaySentence {
    struct Value {
        let text: String
        var color: Color? = nil
        var bold = false
    }

    static func text(_ format: String, _ values: [Value]) -> Text {
        let parts = format.components(separatedBy: "%@")
        var result = Text(parts[0])
        for (index, part) in parts.dropFirst().enumerated() {
            if index < values.count {
                let value = values[index]
                var run = Text(value.text)
                if value.bold { run = run.bold() }
                if let color = value.color { run = run.foregroundColor(color) }
                result = result + run
            }
            result = result + Text(part)
        }
        return result
    }
}

// MARK: - Header

struct TodayHeader: View {
    @AppAccent private var accent
    @Environment(\.locale) private var locale
    let date: Date
    let hasRequests: Bool
    let onBell: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            HStack {
                Wordmark(size: 20).foregroundStyle(Ink.ink)
                Spacer()
                if hasRequests {
                    Button(action: onBell) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(accent)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Approval requests"))
                }
            }
            .frame(minHeight: 44)
            Text("\(date.formatted(.dateTime.weekday(.wide).locale(locale))) · \(date.formatted(.dateTime.day().month(.wide).locale(locale)))")
                .demoraType(.label)
                .foregroundStyle(Ink.inkSoft)
        }
    }
}

// MARK: - Attention

/// The existing banners in one card: one sentence and one action each.
/// Asking again only ever goes through iOS's own prompt (Apple 5.1.1(iv)).
struct TodayAttentionCard: View {
    @Environment(\.demoraAccentColor) private var accentValue
    let needsPermission: Bool
    let monitoringIncomplete: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            if needsPermission { ScreenTimeReauthBanner() }
            if needsPermission && monitoringIncomplete {
                Rectangle().fill(Ink.hairline).frame(height: 1)
            }
            if monitoringIncomplete { EnforcementBanner() }
        }
        .paperCard(fill: Ink.tint(Ink.loosenPair(for: accentValue)))
    }
}

// MARK: - Now card

struct NowCard: View {
    @AppAccent private var accent
    @AppLoosen private var loosen
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let summary: NowSummary
    let now: Date
    let startingWake: Bool
    let wakeSaveFailed: Bool
    let onWakeUp: () -> Void
    /// Opens the rules behind the sentence, when there are any.
    let onOpen: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.m) {
            if let onOpen, summary.action == nil {
                Button(action: onOpen) { statement.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            } else {
                statement
            }
            if summary.action == .wakeUp {
                Button(action: onWakeUp) {
                    HStack(spacing: DemoraSpace.xs) {
                        if startingWake {
                            ProgressView().tint(Ink.paper)
                        } else {
                            Image(systemName: "sunrise").accessibilityHidden(true)
                        }
                        Text(tr("Wake up"))
                    }
                }
                .buttonStyle(DemoraPrimaryButtonStyle())
                .disabled(startingWake)
                if wakeSaveFailed {
                    Text(tr("Wake-up could not be saved. Try again."))
                        .demoraType(.meta)
                        .foregroundStyle(loosen)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DemoraSpace.l)
        .paperCard(padding: 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: summary)
    }

    private var statement: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            hero
                .demoraType(.hero)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            // Facts drop under the sentence; at large sizes they stack.
            ForEach(Array(summary.facts.enumerated()), id: \.offset) { _, fact in
                factView(fact)
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var hero: Text {
        switch summary.hero {
        case .wakeNeeded:
            return Text(tr("Good morning. Your apps wait until you wake up."))
        case .wakeRunning(let opens):
            return TodaySentence.text(tr("Your apps open at %@."), [time(opens, loosen)])
        case .oneBlock(let name, let until):
            return TodaySentence.text(tr("%@ is on until %@."),
                                      [.init(text: name, bold: true), time(until, loosen)])
        case .severalBlocks(let count, let firstEnd):
            return TodaySentence.text(
                tr("%d blocks are on. The first ends at %@.")
                    .replacingOccurrences(of: "%d", with: "\(count)"),
                [time(firstEnd, loosen)])
        case .spent(let names, let forNow):
            if names.count == 1 {
                return TodaySentence.text(tr(forNow ? "%@ is used up for now." : "%@ is used up for today."),
                                          [.init(text: names[0], bold: true)])
            }
            return Text(String(format: tr(forNow ? "%d limits are used up for now."
                                                 : "%d limits are used up for today."), names.count))
        case .free(let until):
            return TodaySentence.text(tr("You're in a free period until %@."), [time(until, Ink.free)])
        case .nothing:
            return Text(tr("Nothing is blocked right now."))
        }
    }

    @ViewBuilder private func factView(_ fact: NowSummary.Fact) -> some View {
        switch fact {
        case .wakeWait(let name, let minutes):
            Text(String(format: tr("%@ · wait %@"), name,
                        ReceiptPlan.waitText(TimeInterval(minutes * 60), locale: locale)))
        case .countdown(let date):
            HStack(spacing: DemoraSpace.xxs) {
                Text(tr(isWake ? "Opens in" : "Ends in"))
                // A wall-clock end (sessions, schedules, a projected wake
                // release), not a TimeGuard deadline, so not CountdownText.
                Text(timerInterval: Date.now...max(Date.now.addingTimeInterval(1), date),
                     countsDown: true)
                    .demoraType(.time)
                    .foregroundStyle(Ink.ink)
            }
        case .names(let names, let more):
            Text(more > 0
                 ? names.joined(separator: ", ") + " " + String(format: tr("and %d more"), more)
                 : names.joined(separator: ", "))
        case .resetsAtMidnight:
            Text(tr("Resets at midnight"))
        case .next(let name, let at):
            TodaySentence.text(tr("Next: %@ at %@"),
                               [.init(text: name, bold: true), time(at, nil)])
        }
    }

    private var isWake: Bool {
        if case .wakeRunning = summary.hero { return true }
        return false
    }

    private func time(_ date: Date, _ color: Color?) -> TodaySentence.Value {
        var calendar = Calendar.current
        calendar.locale = locale
        return .init(text: TodayTimeText.short(date, now: now, calendar: calendar, locale: locale),
                     color: color)
    }
}

// MARK: - Inbox

/// One approval request from someone who chose you as their trusted contact.
struct InboxCard: View {
    @AppAccent private var accent
    @Environment(\.locale) private var locale
    let request: IncomingRequest
    let onRespond: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                (request.requesterName.isEmpty
                    ? Text(String(format: tr("A contact asks to apply “%@”"), request.summary))
                    : TodaySentence.text(tr("%@ asks to apply “%@”"),
                                         [.init(text: request.requesterName, bold: true),
                                          .init(text: request.summary)]))
                    .demoraType(.body)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(request.createdAt.formatted(.dateTime.hour().minute().locale(locale)))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: DemoraSpace.s) {
                Button(tr("Approve")) { onRespond(true) }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                Button(tr("Deny"), role: .destructive) { onRespond(false) }
                    .buttonStyle(.bordered)
            }
            .font(DemoraType.button)
            .controlSize(.regular)
        }
        .paperCard()
    }
}

// MARK: - Extra time

/// Which gate a limit's next extra-time step needs. The same routing the
/// Limits tab used, so every step keeps its wait, contact, phrase or password.
enum ExtraTimeRoute {
    case contact(ExtraContactContext)
    case password
    case phrase
    case wait

    static func route(for limit: AppLimit, remaining: Int) -> ExtraTimeRoute {
        if let pending = ContactsRelay.pendingExtraRequest(for: limit.id) {
            return .contact(pending)
        }
        guard let steps = limit.extraTime?.effectiveSteps,
              steps.indices.contains(steps.count - remaining) else { return .wait }
        let index = steps.count - remaining
        let step = steps[index]
        if step.contactRequired {
            return .contact(ExtraContactContext(
                requestID: UUID().uuidString, limitID: limit.id,
                day: SharedStore.dayKey(for: TimeGuard.now()),
                stepIndex: index, step: step, limitName: limit.name))
        }
        if step.passwordPolicyID != nil { return .password }
        if step.phrasePolicyID != nil { return .phrase }
        return .wait
    }
}

/// Limits whose extra time is ready, waiting or running, under the report.
/// The report can't start host actions, so these rows do.
struct ExtraTimeRows: View {
    @AppAccent private var accent
    let limits: [AppLimit]
    /// Read in event callbacks, never while drawing.
    let states: [UUID: ExtraTimeState]
    /// Limits whose extra time waits on a sent contact request (event-side).
    let contactPending: Set<UUID>
    let onRequest: (AppLimit, Int) -> Void

    var body: some View {
        let rows = limits.compactMap { limit -> (AppLimit, ExtraTimeState)? in
            guard let state = states[limit.id] else { return nil }
            switch state {
            case .ready, .waiting, .active: return (limit, state)
            default: return nil
            }
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Rectangle().fill(Ink.hairline).frame(height: 1) }
                    self.row(row.0, row.1)
                }
            }
            .paperCard(padding: 0)
        }
    }

    @ViewBuilder private func row(_ limit: AppLimit, _ state: ExtraTimeState) -> some View {
        let name = Text(limit.name).bold().foregroundColor(Ink.ink)
        Group {
            switch state {
            case .ready(let remaining):
                Button { onRequest(limit, remaining) } label: {
                    HStack {
                        name + Text(" · ") + Text(contactPending.contains(limit.id)
                            ? tr("Waiting for a trusted contact")
                            : String(format: tr("Get extra time (%d left)"), remaining))
                            .foregroundColor(accent)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ink.inkSoft)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            case .waiting(let until, _):
                HStack(spacing: DemoraSpace.xxs) {
                    name + Text(" · ") + Text(tr("Extra time in")).foregroundColor(Ink.inkSoft)
                    // `until` is a TimeGuard release, so CountdownText projects it.
                    CountdownText(to: until).foregroundStyle(Ink.ink)
                    Spacer(minLength: 0)
                }
            case .active:
                HStack {
                    name + Text(" · ") + Text(tr("Extra time running")).foregroundColor(accent)
                    Spacer(minLength: 0)
                }
            default:
                EmptyView()
            }
        }
        .demoraType(.meta)
        .padding(.horizontal, DemoraSpace.cardPadding)
        .frame(minHeight: 52)
    }
}

// MARK: - Check in

/// When & where rules a check-in could start now (free time, or a block
/// with a place or country), under extra time, in the same row style
/// (docs/conditional-sessions-redesign.md §5.3). The rows come
/// from `ConditionalAvailability.todayRows`; each opens the check-in sheet,
/// which decides for real.
struct CheckInRows: View {
    @AppAccent private var accent
    let rows: [ConditionalAvailability.Row]
    /// Rules left out by the three-row cap.
    let more: Int
    let onCheckIn: (UUID) -> Void
    let onAll: () -> Void

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.ruleID) { index, row in
                    if index > 0 { divider }
                    Button { onCheckIn(row.ruleID) } label: {
                        HStack {
                            // A block rule has no uses: its row only says what checking in does.
                            Text(row.name).bold().foregroundColor(Ink.ink)
                                + Text(" · ") + Text(row.startsBlock ? tr("starts a block")
                                                     : String(format: tr("%d left today"), row.left))
                                    .foregroundColor(Ink.inkSoft)
                                + Text(" · ") + Text(tr("Check in")).foregroundColor(accent)
                            Spacer(minLength: 0)
                            chevron
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .demoraType(.meta)
                    .padding(.horizontal, DemoraSpace.cardPadding)
                    .frame(minHeight: 52)
                    .accessibilityHint(tr("Checks this rule's conditions"))
                }
                if more > 0 {
                    divider
                    Button(action: onAll) {
                        HStack {
                            Text(tr("All in Rules")).foregroundColor(accent)
                            Spacer(minLength: 0)
                            chevron
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .demoraType(.meta)
                    .padding(.horizontal, DemoraSpace.cardPadding)
                    .frame(minHeight: 52)
                }
            }
            .paperCard(padding: 0)
        }
    }

    private var divider: some View { Rectangle().fill(Ink.hairline).frame(height: 1) }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Ink.inkSoft)
            .accessibilityHidden(true)
    }
}

// MARK: - Day thread

/// Today's rules on a vertical thread, with "now" marked on the line.
struct DayThreadView: View {
    @AppAccent private var accent
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    let result: DayThread.Result
    let now: Date
    /// Opens the rule behind an item (its summary sheet).
    var onOpen: ((TodayItem) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(result.entries.enumerated()), id: \.offset) { index, entry in
                if index == result.nowIndex { nowMarker }
                row(entry, isLast: index == result.entries.count - 1 && result.nowIndex < result.entries.count)
            }
            if result.nowIndex == result.entries.count { nowMarker }
        }
        .paperCard()
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar
    }

    private func short(_ date: Date) -> String {
        TodayTimeText.short(date, now: now, calendar: calendar, locale: locale)
    }

    private var nowMarker: some View {
        HStack(spacing: DemoraSpace.xs) {
            Text(short(now))
                .font(.system(.subheadline, design: .serif).monospacedDigit())
                .foregroundStyle(accent)
            Rectangle().fill(accent).frame(height: 1)
        }
        .padding(.vertical, DemoraSpace.xxs)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func row(_ entry: DayThread.Entry, isLast: Bool) -> some View {
        let past = entry.phase == .past
        let time = Text(short(entry.item.start))
            .font(.system(.subheadline, design: .serif).monospacedDigit())
            .foregroundStyle(Ink.inkSoft)
        let item = VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
            Text(entry.item.name)
                .demoraType(.cardTitle)
                .foregroundStyle(past ? Ink.inkSoft : Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
            chip(entry)
        }
        let content = Group {
            if typeSize.isAccessibilitySize {
                // The time column moves above each item at the largest sizes.
                VStack(alignment: .leading, spacing: DemoraSpace.xxs) { time; item }
                    .padding(.vertical, DemoraSpace.xs)
            } else {
                HStack(alignment: .top, spacing: DemoraSpace.s) {
                    time.frame(minWidth: 52, alignment: .leading)
                    VStack(spacing: 0) {
                        Circle()
                            .stroke(past ? Ink.hairline : dotColor(entry), lineWidth: 1.5)
                            .frame(width: 9, height: 9)
                            .padding(.top, 5)
                        Rectangle().fill(Ink.hairline).frame(width: 1)
                    }
                    .frame(width: 12)
                    .accessibilityHidden(true)
                    item.padding(.bottom, DemoraSpace.s)
                    Spacer(minLength: 0)
                }
            }
        }
        if let onOpen {
            Button { onOpen(entry.item) } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(tr("Shows what this rule does"))
        } else {
            content.accessibilityElement(children: .combine)
        }
    }

    private func dotColor(_ entry: DayThread.Entry) -> Color {
        entry.item.kind == .free ? Ink.free : accent
    }

    private func range(_ item: TodayItem) -> String {
        "\(short(item.start))–\(short(item.end))"
    }

    @ViewBuilder private func chip(_ entry: DayThread.Entry) -> some View {
        let item = entry.item
        switch (item.kind, entry.phase) {
        case (.wake, _):
            StateChip(kind: .blocked, text: tr(item.needsTap ? "Wake-up tap needed" : "Wake-up wait"))
        case (.free, .now):
            StateChip(kind: .free, text: tr("Free"))
        case (.free, _):
            StateChip(kind: entry.phase == .past ? .neutral : .free,
                      text: "\(tr("Free")) · \(range(item))")
        case (_, .now):
            StateChip(kind: item.kind == .unblock ? .free : .blocked, text: tr("On now"))
        case (_, .upcoming):
            StateChip(kind: .upcoming, text: range(item))
        case (_, .past):
            StateChip(kind: .neutral, text: range(item))
        }
    }
}
