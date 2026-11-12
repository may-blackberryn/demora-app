//
//  RuleEditors.swift
//  One plain page per rule editor (docs/rules-redesign.md §5.7): sections
//  in a fixed order, advanced options as rows that open sub-pages, and a
//  pinned Review change that opens the change receipt. The first problem
//  stopping a save shows above it; no editor states a delay itself.
//  Drafts, validity and change actions are the old editors', moved here.
//

import SwiftUI
import UIKit
import FamilyControls

// MARK: - Scaffold

enum EditorPresentation { case sheet, pushed }

/// The shared editor page. As a sheet it has its own navigation stack and a
/// Cancel that asks once before throwing away an edited draft; pushed, the
/// back button leaves it.
struct RuleEditorPage<Content: View>: View {
    @AppLoosen private var loosen
    @Environment(\.dismiss) private var dismiss
    let title: String
    var presentation: EditorPresentation = .sheet
    var isDirty = false
    /// The first problem, already in words; shown only once something changed.
    var problem: String? = nil
    var canReview = true
    /// A change for this rule already waits: the button gives way to one line.
    var waiting = false
    /// Paragraphs for the "?" help sheet, for the editors that need one.
    var help: [String]? = nil
    var reviewTitle: String = tr("Review change")
    let onReview: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var confirmDiscard = false
    @State private var showHelp = false

    var body: some View {
        switch presentation {
        case .sheet: NavigationStack { page }
        case .pushed: page
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                content()
            }
            .padding(.horizontal, DemoraSpace.pageGutter)
            .padding(.vertical, DemoraSpace.l)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if presentation == .sheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) {
                        if isDirty { confirmDiscard = true } else { dismiss() }
                    }
                }
            }
            if help != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showHelp = true } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel(tr("Help"))
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .interactiveDismissDisabled(presentation == .sheet && isDirty)
        .confirmationDialog(tr("Discard your changes?"), isPresented: $confirmDiscard,
                            titleVisibility: .visible) {
            Button(tr("Discard"), role: .destructive) { dismiss() }
            Button(tr("Keep editing"), role: .cancel) {}
        }
        .sheet(isPresented: $showHelp) {
            EditorHelpSheet(title: title, paragraphs: help ?? [])
        }
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            if waiting {
                Text(tr("A change is already waiting. Cancel it in Changes to make a different one."))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if isDirty, let problem {
                    Text(problem)
                        .demoraType(.meta)
                        .foregroundStyle(loosen)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(reviewTitle, action: onReview)
                    .buttonStyle(DemoraPrimaryButtonStyle())
                    .disabled(!canReview)
            }
        }
        .padding(.horizontal, DemoraSpace.pageGutter)
        .padding(.vertical, DemoraSpace.xs)
        .frame(maxWidth: DemoraSpace.maxContentWidth)
        .frame(maxWidth: .infinity)
        .background(Ink.paper)
    }
}

/// The short explanations that used to sit above an editor's content.
struct EditorHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let paragraphs: [String]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DemoraSpace.s) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, text in
                        Text(text)
                            .demoraType(.body)
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(DemoraSpace.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Ink.cardRaised.ignoresSafeArea())
            .casedNavigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// A plain section label over one paper card.
struct EditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            SectionHeader(title)
            VStack(alignment: .leading, spacing: DemoraSpace.s) {
                content()
            }
            .paperCard()
        }
    }
}

/// "Different limit per day · Off ›": an advanced option that opens a sub-page
/// inside the same editor. Its edits belong to the same draft.
struct EditorRow<Destination: View>: View {
    let title: String
    let value: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: DemoraSpace.s) {
                Text(title)
                    .demoraType(.body)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DemoraSpace.xs)
                Text(value)
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.inkSoft)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A sub-page of an editor: same paper and title style, no own button.
struct EditorSubPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                content()
            }
            .padding(.horizontal, DemoraSpace.pageGutter)
            .padding(.vertical, DemoraSpace.l)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One quiet line under a control.
struct EditorNote: View {
    let text: String
    var warning = false
    @AppLoosen private var loosen

    var body: some View {
        Text(text)
            .demoraType(.meta)
            .foregroundStyle(warning ? loosen : Ink.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Apps row

/// "Apps · 4 selected ›" with up to six of the chosen apps under it.
struct AppsRow: View {
    @AppAccent private var accent
    @EnvironmentObject private var model: AppModel
    var title: String = tr("Apps")
    @Binding var selection: FamilyActivitySelection
    @State private var showPicker = false

    private static let preview = 6

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            Button { showPicker = true } label: {
                HStack(spacing: DemoraSpace.s) {
                    Text(title).demoraType(.body).foregroundStyle(Ink.ink)
                    Spacer(minLength: DemoraSpace.xs)
                    Text(String(format: tr("%d selected"), RuleCounts(selection).total))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ink.inkSoft)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.authorized)
            if !model.authorized {
                EditorNote(text: tr("App selection is unavailable until Screen Time access is allowed."))
            }
            tokens
        }
        .sheet(isPresented: $showPicker) { AppPickerSheet(selection: $selection) }
    }

    @ViewBuilder private var tokens: some View {
        let categories = Array(selection.categoryTokens.prefix(Self.preview))
        let apps = Array(selection.applicationTokens.prefix(max(0, Self.preview - categories.count)))
        let sites = Array(selection.webDomainTokens.prefix(max(0, Self.preview - categories.count - apps.count)))
        let more = RuleCounts(selection).total - categories.count - apps.count - sites.count
        ForEach(categories, id: \.self) { Label($0).demoraType(.meta) }
        ForEach(apps, id: \.self) { Label($0).demoraType(.meta) }
        ForEach(sites, id: \.self) { Label($0).demoraType(.meta) }
        if more > 0 {
            Text(String(format: tr("and %d more"), more))
                .demoraType(.meta)
                .foregroundStyle(Ink.inkSoft)
        }
    }
}

// MARK: - Duration control

/// The value large, with − / + in 5-minute steps; tapping the value opens the
/// hours and minutes wheels for an exact length.
struct DurationControl: View {
    @AppAccent private var accent
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var minutes: Int
    var range: ClosedRange<Int>
    var step = 5
    /// What 0 means, when 0 is allowed ("Blocked all day").
    var zeroText: String? = nil
    @State private var showWheels = false

    private var valueText: String {
        if minutes == 0 { return zeroText ?? String(format: tr("%d min"), 0) }
        return RuleText.minutes(minutes, locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            let value = Button { showWheels.toggle() } label: {
                Text(valueText)
                    .demoraType(.timeLarge)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(valueText)
            .accessibilityHint(tr("Shows the hour and minute wheels"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: change(+step)
                case .decrement: change(-step)
                @unknown default: break
                }
            }
            if typeSize.isAccessibilitySize {
                value
                HStack { stepButton(-step); Spacer(); stepButton(+step) }
            } else {
                HStack(spacing: DemoraSpace.s) { stepButton(-step); value; stepButton(+step) }
            }
            if showWheels {
                DurationPicker(minutes: $minutes, maxHours: range.upperBound / 60,
                               minMinutes: range.lowerBound)
            }
        }
    }

    private func stepButton(_ delta: Int) -> some View {
        Button { change(delta) } label: {
            Image(systemName: delta < 0 ? "minus" : "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .background(Ink.card, in: Circle())
                .overlay(Circle().strokeBorder(Ink.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .modifier(RepeatOnHold())
        .disabled(delta < 0 ? minutes <= range.lowerBound : minutes >= range.upperBound)
        .accessibilityLabel(tr(delta < 0 ? "Less" : "More"))
    }

    /// Steps snap to the 5-minute grid, never past the range.
    private func change(_ delta: Int) {
        let snapped = delta > 0 ? (minutes / step + 1) * step
            : ((minutes + step - 1) / step - 1) * step
        let next = min(range.upperBound, max(range.lowerBound, snapped))
        guard next != minutes else { return }
        minutes = next
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// Holding − or + keeps stepping (iOS 17 and later).
private struct RepeatOnHold: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.buttonRepeatBehavior(.enabled)
        } else {
            content
        }
    }
}

/// Mutually exclusive choices as rows with a check, for labels too long for a
/// segmented control in every language.
struct ChoiceList<Value: Hashable>: View {
    @AppAccent private var accent
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let (value, title) = options[index]
                Button { selection = value } label: {
                    HStack(spacing: DemoraSpace.s) {
                        Image(systemName: selection == value ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(accent)
                            .accessibilityHidden(true)
                        Text(title).demoraType(.body).foregroundStyle(Ink.ink)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
    }
}

private func onOff(_ on: Bool) -> String { tr(on ? "On" : "Off") }

// MARK: - A. Daily limit

/// New or existing limit. Remove lives on the summary sheet (R6). The draft
/// and validity are the old editor's; `.configureLimit` keeps the rule's ID
/// and spent allowance.
struct LimitEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("limits.countingNoteDismissed") private var countingNoteDismissed = false

    let existing: AppLimit?
    @State private var name = ""
    @State private var selection = FamilyActivitySelection()
    @State private var minutes = 30
    @State private var weekdayEnabled = false
    @State private var weekdayMinutes: [Int: Int] = [:]
    @State private var splitEnabled = false
    @State private var splitCutoffHour = 12
    @State private var splitBeforeMinutes = 15
    @State private var splitThreePortions = true
    @State private var splitSecondCutoffHour = 18
    @State private var splitMiddleMinutes = 10
    @State private var splitCarryUnused = false
    @State private var extraEnabled = false
    @State private var extraSteps = [LimitExtraStep(minutes: 20, waitMinutes: 5),
                                     LimitExtraStep(minutes: 10, waitMinutes: 15)]
    @State private var receipt: ChangeReceiptRequest?

    init(existing: AppLimit?) {
        self.existing = existing
        guard let existing else { return }
        _minutes = State(initialValue: existing.minutesPerDay)
        _selection = State(initialValue: existing.selection)
        _weekdayEnabled = State(initialValue: !existing.weekdayMinutes.isEmpty)
        _weekdayMinutes = State(initialValue: existing.weekdayMinutes)
        _splitEnabled = State(initialValue: existing.split != nil)
        if let split = existing.split {
            let first = min(22, max(1, split.cutoffMinutes / 60))
            _splitCutoffHour = State(initialValue: first)
            _splitBeforeMinutes = State(initialValue: split.beforeMinutes)
            _splitThreePortions = State(initialValue: split.secondCutoffMinutes != nil)
            _splitSecondCutoffHour = State(initialValue: split.secondCutoffMinutes.map { $0 / 60 }
                                            ?? min(23, max(18, first + 1)))
            _splitMiddleMinutes = State(initialValue: split.middleMinutes ?? 10)
            _splitCarryUnused = State(initialValue: split.carryUnused)
        }
        _extraEnabled = State(initialValue: existing.extraTime != nil)
        if let extra = existing.extraTime {
            _extraSteps = State(initialValue: extra.effectiveSteps)
        }
    }

    private var problem: EditorProblem? {
        EditorValidation.limit(name: name, existing: existing, draft: draftLimit, minutes: minutes,
                               extraEnabled: extraEnabled, extraSteps: extraSteps,
                               overrides: model.state.overrides)
    }

    private var isDirty: Bool {
        if let existing { return draftLimit != existing }
        return !name.isEmpty || EditorValidation.hasSelection(selection) || minutes != 30
            || weekdayEnabled || splitEnabled || extraEnabled
    }

    private var waiting: Bool {
        existing.map { RulePending.blocksEdit(of: .limit($0.id), pending: model.state.pending) } ?? false
    }

    var body: some View {
        RuleEditorPage(title: existing?.name ?? tr("New daily limit"),
                       isDirty: isDirty,
                       problem: problem?.messageKey.map(tr),
                       canReview: problem == nil,
                       waiting: waiting,
                       onReview: review) {
            if existing == nil {
                EditorSection(tr("Name")) {
                    TextField(tr("e.g. Instagram"), text: $name)
                        .demoraType(.cardTitle)
                        .frame(minHeight: 44)
                }
            }
            EditorSection(tr("What")) {
                AppsRow(selection: $selection)
                if let existing, existing.selection != selection {
                    EditorNote(text: tr("Changing apps always counts as a looser change."))
                }
            }
            EditorSection(tr("How much")) {
                DurationControl(minutes: $minutes, range: 0...720, zeroText: tr("Blocked all day"))
                if #unavailable(iOS 17.4), !countingNoteDismissed {
                    DismissibleNote(
                        text: tr("Heads up: on your iOS version, a limit only counts screen time from the moment you add it — time you already spent earlier today isn't included. Update to iOS 17.4 or later for exact daily counting."),
                        onDismiss: { countingNoteDismissed = true })
                }
                EditorRow(title: tr("Different limit per day"), value: onOff(weekdayEnabled)) {
                    WeekdayBudgetsPage(enabled: $weekdayEnabled, weekdayMinutes: $weekdayMinutes,
                                       minutes: minutes)
                }
                EditorRow(title: tr("Split the day"), value: onOff(splitEnabled)) {
                    SplitBudgetPage(minutes: minutes, enabled: $splitEnabled,
                                    cutoffHour: $splitCutoffHour, beforeMinutes: $splitBeforeMinutes,
                                    threePortions: $splitThreePortions,
                                    secondCutoffHour: $splitSecondCutoffHour,
                                    middleMinutes: $splitMiddleMinutes, carryUnused: $splitCarryUnused)
                }
            }
            EditorSection(tr("Extra time")) {
                EditorRow(title: tr("Extra time"),
                          value: extraEnabled ? String(format: tr("%d uses"), extraSteps.count) : onOff(false)) {
                    ExtraTimePage(enabled: $extraEnabled, steps: $extraSteps)
                }
            }
        }
        .changeReceipt($receipt) { dismiss() }
        .onChange(of: minutes) { budget in
            splitBeforeMinutes = min(splitBeforeMinutes, budget)
            splitMiddleMinutes = min(splitMiddleMinutes, max(0, budget - splitBeforeMinutes))
        }
    }

    private func review() {
        guard problem == nil else { return }
        receipt = ChangeReceiptRequest(action: existing != nil ? .configureLimit(draftLimit)
                                                                : .addLimit(draftLimit))
    }

    private var draftLimit: AppLimit {
        var draft = existing ?? AppLimit(name: name.isEmpty ? tr("Limit") : name,
                                         selection: selection, minutesPerDay: minutes)
        draft.selection = selection
        draft.minutesPerDay = minutes
        draft.weekdayMinutes = weekdayEnabled ? weekdayMinutes : [:]
        // Wake-up settings now belong to Schedules. Keep legacy gates until migration.
        draft.wakeDelayMinutes = existing?.wakeDelayMinutes
        draft.split = splitEnabled
            ? LimitSplit(cutoffMinutes: splitCutoffHour * 60,
                         beforeMinutes: min(splitBeforeMinutes, minutes),
                         carryUnused: splitCarryUnused,
                         secondCutoffMinutes: splitThreePortions
                            ? max(splitCutoffHour + 1, splitSecondCutoffHour) * 60 : nil,
                         middleMinutes: splitThreePortions
                            ? min(splitMiddleMinutes,
                                  max(0, minutes - splitBeforeMinutes)) : nil)
            : nil
        draft.pacing = nil
        if extraEnabled, let first = extraSteps.first {
            draft.extraTime = LimitExtraTime(minutesPerUse: first.minutes,
                                             usesPerDay: extraSteps.count,
                                             waitMinutes: first.waitMinutes,
                                             steps: extraSteps)
        } else {
            draft.extraTime = nil
        }
        return draft
    }
}

private struct WeekdayBudgetsPage: View {
    @Environment(\.locale) private var locale
    @AppStorage("weekStartMonday") private var weekStartMonday = false
    @Binding var enabled: Bool
    @Binding var weekdayMinutes: [Int: Int]
    let minutes: Int
    @State private var open: Int?

    var body: some View {
        let calendar = DayChipsCalendar.calendar(locale: locale, weekStartMonday: weekStartMonday)
        EditorSubPage(title: tr("Different limit per day")) {
            EditorSection(tr("How much")) {
                Toggle(tr("Different limit per day"), isOn: $enabled)
                    .frame(minHeight: 44)
                if enabled {
                    ForEach(DayChipsCalendar.orderedDays(firstWeekday: calendar.firstWeekday), id: \.self) { day in
                        let value = weekdayMinutes[day] ?? minutes
                        Button { open = open == day ? nil : day } label: {
                            HStack {
                                Text(calendar.weekdaySymbols[day - 1]).demoraType(.body).foregroundStyle(Ink.ink)
                                Spacer()
                                Text(value == 0 ? tr("Blocked all day") : RuleText.minutes(value, locale: locale))
                                    .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if open == day {
                            DurationControl(minutes: Binding(get: { weekdayMinutes[day] ?? minutes },
                                                             set: { weekdayMinutes[day] = $0 }),
                                            range: 0...720, zeroText: tr("Blocked all day"))
                        }
                    }
                    Button(tr("Same every day")) { enabled = false }
                        .buttonStyle(.plain)
                        .font(DemoraType.button)
                        .frame(minHeight: 44)
                }
                EditorNote(text: tr("Each weekday's budget replaces the daily limit for that day."))
            }
        }
        .onChange(of: enabled) { on in
            if on && weekdayMinutes.isEmpty {
                weekdayMinutes = Dictionary(uniqueKeysWithValues: (1...7).map { ($0, minutes) })
            }
        }
    }
}

private struct SplitBudgetPage: View {
    @AppAccent private var accent
    @Environment(\.locale) private var locale
    let minutes: Int
    @Binding var enabled: Bool
    @Binding var cutoffHour: Int
    @Binding var beforeMinutes: Int
    @Binding var threePortions: Bool
    @Binding var secondCutoffHour: Int
    @Binding var middleMinutes: Int
    @Binding var carryUnused: Bool

    private var finalMinutes: Int {
        max(0, minutes - beforeMinutes - (threePortions ? middleMinutes : 0))
    }

    var body: some View {
        EditorSubPage(title: tr("Split the day")) {
            EditorSection(tr("Split")) {
                Toggle(tr("Split daily budget"), isOn: $enabled).frame(minHeight: 44)
                if enabled {
                    dayBar
                    Toggle(tr("Three time portions"), isOn: $threePortions)
                        .onChange(of: threePortions) { on in
                            if on {
                                cutoffHour = min(cutoffHour, 21)
                                secondCutoffHour = max(cutoffHour + 1, secondCutoffHour)
                                middleMinutes = min(middleMinutes, max(0, minutes - beforeMinutes))
                            }
                        }
                    Picker(tr("First cutoff"), selection: $cutoffHour) {
                        ForEach(1...(threePortions ? 21 : 22), id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .onChange(of: cutoffHour) { hour in
                        secondCutoffHour = max(secondCutoffHour, hour + 1)
                    }
                    Stepper(value: $beforeMinutes, in: 0...min(720, minutes)) {
                        Text(String(format: tr("First portion: %d minutes"), beforeMinutes))
                    }
                    .onChange(of: beforeMinutes) { first in
                        middleMinutes = min(middleMinutes, max(0, minutes - first))
                    }
                    if threePortions {
                        Picker(tr("Second cutoff"), selection: $secondCutoffHour) {
                            ForEach((cutoffHour + 1)...23, id: \.self) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour)
                            }
                        }
                        Stepper(value: $middleMinutes, in: 0...max(0, minutes - beforeMinutes)) {
                            Text(String(format: tr("Middle portion: %d minutes"), middleMinutes))
                        }
                    }
                    Text(String(format: tr("Final portion: %d minutes"), finalMinutes))
                        .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                    Toggle(tr("Carry unused early minutes forward"), isOn: $carryUnused)
                }
                EditorNote(text: tr("Divide today's usage into time-of-day portions. Unused minutes can carry into later portions if you choose."))
            }
            EditorNote(text: tr("iOS Screen Time callbacks can arrive late. Wake-up, split, and extra-time boundaries may not switch at the exact minute."))
        }
    }

    /// The day from midnight to midnight, cut at each cutoff, each portion
    /// labelled with its minutes.
    private var dayBar: some View {
        let cuts = threePortions ? [0, cutoffHour, max(cutoffHour + 1, secondCutoffHour), 24] : [0, cutoffHour, 24]
        let amounts = threePortions ? [beforeMinutes, middleMinutes, finalMinutes] : [beforeMinutes, max(0, minutes - beforeMinutes)]
        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<amounts.count, id: \.self) { index in
                    let width = CGFloat(cuts[index + 1] - cuts[index]) / 24 * (geo.size.width - CGFloat(amounts.count - 1) * 2)
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(accent.opacity(0.18 + 0.22 * Double(index)))
                            .frame(height: 10)
                        Text(RuleText.minutes(amounts[index], locale: locale))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Ink.inkSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(width: max(0, width))
                }
            }
        }
        .frame(height: 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(amounts.map { RuleText.minutes($0, locale: locale) }.joined(separator: ", "))
    }
}

private struct ExtraTimePage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.locale) private var locale
    @Binding var enabled: Bool
    @Binding var steps: [LimitExtraStep]

    var body: some View {
        EditorSubPage(title: tr("Extra time")) {
            EditorSection(tr("Extra time")) {
                Toggle(tr("Manual extra time"), isOn: $enabled).frame(minHeight: 44)
            }
            if enabled {
                ForEach(steps.indices, id: \.self) { index in
                    // Rows can outlive a removed step for one update; read
                    // through `step(_:)`, never `steps[index]` directly.
                    EditorSection(RuleSummaryFacts.extraUseText(index,
                        ExtraUseBuilder.use(step(index), overrides: model.state.overrides),
                        translate: tr, locale: locale)) {
                        useEditor(index)
                    }
                }
                if steps.count < 5 {
                    Button {
                        steps.append(LimitExtraStep(minutes: 10, waitMinutes: 15))
                    } label: {
                        Label(tr("Add another use"), systemImage: "plus.circle")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            EditorNote(text: tr("Extra time opens only after the whole day's budget is spent, and resets at midnight."))
        }
    }

    @ViewBuilder private func useEditor(_ index: Int) -> some View {
        Stepper(value: field(index, \.minutes),
                in: 1...120) {
            Text(String(format: tr("Extra usage: %d minutes"), step(index).minutes))
        }
        Menu {
            Button(tr("Wait")) {
                update(index) { $0.passwordPolicyID = nil }
                update(index) { $0.phrasePolicyID = nil }
                update(index) { $0.contactRequired = false }
            }
            ForEach(model.state.overrides.passwordPolicies.filter { $0.allowed.contains(.extraTime) }) { policy in
                Button(policy.name) {
                    update(index) { $0.passwordPolicyID = policy.id }
                    update(index) { $0.phrasePolicyID = nil }
                    update(index) { $0.contactRequired = false }
                }
            }
            ForEach(model.state.overrides.phrasePolicies.filter { $0.allowed.contains(.extraTime) }) { policy in
                Button(policy.name) {
                    update(index) { $0.phrasePolicyID = policy.id }
                    update(index) { $0.passwordPolicyID = nil }
                    update(index) { $0.contactRequired = false }
                }
            }
            if model.state.overrides.contactsEnabled
                && model.state.overrides.contacts.contains(where: { $0.isUsable && $0.allowed.contains(.extraTime) }) {
                Button(tr("Ask a trusted contact")) {
                    update(index) { $0.contactRequired = true }
                    update(index) { $0.passwordPolicyID = nil }
                    update(index) { $0.phrasePolicyID = nil }
                }
            }
        } label: {
            let passwordName = model.state.overrides.passwordPolicies.first {
                $0.id == step(index).passwordPolicyID }?.name
            let phraseName = model.state.overrides.phrasePolicies.first {
                $0.id == step(index).phrasePolicyID }?.name
            Label(step(index).contactRequired ? tr("Ask a trusted contact")
                  : passwordName ?? phraseName ?? tr("Wait"),
                  systemImage: "chevron.down")
                .frame(minHeight: 44)
        }
        if step(index).passwordPolicyID == nil && step(index).phrasePolicyID == nil
            && !step(index).contactRequired {
            Stepper(value: field(index, \.waitMinutes),
                    in: 1...1440) {
                Text(String(format: tr("Wait: %d minutes"), step(index).waitMinutes))
            }
        }
        if steps.count > 1 {
            Button(tr("Remove this use"), role: .destructive) {
                if steps.indices.contains(index) { steps.remove(at: index) }
            }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
        }
    }

    private func step(_ index: Int) -> LimitExtraStep {
        steps.indices.contains(index) ? steps[index] : LimitExtraStep(minutes: 1, waitMinutes: 1)
    }

    private func update(_ index: Int, _ change: (inout LimitExtraStep) -> Void) {
        guard steps.indices.contains(index) else { return }
        change(&steps[index])
    }

    private func field(_ index: Int, _ keyPath: WritableKeyPath<LimitExtraStep, Int>) -> Binding<Int> {
        Binding(get: { step(index)[keyPath: keyPath] },
                set: { value in update(index) { $0[keyPath: keyPath] = value } })
    }
}

// MARK: - Shared time rows

/// From and To joined by a dotted thread.
struct FromToRows: View {
    @Binding var start: Date
    @Binding var end: Date
    let startTitle: String
    let endTitle: String
    var components: DatePickerComponents = .hourAndMinute
    var startRange: PartialRangeFrom<Date>? = nil

    var body: some View {
        HStack(alignment: .center, spacing: DemoraSpace.s) {
            VStack(spacing: 0) {
                Circle().stroke(Ink.inkSoft, lineWidth: 1.5).frame(width: 9, height: 9)
                Line()
                    .stroke(Ink.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                    .frame(width: 1.5)
                Circle().stroke(Ink.inkSoft, lineWidth: 1.5).frame(width: 9, height: 9)
            }
            .frame(width: 12)
            .padding(.vertical, 18)
            .accessibilityHidden(true)
            VStack(spacing: DemoraSpace.xs) {
                if let startRange {
                    DatePicker(startTitle, selection: $start, in: startRange, displayedComponents: components)
                        .frame(minHeight: 44)
                    DatePicker(endTitle, selection: $end, in: start..., displayedComponents: components)
                        .frame(minHeight: 44)
                } else {
                    DatePicker(startTitle, selection: $start, displayedComponents: components)
                        .frame(minHeight: 44)
                    DatePicker(endTitle, selection: $end, displayedComponents: components)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            return path
        }
    }
}

// MARK: - B. Repeating block or free period (new)

struct ScheduleEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    private enum Repeats: Hashable { case daily, some, monthly }
    private enum Monthly: Hashable { case day, ordinal }

    @State private var name = ""
    @State private var isFree = false
    @State private var mode: ScheduleMode = .blockAllExcept
    @State private var selection = FamilyActivitySelection()
    @State private var start = defaultTime(hour: 22)
    @State private var end = defaultTime(hour: 7)
    @State private var repeats: Repeats = .daily
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var monthly: Monthly = .day
    @State private var monthDay = 1
    @State private var ordinal = 1
    @State private var ordinalWeekday = 2
    @State private var receipt: ChangeReceiptRequest?
    @State private var showConflicts = false

    private var recurrence: Recurrence {
        switch repeats {
        case .daily: return .daily
        case .some: return .weekly(weekdays)
        case .monthly:
            return monthly == .day ? .monthlyDay(monthDay)
                : .monthlyOrdinal(weekday: ordinalWeekday, ordinal: ordinal)
        }
    }

    private var draft: BlockSchedule {
        BlockSchedule(name: name.isEmpty ? tr("Schedule") : name, mode: mode, selection: selection,
                      startMinutes: minutesOfDay(start), endMinutes: minutesOfDay(end),
                      recurrence: recurrence)
    }

    private var exemptDraft: ExemptSchedule {
        ExemptSchedule(name: name.isEmpty ? tr("Free period") : name,
                       startMinutes: minutesOfDay(start), endMinutes: minutesOfDay(end),
                       recurrence: recurrence)
    }

    private var problem: EditorProblem? {
        EditorValidation.repeating(name: name, start: minutesOfDay(start), end: minutesOfDay(end),
                                   recurrence: recurrence, isFree: isFree, draft: draft)
    }

    private var isDirty: Bool {
        !name.isEmpty || isFree || EditorValidation.hasSelection(selection) || repeats != .daily
            || minutesOfDay(start) != 22 * 60 || minutesOfDay(end) != 7 * 60
    }

    var body: some View {
        var calendar = Calendar.current
        calendar.locale = locale
        return RuleEditorPage(title: tr("Repeating block"), isDirty: isDirty,
                              problem: problem?.messageKey.map(tr), canReview: problem == nil,
                              onReview: review) {
            EditorSection(tr("Name")) {
                TextField(tr("e.g. Bedtime"), text: $name)
                    .demoraType(.cardTitle)
                    .frame(minHeight: 44)
            }
            EditorSection(tr("Type")) {
                Picker(tr("Type"), selection: $isFree) {
                    Text(tr("Block")).tag(false)
                    Text(tr("Free period")).tag(true)
                }
                .pickerStyle(.segmented)
                if isFree {
                    Text(tr("Limits won't block and usage won't count during this time."))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.free)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !isFree {
                EditorSection(tr("What")) {
                    Picker(tr("What"), selection: $mode) {
                        Text(tr("Only these apps")).tag(ScheduleMode.blockSelected)
                        Text(tr("All except these")).tag(ScheduleMode.blockAllExcept)
                    }
                    .pickerStyle(.segmented)
                    AppsRow(title: mode == .blockAllExcept ? tr("Apps that stay usable") : tr("Apps to block"),
                            selection: $selection)
                }
            }
            EditorSection(tr("When")) {
                FromToRows(start: $start, end: $end, startTitle: tr("From"), endTitle: tr("To"))
                if minutesOfDay(end) < minutesOfDay(start) {
                    EditorNote(text: tr("Ends next day"))
                }
                Picker(tr("Repeats"), selection: $repeats) {
                    Text(tr("Every day")).tag(Repeats.daily)
                    Text(tr("Some days")).tag(Repeats.some)
                    Text(tr("Monthly")).tag(Repeats.monthly)
                }
                .pickerStyle(.segmented)
                switch repeats {
                case .daily:
                    EmptyView()
                case .some:
                    DayChips(selection: $weekdays)
                case .monthly:
                    Picker(tr("Repeats"), selection: $monthly) {
                        Text(tr("Day of month")).tag(Monthly.day)
                        Text(tr("Nth weekday")).tag(Monthly.ordinal)
                    }
                    .pickerStyle(.menu)
                    if monthly == .day {
                        Stepper(String(format: tr("Day %d of every month"), monthDay), value: $monthDay, in: 1...31)
                    } else {
                        Picker(tr("Which one"), selection: $ordinal) {
                            ForEach(1...4, id: \.self) { Text("#\($0)").tag($0) }
                        }
                        Picker(tr("Weekday"), selection: $ordinalWeekday) {
                            ForEach(1...7, id: \.self) { day in
                                Text(calendar.weekdaySymbols[day - 1]).tag(day)
                            }
                        }
                    }
                }
                if problem == .monthlyMidnight {
                    EditorNote(text: tr("Monthly schedules can't cross midnight — set the end time after the start time."),
                               warning: true)
                }
            }
            overlapNote(calendar: calendar)
        }
        .changeReceipt($receipt) { dismiss() }
    }

    /// Brick-style: what this draft would overlap, never blocking the save.
    @ViewBuilder private func overlapNote(calendar: Calendar) -> some View {
        let notes = problem == nil
            ? (isFree ? DraftOverlap.notes(state: model.state, draft: exemptDraft, now: Date(), calendar: calendar)
                      : DraftOverlap.notes(state: model.state, draft: draft, now: Date(), calendar: calendar))
            : []
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                ForEach(notes, id: \.name) { note in
                    EditorNote(text: String(format: tr("Overlaps with %@ on %@."), note.name,
                        RuleText.days(.some(note.weekdays), translate: tr, calendar: calendar)))
                }
                NavigationLink {
                    ScheduleConflictsView()
                } label: {
                    HStack(spacing: DemoraSpace.xxs) {
                        Text(tr("See conflicts"))
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .demoraType(.meta)
                    .frame(minHeight: 44)
                }
            }
        }
    }

    private func review() {
        guard problem == nil else { return }
        receipt = ChangeReceiptRequest(action: isFree ? .addExemption(exemptDraft) : .addSchedule(draft))
    }
}

// MARK: - B2. Edit the apps of a repeating block

/// Only the selection is editable. Read the current rule for validation so a
/// stale sheet cannot recreate a deleted schedule or overwrite other fields.
struct ScheduleSelectionEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let schedule: BlockSchedule
    @State private var selection: FamilyActivitySelection
    @State private var receipt: ChangeReceiptRequest?

    init(schedule: BlockSchedule) {
        self.schedule = schedule
        _selection = State(initialValue: schedule.selection)
    }

    private var current: BlockSchedule? {
        model.state.schedules.first { $0.id == schedule.id }
    }

    private var action: ChangeAction {
        .updateScheduleSelection(id: schedule.id, selection: selection)
    }

    private var pending: Bool {
        RulePending.blocksEdit(of: .schedule(schedule.id), pending: model.state.pending)
    }

    private var isValid: Bool {
        guard let current else { return false }
        return current.selection != selection
            && current.acceptsSelection(selection)
            && !pending
    }

    var body: some View {
        var calendar = Calendar.current
        calendar.locale = locale
        let shown = current ?? schedule
        return RuleEditorPage(title: shown.name, isDirty: selection != schedule.selection,
                              problem: shown.acceptsSelection(selection) ? nil : tr("Choose at least one app."),
                              canReview: isValid, waiting: pending, onReview: review) {
            EditorSection(tr("When")) {
                FactRow(label: tr("Type"), value: shown.mode == .blockAllExcept
                        ? tr("All except these") : tr("Only these apps"))
                FactRow(label: tr("When"), value: RuleText.days(RuleDays(shown.recurrence), translate: tr, calendar: calendar)
                        + " " + RuleText.clock(shown.startMinutes, locale: locale) + "–"
                        + RuleText.clock(shown.endMinutes, locale: locale))
            }
            EditorSection(tr("What")) {
                AppsRow(title: shown.mode == .blockAllExcept ? tr("Apps that stay usable") : tr("Apps to block"),
                        selection: $selection)
                EditorNote(text: tr("Changing apps always waits your looser delay. The current block stays in effect until then."))
            }
        }
        .changeReceipt($receipt) { dismiss() }
    }

    private func review() {
        guard isValid else { return }
        receipt = ChangeReceiptRequest(action: action)
    }
}

// MARK: - C. Plan a block (new)

struct PlannedEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: PlannedKind = .free
    @State private var selection = FamilyActivitySelection()
    @State private var startsAt = Date().addingTimeInterval(3600)
    @State private var endsAt = Date().addingTimeInterval(3 * 3600)
    @State private var receipt: ChangeReceiptRequest?

    private var draft: PlannedWindow {
        PlannedWindow(name: name.isEmpty ? tr("Planned window") : name,
                      kind: kind, selection: selection,
                      startsAt: startsAt, endsAt: endsAt)
    }

    private var problem: EditorProblem? {
        EditorValidation.planned(name: name, kind: kind, selection: selection,
                                 startsAt: startsAt, endsAt: endsAt)
    }

    private var isDirty: Bool {
        !name.isEmpty || kind != .free || EditorValidation.hasSelection(selection)
    }

    var body: some View {
        RuleEditorPage(title: tr("Plan a block"), isDirty: isDirty,
                       problem: problem?.messageKey.map(tr), canReview: problem == nil,
                       onReview: review) {
            EditorSection(tr("Name")) {
                TextField(tr("e.g. Airport, weekend trip"), text: $name)
                    .demoraType(.cardTitle)
                    .frame(minHeight: 44)
            }
            EditorSection(tr("Type")) {
                ChoiceList(selection: $kind, options: [
                    (.blockSelected, tr("Only these apps")),
                    (.blockAllExcept, tr("All except these")),
                    (.free, tr("Free period")),
                ])
                if kind == .free {
                    EditorNote(text: tr("Limits won't block and usage won't count during this window."))
                }
            }
            if kind != .free {
                EditorSection(tr("What")) {
                    AppsRow(title: kind == .blockAllExcept ? tr("Apps that stay usable") : tr("Apps to block"),
                            selection: $selection)
                }
            }
            EditorSection(tr("When")) {
                FromToRows(start: $startsAt, end: $endsAt, startTitle: tr("Starts"), endTitle: tr("Ends"),
                           components: [.date, .hourAndMinute], startRange: Date()...)
            }
        }
        .changeReceipt($receipt) { dismiss() }
    }

    private func review() {
        guard problem == nil else { return }
        receipt = ChangeReceiptRequest(action: .addPlanned(draft))
    }
}

// MARK: - D. Block now / session

struct SessionStartView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: SessionKind = .block
    @State private var selection = FamilyActivitySelection()
    @State private var minutes = 60
    @State private var receipt: ChangeReceiptRequest?

    private var draft: ChangeAction {
        let fallback = kind == .free ? kind.label : "\(kind.label) session"
        return .startSession(name: name.isEmpty ? fallback : name,
                             kind: kind,
                             // A free period frees everything, so its selection
                             // is irrelevant — don't carry stray picks into it.
                             selection: kind == .free ? FamilyActivitySelection() : selection,
                             minutes: minutes)
    }

    private var problem: EditorProblem? { EditorValidation.session(kind: kind, selection: selection) }

    private var isDirty: Bool {
        !name.isEmpty || kind != .block || EditorValidation.hasSelection(selection) || minutes != 60
    }

    var body: some View {
        RuleEditorPage(title: tr("Block now"), isDirty: isDirty,
                       problem: problem?.messageKey.map(tr), canReview: problem == nil,
                       onReview: review) {
            EditorSection(tr("Name")) {
                TextField(tr("Deep work"), text: $name)
                    .demoraType(.cardTitle)
                    .frame(minHeight: 44)
            }
            EditorSection(tr("Type")) {
                Picker(tr("Type"), selection: $kind) {
                    Text(tr("Block")).tag(SessionKind.block)
                    Text(tr("Unblock")).tag(SessionKind.unblock)
                    Text(tr("Free")).tag(SessionKind.free)
                }
                .pickerStyle(.segmented)
                if kind == .unblock {
                    EditorNote(text: tr("Temporarily lifts limits, schedules, and block sessions for the chosen apps."))
                } else if kind == .free {
                    EditorNote(text: tr("Temporarily lifts everything — no app blocks apply, and usage during the free period doesn't count toward your limits."))
                }
            }
            if kind != .free {
                EditorSection(tr("What")) {
                    AppsRow(title: kind == .block ? tr("Apps to block") : tr("Apps to unblock"),
                            selection: $selection)
                }
            }
            EditorSection(tr("How long")) {
                DurationControl(minutes: $minutes, range: 1...1440)
            }
        }
        .changeReceipt($receipt) { dismiss() }
    }

    private func review() {
        guard problem == nil else { return }
        receipt = ChangeReceiptRequest(action: draft,
                                       note: String(format: tr("Then runs for %d min."), minutes))
    }
}
