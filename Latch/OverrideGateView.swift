//
//  OverrideGateView.swift
//  "Apply now" flow for a pending change: pass one of the enabled
//  trusted-contact approval
//  and the change applies immediately, skipping its countdown.
//

import SwiftUI

struct OverrideGateView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let changes: [PendingChange]

    enum Method: String, Identifiable {
        case contacts, password, phrase
        var id: String { rawValue }
    }
    @State private var method: Method?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(changes.count == 1 ? tr("Pending change")
                                            : tr("Pending changes"))
                        .font(.headline)
                    if changes.count == 1, let change = changes.first {
                        Text(change.summary).font(.headline)
                        HStack {
                            Text(tr("Applies in"))
                            Spacer()
                            if model.inTutorial {
                                TutorialCountdownText(
                                    remaining: { model.tutorialRemaining(for: change) ?? 0 })
                                    .foregroundStyle(.secondary)
                            } else if change.isDue {
                                Text(tr("now")).foregroundStyle(.secondary)
                            } else {
                                // Project the TimeGuard-based remaining time onto
                                // the system clock so the countdown matches (and
                                // doesn't flicker) when the clocks disagree.
                                let remaining = max(1, change.appliesAt.timeIntervalSince(TimeGuard.now()))
                                Text(timerInterval: Date.now...Date.now.addingTimeInterval(remaining),
                                     countsDown: true)
                                    .monospacedDigit()
                            }
                        }
                    } else {
                        Text(String(format: tr("%d changes"), changes.count))
                            .font(.headline)
                    }
                }
                .demoraSurface()

                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("Skip the wait")).font(.headline)
                    if model.state.overrides.contactsEnabled
                        && !model.state.overrides.contacts.isEmpty {
                        Button {
                            method = .contacts
                        } label: {
                            Label(tr("Ask a trusted contact"),
                                  systemImage: "person.2")
                        }
                        .tutorialHighlight(model.tutorial == .applyBoth
                                           || model.tutorial == .applyViaContact)
                    }
                    if !model.inTutorial && model.state.overrides.passwordPolicies.contains(where: {
                        policy in changes.allSatisfy { change in
                            guard let area = ChangeEngine.overrideCapability(for: change.action)
                            else { return false }
                            return policy.allowed.contains(area)
                        }
                    }) {
                        Button { method = .password } label: {
                            Label(tr("Enter a password"), systemImage: "key")
                        }
                    }
                    if !model.inTutorial && model.state.overrides.phrasePolicies.contains(where: {
                        policy in changes.allSatisfy { change in
                            guard let area = ChangeEngine.overrideCapability(for: change.action)
                            else { return false }
                            return policy.allowed.contains(area)
                        }
                    }) {
                        Button { method = .phrase } label: {
                            Label(tr("Type a phrase"), systemImage: "text.cursor")
                        }
                    }
                    if model.inTutorial {
                        Text(tr("This time, use your trusted contact — it'll be approved for you."))
                    }
                }
                .demoraSurface()
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Apply now"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close")) { dismiss() }
                }
            }
            .sheet(item: $method) { m in
                switch m {
                case .contacts:
                    if model.inTutorial {
                        TutorialContactGateView(onSuccess: succeed)
                    } else if !changes.isEmpty {
                        ContactGateView(changes: changes,
                                        onSuccess: succeedFromContact)
                    }
                case .password:
                    PasswordChangeGate(changes: changes) {
                        method = nil
                        dismiss()
                    }
                case .phrase:
                    PhraseChangeGate(changes: changes) {
                        method = nil
                        dismiss()
                    }
                }
            }
        }
    }

    private func succeed() {
        model.applyNow(changes)
        method = nil
        dismiss()
    }

    private func succeedFromContact() async {
        model.refreshAfterExternalApply()
        method = nil
        dismiss()
    }
}

struct PhraseChangeGate: View {
    let changes: [PendingChange]
    let onSuccess: () -> Void
    @EnvironmentObject private var model: AppModel
    @State private var selectedID: UUID?
    @State private var attemptID = UUID()
    @State private var failed = false

    private var eligible: [PhrasePolicy] {
        model.state.overrides.phrasePolicies.filter { policy in
            changes.allSatisfy { change in
                guard let area = ChangeEngine.overrideCapability(for: change.action)
                else { return false }
                return policy.allowed.contains(area)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(tr("Choose a phrase that permits every requested change."))
                    ForEach(eligible) { policy in
                        Button {
                            selectedID = policy.id
                            attemptID = UUID()
                            failed = false
                        } label: {
                            Label(policy.name, systemImage: selectedID == policy.id
                                  ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    if let policy = eligible.first(where: { $0.id == selectedID }) {
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
                    }
                    if failed {
                        Text(tr("This change is no longer available. Please try again."))
                            .font(.footnote).foregroundStyle(.red)
                    }
                }
                .demoraSurface().padding(20)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Phrase override"))
            .onAppear { selectedID = eligible.first?.id }
        }
    }
}

struct PasswordChangeGate: View {
    let changes: [PendingChange]
    let onSuccess: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var password = ""
    @State private var working = false
    @State private var failed = false

    private var eligible: [PasswordPolicy] {
        model.state.overrides.passwordPolicies.filter { policy in
            changes.allSatisfy { change in
                guard let area = ChangeEngine.overrideCapability(for: change.action)
                else { return false }
                return policy.allowed.contains(area)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(tr("Choose a password that permits every requested change."))
                    ForEach(eligible) { policy in
                        Button {
                            selectedID = policy.id
                            password = ""
                        } label: {
                            Label(policy.name, systemImage: selectedID == policy.id
                                  ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    SecureField(tr("Password"), text: $password)
                        .textContentType(.password)
                    if failed {
                        Text(tr("Wrong password or this change is no longer available."))
                            .font(.footnote).foregroundStyle(.red)
                    }
                    Button(working ? tr("Checking…") : tr("Apply now")) {
                        guard let selectedID, !working else { return }
                        working = true
                        let hash = AppModel.hash(password)
                        Task {
                            let count = await ChangeEngine.applyNowWithPasswordOffMain(
                                changeIDs: changes.map(\.id), policyID: selectedID,
                                candidateHash: hash)
                            password = ""
                            working = false
                            model.refreshAfterExternalApply()
                            if count == changes.count {
                                dismiss()
                                onSuccess()
                            } else {
                                failed = true
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedID == nil || password.isEmpty || working)
                }
                .demoraSurface().padding(20)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Password override"))
            .onAppear { selectedID = eligible.first?.id }
        }
    }
}

// MARK: - Tutorial contact gate (simulated approval)

/// Stand-in for the real trusted-contact flow during the tutorial: a dummy
/// contact has no real approver, so this shows the request → waiting → approved
/// experience and then succeeds on its own.
struct TutorialContactGateView: View {
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var phase = 0   // 0 ready · 1 waiting · 2 approved

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 48)).foregroundStyle(.tint)
                switch phase {
                case 0:
                    Text(tr("Send a request to Alex (sample). A real contact approves from their own Demora app or with an emailed code."))
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button(tr("Send request")) {
                        phase = 1
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            phase = 2
                            try? await Task.sleep(nanoseconds: 900_000_000)
                            onSuccess()
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                case 1:
                    ProgressView()
                    Text(tr("Waiting for approval…")).foregroundStyle(.secondary)
                default:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40)).foregroundStyle(.green)
                    Text(tr("Approved!")).font(.headline)
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Ask a trusted contact"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phase == 0 {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("Cancel")) { dismiss() }
                    }
                }
            }
        }
    }
}

// MARK: - Math gate

struct MathGateView: View {
    let difficulty: MathDifficulty
    let count: Int
    let wrong: MathWrongBehavior
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    struct Problem {
        let text: String
        let answer: Int

        private static func ipow(_ base: Int, _ exp: Int) -> Int {
            Array(repeating: base, count: exp).reduce(1, *)
        }

        static func random(_ d: MathDifficulty) -> Problem {
            switch d {
            case .elementary:
                // Real arithmetic: multi-digit ± and the times tables.
                switch Int.random(in: 0...2) {
                case 0:
                    let a = Int.random(in: 25...250), b = Int.random(in: 25...250)
                    return Problem(text: "\(a) + \(b)", answer: a + b)
                case 1:
                    let a = Int.random(in: 40...250), b = Int.random(in: 10...a)
                    return Problem(text: "\(a) − \(b)", answer: a - b)
                default:
                    let a = Int.random(in: 2...12), b = Int.random(in: 2...12)
                    return Problem(text: "\(a) × \(b)", answer: a * b)
                }
            case .middle:
                // Multi-digit ×, order of operations, squares, negatives.
                switch Int.random(in: 0...3) {
                case 0:
                    let a = Int.random(in: 12...40), b = Int.random(in: 6...25)
                    return Problem(text: "\(a) × \(b)", answer: a * b)
                case 1:
                    let a = Int.random(in: 3...15), b = Int.random(in: 3...15)
                    let c = Int.random(in: 5...50)
                    return Problem(text: "\(a) × \(b) + \(c)", answer: a * b + c)
                case 2:
                    let a = Int.random(in: 6...25)
                    return Problem(text: "\(a)²", answer: a * a)
                default:
                    let a = Int.random(in: 10...60), b = Int.random(in: 61...140)
                    return Problem(text: "\(a) − \(b)", answer: a - b)   // negative
                }
            case .high:
                // Algebra, powers, roots, parentheses.
                switch Int.random(in: 0...3) {
                case 0:
                    let m = Int.random(in: 3...12), x = Int.random(in: 3...15)
                    let b = Int.random(in: 5...40)
                    return Problem(text: String(format: tr("Solve for x:  %dx + %d = %d"),
                                                m, b, m * x + b), answer: x)
                case 1:
                    let a = Int.random(in: 6...25), b = Int.random(in: 6...25)
                    let c = Int.random(in: 3...9), e = Int.random(in: 15...90)
                    return Problem(text: "(\(a) + \(b)) × \(c) − \(e)",
                                   answer: (a + b) * c - e)
                case 2:
                    let base = Int.random(in: 2...6), exp = Int.random(in: 3...4)
                    return Problem(text: "\(base)^\(exp)", answer: ipow(base, exp))
                default:
                    // ax + b = cx + d  (a > c so x is a positive integer)
                    let x = Int.random(in: 2...12), a = Int.random(in: 4...9)
                    let c = Int.random(in: 1...3), b = Int.random(in: 1...20)
                    let dd = a * x + b - c * x
                    return Problem(text: String(format: tr("Solve for x:  %dx + %d = %dx + %d"),
                                                a, b, c, dd), answer: x)
                }
            case .college:
                // Factorials, multi-step algebra, big products and powers.
                switch Int.random(in: 0...3) {
                case 0:
                    let n = Int.random(in: 4...7)
                    return Problem(text: "\(n)!", answer: (1...n).reduce(1, *))
                case 1:
                    let a = Int.random(in: 11...30), b = Int.random(in: 11...30)
                    let c = Int.random(in: 5...20), e = Int.random(in: 5...20)
                    return Problem(text: "\(a) × \(b) − \(c) × \(e)",
                                   answer: a * b - c * e)
                case 2:
                    let a = Int.random(in: 2...9), x = Int.random(in: 2...12)
                    let b = Int.random(in: 1...10)
                    return Problem(text: String(format: tr("Solve for x:  %d(x + %d) = %d"),
                                                a, b, a * (x + b)), answer: x)
                default:
                    let n = Int.random(in: 6...10)
                    return Problem(text: "2^\(n)", answer: ipow(2, n))
                }
            }
        }
    }

    private var total: Int { max(1, count) }

    @State private var problem: Problem?
    @State private var solved = 0
    @State private var input = ""
    @State private var showWrong = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(String(format: tr("%d of %d solved"), solved, total))
                    .font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(solved), total: Double(total))
                Text(problem?.text ?? "").font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                TextField(tr("Answer"), text: $input)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .font(.title2)
                if showWrong {
                    Text(wrongMessage).foregroundStyle(.red).font(.footnote)
                        .multilineTextAlignment(.center)
                }
                Button(tr("Submit")) { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(input.isEmpty)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Math override"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { dismiss() }
                }
            }
            .onAppear { problem = .random(difficulty) }
        }
    }

    private var wrongMessage: String {
        switch wrong {
        case .nothing:   return tr("Wrong — here's a new problem.")
        case .removeOne: return tr("Wrong — you lost one correct answer.")
        case .restart:   return tr("Wrong — starting over.")
        }
    }

    private func submit() {
        guard let p = problem else { return }
        // Accept a leading minus / whitespace from the punctuation keyboard.
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        if Int(trimmed) == p.answer {
            showWrong = false
            solved += 1
            if solved >= total {
                onSuccess()
                dismiss()
            } else {
                problem = .random(difficulty)
            }
        } else {
            showWrong = true
            switch wrong {
            case .nothing:   break
            case .removeOne: solved = max(0, solved - 1)
            case .restart:   solved = 0
            }
            problem = .random(difficulty)
        }
        input = ""
    }
}

// MARK: - Password gate

struct PasswordGateView: View {
    let hash: String
    let onSuccess: () -> Void
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var wrong = false
    @State private var wrongCount = 0
    @State private var lockedUntil: Date?

    // Throttle guessing: every 5 wrong tries locks the button for a growing
    // cooldown (uses network-anchored time so the clock can't be set back).
    private var isLocked: Bool {
        if let until = lockedUntil { return TimeGuard.now() < until }
        return false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "key.fill").font(.system(size: 48))
                    .foregroundStyle(.tint)
                if model.inTutorial {
                    Text(tr("For the tutorial, the password is: test"))
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                SecureField(tr("Password"), text: $input)
                    .textFieldStyle(.roundedBorder)
                if isLocked {
                    Text(tr("Too many attempts — wait a moment and try again."))
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if wrong {
                    Text(tr("Incorrect password")).foregroundStyle(.red)
                        .font(.footnote)
                }
                Button(tr("Unlock")) {
                    guard !isLocked else { return }
                    if AppModel.hash(input) == hash {
                        onSuccess()
                        dismiss()
                    } else {
                        wrong = true
                        input = ""
                        wrongCount += 1
                        if wrongCount % 5 == 0 {   // cooldown grows each streak
                            lockedUntil = TimeGuard.now()
                                .addingTimeInterval(TimeInterval(30 * (wrongCount / 5)))
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(input.isEmpty || isLocked)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Password override"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel")) { dismiss() }
                }
            }
        }
    }
}
