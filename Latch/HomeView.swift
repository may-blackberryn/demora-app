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
    @Environment(\.scenePhase) private var scenePhase
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
                    }
                    .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 24) {
                        Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .font(.system(size: dateSize, weight: .regular, design: .serif))
                            .tracking(-1.5)
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            if model.inTutorial {
                                DemoraDayLine(date: context.date)
                            } else {
                                HomeDayTimeline(date: context.date, state: model.state,
                                                wakes: wakePresentation)
                            }
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
                                refreshWakePresentation(state: model.state)
                                wakeSaveFailed = needsWakeTap
                            }
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: "sunrise")
                                    .font(.system(size: 34, weight: .ultraLight))
                                Text(tr("Wake up"))
                                    .font(.system(.largeTitle, design: .serif))
                                    .tracking(-0.8)
                                if startingWake { ProgressView().tint(accent) }
                            }
                            .foregroundStyle(accent)
                            .frame(maxWidth: .infinity, minHeight: 116)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(startingWake)
                        if wakeSaveFailed {
                            Text(tr("Wake-up could not be saved. Try again."))
                                .font(.footnote).foregroundStyle(Ink.danger)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }
                    }
                    if wakePresentation.contains(where: { $0.wallRelease != nil }) {
                        VStack(spacing: 12) {
                            ForEach(wakePresentation) { wake in
                                if let release = wake.wallRelease {
                                    HStack {
                                        Label(wake.name, systemImage: "sunrise")
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 12)
                                        Text(timerInterval: Date.now...max(Date.now.addingTimeInterval(1), release),
                                             countsDown: true)
                                            .font(.system(.title3, design: .serif).monospacedDigit())
                                            .foregroundStyle(accent)
                                    }
                                    .font(.subheadline)
                                }
                            }
                        }
                        .demoraSurface()
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
                        CompactHomeUsageReport(limitCount: model.state.limits.count)
                    }
                    NavigationLink {
                        UsageInsightsView().toolbar(.visible, for: .navigationBar)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.xyaxis.line")
                            Text(tr("Usage & trends")).font(.system(.title3, design: .serif))
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption)
                        }
                        .foregroundStyle(accent).frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)

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
            .onReceive(model.$state) { state in
                refreshWakePresentation(state: state)
                // Due changes can disappear while this section is selected.
                // Never leave a stale bulk-action count or stranded Select mode.
                let pendingIDs = Set(state.pending.map(\.id))
                selection.formIntersection(pendingIDs)
                if pendingIDs.isEmpty { selecting = false }
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                refreshWakePresentation(state: model.state)
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { refreshWakePresentation(state: model.state) }
            }
            .onAppear {
                refreshWakePresentation(state: model.state)
                loadOutgoing()
                if model.inTutorial && model.selectedTab == 0 { model.tutorialScreen = "home" }
            }
            .onChange(of: selecting) { _ in syncApplyBar() }
            .onChange(of: selection) { _ in syncApplyBar() }
            .onDisappear { model.applyBarVisible = false }
            .refreshable {
                model.tick()
                refreshWakePresentation(state: model.state)
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

    /// Status helpers may repair clock anchors or mark unreadable runtime state.
    /// Call them only from events, never while SwiftUI evaluates the body.
    private func refreshWakePresentation(state: LatchState) {
        guard !model.inTutorial else { wakePresentation = []; return }
        let wall = Date(), guarded = TimeGuard.now()
        var entries: [HomeWakePresentation] = []
        func append(id: String, name: String, start: Int, latest: Int?, status: GlobalWakeStatus) {
            switch status {
            case .needsTap:
                entries.append(HomeWakePresentation(id: id, name: name,
                    startMinutes: start, wallRelease: nil))
            case .waiting(let until):
                entries.append(HomeWakePresentation(id: id, name: name,
                    startMinutes: start,
                    wallRelease: HomeDayProjection.projectedRelease(until: until,
                        wall: wall, guarded: guarded, latestMinutes: latest, calendar: .current)))
            case .inactive, .awake: break
            }
        }
        append(id: "global", name: tr("Wake-up wait"), start: state.wakeRule.startHour * 60,
               latest: state.wakeRule.latest(on: wall),
               status: GlobalWake.status(state: state, at: wall))
        for group in state.dayNightGroups {
            let timing = group.wakeTiming(on: wall)
            append(id: "day-night-\(group.id)", name: group.name,
                   start: timing.startMinutes, latest: timing.latestMinutes,
                   status: DayNightWake.status(group: group, at: wall, guardedNow: guarded))
        }
        for limit in state.limits {
            let status = LimitFeatures.wakeState(for: limit, at: wall, guardedNow: guarded)
            let timing = (limit.wakeSchedule ?? LimitWakeSchedule())
                .timing(on: wall, defaultWait: limit.wakeDelayMinutes ?? 0)
            switch status {
            case .needsTap:
                append(id: "limit-\(limit.id)", name: limit.name, start: timing.startMinutes,
                       latest: timing.latestMinutes, status: .needsTap)
            case .waiting(let until):
                append(id: "limit-\(limit.id)", name: limit.name, start: timing.startMinutes,
                       latest: timing.latestMinutes, status: .waiting(until))
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

// MARK: - Home day projection (presentation only; no enforcement or usage)

private struct HomeWakePresentation: Identifiable {
    let id: String
    let name: String
    let startMinutes: Int
    /// A guarded deadline projected onto the wall clock in an event callback.
    /// Nil means a tap is needed, not that a future release can be predicted.
    let wallRelease: Date?
}

private struct HomeDaySegment {
    enum Kind { case block, free, wake }
    let name: String
    let kind: Kind
    let start: Double
    let end: Double
    let needsTap: Bool
}

private enum HomeDayProjection {
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

    static func fraction(_ date: Date, in day: DateInterval) -> Double {
        min(1, max(0, date.timeIntervalSince(day.start) / max(1, day.duration)))
    }

    static func segment(name: String, kind: HomeDaySegment.Kind,
                        start: Date, end: Date, day: DateInterval,
                        needsTap: Bool = false) -> HomeDaySegment? {
        guard end >= start, end >= day.start, start < day.end,
              end > day.start || needsTap,
              end > start || needsTap else { return nil }
        return HomeDaySegment(name: name, kind: kind,
            start: fraction(start, in: day), end: fraction(end, in: day), needsTap: needsTap)
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

// MARK: - Home day drawing

private struct HomeDayTimeline: View {
    @AppAccent private var accent
    let date: Date
    let state: LatchState
    let wakes: [HomeWakePresentation]

    private var day: DateInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start,
            end: calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400))
    }

    private var segments: [HomeDaySegment] {
        let day = day, calendar = Calendar.current
        var result: [HomeDaySegment] = []
        func add(_ name: String, _ kind: HomeDaySegment.Kind, _ start: Date, _ end: Date,
                 needsTap: Bool = false) {
            if let segment = HomeDayProjection.segment(name: name, kind: kind,
                start: start, end: end, day: day, needsTap: needsTap) { result.append(segment) }
        }
        for session in state.sessions {
            add("\(session.name) · \(session.kind.label)", session.kind == .block ? .block : .free,
                session.startedAt, session.endsAt)
        }
        for window in state.planned {
            add("\(window.name) · \(window.kind.label)", window.kind == .free ? .free : .block,
                window.startsAt, window.endsAt)
        }
        for schedule in state.schedules {
            for interval in HomeDayProjection.recurring(start: schedule.startMinutes,
                end: schedule.endMinutes, day: day, calendar: calendar,
                matches: { schedule.recurrence.matches(dayOf: $0) }) {
                add("\(schedule.name) · \(schedule.mode.label)", .block, interval.start, interval.end)
            }
        }
        for exemption in state.exemptions {
            for interval in HomeDayProjection.recurring(start: exemption.startMinutes,
                end: exemption.endMinutes, day: day, calendar: calendar,
                matches: { exemption.recurrence.matches(dayOf: $0) }) {
                add("\(exemption.name) · \(tr("Free period"))", .free, interval.start, interval.end)
            }
        }
        for wake in wakes {
            if let release = wake.wallRelease {
                // Only the remaining, known wait. Never infer its original tap
                // from the current configuration, which may have been edited.
                add("\(wake.name) · \(tr("Wake-up wait"))", .wake, date, release)
            } else if let start = calendar.date(bySettingHour: wake.startMinutes / 60,
                minute: wake.startMinutes % 60, second: 0, of: date) {
                // Dashed elapsed awaiting-tap interval ends NOW, not at a
                // fabricated future unlock time. The open dot denotes the tap.
                add("\(wake.name) · \(tr("Wake-up tap needed"))", .wake,
                    min(start, date), date, needsTap: true)
            }
        }
        return result
    }

    var body: some View {
        let day = day, segments = segments
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                var ticks = Path()
                for hour in 0...24 {
                    let boundary = hour == 24 ? day.end
                        : (Calendar.current.date(bySettingHour: hour, minute: 0, second: 0,
                                                 of: day.start) ?? day.start)
                    let x = HomeDayProjection.fraction(boundary, in: day) * size.width
                    ticks.move(to: CGPoint(x: x, y: 0))
                    ticks.addLine(to: CGPoint(x: x, y: hour % 6 == 0 ? 14 : 6))
                }
                context.stroke(ticks, with: .color(Ink.rule), lineWidth: 1)
                for segment in segments {
                    let y: CGFloat = segment.kind == .block ? 24 : (segment.kind == .free ? 32 : 40)
                    let color = segment.kind == .block ? Ink.danger : accent
                    var line = Path()
                    line.move(to: CGPoint(x: segment.start * size.width, y: y))
                    line.addLine(to: CGPoint(x: segment.end * size.width, y: y))
                    context.stroke(line, with: .color(color),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round,
                                           dash: segment.kind == .wake ? [3, 3] : []))
                    if segment.needsTap {
                        let dot = CGRect(x: min(size.width - 3, max(3, segment.end * size.width)) - 3,
                                         y: y - 3, width: 6, height: 6)
                        context.fill(Path(ellipseIn: dot), with: .color(Ink.paper))
                        context.stroke(Path(ellipseIn: dot), with: .color(accent), lineWidth: 1)
                    }
                }
                let x = HomeDayProjection.fraction(date, in: day) * size.width
                var now = Path()
                now.move(to: CGPoint(x: x, y: 0))
                now.addLine(to: CGPoint(x: x, y: segments.isEmpty ? 23 : 46))
                context.stroke(now, with: .color(accent.opacity(0.65)), lineWidth: 1)
            }
            .frame(height: segments.isEmpty ? 24 : 48)
            .accessibilityHidden(true)
            HStack {
                Text("00")
                Spacer()
                Text(date, style: .time).foregroundStyle(accent)
                Spacer()
                Text("24")
            }
            .font(.system(.caption2, design: .monospaced)).foregroundStyle(Ink.faint)
            if !segments.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { legend(segments) }
                    VStack(alignment: .leading, spacing: 6) { legend(segments) }
                }
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(Ink.faint)
                // VoiceOver retains every named interval, including overlapping
                // strokes. This is a schedule illustration, not usage data.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(segments.map { segment in
                    if segment.needsTap { return segment.name }
                    let start = day.start.addingTimeInterval(segment.start * day.duration)
                    let end = day.start.addingTimeInterval(segment.end * day.duration)
                    return "\(segment.name), \(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
                }.joined(separator: "; "))
            }
        }
    }

    @ViewBuilder private func legend(_ segments: [HomeDaySegment]) -> some View {
        if segments.contains(where: { $0.kind == .block }) {
            Label(tr("Block"), systemImage: "minus").foregroundStyle(Ink.danger)
        }
        if segments.contains(where: { $0.kind == .free }) {
            Label("\(tr("Unblock")) / \(tr("Free"))", systemImage: "minus").foregroundStyle(accent)
        }
        if segments.contains(where: { $0.kind == .wake && !$0.needsTap }) {
            Label(tr("Wake-up wait"), systemImage: "ellipsis").foregroundStyle(accent)
        }
        if segments.contains(where: { $0.kind == .wake && $0.needsTap }) {
            Label(tr("Wake-up tap needed"), systemImage: "circle").foregroundStyle(accent)
        }
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
