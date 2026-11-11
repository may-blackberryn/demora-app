//
//  AppModel.swift
//  Observable wrapper around the shared store + change engine.
//

import Foundation
import SwiftUI
import Combine
import CryptoKit
import FamilyControls
import DeviceActivity
import UserNotifications
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published var state = SharedStore.loadState()
    @Published var authorized = false

    @Published var setupStorageUnavailable = false
    @Published var language: AppLanguage = AppLanguage.current {
        didSet { AppLanguage.current = language }
    }
    /// Set when a queue attempt is rejected; shown as an alert.
    @Published var queueNotice: String?
    @Published var queueNoticeIsCapacity = false

    /// Set when a trusted contact revokes their permission; shown as an alert.
    @Published var contactNotice: String?

    /// Count of pending "be my trusted contact" invites awaiting your answer;
    /// drives the invite dot on the You tab.
    @Published var incomingInviteCount = 0

    /// Mirror of SharedStore.enforcementDegraded — drives the warning banner
    /// when iOS couldn't schedule all the background monitors (too many
    /// limits/schedules).
    @Published var enforcementDegraded = false

    /// Demora-user contact codes that aren't currently reachable (their code
    /// isn't found in CloudKit — account gone, or a different build
    /// environment). Held in memory only (never persisted), so it re-checks
    /// fresh each launch and a transient/empty read never sticks. Drives an
    /// in-app "Unavailable" indicator; no notification is sent.
    @Published var unavailableContactCodes: Set<String> = []

    /// Selected bottom tab (0 Today, 1 Rules, 2 Insights, 3 You).
    /// Published for navigation-only cross-tab actions and widget links.
    @Published var selectedTab = 0

    /// Navigation path for You. Keep it when its tab is reconstructed so
    /// language changes in Appearance never pop the user back to its root.
    @Published var youPath: [YouRoute] = []

    private var timer: AnyCancellable?
    private var housekeepingInFlight = false

    init() {
        // A replay interrupted by a force-quit: restore the user's real setup
        // from the backup so nothing is lost (and so we don't fall into the
        // not-set-up onboarding branch below).
        if SharedStore.isReplaying {
            restoreFromReplay()
        }
        let replayRestored = !SharedStore.isReplaying
        if replayRestored { migrateScreenTimeCodeToKeychain() }
        let migrationSucceeded = replayRestored && SharedStore.prepareRedesignMigration()
        setupStorageUnavailable = !migrationSucceeded || SharedStore.stateRecoveryNeeded
        // A force-quit mid-tutorial leaves the app not-yet-set-up with leftover
        // dummy data; wipe it so onboarding restarts clean.
        if migrationSucceeded && !SharedStore.stateRecoveryNeeded && !SharedStore.loadState().isSetUp {
            resetForOnboarding()
        }
        // Fast path so an approved install doesn't flash the banner.
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        // authorizationStatus is unreliable — it can read .notDetermined even
        // when access is granted, which showed the re-auth banner on every
        // launch. requestAuthorization is authoritative: it returns SILENTLY
        // when already approved, so confirm with it for a set-up install. It
        // won't prompt unless access is genuinely missing, and never runs during
        // onboarding/the tutorial (which handle authorization themselves).
        if !setupStorageUnavailable && SharedStore.loadState().isSetUp {
            Task { [weak self] in await self?.verifyAuthorization() }
        }
        // Re-check due changes every 30s while the app is open so a
        // countdown hitting zero applies without relaunching.
        timer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
        tick()
    }

    /// Apply due changes, prune finished sessions, refresh shields & state.
    func tick() {
        guard !setupStorageUnavailable else { return }
        guard !housekeepingInFlight else { return }
        housekeepingInFlight = true
        Task { [weak self] in
            await ChangeEngine.housekeepingOffMain()
            guard let self else { return }
            self.housekeepingInFlight = false
            self.state = SharedStore.loadState()
            self.enforcementDegraded = SharedStore.enforcementDegraded
            self.checkContactApprovals()
            self.checkContactInvites()
            self.sendPendingEmailInvites()
            self.refreshIncomingInviteCount()
            await TimeGuard.syncWithNetwork()
        }
    }

    /// Demora-user contacts must accept an invite before they can approve for
    /// you. This sends any outstanding invites and applies their answers:
    /// accepted → the contact becomes active; declined → it's dropped.
    private func checkContactInvites() {
        let latch = state.overrides.contacts.filter { $0.latchUserCode != nil }
        let currentInviteIds = Set(latch.map { $0.inviteId })
        // Run even with no latch contacts left, so a removed contact's invite
        // gets cleaned up; skip only when there's genuinely nothing to do.
        guard !latch.isEmpty || ContactsRelay.hasSentInvites else { return }
        Task { [weak self] in
            await ContactsRelay.reconcileSentInvites(currentInviteIds: currentInviteIds)
            for contact in latch {
                guard let code = contact.latchUserCode else { continue }
                if contact.isPending {
                    await ContactsRelay.sendInvite(toCode: code,
                                                   inviteId: contact.inviteId)
                    ContactsRelay.recordSentRequest(code: code, name: contact.name,
                                                    status: "pending")
                }
                // Availability: a *successful* lookup that finds nothing means
                // the code is gone in this environment; a thrown error (network)
                // leaves the current state untouched, so flaky reads don't flag
                // a contact as unavailable.
                if let exists = try? await ContactsRelay.codeExists(code) {
                    await MainActor.run {
                        if exists { self?.unavailableContactCodes.remove(code) }
                        else { self?.unavailableContactCodes.insert(code) }
                    }
                }
                // nil = network error or no answer for this id; true/false = accepted/declined.
                guard let accepted = try? await ContactsRelay.inviteResponse(
                        forContactCode: code, inviteId: contact.inviteId)
                else { continue }
                await MainActor.run {
                    self?.resolveInvite(contactID: contact.id, name: contact.name,
                                        wasActive: contact.accepted, accepted: accepted,
                                        code: code)
                }
            }
        }
    }

    /// Poll CloudKit for incoming "be my trusted contact" invites so the
    /// You tab can show a dot when someone is waiting on your answer (Y7).
    func refreshIncomingInviteCount() {
        Task { [weak self] in
            let count = (try? await ContactsRelay.incomingInvites().count) ?? 0
            await MainActor.run { self?.incomingInviteCount = count }
        }
    }

    /// An email contact entered their emailed code — flip them to active.
    func confirmEmailContact(id: UUID) {
        var s = SharedStore.loadState()
        guard let idx = s.overrides.contacts.firstIndex(where: { $0.id == id }),
              !s.overrides.contacts[idx].accepted else { return }
        s.overrides.contacts[idx].accepted = true
        SharedStore.save(s)
        state = s
    }

    /// Email contacts must confirm with a code before they can approve. Send the
    /// confirmation code once per pending email contact (the profile screen
    /// offers a manual resend if it doesn't arrive).
    private func sendPendingEmailInvites() {
        guard EmailCodeService.isConfigured else { return }
        let pending = state.overrides.contacts.filter {
            $0.isEmail && !$0.accepted && !$0.inviteId.isEmpty
                && !ContactsRelay.wasSentEmail("invite-" + $0.inviteId)
        }
        guard !pending.isEmpty else { return }
        for contact in pending {
            guard case .email(let address) = contact.kind else { continue }
            // Mark first so a slow/failed send doesn't re-fire every tick.
            ContactsRelay.markSent(requestId: "invite-" + contact.inviteId, relay: false)
            Task {
                try? await EmailCodeService.sendInviteCode(
                    inviteId: contact.inviteId, email: address,
                    ownerName: ContactsRelay.myName)
            }
        }
    }

    /// Rename a trusted contact — metadata only, no delay gate.
    func renameContact(id: UUID, to newName: String) {
        var s = SharedStore.loadState()
        guard let idx = s.overrides.contacts.firstIndex(where: { $0.id == id }),
              s.overrides.contacts[idx].name != newName else { return }
        s.overrides.contacts[idx].name = newName
        SharedStore.save(s)
        state = s
    }

    /// Set/clear an owned contact's avatar — metadata only, no delay gate.
    func setContactAvatar(id: UUID, _ avatar: ContactAvatar?) {
        var s = SharedStore.loadState()
        guard let idx = s.overrides.contacts.firstIndex(where: { $0.id == id }),
              s.overrides.contacts[idx].avatar != avatar else { return }
        s.overrides.contacts[idx].avatar = avatar
        SharedStore.save(s)
        state = s
    }

    private func resolveInvite(contactID: UUID, name: String, wasActive: Bool,
                               accepted: Bool, code: String) {
        var s = SharedStore.loadState()
        guard let idx = s.overrides.contacts.firstIndex(where: { $0.id == contactID })
        else { return }
        if accepted {
            guard !s.overrides.contacts[idx].accepted else { return } // already active
            s.overrides.contacts[idx].accepted = true
            ContactsRelay.recordSentRequest(code: code, name: name, status: "accepted")
        } else {
            // declined (was pending), or permission revoked (was active).
            s.overrides.contacts.remove(at: idx)
            ContactsRelay.recordSentRequest(code: code, name: name, status: "denied")
            if wasActive { notifyContactRevoked(name: name) }
        }
        SharedStore.save(s)
        state = s
    }

    private func notifyContactRevoked(name: String) {
        let who = name.isEmpty ? tr("A trusted contact") : name
        contactNotice = String(format:
            tr("%@ removed their permission to be your trusted contact."), who)
        let content = UNMutableNotificationContent()
        content.title = tr("Trusted contact removed")
        content.body = contactNotice ?? ""
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "contact-revoked-\(UUID().uuidString)", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    /// Contact requests keep working after the sheet closes: any pending
    /// change with a sent Latch-user request is checked for approval and
    /// applied automatically.
    private func checkContactApprovals() {
        // Drive off the outgoing request record (which covers the whole group of
        // changes under one requestId), not per pending-change — otherwise a
        // grouped request only ever applies its first change on approval.
        let relayRequests = ContactsRelay.outgoingRequests().filter(\.relay)
        guard !relayRequests.isEmpty else { return }
        Task { [weak self] in
            for req in relayRequests {
                if await ContactsRelay.processApprovalIfAvailable(req) {
                    guard let self else { return }
                    self.refreshAfterExternalApply()
                }
            }
        }
    }


    // MARK: - Prevent-disabling page (delayed, one-time access)

    /// One open has been granted (the unlock change applied) and not yet spent.
    var preventReady: Bool {
        guard let at = state.preventUnlockAt else { return false }
        return TimeGuard.now() >= at
    }
    /// An unlock request is still counting down — it lives on Home as a pending
    /// change, where an override can also skip the wait.
    var preventPending: Bool {
        state.pending.contains {
            if case .unlockPreventGuide = $0.action { return true }
            return false
        }
    }

    /// Queue access to the prevent-disabling page as a pending change, so it
    /// shows on Home with a countdown and can be passed with an override.
    func requestPreventAccess() {
        queue(.unlockPreventGuide)
    }
    /// Spend the one open — re-locks the page so the next view needs a new wait.
    func consumePreventAccess() {
        var s = SharedStore.loadState()
        s.preventUnlockAt = nil
        SharedStore.save(s)
        state = s
    }

    // MARK: - Stored-passcode viewing (its own delayed, one-time access)

    /// One look at the stored passcode has been granted and not yet spent.
    var passwordViewReady: Bool {
        guard let at = state.passwordViewUnlockAt else { return false }
        return TimeGuard.now() >= at
    }
    /// A view-passcode request is still counting down on the Home tab.
    var passwordViewPending: Bool {
        state.pending.contains {
            if case .unlockPasswordView = $0.action { return true }
            return false
        }
    }
    /// Queue viewing the stored passcode as a pending change (delay + override
    /// gates apply, like the guide).
    func requestPasswordViewAccess() {
        queue(.unlockPasswordView)
    }
    /// Spend the one look — re-locks so the next view needs a new wait.
    func consumePasswordViewAccess() {
        var s = SharedStore.loadState()
        s.passwordViewUnlockAt = nil
        SharedStore.save(s)
        state = s
    }

    static let screenTimeCodeKey = "latch.screenTimeCode"

    /// The stored Screen Time passcode (empty if none saved). Lives in the
    /// device-only Keychain, not UserDefaults, so it isn't in backups.
    var screenTimeCode: String { Keychain.getString(for: Self.screenTimeCodeKey) ?? "" }

    /// Save/replace the stored Screen Time passcode. Metadata only — no delay.
    func setScreenTimeCode(_ code: String) {
        Keychain.setString(code.trimmingCharacters(in: .whitespacesAndNewlines),
                           for: Self.screenTimeCodeKey)
        objectWillChange.send()   // computed, not @Published — nudge observers
    }

    /// One-time move of the passcode out of the saved state blob (backed up)
    /// into the Keychain.
    private func migrateScreenTimeCodeToKeychain() {
        let s = SharedStore.loadState()
        guard !SharedStore.stateRecoveryNeeded, !s.screenTimeCode.isEmpty else { return }
        if Keychain.getString(for: Self.screenTimeCodeKey) == nil {
            Keychain.setString(s.screenTimeCode, for: Self.screenTimeCodeKey)
            guard Keychain.getString(for: Self.screenTimeCodeKey) == s.screenTimeCode else { return }
        }
        // Remove only the legacy secret before taking a 2.0 backup. Preserve
        // every other raw field, even keys this version doesn't interpret.
        guard let raw = SharedStore.defaults.data(forKey: LatchConstants.stateKey),
              var object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
        else { return }
        object["screenTimeCode"] = ""
        guard let redacted = try? JSONSerialization.data(withJSONObject: object) else { return }
        SharedStore.defaults.set(redacted, forKey: LatchConstants.stateKey)
        state = SharedStore.loadState()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared
                .requestAuthorization(for: .individual)
            authorized = true
            rebuildMonitoringAfterAuthorization()
        } catch {
            authorized = false
        }
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Authoritative authorization check. `authorizationStatus` can read stale
    /// (.notDetermined even when granted), so we confirm with
    /// requestAuthorization, which returns SILENTLY when already approved. It
    /// prompts only if access is genuinely undetermined, and throws (handled)
    /// only if the user previously denied — so it reliably clears a false
    /// "not authorized" without nagging an approved user.
    func verifyAuthorization() async {
        if AuthorizationCenter.shared.authorizationStatus == .approved {
            authorized = true
            return
        }
        do {
            try await AuthorizationCenter.shared
                .requestAuthorization(for: .individual)
            authorized = true
        } catch {
            authorized = false
        }
    }

    /// Sync the published `authorized` flag with the live Screen Time status.
    /// Called on launch and whenever the app becomes active, so an authorization
    /// that was lost or revoked (e.g. after a TestFlight→App Store install, or a
    /// change in Settings) is reflected even for an already-set-up install that
    /// never re-runs onboarding.
    /// Manual poke (e.g. on foreground): only ever upgrades to authorized. The
    /// observer set up in init is the source of truth and handles a real loss of
    /// access; this just catches a grant made in Settings promptly, and never
    /// downgrades on a possibly-stale synchronous read.
    func refreshAuthorization() {
        if AuthorizationCenter.shared.authorizationStatus == .approved {
            let wasAuthorized = authorized
            authorized = true
            if !wasAuthorized { rebuildMonitoringAfterAuthorization() }
        }
    }

    /// A real authorization transition is one of the few times a forced
    /// rebuild is warranted: Screen Time may retain activity names while their
    /// underlying events were invalidated by the revoked permission.
    private func rebuildMonitoringAfterAuthorization() {
        let current = SharedStore.loadState()
        ChangeEngine.reconfigureDailyMonitoring(state: current)
        LimitFeatures.reconfigureSplitMonitoring(state: current)
        LimitFeatures.reconcile(state: current)
        ChangeEngine.reconfigureWindowMonitoring(state: current)
        ShieldController.refresh()
    }

    // MARK: - Changes

    @discardableResult
    func queue(_ action: ChangeAction) -> PendingChange? {
        let change = ChangeEngine.queue(action)
        state = SharedStore.loadState()
        let haptic = UINotificationFeedbackGenerator()
        if change != nil {
            haptic.notificationOccurred(.success)
        } else {
            haptic.notificationOccurred(.error)
            let capacityNotice = MonitorRegistration.rejectionMessage
            queueNoticeIsCapacity = capacityNotice != nil
            queueNotice = capacityNotice
                ?? tr("A change for this setting is already pending. Cancel it in Changes first if you want something different.")
        }
        return change
    }

    func cancel(_ change: PendingChange) {
        ChangeEngine.cancel(change)
        ContactsRelay.clearSent(change.id.uuidString)
        state = SharedStore.loadState()
    }

    func applyNow(_ change: PendingChange) {
        applyNow([change])
    }

    func applyNow(_ changes: [PendingChange]) {
        Task { [weak self] in
            await self?.applyNowAndWait(changes)
        }
    }

    /// Used by async override gates (notably trusted contacts) so their request
    /// is not cleared until Screen Time maintenance has completed off-main.
    func applyNowAndWait(_ changes: [PendingChange]) async {
        guard !changes.isEmpty else { return }
        _ = await ChangeEngine.applyNowOffMain(changeIDs: changes.map(\.id))
        refreshAfterExternalApply()
    }

    func refreshAfterExternalApply() {
        state = SharedStore.loadState()
    }

    #if DEBUG
    /// Debug only: wipe all limits, schedules, sessions, contacts, and settings
    /// and drop back to first-run onboarding — no delay. Saves deleting and
    /// reinstalling the app to test the fresh-install flow.
    func debugFullReset() {
        SharedStore.debugWipeAll()
        SharedStore.simulating = false
        let s = LatchState()                 // isSetUp == false → onboarding
        SharedStore.save(s)
        state = s
        selectedTab = 0
        youPath = []
        ChangeEngine.reconfigureDailyMonitoring(state: s)
        LimitFeatures.resetForNewDay()
        LimitFeatures.reconfigureSplitMonitoring(state: s)
        ChangeEngine.reconfigureWindowMonitoring(state: s)
        ShieldController.refresh()
    }
    #endif

    // MARK: - Legacy replay recovery

    private func restoreFromReplay() {
        guard !SharedStore.stateRecoveryNeeded,
              let backup = SharedStore.loadBackup() else {
            setupStorageUnavailable = true
            return
        }
        guard SharedStore.save(backup) else {
            setupStorageUnavailable = true
            return
        }
        SharedStore.isReplaying = false
        guard !SharedStore.isReplaying else { setupStorageUnavailable = true; return }
        SharedStore.clearBackup()
        SharedStore.simulating = false
        state = backup
        SharedStore.saveBlockedLimitIDs([])
        ChangeEngine.reconfigureDailyMonitoring(state: state)
        LimitFeatures.reconfigureSplitMonitoring(state: state)
        LimitFeatures.reconcile(state: state)
        ChangeEngine.reconfigureWindowMonitoring(state: state)
        ShieldController.refresh()
        selectedTab = 0
    }

    /// Wipe any leftover tutorial state so a force-quit mid-tutorial starts the
    /// walkthrough fresh (the app only marks itself set up at the very end).
    func resetForOnboarding() {
        guard !SharedStore.stateRecoveryNeeded else { return }
        SharedStore.simulating = false
        let s = LatchState()
        SharedStore.save(s)
        SharedStore.saveBlockedLimitIDs([])
        state = s
        ChangeEngine.reconfigureDailyMonitoring(state: s)
        LimitFeatures.resetForNewDay()
        LimitFeatures.reconfigureSplitMonitoring(state: s)
        ChangeEngine.reconfigureWindowMonitoring(state: s)
        ShieldController.refresh()
    }

    /// Direction an action *would* have — used to show "this will take X" hints.
    func preview(_ action: ChangeAction) -> (ChangeDirection, TimeInterval) {
        let dir = ChangeEngine.classify(action, state: state)
        return (dir, state.delayPolicy.delay(for: dir))
    }

    /// Fresh setup commits only its drafts. The migration welcome has a separate
    /// one-time additive day/night path; it never calls or resets this setup.
    func completeInitialSetup(policy: DelayPolicy, firstLimit: AppLimit?,
                              dayNightGroups: [DayNightGroup] = [],
                              overrides: OverridesConfig = OverridesConfig()) async -> Bool {
        MonitorRegistration.clearRejection()
        guard policy.isValid, overrides.isValidInitialSetup,
              !setupStorageUnavailable, !SharedStore.stateRecoveryNeeded,
              !SharedStore.isReplaying, !SharedStore.loadState().isSetUp else { return false }
        if let limit = firstLimit {
            guard (1...720).contains(limit.minutesPerDay),
                  !limit.selection.applicationTokens.isEmpty
                    || !limit.selection.categoryTokens.isEmpty
                    || !limit.selection.webDomainTokens.isEmpty else { return false }
        }
        var setup = LatchState()
        setup.delayPolicy = policy
        setup.overrides = overrides
        if let firstLimit { setup.limits = [firstLimit] }
        guard DayNightGroup.isValidCollection(dayNightGroups, limits: setup.limits) else { return false }
        setup.dayNightGroups = dayNightGroups
        setup.dayNightSetupDone = true
        setup.isSetUp = true
        let running = Set(DeviceActivityCenter().activities.map(\.rawValue))
        guard MonitorRegistration.admit(state: setup, running: running) else { return false }
        SharedStore.simulating = false
        guard SharedStore.save(setup), SharedStore.loadState().isSetUp else { return false }
        state = SharedStore.loadState()
        SharedStore.defaults.set(true, forKey: SharedStore.redesignWelcomeKey)
        SharedStore.defaults.set(true, forKey: SharedStore.redesignMigrationKey)
        SharedStore.defaults.set(true, forKey: "latch.languageExpansionUpdate.shown")
        selectedTab = 0
        await ChangeEngine.ensureMonitoringOffMain()
        return true
    }

    func retrySetupStorage() {
        if SharedStore.isReplaying { restoreFromReplay() }
        guard !SharedStore.isReplaying else { return }
        migrateScreenTimeCodeToKeychain()
        guard SharedStore.prepareRedesignMigration(), !SharedStore.stateRecoveryNeeded else { return }
        state = SharedStore.loadState()
        setupStorageUnavailable = false
        tick()
        if state.isSetUp { Task { await verifyAuthorization() } }
    }

    // MARK: - Limit usage

    /// Whether a limit has spent its budget and is blocked until midnight.
    func isLimitBlocked(_ id: UUID) -> Bool {
        SharedStore.loadBlockedLimitIDs().contains(id)
    }

    // MARK: - Password override (instant change)

    func passwordMatches(_ input: String) -> Bool {
        guard let h = state.overrides.passwordHash, !input.isEmpty else { return false }
        return AppModel.hash(input) == h
    }

    /// Change the override passcode immediately, no delay. Only call after the
    /// current passcode has been verified — changing it requires knowing it.
    func setPasswordInstant(hash: String) {
        var s = SharedStore.loadState()
        s.overrides.passwordEnabled = true
        s.overrides.passwordHash = hash
        SharedStore.save(s)
        state = s
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Preserves the old "know the current password → change it now" path.
    /// Only the secret changes; permission edits still require a queued delay.
    func updatePasswordPolicySecretNow(id: UUID, current: String,
                                       newPassword: String) -> Bool {
        guard !current.isEmpty, !newPassword.isEmpty else { return false }
        var s = SharedStore.loadState()
        guard let index = s.overrides.passwordPolicies.firstIndex(where: { $0.id == id }),
              s.overrides.passwordPolicies[index].hash == AppModel.hash(current),
              !s.pending.contains(where: {
                  ChangeEngine.conflictKey($0.action)
                      == "passwordPolicy-\(id.uuidString)"
              }) else { return false }
        s.overrides.passwordPolicies[index].hash = AppModel.hash(newPassword)
        SharedStore.save(s)
        state = s
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return true
    }

    // MARK: - Password hashing

    nonisolated static func hash(_ password: String) -> String {
        SHA256.hash(data: Data(password.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
