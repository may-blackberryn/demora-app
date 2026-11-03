//
//  HomeView.swift
//  The Today tab (docs/today-redesign.md), and the legacy Home the guided
//  tutorial still runs on.
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var wakePresentation: [HomeWakePresentation] = []
    @State private var usageRefreshRequest: UUID?
    // Today. Spent limits and extra-time states are read in event callbacks.
    @State private var spentLimitIDs: Set<UUID> = []
    @State private var portionLimitIDs: Set<UUID> = []
    @State private var extraRequestPending: Set<UUID> = []
    @State private var extraTimes: [UUID: ExtraTimeState] = [:]
    @State private var showLedger = false
    @State private var ledgerTarget: PendingChange.ID?
    @State private var ruleSheet: RuleSummaryRequest?
    @State private var showAddLimit = false
    @State private var showSession = false
    @State private var extraPasswordTarget: AppLimit?
    @State private var extraPhraseTarget: AppLimit?
    @State private var extraContactTarget: ExtraContactContext?

    private static let inboxAnchor = "today-inbox"

    private var needsWakeTap: Bool {
        wakePresentation.contains { $0.wallRelease == nil }
    }

    /// A sent contact request the user wants to reopen (e.g. to enter the code).
    struct ResumeTarget: Identifiable {
        let id: String
        let changes: [PendingChange]
    }

    var body: some View {
        NavigationStack {
            Group {
                // An interrupted legacy tutorial resumes on the Home it was
                // written for; everyone else gets Today.
                if model.inTutorial {
                    legacyHome
                } else {
                    today
                }
            }
            .background(Ink.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task(id: model.selectedTab == 0) {
                guard model.selectedTab == 0 else { return }
                await loadInbox()
                guard !Task.isCancelled else { return }
                loadOutgoing()
            }
            .onReceive(model.$state) { state in
                refreshSnapshot(state: state)
                // Due changes can disappear while this section is selected.
                // Never leave a stale bulk-action count or stranded Select mode.
                let pendingIDs = Set(state.pending.map(\.id))
                selection.formIntersection(pendingIDs)
                if pendingIDs.isEmpty { selecting = false }
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                refreshSnapshot(state: model.state)
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { refreshSnapshot(state: model.state) }
            }
            .onAppear {
                refreshSnapshot(state: model.state)
                loadOutgoing()
                if model.inTutorial && model.selectedTab == 0 { model.tutorialScreen = "home" }
            }
            .onChange(of: selecting) { _ in syncApplyBar() }
            .onChange(of: selection) { _ in syncApplyBar() }
            .onDisappear { model.applyBarVisible = false }
            .onChange(of: model.selectedTab) { tab in
                // Retained Home no longer disappears on a normal tab switch.
                // Never leave its bulk-action bar active behind another page.
                if tab == 0 { syncApplyBar() }
                else { model.applyBarVisible = false }
            }
            .refreshable {
                usageRefreshRequest = UUID()
                model.tick()
                refreshSnapshot(state: model.state)
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

    // MARK: Today (docs/today-redesign.md §5)

    private var today: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                    TodayHeader(date: Date.now, hasRequests: !inbox.isEmpty) {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                            proxy.scrollTo(Self.inboxAnchor, anchor: .top)
                        }
                    }
                    let needsPermission = model.state.isSetUp && !model.authorized
                    if needsPermission || model.enforcementDegraded {
                        TodayAttentionCard(needsPermission: needsPermission,
                                           monitoringIncomplete: model.enforcementDegraded)
                    }
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let summary = NowSummary.make(state: model.state,
                                                      blockedLimitIDs: spentLimitIDs,
                                                      portionLimitIDs: portionLimitIDs,
                                                      wakes: wakePresentation, now: context.date)
                        NowCard(summary: summary, now: context.date,
                                startingWake: startingWake, wakeSaveFailed: wakeSaveFailed,
                                onWakeUp: wakeUp, onOpen: destination(for: summary, now: context.date))
                    }
                    if !inbox.isEmpty {
                        VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
                            ForEach(inbox) { request in
                                InboxCard(request: request) { respond(to: request, approve: $0) }
                            }
                        }
                        .id(Self.inboxAnchor)
                    }
                    limitsSection
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        dayThread(at: context.date)
                    }
                    changingSoon
                    moreLinks
                }
                .padding(.horizontal, DemoraSpace.pageGutter)
                .padding(.top, DemoraSpace.xs)
                .padding(.bottom, DemoraSpace.xl)
                .frame(maxWidth: DemoraSpace.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            // One primary action per screen: hidden while Wake up shows.
            if !needsWakeTap {
                Button { showSession = true } label: {
                    Label(tr("Block now"), systemImage: "lock")
                }
                .buttonStyle(DemoraPrimaryButtonStyle())
                .padding(.horizontal, DemoraSpace.pageGutter)
                .padding(.vertical, DemoraSpace.xs)
                .frame(maxWidth: DemoraSpace.maxContentWidth)
                .frame(maxWidth: .infinity)
                .background(Ink.paper)
            }
        }
        .navigationDestination(isPresented: $showLedger) {
            ChangesLedgerView(outgoing: activeOutgoing, onRequestsChanged: loadOutgoing,
                              scrollTo: ledgerTarget)
        }
        .ruleSummary($ruleSheet) { id in
            ledgerTarget = id
            showLedger = true
        }
        .sheet(isPresented: $showAddLimit) { LimitEditorView(existing: nil) }
        .sheet(isPresented: $showSession) { SessionStartView() }
        .sheet(item: $extraPasswordTarget) { limit in
            ExtraTimePasswordGate(limitID: limit.id)
        }
        .sheet(item: $extraPhraseTarget) { limit in
            ExtraTimePhraseGate(limitID: limit.id)
        }
        .sheet(item: $extraContactTarget) { context in
            ContactGateView(changes: [], extraContext: context,
                            onSuccess: { model.tick() })
        }
    }

    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
            SectionHeader(tr("Your limits")) {
                if !model.state.limits.isEmpty {
                    SectionHeaderLink(title: tr("All rules")) { model.selectedTab = 1 }
                }
            }
            if model.state.limits.isEmpty {
                EmptyStateView(title: tr("Set your first limit"),
                               systemImage: "apps.iphone",
                               description: tr("Add a daily time limit."),
                               actionTitle: tr("Add a daily limit"),
                               action: { showAddLimit = true })
            } else {
                CompactHomeUsageReport(limits: model.state.limits,
                                       reloadRequest: usageRefreshRequest)
                ExtraTimeRows(limits: model.state.limits, states: extraTimes,
                              contactPending: extraRequestPending) { limit, remaining in
                    requestExtraTime(for: limit, remaining: remaining)
                }
            }
        }
    }

    @ViewBuilder private func dayThread(at now: Date) -> some View {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let day = DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)
                                ?? start.addingTimeInterval(86_400))
        let result = DayThread.make(items: HomeDaySources.items(state: model.state,
                                                                wakes: wakePresentation, date: now),
                                    now: now, day: day)
        if !result.entries.isEmpty {
            VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
                SectionHeader(tr("Today")) {
                    // The full calendar lives on Schedules until Rules exists.
                    SectionHeaderLink(title: tr("Full day")) { model.selectedTab = 2 }
                }
                DayThreadView(result: result, now: now) { item in
                    if let ref = RuleRef(todayItemID: item.id) { ruleSheet = RuleSummaryRequest(ref: ref) }
                }
            }
        }
    }

    @ViewBuilder private var changingSoon: some View {
        let pending = model.state.pending.sorted { $0.appliesAt < $1.appliesAt }
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
                SectionHeader(tr("Changing soon")) {
                    SectionHeaderLink(title: String(format: tr("All %d"), pending.count)) {
                        ledgerTarget = nil
                        showLedger = true
                    }
                }
                ForEach(pending.prefix(2)) { change in
                    let waiting = ChangeWaiting.find(for: change, in: activeOutgoing,
                                                     contacts: model.state.overrides.contacts)
                    ChangeRow(
                        change: change,
                        canOverride: ChangeEngine.hasOverride(for: [change], state: model.state),
                        waiting: waiting,
                        onCancel: { model.cancel(change) },
                        onOverride: { overrideTarget = change },
                        onDebugApply: { model.applyNow(change) },
                        onOpenRequest: { openRequest(waiting) }
                    )
                    .transition(reduceMotion ? .opacity
                        : .move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: pending.map(\.id))
        }
    }

    /// Usage & trends and help stay here until Insights and You exist (§8).
    private var moreLinks: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                UsageInsightsView().toolbar(.visible, for: .navigationBar)
            } label: {
                moreRow(tr("Usage & trends"), symbol: "chart.xyaxis.line")
            }
            Rectangle().fill(Ink.hairline).frame(height: 1)
                .padding(.leading, DemoraSpace.cardPadding)
            NavigationLink {
                HelpHubView().toolbar(.visible, for: .navigationBar)
            } label: {
                moreRow(tr("Help"), symbol: "questionmark.circle")
            }
        }
        .buttonStyle(.plain)
        .paperCard(padding: 0)
    }

    private func moreRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: DemoraSpace.s) {
            Image(systemName: symbol)
                .foregroundStyle(accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title).demoraType(.body).foregroundStyle(Ink.ink)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ink.inkSoft)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DemoraSpace.cardPadding)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    /// Tapping the Now card opens the rule behind its sentence; several
    /// blocks or used-up limits open Rules (docs/rules-redesign.md §8).
    private func destination(for summary: NowSummary, now: Date) -> (() -> Void)? {
        let items = HomeDaySources.items(state: model.state, wakes: wakePresentation, date: now)
        func open(_ item: TodayItem?) -> () -> Void {
            guard let item, let ref = RuleRef(todayItemID: item.id) else { return { model.selectedTab = 1 } }
            return { ruleSheet = RuleSummaryRequest(ref: ref) }
        }
        switch summary.hero {
        case .oneBlock(let name, let until):
            return open(items.first { $0.kind == .block && $0.name == name && $0.end == until && $0.isActive(at: now) })
        case .free(let until):
            return open(items.first { $0.kind == .free && $0.end == until && $0.isActive(at: now) })
        case .spent(let names, _):
            let limits = model.state.limits.filter { names.contains($0.name) }
            if names.count == 1, limits.count == 1, let limit = limits.first {
                return { ruleSheet = RuleSummaryRequest(ref: .limit(limit.id)) }
            }
            return { model.selectedTab = 1 }
        case .severalBlocks:
            return { model.selectedTab = 1 }
        case .wakeNeeded, .wakeRunning, .nothing:
            return nil
        }
    }

    private func wakeUp() {
        startingWake = true
        wakeSaveFailed = false
        Task { @MainActor in
            _ = await ChangeEngine.wakeUpAllOffMain()
            startingWake = false
            model.tick()
            refreshSnapshot(state: model.state)
            wakeSaveFailed = needsWakeTap
        }
    }

    private func respond(to request: IncomingRequest, approve: Bool) {
        Task {
            do {
                try await ContactsRelay.respond(to: request, approve: approve)
                inbox.removeAll { $0.id == request.id }
            } catch {
                // Keep the row — the response didn't go through.
                homeNotice = tr("Couldn't send your response — check your connection and try again.")
            }
        }
    }

    // MARK: Legacy Home (tutorial only)

    /// The Home the legacy tutorial was written for. It renders exactly as
    /// before while the tutorial runs; the parts it only showed outside the
    /// tutorial now live on Today.
    private var legacyHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Wordmark(size: 22)
                        .foregroundStyle(Ink.ink)
                    Spacer()
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
            if model.state.isSetUp && !model.authorized {
                ScreenTimeReauthBanner().demoraSurface()
            }
            if model.enforcementDegraded {
                EnforcementBanner().demoraSurface()
            }
            if !inbox.isEmpty {
                ApprovalInboxSection(requests: inbox) { request, approve in
                    respond(to: request, approve: approve)
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
                HStack {
                    DemoraSectionTitle(title: tr("Pending changes"), symbol: "hourglass")
                    Spacer(minLength: 8)
                    if !model.state.pending.isEmpty {
                        Button(selecting ? tr("Done") : tr("Select")) {
                            selecting.toggle()
                            if !selecting { selection.removeAll() }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .foregroundStyle(accent)
                        .tutorialHighlight(!selecting
                            && (model.tutorial == .applyBoth || model.tutorial == .applyViaContact)
                            && model.tutorialScreen == "home")
                    }
                }
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
    }

    /// Status helpers may repair clock anchors or mark unreadable runtime state.
    /// Call them only from events, never while SwiftUI evaluates the body.
    private func refreshWakePresentation(state: LatchState) {
        guard !model.inTutorial else { wakePresentation = []; return }
        let wall = Date(), guarded = TimeGuard.now()
        var entries: [HomeWakePresentation] = []
        func append(id: String, name: String, start: Int, wait: Int?, latest: Int?,
                    status: GlobalWakeStatus) {
            switch status {
            case .needsTap:
                entries.append(HomeWakePresentation(id: id, name: name,
                    startMinutes: start, waitMinutes: wait, wallRelease: nil))
            case .waiting(let until):
                entries.append(HomeWakePresentation(id: id, name: name,
                    startMinutes: start, waitMinutes: wait,
                    wallRelease: HomeDayProjection.projectedRelease(until: until,
                        wall: wall, guarded: guarded, latestMinutes: latest, calendar: .current)))
            case .inactive, .awake: break
            }
        }
        append(id: "global", name: tr("Wake-up wait"), start: state.wakeRule.startHour * 60,
               wait: state.wakeRule.waitMinutes,
               latest: state.wakeRule.latest(on: wall),
               status: GlobalWake.status(state: state, at: wall))
        for group in state.dayNightGroups {
            let timing = group.wakeTiming(on: wall)
            append(id: "day-night-\(group.id)", name: group.name,
                   start: timing.startMinutes, wait: timing.waitMinutes,
                   latest: timing.latestMinutes,
                   status: DayNightWake.status(group: group, at: wall, guardedNow: guarded))
        }
        for limit in state.limits {
            let status = LimitFeatures.wakeState(for: limit, at: wall, guardedNow: guarded)
            let timing = (limit.wakeSchedule ?? LimitWakeSchedule())
                .timing(on: wall, defaultWait: limit.wakeDelayMinutes ?? 0)
            switch status {
            case .needsTap:
                append(id: "limit-\(limit.id)", name: limit.name, start: timing.startMinutes,
                       wait: timing.waitMinutes, latest: timing.latestMinutes, status: .needsTap)
            case .waiting(let until):
                append(id: "limit-\(limit.id)", name: limit.name, start: timing.startMinutes,
                       wait: timing.waitMinutes, latest: timing.latestMinutes, status: .waiting(until))
            case .notConfigured, .awake: break
            }
        }
        wakePresentation = entries
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

    /// Refreshes what Today reads from outside saved state: the wake snapshot,
    /// the monitor's spent limits and each limit's extra time. Events only,
    /// never while SwiftUI evaluates the body.
    private func refreshSnapshot(state: LatchState) {
        refreshWakePresentation(state: state)
        guard !model.inTutorial else {
            spentLimitIDs = []; portionLimitIDs = []; extraTimes = [:]; extraRequestPending = []
            return
        }
        // The same sets the shield's baseline uses: spent for the day unless
        // extra time is running, plus split portions blocked for now.
        let now = Date()
        let blocked = SharedStore.loadBlockedLimitIDs()
        let extraUnblocked = LimitFeatures.extraUnblockedIDs(state: state, at: now)
        let featureBlocked = LimitFeatures.blockedFeatureIDs(state: state, at: now, includeWake: false)
        let daily = Set(state.limits.filter {
            ($0.minutes(on: now) == 0 || blocked.contains($0.id)) && !extraUnblocked.contains($0.id)
        }.map(\.id))
        spentLimitIDs = daily
        portionLimitIDs = featureBlocked.subtracting(daily)
        var states: [UUID: ExtraTimeState] = [:]
        var pending = Set<UUID>()
        for limit in state.limits where limit.extraTime != nil {
            states[limit.id] = LimitFeatures.extraTimeState(for: limit)
            if ContactsRelay.pendingExtraRequest(for: limit.id) != nil { pending.insert(limit.id) }
        }
        extraTimes = states
        extraRequestPending = pending
    }

    /// Opens the limit's next extra-time gate: contact, password, phrase or wait.
    private func requestExtraTime(for limit: AppLimit, remaining: Int) {
        switch ExtraTimeRoute.route(for: limit, remaining: remaining) {
        case .contact(let context): extraContactTarget = context
        case .password: extraPasswordTarget = limit
        case .phrase: extraPhraseTarget = limit
        case .wait:
            let id = limit.id
            Task {
                let started = await ChangeEngine.requestExtraTimeOffMain(limitID: id)
                model.tick()
                refreshSnapshot(state: model.state)
                if !started {
                    homeNotice = tr("Extra time could not be started safely. Your limit is still in place; try again later.")
                }
            }
        }
    }

    private func openRequest(_ waiting: ChangeWaiting?) {
        guard let waiting,
              let request = activeOutgoing.first(where: { $0.requestId == waiting.requestID })
        else { return }
        resumeTarget = ResumeTarget(id: request.requestId, changes: pendingChanges(for: request))
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
        let incoming = (try? await ContactsRelay.pendingRequestsForMe()) ?? []
        guard !Task.isCancelled, model.selectedTab == 0 else { return }
        inbox = incoming
    }

    /// Mirror the multi-select Apply bar's visibility to the model so the
    /// tutorial callout can lift above it (and otherwise sit at the bottom).
    private func syncApplyBar() {
        model.applyBarVisible = model.selectedTab == 0 && selecting && !selection.isEmpty
    }
}

// MARK: - Home day projection (presentation only; no enforcement or usage)

private struct HomeWakePresentation: Identifiable {
    let id: String
    let name: String
    let startMinutes: Int
    /// The wait a tap would start, for the Now card. Nil when unknown.
    var waitMinutes: Int? = nil
    /// A guarded deadline projected onto the wall clock in an event callback.
    /// Nil means a tap is needed, not that a future release can be predicted.
    let wallRelease: Date?
}

/// Shared with Rules, which projects wake releases the same way.
enum HomeDayProjection {
    /// Display the earlier of the preserved guarded wait and the rule's known
    /// wall-clock ceiling. This never changes the saved deadline or gate state.
    static func projectedRelease(until: Date, wall: Date, guarded: Date,
                                 latestMinutes: Int?, calendar: Calendar) -> Date {
        let release = wall.addingTimeInterval(max(0, until.timeIntervalSince(guarded)))
        guard let latestMinutes,
              let ceiling = calendar.date(bySettingHour: latestMinutes / 60,
                minute: latestMinutes % 60, second: 0, of: wall) else { return release }
        return min(release, ceiling)
    }

    /// Include yesterday's overnight tail only when yesterday matched the rule.
    /// Calendar arithmetic preserves 23/25-hour days and the evening anchor.
    static func recurring(start: Int, end: Int, day: DateInterval,
                          calendar: Calendar,
                          matches: (Date) -> Bool) -> [DateInterval] {
        var intervals: [DateInterval] = []
        for offset in [-1, 0] {
            guard let anchor = calendar.date(byAdding: .day, value: offset, to: day.start),
                  matches(anchor),
                  let startsAt = calendar.date(bySettingHour: start / 60,
                    minute: start % 60, second: 0, of: anchor),
                  let endDay = calendar.date(byAdding: .day, value: start >= end ? 1 : 0, to: anchor),
                  let endsAt = calendar.date(bySettingHour: end / 60,
                    minute: end % 60, second: 0, of: endDay),
                  endsAt > startsAt, startsAt < day.end, endsAt > day.start
            else { continue }
            intervals.append(DateInterval(start: startsAt, end: endsAt))
        }
        return intervals
    }
}

// MARK: - Today's items

/// Today's rule intervals from saved state and the event-side wake snapshot:
/// the sources the old day line drew, plus sleep blocks. No new scheduling
/// logic, and nothing here reads guarded clocks or preferences.
private enum HomeDaySources {
    static func items(state: LatchState, wakes: [HomeWakePresentation], date: Date,
                      calendar: Calendar = .current) -> [TodayItem] {
        let start = calendar.startOfDay(for: date)
        let day = DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)
                                ?? start.addingTimeInterval(86_400))
        var items: [TodayItem] = []
        for session in state.sessions {
            let kind: TodayItem.Kind = session.kind == .block ? .block
                : (session.kind == .free ? .free : .unblock)
            items.append(TodayItem(id: "session-\(session.id)", name: session.name,
                detail: session.kind.label, kind: kind,
                layer: 3, start: session.startedAt, end: session.endsAt))
        }
        for window in state.planned {
            items.append(TodayItem(id: "planned-\(window.id)", name: window.name,
                detail: window.kind.label, kind: window.kind == .free ? .free : .block,
                layer: 2, start: window.startsAt, end: window.endsAt))
        }
        for schedule in state.schedules {
            for interval in HomeDayProjection.recurring(start: schedule.startMinutes,
                end: schedule.endMinutes, day: day, calendar: calendar,
                matches: { schedule.recurrence.matches(dayOf: $0) }) {
                items.append(TodayItem(id: "schedule-\(schedule.id)", name: schedule.name,
                    detail: schedule.mode.label, kind: .block,
                    start: interval.start, end: interval.end))
            }
        }
        for exemption in state.exemptions {
            for interval in HomeDayProjection.recurring(start: exemption.startMinutes,
                end: exemption.endMinutes, day: day, calendar: calendar,
                matches: { exemption.recurrence.matches(dayOf: $0) }) {
                items.append(TodayItem(id: "exemption-\(exemption.id)", name: exemption.name,
                    detail: tr("Free period"), kind: .free,
                    start: interval.start, end: interval.end))
            }
        }
        // Global sleep runs from its start to the wake hour, as the shield plan reads it.
        if state.sleepRule.enabled {
            for interval in HomeDayProjection.recurring(start: state.sleepRule.startMinutes,
                end: state.wakeRule.startHour * 60, day: day, calendar: calendar,
                matches: { state.sleepRule.weekdays.contains(calendar.component(.weekday, from: $0)) }) {
                items.append(TodayItem(id: "global-sleep", name: tr("Sleep"), detail: tr("Sleep"),
                    kind: .block, layer: 0, start: interval.start, end: interval.end))
            }
        }
        // Mirrors DayNightGroup.sleepIsActive: each evening ends at that night's wake time.
        for group in state.dayNightGroups where group.sleepEnabled {
            for offset in [-1, 0] {
                guard let anchor = calendar.date(byAdding: .day, value: offset, to: day.start),
                      group.weekdays.contains(calendar.component(.weekday, from: anchor)),
                      let startsAt = calendar.date(bySettingHour: group.sleepStartMinutes / 60,
                        minute: group.sleepStartMinutes % 60, second: 0, of: anchor) else { continue }
                let sameDayEnd = group.wakeTiming(on: anchor).startMinutes
                let endDay = sameDayEnd > group.sleepStartMinutes ? anchor
                    : (calendar.date(byAdding: .day, value: 1, to: anchor) ?? anchor)
                let endMinute = group.wakeTiming(on: endDay).startMinutes
                guard let endsAt = calendar.date(bySettingHour: endMinute / 60,
                        minute: endMinute % 60, second: 0, of: endDay),
                      endsAt > startsAt, startsAt < day.end, endsAt > day.start else { continue }
                items.append(TodayItem(id: "day-night-sleep-\(group.id)", name: group.name,
                    detail: tr("Sleep"), kind: .block, layer: 0, start: startsAt, end: endsAt))
            }
        }
        for wake in wakes {
            if let release = wake.wallRelease {
                // Only the remaining, known wait. Never infer its original tap
                // from the current configuration, which may have been edited.
                items.append(TodayItem(id: "wake-\(wake.id)", name: wake.name,
                    detail: tr("Wake-up wait"), kind: .wake, start: date, end: release))
            } else if let start = calendar.date(bySettingHour: wake.startMinutes / 60,
                minute: wake.startMinutes % 60, second: 0, of: date) {
                // An awaiting-tap gate ends now, not at a fabricated unlock time.
                items.append(TodayItem(id: "wake-\(wake.id)", name: wake.name,
                    detail: tr("Wake-up tap needed"), kind: .wake,
                    start: min(start, date), end: date, needsTap: true))
            }
        }
        return items
    }
}

extension NowSummary {
    /// The Now card for saved state (spec §5.3). `blockedLimitIDs` is the
    /// monitor's spent list, read in an event callback; names are rule names.
    fileprivate static func make(state: LatchState, blockedLimitIDs: Set<UUID>,
                                 portionLimitIDs: Set<UUID>,
                                 wakes: [HomeWakePresentation], now: Date) -> NowSummary {
        make(items: HomeDaySources.items(state: state, wakes: wakes, date: now),
             spentLimitNames: state.limits.filter { blockedLimitIDs.contains($0.id) }.map(\.name),
             portionLimitNames: state.limits.filter { portionLimitIDs.contains($0.id) }.map(\.name),
             wakes: wakes.map { Wake(name: $0.name, waitMinutes: $0.waitMinutes,
                                     release: $0.wallRelease) },
             now: now)
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
                    // CountdownText projects the TimeGuard deadline onto the
                    // system clock (see CountdownProjection).
                    CountdownText(to: change.appliesAt, style: nil)
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
