//
//  YouPresentation.swift
//  Pure decisions for You, "Ways to skip a wait" and the Skip the wait sheet
//  (docs/you-redesign.md §5.3, §5.9, §5.13, §7). Foundation and the shared
//  models only, so Tests/YouPresentationHarness.py compiles this file as it
//  is. Presentation only: nothing here reads or writes saved state, checks a
//  secret or decides whether a change may apply. The engine still re-checks
//  every permission when a way is used, and the views translate every word.
//

import Foundation

// MARK: - The one list (§5.3)

enum SkipWayKind: Hashable {
    case contact, password, phrase
}

/// The single state chip a row may carry, in priority order (§5.3).
enum SkipWayChip: Equatable {
    /// A removal is queued: "Removed Tue 14:32". Stricter, so never `loosen`.
    case removed(Date)
    /// A permission or secret change is queued: "Changes in 3h".
    case changes(Date)
    /// Still waiting to be added: "Added Tue 14:32".
    case added(Date)
    /// A contact who hasn't accepted (or confirmed by email) yet.
    case waitingToAccept
    /// A Demora contact the relay can't find right now.
    case cantReach
    /// Contacts can't approve while the master switch is off.
    case paused
}

/// A phrase's second fact on line 1: "100 words" or "custom".
enum SkipWayPhraseDetail: Equatable {
    case words(Int)
    case custom
}

struct SkipWayRow: Equatable, Identifiable {
    let id: UUID
    let kind: SkipWayKind
    /// The stored name. Contacts' display names are resolved by the view.
    let name: String
    let allowed: Set<OverrideCapability>
    let phrase: SkipWayPhraseDetail?
    let chip: SkipWayChip?
    /// The waiting change behind a removed/changes/added chip.
    let pendingChangeID: UUID?
    /// Not saved yet: drawn dimmed and opens the ledger, not a detail page.
    let isPendingAddition: Bool
}

struct SkipWayList: Equatable {
    /// The "Contacts can approve" row under the contacts.
    struct ContactsSwitch: Equatable {
        let enabled: Bool
        /// A queued turn on/off, shown on the row; the ledger owns Cancel.
        let pendingChangeID: UUID?
        let pendingAppliesAt: Date?
    }

    let rows: [SkipWayRow]
    /// Nil when the list has no contact rows (§5.3: only with ≥ 1 contact).
    let contactsSwitch: ContactsSwitch?

    var isEmpty: Bool { rows.isEmpty }
    /// Above 12 rows each kind gets a collapsible header (§6 stress test).
    var collapsesKinds: Bool { rows.count > 12 }

    func isExpanded(_ kind: SkipWayKind, collapsed: Set<SkipWayKind>) -> Bool {
        !collapsesKinds || !collapsed.contains(kind)
    }

    func rows(of kind: SkipWayKind) -> [SkipWayRow] { rows.filter { $0.kind == kind } }

    /// Contacts, then passwords, then phrases; within a kind the stored order,
    /// then additions still waiting in the order they were queued.
    static func make(overrides: OverridesConfig, pending: [PendingChange],
                     unavailableCodes: Set<String>) -> SkipWayList {
        var rows: [SkipWayRow] = []

        // Contacts
        let contactIDs = Set(overrides.contacts.map(\.id))
        for contact in overrides.contacts {
            let mine = pending.filter { targets($0.action, contact: contact.id) }
            let (chip, changeID) = savedChip(
                mine, isRemoval: { if case .removeContact = $0 { return true }; return false },
                fallback: {
                    if !contact.accepted { return .waitingToAccept }
                    if let code = contact.latchUserCode, unavailableCodes.contains(code) {
                        return .cantReach
                    }
                    if !overrides.contactsEnabled { return .paused }
                    return nil
                })
            rows.append(SkipWayRow(id: contact.id, kind: .contact, name: contact.name,
                                   allowed: contact.allowed, phrase: nil, chip: chip,
                                   pendingChangeID: changeID, isPendingAddition: false))
        }
        for change in pending {
            guard case .addContact(let contact) = change.action,
                  !contactIDs.contains(contact.id) else { continue }
            rows.append(addition(change, id: contact.id, kind: .contact, name: contact.name,
                                 allowed: contact.allowed, phrase: nil))
        }

        // Passwords
        let passwordIDs = Set(overrides.passwordPolicies.map(\.id))
        for policy in overrides.passwordPolicies {
            let mine = pending.filter { targets($0.action, password: policy.id) }
            let (chip, changeID) = savedChip(
                mine, isRemoval: { if case .removePasswordPolicy = $0 { return true }; return false },
                fallback: { nil })
            rows.append(SkipWayRow(id: policy.id, kind: .password, name: policy.name,
                                   allowed: policy.allowed, phrase: nil, chip: chip,
                                   pendingChangeID: changeID, isPendingAddition: false))
        }
        for change in pending {
            guard case .upsertPasswordPolicy(let policy) = change.action,
                  !passwordIDs.contains(policy.id) else { continue }
            rows.append(addition(change, id: policy.id, kind: .password, name: policy.name,
                                 allowed: policy.allowed, phrase: nil))
        }

        // Phrases
        let phraseIDs = Set(overrides.phrasePolicies.map(\.id))
        for policy in overrides.phrasePolicies {
            let mine = pending.filter { targets($0.action, phrase: policy.id) }
            let (chip, changeID) = savedChip(
                mine, isRemoval: { if case .removePhrasePolicy = $0 { return true }; return false },
                fallback: { nil })
            rows.append(SkipWayRow(id: policy.id, kind: .phrase, name: policy.name,
                                   allowed: policy.allowed, phrase: detail(policy.kind),
                                   chip: chip, pendingChangeID: changeID,
                                   isPendingAddition: false))
        }
        for change in pending {
            guard case .upsertPhrasePolicy(let policy) = change.action,
                  !phraseIDs.contains(policy.id) else { continue }
            rows.append(addition(change, id: policy.id, kind: .phrase, name: policy.name,
                                 allowed: policy.allowed, phrase: detail(policy.kind)))
        }

        var contactsSwitch: ContactsSwitch?
        if rows.contains(where: { $0.kind == .contact }) {
            let toggle = pending.first {
                if case .setContactsOverride = $0.action { return true }
                return false
            }
            contactsSwitch = ContactsSwitch(enabled: overrides.contactsEnabled,
                                            pendingChangeID: toggle?.id,
                                            pendingAppliesAt: toggle?.appliesAt)
        }
        return SkipWayList(rows: rows, contactsSwitch: contactsSwitch)
    }

    /// The queued edit (not removal) of one saved item, and the permissions
    /// it would set — for the detail page's "From Tue 14:32: …" strip. The
    /// checklist itself always shows the current permissions.
    static func queuedEdit(of id: UUID, kind: SkipWayKind,
                           pending: [PendingChange]) -> (change: PendingChange,
                                                         allowed: Set<OverrideCapability>)? {
        for change in pending {
            switch (kind, change.action) {
            case (.contact, .setContactPermissions(let target, let allowed)) where target == id:
                return (change, allowed)
            case (.password, .upsertPasswordPolicy(let policy)) where policy.id == id:
                return (change, policy.allowed)
            case (.phrase, .upsertPhrasePolicy(let policy)) where policy.id == id:
                return (change, policy.allowed)
            default:
                continue
            }
        }
        return nil
    }

    /// Any queued change to one saved item (edit or removal). While one waits,
    /// the engine refuses another, so the detail page disables its actions.
    static func pendingChange(for id: UUID, kind: SkipWayKind,
                              pending: [PendingChange]) -> PendingChange? {
        pending.first { change in
            switch kind {
            case .contact: return targets(change.action, contact: id)
            case .password: return targets(change.action, password: id)
            case .phrase: return targets(change.action, phrase: id)
            }
        }
    }

    // MARK: Helpers

    private static func savedChip(_ mine: [PendingChange],
                                  isRemoval: (ChangeAction) -> Bool,
                                  fallback: () -> SkipWayChip?) -> (SkipWayChip?, UUID?) {
        if let removal = mine.first(where: { isRemoval($0.action) }) {
            return (.removed(removal.appliesAt), removal.id)
        }
        if let edit = mine.first {
            return (.changes(edit.appliesAt), edit.id)
        }
        return (fallback(), nil)
    }

    private static func addition(_ change: PendingChange, id: UUID, kind: SkipWayKind,
                                 name: String, allowed: Set<OverrideCapability>,
                                 phrase: SkipWayPhraseDetail?) -> SkipWayRow {
        SkipWayRow(id: id, kind: kind, name: name, allowed: allowed, phrase: phrase,
                   chip: .added(change.appliesAt), pendingChangeID: change.id,
                   isPendingAddition: true)
    }

    private static func detail(_ kind: PhraseKind) -> SkipWayPhraseDetail {
        switch kind {
        case .random(let count): return .words(count)
        case .custom: return .custom
        }
    }

    private static func targets(_ action: ChangeAction, contact id: UUID) -> Bool {
        switch action {
        case .setContactPermissions(let target, _), .removeContact(let target):
            return target == id
        default: return false
        }
    }

    private static func targets(_ action: ChangeAction, password id: UUID) -> Bool {
        switch action {
        case .upsertPasswordPolicy(let policy): return policy.id == id
        case .removePasswordPolicy(let target): return target == id
        default: return false
        }
    }

    private static func targets(_ action: ChangeAction, phrase id: UUID) -> Bool {
        switch action {
        case .upsertPhrasePolicy(let policy): return policy.id == id
        case .removePhrasePolicy(let target): return target == id
        default: return false
        }
    }
}

// MARK: - What it may skip (§5.3 line 2, §5.10.2)

enum SkipWayPermissionText {
    /// The checklist and summary order; extra time is its own group.
    static let changeAreas: [OverrideCapability] = [
        .limitChanges, .scheduleChanges, .sessionChanges,
        .delayChanges, .protectionChanges, .contactChanges,
    ]

    /// Checklist label and the first item of a summary.
    static func title(_ area: OverrideCapability) -> String {
        switch area {
        case .limitChanges: return "Limits"
        case .scheduleChanges: return "Schedules"
        case .sessionChanges: return "Sessions"
        case .delayChanges: return "Your waits"
        case .protectionChanges: return "Protection"
        case .contactChanges: return "Trusted contacts"
        case .extraTime: return "Extra time"
        }
    }

    /// The same area later in a sentence ("Limits, schedules · extra time").
    /// A separate key, so languages that capitalise nouns can keep doing so.
    static func listForm(_ area: OverrideCapability) -> String {
        switch area {
        case .limitChanges: return "limits"
        case .scheduleChanges: return "schedules"
        case .sessionChanges: return "sessions"
        case .delayChanges: return "your waits"
        case .protectionChanges: return "protection"
        case .contactChanges: return "trusted contacts"
        case .extraTime: return "extra time"
        }
    }

    /// "Everything", "Everything except extra time", "Only extra time",
    /// "Nothing", or the areas in checklist order with extra time after a dot.
    static func summary(_ allowed: Set<OverrideCapability>,
                        translate: (String) -> String) -> String {
        let areas = changeAreas.filter { allowed.contains($0) }
        let extra = allowed.contains(.extraTime)
        if areas.isEmpty { return translate(extra ? "Only extra time" : "Nothing") }
        if areas.count == changeAreas.count {
            return translate(extra ? "Everything" : "Everything except extra time")
        }
        var parts = [translate(title(areas[0]))]
        parts += areas.dropFirst().map { translate(listForm($0)) }
        let list = parts.joined(separator: ", ")
        return extra ? list + " · " + translate(listForm(.extraTime)) : list
    }
}

// MARK: - Who or what can skip this (§5.13, Y4)

enum SkipWay: Equatable, Identifiable {
    case contact(TrustedContact)
    case password(PasswordPolicy)
    case phrase(PhrasePolicy)

    var id: UUID {
        switch self {
        case .contact(let contact): return contact.id
        case .password(let policy): return policy.id
        case .phrase(let policy): return policy.id
        }
    }

    var kind: SkipWayKind {
        switch self {
        case .contact: return .contact
        case .password: return .password
        case .phrase: return .phrase
        }
    }
}

struct EligibleWay: Equatable, Identifiable {
    /// Listed, but can't be used right now (drawn disabled with the reason).
    enum Unavailable: Equatable {
        case cantReach
        case emailNotAvailable
    }

    let way: SkipWay
    let unavailable: Unavailable?
    var id: UUID { way.id }
}

enum SkipWayEligibility {
    /// The ways allowed to skip every one of `changes`: contacts that are
    /// accepted, not paused and allowed each change's capability; passwords
    /// and phrases allowed each change's capability. Non-empty exactly when
    /// `ChangeEngine.hasOverride` is true. Changes with no capability (edits
    /// to the ways themselves) are never eligible. Contacts that can't be
    /// reached, or email contacts in a build without email, stay listed but
    /// unavailable, so the sheet can say why.
    static func ways(for changes: [PendingChange], overrides: OverridesConfig,
                     unavailableCodes: Set<String>, emailAvailable: Bool) -> [EligibleWay] {
        guard !changes.isEmpty else { return [] }
        let areas = changes.map { ChangeEngine.overrideCapability(for: $0.action) }
        guard !areas.contains(where: { $0 == nil }) else { return [] }
        let needed = Set(areas.compactMap { $0 })
        return ways(needing: needed, overrides: overrides,
                    unavailableCodes: unavailableCodes, emailAvailable: emailAvailable)
    }

    /// Contacts who may approve extra time. The step itself names whether a
    /// contact, a password or a phrase is needed (ExtraTimeRoute), so only
    /// the contact step lists choices.
    static func extraTimeContacts(overrides: OverridesConfig, unavailableCodes: Set<String>,
                                  emailAvailable: Bool) -> [EligibleWay] {
        ways(needing: [.extraTime], overrides: overrides, unavailableCodes: unavailableCodes,
             emailAvailable: emailAvailable).filter { $0.way.kind == .contact }
    }

    /// Navigation keeps its opening plan, but sending must use the current
    /// contact identity, consent and permissions, never the captured copy.
    static func currentRequestContacts(for changes: [PendingChange], extraTime: Bool,
                                       offeredIDs: Set<UUID>, overrides: OverridesConfig,
                                       unavailableCodes: Set<String>, emailAvailable: Bool) -> [EligibleWay] {
        let current = extraTime
            ? extraTimeContacts(overrides: overrides, unavailableCodes: unavailableCodes,
                                emailAvailable: emailAvailable)
            : ways(for: changes, overrides: overrides, unavailableCodes: unavailableCodes,
                   emailAvailable: emailAvailable)
        return current.filter { $0.way.kind == .contact && offeredIDs.contains($0.id) }
    }

    private static func ways(needing needed: Set<OverrideCapability>, overrides: OverridesConfig,
                             unavailableCodes: Set<String>, emailAvailable: Bool) -> [EligibleWay] {
        var result: [EligibleWay] = []
        if overrides.contactsEnabled {
            for contact in overrides.contacts
            where contact.isUsable && needed.isSubset(of: contact.allowed) {
                var unavailable: EligibleWay.Unavailable?
                if contact.isEmail && !emailAvailable {
                    unavailable = .emailNotAvailable
                } else if let code = contact.latchUserCode, unavailableCodes.contains(code) {
                    unavailable = .cantReach
                }
                result.append(EligibleWay(way: .contact(contact), unavailable: unavailable))
            }
        }
        for policy in overrides.passwordPolicies where needed.isSubset(of: policy.allowed) {
            result.append(EligibleWay(way: .password(policy), unavailable: nil))
        }
        for policy in overrides.phrasePolicies where needed.isSubset(of: policy.allowed) {
            result.append(EligibleWay(way: .phrase(policy), unavailable: nil))
        }
        return result
    }
}

/// Where the Skip the wait sheet opens (§5.13).
enum SkipWayStart: Equatable {
    /// A contact request was already sent: open on its status.
    case contactRequest(selected: Set<UUID>)
    /// A password or phrase, opened directly.
    case way(SkipWay)
    /// More than one way, or a way that can't be used right now: the list.
    case menu
    /// "None of your ways can skip this change."
    case none

    /// One usable way opens directly. Reopening a sent request (the
    /// ledger's "Waiting for…") opens on its status; Apply now always offers
    /// every eligible way, so a password or phrase stays usable while a
    /// contact request waits (review fix).
    static func initial(_ ways: [EligibleWay], reopensRequest: Bool) -> SkipWayStart {
        if reopensRequest {
            return .contactRequest(selected: Set(ways.filter {
                $0.way.kind == .contact && $0.unavailable == nil
            }.map(\.id)))
        }
        guard !ways.isEmpty else { return .none }
        if ways.count == 1, let only = ways.first, only.unavailable == nil {
            return start(for: only.way)
        }
        return .menu
    }

    /// The step a tapped way opens. A contact opens the request with that
    /// contact checked; the other eligible contacts can be added there.
    static func start(for way: SkipWay) -> SkipWayStart {
        if case .contact(let contact) = way { return .contactRequest(selected: [contact.id]) }
        return .way(way)
    }
}

// MARK: - Adding a way (§5.9, Y3)

enum SkipWayDraft: Equatable {
    case contact(TrustedContact)
    case password(PasswordPolicy)
    case phrase(PhrasePolicy)
}

enum SkipWayAddPlan {
    /// What one receipt queues. A contact added while contacts are paused
    /// also turns approvals on — unless a switch change is already waiting.
    /// Passwords and phrases never touch the switch, and nothing here ever
    /// turns it off.
    static func actions(adding draft: SkipWayDraft, overrides: OverridesConfig,
                        pending: [PendingChange]) -> [ChangeAction] {
        switch draft {
        case .contact(let contact):
            let switchWaiting = pending.contains {
                if case .setContactsOverride = $0.action { return true }
                return false
            }
            return overrides.contactsEnabled || switchWaiting
                ? [.addContact(contact)]
                : [.addContact(contact), .setContactsOverride(enabled: true)]
        case .password(let policy):
            return [.upsertPasswordPolicy(policy)]
        case .phrase(let policy):
            return [.upsertPhrasePolicy(policy)]
        }
    }

    /// The same checks as the old forms: a name, at least one capability for
    /// passwords and phrases, matching passwords, a valid phrase.
    static func passwordIsValid(name: String, password: String, confirm: String,
                                allowed: Set<OverrideCapability>) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty && password == confirm && !allowed.isEmpty
    }

    /// Change the password now: the current one, and a new one typed twice.
    static func secretChangeIsValid(current: String, new: String, confirm: String) -> Bool {
        !current.isEmpty && !new.isEmpty && new == confirm
    }
}

// MARK: - Editing what it may skip (§5.10.2)

enum SkipWayEdit {
    /// Save appears only when the checklist differs, nothing for this item is
    /// waiting, and the result is something the engine accepts.
    static func canSave(kind: SkipWayKind, current: Set<OverrideCapability>,
                        draft: Set<OverrideCapability>, hasPending: Bool) -> Bool {
        guard draft != current, !hasPending else { return false }
        return kind == .contact || !draft.isEmpty
    }
}

// MARK: - One receipt for several actions (§7 extension b)

enum ReceiptBatch {
    /// Looser when any part is looser; it takes effect when the slowest part
    /// does. Same rules as a single receipt (ReceiptPlan).
    static func plan(_ parts: [(looser: Bool, delay: TimeInterval)], now: Date) -> ReceiptPlan {
        ReceiptPlan.make(looser: parts.contains { $0.looser },
                         delay: parts.map(\.delay).max() ?? 0, now: now)
    }
}

// MARK: - Invites (Y7)

enum YouInvites {
    /// The tab that answers invites carries the dot: You (tag 3).
    static let youTab = 3

    static func showsDot(onTab tab: Int, inviteCount: Int) -> Bool {
        tab == youTab && inviteCount > 0
    }
}
