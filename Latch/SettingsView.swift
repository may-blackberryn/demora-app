//
//  SettingsView.swift
//  Language, the two delays, override methods, the app-deletion lock,
//  and beta credits. Every rule change is queued through the change
//  engine; language is cosmetic and switches instantly.
//

import SwiftUI

enum SettingsRoute: Hashable {
    case appearance, rules, delays, overrides, help
}

let gridCols = [GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)]

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack(path: $model.settingsPath) {
            ScrollView {
                VStack(spacing: 14) {
                    LazyVGrid(columns: gridCols, spacing: 14) {
                        NavigationLink(value: SettingsRoute.appearance) {
                            GridCard(symbol: "textformat.size",
                                     title: tr("Appearance"),
                                     subtitle: tr("language, theme, case"))
                        }
                        NavigationLink(value: SettingsRoute.rules) {
                            GridCard(symbol: "slider.horizontal.3", title: tr("Rules"),
                                     subtitle: tr("delays, overrides, blocking"),
                                     showsDot: model.incomingInviteCount > 0)
                        }
                        .tutorialHighlight(model.tutorial == .addContact
                                           && model.tutorialScreen == "settings")
                        NavigationLink(value: SettingsRoute.help) {
                            GridCard(symbol: "questionmark.circle", title: tr("Help"),
                                     subtitle: tr("guide, contact, more"))
                        }
                        #if DEBUG
                        Button { model.debugFullReset() } label: {
                            GridCard(symbol: "trash", title: "Reset app (debug)",
                                     subtitle: "wipe + onboarding")
                        }
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .casedNavigationTitle(tr("Settings"))
            .onAppear {
                if model.inTutorial && model.selectedTab == 3 {
                    model.tutorialScreen = "settings"
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .appearance:  AppearanceGridView()
                case .rules:       RulesGridView()
                case .delays:      DelaysGridView()
                case .overrides:   OverridesGridView()
                case .help:        HelpHubView()
                }
            }
        }
    }

    private var overridesSubtitle: String {
        let o = model.state.overrides
        var n = 0
        if o.mathEnabled { n += 1 }
        if o.passwordEnabled { n += 1 }
        if o.contactsEnabled { n += 1 }
        return n == 0 ? tr("none on") : String(format: tr("%d on"), n)
    }

}

// MARK: - Help hub

struct HelpHubView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridCols, spacing: 14) {
                NavigationLink { GuideView() } label: {
                    GridCard(symbol: "book", title: tr("Guide"),
                             subtitle: tr("how each part works"))
                }
                NavigationLink { ContactView() } label: {
                    GridCard(symbol: "envelope", title: tr("Contact"),
                             subtitle: tr("bug, feature, help"))
                }
                NavigationLink { SoftwareRoadmapView() } label: {
                    GridCard(symbol: "map", title: tr("Software roadmap"),
                             subtitle: tr("features & bugs"))
                }
                NavigationLink { PreventDisablingGateView() } label: {
                    GridCard(symbol: "lock.shield", title: tr("Prevent disabling"),
                             subtitle: tr("lock it with a friend"))
                }
                NavigationLink { BetaTestersView() } label: {
                    GridCard(symbol: "heart", title: tr("Beta testers"),
                             subtitle: tr("thank you"))
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Help"))
    }
}

// MARK: - Software roadmap

struct SoftwareRoadmapView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridCols, spacing: 14) {
                Link(destination: URL(string: "https://trello.com/b/0TKqYTdt/demora")!) {
                    GridCard(symbol: "map", title: tr("Feature roadmap"),
                             subtitle: tr("links to Trello"))
                }
                Link(destination: URL(string: "https://trello.com/b/X9HQlORp/demora-bug-fixing")!) {
                    GridCard(symbol: "ladybug", title: tr("Bug tracker"),
                             subtitle: tr("links to Trello"))
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Software roadmap"))
    }
}

// MARK: - Guide

/// One help topic — shown as a card in the Guide grid and a detail page.
struct GuideTopic: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let summary: String
    let body: String
}

struct GuideView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridCols, spacing: 14) {
                ForEach(topics) { topic in
                    NavigationLink { GuideTopicView(topic: topic) } label: {
                        GridCard(symbol: topic.symbol, title: topic.title,
                                 subtitle: topic.summary)
                    }
                }
                Button { model.replayTutorial() } label: {
                    GridCard(symbol: "arrow.clockwise", title: tr("Replay walkthrough"),
                             subtitle: tr("your setup stays safe"))
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Guide"))
        .alert(tr("Couldn't start the walkthrough"),
               isPresented: $model.replayFailed) {
            Button(tr("OK"), role: .cancel) { }
        } message: {
            Text(tr("Demora couldn't safely back up your current setup, so the replay was cancelled to protect your limits. Nothing was changed. Please try again in a moment."))
        }
    }

    // Built in-body so tr() reflects the current language.
    private var topics: [GuideTopic] {
        [
            GuideTopic(
                id: "what", symbol: "hourglass.circle", title: tr("What Demora is"),
                summary: tr("the core idea"),
                body: tr("Most screen-time apps lock your rules behind a password. Because you know the password, you can undo your own rules the moment you feel the urge — so they rarely stick.\n\nDemora protects your rules with time instead. Every change waits out a countdown you set in advance before it takes effect. You stay in full control of your rules, but you can't change them in a single impulsive moment. The blocking itself is enforced by iOS through Screen Time — the same system parental controls use — so it can't be quietly bypassed.")),
            GuideTopic(
                id: "delays", symbol: "timer", title: tr("Delays"),
                summary: tr("the two countdowns"),
                body: tr("Demora has two delays. The more-strict delay covers any change that tightens your rules: adding a limit, lowering its minutes, adding a schedule, or turning on the deletion lock. The less-strict delay covers changes that loosen them: raising a limit, removing a block, adding a free period, or disabling an override. The less-strict delay is usually set longer, since loosening is where temptation lives.\n\nA change doesn't apply right away — it becomes a pending change with a live countdown on the Home tab. You can cancel it any time before it lands, and when the countdown reaches zero it applies on its own, even if the app is closed.")),
            GuideTopic(
                id: "limits", symbol: "apps.iphone", title: tr("Limits"),
                summary: tr("daily app budgets"),
                body: tr("A limit is a daily time budget for a set of apps or whole categories. When the minutes run out, those apps are blocked for the rest of the day and unlock again at midnight.\n\nThe Limits tab shows today's real usage for each limit, read straight from Screen Time, and tapping a limit reveals exactly which apps and categories it covers. Because usage is measured by iOS, time spent before you created the limit still counts toward it that day. Raising or removing a limit is a less-strict change; adding one or lowering its minutes is stricter.")),
            GuideTopic(
                id: "schedules", symbol: "calendar", title: tr("Schedules"),
                summary: tr("recurring, planned, sessions"),
                body: tr("Schedules block apps by time rather than by budget, in a few shapes. Recurring schedules repeat — every day, on chosen weekdays, or on a monthly pattern. Planned windows are one-offs for a specific date, like a trip or an exam. Sessions are immediate, timed blocks or unblocks you start right now. Free periods are windows where limits don't block and usage doesn't count toward them.\n\nEach blocking schedule either blocks the apps you pick, or blocks everything except the apps you pick. When rules overlap, the most specific one wins: a session beats a planned window, which beats a recurring schedule, and within the same kind the one added most recently takes priority.")),
            GuideTopic(
                id: "overrides", symbol: "key", title: tr("Overrides"),
                summary: tr("escape hatches"),
                body: tr("Overrides are optional escape hatches that let you skip a pending change's countdown. There are three: solve a set of math problems, enter a password, or ask a trusted contact to approve. They're all off by default, so out of the box your delays are absolute.\n\nTurning an override on, or making it easier, counts as a less-strict change and waits out that delay. Turning one off, or making it harder, is stricter — so you can't instantly weaken your own safety net.")),
            GuideTopic(
                id: "contacts", symbol: "person.2", title: tr("Trusted contacts"),
                summary: tr("approval by a person"),
                body: tr("A trusted contact is a person who can approve skipping a countdown for you. They can approve by entering a short code sent to their email, or directly from their own copy of Demora.\n\nAnyone you add has to accept the request before they can approve anything, so no one is involved without their knowledge. You can revoke a contact at any time, and they can step down on their side too. Adding the override is a less-strict change; removing it is stricter.")),
            GuideTopic(
                id: "deletion", symbol: "trash.slash", title: tr("App deletion lock"),
                summary: tr("can't uninstall to bypass"),
                body: tr("When the deletion lock is on, deleting any app from this iPhone is blocked — including Demora itself. That closes the most obvious loophole: uninstalling the app to wipe your rules.\n\nBecause turning the lock off makes things easier to bypass, it counts as a less-strict change and waits out that delay before it takes effect.")),
        ]
    }
}

struct GuideTopicView: View {
    let topic: GuideTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: topic.symbol)
                    .font(.largeTitle).foregroundStyle(Ink.accent)
                Text(topic.body)
                    .font(.body).foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20).frame(maxWidth: 640)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(topic.title)
    }
}

// MARK: - Contact

struct ContactView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridCols, spacing: 14) {
                mailCard(symbol: "ladybug", title: tr("Report a bug"),
                         email: "bugs@getdemora.app")
                mailCard(symbol: "lightbulb", title: tr("Request a feature"),
                         email: "features@getdemora.app")
                mailCard(symbol: "questionmark.circle", title: tr("General help"),
                         email: "hello@getdemora.app")
                Link(destination: URL(string: "https://getdemora.app")!) {
                    GridCard(symbol: "globe", title: tr("Website"),
                             subtitle: "getdemora.app")
                }
                Link(destination: URL(string: "https://instagram.com/get.demora")!) {
                    GridCard(symbol: "camera", title: tr("Instagram"),
                             subtitle: "@get.demora")
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Contact"))
    }

    private func mailCard(symbol: String, title: String, email: String) -> some View {
        Link(destination: URL(string: "mailto:\(email)")!) {
            GridCard(symbol: symbol, title: title, subtitle: email)
        }
    }
}

// MARK: - Appearance grid (tap a card to cycle its value)

struct AppearanceGridView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("textCasing") private var textCasingRaw = TextCasing.lower.rawValue
    @AppStorage("weekStartMonday") private var weekStartMonday = false
    @AppStorage("home.showDelays") private var showDelays = true
    @AppStorage("home.showOverrides") private var showOverrides = true

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridCols, spacing: 14) {
                Button {
                    model.language = model.language == .english ? .spanish : .english
                } label: {
                    GridCard(symbol: "globe", title: tr("Language"),
                             subtitle: model.language.label)
                }
                Button {
                    let all = Appearance.allCases
                    let cur = Appearance(rawValue: appearanceRaw) ?? .system
                    appearanceRaw = all[(all.firstIndex(of: cur)! + 1) % all.count].rawValue
                } label: {
                    GridCard(symbol: "circle.lefthalf.filled", title: tr("Theme"),
                             subtitle: (Appearance(rawValue: appearanceRaw) ?? .system).label)
                }
                Button {
                    let all = TextCasing.allCases
                    let cur = TextCasing(rawValue: textCasingRaw) ?? .lower
                    textCasingRaw = all[(all.firstIndex(of: cur)! + 1) % all.count].rawValue
                } label: {
                    GridCard(symbol: "textformat", title: tr("Text case"),
                             subtitle: (TextCasing(rawValue: textCasingRaw) ?? .lower).label)
                }
                Button {
                    weekStartMonday.toggle()
                } label: {
                    GridCard(symbol: "calendar", title: tr("Week starts"),
                             subtitle: weekStartMonday ? tr("Monday") : tr("Sunday"))
                }
                Button {
                    showDelays.toggle()
                } label: {
                    GridCard(symbol: showDelays ? "eye" : "eye.slash",
                             title: tr("Home delays"),
                             subtitle: showDelays ? tr("shown") : tr("hidden"))
                }
                Button {
                    showOverrides.toggle()
                } label: {
                    GridCard(symbol: showOverrides ? "eye" : "eye.slash",
                             title: tr("Home overrides"),
                             subtitle: showOverrides ? tr("shown") : tr("hidden"))
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Appearance"))
    }
}

// MARK: - Delays grid

struct DelaysGridView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridCols, spacing: 14) {
                NavigationLink { DelayEditorView(kind: .strict) } label: {
                    GridCard(symbol: strictLockSymbol,
                             title: tr("More strict"),
                             subtitle: model.state.strictDelay.shortDelayLabel)
                }
                NavigationLink { DelayEditorView(kind: .lenient) } label: {
                    GridCard(symbol: "lock.open", title: tr("Less strict"),
                             subtitle: model.state.lenientDelay.shortDelayLabel)
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Delays"))
    }
}

// MARK: - Overrides grid

struct OverridesGridView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LazyVGrid(columns: gridCols, spacing: 14) {
                    NavigationLink { MathOverrideEditor() } label: {
                        GridCard(symbol: "function", title: tr("Math problems"),
                                 subtitle: model.state.overrides.mathEnabled
                                    ? (model.state.overrides.mathDifficulty?.label ?? tr("On"))
                                    : tr("Off"))
                    }
                    NavigationLink { PasswordOverrideEditor() } label: {
                        GridCard(symbol: "key", title: tr("Password"),
                                 subtitle: model.state.overrides.passwordEnabled
                                    ? tr("On") : tr("Off"))
                    }
                    NavigationLink { ContactsOverrideEditor() } label: {
                        GridCard(symbol: "person.2", title: tr("Trusted contacts"),
                                 subtitle: model.state.overrides.contactsEnabled
                                    ? String(model.state.overrides.contacts.count)
                                    : tr("Off"),
                                 showsDot: model.incomingInviteCount > 0)
                    }
                    .tutorialHighlight(model.tutorial == .addContact
                                       && model.tutorialScreen == "overrides")
                }
                Text(tr("Overrides skip a pending change's countdown. Enabling or weakening one is a less-strict change; disabling or strengthening one is stricter. All edits here go through the matching delay."))
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Overrides"))
        .onAppear { if model.inTutorial { model.tutorialScreen = "overrides" } }
    }
}

// MARK: - Rules grid (two cards: delays and overrides)

struct RulesGridView: View {
    @EnvironmentObject var model: AppModel

    private var overridesSubtitle: String {
        let o = model.state.overrides
        var n = 0
        if o.mathEnabled { n += 1 }
        if o.passwordEnabled { n += 1 }
        if o.contactsEnabled { n += 1 }
        return n == 0 ? tr("all off") : String(format: tr("%d on"), n)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridCols, spacing: 14) {
                NavigationLink { DelaysGridView() } label: {
                    GridCard(symbol: "hourglass", title: tr("Delays"),
                             subtitle: String(format: tr("%@ · %@"),
                                model.state.strictDelay.shortDelayLabel,
                                model.state.lenientDelay.shortDelayLabel))
                }
                NavigationLink { OverridesGridView() } label: {
                    GridCard(symbol: "key", title: tr("Overrides"),
                             subtitle: overridesSubtitle,
                             showsDot: model.incomingInviteCount > 0)
                }
                .tutorialHighlight(model.tutorial == .addContact
                                   && model.tutorialScreen == "rules")
                NavigationLink { GeneralBlockingView() } label: {
                    GridCard(symbol: "shield", title: tr("General blocking"),
                             subtitle: tr("deletion, websites"))
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Rules"))
        .onAppear { if model.inTutorial { model.tutorialScreen = "rules" } }
    }
}

// MARK: - General blocking grid

struct GeneralBlockingView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LazyVGrid(columns: gridCols, spacing: 14) {
                    NavigationLink {
                        BlockToggleEditor(
                            navTitle: tr("App deletion"),
                            title: tr("Block app deletion"),
                            isOn: { $0.blockAppRemoval },
                            makeAction: { .setBlockAppRemoval($0) },
                            footer: tr("When on, deleting ANY app from this iPhone is blocked — including Demora itself, so blocks can't be bypassed by uninstalling."))
                    } label: {
                        GridCard(symbol: "trash.slash", title: tr("App deletion"),
                                 subtitle: model.state.blockAppRemoval ? tr("On") : tr("Off"))
                    }
                    NavigationLink {
                        BlockToggleEditor(
                            navTitle: tr("Adult websites"),
                            title: tr("Block adult websites"),
                            isOn: { $0.blockAdultWebsites },
                            makeAction: { .setBlockAdultWebsites($0) },
                            footer: tr("Uses Apple's built-in filter to limit adult websites in Safari and other apps."))
                    } label: {
                        GridCard(symbol: "eye.slash", title: tr("Adult websites"),
                                 subtitle: model.state.blockAdultWebsites ? tr("On") : tr("Off"))
                    }
                    NavigationLink { WebsiteBlockerEditor() } label: {
                        GridCard(symbol: "globe", title: tr("Website blocker"),
                                 subtitle: model.state.blockedDomains.isEmpty
                                    ? tr("Off")
                                    : String(format: tr("%d sites"),
                                             model.state.blockedDomains.count))
                    }
                }
                Text(tr("Stop apps from being deleted, limit adult websites, or block specific sites by domain. Every change here goes through your delays."))
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("General blocking"))
    }
}

/// A queued on/off blocking toggle (app deletion, adult websites). Reads its
/// value live from state so the status reflects the latest applied change.
struct BlockToggleEditor: View {
    @EnvironmentObject var model: AppModel
    let navTitle: String
    let title: String
    let isOn: (LatchState) -> Bool
    let makeAction: (Bool) -> ChangeAction
    let footer: String

    var body: some View {
        let on = isOn(model.state)
        let action = makeAction(!on)
        let (dir, delay) = model.preview(action)
        Form {
            Section {
                HStack {
                    Text(title)
                    Spacer()
                    Text(on ? tr("On") : tr("Off")).foregroundStyle(.secondary)
                }
                Button(on ? tr("Queue: turn off") : tr("Queue: turn on")) {
                    model.queue(action)
                }
                Label(String(format: tr("%@ — takes effect in %@"),
                             dir.label, delay.shortDelayLabel),
                      systemImage: "clock")
                    .font(.footnote).foregroundStyle(.secondary)
            } footer: {
                Text(footer)
            }
        }
        .paper()
        .casedNavigationTitle(navTitle)
    }
}

/// Manual website blocklist — type raw domains instead of relying on Apple's
/// site picker. Adds/removes are queued through the usual delays.
struct WebsiteBlockerEditor: View {
    @EnvironmentObject var model: AppModel
    @State private var newDomain = ""

    private var blockedDomains: [String] { model.state.blockedDomains }

    private var canAdd: Bool {
        let d = ChangeEngine.normalizeDomain(newDomain)
        return d.contains(".")
            && !blockedDomains.contains { $0.caseInsensitiveCompare(d) == .orderedSame }
    }

    var body: some View {
        Form {
            Section {
                ForEach(blockedDomains, id: \.self) { domain in
                    HStack {
                        Text(domain)
                        Spacer()
                        Button(tr("Queue: remove")) {
                            model.queue(.removeBlockedDomain(domain))
                        }
                        .font(.footnote)
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField(tr("e.g. reddit.com"), text: $newDomain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button(tr("Add")) {
                        model.queue(.addBlockedDomain(newDomain))
                        newDomain = ""
                    }
                    .disabled(!canAdd)
                }
            } header: {
                Text(tr("Blocked sites"))
            } footer: {
                Text(tr("Block specific websites by typing their domain — no need for Apple's site picker, which often comes up empty. Note: blocking sites also turns on Apple's adult-content filter. Adding a site is gated by your delays; removing one waits the longer delay."))
            }
        }
        .paper()
        .casedNavigationTitle(tr("Website blocker"))
    }
}

// MARK: - Delay editor

struct DelayEditorView: View {
    enum Kind { case strict, lenient }
    let kind: Kind

    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var seconds: TimeInterval = 0

    private var current: TimeInterval {
        kind == .strict ? model.state.strictDelay : model.state.lenientDelay
    }
    private var action: ChangeAction {
        kind == .strict ? .setStrictDelay(seconds) : .setLenientDelay(seconds)
    }

    var body: some View {
        Form {
            Section {
                DelayPicker(title: kind == .strict
                            ? tr("More-strict delay") : tr("Less-strict delay"),
                            seconds: $seconds)
            } footer: {
                Text(String(format: tr("Current: %@"), current.shortDelayLabel))
            }
            if seconds != current && seconds > 0 {
                Section {
                    let (dir, delay) = model.preview(action)
                    Label(String(format: tr("%@ — takes effect in %@"),
                                 dir.label, delay.shortDelayLabel),
                          systemImage: "clock")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(tr("Queue change")) {
                        model.queue(action)
                        dismiss()
                    }
                }
            }
        }
        .paper()
        .casedNavigationTitle(tr("Delay"))
        .onAppear { seconds = current }
    }
}

// MARK: - Override editors

struct MathOverrideEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = false
    @State private var difficulty: MathDifficulty = .elementary
    @State private var count = 3
    @State private var wrong: MathWrongBehavior = .nothing

    var body: some View {
        Form {
            Toggle(tr("Enable math override"), isOn: $enabled)
            if enabled {
                Picker(tr("Difficulty"), selection: $difficulty) {
                    ForEach(MathDifficulty.allCases) { Text($0.label).tag($0) }
                }
                Picker(tr("Problems to solve"), selection: $count) {
                    ForEach(mathQuestionCountOptions, id: \.self) {
                        Text("\($0)").tag($0)
                    }
                }
                Picker(tr("If an answer is wrong"), selection: $wrong) {
                    ForEach(MathWrongBehavior.allCases) { Text($0.label).tag($0) }
                }
            }
            queueSection(
                model: model,
                action: .setMathOverride(enabled: enabled,
                                         difficulty: enabled ? difficulty : nil,
                                         count: count, wrong: wrong),
                changed: enabled != model.state.overrides.mathEnabled
                    || (enabled && (difficulty != model.state.overrides.mathDifficulty
                        || count != model.state.overrides.mathProblemCount
                        || wrong != model.state.overrides.mathWrongBehavior)),
                dismiss: dismiss
            )
        }
        .paper()
        .casedNavigationTitle(tr("Math override"))
        .onAppear {
            enabled = model.state.overrides.mathEnabled
            difficulty = model.state.overrides.mathDifficulty ?? .elementary
            let c = model.state.overrides.mathProblemCount
            count = mathQuestionCountOptions.contains(c) ? c : 3
            wrong = model.state.overrides.mathWrongBehavior
        }
    }
}

struct PasswordOverrideEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var changeError: String?

    private var matchOK: Bool { !password.isEmpty && password == confirm }

    var body: some View {
        Form {
            if model.state.overrides.passwordEnabled {
                // Knowing the current passcode lets you change it instantly.
                Section {
                    SecureField(tr("Current passcode"), text: $current)
                    SecureField(tr("New passcode"), text: $password)
                    SecureField(tr("Confirm new passcode"), text: $confirm)
                    if !password.isEmpty && password != confirm {
                        Text(tr("Passwords don't match"))
                            .font(.footnote).foregroundStyle(.red)
                    }
                    if let changeError {
                        Text(changeError).font(.footnote).foregroundStyle(.red)
                    }
                    Button(tr("Change passcode now")) { changeNow() }
                        .disabled(current.isEmpty || !matchOK)
                } header: {
                    Text(tr("Change passcode"))
                } footer: {
                    Text(tr("Enter your current passcode to change it instantly. Forgot it? Reset below — that one waits out your delay."))
                }

                // Forgot it → reset to a new passcode through the delay.
                Section {
                    let action = ChangeAction.setPasswordOverride(
                        enabled: true, passwordHash: AppModel.hash(password))
                    delayHint(action)
                    Button(tr("Reset passcode (forgot)")) {
                        model.queue(action); dismiss()
                    }
                    .disabled(!matchOK)
                } header: {
                    Text(tr("Forgot it?"))
                }

                // Turn the override off (delayed, stricter).
                Section {
                    let action = ChangeAction.setPasswordOverride(
                        enabled: false, passwordHash: nil)
                    delayHint(action)
                    Button(tr("Turn off password override"), role: .destructive) {
                        model.queue(action); dismiss()
                    }
                }
            } else {
                // Not enabled yet — enabling goes through the delay.
                Section {
                    SecureField(tr("New password"), text: $password)
                    SecureField(tr("Confirm password"), text: $confirm)
                    if !password.isEmpty && password != confirm {
                        Text(tr("Passwords don't match"))
                            .font(.footnote).foregroundStyle(.red)
                    }
                }
                queueSection(
                    model: model,
                    action: .setPasswordOverride(enabled: true,
                                                 passwordHash: AppModel.hash(password)),
                    changed: matchOK,
                    dismiss: dismiss
                )
            }
        }
        .paper()
        .casedNavigationTitle(tr("Password override"))
    }

    private func changeNow() {
        guard model.passwordMatches(current) else {
            changeError = tr("Wrong passcode."); return
        }
        model.setPasswordInstant(hash: AppModel.hash(password))
        dismiss()
    }

    private func delayHint(_ action: ChangeAction) -> some View {
        let (dir, delay) = model.preview(action)
        return Label(String(format: tr("%@ — takes effect in %@"),
                            dir.label, delay.shortDelayLabel), systemImage: "clock")
            .font(.footnote).foregroundStyle(.secondary)
    }
}

/// Shared "queue change" section with a strictness/delay hint.
@MainActor
func queueSection(model: AppModel, action: ChangeAction,
                  changed: Bool, dismiss: DismissAction) -> some View {
    Group {
        if changed {
            Section {
                let (dir, delay) = model.preview(action)
                Label(String(format: tr("%@ — takes effect in %@"),
                             dir.label, delay.shortDelayLabel),
                      systemImage: "clock")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(tr("Queue change")) {
                    model.queue(action)
                    dismiss()
                }
            }
        }
    }
}
