//
//  LatchApp.swift
//  App entry point. Applies any due pending changes every time the app
//  comes to the foreground, so countdowns resolve even if a background
//  DeviceActivity callback was missed.
//

import SwiftUI
import UIKit
import StoreKit

@main
struct LatchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("textCasing") private var textCasingRaw = TextCasing.lower.rawValue
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
                .textCase((TextCasing(rawValue: textCasingRaw) ?? .lower).textCase)
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
    @State private var tutorialHoles: [CGRect] = []
    @AppStorage(SharedStore.redesignIntroKey, store: SharedStore.defaults)
    private var redesignIntroSeen = false
    @AppStorage(SharedStore.redesignWelcomeKey,
                store: SharedStore.defaults)
    private var redesignWelcomeSeen = false
    @AppStorage("latch.languageExpansionUpdate.reviewRequested", store: SharedStore.defaults)
    private var updateReviewRequested = false

    private var mainTabView: some View {
        VStack(spacing: 0) {
            currentTab
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            DemoraTabBar(selection: $model.selectedTab,
                         locked: model.inTutorial,
                         pendingCount: model.state.pending.count,
                         inviteCount: model.incomingInviteCount)
        }
        .background(Ink.paper.ignoresSafeArea())
    }

    @ViewBuilder private var currentTab: some View {
        switch model.selectedTab {
        case 1: LimitsView()
        case 2: SchedulesView()
        case 3: SettingsView()
        case 4: DelaysOverridesTabView()
        default: HomeView()
        }
    }

    /// The single screen the tutorial is currently on (used on iPad, where the
    /// tab bar can't be reliably locked). Mirrors the tab tags.
    @ViewBuilder private var tutorialScreen: some View {
        switch model.selectedTab {
        case 1:  LimitsView()
        case 2:  SchedulesView()
        case 3:  SettingsView()
        default: HomeView()
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
                tutorialActive: model.tutorial != nil,
                welcomeSeen: redesignWelcomeSeen, introSeen: redesignIntroSeen
            ) {
                RedesignIntroView { redesignIntroSeen = true }
            } else if model.state.isSetUp, model.tutorial == nil, !redesignWelcomeSeen {
                RedesignWelcomeView {
                    redesignWelcomeSeen = true
                    SharedStore.defaults.set(true, forKey: "latch.languageExpansionUpdate.shown")
                    requestUpdateReviewIfNeeded()
                }
            } else if model.state.isSetUp || model.tutorial != nil {
                Group {
                    if model.tutorial != nil
                        && UIDevice.current.userInterfaceIdiom == .pad {
                        // No switchable tab bar during the tutorial on iPad — render
                        // only the active screen so the user can't tap to switch
                        // (iPadOS's top tab bar ignores the selection lock). The
                        // tutorial auto-navigates between screens itself.
                        tutorialScreen
                    } else {
                        mainTabView
                    }
                }
                .id(model.language)   // re-render everything on language change
                .onPreferenceChange(TutorialHoleKey.self) { tutorialHoles = $0 }
                .overlay {
                    if let t = model.tutorial, t != .configure {
                        TutorialBlocker(holes: tutorialHoles)
                    }
                }
                .overlay(alignment: .bottom) { TutorialCallout() }
                .overlay(alignment: .top) {
                    if let t = model.tutorial, t != .configure {
                        TutorialDemoBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .fullScreenCover(isPresented: Binding(
                    get: { model.tutorial == .configure },
                    set: { _ in })) {
                    TutorialFinishView()
                }
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

/// The five destinations in the redesign use an app-owned navigation bar
/// instead of the system TabView chrome. It leaves system permission sheets
/// and app pickers native, where replacing them would reduce accessibility.
private struct DemoraTabBar: View {
    @AppAccent private var accent
    @Binding var selection: Int
    let locked: Bool
    let pendingCount: Int
    let inviteCount: Int

    private let items: [(Int, String, String)] = [
        (4, "Delays", "hourglass"),
        (1, "Limits", "square.stack.3d.up"),
        (0, "Home", "house.fill"),
        (2, "Schedules", "calendar"),
        (3, "Settings", "slider.horizontal.3")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.0) { item in
                Button {
                    guard !locked else { return }
                    withAnimation(.easeInOut(duration: 0.18)) { selection = item.0 }
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: item.2)
                                .font(.system(size: item.0 == 0 ? 19 : 17,
                                              weight: .regular))
                                .foregroundStyle(selection == item.0
                                                 ? accent : Ink.faint)
                                .frame(width: 44, height: 26)
                            let count = item.0 == 0 ? pendingCount
                                : (item.0 == 3 ? inviteCount : 0)
                            if count > 0 {
                                Circle().fill(Ink.danger)
                                    .frame(width: 7, height: 7)
                                    .offset(x: -2, y: 2)
                            }
                        }
                        Text(tr(item.1))
                            .font(.system(size: 10, weight: selection == item.0
                                          ? .semibold : .regular, design: .monospaced))
                            .foregroundStyle(selection == item.0
                                             ? Ink.ink : Ink.faint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .overlay(alignment: .top) {
                        if selection == item.0 {
                            Rectangle().fill(accent).frame(width: 24, height: 2)
                                .offset(y: -10)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr(item.1))
                .accessibilityAddTraits(selection == item.0 ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(Ink.rule).frame(height: 1)
        }
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .background(Ink.paper.ignoresSafeArea(edges: .bottom))
    }
}
