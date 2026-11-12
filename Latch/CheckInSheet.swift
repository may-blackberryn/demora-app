//
//  CheckInSheet.swift
//  The When & where check-in (docs/conditional-sessions-redesign.md §5.5):
//  checks day, time and dates on the guarded clock, shows ✓ / ✗ / ? per
//  condition with its reason, and when the rule is met starts free time
//  through `ChangeEngine.startConditionalSessionOffMain`, which validates
//  everything again. No location in this build (C15 step 3): a rule that
//  needs a place or country says so and can't start. A condition has no
//  way around it here: no skip, no Apply now, no password, phrase or contact.
//

import SwiftUI
import UIKit

/// A rule to check in on, as a sheet item.
struct CheckInRequest: Identifiable, Equatable {
    let id = UUID()
    let ruleID: UUID
}

struct CheckInSheet: View {
    @AppAccent private var accent
    @AppLoosen private var loosen
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let ruleID: UUID
    /// The last check. Read in events, never while drawing; dropped with the sheet.
    @State private var check: CheckInResult?
    @State private var attempt: CheckInAttempt?
    @State private var minutes = 60
    /// Set before the start leaves the main actor, so a second hold or a
    /// confirmation tap can't send another request.
    @State private var starting = false

    private var live: ConditionalRule? { model.state.conditionalRules.first { $0.id == ruleID } }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            ScrollView {
                content(now: context.date)
                    .padding(DemoraSpace.xl)
                    .frame(maxWidth: DemoraSpace.maxContentWidth)
                    .frame(maxWidth: .infinity)
            }
            // A check past its freshness, or from before midnight, is run
            // again on its own so the sheet never shows a stale verdict.
            .onChange(of: context.date) { _ in
                if let check, !starting,
                   ConditionalCheckIn.needsRecheck(check, live: live,
                                                   clock: ConditionalClockInput.current(for: model.state)) {
                    runCheck(model.state, announce: false)
                }
            }
        }
        .background(Ink.cardRaised.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear { runCheck(model.state, announce: true) }
        // `$state` publishes before the property changes: read the new value.
        .onReceive(model.$state) { state in
            guard let check, !starting else { return }
            let rule = state.conditionalRules.first { $0.id == ruleID }
            // An edit that landed (or a removal) makes this check stale.
            if rule.map({ $0.revision != check.rule.revision || !$0.sameConfiguration(as: check.rule) }) ?? true {
                attempt = nil
                runCheck(state, announce: false)
            }
        }
    }

    // MARK: Content

    @ViewBuilder private func content(now: Date) -> some View {
        let screen = ConditionalCheckIn.screen(check: check, live: live, sessions: model.state.sessions,
                                               attempt: attempt, now: now)
        VStack(alignment: .leading, spacing: DemoraSpace.m) {
            VStack(alignment: .leading, spacing: DemoraSpace.xs) {
                Text(live?.name ?? check?.rule.name ?? "")
                    .demoraType(.label)
                    .foregroundStyle(Ink.inkSoft)
                hero(screen, now: now)
                    .demoraType(.hero)
                    .foregroundStyle(heroColor(screen))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let detail = ConditionalCheckIn.detailKey(screen) {
                    Text(tr(detail))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            if let check, showsRows(screen) {
                dashed
                Text(tr(ConditionalCheckIn.needsLine(check.rule)))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                VStack(alignment: .leading, spacing: DemoraSpace.s) {
                    ForEach(Array(zip(check.rule.conditions, check.evaluation.results).enumerated()),
                            id: \.offset) { _, pair in
                        ConditionRow(condition: pair.0, status: pair.1.status,
                                     reason: ConditionalCheckIn.reason(pair.1, condition: pair.0, translate: tr,
                                                                       locale: locale, calendar: calendar))
                    }
                }
                .transition(.opacity)
            }
            dashed
            actions(screen, now: now)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: screen)
    }

    private func hero(_ screen: CheckInScreen, now: Date) -> Text {
        let key = ConditionalCheckIn.heroKey(screen)
        if case .running(let until) = screen {
            return TodaySentence.text(tr(key), [.init(text: time(until, now: now), color: Ink.free)])
        }
        return Text(tr(key))
    }

    private func heroColor(_ screen: CheckInScreen) -> Color {
        switch screen {
        case .met, .running: return Ink.free
        default: return Ink.ink
        }
    }

    private func showsRows(_ screen: CheckInScreen) -> Bool {
        switch screen {
        case .gone, .changed, .running, .checking, .refused, .queued: return false
        default: return true
        }
    }

    private var dashed: some View {
        Rectangle()
            .stroke(Ink.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func time(_ date: Date, now: Date) -> String {
        TodayTimeText.short(date, now: now, calendar: calendar, locale: locale)
    }

    // MARK: Actions

    @ViewBuilder private func actions(_ screen: CheckInScreen, now: Date) -> some View {
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            switch screen {
            case .met(let cap):
                let chosen = ConditionalCheckIn.requestMinutes(chosen: minutes, cap: cap)
                Text(tr("How long")).demoraType(.meta).foregroundStyle(Ink.inkSoft)
                DurationControl(minutes: lengthBinding(cap: cap), range: min(5, cap)...cap)
                if let check, let usesPerDay = usesPerDay(check.rule) {
                    Text(String(format: tr("Ends at %@ · %d of %d today"),
                                time(ConditionalCheckIn.endsAt(minutes: chosen, windowEnd: check.wallWindowEnd,
                                                               now: now), now: now),
                                (check.used ?? 0) + 1, usesPerDay))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HoldButton(tr("Hold to start free time"), role: .free,
                           confirmationTitle: tr("Start free time now?")) { start(cap: cap) }
                    .disabled(starting)
                if starting { ProgressView().frame(maxWidth: .infinity) }
                quiet(tr("Not now")) { dismiss() }
            case .running, .gone, .queued:
                primary(tr("Done")) { dismiss() }
            case .checking:
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
            default:
                // Not met, used up, needs location, changed, refused: no way
                // around a condition, only checking again.
                primary(tr("Try again")) {
                    attempt = nil
                    runCheck(model.state, announce: true)
                }
                quiet(tr("Done")) { dismiss() }
            }
        }
    }

    private func usesPerDay(_ rule: ConditionalRule) -> Int? {
        if case .freeTime(_, _, _, let uses) = rule.outcome { return uses }
        return nil
    }

    /// The chosen length, kept within what the rule allows now.
    private func lengthBinding(cap: Int) -> Binding<Int> {
        Binding(get: { ConditionalCheckIn.requestMinutes(chosen: minutes, cap: cap) },
                set: { minutes = ConditionalCheckIn.requestMinutes(chosen: $0, cap: cap) })
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(DemoraPrimaryButtonStyle())
    }

    private func quiet(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(DemoraType.button)
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }

    // MARK: Events

    /// Day, time and dates on the guarded clock, from saved state. Location is
    /// never read here. `announce` adds the one verdict haptic (spec §9).
    private func runCheck(_ state: LatchState, announce: Bool) {
        guard let rule = state.conditionalRules.first(where: { $0.id == ruleID }) else {
            check = nil
            return
        }
        let result = CheckInResult.make(rule: rule, state: state,
                                        clock: ConditionalClockInput.current(for: state))
        if check == nil, case .freeTime(_, _, let maxMinutes, _) = rule.outcome { minutes = maxMinutes }
        check = result
        guard announce else { return }
        let screen = ConditionalCheckIn.screen(check: result, live: rule, sessions: state.sessions,
                                               attempt: attempt, now: Date())
        if screen.canStart {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else if case .running = screen {
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    /// Sends the shown check, once. A stale check is run again instead and
    /// needs a new hold; the engine validates the request again regardless.
    private func start(cap: Int) {
        guard !starting, let check else { return }
        let state = model.state
        let live = state.conditionalRules.first { $0.id == ruleID }
        guard ConditionalCheckIn.screen(check: check, live: live, sessions: state.sessions,
                                        attempt: attempt, now: Date()).canStart else { return }
        if ConditionalCheckIn.needsRecheck(check, live: live, clock: ConditionalClockInput.current(for: state)) {
            runCheck(state, announce: true)
            return
        }
        starting = true
        let request = ConditionalStartRequest(ruleID: check.rule.id, revision: check.rule.revision,
                                              minutes: ConditionalCheckIn.requestMinutes(chosen: minutes, cap: cap),
                                              stamp: check.stamp)
        Task { @MainActor in
            let result = await ChangeEngine.startConditionalSessionOffMain(request)
            model.refreshAfterExternalApply()
            switch result {
            case .started(let session): attempt = .started(until: session.endsAt)
            case .waiting: attempt = .waiting
            case .refused(let refusal):
                attempt = .refused(refusal)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
            // The stamp is spent either way; a new start needs a new check.
            runCheck(model.state, announce: false)
            starting = false
        }
    }
}
