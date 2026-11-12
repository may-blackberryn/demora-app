//
//  YouView.swift
//  The You page (docs/you-redesign.md §5, Y1): an invite when someone asked,
//  Ways to skip a wait, Approving for others, Notifications, App and a
//  footer. It is the fourth tab (tag 3). The decisions
//  live in YouPresentation.swift; this file reads the relay and preferences
//  in events and draws. Every rule change still goes through the receipt.
//

import SwiftUI
import UserNotifications

/// Pages pushed inside You.
enum YouRoute: Hashable {
    case appearance, preventDisabling, help, credits
    case yourCode, approveFor, blocked, requestsSent
    case way(SkipWayKind, UUID)
    /// The Changes ledger, scrolled to one change when given.
    case ledger(UUID?)
}

struct YouView: View {
    @AppAccent private var accent
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Read in events (appear, refresh, state change), never while drawing.
    @State private var invites: [ContactsRelay.IncomingInvite] = []
    @State private var grantsCount: Int?
    @State private var blockedCount = 0
    @State private var hasSentHistory = false
    @State private var outgoing: [ContactsRelay.OutgoingRequest] = []
    @State private var blockTarget: ContactsRelay.IncomingInvite?
    @State private var receipt: ChangeReceiptRequest?
    @State private var showAdd = false
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("textCasing") private var textCasingRaw = TextCasing.fallback.rawValue
    @AppStorage("latch.accentColor", store: SharedStore.defaults)
    private var accentColorRaw = "blue"

    var body: some View {
        NavigationStack(path: $model.youPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: DemoraSpace.sectionGap) {
                    Text(tr("You"))
                        .demoraType(.pageTitle)
                        .foregroundStyle(Ink.ink)
                        .accessibilityAddTraits(.isHeader)
                    if !invites.isEmpty {
                        VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
                            ForEach(invites) { invite in
                                InviteCard(invite: invite,
                                           onAccept: { respond(invite, accept: true) },
                                           onDecline: { respond(invite, accept: false) },
                                           onBlock: { blockTarget = invite })
                                    .transition(.opacity)
                            }
                        }
                    }
                    WaysToSkipSection(
                        onOpen: open,
                        onAdd: { showAdd = true },
                        onToggleContacts: { enabled in
                            receipt = ChangeReceiptRequest(action: .setContactsOverride(enabled: enabled))
                        },
                        showsSentLink: hasSentHistory
                            || !model.state.overrides.contacts.isEmpty,
                        onSent: { model.youPath.append(.requestsSent) })
                    approvingSection
                    NotificationsSection()
                    appSection
                    #if DEBUG
                    developerSection
                    #endif
                    footer
                }
                .padding(.horizontal, DemoraSpace.pageGutter)
                .padding(.top, DemoraSpace.xs)
                .padding(.bottom, DemoraSpace.xl)
                .frame(maxWidth: DemoraSpace.maxContentWidth)
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: invites.map(\.id))
            }
            .background(Ink.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await ContactsRelay.registerSelfIfNeeded()
                await reload()
            }
            .refreshable { await reload() }
            .onAppear { readLocal() }
            // The published value, not the state it is about to replace.
            .onReceive(model.$state) { readLocal(pending: $0.pending) }
            .navigationDestination(for: YouRoute.self) { route in
                destination(route).toolbar(.visible, for: .navigationBar)
            }
            .changeReceipt($receipt)
            .sheet(isPresented: $showAdd) { AddSkipWaySheet() }
            .confirmationDialog(tr("Block this person? They can't send you requests."),
                                isPresented: Binding(get: { blockTarget != nil },
                                                     set: { if !$0 { blockTarget = nil } }),
                                titleVisibility: .visible) {
                Button(tr("Block"), role: .destructive) {
                    if let invite = blockTarget {
                        ContactsRelay.block(invite.fromCode)
                        respond(invite, accept: false)
                    }
                    blockTarget = nil
                }
                Button(tr("Cancel"), role: .cancel) { blockTarget = nil }
            }
        }
    }

    // MARK: Approving for others (§5.4)

    private var approvingSection: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
            SectionHeader(tr("Approving for others"))
            VStack(spacing: 0) {
                YouNavigationRow(title: tr("Your code"), valueStyle: .time,
                                 value: ContactsRelay.myCode) {
                    model.youPath.append(.yourCode)
                }
                YouRowDivider()
                YouNavigationRow(title: tr("People you approve for"),
                                 value: grantsCount.map { $0.formatted() }) {
                    model.youPath.append(.approveFor)
                }
                if blockedCount > 0 {
                    YouRowDivider()
                    YouNavigationRow(title: tr("Blocked"), value: blockedCount.formatted()) {
                        model.youPath.append(.blocked)
                    }
                }
            }
            .paperCard(padding: 0)
        }
    }

    // MARK: App (§5.6)

    private var appSection: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
            SectionHeader(tr("App"))
            VStack(spacing: 0) {
                YouNavigationRow(title: tr("Appearance"), value: AppearanceSummary.text(
                    appearance: appearanceRaw, accent: accentColorRaw, casing: textCasingRaw)) {
                    model.youPath.append(.appearance)
                }
                YouRowDivider()
                YouNavigationRow(title: tr("Prevent disabling"),
                                 value: model.screenTimeCode.isEmpty ? nil : tr("Passcode saved")) {
                    model.youPath.append(.preventDisabling)
                }
                YouRowDivider()
                YouNavigationRow(title: tr("Help & guide")) {
                    model.youPath.append(.help)
                }
            }
            .paperCard(padding: 0)
        }
    }

    #if DEBUG
    private var developerSection: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
            SectionHeader("Developer")
            VStack(spacing: 0) {
                NavigationLink { DeveloperDemosView() } label: {
                    YouRowLabel(title: "Setup demos (debug)",
                                value: "new user + migration · nothing saves")
                }
                .buttonStyle(.plain)
                YouRowDivider()
                Button { model.debugFullReset() } label: {
                    YouRowLabel(title: "Reset app (debug)", value: "wipe + onboarding",
                                chevron: false)
                }
                .buttonStyle(.plain)
            }
            .paperCard(padding: 0)
        }
    }
    #endif

    // MARK: Footer (§5.7)

    private var footer: some View {
        VStack(spacing: DemoraSpace.xs) {
            Text(AppVersion.label)
                .demoraType(.meta)
                .foregroundStyle(Ink.inkSoft)
            HStack(spacing: DemoraSpace.s) {
                Link(tr("Privacy"), destination: AppVersion.privacyURL)
                Text("·").accessibilityHidden(true).foregroundStyle(Ink.inkSoft)
                Button(tr("Credits")) { model.youPath.append(.credits) }
                    .buttonStyle(.plain)
            }
            .demoraType(.meta)
            .foregroundStyle(accent)
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: Destinations

    @ViewBuilder private func destination(_ route: YouRoute) -> some View {
        switch route {
        case .appearance: AppearanceView()
        case .preventDisabling: PreventDisablingPage()
        case .help: HelpGuideView()
        case .credits: CreditsView()
        case .yourCode: MyInfoView()
        case .approveFor: ApproveForView()
        case .blocked: BlockedUsersView()
        case .requestsSent: SentHistoryView()
        case .way(let kind, let id): SkipWayDetailView(kind: kind, id: id)
        case .ledger(let id):
            ChangesLedgerView(outgoing: outgoing, onRequestsChanged: { readLocal() }, scrollTo: id)
        }
    }

    private func open(_ row: SkipWayRow) {
        if row.isPendingAddition {
            model.youPath.append(.ledger(row.pendingChangeID))
        } else {
            model.youPath.append(.way(row.kind, row.id))
        }
    }

    // MARK: Events

    /// Local reads: blocked count, sent history and sent requests for the
    /// ledger. Called on appear and when saved state changes.
    private func readLocal(pending: [PendingChange]? = nil) {
        blockedCount = ContactsRelay.blockedCodes().count
        hasSentHistory = !ContactsRelay.sentRequestHistory().isEmpty
        let pendingIDs = Set((pending ?? model.state.pending).map(\.id))
        outgoing = ContactsRelay.outgoingRequests().filter {
            $0.changeIds.contains(where: pendingIDs.contains)
        }
    }

    /// Invites and the people you approve for, from the relay. A failed fetch
    /// keeps what was last shown (offline is silent, and is not "no invites").
    private func reload() async {
        if let fetched = try? await ContactsRelay.incomingInvites() {
            invites = fetched
            model.incomingInviteCount = fetched.count
        }
        if let grants = try? await ContactsRelay.grantsToMe() { grantsCount = grants.count }
        readLocal()
    }

    private func respond(_ invite: ContactsRelay.IncomingInvite, accept: Bool) {
        invites.removeAll { $0.id == invite.id }
        model.incomingInviteCount = invites.count
        Task {
            try? await ContactsRelay.respondToInvite(invite, accept: accept)
            await reload()
        }
    }
}

extension SkipWayKind: Identifiable {
    var id: Self { self }
}

// MARK: - Invite card (§5.2)

private struct InviteCard: View {
    @AppAccent private var accent
    @Environment(\.demoraAccentColor) private var accentValue
    let invite: ContactsRelay.IncomingInvite
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onBlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.s) {
            Text(invite.fromName.isEmpty
                 ? String(format: tr("A Demora user (code %@) wants to add you as their trusted contact."), invite.fromCode)
                 : String(format: tr("%@ (code %@) wants to add you as their trusted contact."), invite.fromName, invite.fromCode))
                .demoraType(.body)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DemoraSpace.m) {
                Button(tr("Accept"), action: onAccept)
                    .font(DemoraType.button)
                    .foregroundStyle(Ink.paper)
                    .padding(.horizontal, DemoraSpace.m)
                    .frame(minHeight: 44)
                    .background(accent, in: Capsule())
                    .buttonStyle(.plain)
                Button(tr("Decline"), action: onDecline)
                    .buttonStyle(.plain)
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                    .frame(minHeight: 44)
                Text("·").foregroundStyle(Ink.inkSoft).accessibilityHidden(true)
                Button(tr("Block"), action: onBlock)
                    .buttonStyle(.plain)
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                    .frame(minHeight: 44)
            }
        }
        .paperCard(fill: Ink.tint(InkRole.accent.pair(accent: accentValue)))
    }
}

// MARK: - Notifications (§5.5, Y8)

private struct NotificationsSection: View {
    @AppLoosen private var loosen
    @AppStorage("latch.notifications.limitFiveMinutes.v1", store: SharedStore.defaults)
    private var limitWarnings = true
    @AppStorage("latch.notifications.freeBoundary.v1", store: SharedStore.defaults)
    private var freeWarnings = false
    @State private var notificationsAllowed = true

    var body: some View {
        VStack(alignment: .leading, spacing: DemoraSpace.cardGap) {
            SectionHeader(tr("Notifications"))
            VStack(spacing: 0) {
                Toggle(isOn: $limitWarnings) {
                    toggleLabel(tr("5 minutes left for a limit"),
                                tr("Only for limits longer than 5 minutes. No alert is sent during a free period."))
                }
                .padding(.horizontal, DemoraSpace.cardPadding)
                YouRowDivider()
                Toggle(isOn: $freeWarnings) {
                    toggleLabel(tr("Free period starts or ends in 5 minutes"),
                                tr("Optional reminders for scheduled free periods and free-session endings."))
                }
                .padding(.horizontal, DemoraSpace.cardPadding)
            }
            .toggleStyle(DemoraToggleStyle())
            .paperCard(padding: 0)
            if !notificationsAllowed {
                Text(tr("iOS notifications for Demora are off. You can turn them on in iOS Settings."))
                    .demoraType(.meta)
                    .foregroundStyle(loosen)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { Task { await refreshPermission() } }
        .onChange(of: limitWarnings) { enabled in
            if enabled { Task { await refreshPermission(requestIfPossible: true) } }
        }
        .onChange(of: freeWarnings) { _ in
            DemoraNotifications.rescheduleFreeBoundaries(state: SharedStore.loadState())
            if freeWarnings { Task { await refreshPermission(requestIfPossible: true) } }
        }
    }

    private func toggleLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: DemoraSpace.xxs) {
            Text(title).demoraType(.body).foregroundStyle(Ink.ink)
            Text(detail)
                .demoraType(.meta)
                .foregroundStyle(Ink.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DemoraSpace.s)
    }

    /// Same permission handling as before: ask once on the first enable,
    /// never redirect to iOS Settings.
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

// MARK: - Rows

/// A navigation row inside a You card: title, an optional value and a chevron.
struct YouNavigationRow: View {
    let title: String
    var valueStyle: DemoraType = .meta
    var value: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            YouRowLabel(title: title, value: value, valueStyle: valueStyle)
        }
        .buttonStyle(.plain)
    }
}

struct YouRowLabel: View {
    let title: String
    var value: String? = nil
    var valueStyle: DemoraType = .meta
    var chevron = true
    var titleColor: Color = Ink.ink

    var body: some View {
        HStack(spacing: DemoraSpace.s) {
            Text(title)
                .demoraType(.body)
                .foregroundStyle(titleColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DemoraSpace.xs)
            if let value {
                Text(value)
                    .demoraType(valueStyle)
                    .foregroundStyle(Ink.inkSoft)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.inkSoft)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, DemoraSpace.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct YouRowDivider: View {
    var heavy = false

    var body: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(height: 1)
            .padding(.leading, heavy ? 0 : DemoraSpace.cardPadding)
            .padding(.vertical, heavy ? DemoraSpace.xs : 0)
            .accessibilityHidden(true)
    }
}

// MARK: - Footer facts

enum AppVersion {
    /// "demora 2.0.0 (67)", from the bundle.
    static var label: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "demora \(version)" : "demora \(version) (\(build))"
    }

    /// The website's privacy page (it describes the disclosed relays).
    static let privacyURL = URL(string: "https://getdemora.app/privacy-policy.html")!
}

/// Third-party data bundled in the app, each shown as its attribution file
/// is written (English): the phrase word list and the country borders.
struct CreditsView: View {
    private struct Credit: Identifiable {
        let titleKey: String
        let resource: String
        let fallback: String
        var id: String { resource }
    }

    private static let credits = [
        Credit(titleKey: "Word list", resource: "WORDLIST_ATTRIBUTION",
               fallback: "The bundled word list is derived from the Electronic Frontier Foundation's long wordlist, created by Joseph Bonneau: https://www.eff.org/dice"),
        Credit(titleKey: "Country borders", resource: "COUNTRY_BORDERS_ATTRIBUTION",
               fallback: "Country borders: made with Natural Earth. Free vector and raster map data @ naturalearthdata.com."),
    ]

    @State private var texts: [String: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoraSpace.l) {
                ForEach(Self.credits) { credit in
                    VStack(alignment: .leading, spacing: DemoraSpace.xs) {
                        SectionHeader(tr(credit.titleKey))
                        Text(texts[credit.resource] ?? credit.fallback)
                            .demoraType(.body)
                            .foregroundStyle(Ink.ink)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .paperCard()
                    }
                }
            }
            .padding(.horizontal, DemoraSpace.pageGutter)
            .padding(.vertical, DemoraSpace.l)
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Credits"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // The bundled attribution files, shown as written (English).
            for credit in Self.credits {
                if let url = Bundle.main.url(forResource: credit.resource, withExtension: "md"),
                   let contents = try? String(contentsOf: url, encoding: .utf8) {
                    texts[credit.resource] = contents.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }
}
