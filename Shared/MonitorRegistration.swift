import Foundation
import DeviceActivity

/// One admission/registration policy for the app and Screen Time extensions.
/// Echoes are optional retries; never evict an enforcement or usage activity.
enum MonitorRegistration {
    private static let rejectionKey = "latch.monitoringCapacity.rejection.v1"
    enum CapacityError: Error { case full }

    static var rejectionMessage: String? {
        guard let raw = SharedStore.defaults.string(forKey: rejectionKey), let required = Int(raw) else { return nil }
        return String(format: tr("This change needs %d background monitors, but iOS allows %d. Remove a schedule, split budget or pending change, then try again."),
                      required, MonitoringBudget.maximum)
    }
    static func clearRejection() { SharedStore.defaults.set(nil, forKey: rejectionKey) }
    static func reject(required: Int) { SharedStore.defaults.set(String(required), forKey: rejectionKey) }

    static func admit(state: LatchState, running: Set<String>, repair: Bool = false) -> Bool {
        let required = MonitoringBudget.required(state: state, running: running)
        guard required <= MonitoringBudget.maximum || repair else {
            reject(required: required)
            return false
        }
        return true
    }

    static func start(_ name: DeviceActivityName, during schedule: DeviceActivitySchedule,
                      events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]) throws {
        let center = DeviceActivityCenter()
        let running = Set(center.activities.map(\.rawValue))
        let replacing = running.contains(name.rawValue)
        if name.rawValue.hasPrefix("echo-") {
            let reserved = MonitoringBudget.required(state: SharedStore.loadState(), running: running)
            let echoes = running.filter { $0.hasPrefix("echo-") }.count
            guard replacing || (running.count < MonitoringBudget.maximum
                && reserved + echoes < MonitoringBudget.maximum) else { throw CapacityError.full }
        }
        // A replacement is not another slot. Apple is still the final arbiter:
        // another process can register between occupancy and this XPC call.
        do { try center.startMonitoring(name, during: schedule, events: events) }
        catch {
            // Ask Apple first: an invalid schedule or denied authorization
            // must not evict working retries. Only a capacity error permits
            // one bounded retry, after releasing known optional echoes.
            if !name.rawValue.hasPrefix("echo-"),
               let reason = error as? DeviceActivityCenter.MonitoringError,
               reason == .excessiveActivities {
                let fresh = Set(center.activities.map(\.rawValue))
                let optional = fresh.filter { $0.hasPrefix("echo-") }.sorted()
                let needed = max(0, fresh.count - MonitoringBudget.maximum
                                 + (fresh.contains(name.rawValue) ? 0 : 1))
                if optional.count >= needed {
                    if needed > 0 {
                        center.stopMonitoring(optional.prefix(needed).map { DeviceActivityName($0) })
                    }
                    do {
                        try center.startMonitoring(name, during: schedule, events: events)
                        return
                    } catch {
                        SharedStore.enforcementDegraded = true
                        NSLog("Demora: monitor registration retry failed: %@", String(describing: error))
                        throw error
                    }
                }
            }
            if !name.rawValue.hasPrefix("echo-") {
                SharedStore.enforcementDegraded = true
                NSLog("Demora: monitor registration failed: %@", String(describing: error))
            }
            throw error
        }
    }
}
