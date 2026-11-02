//
//  DemoraComponents.swift
//  The shared pieces from docs/foundations-redesign.md §6: paper cards,
//  section headers, state chips, countdowns, the hold-to-confirm button and
//  day chips. Screens adopt them one by one as their specs are built.
//

import SwiftUI
import UIKit

// MARK: - Ink roles

/// Which family of ink a component speaks in. Resolved against the accent the
/// user picked, so "blocked" turns ochre when the accent itself is red.
enum InkRole {
    case accent, loosen, free

    func pair(accent value: String) -> InkPair {
        switch self {
        case .accent: return Ink.accentPair(for: value)
        case .loosen: return Ink.loosenPair(for: value)
        case .free:   return InkPalette.free
        }
    }
}

// MARK: - Paper card

extension View {
    /// A soft card on paper: `card` fill, hairline border, continuous corners,
    /// no shadow. Replaces `demoraSurface()` call by call.
    func paperCard(padding: CGFloat = DemoraSpace.cardPadding,
                   fill: Color = Ink.card) -> some View {
        let shape = RoundedRectangle(cornerRadius: DemoraRadius.card, style: .continuous)
        return self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(Ink.hairline, lineWidth: 1))
    }
}

// MARK: - Section header

/// A quiet section label with an optional trailing link. Replaces
/// `DemoraSectionTitle` as screens move over.
struct SectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DemoraSpace.s) {
            Text(title)
                .demoraType(.label)
                .foregroundStyle(Ink.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// The trailing link most headers use ("See all", "Edit").
struct SectionHeaderLink: View {
    @AppAccent private var accent
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .demoraType(.meta)
            .foregroundStyle(accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - State chip

/// A small, non-interactive label for a rule's or change's state.
struct StateChip: View {
    enum Kind { case active, blocked, loosening, free, upcoming, neutral }

    @Environment(\.demoraAccentColor) private var accentValue
    let kind: Kind
    let text: String
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 24

    private var role: InkRole? {
        switch kind {
        case .active: return .accent
        case .blocked, .loosening: return .loosen
        case .free: return .free
        case .upcoming, .neutral: return nil
        }
    }

    private var symbol: String? {
        switch kind {
        case .active, .blocked, .free: return "circle.fill"
        case .loosening: return "arrow.down.right"
        case .upcoming: return "clock"
        case .neutral: return nil
        }
    }

    var body: some View {
        let pair = role?.pair(accent: accentValue)
        let ink = pair.map(Ink.color) ?? Ink.inkSoft
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: symbol == "circle.fill" ? 6 : 10, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .demoraType(.chip)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 10)
        .frame(minHeight: height)
        .background {
            if let pair {
                Capsule().fill(Ink.tint(pair))
            } else {
                Capsule().strokeBorder(Ink.hairline, lineWidth: 1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Countdowns

/// Pure projection of a TimeGuard deadline onto the system clock.
/// `appliesAt` is anchored to TimeGuard's tamper-resistant clock, but
/// `Text(timerInterval:)` ticks on the system clock. Projecting the guarded
/// remaining time onto the system clock keeps the countdown right — and stops
/// it flickering at ~1 s — even when the two clocks disagree (after sleep).
enum CountdownProjection {
    /// Seconds still to wait on the guarded clock, never below one second, so
    /// a change that isn't due yet never reads 0:00.
    static func remaining(until deadline: Date, guardedNow: Date) -> TimeInterval {
        max(1, deadline.timeIntervalSince(guardedNow))
    }

    static func interval(until deadline: Date, guardedNow: Date,
                         systemNow: Date) -> ClosedRange<Date> {
        systemNow...systemNow.addingTimeInterval(
            remaining(until: deadline, guardedNow: guardedNow))
    }

    /// Share of the wait already elapsed, 0...1. A zero-length or inverted
    /// wait counts as complete.
    static func progress(from start: Date, until deadline: Date,
                         guardedNow: Date) -> Double {
        let total = deadline.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, guardedNow.timeIntervalSince(start) / total))
    }
}

/// A live countdown to a TimeGuard deadline. The caller decides what shows
/// once the deadline is due (for example "Applying…"); until then this ticks
/// down and holds at 0:01 rather than looping.
struct CountdownText: View {
    let deadline: Date
    /// `nil` leaves the font to the caller.
    var style: DemoraType? = .time

    init(to deadline: Date, style: DemoraType? = .time) {
        self.deadline = deadline
        self.style = style
    }

    var body: some View {
        let text = Text(timerInterval: CountdownProjection.interval(
            until: deadline, guardedNow: TimeGuard.now(), systemNow: Date.now),
                        countsDown: true)
        if let style {
            text.demoraType(style)
        } else {
            text
        }
    }
}

/// A 28 pt ring that fills as the wait elapses, with the countdown beside it.
struct CountdownRing: View {
    let start: Date
    let deadline: Date
    var role: InkRole = .accent
    @Environment(\.demoraAccentColor) private var accentValue
    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = 28

    init(from start: Date, to deadline: Date, role: InkRole = .accent) {
        self.start = start
        self.deadline = deadline
        self.role = role
    }

    var body: some View {
        let ink = Ink.color(role.pair(accent: accentValue))
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let guardedNow = TimeGuard.now()
            HStack(spacing: DemoraSpace.xs) {
                ZStack {
                    Circle().stroke(Ink.hairline, lineWidth: 3)
                    Circle().trim(from: 0, to: CountdownProjection.progress(
                        from: start, until: deadline, guardedNow: guardedNow))
                        .stroke(ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: size, height: size)
                .accessibilityHidden(true)
                if guardedNow >= deadline {
                    Text(tr("Applying…")).demoraType(.meta).foregroundStyle(Ink.inkSoft)
                } else {
                    CountdownText(to: deadline).foregroundStyle(Ink.ink)
                }
            }
        }
    }
}

// MARK: - Buttons

/// The one primary action on a screen: a full-width accent capsule.
struct DemoraPrimaryButtonStyle: ButtonStyle {
    @AppAccent private var accent
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DemoraType.button)
            .foregroundStyle(Ink.paper)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DemoraSpace.l)
            .padding(.vertical, DemoraSpace.s)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(accent, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.48)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15),
                       value: configuration.isPressed)
    }
}

/// Hold to confirm a deliberate change (looser edits, removals). The fill runs
/// left to right over `duration`; letting go early cancels. With VoiceOver or
/// Reduce Motion on it becomes a plain button that asks for one confirmation.
struct HoldButton: View {
    let title: String
    var role: InkRole = .loosen
    var duration: TimeInterval = 1.2
    /// The question asked instead of a hold, e.g. "Confirm looser change?"
    let confirmationTitle: String
    let action: () -> Void

    @Environment(\.demoraAccentColor) private var accentValue
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var progress: CGFloat = 0
    @State private var completed = false
    @State private var confirming = false

    init(_ title: String, role: InkRole = .loosen, duration: TimeInterval = 1.2,
         confirmationTitle: String, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.duration = duration
        self.confirmationTitle = confirmationTitle
        self.action = action
    }

    var body: some View {
        let pair = role.pair(accent: accentValue)
        Group {
            if voiceOver || reduceMotion {
                Button { confirming = true } label: {
                    label(Ink.paper).frame(maxWidth: .infinity, minHeight: 54)
                        .background(Ink.color(pair), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                holdBody(pair)
            }
        }
        .opacity(isEnabled ? 1 : 0.48)
        .alert(confirmationTitle, isPresented: $confirming) {
            Button(tr("Confirm")) { action() }
            Button(tr("Cancel"), role: .cancel) {}
        }
    }

    private func label(_ color: Color) -> some View {
        Text(title)
            .font(DemoraType.button)
            .foregroundStyle(color)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DemoraSpace.l)
    }

    private func holdBody(_ pair: InkPair) -> some View {
        ZStack {
            Capsule().fill(Ink.tint(pair))
            label(Ink.color(pair))
            ZStack {
                Capsule().fill(Ink.color(pair))
                label(Ink.paper)
            }
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().frame(width: geo.size.width * progress)
                }
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 40) {
            completed = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            action()
            progress = 0
        } onPressingChanged: { pressing in
            if pressing {
                completed = false
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.linear(duration: duration)) { progress = 1 }
            } else if !completed {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        // Switch Control and Voice Control can't hold; they get the question.
        .accessibilityAction { confirming = true }
    }
}

// MARK: - Day chips

/// Seven round day toggles in the user's calendar order. Days use Calendar
/// weekday numbers (1 = Sunday … 7 = Saturday), as the saved rules do.
struct DayChips: View {
    @AppAccent private var accent
    @Binding var selection: Set<Int>
    /// Rules need at least one day, so by default the last day can't be cleared.
    var allowsEmpty = false

    private var orderedDays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        let calendar = Calendar.current
        HStack(spacing: DemoraSpace.xxs) {
            ForEach(orderedDays, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn {
                        guard allowsEmpty || selection.count > 1 else { return }
                        selection.remove(day)
                    } else {
                        selection.insert(day)
                    }
                } label: {
                    // A circle inscribes itself in the cell: 44 pt where there's
                    // room, the cell's width on the narrowest phones.
                    Text(calendar.veryShortWeekdaySymbols[day - 1])
                        .font(.system(.subheadline, design: .default).weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(isOn ? Ink.paper : Ink.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if isOn {
                                Circle().fill(accent)
                            } else {
                                Circle().fill(Ink.card)
                                    .overlay(Circle().strokeBorder(Ink.hairline, lineWidth: 1))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[day - 1])
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Empty state

/// iOS 16-compatible stand-in for ContentUnavailableView (iOS 17+), drawn as
/// a paper card with at most one action.
struct EmptyStateView: View {
    @AppAccent private var accent
    let title: String
    let systemImage: String
    let description: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            VStack(alignment: .leading, spacing: DemoraSpace.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(title)
                    .demoraType(.cardTitle)
                    .foregroundStyle(Ink.ink)
                Text(description)
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(DemoraType.button)
                    .foregroundStyle(accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
        .paperCard()
    }
}
