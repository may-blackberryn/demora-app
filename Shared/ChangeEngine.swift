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

enum LimitRecheckResult: Equatable {
    case completed(released: Int, confirmed: Int)
    case noBlockedLimits
    case freeWindowActive
    case cooldown(remaining: TimeInterval)
    case unsupportedVersion
    case monitorUnavailable
    case cancelled
}

/// Combined "how hard is this math gate" score, so a config change can be
/// classified stricter vs lenient. Harder level, more problems, and a harsher
/// wrong-answer penalty all increase it.
func mathStrictnessScore(_ difficulty: MathDifficulty, _ count: Int,
                         _ wrong: MathWrongBehavior) -> Int {
    difficulty.rawValue * 1000 + count * 10 + wrong.rawValue
}

enum ChangeEngine {

    /// DeviceActivity talks to Screen Time through synchronous XPC. If its
    /// daemon is slow, making those calls on the main actor can trigger an iOS
    /// watchdog kill. App-driven maintenance and override application are
    /// serialized here so the UI remains responsive and two approval listeners
    /// cannot reconfigure the same monitors concurrently.
    private static let deviceActivityWorkQueue = DispatchQueue(
        label: "app.demora.device-activity-work", qos: .userInitiated)

    static func applyNowOffMain(changeIDs: [UUID]) async -> Int {
        await withCheckedContinuation { continuation in
            deviceActivityWorkQueue.async {
                continuation.resume(returning: applyNow(changeIDs: changeIDs))
            }
        }
    }

    static func housekeepingOffMain() async {
        await withCheckedContinuation { continuation in
            deviceActivityWorkQueue.async {
                housekeeping()
                continuation.resume()
            }
        }
    }

    static func ensureMonitoringOffMain() async {
        await withCheckedContinuation { continuation in
            deviceActivityWorkQueue.async {
                ensureMonitoring(state: SharedStore.loadState())
                continuation.resume()
            }
        }
    }

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
        case .unlockPasswordView:
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
        case .unlockPasswordView:
            return tr("Unlock viewing the stored passcode")
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
        case .unlockPasswordView:
            return "unlockPasswordView"
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
        _ = applyNow(changeIDs: [change.id])
    }

    /// Mark a group due in one store write, then let the normal application
    /// engine merge the whole batch. Deliberately does not stop the pending
    /// activities here: applyDueChanges performs one batched cleanup after the
    /// resulting state is safely persisted.
    @discardableResult
    private static func applyNow(changeIDs: [UUID]) -> Int {
        var state = SharedStore.loadState()
        let requested = Set(changeIDs)
        let matching = state.pending.filter { requested.contains($0.id) }
        guard !matching.isEmpty else {
            #if DEBUG
            print("⚠️ applyNow: requested changes are no longer pending")
            #endif
            return 0
        }
        #if DEBUG
        print("   applyNow OK: \(matching.count) change(s)")
        #endif
        for index in state.pending.indices
        where requested.contains(state.pending[index].id) {
            state.pending[index].appliesAt = .distantPast
        }
        SharedStore.save(state)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: matching.map { $0.id.uuidString })
        applyDueChanges()
        return matching.count
    }

    // MARK: - Applying

    /// Merge every due pending change into the active state, then
    /// reconfigure monitoring/shields. Safe to call from app or extensions.
    static func applyDueChanges() {
        var state = SharedStore.loadState()
        let due = state.pending.filter(\.isDue).sorted { $0.appliesAt < $1.appliesAt }
        guard !due.isEmpty else { return }

        // Starting a session, changing an override, etc. does not alter daily
        // limit events. Restarting the daily monitor for every change exposed
        // us to spurious immediate threshold callbacks from Screen Time.
        let dailyLimitsChanged = due.contains { change in
            switch change.action {
            case .addLimit, .updateLimitMinutes, .removeLimit:
                return true
            default:
                return false
            }
        }

        let windowMonitoringChanged = due.contains { change in
            switch change.action {
            case .addSchedule, .removeSchedule,
                 .addExemption, .removeExemption,
                 .addPlanned, .removePlanned:
                return true
            default:
                return false
            }
        }

        // Capture cleanup targets before mutating the state. Pending-change
        // wake activities are stopped together; removed planned windows and
        // ended sessions also contribute their own activity names.
        var cleanupActivityNames = Set(due.map(\.activityName))
        for change in due {
            switch change.action {
            case .removePlanned(let id):
                if let planned = state.planned.first(where: { $0.id == id }) {
                    cleanupActivityNames.insert(planned.activityName)
                }
            case .endSessionEarly(let id):
                if let session = state.sessions.first(where: { $0.id == id }) {
                    cleanupActivityNames.insert(session.activityName)
                }
            default:
                break
            }
        }
        let sessionIDsBefore = Set(state.sessions.map(\.id))

        for change in due {
            apply(change.action, to: &state)
            state.pending.removeAll { $0.id == change.id }
        }

        // Persist the approved configuration before touching Apple's XPC
        // service. If Screen Time stalls or the process is interrupted, the
        // rule is still committed and the next maintenance pass can self-heal.
        SharedStore.save(state)

        if !SharedStore.simulating && !cleanupActivityNames.isEmpty {
            DeviceActivityCenter().stopMonitoring(cleanupActivityNames.map {
                DeviceActivityName($0)
            })
        }
        for session in state.sessions where !sessionIDsBefore.contains(session.id) {
            startSessionCleanupActivity(session)
        }
        // Reconcile first. If this batch starts a free window, its guard is in
        // place before a genuinely-required daily-monitor restart can deliver
        // callbacks. If it ends one, credit is committed before the restart.
        reconcileFreeWindow()
        if dailyLimitsChanged {
            reconfigureDailyMonitoring(state: state)
        }
        if windowMonitoringChanged {
            reconfigureWindowMonitoring(state: state)
        }
        ShieldController.refresh()
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
            SharedStore.mutateBlockedLimitIDs { blocked in
                blocked.remove(id)
            }
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
            state.planned.removeAll { $0.id == id }
        case .startSession(let name, let kind, let selection, let minutes):
            // The delay already ran (this is apply time) — session starts now.
            let session = BlockSession(
                name: name, kind: kind, selection: selection,
                startedAt: Date(),
                endsAt: Date().addingTimeInterval(TimeInterval(minutes) * 60))
            state.sessions.append(session)
        case .endSessionEarly(let id):
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
        case .unlockPasswordView:
            // Grant one look at the stored passcode (passwordViewReady).
            state.passwordViewUnlockAt = .distantPast
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

    private static let dailyMonitorFingerprintKey =
        "latch.dailyMonitorFingerprint.v2"
#if DEBUG
    // Allow rapid abuse-testing in the separately installed dev build. The
    // verification delay and conservative anti-bypass checks still apply.
    static let limitRecheckCooldown: TimeInterval = 0
#else
    static let limitRecheckCooldown: TimeInterval = 10 * 60
#endif
    private static let limitRecheckVerificationDelay: UInt64 =
        30 * 1_000_000_000

    /// A compact description of everything that changes a daily event's
    /// threshold. Limit selections are immutable after creation; a replacement
    /// gets a new UUID, while minute edits retain the UUID and change the value.
    private static func dailyMonitorFingerprint(state: LatchState) -> String {
        let credit = SharedStore.loadFreeCreditByLimit()
        let limits = state.limits.sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                "\($0.id.uuidString):\($0.minutesPerDay):\(credit[$0.id] ?? 0)"
            }
            .joined(separator: "|")
        return "3;\(SharedStore.dayKey(for: Date()));\(limits)"
    }

    /// Foreground self-healing without tearing down healthy Screen Time
    /// monitors. Genuine configuration changes already reconfigure at their
    /// apply sites; this catches monitors iOS silently dropped, app upgrades,
    /// and an interrupted setup while avoiding iOS 26's restart-triggered
    /// premature threshold callbacks.
    static func ensureMonitoring(state: LatchState) {
        let center = DeviceActivityCenter()
        let running = Set(center.activities.map(\.rawValue))
        let daily = LatchConstants.dailyActivityName
        let shouldHaveDaily = !SharedStore.simulating && !state.limits.isEmpty
        let savedFingerprint = SharedStore.defaults
            .string(forKey: dailyMonitorFingerprintKey)
        let expectedFingerprint = dailyMonitorFingerprint(state: state)

        if shouldHaveDaily {
            if !running.contains(daily)
                || savedFingerprint != expectedFingerprint {
                reconfigureDailyMonitoring(state: state)
            }
        } else {
            if running.contains(daily) {
                reconfigureDailyMonitoring(state: state)
            } else {
                SharedStore.defaults.removeObject(
                    forKey: dailyMonitorFingerprintKey)
            }
        }

        let expectedWindows = expectedWindowActivityNames(state: state)
        let runningWindows = Set(running.filter {
            $0.hasPrefix("sched-") || $0.hasPrefix("exempt-")
                || $0.hasPrefix("planned-")
        })
        if runningWindows != expectedWindows {
            reconfigureWindowMonitoring(state: state)
        } else if !SharedStore.simulating {
            // Echoes are redundant midnight wake-ups. Restore only the missing
            // ones without tearing down healthy enforcement windows.
            startMissingEchoActivities(alreadyRunning: running)
        }
    }

    private static func expectedWindowActivityNames(state: LatchState)
        -> Set<String> {
        guard !SharedStore.simulating else { return [] }
        var names = Set<String>()

        func add(prefix: String, start: Int, end: Int,
                 recurrence: Recurrence) {
            let wraps = start >= end
            switch recurrence {
            case .daily:
                let segments: [(Int, Int)] = wraps
                    ? [(start, 24 * 60 - 1), (0, end)]
                    : [(start, end)]
                for (index, segment) in segments.enumerated() {
                    let paddedEnd = min(max(segment.1, segment.0 + 15),
                                        24 * 60 - 1)
                    if paddedEnd - segment.0 >= 15 {
                        names.insert("\(prefix)-\(index)")
                    }
                }
            case .weekly(let days):
                for day in days {
                    names.insert("\(prefix)-w\(day)")
                }
            case .monthlyDay:
                names.insert("\(prefix)-m")
            case .monthlyOrdinal:
                names.insert("\(prefix)-o")
            }
        }

        for schedule in state.schedules {
            add(prefix: "sched-\(schedule.id.uuidString)",
                start: schedule.startMinutes, end: schedule.endMinutes,
                recurrence: schedule.recurrence)
        }
        for exemption in state.exemptions {
            add(prefix: "exempt-\(exemption.id.uuidString)",
                start: exemption.startMinutes, end: exemption.endMinutes,
                recurrence: exemption.recurrence)
        }
        for planned in state.planned where !planned.isPast {
            names.insert(planned.activityName)
        }
        return names
    }

    /// Conservatively verify existing daily-limit blocks. Current shields stay
    /// in place during the check. Re-registering with includesPastActivity asks
    /// iOS to emit fresh callbacks for genuinely-spent limits; only stale IDs
    /// that receive no fresh callback are released. The events remain armed, so
    /// a late callback immediately restores a legitimate block.
    @MainActor
    static func recheckBlockedLimits() async -> LimitRecheckResult {
        guard #available(iOS 17.4, *) else { return .unsupportedVersion }
        if let last = SharedStore.lastLimitRecheckAt {
            let remaining = limitRecheckCooldown
                - Date().timeIntervalSince(last)
            if remaining > 0 { return .cooldown(remaining: remaining) }
        }
        guard !isFreeWindowActive() else { return .freeWindowActive }

        let state = SharedStore.loadState()
        let eligible = Set(state.limits.filter { $0.minutesPerDay > 0 }
            .map(\.id))
        let candidates = SharedStore.loadBlockedLimitIDs()
            .intersection(eligible)
        guard !candidates.isEmpty else { return .noBlockedLimits }

        let startedAt = Date()
        let controlID = UUID()
        // includeBlockedLimits is essential: normal monitoring omits already
        // spent limits because they need no second event, while this repair
        // specifically needs iOS to confirm each stored block again.
        guard reconfigureDailyMonitoring(state: state,
                                         includeBlockedLimits: true,
                                         recheckControlID: controlID) else {
            // Registration failure means iOS never performed a recheck. Keep
            // every current block rather than treating silence as clearance.
            return .monitorUnavailable
        }
        SharedStore.lastLimitRecheckAt = startedAt
        let verificationFingerprint = dailyMonitorFingerprint(state: state)
        let verificationDay = SharedStore.dayKey(for: Date())

        do {
            try await Task.sleep(nanoseconds: limitRecheckVerificationDelay)
        } catch {
            // Never release a block if the verification task was interrupted.
            return .cancelled
        }

        // Any state transition that replaced the verification monitor makes
        // silence ambiguous. Likewise, never resolve a check across midnight or
        // while a free period has since begun. All of these paths keep blocks.
        guard SharedStore.dayKey(for: Date()) == verificationDay else {
            return .noBlockedLimits
        }
        guard !isFreeWindowActive() else { return .freeWindowActive }
        let dailyStillRunning = DeviceActivityCenter().activities.contains {
            $0.rawValue == LatchConstants.dailyActivityName
        }
        guard dailyStillRunning,
              SharedStore.defaults.string(forKey: dailyMonitorFingerprintKey)
                == verificationFingerprint else {
            return .monitorUnavailable
        }
        // An all-activity 1-minute control event must also have fired. Because a
        // blocked-limit candidate necessarily represents at least one minute
        // of claimed activity, absence of this control means Screen Time is not
        // reliably evaluating the fresh monitor; silence cannot authorize an
        // unblock in that state.
        guard SharedStore.wasLimitRecheckControlConfirmed(controlID) else {
            return .monitorUnavailable
        }

        let confirmed = SharedStore.limitsConfirmedSince(startedAt,
                                                          among: candidates)
        let stale = candidates.subtracting(confirmed)
        if !stale.isEmpty {
            SharedStore.mutateBlockedLimitIDs { blocked in
                blocked.subtract(stale)
            }
        }
        ShieldController.refresh()
        return .completed(released: stale.count, confirmed: confirmed.count)
    }

    /// Ask iOS for an extra extension wake this long BEFORE each interval
    /// boundary (intervalWillStart/EndWarning). Shields are recomputed from
    /// the wall clock on every wake, so each warning is a free chance to
    /// self-heal a transition whose main callback gets dropped.
    private static let boundaryWarning = DateComponents(minute: 5)

    /// One repeating daily schedule with a per-limit threshold event. The
    /// threshold is the day's minutes plus the free-period credit *that limit*
    /// earned today (its measured usage inside ended free windows), so time
    /// spent while a free window lifted the shields never counts against the
    /// real limit — and untouched limits get no extra time. On iOS 17.4+
    /// `includesPastActivity` makes the event fire at the true daily total
    /// regardless of monitoring restarts.
    @discardableResult
    static func reconfigureDailyMonitoring(
        state: LatchState,
        includeBlockedLimits: Bool = false,
        recheckControlID: UUID? = nil
    ) -> Bool {
        // Optimistic reset; any startMonitoring failure below (or in the window
        // pass that follows) flips it back on. Drives the "enforcement degraded"
        // banner.
        SharedStore.enforcementDegraded = false
        let credit = SharedStore.loadFreeCreditByLimit()
        let center = DeviceActivityCenter()
        let daily = DeviceActivityName(LatchConstants.dailyActivityName)
        center.stopMonitoring([daily])
        // Tutorial simulation: don't start any real limit monitoring.
        if SharedStore.simulating {
            SharedStore.defaults.removeObject(forKey: dailyMonitorFingerprintKey)
            return false
        }
        guard !state.limits.isEmpty else {
            SharedStore.defaults.removeObject(forKey: dailyMonitorFingerprintKey)
            return false
        }

        let blocked = SharedStore.loadBlockedLimitIDs()
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

        for limit in state.limits {
            // A 0-minute limit is always blocked (handled by the shield), and a
            // limit already at its cap stays blocked — neither needs an event.
            if limit.minutesPerDay == 0
                || (!includeBlockedLimits && blocked.contains(limit.id)) {
                continue
            }

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

        if let recheckControlID, #available(iOS 17.4, *) {
            // Empty selections mean all activity. This independent event proves
            // the newly-created monitor is actually evaluating past activity;
            // without it, a missing limit callback is not evidence of anything.
            events[DeviceActivityEvent.Name(
                "recheck-control-\(recheckControlID.uuidString)")] =
                DeviceActivityEvent(
                    threshold: thresholdComponents(minutes: 1),
                    includesPastActivity: true)
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true,
            warningTime: boundaryWarning
        )
        do {
            try center.startMonitoring(daily, during: schedule, events: events)
            SharedStore.defaults.set(dailyMonitorFingerprint(state: state),
                                     forKey: dailyMonitorFingerprintKey)
            return true
        } catch {
            print("Demora: failed to start daily monitoring: \(error)")
            SharedStore.defaults.removeObject(forKey: dailyMonitorFingerprintKey)
            SharedStore.enforcementDegraded = true
            return false
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
                || $0.rawValue.hasPrefix("echo-")
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
                repeats: false,
                warningTime: boundaryWarning
            )
            do {
                try center.startMonitoring(
                    DeviceActivityName(w.activityName), during: schedule)
            } catch {
                print("Demora: failed to schedule planned window: \(error)")
                SharedStore.enforcementDegraded = true
            }
        }

        // Post-midnight echoes: fixed activities whose only job is waking the
        // extension shortly after midnight (00:05, 01:00, 06:00) so a missed
        // midnight rollover gets retried — the 06:00 sweep lands before most
        // people pick up their phone. The rollover is day-key-gated, so these
        // are no-ops whenever the midnight reset already ran. Registered LAST so
        // real enforcement activities claim the ~20-activity budget first: a
        // dropped echo is tolerated redundancy (no enforcementDegraded), whereas
        // a dropped schedule/window is real lost enforcement.
        startMissingEchoActivities(alreadyRunning: [])
    }

    /// Register only absent post-midnight echo activities. These are fallback
    /// wakes, not enforcement rules, so a failure is tolerated and never causes
    /// healthy schedule/free-period monitors to be restarted on every launch.
    private static func startMissingEchoActivities(
        alreadyRunning: Set<String>
    ) {
        let center = DeviceActivityCenter()
        for (i, w) in [(5, 35), (60, 90), (360, 390)].enumerated() {
            let name = "echo-\(i)"
            if alreadyRunning.contains(name) { continue }
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: w.0 / 60, minute: w.0 % 60),
                intervalEnd: DateComponents(hour: w.1 / 60, minute: w.1 % 60),
                repeats: true,
                warningTime: boundaryWarning)
            do {
                try center.startMonitoring(DeviceActivityName(name),
                                           during: schedule)
            } catch {
                print("Demora: failed to start echo activity \(i): \(error)")
            }
        }
    }

    private static func startWindowActivities(prefix: String, start: Int,
                                              end: Int, recurrence: Recurrence) {
        let center = DeviceActivityCenter()
        func register(_ name: String, _ s: DateComponents, _ e: DateComponents) {
            let schedule = DeviceActivitySchedule(intervalStart: s,
                                                  intervalEnd: e, repeats: true,
                                                  warningTime: boundaryWarning)
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
            repeats: false,
            warningTime: boundaryWarning
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
        // A free session may have just expired — credit its in-window usage.
        reconcileFreeWindow()
        ShieldController.refresh()
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
    static func isFreeWindowActive() -> Bool {
        let state = SharedStore.loadState()
        return state.exemptions.contains { $0.isActive() }
            || state.planned.contains { $0.kind == .free && $0.isActive }
            || state.sessions.contains { $0.kind == .free && $0.isActive }
    }

    static func reconcileFreeWindow() {
        let active = isFreeWindowActive()
        let running = SharedStore.freeWindowStart != nil
        if active && !running { exemptWindowStarted() }
        else if !active && running { exemptWindowEnded() }
    }

    static func exemptWindowStarted() {
        // Don't reset an already-running window (overlapping free periods).
        if SharedStore.freeWindowStart == nil {
            // Preserve real pre-window blocks. Threshold callbacks can arrive
            // while shields are lifted, but free-window usage must never create
            // a new persistent block that appears when the window closes.
            SharedStore.freeWindowBlockedSnapshot =
                SharedStore.loadBlockedLimitIDs()
            SharedStore.clearFreeWindowSuppressedLimitIDs()
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
    /// to its daily budget, restore the exact set of limits blocked before the
    /// window, and rearm events only if usage or a suppressed callback requires
    /// it. Limits untouched during the window get no credit or new block.
    static func exemptWindowEnded() {
        DeviceActivityCenter().stopMonitoring(
            [DeviceActivityName(freeWindowActivityName)])
        var shouldRearmDailyMonitoring = false
        if SharedStore.freeWindowStart != nil {
            let usage = SharedStore.loadFreeWindowUsage()
            let suppressed = SharedStore.loadFreeWindowSuppressedLimitIDs()
            var credit = SharedStore.loadFreeCreditByLimit()
            for (id, minutes) in usage where minutes > 0 {
                credit[id, default: 0] += min(minutes, 24 * 60)
            }
            SharedStore.saveFreeCreditByLimit(credit)

            if let snapshot = SharedStore.freeWindowBlockedSnapshot {
                // Restore exactly the limits that were spent before the free
                // window. New threshold callbacks were either free usage or a
                // spurious Screen Time callback and must not survive it.
                let validIDs = Set(SharedStore.loadState().limits.map(\.id))
                SharedStore.saveBlockedLimitIDs(snapshot.intersection(validIDs))
            } else if !usage.isEmpty {
                // Migration fallback for a free window started by an older app
                // version that did not save a pre-window snapshot.
                SharedStore.mutateBlockedLimitIDs { blocked in
                    blocked.subtract(usage.keys)
                }
            }

            SharedStore.saveFreeWindowUsage([:])
            SharedStore.freeWindowStart = nil
            SharedStore.freeWindowBlockedSnapshot = nil
            SharedStore.clearFreeWindowSuppressedLimitIDs()

            // No limited app usage and no suppressed callback means the daily
            // monitor is still valid. Avoiding an unnecessary restart avoids
            // the iOS immediate-threshold regression altogether.
            shouldRearmDailyMonitoring = !usage.isEmpty || !suppressed.isEmpty
        }
        if shouldRearmDailyMonitoring {
            reconfigureDailyMonitoring(state: SharedStore.loadState())
        }
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
            repeats: false,
            warningTime: boundaryWarning
        )
        do {
            try DeviceActivityCenter().startMonitoring(
                DeviceActivityName(change.activityName), during: schedule)
        } catch {
            print("Demora: failed to schedule apply activity: \(error)")
        }
    }

    // MARK: - Midnight reset nudge

    /// Scheduled when a limit blocks: a notification for 00:10 that only
    /// survives if NO reset ran by then — every reset path cancels it via
    /// `cancelResetNudge()`. Tapping it opens the app, whose foreground
    /// rollover clears the stale shields. This turns the worst case from
    /// "user must guess to open the app" into "user gets told to tap".
    static func scheduleResetNudge() {
        let content = UNMutableNotificationContent()
        content.title = tr("Your limits have reset")
        content.body = tr("If any apps still look blocked, open Demora to refresh them.")
        content.sound = .default
        let cal = Calendar.current
        guard let midnight = cal.date(byAdding: .day, value: 1,
                                      to: cal.startOfDay(for: Date()))
        else { return }
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute],
                                       from: midnight.addingTimeInterval(10 * 60))
        // Stable identifier: multiple limits blocking the same day collapse
        // into one pending nudge (each add replaces the previous request).
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: LatchConstants.resetNudgeID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps,
                                                   repeats: false)))
    }

    /// A day rollover actually ran — the nudge is moot. Also removes one
    /// that already fired (e.g. an echo reset at 01:00 beat the user to it).
    static func cancelResetNudge() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: [LatchConstants.resetNudgeID])
        center.removeDeliveredNotifications(
            withIdentifiers: [LatchConstants.resetNudgeID])
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
