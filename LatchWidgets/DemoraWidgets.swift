import SwiftUI
import WidgetKit

private struct DemoraEntry: TimelineEntry {
    let date: Date
    let snapshot: DemoraWidgetSnapshot?
}

private struct DemoraProvider: TimelineProvider {
    func placeholder(in context: Context) -> DemoraEntry {
        DemoraEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (DemoraEntry) -> Void) {
        completion(DemoraEntry(date: Date(), snapshot: DemoraWidgetSnapshot.load()))
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
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(15)
            .background(Color(red: 0.07, green: 0.12, blue: 0.19))
            .foregroundStyle(.white)
    }
}

private struct NowNextView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DemoraEntry

    var body: some View {
        let snapshot = entry.snapshot
        let active = snapshot?.active(at: entry.date)
        let next = snapshot?.next(at: entry.date)
        WidgetShell {
            VStack(alignment: .leading, spacing: 6) {
                Label("demora", systemImage: "hourglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.71, green: 0.87, blue: 1))
                Text(snapshot?.nowLabel ?? "Now")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(active?.title ?? snapshot?.noTimedRuleLabel ?? "Open Demora")
                    .font(.headline)
                    .lineLimit(2)
                if let active {
                    Text(active.kind).font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 2)
                if family == .systemMedium {
                    Text(snapshot?.nextLabel ?? "Next")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                    HStack(spacing: 5) {
                        Text(next?.0 ?? snapshot?.noNextLabel ?? "Nothing coming up")
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let date = next?.1 {
                            Text(date, style: .time).fixedSize()
                        }
                    }
                    .font(.caption)
                } else if let date = next?.1 {
                    Text(date, style: .time)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
    }
}

private struct PendingView: View {
    let entry: DemoraEntry

    var body: some View {
        let snapshot = entry.snapshot
        let pending = snapshot?.nextPending(at: entry.date)
        WidgetShell {
            VStack(alignment: .leading, spacing: 7) {
                Label("demora", systemImage: "hourglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.71, green: 0.87, blue: 1))
                Text(snapshot?.pendingLabel ?? "Pending change")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(pending?.title ?? snapshot?.noPendingLabel ?? "Open Demora")
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 2)
                if let pending, pending.appliesAt > entry.date {
                    Text(timerInterval: entry.date...pending.appliesAt, countsDown: true)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct NowNextWidget: Widget {
    let kind = "demora.now-next"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DemoraProvider()) { entry in
            NowNextView(entry: entry)
        }
        .configurationDisplayName("Demora: Now & Next")
        .description("See your current timed rule and what changes next.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct PendingChangeWidget: Widget {
    let kind = "demora.pending-change"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DemoraProvider()) { entry in
            PendingView(entry: entry)
        }
        .configurationDisplayName("Demora: Pending Change")
        .description("Keep an eye on your next pending change.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct DemoraWidgets: WidgetBundle {
    var body: some Widget {
        NowNextWidget()
        PendingChangeWidget()
    }
}
