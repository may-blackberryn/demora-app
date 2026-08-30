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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Ink.accent)
                .serifDesign()
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
                }
                .onChange(of: appearanceRaw) { newValue in
                    SharedStore.defaults.set(newValue, forKey: "latch.appearance")
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                if !SharedStore.defaults.bool(forKey: "latch.healedRaceCondition") {
                    SharedStore.saveBlockedLimitIDs([])
                    ShieldController.refresh()
                    SharedStore.defaults.set(true, forKey: "latch.healedRaceCondition")
                }

                model.refreshAuthorization()
                model.tick()
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
    @State private var showLanguageExpansionUpdate = false
    @State private var wasSetUpAtLaunch = SharedStore.loadState().isSetUp
    @AppStorage("latch.languageExpansionUpdate.shown",
                store: SharedStore.defaults)
    private var languageExpansionUpdateShown = false
    @AppStorage("latch.languageExpansionUpdate.reviewRequested",
                store: SharedStore.defaults)
    private var languageExpansionReviewRequested = false

    /// During the tutorial, ignore manual tab taps (only programmatic
    /// step changes move tabs); otherwise pass through.
    private var tabSelection: Binding<Int> {
        Binding(get: { model.selectedTab },
                set: { if model.tutorial == nil { model.selectedTab = $0 } })
    }

    private var mainTabView: some View {
        TabView(selection: tabSelection) {
            HomeView()
                .tabItem { Label(tr("Home"), systemImage: "hourglass") }
                .badge(model.state.pending.count)
                .tag(0)
            LimitsView()
                .tabItem { Label(tr("Limits"), systemImage: "apps.iphone") }
                .tag(1)
            SchedulesView()
                .tabItem { Label(tr("Schedules"), systemImage: "calendar.badge.clock") }
                .tag(2)
            SettingsView()
                .tabItem { Label(tr("Settings"), systemImage: "gearshape") }
                .badge(model.incomingInviteCount)
                .tag(3)
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
            if model.state.isSetUp || model.tutorial != nil {
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
                    model.queueNotice != nil ? tr("Already pending")
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
        .onAppear { presentLanguageExpansionIfNeeded() }
        .fullScreenCover(
            isPresented: $showLanguageExpansionUpdate,
            onDismiss: requestLanguageExpansionReviewIfNeeded
        ) {
            LanguageExpansionUpdateView {
                languageExpansionUpdateShown = true
            }
        }
    }

    private func presentLanguageExpansionIfNeeded() {
        guard wasSetUpAtLaunch,
              model.tutorial == nil,
              !languageExpansionUpdateShown,
              !showLanguageExpansionUpdate else { return }
        showLanguageExpansionUpdate = true
    }

    private func requestLanguageExpansionReviewIfNeeded() {
        guard !languageExpansionReviewRequested else { return }
        languageExpansionReviewRequested = true
        // Let the update cover finish dismissing before asking StoreKit. Apple
        // retains final control over whether its native rating prompt appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            requestReview()
        }
    }
}
