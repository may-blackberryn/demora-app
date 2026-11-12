//
//  CheckInSheet.swift
//  The When & where check-in (docs/conditional-sessions-redesign.md §5.5):
//  checks day, time and dates on the guarded clock first, then, only when a
//  place or country could still change the answer (C8), reads one foreground fix through
//  `LocationCheck` and checks again with it. Shows ✓ / ✗ / ? per condition
//  with its reason, and when the rule is met starts free time through
//  `ChangeEngine.startConditionalSessionOffMain`, which validates everything
//  again. The stamp comes from the check that read the fix; the fix itself is
//  never kept (only ✓/✗ results), and checks refreshed on their own never
//  read location. A country is told by the bundled offline borders
//  (`CountryBorders`, no network, no geocoder); block check-ins are step 6.
//  A condition has no way around it here: no skip, no Apply now, no password,
//  phrase or contact.
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
    /// Made with the sheet and dropped with it; nothing outside reads it.
    @StateObject private var locator = LocationCheck()
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
    /// A hold landed on a check that had to be run again (midnight, a zone
    /// change, an edit): the new result is shown and needs a new hold.
    @State private var checkedAgain = false
    /// The one location read: the card before iOS asks, or the fix in flight.
    @State private var locationPhase: CheckInLocationPhase = .idle
    /// Bumped by every check, so a fix that arrives late can't replace a newer one.
    @State private var generation = 0
    /// iOS's prompt is up: a second tap on Allow location does nothing.
    @State private var requestingPermission = false

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
                if let check, !starting, locationPhase == .idle,
                   ConditionalCheckIn.needsRecheck(check, live: live,
                                                   clock: ConditionalClockInput.current(for: model.state)) {
                    runCheck(model.state, announce: false)
                }
            }
        }
        .background(Ink.cardRaised.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        // Opening the sheet is the user's Check in tap (C8).
        .onAppear { runCheck(model.state, announce: true, userAsked: true) }
        .onDisappear {
            generation += 1
            locator.stop()
        }
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
                                               attempt: attempt, now: now, location: locationPhase)
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
                if checkedAgain, screen.canStart {
                    Text(tr("Checked again. Hold again to start."))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                        if screen == .locating, pair.0.usesLocation {
                            ConditionRow(condition: pair.0, checking: true, reason: tr("Checking where you are"))
                        } else {
                            ConditionRow(condition: pair.0, status: pair.1.status,
                                         reason: ConditionalCheckIn.reason(pair.1, condition: pair.0, translate: tr,
                                                                           locale: locale, calendar: calendar))
                        }
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
        case .gone, .changed, .running, .checking, .refused, .queued, .arrivesLater(.block): return false
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
            case .checking, .locating:
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
            case .askPermission:
                // The in-sheet card comes first; iOS asks only after this tap.
                primary(tr("Allow location")) { allowLocation() }
                    .disabled(requestingPermission)
                quiet(tr("Not now")) { dismiss() }
            default:
                // Not met, used up, needs location, changed, refused: no way
                // around a condition, only checking again.
                primary(tr("Try again")) {
                    attempt = nil
                    checkedAgain = false
                    // The user's tap: it may read one new fix (timeout, aged
                    // check). Denied stays "off" and is never re-prompted.
                    runCheck(model.state, announce: true, userAsked: true)
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

    /// Day, time and dates on the guarded clock, from saved state. Only when
    /// the user asked (opening the sheet, Try again, Allow location) and a
    /// place could still change the answer does it go on to the permission
    /// card or one fix (C8); checks refreshed on their own never read
    /// location. `announce` adds the one verdict haptic (spec §9).
    private func runCheck(_ state: LatchState, announce: Bool, userAsked: Bool = false) {
        generation += 1
        locationPhase = .idle
        locator.cancel()
        guard let rule = state.conditionalRules.first(where: { $0.id == ruleID }) else {
            check = nil
            return
        }
        let clock = ConditionalClockInput.current(for: state)
        var result = CheckInResult.make(rule: rule, state: state, clock: clock, location: .notRead)
        if check == nil, case .freeTime(_, _, let maxMinutes, _) = rule.outcome { minutes = maxMinutes }
        check = result
        if userAsked {
            switch ConditionalCheckIn.locationStep(result, permission: locator.permission,
                                                   sessions: state.sessions, now: Date()) {
            case .read:
                readLocation(announce: announce, precise: ConditionalCheckIn.wantsPrecise(rule))
                return
            case .ask:
                locationPhase = .asking
                return
            case .off:
                // Denied or restricted: say so on the rows; never ask again.
                result = CheckInResult.make(rule: rule, state: state, clock: clock,
                                            location: .unavailable(.locationOff))
                check = result
            case .none:
                break
            }
        }
        if announce { announceVerdict(result, rule: rule, sessions: state.sessions) }
    }

    /// One fix, then the same check again with it, on a fresh clock read so
    /// the stamp's time matches the fix. The fix goes no further than this
    /// and the offline country lookup. Temporary precise location is asked
    /// for only when a place needs it (`precise`), never for a country alone.
    private func readLocation(announce: Bool, precise: Bool) {
        let token = generation
        locationPhase = .reading
        Self.preloadCountries(for: model.state.conditionalRules.first { $0.id == ruleID })
        Task { @MainActor in
            let outcome = await locator.readOnce(wantsPrecise: precise)
            guard token == generation else { return }
            locationPhase = .idle
            let state = model.state
            guard let rule = state.conditionalRules.first(where: { $0.id == ruleID }) else {
                check = nil
                return
            }
            let clock = ConditionalClockInput.current(for: state)
            let result = CheckInResult.make(rule: rule, state: state, clock: clock,
                                            location: LocationTrust.checkInInput(outcome, wallNow: clock.wallNow,
                                                                                 country: Self.countryLookup(for: rule)))
            check = result
            if announce { announceVerdict(result, rule: rule, sessions: state.sessions) }
        }
    }

    /// The card's button: iOS's "While Using" prompt, then the check again.
    /// After a denial the card never comes back (the rows say location is off).
    private func allowLocation() {
        guard !requestingPermission else { return }
        requestingPermission = true
        let token = generation
        Task { @MainActor in
            await locator.requestPermission()
            requestingPermission = false
            guard token == generation else { return }
            runCheck(model.state, announce: true, userAsked: true)
        }
    }

    private func announceVerdict(_ result: CheckInResult, rule: ConditionalRule, sessions: [BlockSession]) {
        let screen = ConditionalCheckIn.screen(check: result, live: rule, sessions: sessions,
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
        guard !starting, var check else { return }
        let state = model.state
        let live = state.conditionalRules.first { $0.id == ruleID }
        var cap = cap
        guard ConditionalCheckIn.screen(check: check, live: live, sessions: state.sessions,
                                        attempt: attempt, now: Date()).canStart else { return }
        let clock = ConditionalClockInput.current(for: state)
        if ConditionalCheckIn.needsRecheck(check, live: live, clock: clock) {
            // The hold was the deliberate act: a check that only aged is run
            // again and, if it still holds on the same day for the same rule,
            // sent in its place. Anything else is shown and needs a new hold.
            guard let rule = live else { runCheck(state, announce: false); return }
            if check.readLocation {
                // Its fix is too old to trust: read where you are again first.
                recheckWithLocation(old: check)
                return
            }
            let fresh = CheckInResult.make(rule: rule, state: state, clock: clock, location: .notRead)
            guard ConditionalCheckIn.mayStartAfterRecheck(old: check, fresh: fresh, live: live,
                                                          sessions: state.sessions, now: Date()),
                  case .met(let freshCap) = ConditionalCheckIn.screen(check: fresh, live: live,
                      sessions: state.sessions, attempt: nil, now: Date()) else {
                self.check = fresh
                checkedAgain = true
                return
            }
            self.check = fresh
            check = fresh
            cap = freshCap
        }
        send(check, cap: cap)
    }

    /// A hold on an aged check that had read location: one new fix (the
    /// hold is the user's tap), then the same rule as `start`: sent only if
    /// still met for the same rule version, day and zone; otherwise shown.
    private func recheckWithLocation(old: CheckInResult) {
        starting = true
        generation += 1
        let token = generation
        locationPhase = .reading
        Self.preloadCountries(for: old.rule)
        Task { @MainActor in
            let outcome = await locator.readOnce(wantsPrecise: ConditionalCheckIn.wantsPrecise(old.rule))
            guard token == generation else { starting = false; return }
            locationPhase = .idle
            let state = model.state
            let live = state.conditionalRules.first { $0.id == ruleID }
            guard let rule = live else {
                starting = false
                runCheck(state, announce: false)
                return
            }
            let clock = ConditionalClockInput.current(for: state)
            let fresh = CheckInResult.make(rule: rule, state: state, clock: clock,
                                           location: LocationTrust.checkInInput(outcome, wallNow: clock.wallNow,
                                                                                country: Self.countryLookup(for: rule)))
            check = fresh
            guard ConditionalCheckIn.mayStartAfterRecheck(old: old, fresh: fresh, live: live,
                                                          sessions: state.sessions, now: Date()),
                  case .met(let freshCap) = ConditionalCheckIn.screen(check: fresh, live: live,
                      sessions: state.sessions, attempt: nil, now: Date()) else {
                checkedAgain = true
                starting = false
                return
            }
            starting = false
            send(fresh, cap: freshCap)
        }
    }

    /// The bundled offline borders, only for a rule with a country (a place
    /// rule never loads them). No network: `CountryBorders` reads the app's
    /// own file. Nil if it can't load: the country row then says it couldn't tell.
    private static func countryLookup(for rule: ConditionalRule) -> LocationTrust.CountryAt? {
        guard hasCountry(rule), let borders = CountryBorders.bundled else { return nil }
        return { borders.lookup(latitude: $0, longitude: $1) }
    }

    private static func hasCountry(_ rule: ConditionalRule?) -> Bool {
        rule?.conditions.contains(where: { if case .country = $0 { return true }; return false }) ?? false
    }

    /// Reads the bundled borders off the main thread while iOS gets the fix,
    /// so the lookup after it doesn't wait for the file.
    private static func preloadCountries(for rule: ConditionalRule?) {
        guard hasCountry(rule) else { return }
        Task.detached(priority: .userInitiated) { _ = CountryBorders.bundled }
    }

    /// The one place a start request is made, for the check on screen.
    private func send(_ check: CheckInResult, cap: Int) {
        guard !starting else { return }
        starting = true
        checkedAgain = false
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
