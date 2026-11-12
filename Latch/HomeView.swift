//
//  HomeView.swift
//  The Today tab (docs/today-redesign.md).
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
    @Binding var widgetDestination: WidgetDestination?

    init(widgetDestination: Binding<WidgetDestination?> = .constant(nil)) {
        _widgetDestination = widgetDestination
    }

    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var outgoing: [ContactsRelay.OutgoingRequest] = []
    /// Apply now, "Waiting for…" and extra time open Skip the wait.
    @State private var skipTarget: SkipWaitTarget?
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
    // When & where Check in rows: the engine's use counts and the clock,
    // both read in events.
    @State private var conditionalUsed: [UUID: Int] = [:]
    @State private var conditionalClock: ConditionalClockRead?
    @State private var checkIn: CheckInRequest?
    private enum TodayRoute: Hashable { case changes }
    @State private var todayPath: [TodayRoute] = []
    @State private var ledgerTarget: PendingChange.ID?
    @State private var ledgerNavigationReset: UUID?
    @State private var ruleSheet: RuleSummaryRequest?
    @State private var showAddLimit = false
    @State private var showSession = false
    @State private var showCalendar = false

    private static let inboxAnchor = "today-inbox"

    private var inboxVisible: Bool {
        model.selectedTab == 0 && scenePhase == .active
    }

    private var needsWakeTap: Bool {
        wakePresentation.contains { $0.wallRelease == nil }
    }

    var body: some View {
        NavigationStack(path: $todayPath) {
            today
            .background(Ink.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task(id: inboxVisible) {
                guard inboxVisible else { return }
                while !Task.isCancelled {
                    // Local read first: "Waiting for…" rows never wait on
                    // the network.
                    loadOutgoing()
                    await loadInbox()
                    guard !Task.isCancelled, inboxVisible else { return }
                    loadOutgoing()
                    do {
                        try await Task.sleep(nanoseconds: 30_000_000_000)
                    } catch {
                        return
                    }
                }
            }
            .onReceive(model.$state) { state in
                refreshSnapshot(state: state)
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
                consumeWidgetDestination()
            }
            .onChange(of: model.todayRequest) { _ in
                // Sent here from a sheet on top of Today (e.g. Calendar →
                // a limit → Get extra time): show Today itself.
                showCalendar = false
            }
            .onChange(of: widgetDestination) { _ in consumeWidgetDestination() }
            .refreshable {
                usageRefreshRequest = UUID()
                model.tick()
                refreshSnapshot(state: model.state)
                await loadInbox()
                loadOutgoing()
            }
            .skipWaitSheet($skipTarget, onDismiss: {
                loadOutgoing()
                refreshSnapshot(state: model.state)
            })
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

    private func consumeWidgetDestination() {
        guard model.state.isSetUp, !model.setupStorageUnavailable,
              let destination = widgetDestination else { return }
        // Navigate out of transient UI without changing/cancelling saved rules
        // or requests, and never remount the retained private usage report.
        ruleSheet = nil
        checkIn = nil
        skipTarget = nil
        homeNotice = nil
        showAddLimit = false
        showSession = false
        showCalendar = false
        ledgerTarget = nil
        ledgerNavigationReset = UUID()
        todayPath = destination == .changes ? [.changes] : []
        widgetDestination = nil
    }

    private var today: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                    TodayHeader(date: Date.now, hasRequests: !model.approvalInbox.isEmpty) {
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
                    if !model.approvalInbox.isEmpty {
                        VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
                            ForEach(model.approvalInbox) { request in
                                InboxCard(request: request) { respond(to: request, approve: $0) }
                            }
                        }
                        .id(Self.inboxAnchor)
                    }
                    limitsSection
                    if !model.state.conditionalRules.isEmpty {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            checkInRows(at: context.date)
                        }
                    }
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        dayThread(at: context.date)
                    }
                    changingSoon
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
        .navigationDestination(for: TodayRoute.self) { route in
            switch route {
            case .changes:
                ChangesLedgerView(outgoing: activeOutgoing, onRequestsChanged: loadOutgoing,
                                  scrollTo: ledgerTarget, navigationReset: ledgerNavigationReset)
            }
        }
        .ruleSummary($ruleSheet) { id in
            ledgerTarget = id
            todayPath = [.changes]
        }
        .sheet(item: $checkIn) { request in CheckInSheet(ruleID: request.ruleID) }
        .sheet(isPresented: $showAddLimit) { LimitEditorView(existing: nil) }
        .sheet(isPresented: $showSession) { SessionStartView() }
        .sheet(isPresented: $showCalendar) {
            NavigationStack {
                CalendarView(onSeeChange: { id in
                    showCalendar = false
                    ledgerTarget = id
                    todayPath = [.changes]
                })
                .toolbar(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Done")) { showCalendar = false }
                    }
                }
            }
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

    /// Under extra time: rules a check-in could start now (spec §5.3).
    @ViewBuilder private func checkInRows(at now: Date) -> some View {
        if let read = conditionalClock {
            let available = ConditionalAvailability.todayRows(
                state: model.state, used: conditionalUsed, clock: read.clock(at: now, calendar: .current))
            CheckInRows(rows: available.rows, more: available.more,
                        onCheckIn: { checkIn = CheckInRequest(ruleID: $0) },
                        onAll: { model.selectedTab = 1 })
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
                    SectionHeaderLink(title: tr("Full day")) { showCalendar = true }
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
                        todayPath = [.changes]
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
                        onOverride: { skipTarget = .changes([change]) },
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
                model.approvalInbox.removeAll { $0.id == request.id }
            } catch {
                // Keep the row — the response didn't go through.
                homeNotice = tr("Couldn't send your response — check your connection and try again.")
            }
        }
    }

    /// Status helpers may repair clock anchors or mark unreadable runtime state.
    /// Call them only from events, never while SwiftUI evaluates the body.
    private func refreshWakePresentation(state: LatchState) {
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
        if state.conditionalRules.isEmpty {
            conditionalUsed = [:]
            conditionalClock = nil
        } else {
            let guarded = TimeGuard.now()
            conditionalUsed = RuleLiveReads.conditionalUsed(state: state, guardedNow: guarded, wallNow: now)
            conditionalClock = ConditionalClockRead(
                guardedOffset: guarded.timeIntervalSince(now),
                recentTimeZoneIDs: ConditionalClockInput.current(for: state, guardedNow: guarded,
                                                                 wallNow: now).recentTimeZoneIDs)
        }
    }

    /// Opens the limit's next extra-time gate: contact, password, phrase or wait.
    private func requestExtraTime(for limit: AppLimit, remaining: Int) {
        switch ExtraTimeRoute.route(for: limit, remaining: remaining) {
        case .contact(let context): skipTarget = .extraContact(context)
        case .password:
            skipTarget = ExtraTimeUse(limit: limit, remaining: remaining,
                                      policies: model.state.overrides).map(SkipWaitTarget.extraPassword)
        case .phrase:
            skipTarget = ExtraTimeUse(limit: limit, remaining: remaining,
                                      policies: model.state.overrides).map(SkipWaitTarget.extraPhrase)
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
        // Opens straight on the request's status (it was already sent).
        skipTarget = .request(pendingChanges(for: request))
    }

    private func loadInbox() async {
        guard !Task.isCancelled, inboxVisible else { return }
        do {
            let incoming = try await ContactsRelay.pendingRequestsForMe()
            guard !Task.isCancelled, inboxVisible else { return }
            model.approvalInbox = incoming
        } catch {
            // A failed refresh is not an empty inbox. Keep the last rows/count.
        }
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
