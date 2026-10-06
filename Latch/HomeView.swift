//
//  HomeView.swift
//  Pending changes with live countdowns, cancel, and override ("apply now").
//

import SwiftUI

/// "lock.badge.clock" only exists from iOS 17; older devices fall back
/// to the plain lock.
var strictLockSymbol: String {
    if #available(iOS 17, *) { return "lock.badge.clock" }
    return "lock.fill"
}

/// Shown on Home when the app is set up but Screen Time authorization is
/// missing (revoked, or dropped by a TestFlight→App Store install). Lets the
/// user re-grant without going back through onboarding.
struct ScreenTimeReauthBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Permissions"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.ink)
                Text(tr("Demora needs Screen Time access to set limits and block apps, and notifications to tell you when a pending change is ready. iOS will ask for each."))
                    .font(.caption).foregroundStyle(.secondary)
                // Same call as onboarding: iOS shows its own prompt. We don't
                // redirect to Settings — matching the onboarding flow.
                Button(tr("Continue")) {
                    Task { await model.requestAuthorization() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

struct HomeView: View {
    @AppAccent private var accent
    @EnvironmentObject var model: AppModel
    @ScaledMetric(relativeTo: .largeTitle) private var dateSize: CGFloat = 43
    @State private var overrideTarget: PendingChange?
    @State private var inbox: [IncomingRequest] = []
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var bulkChanges: [PendingChange] = []
    @State private var showBulkOverride = false
    @State private var outgoing: [ContactsRelay.OutgoingRequest] = []
    @State private var resumeTarget: ResumeTarget?
    @State private var homeNotice: String?
    @State private var startingWake = false
    @State private var wakeSaveFailed = false

    private var needsWakeTap: Bool {
        GlobalWake.status(state: model.state) == .needsTap
            || model.state.dayNightGroups.contains { DayNightWake.status(group: $0) == .needsTap }
            || model.state.limits.contains { ChangeEngine.wakeState(for: $0) == .needsTap }
    }

    /// A sent contact request the user wants to reopen (e.g. to enter the code).
    struct ResumeTarget: Identifiable {
        let id: String
        let changes: [PendingChange]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        Wordmark(size: 22)
                            .foregroundStyle(Ink.ink)
                        Spacer()
                        if !model.inTutorial {
                            NavigationLink {
                                HelpHubView().toolbar(.visible, for: .navigationBar)
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .font(.title3)
                            }
                            .accessibilityLabel(tr("Help"))
                        }
                        if !model.state.pending.isEmpty {
                            Button(selecting ? tr("Done") : tr("Select")) {
                                selecting.toggle()
                                if !selecting { selection.removeAll() }
                            }
                            .tutorialHighlight(!selecting
                                && (model.tutorial == .applyBoth
                                    || model.tutorial == .applyViaContact)
                                && model.tutorialScreen == "home")
                        }
                    }
                    .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 24) {
                        Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .font(.system(size: dateSize, weight: .regular, design: .serif))
                            .tracking(-1.5)
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            DemoraDayLine(date: context.date)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !model.inTutorial {
                    if needsWakeTap {
                        Button {
                            startingWake = true
                            wakeSaveFailed = false
                            Task { @MainActor in
                                _ = await ChangeEngine.wakeUpAllOffMain()
                                startingWake = false
                                model.tick()
                                wakeSaveFailed = needsWakeTap
                            }
                        } label: {
                            Label(tr("Wake up"), systemImage: "sunrise")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .demoraSurface()
                        }
                        .buttonStyle(.plain).disabled(startingWake)
                        if wakeSaveFailed {
                            Text(tr("Wake-up could not be saved. Try again."))
                                .font(.footnote).foregroundStyle(Ink.danger)
                        }
                    }
                    ForEach(model.state.dayNightGroups) { group in
                        if case .waiting(let until) = DayNightWake.status(group: group) {
                            HStack {
                                Label(group.name, systemImage: "sunrise")
                                Spacer()
                                let seconds = max(1, until.timeIntervalSince(TimeGuard.now()))
                                Text(timerInterval: Date.now...Date.now.addingTimeInterval(seconds),
                                     countsDown: true).monospacedDigit()
                            }
                            .font(.subheadline).demoraSurface()
                        }
                    }
                    switch GlobalWake.status(state: model.state) {
                    case .needsTap:
                        EmptyView() // one shared action above, not duplicate taps
                    case .waiting(let until):
                        HStack {
                            Label(tr("Wake-up wait"), systemImage: "sunrise")
                            Spacer()
                            let seconds = max(1, until.timeIntervalSince(TimeGuard.now()))
                            Text(timerInterval: Date.now...Date.now.addingTimeInterval(seconds),
                                 countsDown: true)
                                .monospacedDigit()
                        }
                        .demoraSurface()
                    case .inactive, .awake:
                        EmptyView()
                    }
                    if model.state.limits.isEmpty {
                        Button { model.selectedTab = 1 } label: {
                            EmptyStateView(title: tr("No limits yet"),
                                           systemImage: "apps.iphone",
                                           description: tr("Add a daily time limit."))
                                .demoraSurface()
                        }
                        .buttonStyle(.plain)
                    } else {
                        HomeUsageCard(limitCount: model.state.limits.count)
                    }

                        VStack(alignment: .leading, spacing: 10) {
                            Button { model.selectedTab = 2 } label: {
                              HStack {
                                DemoraSectionTitle(title: tr("Today's sessions"),
                                                   symbol: "calendar")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption).foregroundStyle(accent)
                            }
                            }
                            .buttonStyle(.plain)
                            let active = model.state.sessions.filter(\.isActive)
                            let plannedToday = model.state.planned.filter {
                                Calendar.current.isDateInToday($0.startsAt)
                                    && $0.endsAt > Date.now
                            }
                            if active.isEmpty && plannedToday.isEmpty {
                                Text(tr("No sessions today"))
                                    .font(.subheadline).foregroundStyle(Ink.faint)
                            } else {
                                ForEach(active.prefix(3)) { session in
                                    NavigationLink {
                                        ScheduledItemDetailView(
                                            title: session.name, summary: session.kind.label,
                                            timing: String(format: tr("until %@"), session.endsAt.formatted(
                                                date: .omitted, time: .shortened)),
                                            appsTitle: session.kind == .free ? nil
                                                : (session.kind == .block ? tr("Apps blocked") : tr("Apps unblocked")),
                                            selection: session.kind == .free ? nil : session.selection)
                                        .toolbar(.visible, for: .navigationBar)
                                    } label: {
                                    HStack {
                                        Text(session.name)
                                            .font(.system(.title3, design: .serif))
                                            .foregroundStyle(Ink.ink)
                                        Spacer()
                                        Text(String(format: tr("until %@"), session.endsAt.formatted(
                                            date: .omitted, time: .shortened)))
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(Ink.faint)
                                    }
                                    .padding(.vertical, 12).padding(.leading, 28)
                                    .overlay(alignment: .leading) { DemoraTimelineMark() }
                                    }
                                    .buttonStyle(.plain)
                                }
                                ForEach(plannedToday.prefix(max(0, 3 - active.count))) { window in
                                    NavigationLink {
                                        ScheduledItemDetailView(
                                            title: window.name, summary: window.kind.label,
                                            timing: window.startsAt.formatted(date: .abbreviated, time: .shortened),
                                            appsTitle: window.kind == .free ? nil
                                                : (window.kind == .blockAllExcept
                                                   ? tr("Apps that stay usable") : tr("Apps to block")),
                                            selection: window.kind == .free ? nil : window.selection)
                                        .toolbar(.visible, for: .navigationBar)
                                    } label: {
                                    HStack {
                                        Text(window.name)
                                            .font(.system(.title3, design: .serif))
                                            .foregroundStyle(Ink.ink)
                                        Spacer()
                                        Text(window.startsAt.formatted(
                                            date: .omitted, time: .shortened))
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(Ink.faint)
                                    }
                                    .padding(.vertical, 12).padding(.leading, 28)
                                    .overlay(alignment: .leading) { DemoraTimelineMark(color: Ink.faint) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .demoraSurface()
                }
                if model.state.isSetUp && !model.authorized {
                    ScreenTimeReauthBanner().demoraSurface()
                }
                if model.enforcementDegraded {
                    EnforcementBanner().demoraSurface()
                }
                if !inbox.isEmpty {
                    ApprovalInboxSection(requests: inbox) { request, approve in
                        Task {
                            do {
                                try await ContactsRelay.respond(to: request,
                                                                approve: approve)
                                inbox.removeAll { $0.id == request.id }
                            } catch {
                                // Keep the row — the response didn't go through.
                                homeNotice = tr("Couldn't send your response — check your connection and try again.")
                            }
                        }
                    }
                    .demoraSurface()
                }

                if !activeOutgoing.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("Awaiting approval")).font(.headline)
                        ForEach(activeOutgoing) { req in
                            let reqChanges = pendingChanges(for: req)
                            Button {
                                #if DEBUG
                                print("📂 resume req=\(req.requestId.prefix(8)) changeIds=\(req.changeIds.count) reqChanges=\(reqChanges.count)")
                                #endif
                                resumeTarget = ResumeTarget(id: req.requestId,
                                                            changes: reqChanges)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(reqChanges.count == 1
                                             ? (reqChanges.first?.summary ?? "")
                                             : String(format: tr("%d changes"),
                                                      reqChanges.count))
                                            .font(.subheadline)
                                        Text(req.email
                                             ? tr("Tap to enter the email code")
                                             : tr("Waiting for approval…"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: req.email
                                          ? "envelope.badge" : "hourglass")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .tint(.primary)
                        }
                    }
                    .demoraSurface()
                }

                VStack(alignment: .leading, spacing: 12) {
                    DemoraSectionTitle(title: tr("Pending changes"),
                                       symbol: "hourglass")
                    if model.state.pending.isEmpty {
                        EmptyStateView(
                            title: tr("No pending changes"),
                            systemImage: "checkmark.circle",
                            description: tr("Changes you make will appear here with a countdown.")
                        )
                    } else {
                        ForEach(model.state.pending
                            .sorted { $0.appliesAt < $1.appliesAt }) { change in
                            if selecting {
                                Button {
                                    if selection.contains(change.id) {
                                        selection.remove(change.id)
                                    } else {
                                        selection.insert(change.id)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selection.contains(change.id)
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(.tint)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(change.direction.label)
                                                .font(.caption.bold())
                                                .foregroundStyle(change.direction == .stricter
                                                                 ? .green : .orange)
                                            Text(change.summary).font(.subheadline)
                                        }
                                        Spacer()
                                    }
                                }
                                .tint(.primary)
                                .tutorialHighlight((model.tutorial == .applyBoth
                                    || model.tutorial == .applyViaContact)
                                    && model.tutorialScreen == "home", ring: false)
                            } else {
                                PendingChangeRow(
                                    change: change,
                                    canOverride: ChangeEngine.hasOverride(
                                        for: [change], state: model.state),
                                    frozenRemaining: model.inTutorial
                                        ? { model.tutorialRemaining(for: change) ?? 0 } : nil,
                                    reportHole: (model.tutorial == .applyBoth
                                        || model.tutorial == .applyViaContact)
                                        && model.tutorialScreen == "home",
                                    onCancel: { model.cancel(change) },
                                    onOverride: { overrideTarget = change },
                                    onDebugApply: { model.applyNow(change) }
                                )
                            }
                        }
                    }
                }
                .demoraSurface()
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if selecting && !selection.isEmpty {
                    HStack {
                        if !model.inTutorial {
                            Button(role: .destructive) { bulkCancel() } label: {
                                Label(String(format: tr("Cancel %d"), selection.count),
                                      systemImage: "xmark.circle")
                            }
                        }
                        Spacer()
                        Button { bulkApply() } label: {
                            Label(String(format: tr("Apply %d now"), selection.count),
                                  systemImage: "bolt")
                        }
                        .tutorialHighlight(model.inTutorial && model.tutorialScreen == "home")
                    }
                    .padding()
                    .background(.bar)
                }
            }
            .task { await loadInbox(); loadOutgoing() }
            .onAppear {
                loadOutgoing()
                if model.inTutorial && model.selectedTab == 0 { model.tutorialScreen = "home" }
            }
            .onChange(of: selecting) { _ in syncApplyBar() }
            .onChange(of: selection) { _ in syncApplyBar() }
            .onDisappear { model.applyBarVisible = false }
            .refreshable {
                model.tick()
                await loadInbox()
                loadOutgoing()
            }
            .sheet(item: $overrideTarget) { change in
                OverrideGateView(changes: [change])
            }
            .sheet(isPresented: $showBulkOverride) {
                OverrideGateView(changes: bulkChanges)
            }
            .sheet(item: $resumeTarget, onDismiss: { loadOutgoing() }) { target in
                ContactGateView(changes: target.changes, showChangeList: true,
                                onSuccess: {
                                    #if DEBUG
                                    print("✅ approval resolved \(target.changes.count) change(s)")
                                    #endif
                                    model.refreshAfterExternalApply()
                                })
            }
            .alert(tr("Heads up"), isPresented: Binding(
                get: { homeNotice != nil },
                set: { if !$0 { homeNotice = nil } })) {
                Button(tr("OK"), role: .cancel) {}
            } message: {
                Text(homeNotice ?? "")
            }
        }
    }

    /// Sent requests that still have at least one pending change to act on.
    private var activeOutgoing: [ContactsRelay.OutgoingRequest] {
        outgoing.filter { !pendingChanges(for: $0).isEmpty }
    }

    /// Pending changes still covered by a sent request.
    private func pendingChanges(for req: ContactsRelay.OutgoingRequest) -> [PendingChange] {
        model.state.pending.filter { req.changeIds.contains($0.id) }
    }

    /// Load outgoing requests, dropping any whose changes are no longer pending
    /// (applied or cancelled), so the list self-cleans.
    private func loadOutgoing() {
        for req in ContactsRelay.outgoingRequests()
        where req.extraContext == nil && pendingChanges(for: req).isEmpty {
            ContactsRelay.clearOutgoing(req.requestId)
        }
        outgoing = ContactsRelay.outgoingRequests()
            .filter { !pendingChanges(for: $0).isEmpty }
    }

    private var selectedChanges: [PendingChange] {
        model.state.pending.filter { selection.contains($0.id) }
    }

    private func bulkCancel() {
        for c in selectedChanges { model.cancel(c) }
        selection.removeAll()
        selecting = false
    }

    private func bulkApply() {
        let chosen = selectedChanges
        model.applyNow(chosen.filter(\.isDue))
        let needGate = chosen.filter { !$0.isDue }
        if !needGate.isEmpty {
            if ChangeEngine.hasOverride(for: needGate, state: model.state) {
                bulkChanges = needGate
                showBulkOverride = true
            } else {
                // No override to skip the wait — say so instead of doing nothing.
                homeNotice = tr("Those changes are still counting down. Wait them out or use an available override.")
            }
        }
        selection.removeAll()
        selecting = false
    }

    private func loadInbox() async {
        inbox = (try? await ContactsRelay.pendingRequestsForMe()) ?? []
    }

    /// Mirror the multi-select Apply bar's visibility to the model so the
    /// tutorial callout can lift above it (and otherwise sit at the bottom).
    private func syncApplyBar() {
        model.applyBarVisible = selecting && !selection.isEmpty
    }
}

/// iOS 16-compatible stand-in for ContentUnavailableView (iOS 17+).
struct EmptyStateView: View {
    @AppAccent private var accent
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .ultraLight))
                .foregroundStyle(accent)
            Text(title).font(.system(.title3, design: .serif))
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

struct PendingChangeRow: View {
    @AppAccent private var accent
    let change: PendingChange
    let canOverride: Bool
    /// When set (tutorial), the countdown ticks toward a floor and can't be
    /// waited out; Cancel is hidden.
    var frozenRemaining: (() -> TimeInterval)? = nil
    /// Reports the row's frame to the tutorial blocker so it stays tappable.
    var reportHole: Bool = false
    let onCancel: () -> Void
    let onOverride: () -> Void
    let onDebugApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(change.direction.label)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(change.direction == .stricter ? accent : Ink.danger)
                Spacer()
                if let frozenRemaining {
                    TutorialCountdownText(remaining: frozenRemaining)
                        .font(.system(.title2, design: .serif))
                } else if change.isDue {
                    Text(tr("Applying…")).font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // `appliesAt` is anchored to TimeGuard's tamper-resistant
                    // clock, but Text(timerInterval:) ticks on the system clock.
                    // Project the TimeGuard-based remaining time onto the system
                    // clock so the countdown is correct — and doesn't flicker at
                    // ~1s — even when the two clocks disagree (e.g. after sleep).
                    let remaining = max(1, change.appliesAt.timeIntervalSince(TimeGuard.now()))
                    Text(timerInterval: Date.now...Date.now.addingTimeInterval(remaining),
                         countsDown: true)
                        .font(.system(.title2, design: .serif).monospacedDigit())
                }
            }
            Text(change.summary).font(.subheadline)
            // During the tutorial the row has no buttons — applying is done by
            // Select → Apply, which is what the tour teaches.
            if frozenRemaining == nil {
                HStack {
                    Button(tr("Cancel"), role: .destructive, action: onCancel)
                        .buttonStyle(.plain).font(.subheadline)
                        .frame(minHeight: 44)
                    if canOverride && !change.isDue {
                        Button(tr("Apply now…"), action: onOverride)
                            .buttonStyle(.plain).font(.subheadline)
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
        .padding(.vertical, 16)
        .padding(.leading, 28)
        .overlay(alignment: .leading) {
            DemoraTimelineMark(color: change.direction == .stricter ? accent : Ink.danger)
        }
        .tutorialHighlight(reportHole, ring: false)
    }
}
