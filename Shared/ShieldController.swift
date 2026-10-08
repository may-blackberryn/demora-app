//
//  ShieldController.swift
//  Re-derives all ManagedSettings shields from current state:
//  limits that hit their threshold, active recurring schedules,
//  active block sessions, free periods, and the app-deletion lock.
//

import Foundation
import ManagedSettings
import FamilyControls

struct ShieldController {
    static let store = ManagedSettingsStore(named: .init("latch.main"))
    private static let dayNightSelected = ManagedSettingsStore(named: .init("latch.dayNight.selected"))
    private static let dayNightOther = ManagedSettingsStore(named: .init("latch.dayNight.other"))
    // Three legacy stores + at most 46 category cohorts stay below Apple's 50
    // named-store ceiling. Names are shared by the host and all extensions.
    private static let categoryStoreCapacity = 46
    private static let categoryStoreCountKey = "latch.scheduleCategoryStores.v1"
    private static let categoryStoreUnverifiedKey = "latch.scheduleCategoryStores.unverified.v1"
    private static func categoryStore(_ index: Int) -> ManagedSettingsStore {
        ManagedSettingsStore(named: .init("latch.schedule.category.\(index)"))
    }

    @discardableResult
    private static func applyCategoryShields(_ cohorts: [FamilyActivitySelection]) -> Bool {
        // Serialize the manifest and cohort updates across app/monitor writers.
        // Publish a monotonic high-water mark BEFORE applying new settings, so
        // a crash cannot strand an unrecorded named store. Never rewrite it on
        // healthy refreshes or decode the configuration again here.
        return SharedStore.coordinateStateMutation {
            var groups = cohorts
            if groups.count > categoryStoreCapacity {
                // Pathological overlapping selections must never drop blocks.
                // Coalesce overflow without exceptions (conservative fallback).
                var overflow = FamilyActivitySelection()
                for group in groups.dropFirst(categoryStoreCapacity - 1) {
                    overflow.categoryTokens.formUnion(group.categoryTokens)
                }
                groups = Array(groups.prefix(categoryStoreCapacity - 1)) + [overflow]
                if !SharedStore.enforcementDegraded { SharedStore.enforcementDegraded = true }
            }
            let raw = SharedStore.defaults.object(forKey: categoryStoreCountKey)
            let recorded = raw as? Int
            let oldCount = recorded.map { (0...categoryStoreCapacity).contains($0) ? $0 : categoryStoreCapacity }
                ?? (raw == nil ? 0 : categoryStoreCapacity)
            let highWater = max(oldCount, groups.count)
            if highWater > oldCount || SharedStore.defaults.bool(forKey: categoryStoreUnverifiedKey) {
                // Keep failed publication visibly unverified in the cached
                // suite, so a retry cannot trust a failed growth as oldCount.
                SharedStore.defaults.set(true, forKey: categoryStoreUnverifiedKey)
                SharedStore.defaults.set(highWater, forKey: categoryStoreCountKey)
                guard SharedStore.defaults.synchronize(),
                      SharedStore.defaults.object(forKey: categoryStoreCountKey) as? Int == highWater
                else { return false }
                SharedStore.defaults.set(false, forKey: categoryStoreUnverifiedKey)
            }
            // A conservative bridge protects categories while cohort indices
            // are replaced. If the process dies between two setter calls,
            // this bridge remains restrictive until the next complete refresh.
            // No opaque category-to-app membership has to be guessed.
            var bridge = Set(groups.flatMap { $0.categoryTokens })
            if case .specific(let categories, _) = dayNightSelected.shield.applicationCategories {
                bridge.formUnion(categories)
            }
            for index in 0..<highWater {
                if case .specific(let categories, _) = categoryStore(index).shield.applicationCategories {
                    bridge.formUnion(categories)
                }
            }
            dayNightSelected.shield.applicationCategories = bridge.isEmpty ? nil : .specific(bridge)
            dayNightSelected.shield.webDomainCategories = bridge.isEmpty ? nil : .specific(bridge)
            // Install the new restrictions before retiring obsolete cohorts.
            for (index, group) in groups.enumerated() {
                let target = categoryStore(index)
                target.shield.applicationCategories = .specific(group.categoryTokens, except: group.applicationTokens)
                target.shield.webDomainCategories = .specific(group.categoryTokens, except: group.webDomainTokens)
            }
            for index in groups.count..<highWater {
                let target = categoryStore(index)
                if target.shield.applicationCategories != nil || target.shield.webDomainCategories != nil {
                    target.clearAllSettings()
                }
            }
            return true
        } ?? false
    }

    /// Re-derive shields from state + blocked limit IDs. Idempotent —
    /// safe to call from the app or any extension at any time.
    ///
    /// Rules are layered lowest-first: daily usage < wake/sleep < recurring
    /// < planned < sessions. Explicit promoted schedules apply last and all
    /// promotion/restoration edits are delay-gated.
    /// Within the recurring group, the most recently added window is applied
    /// last (so it wins). Each rule either blocks apps, "blocks all except" an
    /// allowlist, frees specific apps (unblock sessions), or frees everything
    /// (a free period). Stricter specific blocks still apply on top of an
    /// "all except" so a limit-spent allowlisted app stays blocked.
    static func refresh() {
        // Read the latest state and usage markers inside the same cross-process
        // transaction as ALL shield writes. An older host refresh must not run
        // after a newer monitor refresh and erase its freshly-confirmed block.
        guard SharedStore.coordinateStateMutation({
            refreshCoordinated()
            return true
        }) == true else {
            if !SharedStore.enforcementDegraded { SharedStore.enforcementDegraded = true }
            return
        }
    }

    private static func refreshCoordinated() {
        // A replay of the walkthrough runs the tour over throwaway sample state,
        // but the user's REAL limits must keep blocking the whole time —
        // otherwise starting a replay would be a way to unblock apps. Enforce the
        // backed-up real state and ignore the sample state entirely. Checked
        // BEFORE `simulating` (a replay sets both flags).
        if SharedStore.isReplaying, let real = SharedStore.loadBackup() {
            apply(state: real)
            return
        }
        // During the first-run tutorial nothing real exists yet — clear any
        // shields and bail, so a user can't lock themselves (or Demora) out.
        if SharedStore.simulating {
            clearAll()
            return
        }
        apply(state: SharedStore.loadState())
    }

    /// Remove every shield this store owns.
    private static func clearAll() {
        applyCategoryShields([])
        dayNightSelected.clearAllSettings()
        dayNightOther.clearAllSettings()
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
        store.application.denyAppRemoval = nil
        store.webContent.blockedByFilter = nil
    }

    /// Re-derive and apply every shield from the given state. Layered lowest to
    /// highest priority, including persisted schedule priority choices.
    private static func apply(state: LatchState) {
        let blockedIDs = SharedStore.loadBlockedLimitIDs()
        let now = Date()
        let featureBlockedIDs = LimitFeatures.blockedFeatureIDs(state: state, at: now, includeWake: false)
        let extraUnblockedIDs = LimitFeatures.extraUnblockedIDs(state: state, at: now)
        var baseline = FamilyActivitySelection()
        for limit in state.limits
        where ((limit.minutes(on: now) == 0 || blockedIDs.contains(limit.id))
                && !extraUnblockedIDs.contains(limit.id)) || featureBlockedIDs.contains(limit.id) {
            baseline.applicationTokens.formUnion(limit.selection.applicationTokens)
            baseline.categoryTokens.formUnion(limit.selection.categoryTokens)
            baseline.webDomainTokens.formUnion(limit.selection.webDomainTokens)
        }
        let wakeActive: (GlobalWakeStatus) -> Bool = {
            switch $0 { case .needsTap, .waiting: return true; case .inactive, .awake: return false }
        }
        let plan = ScheduleShieldPlan.build(state: state, baseline: baseline, at: now,
            globalWakeActive: wakeActive(GlobalWake.status(state: state, at: now)),
            limitWakeActive: { limit in
                switch LimitFeatures.wakeState(for: limit, at: now) {
                case .needsTap, .waiting: return true
                case .notConfigured, .awake: return false
                }
            },
            groupWakeActive: { wakeActive(DayNightWake.status(group: $0, at: now)) })
        let categoriesApplied = applyCategoryShields(plan.categoryShields)
        store.shield.applications = plan.blocked.applicationTokens.isEmpty ? nil : plan.blocked.applicationTokens
        store.shield.webDomains = plan.blocked.webDomainTokens.isEmpty ? nil : plan.blocked.webDomainTokens
        if let allow = plan.allowed {
            store.shield.applicationCategories = .all(except: allow.applicationTokens)
            store.shield.webDomainCategories = .all(except: allow.webDomainTokens)
        } else {
            store.shield.applicationCategories = nil
            store.shield.webDomainCategories = nil
        }
        // Category-specific exceptions cannot share one Apple's .specific
        // policy. Keep separate cohorts; a promoted category revokes only its
        // own exceptions, while spent categories keep unrelated session frees.
        if categoriesApplied {
            dayNightSelected.clearAllSettings()
            dayNightOther.clearAllSettings()
        } else {
            // Coordination failure cannot silently drop a spent category.
            // Preserve old cohorts and conservatively apply all current ones.
            dayNightSelected.shield.applicationCategories = plan.blocked.categoryTokens.isEmpty ? nil
                : .specific(plan.blocked.categoryTokens)
            dayNightSelected.shield.webDomainCategories = plan.blocked.categoryTokens.isEmpty ? nil
                : .specific(plan.blocked.categoryTokens)
            if !SharedStore.enforcementDegraded { SharedStore.enforcementDegraded = true }
        }

        // App-deletion lock (blocks deleting ANY app, incl. this one).
        store.application.denyAppRemoval = state.blockAppRemoval ? true : nil

        // Web content filter. Apple's API only blocks specific domains through
        // the same filter that limits adult content, so a custom blocklist
        // turns on adult filtering too. `.auto` = limit adult sites + block the
        // given domains.
        let customDomains = Set(state.blockedDomains.map { WebDomain(domain: $0) })
        if state.blockAdultWebsites || !customDomains.isEmpty {
            store.webContent.blockedByFilter = .auto(customDomains, except: [])
        } else {
            store.webContent.blockedByFilter = nil
        }
    }

    /// New day: nothing has hit its threshold and no minutes are used yet.
    static func clearForNewDay() {
        SharedStore.saveBlockedLimitIDs([])
        SharedStore.clearUsageTracking()
        // The reset ran, so the "still blocked?" fallback nudge is moot.
        ChangeEngine.cancelResetNudge()
        refresh()
    }
}
