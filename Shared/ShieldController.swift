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

    /// Re-derive shields from state + blocked limit IDs. Idempotent —
    /// safe to call from the app or any extension at any time.
    ///
    /// Rules are layered from lowest to highest priority so the higher one has
    /// the final say:  limits  <  recurring  <  planned  <  session.
    /// Within the recurring group, the most recently added window is applied
    /// last (so it wins). Each rule either blocks apps, "blocks all except" an
    /// allowlist, frees specific apps (unblock sessions), or frees everything
    /// (a free period). Stricter specific blocks still apply on top of an
    /// "all except" so a limit-spent allowlisted app stays blocked.
    static func refresh() {
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
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
        store.application.denyAppRemoval = nil
        store.webContent.blockedByFilter = nil
    }

    /// Re-derive and apply every shield from the given state. Layered lowest to
    /// highest priority: limits < recurring < planned < session.
    private static func apply(state: LatchState) {
        let blockedIDs = SharedStore.loadBlockedLimitIDs()
        let now = Date()

        var apps = Set<ApplicationToken>()
        var cats = Set<ActivityCategoryToken>()
        var webs = Set<WebDomainToken>()
        // nil = no "block all except" in effect.
        var allowApps: Set<ApplicationToken>?
        var allowWebs = Set<WebDomainToken>()
        // Apps/domains an unblock session freed — excepted from category shields
        // too, so unblocking works even when the block came from a category.
        var freedApps = Set<ApplicationToken>()
        var freedWebs = Set<WebDomainToken>()

        func block(_ s: FamilyActivitySelection) {
            apps.formUnion(s.applicationTokens)
            cats.formUnion(s.categoryTokens)
            webs.formUnion(s.webDomainTokens)
            // A re-block overrides an earlier free for the same items.
            freedApps.subtract(s.applicationTokens)
            freedWebs.subtract(s.webDomainTokens)
        }
        func freeSel(_ s: FamilyActivitySelection) {
            apps.subtract(s.applicationTokens)
            cats.subtract(s.categoryTokens)
            webs.subtract(s.webDomainTokens)
            freedApps.formUnion(s.applicationTokens)
            freedWebs.formUnion(s.webDomainTokens)
            if allowApps != nil {
                allowApps!.formUnion(s.applicationTokens)
                allowWebs.formUnion(s.webDomainTokens)
            }
        }
        func freeAll() {
            apps.removeAll(); cats.removeAll(); webs.removeAll()
            allowApps = nil; allowWebs.removeAll()
            freedApps.removeAll(); freedWebs.removeAll()
        }
        func allExcept(_ s: FamilyActivitySelection) {
            allowApps = s.applicationTokens
            allowWebs = s.webDomainTokens
        }

        // 0. Limits that ran out (baseline). A 0-minute limit allows no time at
        //    all, so it's blocked all day regardless of usage.
        for limit in state.limits
        where limit.minutesPerDay == 0 || blockedIDs.contains(limit.id) {
            block(limit.selection)
        }

        // 1. Recurring (schedules + free periods), oldest-added first.
        var recurring: [(Date, () -> Void)] = []
        for s in state.schedules where s.isActive(at: now) {
            let sel = s.selection, mode = s.mode
            recurring.append((s.addedAt, {
                mode == .blockAllExcept ? allExcept(sel) : block(sel)
            }))
        }
        for e in state.exemptions where e.isActive(at: now) {
            recurring.append((e.addedAt, { freeAll() }))
        }
        for (_, apply) in recurring.sorted(by: { $0.0 < $1.0 }) { apply() }

        // 2. Planned one-off windows (add order).
        for w in state.planned where w.isActive {
            switch w.kind {
            case .blockSelected:  block(w.selection)
            case .blockAllExcept: allExcept(w.selection)
            case .free:           freeAll()
            }
        }

        // 3. Sessions (add order) — highest priority.
        for s in state.sessions where s.isActive {
            switch s.kind {
            case .block:   block(s.selection)
            case .unblock: freeSel(s.selection)
            case .free:    freeAll()          // a one-off free period
            }
        }

        // Apply to the store.
        if let allow = allowApps {
            store.shield.applicationCategories = .all(except: allow)
            store.shield.webDomainCategories = .all(except: allowWebs)
            store.shield.applications = apps.isEmpty ? nil : apps
            store.shield.webDomains = webs.isEmpty ? nil : webs
        } else {
            store.shield.applications = apps.isEmpty ? nil : apps
            store.shield.applicationCategories = cats.isEmpty
                ? nil : .specific(cats, except: freedApps)
            store.shield.webDomains = webs.isEmpty ? nil : webs
            store.shield.webDomainCategories = cats.isEmpty
                ? nil : .specific(cats, except: freedWebs)
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
        SharedStore.clearReconciledUnblocked()   // yesterday's overrides don't carry
        refresh()
    }
}
