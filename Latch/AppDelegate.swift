//
//  AppDelegate.swift
//  Handles CloudKit silent pushes so a trusted contact's override approval
//  applies in the background — without the user reopening Demora.
//
//

import UIKit
import CloudKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // CloudKit delivers its pushes over APNs, so we still register here.
        application.registerForRemoteNotifications()
        ContactsRelay.ensureApprovalSubscription()
        return true
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
