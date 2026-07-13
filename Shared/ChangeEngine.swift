//
//  ChangeEngine.swift
//  The core of the app: every settings mutation becomes a PendingChange,
//  classified stricter/lenient, gated by the matching delay, and applied
//  only when its timer elapses (or the user passes an override).
//

import Foundation
import DeviceActivity
import FamilyControls
import UserNotifications

/// Combined "how hard is this math gate" score, so a config change can be
/// classified stricter vs lenient. Harder level, more problems, and a harsher
/// wrong-answer penalty all increase it.
func mathStrictnessScore(_ difficulty: MathDifficulty, _ count: Int,
                         _ wrong: MathWrongBehavior) -> Int {
    difficulty.rawValue * 1000 + count * 10 + wrong.rawValue
}

enum ChangeEngine {

    // MARK: - Classification

    /// Decide which delay gates an action, given the current state.
    /// Rules:
    ///  • add limit / lower minutes            → stricter
    ///  • remove limit / raise minutes         → lenient
    ///  • increase either delay                → stricter
    ///  • decrease either delay                → lenient
    ///  • enable an override / make it easier  → lenient
    ///  • disable an override / make it harder → stricter
    static func classify(_ action: ChangeAction, state: LatchState) -> ChangeDirection {
        switch action {
        case .addLimit:
            return .stricter
        case .removeLimit:
            return .lenient
        case .updateLimitMinutes(let id, let minutes):
            // Unknown id (stale) or an unchanged value gets no free pass — they
            // default to the stricter (longer) gate rather than the lenient one.
            guard let current = state.limits.first(where: { $0.id == id })?.minutesPerDay
            else { return .stricter }
            if minutes < current { return .stricter }   // lowering = stricter
            if minutes > current { return .lenient }     // raising = lenient
            return .stricter                             // unchanged: safe default
        case .setStrictDelay(let new):
            return new > state.strictDelay ? .stricter : .lenient
        case .setLenientDelay(let new):
            return new > state.lenientDelay ? .stricter : .lenient
        case .setMathOverride(let enabled, let difficulty, let count, let wrong):
            if enabled != state.overrides.mathEnabled {
                return enabled ? .lenient : .stricter
            }
            let oldScore = mathStrictnessScore(state.overrides.mathDifficulty ?? .elementary,
                                               state.overrides.mathProblemCount,
                                               state.overrides.mathWrongBehavior)
            let newScore = mathStrictnessScore(difficulty ?? .elementary, count, wrong)
            return newScore > oldScore ? .stricter : .lenient
        case .setPasswordOverride(let enabled, _):
            if enabled != state.overrides.passwordEnabled {
                return enabled ? .lenient : .stricter
            }
            // Changing the password itself: treat as lenient (safe default).
            return .lenient
        case .setContactsOverride(let enabled):
            return enabled ? .lenient : .stricter
        case .addContact:
            return .lenient    // another way to bypass = less strict
        case .removeContact:
            return .stricter   // fewer ways to bypass = stricter
        case .addSchedule:
            return .stricter
        case .removeSchedule:
            return .lenient
        case .addExemption:
            return .lenient   // a free period loosens enforcement
        case .removeExemption:
            return .stricter
        case .addPlanned(let w):
            return w.kind == .free ? .lenient : .stricter
        case .removePlanned(let id):
            let kind = state.planned.first { $0.id == id }?.kind ?? .blockSelected
            return kind == .free ? .stricter : .lenient
        case .startSession(_, let kind, _, _):
            // Blocking now = stricter; unblocking now = lenient.
            return kind == .block ? .stricter : .lenient
        case .endSessionEarly(let id):
            let kind = state.sessions.first { $0.id == id }?.kind ?? .block
            // Ending a block early = lenient; ending an unblock early = stricter.
            return kind == .block ? .lenient : .stricter
        case .setBlockAppRemoval(let on):
            return on ? .stricter : .lenient
        case .setBlockAdultWebsites(let on):
            return on ? .stricter : .lenient
        case .addBlockedDomain:
            return .stricter   // adding a block = stricter
        case .removeBlockedDomain:
            return .lenient    // unblocking = looser
        case .unlockPreventGuide:
            return .lenient    // gaining access = looser
        }
    }

    static func summary(for action: ChangeAction, state: LatchState) -> String {
        switch action {
        case .addLimit(let l):
            return String(format: tr("Add limit: %@ — %d min/day"),
                          l.name, l.minutesPerDay)
        case .updateLimitMinutes(let id, let m):
            let name = state.limits.first { $0.id == id }?.name ?? tr("limit")
            return String(format: tr("Change %@ to %d min/day"), name, m)
        case .removeLimit(let id):
            let name = state.limits.first { $0.id == id }?.name ?? tr("limit")
            return String(format: tr("Remove limit: %@"), name)
        case .setStrictDelay(let t):
            return String(format: tr("Set 'more strict' delay to %@"),
                          t.shortDelayLabel)
        case .setLenientDelay(let t):
            return String(format: tr("Set 'less strict' delay to %@"),
                          t.shortDelayLabel)
        case .setMathOverride(let on, let d, let count, _):
            return on ? String(format: tr("Enable math override (%@, %d problems)"),
                               d?.label ?? "—", count)
                      : tr("Disable math override")
        case .setPasswordOverride(let on, _):
            return on ? tr("Enable/update password override")
                      : tr("Disable password override")
        case .setContactsOverride(let on):
            return on ? tr("Enable trusted-contact override")
                      : tr("Disable trusted-contact override")
        case .addContact(let contact):
            return String(format: tr("Add trusted contact: %@"), contact.name)
        case .removeContact(let id):
            let name = state.overrides.contacts
                .first { $0.id == id }?.name ?? tr("contact")
            return String(format: tr("Remove trusted contact: %@"), name)
        case .addSchedule(let s):
            return String(format: tr("Add schedule: %@ (%@ %@)"),
                          s.name, s.mode.label, s.windowLabel)
        case .removeSchedule(let id):
            let name = state.schedules.first { $0.id == id }?.name ?? tr("schedule")
            return String(format: tr("Remove schedule: %@"), name)
        case .addExemption(let e):
            return String(format: tr("Add free period: %@ (%@)"),
                          e.name, e.windowLabel)
        case .removeExemption(let id):
            let name = state.exemptions.first { $0.id == id }?.name ?? tr("free period")
            return String(format: tr("Remove free period: %@"), name)
        case .addPlanned(let w):
            let df = DateFormatter()
            df.dateStyle = .short
            df.timeStyle = .short
            return String(format: tr("Plan %@: %@ (%@)"),
                          w.kind.label, w.name, df.string(from: w.startsAt))
        case .removePlanned(let id):
            let name = state.planned.first { $0.id == id }?.name ?? tr("planned window")
            return String(format: tr("Remove planned window: %@"), name)
        case .startSession(let name, let kind, _, let minutes):
            if kind == .free {
                return String(format: tr("Free period: %@ (%d min)"), name, minutes)
            }
            return String(format: tr("%@ session: %@ (%d min)"),
                          kind.label, name, minutes)
        case .endSessionEarly(let id):
            let session = state.sessions.first { $0.id == id }
            return String(format: tr("End session early: %@"),
                          session?.name ?? tr("session"))
        case .setBlockAppRemoval(let on):
            return on ? tr("Block app deletion") : tr("Allow app deletion")
        case .setBlockAdultWebsites(let on):
            return on ? tr("Block adult websites") : tr("Allow adult websites")
        case .addBlockedDomain(let d):
            return String(format: tr("Block website: %@"), d)
        case .removeBlockedDomain(let d):
            return String(format: tr("Unblock website: %@"), d)
        case .unlockPreventGuide:
            return tr("Unlock the “Prevent disabling” guide")
        }
    }

    // MARK: - Queueing

    /// One pending change per setting: actions that touch the same thing
    /// share a key, and a second queue attempt is rejected while the first
    /// is still counting down.
    static func conflictKey(_ action: ChangeAction) -> String {
        switch action {
        case .addLimit(let l):
            return "addLimit-\(l.name.lowercased())"
        case .updateLimitMinutes(let id, _), .removeLimit(let id):
            return "limit-\(id.uuidString)"
        case .setStrictDelay:
            return "strictDelay"
        case .setLenientDelay:
            return "lenientDelay"
        case .setMathOverride:
            return "mathOverride"
        case .setPasswordOverride:
            return "passwordOverride"
        case .setContactsOverride:
            return "contactsOverride"
        case .addContact(let c):
            return "addContact-\(c.detail.lowercased())"
        case .removeContact(let id):
            return "contact-\(id.uuidString)"
        case .addSchedule(let s):
            return "addSchedule-\(s.name.lowercased())"
        case .removeSchedule(let id):
            return "schedule-\(id.uuidString)"
        case .addExemption(let e):
            return "addExemption-\(e.name.lowercased())"
        case .removeExemption(let id):
            return "exemption-\(id.uuidString)"
        case .addPlanned(let w):
            return "addPlanned-\(w.name.lowercased())-\(Int(w.startsAt.timeIntervalSince1970))"
        case .removePlanned(let id):
            return "planned-\(id.uuidString)"
        case .startSession(_, let kind, _, _):
            return "startSession-\(kind.rawValue)"
        case .endSessionEarly(let id):
            return "endSession-\(id.uuidString)"
        case .setBlockAppRemoval:
            return "blockAppRemoval"
        case .setBlockAdultWebsites:
            return "blockAdultWebsites"
        case .addBlockedDomain(let d), .removeBlockedDomain(let d):
            return "blockedDomain-\(d.lowercased())"
        case .unlockPreventGuide:
            return "unlockPreventGuide"
        }
    }

    /// Queue an action behind its delay. Returns the created pending change,
    /// or nil if an equivalent change is already pending.
    @discardableResult
    static func queue(_ action: ChangeAction) -> PendingChange? {
        var state = SharedStore.loadState()
        let key = conflictKey(action)
        guard !state.pending.contains(where: { conflictKey($0.action) == key })
        else { return nil }
        let direction = classify(action, state: state)
        let delay = direction == .stricter ? state.strictDelay : state.lenientDelay
        let now = TimeGuard.now()
        let change = PendingChange(
            createdAt: now,
            appliesAt: now.addingTimeInterval(delay),
            direction: direction,
            summary: summary(for: action, state: state),
            action: action
        )
        state.pending.append(change)
        SharedStore.save(state)

        if delay > 0 {
            scheduleApplyActivity(for: change)
            scheduleNotification(for: change)
        }
        applyDueChanges()   // delay == 0 (e.g. during setup) applies instantly
        return change
    }

    static func cancel(_ change: PendingChange) {
        var state = SharedStore.loadState()
        state.pending.removeAll { $0.id == change.id }
        SharedStore.save(state)
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(change.activityName)])
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [change.id.uuidString])
    }

    /// Apply `change` immediately — caller must have passed an override gate first.
    static func applyNow(_ change: PendingChange) {
        var state = SharedStore.loadState()
        guard let idx = state.pending.firstIndex(where: { $0.id == change.id })
        else {
            #if DEBUG
            print("⚠️ applyNow: \(change.id.uuidString.prefix(8)) NOT in pending")
            #endif
            return
        }
        #if DEBUG
        print("   applyNow OK: \(change.summary)")
        #endif
        var c = state.pending[idx]
        c.appliesAt = .distantPast   // due immediately under any clock
        state.pending[idx] = c
        SharedStore.save(state)
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(change.activityName)])
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [change.id.uuidString])
        applyDueChanges()
    }

    // MARK: - Applying

    /// Merge every due pending change into the active state, then
    /// reconfigure monitoring/shields. Safe to call from app or extensions.
    static func applyDueChanges() {
        var state = SharedStore.loadState()
        let due = state.pending.filter(\.isDue).sorted { $0.appliesAt < $1.appliesAt }
        guard !due.isEmpty else { return }

        for change in due {
            apply(change.action, to: &state)
            state.pending.removeAll { $0.id == change.id }
            DeviceActivityCenter()
                .stopMonitoring([DeviceActivityName(change.activityName)])
        }
        SharedStore.save(state)
        reconfigureDailyMonitoring(state: state)
        reconfigureWindowMonitoring(state: state)
        ShieldController.refresh()
        reconcileFreeWindow()   // a free session may have started or ended early
    }

    /// Periodic maintenance: apply due changes, drop finished sessions,
    /// re-derive shields. Called on app foreground/timer and from extensions.
    static func housekeeping() {
        rolloverIfNewDay()
        applyDueChanges()
        pruneExpiredSessions()
        prunePastPlanned()
        ShieldController.refresh()
        reconcileFreeWindow()
    }

    /// Foreground fallback for the midnight reset. iOS doesn't guarantee the
    /// monitor's daily `intervalDidStart` fires on time in the background, so a
    /// limit spent yesterday can still be shielded after midnight — and, because
    /// `housekeeping()` otherwise just re-derives shields from the stale
    /// `blockedLimitIDs`, opening the app wouldn't clear it either. Mirroring the
    /// monitor's reset here guarantees an app open on a new day always unblocks.
    /// Uses the same `lastResetDay` guard as the monitor, so the two never
    /// double-reset. Skipped during the tutorial/replay (simulation).
    static func rolloverIfNewDay() {
        guard !SharedStore.simulating else { return }
        let today = SharedStore.dayKey(for: TimeGuard.now())
        guard SharedStore.lastResetDay != today else { return }
        ShieldController.clearForNewDay()          // clears blocks + usage
        SharedStore.lastResetDay = today
        reconfigureDailyMonitoring(state: SharedStore.loadState())
    }

    /// Planned windows in the past expire on their own — no delay needed.
    static func prunePastPlanned() {
        var state = SharedStore.loadState()
        let past = state.planned.filter(\.isPast)
        guard !past.isEmpty else { return }
        state.planned.removeAll(where: \.isPast)
        SharedStore.save(state)
        DeviceActivityCenter().stopMonitoring(
            past.map { DeviceActivityName($0.activityName) })
    }

    private static func apply(_ action: ChangeAction, to state: inout LatchState) {
        switch action {
        case .addLimit(let l):
            state.limits.append(l)
        case .updateLimitMinutes(let id, let m):
            if let i = state.limits.firstIndex(where: { $0.id == id }) {
                state.limits[i].minutesPerDay = m
            }
        case .removeLimit(let id):
            state.limits.removeAll { $0.id == id }
            var blocked = SharedStore.loadBlockedLimitIDs()
            blocked.remove(id)
            SharedStore.saveBlockedLimitIDs(blocked)
        case .setStrictDelay(let t):
            state.strictDelay = t
        case .setLenientDelay(let t):
            state.lenientDelay = t
        case .setMathOverride(let on, let d, let count, let wrong):
            state.overrides.mathEnabled = on
            state.overrides.mathDifficulty = on ? d : nil
            if on {
                state.overrides.mathQuestionCount = count
                state.overrides.mathWrongBehavior = wrong
            }
        case .setPasswordOverride(let on, let hash):
            state.overrides.passwordEnabled = on
            state.overrides.passwordHash = on ? hash : nil
        case .setContactsOverride(let on):
            state.overrides.contactsEnabled = on
        case .addContact(let contact):
            state.overrides.contacts.append(contact)
        case .removeContact(let id):
            state.overrides.contacts.removeAll { $0.id == id }
        case .addSchedule(let s):
            state.schedules.append(s)
        case .removeSchedule(let id):
            state.schedules.removeAll { $0.id == id }
        case .addExemption(let e):
            state.exemptions.append(e)
        case .removeExemption(let id):
            state.exemptions.removeAll { $0.id == id }
        case .addPlanned(let w):
            state.planned.append(w)
        case .removePlanned(let id):
            if let w = state.planned.first(where: { $0.id == id }) {
                DeviceActivityCenter()
                    .stopMonitoring([DeviceActivityName(w.activityName)])
            }
            state.planned.removeAll { $0.id == id }
        case .startSession(let name, let kind, let selection, let minutes):
            // The delay already ran (this is apply time) — session starts now.
            let session = BlockSession(
                name: name, kind: kind, selection: selection,
                startedAt: Date(),
                endsAt: Date().addingTimeInterval(TimeInterval(minutes) * 60))
            state.sessions.append(session)
            startSessionCleanupActivity(session)
        case .endSessionEarly(let id):
            if let session = state.sessions.first(where: { $0.id == id }) {
                DeviceActivityCenter()
                    .stopMonitoring([DeviceActivityName(session.activityName)])
            }
            state.sessions.removeAll { $0.id == id }
        case .setBlockAppRemoval(let on):
            state.blockAppRemoval = on
        case .setBlockAdultWebsites(let on):
            state.blockAdultWebsites = on
        case .addBlockedDomain(let d):
            let domain = Self.normalizeDomain(d)
            if !domain.isEmpty,
               !state.blockedDomains.contains(where: { $0.caseInsensitiveCompare(domain) == .orderedSame }) {
                state.blockedDomains.append(domain)
            }
        case .removeBlockedDomain(let d):
            state.blockedDomains.removeAll { $0.caseInsensitiveCompare(d) == .orderedSame }
        case .unlockPreventGuide:
            // Grant one open: a past timestamp means "ready" (preventReady).
            state.preventUnlockAt = .distantPast
        }
    }

    /// Normalize a typed domain: trim, lowercase, drop scheme and any path so
    /// "https://Reddit.com/r/x" and "reddit.com" land on the same entry.
    static func normalizeDomain(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = s.range(of: "://") { s = String(s[range.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if s.hasPrefix("www.") { s = String(s.dropFirst(4)) }
        return s
    }

    // MARK: - DeviceActivity scheduling

    /// One repeating daily schedule with a per-limit threshold event. The
    /// threshold is the day's minutes plus the free-period credit *that limit*
    /// earned today (its measured usage inside ended free windows), so time
    /// spent while a free window lifted the shields never counts against the
    /// real limit — and untouched limits get no extra time. On iOS 17.4+
    /// `includesPastActivity` makes the event fire at the true daily total
    /// regardless of monitoring restarts.
    static func reconfigureDailyMonitoring(state: LatchState) {
        // Optimistic reset; any startMonitoring failure below (or in the window
        // pass that follows) flips it back on. Drives the "enforcement degraded"
        // banner.
        SharedStore.enforcementDegraded = false
        let credit = SharedStore.loadFreeCreditByLimit()
        let center = DeviceActivityCenter()
        let daily = DeviceActivityName(LatchConstants.dailyActivityName)
        center.stopMonitoring([daily])
        // Tutorial simulation: don't start any real limit monitoring.
        if SharedStore.simulating { return }
        guard !state.limits.isEmpty else { return }

        let blocked = SharedStore.loadBlockedLimitIDs()
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

        for limit in state.limits {
            // A 0-minute limit is always blocked (handled by the shield), and a
            // limit already at its cap stays blocked — neither needs an event.
            if limit.minutesPerDay == 0 || blocked.contains(limit.id) { continue }

            // includesPastActivity:true makes the OS count usage that already
            // happened earlier today — including time spent before this limit
            // was added mid-day — so the threshold fires at the real daily
            // total instead of restarting the count from zero every time
            // monitoring restarts. The report extension shows the live number;
            // this drives the actual block.
            let apps = limit.selection.applicationTokens
            let cats = limit.selection.categoryTokens
            let webs = limit.selection.webDomainTokens
            // Real limit + this limit's free-period credit. Split into
            // hour/minute: a bare DateComponents(minute:) > 59 is unreliable
            // across iOS.
            let cap = thresholdComponents(minutes: limit.minutesPerDay
                                          + (credit[limit.id] ?? 0))
            let limitEvent: DeviceActivityEvent
            if #available(iOS 17.4, *) {
                limitEvent = DeviceActivityEvent(
                    applications: apps, categories: cats, webDomains: webs,
                    threshold: cap, includesPastActivity: true)
            } else {
                // iOS 16 / pre-17.4: no includesPastActivity, so the cap counts
                // only from when monitoring (re)starts.
                limitEvent = DeviceActivityEvent(
                    applications: apps, categories: cats, webDomains: webs,
                    threshold: cap)
            }
            events[DeviceActivityEvent.Name("limit-\(limit.id.uuidString)")] = limitEvent
        }
        SharedStore.saveBlockedLimitIDs(blocked)

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),  
            repeats: true
        )
        do {
            try center.startMonitoring(daily, during: schedule, events: events)
        } catch {
            print("Demora: failed to start daily monitoring: \(error)")
            SharedStore.enforcementDegraded = true
        }
    }

    /// A DeviceActivity threshold as hour+minute. A bare `DateComponents(minute:)`
    /// above 59 behaves inconsistently across iOS versions, so always split it.
    private static func thresholdComponents(minutes: Int) -> DateComponents {
        let m = max(1, minutes)
        return DateComponents(hour: m / 60, minute: m % 60)
    }

    /// Repeating activities for every schedule and free-period window plus
    /// one-shot activities for planned windows, so the monitor extension
    /// wakes at each boundary and refreshes shields. Shield state itself is
    /// always recomputed from the wall clock, so a missed callback only
    /// delays a transition until the next wake-up.
    static func reconfigureWindowMonitoring(state: LatchState) {
        let center = DeviceActivityCenter()
        let stale = center.activities.filter {
            $0.rawValue.hasPrefix("sched-") || $0.rawValue.hasPrefix("exempt-")
                || $0.rawValue.hasPrefix("planned-")
        }
        if !stale.isEmpty { center.stopMonitoring(stale) }
        // Tutorial simulation: don't start any real window monitoring.
        if SharedStore.simulating { return }

        for s in state.schedules {
            startWindowActivities(prefix: "sched-\(s.id.uuidString)",
                                  start: s.startMinutes, end: s.endMinutes,
                                  recurrence: s.recurrence)
        }
        for e in state.exemptions {
            startWindowActivities(prefix: "exempt-\(e.id.uuidString)",
                                  start: e.startMinutes, end: e.endMinutes,
                                  recurrence: e.recurrence)
        }
        let cal = Calendar.current
        for w in state.planned where !w.isPast {
            // Round BOTH ends UP to the next whole minute. Truncated (minute-
            // granular) bounds fire a few seconds early: the start fires before
            // the window is active (so it doesn't turn on until the app is
            // reopened) and the end fires before it's over (so it doesn't turn
            // off). Rounding up makes each callback land at-or-after the real
            // boundary, so planned windows begin and end in the background.
            let start = ceilToMinute(max(w.startsAt, Date().addingTimeInterval(60)), cal)
            let end = ceilToMinute(max(w.endsAt, start.addingTimeInterval(16 * 60)), cal)
            let schedule = DeviceActivitySchedule(
                intervalStart: cal.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: start),
                intervalEnd: cal.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: end),
                repeats: false
            )
            do {
                try center.startMonitoring(
                    DeviceActivityName(w.activityName), during: schedule)
            } catch {
                print("Demora: failed to schedule planned window: \(error)")
                SharedStore.enforcementDegraded = true
            }
        }
    }

    private static func startWindowActivities(prefix: String, start: Int,
                                              end: Int, recurrence: Recurrence) {
        let center = DeviceActivityCenter()
        func register(_ name: String, _ s: DateComponents, _ e: DateComponents) {
            let schedule = DeviceActivitySchedule(intervalStart: s,
                                                  intervalEnd: e, repeats: true)
            do {
                try center.startMonitoring(DeviceActivityName(name),
                                           during: schedule)
            } catch {
                print("Demora: failed to start window activity \(name): \(error)")
                SharedStore.enforcementDegraded = true
            }
        }
        let sh = start / 60, sm = start % 60
        let eh = end / 60, em = end % 60
        let wraps = start >= end

        switch recurrence {
        case .daily:
            let segments: [(Int, Int)] = wraps
                ? [(start, 24 * 60 - 1), (0, end)]
                : [(start, end)]
            for (i, seg) in segments.enumerated() {
                // DeviceActivity requires intervals ≥15 min. Rather than
                // silently drop a short (or midnight-wrapping) segment — leaving
                // no background wake at its boundary — pad the end to the floor,
                // clamped to the day. Shield state is recomputed from the wall
                // clock on every wake, so the padded end doesn't distort
                // enforcement; it just guarantees a wake near the boundary.
                let paddedEnd = min(max(seg.1, seg.0 + 15), 24 * 60 - 1)
                guard paddedEnd - seg.0 >= 15 else { continue }
                register("\(prefix)-\(i)",
                         DateComponents(hour: seg.0 / 60, minute: seg.0 % 60),
                         DateComponents(hour: paddedEnd / 60, minute: paddedEnd % 60))
            }
        case .weekly(let days):
            for d in days.sorted() {
                register("\(prefix)-w\(d)",
                         DateComponents(hour: sh, minute: sm, weekday: d),
                         DateComponents(hour: eh, minute: em,
                                        weekday: wraps ? (d % 7) + 1 : d))
            }
        case .monthlyDay(let day):
            // Midnight-wrapping windows are rejected by the editor for
            // monthly rules, so start < end here.
            register("\(prefix)-m",
                     DateComponents(day: day, hour: sh, minute: sm),
                     DateComponents(day: day, hour: eh, minute: em))
        case .monthlyOrdinal(let weekday, let ordinal):
            register("\(prefix)-o",
                     DateComponents(hour: sh, minute: sm, weekday: weekday,
                                    weekdayOrdinal: ordinal),
                     DateComponents(hour: eh, minute: em, weekday: weekday,
                                    weekdayOrdinal: ordinal))
        }
    }

    // MARK: - Sessions

    /// One-shot activity so the extension cleans up (or, for unblock
    /// sessions, re-blocks) at session end even if the app stays closed.
    private static func startSessionCleanupActivity(_ session: BlockSession) {
        let cal = Calendar.current
        // DeviceActivity schedules are minute-granular (and must span ≥15 min).
        // The interval end is truncated to the minute, so we round the session
        // end UP to the next whole minute — otherwise intervalDidEnd fires a few
        // seconds BEFORE endsAt, the session still reads as active, nothing gets
        // pruned, and the apps stay unblocked until Demora is next opened.
        let target = max(session.endsAt, Date().addingTimeInterval(16 * 60))
        let end = ceilToMinute(target, cal)
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.year, .month, .day, .hour, .minute],
                                              from: Date().addingTimeInterval(60)),
            intervalEnd: cal.dateComponents([.year, .month, .day, .hour, .minute],
                                            from: end),
            repeats: false
        )
        try? DeviceActivityCenter().startMonitoring(
            DeviceActivityName(session.activityName), during: schedule)
    }

    /// Round up to the next whole minute (unchanged if already on a boundary),
    /// so a minute-granular DeviceActivity interval ends at-or-after `date`.
    private static func ceilToMinute(_ date: Date, _ cal: Calendar) -> Date {
        let floored = cal.date(from: cal.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date)) ?? date
        return floored >= date ? floored : floored.addingTimeInterval(60)
    }

    static func pruneExpiredSessions() {
        var state = SharedStore.loadState()
        let expired = state.sessions.filter { !$0.isActive }
        guard !expired.isEmpty else { return }
        state.sessions.removeAll { !$0.isActive }
        SharedStore.save(state)
        DeviceActivityCenter().stopMonitoring(
            expired.map { DeviceActivityName($0.activityName) })
        ShieldController.refresh()
        // A free session may have just expired — credit its in-window usage.
        reconcileFreeWindow()
    }

    /// Name of the one-shot activity that measures per-limit usage inside the
    /// currently-active free window.
    static let freeWindowActivityName = "latch.freewin"

    /// Checkpoint rungs (minutes) for free-window usage measurement — dense at
    /// the low end where accuracy matters most, sparser later to keep the
    /// event count per limit small (usage between rungs under-credits by at
    /// most the gap, which errs on the strict side).
    private static let freeCheckpointLadder = [1, 2, 3, 5, 8, 10, 15, 20, 30,
                                               45, 60, 90, 120, 180, 240]

    /// A free period just started: shields are lifted by refresh(), and a
    /// dedicated activity starts firing silent per-limit checkpoints so we
    /// know how much each limit's apps were *actually* used inside the window.
    /// A free-period session works like a scheduled free period: while active,
    /// limits don't block and usage inside it isn't counted. Free-window usage
    /// tracking is a single global thing, so ensure it's ON whenever ANY free
    /// period (a scheduled exemption, a planned free window, or a free session)
    /// is active, and OFF (crediting measured usage) when none is. Idempotent,
    /// so it also recovers if a monitor start/end callback was missed. Sessions
    /// can be ended early, which no other free period can — this is what keeps
    /// their tracking correct without a dedicated per-session callback.
    static func reconcileFreeWindow() {
        let state = SharedStore.loadState()
        let active = state.exemptions.contains { $0.isActive() }
            || state.planned.contains { $0.kind == .free && $0.isActive }
            || state.sessions.contains { $0.kind == .free && $0.isActive }
        let running = SharedStore.freeWindowStart != nil
        if active && !running { exemptWindowStarted() }
        else if !active && running { exemptWindowEnded() }
    }

    static func exemptWindowStarted() {
        // Don't reset an already-running window (overlapping free periods).
        if SharedStore.freeWindowStart == nil {
            SharedStore.freeWindowStart = TimeGuard.now()
            SharedStore.saveFreeWindowUsage([:])
            startFreeWindowTracking()
        }
        ShieldController.refresh()
    }

    /// One-shot activity spanning the free window whose events are per-limit
    /// usage checkpoints ("fw-<limitID>-<minutes>"). Thresholds count only
    /// activity inside this interval (no includesPastActivity), i.e. only
    /// usage inside the window. Stopped early by exemptWindowEnded(); the
    /// 24 h tail is just a ceiling.
    private static func startFreeWindowTracking() {
        if SharedStore.simulating { return }
        let state = SharedStore.loadState()
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        // 0-minute limits stay blocked all day by the shield; no credit applies.
        for limit in state.limits where limit.minutesPerDay > 0 {
            for m in freeCheckpointLadder {
                events[DeviceActivityEvent.Name("fw-\(limit.id.uuidString)-\(m)")] =
                    DeviceActivityEvent(
                        applications: limit.selection.applicationTokens,
                        categories: limit.selection.categoryTokens,
                        webDomains: limit.selection.webDomainTokens,
                        threshold: thresholdComponents(minutes: m))
            }
        }
        guard !events.isEmpty else { return }
        let cal = Calendar.current
        let start = Date().addingTimeInterval(60)
        let end = start.addingTimeInterval(24 * 3600)
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.year, .month, .day, .hour, .minute],
                                              from: start),
            intervalEnd: cal.dateComponents([.year, .month, .day, .hour, .minute],
                                            from: end),
            repeats: false
        )
        do {
            try DeviceActivityCenter().startMonitoring(
                DeviceActivityName(freeWindowActivityName),
                during: schedule, events: events)
        } catch {
            print("Demora: failed to start free-window tracking: \(error)")
            SharedStore.enforcementDegraded = true
        }
    }

    /// Monitor extension saw a free-window checkpoint ("fw-<uuid>-<minutes>"):
    /// record the highest rung per limit.
    static func recordFreeWindowCheckpoint(eventName: String) {
        let body = eventName.dropFirst("fw-".count)
        guard let lastDash = body.lastIndex(of: "-"),
              let minutes = Int(body[body.index(after: lastDash)...]),
              let id = UUID(uuidString: String(body[..<lastDash]))
        else { return }
        var usage = SharedStore.loadFreeWindowUsage()
        usage[id] = max(usage[id] ?? 0, minutes)
        SharedStore.saveFreeWindowUsage(usage)
    }

    /// A free period just ended: credit each limit's measured in-window usage
    /// to its daily budget, and unblock only the limits that earned credit —
    /// their raised threshold re-fires if the day's total (which includes the
    /// window on iOS 17.4+) is still over. Limits untouched during the window
    /// get no credit and stay exactly as they were.
    static func exemptWindowEnded() {
        DeviceActivityCenter().stopMonitoring(
            [DeviceActivityName(freeWindowActivityName)])
        if SharedStore.freeWindowStart != nil {
            let usage = SharedStore.loadFreeWindowUsage()
            var credit = SharedStore.loadFreeCreditByLimit()
            for (id, minutes) in usage where minutes > 0 {
                credit[id, default: 0] += min(minutes, 24 * 60)
            }
            SharedStore.saveFreeCreditByLimit(credit)
            SharedStore.saveFreeWindowUsage([:])
            SharedStore.freeWindowStart = nil
            if !usage.isEmpty {
                var blocked = SharedStore.loadBlockedLimitIDs()
                blocked.subtract(usage.keys)
                SharedStore.saveBlockedLimitIDs(blocked)
            }
        }
        reconfigureDailyMonitoring(state: SharedStore.loadState())
        ShieldController.refresh()
    }

    /// A one-shot DeviceActivity interval starting at `appliesAt` so the
    /// monitor extension wakes up in the background and applies the change
    /// even if the app is never opened.
    private static func scheduleApplyActivity(for change: PendingChange) {
        let cal = Calendar.current
        // Round the start UP to the next whole minute. A truncated (minute-
        // granular) intervalStart fires a few seconds BEFORE appliesAt, so
        // applyDueChanges runs while the change isn't due yet, does nothing, and
        // the one-shot never fires again — the change then only applies when the
        // app is next opened. Rounding up guarantees the callback lands at-or-
        // after appliesAt, so the change (e.g. a session starting) applies in the
        // background on its own.
        let start = ceilToMinute(max(change.appliesAt, Date().addingTimeInterval(60)), cal)
        let end = start.addingTimeInterval(30 * 60) // ≥15 min interval required
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.year, .month, .day, .hour, .minute],
                                              from: start),
            intervalEnd: cal.dateComponents([.year, .month, .day, .hour, .minute],
                                            from: end),
            repeats: false
        )
        do {
            try DeviceActivityCenter().startMonitoring(
                DeviceActivityName(change.activityName), during: schedule)
        } catch {
            print("Demora: failed to schedule apply activity: \(error)")
        }
    }

    private static func scheduleNotification(for change: PendingChange) {
        let content = UNMutableNotificationContent()
        // Fires when the delay elapses; the change applies on the next wake, so
        // "ready" is accurate where "applied" would be premature. Localized.
        content.title = tr("Your change is ready")
        content.body = change.summary
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, change.appliesAt.timeIntervalSinceNow),
            repeats: false
        )
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: change.id.uuidString,
                                  content: content, trigger: trigger))
    }
}
