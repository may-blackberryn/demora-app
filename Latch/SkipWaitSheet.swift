//
//  SkipWaitSheet.swift
//  Skip the wait (docs/you-redesign.md §5.13, Y4): one sheet with its own
//  stack that says what is being skipped and lists only the ways allowed to
//  skip it; one usable way opens directly. Replaces the Apply now gate and
//  its stacked contact, password and phrase sheets, and the extra-time gates.
//
//  The checks underneath are the existing ones, moved here unchanged: the
//  contact request/poll/verify flow, the hashed password check off the main
//  thread and the word-by-word phrase challenge. The engine re-checks every
//  permission when a way is used.
//

import SwiftUI
import UIKit

/// What the sheet skips.
enum SkipWaitTarget: Identifiable {
    /// Apply now (one change) or the bulk bar (several).
    case changes([PendingChange])
    /// A limit's next extra-time use that asks a contact. Reopens a sent request.
    case extraContact(ExtraContactContext)
    /// A limit's next extra-time use that asks for its password or phrase.
    case extraPassword(ExtraTimeUse)
    case extraPhrase(ExtraTimeUse)

    var id: String {
        switch self {
        case .changes(let changes): return "changes-" + changes.map(\.id.uuidString).joined()
        case .extraContact(let context): return "contact-" + context.requestID
        case .extraPassword(let use): return "password-\(use.limitID)-\(use.stepIndex)"
        case .extraPhrase(let use): return "phrase-\(use.limitID)-\(use.stepIndex)"
        }
    }
}

/// The extra-time use a password or phrase step is for, read when the row
/// was tapped (an event), for the header and the step's title.
struct ExtraTimeUse: Equatable {
    let limitID: UUID
    let limitName: String
    let stepIndex: Int
    let minutes: Int
    let policyName: String?

    init?(limit: AppLimit, remaining: Int, policies: OverridesConfig) {
        guard let steps = limit.extraTime?.effectiveSteps,
              steps.indices.contains(steps.count - remaining) else { return nil }
        let index = steps.count - remaining
        let step = steps[index]
        limitID = limit.id
        limitName = limit.name
        stepIndex = index
        minutes = step.minutes
        if let id = step.passwordPolicyID {
            policyName = policies.passwordPolicies.first { $0.id == id }?.name
        } else if let id = step.phrasePolicyID {
            policyName = policies.phrasePolicies.first { $0.id == id }?.name
        } else {
            policyName = nil
        }
    }
}

extension View {
    /// Shows Skip the wait for `target`. `onDismiss` runs when it closes, so
    /// a caller can reload its sent requests.
    func skipWaitSheet(_ target: Binding<SkipWaitTarget?>,
                       onDismiss: @escaping () -> Void = {}) -> some View {
        modifier(SkipWaitPresenter(target: target, onDismiss: onDismiss))
    }
}

private struct SkipWaitPresenter: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @Binding var target: SkipWaitTarget?
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.sheet(item: $target, onDismiss: onDismiss) { target in
            SkipWaitSheet(target: target, plan: plan(for: target))
        }
    }

    /// Decided once, when the sheet opens, so the steps don't jump while a
    /// change lands or a contact's state refreshes underneath.
    private func plan(for target: SkipWaitTarget) -> SkipWaitPlan {
        let email = EmailCodeService.isConfigured
        switch target {
        case .changes(let changes):
            let ways = SkipWayEligibility.ways(for: changes, overrides: model.state.overrides,
                                               unavailableCodes: model.unavailableContactCodes,
                                               emailAvailable: email)
            let requestID = changes.first?.id.uuidString ?? ""
            let sent = !requestID.isEmpty
                && (ContactsRelay.wasSentEmail(requestID) || ContactsRelay.wasSentRelay(requestID))
            return SkipWaitPlan(ways: ways, start: SkipWayStart.initial(ways, requestSent: sent))
        case .extraContact(let context):
            let ways = SkipWayEligibility.extraTimeContacts(
                overrides: model.state.overrides, unavailableCodes: model.unavailableContactCodes,
                emailAvailable: email)
            let usable = Set(ways.filter { $0.unavailable == nil }.map(\.id))
            // A sent request always reopens on its status, even if contacts
            // were paused since; otherwise there must be someone to ask.
            let sent = ContactsRelay.wasSentEmail(context.requestID)
                || ContactsRelay.wasSentRelay(context.requestID)
            return SkipWaitPlan(ways: ways, start: sent || !ways.isEmpty
                                ? .contactRequest(selected: usable) : .none)
        case .extraPassword, .extraPhrase:
            // The step names its method; the engine checks the step's own policy.
            return SkipWaitPlan(ways: [], start: .menu)
        }
    }
}

struct SkipWaitPlan {
    let ways: [EligibleWay]
    let start: SkipWayStart
}

/// Steps pushed inside the sheet.
private enum SkipWaitStep: Hashable {
    case contact(Set<UUID>)
    case password(UUID)
    case phrase(UUID)
}

struct SkipWaitSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let target: SkipWaitTarget
    let plan: SkipWaitPlan
    @State private var path: [SkipWaitStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: SkipWaitStep.self) { step in
                    stepView(step)
                }
        }
        .presentationDetents([.medium, .large])
        .background(Ink.cardRaised.ignoresSafeArea())
    }

    private var changes: [PendingChange] {
        if case .changes(let changes) = target { return changes }
        return []
    }

    // MARK: Root: the step itself when there is only one, else the menu

    @ViewBuilder private var root: some View {
        switch target {
        case .changes:
            switch plan.start {
            case .contactRequest(let selected): stepView(.contact(selected))
            case .way(let way): stepView(step(for: way))
            case .menu: menu
            case .none: noneEligible
            }
        case .extraContact:
            if case .contactRequest(let selected) = plan.start {
                stepView(.contact(selected))
            } else {
                noneEligible
            }
        case .extraPassword(let use):
            SkipWaitPage(header: header, title: use.policyName ?? tr("Password"), close: close) {
                PasswordSkipStep(extraTime: use, changes: [], policyID: nil, onSuccess: succeed)
            }
        case .extraPhrase(let use):
            SkipWaitPage(header: header, title: use.policyName ?? tr("Phrase"), close: close) {
                ExtraTimePhraseStep(limitID: use.limitID, onSuccess: succeed)
            }
        }
    }

    private func step(for way: SkipWay) -> SkipWaitStep {
        switch way {
        case .contact(let contact): return .contact([contact.id])
        case .password(let policy): return .password(policy.id)
        case .phrase(let policy): return .phrase(policy.id)
        }
    }

    @ViewBuilder private func stepView(_ step: SkipWaitStep) -> some View {
        switch step {
        case .contact(let selected):
            let contacts = plan.ways.compactMap { way -> (TrustedContact, Bool)? in
                if case .contact(let contact) = way.way { return (contact, way.unavailable == nil) }
                return nil
            }
            SkipWaitPage(header: header, title: tr("Ask a trusted contact"), close: close) {
                ContactRequestStep(changes: changes, extraContext: extraContext,
                                   contacts: contacts, initiallySelected: selected,
                                   close: close, onSuccess: succeedFromContact)
            }
        case .password(let id):
            let policy = plan.ways.lazy.compactMap { way -> PasswordPolicy? in
                if case .password(let policy) = way.way, policy.id == id { return policy }
                return nil
            }.first
            SkipWaitPage(header: header, title: policy?.name ?? tr("Password"), close: close) {
                PasswordSkipStep(extraTime: nil, changes: changes, policyID: id, onSuccess: succeed)
            }
        case .phrase(let id):
            let policy = plan.ways.lazy.compactMap { way -> PhrasePolicy? in
                if case .phrase(let policy) = way.way, policy.id == id { return policy }
                return nil
            }.first
            SkipWaitPage(header: header, title: policy?.name ?? tr("Phrase"), close: close) {
                if let policy {
                    PhraseSkipStep(policy: policy, changes: changes, onSuccess: succeed)
                }
            }
        }
    }

    private var extraContext: ExtraContactContext? {
        if case .extraContact(let context) = target { return context }
        return nil
    }

    private var menu: some View {
        SkipWaitPage(header: header, title: tr("Skip the wait"), close: close) {
            VStack(alignment: .leading, spacing: DemoraSpace.s) {
                SectionHeader(tr("Who or what can skip it"))
                VStack(spacing: 0) {
                    ForEach(Array(plan.ways.enumerated()), id: \.element.id) { index, way in
                        if index > 0 { YouRowDivider() }
                        SkipWayChoiceRow(way: way) { path.append(step(for: way.way)) }
                    }
                }
                .paperCard(padding: 0)
                Text(tr("Only ways allowed to skip this change are listed."))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noneEligible: some View {
        SkipWaitPage(header: header, title: tr("Skip the wait"), close: close) {
            VStack(alignment: .leading, spacing: DemoraSpace.s) {
                Text(tr("None of your ways can skip this change."))
                    .demoraType(.body)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                SectionHeaderLink(title: tr("Ways to skip a wait")) {
                    model.youPath = []
                    model.selectedTab = YouInvites.youTab
                    close()
                }
            }
        }
    }

    private var header: SkipWaitHeader {
        switch target {
        case .changes(let changes): return SkipWaitHeader(content: .changes(changes))
        case .extraContact(let context):
            return SkipWaitHeader(content: .extraTime(name: context.limitName, minutes: context.step.minutes))
        case .extraPassword(let use), .extraPhrase(let use):
            return SkipWaitHeader(content: .extraTime(name: use.limitName, minutes: use.minutes))
        }
    }

    // MARK: Endings

    private func close() { dismiss() }

    private func succeed() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func succeedFromContact() async {
        if extraContext != nil { model.tick() } else { model.refreshAfterExternalApply() }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Page frame: pinned header, scrolling step

private struct SkipWaitPage<Content: View>: View {
    let header: SkipWaitHeader
    let title: String
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, DemoraSpace.l)
                .padding(.top, DemoraSpace.s)
                .padding(.bottom, DemoraSpace.s)
            DashedRule()
                .padding(.horizontal, DemoraSpace.l)
            ScrollView {
                content()
                    .padding(DemoraSpace.l)
                    .frame(maxWidth: DemoraSpace.maxContentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Ink.cardRaised.ignoresSafeArea())
        .casedNavigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(tr("Close"), action: close)
            }
        }
    }
}

private struct DashedRule: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geometry.size.width, y: 0.5))
            }
            .stroke(Ink.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}

/// What is being skipped. Read first by VoiceOver.
struct SkipWaitHeader: View {
    enum Content {
        case changes([PendingChange])
        case extraTime(name: String, minutes: Int)
    }

    @Environment(\.locale) private var locale
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            switch content {
            case .changes(let changes):
                if changes.count == 1, let change = changes.first {
                    StateChip(kind: change.direction == .stricter ? .active : .loosening,
                              text: tr(change.direction == .stricter ? "Stricter" : "Looser"))
                    Text(change.summary)
                        .demoraType(.cardTitle)
                        .foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    landing(change.appliesAt)
                } else {
                    Text(String(format: tr("%d changes"), changes.count))
                        .demoraType(.cardTitle)
                        .foregroundStyle(Ink.ink)
                    Text(changes.map(\.summary).joined(separator: " · "))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .lineLimit(3)
                    if let latest = changes.map(\.appliesAt).max() { landing(latest) }
                }
            case .extraTime(let name, let minutes):
                Text([tr("Extra time"), name, String(format: tr("+%d min"), minutes)]
                    .joined(separator: " · "))
                    .demoraType(.cardTitle)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilitySortPriority(1)
    }

    private func landing(_ date: Date) -> some View {
        var calendar = Calendar.current
        calendar.locale = locale
        return HStack(spacing: DemoraSpace.xxs) {
            Text(String(format: tr("Lands %@ · in"),
                        TodayTimeText.short(date, now: Date(), calendar: calendar, locale: locale)))
            CountdownText(to: date, style: nil).monospacedDigit()
        }
        .demoraType(.meta)
        .foregroundStyle(Ink.inkSoft)
    }
}

/// One eligible way in the menu.
private struct SkipWayChoiceRow: View {
    @EnvironmentObject private var model: AppModel
    let way: EligibleWay
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DemoraSpace.s) {
                leading
                VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                    Text(name).demoraType(.cardTitle).foregroundStyle(Ink.ink)
                    Text(detail)
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DemoraSpace.xs)
                if way.unavailable == nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ink.inkSoft)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DemoraSpace.cardPadding)
            .padding(.vertical, DemoraSpace.s)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(way.unavailable != nil)
        .opacity(way.unavailable == nil ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }

    private var name: String {
        switch way.way {
        case .contact(let contact):
            if let code = contact.latchUserCode {
                return resolvedName(forCode: code, model: model, fallback: contact.name)
            }
            return contact.name
        case .password(let policy): return policy.name
        case .phrase(let policy): return policy.name
        }
    }

    private var detail: String {
        switch way.unavailable {
        case .cantReach: return tr("Can't reach right now")
        case .emailNotAvailable: return tr("Email approvals aren't available in this version")
        case nil: break
        }
        switch way.way {
        case .contact(let contact):
            return contact.isEmail ? tr("gets an email code") : tr("asks in their Demora app")
        case .password: return tr("Type the password")
        case .phrase(let policy):
            return String(format: tr("%d words, typed one by one"), policy.kind.wordCount)
        }
    }

    @ViewBuilder private var leading: some View {
        switch way.way {
        case .contact(let contact):
            ContactAvatarView(avatar: contact.latchUserCode.flatMap {
                resolvedAvatar(forCode: $0, model: model)
            } ?? contact.avatar, size: 36)
        case .password: SkipWaySymbol(symbol: "key")
        case .phrase: SkipWaySymbol(symbol: "text.quote")
        }
    }
}

// MARK: - Password (unchanged check: hash, apply off main, field cleared)

private struct PasswordSkipStep: View {
    @EnvironmentObject private var model: AppModel
    /// Extra time checks the step's own password; otherwise `policyID`.
    let extraTime: ExtraTimeUse?
    let changes: [PendingChange]
    let policyID: UUID?
    let onSuccess: () -> Void
    @State private var password = ""
    @State private var working = false
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.m) {
            SecureField(tr("Password"), text: $password)
                .textContentType(.password)
                .focused($focused)
                .frame(minHeight: 44)
                .padding(.horizontal, DemoraSpace.s)
                .background(Ink.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Ink.hairline, lineWidth: 1))
                .onSubmit(submit)
            if failed {
                Text(extraTime == nil
                     ? tr("That password doesn't match, or this change is no longer waiting.")
                     : tr("Wrong password or this extra-time use is no longer available."))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(working ? tr("Checking…") : (extraTime == nil ? tr("Skip the wait") : tr("Get extra time")),
                   action: submit)
                .buttonStyle(DemoraPrimaryButtonStyle())
                .disabled(password.isEmpty || working || (extraTime == nil && policyID == nil))
        }
        .onAppear { focused = true }
    }

    private func submit() {
        guard !working, !password.isEmpty else { return }
        working = true
        let hash = AppModel.hash(password)
        Task {
            let ok: Bool
            if let extraTime {
                ok = await ChangeEngine.requestExtraTimeOffMain(
                    limitID: extraTime.limitID, candidateHash: hash)
                model.tick()
            } else if let policyID {
                let count = await ChangeEngine.applyNowWithPasswordOffMain(
                    changeIDs: changes.map(\.id), policyID: policyID, candidateHash: hash)
                model.refreshAfterExternalApply()
                ok = count == changes.count
            } else {
                ok = false
            }
            password = ""
            working = false
            if ok {
                onSuccess()
            } else {
                failed = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

// MARK: - Phrase (unchanged challenge: word by word, no paste, nothing stored)

private struct PhraseSkipStep: View {
    @EnvironmentObject private var model: AppModel
    let policy: PhrasePolicy
    let changes: [PendingChange]
    let onSuccess: () -> Void
    @State private var attemptID = UUID()
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.m) {
            PhraseEntry(policy: policy,
                        scope: .changes(changes.map(\.id).sorted {
                            $0.uuidString < $1.uuidString
                        })) { proofID in
                Task {
                    let count = await ChangeEngine.applyNowWithPhraseOffMain(
                        changeIDs: changes.map(\.id), policyID: policy.id,
                        proofID: proofID)
                    model.refreshAfterExternalApply()
                    if count == changes.count {
                        onSuccess()
                    } else {
                        failed = true
                        attemptID = UUID()
                    }
                }
            }
            .id(attemptID)
            if failed {
                Text(tr("This change is no longer available. Please try again."))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.danger)
            }
        }
    }
}

private struct ExtraTimePhraseStep: View {
    @EnvironmentObject private var model: AppModel
    let limitID: UUID
    let onSuccess: () -> Void
    @State private var attemptID = UUID()
    @State private var failed = false

    private var nextStep: (policy: PhrasePolicy, index: Int)? {
        guard let limit = model.state.limits.first(where: { $0.id == limitID }),
              let steps = limit.extraTime?.effectiveSteps,
              case .ready(let remaining) = LimitFeatures.extraTimeState(for: limit),
              steps.indices.contains(steps.count - remaining),
              let id = steps[steps.count - remaining].phrasePolicyID,
              let policy = model.state.overrides.phrasePolicies.first(where: {
                  $0.id == id && $0.allowed.contains(.extraTime)
              }) else { return nil }
        return (policy, steps.count - remaining)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.m) {
            if let nextStep {
                Text(tr("Type every word to receive this use of extra time."))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                PhraseEntry(policy: nextStep.policy,
                            scope: .extraTime(
                                limitID: limitID,
                                day: SharedStore.dayKey(for: TimeGuard.now()),
                                step: nextStep.index)) { proofID in
                    Task {
                        let started = await ChangeEngine.requestExtraTimeOffMain(
                            limitID: limitID, phraseProofID: proofID)
                        model.tick()
                        if started {
                            onSuccess()
                        } else {
                            failed = true
                            attemptID = UUID()
                        }
                    }
                }
                .id(attemptID)
            } else {
                Text(tr("This extra-time use is no longer available."))
                    .demoraType(.body)
                    .foregroundStyle(Ink.ink)
            }
            if failed {
                Text(tr("Extra time could not be started safely. Your limit is still in place; try again later."))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Contact request (the ContactGateView flow, unchanged underneath)

private struct ContactRequestStep: View {
    let changes: [PendingChange]
    let extraContext: ExtraContactContext?
    /// Eligible contacts and whether each can be asked right now.
    let contacts: [(TrustedContact, Bool)]
    let initiallySelected: Set<UUID>
    let close: () -> Void
    let onSuccess: () async -> Void

    @AppAccent private var accent
    @EnvironmentObject var model: AppModel

    /// One request id covers the whole group (the first change's id).
    private var reqId: String {
        extraContext?.requestID ?? changes.first?.id.uuidString ?? ""
    }

    /// What the contact is asked to approve — every change, not just the first.
    private var combinedSummary: String {
        if let extraContext {
            return String(format: tr("Extra time for %@: %d usage minutes"),
                          extraContext.limitName, extraContext.step.minutes)
        }
        return changes.count == 1
            ? (changes.first?.summary ?? "")
            : String(format: tr("%d changes: %@"), changes.count,
                     changes.map(\.summary).joined(separator: " • "))
    }

    @State private var selected: Set<UUID> = []
    @State private var message = ""
    @State private var sent = false
    @State private var sending = false
    @State private var codeInput = ""
    @State private var verifying = false
    @State private var error: String?
    @State private var pollTask: Task<Void, Never>?

    @State private var emailSent = false
    @State private var latchSent = false
    @State private var deniedDetected = false
    @State private var usage: EmailCodeService.Usage?

    private var usable: [TrustedContact] { contacts.filter(\.1).map(\.0) }
    private var selectedContacts: [TrustedContact] {
        usable.filter { selected.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.l) {
            if !sent {
                choose
            } else {
                waiting
            }
            if let error {
                Text(error)
                    .demoraType(.meta)
                    .foregroundStyle(Ink.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            selected = initiallySelected.intersection(Set(usable.map(\.id)))
            // Resume a request sent earlier (sheet was closed meanwhile).
            let requestId = reqId
            emailSent = ContactsRelay.wasSentEmail(requestId)
            latchSent = ContactsRelay.wasSentRelay(requestId)
            if emailSent || latchSent { sent = true }
            if latchSent { startPolling(requestId: requestId) }
        }
        .task {
            if EmailCodeService.isConfigured {
                usage = try? await EmailCodeService.usage()
            }
        }
        .onDisappear { pollTask?.cancel() }
    }

    // Step 1: who to ask, an optional message, Send request.
    private var choose: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.m) {
            VStack(spacing: 0) {
                ForEach(Array(contacts.enumerated()), id: \.element.0.id) { index, item in
                    if index > 0 { YouRowDivider() }
                    contactRow(item.0, usable: item.1)
                }
            }
            .paperCard(padding: 0)
            Text(tr("Any one approval is enough."))
                .demoraType(.meta)
                .foregroundStyle(Ink.inkSoft)
            TextField(tr("Why you're asking — they'll see it"), text: $message, axis: .vertical)
                .lineLimit(2...4)
                .padding(DemoraSpace.s)
                .background(Ink.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Ink.hairline, lineWidth: 1))
            if let u = usage, selectedContacts.contains(where: \.isEmail) {
                EmailUsageBars(usage: u)
            }
            Button(sending ? tr("Sending…") : tr("Send request")) {
                Task { await send() }
            }
            .buttonStyle(DemoraPrimaryButtonStyle())
            .disabled(selected.isEmpty || sending)
        }
    }

    private func contactRow(_ contact: TrustedContact, usable: Bool) -> some View {
        let isOn = selected.contains(contact.id)
        return Button {
            if isOn { selected.remove(contact.id) } else { selected.insert(contact.id) }
        } label: {
            HStack(spacing: DemoraSpace.s) {
                ContactAvatarView(avatar: contact.latchUserCode.flatMap {
                    resolvedAvatar(forCode: $0, model: model)
                } ?? contact.avatar, size: 36)
                VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
                    Text(contact.latchUserCode.map {
                        resolvedName(forCode: $0, model: model, fallback: contact.name)
                    } ?? contact.name)
                        .demoraType(.cardTitle).foregroundStyle(Ink.ink)
                    Text(usable ? (contact.isEmail ? tr("gets an email code") : tr("asks in their Demora app"))
                         : (contact.isEmail ? tr("Email approvals aren't available in this version")
                                            : tr("Can't reach right now")))
                        .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                }
                Spacer(minLength: DemoraSpace.xs)
                if usable {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DemoraSpace.cardPadding)
            .padding(.vertical, DemoraSpace.s)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!usable)
        .opacity(usable ? 1 : 0.6)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    // Step 2: status, the email code, Ask again.
    private var waiting: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.m) {
            if latchSent {
                VStack(alignment: .leading, spacing: DemoraSpace.xs) {
                    if deniedDetected {
                        Label(tr("Denied"), systemImage: "hand.raised")
                            .demoraType(.body)
                            .foregroundStyle(Ink.danger)
                    } else {
                        HStack(spacing: DemoraSpace.xs) {
                            ProgressView()
                            Text(tr("Sent · waiting")).demoraType(.body).foregroundStyle(Ink.ink)
                        }
                        Text(tr("Checks automatically every few seconds. The request expires after 1 hour."))
                            .demoraType(.meta)
                            .foregroundStyle(Ink.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .paperCard()
            }
            if emailSent {
                VStack(alignment: .leading, spacing: DemoraSpace.s) {
                    Text(emailPrompt)
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField(tr("6-digit code"), text: $codeInput)
                        .keyboardType(.numberPad)
                        .font(.title2.monospaced())
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 44)
                    Button(verifying ? tr("Checking…") : tr("Verify code")) {
                        Task { await verifyCode() }
                    }
                    .buttonStyle(DemoraPrimaryButtonStyle())
                    .disabled(codeInput.count != 6 || verifying)
                }
                .paperCard()
            }
            Button(extraContext == nil ? tr("Ask again") : tr("Cancel and start again")) {
                Task { await startOver() }
            }
            .buttonStyle(.plain)
            .font(DemoraType.button)
            .foregroundStyle(Ink.inkSoft)
            .frame(minHeight: 44)
            Text(extraContext == nil
                 ? tr("Cancels this request and lets you pick contacts again.")
                 : tr("Cancel this request, then reopen extra time to choose contacts again."))
                .demoraType(.meta)
                .foregroundStyle(Ink.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Enter the code Sam received…" when the one email contact is known.
    private var emailPrompt: String {
        let emails = selectedContacts.filter(\.isEmail)
        if emails.count == 1, let name = emails.first?.name, !name.isEmpty {
            return String(format: tr("Enter the code %@ received. It expires in 15 minutes."), name)
        }
        return tr("Your contact received a code by email. Enter it here. It expires in 15 minutes.")
    }

    private func send() async {
        sending = true
        defer { sending = false }
        error = nil
        if extraContext != nil && !model.state.overrides.contactsEnabled {
            error = tr("Trusted-contact approvals are turned off.")
            return
        }
        if let extraContext {
            guard extraContext.day == SharedStore.dayKey(for: TimeGuard.now()),
                  let limit = SharedStore.loadState().limits.first(where: {
                      $0.id == extraContext.limitID
                  }),
                  let steps = limit.extraTime?.effectiveSteps,
                  steps.indices.contains(extraContext.stepIndex),
                  steps[extraContext.stepIndex] == extraContext.step,
                  case .ready(let remaining) = LimitFeatures.extraTimeState(for: limit),
                  extraContext.stepIndex == steps.count - remaining,
                  ContactsRelay.pendingExtraRequest(for: extraContext.limitID) == nil else {
                error = tr("This extra-time use is no longer available.")
                return
            }
        }
        let requestId = reqId
        let recipients = selectedContacts
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullSummary = trimmed.isEmpty
            ? combinedSummary
            : String(format: tr("%@ — Note: %@"), combinedSummary, trimmed)
        var emailOK = false
        var codesOK = false
        do {
            let emails: [String] = recipients.compactMap {
                if case .email(let address) = $0.kind { return address }
                return nil
            }
            let codes: [String] = recipients.compactMap {
                if case .latchUser(let code) = $0.kind { return code }
                return nil
            }
            if !emails.isEmpty {
                try await EmailCodeService.requestCode(
                    requestId: requestId, emails: emails,
                    summary: fullSummary)
                ContactsRelay.markSent(requestId: requestId, relay: false)
                emailSent = true
                emailOK = true
                usage = try? await EmailCodeService.usage()
            }
            if !codes.isEmpty {
                await ContactsRelay.registerSelfIfNeeded()
                try await ContactsRelay.sendRequests(
                    requestId: requestId, approverCodes: codes,
                    summary: fullSummary)
                ContactsRelay.markSent(requestId: requestId, relay: true)
                latchSent = true
                codesOK = true
                startPolling(requestId: requestId)
            }
        } catch EmailCodeError.rateLimited(let global) {
            self.error = global
                ? tr("Approval emails are at capacity right now. Try again later, or use a Demora contact.")
                : tr("You've used all of today's approval emails. Try again tomorrow.")
            // Refresh so the bars and the upgrade prompt reflect the limit.
            usage = try? await EmailCodeService.usage()
        } catch {
            self.error = tr("Couldn't send the request — check your connection and try again.")
        }
        // Record whatever actually went out — even on a partial failure — so
        // the ledger's "Waiting for…" matches reality.
        if emailOK || codesOK {
            let emailIDs = emailOK ? recipients.filter(\.isEmail).map(\.id) : []
            let relayIDs = codesOK ? recipients.filter {
                $0.latchUserCode != nil
            }.map(\.id) : []
            if let extraContext {
                ContactsRelay.recordOutgoingExtra(extraContext,
                                                  email: emailOK, relay: codesOK,
                                                  emailContactIDs: emailIDs,
                                                  relayContactIDs: relayIDs)
            } else {
                ContactsRelay.recordOutgoing(requestId: requestId,
                                             changeIds: changes.map(\.id),
                                             email: emailOK, relay: codesOK,
                                             emailContactIDs: emailIDs,
                                             relayContactIDs: relayIDs)
            }
            sent = true
        }
    }

    private func verifyCode() async {
        verifying = true
        defer { verifying = false }
        do {
            if try await EmailCodeService.verify(
                requestId: reqId, code: codeInput) {
                await finish()
            } else {
                error = tr("Wrong or expired code.")
                codeInput = ""
            }
        } catch {
            self.error = tr("Couldn't check the code — check your connection and try again.")
        }
    }

    private func startPolling(requestId: String) {
        let since = ContactsRelay.relaySentDate(requestId) ?? .distantPast
        pollTask = Task {
            while !Task.isCancelled {
                if let decisions = try? await ContactsRelay.decisions(
                    requestId: requestId, since: since) {
                    if decisions.approved {
                        await finish(relayApproved: true)
                        return
                    }
                    if decisions.denied {
                        await MainActor.run { deniedDetected = true }
                        // Keep polling: another chosen contact may approve.
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Abandon the current request (e.g. after a denial) and start fresh.
    @MainActor
    private func startOver() async {
        pollTask?.cancel()
        let requestId = reqId
        ContactsRelay.clearSent(requestId)
        ContactsRelay.clearOutgoing(requestId)
        await ContactsRelay.cleanup(requestId: requestId)
        sent = false
        emailSent = false
        latchSent = false
        deniedDetected = false
        error = nil
        codeInput = ""
        if extraContext != nil { close() }
    }

    @MainActor
    private func finish(relayApproved: Bool = false) async {
        pollTask?.cancel()
        if relayApproved {
            _ = await ContactsRelay.applyKnownApproval(requestId: reqId)
            guard requestWasApplied else {
                error = approvalError
                return
            }
            await onSuccess()
        } else {
            // Verification proves the code, but current per-contact scopes
            // are checked again on the serialized application queue.
            _ = await ContactsRelay.consumeVerifiedEmailRequest(requestId: reqId)
            guard requestWasApplied else {
                error = approvalError
                return
            }
            await onSuccess()
        }
        close()
    }

    private var requestWasApplied: Bool {
        if let extraContext {
            return extraContext.day == SharedStore.dayKey(for: TimeGuard.now())
                && LimitFeatures.extraRequestCount(for: extraContext.limitID)
                    > extraContext.stepIndex
        }
        let remaining = Set(SharedStore.loadState().pending.map(\.id))
        return !changes.isEmpty && changes.allSatisfy { !remaining.contains($0.id) }
    }

    private var approvalError: String {
        extraContext == nil
            ? tr("This contact can no longer approve these changes. Send a new request.")
            : tr("This contact approval could not grant extra time. Cancel and try again.")
    }
}
