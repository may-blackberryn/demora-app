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
    // Three legacy stores + at most 42 category cohorts + 4 overflow stores
    // stay below Apple's 50 named-store ceiling. Names are shared by the host
    // and all extensions. (2.0.0 allowed 46 cohorts; 42–45 are swept once.)
    private static let categoryStoreCapacity = 42
    private static let legacyCategoryStoreCapacity = 46
    private static let legacyCohortsSweptKey = "latch.scheduleCategoryStores.swept42.v1"

    // MARK: 50-token cap (2.0.1)
    //
    // Apple shields at most 50 app tokens and 50 web-domain tokens per store
    // setting (documented for sites, categories and exceptions; reported for
    // apps): with more, the store shields NOTHING. Up to 50, everything stays
    // in `latch.main` exactly as before. Above that, each token goes to a
    // store chosen by a stable hash of its bytes, so a token never moves
    // between stores while the set changes around it. A full bucket, or an
    // exception list over 50, is trimmed (under-blocking a few tokens, or
    // over-blocking a few allowed ones) and recorded for Details.
    private static let tokensPerStore = 50
    private static let overflowStoreCount = 4
    private static func overflowStore(_ index: Int) -> ManagedSettingsStore {
        ManagedSettingsStore(named: .init("latch.overflow.\(index)"))
    }

    /// FNV-1a over the token's encoded bytes: stable across processes and
    /// launches, unlike Swift's seeded `Hasher`.
    private static func stableHash<T: Encodable>(_ token: T) -> UInt64 {
        guard let data = try? JSONEncoder().encode(token) else { return 0 }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data { hash ^= UInt64(byte); hash = hash &* 0x100000001b3 }
        // Finalizer (MurmurHash3 fmix64): FNV's low bits are skewed when
        // encodings share a suffix, which would crowd one store.
        hash ^= hash >> 33; hash = hash &* 0xff51afd7ed558ccd
        hash ^= hash >> 33; hash = hash &* 0xc4ceb9fe1a85ec53
        hash ^= hash >> 33
        return hash
    }

    /// Store 0 is `latch.main`; 1… are the overflow stores.
    private static func distribute<T: Hashable & Encodable>(_ tokens: Set<T>) -> (stores: [Set<T>], trimmed: Bool) {
        var stores = Array(repeating: Set<T>(), count: 1 + overflowStoreCount)
        if tokens.count <= tokensPerStore { stores[0] = tokens; return (stores, false) }
        var trimmed = false
        let ordered = tokens.map { ($0, stableHash($0)) }.sorted { $0.1 < $1.1 }
        for (token, hash) in ordered {
            // Home store by hash; if it's full, the next store with room.
            let home = Int(hash % UInt64(stores.count))
            if let bucket = (0..<stores.count).map({ (home + $0) % stores.count })
                .first(where: { stores[$0].count < tokensPerStore }) {
                stores[bucket].insert(token)
            } else {
                trimmed = true
            }
        }
        return (stores, trimmed)
    }

    /// At most 50 exceptions, chosen stably. Dropped exceptions stay shielded.
    private static func capped<T: Hashable & Encodable>(_ tokens: Set<T>) -> (tokens: Set<T>, trimmed: Bool) {
        guard tokens.count > tokensPerStore else { return (tokens, false) }
        let kept = tokens.map { ($0, stableHash($0)) }.sorted { $0.1 < $1.1 }.prefix(tokensPerStore).map(\.0)
        return (Set(kept), true)
    }
    private static let categoryStoreCountKey = "latch.scheduleCategoryStores.v1"
    private static let categoryStoreUnverifiedKey = "latch.scheduleCategoryStores.unverified.v1"
    private static func categoryStore(_ index: Int) -> ManagedSettingsStore {
        ManagedSettingsStore(named: .init("latch.schedule.category.\(index)"))
    }

    /// Set while a refresh trims a token list to Apple's 50 (recorded after).
    private static var tokenCapHit = false

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
                // Fails safe (over-blocks); still worth showing. Recording an
                // unchanged failure again doesn't rewrite preferences.
                SharedStore.recordEnforcementFailure(SharedStore.EnforcementKey.categoryShields,
                                                     detail: "category exceptions merged")
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
                // 2.0.1: only the read-back decides. A defaults write reaches
                // the preferences daemon when it's made; `synchronize()` is
                // documented as unnecessary, and its result can stay false
                // (seen on a device: every refresh then failed this step, the
                // unverified flag never cleared and category shields never
                // published). It's still called as a harmless flush hint.
                _ = SharedStore.defaults.synchronize()
                guard SharedStore.defaults.object(forKey: categoryStoreCountKey) as? Int == highWater
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
                let apps = capped(group.applicationTokens), sites = capped(group.webDomainTokens)
                if apps.trimmed || sites.trimmed { tokenCapHit = true }
                target.shield.applicationCategories = .specific(group.categoryTokens, except: apps.tokens)
                target.shield.webDomainCategories = .specific(group.categoryTokens, except: sites.tokens)
            }
            for index in groups.count..<highWater {
                let target = categoryStore(index)
                if target.shield.applicationCategories != nil || target.shield.webDomainCategories != nil {
                    target.clearAllSettings()
                }
            }
            // Once: 2.0.0 could use cohorts 42–45, now beyond the capacity.
            if !SharedStore.defaults.bool(forKey: legacyCohortsSweptKey) {
                for index in categoryStoreCapacity..<legacyCategoryStoreCapacity {
                    categoryStore(index).clearAllSettings()
                }
                SharedStore.defaults.set(true, forKey: legacyCohortsSweptKey)
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
            SharedStore.recordEnforcementFailure(SharedStore.EnforcementKey.stateLock,
                                                 detail: "shield refresh couldn't take the state lock")
            return
        }
        SharedStore.clearEnforcementFailure(SharedStore.EnforcementKey.stateLock)
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
        // Missing or undecodable saved state is unknown, not "no rules": keep
        // whatever shields are in place rather than lifting every block and
        // the deletion lock (2.0.1). The next refresh with readable state
        // re-derives everything.
        guard let state = SharedStore.loadStateForEnforcement() else {
            // Except the deletion lock: with unreadable rules the app can't
            // save or recover by itself, and reinstalling must stay possible.
            NSLog("Demora: saved rules unreadable; keeping app shields, lifting deletion lock")
            store.application.denyAppRemoval = nil
            return
        }
        apply(state: state)
    }

    /// Remove every shield this store owns.
    private static func clearAll() {
        applyCategoryShields([])
        for index in 1...overflowStoreCount { overflowStore(index).clearAllSettings() }
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
        tokenCapHit = false
        let categoriesApplied = applyCategoryShields(plan.categoryShields)
        let apps = distribute(plan.blocked.applicationTokens)
        let sites = distribute(plan.blocked.webDomainTokens)
        if apps.trimmed || sites.trimmed { tokenCapHit = true }
        // Order so a token is never briefly unshielded: when the set grows
        // into the overflow stores, write them before latch.main drops the
        // token; when it shrinks back, latch.main takes the tokens first and
        // only then are the overflow stores cleared. Whether overflow stores
        // hold anything is read from the stores themselves (no flag to strand).
        let overflowNeeded = apps.stores.dropFirst().contains { !$0.isEmpty }
            || sites.stores.dropFirst().contains { !$0.isEmpty }
        func writeOverflow() {
            for index in 1...overflowStoreCount {
                let target = overflowStore(index)
                let newApps = apps.stores[index].isEmpty ? nil : apps.stores[index]
                let newSites = sites.stores[index].isEmpty ? nil : sites.stores[index]
                if target.shield.applications != newApps { target.shield.applications = newApps }
                if target.shield.webDomains != newSites { target.shield.webDomains = newSites }
            }
        }
        if overflowNeeded { writeOverflow() }
        store.shield.applications = apps.stores[0].isEmpty ? nil : apps.stores[0]
        store.shield.webDomains = sites.stores[0].isEmpty ? nil : sites.stores[0]
        if !overflowNeeded { writeOverflow() }
        if let allow = plan.allowed {
            let allowedApps = capped(allow.applicationTokens), allowedSites = capped(allow.webDomainTokens)
            if allowedApps.trimmed || allowedSites.trimmed { tokenCapHit = true }
            store.shield.applicationCategories = .all(except: allowedApps.tokens)
            store.shield.webDomainCategories = .all(except: allowedSites.tokens)
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
            if plan.categoryShields.count <= categoryStoreCapacity {
                SharedStore.clearEnforcementFailure(SharedStore.EnforcementKey.categoryShields)
            }
        } else {
            // Coordination failure cannot silently drop a spent category.
            // Preserve old cohorts and conservatively apply all current ones.
            // Every category any cohort blocks, not just the baseline's.
            let fallback = plan.blocked.categoryTokens
                .union(plan.categoryShields.flatMap(\.categoryTokens))
            dayNightSelected.shield.applicationCategories = fallback.isEmpty ? nil : .specific(fallback)
            dayNightSelected.shield.webDomainCategories = fallback.isEmpty ? nil : .specific(fallback)
            SharedStore.recordEnforcementFailure(SharedStore.EnforcementKey.categoryShields,
                                                 detail: "category shields not published")
        }

        if tokenCapHit {
            SharedStore.recordEnforcementFailure(SharedStore.EnforcementKey.tokenCap,
                                                 detail: "more than 50 apps or sites in one shield")
        } else {
            SharedStore.clearEnforcementFailure(SharedStore.EnforcementKey.tokenCap)
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
        // A late rollover can clear a block earned after midnight; the daily
        // re-registration that follows (includesPastActivity) re-fires every
        // limit genuinely spent today, so nothing is kept here.
        SharedStore.saveBlockedLimitIDs([])
        SharedStore.clearUsageTracking()
        // The reset ran, so the "still blocked?" fallback nudge is moot.
        ChangeEngine.cancelResetNudge()
        refresh()
    }
}
