import SwiftUI

/// Drafts only. The caller validates and commits this one-time replacement;
/// leaving this sheet without finishing cannot create an active override.
struct MathPhraseMigrationView: View {
    var isDemo = false
    let install: ([PhrasePolicy]) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var phrases: [PhrasePolicy] = []
    @State private var showEditor = false
    @State private var saving = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    #if DEBUG
                    if isDemo { DeveloperDemoNotice() }
                    #endif
                    DemoraPageTitle(title: tr("From math to phrases"))
                    Text(tr("Math problems have been replaced with phrases. Since you used math overrides, you can add replacement phrases now without waiting."))
                        .foregroundStyle(Ink.faint)
                    Text(tr("Choose what each phrase can approve. This one-time offer covers pending changes, not extra time. Later additions and edits follow your delays."))
                        .font(.footnote).foregroundStyle(Ink.faint)
                    ForEach(phrases) { phrase in
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(phrase.name).font(.system(.title3, design: .serif))
                                Text(phrase.allowed.map(\.label).sorted().joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Ink.faint)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                phrases.removeAll { $0.id == phrase.id }
                            } label: { Image(systemName: "minus.circle") }
                                .accessibilityLabel(tr("Remove phrase"))
                        }
                        .padding(.vertical, 8)
                    }
                    if phrases.count < 5 {
                        Button { showEditor = true } label: {
                            Label(tr("Add phrase"), systemImage: "plus")
                        }
                        .frame(minHeight: 44)
                    }
                    Button {
                        saving = true
                        Task { @MainActor in
                            let success = await install(phrases)
                            saving = false
                            if success { dismiss() } else { failed = true }
                        }
                    } label: {
                        HStack {
                            if saving { ProgressView().tint(Ink.buttonText) }
                            Text(tr("Use these phrases now"))
                        }
                    }
                    .buttonStyle(DemoraPrimaryButtonStyle())
                    .disabled(phrases.isEmpty)
                }
                .disabled(saving)
                .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .paper()
            .toolbar {
                Button(tr("Cancel")) { dismiss() }.disabled(saving)
            }
            .sheet(isPresented: $showEditor) {
                NavigationStack {
                    PhrasePolicyEditor(existing: nil, onStage: { phrases.append($0) }, isDemo: isDemo)
                        .toolbar { Button(tr("Cancel")) { showEditor = false } }
                }
            }
            .alert(tr("Setup couldn't be saved"), isPresented: $failed) {
                Button(tr("OK"), role: .cancel) { }
            } message: {
                Text(tr("Your choices are still here. Please try again."))
            }
        }
        .interactiveDismissDisabled(saving)
    }
}
