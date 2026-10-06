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
import CryptoKit

enum LimitRecheckResult: Equatable {
    case completed(released: Int, confirmed: Int)
    case noBlockedLimits
    case splitBlocksNotRecheckable
    case freeWindowActive
    case cooldown(remaining: TimeInterval)
    case unsupportedVersion
    case monitorUnavailable
    case cancelled
}

enum GlobalWakeStatus: Equatable {
    case inactive, needsTap, waiting(Date), awake
}

/// A single daily tap gate shared by the selected apps/groups. The schedule is
/// wall-clock based; only the elapsed wait uses TimeGuard. Extension callbacks
/// read the same App Group state and never depend on Demora's window staying open.
enum GlobalWake {
    private static let dayKey = "latch.globalWake.day.v1"
    private static let releaseKey = "latch.globalWake.release.v1"
    private static let activity = DeviceActivityName("global-wake-release")

    static func status(state: LatchState, at date: Date = Date()) -> GlobalWakeStatus {
        let rule = state.wakeRule
        let clock = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
        guard rule.enabled, rule.weekdays.contains(Calendar.current.component(.weekday, from: date)),
              minute >= rule.startHour * 60 else { return .inactive }
        guard SharedStore.defaults.string(forKey: dayKey)
                == SharedStore.dayKey(for: date),
              let release = SharedStore.defaults.object(forKey: releaseKey) as? Date
        else { return .needsTap }
        return TimeGuard.now() < release ? .waiting(release) : .awake
    }

    @discardableResult
    static func tap() -> Bool {
        guard !SharedStore.simulating else { return false }
        let state = SharedStore.loadState()
        guard status(state: state) == .needsTap else { return false }
        let release = TimeGuard.now().addingTimeInterval(
            TimeInterval(state.wakeRule.waitMinutes) * 60)
        SharedStore.defaults.set(release, forKey: releaseKey)
        SharedStore.defaults.set(SharedStore.dayKey(for: Date()), forKey: dayKey)
        if state.wakeRule.waitMinutes > 0 { scheduleRelease(at: release) }
        ShieldController.refresh()
        return true
    }

    static func clearTap() {
        SharedStore.defaults.removeObject(forKey: dayKey)
        SharedStore.defaults.removeObject(forKey: releaseKey)
        DeviceActivityCenter().stopMonitoring([activity])
    }

    static func reconcile(state: LatchState, running: Set<String>? = nil) {
        let activities = running ?? Set(DeviceActivityCenter().activities.map(\.rawValue))
        if case .waiting(let release) = status(state: state) {
            if !activities.contains(activity.rawValue) { scheduleRelease(at: release) }
        } else if activities.contains(activity.rawValue) {
            DeviceActivityCenter().stopMonitoring([activity])
        }
    }

    private static func scheduleRelease(at release: Date) {
        let calendar = Calendar.current
        let wallRelease = Date().addingTimeInterval(max(0, release.timeIntervalSince(TimeGuard.now())))
        let future = max(wallRelease, Date().addingTimeInterval(60))
        let floor = calendar.date(from: calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: future)) ?? future
        let start = floor >= future ? floor : floor.addingTimeInterval(60)
        let end = start.addingTimeInterval(16 * 60)
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: start),
            intervalEnd: calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: end),
            repeats: false)
        do {
            try MonitorRegistration.start(activity, during: schedule)
        } catch {
            NSLog("Demora: global wake release monitor failed: %@", String(describing: error))
            SharedStore.enforcementDegraded = true
        }
    }
}

/// Combined "how hard is this math gate" score, so a config change can be
/// classified stricter vs lenient. Harder level, more problems, and a harsher
/// wrong-answer penalty all increase it.
func mathStrictnessScore(_ difficulty: MathDifficulty, _ count: Int,
                         _ wrong: MathWrongBehavior) -> Int {
    difficulty.rawValue * 1000 + count * 10 + wrong.rawValue
}

enum ChangeEngine {

    static func wakeState(for limit: AppLimit) -> WakeState {
        LimitFeatures.wakeState(for: limit)
    }

    @discardableResult
    static func wakeUp(limitID: UUID) -> Bool {
        LimitFeatures.wakeUp(limitID: limitID)
    }

    static func wakeUpOffMain(limitID: UUID) async -> Bool {
        await withCheckedContinuation { continuation in
            deviceActivityWorkQueue.async {
                applyDueChanges()
                continuation.resume(returning: LimitFeatures.wakeUp(limitID: limitID))
            }
        }
    }

    static func wakeUpGlobalOffMain() async -> Bool {
        await withCheckedContinuation { continuation in
            deviceActivityWorkQueue.async {
                continuation.resume(returning: GlobalWake.tap())
            }
        }
    }

    /// One tap also starts eligible legacy gates; existing waits are never reset.
    static func wakeUpAllOffMain() async -> Bool {
        await withCheckedContinuation { continuation in
            deviceActivityWorkQueue.async {
                applyDueChanges()
                var changed = DayNightWake.tapAll()
                if GlobalWake.status(state: SharedStore.loadState()) == .needsTap {
                    changed = GlobalWake.tap() || changed
                }
                for limit in SharedStore.loadState().limits {
                    if LimitFeatures.wakeState(for: limit) == .needsTap {
                        changed = LimitFeatures.wakeUp(limitID: limit.id) || changed
                    }
                }
                ShieldController.refresh()
                continuation.resume(returning: changed)
            }
        }
    }

    static func setUpInitialDayNightOffMain(_ groups: [DayNightGroup]) async -> Bool {
        await withCheckedContinuation { continuation in
            deviceActivityWorkQueue.async {
                MonitorRegistration.clearRejection()
                let running = Set(DeviceActivityCenter().activities.map(\.rawValue))
                let saved = SharedStore.coordinateStateMutation {
                    guard !SharedStore.stateRecoveryNeeded, !SharedStore.isReplaying else { return false }
                    let state = SharedStore.loadState()
                    guard let updated = SharedStore.initialDayNightState(groups, state: state,
                                                                          in: SharedStore.defaults)
                    else { return false }
                    guard MonitorRegistration.admit(state: updated, running: running) else { return false }
                    return SharedStore.save(updated)
                } ?? false
                if saved { ensureMonitoring(state: SharedStore.loadState()) }
                continuation.resume(returning: saved)
            }
        }
    }

    static func requestExtraTimeOffMain(limitID: UUID,
                                        candidateHash: String? = nil,
                                        phraseProofID: UUID? = nil) async -> Bool {
        await withCheckedContinuation { continuation in
            deviceActivityWorkQueue.async {
                // Commit overdue policy/limit edits before the grant checks
                // read their state, on the same serialized enforcement queue.
                applyDueChanges()
                continuation.resume(returning: LimitFeatures.requestExtraTime(
                    limitID: limitID, candidateHash: candidateHash,
                    phraseProofID: phraseProofID))
            }
        }
    }

    /// DeviceActivity talks to Screen Time through synchronous XPC. If its
    /// daemon is slow, making those calls on the main actor can trigger an iOS
    /// watchdog kill. App-driven maintenance and override application are
    /// serialized here so the UI remains responsive and two approval listeners
    /// cannot reconfigure the same monitors concurrently.
    private static let deviceActivityWorkQueue = DispatchQueue(
        label: "app.demora.device-activity-work", qos: .userInitiated)

    static func replaceLegacyMathOffMain(with policies: [PhrasePolicy]) async -> Bool {
        await withCheckedContinuation { continuation in
            deviceActivityWorkQueue.async {
                let saved = SharedStore.coordinateStateMutation {
                    guard !SharedStore.stateRecoveryNeeded else { return false }
                    let state = SharedStore.loadState()
                    guard let replacement = SharedStore.mathReplacementState(
                        policies, state: state, in: SharedStore.defaults),
                          SharedStore.save(replacement) else { return false }
                    SharedStore.defaults.set(true, forKey: SharedStore.mathReplacementConsumedKey)
                    // The verified blob already consumes the offer. A failure
                    // of the redundant marker must not report a failed install.
                    return true
                } ?? false
                continuation.resume(returning: saved)
            }
        }
    }

    static func applyNowOffMain(changeIDs: [UUID]) async -> Int {
        await withCheckedContinuation { continuation in
            deviceActivityWorkQueue.async {
                continuation.resume(returning: applyNow(changeIDs: changeIDs))
            }
        }
    }

    /// Re-read the policy and every requested change on the serialized
    /// enforcement queue. A stale UI cannot use a removed policy or apply a
    /// change outside its permitted area.
    static func applyNowWithPasswordOffMain(changeIDs: [UUID], policyID: UUID,
                                            candidateHash: String) async -> Int {
        await withCheckedContinuation { continuation in
            deviceActivityWorkQueue.async {
                applyDueChanges()
                let state = SharedStore.loadState()
                let requested = Set(changeIDs)
                let matching = state.pending.filter { requested.contains($0.id) }
                guard !hasUnappliedDueChanges(state),
                      !matching.isEmpty, matching.count == requested.count,
                      let policy = state.overrides.passwordPolicies.first(where: {
                          $0.id == policyID && $0.hash == candidateHash
                      }),
                      matching.allSatisfy({ change in
                          guard let area = overrideCapability(for: change.action) else {
                              return false
                          }
                          return policy.allowed.contains(area)
                      }) else {
                    continuation.resume(returning: 0)
                    return
                }
                continuation.resume(returning: applyNow(changeIDs: changeIDs) { fresh, changes in
                    changes == matching
                        && fresh.overrides.passwordPolicies.contains(policy)
                })
            }
        }
    }

    static func applyNowWithPhraseOffMain(changeIDs: [UUID], policyID: UUID,
                                          proofID: UUID) async -> Int {
        await withCheckedContinuation { continuation in
            deviceActivityWorkQueue.async {
                applyDueChanges()
                let state = SharedStore.loadState()
                let requested = Set(changeIDs)
                let matching = state.pending.filter { requested.contains($0.id) }
                guard !hasUnappliedDueChanges(state),
                      !matching.isEmpty, matching.count == requested.count,
                      let policy = state.overrides.phrasePolicies.first(where: {
                          $0.id == policyID
                      }),
                      matching.allSatisfy({ change in
                          guard let area = overrideCapability(for: change.action) else {
                              return false
                          }
                          return policy.allowed.contains(area)
                      }),
                      PhraseChallenges.consume(proofID, policy: policy,
                                               scope: .changes(changeIDs.sorted {
                                                   $0.uuidString < $1.uuidString
                                               })) else {
                    continuation.resume(returning: 0)
                    return
                }
                continuation.resume(returning: applyNow(changeIDs: changeIDs) { fresh, changes in
                    changes == matching
                        && fresh.overrides.phrasePolicies.contains(policy)
                })
            }
        }
    }

    enum ContactApprovalSource {
        case relay(contactIDs: [UUID], approvedCodes: Set<String>)
        case email(contactIDs: [UUID])
    }

    /// Contact permissions are checked on the same serialized queue that
    /// applies the changes. A permission edit taking effect while a request is
    /// outstanding cannot leave a stale approval capable of skipping a wait.
    static func applyNowWithContactOffMain(changeIDs: [UUID],
                                           source: ContactApprovalSource) async -> Int {
        await withCheckedContinuation { continuation in
            deviceActivityWorkQueue.async {
                applyDueChanges()
                let state = SharedStore.loadState()
                let ids = Set(changeIDs)
                let matching = state.pending.filter { ids.contains($0.id) }
                let areas = matching.compactMap { overrideCapability(for: $0.action) }
                guard !hasUnappliedDueChanges(state),
                      state.overrides.contactsEnabled,
                      !matching.isEmpty, matching.count == ids.count,
                      areas.count == matching.count else {
                    continuation.resume(returning: 0)
                    return
                }
                let required = Set(areas)
                let permitted = contactPermitted(source, state: state,
                                                 required: required)
                continuation.resume(returning: permitted
                    ? applyNow(changeIDs: changeIDs) { fresh, changes in
                        changes == matching
                            && contactPermitted(source, state: fresh, required: required)
                    } : 0)
            }
        }
    }

    private static func contactPermitted(_ source: ContactApprovalSource,
                                         state: LatchState,
                                         required: Set<OverrideCapability>) -> Bool {
        guard state.overrides.contactsEnabled else { return false }
        switch source {
        case .relay(let contactIDs, let approvedCodes):
            return !contactIDs.isEmpty && state.overrides.contacts.contains { contact in
                contactIDs.contains(contact.id) && contact.isUsable
                    && required.isSubset(of: contact.allowed)
                    && contact.latchUserCode.map(approvedCodes.contains) == true
            }
        case .email(let contactIDs):
            // The Worker uses one code for all recipients. Every recipient
            // must remain permitted because the code cannot identify which
            // person supplied it.
            return !contactIDs.isEmpty && contactIDs.allSatisfy { id in
                state.overrides.contacts.contains { contact in
                    contact.id == id && contact.isEmail && contact.isUsable
                        && required.isSubset(of: contact.allowed)
                }
            }
        }
    }

    static func grantContactExtraTimeOffMain(context: ExtraContactContext,
                                             source: ContactApprovalSource) async -> Bool {
        await withCheckedContinuation { continuation in
            deviceActivityWorkQueue.async {
                applyDueChanges()
                let state = SharedStore.loadState()
                guard !hasUnappliedDueChanges(state),
                      contactPermitted(source, state: state, required: [.extraTime]),
                      context.day == SharedStore.dayKey(for: TimeGuard.now()),
                      let limit = state.limits.first(where: { $0.id == context.limitID }),
                      let steps = limit.extraTime?.effectiveSteps,
                      steps.indices.contains(context.stepIndex),
                      steps[context.stepIndex] == context.step,
                      context.step.contactRequired,
                      case .ready(let remaining) = LimitFeatures.extraTimeState(for: limit),
                      context.stepIndex == steps.count - remaining else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: LimitFeatures.requestExtraTime(
                    limitID: context.limitID, contactValidator: { fresh, index, step in
                        context.day == SharedStore.dayKey(for: TimeGuard.now())
                            && context.stepIndex == index && context.step == step
                            && contactPermitted(source, state: fresh, required: [.extraTime])
                    }))
            }
        }
    }

    static func overrideCapability(for action: ChangeAction) -> OverrideCapability? {
        switch action {
        case .addLimit, .updateLimitMinutes, .updateLimit, .configureLimit,
             .removeLimit, .setGroupWakeDelay, .setGroupWakeSchedule, .setWakeRule, .setSleepRule:
            return .limitChanges
        case .addSchedule, .updateScheduleSelection, .removeSchedule,
             .upsertDayNightGroup, .removeDayNightGroup,
             .addExemption, .removeExemption,
             .addPlanned, .removePlanned:
            return .scheduleChanges
        case .startSession, .endSessionEarly: return .sessionChanges
        case .setDelayPolicy, .setStrictDelay, .setLenientDelay: return .delayChanges
        case .setBlockAppRemoval, .setBlockAdultWebsites,
             .addBlockedDomain, .removeBlockedDomain,
             .unlockPreventGuide, .unlockPasswordView:
            return .protectionChanges
        case .setContactsOverride, .addContact, .removeContact:
            return .contactChanges
        case .setMathOverride, .setPasswordOverride, .upsertPasswordPolicy,
             .removePasswordPolicy, .upsertPhrasePolicy, .removePhrasePolicy,
             .setContactPermissions:
            return nil // self-override policies never edit themselves instantly
        }
    }

    static func hasOverride(for changes: [PendingChange], state: LatchState) -> Bool {
        guard !changes.isEmpty else { return false }
        if state.overrides.contactsEnabled,
           state.overrides.contacts.contains(where: { contact in
               contact.isUsable && changes.allSatisfy { change in
                   guard let area = overrideCapability(for: change.action) else {
                       return false
                   }
                   return contact.allowed.contains(area)
               }
           }) { return true }
        return state.overrides.passwordPolicies.contains { policy in
            changes.allSatisfy { change in
                guard let area = overrideCapability(for: change.action) else {
                    return false
                }
                return policy.allowed.contains(area)
            }
        } || state.overrides.phrasePolicies.contains { policy in
            changes.allSatisfy { change in
                guard let area = overrideCapability(for: change.action) else {
                    return false
                }
                return policy.allowed.contains(area)
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
        case .setGroupWakeSchedule(let id, let minutes, let schedule):
            guard let minutes else { return .lenient }
            guard let old = state.limits.first(where: { $0.id == id }), let oldWait = old.wakeDelayMinutes else { return .stricter }
            return schedule.noLooser(than: old.wakeSchedule ?? LimitWakeSchedule(), wait: minutes, oldWait: oldWait) ? .stricter : .lenient
        case .setGroupWakeDelay(let id, let minutes):
            let old = state.limits.first { $0.id == id }?.wakeDelayMinutes
            guard let minutes else { return .lenient }
            return old.map { minutes >= $0 ? .stricter : .lenient } ?? .stricter
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
        case .updateLimit(let id, let selection, let minutes):
            guard let current = state.limits.first(where: { $0.id == id })
            else { return .stricter }
            // Adding, removing, or changing selected apps/categories/websites
            // always waits through the less-strict delay, per product policy.
            if selection != current.selection { return .lenient }
            if minutes < current.minutesPerDay { return .stricter }
            if minutes > current.minutesPerDay { return .lenient }
            return .stricter
        case .configureLimit(let updated):
            guard let old = state.limits.first(where: { $0.id == updated.id })
            else { return .stricter }
            if updated.selection != old.selection { return .lenient }
            // An edit combining tightening and loosening must take the slower
            // less-strict path. New advanced rules default there unless their
            // only change is enabling/lengthening a wake gate.
            if updated.split != old.split || updated.extraTime != old.extraTime {
                return .lenient
            }
            if let oldWait = old.wakeDelayMinutes,
               (updated.wakeDelayMinutes == nil || !(updated.wakeSchedule ?? LimitWakeSchedule())
                .noLooser(than: old.wakeSchedule ?? LimitWakeSchedule(), wait: updated.wakeDelayMinutes ?? 0, oldWait: oldWait)) {
                return .lenient
            }
            for day in 1...7 {
                let before = old.weekdayMinutes[day] ?? old.minutesPerDay
                let after = updated.weekdayMinutes[day] ?? updated.minutesPerDay
                if after > before { return .lenient }
            }
            return .stricter
        case .setStrictDelay(let new):
            return state.delayPolicy.replacing(.stricter, with: new).direction(comparedTo: state.delayPolicy)
        case .setLenientDelay(let new):
            return state.delayPolicy.replacing(.lenient, with: new).direction(comparedTo: state.delayPolicy)
        case .setDelayPolicy(let policy):
            return policy.direction(comparedTo: state.delayPolicy)
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
        case .upsertPasswordPolicy:
            return .lenient
        case .removePasswordPolicy:
            return .stricter
        case .upsertPhrasePolicy:
            return .lenient
        case .removePhrasePolicy:
            return .stricter
        case .setContactsOverride(let enabled):
            return enabled ? .lenient : .stricter
        case .setWakeRule(let rule):
            return rule.enabled && !state.wakeRule.enabled ? .stricter : .lenient
        case .setSleepRule(let rule):
            return rule.enabled && !state.sleepRule.enabled ? .stricter : .lenient
        case .upsertDayNightGroup(let group):
            guard let old = state.dayNightGroups.first(where: { $0.id == group.id }) else {
                return state.dayNightGroups.contains(where: { $0.scope.mode == .allOtherApps })
                    ? .lenient : .stricter
            }
            return group.scope == old.scope && group.weekdays == old.weekdays
                && group.timingNoLooser(than: old) && group.sleepStartMinutes == old.sleepStartMinutes
                && (!old.wakeEnabled || group.wakeEnabled) && (!old.sleepEnabled || group.sleepEnabled)
                ? .stricter : .lenient
        case .removeDayNightGroup:
            return .lenient
        case .addContact:
            return .lenient    // another way to bypass = less strict
        case .removeContact:
            return .stricter   // fewer ways to bypass = stricter
        case .setContactPermissions(let id, let allowed):
            guard let old = state.overrides.contacts.first(where: { $0.id == id })?.allowed
            else { return .lenient }
            return allowed.isSubset(of: old) ? .stricter : .lenient
        case .addSchedule:
            return .stricter
        case .updateScheduleSelection:
            // Same policy as limit-group selection edits, in either mode:
            // additions, removals and replacements are always less strict.
            return .lenient
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
        case .setGroupWakeSchedule(let id, _, _):
            let name = state.limits.first { $0.id == id }?.name ?? tr("group")
            return String(format: tr("Change wake-up schedule for %@"), name)
        case .setGroupWakeDelay(let id, let minutes):
            let name = state.limits.first { $0.id == id }?.name ?? tr("group")
            return minutes.map { String(format: tr("Wake-up for %@: %d minutes"), name, $0) }
                ?? String(format: tr("Turn off wake-up for %@"), name)
        case .addLimit(let l):
            return String(format: tr("Add limit: %@ — %d min/day"),
                          l.name, l.minutesPerDay)
        case .updateLimitMinutes(let id, let m):
            let name = state.limits.first { $0.id == id }?.name ?? tr("limit")
            return String(format: tr("Change %@ to %d min/day"), name, m)
        case .updateLimit(let id, let selection, let minutes):
            guard let current = state.limits.first(where: { $0.id == id })
            else { return tr("Change limit") }
            if selection != current.selection {
                if minutes != current.minutesPerDay {
                    return String(format: tr("Change apps and daily limit for %@ to %d min/day"),
                                  current.name, minutes)
                }
                return String(format: tr("Change apps in %@"), current.name)
            }
            return String(format: tr("Change %@ to %d min/day"),
                          current.name, minutes)
        case .configureLimit(let limit):
            return String(format: tr("Change limit: %@"), limit.name)
        case .removeLimit(let id):
            let name = state.limits.first { $0.id == id }?.name ?? tr("limit")
            return String(format: tr("Remove limit: %@"), name)
        case .setStrictDelay(let t):
            return String(format: tr("Set 'more strict' delay to %@"),
                          t.shortDelayLabel)
        case .setLenientDelay(let t):
            return String(format: tr("Set 'less strict' delay to %@"),
                          t.shortDelayLabel)
        case .setDelayPolicy(let policy):
            return String(format: tr("Change delays: %@"), policy.mode.label)
        case .setMathOverride(let on, let d, let count, _):
            return on ? String(format: tr("Enable math override (%@, %d problems)"),
                               d?.label ?? "—", count)
                      : tr("Disable math override")
        case .setPasswordOverride(let on, _):
            return on ? tr("Enable/update password override")
                      : tr("Disable password override")
        case .upsertPasswordPolicy(let policy):
            return String(format: tr("Add or change password: %@"), policy.name)
        case .removePasswordPolicy(let id):
            let name = state.overrides.passwordPolicies.first { $0.id == id }?.name
                ?? tr("password")
            return String(format: tr("Remove password: %@"), name)
        case .upsertPhrasePolicy(let policy):
            return String(format: tr("Add or change phrase: %@"), policy.name)
        case .removePhrasePolicy(let id):
            let name = state.overrides.phrasePolicies.first { $0.id == id }?.name
                ?? tr("phrase")
            return String(format: tr("Remove phrase: %@"), name)
        case .setContactsOverride(let on):
            return on ? tr("Enable trusted-contact override")
                      : tr("Disable trusted-contact override")
        case .setWakeRule:
            return tr("Change wake-up blocking")
        case .setSleepRule:
            return tr("Change sleep blocking")
        case .upsertDayNightGroup(let group):
            return String(format: tr("Add or change day/night group: %@"), group.name)
        case .removeDayNightGroup(let id):
            return String(format: tr("Remove day/night group: %@"),
                          state.dayNightGroups.first(where: { $0.id == id })?.name ?? tr("Group"))
        case .addContact(let contact):
            return String(format: tr("Add trusted contact: %@"), contact.name)
        case .removeContact(let id):
            let name = state.overrides.contacts
                .first { $0.id == id }?.name ?? tr("contact")
            return String(format: tr("Remove trusted contact: %@"), name)
        case .setContactPermissions(let id, _):
            let name = state.overrides.contacts
                .first { $0.id == id }?.name ?? tr("contact")
            return String(format: tr("Change trusted-contact permissions: %@"), name)
        case .addSchedule(let s):
            return String(format: tr("Add schedule: %@ (%@ %@)"),
                          s.name, s.mode.label, s.windowLabel)
        case .updateScheduleSelection(let id, _):
            let name = state.schedules.first { $0.id == id }?.name ?? tr("schedule")
            return String(format: tr("Change apps in %@"), name)
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
        case .updateLimitMinutes(let id, _), .updateLimit(let id, _, _),
             .removeLimit(let id), .setGroupWakeDelay(let id, _), .setGroupWakeSchedule(let id, _, _):
            return "limit-\(id.uuidString)"
        case .configureLimit(let limit):
            return "limit-\(limit.id.uuidString)"
        case .setDelayPolicy, .setStrictDelay, .setLenientDelay:
            return "delayPolicy"
        case .setMathOverride:
            return "mathOverride"
        case .setPasswordOverride:
            return "passwordOverride"
        case .upsertPasswordPolicy(let policy):
            return "passwordPolicy-\(policy.id.uuidString)"
        case .removePasswordPolicy(let id):
            return "passwordPolicy-\(id.uuidString)"
        case .upsertPhrasePolicy(let policy):
            return "phrasePolicy-\(policy.id.uuidString)"
        case .removePhrasePolicy(let id):
            return "phrasePolicy-\(id.uuidString)"
        case .setContactsOverride:
            return "contactsOverride"
        case .setWakeRule:
            return "wakeRule"
        case .setSleepRule:
            return "sleepRule"
        case .upsertDayNightGroup, .removeDayNightGroup:
            // Scope/fallback validation spans groups; serialize collection edits.
            return "dayNightGroups"
        case .addContact(let c):
            return "addContact-\(c.detail.lowercased())"
        case .removeContact(let id):
            return "contact-\(id.uuidString)"
        case .setContactPermissions(let id, _):
            return "contact-\(id.uuidString)"
        case .addSchedule(let s):
            return "addSchedule-\(s.name.lowercased())"
        case .updateScheduleSelection(let id, _), .removeSchedule(let id):
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
        MonitorRegistration.clearRejection()
        // Old UI types remain Codable for state compatibility, but these
        // retired overrides must never enter the queue again.
        switch action {
        case .setMathOverride, .setPasswordOverride: return nil
        default: break
        }
        let running = Set(DeviceActivityCenter().activities.map(\.rawValue))
        let queued: PendingChange? = SharedStore.coordinateStateMutation {
            queueCoordinated(action, running: running)
        } ?? nil
        guard let change = queued else { return nil }
        if change.appliesAt > TimeGuard.now() {
            scheduleApplyActivity(for: change)
            scheduleNotification(for: change)
        }
        applyDueChanges() // immediate tightening still applies without waiting
        return change
    }

    /// Pure validation/admission plus persistence under state coordination.
    /// No DeviceActivity or notification calls may run while the lock is held.
    private static func queueCoordinated(_ action: ChangeAction, running: Set<String>) -> PendingChange? {
        var state = SharedStore.loadState()
        guard !SharedStore.stateRecoveryNeeded else { return nil }
        if case .setGroupWakeSchedule(let id, let minutes, let schedule) = action {
            guard let limit = state.limits.first(where: { $0.id == id }), schedule.isValid,
                  minutes.map({ (0...1440).contains($0) }) ?? true,
                  limit.wakeDelayMinutes != minutes || (limit.wakeSchedule ?? LimitWakeSchedule()) != schedule else { return nil }
        }
        if case .setGroupWakeDelay(let id, let minutes) = action {
            guard let limit = state.limits.first(where: { $0.id == id }),
                  limit.wakeDelayMinutes != minutes,
                  minutes.map({ (0...1440).contains($0) }) ?? true else { return nil }
        }
        if case .upsertPasswordPolicy(let policy) = action {
            guard !policy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  policy.hash.count == 64,
                  policy.hash.allSatisfy({ $0.isHexDigit }),
                  !policy.allowed.isEmpty else { return nil }
        }
        if case .removePasswordPolicy(let id) = action {
            guard state.overrides.passwordPolicies.contains(where: { $0.id == id })
            else { return nil }
        }
        if case .upsertPhrasePolicy(let policy) = action {
            guard PhraseWords.isValid(policy) else { return nil }
        }
        if case .removePhrasePolicy(let id) = action {
            guard state.overrides.phrasePolicies.contains(where: { $0.id == id })
            else { return nil }
        }
        if case .setContactPermissions(let id, let allowed) = action {
            guard let contact = state.overrides.contacts.first(where: { $0.id == id }),
                  contact.allowed != allowed else { return nil }
        }
        if case .configureLimit(let limit) = action {
            guard state.limits.contains(where: { $0.id == limit.id }),
                  isValidLimit(limit) else { return nil }
            let limits = state.limits.map { $0.id == limit.id ? limit : $0 }
            guard DayNightGroup.supportsLimitSelections(state.dayNightGroups, limits: limits) else { return nil }
        }
        if case .addLimit(let limit) = action {
            guard isValidLimit(limit) else { return nil }
        }
        if case .setWakeRule(let rule) = action {
            guard rule.isValid(in: state),
                  !state.pending.contains(where: {
                      if case .setSleepRule = $0.action { return true }
                      return false
                  }),
                  !state.sleepRule.enabled
                    || state.sleepRule.startMinutes != rule.startHour * 60
            else { return nil }
        }
        if case .upsertDayNightGroup(let group) = action {
            var proposed = state.dayNightGroups.filter { $0.id != group.id }
            proposed.append(group)
            guard DayNightGroup.isValidCollection(proposed, limits: state.limits),
                  state.dayNightGroups.first(where: { $0.id == group.id }) != group else { return nil }
        }
        if case .removeDayNightGroup(let id) = action {
            guard state.dayNightGroups.contains(where: { $0.id == id }) else { return nil }
        }
        if case .setSleepRule(let rule) = action {
            guard !state.pending.contains(where: {
                      if case .setWakeRule = $0.action { return true }
                      return false
                  }),
                  rule.isValid(in: state, wakeHour: state.wakeRule.startHour) else {
                return nil
            }
        }
        if case .updateLimit(let id, let selection, _) = action {
            // An empty DeviceActivity selection means "all device activity".
            // Reject it even if a caller bypasses the editor's validation.
            guard state.limits.contains(where: { $0.id == id }),
                  !selection.applicationTokens.isEmpty
                    || !selection.categoryTokens.isEmpty
                    || !selection.webDomainTokens.isEmpty
            else { return nil }
            var limits = state.limits
            if let index = limits.firstIndex(where: { $0.id == id }) { limits[index].selection = selection }
            guard DayNightGroup.supportsLimitSelections(state.dayNightGroups, limits: limits) else { return nil }
        }
        if case .updateScheduleSelection(let id, let selection) = action {
            guard let current = state.schedules.first(where: { $0.id == id }),
                  current.selection != selection,
                  current.acceptsSelection(selection) else { return nil }
        }
        if case .setDelayPolicy(let policy) = action {
            guard policy.isValid, policy.normalized != state.delayPolicy.normalized else { return nil }
        }
        let key = conflictKey(action)
        guard !state.pending.contains(where: { conflictKey($0.action) == key })
        else { return nil }
        let direction = classify(action, state: state)
        let delay = state.delayPolicy.delay(for: direction)
        let now = TimeGuard.now()
        let change = PendingChange(
            createdAt: now,
            appliesAt: now.addingTimeInterval(delay),
            direction: direction,
            summary: summary(for: action, state: state),
            action: action
        )
        let repair = MonitoringBudget.isRepair(action, state: state)
        state.pending.append(change)
        guard SharedStore.simulating || MonitorRegistration.admit(state: state, running: running, repair: repair),
              SharedStore.save(state) else { return nil }
        return change
    }

    private static func isValidLimit(_ limit: AppLimit) -> Bool {
        let selection = limit.selection
        guard !selection.applicationTokens.isEmpty
                || !selection.categoryTokens.isEmpty
                || !selection.webDomainTokens.isEmpty,
              (0...720).contains(limit.minutesPerDay),
              limit.weekdayMinutes.allSatisfy({ (1...7).contains($0.key)
                                              && (0...720).contains($0.value) })
        else { return false }
        if let wake = limit.wakeDelayMinutes,
           !(0...1440).contains(wake) { return false }
        if let schedule = limit.wakeSchedule, !schedule.isValid { return false }
        if let split = limit.split,
           (!(1...22).contains(split.cutoffMinutes / 60)
            || split.cutoffMinutes % 60 != 0
            || !(0...720).contains(split.beforeMinutes)
            || split.beforeMinutes > split.cutoffMinutes) { return false }
        if let split = limit.split,
           let second = split.secondCutoffMinutes {
            guard second % 60 == 0, second > split.cutoffMinutes,
                  second <= 23 * 60,
                  let middle = split.middleMinutes,
                  (0...720).contains(middle),
                  split.beforeMinutes + middle <= limit.minutesPerDay
            else { return false }
        }
        if let extra = limit.extraTime {
            let steps = extra.effectiveSteps
            guard (1...5).contains(steps.count),
                  steps.allSatisfy({ (1...120).contains($0.minutes)
                      && [$0.passwordPolicyID != nil, $0.phrasePolicyID != nil,
                          $0.contactRequired].filter({ $0 }).count <= 1
                      && ($0.passwordPolicyID != nil || $0.phrasePolicyID != nil
                          || $0.contactRequired
                          || (1...1440).contains($0.waitMinutes)) }),
                  limit.minutesPerDay + steps.reduce(0, { $0 + $1.minutes }) <= 1439
            else { return false }
        }
        return true
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
    private static func applyNow(changeIDs: [UUID],
                                 validate: ((LatchState, [PendingChange]) -> Bool)? = nil) -> Int {
        var state = SharedStore.loadState()
        let requested = Set(changeIDs)
        let matching = state.pending.filter { requested.contains($0.id) }
        guard !matching.isEmpty,
              validate?(state, matching) ?? true,
              !hasUnappliedDueChanges(state, excluding: requested) else {
            #if DEBUG
            print("⚠️ applyNow: pending authorization changed or maintenance is due")
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

    /// A bounded fail-closed fence, not a maintenance retry loop. Cleanup XPC
    /// can outlast a second policy's deadline after applyDueChanges snapshots
    /// its due set. An override must not use that still-unapplied policy.
    /// Exclusions are only for targets being marked due by applyNow; natural
    /// zero-delay application through applyDueChanges is never gated here.
    static func hasUnappliedDueChanges(_ state: LatchState,
                                      excluding ids: Set<UUID> = []) -> Bool {
        state.pending.contains { !ids.contains($0.id) && $0.isDue }
    }

    /// Merge every due pending change into the active state, then
    /// reconfigure monitoring/shields. Safe to call from app or extensions.
    static func applyDueChanges() {
        var state = SharedStore.loadState()
        let due = state.pending.filter(\.isDue).sorted { $0.appliesAt < $1.appliesAt }
        guard !due.isEmpty else { return }
        let stateBefore = state
        let newWakeGates = Set(due.compactMap { change -> UUID? in
            let id: UUID, minutes: Int?
            switch change.action {
            case .setGroupWakeDelay(let target, let wait): id = target; minutes = wait
            case .setGroupWakeSchedule(let target, let wait, _): id = target; minutes = wait
            default: return nil
            }
            guard minutes != nil,
                  let limit = state.limits.first(where: { $0.id == id }),
                  limit.wakeDelayMinutes == nil else { return nil }
            return id
        })
        guard LimitFeatures.prepareNewWakeGates(newWakeGates) else { return }

        // Starting a session, changing an override, etc. does not alter daily
        // limit events. Restarting the daily monitor for every change exposed
        // us to spurious immediate threshold callbacks from Screen Time.
        let dailyLimitsChanged = due.contains { change in
            switch change.action {
            case .addLimit, .updateLimitMinutes, .updateLimit,
                 .configureLimit, .removeLimit:
                return true
            default:
                return false
            }
        }
        let editedSelectionIDs = Set(due.compactMap { change -> UUID? in
            switch change.action {
            case .updateLimit(let id, let selection, _):
                guard let old = state.limits.first(where: { $0.id == id }),
                      old.selection != selection else { return nil }
                return id
            case .configureLimit(let updated):
                guard let old = state.limits.first(where: { $0.id == updated.id }),
                      old.selection != updated.selection else { return nil }
                return updated.id
            default: return nil
            }
        })
        let editedFeatureIDs = Set(due.compactMap { change -> UUID? in
            guard case .configureLimit(let updated) = change.action,
                  let old = state.limits.first(where: { $0.id == updated.id }),
                  old.selection != updated.selection
                    || old.wakeDelayMinutes != updated.wakeDelayMinutes
                    || old.split != updated.split
                    || old.extraTime != updated.extraTime
            else { return nil }
            return updated.id
        })
        let editedSplitIDs = Set(due.compactMap { change -> UUID? in
            guard case .configureLimit(let updated) = change.action,
                  let old = state.limits.first(where: { $0.id == updated.id }),
                  old.split != updated.split else { return nil }
            return updated.id
        })

        let windowMonitoringChanged = due.contains { change in
            // Selection-only schedule edits leave every boundary unchanged.
            // The normal shield refresh below applies the new tokens without
            // restarting window or daily usage monitors.
            switch change.action {
            case .setGroupWakeDelay, .setGroupWakeSchedule:
                // Shared contributors can disappear together: comparing each
                // removal alone would leave their last shared sentinel stale.
                let projected = due.reduce(state) { MonitoringBudget.project($1.action, onto: $0) }
                return MonitoringBudget.windowNames(state: projected)
                    != MonitoringBudget.windowNames(state: state)
            case .addSchedule, .removeSchedule,
                 .addExemption, .removeExemption,
                 .addPlanned, .removePlanned,
                 .setWakeRule, .setSleepRule, .upsertDayNightGroup, .removeDayNightGroup:
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

        // Opt only edited limits into token-aware monitor fingerprints BEFORE
        // saving their new selections. Existing users keep their current
        // healthy monitor on upgrade; a crash between these writes can at
        // worst cause an extra rebuild, never bless a stale selection.
        if !editedSelectionIDs.isEmpty {
            var tracked = Set(SharedStore.defaults.stringArray(
                forKey: trackedLimitSelectionsKey) ?? [])
            tracked.formUnion(editedSelectionIDs.map(\.uuidString))
            SharedStore.defaults.set(tracked.sorted(),
                                     forKey: trackedLimitSelectionsKey)
        }

        // Invalidate credits BEFORE publishing the new selection. If the
        // process is killed between writes, an old credit can never enlarge a
        // newly edited group's budget. Rearm tracking only after state saves.
        let rotatedFreeTracking = editedSelectionIDs.isEmpty ? false
            : prepareUsageCreditForSelectionEdit(ids: editedSelectionIDs,
                                                 state: state)
        LimitFeatures.resetEditedLimits(editedFeatureIDs)
        LimitFeatures.clearSplitMarkers(for: editedSplitIDs)

        // Persist the approved configuration before touching Apple's XPC
        // service. If Screen Time stalls or the process is interrupted, the
        // rule is still committed and the next maintenance pass can self-heal.
        guard SharedStore.save(state) else { return }

        if !dailyLimitsChanged, due.contains(where: {
            switch $0.action {
            case .setGroupWakeDelay, .setGroupWakeSchedule: return true
            default: return false
            }
        }) {
            preserveDailyMonitoringForWakeEdit(from: stateBefore, to: state)
        }

        if !SharedStore.simulating && !cleanupActivityNames.isEmpty {
            DeviceActivityCenter().stopMonitoring(cleanupActivityNames.map {
                DeviceActivityName($0)
            })
        }
        // Release admitted pending slots only after persistence, but before
        // replacement tracking starts, so a fitting plan also fits mid-apply.
        if rotatedFreeTracking && isFreeWindowActive() {
            DeviceActivityCenter().stopMonitoring(
                [DeviceActivityName(freeWindowActivityName)])
            startFreeWindowTracking()
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
            LimitFeatures.reconfigureSplitMonitoring(state: state)
            LimitFeatures.reconcile(state: state)
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
        reconcileFreeWindow()
        LimitFeatures.reconcile(state: SharedStore.loadState())
        GlobalWake.reconcile(state: SharedStore.loadState())
        DayNightWake.reconcile(state: SharedStore.loadState())
        ShieldController.refresh()
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
        LimitFeatures.resetForNewDay()
        SharedStore.lastResetDay = today
        reconfigureDailyMonitoring(state: SharedStore.loadState())
        LimitFeatures.reconfigureSplitMonitoring(state: SharedStore.loadState())
        LimitFeatures.reconcile(state: SharedStore.loadState())
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
        case .setGroupWakeSchedule(let id, let minutes, let schedule):
            guard schedule.isValid, minutes.map({ (0...1440).contains($0) }) ?? true,
                  let index = state.limits.firstIndex(where: { $0.id == id }) else { break }
            state.limits[index].wakeDelayMinutes = minutes
            state.limits[index].wakeSchedule = schedule
        case .setGroupWakeDelay(let id, let minutes):
            guard minutes.map({ (0...1440).contains($0) }) ?? true,
                  let index = state.limits.firstIndex(where: { $0.id == id }) else { break }
            state.limits[index].wakeDelayMinutes = minutes
        case .addLimit(let l):
            state.limits.append(l)
        case .updateLimitMinutes(let id, let m):
            if let i = state.limits.firstIndex(where: { $0.id == id }) {
                state.limits[i].minutesPerDay = m
            }
        case .updateLimit(let id, let selection, let minutes):
            guard !selection.applicationTokens.isEmpty
                    || !selection.categoryTokens.isEmpty
                    || !selection.webDomainTokens.isEmpty
            else { break }
            if let i = state.limits.firstIndex(where: { $0.id == id }) {
                var limits = state.limits
                limits[i].selection = selection
                guard DayNightGroup.supportsLimitSelections(state.dayNightGroups, limits: limits) else { break }
                state.limits[i].selection = selection
                state.limits[i].minutesPerDay = minutes
            }
        case .configureLimit(let updated):
            guard isValidLimit(updated) else { break }
            if let index = state.limits.firstIndex(where: { $0.id == updated.id }) {
                var limits = state.limits
                limits[index] = updated
                guard DayNightGroup.supportsLimitSelections(state.dayNightGroups, limits: limits) else { break }
                state.limits[index] = updated
            }
        case .removeLimit(let id):
            state.limits.removeAll { $0.id == id }
            SharedStore.mutateBlockedLimitIDs { blocked in
                blocked.remove(id)
            }
        case .setStrictDelay(let t):
            state.delayPolicy = state.delayPolicy.replacing(.stricter, with: t)
        case .setLenientDelay(let t):
            state.delayPolicy = state.delayPolicy.replacing(.lenient, with: t)
        case .setDelayPolicy(let policy):
            if policy.isValid { state.delayPolicy = policy }
        case .setMathOverride, .setPasswordOverride:
            // A queued change from an older build must not re-enable a
            // retired self-override after this update is installed.
            break
        case .upsertPasswordPolicy(let policy):
            guard !policy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  policy.hash.count == 64,
                  !policy.allowed.isEmpty else { break }
            if let index = state.overrides.passwordPolicies.firstIndex(where: {
                $0.id == policy.id
            }) {
                state.overrides.passwordPolicies[index] = policy
            } else {
                state.overrides.passwordPolicies.append(policy)
            }
        case .removePasswordPolicy(let id):
            state.overrides.passwordPolicies.removeAll { $0.id == id }
        case .upsertPhrasePolicy(let policy):
            guard PhraseWords.isValid(policy) else { break }
            if let index = state.overrides.phrasePolicies.firstIndex(where: {
                $0.id == policy.id
            }) {
                state.overrides.phrasePolicies[index] = policy
            } else {
                state.overrides.phrasePolicies.append(policy)
            }
        case .removePhrasePolicy(let id):
            state.overrides.phrasePolicies.removeAll { $0.id == id }
        case .setContactsOverride(let on):
            state.overrides.contactsEnabled = on
        case .setWakeRule(let rule):
            guard rule.isValid(in: state),
                  !state.sleepRule.enabled
                    || state.sleepRule.startMinutes != rule.startHour * 60
            else { break }
            state.wakeRule = rule
            GlobalWake.clearTap()
        case .setSleepRule(let rule):
            guard rule.isValid(in: state, wakeHour: state.wakeRule.startHour) else { break }
            state.sleepRule = rule
        case .upsertDayNightGroup(var group):
            if let old = state.dayNightGroups.first(where: { $0.id == group.id }) {
                group.wakeEpoch = !old.wakeEnabled && group.wakeEnabled ? UUID() : old.wakeEpoch
            }
            var proposed = state.dayNightGroups.filter { $0.id != group.id }
            proposed.append(group)
            guard DayNightGroup.isValidCollection(proposed, limits: state.limits) else { break }
            state.dayNightGroups = proposed
        case .removeDayNightGroup(let id):
            state.dayNightGroups.removeAll { $0.id == id }
        case .addContact(let contact):
            state.overrides.contacts.append(contact)
        case .removeContact(let id):
            state.overrides.contacts.removeAll { $0.id == id }
        case .setContactPermissions(let id, let allowed):
            if let index = state.overrides.contacts.firstIndex(where: { $0.id == id }) {
                state.overrides.contacts[index].allowed = allowed
            }
        case .addSchedule(let s):
            state.schedules.append(s)
        case .updateScheduleSelection(let id, let selection):
            // A removed schedule must not be resurrected by a stale edit.
            if let index = state.schedules.firstIndex(where: { $0.id == id }),
               state.schedules[index].acceptsSelection(selection) {
                state.schedules[index].selection = selection
            }
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

    /// Wake-only changes don't alter usage events. Rebase only a verified
    /// fingerprint of the pre-edit state; never bless a stale/dropped monitor.
    private static func preserveDailyMonitoringForWakeEdit(from before: LatchState,
                                                           to after: LatchState) {
        guard SharedStore.defaults.string(forKey: dailyMonitorFingerprintKey)
                == dailyMonitorFingerprint(state: before) else { return }
        SharedStore.defaults.set(dailyMonitorFingerprint(state: after),
                                 forKey: dailyMonitorFingerprintKey)
    }
#if DEBUG
    // Allow rapid abuse-testing in the separately installed dev build. The
    // verification delay and conservative anti-bypass checks still apply.
    static let limitRecheckCooldown: TimeInterval = 0
#else
    static let limitRecheckCooldown: TimeInterval = 10 * 60
#endif
    private static let limitRecheckVerificationDelay: UInt64 =
        30 * 1_000_000_000

    private static let trackedLimitSelectionsKey =
        "latch.limitSelectionFingerprintIDs.v1"

    /// A stable digest of opaque selection tokens. Encoding each token on its
    /// own and sorting avoids Swift Set's process-dependent iteration order,
    /// which would otherwise restart the daily monitor on every app launch.
    private static func limitSelectionDigest(_ selection: FamilyActivitySelection) -> String {
        let encoder = JSONEncoder()
        func sortedTokens<T: Encodable & Hashable>(_ tokens: Set<T>) -> String {
            tokens.map {
                (try? encoder.encode($0).base64EncodedString()) ?? "encode-failed"
            }.sorted().joined(separator: ",")
        }
        let description = [
            selection.includeEntireCategory ? "all" : "selected",
            sortedTokens(selection.applicationTokens),
            sortedTokens(selection.categoryTokens),
            sortedTokens(selection.webDomainTokens)
        ].joined(separator: "|")
        return SHA256.hash(data: Data(description.utf8))
            .map { String(format: "%02x", Int($0)) }.joined()
    }

    /// A compact description of everything that changes a daily event.
    /// Only limits edited after this feature are token-aware: that avoids an
    /// unnecessary monitor restart (and iOS's occasional spurious threshold
    /// callbacks) for every existing user on the first launch after upgrade.
    private static func dailyMonitorFingerprint(state: LatchState) -> String {
        let credit = SharedStore.loadFreeCreditByLimit()
        let tracked = Set(SharedStore.defaults.stringArray(
            forKey: trackedLimitSelectionsKey) ?? [])
        let limits = state.limits.sorted { $0.id.uuidString < $1.id.uuidString }
            .map { limit in
                let base = "\(limit.id.uuidString):\(limit.minutes(on: Date())):\(credit[limit.id] ?? 0)"
                let hasFeatures = !limit.weekdayMinutes.isEmpty
                    || limit.wakeDelayMinutes != nil || limit.split != nil
                    || limit.extraTime != nil
                var result = tracked.contains(limit.id.uuidString) || hasFeatures
                    ? base + ":" + limitSelectionDigest(limit.selection) : base
                if hasFeatures {
                    let weekdays = limit.weekdayMinutes.keys.sorted().map { day in
                        "\(day)=\(limit.weekdayMinutes[day] ?? -1)"
                    }.joined(separator: ",")
                    let split = limit.split.map {
                        "\($0.cutoffMinutes),\($0.beforeMinutes),\($0.carryUnused),\($0.secondCutoffMinutes ?? -1),\($0.middleMinutes ?? -1)"
                    } ?? "off"
                    let extra = limit.extraTime.map {
                        $0.effectiveSteps.map {
                            "\($0.minutes),\($0.waitMinutes),\($0.passwordPolicyID?.uuidString ?? "wait"),\($0.phrasePolicyID?.uuidString ?? "none"),\($0.contactRequired)"
                        }
                            .joined(separator: ";")
                    } ?? "off"
                    result += ":\(weekdays):\(limit.wakeDelayMinutes ?? -1):\(split):\(extra)"
                }
                return result
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
                || $0.hasPrefix("global-wake-boundary")
                || $0.hasPrefix("global-sleep-boundary")
                || $0.hasPrefix("day-night-boundary-")
        })
        if runningWindows != expectedWindows {
            reconfigureWindowMonitoring(state: state)
        } else if !SharedStore.simulating {
            // Echoes are redundant midnight wake-ups. Restore only the missing
            // ones without tearing down healthy enforcement windows.
            startMissingEchoActivities(alreadyRunning: running)
        }
        if LimitFeatures.splitActivitiesNeedRepair(state: state, running: running) {
            LimitFeatures.reconfigureSplitMonitoring(state: state)
        }
        LimitFeatures.reconcile(state: state)
        GlobalWake.reconcile(state: state, running: running)
        DayNightWake.reconcile(state: state, running: running)
        ShieldController.refresh()
    }

    private static func expectedWindowActivityNames(state: LatchState)
        -> Set<String> {
        guard !SharedStore.simulating else { return [] }
        return MonitoringBudget.windowNames(state: state)
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
        let eligible = Set(state.limits.filter {
            $0.minutes(on: Date()) > 0
                && !LimitFeatures.splitCurrentlyBlocks($0)
        }
            .map(\.id))
        let candidates = SharedStore.loadBlockedLimitIDs()
            .intersection(eligible)
        guard !candidates.isEmpty else {
            return state.limits.contains(where: {
                LimitFeatures.splitCurrentlyBlocks($0)
            }) ? .splitBlocksNotRecheckable : .noBlockedLimits
        }

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
            let apps = limit.selection.applicationTokens
            let cats = limit.selection.categoryTokens
            let webs = limit.selection.webDomainTokens
            func usageEvent(at minutes: Int) -> DeviceActivityEvent {
                let cap = thresholdComponents(minutes: minutes)
                if #available(iOS 17.4, *) {
                    return DeviceActivityEvent(
                        applications: apps, categories: cats, webDomains: webs,
                        threshold: cap, includesPastActivity: true)
                }
                return DeviceActivityEvent(
                    applications: apps, categories: cats, webDomains: webs,
                    threshold: cap)
            }
            let base = limit.minutes(on: Date())
            let freeCredit = credit[limit.id] ?? 0
            // A spent base limit still needs its higher extra-time thresholds
            // registered. Activating extra time never restarts this monitor.
            if base > 0 && (includeBlockedLimits || !blocked.contains(limit.id)) {
                events[.init("limit-\(limit.id.uuidString)")] =
                    usageEvent(at: base + freeCredit)
            }
            if let extra = limit.extraTime, !extra.effectiveSteps.isEmpty {
                let day = SharedStore.dayKey(for: Date())
                var accumulated = 0
                for (index, step) in extra.effectiveSteps.enumerated() {
                    accumulated += step.minutes
                    let total = base + accumulated + freeCredit
                    let tier = index + 1
                    events[.init("extra:\(day):\(tier):\(limit.id.uuidString)")] =
                        usageEvent(at: total)
                }
            }
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
            try MonitorRegistration.start(daily, during: schedule, events: events)
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
        let m = min(24 * 60 - 1, max(1, minutes))
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
                || $0.rawValue.hasPrefix("global-wake-boundary")
                || $0.rawValue.hasPrefix("global-sleep-boundary")
                || $0.rawValue.hasPrefix("day-night-boundary-")
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
        if state.wakeRule.enabled || state.sleepRule.enabled {
            startWindowActivities(prefix: "global-wake-boundary",
                                  start: state.wakeRule.startHour * 60,
                                  end: min(state.wakeRule.startHour * 60 + 15, 1439),
                                  recurrence: .daily)
        }
        if state.sleepRule.enabled {
            startWindowActivities(prefix: "global-sleep-boundary",
                                  start: state.sleepRule.startMinutes,
                                  end: state.wakeRule.startHour * 60,
                                  recurrence: .daily)
        }
        for minute in DayNightWake.boundaryMinutes(state: state).sorted() {
            startWindowActivities(prefix: "day-night-boundary-\(minute)",
                                  start: minute, end: minute + 15, recurrence: .daily)
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
                try MonitorRegistration.start(
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
        // real enforcement activities claim the 20-activity budget first: a
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
        for (i, w) in [(5, 35), (60, 90), (360, 390)].enumerated() {
            let name = "echo-\(i)"
            if alreadyRunning.contains(name) { continue }
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: w.0 / 60, minute: w.0 % 60),
                intervalEnd: DateComponents(hour: w.1 / 60, minute: w.1 % 60),
                repeats: true,
                warningTime: boundaryWarning)
            do {
                try MonitorRegistration.start(DeviceActivityName(name), during: schedule)
            } catch {
                print("Demora: failed to start echo activity \(i): \(error)")
            }
        }
    }

    private static func startWindowActivities(prefix: String, start: Int,
                                              end: Int, recurrence: Recurrence) {
        for window in MonitoringBudget.windows(prefix: prefix, start: start, end: end,
                                                recurrence: recurrence) {
            let schedule = DeviceActivitySchedule(intervalStart: window.start,
                                                  intervalEnd: window.end, repeats: true,
                                                  warningTime: boundaryWarning)
            do {
                try MonitorRegistration.start(DeviceActivityName(window.name), during: schedule)
            } catch {
                print("Demora: failed to start window activity \(window.name): \(error)")
                SharedStore.enforcementDegraded = true
            }
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
        try? MonitorRegistration.start(
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

    /// Credits earned with the old selection cannot be applied to a different
    /// group of apps. Preserve the existing spent-limit marker (no bypass),
    /// discard only edited limits' old credits, and rotate an active free-window
    /// monitor so future checkpoints refer to the new selection. Other limits'
    /// checkpoints are banked first, so their free-period usage is not lost.
    @discardableResult
    private static func prepareUsageCreditForSelectionEdit(ids: Set<UUID>,
                                                            state: LatchState) -> Bool {
        LimitFeatures.clearCredits(for: ids)
        var credit = SharedStore.loadFreeCreditByLimit()
        let wasTrackingFreeWindow = SharedStore.freeWindowStart != nil
        if wasTrackingFreeWindow {
            // Reject callbacks from the old token set before stopping it.
            SharedStore.freeWindowTrackingEpoch = "rotating"
            DeviceActivityCenter().stopMonitoring(
                [DeviceActivityName(freeWindowActivityName)])
            let validIDs = Set(state.limits.map(\.id))
            for (id, minutes) in SharedStore.loadFreeWindowUsage()
            where !ids.contains(id) && validIDs.contains(id) && minutes > 0 {
                credit[id, default: 0] += min(minutes, 24 * 60)
            }
            SharedStore.saveFreeWindowUsage([:])
        }
        for id in ids { credit.removeValue(forKey: id) }
        SharedStore.saveFreeCreditByLimit(credit)
        return wasTrackingFreeWindow
    }

    static func reconcileFreeWindow() {
        let active = isFreeWindowActive()
        let running = SharedStore.freeWindowStart != nil
        if active && !running { exemptWindowStarted() }
        else if !active && running { exemptWindowEnded() }
        else if active && running
                && SharedStore.freeWindowTrackingEpoch == "rotating" {
            // A process may have died after invalidating old credits but
            // before it could rearm tracking with the saved selection.
            startFreeWindowTracking()
        }
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
        LimitFeatures.reconcile(state: SharedStore.loadState())
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
        let epoch = UUID().uuidString
        SharedStore.freeWindowTrackingEpoch = epoch
        // 0-minute limits stay blocked all day by the shield; no credit applies.
        for limit in state.limits where limit.minutes(on: Date()) > 0 {
            for m in freeCheckpointLadder {
                events[DeviceActivityEvent.Name("fw-\(epoch):\(limit.id.uuidString)-\(m)")] =
                    DeviceActivityEvent(
                        applications: limit.selection.applicationTokens,
                        categories: limit.selection.categoryTokens,
                        webDomains: limit.selection.webDomainTokens,
                        threshold: thresholdComponents(minutes: m))
            }
        }
        guard !events.isEmpty else {
            SharedStore.freeWindowTrackingEpoch = nil
            return
        }
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
            try MonitorRegistration.start(
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
        guard SharedStore.freeWindowStart != nil else { return }
        let body = eventName.dropFirst("fw-".count)
        guard let lastDash = body.lastIndex(of: "-"),
              let minutes = Int(body[body.index(after: lastDash)...])
        else { return }
        let identity = body[..<lastDash]
        let id: UUID?
        if let separator = identity.firstIndex(of: ":") {
            let epoch = String(identity[..<separator])
            guard SharedStore.freeWindowTrackingEpoch == epoch else { return }
            id = UUID(uuidString: String(identity[identity.index(after: separator)...]))
        } else {
            // Tolerate a free-window monitor created by an older build until
            // it ends. Once tracking is rearmed, its late callbacks are stale.
            guard SharedStore.freeWindowTrackingEpoch == nil else { return }
            id = UUID(uuidString: String(identity))
        }
        guard let id else { return }
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
        SharedStore.freeWindowTrackingEpoch = "stopped"
        var shouldRearmDailyMonitoring = false
        var shouldRearmSplitMonitoring = false
        if SharedStore.freeWindowStart != nil {
            let usage = SharedStore.loadFreeWindowUsage()
            let suppressed = SharedStore.loadFreeWindowSuppressedLimitIDs()
            let suppressedSplit = LimitFeatures.takeSuppressedSplitIDs()
            var credit = SharedStore.loadFreeCreditByLimit()
            for (id, minutes) in usage where minutes > 0 {
                credit[id, default: 0] += min(minutes, 24 * 60)
            }
            SharedStore.saveFreeCreditByLimit(credit)
            if let start = SharedStore.freeWindowStart {
                LimitFeatures.creditFreeUsage(usage, from: start, to: Date(),
                                              state: SharedStore.loadState())
            }

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
            SharedStore.freeWindowTrackingEpoch = nil
            SharedStore.freeWindowBlockedSnapshot = nil
            SharedStore.clearFreeWindowSuppressedLimitIDs()

            // No limited app usage and no suppressed callback means the daily
            // monitor is still valid. Avoiding an unnecessary restart avoids
            // the iOS immediate-threshold regression altogether.
            shouldRearmDailyMonitoring = !usage.isEmpty || !suppressed.isEmpty
            shouldRearmSplitMonitoring = !usage.isEmpty || !suppressedSplit.isEmpty
        }
        if SharedStore.freeWindowStart == nil {
            SharedStore.freeWindowTrackingEpoch = nil
        }
        if shouldRearmDailyMonitoring {
            reconfigureDailyMonitoring(state: SharedStore.loadState())
        }
        if shouldRearmSplitMonitoring {
            LimitFeatures.reconfigureSplitMonitoring(state: SharedStore.loadState())
        }
        LimitFeatures.reconcile(state: SharedStore.loadState())
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
            try MonitorRegistration.start(
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
