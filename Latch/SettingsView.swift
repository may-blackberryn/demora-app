//
//  SettingsView.swift
//  Pages that outlived the Settings tab: limitations, the Guide, the
//  language picker, setup password editor and the website list. You
//  (YouView.swift) replaced the Settings root; every rule change is still
//  queued through the change engine.
//

import SwiftUI

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
                id: "delays", symbol: "timer", title: tr("Your waits"),
                summary: tr("choose a policy, manage pending changes"),
                sections: [
                    GuideSection(title: tr("Delay policy"), body: tr("Demora protects deliberate decisions with time. In Rules → Your waits, choose separate waits for stricter and less-strict changes, one shared wait, or immediate tightening with a wait only for loosening. Lowering a budget tightens it; raising or removing it loosens it. Changing the policy follows your current policy, not the new one.")),
                    GuideSection(title: tr("Pending changes"), body: tr("Changes on Today shows queued changes and their countdowns. Cancel one there before it applies, or skip its wait with an eligible way to skip a wait. Current rules stay active until the change applies. Existing countdowns keep their deadlines when you edit delay settings or reopen Demora. Background application depends on iOS callbacks; open Demora if a due change has not appeared."))
                ]),
            GuideTopic(
                id: "limits", symbol: "apps.iphone", title: tr("Limits"),
                summary: tr("daily app budgets"),
                sections: [
                    GuideSection(title: tr("Daily limit"), body: tr("In Rules, tap New rule → Daily limit, name a limit, choose apps, categories or websites, and set usage minutes. A group shares one allowance across its selection. Zero minutes blocks it all day. Open an existing limit to edit it. Different limits by weekday replaces the default budget on each chosen day. Daily allowances reset at midnight; on iOS 17.4 or later, earlier usage that day also counts.")),
                    GuideSection(title: tr("Split daily budget"), body: tr("Expand Split daily budget to divide the allowance into time-of-day portions, with optional carryover of unused early minutes. New limits can use three portions; existing two-portion limits remain editable. Spending an early portion blocks until its next boundary, even if later portions have minutes left. Editing a spent limit does not give it a fresh daily allowance. Selection edits follow the less-strict delay and can discard free-period credit tied to the old selection.")),
                    GuideSection(title: tr("Manual extra time"), body: tr("In a limit's editor, Manual extra time sets up to five ordered uses, each with its own usage minutes and a wait, named password, phrase or contact approval. Request a use on Today only after the full daily budget is spent. These are app-usage minutes, not a timed unblock session. Requests survive reopening Demora and reset at midnight. Extra time does not skip an early split portion, wake wait or unrelated block."))
                ]),
            GuideTopic(
                id: "daynight", symbol: "sun.max", title: tr("Day & night"),
                summary: tr("wake waits, latest times and sleep"),
                sections: [
                    GuideSection(title: tr("Day/night group"), body: tr("In Rules, tap New rule → Day & night to create up to five named groups. Check existing limits and choose extra apps, then set wake-up and sleep times and weekdays. One optional all-other-apps group automatically excludes explicitly timed groups; whole-category exceptions are not supported. Existing general wake/sleep settings and Group wake-up gates still apply alongside these groups.")),
                    GuideSection(title: tr("Wake up"), body: tr("Set a wake-up start and wait, with optional per-weekday start and wait overrides. Tap Wake up on Today to start every eligible group's wait together; tapping again does not restart it. An optional latest wake-up time, also configurable by weekday, ends only that wake gate even without a tap or during a wait. It does not end sleep blocking or restore a spent daily budget.")),
                    GuideSection(title: tr("Sleep"), body: tr("Sleep starts on the selected evening and ends at the following morning's wake-up start, using that morning's custom time. Group edits follow your delay policy. Wake timing edits preserve spent usage, split accounting, extra-time grants and a running wait's deadline; a new wait applies to the next tap. A delayed latest-time change can end today's gate once it applies. Turning the gate off is delay-gated too."))
                ]),
            GuideTopic(
                id: "schedules", symbol: "calendar", title: tr("Schedules"),
                summary: tr("recurring, planned, sessions"),
                sections: [
                    GuideSection(title: tr("Sessions"), body: tr("In Rules, tap New rule and choose Block now, Plan a block or Repeating block; Block now also sits at the bottom of Today. Create a block, unblock or free period. Block now starts after any required delay; its duration starts when it takes effect. Planned uses a specific date. Repeating runs daily, on weekdays or on a monthly pattern, and can cross midnight. Blocking rules can target selected apps or everything except a selection. Rules → Calendar shows occurrences.")),
                    GuideSection(title: tr("Free periods"), body: tr("A free period suspends daily limits within its scope, and usage during it is credited back using Screen Time checkpoints, not an exact live stopwatch. An unblock makes its selected apps usable but is not the same as free usage. Other overlapping rules can still block them. Recurring free periods live alongside recurring blocks. Edit apps on a recurring block keeps its identity and timing; the old selection stays active through the less-strict delay."))
                ]),
            GuideTopic(
                id: "conflicts", symbol: "arrow.triangle.branch", title: tr("Schedule conflicts"),
                summary: tr("overlaps, scopes and priority"),
                sections: [
                    GuideSection(title: tr("Potential overlaps"), body: tr("In Rules, tap Conflicts to review the next week's potential overlaps. Default application order is wake/sleep → recurring → planned → sessions. Later effects apply only within their scope: an allowlist is not a global unblock, does not reset daily usage, and does not clear unrelated specific blocks. Category membership is hidden by Apple, and untapped wake windows are estimates, so some overlaps are uncertain.")),
                    GuideSection(title: tr("Priority"), body: tr("Use Prioritize this to apply a rule after rules at default priority, or Restore default priority to undo that choice. Both actions always queue a less-strict change, even if you expect a stricter result. Among prioritized rules, the last one promoted applies last. Priority changes ordering, not a rule's app selection or your spent daily allowance."))
                ]),
            GuideTopic(
                id: "overrides", symbol: "key", title: tr("Ways to skip a wait"),
                summary: tr("contacts, passwords and phrases"),
                sections: [
                    GuideSection(title: tr("Passwords & phrases"), body: tr("Open You → Ways to skip a wait to add, change or remove named passwords and phrases. Each has its own allowed uses; it cannot approve an unrelated change. Phrases can be custom or random on-device words, typed word by word with your chosen mistake allowance. Adding one or expanding what it may skip waits through the less-strict delay. Knowing the current password permits an immediate secret-only change, not an immediate permissions change.")),
                    GuideSection(title: tr("Trusted contacts"), body: tr("Choose approval permissions separately for each contact. Extra-time permission is opt-in, including for existing contacts, and a limit's extra-time step must also require contact approval. Demora-user contacts accept an invitation before approving in their app. For email approval, enter the short code in your Demora. Permission edits are delay-gated; an approval skips only the eligible request's wait, not every rule."))
                ]),
            GuideTopic(
                id: "usage", symbol: "chart.bar", title: tr("Insights"),
                summary: tr("Screen Time reports and a personal baseline"),
                sections: [
                    GuideSection(title: tr("Usage reports"), body: tr("Open Insights for daily usage and comparisons of the past four complete seven-day periods, with today's partial day shown separately. It shows recent history provided by iOS, not a permanent archive. Missing or blank data is not zero usage; try Refresh. iCloud Screen Time sharing may include other devices of the same kind.")),
                    GuideSection(title: tr("Weekly baseline"), body: tr("In Insights → About this data, open Your starting point to add, change or remove your optional estimate. Enter hours and minutes per week, not per day; its date shows when it was recorded. This is your own estimate of usage before Demora, not a measured historical report or proof of time saved. Leaving it unset does not affect reports, rules or allowances."))
                ]),
            GuideTopic(
                id: "troubleshooting", symbol: "wrench.and.screwdriver", title: tr("Troubleshooting"),
                summary: tr("permissions, blank reports and false blocks"),
                sections: [
                    GuideSection(title: tr("Screen Time access"), body: tr("Blocking needs Screen Time permission. You may finish setup after declining it; Demora respects denial and does not automatically redirect you to iOS Settings. If you want to enable access later, use Demora's permission prompt or open iOS Settings yourself. iOS controls authorization and background callbacks, so blocking is not an unbypassable guarantee.")),
                    GuideSection(title: tr("Today's usage reporting"), body: tr("A blank Screen Time report does not mean no usage. Try the refresh arrow, wait for iOS to load, and check access if it stays blank. If a schedule, daily reset or due change seems late, open Demora to reconcile state. An enforcement warning means monitoring needs attention; if a new rule exceeds capacity, reduce overlapping schedules rather than assuming it was saved.")),
                    GuideSection(title: tr("Recheck blocked limits"), body: tr("In Rules, Recheck blocked limits takes around 30 seconds and keeps current blocks in place while iOS verifies usage. Confirmed spent limits stay blocked; a failed or interrupted check changes nothing. This is not a bypass for a real spent budget, split boundary, wake wait or schedule. Safe rechecking needs iOS 17.4 or later; wait until an active free period ends before trying."))
                ]),
            GuideTopic(
                id: "notifications", symbol: "bell", title: tr("Notifications & widgets"),
                summary: tr("optional reminders and privacy"),
                sections: [
                    GuideSection(title: tr("Notifications"), body: tr("In You → Notifications, choose five-minute limit warnings and optional free-period boundary reminders. Limit warnings are only for budgets longer than five minutes and are suppressed during free periods. iOS notification permission is separate from Screen Time access, and alerts can arrive late or not at all. Now & Next and Pending Change widgets are read-only summaries; they do not apply overrides or show raw usage.")),
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

// MARK: - Language

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

// MARK: - Always-on rules
// App deletion, adult websites and the website list live in Rules → Always
// on (docs/rules-redesign.md §8).

/// Manual website blocklist — type raw domains instead of relying on Apple's
/// site picker. Adds and removes go through the change receipt.
struct WebsiteBlockerEditor: View {
    @AppAccent private var accent
    @AppLoosen private var loosen
    @EnvironmentObject var model: AppModel
    @State private var newDomain = ""
    @State private var receipt: ChangeReceiptRequest?
    @FocusState private var addFocused: Bool
    /// Opened from New rule → Website: the address field starts focused.
    let focusAdd: Bool

    init(focusAdd: Bool = false) {
        self.focusAdd = focusAdd
    }

    private var blockedDomains: [String] { model.state.blockedDomains }

    /// A new address: not saved and not already waiting to be added.
    private var canAdd: Bool {
        let d = ChangeEngine.normalizeDomain(newDomain)
        return d.contains(".") && !rows.contains { ChangeEngine.normalizeDomain($0) == d }
    }

    /// Saved sites, then sites whose addition is still waiting, as the
    /// engine will save them.
    private var rows: [String] {
        var seen = Set(blockedDomains.map(ChangeEngine.normalizeDomain))
        let waiting = model.state.pending.compactMap { change -> String? in
            guard case .addBlockedDomain(let domain) = change.action else { return nil }
            let normalized = ChangeEngine.normalizeDomain(domain)
            return seen.insert(normalized).inserted ? normalized : nil
        }
        return blockedDomains + waiting
    }

    /// Each site's waiting add or remove, keyed as the engine saves it.
    private var waiting: [String: PendingChange] {
        var result: [String: PendingChange] = [:]
        for change in model.state.pending {
            switch change.action {
            case .addBlockedDomain(let domain), .removeBlockedDomain(let domain):
                result[ChangeEngine.normalizeDomain(domain)] = change
            default:
                continue
            }
        }
        return result
    }

    var body: some View {
        let pending = waiting
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                VStack(alignment: .leading, spacing: DemoraSpace.s) {
                    HStack(spacing: DemoraSpace.s) {
                        TextField(tr("e.g. reddit.com"), text: $newDomain)
                            .focused($addFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .frame(minHeight: 44)
                        Button(tr("Add")) {
                            // The engine saves the normalized address; queue
                            // that, so the same site can't wait twice.
                            receipt = ChangeReceiptRequest(
                                action: .addBlockedDomain(ChangeEngine.normalizeDomain(newDomain)))
                        }
                        .disabled(!canAdd)
                        .font(DemoraType.button)
                        .foregroundStyle(canAdd ? accent : Ink.inkSoft)
                        .frame(minHeight: 44)
                    }
                }
                .paperCard()
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
                        SectionHeader(tr("Blocked sites"))
                        ForEach(rows, id: \.self) { domain in
                            row(domain, pending: pending[ChangeEngine.normalizeDomain(domain)])
                        }
                    }
                }
                EditorNote(text: tr("Blocking any site also turns on Apple's adult-content filter."))
            }
            .padding(.horizontal, DemoraSpace.pageGutter)
            .padding(.vertical, DemoraSpace.l)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Websites"))
        .navigationBarTitleDisplayMode(.inline)
        .changeReceipt($receipt) { newDomain = "" }
        .onAppear { if focusAdd { addFocused = true } }
    }

    /// On this page a waiting change is about one site: added or removed.
    private func pendingLabel(_ change: PendingChange) -> String {
        if case .removeBlockedDomain = change.action { return RulePending.labelKey(.removed) }
        return RulePending.labelKey(.added)
    }

    private func row(_ domain: String, pending: PendingChange?) -> some View {
        let saved = blockedDomains.contains(domain)
        return VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
            HStack(spacing: DemoraSpace.s) {
                Text(domain)
                    .demoraType(.body)
                    .foregroundStyle(saved ? Ink.ink : Ink.inkSoft)
                Spacer(minLength: DemoraSpace.xs)
                if saved && pending == nil {
                    Button(tr("Remove")) {
                        receipt = ChangeReceiptRequest(action: .removeBlockedDomain(domain))
                    }
                    .buttonStyle(.plain)
                    .font(DemoraType.button)
                    .foregroundStyle(loosen)
                    .frame(minHeight: 44)
                }
            }
            if let pending {
                HStack(spacing: DemoraSpace.xxs) {
                    Image(systemName: "clock").accessibilityHidden(true)
                    Text(tr(pendingLabel(pending)))
                    CountdownText(to: pending.appliesAt, style: nil).monospacedDigit()
                }
                .demoraType(.meta)
                .foregroundStyle(pending.direction == .lenient ? loosen : accent)
            }
        }
        .frame(minHeight: 44)
        .paperCard()
    }
}
