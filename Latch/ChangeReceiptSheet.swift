//
//  ChangeReceiptSheet.swift
//  The receipt every editor shows before a change is queued
//  (docs/today-redesign.md §5.10): what changes, when it takes effect and how
//  long it waits. Looser changes and removals hold to confirm; stricter ones
//  confirm with one tap. Nothing is queued until the person confirms.
//

import SwiftUI

/// A change waiting for its receipt. Identifiable so it can drive a sheet.
struct ChangeReceiptRequest: Identifiable {
    let id = UUID()
    let action: ChangeAction
    /// One more line under "Takes effect", e.g. "Then runs for 60 min."
    var note: String? = nil
    /// Checked again just before queueing (the day & night editor re-runs its
    /// collection guards); false keeps the receipt open with a notice.
    var canQueue: (() -> Bool)? = nil
}

extension View {
    /// Shows the receipt for `request`. `onQueued` runs after the receipt has
    /// closed on a successful queue, so an editor can then close itself.
    func changeReceipt(_ request: Binding<ChangeReceiptRequest?>,
                       onQueued: @escaping () -> Void = {}) -> some View {
        modifier(ChangeReceiptPresenter(request: request, onQueued: onQueued))
    }
}

private struct ChangeReceiptPresenter: ViewModifier {
    @Binding var request: ChangeReceiptRequest?
    let onQueued: () -> Void
    @State private var queued = false

    func body(content: Content) -> some View {
        content.sheet(item: $request, onDismiss: {
            if queued { queued = false; onQueued() }
        }) { request in
            ChangeReceiptSheet(action: request.action, note: request.note,
                               canQueue: request.canQueue) { queued = true }
        }
    }
}

struct ChangeReceiptSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @AppLoosen private var loosen
    let action: ChangeAction
    var note: String? = nil
    var canQueue: (() -> Bool)? = nil
    let onQueued: () -> Void
    @State private var notice: String?

    var body: some View {
        // The preview follows the current clock while the sheet is open; the
        // queued change keeps its own stored deadline.
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
        .background(Ink.cardRaised.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func content(now: Date) -> some View {
        let (direction, delay) = model.preview(action)
        let plan = ReceiptPlan.make(looser: direction == .lenient, delay: delay, now: now)
        var calendar = Calendar.current
        calendar.locale = locale
        return ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.m) {
                StateChip(kind: plan.looser ? .loosening : .active,
                          text: tr(plan.looser ? "Looser change" : "Stricter change"))
                Text(ChangeEngine.summary(for: action, state: model.state))
                    .demoraType(.hero)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Line()
                    .stroke(Ink.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(height: 1)
                    .accessibilityHidden(true)
                VStack(spacing: DemoraSpace.xs) {
                    row(tr("Takes effect"), plan.takesEffect.map {
                        TodayTimeText.short($0, now: now, calendar: calendar, locale: locale)
                    } ?? tr("Right away"))
                    if let wait = plan.wait {
                        row(tr("Wait"), ReceiptPlan.waitText(wait, locale: locale))
                    }
                }
                if let note {
                    Text(note)
                        .demoraType(.meta)
                        .foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if plan.wait != nil {
                    Text(tr("Until then nothing changes. You can cancel it from Today."))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let notice {
                    Text(notice)
                        .demoraType(.meta)
                        .foregroundStyle(loosen)
                        .fixedSize(horizontal: false, vertical: true)
                }
                switch plan.commit {
                case .hold:
                    HoldButton(tr("Hold to confirm"), role: .loosen,
                               confirmationTitle: tr("Confirm looser change?")) { commit() }
                case .confirm:
                    Button(tr("Confirm")) { commit() }
                        .buttonStyle(DemoraPrimaryButtonStyle())
                }
                Button(tr("Keep editing")) { dismiss() }
                    .buttonStyle(.plain)
                    .font(DemoraType.button)
                    .foregroundStyle(Ink.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .padding(DemoraSpace.xl)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DemoraSpace.s) {
            Text(title).demoraType(.meta).foregroundStyle(Ink.inkSoft)
            Spacer(minLength: DemoraSpace.s)
            Text(value)
                .demoraType(.time)
                .foregroundStyle(Ink.ink)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// Queues through the normal change engine. A refusal (already pending,
    /// monitoring capacity) stays on the receipt instead of the app-wide alert.
    private func commit() {
        if let canQueue, !canQueue() {
            notice = tr("This change could not be saved. Review it and try again.")
            return
        }
        if model.queue(action) != nil {
            onQueued()
            dismiss()
        } else {
            notice = model.queueNotice
                ?? tr("A change for this setting is already pending. Cancel it in Changes first if you want something different.")
            model.queueNotice = nil
            model.queueNoticeIsCapacity = false
        }
    }
}

// MARK: - Receipt as a pushed step, for one or several actions

/// Several actions confirmed together, e.g. "add Alex" and "turn on contact
/// approvals" (docs/you-redesign.md §7 extension b). Identifiable so it can
/// drive a sheet.
struct ChangeReceiptBatchRequest: Identifiable {
    let id = UUID()
    let actions: [ChangeAction]
    /// Extra lines under the summary ("Also turns on contact approvals").
    var lines: [String] = []
    var note: String? = nil
}

extension View {
    /// The batch receipt in its own sheet (used where no sheet is open yet).
    func changeReceiptBatch(_ request: Binding<ChangeReceiptBatchRequest?>,
                            onQueued: @escaping () -> Void = {}) -> some View {
        modifier(ChangeReceiptBatchPresenter(request: request, onQueued: onQueued))
    }
}

private struct ChangeReceiptBatchPresenter: ViewModifier {
    @Binding var request: ChangeReceiptBatchRequest?
    let onQueued: () -> Void
    @State private var queued = false

    func body(content: Content) -> some View {
        content.sheet(item: $request, onDismiss: {
            if queued { queued = false; onQueued() }
        }) { request in
            ChangeReceiptBatchSheet(request: request) { queued = true }
        }
    }
}

private struct ChangeReceiptBatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: ChangeReceiptBatchRequest
    let onQueued: () -> Void

    var body: some View {
        ChangeReceiptView(actions: request.actions, lines: request.lines, note: request.note,
                          onQueued: { onQueued(); dismiss() }, onBack: { dismiss() })
            .background(Ink.cardRaised.ignoresSafeArea())
            .presentationDetents([.medium, .large])
    }
}

/// The receipt's content without its own sheet, so a flow that is already
/// in a sheet can push it as its last step (no sheet on a sheet). Same
/// rules as ChangeReceiptSheet: direction and delay from `model.preview`,
/// looser holds to confirm, stricter confirms with one tap, nothing is
/// queued until then, and a refusal stays here.
struct ChangeReceiptView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.locale) private var locale
    @AppLoosen private var loosen
    let actions: [ChangeAction]
    var lines: [String] = []
    var note: String? = nil
    /// Runs once every action is queued.
    let onQueued: () -> Void
    /// "Keep editing": back to the step before.
    let onBack: () -> Void
    @State private var notice: String?
    /// Actions already queued, so a retry after a partial refusal never
    /// queues one twice.
    @State private var queuedCount = 0

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let parts = actions.map { action -> (looser: Bool, delay: TimeInterval) in
            let (direction, delay) = model.preview(action)
            return (direction == .lenient, delay)
        }
        let plan = ReceiptBatch.plan(parts, now: now)
        var calendar = Calendar.current
        calendar.locale = locale
        return ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.m) {
                StateChip(kind: plan.looser ? .loosening : .active,
                          text: tr(plan.looser ? "Looser change" : "Stricter change"))
                if let first = actions.first {
                    Text(ChangeEngine.summary(for: first, state: model.state))
                        .demoraType(.hero)
                        .foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(lines, id: \.self) { line in
                    Label(line, systemImage: "plus")
                        .demoraType(.meta)
                        .foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Line()
                    .stroke(Ink.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(height: 1)
                    .accessibilityHidden(true)
                VStack(spacing: DemoraSpace.xs) {
                    row(tr("Takes effect"), plan.takesEffect.map {
                        TodayTimeText.short($0, now: now, calendar: calendar, locale: locale)
                    } ?? tr("Right away"))
                    if let wait = plan.wait {
                        row(tr("Wait"), ReceiptPlan.waitText(wait, locale: locale))
                    }
                }
                if let note {
                    Text(note)
                        .demoraType(.meta)
                        .foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if plan.wait != nil {
                    Text(tr("Until then nothing changes. You can cancel it from Today."))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let notice {
                    Text(notice)
                        .demoraType(.meta)
                        .foregroundStyle(loosen)
                        .fixedSize(horizontal: false, vertical: true)
                }
                switch plan.commit {
                case .hold:
                    HoldButton(tr("Hold to confirm"), role: .loosen,
                               confirmationTitle: tr("Confirm looser change?")) { commit() }
                case .confirm:
                    Button(tr("Confirm")) { commit() }
                        .buttonStyle(DemoraPrimaryButtonStyle())
                }
                Button(tr("Keep editing"), action: onBack)
                    .buttonStyle(.plain)
                    .font(DemoraType.button)
                    .foregroundStyle(Ink.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .padding(DemoraSpace.xl)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DemoraSpace.s) {
            Text(title).demoraType(.meta).foregroundStyle(Ink.inkSoft)
            Spacer(minLength: DemoraSpace.s)
            Text(value)
                .demoraType(.time)
                .foregroundStyle(Ink.ink)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// Queues each action through the normal change engine, in order. A
    /// refusal stops there and stays on the receipt; actions already queued
    /// stay queued (they show in Changes, where they can be cancelled).
    private func commit() {
        while queuedCount < actions.count {
            guard model.queue(actions[queuedCount]) != nil else {
                notice = (queuedCount > 0
                          ? tr("Part of this was saved and is waiting in Changes. The rest couldn't be saved.") + " "
                          : "")
                    + (model.queueNotice
                       ?? tr("A change for this setting is already pending. Cancel it in Changes first if you want something different."))
                model.queueNotice = nil
                model.queueNoticeIsCapacity = false
                return
            }
            queuedCount += 1
        }
        onQueued()
    }
}

/// A horizontal line for a dashed divider.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
