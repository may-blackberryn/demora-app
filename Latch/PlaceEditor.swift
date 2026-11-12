//
//  PlaceEditor.swift
//  One place inside a When & where rule (docs/conditional-sessions-redesign.md
//  §5.7; C10–C12; C15 step 4): a name, a centre set from where you are now
//  (one foreground fix through `LocationCheck`, never at launch), and a size
//  from 100 m to 2 km. "Use a place from another rule" copies that place into
//  this rule; nothing is shared between rules (C11). Only the name, rounded
//  centre and size travel back to the rule editor, whose change waits like
//  any looser edit. No map and no address search in this build: both would
//  load from Apple's servers (C12), and the map is left for later.
//

import SwiftUI

/// Which place the editor opens: a new one, or a rule's existing one.
struct PlaceEditRequest: Identifiable {
    let id = UUID()
    /// The condition being changed; nil adds a new place.
    let conditionID: UUID?
    let place: ConditionalPlace?
}

struct PlaceEditor: View {
    @AppAccent private var accent
    @AppLoosen private var loosen
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    /// Made with the sheet and dropped with it.
    @StateObject private var locator = LocationCheck()
    let initial: ConditionalPlace?
    /// The rule being edited, so its own places aren't offered to copy.
    let ruleID: UUID
    let onDone: (ConditionalPlace) -> Void

    @State private var name: String
    @State private var centre: PlaceCentre?
    @State private var radius: Int
    @State private var reading = false
    /// The in-sheet card before iOS's prompt (asked only from this button).
    @State private var asking = false
    @State private var problemKey: String?
    @State private var generation = 0
    /// iOS's prompt is up: a second tap on Allow location does nothing.
    @State private var requestingPermission = false

    init(initial: ConditionalPlace?, ruleID: UUID, onDone: @escaping (ConditionalPlace) -> Void) {
        self.initial = initial
        self.ruleID = ruleID
        self.onDone = onDone
        _name = State(initialValue: initial?.name ?? "")
        _centre = State(initialValue: initial.map { PlaceCentre(latitude: $0.latitude, longitude: $0.longitude) })
        _radius = State(initialValue: initial?.radiusMeters ?? PlaceChoices.defaultRadius)
    }

    private var place: ConditionalPlace? { PlaceChoices.place(name: name, centre: centre, radius: radius) }

    private var others: [ConditionalPlace] {
        PlaceChoices.otherPlaces(state: model.state, excluding: ruleID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.m) {
                Text(tr("Place"))
                    .demoraType(.hero)
                    .foregroundStyle(Ink.ink)
                    .accessibilityAddTraits(.isHeader)
                EditorSection(tr("Name")) {
                    TextField(tr("e.g. Home"), text: $name)
                        .demoraType(.cardTitle)
                        .frame(minHeight: 44)
                }
                EditorSection(tr("Centre")) { centreControls }
                EditorSection(tr("Size")) {
                    ChoiceList(selection: $radius, options: PlaceChoices.sizes.map {
                        ($0, ConditionalText.radius($0, locale: locale) + " · " + tr(PlaceChoices.sizeWordsKey($0)))
                    })
                }
                if !others.isEmpty { copyMenu }
                VStack(spacing: DemoraSpace.s) {
                    if place == nil {
                        EditorNote(text: tr(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                            ? "Give it a name." : "Set a centre first."))
                    }
                    Button(tr("Use this place")) {
                        guard let place else { return }
                        onDone(place)
                        dismiss()
                    }
                    .buttonStyle(DemoraPrimaryButtonStyle())
                    .disabled(place == nil)
                    quiet(tr("Cancel")) { dismiss() }
                }
            }
            .padding(DemoraSpace.xl)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.cardRaised.ignoresSafeArea())
        .presentationDetents([.large])
        .onDisappear {
            generation += 1
            locator.stop()
        }
    }

    @ViewBuilder private var centreControls: some View {
        EditorNote(text: tr(centre == nil ? "Stand at the place, then set its centre."
                                          : "Centre set. Only the centre and size are saved, on this iPhone."))
        if asking {
            EditorNote(text: tr("Demora reads where you are once to set this place's centre. It doesn't send your location."))
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
            Button { setFromHere() } label: {
                Label(tr("Set to where I am now"), systemImage: "location")
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

    private var copyMenu: some View {
        Menu {
            ForEach(Array(others.enumerated()), id: \.offset) { _, other in
                Button(other.name + " · " + ConditionalText.radius(other.radiusMeters, locale: locale)) {
                    // A copy: later edits to either rule don't touch the other (C11).
                    // A fix still on its way must not replace the copied centre.
                    generation += 1
                    locator.cancel()
                    reading = false
                    asking = false
                    name = other.name
                    centre = PlaceCentre(latitude: other.latitude, longitude: other.longitude)
                    radius = other.radiusMeters
                    problemKey = nil
                }
            }
        } label: {
            Label(tr("Use a place from another rule"), systemImage: "doc.on.doc")
                .demoraType(.body)
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
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
    private func setFromHere() {
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

    /// One fix; only its rounded centre is kept, and only if it passes the
    /// trust rules (precise, real, fresh, good to 100 m).
    private func read() {
        generation += 1
        let token = generation
        reading = true
        Task { @MainActor in
            let outcome = await locator.readOnce(wantsPrecise: true)
            guard token == generation else { return }
            reading = false
            switch LocationTrust.centre(outcome, wallNow: Date()) {
            case .success(let value): centre = value
            case .failure(let problem): problemKey = problem.messageKey
            }
        }
    }
}
