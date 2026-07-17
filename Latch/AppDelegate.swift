//
//  AppDelegate.swift
//  Handles CloudKit silent pushes so a trusted contact's override approval
//  applies in the background — without the user reopening Demora.
//
//

import UIKit
import CloudKit
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // CloudKit delivers its pushes over APNs, so we still register here.
        application.registerForRemoteNotifications()
        ContactsRelay.ensureApprovalSubscription()
        // Register the background-refresh handler BEFORE launch finishes (a hard
        // requirement of BGTaskScheduler), then queue the first run.
        registerBackgroundRefresh()
        scheduleMidnightRefresh()
        return true
    }

    // MARK: - Background refresh (extra overnight wake for the daily rollover)
    //
    // A best-effort second lottery ticket, independent of the DeviceActivity
    // extension: iOS tends to run BGAppRefreshTasks while the device charges
    // overnight — exactly when a spent limit would otherwise sit stale until
    // morning. It runs the same idempotent rollover the app runs on foreground,
    // so it's a no-op whenever a DeviceActivity callback already handled midnight.

    private func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: LatchConstants.bgRefreshID, using: nil
        ) { [weak self] task in
            self?.handleMidnightRefresh(task as! BGAppRefreshTask)
        }
    }

    /// Ask iOS to run us shortly after the next midnight. `earliestBeginDate` is
    /// a floor, not a promise — iOS decides the actual time (often overnight
    /// while charging). Re-submitting with the same id replaces any pending one.
    func scheduleMidnightRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: LatchConstants.bgRefreshID)
        let cal = Calendar.current
        let nextMidnight = cal.date(byAdding: .day, value: 1,
                                    to: cal.startOfDay(for: Date()))
        request.earliestBeginDate = nextMidnight?.addingTimeInterval(10 * 60) // 00:10
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("Demora: failed to submit background refresh: \(error)")
        }
    }

    private func handleMidnightRefresh(_ task: BGAppRefreshTask) {
        // Chain the next one first, so the schedule never dies if this run is cut short.
        scheduleMidnightRefresh()
        // The work is quick and idempotent; nothing to cancel on expiration.
        task.expirationHandler = { }
        // housekeeping() is sufficient: its rolloverIfNewDay already
        // reconfigures monitoring when the day actually changed. No explicit
        // reconfigure here — on a same-day run that would pointlessly restart
        // the daily monitor mid-night, and monitor restarts are the one
        // operation with a history of side effects (spurious threshold
        // re-fires, racing the extension's own rollover).
        // NOTE: runs on a background queue (register uses `using: nil`) —
        // keep AppModel/@Published state out of this path.
        ChangeEngine.housekeeping()
        task.setTaskCompleted(success: true)
    }

    // CloudKit routes pushes itself; we don't need the device token, but the
    // callbacks must exist for registration to complete.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken _: Data) {}
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError _: Error) {
        // Non-fatal: approvals still apply when the app is next opened.
    }

    /// A silent push arrived. If it's our approval subscription, apply any
    /// newly-approved override changes in the background.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler:
            @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let isOurs = CKNotification(fromRemoteNotificationDictionary: userInfo)?
            .subscriptionID == ContactsRelay.approvalSubscriptionID
        guard isOurs else { completionHandler(.noData); return }
        Task {
            let applied = await ContactsRelay.processApprovalsInBackground()
            completionHandler(applied ? .newData : .noData)
        }
    }
}
