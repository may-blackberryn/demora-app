import SwiftUI
import WidgetKit

private struct DemoraEntry: TimelineEntry {
    let date: Date
    let snapshot: DemoraWidgetSnapshot?
    var isPlaceholder = false

    /// Synthetic gallery content only. Never read saved rules for previews.
    static func sample(at date: Date, placeholder: Bool = false) -> DemoraEntry {
        let snapshot = DemoraWidgetSnapshot(
            windows: [
                .init(title: "Evening block", kind: "Schedule",
                      startsAt: date.addingTimeInterval(-1800),
                      endsAt: date.addingTimeInterval(3600), priority: 100, style: "block"),
                .init(title: "Reading", kind: "Session",
                      startsAt: date.addingTimeInterval(7200),
                      endsAt: date.addingTimeInterval(10800), priority: 300, style: "block")
            ],
            pending: [.init(title: "Daily limit 30 → 60 min",
                            appliesAt: date.addingTimeInterval(11524), direction: "lenient")],
            savedAt: date, nowLabel: "Now", nextLabel: "Next",
            pendingLabel: "Changing soon", noTimedRuleLabel: "No timed rule active",
            noNextLabel: "Nothing coming up", noPendingLabel: "No changes waiting",
            copy: .init())
        return DemoraEntry(date: date, snapshot: snapshot, isPlaceholder: placeholder)
    }
}

private struct DemoraProvider: TimelineProvider {
    func placeholder(in context: Context) -> DemoraEntry {
        .sample(at: Date(), placeholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (DemoraEntry) -> Void) {
        if context.isPreview {
            completion(.sample(at: Date()))
        } else {
            completion(DemoraEntry(date: Date(), snapshot: DemoraWidgetSnapshot.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DemoraEntry>) -> Void) {
        let now = Date()
        let snapshot = DemoraWidgetSnapshot.load()
        let end = now.addingTimeInterval(48 * 3600)
        let transitions = snapshot?.transitionDates(after: now, through: end) ?? []
        let dates = [now] + Array(transitions.prefix(80)).map {
            $0.addingTimeInterval(1)
        }
        let entries = dates.map { DemoraEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries,
                            policy: .after(now.addingTimeInterval(12 * 3600))))
    }
}

private struct WidgetShell<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @ViewBuilder var content: Content

    private var isAccessory: Bool {
        family == .accessoryInline || family == .accessoryRectangular
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            // WidgetKit supplies margins; do not double them with padding.
            surface.containerBackground(for: .widget) {
                if !isAccessory { WidgetInk.card }
            }
        } else if isAccessory {
            surface
        } else {
            surface.padding(16).background(WidgetInk.card)
        }
    }

    private var surface: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(WidgetInk.ink)
            .multilineTextAlignment(.leading)
    }
}

private struct WidgetMark: View {
    var body: some View {
        // Approved fallback: no host-bundle asset dependency.
        Image(systemName: "hourglass")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(WidgetInk.inkSoft)
            .accessibilityHidden(true)
    }
}

private struct WidgetHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .widgetType(.label)
            .foregroundStyle(WidgetInk.inkSoft)
            .lineLimit(2)
    }
}

private struct DirectionChip: View {
    let direction: String?
    let copy: DemoraWidgetSnapshot.Copy
    let accent: String

    var body: some View {
        if direction == "lenient" {
            chip(copy.looser, pair: WidgetInk.loosenPair(for: accent))
        } else if direction == "stricter" {
            chip(copy.stricter, pair: WidgetInk.accentPair(for: accent))
        }
        // Legacy nil and unknown directions intentionally have no chip.
    }

    private func chip(_ label: String, pair: WidgetInkPair) -> some View {
        Text(label)
            .widgetType(.chip)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(WidgetTheme.color(pair))
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .background(WidgetTheme.tint(pair), in: Capsule())
            .widgetAccentable()
    }
}

private struct PendingCountdown: View {
    let date: Date
    let pending: DemoraWidgetSnapshot.Pending
    var large = false

    var body: some View {
        // Never construct an inverted/non-finite interval. The system timer
        // stops at zero; only the host applies a change.
        if date.timeIntervalSinceReferenceDate.isFinite,
           pending.appliesAt.timeIntervalSinceReferenceDate.isFinite,
           pending.appliesAt > date {
            Text(timerInterval: date...pending.appliesAt, countsDown: true)
                .widgetType(large ? .timeLarge : .time)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .fixedSize(horizontal: false, vertical: true)
                .widgetAccentable()
        }
    }
}

private struct PendingLanding: View {
    let date: Date

    var body: some View {
        Text(date, format: .dateTime.weekday(.abbreviated).hour().minute())
            .widgetType(.meta)
            .foregroundStyle(WidgetInk.inkSoft)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct NowNextView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.locale) private var locale
    let entry: DemoraEntry

    private var copy: DemoraWidgetSnapshot.Copy {
        WidgetPresentation.copy(snapshot: entry.snapshot)
    }
    private var current: WidgetPresentation.Current {
        WidgetPresentation.current(snapshot: entry.snapshot, at: entry.date)
    }

    var body: some View {
        WidgetShell {
            switch family {
            case .accessoryInline:
                inline
            case .accessoryRectangular:
                currentBlock(accessory: true)
            case .systemMedium:
                HStack(alignment: .top, spacing: 16) {
                    homeCurrent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    Rectangle().fill(WidgetInk.hairline).frame(width: 1)
                        .accessibilityHidden(true)
                    PendingBlock(entry: entry, compact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            default:
                homeCurrent
            }
        }
        .widgetURL(WidgetDestination.today.url)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    private var homeCurrent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                WidgetHeading(text: entry.snapshot?.nowLabel ?? "Now")
                Spacer(minLength: 0)
                WidgetMark()
            }
            currentBlock(accessory: false)
            Spacer(minLength: 0)
            if let next = entry.snapshot?.next(at: entry.date) {
                Rectangle().fill(WidgetInk.hairline).frame(height: 1)
                    .accessibilityHidden(true)
                Text(nextSentence(next))
                    .widgetType(.meta)
                    .foregroundStyle(WidgetInk.inkSoft)
                    .lineLimit(1)
                    .accessibilityElement(children: .combine)
                    .privacySensitive()
            }
        }
    }

    private func currentBlock(accessory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch current {
            case .unpublished:
                Text(copy.openDemora).widgetType(.cardTitle).lineLimit(2)
            case .wake:
                // Future-ready schema only: live wake publication is deferred
                // pending approval of the engine read-boundary design.
                Text(copy.wakeDue).widgetType(.cardTitle).lineLimit(accessory ? 3 : 4)
            case .empty:
                Text(copy.nothingBlocked).widgetType(.cardTitle).lineLimit(2)
            case .rule(let window):
                Text(window.title)
                    .widgetType(.cardTitle)
                    .lineLimit(2)
                    .privacySensitive()
                Text(window.style == "spent" ? copy.usedUp : until(window.endsAt))
                    .font(accessory
                          ? .system(.subheadline, design: .serif).monospacedDigit()
                          : WidgetType.time.font)
                    .foregroundStyle(window.style == "free" ? WidgetInk.sage
                        : WidgetTheme.color(WidgetInk.loosenPair(for: WidgetTheme.accentValue())))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .widgetAccentable()
            }
        }
        .accessibilityElement(children: .combine)
        // Includes the rule name in the combined VoiceOver element.
        .privacySensitive()
    }

    private var inline: some View {
        Group {
            switch current {
            case .unpublished: Text(copy.openDemora)
            case .wake: Text(copy.wakeDue)
            case .empty: Text(copy.nothingBlocked)
            case .rule(let window):
                Text(window.title + " " + (window.style == "spent" ? copy.usedUp : until(window.endsAt)))
            }
        }
        .font(.system(.caption, design: .default))
        .accessibilityElement(children: .combine)
        .privacySensitive()
    }

    private func until(_ date: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        return String(format: copy.untilFormat, locale: locale, time)
    }

    private func nextSentence(_ next: (String, Date)) -> String {
        let time = next.1.formatted(.dateTime.hour().minute().locale(locale))
        return String(format: copy.nextFormat, locale: locale, time, next.0)
    }
}

/// Standalone pending widget and the right-hand medium Now & next column.
private struct PendingBlock: View {
    let entry: DemoraEntry
    var compact = false

    private var copy: DemoraWidgetSnapshot.Copy {
        WidgetPresentation.copy(snapshot: entry.snapshot)
    }

    var body: some View {
        let pending = entry.snapshot?.nextPending(at: entry.date)
        VStack(alignment: .leading, spacing: 6) {
            if compact {
                WidgetHeading(text: entry.snapshot?.pendingLabel ?? "Changing soon")
            } else {
                HStack(alignment: .top, spacing: 4) {
                    WidgetHeading(text: entry.snapshot?.pendingLabel ?? "Changing soon")
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    DirectionChip(direction: pending?.direction, copy: copy,
                                  accent: WidgetTheme.accentValue())
                }
            }
            if let pending {
                Text(pending.title)
                    .widgetType(.cardTitle)
                    .lineLimit(compact ? 1 : 2)
                    .privacySensitive()
                Spacer(minLength: 0)
                if !compact {
                    PendingCountdown(date: entry.date, pending: pending, large: true)
                }
                PendingLanding(date: pending.appliesAt)
            } else {
                Text(entry.snapshot == nil ? copy.openDemora
                     : entry.snapshot?.noPendingLabel ?? "No changes waiting")
                    .widgetType(.cardTitle)
                    .lineLimit(2)
                if entry.snapshot != nil {
                    Text(copy.changesWaitHere)
                        .widgetType(.meta)
                        .foregroundStyle(WidgetInk.inkSoft)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .privacySensitive()
    }
}

private struct PendingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DemoraEntry

    private var copy: DemoraWidgetSnapshot.Copy {
        WidgetPresentation.copy(snapshot: entry.snapshot)
    }

    var body: some View {
        WidgetShell {
            switch family {
            case .accessoryInline:
                inline
            case .accessoryRectangular:
                rectangular
            default:
                PendingBlock(entry: entry)
            }
        }
        .widgetURL(WidgetDestination.changes.url)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    private var inline: some View {
        Group {
            if let pending = entry.snapshot?.nextPending(at: entry.date) {
                Text(pending.title) + Text(" · ") + Text(pending.appliesAt, style: .time)
            } else {
                Text(entry.snapshot == nil ? copy.openDemora
                     : entry.snapshot?.noPendingLabel ?? "No changes waiting")
            }
        }
        .font(.system(.caption, design: .default))
        .accessibilityElement(children: .combine)
        .privacySensitive()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let pending = entry.snapshot?.nextPending(at: entry.date) {
                Text(pending.title)
                    .widgetType(.cardTitle)
                    .lineLimit(2)
                    .privacySensitive()
                PendingCountdown(date: entry.date, pending: pending)
            } else {
                Text(entry.snapshot == nil ? copy.openDemora
                     : entry.snapshot?.noPendingLabel ?? "No changes waiting")
                    .widgetType(.cardTitle)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .privacySensitive()
    }
}

private struct NowNextWidget: Widget {
    let kind = "demora.now-next"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DemoraProvider()) { entry in
            NowNextView(entry: entry)
        }
        .configurationDisplayName("Now & next")
        .description("See what's on now and what's next.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular])
    }
}

private struct PendingChangeWidget: Widget {
    let kind = "demora.pending-change"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DemoraProvider()) { entry in
            PendingView(entry: entry)
        }
        .configurationDisplayName("Changing soon")
        .description("Your next change and when it lands.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular])
    }
}

@main
struct DemoraWidgets: WidgetBundle {
    var body: some Widget {
        NowNextWidget()
        PendingChangeWidget()
    }
}
