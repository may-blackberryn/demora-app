//
//  ChangesLedgerView.swift
//  The Changes ledger pushed from Today, and the row both share
//  (docs/today-redesign.md §5.9): every pending change grouped by when it
//  lands, with its countdown, Cancel and, when an override exists, Apply now.
//

import SwiftUI

/// A sent contact request a pending change is waiting on.
struct ChangeWaiting: Equatable {
    let requestID: String
    /// The asked contacts' names, or nil when they can't be named.
    let names: String?
    let email: Bool

    /// The sent request covering `change`, named from the saved contacts.
    static func find(for change: PendingChange,
                     in requests: [ContactsRelay.OutgoingRequest],
                     contacts: [TrustedContact]) -> ChangeWaiting? {
        guard let request = requests.first(where: { $0.changeIds.contains(change.id) })
        else { return nil }
        let ids = (request.relayContactIDs ?? []) + (request.emailContactIDs ?? [])
        var names: [String] = []
        for id in ids {
            let name = contacts.first { $0.id == id }?.name
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !name.isEmpty && !names.contains(name) { names.append(name) }
        }
        return ChangeWaiting(requestID: request.requestId,
                             names: names.isEmpty ? nil : names.joined(separator: ", "),
                             email: request.email)
    }
}

/// One pending change. Takes the same inputs as the legacy PendingChangeRow,
/// plus the contact request it may be waiting on.
struct ChangeRow: View {
    @AppAccent private var accent
    @AppLoosen private var loosen
    @Environment(\.locale) private var locale
    let change: PendingChange
    let canOverride: Bool
    /// When set (tutorial), the countdown ticks toward a floor and can't be
    /// waited out; the actions are hidden.
    var frozenRemaining: (() -> TimeInterval)? = nil
    /// Reports the row's frame to the tutorial blocker so it stays tappable.
    var reportHole: Bool = false
    var waiting: ChangeWaiting? = nil
    let onCancel: () -> Void
    let onOverride: () -> Void
    let onDebugApply: () -> Void
    var onOpenRequest: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            HStack(alignment: .center, spacing: DemoraSpace.xs) {
                StateChip(kind: change.direction == .stricter ? .active : .loosening,
                          text: tr(change.direction == .stricter ? "Stricter" : "Looser"))
                Spacer(minLength: DemoraSpace.xs)
                if let frozenRemaining {
                    TutorialCountdownText(remaining: frozenRemaining)
                        .demoraType(.time)
                } else if change.isDue {
                    Text(tr("Applying…")).demoraType(.meta).foregroundStyle(Ink.inkSoft)
                } else {
                    // CountdownText projects the TimeGuard deadline onto the
                    // system clock (see CountdownProjection).
                    CountdownText(to: change.appliesAt)
                        .foregroundStyle(Ink.ink)
                        .layoutPriority(1)
                }
            }
            Text(change.summary)
                .demoraType(.cardTitle)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let waiting {
                Button(action: onOpenRequest) {
                    HStack(alignment: .firstTextBaseline, spacing: DemoraSpace.xs) {
                        Image(systemName: waiting.email ? "envelope.badge" : "hourglass")
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(waiting.names.map { String(format: tr("Waiting for %@"), $0) }
                                 ?? tr("Waiting for approval…"))
                                .foregroundStyle(Ink.ink)
                            if waiting.email || waiting.names != nil {
                                Text(tr(waiting.email ? "Tap to enter the email code"
                                                      : "Waiting for approval…"))
                                    .foregroundStyle(Ink.inkSoft)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .demoraType(.meta)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DemoraSpace.m) {
                    landing
                    Spacer(minLength: DemoraSpace.xs)
                    actions
                }
                VStack(alignment: .leading, spacing: 0) {
                    landing
                    HStack(spacing: DemoraSpace.m) { actions }
                }
            }
        }
        .paperCard()
        .tutorialHighlight(reportHole, ring: false)
    }

    /// The stored landing time, "Tue 14:32" (the countdown above is the
    /// tamper-aware projection).
    private var landing: some View {
        var calendar = Calendar.current
        calendar.locale = locale
        return Text(TodayTimeText.short(change.appliesAt, now: Date(),
                                        calendar: calendar, locale: locale))
            .demoraType(.meta)
            .foregroundStyle(Ink.inkSoft)
    }

    // During the tutorial the row has no buttons — applying is done by
    // Select → Apply, which is what the tour teaches.
    @ViewBuilder private var actions: some View {
        if frozenRemaining == nil {
            Button(tr("Cancel"), action: onCancel)
                .buttonStyle(.plain)
                .demoraType(.meta)
                .foregroundStyle(loosen)
                .frame(minHeight: 44)
            if canOverride && !change.isDue {
                Button(tr("Apply now…"), action: onOverride)
                    .buttonStyle(.plain)
                    .demoraType(.meta)
                    .foregroundStyle(accent)
                    .frame(minHeight: 44)
            }
#if DEBUG
            if !change.isDue {
                Button("Skip delay (dev)", action: onDebugApply)
                    .buttonStyle(.bordered).controlSize(.small)
                    .tint(.purple)
            }
#endif
        }
    }
}

/// Every pending change, grouped by when it lands. Select keeps the bulk
/// Cancel N / Apply N now bar; bulk cancel asks once.
struct ChangesLedgerView: View {
    @AppAccent private var accent
    @EnvironmentObject private var model: AppModel
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Sent contact requests Today already loads.
    let outgoing: [ContactsRelay.OutgoingRequest]
    /// Reloads `outgoing` after a contact sheet closes.
    let onRequestsChanged: () -> Void
    /// A change to bring into view when the ledger opens (from a rule's
    /// pending line or summary sheet).
    var scrollTo: PendingChange.ID? = nil
    /// A navigation request resets transient ledger UI, never saved requests.
    var navigationReset: UUID? = nil
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var confirmBulkCancel = false
    /// Apply now, the bulk bar and "Waiting for…" all open Skip the wait.
    @State private var skipTarget: SkipWaitTarget?
    @State private var notice: String?

    var body: some View {
        var calendar = Calendar.current
        calendar.locale = locale
        let groups = LedgerGrouping.groups(model.state.pending, date: \.appliesAt,
                                           now: Date(), calendar: calendar)
            .map { LedgerSection(bucket: $0.bucket, changes: $0.items) }
        return ScrollViewReader { proxy in ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                Text(tr("Changes"))
                    .demoraType(.pageTitle)
                    .foregroundStyle(Ink.ink)
                    .accessibilityAddTraits(.isHeader)
                if groups.isEmpty {
                    EmptyStateView(title: tr("No changes waiting"),
                                   systemImage: "checkmark.circle",
                                   description: tr("Changes you make wait here until they apply."))
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
                        SectionHeader(title(group.bucket))
                        ForEach(group.changes) { change in
                            row(change)
                                .id(change.id)
                                .transition(reduceMotion ? .opacity
                                    : .move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
            }
            .padding(.horizontal, DemoraSpace.pageGutter)
            .padding(.vertical, DemoraSpace.xl)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25),
                       value: model.state.pending.map(\.id))
        }
        .onAppear {
            guard let scrollTo else { return }
            DispatchQueue.main.async { proxy.scrollTo(scrollTo, anchor: .center) }
        }
        }
        .background(Ink.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !model.state.pending.isEmpty {
                    Button(selecting ? tr("Done") : tr("Select")) {
                        selecting.toggle()
                        if !selecting { selection.removeAll() }
                    }
                    .foregroundStyle(accent)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting && !selection.isEmpty {
                HStack {
                    Button(role: .destructive) { confirmBulkCancel = true } label: {
                        Label(String(format: tr("Cancel %d"), selection.count),
                              systemImage: "xmark.circle")
                    }
                    Spacer()
                    Button { bulkApply() } label: {
                        Label(String(format: tr("Apply %d now"), selection.count),
                              systemImage: "bolt")
                    }
                }
                .padding()
                .background(.bar)
            }
        }
        .onReceive(model.$state) { state in
            // Due changes can disappear while selected. Never leave a stale
            // bulk-action count or stranded Select mode.
            let pendingIDs = Set(state.pending.map(\.id))
            selection.formIntersection(pendingIDs)
            if pendingIDs.isEmpty { selecting = false }
        }
        .onChange(of: navigationReset) { _ in
            skipTarget = nil
            notice = nil
            confirmBulkCancel = false
            selecting = false
            selection = []
        }
        .confirmationDialog(tr("Cancel these changes?"), isPresented: $confirmBulkCancel,
                            titleVisibility: .visible) {
            Button(String(format: tr("Cancel %d"), selection.count), role: .destructive) {
                bulkCancel()
            }
            Button(tr("Keep editing"), role: .cancel) {}
        }
        .skipWaitSheet($skipTarget, onDismiss: onRequestsChanged)
        .alert(tr("Heads up"), isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } })) {
            Button(tr("OK"), role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    @ViewBuilder private func row(_ change: PendingChange) -> some View {
        if selecting {
            Button {
                if selection.contains(change.id) {
                    selection.remove(change.id)
                } else {
                    selection.insert(change.id)
                }
            } label: {
                HStack(spacing: DemoraSpace.s) {
                    Image(systemName: selection.contains(change.id)
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                        StateChip(kind: change.direction == .stricter ? .active : .loosening,
                                  text: tr(change.direction == .stricter ? "Stricter" : "Looser"))
                        Text(change.summary)
                            .demoraType(.cardTitle)
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .paperCard()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection.contains(change.id) ? [.isSelected] : [])
        } else {
            let waiting = ChangeWaiting.find(for: change, in: outgoing,
                                             contacts: model.state.overrides.contacts)
            ChangeRow(
                change: change,
                canOverride: ChangeEngine.hasOverride(for: [change], state: model.state),
                waiting: waiting,
                onCancel: { model.cancel(change) },
                onOverride: { skipTarget = .changes([change]) },
                onDebugApply: { model.applyNow(change) },
                onOpenRequest: { openRequest(waiting) }
            )
        }
    }

    private func title(_ bucket: LedgerGrouping.Bucket) -> String {
        switch bucket {
        case .withinHour: return tr("Within the hour")
        case .laterToday: return tr("Later today")
        case .tomorrow:   return tr("Tomorrow")
        case .day(let day):
            return day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
        case .later:      return tr("Later")
        }
    }

    private func openRequest(_ waiting: ChangeWaiting?) {
        guard let waiting,
              let request = outgoing.first(where: { $0.requestId == waiting.requestID })
        else { return }
        // Opens straight on the request's status (it was already sent).
        skipTarget = .request(model.state.pending.filter { request.changeIds.contains($0.id) })
    }

    private var selectedChanges: [PendingChange] {
        model.state.pending.filter { selection.contains($0.id) }
    }

    private func bulkCancel() {
        for change in selectedChanges { model.cancel(change) }
        selection.removeAll()
        selecting = false
    }

    private func bulkApply() {
        let chosen = selectedChanges
        model.applyNow(chosen.filter(\.isDue))
        let needGate = chosen.filter { !$0.isDue }
        if !needGate.isEmpty {
            if ChangeEngine.hasOverride(for: needGate, state: model.state) {
                skipTarget = .changes(needGate)
            } else {
                // No override to skip the wait — say so instead of doing nothing.
                notice = tr("Those changes are still counting down. Wait them out or use an available override.")
            }
        }
        selection.removeAll()
        selecting = false
    }
}

private struct LedgerSection: Identifiable {
    let bucket: LedgerGrouping.Bucket
    let changes: [PendingChange]
    var id: LedgerGrouping.Bucket { bucket }
}
