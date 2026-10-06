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

/// Open, ruled entry reused on the main contacts screen and both profiles.
struct ContactApprovalSummary: View {
    @AppAccent private var accent
    let contact: TrustedContact
    @EnvironmentObject private var model: AppModel

    private var pending: PendingChange? {
        ContactPermissionPresentation.pendingChange(for: contact.id, in: model.state.pending)
    }

    var body: some View {
        NavigationLink {
            ContactPermissionsEditor(contactID: contact.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(tr("Approval permissions"), systemImage: "checkmark.shield")
                        .font(.system(.headline, design: .serif))
                    Spacer(minLength: 8)
                    Text(tr("Edit")).font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                Text(tr("Current permissions")).font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.faint)
                Text(String(format: tr("Pending changes: %@"),
                            ContactPermissionPresentation.summary(contact.allowed)))
                    .font(.footnote).foregroundStyle(Ink.ink)
                Text(String(format: tr("Extra time: %@"),
                            contact.allowed.contains(.extraTime) ? tr("On") : tr("Off")))
                    .font(.footnote).foregroundStyle(Ink.ink)
                if let pending {
                    if case .setContactPermissions(_, let queued) = pending.action {
                        Text(tr("Queued permissions")).font(.caption.weight(.semibold))
                            .foregroundStyle(Ink.faint)
                        Text(String(format: tr("Pending changes: %@"),
                                    ContactPermissionPresentation.summary(queued)))
                            .font(.footnote).foregroundStyle(Ink.ink)
                        Text(String(format: tr("Extra time: %@"),
                                    queued.contains(.extraTime) ? tr("On") : tr("Off")))
                            .font(.footnote).foregroundStyle(Ink.ink)
                    } else {
                        Text(tr("Contact removal queued")).font(.footnote)
                            .foregroundStyle(Ink.danger)
                    }
                    Text(pending.appliesAt, style: .date)
                        + Text(" · ") + Text(pending.appliesAt, style: .time)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .foregroundStyle(accent)
        }
        .buttonStyle(.plain)
    }
}

struct ContactPermissionsEditor: View {
    @AppAccent private var accent
    let contactID: UUID
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var allowed: Set<OverrideCapability> = []

    private var contact: TrustedContact? {
        model.state.overrides.contacts.first { $0.id == contactID }
    }

    private var pending: PendingChange? {
        ContactPermissionPresentation.pendingChange(for: contactID, in: model.state.pending)
    }

    private var queuedPermissions: Set<OverrideCapability>? {
        guard let pending, case .setContactPermissions(_, let queued) = pending.action else {
            return nil
        }
        return queued
    }

    private var action: ChangeAction {
        .setContactPermissions(id: contactID, allowed: allowed)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DemoraPageTitle(title: tr("Approval permissions"))
                if let contact {
                    Text(contact.name.isEmpty ? contact.detail : contact.name)
                        .font(.system(.title3, design: .serif)).foregroundStyle(Ink.ink)
                    Text(tr("Choose what this person can approve. Expanding permissions waits through your less-strict delay; removing permissions waits through your more-strict delay."))
                        .font(.subheadline).foregroundStyle(Ink.faint)
                    if !model.state.overrides.contactsEnabled {
                        Label(tr("Trusted-contact approvals are turned off."), systemImage: "pause.circle")
                            .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    if !contact.isUsable {
                        Text(tr("This contact must confirm before they can approve."))
                            .font(.footnote).foregroundStyle(Ink.faint)
                    }
                    if let pending { pendingSection(pending) }
                    permissionSection(title: tr("Pending changes"),
                                      areas: OverrideCapability.allCases.filter { $0 != .extraTime },
                                      contact: contact)
                    permissionSection(title: tr("Extra time"), areas: [.extraTime], contact: contact)
                    Text(tr("Extra time is opt-in. Approval grants only a configured extra-time use after the daily budget is spent; it does not bypass other blocks."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                    Text(tr("Permission edits cannot be approved early by a contact, password, or phrase. Approvals are checked against current permissions when used."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                    if pending == nil && contact.allowed != allowed {
                        let (direction, delay) = model.preview(action)
                        Label(String(format: tr("%@ — takes effect in %@"),
                                     direction.label, delay.shortDelayLabel), systemImage: "clock")
                            .font(.footnote).foregroundStyle(Ink.faint)
                        Text(tr("Current permissions stay in effect until this change applies."))
                            .font(.footnote).foregroundStyle(Ink.faint)
                        Button(tr("Queue change")) {
                            guard self.pending == nil, self.contact != nil else { return }
                            if model.queue(action) != nil { dismiss() }
                        }
                        .buttonStyle(DemoraPrimaryButtonStyle())
                    }
                } else {
                    Text(tr("This contact is no longer available."))
                        .foregroundStyle(Ink.faint)
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Approval permissions"))
        .onAppear { allowed = contact?.allowed ?? [] }
        .onChange(of: contact?.allowed) { value in allowed = value ?? [] }
    }

    private func permissionSection(title: String, areas: [OverrideCapability],
                                   contact: TrustedContact) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DemoraSectionTitle(title: title).padding(.bottom, 12)
            ForEach(areas) { area in
                VStack(alignment: .leading, spacing: 8) {
                    if pending != nil {
                        Text(area.label).font(.headline).foregroundStyle(Ink.ink)
                        HStack(alignment: .top, spacing: 24) {
                            permissionStatus(tr("Current"), enabled: contact.allowed.contains(area))
                            if let queuedPermissions {
                                permissionStatus(tr("Queued"), enabled: queuedPermissions.contains(area))
                            }
                        }
                    } else {
                        Toggle(isOn: Binding(
                            get: { allowed.contains(area) },
                            set: { enabled in
                                if enabled { allowed.insert(area) }
                                else { allowed.remove(area) }
                            })) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(area.label).font(.headline).foregroundStyle(Ink.ink)
                                    Text(String(format: tr("Current: %@"),
                                                contact.allowed.contains(area) ? tr("On") : tr("Off")))
                                        .font(.caption).foregroundStyle(Ink.faint)
                                }
                            }
                            .tint(accent)
                    }
                }
                .padding(.vertical, 14)
                Divider().overlay(Ink.rule)
            }
        }
    }

    private func permissionStatus(_ title: String, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Ink.faint)
            Label(enabled ? tr("On") : tr("Off"),
                  systemImage: enabled ? "checkmark" : "minus")
                .font(.subheadline).foregroundStyle(enabled ? accent : Ink.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pendingSection(_ change: PendingChange) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DemoraSectionTitle(title: queuedPermissions == nil
                               ? tr("Contact removal queued") : tr("Queued permissions"), symbol: "clock")
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                let remaining = max(0, change.appliesAt.timeIntervalSince(TimeGuard.now()))
                Text(remaining > 0
                     ? String(format: tr("%@ — takes effect in %@"),
                              change.direction.label, remaining.shortDelayLabel)
                     : tr("Due — waiting to apply"))
                    .font(.subheadline).foregroundStyle(accent)
            }
            Text(change.appliesAt, style: .date)
                + Text(" · ") + Text(change.appliesAt, style: .time)
            Text(tr("Current permissions stay in effect until this change applies."))
                .font(.footnote).foregroundStyle(Ink.faint)
            Text(tr("Cancel the queued change before editing permissions again."))
                .font(.footnote).foregroundStyle(Ink.faint)
            Button(tr("Cancel queued change"), role: .destructive) {
                guard !change.isDue, pending?.id == change.id else { return }
                model.cancel(change)
                allowed = contact?.allowed ?? []
            }
            .disabled(change.isDue)
            Divider().overlay(Ink.rule)
        }
    }
}
