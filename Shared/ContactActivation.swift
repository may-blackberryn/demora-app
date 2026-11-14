//
//  ContactActivation.swift
//  F2 (docs/fixes-2.0-batch.md): pair a trusted contact now, let their
//  approvals count only after the wait. Pure state transforms on LatchState;
//  ChangeEngine runs each one inside a single coordinated state write and
//  does the DeviceActivity/notification cleanup afterwards. Foundation and
//  the shared models only, so Tests/ContactActivationHarness.py compiles this
//  file as it is.
//
//  Clock domain: none. Nothing here reads a clock or changes a deadline:
//  `id`, `createdAt` and `appliesAt` of every pending change are preserved.
//

import Foundation

enum ContactActivation {
    /// The pending `.addContact` for one contact id, if any.
    static func pendingAdd(for id: UUID, in pending: [PendingChange]) -> PendingChange? {
        pending.first { change in
            if case .addContact(let contact) = change.action { return contact.id == id }
            return false
        }
    }

    /// Queue-time step, inside the same coordinated write as the pending
    /// change. A new contact is saved at once with `awaitingActivation`, so
    /// invites, email codes and safety codes can go out now; the action's copy
    /// carries the flag too. Permission edits wait until the contact is
    /// active. Returns nil to refuse the action; any other action passes.
    static func prepareQueue(_ action: ChangeAction, state: inout LatchState) -> ChangeAction? {
        switch action {
        case .addContact(var contact):
            guard !state.overrides.contacts.contains(where: { $0.id == contact.id }) else { return nil }
            contact.awaitingActivation = true
            state.overrides.contacts.append(contact)
            return .addContact(contact)
        case .setContactPermissions(let id, _):
            let waiting = state.overrides.contacts.first { $0.id == id }?.awaitingActivation == true
            return waiting ? nil : action
        default:
            return action
        }
    }

    /// Apply-time step for `.addContact` (also reached by Apply now). A saved
    /// contact with the same id is activated, keeping its acceptance,
    /// permissions, name and avatar. A flagged copy whose contact was removed
    /// or declined does nothing: it never comes back. A legacy copy without
    /// the flag keeps the old append.
    static func apply(_ contact: TrustedContact, to state: inout LatchState) {
        if let index = state.overrides.contacts.firstIndex(where: { $0.id == contact.id }) {
            state.overrides.contacts[index].awaitingActivation = false
        } else if !contact.awaitingActivation {
            state.overrides.contacts.append(contact)
        }
    }

    /// Removing (or a declined invite) before activation: drop the waiting
    /// contact and its pending add in one write. Stricter, so immediate.
    /// Returns the removed pending changes for activity/notification cleanup,
    /// or nil when there was nothing to drop: an already active contact is
    /// left alone (its removal waits as usual).
    @discardableResult
    static func dropAwaiting(contactID id: UUID, state: inout LatchState) -> [PendingChange]? {
        guard let contact = state.overrides.contacts.first(where: { $0.id == id }),
              contact.awaitingActivation else { return nil }
        let removed = state.pending.filter { change in
            if case .addContact(let c) = change.action { return c.id == id }
            return false
        }
        state.overrides.contacts.removeAll { $0.id == id }
        state.pending.removeAll { change in removed.contains { $0.id == change.id } }
        return removed
    }

    /// Cancelling a pending change from Changes. Cancelling a new-style add
    /// also drops the still-waiting contact it saved.
    @discardableResult
    static func cancel(_ changeID: UUID, state: inout LatchState) -> PendingChange? {
        guard let change = state.pending.first(where: { $0.id == changeID }) else { return nil }
        state.pending.removeAll { $0.id == changeID }
        if case .addContact(let contact) = change.action {
            state.overrides.contacts.removeAll { $0.id == contact.id && $0.awaitingActivation }
        }
        return change
    }

    /// Housekeeping repair, idempotent. (1) One-shot migration: an add queued
    /// before F2 (no flag, contact not saved) saves its contact now, flagged,
    /// and its copy is rewritten with the flag; the change keeps its id,
    /// createdAt and appliesAt, so invites go out earlier but nobody can
    /// approve sooner. (2) Fail closed: a flagged contact whose pending add no
    /// longer exists is pruned, never activated. Returns whether it changed.
    static func repair(_ state: inout LatchState) -> Bool {
        var changed = false
        for index in state.pending.indices {
            guard case .addContact(var contact) = state.pending[index].action,
                  !contact.awaitingActivation,
                  !state.overrides.contacts.contains(where: { $0.id == contact.id }) else { continue }
            contact.awaitingActivation = true
            state.overrides.contacts.append(contact)
            state.pending[index].action = .addContact(contact)
            changed = true
        }
        let before = state.overrides.contacts.count
        state.overrides.contacts.removeAll { contact in
            contact.awaitingActivation && pendingAdd(for: contact.id, in: state.pending) == nil
        }
        return changed || state.overrides.contacts.count != before
    }
}
