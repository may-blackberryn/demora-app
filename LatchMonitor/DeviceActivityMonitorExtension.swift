//
//  DeviceActivityMonitorExtension.swift
//  LatchMonitor — background brain of the app.
//
//  • Daily interval start: new day → clear yesterday's blocks, apply any
//    due pending changes.
//  • Threshold event: a limit's daily minutes ran out → shield its apps.
//  • One-shot "apply" intervals: a pending change's delay elapsed →
//    apply it without the app being opened.
//

import DeviceActivity
import ManagedSettings
import Foundation

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        let raw = activity.rawValue
        if raw == LatchConstants.dailyActivityName {
            // This callback fires both at real midnight AND whenever the daily
            // monitor is restarted mid-day to apply reduced thresholds. Only a
            // genuine new day should wipe today's blocks and usage — otherwise
            // applying a session (or any change) would un-block a spent limit.
            let today = SharedStore.dayKey(for: TimeGuard.now())
            if SharedStore.lastResetDay != today {
                ShieldController.clearForNewDay()           // clears blocks + usage
                SharedStore.lastResetDay = today
                // Restore full budgets for the new day. The restart this causes
                // re-fires this callback, but lastResetDay now equals today, so
                // it falls through without wiping anything (no loop).
                ChangeEngine.reconfigureDailyMonitoring(state: SharedStore.loadState())
            }
            // Otherwise: a mid-day restart. The restart that triggered this
            // already set the correct thresholds, so we leave usage/blocks alone.
        }
        if raw.hasPrefix("exempt-") {
            // Free period begins: start measuring per-limit usage inside the
            // window so it can be credited back when the window ends.
            ChangeEngine.exemptWindowStarted()
        }
        if raw.hasPrefix("planned-"),
           let id = UUID(uuidString: String(raw.dropFirst(8))),
           SharedStore.loadState().planned
               .first(where: { $0.id == id })?.kind == .free {
            ChangeEngine.exemptWindowStarted()
        }
        // Covers one-shot apply activities and schedule/session windows too.
        ChangeEngine.applyDueChanges()
        ShieldController.refresh()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        let raw = activity.rawValue
        if raw.hasPrefix("exempt-") {
            // Free period over: credit each limit's measured in-window usage.
            ChangeEngine.exemptWindowEnded()
        }
        if raw.hasPrefix("session-") {
            ChangeEngine.pruneExpiredSessions()
        }
        if raw.hasPrefix("planned-") {
            if let id = UUID(uuidString: String(raw.dropFirst(8))),
               SharedStore.loadState().planned
                   .first(where: { $0.id == id })?.kind == .free {
                ChangeEngine.exemptWindowEnded()
            }
            ChangeEngine.prunePastPlanned()
        }
        ChangeEngine.applyDueChanges()
        ShieldController.refresh()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        let raw = event.rawValue
        if raw.hasPrefix("limit-"),
           let id = UUID(uuidString: String(raw.dropFirst(6))) {
            // Budget spent → block for the rest of the day.
            SharedStore.mutateBlockedLimitIDs { blocked in
                blocked.insert(id)
            }
            ShieldController.refresh()
        } else if raw.hasPrefix("fw-") {
            // Silent free-window checkpoint — per-limit usage inside the window.
            ChangeEngine.recordFreeWindowCheckpoint(eventName: raw)
        }
    }
}
