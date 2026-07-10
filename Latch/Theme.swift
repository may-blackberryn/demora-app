//
//  Theme.swift
//  Editorial paper-and-ink look, matching the website: warm paper
//  background, serif type, a single teal accent. Colors adapt to
//  light/dark via dynamic providers.
//

import SwiftUI
import UIKit

// MARK: - Appearance setting

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return tr("System")
        case .light:  return tr("Light")
        case .dark:   return tr("Dark")
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Text case setting

/// Whether the app renders its text all-lowercase (the editorial default)
/// or in the regular case written in code. Applied once at the app root via
/// `.textCase()`, which cascades to every Text. The "demora" wordmark is
/// written lowercase, so it stays lowercase in either mode.
enum TextCasing: String, CaseIterable, Identifiable {
    case lower, regular

    var id: String { rawValue }
    var label: String {
        switch self {
        case .lower:   return tr("lowercase")
        case .regular: return tr("Regular")
        }
    }
    var textCase: Text.Case? { self == .lower ? .lowercase : nil }
}

// MARK: - Grid card

/// A square-ish tile used across the grid-style screens (Schedules, Settings).
struct GridCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    /// Shows a small red notification dot in the corner when true.
    var showsDot: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Ink.accent)
            Spacer(minLength: 12)
            Text(title).font(.headline).foregroundStyle(Ink.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(subtitle).font(.caption).foregroundStyle(Ink.faint)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .padding(16)
        .background(Ink.ink.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Ink.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            if showsDot {
                Circle().fill(Color.red)
                    .frame(width: 10, height: 10)
                    .padding(12)
            }
        }
    }
}

// MARK: - Wordmark

/// "demora" with a teal initial — the app's wordmark. Always lowercase.
struct Wordmark: View {
    var size: CGFloat = 34
    var weight: Font.Weight = .regular

    var body: some View {
        (Text("d").foregroundColor(Ink.accent) + Text("emora"))
            .font(.system(size: size, weight: weight, design: .serif))
            .textCase(.lowercase)
    }
}

// MARK: - Palette

enum Ink {
    static let paper  = dynamic(0xF1EDE3, 0x181714)
    static let ink    = dynamic(0x1D1D1B, 0xE9E4D8)
    static let faint  = dynamic(0x6F6A60, 0x948E80)
    static let rule   = dynamic(0xCFC8B9, 0x3A3730)
    static let accent = dynamic(0x1D5C63, 0x8EC4CA)
    /// Muted brick red for warnings/expiry — warm enough to sit in the paper
    /// palette rather than a neon system red.
    static let danger = dynamic(0xA23B2E, 0xD9877A)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Helpers

extension View {
    /// Paper background behind a List/Form.
    func paper() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Ink.paper.ignoresSafeArea())
    }

    /// New York serif app-wide; no-op on iOS 16.0 (modifier is 16.1+).
    @ViewBuilder
    func serifDesign() -> some View {
        if #available(iOS 16.1, *) {
            self.fontDesign(.serif)
        } else {
            self
        }
    }

    /// A navigation title that follows the app-wide text-case setting.
    /// The nav bar renders titles through UIKit, which ignores the global
    /// `.textCase`, so we lowercase the string ourselves when needed.
    func casedNavigationTitle(_ title: String) -> some View {
        modifier(CasedNavigationTitle(title: title))
    }

    /// A gently pulsing accent ring used to point the user at the next control
    /// during the guided tutorial. No-op (and no hit-testing impact) when off.
    func tutorialHighlight(_ active: Bool, ring: Bool = true,
                           cornerRadius: CGFloat = 16) -> some View {
        modifier(TutorialHighlight(active: active, ring: ring,
                                   cornerRadius: cornerRadius))
    }
}

/// A live M:SS countdown for a value that changes each second — used for the
/// tutorial's "ticks down then holds" countdown. Caller styles the font.
struct TutorialCountdownText: View {
    let remaining: () -> TimeInterval
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let t = Int(max(0, remaining()).rounded())
            Text(String(format: "%d:%02d", t / 60, t % 60)).monospacedDigit()
        }
    }
}

private struct TutorialHighlight: ViewModifier {
    let active: Bool
    var ring: Bool = true
    var cornerRadius: CGFloat = 16
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            // Report the target's frame so the blocker can leave a hole here.
            .background {
                if active {
                    GeometryReader { geo in
                        Color.clear.preference(key: TutorialHoleKey.self,
                                               value: [geo.frame(in: .global)])
                    }
                }
            }
            .overlay {
                if active && ring {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Ink.accent, lineWidth: 2)
                        .opacity(pulse ? 0.25 : 1)
                        .padding(-2)
                        .allowsHitTesting(false)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.9)
                                .repeatForever(autoreverses: true)) { pulse = true }
                        }
                }
            }
    }
}

/// Collects the global frame(s) of the currently-highlighted tutorial target(s).
struct TutorialHoleKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value += nextValue()
    }
}

/// A near-invisible layer that swallows taps everywhere except over the
/// highlighted control(s), so during the tutorial only the intended target is
/// tappable. Sheets present above this, so they stay fully interactive.
struct TutorialBlocker: View {
    let holes: [CGRect]

    private func unionOf(_ rects: [CGRect]) -> CGRect? {
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    var body: some View {
        GeometryReader { geo in
            let full = geo.frame(in: .global)
            // Keep every highlight that touches the screen (a midpoint test drops
            // edge-aligned targets on iPad). Leaving genuine GAPS — rather than a
            // covering view with a cut-out shape — guarantees the highlighted
            // controls receive taps reliably (no flaky hit-test pass-through).
            let visible = holes.filter { $0.intersects(full) }
            let top: CGFloat = 100
            if let union = unionOf(visible) {
                let h = CGRect(x: union.minX - full.minX, y: union.minY - full.minY,
                               width: union.width, height: union.height)
                    .insetBy(dx: -8, dy: -8)
                let bandTop = max(top, h.minY)
                ZStack(alignment: .topLeading) {
                    strip(0, top, full.width, h.minY - top)
                    strip(0, h.maxY, full.width, full.height - h.maxY)
                    strip(0, bandTop, h.minX, h.maxY - bandTop)
                    strip(h.maxX, bandTop, full.width - h.maxX, h.maxY - bandTop)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func strip(_ x: CGFloat, _ y: CGFloat,
                       _ w: CGFloat, _ h: CGFloat) -> some View {
        let ww = max(0, w), hh = max(0, h)
        return Color.black.opacity(0.001)
            .frame(width: ww, height: hh)
            .contentShape(Rectangle())
            .position(x: x + ww / 2, y: y + hh / 2)
    }
}

private struct CasedNavigationTitle: ViewModifier {
    @AppStorage("textCasing") private var textCasingRaw = TextCasing.lower.rawValue
    let title: String

    func body(content: Content) -> some View {
        content.navigationTitle(
            (TextCasing(rawValue: textCasingRaw) ?? .lower) == .lower
                ? title.lowercased() : title)
    }
}
