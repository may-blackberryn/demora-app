// Advanced limit enforcement shared by the app and DeviceActivity extension.
// User intent is persisted independently of callbacks: an omitted iOS wake can
// delay a transition, but relaunching the app cannot erase a gate or cooldown.

import Foundation
import DeviceActivity
import FamilyControls

enum WakeState: Equatable {
    case notConfigured
    case needsTap
    case waiting(Date)
    case awake
}

enum ExtraTimeState: Equatable {
    case notConfigured
    case notNeeded(remaining: Int)
    case ready(remaining: Int)
    case waiting(until: Date, remaining: Int)
    case active(remaining: Int)
    case exhausted
}

private struct LimitFeatureEntry: Codable {
    var day: String = ""
    var wakeReleaseAt: Date?
    var earlyBlocked = false
    var lateBlocked = false
    var suppressedSplit = false
    var earlyFreeCredit = 0
    var lateFreeCredit = 0
    var middleBlocked = false
    var middleFreeCredit = 0
    var extraRequests = 0
    var extraActiveTier = 0
    var extraReachedTier = 0
    var extraReleaseAt: Date?
    var extraLastRequestID: UUID?
    var paceCycleID: UUID?
    var paceCycleStart: Date?
    var paceLockedUntil: Date?
    var paceMonitorReady = false

    init(day: String = "") { self.day = day }

    private enum CodingKeys: String, CodingKey {
        case day, wakeReleaseAt, earlyBlocked, lateBlocked, suppressedSplit,
             earlyFreeCredit,
             lateFreeCredit, middleBlocked, middleFreeCredit,
             extraRequests, extraActiveTier, extraReachedTier, extraReleaseAt,
             extraLastRequestID,
             paceCycleID, paceCycleStart, paceLockedUntil,
             paceMonitorReady
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        wakeReleaseAt = try c.decodeIfPresent(Date.self, forKey: .wakeReleaseAt)
        earlyBlocked = try c.decodeIfPresent(Bool.self, forKey: .earlyBlocked) ?? false
        lateBlocked = try c.decodeIfPresent(Bool.self, forKey: .lateBlocked) ?? false
        suppressedSplit = try c.decodeIfPresent(Bool.self, forKey: .suppressedSplit) ?? false
        earlyFreeCredit = try c.decodeIfPresent(Int.self, forKey: .earlyFreeCredit) ?? 0
        lateFreeCredit = try c.decodeIfPresent(Int.self, forKey: .lateFreeCredit) ?? 0
        middleBlocked = try c.decodeIfPresent(Bool.self, forKey: .middleBlocked) ?? false
        middleFreeCredit = try c.decodeIfPresent(Int.self, forKey: .middleFreeCredit) ?? 0
        extraRequests = try c.decodeIfPresent(Int.self, forKey: .extraRequests) ?? 0
        extraActiveTier = try c.decodeIfPresent(Int.self, forKey: .extraActiveTier) ?? 0
        extraReachedTier = try c.decodeIfPresent(Int.self, forKey: .extraReachedTier) ?? 0
        extraReleaseAt = try c.decodeIfPresent(Date.self, forKey: .extraReleaseAt)
        extraLastRequestID = try c.decodeIfPresent(UUID.self,
                                                  forKey: .extraLastRequestID)
        paceCycleID = try c.decodeIfPresent(UUID.self, forKey: .paceCycleID)
        paceCycleStart = try c.decodeIfPresent(Date.self, forKey: .paceCycleStart)
        paceLockedUntil = try c.decodeIfPresent(Date.self, forKey: .paceLockedUntil)
        paceMonitorReady = try c.decodeIfPresent(Bool.self, forKey: .paceMonitorReady) ?? false
    }
}

enum LimitFeatures {
    private static let runtimeName = "limitFeatures.v1.json"
    private static let splitEpochKey = "latch.splitMonitorEpoch.v1"
    private static let splitDayKey = "latch.splitMonitorDay.v1"
    private static let splitReadyKey = "latch.splitMonitorReady.v1"
    private static let splitPrefix = "limit-part-"
    private static let pacePrefix = "limit-pace-"
    private static let paceTickPrefix = "limit-pace-tick-"
    private static let paceReleasePrefix = "limit-pace-release-"
    private static let wakeReleasePrefix = "limit-wake-release-"
    private static let extraReleasePrefix = "limit-extra-release-"

    private static var fileURL: URL {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: LatchConstants.appGroupID)!
            .appendingPathComponent(runtimeName)
    }

    private static func loadAll() -> [UUID: LimitFeatureEntry] {
        guard let data = try? Data(contentsOf: fileURL) else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                SharedStore.enforcementDegraded = true
                SharedStore.defaults.set(false, forKey: splitReadyKey)
            }
            return [:]
        }
        guard let value = try? JSONDecoder().decode(
            [UUID: LimitFeatureEntry].self, from: data) else {
            NSLog("Demora: unreadable limit feature state; keeping split rules blocked")
            SharedStore.enforcementDegraded = true
            SharedStore.defaults.set(false, forKey: splitReadyKey)
            return [:]
        }
        return value
    }

    /// Coordinated across app/extension processes, as with blocked limit IDs.
    @discardableResult
    private static func mutate(_ body: (inout [UUID: LimitFeatureEntry]) -> Void) -> Bool {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var saved = false
        coordinator.coordinate(writingItemAt: fileURL, options: [],
                               error: &coordinationError) { url in
            var value: [UUID: LimitFeatureEntry] = [:]
            if FileManager.default.fileExists(atPath: url.path) {
                guard let data = try? Data(contentsOf: url),
                      let decoded = try? JSONDecoder().decode(
                        [UUID: LimitFeatureEntry].self, from: data) else {
                    // Preserve unreadable enforcement state; overwriting it
                    // with an empty dictionary could unspend today's rules.
                    SharedStore.enforcementDegraded = true
                    SharedStore.defaults.set(false, forKey: splitReadyKey)
                    return
                }
                value = decoded
            }
            body(&value)
            guard let data = try? JSONEncoder().encode(value) else { return }
            do {
                try data.write(to: url, options: [.atomic,
                    .completeFileProtectionUntilFirstUserAuthentication])
                saved = try Data(contentsOf: url) == data
            } catch {
                NSLog("Demora: failed to persist limit feature state: %@",
                      String(describing: error))
                SharedStore.enforcementDegraded = true
                SharedStore.defaults.set(false, forKey: splitReadyKey)
            }
        }
        if let coordinationError {
            NSLog("Demora: limit feature coordination failed: %@",
                  String(describing: coordinationError))
            SharedStore.enforcementDegraded = true
            SharedStore.defaults.set(false, forKey: splitReadyKey)
        }
        return saved && coordinationError == nil
    }

    private static func entry(_ id: UUID, at date: Date = Date()) -> LimitFeatureEntry {
        let value = loadAll()[id] ?? LimitFeatureEntry()
        return value.day == SharedStore.dayKey(for: date)
            ? value : LimitFeatureEntry(day: SharedStore.dayKey(for: date))
    }

    static func wakeState(for limit: AppLimit, at date: Date = Date(),
                          guardedNow: Date = TimeGuard.now()) -> WakeState {
        guard limit.wakeDelayMinutes != nil else { return .notConfigured }
        if (limit.wakeSchedule ?? LimitWakeSchedule())
            .timing(on: date, defaultWait: limit.wakeDelayMinutes ?? 0).ceilingReached(on: date) {
            return .awake
        }
        if let release = entry(limit.id, at: date).wakeReleaseAt {
            return guardedNow < release ? .waiting(release) : .awake
        }
        guard (limit.wakeSchedule ?? LimitWakeSchedule()).eligible(on: date) else { return .notConfigured }
        return .needsTap
    }

    /// Enabling a previously disabled group gate must not reuse an old tap.
    /// Leave usage, free credits, split blocks and extra-time grants alone.
    static func prepareNewWakeGates(_ ids: Set<UUID>) -> Bool {
        guard !ids.isEmpty else { return true }
        guard mutate({ values in
            for id in ids {
                guard var value = values[id] else { continue }
                value.wakeReleaseAt = nil
                values[id] = value
            }
        }) else { return false }
        DeviceActivityCenter().stopMonitoring(ids.map {
            DeviceActivityName(wakeReleasePrefix + $0.uuidString)
        })
        return true
    }

    @discardableResult
    static func wakeUp(limitID: UUID) -> Bool {
        let wall = Date(), now = TimeGuard.now()
        guard !SharedStore.simulating,
              let limit = SharedStore.loadState().limits.first(where: { $0.id == limitID }),
              let defaultWait = limit.wakeDelayMinutes, defaultWait >= 0,
              wakeState(for: limit, at: wall, guardedNow: now) == .needsTap else { return false }
        let delay = (limit.wakeSchedule ?? LimitWakeSchedule()).timing(on: wall, defaultWait: defaultWait).waitMinutes
        let release = now.addingTimeInterval(TimeInterval(delay) * 60)
        let day = SharedStore.dayKey(for: wall)
        var installed = false
        guard mutate({ values in
            var value = values[limitID] ?? LimitFeatureEntry()
            if value.day != day {
                value = LimitFeatureEntry(day: day)
            }
            // A second tap can never shorten an already persisted wait.
            guard value.wakeReleaseAt == nil else { return }
            value.wakeReleaseAt = release
            values[limitID] = value
            installed = true
        }), installed else { return false }
        if delay > 0 {
            scheduleWake(for: limitID, at: release)
        }
        ShieldController.refresh()
        return true
    }

    static func extraTimeState(for limit: AppLimit) -> ExtraTimeState {
        guard let rule = limit.extraTime else { return .notConfigured }
        let value = entry(limit.id)
        let remaining = max(0, rule.effectiveSteps.count - value.extraRequests)
        if let release = value.extraReleaseAt,
           value.extraActiveTier < value.extraRequests {
            return .waiting(until: release, remaining: remaining)
        }
        if value.extraActiveTier > 0
            && value.extraReachedTier < value.extraActiveTier {
            return .active(remaining: remaining)
        }
        let spent = SharedStore.loadBlockedLimitIDs().contains(limit.id)
            || limit.minutes(on: Date()) == 0
            || (value.extraActiveTier > 0
                && value.extraReachedTier >= value.extraActiveTier)
        if !spent { return .notNeeded(remaining: remaining) }
        if remaining == 0 { return .exhausted }
        return .ready(remaining: remaining)
    }

    static func extraRequestCount(for limitID: UUID, at date: Date = TimeGuard.now()) -> Int {
        entry(limitID, at: date).extraRequests
    }

    /// Request exactly one extra usage allowance. The old shield remains in
    /// place throughout the wait; a second request cannot shorten that wait.
    @discardableResult
    static func requestExtraTime(limitID: UUID,
                                 candidateHash: String? = nil,
                                 phraseProofID: UUID? = nil,
                                 contactValidator: ((LatchState, Int, LimitExtraStep) -> Bool)? = nil) -> Bool {
        let initial = SharedStore.loadState()
        let requestDay = SharedStore.dayKey(for: TimeGuard.now())
        guard !SharedStore.simulating,
              let limit = initial.limits.first(where: { $0.id == limitID }),
              let rule = limit.extraTime,
              case .ready = extraTimeState(for: limit),
              (limit.wakeDelayMinutes == nil
                || ChangeEngine.wakeState(for: limit) == .awake),
              DeviceActivityCenter().activities.contains(
                  DeviceActivityName(LatchConstants.dailyActivityName)),
              !SharedStore.enforcementDegraded else { return false }
        // The monitor lookup above is synchronous XPC. Never authorize from
        // the rule/policy snapshot taken before it, even on our serial queue.
        let state = SharedStore.loadState()
        guard state.limits.first(where: { $0.id == limitID }) == limit,
              SharedStore.dayKey(for: TimeGuard.now()) == requestDay,
              !ChangeEngine.hasUnappliedDueChanges(state) else { return false }
        let now = TimeGuard.now()
        let oldRequests = entry(limitID, at: now).extraRequests
        let requestID = UUID()
        guard rule.effectiveSteps.indices.contains(oldRequests) else { return false }
        let step = rule.effectiveSteps[oldRequests]
        guard step.minutes > 0,
              [step.passwordPolicyID != nil, step.phrasePolicyID != nil,
               step.contactRequired].filter({ $0 }).count <= 1,
              contactValidator == nil || step.contactRequired
        else { return false }
        let approvedPassword = step.passwordPolicyID.flatMap { id in
            initial.overrides.passwordPolicies.first {
                $0.id == id && $0.hash == candidateHash && $0.allowed.contains(.extraTime)
            }
        }
        var approvedPhrase: PhrasePolicy?
        if let policyID = step.phrasePolicyID {
            guard let phraseProofID,
                  let policy = initial.overrides.phrasePolicies.first(where: {
                      $0.id == policyID && $0.allowed.contains(.extraTime)
                  }),
                  PhraseChallenges.consume(phraseProofID, policy: policy,
                      scope: .extraTime(limitID: limitID,
                                        day: requestDay,
                                        step: oldRequests)) else { return false }
            approvedPhrase = policy
        }
        guard extraTimeAuthorized(state: state, limit: limit, index: oldRequests,
                                  step: step, approvedPassword: approvedPassword,
                                  approvedPhrase: approvedPhrase,
                                  contactValidator: contactValidator) else { return false }
        var release: Date?
        var committed = false
        mutate { values in
            // File coordination may wait past a revocation deadline. This is
            // inside the acquired runtime-file coordination, with no nested
            // coordination, maintenance, or monitor XPC in the validator.
            let fresh = SharedStore.loadState()
            let commitNow = TimeGuard.now()
            guard !SharedStore.simulating, !SharedStore.enforcementDegraded,
                  SharedStore.dayKey(for: commitNow) == requestDay,
                  extraTimeAuthorized(state: fresh, limit: limit, index: oldRequests,
                                      step: step, approvedPassword: approvedPassword,
                                      approvedPhrase: approvedPhrase,
                                      contactValidator: contactValidator) else { return }
            var value = values[limitID] ?? LimitFeatureEntry()
            if value.day != SharedStore.dayKey(for: commitNow) {
                value = LimitFeatureEntry(day: SharedStore.dayKey(for: commitNow))
            }
            guard value.extraRequests == oldRequests,
                  value.extraRequests < rule.effectiveSteps.count,
                  value.extraReleaseAt == nil,
                  value.extraActiveTier == 0 || value.extraReachedTier >= value.extraActiveTier,
                  SharedStore.loadBlockedLimitIDs().contains(limitID)
                    || limit.minutes(on: commitNow) == 0
                    || (value.extraActiveTier > 0
                        && value.extraReachedTier >= value.extraActiveTier),
                  !ChangeEngine.hasUnappliedDueChanges(fresh) else { return }
            release = !step.contactRequired && step.passwordPolicyID == nil
                && step.phrasePolicyID == nil
                ? commitNow.addingTimeInterval(TimeInterval(step.waitMinutes) * 60) : nil
            value.extraRequests += 1
            value.extraReleaseAt = release
            value.extraLastRequestID = requestID
            if release == nil { value.extraActiveTier = value.extraRequests }
            values[limitID] = value
            committed = true
        }
        let persisted = entry(limitID, at: now)
        guard committed,
              persisted.extraRequests == oldRequests + 1,
              persisted.extraLastRequestID == requestID,
              persisted.extraReleaseAt == release,
              release != nil || persisted.extraActiveTier == oldRequests + 1
        else { return false }
        if let release {
            scheduleWake(for: limitID, at: release, prefix: extraReleasePrefix)
        }
        ShieldController.refresh()
        return true
    }

    /// Pure authorization against a freshly decoded policy snapshot. A phrase
    /// proof is consumed once before coordination; its exact policy must still
    /// exist at commit. Contact validation retains the source IDs/codes rather
    /// than turning a preflight check into a reusable Boolean.
    private static func extraTimeAuthorized(state: LatchState, limit: AppLimit,
                                            index: Int, step: LimitExtraStep,
                                            approvedPassword: PasswordPolicy?,
                                            approvedPhrase: PhrasePolicy?,
                                            contactValidator: ((LatchState, Int, LimitExtraStep) -> Bool)?) -> Bool {
        guard state.limits.first(where: { $0.id == limit.id }) == limit else { return false }
        let permitted: Bool
        if step.contactRequired {
            permitted = contactValidator?(state, index, step) ?? false
        } else if let id = step.passwordPolicyID {
            permitted = approvedPassword.map { policy in
                policy.id == id && policy.allowed.contains(.extraTime)
                    && state.overrides.passwordPolicies.contains(policy)
            } ?? false
        } else if let id = step.phrasePolicyID {
            permitted = approvedPhrase.map { policy in
                policy.id == id && policy.allowed.contains(.extraTime)
                    && state.overrides.phrasePolicies.contains(policy)
            } ?? false
        } else {
            permitted = step.waitMinutes > 0
        }
        return permitted && !ChangeEngine.hasUnappliedDueChanges(state)
    }

    /// A reached higher tier may predate a request (e.g. other overlapping
    /// rules allowed usage). In that case the request stays blocked rather than
    /// granting an unverified allowance.
    static func extraUnblockedIDs(state: LatchState, at date: Date) -> Set<UUID> {
        guard state.limits.contains(where: { $0.extraTime != nil }),
              !SharedStore.enforcementDegraded,
              DeviceActivityCenter().activities.contains(
                  DeviceActivityName(LatchConstants.dailyActivityName)) else {
            return []
        }
        let entries = loadAll()
        let day = SharedStore.dayKey(for: date)
        return Set(state.limits.compactMap { limit in
            guard limit.extraTime != nil,
                  let value = entries[limit.id], value.day == day,
                  value.extraReleaseAt == nil,
                  value.extraActiveTier > 0,
                  value.extraReachedTier < value.extraActiveTier else { return nil }
            return limit.id
        })
    }

    static func receivedExtraThreshold(_ raw: String) {
        let parts = raw.split(separator: ":")
        guard parts.count == 4, parts[0] == "extra",
              String(parts[1]) == SharedStore.dayKey(for: Date()),
              let tier = Int(parts[2]),
              let id = UUID(uuidString: String(parts[3])),
              let limit = SharedStore.loadState().limits.first(where: { $0.id == id }),
              let rule = limit.extraTime, (1...rule.effectiveSteps.count).contains(tier)
        else { return }
        if SharedStore.freeWindowStart != nil || ChangeEngine.isFreeWindowActive() {
            SharedStore.recordFreeWindowSuppressedLimitID(id)
            return
        }
        mutate { values in
            var value = values[id] ?? LimitFeatureEntry()
            let day = SharedStore.dayKey(for: Date())
            if value.day != day { value = LimitFeatureEntry(day: day) }
            value.extraReachedTier = max(value.extraReachedTier, tier)
            values[id] = value
        }
        ShieldController.refresh()
    }

    static func earlyBlocks(_ limit: AppLimit, at date: Date = Date()) -> Bool {
        guard let split = limit.split,
              minuteOfDay(date) < split.cutoffMinutes else { return false }
        let before = min(max(0, split.beforeMinutes), limit.minutes(on: date))
        return before == 0 || entry(limit.id, at: date).earlyBlocked
    }

    static func lateZeroBlocks(_ limit: AppLimit, at date: Date = Date()) -> Bool {
        guard let split = limit.split, !split.carryUnused,
              minuteOfDay(date) >= (split.secondCutoffMinutes ?? split.cutoffMinutes)
        else { return false }
        let before = min(max(0, split.beforeMinutes), limit.minutes(on: date))
        let middle = min(max(0, split.middleMinutes ?? 0),
                         limit.minutes(on: date) - before)
        return limit.minutes(on: date) - before - middle == 0
    }

    static func lateThresholdBlocked(_ id: UUID) -> Bool {
        entry(id).lateBlocked
    }

    static func splitCurrentlyBlocks(_ limit: AppLimit,
                                     at date: Date = Date()) -> Bool {
        guard let split = limit.split else { return false }
        if splitMonitoringBlocks(limit) { return true }
        let budget = limit.minutes(on: date)
        let before = min(max(0, split.beforeMinutes), budget)
        let middle = min(max(0, split.middleMinutes ?? 0), budget - before)
        let minute = minuteOfDay(date)
        let value = entry(limit.id, at: date)
        if minute < split.cutoffMinutes {
            return before == 0 || value.earlyBlocked
        }
        if let second = split.secondCutoffMinutes, minute < second {
            return (split.carryUnused ? before + middle : middle) == 0
                || value.middleBlocked
                || (split.carryUnused && middle == 0 && value.earlyBlocked)
        }
        return !split.carryUnused
            && (budget - before - middle == 0 || value.lateBlocked)
    }

    static func splitMonitoringBlocks(_ limit: AppLimit) -> Bool {
        guard limit.split != nil else { return false }
        return !SharedStore.defaults.bool(forKey: splitReadyKey)
            || SharedStore.defaults.string(forKey: splitDayKey)
                != SharedStore.dayKey(for: Date())
    }

    /// One runtime read for the full shield pass. Re-reading the coordinated
    /// file once per limit would make a large group expensive in the monitor
    /// extension's short callback budget.
    static func blockedFeatureIDs(state: LatchState, at date: Date, includeWake: Bool = true) -> Set<UUID> {
        guard state.limits.contains(where: {
            $0.wakeDelayMinutes != nil || $0.split != nil
                || $0.pacing != nil || $0.extraTime != nil
        }) else { return [] }
        let entries = loadAll()
        let day = SharedStore.dayKey(for: date)
        let minute = minuteOfDay(date)
        let guardedNow = TimeGuard.now()
        let splitReady = SharedStore.defaults.bool(forKey: splitReadyKey)
            && SharedStore.defaults.string(forKey: splitDayKey) == day
        var blocked = Set<UUID>()
        for limit in state.limits {
            let value = entries[limit.id].flatMap { $0.day == day ? $0 : nil }
            let budget = limit.minutes(on: date)
            if includeWake, limit.wakeDelayMinutes != nil,
               !(limit.wakeSchedule ?? LimitWakeSchedule()).timing(on: date, defaultWait: limit.wakeDelayMinutes ?? 0).ceilingReached(on: date),
               (value?.wakeReleaseAt.map { guardedNow < $0 }
                ?? (limit.wakeSchedule ?? LimitWakeSchedule()).eligible(on: date)) {
                blocked.insert(limit.id)
                continue
            }
            if let split = limit.split {
                let before = min(max(0, split.beforeMinutes), budget)
                let middle = min(max(0, split.middleMinutes ?? 0),
                                 budget - before)
                let phaseBlocked: Bool
                if minute < split.cutoffMinutes {
                    phaseBlocked = before == 0 || value?.earlyBlocked == true
                } else if let second = split.secondCutoffMinutes,
                          minute < second {
                    let available = split.carryUnused ? before + middle : middle
                    phaseBlocked = available == 0 || value?.middleBlocked == true
                        || (split.carryUnused && middle == 0
                            && value?.earlyBlocked == true)
                } else {
                    let available = budget - before - middle
                    phaseBlocked = !split.carryUnused
                        && (available == 0 || value?.lateBlocked == true)
                }
                // Extra time is a daily-usage allowance, not a new portion.
                // It is offered only after the *whole* daily budget is spent;
                // once active it may lift a spent portion, but never a failed
                // split monitor or a wake-up gate.
                let extraActive = value.map {
                    $0.extraActiveTier > 0
                        && $0.extraReachedTier < $0.extraActiveTier
                        && $0.extraReleaseAt == nil
                } ?? false
                if !splitReady || (phaseBlocked && !extraActive) {
                    blocked.insert(limit.id)
                    continue
                }
            }
            if limit.extraTime != nil,
               (value?.extraRequests ?? 0) > 0,
               ((value?.extraReleaseAt != nil)
                || (value?.extraActiveTier ?? 0) < (value?.extraRequests ?? 0)
                || (value?.extraReachedTier ?? 0) >= (value?.extraActiveTier ?? 0)) {
                blocked.insert(limit.id)
                continue
            }
            if limit.pacing != nil {
                if let until = value?.paceLockedUntil, guardedNow < until {
                    blocked.insert(limit.id)
                } else if value?.paceCycleID == nil || value?.paceMonitorReady != true {
                    blocked.insert(limit.id)
                }
            }
        }
        return blocked
    }

    static func takeSuppressedSplitIDs() -> Set<UUID> {
        guard !loadAll().isEmpty else { return [] }
        var result = Set<UUID>()
        mutate { values in
            for id in Array(values.keys) {
                guard var value = values[id], value.suppressedSplit else { continue }
                result.insert(id)
                value.suppressedSplit = false
                values[id] = value
            }
        }
        return result
    }

    private static func recordSuppressedSplit(_ id: UUID) {
        mutate { values in
            var value = values[id] ?? LimitFeatureEntry()
            let day = SharedStore.dayKey(for: Date())
            if value.day != day { value = LimitFeatureEntry(day: day) }
            value.suppressedSplit = true
            values[id] = value
        }
    }

    private static func minuteOfDay(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func clearCredits(for ids: Set<UUID>) {
        mutate { values in
            for id in ids {
                guard var value = values[id] else { continue }
                value.earlyFreeCredit = 0
                value.middleFreeCredit = 0
                value.lateFreeCredit = 0
                values[id] = value
            }
        }
    }

    /// Retire usage events tied to an old selection/pacing policy. Keep an
    /// already reached early block or cooldown, so editing cannot grant a
    /// fresh allowance; require a new wake tap for the changed group.
    static func resetEditedLimits(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        mutate { values in
            for id in ids {
                guard var value = values[id] else { continue }
                value.wakeReleaseAt = nil
                value.earlyFreeCredit = 0
                value.middleFreeCredit = 0
                value.lateFreeCredit = 0
                // A delayed edit to the app selection or extra-time policy
                // must not carry an in-flight grant into a different rule.
                // Preserve the day's request count so editing cannot mint
                // fresh requests.
                value.extraActiveTier = 0
                value.extraReleaseAt = nil
                value.paceCycleID = nil
                value.paceCycleStart = nil
                value.paceMonitorReady = false
                values[id] = value
            }
        }
        let center = DeviceActivityCenter()
        for id in ids {
            center.stopMonitoring([
                DeviceActivityName(pacePrefix + id.uuidString),
                DeviceActivityName(paceTickPrefix + id.uuidString),
                DeviceActivityName(extraReleasePrefix + id.uuidString),
                DeviceActivityName(wakeReleasePrefix + id.uuidString)])
        }
    }

    /// Once a delayed split-policy edit applies, its old phase-only blocks no
    /// longer describe the active rule. Whole-day spent markers live in
    /// SharedStore and are deliberately untouched.
    static func clearSplitMarkers(for ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        mutate { values in
            for id in ids {
                guard var value = values[id] else { continue }
                value.earlyBlocked = false
                value.middleBlocked = false
                value.lateBlocked = false
                values[id] = value
            }
        }
    }

    static func creditFreeUsage(_ usage: [UUID: Int], from start: Date,
                                to end: Date, state: LatchState) {
        guard !usage.isEmpty, state.limits.contains(where: {
            $0.split != nil && usage[$0.id] != nil
        }) else { return }
        mutate { values in
            for limit in state.limits {
                guard let split = limit.split,
                      let amount = usage[limit.id], amount > 0 else { continue }
                let dayStart = Calendar.current.startOfDay(for: end)
                let cutoff = dayStart
                    .addingTimeInterval(TimeInterval(split.cutoffMinutes) * 60)
                let second = split.secondCutoffMinutes.map {
                    dayStart.addingTimeInterval(TimeInterval($0) * 60)
                }
                var value = values[limit.id] ?? LimitFeatureEntry()
                let day = SharedStore.dayKey(for: end)
                if value.day != day { value = LimitFeatureEntry(day: day) }
                // Screen Time supplies only aggregate checkpoint usage. For
                // a window crossing the cutoff, each side receives an upper
                // bound: no more than total usage or elapsed time on that side.
                // This avoids false blocks and bounds the extra allowance.
                let earlySeconds = max(0, min(end, cutoff).timeIntervalSince(start))
                let middleSeconds = second.map {
                    max(0, min(end, $0).timeIntervalSince(max(start, cutoff)))
                } ?? 0
                let lateSeconds = max(0, end.timeIntervalSince(
                    max(start, second ?? cutoff)))
                let earlyCap = Int(ceil(earlySeconds / 60))
                let middleCap = Int(ceil(middleSeconds / 60))
                let lateCap = Int(ceil(lateSeconds / 60))
                value.earlyFreeCredit += min(amount, min(1440, earlyCap))
                value.middleFreeCredit += min(amount, min(1440, middleCap))
                value.lateFreeCredit += min(amount, min(1440, lateCap))
                values[limit.id] = value
            }
        }
    }

    static func resetForNewDay() {
        guard FileManager.default.fileExists(atPath: fileURL.path)
            || SharedStore.defaults.string(forKey: splitDayKey) != nil
        else { return }
        mutate { $0.removeAll() }
        SharedStore.defaults.removeObject(forKey: splitDayKey)
        SharedStore.defaults.set(false, forKey: splitReadyKey)
        let center = DeviceActivityCenter()
        let stale = center.activities.filter {
            $0.rawValue.hasPrefix(pacePrefix)
                || $0.rawValue.hasPrefix(wakeReleasePrefix)
                || $0.rawValue.hasPrefix(extraReleasePrefix)
        }
        if !stale.isEmpty { center.stopMonitoring(stale) }
    }

    // MARK: Split-budget activities

    private static func splitActivityName(_ phase: String,
                                          _ start: Int, _ end: Int) -> String {
        "\(splitPrefix)\(phase)-\(start)-\(end)"
    }

    static func expectedSplitActivityNames(state: LatchState) -> Set<String> {
        guard !SharedStore.simulating else { return [] }
        return MonitoringBudget.splitNames(state: state)
    }

    static func splitActivitiesNeedRepair(state: LatchState,
                                          running: Set<String>) -> Bool {
        let expected = expectedSplitActivityNames(state: state)
        let actual = Set(running.filter { $0.hasPrefix(splitPrefix) })
        return expected != actual || (!expected.isEmpty &&
            (SharedStore.defaults.string(forKey: splitDayKey)
                != SharedStore.dayKey(for: Date())
             || !SharedStore.defaults.bool(forKey: splitReadyKey)))
    }

    static func reconfigureSplitMonitoring(state: LatchState) {
        let center = DeviceActivityCenter()
        SharedStore.defaults.set(false, forKey: splitReadyKey)
        let old = center.activities.filter { $0.rawValue.hasPrefix(splitPrefix) }
        if !old.isEmpty { center.stopMonitoring(old) }
        if SharedStore.simulating || state.limits.allSatisfy({ $0.split == nil }) {
            SharedStore.defaults.removeObject(forKey: splitDayKey)
            return
        }
        let epoch = UUID().uuidString
        SharedStore.defaults.set(epoch, forKey: splitEpochKey)
        let now = Date()
        let blocked = SharedStore.loadBlockedLimitIDs()
        typealias Bucket = (start: Int, end: Int,
                            events: [DeviceActivityEvent.Name: DeviceActivityEvent])
        var buckets: [String: Bucket] = [:]
        func add(_ phase: String, start: Int, end: Int,
                 eventName: DeviceActivityEvent.Name? = nil,
                 event: DeviceActivityEvent? = nil) {
            let name = splitActivityName(phase, start, end)
            var bucket = buckets[name] ?? (start: start, end: end, events: [:])
            if let eventName, let event { bucket.events[eventName] = event }
            buckets[name] = bucket
        }
        var allRegistered = true
        for limit in state.limits {
            guard let split = limit.split else { continue }
            let budget = limit.minutes(on: now)
            let first = split.cutoffMinutes / 60
            let before = min(max(0, split.beforeMinutes), budget)
            let middle = min(max(0, split.middleMinutes ?? 0), budget - before)
            let value = entry(limit.id, at: now)
            let id = limit.id.uuidString
            add("early", start: 0, end: first,
                eventName: before > 0 && !value.earlyBlocked
                    ? .init("part-early-\(epoch):\(id)") : nil,
                event: before > 0 && !value.earlyBlocked
                    ? event(for: limit, minutes: before + value.earlyFreeCredit) : nil)

            if let secondCutoff = split.secondCutoffMinutes {
                let second = secondCutoff / 60
                let middleAllowance = split.carryUnused ? before + middle : middle
                let middleCredit = split.carryUnused
                    ? value.earlyFreeCredit + value.middleFreeCredit
                    : value.middleFreeCredit
                add(split.carryUnused ? "middle-carry" : "middle",
                    start: split.carryUnused ? 0 : first, end: second,
                    eventName: middleAllowance > 0 && !value.middleBlocked
                        ? .init("part-middle-\(epoch):\(id)") : nil,
                    event: middleAllowance > 0 && !value.middleBlocked
                        ? event(for: limit,
                                minutes: middleAllowance + middleCredit) : nil)
                if !split.carryUnused {
                    let late = budget - before - middle
                    add("late", start: second, end: 23,
                        eventName: late > 0 && !blocked.contains(limit.id)
                            && !value.lateBlocked
                            ? .init("part-late-\(epoch):\(id)") : nil,
                        event: late > 0 && !blocked.contains(limit.id)
                            && !value.lateBlocked
                            ? event(for: limit,
                                    minutes: late + value.lateFreeCredit) : nil)
                }
            } else if !split.carryUnused {
                let late = budget - before
                add("late", start: first, end: 23,
                    eventName: late > 0 && !blocked.contains(limit.id)
                        && !value.lateBlocked
                        ? .init("part-late-\(epoch):\(id)") : nil,
                    event: late > 0 && !blocked.contains(limit.id)
                        && !value.lateBlocked
                        ? event(for: limit,
                                minutes: late + value.lateFreeCredit) : nil)
            }
        }
        // Empty-event intervals are intentional: their boundary callbacks
        // release a spent earlier portion even when the next budget is zero.
        for (name, bucket) in buckets.sorted(by: {
            $0.value.start == $1.value.start
                ? $0.value.end < $1.value.end
                : $0.value.start < $1.value.start
        }) {
            allRegistered = registerSplit(center,
                name: name, start: bucket.start, end: bucket.end,
                events: bucket.events) && allRegistered
        }
        SharedStore.defaults.set(SharedStore.dayKey(for: now), forKey: splitDayKey)
        SharedStore.defaults.set(allRegistered, forKey: splitReadyKey)
    }

    private static func event(for limit: AppLimit, minutes: Int) -> DeviceActivityEvent {
        let capped = min(1439, max(1, minutes))
        let components = DateComponents(hour: capped / 60,
                                        minute: capped % 60)
        if #available(iOS 17.4, *) {
            return DeviceActivityEvent(
                applications: limit.selection.applicationTokens,
                categories: limit.selection.categoryTokens,
                webDomains: limit.selection.webDomainTokens,
                threshold: components, includesPastActivity: true)
        }
        return DeviceActivityEvent(
            applications: limit.selection.applicationTokens,
            categories: limit.selection.categoryTokens,
            webDomains: limit.selection.webDomainTokens,
            threshold: components)
    }

    private static func registerSplit(_ center: DeviceActivityCenter, name: String,
                                      start: Int, end: Int,
                                      events: [DeviceActivityEvent.Name: DeviceActivityEvent]) -> Bool {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: start, minute: 0),
            intervalEnd: DateComponents(hour: end, minute: end == 23 ? 59 : 0),
            repeats: true, warningTime: DateComponents(minute: 5))
        do {
            try MonitorRegistration.start(.init(name), during: schedule, events: events)
            return true
        } catch {
            NSLog("Demora: split monitor %@ failed: %@", name,
                  String(describing: error))
            SharedStore.enforcementDegraded = true
            return false
        }
    }

    static func receivedSplitThreshold(_ raw: String) {
        guard let separator = raw.firstIndex(of: ":") else { return }
        let before = raw[..<separator]
        let idText = raw[raw.index(after: separator)...]
        guard let id = UUID(uuidString: String(idText)),
              let limit = SharedStore.loadState().limits.first(where: { $0.id == id }),
              let split = limit.split,
              before.hasSuffix(SharedStore.defaults.string(forKey: splitEpochKey) ?? "invalid"),
              SharedStore.defaults.string(forKey: splitDayKey) == SharedStore.dayKey(for: Date())
        else { return }
        if SharedStore.freeWindowStart != nil || ChangeEngine.isFreeWindowActive() {
            recordSuppressedSplit(id)
            return
        }
        let minute = minuteOfDay(Date())
        if raw.hasPrefix("part-early-") && minute < split.cutoffMinutes {
            mutate { values in
                var value = values[id] ?? LimitFeatureEntry()
                if value.day != SharedStore.dayKey(for: Date()) {
                    value = LimitFeatureEntry(day: SharedStore.dayKey(for: Date()))
                }
                value.earlyBlocked = true
                values[id] = value
            }
            ShieldController.refresh()
        } else if raw.hasPrefix("part-middle-"),
                  let second = split.secondCutoffMinutes,
                  minute >= split.cutoffMinutes && minute < second {
            mutate { values in
                var value = values[id] ?? LimitFeatureEntry()
                if value.day != SharedStore.dayKey(for: Date()) {
                    value = LimitFeatureEntry(day: SharedStore.dayKey(for: Date()))
                }
                value.middleBlocked = true
                values[id] = value
            }
            ShieldController.refresh()
        } else if raw.hasPrefix("part-late-") && !split.carryUnused
                    && minute >= (split.secondCutoffMinutes ?? split.cutoffMinutes) {
            mutate { values in
                var value = values[id] ?? LimitFeatureEntry()
                if value.day != SharedStore.dayKey(for: Date()) {
                    value = LimitFeatureEntry(day: SharedStore.dayKey(for: Date()))
                }
                value.lateBlocked = true
                values[id] = value
            }
            ShieldController.refresh()
            ChangeEngine.scheduleResetNudge()
        }
    }

    // MARK: Wake and pacing background callbacks

    private static func ceilMinute(_ date: Date) -> Date {
        let cal = Calendar.current
        let floor = cal.date(from: cal.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date)) ?? date
        return floor >= date ? floor : floor.addingTimeInterval(60)
    }

    /// Persisted wake/break deadlines use TimeGuard's elapsed-time clock.
    /// DeviceActivity accepts local wall-clock components, so project only
    /// their remaining duration when registering a background wake.
    private static func wallDate(for guardedTarget: Date) -> Date {
        Date().addingTimeInterval(max(0,
            guardedTarget.timeIntervalSince(TimeGuard.now())))
    }

    private static func scheduleWake(for id: UUID, at date: Date,
                                     prefix: String = wakeReleasePrefix) {
        let start = ceilMinute(max(wallDate(for: date),
                                   Date().addingTimeInterval(60)))
        let end = start.addingTimeInterval(30 * 60)
        let cal = Calendar.current
        let name = DeviceActivityName(prefix + id.uuidString)
        let center = DeviceActivityCenter()
        center.stopMonitoring([name])
        do {
            try MonitorRegistration.start(name, during: DeviceActivitySchedule(
                intervalStart: cal.dateComponents([.year, .month, .day,
                                                   .hour, .minute], from: start),
                intervalEnd: cal.dateComponents([.year, .month, .day,
                                                 .hour, .minute], from: end),
                repeats: false))
        } catch {
            NSLog("Demora: wake-release monitor failed: %@", String(describing: error))
            SharedStore.enforcementDegraded = true
        }
    }

    static func isFeatureActivity(_ raw: String) -> Bool {
        raw.hasPrefix(splitPrefix) || raw.hasPrefix(paceTickPrefix)
            || raw.hasPrefix(paceReleasePrefix)
            || raw.hasPrefix(wakeReleasePrefix)
            || raw.hasPrefix(extraReleasePrefix)
    }

    static func receivedFeatureActivity(_ raw: String) {
        guard isFeatureActivity(raw) else { return }
        if raw.hasPrefix(wakeReleasePrefix) || raw.hasPrefix(extraReleasePrefix)
            || raw.hasPrefix(paceTickPrefix)
            || raw.hasPrefix(paceReleasePrefix) {
            DeviceActivityCenter().stopMonitoring([.init(raw)])
        }
        reconcile(state: SharedStore.loadState())
        ShieldController.refresh()
    }

    private static func schedulePaceTick(for id: UUID, at date: Date,
                                         prefix: String = paceTickPrefix) {
        let start = ceilMinute(max(wallDate(for: date),
                                   Date().addingTimeInterval(60)))
        let end = start.addingTimeInterval(30 * 60)
        let cal = Calendar.current
        let name = DeviceActivityName(prefix + id.uuidString)
        let center = DeviceActivityCenter()
        center.stopMonitoring([name])
        do {
            try MonitorRegistration.start(name, during: DeviceActivitySchedule(
                intervalStart: cal.dateComponents([.year, .month, .day,
                                                   .hour, .minute], from: start),
                intervalEnd: cal.dateComponents([.year, .month, .day,
                                                 .hour, .minute], from: end),
                repeats: false))
        } catch {
            NSLog("Demora: pace wake monitor failed: %@", String(describing: error))
            SharedStore.enforcementDegraded = true
        }
    }

    private static func startPaceMonitor(for limit: AppLimit, cycleID: UUID) {
        guard let pacing = limit.pacing else { return }
        let now = Date()
        let cal = Calendar.current
        let floor = cal.date(from: cal.dateComponents(
            [.year, .month, .day, .hour, .minute], from: now)) ?? now
        let end = floor.addingTimeInterval(24 * 3600)
        let name = DeviceActivityName(pacePrefix + limit.id.uuidString)
        let center = DeviceActivityCenter()
        center.stopMonitoring([name])
        let components = DateComponents(hour: pacing.usageMinutes / 60,
                                        minute: pacing.usageMinutes % 60)
        let event = DeviceActivityEvent(
            applications: limit.selection.applicationTokens,
            categories: limit.selection.categoryTokens,
            webDomains: limit.selection.webDomainTokens,
            threshold: components)
        do {
            try MonitorRegistration.start(name, during: DeviceActivitySchedule(
                intervalStart: cal.dateComponents([.year, .month, .day,
                                                   .hour, .minute], from: floor),
                intervalEnd: cal.dateComponents([.year, .month, .day,
                                                 .hour, .minute], from: end),
                repeats: false), events: [
                    .init("pace-\(cycleID.uuidString):\(limit.id.uuidString)"): event])
            mutate { values in
                var value = values[limit.id] ?? LimitFeatureEntry()
                guard value.paceCycleID == cycleID else { return }
                value.paceMonitorReady = true
                values[limit.id] = value
            }
        } catch {
            NSLog("Demora: pacing monitor failed: %@", String(describing: error))
            SharedStore.enforcementDegraded = true
        }
    }

    static func receivedPaceThreshold(_ raw: String) {
        guard raw.hasPrefix("pace-"),
              let separator = raw.firstIndex(of: ":"),
              let cycleID = UUID(uuidString: String(raw.dropFirst(5)[..<separator])),
              let id = UUID(uuidString: String(raw[raw.index(after: separator)...])),
              let limit = SharedStore.loadState().limits.first(where: { $0.id == id }),
              let pacing = limit.pacing,
              !ChangeEngine.isFreeWindowActive() else { return }
        let now = TimeGuard.now()
        let value = entry(id, at: now)
        guard value.paceCycleID == cycleID,
              let start = value.paceCycleStart,
              value.paceLockedUntil == nil else { return }
        guard now < start.addingTimeInterval(TimeInterval(pacing.intervalMinutes) * 60)
        else {
            // A delayed threshold from an expired cycle must not create a
            // fresh break; use it as a chance to repair the next cycle.
            reconcile(state: SharedStore.loadState())
            return
        }
        let until = max(now.addingTimeInterval(TimeInterval(pacing.cooldownMinutes) * 60),
                        start.addingTimeInterval(TimeInterval(pacing.intervalMinutes) * 60))
        mutate { values in
            var current = values[id] ?? LimitFeatureEntry()
            guard current.day == SharedStore.dayKey(for: now),
                  current.paceCycleID == cycleID else { return }
            current.paceLockedUntil = until
            current.paceMonitorReady = false
            values[id] = current
        }
        DeviceActivityCenter().stopMonitoring([
            DeviceActivityName(pacePrefix + id.uuidString),
            DeviceActivityName(paceTickPrefix + id.uuidString)])
        schedulePaceTick(for: id, at: until, prefix: paceReleasePrefix)
        ShieldController.refresh()
    }

    /// Repair missed interval callbacks when any process wakes. A missing pace
    /// monitor while a cycle is in progress is treated conservatively as a
    /// lock until cycle end, rather than granting a fresh usage allowance.
    static func reconcile(state: LatchState) {
        guard !SharedStore.simulating else { return }
        guard state.limits.contains(where: {
            $0.wakeDelayMinutes != nil || $0.pacing != nil
                || $0.extraTime != nil
        }) || !loadAll().isEmpty else { return }
        let now = TimeGuard.now()
        let center = DeviceActivityCenter()
        let activities = center.activities
        let validIDs = Set(state.limits.map(\.id))
        let pacedIDs = Set(state.limits.filter { $0.pacing != nil }.map(\.id))
        let extraIDs = Set(state.limits.filter { $0.extraTime != nil }.map(\.id))
        let stale = activities.filter { activity in
            let raw = activity.rawValue
            let text: String
            if raw.hasPrefix(wakeReleasePrefix) {
                text = String(raw.dropFirst(wakeReleasePrefix.count))
            } else if raw.hasPrefix(extraReleasePrefix) {
                text = String(raw.dropFirst(extraReleasePrefix.count))
            } else if raw.hasPrefix(paceTickPrefix) {
                text = String(raw.dropFirst(paceTickPrefix.count))
            } else if raw.hasPrefix(paceReleasePrefix) {
                text = String(raw.dropFirst(paceReleasePrefix.count))
            } else if raw.hasPrefix(pacePrefix) {
                text = String(raw.dropFirst(pacePrefix.count))
            } else { return false }
            guard let id = UUID(uuidString: text) else { return false }
            if raw.hasPrefix(pacePrefix) { return !pacedIDs.contains(id) }
            if raw.hasPrefix(extraReleasePrefix) { return !extraIDs.contains(id) }
            return !validIDs.contains(id)
        }
        if !stale.isEmpty { center.stopMonitoring(stale) }
        let running = Set(activities.map(\.rawValue)).subtracting(stale.map(\.rawValue))
        let free = ChangeEngine.isFreeWindowActive()
        for limit in state.limits {
            let wakeName = wakeReleasePrefix + limit.id.uuidString
            if case .waiting(let release) = wakeState(for: limit) {
                if !running.contains(wakeName) { scheduleWake(for: limit.id, at: release) }
            } else if running.contains(wakeName) {
                // A calendar ceiling may release before the persisted wait.
                // Retire only this wake monitor; usage/accounting stay intact.
                center.stopMonitoring([DeviceActivityName(wakeName)])
            }
            if limit.extraTime != nil {
                let value = entry(limit.id, at: now)
                if let release = value.extraReleaseAt,
                   value.extraActiveTier < value.extraRequests {
                    if now >= release {
                        mutate { values in
                            var current = values[limit.id] ?? LimitFeatureEntry()
                            guard current.day == SharedStore.dayKey(for: now),
                                  current.extraReleaseAt == release else { return }
                            current.extraActiveTier = current.extraRequests
                            current.extraReleaseAt = nil
                            values[limit.id] = current
                        }
                        center.stopMonitoring([
                            DeviceActivityName(extraReleasePrefix + limit.id.uuidString)])
                    } else if !running.contains(extraReleasePrefix + limit.id.uuidString) {
                        scheduleWake(for: limit.id, at: release,
                                     prefix: extraReleasePrefix)
                    }
                }
            }
            guard let pacing = limit.pacing,
                  pacing.usageMinutes > 0,
                  pacing.intervalMinutes >= 15,
                  pacing.cooldownMinutes > 0 else { continue }
            let name = pacePrefix + limit.id.uuidString
            let id = limit.id
            var value = entry(id, at: now)
            if free {
                if running.contains(name) {
                    DeviceActivityCenter().stopMonitoring([.init(name)])
                }
                // Restart a full allowance when a free period ends; usage in
                // the free period is never charged to the paced burst.
                if value.paceCycleID != nil {
                    mutate { values in
                        var current = values[id] ?? LimitFeatureEntry()
                        current.paceCycleID = nil
                        current.paceCycleStart = nil
                        current.paceMonitorReady = false
                        values[id] = current
                    }
                }
                continue
            }
            if let until = value.paceLockedUntil, now < until {
                if running.contains(name) {
                    center.stopMonitoring([.init(name)])
                }
                if !running.contains(paceReleasePrefix + id.uuidString) {
                    schedulePaceTick(for: id, at: until, prefix: paceReleasePrefix)
                }
                continue
            }
            if value.paceLockedUntil != nil {
                mutate { values in
                    var current = values[id] ?? LimitFeatureEntry()
                    current.paceLockedUntil = nil
                    current.paceCycleID = nil
                    current.paceCycleStart = nil
                    current.paceMonitorReady = false
                    values[id] = current
                }
                value = entry(id, at: now)
            }
            let cycleEnd = value.paceCycleStart?.addingTimeInterval(
                TimeInterval(pacing.intervalMinutes) * 60)
            if let cycleEnd, now < cycleEnd {
                if !running.contains(name) {
                    // Missing monitor => usage since cycle start is unknown.
                    mutate { values in
                        var current = values[id] ?? LimitFeatureEntry()
                        current.paceLockedUntil = cycleEnd
                        current.paceMonitorReady = false
                        values[id] = current
                    }
                    schedulePaceTick(for: id, at: cycleEnd,
                                     prefix: paceReleasePrefix)
                    continue
                }
                if !running.contains(paceTickPrefix + id.uuidString) {
                    schedulePaceTick(for: id, at: cycleEnd)
                }
                continue
            }
            let cycleID = UUID()
            mutate { values in
                var current = values[id] ?? LimitFeatureEntry()
                if current.day != SharedStore.dayKey(for: now) {
                    current = LimitFeatureEntry(day: SharedStore.dayKey(for: now))
                }
                current.paceCycleID = cycleID
                current.paceCycleStart = now
                current.paceLockedUntil = nil
                current.paceMonitorReady = false
                values[id] = current
            }
            startPaceMonitor(for: limit, cycleID: cycleID)
            schedulePaceTick(for: id,
                at: now.addingTimeInterval(TimeInterval(pacing.intervalMinutes) * 60))
        }
    }
}
