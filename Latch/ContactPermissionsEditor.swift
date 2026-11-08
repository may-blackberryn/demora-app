//
//  ContactPermissionsEditor.swift
//  The contact permission editor moved to You → Ways to skip a wait
//  (SkipWayEditors.swift, docs/you-redesign.md §5.10). This presentation
//  helper stays for Tests/ContactPermissionsPresentationHarness.swift.
//

import SwiftUI

/// Presentation only: the engine owns delays and approval authorization.
enum ContactPermissionPresentation {
    static func pendingChange(for contactID: UUID, in changes: [PendingChange]) -> PendingChange? {
        changes.first { change in
            switch change.action {
            case .setContactPermissions(let id, _), .removeContact(let id):
                return id == contactID
            default: return false
            }
        }
    }

    static func summary(_ allowed: Set<OverrideCapability>) -> String {
        let areas = OverrideCapability.allCases.filter {
            $0 != .extraTime && allowed.contains($0)
        }
        if areas.isEmpty { return tr("None") }
        if areas.count == OverrideCapability.allCases.count - 1 {
            return tr("All pending changes")
        }
        return areas.map(\.label).joined(separator: ", ")
    }
}
