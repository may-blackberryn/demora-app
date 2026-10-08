//
//  SettingsView.swift
//  Language, the two delays, override methods, the app-deletion lock,
//  and beta credits. Every rule change is queued through the change
//  engine; language is cosmetic and switches after confirmation.
//

import SwiftUI
import UserNotifications

enum SettingsRoute: Hashable {
    case appearance, rules, delays, overrides, notifications, help, fineTuneOverrides
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack(path: $model.settingsPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DemoraPageTitle(title: tr("Settings"))
                    VStack(alignment: .leading, spacing: 0) {
                        NavigationLink(value: SettingsRoute.appearance) {
                            GridCard(symbol: "textformat.size",
                                     title: tr("Appearance"),
                                     subtitle: tr("language, theme, case"))
                        }
                        if model.inTutorial {
                            NavigationLink(value: SettingsRoute.rules) {
                                GridCard(symbol: "slider.horizontal.3", title: tr("Rules"),
                                         subtitle: tr("delays, overrides, blocking"))
                            }
                            .tutorialHighlight(model.tutorial == .addContact
                                               && model.tutorialScreen == "settings")
                        }
                        NavigationLink(value: SettingsRoute.notifications) {
                            GridCard(symbol: "bell", title: tr("Notifications"),
                                     subtitle: tr("limit and free-period alerts"))
                        }
                        NavigationLink(value: SettingsRoute.help) {
                            GridCard(symbol: "questionmark.circle", title: tr("Help"),
                                     subtitle: tr("guide, contact, more"))
                        }
                        if !model.inTutorial {
                            NavigationLink(value: SettingsRoute.fineTuneOverrides) {
                                GridCard(symbol: "slider.horizontal.3",
                                         title: tr("Fine-tune overrides"),
                                         subtitle: tr("trusted contacts and methods"))
                            }
                        }
                        #if DEBUG
                        if !model.inTutorial {
                            NavigationLink { DeveloperDemosView() } label: {
                                GridCard(symbol: "play.rectangle", title: "Setup demos (debug)",
                                         subtitle: "new user + migration · nothing saves")
                            }
                        }
                        Button { model.debugFullReset() } label: {
                            GridCard(symbol: "trash", title: "Reset app (debug)",
                                     subtitle: "wipe + onboarding")
                        }
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Ink.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if model.inTutorial && model.selectedTab == 3 {
                    model.tutorialScreen = "settings"
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .appearance:  AppearanceGridView().toolbar(.visible, for: .navigationBar)
                case .rules:       RulesGridView().toolbar(.visible, for: .navigationBar)
                case .delays:      DelaysGridView().toolbar(.visible, for: .navigationBar)
                case .overrides:   OverridesGridView().toolbar(.visible, for: .navigationBar)
                case .notifications: NotificationPreferencesView().toolbar(.visible, for: .navigationBar)
                case .help:        HelpHubView().toolbar(.visible, for: .navigationBar)
                case .fineTuneOverrides:
                    FineTuneOverridesView().toolbar(.visible, for: .navigationBar)
                }
            }
        }
    }

    private var overridesSubtitle: String {
        let o = model.state.overrides
        return o.contactsEnabled ? tr("trusted contacts on") : tr("none on")
    }

}

private struct NotificationPreferencesView: View {
    @AppStorage("latch.notifications.limitFiveMinutes.v1", store: SharedStore.defaults)
    private var limitWarnings = true
    @AppStorage("latch.notifications.freeBoundary.v1", store: SharedStore.defaults)
    private var freeWarnings = false
    @State private var notificationsAllowed = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DemoraPageTitle(title: tr("Notifications"))
                VStack(alignment: .leading, spacing: 12) {
                Toggle(tr("5 minutes left for a limit"), isOn: $limitWarnings)
                Text(tr("Only for limits longer than 5 minutes. No alert is sent during a free period."))
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
                .demoraSurface()
                VStack(alignment: .leading, spacing: 12) {
                Toggle(tr("Free period starts or ends in 5 minutes"),
                       isOn: $freeWarnings)
                Text(tr("Optional reminders for scheduled free periods and free-session endings."))
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
                .demoraSurface()
            if !notificationsAllowed {
                Text(tr("iOS notifications for Demora are off. Enable them in iOS Settings to receive alerts."))
                    .font(.footnote).foregroundStyle(Ink.danger)
                    .demoraSurface()
            }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Notifications"))
        .onAppear { Task { await refreshPermission() } }
        .onChange(of: limitWarnings) { enabled in
            if enabled { Task { await refreshPermission(requestIfPossible: true) } }
        }
        .onChange(of: freeWarnings) { _ in
            DemoraNotifications.rescheduleFreeBoundaries(state: SharedStore.loadState())
            if freeWarnings { Task { await refreshPermission(requestIfPossible: true) } }
        }
    }

    private func refreshPermission(requestIfPossible: Bool = false) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if requestIfPossible && settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let current = await center.notificationSettings()
        notificationsAllowed = current.authorizationStatus == .authorized
            || current.authorizationStatus == .provisional
    }
}

// MARK: - Help hub

struct HelpHubView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink { GuideView() } label: {
                    GridCard(symbol: "book", title: tr("Guide"),
                             subtitle: tr("how each part works"))
                }
                NavigationLink { LimitationsView() } label: {
                    GridCard(symbol: "exclamationmark.triangle", title: tr("Limitations"),
                             subtitle: tr("iOS reporting notes"))
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
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Help"))
    }
}

// MARK: - Limitations

/// Reference page for the informational notes shown around the app (which can be
/// dismissed where they appear). The pre-iOS-17.4 counting note only shows when
/// it actually applies to this device.
struct LimitationsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                limitation(
                    symbol: "clock.arrow.circlepath",
                    title: tr("Today's usage reporting"),
                    body: tr("Today's usage is reported by iOS Screen Time, which can be slow to load or briefly show nothing. If it looks empty, tap the refresh arrow a couple of times."))
                if #unavailable(iOS 17.4) {
                    limitation(
                        symbol: "calendar.badge.exclamationmark",
                        title: tr("Daily counting on older iOS"),
                        body: tr("Heads up: on your iOS version, a limit only counts screen time from the moment you add it — time you already spent earlier today isn't included. Update to iOS 17.4 or later for exact daily counting."))
                }
            }
            .padding(20).frame(maxWidth: 640)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Limitations"))
    }

    private func limitation(symbol: String, title: String,
                            body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline).foregroundStyle(Ink.ink)
            Text(body)
                .font(.body).foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Software roadmap

struct SoftwareRoadmapView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
    let sections: [GuideSection]
}

struct GuideSection {
    let title: String
    let body: String
}

struct GuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(topics) { topic in
                    NavigationLink { GuideTopicView(topic: topic) } label: {
                        GridCard(symbol: topic.symbol, title: topic.title,
                                 subtitle: topic.summary)
                    }
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Guide"))
    }

    // Built in-body so tr() reflects the current language.
    private var topics: [GuideTopic] {
        [
            GuideTopic(
                id: "delays", symbol: "timer", title: tr("Delays"),
                summary: tr("choose a policy, manage pending changes"),
                sections: [
                    GuideSection(title: tr("Delay policy"), body: tr("Demora protects deliberate decisions with time. In Delays, choose separate waits for stricter and less-strict changes, one shared wait, or immediate tightening with a wait only for loosening. Lowering a budget tightens it; raising or removing it loosens it. Changing the policy follows your current policy, not the new one.")),
                    GuideSection(title: tr("Pending changes"), body: tr("Home shows queued changes and their countdowns. Cancel a draft there before it applies, or use an eligible override. Current rules stay active until the change applies. Existing countdowns keep their deadlines when you edit delay settings or reopen Demora. Background application depends on iOS callbacks; open Demora if a due change has not appeared."))
                ]),
            GuideTopic(
                id: "limits", symbol: "apps.iphone", title: tr("Limits"),
                summary: tr("daily app budgets"),
                sections: [
                    GuideSection(title: tr("Daily limit"), body: tr("In Limits & blocks, tap New limit, name a limit, choose apps, categories or websites, and set usage minutes. A group shares one allowance across its selection. Zero minutes blocks it all day. Open an existing limit to edit it. Different limits by weekday replaces the default budget on each chosen day. Daily allowances reset at midnight; on iOS 17.4 or later, earlier usage that day also counts.")),
                    GuideSection(title: tr("Split daily budget"), body: tr("Expand Split daily budget to divide the allowance into time-of-day portions, with optional carryover of unused early minutes. New limits can use three portions; existing two-portion limits remain editable. Spending an early portion blocks until its next boundary, even if later portions have minutes left. Editing a spent limit does not give it a fresh daily allowance. Selection edits follow the less-strict delay and can discard free-period credit tied to the old selection.")),
                    GuideSection(title: tr("Manual extra time"), body: tr("Expand Manual extra time to set up to five ordered uses, each with its own usage minutes and a wait, named password, phrase or contact approval. Request a use from the limit only after the full daily budget is spent. These are app-usage minutes, not a timed unblock session. Requests survive reopening Demora and reset at midnight. Extra time does not skip an early split portion, wake wait or unrelated block."))
                ]),
            GuideTopic(
                id: "daynight", symbol: "sun.max", title: tr("Day & night"),
                summary: tr("wake waits, latest times and sleep"),
                sections: [
                    GuideSection(title: tr("Day/night group"), body: tr("Open Schedules → Day & night to create up to five named groups. Check existing limits and choose extra apps, then set wake-up and sleep times and weekdays. One optional all-other-apps group automatically excludes explicitly timed groups; whole-category exceptions are not supported. Existing general wake/sleep settings and Group wake-up gates still apply alongside these groups.")),
                    GuideSection(title: tr("Wake up"), body: tr("Set a wake-up start and wait, with optional per-weekday start and wait overrides. Tap Wake up on Home to start every eligible group's wait together; tapping again does not restart it. An optional latest wake-up time, also configurable by weekday, ends only that wake gate even without a tap or during a wait. It does not end sleep blocking or restore a spent daily budget.")),
                    GuideSection(title: tr("Sleep"), body: tr("Sleep starts on the selected evening and ends at the following morning's wake-up start, using that morning's custom time. Group edits follow your delay policy. Wake timing edits preserve spent usage, split accounting, extra-time grants and a running wait's deadline; a new wait applies to the next tap. A delayed latest-time change can end today's gate once it applies. Turning the gate off is delay-gated too."))
                ]),
            GuideTopic(
                id: "schedules", symbol: "calendar", title: tr("Schedules"),
                summary: tr("recurring, planned, sessions"),
                sections: [
                    GuideSection(title: tr("Sessions"), body: tr("Open Schedules → Sessions and choose Now, Planned or Recurring. Create a block, unblock or free period. Now starts after any required delay; its duration starts when it takes effect. Planned uses a specific date. Recurring repeats daily, on weekdays or on a monthly pattern, and can cross midnight. Blocking rules can target selected apps or everything except a selection. Calendar shows occurrences; Now & Next shows the next occurrence of each repeating rule.")),
                    GuideSection(title: tr("Free periods"), body: tr("A free period suspends daily limits within its scope, and usage during it is credited back using Screen Time checkpoints, not an exact live stopwatch. An unblock makes its selected apps usable but is not the same as free usage. Other overlapping rules can still block them. Recurring free periods live alongside recurring blocks. Edit apps on a recurring block keeps its identity and timing; the old selection stays active through the less-strict delay."))
                ]),
            GuideTopic(
                id: "conflicts", symbol: "arrow.triangle.branch", title: tr("Schedule conflicts"),
                summary: tr("overlaps, scopes and priority"),
                sections: [
                    GuideSection(title: tr("Potential overlaps"), body: tr("Open Schedules → Schedule conflicts to review the next week's potential overlaps. Default application order is wake/sleep → recurring → planned → sessions. Later effects apply only within their scope: an allowlist is not a global unblock, does not reset daily usage, and does not clear unrelated specific blocks. Category membership is hidden by Apple, and untapped wake windows are estimates, so some overlaps are uncertain.")),
                    GuideSection(title: tr("Priority"), body: tr("Use Prioritize this to apply a rule after rules at default priority, or Restore default priority to undo that choice. Both actions always queue a less-strict change, even if you expect a stricter result. Among prioritized rules, the last one promoted applies last. Priority changes ordering, not a rule's app selection or your spent daily allowance."))
                ]),
            GuideTopic(
                id: "overrides", symbol: "key", title: tr("Overrides"),
                summary: tr("named methods and per-contact permissions"),
                sections: [
                    GuideSection(title: tr("Passwords & phrases"), body: tr("Open Delays → Extra overrides, or Settings → Fine-tune overrides, to manage named passwords and phrases. Each method has its own allowed uses; it cannot approve an unrelated change. Phrases can be custom or random on-device words, typed word by word with your chosen mistake allowance. Adding methods or expanding permissions waits through the less-strict delay. Knowing the current password permits an immediate secret-only change, not an immediate permissions change.")),
                    GuideSection(title: tr("Trusted contacts"), body: tr("Choose approval permissions separately for each contact. Extra-time permission is opt-in, including for existing contacts, and a limit's extra-time step must also require contact approval. Demora-user contacts accept an invitation before approving in their app. For email approval, enter the short code in your Demora. Permission edits are delay-gated; an approval skips only the eligible request's wait, not every rule."))
                ]),
            GuideTopic(
                id: "usage", symbol: "chart.bar", title: tr("Usage & trends"),
                summary: tr("Screen Time reports and a personal baseline"),
                sections: [
                    GuideSection(title: tr("Usage reports"), body: tr("Open Home → Usage & trends for daily usage and comparisons of the past four complete seven-day periods, with today's partial day shown separately. It shows recent history provided by iOS, not a permanent archive. Missing or blank data is not zero usage; try Refresh. iCloud Screen Time sharing may include other devices of the same kind.")),
                    GuideSection(title: tr("Weekly baseline"), body: tr("In Home → Usage & trends, tap Edit weekly estimate to add, change or remove your optional starting point. Enter hours and minutes per week, not per day; its date shows when it was recorded. This is your own estimate of usage before Demora, not a measured historical report or proof of time saved. Leaving it unset does not affect reports, rules or allowances."))
                ]),
            GuideTopic(
                id: "troubleshooting", symbol: "wrench.and.screwdriver", title: tr("Troubleshooting"),
                summary: tr("permissions, blank reports and false blocks"),
                sections: [
                    GuideSection(title: tr("Screen Time access"), body: tr("Blocking needs Screen Time permission. You may finish setup after declining it; Demora respects denial and does not automatically redirect you to iOS Settings. If you want to enable access later, use Demora's permission prompt or open iOS Settings yourself. iOS controls authorization and background callbacks, so blocking is not an unbypassable guarantee.")),
                    GuideSection(title: tr("Today's usage reporting"), body: tr("A blank Screen Time report does not mean no usage. Try the refresh arrow, wait for iOS to load, and check access if it stays blank. If a schedule, daily reset or due change seems late, open Demora to reconcile state. An enforcement warning means monitoring needs attention; if a new rule exceeds capacity, reduce overlapping schedules rather than assuming it was saved.")),
                    GuideSection(title: tr("Recheck blocked limits"), body: tr("In Limits & blocks, Recheck blocked limits takes around 30 seconds and keeps current blocks in place while iOS verifies usage. Confirmed spent limits stay blocked; a failed or interrupted check changes nothing. This is not a bypass for a real spent budget, split boundary, wake wait or schedule. Safe rechecking needs iOS 17.4 or later; wait until an active free period ends before trying."))
                ]),
            GuideTopic(
                id: "notifications", symbol: "bell", title: tr("Notifications & widgets"),
                summary: tr("optional reminders and privacy"),
                sections: [
                    GuideSection(title: tr("Notifications"), body: tr("In Settings → Notifications, choose five-minute limit warnings and optional free-period boundary reminders. Limit warnings are only for budgets longer than five minutes and are suppressed during free periods. iOS notification permission is separate from Screen Time access, and alerts can arrive late or not at all. Now & Next and Pending Change widgets are read-only summaries; they do not apply overrides or show raw usage.")),
                    GuideSection(title: tr("Privacy"), body: tr("App choices and usage stay on-device. Demora has no accounts, advertising or analytics. Optional contact invitations and approval requests relay the names, descriptions and notes you send through CloudKit or Cloudflare and Resend; the email provider receives the readable message and code. Time checks contact Apple's website, and email requests use App Attest verification. Widgets use a small local summary, not app-selection tokens or raw usage.")),
                    GuideSection(title: tr("App deletion lock"), body: tr("The app deletion lock asks iOS to prevent deleting apps, including Demora. Turning it off is a less-strict change. It discourages one bypass route but does not make Screen Time permissions or the device impossible to change. Notifications and widgets are optional aids, not the enforcement mechanism."))
                ]),
        ]
    }
}

struct GuideTopicView: View {
    @AppAccent private var accent
    let topic: GuideTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: topic.symbol)
                    .font(.largeTitle).foregroundStyle(accent)
                ForEach(topic.sections.indices, id: \.self) { index in
                    let section = topic.sections[index]
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline).foregroundStyle(Ink.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(section.body)
                            .font(.body).foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
            VStack(alignment: .leading, spacing: 0) {
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

// MARK: - Appearance grid

struct AppearanceGridView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("textCasing") private var textCasingRaw = TextCasing.lower.rawValue
    @AppStorage("weekStartMonday") private var weekStartMonday = false
    @AppStorage("latch.accentColor", store: SharedStore.defaults)
    private var accentColorRaw = "blue"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink {
                    LanguagePickerView()
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
                    accentColorRaw = accentColorRaw == "red" ? "blue" : "red"
                } label: {
                    GridCard(symbol: "paintpalette", title: tr("App color"),
                             subtitle: accentColorRaw == "red"
                                ? tr("Red") : tr("Blue"))
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Appearance"))
    }
}

struct LanguagePickerView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedLanguage = AppLanguage.current
    @State private var showLanguageBetaNotice = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            selectedLanguage = language
                        } label: {
                            GridCard(symbol: selectedLanguage == language
                                     ? "checkmark.circle.fill" : "circle",
                                     title: language.label,
                                     subtitle: language.rawValue.uppercased())
                        }
                    }
                }

                Button(tr("Apply language")) { applyLanguage() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(selectedLanguage == model.language)
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Language"))
        .alert(tr("Translation in beta"),
               isPresented: $showLanguageBetaNotice) {
            Button(tr("OK"), role: .cancel) { }
        } message: {
            Text(tr("This language is in beta. Please report any mistranslations or unclear phrasing to hello@getdemora.app."))
        }
    }

    private func applyLanguage() {
        model.language = selectedLanguage
        if selectedLanguage.isBetaTranslation {
            showLanguageBetaNotice = true
        }
    }
}

// MARK: - Delays grid

struct DelaysGridView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            DelayPolicyNavigationRows()
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Delays"))
    }
}

/// First-class destination from the redesigned bottom navigation. Existing
/// delay and contact editors keep their queued-change semantics unchanged.
struct DelaysOverridesTabView: View {
    @AppAccent private var accent
    @EnvironmentObject var model: AppModel
    @State private var showAddContact = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        DemoraPageTitle(title: tr("Delays & overrides"))
                        Text(tr("Your rules can change—just not in the moment."))
                            .font(.subheadline).foregroundStyle(Ink.faint)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        DemoraSectionTitle(title: tr("Delays"), symbol: "hourglass")
                        DelayPolicyNavigationRows()
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        DemoraSectionTitle(title: tr("Overrides"), symbol: "person.2")
                        HStack {
                            Text(tr("Trusted contacts"))
                                .font(.system(.title3, design: .serif).weight(.semibold))
                            Spacer()
                            NavigationLink(tr("See all")) {
                                ContactsDetailView()
                                    .toolbar(.visible, for: .navigationBar)
                            }
                        }
                        ForEach(model.state.overrides.contacts.prefix(2)) { contact in
                            TrustedContactApprovalRow(contact: contact)
                        }
                        Button { showAddContact = true } label: {
                            Label(tr("Add contact…"),
                                  systemImage: "person.crop.circle.badge.plus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(accent)
                        .frame(minHeight: 44)
                        NavigationLink {
                            ContactsOverrideEditor()
                                .toolbar(.visible, for: .navigationBar)
                        } label: {
                            GridCard(symbol: "person.2", title: tr("Contact settings"),
                                     subtitle: model.state.overrides.contactsEnabled
                                        ? tr("On") : tr("Off"),
                                     showsDot: model.incomingInviteCount > 0)
                        }
                        NavigationLink {
                            ExtraOverridesView()
                                .toolbar(.visible, for: .navigationBar)
                        } label: {
                            GridCard(symbol: "key.horizontal",
                                     title: tr("Extra overrides"),
                                     subtitle: tr("passwords and phrases"))
                        }
                        NavigationLink {
                            FineTuneOverridesView()
                                .toolbar(.visible, for: .navigationBar)
                        } label: {
                            GridCard(symbol: "slider.horizontal.3",
                                     title: tr("Fine-tune overrides"),
                                     subtitle: tr("methods and permissions"))
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .background(Ink.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAddContact) { AddContactView() }
        }
    }
}

struct ExtraOverridesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NavigationLink { PasswordPoliciesView() } label: {
                    GridCard(symbol: "key", title: tr("Passwords"),
                             subtitle: tr("multiple passwords, separate permissions"))
                }
                NavigationLink { PhrasePoliciesView() } label: {
                    GridCard(symbol: "text.cursor", title: tr("Phrases"),
                             subtitle: tr("custom or random words, separate permissions"))
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Extra overrides"))
    }
}

struct FineTuneOverridesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NavigationLink { ContactsDetailView() } label: {
                    GridCard(symbol: "person.2", title: tr("Trusted contacts"),
                             subtitle: tr("Approval permissions"))
                }
                NavigationLink { PasswordPoliciesView() } label: {
                    GridCard(symbol: "key", title: tr("Passwords"),
                             subtitle: tr("separate permissions for each password"))
                }
                NavigationLink { PhrasePoliciesView() } label: {
                    GridCard(symbol: "text.cursor", title: tr("Phrases"),
                             subtitle: tr("separate permissions for each phrase"))
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Fine-tune overrides"))
    }
}

struct PasswordPoliciesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("Each password can unlock only the changes you choose. Adding or changing one waits through your less-strict delay."))
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(model.state.overrides.passwordPolicies) { policy in
                    NavigationLink { PasswordPolicyEditor(existing: policy) } label: {
                        GridCard(symbol: "key", title: policy.name,
                                 subtitle: policy.allowed.map(\.label).sorted().joined(separator: " · "))
                    }
                }
                NavigationLink { PasswordPolicyEditor(existing: nil) } label: {
                    Label(tr("Add password"), systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .demoraSurface()
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Passwords"))
    }
}

struct PasswordPolicyEditor: View {
    let existing: PasswordPolicy?
    /// Initial setup stages only a hash, never a plaintext password or a
    /// pending change. Ordinary policy edits keep the existing delay path.
    var onStage: ((PasswordPolicy) -> Void)? = nil
    var isDemo = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var draftID = UUID()
    @State private var password = ""
    @State private var confirm = ""
    @State private var current = ""
    @State private var instantError = false
    @State private var allowed: Set<OverrideCapability> = []
    @State private var loaded = false

    private var policy: PasswordPolicy {
        PasswordPolicy(id: existing?.id ?? draftID, name: name,
                       hash: password.isEmpty ? (existing?.hash ?? "")
                           : AppModel.hash(password), allowed: allowed)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                #if DEBUG
                if isDemo { DeveloperDemoNotice() }
                #endif
                TextField(tr("Name"), text: $name)
                SecureField(existing == nil ? tr("Password") : tr("New password (leave blank to keep)"),
                            text: $password)
                SecureField(tr("Confirm password"), text: $confirm)
                if let existing, onStage == nil {
                    SecureField(tr("Current password (for an immediate password-only change)"),
                                text: $current)
                    Button(tr("Change password now")) {
                        if model.updatePasswordPolicySecretNow(id: existing.id,
                                                               current: current,
                                                               newPassword: password) {
                            dismiss()
                        } else {
                            instantError = true
                        }
                    }
                    .disabled(current.isEmpty || password.isEmpty || password != confirm)
                    if instantError {
                        Text(tr("The current password is wrong or a change is already pending."))
                            .font(.footnote).foregroundStyle(.red)
                    }
                }
                Text(tr("Allowed uses")).font(.headline)
                ForEach(OverrideCapability.allCases) { area in
                    Toggle(area.label, isOn: Binding(
                        get: { allowed.contains(area) },
                        set: { enabled in
                            if enabled { allowed.insert(area) }
                            else { allowed.remove(area) }
                        }))
                }
                Button(onStage == nil ? tr("Queue change") : tr("Save")) {
                    if let onStage {
                        onStage(policy)
                        dismiss()
                    } else if model.queue(.upsertPasswordPolicy(policy)) != nil { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || allowed.isEmpty || (existing == nil && password.isEmpty)
                          || password != confirm || policy == existing)
                if let existing, onStage == nil {
                    Button(tr("Remove password"), role: .destructive) {
                        if model.queue(.removePasswordPolicy(id: existing.id)) != nil {
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
        .casedNavigationTitle(existing == nil ? tr("Add password") : tr("Edit password"))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = existing?.name ?? ""
            allowed = existing?.allowed ?? []
        }
    }
}

// MARK: - Overrides grid

struct OverridesGridView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
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
                Text(tr("A trusted contact can approve skipping a pending change's countdown. Turning this on waits through your less-strict delay."))
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
        return o.contactsEnabled ? tr("trusted contacts on") : tr("all off")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GeneralBlockingCards()
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

struct GeneralBlockingCards: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        .buttonStyle(.plain)
    }
}

/// A queued on/off blocking toggle (app deletion, adult websites). Reads its
/// value live from state so the status reflects the latest applied change.
struct BlockToggleEditor: View {
    @AppAccent private var accent
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(on ? tr("On") : tr("Off"))
                        .foregroundStyle(on ? accent : Ink.faint)
                }
                .font(.headline)
                Button(on ? tr("Queue: turn off") : tr("Queue: turn on")) {
                    model.queue(action)
                }
                .buttonStyle(.borderedProminent)
                Label(String(format: tr("%@ — takes effect in %@"),
                             dir.label, delay.shortDelayLabel),
                      systemImage: "clock")
                    .font(.footnote).foregroundStyle(Ink.faint)
                Text(footer)
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
            .demoraSurface()
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(tr("Blocked sites")).font(.headline)
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
                    .demoraSurface()
                }
                HStack {
                    TextField(tr("e.g. reddit.com"), text: $newDomain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textFieldStyle(.roundedBorder)
                    Button(tr("Add")) {
                        model.queue(.addBlockedDomain(newDomain))
                        newDomain = ""
                    }
                    .disabled(!canAdd)
                    .buttonStyle(.borderedProminent)
                }
                .demoraSurface()
                Text(tr("Block specific websites by typing their domain — no need for Apple's site picker, which often comes up empty. Note: blocking sites also turns on Apple's adult-content filter. Adding a site is gated by your delays; removing one waits the longer delay."))
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Website blocker"))
    }
}

// MARK: - Delay editor

struct DelayEditorView: View {
    enum Kind { case strict, lenient }
    let kind: Kind
    var body: some View { DelayPolicySettingsView() }
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
