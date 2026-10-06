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
    /// highest priority: limits < recurring < planned < session.
    private static func apply(state: LatchState) {
        let blockedIDs = SharedStore.loadBlockedLimitIDs()
        let now = Date()
        let featureBlockedIDs = LimitFeatures.blockedFeatureIDs(state: state, at: now)
        let extraUnblockedIDs = LimitFeatures.extraUnblockedIDs(state: state, at: now)

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
        where ((limit.minutes(on: now) == 0 || blockedIDs.contains(limit.id))
                && !extraUnblockedIDs.contains(limit.id))
            || featureBlockedIDs.contains(limit.id) {
            block(limit.selection)
        }

        // Global wake and sleep boundaries layer above ordinary usage limits.
        // Excluding a group here never clears its separately-spent daily limit.
        func applyBoundary(_ scope: BoundaryBlockScope) {
            var selection = scope.selection
            if scope.mode == .blockGroups {
                selection = FamilyActivitySelection()
                for group in state.limits where scope.groupIDs.contains(group.id)
                    && !scope.excludedLimitIDs.contains(group.id) {
                    selection.applicationTokens.formUnion(group.selection.applicationTokens)
                    selection.categoryTokens.formUnion(group.selection.categoryTokens)
                    selection.webDomainTokens.formUnion(group.selection.webDomainTokens)
                }
            } else {
                for group in state.limits where scope.excludedLimitIDs.contains(group.id) {
                    if scope.mode == .blockAllExcept {
                        selection.applicationTokens.formUnion(group.selection.applicationTokens)
                        selection.webDomainTokens.formUnion(group.selection.webDomainTokens)
                    } else {
                        selection.applicationTokens.subtract(group.selection.applicationTokens)
                        selection.categoryTokens.subtract(group.selection.categoryTokens)
                        selection.webDomainTokens.subtract(group.selection.webDomainTokens)
                    }
                }
            }
            scope.mode == .blockAllExcept ? allExcept(selection) : block(selection)
        }
        switch GlobalWake.status(state: state, at: now) {
        case .needsTap, .waiting:
            applyBoundary(state.wakeRule.scope)
        case .inactive, .awake:
            break
        }
        if state.sleepRule.enabled,
           windowActive(at: now,
                        start: state.sleepRule.startMinutes,
                        end: state.wakeRule.startHour * 60,
                        recurrence: .weekly(state.sleepRule.weekdays)) {
            applyBoundary(state.sleepRule.scope)
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

        let nightPlan = DayNightPolicy.plan(state: state, at: now) {
            DayNightWake.status(group: $0, at: now)
        }
        dayNightSelected.shield.applications = nightPlan.blocked.applicationTokens.isEmpty
            ? nil : nightPlan.blocked.applicationTokens
        dayNightSelected.shield.webDomains = nightPlan.blocked.webDomainTokens.isEmpty
            ? nil : nightPlan.blocked.webDomainTokens
        dayNightSelected.shield.applicationCategories = nightPlan.blocked.categoryTokens.isEmpty
            ? nil : .specific(nightPlan.blocked.categoryTokens, except: nightPlan.freed.applicationTokens)
        dayNightSelected.shield.webDomainCategories = nightPlan.blocked.categoryTokens.isEmpty
            ? nil : .specific(nightPlan.blocked.categoryTokens, except: nightPlan.freed.webDomainTokens)
        dayNightOther.shield.applicationCategories = nightPlan.allowed.map {
            .all(except: $0.applicationTokens)
        }
        dayNightOther.shield.webDomainCategories = nightPlan.allowed.map {
            .all(except: $0.webDomainTokens)
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
        // The reset ran, so the "still blocked?" fallback nudge is moot.
        ChangeEngine.cancelResetNudge()
        refresh()
    }
}
