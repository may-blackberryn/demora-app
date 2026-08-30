//
//  LanguageExpansionUpdateView.swift
//  One-time update notice for existing users when the expanded localization
//  set was introduced. Fresh installs already choose during onboarding.
//

import SwiftUI

struct LanguageExpansionUpdateView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let onPresented: () -> Void

    @State private var selectedLanguage = AppLanguage.current
    @State private var showLanguageBetaNotice = false
    @State private var dismissAfterBetaNotice = false

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "character.bubble.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(.tint)

                    Text(tr("Demora now speaks more languages"))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(tr("We've added support for German, French, Portuguese, Polish, Turkish, and Hindi."))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    Text(tr("Choose your language here. You can change it anytime under Settings → Appearance → Language."))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(AppLanguage.allCases) { language in
                            Button {
                                selectedLanguage = language
                            } label: {
                                GridCard(
                                    symbol: selectedLanguage == language
                                        ? "checkmark.circle.fill" : "circle",
                                    title: language.label,
                                    subtitle: language.rawValue.uppercased())
                            }
                        }
                    }

                    Button(tr("Continue")) { commitAndContinue() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .background(Ink.paper.ignoresSafeArea())
            .interactiveDismissDisabled()
            .onAppear(perform: onPresented)
            .alert(tr("Translation in beta"),
                   isPresented: $showLanguageBetaNotice) {
                Button(tr("OK"), role: .cancel) {
                    if dismissAfterBetaNotice { dismiss() }
                }
            } message: {
                Text(tr("This language is in beta. Please report any mistranslations or unclear phrasing to hello@getdemora.app."))
            }
        }
    }

    private func commitAndContinue() {
        let changedLanguage = selectedLanguage != model.language
        if changedLanguage {
            model.language = selectedLanguage
        }

        if changedLanguage && selectedLanguage.isBetaTranslation {
            dismissAfterBetaNotice = true
            showLanguageBetaNotice = true
        } else {
            dismiss()
        }
    }
}
