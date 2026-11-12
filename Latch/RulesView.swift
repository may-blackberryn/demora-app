//
//  RulesView.swift
//  The Rules tab (docs/rules-redesign.md §5.1–5.5): every rule in one list,
//  grouped by kind, each a card with its live state and any waiting change.
//  The decisions live in RulesPresentation.swift; this file reads the
//  monitor's spent list and wake states in events and draws.
//

import SwiftUI

/// Pages pushed inside the Rules tab.
enum RulesRoute: Hashable {
    case calendar, conflicts, waits
    case websites(focusAdd: Bool)
    /// The Changes ledger, scrolled to one change when given.
    case ledger(UUID?)
}

extension NewRuleKind: Identifiable {
    var id: Self { self }
}

struct RulesView: View {
    @AppAccent private var accent
    @AppLoosen private var loosen
    @EnvironmentObject private var model: AppModel
    @Environment(\.locale) private var locale
    @Environment(\.demoraAccentColor) private var accentValue
    @State private var path: [RulesRoute] = []
    // Read in events (appear, state refresh), never while drawing.
    @State private var blockedLimitIDs: Set<UUID> = []
    @State private var wakeOpens: [RuleRef: Date] = [:]
    @State private var conditionalUsed: [UUID: Int] = [:]
    /// The day the live reads were taken (uses reset at midnight).
    @State private var readDay = ""
    @State private var hasConflicts = false
    @State private var outgoing: [ContactsRelay.OutgoingRequest] = []
    @State private var showChooser = false
    @State private var chosen: NewRuleKind?
    @State private var newRule: NewRuleKind?
    @State private var summary: RuleSummaryRequest?
    @State private var recheckInFlight = false
    @State private var recheckMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                    header
                    if model.enforcementDegraded { monitoringCard }
                    waitsStrip
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        sections(now: context.date)
                            .onChange(of: ConditionalUses.dayKey(for: context.date, calendar: .current)) { day in
                                if day != readDay { refresh(model.state) }
                            }
                    }
                }
                .padding(.horizontal, DemoraSpace.pageGutter)
                .padding(.top, DemoraSpace.xs)
                .padding(.bottom, DemoraSpace.xl)
                .frame(maxWidth: DemoraSpace.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { model.tick() }
            .safeAreaInset(edge: .bottom) {
                Button { showChooser = true } label: {
                    Label(tr("New rule"), systemImage: "plus")
                }
                .buttonStyle(DemoraPrimaryButtonStyle())
                .padding(.horizontal, DemoraSpace.pageGutter)
                .padding(.vertical, DemoraSpace.xs)
                .frame(maxWidth: DemoraSpace.maxContentWidth)
                .frame(maxWidth: .infinity)
                .background(Ink.paper)
            }
            .navigationDestination(for: RulesRoute.self) { route in
                destination(route).toolbar(.visible, for: .navigationBar)
            }
        }
        .onAppear { refresh(model.state) }
        .onReceive(model.$state) { refresh($0) }
        .sheet(isPresented: $showChooser, onDismiss: {
            // The editor opens once the chooser has gone.
            if let kind = chosen { chosen = nil; open(kind) }
        }) {
            NewRuleChooser { kind in
                chosen = kind
                showChooser = false
            }
        }
        .sheet(item: $newRule) { kind in editor(for: kind) }
        .ruleSummary($summary) { id in path.append(.ledger(id)) }
        .alert(tr("Limit recheck"), isPresented: Binding(
            get: { recheckMessage != nil },
            set: { if !$0 { recheckMessage = nil } }
        )) {
            Button(tr("OK"), role: .cancel) {}
        } message: {
            Text(recheckMessage ?? "")
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar
    }

    // MARK: Header (§5.1)

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DemoraSpace.xs) {
            Text(tr("Rules"))
                .demoraType(.pageTitle)
                .foregroundStyle(Ink.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DemoraSpace.xs)
            iconButton("calendar", label: tr("Calendar")) { path.append(.calendar) }
            iconButton("arrow.triangle.branch", label: tr("Conflicts"),
                       dot: hasConflicts) { path.append(.conflicts) }
        }
    }

    private func iconButton(_ symbol: String, label: String, dot: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if dot {
                        Circle().fill(loosen).frame(width: 7, height: 7)
                            .offset(x: -8, y: 9)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(dot ? tr("Rules overlap") : "")
    }

    private var monitoringCard: some View {
        Text(tr("iOS can't watch all your rules in the background. Removing a few restores full blocking."))
            .demoraType(.meta)
            .foregroundStyle(Ink.ink)
            .fixedSize(horizontal: false, vertical: true)
            .paperCard(fill: Ink.tint(InkRole.loosen.pair(accent: accentValue)))
    }

    // MARK: Your waits (§5.2)

    private var waitsStrip: some View {
        let pending = RulePending.index(model.state.pending)[.waits]
        return VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            Button { path.append(.waits) } label: {
                HStack(spacing: DemoraSpace.s) {
                    VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                        Text(tr("Your waits"))
                            .demoraType(.label)
                            .foregroundStyle(Ink.inkSoft)
                        Text(RuleText.waits(model.state.delayPolicy, translate: tr, locale: locale))
                            .demoraType(.meta)
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ink.inkSoft)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let pending {
                PendingLine(change: pending, label: tr("Changes in")) {
                    path.append(.ledger(pending.id))
                }
            }
        }
        .paperCard()
    }

    // MARK: Sections (§5.3)

    @ViewBuilder private func sections(now: Date) -> some View {
        let state = model.state
        let sections = RuleCatalog.sections(state: state, now: now)
        let pending = RulePending.index(state.pending)
        VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
            if RuleCatalog.isFirstUse(sections) {
                EmptyStateView(title: tr("No rules yet"),
                               systemImage: "square.stack.3d.up",
                               description: tr("Start with a daily limit or a repeating block."),
                               actionTitle: tr("Add a daily limit"),
                               action: { newRule = .dailyLimit },
                               secondaryTitle: tr("Repeating block"),
                               secondaryAction: { newRule = .repeating })
            }
            ForEach(sections, id: \.section) { section in
                LazyVStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
                    SectionHeader(tr(section.section.titleKey))
                    ForEach(section.cards) { card in
                        let chip = RuleChip.live(ref: card.ref, state: state,
                                                 blockedLimitIDs: blockedLimitIDs,
                                                 wakeOpens: wakeOpens, conditionalUsed: conditionalUsed,
                                                 now: now, calendar: calendar)
                        RuleCardView(
                            name: RuleNames.name(card),
                            summary: RuleSummaryLine.text(RuleSummaryLine.parts(for: card.ref, state: state),
                                                          translate: tr, locale: locale, calendar: calendar),
                            chip: card.isAddition ? nil : chip.map { ChipText.make($0, now: now, calendar: calendar, locale: locale) },
                            pending: pending[card.ref].map { ($0, RulePending.label(change: $0, state: state)) },
                            isAddition: card.isAddition,
                            onOpen: { open(card.ref) },
                            onPending: { change in path.append(.ledger(change.id)) })
                    }
                    if section.section == .limits && state.limits.contains(where: {
                        RuleChip.live(ref: .limit($0.id), state: state, blockedLimitIDs: blockedLimitIDs,
                                      now: now, calendar: calendar) == .blocked
                    }) {
                        recheckButton
                    }
                }
            }
        }
    }

    private var recheckButton: some View {
        Button { beginLimitRecheck() } label: {
            HStack(spacing: DemoraSpace.xs) {
                Text(tr(recheckInFlight ? "Takes around 30 seconds" : "Recheck blocked limits"))
                if recheckInFlight { ProgressView() }
            }
            .demoraType(.meta)
            .foregroundStyle(accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(recheckInFlight)
    }

    // MARK: Routing

    private func open(_ kind: NewRuleKind) {
        if kind == .website {
            path.append(.websites(focusAdd: true))
        } else {
            newRule = kind
        }
    }

    private func open(_ ref: RuleRef) {
        summary = RuleSummaryRequest(ref: ref)
    }

    @ViewBuilder private func editor(for kind: NewRuleKind) -> some View {
        switch kind {
        case .dailyLimit: LimitEditorView(existing: nil)
        case .blockNow: SessionStartView()
        case .repeating: ScheduleEditorView()
        case .planned: PlannedEditorView()
        case .dayNight: DayNightQueuedEditor(group: DayNightGroup(name: ""))
        case .whenWhere: ConditionalRuleEditor(existing: nil)
        case .website: EmptyView()
        }
    }

    @ViewBuilder private func destination(_ route: RulesRoute) -> some View {
        switch route {
        case .calendar: CalendarView(onSeeChange: { id in path.append(.ledger(id)) })
        case .conflicts: ScheduleConflictsView()
        case .waits: DelayPolicySettingsView()
        case .websites(let focusAdd): WebsiteBlockerEditor(focusAdd: focusAdd)
        case .ledger(let id):
            ChangesLedgerView(outgoing: outgoing, onRequestsChanged: loadOutgoing, scrollTo: id)
                .onAppear(perform: loadOutgoing)
        }
    }

    // MARK: Events

    private func refresh(_ state: LatchState) {
        readDay = ConditionalUses.dayKey(for: Date(), calendar: .current)
        let reads = RuleLiveReads.read(state: state)
        blockedLimitIDs = reads.blockedLimitIDs
        wakeOpens = reads.wakeOpens
        conditionalUsed = reads.conditionalUsed
        hasConflicts = reads.hasConflicts
    }

    /// Sent contact requests whose changes still wait, for the ledger. Reads
    /// only; Today keeps clearing finished requests.
    private func loadOutgoing() {
        let pendingIDs = Set(model.state.pending.map(\.id))
        outgoing = ContactsRelay.outgoingRequests().filter { $0.changeIds.contains(where: pendingIDs.contains) }
    }

    private func beginLimitRecheck() {
        guard !recheckInFlight else { return }
        recheckInFlight = true
        Task {
            let result = await ChangeEngine.recheckBlockedLimits()
            switch result {
            case .completed(let released, let confirmed):
                if released > 0 {
                    recheckMessage = String(
                        format: tr("Released %d stale limit blocks. %d limits were freshly confirmed by iOS."),
                        released, confirmed)
                } else {
                    recheckMessage = tr("iOS freshly confirmed all current limit blocks.")
                }
            case .noBlockedLimits:
                recheckMessage = tr("No blocked limits need to be rechecked.")
            case .splitBlocksNotRecheckable:
                recheckMessage = tr("Split-budget blocks cannot be manually rechecked. They remain until their scheduled boundary.")
            case .freeWindowActive:
                recheckMessage = tr("Wait until the active free period ends, then recheck again.")
            case .cooldown(let remaining):
                recheckMessage = String(format: tr("You can recheck again in %@."), remaining.shortDelayLabel)
            case .unsupportedVersion:
                recheckMessage = tr("Safe limit rechecking requires iOS 17.4 or later. No blocks were changed.")
            case .monitorUnavailable:
                recheckMessage = tr("iOS couldn't complete the verification safely. No blocks were changed. Try again later.")
            case .cancelled:
                recheckMessage = tr("The recheck was interrupted. No blocks were changed.")
            }
            recheckInFlight = false
            model.tick()
        }
    }
}

// MARK: - Live reads

/// What Rules and the summary sheet read from outside saved state: the limits
/// the shield treats as spent (the same sets Today reads), projected wake
/// releases and whether any rules overlap. Call from events (appear, a state
/// refresh), never while SwiftUI draws.
enum RuleLiveReads {
    struct Reads {
        var blockedLimitIDs: Set<UUID> = []
        var wakeOpens: [RuleRef: Date] = [:]
        var hasConflicts = false
        /// Today's uses per When & where free-time rule, on the guarded clock
        /// in every recent time zone (the engine's own count). Empty when the
        /// zones can't be resolved: the cards then show no count.
        var conditionalUsed: [UUID: Int] = [:]
    }

    @MainActor static func read(state: LatchState) -> Reads {
        let now = Date(), guarded = TimeGuard.now()
        var reads = Reads()
        let blocked = SharedStore.loadBlockedLimitIDs()
        let extraUnblocked = LimitFeatures.extraUnblockedIDs(state: state, at: now)
        let portions = LimitFeatures.blockedFeatureIDs(state: state, at: now, includeWake: false)
        let daily = Set(state.limits.filter {
            ($0.minutes(on: now) == 0 || blocked.contains($0.id)) && !extraUnblocked.contains($0.id)
        }.map(\.id))
        reads.blockedLimitIDs = daily.union(portions)
        for group in state.dayNightGroups {
            if case .waiting(let until) = DayNightWake.status(group: group, at: now, guardedNow: guarded) {
                reads.wakeOpens[.dayNight(group.id)] = HomeDayProjection.projectedRelease(
                    until: until, wall: now, guarded: guarded,
                    latestMinutes: group.wakeTiming(on: now).latestMinutes, calendar: .current)
            }
        }
        if case .waiting(let until) = GlobalWake.status(state: state, at: now) {
            reads.wakeOpens[.legacyWake] = HomeDayProjection.projectedRelease(
                until: until, wall: now, guarded: guarded,
                latestMinutes: state.wakeRule.latest(on: now), calendar: .current)
        }
        if state.conditionalRules.contains(where: \.isFreeTime),
           let keys = ConditionalClockInput.current(for: state, guardedNow: guarded, wallNow: now).dayKeys {
            for rule in state.conditionalRules where rule.isFreeTime {
                reads.conditionalUsed[rule.id] = ConditionalUses.used(ruleID: rule.id, dayKeys: keys,
                                                                      in: state.conditionalUses)
            }
        }
        let week = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        reads.hasConflicts = !SchedulePrecedence.conflicts(
            entries: SchedulePrecedence.entries(state: state, from: now, through: week),
            prioritizedKeys: state.prioritizedScheduleKeys).isEmpty
        return reads
    }
}

// MARK: - Names and chips

enum RuleNames {
    /// Built-in rules are named by the app; everything else by its owner.
    static func name(_ card: RuleCard) -> String { name(card.ref, saved: card.name) }

    static func name(_ ref: RuleRef, saved: String) -> String {
        switch ref {
        case .appDeletion: return tr("App deletion")
        case .adultWebsites: return tr("Adult websites")
        case .websites: return tr("Websites")
        case .legacyWake: return tr("Wake-up")
        case .legacySleep: return tr("Sleep")
        case .waits: return tr("Your waits")
        default: return saved
        }
    }
}

/// A chip's kind and words.
struct ChipText: Equatable {
    let kind: StateChip.Kind
    let text: String

    static func make(_ chip: RuleChip, now: Date, calendar: Calendar, locale: Locale) -> ChipText {
        func time(_ date: Date) -> String {
            TodayTimeText.short(date, now: now, calendar: calendar, locale: locale)
        }
        switch chip {
        case .blocked: return ChipText(kind: .blocked, text: tr("Blocked"))
        case .onUntil(let date): return ChipText(kind: .active, text: String(format: tr("On until %@"), time(date)))
        case .freeUntil(let date): return ChipText(kind: .free, text: String(format: tr("Free until %@"), time(date)))
        case .opens(let date): return ChipText(kind: .loosening, text: String(format: tr("Opens %@"), time(date)))
        case .startsIn(let date):
            return ChipText(kind: .upcoming, text: String(format: tr("Starts in %@"),
                RuleText.duration(date.timeIntervalSince(now), locale: locale)))
        case .on: return ChipText(kind: .active, text: tr("On"))
        case .off: return ChipText(kind: .neutral, text: tr("Off"))
        case .usesLeft(let left): return ChipText(kind: .neutral, text: String(format: tr("%d left today"), left))
        case .noneLeft: return ChipText(kind: .neutral, text: tr("None left today"))
        }
    }
}

// MARK: - Rule card (§5.4)

struct RuleCardView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let name: String
    let summary: String
    let chip: ChipText?
    let pending: (PendingChange, RulePending.Label)?
    var isAddition = false
    let onOpen: () -> Void
    let onPending: (PendingChange) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                    titleRow
                    if !summary.isEmpty {
                        Text(summary)
                            .demoraType(.meta)
                            .foregroundStyle(Ink.inkSoft)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(tr("Shows what this rule does"))
            if let pending {
                PendingLine(change: pending.0, label: tr(RulePending.labelKey(pending.1))) {
                    onPending(pending.0)
                }
            }
        }
        .padding(DemoraSpace.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: shape)
        .overlay(shape.strokeBorder(Ink.hairline,
                                    style: StrokeStyle(lineWidth: 1, dash: isAddition ? [4, 4] : [])))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DemoraRadius.card, style: .continuous)
    }

    @ViewBuilder private var titleRow: some View {
        let title = Text(name)
            .demoraType(.cardTitle)
            .foregroundStyle(isAddition ? Ink.inkSoft : Ink.ink)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                title
                if let chip { StateChip(kind: chip.kind, text: chip.text) }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: DemoraSpace.xs) {
                title.frame(maxWidth: .infinity, alignment: .leading)
                if let chip { StateChip(kind: chip.kind, text: chip.text) }
            }
        }
    }
}

/// "◷ Loosens in 3:12:04": a waiting change on a rule. Tapping opens it in
/// the Changes ledger, the one place to cancel it.
struct PendingLine: View {
    @AppAccent private var accent
    @AppLoosen private var loosen
    let change: PendingChange
    let label: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DemoraSpace.xxs) {
                Image(systemName: "clock").accessibilityHidden(true)
                Text(label)
                CountdownText(to: change.appliesAt, style: nil)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .demoraType(.meta)
            .foregroundStyle(change.direction == .lenient ? loosen : accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(tr("See in Changes"))
    }
}

// MARK: - New rule chooser (§5.5)

struct NewRuleChooser: View {
    @EnvironmentObject private var model: AppModel
    let onChoose: (NewRuleKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.s) {
                Text(tr("New rule"))
                    .demoraType(.hero)
                    .foregroundStyle(Ink.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, DemoraSpace.xxs)
                ForEach(NewRuleKind.allCases) { kind in
                    row(kind, reason: NewRuleKind.disabledReason(kind, state: model.state))
                }
            }
            .padding(DemoraSpace.xl)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.cardRaised.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func row(_ kind: NewRuleKind, reason: String?) -> some View {
        let (symbol, title, line) = Self.copy(kind)
        return Button { onChoose(kind) } label: {
            HStack(spacing: DemoraSpace.s) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Ink.ink)
                    .frame(width: 40, height: 40)
                    .background(Ink.card, in: Circle())
                    .overlay(Circle().strokeBorder(Ink.hairline, lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr(title)).demoraType(.cardTitle).foregroundStyle(Ink.ink)
                    Text(tr(reason ?? line))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(reason != nil)
        .opacity(reason == nil ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }

    static func copy(_ kind: NewRuleKind) -> (symbol: String, title: String, line: String) {
        switch kind {
        case .dailyLimit: return ("hourglass", "Daily limit", "A daily time budget for some apps")
        case .blockNow: return ("play.circle", "Block now", "Block apps for a set time, starting soon")
        case .repeating: return ("repeat", "Repeating block", "Every day, some days, or monthly — or a free period")
        case .planned: return ("calendar.badge.clock", "Plan a block", "One time: a trip, an exam, a weekend")
        case .dayNight: return ("sun.horizon", "Day & night", "A wake-up wait and a sleep time")
        case .website: return ("globe", "Website", "Block a site by its address")
        case .whenWhere: return ("mappin.and.ellipse", "When & where", "Free time or a block that depends on place, day or time")
        }
    }
}
