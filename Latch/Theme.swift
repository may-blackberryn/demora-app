//
//  Theme.swift
//  Demora's daily-journal language: open paper, fine rules, time threads,
//  serif waits, and blue or brick-red ink. Colors adapt to light and dark.
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

// MARK: - Open navigation rows

/// Kept under its original name for existing destinations. Navigation now
/// reads like entries in a journal, rather than a dashboard of boxed tiles.
struct GridCard: View {
    @AppAccent private var accent
    let symbol: String
    let title: String
    let subtitle: String
    /// Shows a small red notification dot in the corner when true.
    var showsDot: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .light))
                    .foregroundStyle(accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.subheadline).foregroundStyle(Ink.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsDot {
                    Circle().fill(Ink.danger).frame(width: 7, height: 7)
                }
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Ink.faint)
            }
            .padding(.vertical, 22)
            Rectangle().fill(Ink.rule).frame(height: 1)
        }
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())
    }
}

/// A quiet wordmark and an unboxed, book-sized heading on each main tab.
struct DemoraPageTitle: View {
    let title: String
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 42

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Wordmark(size: 20)
                .foregroundStyle(Ink.faint)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: titleSize, weight: .regular, design: .serif))
                .tracking(-1.4)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A section label that visually separates content without a system Form header.
struct DemoraSectionTitle: View {
    @AppAccent private var accent
    let title: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(Ink.faint)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Ink.rule).frame(height: 1)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

struct DemoraPrimaryButtonStyle: ButtonStyle {
    @AppAccent private var accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .serif))
            .foregroundStyle(Ink.buttonText)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(accent, in: Capsule())
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The position within a calendar day, not a usage estimate. The little ink
/// mark moves with the actual clock; Screen Time progress stays in its report.
struct DemoraDayLine: View {
    @AppAccent private var accent
    let date: Date

    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                let hour = Calendar.current.component(.hour, from: date)
                let minute = Calendar.current.component(.minute, from: date)
                let position = CGFloat(hour * 60 + minute) / 1440
                var ticks = Path()
                for tick in 0...24 {
                    let x = CGFloat(tick) / 24 * size.width
                    ticks.move(to: CGPoint(x: x, y: 0))
                    ticks.addLine(to: CGPoint(x: x, y: tick % 6 == 0 ? 16 : 7))
                }
                context.stroke(ticks, with: .color(Ink.rule), lineWidth: 1)
                let marker = CGRect(x: position * size.width - 2, y: 0,
                                    width: 4, height: 23)
                context.fill(Path(roundedRect: marker, cornerRadius: 2),
                             with: .color(accent))
            }
            .frame(height: 24)
            HStack {
                Text("00")
                Spacer()
                Text(date, style: .time).foregroundStyle(accent)
                Spacer()
                Text("24")
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(Ink.faint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date, style: .time))
    }
}

/// Waits are the defining action in Demora, so they get the largest type,
/// rather than a small subtitle in the same tile as every other preference.
struct DemoraDelayRow: View {
    @AppAccent private var accent
    let title: String
    let duration: String
    let symbol: String
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline).foregroundStyle(Ink.faint)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.callout.weight(.light)).foregroundStyle(accent)
            }
            Text(duration)
                .font(.system(size: timeSize, weight: .regular, design: .serif))
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .demoraSurface()
        .contentShape(Rectangle())
    }
}

struct DemoraToggleStyle: ToggleStyle {
    @AppAccent private var accent
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 18) {
                configuration.label
                    .foregroundStyle(Ink.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().stroke(configuration.isOn ? accent : Ink.faint,
                                    lineWidth: 1.5)
                    if configuration.isOn {
                        Circle().fill(accent).padding(4)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Ink.buttonText)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? tr("On") : tr("Off"))
    }
}

/// A thread connects related events without enclosing each in a box.
struct DemoraTimelineMark: View {
    @AppAccent private var accent
    var color: Color? = nil
    var body: some View {
        VStack(spacing: 7) {
            Circle().stroke(color ?? accent, lineWidth: 1.5).frame(width: 9, height: 9)
            Rectangle().fill(Ink.rule).frame(width: 1)
        }
        .frame(width: 16)
        .padding(.top, 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Wordmark

/// "demora" with a teal initial — the app's wordmark. Always lowercase.
struct Wordmark: View {
    @AppAccent private var accent
    var size: CGFloat = 34
    var weight: Font.Weight = .regular
    var onDark = false

    var body: some View {
        (Text("d").foregroundColor(onDark ? $accent : accent)
         + Text("emora"))
            .font(.system(size: size, weight: weight, design: .serif))
            .textCase(.lowercase)
    }
}

// MARK: - Palette

private struct DemoraAccentColorKey: EnvironmentKey {
    static let defaultValue = "blue"
}

extension EnvironmentValues {
    var demoraAccentColor: String {
        get { self[DemoraAccentColorKey.self] }
        set { self[DemoraAccentColorKey.self] = newValue }
    }
}

/// Observe appearance through SwiftUI, not a non-reactive defaults lookup.
/// Changing color invalidates just the dependent views, preserving navigation,
/// sheet state, countdowns, and in-progress edits.
@propertyWrapper
struct AppAccent: DynamicProperty {
    @Environment(\.demoraAccentColor) private var rawValue
    var wrappedValue: Color { Ink.accent(for: rawValue) }
    var projectedValue: Color { Ink.accentOnDark(for: rawValue) }
}

enum Ink {
    static let paper  = dynamic(0xF6F3EB, 0x191C1D)
    static let ink    = dynamic(0x252E32, 0xEFEDE5)
    static let faint  = dynamic(0x656C6D, 0xA5ADAE)
    static let rule   = dynamic(0xD5D6CF, 0x3D4446)
    static let surface = dynamic(0xFFFCF5, 0x222829)
    static let hero = dynamic(0x222D2C, 0x303B39)
    static let heroText = Color(red: 0.97, green: 0.96, blue: 0.92)
    static let heroMuted = Color(red: 0.73, green: 0.80, blue: 0.77)
    static let buttonText = dynamic(0xFFFCF5, 0x171D1B)
    static var accentOnDark: Color {
        accentOnDark(for: SharedStore.defaults.string(forKey: "latch.accentColor") ?? "blue")
    }
    static func accentOnDark(for value: String) -> Color {
        value == "red"
            ? Color(red: 0.94, green: 0.63, blue: 0.56)
            : Color(red: 0.58, green: 0.82, blue: 0.84)
    }
    static var accent: Color {
        accent(for: SharedStore.defaults.string(forKey: "latch.accentColor") ?? "blue")
    }
    static func accent(for value: String) -> Color {
        value == "red"
            ? dynamic(0xA23B2E, 0xD9877A)
            : dynamic(0x325F79, 0xA0C5D9)
    }
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
    /// A section of the same page: a fine rule and breathing room. No separate
    /// background, shadow, or repeated rounded rectangle around each control.
    func demoraSurface() -> some View {
        self.padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(Ink.rule).frame(height: 1)
            }
    }

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
    @AppAccent private var accent
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
                        .stroke(accent, lineWidth: 2)
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
