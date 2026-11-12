//
//  RuleSummarySheet.swift
//  What one rule does, its live state, any waiting change, and its Edit and
//  Remove actions (docs/rules-redesign.md §5.6). Opened from a rule card,
//  Today's Now card and day thread, and the Calendar. Reads the live rule
//  from saved state on every render, so a stale sheet never shows or edits
//  a removed rule. Every change ends on the change receipt.
//

import SwiftUI
import FamilyControls

/// A rule to show, as a sheet item.
struct RuleSummaryRequest: Identifiable, Equatable {
    let id = UUID()
    let ref: RuleRef
}

extension View {
    /// Shows the summary sheet for `request`. `onSeeChange` runs after the
    /// sheet has closed, so the caller can open the Changes ledger.
    func ruleSummary(_ request: Binding<RuleSummaryRequest?>,
                     onSeeChange: @escaping (PendingChange.ID) -> Void) -> some View {
        modifier(RuleSummaryPresenter(request: request, onSeeChange: onSeeChange))
    }
}

private struct RuleSummaryPresenter: ViewModifier {
    @Binding var request: RuleSummaryRequest?
    let onSeeChange: (PendingChange.ID) -> Void
    @State private var seeChange: PendingChange.ID?

    func body(content: Content) -> some View {
        content.sheet(item: $request, onDismiss: {
            if let id = seeChange { seeChange = nil; onSeeChange(id) }
        }) { request in
            RuleSummarySheet(requested: request.ref) { seeChange = $0 }
        }
    }
}

/// What the sheet opens on top of itself.
private enum SummaryEditor: Identifiable {
    case limit(AppLimit)
    case scheduleApps(BlockSchedule)
    case dayNight(DayNightGroup)
    case conditional(ConditionalRule)
    case legacyWake, legacySleep

    var id: String {
        switch self {
        case .limit(let limit): return "limit-\(limit.id)"
        case .scheduleApps(let schedule): return "schedule-\(schedule.id)"
        case .dayNight(let group): return "day-night-\(group.id)"
        case .conditional(let rule): return "conditional-\(rule.id)"
        case .legacyWake: return "legacy-wake"
        case .legacySleep: return "legacy-sleep"
        }
    }
}

/// Pages pushed inside the sheet.
private enum SummaryRoute: Hashable {
    case apps, groupWake(UUID), websites
}

struct RuleSummarySheet: View {
    /// A queued Block now becomes its session once it starts, so an open
    /// sheet follows it instead of reading "removed".
    private var ref: RuleRef {
        RuleCatalog.resolve(requested, state: model.state, remembered: rememberedStart)
    }
    @AppAccent private var accent
    @AppLoosen private var loosen
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    let requested: RuleRef
    /// Closes the sheet and asks the caller to open this change in Changes.
    let onSeeChange: (PendingChange.ID) -> Void
    @State private var receipt: ChangeReceiptRequest?
    @State private var editor: SummaryEditor?
    @State private var path: [SummaryRoute] = []
    // Read in events, never while drawing.
    @State private var blockedLimitIDs: Set<UUID> = []
    @State private var wakeOpens: [RuleRef: Date] = [:]
    @State private var conditionalUsed: [UUID: Int] = [:]
    @State private var extraState: ExtraTimeState = .notConfigured
    /// The queued Block now this sheet opened on, kept after it applies.
    @State private var rememberedStart: PendingChange?

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar
    }

    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView {
                    content(now: context.date)
                        .padding(DemoraSpace.xl)
                        .frame(maxWidth: DemoraSpace.maxContentWidth)
                        .frame(maxWidth: .infinity)
                }
            }
            .background(Ink.cardRaised.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SummaryRoute.self) { route in
                destination(route)
                    .toolbar(.visible, for: .navigationBar)
            }
        }
        .presentationDetents([.medium, .large])
        .changeReceipt($receipt) { dismiss() }
        .sheet(item: $editor) { editor in editorView(editor) }
        .onAppear { refresh(model.state) }
        // `$state` publishes before the property changes: read the new value.
        .onReceive(model.$state) { refresh($0) }
    }

    // MARK: Content

    @ViewBuilder private func content(now: Date) -> some View {
        let state = model.state
        switch RuleCatalog.source(of: ref, state: state) {
        case .gone:
            VStack(alignment: .leading, spacing: DemoraSpace.m) {
                Text(tr("This rule has been removed."))
                    .demoraType(.hero)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Done")) { dismiss() }
                    .buttonStyle(DemoraPrimaryButtonStyle())
            }
        case .waiting(let change):
            VStack(alignment: .leading, spacing: DemoraSpace.m) {
                header(state: state, chip: nil)
                dashed
                facts(state: state)
                dashed
                pendingBlock(change, now: now)
            }
        case .live:
            let chip = RuleChip.live(ref: ref, state: state, blockedLimitIDs: blockedLimitIDs,
                                     wakeOpens: wakeOpens, conditionalUsed: conditionalUsed,
                                     now: now, calendar: calendar)
            let pending = RulePending.index(state.pending)[ref]
            VStack(alignment: .leading, spacing: DemoraSpace.m) {
                header(state: state, chip: chip.map {
                    ChipText.make($0, now: now, calendar: calendar, locale: locale) })
                let rows = RuleSummaryFacts.make(ref: ref, state: state, extraLeft: extraLeft,
                                                 conditionalUsed: usedToday)
                if !rows.isEmpty || explanation != nil {
                    dashed
                    if let explanation {
                        Text(tr(explanation))
                            .demoraType(.body)
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    facts(state: state)
                }
                if let pending {
                    dashed
                    pendingBlock(pending, now: now)
                }
                actions(state: state)
            }
        }
    }

    private var dashed: some View {
        DashedRule()
            .stroke(Ink.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func header(state: LatchState, chip: ChipText?) -> some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr(kindLabel(state: state)))
                    .demoraType(.label)
                    .foregroundStyle(Ink.inkSoft)
                Spacer(minLength: DemoraSpace.xs)
                if let chip { StateChip(kind: chip.kind, text: chip.text) }
            }
            Text(name(state: state))
                .demoraType(.hero)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func kindLabel(state: LatchState) -> String {
        switch ref.kind {
        case .limit: return "Daily limit"
        case .repeatingBlock: return "Repeating block"
        case .freePeriod: return "Free period"
        case .dayNight: return "Day & night"
        case .planned:
            if case .planned(let id) = ref,
               (state.planned.first { $0.id == id })?.kind == .free { return "Free period" }
            return "Planned"
        case .session: return "Session"
        case .alwaysOn: return "Always on"
        case .waits: return "Your waits"
        case .conditional: return "When & where"
        }
    }

    private func name(state: LatchState) -> String {
        switch ref {
        case .limit(let id):
            return state.limits.first { $0.id == id }?.name ?? queuedName(state)
        case .schedule(let id):
            return state.schedules.first { $0.id == id }?.name ?? queuedName(state)
        case .exemption(let id):
            return state.exemptions.first { $0.id == id }?.name ?? queuedName(state)
        case .planned(let id):
            return state.planned.first { $0.id == id }?.name ?? queuedName(state)
        case .session(let id):
            return state.sessions.first { $0.id == id }?.name ?? ""
        case .dayNight(let id):
            return state.dayNightGroups.first { $0.id == id }?.name ?? queuedName(state)
        case .queuedSession:
            return queuedName(state)
        case .conditional(let id):
            return ConditionalText.rule(id, state: state)?.name ?? ""
        default:
            return RuleNames.name(ref, saved: "")
        }
    }

    /// A queued addition's name, from the card the catalog built for it.
    private func queuedName(_ state: LatchState) -> String {
        RuleCatalog.sections(state: state, now: Date()).flatMap(\.cards)
            .first { $0.ref == ref }?.name ?? ""
    }

    /// The always-on toggles explain themselves here (§5.7 I).
    private var explanation: String? {
        switch ref {
        case .appDeletion:
            return "When on, deleting ANY app from this iPhone is blocked — including Demora itself, so blocks can't be bypassed by uninstalling."
        case .adultWebsites:
            return "Uses Apple's built-in filter to limit adult websites in Safari and other apps."
        case .websites:
            return "Blocking any site also turns on Apple's adult-content filter."
        default:
            return nil
        }
    }

    // MARK: Facts

    @ViewBuilder private func facts(state: LatchState) -> some View {
        let rows = RuleSummaryFacts.make(ref: ref, state: state, extraLeft: extraLeft,
                                         conditionalUsed: usedToday)
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, fact in
                factRow(fact)
            }
        }
    }

    @ViewBuilder private func factRow(_ fact: RuleFact) -> some View {
        let label = tr(fact.labelKey)
        switch fact {
        case .howMuch(let daily, let perDay):
            FactRow(label: label, value: howMuch(daily: daily, perDay: perDay))
        case .window(let days, let start, let end):
            FactRow(label: label, value: RuleText.days(days, translate: tr, calendar: calendar) + " "
                    + RuleText.clock(start, locale: locale) + "–" + RuleText.clock(end, locale: locale))
        case .range(let start, let end):
            FactRow(label: label, value: RuleText.range(start, end, locale: locale, calendar: calendar))
        case .until(let date):
            FactRow(label: label, value: String(format: tr("Until %@"),
                TodayTimeText.short(date, now: Date(), calendar: calendar, locale: locale)))
        case .days(let days):
            VStack(alignment: .leading, spacing: DemoraSpace.xs) {
                Text(label).demoraType(.meta).foregroundStyle(Ink.inkSoft)
                DayChips(selection: .constant(days), allowsEmpty: true)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityValue(RuleText.days(RuleDays(weekdays: days), translate: tr, calendar: calendar))
            }
        case .what(let what):
            whatRow(label: label, what: what)
        case .split(let portions, let carry):
            FactRow(label: label, value: portions.map { portion in
                let minutes = RuleText.minutes(portion.minutes, locale: locale)
                guard let until = portion.untilMinutes else {
                    return String(format: tr("rest of the day %@"), minutes)
                }
                return String(format: tr("until %@: %@"), RuleText.clock(until, locale: locale), minutes)
            }.joined(separator: " · ") + (carry ? "\n" + tr("Unused minutes carry forward") : ""))
        case .extraTime(let uses, let left):
            VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                FactRow(label: label, value: uses.enumerated().map {
                    RuleSummaryFacts.extraUseText($0.offset, $0.element, translate: tr, locale: locale)
                }.joined(separator: "\n") + (left.map { "\n" + leftText($0) } ?? ""))
                if case .ready = extraState {
                    Button {
                        dismiss()
                        model.openToday()
                    } label: {
                        linkLabel(tr("Get extra time on Today"))
                    }
                    .buttonStyle(.plain)
                }
            }
        case .wakeUp(let start, let wait, let latest):
            let value = String(format: tr("Wake %@ + %@"), RuleText.clock(start, locale: locale),
                               RuleText.minutes(wait, locale: locale))
                + (latest.map { "\n" + String(format: tr("Latest wake-up: %@"), RuleText.clock($0, locale: locale)) } ?? "")
            if case .limit(let id) = ref {
                Button { path.append(.groupWake(id)) } label: {
                    FactRow(label: label, value: value, chevron: true)
                }
                .buttonStyle(.plain)
                .disabled(!canEdit)
            } else {
                FactRow(label: label, value: value)
            }
        case .sleep(let start):
            FactRow(label: label, value: RuleText.clock(start, locale: locale))
        case .conditions(_, let conditions):
            VStack(alignment: .leading, spacing: DemoraSpace.xs) {
                Text(label).demoraType(.meta).foregroundStyle(Ink.inkSoft)
                ForEach(Array(conditions.enumerated()), id: \.offset) { _, condition in
                    ConditionRow(condition: condition)
                }
            }
            .accessibilityElement(children: .combine)
        case .then(let outcome):
            let value = ConditionalText.outcomeLines(outcome, translate: tr, locale: locale).joined(separator: "\n")
            if selection != nil {
                Button { path.append(.apps) } label: {
                    FactRow(label: label, value: value, chevron: true)
                }
                .buttonStyle(.plain)
            } else {
                FactRow(label: label, value: value)
            }
        case .usesToday(let left, let total):
            FactRow(label: label, value: String(format: tr("%d of %d left"), left, total))
        }
    }

    /// Today's uses of this When & where rule, read in events; nil = unknown.
    private var usedToday: Int? {
        guard case .conditional(let id) = ref else { return nil }
        return conditionalUsed[id]
    }

    private func howMuch(daily: Int, perDay: [Int: Int]) -> String {
        func amount(_ value: Int) -> String {
            value == 0 ? tr("Blocked all day") : String(format: tr("%d min a day"), value)
        }
        guard !perDay.isEmpty else { return amount(daily) }
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        let days = order.filter { perDay[$0] != nil }
            .map { calendar.shortWeekdaySymbols[$0 - 1] + " " + RuleText.minutes(perDay[$0] ?? 0, locale: locale) }
        return amount(daily) + "\n" + days.joined(separator: ", ")
    }

    private func leftText(_ left: Int) -> String {
        left == 0 ? tr("none left today") : String(format: tr("%d left today"), left)
    }

    private var extraLeft: Int? {
        switch extraState {
        case .notNeeded(let remaining), .ready(let remaining), .active(let remaining):
            return remaining
        case .waiting(_, let remaining):
            return remaining
        case .exhausted:
            return 0
        case .notConfigured:
            return nil
        }
    }

    @ViewBuilder private func whatRow(label: String, what: RuleFact.What) -> some View {
        let value: String = {
            switch what {
            case .only(let counts):
                return counts.total == 0 ? tr("Nothing selected")
                    : String(format: tr("Block only %@"), RuleText.counts(counts, translate: tr))
            case .allExcept(let counts):
                return counts.total == 0 ? tr("Block every app")
                    : String(format: tr("Block all except %@"), RuleText.counts(counts, translate: tr))
            case .covers(let counts):
                return RuleText.counts(counts, translate: tr)
            case .dayNight(let except, let names, let extra):
                let mode = tr(except ? "Everything except…" : "Chosen limits and apps")
                var parts = [mode]
                if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
                if extra.total > 0 { parts.append(RuleText.counts(extra, translate: tr)) }
                return parts.joined(separator: "\n")
            }
        }()
        if selection != nil {
            Button { path.append(.apps) } label: {
                FactRow(label: label, value: value, chevron: true)
            }
            .buttonStyle(.plain)
        } else {
            FactRow(label: label, value: value)
        }
    }

    /// The apps a rule names, for the What page. Nil when there's nothing to list.
    private var selection: FamilyActivitySelection? {
        let state = model.state
        let found: FamilyActivitySelection?
        switch ref {
        case .limit(let id): found = state.limits.first { $0.id == id }?.selection
        case .schedule(let id): found = state.schedules.first { $0.id == id }?.selection
        case .planned(let id): found = state.planned.first { $0.id == id && $0.kind != .free }?.selection
        case .session(let id): found = state.sessions.first { $0.id == id && $0.kind != .free }?.selection
        case .dayNight(let id): found = state.dayNightGroups.first { $0.id == id }?.scope.selection
        case .conditional(let id):
            switch state.conditionalRules.first(where: { $0.id == id })?.outcome {
            case .freeTime(.unblock, let apps, _, _)?, .block(_, let apps, _)?: found = apps
            default: found = nil
            }
        default: found = nil
        }
        guard let found, RuleCounts(found).total > 0 else { return nil }
        return found
    }

    // MARK: Pending

    private func pendingBlock(_ change: PendingChange, now: Date) -> some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: DemoraSpace.xxs) {
                Image(systemName: "clock").accessibilityHidden(true)
                Text(String(format: tr(change.direction == .lenient
                                       ? "Looser change waiting · lands %@"
                                       : "Stricter change waiting · lands %@"),
                            TodayTimeText.short(change.appliesAt, now: now, calendar: calendar, locale: locale)))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .demoraType(.meta)
            .foregroundStyle(change.direction == .lenient ? loosen : accent)
            Button {
                onSeeChange(change.id)
                dismiss()
            } label: {
                linkLabel(tr("See in Changes"))
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .contain)
    }

    private func linkLabel(_ title: String) -> some View {
        HStack(spacing: DemoraSpace.xxs) {
            Text(title)
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).accessibilityHidden(true)
        }
        .demoraType(.meta)
        .foregroundStyle(accent)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    // MARK: Actions

    private var canEdit: Bool { !RulePending.blocksEdit(of: ref, pending: model.state.pending) }

    @ViewBuilder private func actions(state: LatchState) -> some View {
        let blocked = !canEdit
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            if blocked {
                Text(tr("A change is already waiting. Cancel it in Changes to make a different one."))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch ref {
            case .limit(let id):
                if let limit = state.limits.first(where: { $0.id == id }) {
                    primary(tr("Edit")) { editor = .limit(limit) }.disabled(blocked)
                    quiet(tr("Remove limit")) { receipt = ChangeReceiptRequest(action: .removeLimit(id: id)) }
                        .disabled(blocked)
                }
            case .schedule(let id):
                if let schedule = state.schedules.first(where: { $0.id == id }) {
                    primary(tr("Edit apps")) { editor = .scheduleApps(schedule) }.disabled(blocked)
                    quiet(tr("Remove block")) { receipt = ChangeReceiptRequest(action: .removeSchedule(id: id)) }
                        .disabled(blocked)
                }
            case .exemption(let id):
                onlyRemove()
                quiet(tr("Remove free period")) { receipt = ChangeReceiptRequest(action: .removeExemption(id: id)) }
                    .disabled(blocked)
            case .planned(let id):
                onlyRemove()
                quiet(tr("Remove")) { receipt = ChangeReceiptRequest(action: .removePlanned(id: id)) }
                    .disabled(blocked)
            case .session(let id):
                quiet(tr("End early")) { receipt = ChangeReceiptRequest(action: .endSessionEarly(id: id)) }
                    .disabled(blocked)
            case .dayNight(let id):
                if let group = state.dayNightGroups.first(where: { $0.id == id }) {
                    primary(tr("Edit")) { editor = .dayNight(group) }.disabled(blocked)
                    quiet(tr("Remove group")) { receipt = ChangeReceiptRequest(action: .removeDayNightGroup(id: id)) }
                        .disabled(blocked)
                }
            case .legacyWake:
                primary(tr("Edit")) { editor = .legacyWake }.disabled(blocked)
            case .legacySleep:
                primary(tr("Edit")) { editor = .legacySleep }.disabled(blocked)
            case .appDeletion:
                let on = state.blockAppRemoval
                primary(tr(on ? "Turn off" : "Turn on")) {
                    receipt = ChangeReceiptRequest(action: .setBlockAppRemoval(!on))
                }
                .disabled(blocked)
            case .adultWebsites:
                let on = state.blockAdultWebsites
                primary(tr(on ? "Turn off" : "Turn on")) {
                    receipt = ChangeReceiptRequest(action: .setBlockAdultWebsites(!on))
                }
                .disabled(blocked)
            case .websites:
                primary(tr("Edit list")) { path.append(.websites) }
            case .conditional(let id):
                if let rule = state.conditionalRules.first(where: { $0.id == id }) {
                    // Check in arrives with C15 step 3; until then it is shown,
                    // clearly off, so the rule's purpose reads right.
                    primary(tr("Check in")) {}.disabled(true)
                    Text(tr("Check in arrives in a later update."))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    secondary(tr("Edit")) { editor = .conditional(rule) }.disabled(blocked)
                    quiet(tr("Remove rule")) { receipt = ChangeReceiptRequest(action: .removeConditionalRule(id: id)) }
                        .disabled(blocked)
                }
            case .queuedSession, .waits:
                EmptyView()
            }
        }
        .padding(.top, DemoraSpace.xs)
    }

    private func onlyRemove() -> some View {
        Text(tr("To change it, remove it and add a new one."))
            .demoraType(.meta)
            .foregroundStyle(Ink.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(DemoraPrimaryButtonStyle())
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(DemoraType.button)
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }

    private func quiet(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(DemoraType.button)
            .foregroundStyle(loosen)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }

    // MARK: Destinations

    @ViewBuilder private func destination(_ route: SummaryRoute) -> some View {
        switch route {
        case .apps:
            ScrollView {
                VStack(alignment: .leading, spacing: DemoraSpace.xs) {
                    if let selection { SelectedAppsView(selection: selection) }
                }
                .padding(DemoraSpace.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("What"))
        case .groupWake(let id):
            GroupWakeDelayEditor(limitID: id)
        case .websites:
            WebsiteBlockerEditor()
        }
    }

    @ViewBuilder private func editorView(_ editor: SummaryEditor) -> some View {
        switch editor {
        case .limit(let limit): LimitEditorView(existing: limit)
        case .scheduleApps(let schedule): ScheduleSelectionEditorView(schedule: schedule)
        case .dayNight(let group): DayNightQueuedEditor(group: group)
        case .conditional(let rule): ConditionalRuleEditor(existing: rule)
        case .legacyWake: WakeBlockEditor(presentation: .sheet)
        case .legacySleep: SleepBlockEditor(presentation: .sheet)
        }
    }

    // MARK: Events

    private func refresh(_ state: LatchState) {
        if case .queuedSession(let id) = requested,
           let change = state.pending.first(where: { $0.id == id }) {
            rememberedStart = change
        }
        let reads = RuleLiveReads.read(state: state)
        blockedLimitIDs = reads.blockedLimitIDs
        wakeOpens = reads.wakeOpens
        conditionalUsed = reads.conditionalUsed
        if case .limit(let id) = ref, let limit = state.limits.first(where: { $0.id == id }) {
            extraState = LimitFeatures.extraTimeState(for: limit)
        } else {
            extraState = .notConfigured
        }
    }
}

/// A label and its value; the value wraps under the label at large type.
struct FactRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let label: String
    let value: String
    var chevron = false

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DemoraSpace.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DemoraSpace.s))
        layout {
            Text(label)
                .demoraType(.meta)
                .foregroundStyle(Ink.inkSoft)
            if !typeSize.isAccessibilitySize { Spacer(minLength: DemoraSpace.s) }
            HStack(alignment: .firstTextBaseline, spacing: DemoraSpace.xxs) {
                Text(value)
                    .demoraType(.body)
                    .foregroundStyle(Ink.ink)
                    .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Ink.inkSoft)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: chevron ? 44 : nil, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct DashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
