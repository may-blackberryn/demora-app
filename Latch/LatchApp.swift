//
//  LatchApp.swift
//  App entry point. Applies any due pending changes every time the app
//  comes to the foreground, so countdowns resolve even if a background
//  DeviceActivity callback was missed.
//

import SwiftUI
import UIKit

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
                // Re-register OS monitoring so the current limits/thresholds are
                // installed (e.g. includesPastActivity). Housekeeping's 30s tick
                // only reconfigures when a pending change is due, so without this
                // an already-spent limit never gets a threshold that can fire.
                ChangeEngine.reconfigureDailyMonitoring(state: SharedStore.loadState())
                model.refreshAuthorization()
                model.tick()
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tutorialHoles: [CGRect] = []

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
}
