//
//  LatchApp.swift
//  App entry point. Applies any due pending changes every time the app
//  comes to the foreground, so countdowns resolve even if a background
//  DeviceActivity callback was missed.
//

import SwiftUI
import UIKit
import StoreKit
import WidgetKit

@main
struct LatchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("textCasing") private var textCasingRaw = TextCasing.fallback.rawValue
    @AppStorage("latch.accentColor", store: SharedStore.defaults)
    private var accentColorRaw = "blue"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environment(\.demoraAccentColor, accentColorRaw)
                .tint(Ink.accent(for: accentColorRaw))
                .serifDesign()
                .toggleStyle(DemoraToggleStyle())
                .textCase(TextCasing.resolved(textCasingRaw).textCase)
                .environment(\.locale, model.language.locale)
                .preferredColorScheme(
                    (Appearance(rawValue: appearanceRaw) ?? .system).colorScheme)
                // Hidden screenshot helper: tap to flip light ⇄ dark. Invisible.
                // Top-center on iPhone (over the wordmark); on iPad the tab bar
                // and nav sit at the top, so it lives at the bottom-center there.
                // DEBUG-only so it never ships to TestFlight / the App Store —
                // users set the theme in Settings → Appearance instead.
                #if DEBUG
                .overlay(alignment: UIDevice.current.userInterfaceIdiom == .pad
                         ? .bottomLeading : .top) {
                    Color.clear
                        .frame(width: 160, height: 44)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let cur = Appearance(rawValue: appearanceRaw) ?? .system
                            appearanceRaw = (cur == .dark ? Appearance.light
                                                          : Appearance.dark).rawValue
                        }
                        .accessibilityHidden(true)
                }
                #endif
                // Mirror the chosen appearance into the App Group so the
                // Screen Time report extension (separate process) can match it.
                .onAppear {
                    SharedStore.defaults.set(appearanceRaw, forKey: "latch.appearance")
                    DemoraWidgetSnapshot.publish(state: SharedStore.loadState())
                }
                .onChange(of: appearanceRaw) { newValue in
                    SharedStore.defaults.set(newValue, forKey: "latch.appearance")
                }
                .onChange(of: accentColorRaw) { _ in
                    WidgetCenter.shared.reloadAllTimelines()
                }
        }
        .onChange(of: scenePhase) { phase in
            guard !model.setupStorageUnavailable else { return }
            if phase == .active {
                if !SharedStore.defaults.bool(forKey: "latch.healedRaceCondition") {
                    SharedStore.saveBlockedLimitIDs([])
                    ShieldController.refresh()
                    SharedStore.defaults.set(true, forKey: "latch.healedRaceCondition")
                }

                model.refreshAuthorization()
                model.tick()
                DemoraNotifications.rescheduleFreeBoundaries(state: SharedStore.loadState())
                DemoraWidgetSnapshot.publish(state: SharedStore.loadState())
                // Self-heal monitors that iOS actually dropped or whose saved
                // configuration is outdated. Healthy monitors are left alone:
                // restarting them on every foreground entry exposed users to
                // iOS 26's premature DeviceActivity threshold regression.
                Task { await ChangeEngine.ensureMonitoringOffMain() }
            }
            if phase == .background {
                // Keep the overnight background-refresh request freshly queued.
                appDelegate.scheduleMidnightRefresh()
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @State private var widgetDestination: WidgetDestination?
    @State private var insightsHasOpened = false
    @AppStorage(SharedStore.redesignIntroKey, store: SharedStore.defaults)
    private var redesignIntroSeen = false
    @AppStorage(SharedStore.redesignWelcomeKey,
                store: SharedStore.defaults)
    private var redesignWelcomeSeen = false
    @AppStorage("latch.languageExpansionUpdate.reviewRequested", store: SharedStore.defaults)
    private var updateReviewRequested = false

    private var mainTabView: some View {
        VStack(spacing: 0) {
            ZStack {
                // Keep the private report hierarchies alive across tab changes.
                // Hidden hosts cancel refresh work and expose no hit/a11y targets.
                HomeView(widgetDestination: $widgetDestination)
                    .opacity(homeSelected ? 1 : 0)
                    .allowsHitTesting(homeSelected)
                    .accessibilityHidden(!homeSelected)
                if insightsHasOpened || model.selectedTab == 2 {
                    NavigationStack {
                        UsageInsightsView().toolbar(.hidden, for: .navigationBar)
                    }
                    .opacity(model.selectedTab == 2 ? 1 : 0)
                    .allowsHitTesting(model.selectedTab == 2)
                    .accessibilityHidden(model.selectedTab != 2)
                }
                if !homeSelected && model.selectedTab != 2 { currentTab }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            DemoraTabBar(selection: $model.selectedTab,
                         approvalCount: model.approvalInbox.count,
                         inviteCount: model.incomingInviteCount)
        }
        .background(Ink.paper.ignoresSafeArea())
        .onAppear { if model.selectedTab == 2 { insightsHasOpened = true } }
        .onChange(of: model.selectedTab) { tab in
            if tab == 2 { insightsHasOpened = true }
        }
        // Today owns its visible inbox poll. Elsewhere, fetch only the same
        // pending requests for a badge. Switching among other tabs does not
        // restart the task; backgrounding cancels it.
        .task(id: model.selectedTab != 0 && scenePhase == .active) {
            guard model.selectedTab != 0, scenePhase == .active else { return }
            while !Task.isCancelled {
                if let requests = try? await ContactsRelay.pendingRequestsForMe() {
                    guard !Task.isCancelled, model.selectedTab != 0,
                          scenePhase == .active else { return }
                    model.approvalInbox = requests
                }
                do { try await Task.sleep(nanoseconds: 30_000_000_000) }
                catch { return }
            }
        }
    }

    private var homeSelected: Bool { !(1...3).contains(model.selectedTab) }

    @ViewBuilder private var currentTab: some View {
        switch model.selectedTab {
        case 1: RulesView()
        case 3: YouView()
        default: EmptyView()
        }
    }

    var body: some View {
        Group {
            if model.setupStorageUnavailable {
                VStack(alignment: .leading, spacing: 24) {
                    DemoraPageTitle(title: tr("Your setup is safe"))
                    Text(tr("Demora could not finish reading or backing up your saved setup. Nothing has been reset. Try again, or contact hello@getdemora.app before reinstalling."))
                        .foregroundStyle(Ink.faint)
                    Button(tr("Try again")) { model.retrySetupStorage() }
                        .buttonStyle(DemoraPrimaryButtonStyle())
                    Link("hello@getdemora.app", destination: URL(string: "mailto:hello@getdemora.app")!)
                }
                .padding(26).frame(maxWidth: 640).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Ink.paper.ignoresSafeArea())
            } else if RedesignIntroGate.shouldShow(
                storageUnavailable: model.setupStorageUnavailable,
                welcomeSeen: redesignWelcomeSeen, introSeen: redesignIntroSeen
            ) {
                RedesignIntroView(variant: RedesignIntroGate.variant(isSetUp: model.state.isSetUp)) {
                    redesignIntroSeen = true
                }
            } else if model.state.isSetUp, !redesignWelcomeSeen {
                RedesignWelcomeView {
                    redesignWelcomeSeen = true
                    SharedStore.defaults.set(true, forKey: "latch.languageExpansionUpdate.shown")
                    requestUpdateReviewIfNeeded()
                }
            } else if model.state.isSetUp {
                mainTabView
                // tr() reads the language when a view evaluates, so rebuild
                // the tabs on a language change; navigation paths that must
                // survive live in AppModel, and the reports re-query anyway.
                .id(model.language)
                .alert(
                    model.queueNotice != nil ? tr(model.queueNoticeIsCapacity ? "Background monitoring limit" : "Already pending")
                                             : tr("Trusted contact removed"),
                    isPresented: Binding(
                        get: { model.queueNotice != nil || model.contactNotice != nil },
                        set: { if !$0 { model.queueNotice = nil; model.contactNotice = nil } }
                    )
                ) {
                    Button(tr("OK"), role: .cancel) {}
                } message: {
                    Text(model.queueNotice ?? model.contactNotice ?? "")
                }
            } else {
                OnboardingView()
            }
        }
        .onOpenURL { url in
            guard model.state.isSetUp, !model.setupStorageUnavailable,
                  let destination = WidgetDestination.parse(url) else { return }
            model.selectedTab = 0
            widgetDestination = destination
        }
    }

    private func requestUpdateReviewIfNeeded() {
        // Preserve the existing once-only post-update review opportunity.
        // StoreKit decides whether to show its prompt; never ask on each launch.
        guard redesignWelcomeSeen, !updateReviewRequested,
              !model.setupStorageUnavailable else { return }
        updateReviewRequested = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { requestReview() }
    }
}

/// The four destinations use the approved app-owned navigation bar
/// instead of the system TabView chrome. It leaves system permission sheets
/// and app pickers native, where replacing them would reduce accessibility.
/// Styled per docs/foundations-redesign.md §7 (equal items, icon above label,
/// selected in accent, others in inkSoft, paper with a top hairline); the
/// four destinations are sections, never rule actions.
private struct DemoraTabBar: View {
    @AppAccent private var accent
    @AppLoosen private var loosen
    @Binding var selection: Int
    let approvalCount: Int
    let inviteCount: Int

    private let items: [(Int, String, String)] = [
        (0, "Today", "sun.horizon"),
        (1, "Rules", "list.bullet.rectangle"),
        (2, "Insights", "chart.bar"),
        (3, "You", "person.crop.circle")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.0) { item in
                Button {
                    selection = item.0
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: item.2)
                                .font(.system(.body, design: .default))
                                .foregroundStyle(selection == item.0
                                                 ? accent : Ink.inkSoft)
                                .frame(width: 44, height: 26)
                            let count = item.0 == 0 ? approvalCount
                                : (item.0 == 3 ? inviteCount : 0)
                            if count > 0 {
                                Circle().fill(loosen)
                                    .frame(width: 7, height: 7)
                                    .offset(x: -2, y: 2)
                            }
                        }
                        Text(tr(item.1))
                            .font(.system(.caption2, design: .default)
                                .weight(selection == item.0 ? .semibold : .medium))
                            .foregroundStyle(selection == item.0
                                             ? accent : Ink.inkSoft)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr(item.1))
                .accessibilityValue(dotDescription(for: item.0))
                .accessibilityAddTraits(selection == item.0 ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(Ink.hairline).frame(height: 1)
        }
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .background(Ink.paper.ignoresSafeArea(edges: .bottom))
    }

    /// The dot is colour only; VoiceOver hears what it means.
    private func dotDescription(for tab: Int) -> String {
        if tab == 0 && approvalCount > 0 { return tr("Approval request waiting") }
        if tab == 3 && inviteCount > 0 { return tr("Invite waiting") }
        return ""
    }
}
