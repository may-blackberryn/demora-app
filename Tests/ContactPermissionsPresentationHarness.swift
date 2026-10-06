// Runs the actual presentation helper without SwiftUI or an iOS device:
// (sed -n '/^enum ContactPermissionPresentation {/,/^}/p' Latch/ContactPermissionsEditor.swift;
//  cat Tests/ContactPermissionsPresentationHarness.swift) | swift -
// These stand-ins cover presentation only, not approval enforcement.
import Foundation

func tr(_ text: String) -> String { text }

enum OverrideCapability: String, CaseIterable, Hashable {
    case limitChanges, scheduleChanges, sessionChanges, delayChanges
    case protectionChanges, contactChanges, extraTime
    var label: String { rawValue }
}

enum ChangeAction {
    case setContactPermissions(id: UUID, allowed: Set<OverrideCapability>)
    case removeContact(id: UUID)
    case unrelated
}

struct PendingChange {
    var id = UUID()
    var action: ChangeAction
}

let contactID = UUID()
let otherID = UUID()
let edit = PendingChange(action: .setContactPermissions(id: contactID, allowed: [.extraTime]))
let removal = PendingChange(action: .removeContact(id: contactID))
let otherEdit = PendingChange(action: .setContactPermissions(id: otherID, allowed: []))
let unrelated = PendingChange(action: .unrelated)

precondition(ContactPermissionPresentation.pendingChange(for: contactID, in: []) == nil)
precondition(ContactPermissionPresentation.pendingChange(
    for: contactID, in: [otherEdit, unrelated]) == nil)
precondition(ContactPermissionPresentation.pendingChange(
    for: contactID, in: [otherEdit, unrelated, edit])?.id == edit.id)
precondition(ContactPermissionPresentation.pendingChange(
    for: contactID, in: [otherEdit, removal])?.id == removal.id)
precondition(ContactPermissionPresentation.pendingChange(
    for: otherID, in: [edit, otherEdit])?.id == otherEdit.id)

precondition(ContactPermissionPresentation.summary([]) == "None")
precondition(ContactPermissionPresentation.summary([.extraTime]) == "None")
precondition(ContactPermissionPresentation.summary([.scheduleChanges, .limitChanges, .extraTime])
             == "limitChanges, scheduleChanges")
precondition(ContactPermissionPresentation.summary(Set(OverrideCapability.allCases))
             == "All pending changes")
print("Contact permission presentation checks passed (9 assertions)")
