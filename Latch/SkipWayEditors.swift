//
//  SkipWayEditors.swift
//  Adding, editing and removing a way to skip a wait (docs/you-redesign.md
//  §5.9, §5.10, Y5, Y11). One add sheet with its steps pushed inside it and
//  the receipt as its last step; a detail page per contact, password or
//  phrase. Every add, permission change and removal ends on the receipt and
//  queues through the engine. Knowing a password allows only an immediate
//  change of the secret itself. Plain passwords are hashed on Continue and
//  never stored or logged; fields clear when their page closes.
//

import SwiftUI

// MARK: - What it can skip (SkipPermissionsChecklist, §5.10.2)

struct SkipPermissionsChecklist: View {
    @Binding var allowed: Set<OverrideCapability>
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
            SectionHeader(tr("What it can skip"))
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("Changes that wait"))
                    .demoraType(.label)
                    .foregroundStyle(Ink.inkSoft)
                    .padding(.horizontal, DemoraSpace.cardPadding)
                    .padding(.top, DemoraSpace.s)
                ForEach(SkipWayPermissionText.changeAreas) { area in
                    toggle(area, detail: detail(area))
                    if area != SkipWayPermissionText.changeAreas.last { YouRowDivider() }
                }
            }
            .paperCard(padding: 0)
            VStack(alignment: .leading, spacing: 0) {
                toggle(.extraTime, detail: tr("Also needs a limit whose extra time asks for this."))
            }
            .paperCard(padding: 0)
            Text(tr("Changes to passwords, phrases and what anyone may skip can never be skipped early."))
                .demoraType(.meta)
                .foregroundStyle(Ink.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private func detail(_ area: OverrideCapability) -> String? {
        switch area {
        case .protectionChanges: return tr("App deletion lock, websites and Prevent disabling access")
        case .contactChanges: return tr("Adding, removing or pausing trusted contacts")
        default: return nil
        }
    }

    private func toggle(_ area: OverrideCapability, detail: String?) -> some View {
        Toggle(isOn: Binding(
            get: { allowed.contains(area) },
            set: { on in if on { allowed.insert(area) } else { allowed.remove(area) } })) {
                VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                    Text(tr(SkipWayPermissionText.title(area))).demoraType(.body)
                    if let detail {
                        Text(detail)
                            .demoraType(.meta)
                            .foregroundStyle(Ink.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, DemoraSpace.xxs)
            }
            .toggleStyle(DemoraToggleStyle())
            .padding(.horizontal, DemoraSpace.cardPadding)
    }
}

// MARK: - Add a way to skip a wait (§5.9)

private enum AddSkipStep: Hashable {
    case details(SkipWayKind)
    case receipt
}

struct AddSkipWaySheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var path: [AddSkipStep] = []
    @State private var draft: SkipWayDraft?

    var body: some View {
        NavigationStack(path: $path) {
            choose
                .navigationDestination(for: AddSkipStep.self) { step in
                    switch step {
                    case .details(let kind):
                        details(kind)
                    case .receipt:
                        receipt
                    }
                }
        }
    }

    private var choose: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.m) {
                VStack(spacing: 0) {
                    option(.contact, title: tr("Someone you trust"),
                           detail: EmailCodeService.isConfigured
                            ? tr("They approve from their Demora app, or with a code you email them.")
                            : tr("They approve from their Demora app."),
                           avatar: { ContactAvatarView(avatar: nil, size: 36) })
                    YouRowDivider()
                    option(.password, title: tr("A password"),
                           detail: tr("Best if someone else keeps it, or it's written down somewhere out of reach."),
                           avatar: { SkipWaySymbol(symbol: "key") })
                    YouRowDivider()
                    option(.phrase, title: tr("A phrase"), detail: tr("Typed word by word. Slow on purpose."),
                           avatar: { SkipWaySymbol(symbol: "text.quote") })
                }
                .paperCard(padding: 0)
            }
            .padding(DemoraSpace.l)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Add a way to skip a wait"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(tr("Cancel")) { dismiss() }
            }
        }
    }

    private func option<Avatar: View>(_ kind: SkipWayKind, title: String, detail: String,
                                      @ViewBuilder avatar: () -> Avatar) -> some View {
        Button { path.append(.details(kind)) } label: {
            HStack(spacing: DemoraSpace.s) {
                avatar()
                VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                    Text(title).demoraType(.cardTitle).foregroundStyle(Ink.ink)
                    Text(detail)
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DemoraSpace.xs)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.inkSoft)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DemoraSpace.cardPadding)
            .padding(.vertical, DemoraSpace.s)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func details(_ kind: SkipWayKind) -> some View {
        switch kind {
        case .contact:
            AddContactDetails { contact in draft = .contact(contact); path.append(.receipt) }
        case .password:
            AddPasswordDetails { policy in draft = .password(policy); path.append(.receipt) }
        case .phrase:
            PhraseDetailsPage(existing: nil, title: tr("A phrase"), showsChecklist: true) { policy in
                draft = .phrase(policy); path.append(.receipt)
            }
        }
    }

    @ViewBuilder private var receipt: some View {
        if let draft {
            let actions = SkipWayAddPlan.actions(adding: draft, overrides: model.state.overrides,
                                                 pending: model.state.pending)
            ChangeReceiptView(
                actions: actions,
                lines: actions.count > 1 ? [tr("Also turns on contact approvals")] : [],
                note: contactNote(draft),
                onQueued: { dismiss() },
                onBack: { path.removeLast() })
                .background(Ink.cardRaised.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func contactNote(_ draft: SkipWayDraft) -> String? {
        guard case .contact(let contact) = draft else { return nil }
        let name = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(format: tr("%@ must also accept before they can approve."),
                      name.isEmpty ? tr("This contact") : name)
    }
}

/// Name and Demora code (or email, only when this build can send email),
/// the same checks as before, then what they may skip.
private struct AddContactDetails: View {
    @EnvironmentObject private var model: AppModel
    let onContinue: (TrustedContact) -> Void

    private enum ContactType: Hashable { case latchUser, email }

    @State private var name = ""
    @State private var type: ContactType = .latchUser
    @State private var email = ""
    @State private var code = ""
    @State private var checking = false
    @State private var error: String?
    @State private var emailUsage: EmailCodeService.Usage?
    /// Fresh per add, so re-adding a contact requires a new acceptance.
    @State private var inviteId = UUID().uuidString
    @State private var allowed = Set(OverrideCapability.allCases.filter { $0 != .extraTime })

    private var draft: TrustedContact {
        switch type {
        case .email:
            return TrustedContact(name: name, kind: .email(
                email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
                accepted: false, inviteId: inviteId, allowed: allowed)
        case .latchUser:
            return TrustedContact(name: name, kind: .latchUser(code:
                code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()),
                accepted: false, inviteId: inviteId, allowed: allowed)
        }
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch type {
        case .email: return EmailCodeService.isConfigured && email.contains("@")
        case .latchUser: return code.trimmingCharacters(in: .whitespaces).count == 6
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                VStack(alignment: .leading, spacing: DemoraSpace.s) {
                    TextField(tr("Name, e.g. Mom or Alex"), text: $name)
                        .demoraType(.cardTitle)
                        .textInputAutocapitalization(.words)
                        .frame(minHeight: 44)
                    Rectangle().fill(Ink.hairline).frame(height: 1).accessibilityHidden(true)
                    if EmailCodeService.isConfigured {
                        Picker(tr("Type"), selection: $type) {
                            Text(tr("Demora user")).tag(ContactType.latchUser)
                            Text(tr("Email")).tag(ContactType.email)
                        }
                        .pickerStyle(.segmented)
                    }
                    switch type {
                    case .latchUser:
                        TextField(tr("Their Demora code"), text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(.title3, design: .monospaced))
                            .frame(minHeight: 44)
                        Text(String(format: tr("Ask them for the code under You → Your code. Yours is %@."),
                                    ContactsRelay.myCode))
                            .demoraType(.meta)
                            .foregroundStyle(Ink.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    case .email:
                        TextField(tr("Email address"), text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .frame(minHeight: 44)
                        Text(tr("Email contacts have a daily send limit; Demora-user contacts don't."))
                            .demoraType(.meta)
                            .foregroundStyle(Ink.inkSoft)
                        if let emailUsage { EmailUsageBars(usage: emailUsage) }
                    }
                }
                .paperCard()
                SkipPermissionsChecklist(allowed: $allowed)
                if let error {
                    Text(error)
                        .demoraType(.meta)
                        .foregroundStyle(Ink.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(checking ? tr("Checking…") : tr("Continue")) {
                    Task { await submit() }
                }
                .buttonStyle(DemoraPrimaryButtonStyle())
                .disabled(!isValid || checking)
            }
            .padding(DemoraSpace.l)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Someone you trust"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if EmailCodeService.isConfigured {
                emailUsage = try? await EmailCodeService.usage()
            }
        }
    }

    /// The old form's checks: not already a contact (saved or waiting to be
    /// added), not your own code, and a Demora user who exists.
    private func submit() async {
        error = nil
        let waiting = model.state.pending.compactMap { change -> TrustedContact? in
            if case .addContact(let contact) = change.action { return contact }
            return nil
        }
        let duplicate = (model.state.overrides.contacts + waiting).contains { existing in
            switch (existing.kind, draft.kind) {
            case let (.email(a), .email(b)): return a == b
            case let (.latchUser(a), .latchUser(b)): return a == b
            default: return false
            }
        }
        if duplicate {
            error = tr("You already have this person as a contact.")
            return
        }
        if case .latchUser(let value) = draft.kind {
            guard value != ContactsRelay.myCode else {
                error = tr("That's your own code — add someone else.")
                return
            }
            checking = true
            defer { checking = false }
            let exists = (try? await ContactsRelay.codeExists(value)) ?? false
            guard exists else {
                error = tr("No Demora user found with that code.")
                return
            }
        }
        onContinue(draft)
    }
}

/// Name, the password twice and what it may skip. Hashed on Continue.
private struct AddPasswordDetails: View {
    let onContinue: (PasswordPolicy) -> Void
    @State private var name = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var allowed: Set<OverrideCapability> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                VStack(alignment: .leading, spacing: DemoraSpace.s) {
                    TextField(tr("Name"), text: $name)
                        .demoraType(.cardTitle)
                        .frame(minHeight: 44)
                    Rectangle().fill(Ink.hairline).frame(height: 1).accessibilityHidden(true)
                    SecureField(tr("Password"), text: $password)
                        .frame(minHeight: 44)
                    SecureField(tr("Confirm password"), text: $confirm)
                        .frame(minHeight: 44)
                    if !confirm.isEmpty && password != confirm {
                        Text(tr("Passwords don't match"))
                            .demoraType(.meta)
                            .foregroundStyle(Ink.danger)
                    }
                }
                .paperCard()
                SkipPermissionsChecklist(allowed: $allowed)
                Button(tr("Continue")) {
                    let policy = PasswordPolicy(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                hash: AppModel.hash(password), allowed: allowed)
                    password = ""
                    confirm = ""
                    onContinue(policy)
                }
                .buttonStyle(DemoraPrimaryButtonStyle())
                .disabled(!SkipWayAddPlan.passwordIsValid(name: name, password: password,
                                                          confirm: confirm, allowed: allowed))
            }
            .padding(DemoraSpace.l)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("A password"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { password = ""; confirm = "" }
    }
}

/// The phrase fields (shared by add and Change the words): name, random
/// words or a custom phrase, mistakes before starting over.
struct PhraseDetailsPage: View {
    let existing: PhrasePolicy?
    let title: String
    /// Add shows the checklist; Change the words keeps what it may skip.
    let showsChecklist: Bool
    let onContinue: (PhrasePolicy) -> Void
    @State private var draftID = UUID()
    @State private var name = ""
    @State private var isRandom = true
    @State private var randomCount = 50
    @State private var customText = ""
    @State private var errorAllowance = 0 // -1 means unlimited
    @State private var allowed: Set<OverrideCapability> = []
    @State private var loaded = false

    private var policy: PhrasePolicy {
        PhrasePolicy(id: existing?.id ?? draftID,
                     name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                     kind: isRandom ? .random(randomCount) : .custom(customText),
                     allowedErrors: errorAllowance < 0 ? nil : errorAllowance,
                     allowed: allowed)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                VStack(alignment: .leading, spacing: DemoraSpace.s) {
                    TextField(tr("Name"), text: $name)
                        .demoraType(.cardTitle)
                        .frame(minHeight: 44)
                    Rectangle().fill(Ink.hairline).frame(height: 1).accessibilityHidden(true)
                    Picker(tr("Phrase type"), selection: $isRandom) {
                        Text(tr("Random words")).tag(true)
                        Text(tr("Custom phrase")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    if isRandom {
                        Picker(tr("Words"), selection: $randomCount) {
                            ForEach([50, 100, 200, 500, 1000], id: \.self) { count in
                                Text(String(format: tr("%d words"), count)).tag(count)
                            }
                        }
                        .frame(minHeight: 44)
                    } else {
                        Text(tr("The exact custom phrase is saved on this device. Choose something you would not type impulsively."))
                            .demoraType(.meta)
                            .foregroundStyle(Ink.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        TextEditor(text: $customText)
                            .frame(minHeight: 100)
                            .scrollContentBackground(.hidden)
                            .background(Ink.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Picker(tr("Wrong words before reset"), selection: $errorAllowance) {
                        ForEach([0, 1, 5, 10, -1], id: \.self) { count in
                            Text(count < 0 ? tr("Unlimited") : "\(count)").tag(count)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .paperCard()
                if showsChecklist { SkipPermissionsChecklist(allowed: $allowed) }
                Button(tr("Continue")) { onContinue(policy) }
                    .buttonStyle(DemoraPrimaryButtonStyle())
                    .disabled(!PhraseWords.isValid(policy) || policy == existing)
            }
            .padding(DemoraSpace.l)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = existing?.name ?? ""
            allowed = existing?.allowed ?? []
            errorAllowance = existing.map { $0.allowedErrors ?? -1 } ?? 0
            if let existing {
                switch existing.kind {
                case .custom(let text): isRandom = false; customText = text
                case .random(let count): isRandom = true; randomCount = count
                }
            }
        }
    }
}

// MARK: - Detail page (§5.10)

struct SkipWayDetailView: View {
    @AppAccent private var accent
    @AppLoosen private var loosen
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let kind: SkipWayKind
    let id: UUID
    @State private var allowed: Set<OverrideCapability> = []
    @State private var loadedFor: Set<OverrideCapability>?
    @State private var receipt: ChangeReceiptRequest?
    @State private var closeAfterReceipt = false

    private var current: Set<OverrideCapability>? {
        switch kind {
        case .contact: return model.state.overrides.contacts.first { $0.id == id }?.allowed
        case .password: return model.state.overrides.passwordPolicies.first { $0.id == id }?.allowed
        case .phrase: return model.state.overrides.phrasePolicies.first { $0.id == id }?.allowed
        }
    }

    private var title: String {
        switch kind {
        case .contact:
            guard let contact = model.state.overrides.contacts.first(where: { $0.id == id })
            else { return tr("Contact") }
            let name = contact.latchUserCode.map {
                resolvedName(forCode: $0, model: model, fallback: contact.name)
            } ?? contact.name
            return name.isEmpty ? tr("Contact") : name
        case .password:
            return model.state.overrides.passwordPolicies.first { $0.id == id }?.name ?? tr("Password")
        case .phrase:
            return model.state.overrides.phrasePolicies.first { $0.id == id }?.name ?? tr("Phrase")
        }
    }

    var body: some View {
        let pending = SkipWayList.pendingChange(for: id, kind: kind, pending: model.state.pending)
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                if let current {
                    identity
                    if let pending { pendingStrip(pending) }
                    SkipPermissionsChecklist(allowed: $allowed, disabled: pending != nil)
                    if allowed != current {
                        if pending != nil {
                            Text(tr("A change is already waiting"))
                                .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                        } else if SkipWayEdit.canSave(kind: kind, current: current, draft: allowed,
                                                      hasPending: false) {
                            Button(tr("Save changes")) { saveChanges() }
                                .buttonStyle(DemoraPrimaryButtonStyle())
                        } else {
                            Text(tr("Choose at least one thing it can skip."))
                                .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                        }
                    }
                    actions(pending: pending)
                } else {
                    Text(tr("This is no longer available."))
                        .demoraType(.body).foregroundStyle(Ink.inkSoft)
                }
            }
            .padding(.horizontal, DemoraSpace.pageGutter)
            .padding(.vertical, DemoraSpace.l)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .changeReceipt($receipt) {
            if closeAfterReceipt {
                closeAfterReceipt = false
                dismiss()
            } else if let current {
                // The queued set shows in the strip above; the checklist
                // never pretends it is live (§5.10.2, review fix).
                allowed = current
            }
        }
        .onAppear(perform: load)
        .onChange(of: current) { _ in load() }
    }

    /// The checklist shows the current permissions; it reloads when they
    /// change underneath (a queued change applied).
    private func load() {
        guard let current, loadedFor != current else { return }
        loadedFor = current
        allowed = current
    }

    @ViewBuilder private var identity: some View {
        switch kind {
        case .contact:
            if let contact = model.state.overrides.contacts.first(where: { $0.id == id }) {
                ContactIdentityCard(contact: contact)
            }
        case .password:
            VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                Text(title).demoraType(.cardTitle).foregroundStyle(Ink.ink)
                Text(tr("Password set")).demoraType(.meta).foregroundStyle(Ink.inkSoft)
            }
            .paperCard()
        case .phrase:
            if let policy = model.state.overrides.phrasePolicies.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                    Text(policy.name).demoraType(.cardTitle).foregroundStyle(Ink.ink)
                    Text(phraseKind(policy)).demoraType(.meta).foregroundStyle(Ink.inkSoft)
                    Text(policy.allowedErrors.map { String(format: tr("Mistakes allowed: %d"), $0) }
                         ?? tr("Mistakes allowed: unlimited"))
                        .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                }
                .paperCard()
            }
        }
    }

    private func phraseKind(_ policy: PhrasePolicy) -> String {
        switch policy.kind {
        case .random(let count): return String(format: tr("%d random words"), count)
        case .custom: return tr("Custom phrase")
        }
    }

    /// "From Tue 14:32: Limits, schedules" for a queued edit, or the queued
    /// removal; the ledger owns Cancel.
    private func pendingStrip(_ change: PendingChange) -> some View {
        var calendar = Calendar.current
        calendar.locale = locale
        let when = TodayTimeText.short(change.appliesAt, now: Date(), calendar: calendar, locale: locale)
        let text: String
        if let edit = SkipWayList.queuedEdit(of: id, kind: kind, pending: model.state.pending),
           edit.change.id == change.id {
            text = String(format: tr("From %@: %@"), when,
                          SkipWayPermissionText.summary(edit.allowed, translate: tr))
        } else {
            text = String(format: tr("Removed %@"), when)
        }
        return VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            HStack(spacing: DemoraSpace.xxs) {
                Image(systemName: "clock").accessibilityHidden(true)
                Text(text).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DemoraSpace.xs)
                CountdownText(to: change.appliesAt, style: nil).monospacedDigit()
            }
            .demoraType(.meta)
            .foregroundStyle(Ink.ink)
            SectionHeaderLink(title: tr("See in Changes")) {
                model.youPath.append(.ledger(change.id))
            }
        }
        .paperCard(fill: Ink.tint(InkPalette.hairline))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func actions(pending: PendingChange?) -> some View {
        VStack(spacing: 0) {
            switch kind {
            case .password:
                NavigationLink {
                    PasswordSecretChangeView(id: id)
                } label: {
                    YouRowLabel(title: tr("Change the password"))
                }
                .buttonStyle(.plain)
                YouRowDivider()
            case .phrase:
                if let policy = model.state.overrides.phrasePolicies.first(where: { $0.id == id }) {
                    NavigationLink {
                        PhraseWordsChangeView(policy: policy)
                    } label: {
                        YouRowLabel(title: tr("Change the words"))
                    }
                    .buttonStyle(.plain)
                    .disabled(pending != nil)
                    YouRowDivider()
                }
            case .contact:
                if let code = model.state.overrides.contacts.first(where: { $0.id == id })?.latchUserCode {
                    NavigationLink {
                        ScrollView {
                            ContactVerificationSection(code: code)
                                .padding(DemoraSpace.l)
                                .frame(maxWidth: DemoraSpace.maxContentWidth)
                                .frame(maxWidth: .infinity)
                        }
                        .background(Ink.paper.ignoresSafeArea())
                        .casedNavigationTitle(tr("Safety code"))
                    } label: {
                        YouRowLabel(title: tr("Safety code"))
                    }
                    .buttonStyle(.plain)
                    YouRowDivider()
                }
            }
            Button {
                closeAfterReceipt = true
                receipt = ChangeReceiptRequest(action: removal)
            } label: {
                YouRowLabel(title: tr("Remove…"), chevron: false, titleColor: loosen)
            }
            .buttonStyle(.plain)
            .disabled(pending != nil)
        }
        .paperCard(padding: 0)
    }

    private var removal: ChangeAction {
        switch kind {
        case .contact: return .removeContact(id: id)
        case .password: return .removePasswordPolicy(id: id)
        case .phrase: return .removePhrasePolicy(id: id)
        }
    }

    /// Direction comes from the engine: narrowing a contact is stricter;
    /// password and phrase edits stay looser (owner answer 1).
    private func saveChanges() {
        let action: ChangeAction
        switch kind {
        case .contact:
            action = .setContactPermissions(id: id, allowed: allowed)
        case .password:
            guard var policy = model.state.overrides.passwordPolicies.first(where: { $0.id == id })
            else { return }
            policy.allowed = allowed
            action = .upsertPasswordPolicy(policy)
        case .phrase:
            guard var policy = model.state.overrides.phrasePolicies.first(where: { $0.id == id })
            else { return }
            policy.allowed = allowed
            action = .upsertPhrasePolicy(policy)
        }
        closeAfterReceipt = false
        receipt = ChangeReceiptRequest(action: action)
    }
}

/// Avatar, name (local, immediate), code or email and the contact's state.
private struct ContactIdentityCard: View {
    @AppAccent private var accent
    @EnvironmentObject private var model: AppModel
    let contact: TrustedContact
    @State private var name = ""
    @State private var avatar = ContactAvatar()
    @State private var loaded = false
    // Email confirmation (unchanged flow).
    @State private var codeInput = ""
    @State private var sending = false
    @State private var verifying = false
    @State private var sentNow = false
    @State private var error: String?
    @State private var info: String?

    private var inviteSent: Bool {
        sentNow || ContactsRelay.wasSentEmail("invite-" + contact.inviteId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            HStack(spacing: DemoraSpace.s) {
                NavigationLink {
                    ScrollView {
                        AvatarEditorView(avatar: $avatar)
                            .paperCard()
                            .padding(DemoraSpace.l)
                            .frame(maxWidth: DemoraSpace.maxContentWidth)
                            .frame(maxWidth: .infinity)
                    }
                    .background(Ink.paper.ignoresSafeArea())
                    .casedNavigationTitle(tr("Avatar"))
                } label: {
                    ContactAvatarView(avatar: avatar, size: 56)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Avatar"))
                TextField(tr("Name (optional)"), text: $name)
                    .demoraType(.cardTitle)
                    .textInputAutocapitalization(.words)
                    .frame(minHeight: 44)
            }
            Text(contact.latchUserCode.map { String(format: tr("Demora code %@"), $0) } ?? contact.detail)
                .demoraType(.meta)
                .foregroundStyle(Ink.inkSoft)
                .textSelection(.enabled)
            if let state = stateLine {
                Text(state)
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if contact.isEmail && !contact.accepted && EmailCodeService.isConfigured {
                emailConfirmation
            }
            if let info { Text(info).demoraType(.meta).foregroundStyle(Ink.inkSoft) }
            if let error { Text(error).demoraType(.meta).foregroundStyle(Ink.danger) }
        }
        .paperCard()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            // Prefer the shared per-code values so a name or photo set on the
            // "people you approve for" side shows here too.
            if let code = contact.latchUserCode {
                name = resolvedName(forCode: code, model: model, fallback: contact.name)
                avatar = resolvedAvatar(forCode: code, model: model) ?? contact.avatar ?? ContactAvatar()
            } else {
                name = contact.name
                avatar = contact.avatar ?? ContactAvatar()
            }
        }
        .onChange(of: name) { value in
            // Renaming is local metadata: immediate, as before.
            model.renameContact(id: contact.id, to: value)
            if let code = contact.latchUserCode { ContactsRelay.setName(value, forCode: code) }
        }
        .onChange(of: avatar) { value in
            model.setContactAvatar(id: contact.id, value)
            if let code = contact.latchUserCode { ContactsRelay.setAvatar(value, forCode: code) }
        }
    }

    private var stateLine: String? {
        if contact.isEmail {
            if !EmailCodeService.isConfigured { return tr("Email approvals aren't available in this version") }
            return contact.accepted ? tr("Confirmed") : nil
        }
        if contact.isPending { return tr("Waiting for them to accept in their Demora app.") }
        if let code = contact.latchUserCode, model.unavailableContactCodes.contains(code) {
            return tr("Can't reach this contact right now — they may have removed Demora or signed out. They won't be able to approve until they're back.")
        }
        return nil
    }

    private var emailConfirmation: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            Text(tr("We email a code to this address. Your contact gives you the code, you enter it here, and then they can approve for you. Until then they can't."))
                .demoraType(.meta)
                .foregroundStyle(Ink.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button(sending ? tr("Sending…")
                   : (inviteSent ? tr("Resend code") : tr("Send confirmation code"))) {
                Task { await sendCode() }
            }
            .buttonStyle(.plain)
            .font(DemoraType.button)
            .foregroundStyle(accent)
            .frame(minHeight: 44)
            .disabled(sending)
            if inviteSent {
                TextField(tr("6-digit code"), text: $codeInput)
                    .keyboardType(.numberPad)
                    .font(.title2.monospaced())
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 44)
                Button(verifying ? tr("Checking…") : tr("Confirm contact")) {
                    Task { await confirm() }
                }
                .buttonStyle(DemoraPrimaryButtonStyle())
                .disabled(codeInput.count != 6 || verifying)
            }
        }
    }

    private var email: String {
        if case .email(let address) = contact.kind { return address }
        return ""
    }

    private func sendCode() async {
        guard !contact.inviteId.isEmpty, !email.isEmpty else { return }
        sending = true
        defer { sending = false }
        error = nil; info = nil
        do {
            try await EmailCodeService.sendInviteCode(
                inviteId: contact.inviteId, email: email, ownerName: ContactsRelay.myName)
            ContactsRelay.markSent(requestId: "invite-" + contact.inviteId, relay: false)
            sentNow = true
            info = tr("Code sent. Ask your contact for it.")
        } catch let EmailCodeError.rateLimited(global) {
            error = global ? tr("Daily email limit reached. Try again later.")
                           : tr("You've sent too many codes today. Try again tomorrow.")
        } catch {
            self.error = tr("Couldn't send the code. Check your connection and try again.")
        }
    }

    private func confirm() async {
        verifying = true
        defer { verifying = false }
        error = nil
        do {
            if try await EmailCodeService.verifyInvite(inviteId: contact.inviteId, code: codeInput) {
                model.confirmEmailContact(id: contact.id)
                ContactsRelay.clearSent("invite-" + contact.inviteId)
            } else {
                error = tr("That code didn't match. Double-check and try again.")
            }
        } catch {
            // Don't call a network failure a wrong code.
            self.error = tr("Couldn't check the code — check your connection and try again.")
        }
    }
}

// MARK: - Change the password now (Y5)

/// Knowing the current password allows changing only the secret, right
/// away. What it may skip stays the same; that edit waits on the detail page.
private struct PasswordSecretChangeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.m) {
                VStack(alignment: .leading, spacing: DemoraSpace.s) {
                    SecureField(tr("Current password"), text: $current)
                        .frame(minHeight: 44)
                    Rectangle().fill(Ink.hairline).frame(height: 1).accessibilityHidden(true)
                    SecureField(tr("New password"), text: $new)
                        .frame(minHeight: 44)
                    SecureField(tr("Confirm password"), text: $confirm)
                        .frame(minHeight: 44)
                }
                .paperCard()
                Text(tr("Takes effect right away. What it can skip stays the same."))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if failed {
                    Text(tr("The current password is wrong or a change is already pending."))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(tr("Change now")) {
                    let changed = model.updatePasswordPolicySecretNow(id: id, current: current,
                                                                      newPassword: new)
                    current = ""; new = ""; confirm = ""
                    if changed {
                        dismiss()
                    } else {
                        failed = true
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                }
                .buttonStyle(DemoraPrimaryButtonStyle())
                .disabled(!SkipWayAddPlan.secretChangeIsValid(current: current, new: new, confirm: confirm))
            }
            .padding(DemoraSpace.l)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Change the password"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { current = ""; new = ""; confirm = "" }
    }
}

// MARK: - Change the words

/// New words, kind or mistakes for a phrase: a queued, looser change.
private struct PhraseWordsChangeView: View {
    @Environment(\.dismiss) private var dismiss
    let policy: PhrasePolicy
    @State private var receipt: ChangeReceiptRequest?

    var body: some View {
        PhraseDetailsPage(existing: policy, title: tr("Change the words"), showsChecklist: false) { updated in
            var changed = updated
            changed.allowed = policy.allowed
            receipt = ChangeReceiptRequest(action: .upsertPhrasePolicy(changed))
        }
        .changeReceipt($receipt) { dismiss() }
    }
}
