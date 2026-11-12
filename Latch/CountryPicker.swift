//
//  CountryPicker.swift
//  One country inside a When & where rule (docs/conditional-sessions-redesign.md
//  §5.7; C5, C8, Q4; C15 step 5): a searchable list of the countries the
//  bundled offline borders know, named by iOS in the app's language, plus
//  "Use the country I'm in": one foreground fix through `LocationCheck`
//  (precise location not needed), looked up on the iPhone in
//  `CountryBorders`, never sent and never kept. Only the region code travels
//  back to the rule editor, whose change waits like any looser edit. No
//  geocoder, no map, no network.
//

import SwiftUI

/// Which country the picker opens with: a new condition, or a rule's existing one.
struct CountryEditRequest: Identifiable {
    let id = UUID()
    /// The condition being changed; nil adds a new country.
    let conditionID: UUID?
    let code: String?
}

struct CountryPicker: View {
    @AppAccent private var accent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    /// Made with the sheet and dropped with it.
    @StateObject private var locator = LocationCheck()
    let onDone: (String) -> Void

    @State private var selected: String?
    @State private var query = ""
    @State private var reading = false
    /// The in-sheet card before iOS's prompt (asked only from this button).
    @State private var asking = false
    @State private var problemKey: String?
    @State private var generation = 0
    /// iOS's prompt is up: a second tap on Allow location does nothing.
    @State private var requestingPermission = false

    init(initial: String?, onDone: @escaping (String) -> Void) {
        self.onDone = onDone
        _selected = State(initialValue: initial)
    }

    /// Codes the borders can answer with, read off the main thread when the
    /// sheet opens; nil while loading, empty if the file couldn't load.
    @State private var codes: [String]?

    private var choices: [CountryChoices.Choice] {
        CountryChoices.list(codes: codes ?? [], locale: locale, query: query)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.m) {
                Text(tr("Country"))
                    .demoraType(.hero)
                    .foregroundStyle(Ink.ink)
                    .accessibilityAddTraits(.isHeader)
                hereControls
                searchField
                list
            }
            .padding(DemoraSpace.xl)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { actions }
        .background(Ink.cardRaised.ignoresSafeArea())
        .presentationDetents([.large])
        .task {
            let loaded = await Task.detached(priority: .userInitiated) {
                CountryBorders.bundled?.regionCodes ?? []
            }.value
            codes = loaded
        }
        .onDisappear {
            generation += 1
            locator.stop()
        }
    }

    @ViewBuilder private var hereControls: some View {
        if asking {
            EditorNote(text: tr("Demora reads where you are once to find your country. It doesn't send your location."))
            Button(tr("Allow location")) { allowLocation() }
                .buttonStyle(DemoraPrimaryButtonStyle())
                .disabled(requestingPermission)
            quiet(tr("Not now")) { asking = false }
        } else if reading {
            HStack(spacing: DemoraSpace.s) {
                ProgressView()
                Text(tr("Checking where you are")).demoraType(.body).foregroundStyle(Ink.ink)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
        } else {
            Button { useHere() } label: {
                Label(tr("Use the country I'm in"), systemImage: "location")
                    .demoraType(.body)
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        if let problemKey {
            EditorNote(text: tr(problemKey), warning: true)
        }
    }

    private var searchField: some View {
        HStack(spacing: DemoraSpace.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Ink.inkSoft)
                .accessibilityHidden(true)
            TextField(tr("Search countries"), text: $query)
                .demoraType(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
        }
        .padding(.horizontal, DemoraSpace.s)
        .frame(minHeight: 44)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: DemoraRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DemoraRadius.card, style: .continuous)
            .strokeBorder(Ink.hairline, lineWidth: 1))
    }

    @ViewBuilder private var list: some View {
        let rows = choices
        if codes == nil {
            ProgressView().frame(maxWidth: .infinity, minHeight: 44)
        } else if rows.isEmpty {
            EditorNote(text: tr(codes?.isEmpty ?? true ? ConditionalCheckIn.unknownKey(.countryUnavailable)
                                                         : "No country matches."))
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { choice in
                    row(choice)
                    if choice != rows.last {
                        Rectangle().fill(Ink.hairline).frame(height: 1).accessibilityHidden(true)
                    }
                }
            }
            .paperCard(padding: 0)
        }
    }

    private func row(_ choice: CountryChoices.Choice) -> some View {
        Button {
            selected = choice.code
            problemKey = nil
        } label: {
            HStack(spacing: DemoraSpace.s) {
                Text(choice.name)
                    .demoraType(.body)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DemoraSpace.xs)
                if selected == choice.code {
                    Image(systemName: "checkmark")
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DemoraSpace.cardPadding)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == choice.code ? .isSelected : [])
    }

    private var actions: some View {
        VStack(spacing: DemoraSpace.xs) {
            if let selected {
                Text(ConditionalText.countryName(selected, locale: locale))
                    .demoraType(.cardTitle)
                    .foregroundStyle(Ink.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EditorNote(text: tr("Choose a country first."))
            }
            Button(tr("Use this country")) {
                guard let selected else { return }
                onDone(selected)
                dismiss()
            }
            .buttonStyle(DemoraPrimaryButtonStyle())
            .disabled(selected == nil)
            quiet(tr("Cancel")) { dismiss() }
        }
        .padding(.horizontal, DemoraSpace.xl)
        .padding(.vertical, DemoraSpace.s)
        .frame(maxWidth: DemoraSpace.maxContentWidth)
        .frame(maxWidth: .infinity)
        .background(Ink.cardRaised.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Ink.hairline).frame(height: 1).accessibilityHidden(true)
        }
    }

    private func quiet(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(DemoraType.button)
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }

    // MARK: Events

    /// The user's tap: the card if Demora was never asked, words if location
    /// is off (no re-prompt, no Settings redirect), otherwise one fix.
    private func useHere() {
        problemKey = nil
        switch locator.permission {
        case .notAsked:
            asking = true
        case .denied, .restricted:
            problemKey = ConditionalCheckIn.unknownKey(.locationOff)
        case .allowed:
            read()
        }
    }

    private func allowLocation() {
        guard !requestingPermission else { return }
        requestingPermission = true
        let token = generation
        Task { @MainActor in
            await locator.requestPermission()
            requestingPermission = false
            asking = false
            guard token == generation else { return }
            if case .allowed = locator.permission { read() }
            else { problemKey = ConditionalCheckIn.unknownKey(.locationOff) }
        }
    }

    /// One fix (precise not needed); only the country's code is kept, and
    /// only if the point is clearly inside it (accuracy + 2 km from any border).
    private func read() {
        generation += 1
        let token = generation
        reading = true
        Task { @MainActor in
            let outcome = await locator.readOnce(wantsPrecise: false)
            guard token == generation else { return }
            reading = false
            let borders = CountryBorders.bundled
            let lookup: LocationTrust.CountryAt? = borders.map { b in { b.lookup(latitude: $0, longitude: $1) } }
            switch LocationTrust.countryHere(outcome, wallNow: Date(), country: lookup) {
            case .success(let code):
                selected = code
                query = ""
            case .failure(let problem):
                problemKey = problem.messageKey
            }
        }
    }
}
