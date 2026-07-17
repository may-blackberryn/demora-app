//
//  AppModel.swift
//  Observable wrapper around the shared store + change engine.
//

import Foundation
import SwiftUI
import Combine
import CryptoKit
import FamilyControls
import UserNotifications
import UIKit

/// Steps of the guided first-run tutorial. While non-nil the app shows the
/// real tabs but in a coached, constrained mode.
enum TutorialStep: Int {
    case addLimit         // Limits: add your first limit
    case addSchedule      // Schedules: add a recurring schedule
    case applyBoth        // Home: select both pending and apply via password
    case exploreCalendar  // Schedules: see now & next, open the calendar
    case removeSchedule   // Schedules: remove the recurring schedule
    case removeLimit      // Limits: remove the limit (auto-switched here)
    case addContact       // Settings: add a sample trusted contact
    case applyViaContact  // Home: apply the removals via the trusted contact
    case configure        // final: pick real overrides + delays
}

@MainActor
final class AppModel: ObservableObject {
    @Published var state = SharedStore.loadState()
    @Published var authorized = false

    /// Non-nil while the first-run tutorial is running.
    @Published var tutorial: TutorialStep?
    var inTutorial: Bool { tutorial != nil }

    /// True while replaying the walkthrough from Help (vs the first-run tour).
    /// In a replay the real setup is restored at the end instead of writing a
    /// fresh one, so nothing is lost.
    @Published var isReplay = false

    /// Set when a replay was blocked because the real setup couldn't be backed
    /// up. Drives a warning alert in the Help screen; nothing was changed.
    @Published var replayFailed = false

    /// During the calendar step: focus "now & next" first, then the calendar.
    @Published var calendarFocusNowNext = false

    /// The screen currently on top, so only its highlight feeds the blocker
    /// (a screen pushed away no longer counts). Set by advanceTutorial for the
    /// step's root screen, and by each pushed screen's onAppear.
    @Published var tutorialScreen = ""
    @Published var language: AppLanguage = AppLanguage.current {
        didSet { AppLanguage.current = language }
    }
    /// Set when a queue attempt is rejected (duplicate); shown as an alert.
    @Published var queueNotice: String?

    /// Set when a trusted contact revokes their permission; shown as an alert.
    @Published var contactNotice: String?

    /// Count of pending "be my trusted contact" invites awaiting your answer;
    /// drives the red badge on the Settings tab.
    @Published var incomingInviteCount = 0

    /// True while Home's multi-select "Apply" bar is on screen. The tutorial
    /// callout lifts above it when set, and otherwise sits at the bottom so it
    /// doesn't cover the pending changes.
    @Published var applyBarVisible = false

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

    /// Selected bottom tab (0 Home, 1 Limits, 2 Schedules, 3 Settings).
    /// Published so views can navigate between tabs (e.g. Home → Settings).
    @Published var selectedTab = 0

    /// Navigation path for the Settings tab. Held here (not @State in the view)
    /// so it survives the language re-render — the TabView is rebuilt on a
    /// language change, which would otherwise pop you back to the root and
    /// kick you out of e.g. Appearance. Home's "change" link also sets it.
    @Published var settingsPath: [SettingsRoute] = []

    private var timer: AnyCancellable?

    init() {
        // A replay interrupted by a force-quit: restore the user's real setup
        // from the backup so nothing is lost (and so we don't fall into the
        // not-set-up onboarding branch below).
        if SharedStore.isReplaying {
            restoreFromReplay()
        }
        // A force-quit mid-tutorial leaves the app not-yet-set-up with leftover
        // dummy data; wipe it so onboarding restarts clean.
        if !SharedStore.loadState().isSetUp {
            resetForOnboarding()
        }
        isReplay = SharedStore.isReplaying
        migrateScreenTimeCodeToKeychain()
        // Fast path so an approved install doesn't flash the banner.
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
        // authorizationStatus is unreliable — it can read .notDetermined even
        // when access is granted, which showed the re-auth banner on every
        // launch. requestAuthorization is authoritative: it returns SILENTLY
        // when already approved, so confirm with it for a set-up install. It
        // won't prompt unless access is genuinely missing, and never runs during
        // onboarding/the tutorial (which handle authorization themselves).
        if SharedStore.loadState().isSetUp && tutorial == nil {
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
        ChangeEngine.housekeeping()
        state = SharedStore.loadState()
        enforcementDegraded = SharedStore.enforcementDegraded
        checkContactApprovals()
        checkContactInvites()
        sendPendingEmailInvites()
        refreshIncomingInviteCount()
        Task { await TimeGuard.syncWithNetwork() }
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
    /// Settings tab can show a badge when someone is waiting on your answer.
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
                let since = ContactsRelay.relaySentDate(req.requestId) ?? .distantPast
                let decisions = try? await ContactsRelay.decisions(
                    requestId: req.requestId, since: since)
                if decisions?.approved == true {
                    ContactsRelay.clearSent(req.requestId)
                    ContactsRelay.clearOutgoing(req.requestId)
                    await ContactsRelay.cleanup(requestId: req.requestId)
                    await MainActor.run {
                        guard let self else { return }
                        for change in self.state.pending
                        where req.changeIds.contains(change.id) {
                            self.applyNow(change)
                        }
                    }
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
        guard !s.screenTimeCode.isEmpty else { return }
        if Keychain.getString(for: Self.screenTimeCodeKey) == nil {
            Keychain.setString(s.screenTimeCode, for: Self.screenTimeCodeKey)
        }
        var t = s
        t.screenTimeCode = ""
        SharedStore.save(t)
        state = t
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared
                .requestAuthorization(for: .individual)
            authorized = true
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
            authorized = true
        }
    }

    // MARK: - Changes

    @discardableResult
    func queue(_ action: ChangeAction) -> PendingChange? {
        let change = ChangeEngine.queue(action)
        state = SharedStore.loadState()
        let haptic = UINotificationFeedbackGenerator()
        if let change {
            haptic.notificationOccurred(.success)
            // Tutorial: each queued change is frozen (can't be waited out) and
            // moves the tour along.
            if let step = tutorial {
                switch step {
                case .addLimit:
                    if case .addLimit = action {
                        freezePending(change.id); advanceTutorial(to: .addSchedule)
                    }
                case .addSchedule:
                    // A recurring block or a recurring free period both count.
                    if case .addSchedule = action {
                        freezePending(change.id); advanceTutorial(to: .applyBoth)
                    } else if case .addExemption = action {
                        freezePending(change.id); advanceTutorial(to: .applyBoth)
                    }
                case .removeSchedule:
                    // The thing they added may be a block schedule or a free
                    // period (exemption) — removing either advances the tour.
                    if case .removeSchedule = action {
                        freezePending(change.id); advanceTutorial(to: .removeLimit)
                    } else if case .removeExemption = action {
                        freezePending(change.id); advanceTutorial(to: .removeLimit)
                    }
                case .removeLimit:
                    if case .removeLimit = action {
                        freezePending(change.id); advanceTutorial(to: .addContact)
                    }
                default:
                    break
                }
            }
        } else {
            haptic.notificationOccurred(.error)
            queueNotice = tr("A change for this setting is already pending. Cancel it on the Home tab first if you want something different.")
        }
        return change
    }

    func cancel(_ change: PendingChange) {
        ChangeEngine.cancel(change)
        ContactsRelay.clearSent(change.id.uuidString)
        state = SharedStore.loadState()
    }

    func applyNow(_ change: PendingChange) {
        ChangeEngine.applyNow(change)
        state = SharedStore.loadState()
        // Tutorial: once all the staged changes are applied, move on.
        if tutorial == .applyBoth, state.pending.isEmpty {
            advanceTutorial(to: .exploreCalendar)
        } else if tutorial == .applyViaContact, state.pending.isEmpty {
            advanceTutorial(to: .configure)
        }
    }

    // MARK: - Guided tutorial

    /// Start the first-run tutorial from a clean slate, with dummy delays
    /// (5 min strict / 15 min lenient) and overrides where only the password
    /// works (the password is "test"). Nothing is marked set-up yet.
    func beginTutorial() {
        var s = SharedStore.loadState()
        s.limits = []; s.schedules = []; s.exemptions = []
        s.planned = []; s.sessions = []; s.pending = []
        s.strictDelay = 5 * 60
        s.lenientDelay = 15 * 60
        var o = OverridesConfig()
        o.mathEnabled = true; o.mathDifficulty = .elementary
        o.passwordEnabled = true; o.passwordHash = AppModel.hash("test")
        o.contactsEnabled = false
        s.overrides = o
        s.isSetUp = false
        SharedStore.simulating = true     // no real blocks during the tour
        SharedStore.save(s)
        state = s
        ShieldController.refresh()         // clears any shields under simulation
        tutorial = .addLimit
        selectedTab = 1   // Limits
        tutorialScreen = "limits"
    }

    /// Jump to the Settings tab and open a specific section (Delays, Overrides,
    /// …), always landing on that section's *main* page. Reassigning the path to
    /// a different value rebuilds the stack and drops any closure-based
    /// sub-pushes (e.g. a Contacts page inside Overrides). If we happen to already
    /// be at this exact route, clear it first so we still pop back to the root
    /// instead of leaving a deeper page on screen.
    func openSettings(to route: SettingsRoute) {
        selectedTab = 3
        if settingsPath == [route] {
            settingsPath = []
            DispatchQueue.main.async { self.settingsPath = [route] }
        } else {
            settingsPath = [route]
        }
    }

    private func advanceTutorial(to step: TutorialStep) {
        tutorial = step
        switch step {
        case .addLimit:        selectedTab = 1; tutorialScreen = "limits"
        case .addSchedule:     selectedTab = 2; tutorialScreen = "schedulesRoot"
        case .applyBoth:       selectedTab = 0; tutorialScreen = "home"
        case .exploreCalendar:
            selectedTab = 2; tutorialScreen = "schedulesRoot"
            calendarFocusNowNext = false          // skip now & next; go to calendar
        case .removeSchedule:  selectedTab = 2; tutorialScreen = "schedulesRoot"
        case .removeLimit:     selectedTab = 1; tutorialScreen = "limits"
        case .addContact:      selectedTab = 3; tutorialScreen = "settings"
        case .applyViaContact: selectedTab = 0; tutorialScreen = "home"
        case .configure:       break
        }
    }

    /// Called when the calendar opens during the tour.
    func tutorialDidOpenCalendar() {
        if tutorial == .exploreCalendar { advanceTutorial(to: .removeSchedule) }
    }

    /// Adds a usable sample Demora contact instantly (no relay) during the tour,
    /// then moves to applying the removals via that contact.
    func addTutorialContact(_ contact: TrustedContact) {
        guard tutorial == .addContact else { return }
        var s = SharedStore.loadState()
        s.overrides.contactsEnabled = true
        var c = contact
        c.accepted = true                 // usable immediately during the tour
        if s.overrides.contacts.isEmpty { s.overrides.contacts.append(c) }
        SharedStore.save(s)
        state = s
        advanceTutorial(to: .applyViaContact)
    }

    /// When the current tutorial change was frozen — anchors the countdown.
    private var tutorialFreezeStart: Date?

    /// Push a pending change's real apply time far into the future so it never
    /// auto-applies (it can't be waited out); the displayed countdown is driven
    /// separately by `tutorialRemaining` so it still ticks down a little.
    private func freezePending(_ id: UUID) {
        var s = SharedStore.loadState()
        if let i = s.pending.firstIndex(where: { $0.id == id }) {
            s.pending[i].appliesAt = .distantFuture
            SharedStore.save(s)
            state = s
            tutorialFreezeStart = Date()
        }
    }

    /// Seconds to show for a frozen tutorial change: starts at the full delay
    /// (5 or 15 min), counts down for one minute, then holds at the floor
    /// (4 or 14 min) so it visibly can't be waited out. nil when not applicable.
    func tutorialRemaining(for change: PendingChange) -> TimeInterval? {
        guard inTutorial, let start = tutorialFreezeStart else { return nil }
        let total: TimeInterval = change.direction == .stricter ? 5 * 60 : 15 * 60
        let floor = total - 60
        return max(floor, total - Date().timeIntervalSince(start))
    }

    /// Finish the tour: write the user's real delays + overrides, clear the
    /// dummy state, and enter the app for real.
    /// Replay the walkthrough non-destructively: stash the user's real state,
    /// then run the tour over sample data. `finishReplay()` restores it.
    func replayTutorial() {
        // Refuse to start unless the real setup is provably backed up. If the
        // backup can't be written, a replay could lose the user's limits or lift
        // their blocks with no way to restore — so we bail and warn instead.
        guard SharedStore.saveBackup(SharedStore.loadState()) else {
            replayFailed = true
            return
        }
        SharedStore.isReplaying = true
        isReplay = true
        // Replay is launched from inside Settings → Help; pop that stack back to
        // root so the user doesn't land mid-Settings when the tour ends.
        settingsPath = []
        beginTutorial()
    }

    /// End a replay: put the user's real limits, schedules, delays, overrides,
    /// and protections back exactly as they were.
    func finishReplay() { restoreFromReplay() }

    /// Let the user bail out of the walkthrough at any point. A replay restores
    /// the real setup; a first run jumps straight to the final setup screen so
    /// they're never trapped behind the tutorial's locked tab bar.
    func skipTutorial() {
        if SharedStore.isReplaying { finishReplay(); return }
        tutorial = .configure
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
        tutorial = nil
        isReplay = false
        selectedTab = 0
        settingsPath = []
        ChangeEngine.reconfigureDailyMonitoring(state: s)
        ChangeEngine.reconfigureWindowMonitoring(state: s)
        ShieldController.refresh()
    }
    #endif

    private func restoreFromReplay() {
        tutorial = nil
        SharedStore.simulating = false
        if let backup = SharedStore.loadBackup() {
            SharedStore.save(backup)
            state = backup
        }
        SharedStore.clearBackup()
        SharedStore.isReplaying = false
        isReplay = false
        SharedStore.saveBlockedLimitIDs([])
        ChangeEngine.reconfigureDailyMonitoring(state: state)
        ChangeEngine.reconfigureWindowMonitoring(state: state)
        ShieldController.refresh()
        selectedTab = 0
    }

    func finishTutorial(strictDelay: TimeInterval,
                        lenientDelay: TimeInterval,
                        overrides: OverridesConfig,
                        blockAppRemoval: Bool = false,
                        blockAdultWebsites: Bool = false) {
        // A replay ends by restoring the real setup, not writing a new one.
        if SharedStore.isReplaying { restoreFromReplay(); return }
        tutorial = nil
        SharedStore.simulating = false    // back to real blocking
        var s = SharedStore.loadState()
        s.pending = []
        s.limits = []
        s.schedules = []
        s.exemptions = []
        s.sessions = []
        s.strictDelay = strictDelay
        s.lenientDelay = lenientDelay
        s.overrides = overrides
        s.blockAppRemoval = blockAppRemoval
        s.blockAdultWebsites = blockAdultWebsites
        s.isSetUp = true
        SharedStore.save(s)
        SharedStore.saveBlockedLimitIDs([])
        state = s
        ChangeEngine.reconfigureDailyMonitoring(state: s)
        ChangeEngine.reconfigureWindowMonitoring(state: s)
        ShieldController.refresh()
        selectedTab = 0
    }

    /// Wipe any leftover tutorial state so a force-quit mid-tutorial starts the
    /// walkthrough fresh (the app only marks itself set up at the very end).
    func resetForOnboarding() {
        SharedStore.simulating = false
        let s = LatchState()
        SharedStore.save(s)
        SharedStore.saveBlockedLimitIDs([])
        state = s
        ChangeEngine.reconfigureDailyMonitoring(state: s)
        ChangeEngine.reconfigureWindowMonitoring(state: s)
        ShieldController.refresh()
    }

    /// Direction an action *would* have — used to show "this will take X" hints.
    func preview(_ action: ChangeAction) -> (ChangeDirection, TimeInterval) {
        let dir = ChangeEngine.classify(action, state: state)
        return (dir, dir == .stricter ? state.strictDelay : state.lenientDelay)
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

    // MARK: - Password hashing

    nonisolated static func hash(_ password: String) -> String {
        SHA256.hash(data: Data(password.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
