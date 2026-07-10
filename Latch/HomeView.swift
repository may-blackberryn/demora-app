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
    @EnvironmentObject var model: AppModel
    // Home section visibility & collapse state (collapse persisted per device).
    @AppStorage("home.showDelays") private var showDelays = true
    @AppStorage("home.showOverrides") private var showOverrides = true
    @AppStorage("home.delaysCollapsed") private var delaysCollapsed = false
    @AppStorage("home.overridesCollapsed") private var overridesCollapsed = false
    @State private var overrideTarget: PendingChange?
    @State private var inbox: [IncomingRequest] = []
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var bulkChanges: [PendingChange] = []
    @State private var showBulkOverride = false
    @State private var outgoing: [ContactsRelay.OutgoingRequest] = []
    @State private var resumeTarget: ResumeTarget?
    @State private var homeNotice: String?

    /// A sent contact request the user wants to reopen (e.g. to enter the code).
    struct ResumeTarget: Identifiable {
        let id: String
        let changes: [PendingChange]
    }

    var body: some View {
        NavigationStack {
            List {
                if model.state.isSetUp && !model.authorized {
                    Section { ScreenTimeReauthBanner() }
                }
                if model.enforcementDegraded {
                    Section { EnforcementBanner() }
                }
                if showDelays {
                    Section {
                        if !delaysCollapsed {
                            HStack {
                                Label(tr("Stricter changes"),
                                      systemImage: strictLockSymbol)
                                Spacer()
                                Text(model.state.strictDelay.shortDelayLabel)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Label(tr("Looser changes"), systemImage: "lock.open")
                                Spacer()
                                Text(model.state.lenientDelay.shortDelayLabel)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        collapsibleHeader(tr("Current delays"),
                                          collapsed: $delaysCollapsed)
                    }
                }

                if showOverrides && !model.inTutorial {
                    Section {
                        if !overridesCollapsed {
                            if !model.state.overrides.anyEnabled {
                                Text(tr("No overrides on")).foregroundStyle(.secondary)
                            } else {
                                if model.state.overrides.mathEnabled {
                                    overrideRow(tr("Math problems"), "function",
                                                model.state.overrides.mathDifficulty?.label ?? tr("On"))
                                }
                                if model.state.overrides.passwordEnabled {
                                    overrideRow(tr("Password"), "key", tr("On"))
                                }
                                if model.state.overrides.contactsEnabled {
                                    overrideRow(tr("Trusted contacts"), "person.2",
                                                String(model.state.overrides.contacts.count))
                                }
                            }
                        }
                    } header: {
                        collapsibleHeader(tr("Current overrides"),
                                          collapsed: $overridesCollapsed)
                    }
                }

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

                if !activeOutgoing.isEmpty {
                    Section {
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
                    } header: {
                        Text(tr("Awaiting approval"))
                    }
                }

                Section {
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
                                    canOverride: model.state.overrides.anyEnabled,
                                    frozenRemaining: model.inTutorial
                                        ? { model.tutorialRemaining(for: change) ?? 0 } : nil,
                                    reportHole: (model.tutorial == .applyBoth
                                        || model.tutorial == .applyViaContact)
                                        && model.tutorialScreen == "home",
                                    onCancel: { model.cancel(change) },
                                    onOverride: { overrideTarget = change }
                                )
                            }
                        }
                    }
                } header: {
                    Text(tr("Pending changes"))
                }
            }
            .paper()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !model.inTutorial {
                    ToolbarItem(placement: .navigationBarLeading) {
                        NavigationLink { HelpHubView() } label: {
                            Image(systemName: "questionmark.circle")
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Wordmark(size: 22, weight: .semibold)
                }
                if !model.state.pending.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
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
            }
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
                                    print("✅ approval applying \(target.changes.count) change(s)")
                                    #endif
                                    for c in target.changes { model.applyNow(c) }
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

    private func overrideRow(_ title: String, _ symbol: String, _ value: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func collapsibleHeader(_ title: String,
                                   collapsed: Binding<Bool>) -> some View {
        HStack {
            Button {
                withAnimation { collapsed.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: collapsed.wrappedValue
                          ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                    Text(title)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if !model.inTutorial {
                Button(tr("change")) {
                    model.selectedTab = 3
                    model.settingsPath = [.rules]
                }
                .font(.footnote)
                .italic()
            }
        }
    }

    /// Pending changes still covered by a sent request.
    private func pendingChanges(for req: ContactsRelay.OutgoingRequest) -> [PendingChange] {
        model.state.pending.filter { req.changeIds.contains($0.id) }
    }

    /// Load outgoing requests, dropping any whose changes are no longer pending
    /// (applied or cancelled), so the list self-cleans.
    private func loadOutgoing() {
        for req in ContactsRelay.outgoingRequests()
        where pendingChanges(for: req).isEmpty {
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
        for c in chosen where c.isDue { model.applyNow(c) }
        let needGate = chosen.filter { !$0.isDue }
        if !needGate.isEmpty {
            if model.state.overrides.anyEnabled {
                bulkChanges = needGate
                showBulkOverride = true
            } else {
                // No override to skip the wait — say so instead of doing nothing.
                homeNotice = tr("Those changes are still counting down. Wait them out, or turn on an override in Settings → Rules → Overrides to skip the wait.")
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
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct PendingChangeRow: View {
    let change: PendingChange
    let canOverride: Bool
    /// When set (tutorial), the countdown ticks toward a floor and can't be
    /// waited out; Cancel is hidden.
    var frozenRemaining: (() -> TimeInterval)? = nil
    /// Reports the row's frame to the tutorial blocker so it stays tappable.
    var reportHole: Bool = false
    let onCancel: () -> Void
    let onOverride: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: change.direction == .stricter
                      ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundStyle(change.direction == .stricter ? .green : .orange)
                Text(change.direction.label)
                    .font(.caption.bold())
                    .foregroundStyle(change.direction == .stricter ? .green : .orange)
                Spacer()
                if let frozenRemaining {
                    TutorialCountdownText(remaining: frozenRemaining)
                        .font(.headline)
                } else if change.isDue {
                    Text(tr("Applying…")).font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(timerInterval: Date.now...max(change.appliesAt,
                                                       Date.now.addingTimeInterval(1)),
                         countsDown: true)
                        .font(.headline.monospacedDigit())
                }
            }
            Text(change.summary).font(.subheadline)
            // During the tutorial the row has no buttons — applying is done by
            // Select → Apply, which is what the tour teaches.
            if frozenRemaining == nil {
                HStack {
                    Button(tr("Cancel"), role: .destructive, action: onCancel)
                        .buttonStyle(.bordered).controlSize(.small)
                    if canOverride && !change.isDue {
                        Button(tr("Apply now…"), action: onOverride)
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .tutorialHighlight(reportHole, ring: false)
    }
}
