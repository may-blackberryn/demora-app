import SwiftUI

/// Local setup drafts only. Nothing is queued, invited, or persisted here.
/// AppModel commits the complete fresh setup; its normal consent flow then
/// sends invitations. Developer previews never reach that commit path.
struct OnboardingOverridesDraftView: View {
    @Binding var overrides: OverridesConfig
    var isDemo = false
    @State private var showAddContact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                DemoraSectionTitle(title: tr("Trusted contacts"), symbol: "person.2")
                ForEach($overrides.contacts) { $contact in
                    HStack(alignment: .top) {
                        NavigationLink {
                            OnboardingContactPermissions(contact: $contact, isDemo: isDemo)
                        } label: {
                            draftLabel(contact.name, detail: contact.detail)
                        }
                        removeButton {
                            overrides.contacts.removeAll { $0.id == contact.id }
                            overrides.contactsEnabled = !overrides.contacts.isEmpty
                        }
                    }
                }
                Button { showAddContact = true } label: {
                    Label(tr("Add contact"), systemImage: "plus")
                        .frame(minHeight: 44)
                }
            }
            Divider().overlay(Ink.rule)
            VStack(alignment: .leading, spacing: 10) {
                DemoraSectionTitle(title: tr("Phrases"), symbol: "text.cursor")
                ForEach(overrides.phrasePolicies) { policy in
                    HStack(alignment: .top) {
                        NavigationLink {
                            PhrasePolicyEditor(existing: policy, onStage: stagePhrase,
                                               isDemo: isDemo, allowsExtraTimeWhenStaging: true)
                        } label: {
                            draftLabel(policy.name, detail: permissions(policy.allowed))
                        }
                        removeButton { overrides.phrasePolicies.removeAll { $0.id == policy.id } }
                    }
                }
                NavigationLink {
                    PhrasePolicyEditor(existing: nil, onStage: stagePhrase,
                                       isDemo: isDemo, allowsExtraTimeWhenStaging: true)
                } label: {
                    Label(tr("Add phrase"), systemImage: "plus").frame(minHeight: 44)
                }
            }
            Divider().overlay(Ink.rule)
            VStack(alignment: .leading, spacing: 10) {
                DemoraSectionTitle(title: tr("Passwords"), symbol: "key")
                ForEach(overrides.passwordPolicies) { policy in
                    HStack(alignment: .top) {
                        NavigationLink {
                            PasswordPolicyEditor(existing: policy, onStage: stagePassword,
                                                 isDemo: isDemo)
                        } label: {
                            draftLabel(policy.name, detail: permissions(policy.allowed))
                        }
                        removeButton { overrides.passwordPolicies.removeAll { $0.id == policy.id } }
                    }
                }
                NavigationLink {
                    PasswordPolicyEditor(existing: nil, onStage: stagePassword, isDemo: isDemo)
                } label: {
                    Label(tr("Add password"), systemImage: "plus").frame(minHeight: 44)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showAddContact) {
            AddContactView(onAdd: { contact in
                overrides.contacts.append(contact)
                overrides.contactsEnabled = true
            }, existingContacts: overrides.contacts, isDemo: isDemo)
        }
    }

    private func stagePhrase(_ policy: PhrasePolicy) {
        if let index = overrides.phrasePolicies.firstIndex(where: { $0.id == policy.id }) {
            overrides.phrasePolicies[index] = policy
        } else { overrides.phrasePolicies.append(policy) }
    }

    private func stagePassword(_ policy: PasswordPolicy) {
        if let index = overrides.passwordPolicies.firstIndex(where: { $0.id == policy.id }) {
            overrides.passwordPolicies[index] = policy
        } else { overrides.passwordPolicies.append(policy) }
    }

    private func permissions(_ allowed: Set<OverrideCapability>) -> String {
        OverrideCapability.allCases.filter { allowed.contains($0) }.map(\.label).joined(separator: " · ")
    }

    private func draftLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(.title3, design: .serif)).foregroundStyle(Ink.ink)
            Text(detail).font(.footnote).foregroundStyle(Ink.faint)
            Label(tr("Edit"), systemImage: "chevron.right").font(.caption)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle").frame(width: 44, height: 44)
        }
        .accessibilityLabel(tr("Remove"))
    }
}

private struct OnboardingContactPermissions: View {
    @Binding var contact: TrustedContact
    var isDemo = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                #if DEBUG
                if isDemo { DeveloperDemoNotice() }
                #endif
                DemoraPageTitle(title: contact.name)
                Text(contact.detail).foregroundStyle(Ink.faint)
                Text(tr("Allowed uses")).font(.headline)
                ForEach(OverrideCapability.allCases) { area in
                    Toggle(area.label, isOn: Binding(
                        get: { contact.allowed.contains(area) },
                        set: { enabled in
                            if enabled { contact.allowed.insert(area) }
                            else { contact.allowed.remove(area) }
                        }))
                }
                Text(tr("This contact must confirm before they can approve."))
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
            .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .paper()
        .casedNavigationTitle(tr("Approval permissions"))
    }
}
