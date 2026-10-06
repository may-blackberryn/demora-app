import SwiftUI
import UIKit

/// Presentation only: separate from setup completion and migration state.
enum RedesignIntroGate {
    static func shouldShow(storageUnavailable: Bool, tutorialActive: Bool,
                           welcomeSeen: Bool, introSeen: Bool) -> Bool {
        !storageUnavailable && !tutorialActive && !welcomeSeen && !introSeen
    }
}

enum RedesignIntroPhase: Int, CaseIterable {
    case logo, wordmark, version, tagline

    var holdNanoseconds: UInt64 {
        switch self {
        case .logo: return 750_000_000
        case .wordmark: return 950_000_000
        case .version: return 800_000_000
        case .tagline: return 1_600_000_000
        }
    }
}

/// The same short opening for fresh setup, upgrades, and isolated dev previews.
/// Its owner decides whether to persist completion; this view never saves rules.
struct RedesignIntroView: View {
    let onComplete: () -> Void
    var isDemo = false
    var onClose: (() -> Void)? = nil
    @AppAccent private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase = RedesignIntroPhase.logo
    @State private var visible = false
    @State private var completed = false

    private var expanded: Bool { phase.rawValue >= RedesignIntroPhase.wordmark.rawValue }

    var body: some View {
        VStack(spacing: 0) {
            #if DEBUG
            if isDemo {
                DeveloperDemoNotice()
                if let onClose {
                    Button("Close", action: onClose).frame(minHeight: 44)
                }
            }
            #endif
            GeometryReader { geometry in
                let fontSize = min(52.0, max(28.0, (geometry.size.width - 48) / 4.3))
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        Spacer(minLength: 20)
                        if reduceMotion {
                            // Fixed geometry: only crossfade, no expanding mask,
                            // scaling logo, or horizontal movement.
                            ZStack {
                                logo(fontSize: fontSize).opacity(expanded ? 0 : 1)
                                heading(fontSize: fontSize, reveals: true)
                                    .opacity(expanded ? 1 : 0)
                            }
                        } else {
                            heading(fontSize: fontSize, reveals: expanded)
                                .offset(y: expanded ? 0 : 20)
                        }

                        Text(tr("more powerful, more intuitive"))
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(Ink.faint)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 24)
                            .opacity(phase == .tagline ? 1 : 0)
                            .offset(y: reduceMotion || phase == .tagline ? 0 : 10)
                        Spacer(minLength: 20)
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    .opacity(visible ? 1 : 0)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityTitle)
                }
            }
            Button(tr("Continue"), action: finish)
                .buttonStyle(.plain)
                .font(.system(.body, design: .serif))
                .foregroundStyle(Ink.faint)
                .frame(minWidth: 100, minHeight: 48)
                .padding(.bottom, 16)
        }
        .background(Ink.paper.ignoresSafeArea())
        .task(id: scenePhase) { await play() }
        .interactiveDismissDisabled()
    }

    private func logo(fontSize: CGFloat) -> some View {
        Image("DemoraLogo")
            .resizable().renderingMode(.template)
            .foregroundStyle(Ink.ink)
            .aspectRatio(contentMode: .fit)
            .frame(width: fontSize * 0.56, height: fontSize * 0.82)
    }

    private func wordmark(fontSize: CGFloat, reveals: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            logo(fontSize: fontSize)
                .scaleEffect(reduceMotion || reveals ? 1 : 1.45)
            IntroWordmarkReveal(progress: reveals ? 1 : 0) {
                Text("emora")
                    .font(.system(size: fontSize, weight: .regular, design: .serif))
                    .tracking(-1)
                    .foregroundStyle(Ink.ink)
                    .textCase(nil)
                    .fixedSize()
                    // Preserve serif ink overhang at the reveal's trailing edge.
                    .padding(.trailing, 2)
            }
                .alignmentGuide(.bottom) { $0[.lastTextBaseline] }
                .clipped()
                .opacity(reveals ? 1 : 0)
        }
    }

    private func heading(fontSize: CGFloat, reveals: Bool) -> some View {
        let showsVersion = phase.rawValue >= RedesignIntroPhase.version.rawValue
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            wordmark(fontSize: fontSize, reveals: reveals)
            Text("2.0")
                .font(.system(size: fontSize * 0.65, weight: .light, design: .serif))
                .foregroundStyle(accent)
                .fixedSize()
                .frame(width: reduceMotion || showsVersion ? fontSize * 1.1 : 0,
                       alignment: .trailing)
                .clipped()
                .opacity(showsVersion ? 1 : 0)
        }
    }

    private var accessibilityTitle: String {
        switch phase {
        case .logo, .wordmark: return "demora"
        case .version: return "demora 2.0"
        case .tagline: return "demora 2.0. " + tr("more powerful, more intuitive")
        }
    }

    @MainActor private func play() async {
        guard scenePhase == .active, !completed else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.4)) { visible = true }
        // SwiftUI cancels this task on dismissal/background. Resume from the
        // current phase when active again, rather than finishing off-screen.
        do {
            while !completed {
                try await Task.sleep(nanoseconds: phase.holdNanoseconds)
                try Task.checkCancellation()
                guard scenePhase == .active, !completed else { return }
                if phase == .tagline {
                    // Let VoiceOver users read at their own pace with Continue.
                    if !UIAccessibility.isVoiceOverRunning { finish() }
                    return
                }
                guard let next = RedesignIntroPhase(rawValue: phase.rawValue + 1) else { return }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2)
                              : .easeInOut(duration: 0.65)) { phase = next }
            }
        } catch { /* Cancellation must not consume the once-only marker. */ }
    }

    private func finish() {
        guard !completed else { return }
        completed = true
        onComplete()
    }
}

/// Animate the reveal window, never the text's intrinsic layout. Measuring on
/// each pass also follows font-size changes without a stale cached width.
private struct IntroWordmarkReveal: Layout {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let size = text.sizeThatFits(.unspecified)
        return CGSize(width: size.width * min(1, max(0, progress)), height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        guard let text = subviews.first else { return }
        let size = text.sizeThatFits(.unspecified)
        text.place(at: bounds.origin, anchor: .topLeading,
                   proposal: ProposedViewSize(width: size.width, height: size.height))
    }
}
