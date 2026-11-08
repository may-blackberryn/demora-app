//
//  YouPages.swift
//  Pages pushed from You → App (docs/you-redesign.md §5.8, §5.11, §5.12):
//  Appearance with every option inline and a live preview (Y9), Prevent
//  disabling as one page (Y12) and Help & guide. Appearance changes are
//  local display preferences and apply at once; the prevent-disabling
//  guide and passcode look keep their delayed, one-time access.
//

import SwiftUI

// MARK: - Appearance (§5.8, Y9)

enum AppearanceSummary {
    /// "Light · Blue · Regular".
    static func text(appearance: String, accent: String, casing: String) -> String {
        [(Appearance(rawValue: appearance) ?? .system).label,
         accent == "red" ? tr("Brick") : tr("Blue"),
         TextCasing.resolved(casing).label].joined(separator: " · ")
    }
}

struct AppearanceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("textCasing") private var textCasingRaw = TextCasing.fallback.rawValue
    @AppStorage("weekStartMonday") private var weekStartMonday = false
    @AppStorage("latch.accentColor", store: SharedStore.defaults)
    private var accentColorRaw = "blue"

    private var appearance: Appearance { Appearance(rawValue: appearanceRaw) ?? .system }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                AppearancePreviewCard()
                    .id(appearanceRaw + accentColorRaw + textCasingRaw)
                    .transition(.opacity)
                section(tr("Theme")) {
                    let tiles = ForEach(Appearance.allCases) { option in
                        ThemePreviewTile(option: option, selected: appearance == option) {
                            change { appearanceRaw = option.rawValue }
                        }
                    }
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: DemoraSpace.xs) { tiles }
                    } else {
                        HStack(alignment: .top, spacing: DemoraSpace.s) { tiles }
                    }
                }
                section(tr("Colour")) {
                    HStack(spacing: DemoraSpace.l) {
                        swatch("blue", label: tr("Blue"))
                        swatch("red", label: tr("Brick"))
                    }
                    if accentColorRaw == "red" {
                        Text(tr("Blocked items use ochre so they don't look like buttons."))
                            .demoraType(.meta)
                            .foregroundStyle(Ink.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                section(tr("Text")) {
                    Picker(tr("Text"), selection: Binding(
                        get: { TextCasing.resolved(textCasingRaw) },
                        set: { value in change { textCasingRaw = value.rawValue } })) {
                        Text(TextCasing.regular.label).tag(TextCasing.regular)
                        Text(TextCasing.lower.label).tag(TextCasing.lower)
                    }
                    .pickerStyle(.segmented)
                }
                section(tr("Week starts on")) {
                    Picker(tr("Week starts on"), selection: $weekStartMonday) {
                        Text(tr("Monday")).tag(true)
                        Text(tr("Sunday")).tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                NavigationLink { LanguagePickerView() } label: {
                    YouRowLabel(title: tr("Language"), value: model.language.label)
                        .paperCard(padding: 0)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DemoraSpace.pageGutter)
            .padding(.vertical, DemoraSpace.l)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Appearance"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func change(_ update: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25), update)
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            SectionHeader(title)
            content()
        }
    }

    private func swatch(_ value: String, label: String) -> some View {
        let selected = accentColorRaw == value
        return Button { change { accentColorRaw = value } } label: {
            VStack(spacing: DemoraSpace.xxs) {
                Circle()
                    .fill(Ink.accent(for: value))
                    .frame(width: 44, height: 44)
                    .padding(4)
                    .overlay(Circle().strokeBorder(selected ? Ink.ink : Color.clear, lineWidth: 2))
                Text(label).demoraType(.meta).foregroundStyle(Ink.ink)
            }
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A sample rule card drawn with the current choices (Joi-style preview).
private struct AppearancePreviewCard: View {
    @State private var until = Date().addingTimeInterval(2 * 3600 + 14 * 60)

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Evening block"))
                    .demoraType(.cardTitle)
                    .foregroundStyle(Ink.ink)
                Spacer(minLength: DemoraSpace.xs)
                StateChip(kind: .active, text: String(format: tr("On until %@"),
                                                      until.formatted(date: .omitted, time: .shortened)))
            }
            Text(timerInterval: Date.now...until, countsDown: true)
                .demoraType(.time)
                .foregroundStyle(Ink.ink)
            Text(tr("Social apps"))
                .demoraType(.meta)
                .foregroundStyle(Ink.inkSoft)
        }
        .paperCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("Preview"))
    }
}

/// One theme choice: a small page drawn in that theme, with a radio below.
struct ThemePreviewTile: View {
    @AppAccent private var accent
    let option: Appearance
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DemoraSpace.xs) {
                ZStack {
                    switch option {
                    case .system:
                        HStack(spacing: 0) {
                            page.environment(\.colorScheme, .light)
                            page.environment(\.colorScheme, .dark)
                        }
                    case .light: page.environment(\.colorScheme, .light)
                    case .dark: page.environment(\.colorScheme, .dark)
                    }
                }
                .frame(width: 88, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? accent : Ink.hairline, lineWidth: selected ? 2 : 1))
                HStack(spacing: DemoraSpace.xxs) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? accent : Ink.inkSoft)
                        .accessibilityHidden(true)
                    Text(option.label).demoraType(.meta).foregroundStyle(Ink.ink)
                }
            }
            .frame(minWidth: 88, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(Ink.ink).frame(width: 30, height: 5)
            RoundedRectangle(cornerRadius: 6)
                .fill(Ink.card)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Ink.hairline, lineWidth: 1))
                .frame(height: 30)
            RoundedRectangle(cornerRadius: 6)
                .fill(Ink.card)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Ink.hairline, lineWidth: 1))
                .frame(height: 30)
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.paper)
    }
}

// MARK: - Prevent disabling (§5.11, Y12)

/// One page with its two parts. Behaviour unchanged: the guide opens once
/// after the looser wait (owner answer 3), the passcode is saved at once in
/// the Keychain, and one look at it waits like the guide.
struct PreventDisablingPage: View {
    @AppAccent private var accent
    @EnvironmentObject private var model: AppModel
    @State private var receipt: ChangeReceiptRequest?
    @State private var showGuide = false
    @State private var showEntry = false
    @State private var confirmReplace = false
    @State private var revealed: String?

    private func waiting(_ match: (ChangeAction) -> Bool) -> PendingChange? {
        model.state.pending.first { match($0.action) }
    }

    var body: some View {
        // Re-read each second so a wait that ends shows Ready without leaving.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                    Text(tr("Demora can't stop you from turning off its Screen Time access in iOS Settings — but a friend can. If Screen Time itself is locked with someone else's passcode, iOS blocks any change to Demora's access, while Demora keeps doing all the blocking."))
                        .demoraType(.body)
                        .foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    guideCard
                    passcodeCard
                }
                .padding(.horizontal, DemoraSpace.pageGutter)
                .padding(.vertical, DemoraSpace.l)
                .frame(maxWidth: DemoraSpace.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Prevent disabling"))
        .navigationBarTitleDisplayMode(.inline)
        .changeReceipt($receipt)
        .alert(tr("Change the passcode?"), isPresented: $confirmReplace) {
            Button(tr("Cancel"), role: .cancel) {}
            Button(tr("Change passcode")) { showEntry = true }
        } message: {
            Text(tr("Are you sure? There is no way to undo this — the saved passcode is replaced only when you save a new one."))
        }
        .sheet(isPresented: $showEntry, onDismiss: { revealed = nil }) { PasscodeEntrySheet() }
        .sheet(isPresented: $showGuide) {
            NavigationStack {
                ScrollView {
                    PreventDisablingContent(showsPasscodeStore: false)
                        .padding(DemoraSpace.l)
                        .frame(maxWidth: DemoraSpace.maxContentWidth)
                        .frame(maxWidth: .infinity)
                }
                .background(Ink.paper.ignoresSafeArea())
                .casedNavigationTitle(tr("Prevent disabling"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Done")) { showGuide = false }
                    }
                }
            }
        }
    }

    private var guideCard: some View {
        let pending = waiting { if case .unlockPreventGuide = $0 { return true }; return false }
        return VStack(alignment: .leading, spacing: DemoraSpace.s) {
            Text(tr("Setup guide")).demoraType(.cardTitle).foregroundStyle(Ink.ink)
            if model.preventReady {
                Text(tr("Ready — opens once")).demoraType(.meta).foregroundStyle(Ink.inkSoft)
                Button(tr("Open the guide")) {
                    model.consumePreventAccess()   // spend the single open
                    showGuide = true
                }
                .buttonStyle(DemoraPrimaryButtonStyle())
            } else if let pending {
                waitingLine(pending)
                Text(tr("Access requested. It opens after your looser wait. Track it in Changes on Today, where a way to skip a wait can also open it early."))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(tr("This guide is behind your less-strict delay: request it, wait out the delay, and you get one open. After you view it, it locks again."))
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Request access")) {
                    receipt = ChangeReceiptRequest(action: .unlockPreventGuide)
                }
                .buttonStyle(DemoraPrimaryButtonStyle())
            }
        }
        .paperCard()
    }

    private var passcodeCard: some View {
        let saved = !model.screenTimeCode.isEmpty
        let pending = waiting { if case .unlockPasswordView = $0 { return true }; return false }
        return VStack(alignment: .leading, spacing: DemoraSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Screen Time passcode")).demoraType(.cardTitle).foregroundStyle(Ink.ink)
                Spacer(minLength: DemoraSpace.xs)
                Text(saved ? tr("Saved") : tr("None saved"))
                    .demoraType(.meta).foregroundStyle(Ink.inkSoft)
            }
            Text(tr("The friend who set the Screen Time passcode can store it here so it isn't lost. Going back without saving keeps the current one."))
                .demoraType(.meta)
                .foregroundStyle(Ink.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button(tr("Enter passcode")) {
                if saved { confirmReplace = true } else { showEntry = true }
            }
            .buttonStyle(.plain)
            .font(DemoraType.button)
            .foregroundStyle(accent)
            .frame(minHeight: 44)
            if saved {
                Rectangle().fill(Ink.hairline).frame(height: 1).accessibilityHidden(true)
                if let revealed {
                    Label(String(format: tr("Saved passcode: %@"), revealed), systemImage: "key.fill")
                        .demoraType(.time)
                        .foregroundStyle(accent)
                    Text(tr("Access is spent — viewing it again needs a new request."))
                        .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                } else if model.passwordViewReady {
                    Text(tr("Your one-time access is ready.")).demoraType(.meta).foregroundStyle(Ink.inkSoft)
                    Button(tr("View passcode")) {
                        model.consumePasswordViewAccess()   // spend the single look
                        revealed = model.screenTimeCode
                    }
                    .buttonStyle(DemoraPrimaryButtonStyle())
                } else if let pending {
                    waitingLine(pending)
                } else {
                    Text(tr("Viewing the stored passcode is behind your less-strict delay: request it, wait out the delay, and you get one look. After that it locks again."))
                        .demoraType(.meta)
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(tr("View passcode")) {
                        receipt = ChangeReceiptRequest(action: .unlockPasswordView)
                    }
                    .buttonStyle(.plain)
                    .font(DemoraType.button)
                    .foregroundStyle(accent)
                    .frame(minHeight: 44)
                }
            }
        }
        .paperCard()
    }

    private func waitingLine(_ change: PendingChange) -> some View {
        HStack(spacing: DemoraSpace.xxs) {
            Image(systemName: "clock").accessibilityHidden(true)
            Text(String(format: tr("Opens %@"), change.appliesAt.formatted(
                .dateTime.weekday(.abbreviated).hour().minute())))
            CountdownText(to: change.appliesAt, style: nil).monospacedDigit()
        }
        .demoraType(.meta)
        .foregroundStyle(accent)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Help & guide (§5.12)

struct HelpGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                VStack(spacing: 0) {
                    NavigationLink { HowDemoraWorksView() } label: {
                        YouRowLabel(title: tr("How Demora works"), value: tr("four short pages"))
                    }
                    YouRowDivider()
                    NavigationLink { GuideView() } label: {
                        YouRowLabel(title: tr("Guide"), value: tr("how each part works"))
                    }
                    YouRowDivider()
                    NavigationLink { LimitationsView() } label: {
                        YouRowLabel(title: tr("Limitations"), value: tr("iOS reporting notes"))
                    }
                }
                .buttonStyle(.plain)
                .paperCard(padding: 0)
                VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
                    SectionHeader(tr("Contact & feedback"))
                    VStack(spacing: 0) {
                        link(tr("Report a bug"), "bugs@getdemora.app", "mailto:bugs@getdemora.app")
                        YouRowDivider()
                        link(tr("Request a feature"), "features@getdemora.app", "mailto:features@getdemora.app")
                        YouRowDivider()
                        link(tr("General help"), "hello@getdemora.app", "mailto:hello@getdemora.app")
                        YouRowDivider()
                        link(tr("Feature roadmap"), tr("links to Trello"), "https://trello.com/b/0TKqYTdt/demora")
                        YouRowDivider()
                        link(tr("Bug tracker"), tr("links to Trello"), "https://trello.com/b/X9HQlORp/demora-bug-fixing")
                        YouRowDivider()
                        link(tr("Website"), "getdemora.app", "https://getdemora.app")
                        YouRowDivider()
                        link(tr("Instagram"), "@get.demora", "https://instagram.com/get.demora")
                    }
                    .paperCard(padding: 0)
                }
            }
            .padding(.horizontal, DemoraSpace.pageGutter)
            .padding(.vertical, DemoraSpace.l)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Help & guide"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func link(_ title: String, _ detail: String, _ address: String) -> some View {
        Link(destination: URL(string: address)!) {
            YouRowLabel(title: title, value: detail)
        }
        .buttonStyle(.plain)
    }
}
