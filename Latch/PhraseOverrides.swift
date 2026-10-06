import SwiftUI
import UIKit

struct PhrasePoliciesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("Each phrase can unlock only the changes you choose. Adding or changing one waits through your less-strict delay."))
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(model.state.overrides.phrasePolicies) { policy in
                    NavigationLink { PhrasePolicyEditor(existing: policy) } label: {
                        GridCard(symbol: "text.cursor", title: policy.name,
                                 subtitle: policy.allowed.map(\.label).sorted().joined(separator: " · "))
                    }
                }
                NavigationLink { PhrasePolicyEditor(existing: nil) } label: {
                    Label(tr("Add phrase"), systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .demoraSurface()
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Phrases"))
    }
}

struct PhrasePolicyEditor: View {
    let existing: PhrasePolicy?
    /// Staging a migration replacement uses the same editor, but does not
    /// write to the store. The welcome commits the complete batch once.
    var onStage: ((PhrasePolicy) -> Void)? = nil
    var isDemo = false
    /// Migration replacements cannot gain new extra-time permissions. Fresh
    /// setup can choose them, without changing the migration editor's default.
    var allowsExtraTimeWhenStaging = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftID = UUID()
    @State private var name = ""
    @State private var isRandom = true
    @State private var randomCount = 50
    @State private var customText = ""
    @State private var errorAllowance = 0 // -1 means unlimited
    @State private var allowed: Set<OverrideCapability> = []
    @State private var loaded = false

    private var policy: PhrasePolicy {
        PhrasePolicy(id: existing?.id ?? draftID, name: name,
                     kind: isRandom ? .random(randomCount) : .custom(customText),
                     allowedErrors: errorAllowance < 0 ? nil : errorAllowance,
                     allowed: allowed)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                #if DEBUG
                if isDemo { DeveloperDemoNotice() }
                #endif
                TextField(tr("Name"), text: $name)
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
                } else {
                    Text(tr("The exact custom phrase is saved on this device. Choose something you would not type impulsively."))
                        .font(.footnote).foregroundStyle(.secondary)
                    TextEditor(text: $customText)
                        .frame(minHeight: 100)
                }
                Picker(tr("Wrong words before reset"), selection: $errorAllowance) {
                    ForEach([0, 1, 5, 10, -1], id: \.self) { count in
                        Text(count < 0 ? tr("Unlimited") : "\(count)").tag(count)
                    }
                }
                Text(tr("Allowed uses")).font(.headline)
                ForEach(OverrideCapability.allCases.filter {
                    onStage == nil || allowsExtraTimeWhenStaging || $0 != .extraTime
                }) { area in
                    Toggle(area.label, isOn: Binding(
                        get: { allowed.contains(area) },
                        set: { enabled in
                            if enabled { allowed.insert(area) }
                            else { allowed.remove(area) }
                        }))
                }
                Button(onStage == nil ? tr("Queue change") : tr("Add phrase")) {
                    if let onStage {
                        onStage(policy)
                        dismiss()
                    } else if model.queue(.upsertPhrasePolicy(policy)) != nil { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!PhraseWords.isValid(policy) || policy == existing)
                if let existing, onStage == nil {
                    Button(tr("Remove phrase"), role: .destructive) {
                        if model.queue(.removePhrasePolicy(id: existing.id)) != nil {
                            dismiss()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .demoraSurface()
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(existing == nil ? tr("Add phrase") : tr("Edit phrase"))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = existing?.name ?? ""
            allowed = existing?.allowed ?? []
            errorAllowance = existing?.allowedErrors ?? -1
            if let existing {
                switch existing.kind {
                case .custom(let text): isRandom = false; customText = text
                case .random(let count): isRandom = true; randomCount = count
                }
            } else {
                errorAllowance = 0
            }
        }
    }
}

struct ExtraTimePhraseGate: View {
    let limitID: UUID
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let nextStep {
                        Text(tr("Type every word to receive this use of extra time."))
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
                                    dismiss()
                                } else {
                                    failed = true
                                    attemptID = UUID()
                                }
                            }
                        }
                        .id(attemptID)
                    } else {
                        Text(tr("This extra-time use is no longer available."))
                    }
                    if failed {
                        Text(tr("Extra time could not be started safely. Your limit is still in place; try again later."))
                            .font(.footnote).foregroundStyle(.red)
                    }
                }
                .demoraSurface().padding(20)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Extra time"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close")) { dismiss() }
                }
            }
        }
    }
}

/// A word-at-a-time challenge. Long random phrases are shown in 20-word
/// pages; they never leave memory or touch the trusted-contact server.
struct PhraseEntry: View {
    @AppAccent private var accent
    let policy: PhrasePolicy
    let scope: PhraseChallenges.Scope
    let onVerified: (UUID) -> Void
    @State private var challengeID: UUID?
    @State private var words: [String] = []
    @State private var index = 0
    @State private var mistakes = 0
    @State private var input = ""
    @State private var message = ""
    @State private var completed = false

    private var pageStart: Int { (index / 20) * 20 }
    private var pageEnd: Int { min(pageStart + 20, words.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if words.isEmpty {
                Text(tr("Phrase unavailable. Close this screen and try again."))
                    .foregroundStyle(.red)
            } else {
                Text(String(format: tr("Word %d of %d"), index + 1, words.count))
                    .font(.headline)
                Text(String(format: tr("Mistakes: %d"), mistakes))
                    .font(.footnote).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading) {
                    ForEach(pageStart..<pageEnd, id: \.self) { position in
                        Text("\(position + 1). \(words[position])")
                            .font(.footnote)
                            .foregroundStyle(position == index ? accent : Ink.ink)
                            .fontWeight(position == index ? .bold : .regular)
                    }
                }
                .accessibilityElement(children: .contain)
                NoPasteWordField(text: $input, onSubmit: submit)
                    .frame(height: 44)
                    .padding(.horizontal, 10)
                    .background(Ink.paper, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityLabel(tr("Type the highlighted word"))
                if !message.isEmpty {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
                Button(tr("Check word"), action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || completed)
            }
        }
        .onAppear(perform: restart)
        .onDisappear {
            if let challengeID { PhraseChallenges.abandon(challengeID) }
        }
    }

    private func restart() {
        if let challengeID { PhraseChallenges.abandon(challengeID) }
        let fresh = PhraseChallenges.start(policy: policy, scope: scope)
        challengeID = fresh?.id
        words = fresh?.words ?? []
        index = 0
        mistakes = 0
        input = ""
        completed = false
    }

    private func submit() {
        guard let challengeID, !completed,
              !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        let result = PhraseChallenges.submit(word: input, to: challengeID)
        input = ""
        switch result {
        case .next(let next, let errors):
            index = next
            mistakes = errors
            message = ""
        case .wrong(let errors):
            mistakes = errors
            message = tr("That word was incorrect. Try again.")
        case .reset:
            restart() // random policies draw a new challenge after a reset
            message = tr("Too many mistakes. Start again.")
        case .completed(let proofID):
            completed = true
            message = ""
            onVerified(proofID)
        case .unavailable:
            words = []
        }
    }
}

/// The standard paste menu and drop gesture are disabled. iOS does not
/// guarantee proof of physical keystrokes (dictation/accessibility remain).
private struct NoPasteWordField: UIViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    final class Field: UITextField {
        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            if action == #selector(paste(_:)) || action == #selector(cut(_:)) {
                return false
            }
            return super.canPerformAction(action, withSender: sender)
        }

        override func paste(_ sender: Any?) {}
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NoPasteWordField
        init(_ parent: NoPasteWordField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Field {
        let field = Field()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)),
                        for: .editingChanged)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .done
        field.borderStyle = .none
        if let dropInteraction = field.textDropInteraction {
            field.removeInteraction(dropInteraction)
        }
        return field
    }

    func updateUIView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
    }
}
