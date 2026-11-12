//
//  ConditionalRuleEditor.swift
//  The When & where editor (docs/conditional-sessions-redesign.md §5.10):
//  one plain page with a name, up to four conditions joined by "all of" or
//  "any of", and one outcome. Review change opens the change receipt; the
//  first problem stopping it shows above the button (R12). Decisions live in
//  RulesPresentation.swift (`EditorValidation.conditional`, `ConditionKind`,
//  `ConditionalText`); the engine validates again when the change queues
//  and applies. Places and countries need location, which arrives in a later
//  build step (C15 steps 4–5): the chooser explains that instead of offering
//  a picker. Nothing here reads location, the guarded clock or saved state
//  outside `model.state`.
//

import SwiftUI
import FamilyControls

/// One condition being edited, with a stable identity for the list.
private struct ConditionDraft: Identifiable, Equatable {
    let id = UUID()
    var condition: ConditionalCondition
}

struct ConditionalRuleEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let existing: ConditionalRule?

    private enum OutcomeChoice: Hashable { case free, block }
    private enum EndChoice: Hashable { case time, duration }

    @State private var ruleID: UUID
    /// A new rule's precedence tie-break, fixed when the page opens.
    @State private var addedAt: Date
    @State private var name: String
    @State private var match: ConditionalMatch
    @State private var conditions: [ConditionDraft]
    @State private var outcomeChoice: OutcomeChoice
    @State private var freeKind: SessionKind
    @State private var freeSelection: FamilyActivitySelection
    @State private var maxMinutes: Int
    @State private var usesPerDay: Int
    @State private var blockSelection: FamilyActivitySelection
    @State private var endChoice: EndChoice
    @State private var untilMinute: Int
    @State private var blockMinutes: Int
    @State private var receipt: ChangeReceiptRequest?
    @State private var showChooser = false
    @State private var chosenKind: ConditionKind?

    init(existing: ConditionalRule?) {
        self.existing = existing
        _ruleID = State(initialValue: existing?.id ?? UUID())
        _addedAt = State(initialValue: Date())
        _name = State(initialValue: existing?.name ?? "")
        _match = State(initialValue: existing?.match ?? .all)
        _conditions = State(initialValue: (existing?.conditions ?? []).map { ConditionDraft(condition: $0) })
        var outcome = OutcomeChoice.free
        var kind = SessionKind.free
        var free = FamilyActivitySelection()
        var minutes = 60, uses = 1
        var blocked = FamilyActivitySelection()
        var end = EndChoice.time
        var until = 7 * 60, length = 180
        switch existing?.outcome {
        case .freeTime(let k, let selection, let m, let u)?:
            kind = k == .unblock ? .unblock : .free
            free = selection
            minutes = m
            uses = u
        case .block(_, let selection, let ends)?:
            outcome = .block
            blocked = selection
            switch ends {
            case .time(let minute): until = minute
            case .duration(let m): end = .duration; length = m
            }
        case nil:
            break
        }
        _outcomeChoice = State(initialValue: outcome)
        _freeKind = State(initialValue: kind)
        _freeSelection = State(initialValue: free)
        _maxMinutes = State(initialValue: minutes)
        _usesPerDay = State(initialValue: uses)
        _blockSelection = State(initialValue: blocked)
        _endChoice = State(initialValue: end)
        _untilMinute = State(initialValue: until)
        _blockMinutes = State(initialValue: length)
    }

    // MARK: Draft

    private var outcome: ConditionalOutcome {
        switch outcomeChoice {
        case .free:
            // "Everything" frees all apps, so stray picks don't travel with it.
            return .freeTime(kind: freeKind,
                             selection: freeKind == .unblock ? freeSelection : FamilyActivitySelection(),
                             maxMinutes: maxMinutes, usesPerDay: usesPerDay)
        case .block:
            return .block(mode: .blockSelected, selection: blockSelection,
                          until: endChoice == .time ? .time(untilMinute) : .duration(minutes: blockMinutes))
        }
    }

    /// New: `addedAt` = when the page opened, `revision` 0. Edit: the saved
    /// rule's ID, `addedAt` and revision (the engine bumps the revision).
    private var draft: ConditionalRule {
        ConditionalRule(id: ruleID, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        match: match, conditions: conditions.map(\.condition), outcome: outcome,
                        addedAt: existing?.addedAt ?? addedAt, revision: existing?.revision ?? 0)
    }

    /// The saved rule this page edits, read live so a stale sheet can't
    /// recreate a removed rule.
    private var current: ConditionalRule? {
        guard let existing else { return nil }
        return model.state.conditionalRules.first { $0.id == existing.id }
    }

    private var problem: EditorProblem? {
        EditorValidation.conditional(draft, existing: current ?? existing)
    }

    private var waiting: Bool {
        guard let existing else { return false }
        return RulePending.blocksEdit(of: .conditional(existing.id), pending: model.state.pending)
    }

    /// The saved rule changed (an edit landed) since this page opened: the
    /// draft would silently undo it, so the page asks to be reopened.
    private var changedUnderneath: Bool {
        guard let existing, let current else { return false }
        return !current.sameConfiguration(as: existing)
    }

    private var canReview: Bool {
        problem == nil && !waiting && !changedUnderneath && (existing == nil || current != nil)
    }

    private var isDirty: Bool {
        if let existing { return !draft.sameConfiguration(as: existing) }
        return !name.isEmpty || !conditions.isEmpty || match != .all || outcomeChoice != .free
            || freeKind != .free || maxMinutes != 60 || usesPerDay != 1
            || endChoice != .time || untilMinute != 7 * 60 || blockMinutes != 180
            || EditorValidation.hasSelection(freeSelection) || EditorValidation.hasSelection(blockSelection)
    }

    /// A condition's binding found by ID on every read and write, so a card
    /// removed while one of its pickers is still committing reads a harmless
    /// value and writes nothing (never another card, never out of range).
    private func binding(for id: UUID) -> Binding<ConditionalCondition> {
        Binding(get: {
            conditions.first(where: { $0.id == id })?.condition ?? .days([])
        }, set: { value in
            guard let index = conditions.firstIndex(where: { $0.id == id }) else { return }
            conditions[index].condition = value
        })
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar
    }

    // MARK: Page

    var body: some View {
        RuleEditorPage(title: existing?.name ?? tr("New When & where rule"), isDirty: isDirty,
                       problem: problem?.messageKey.map(tr), canReview: canReview,
                       waiting: waiting, onReview: review) {
            if changedUnderneath {
                EditorNote(text: tr("This rule changed while you were editing. Close it and open it again."),
                           warning: true)
            }
            EditorSection(tr("Name")) {
                TextField(tr("e.g. Sunday in Mexico"), text: $name)
                    .demoraType(.cardTitle)
                    .frame(minHeight: 44)
            }
            conditionsSection
            outcomeSection
        }
        .changeReceipt($receipt) { dismiss() }
        .sheet(isPresented: $showChooser, onDismiss: addChosen) {
            ConditionChooser(conditionCount: conditions.count) { kind in
                chosenKind = kind
                showChooser = false
            }
        }
    }

    // MARK: If

    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            SectionHeader(tr("If"))
            VStack(alignment: .leading, spacing: DemoraSpace.s) {
                Picker(tr("If"), selection: $match) {
                    Text(tr("All of these")).tag(ConditionalMatch.all)
                    Text(tr("Any of these")).tag(ConditionalMatch.any)
                }
                .pickerStyle(.segmented)
                ForEach(conditions) { item in
                    if item.id != conditions.first?.id {
                        Text(tr(match == .all ? "and" : "or"))
                            .demoraType(.label)
                            .foregroundStyle(Ink.inkSoft)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                    ConditionEditorCard(condition: binding(for: item.id)) {
                        conditions.removeAll { $0.id == item.id }
                    }
                }
                addConditionButton
            }
            .paperCard()
        }
    }

    private var addConditionButton: some View {
        let full = conditions.count >= ConditionalRule.maximumConditions
        return VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
            Button { showChooser = true } label: {
                Label(tr("Add condition"), systemImage: "plus")
                    .demoraType(.body)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: DemoraRadius.card, style: .continuous)
                        .strokeBorder(Ink.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(full)
            .opacity(full ? 0.55 : 1)
            if full { EditorNote(text: tr("You can add up to four conditions.")) }
        }
    }

    private func addChosen() {
        guard let kind = chosenKind else { return }
        chosenKind = nil
        guard conditions.count < ConditionalRule.maximumConditions,
              let condition = ConditionKind.defaultCondition(kind, now: Date(), calendar: .current)
        else { return }
        conditions.append(ConditionDraft(condition: condition))
    }

    // MARK: Then

    private var outcomeSection: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            SectionHeader(tr("Then"))
            VStack(alignment: .leading, spacing: DemoraSpace.s) {
                Picker(tr("Then"), selection: $outcomeChoice) {
                    Text(tr("Free time")).tag(OutcomeChoice.free)
                    Text(tr("Block")).tag(OutcomeChoice.block)
                }
                .pickerStyle(.segmented)
                switch outcomeChoice {
                case .free: freeControls
                case .block: blockControls
                }
            }
            .paperCard()
        }
    }

    @ViewBuilder private var freeControls: some View {
        Picker(tr("What"), selection: $freeKind) {
            Text(tr("Everything")).tag(SessionKind.free)
            Text(tr("Only these apps")).tag(SessionKind.unblock)
        }
        .pickerStyle(.segmented)
        if freeKind == .unblock {
            AppsRow(title: tr("Apps to unblock"), selection: $freeSelection)
        } else {
            EditorNote(text: tr("Free time lifts every block, including day & night, while it runs."))
        }
        Text(tr("Up to")).demoraType(.meta).foregroundStyle(Ink.inkSoft)
        DurationControl(minutes: $maxMinutes, range: 5...240)
        Stepper(value: $usesPerDay, in: 1...5) {
            HStack {
                Text(tr("Times a day")).demoraType(.body).foregroundStyle(Ink.ink)
                Spacer(minLength: DemoraSpace.xs)
                Text("\(usesPerDay)").demoraType(.body).foregroundStyle(Ink.ink).monospacedDigit()
            }
        }
        .frame(minHeight: 44)
        EditorNote(text: tr("You start it with Check in on the rule or on Today."))
    }

    @ViewBuilder private var blockControls: some View {
        AppsRow(title: tr("Apps to block"), selection: $blockSelection)
        Picker(tr("Until"), selection: $endChoice) {
            Text(tr("Until a time")).tag(EndChoice.time)
            Text(tr("For a while")).tag(EndChoice.duration)
        }
        .pickerStyle(.segmented)
        switch endChoice {
        case .time:
            DatePicker(tr("Until"), selection: clockBinding($untilMinute), displayedComponents: .hourAndMinute)
                .frame(minHeight: 44)
        case .duration:
            DurationControl(minutes: $blockMinutes, range: 5...1440)
        }
        // The v1 block limits, in words (`ConditionalRule.isValid`).
        EditorNote(text: tr("A block starts when you check in at a place or in a country, and runs until the end you choose. Leaving doesn't end it. It blocks only the apps you choose."))
        if match == .any {
            EditorNote(text: tr("With “any of”, a time on its own blocks every day, like a repeating block."))
        }
        if let note = selfRunningNote { EditorNote(text: note) }
    }

    /// "From 22:00 this blocks on its own. At Home it starts when you check in."
    private var selfRunningNote: String? {
        guard match == .any else { return nil }
        let conditions = conditions.map(\.condition)
        guard let start = conditions.lazy.compactMap({ c -> Int? in
                  if case .time(let start, _) = c { return start }; return nil }).first,
              let place = conditions.first(where: \.usesLocation) else { return nil }
        let where_: String
        switch place {
        case .place(let value): where_ = value.name
        case .country(let code): where_ = ConditionalText.countryName(code, locale: locale)
        default: return nil
        }
        return String(format: tr("From %@ this blocks on its own. At %@ it starts when you check in."),
                      RuleText.clock(start, locale: locale), where_)
    }

    private func review() {
        guard canReview else { return }
        receipt = ChangeReceiptRequest(action: existing == nil ? .addConditionalRule(draft)
                                                               : .updateConditionalRule(draft))
    }
}

/// Minutes after midnight as a time-of-day Date for the system pickers.
private func clockBinding(_ minutes: Binding<Int>) -> Binding<Date> {
    Binding(get: {
        Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60,
                              second: 0, of: Date()) ?? Date()
    }, set: { minutes.wrappedValue = minutesOfDay($0) })
}

// MARK: - One condition, editable

private struct ConditionEditorCard: View {
    @AppAccent private var accent
    @AppLoosen private var loosen
    @Environment(\.locale) private var locale
    @Binding var condition: ConditionalCondition
    let onRemove: () -> Void

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar
    }

    var body: some View {
        let kind = ConditionKind.of(condition)
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            HStack(spacing: DemoraSpace.xs) {
                Label(tr(kind.titleKey), systemImage: kind.symbol)
                    .demoraType(.cardTitle)
                    .foregroundStyle(Ink.ink)
                Spacer(minLength: DemoraSpace.xs)
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundStyle(loosen)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Remove condition"))
            }
            content
        }
        .padding(DemoraSpace.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: DemoraRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DemoraRadius.card, style: .continuous)
            .strokeBorder(Ink.hairline, lineWidth: 1))
    }

    @ViewBuilder private var content: some View {
        switch condition {
        case .days:
            DayChips(selection: days, allowsEmpty: true)
            HStack(spacing: DemoraSpace.s) {
                shortcut(tr("Weekdays")) { condition = .days(Set(2...6)) }
                shortcut(tr("Weekends")) { condition = .days([1, 7]) }
                Spacer(minLength: 0)
            }
        case .time(let start, let end):
            FromToRows(start: clockBinding(timeStart), end: clockBinding(timeEnd),
                       startTitle: tr("From"), endTitle: tr("To"))
            if end < start && end != 0 { EditorNote(text: tr("Ends next day")) }
            shortcut(String(format: tr("After %@"), RuleText.clock(22 * 60, locale: locale))) {
                condition = .time(start: 22 * 60, end: 0)
            }
        case .dates:
            DatePicker(tr("First day"), selection: dateBinding(first: true), displayedComponents: .date)
                .frame(minHeight: 44)
            DatePicker(tr("Last day"), selection: dateBinding(first: false), displayedComponents: .date)
                .frame(minHeight: 44)
        case .place, .country:
            // Only an existing rule can hold one before location arrives; it
            // is kept as it is (or removed with the trash button).
            ConditionRow(condition: condition)
        }
    }

    private func shortcut(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .demoraType(.meta)
            .foregroundStyle(accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private var days: Binding<Set<Int>> {
        Binding(get: {
            if case .days(let value) = condition { return value }
            return []
        }, set: { condition = .days($0) })
    }

    private var timeStart: Binding<Int> {
        Binding(get: {
            if case .time(let start, _) = condition { return start }
            return 0
        }, set: { value in
            if case .time(_, let end) = condition { condition = .time(start: value, end: end) }
        })
    }

    private var timeEnd: Binding<Int> {
        Binding(get: {
            if case .time(_, let end) = condition { return end }
            return 0
        }, set: { value in
            if case .time(let start, _) = condition { condition = .time(start: start, end: value) }
        })
    }

    /// Calendar days in the Gregorian calendar of the current zone, the way
    /// the evaluator reads them, whatever calendar the picker shows.
    private func dateBinding(first: Bool) -> Binding<Date> {
        let zone = TimeZone.current
        return Binding(get: {
            guard case .dates(let a, let b) = condition else { return Date() }
            let day = first ? a : b
            return ConditionalDay.gregorian(in: zone)
                .date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? Date()
        }, set: { date in
            guard case .dates(let a, let b) = condition else { return }
            let day = ConditionalDay.of(date, in: zone)
            condition = first ? .dates(first: day, last: b) : .dates(first: a, last: day)
        })
    }
}

// MARK: - One condition, read-only

/// Symbol and words for one condition, as the summary sheet lists them. The
/// check-in sheet adds its mark (✓ met, ✗ not met, ? can't tell, – not
/// needed) and the reason; "?" always counts as not met.
struct ConditionRow: View {
    @AppLoosen private var loosen
    @Environment(\.locale) private var locale
    let condition: ConditionalCondition
    var status: ConditionStatus? = nil
    var reason: String? = nil

    var body: some View {
        var calendar = Calendar.current
        calendar.locale = locale
        let line = ConditionalText.sheetLine(condition, translate: tr, locale: locale, calendar: calendar)
        return HStack(alignment: .firstTextBaseline, spacing: DemoraSpace.s) {
            Image(systemName: status.map(Self.mark) ?? ConditionalText.symbol(condition))
                .foregroundStyle(status.map(color) ?? Ink.inkSoft)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(line)
                    .demoraType(.body)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let reason, !reason.isEmpty {
                    Text(reason)
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([status.map { tr(ConditionalCheckIn.statusKey($0)) }, line, reason]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    private static func mark(_ status: ConditionStatus) -> String {
        switch status {
        case .met: return "checkmark.circle.fill"
        case .notMet: return "xmark.circle"
        case .unknown: return "questionmark.circle"
        case .notNeeded: return "minus.circle"
        }
    }

    private func color(_ status: ConditionStatus) -> Color {
        switch status {
        case .met: return Ink.free
        case .notMet, .unknown: return loosen
        case .notNeeded: return Ink.inkSoft
        }
    }
}

// MARK: - Add condition chooser

/// Rows with a title and one example line (Google Home). Place and Country
/// explain that they arrive in a later update.
struct ConditionChooser: View {
    let conditionCount: Int
    let onChoose: (ConditionKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.s) {
                Text(tr("Add condition"))
                    .demoraType(.hero)
                    .foregroundStyle(Ink.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, DemoraSpace.xxs)
                ForEach(ConditionKind.allCases, id: \.self) { kind in
                    row(kind, reason: ConditionKind.disabledReason(kind, conditionCount: conditionCount))
                }
            }
            .padding(DemoraSpace.xl)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.cardRaised.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func row(_ kind: ConditionKind, reason: String?) -> some View {
        Button { onChoose(kind) } label: {
            HStack(spacing: DemoraSpace.s) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Ink.ink)
                    .frame(width: 40, height: 40)
                    .background(Ink.card, in: Circle())
                    .overlay(Circle().strokeBorder(Ink.hairline, lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr(kind.titleKey)).demoraType(.cardTitle).foregroundStyle(Ink.ink)
                    Text(tr(reason ?? kind.exampleKey))
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
}
