import Foundation
import FamilyControls

struct DayNightShieldPlan {
    var blocked = FamilyActivitySelection()
    var allowed: FamilyActivitySelection? = nil
    var freed = FamilyActivitySelection()
}

/// Pure restrictive composition. Exceptions belong only to their own group;
/// finishing one wait cannot clear another group's block or a spent limit.
enum DayNightPolicy {
    static func plan(state: LatchState, at date: Date,
                     wakeStatus: (DayNightGroup) -> GlobalWakeStatus) -> DayNightShieldPlan {
        var plan = DayNightShieldPlan()
        func add(_ group: DayNightGroup, wake: Bool) {
            var targets = group.scope.resolved(limits: state.limits)
            if group.scope.mode == .selected {
                plan.blocked.applicationTokens.formUnion(targets.applicationTokens)
                plan.blocked.categoryTokens.formUnion(targets.categoryTokens)
                plan.blocked.webDomainTokens.formUnion(targets.webDomainTokens)
                return
            }
            // A shorter/longer default must not change the independently
            // chosen wait for apps in an explicitly timed group.
            for other in state.dayNightGroups where other.scope.mode == .selected
                && (wake ? other.wakeEnabled : other.sleepEnabled) {
                let selected = other.scope.resolved(limits: state.limits)
                targets.applicationTokens.formUnion(selected.applicationTokens)
                targets.webDomainTokens.formUnion(selected.webDomainTokens)
            }
            if var allowed = plan.allowed {
                allowed.applicationTokens.formIntersection(targets.applicationTokens)
                allowed.webDomainTokens.formIntersection(targets.webDomainTokens)
                plan.allowed = allowed
            } else {
                targets.categoryTokens = []
                plan.allowed = targets
            }
        }
        for group in state.dayNightGroups {
            switch wakeStatus(group) {
            case .needsTap, .waiting: add(group, wake: true)
            case .inactive, .awake: break
            }
            if group.sleepIsActive(at: date) {
                add(group, wake: false)
            }
        }
        // Retain Demora's explicit, delay-gated free/unblock semantics across
        // all three stores. Ordinary block sessions remain in latch.main.
        if state.exemptions.contains(where: { $0.isActive(at: date) })
            || state.planned.contains(where: { $0.kind == .free && date >= $0.startsAt && date < $0.endsAt })
            || state.sessions.contains(where: { $0.kind == .free && date >= $0.startedAt && date < $0.endsAt }) {
            return DayNightShieldPlan()
        }
        for session in state.sessions where session.kind == .unblock
            && date >= session.startedAt && date < session.endsAt {
            let selected = session.selection
            plan.blocked.applicationTokens.subtract(selected.applicationTokens)
            plan.blocked.categoryTokens.subtract(selected.categoryTokens)
            plan.blocked.webDomainTokens.subtract(selected.webDomainTokens)
            plan.freed.applicationTokens.formUnion(selected.applicationTokens)
            plan.freed.webDomainTokens.formUnion(selected.webDomainTokens)
            if plan.allowed != nil {
                plan.allowed!.applicationTokens.formUnion(selected.applicationTokens)
                plan.allowed!.webDomainTokens.formUnion(selected.webDomainTokens)
            }
        }
        return plan
    }
}
