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

/// Whether the app renders its text all-lowercase or in the regular case
/// written in code. Applied once at the app root via `.textCase()`, which
/// cascades to every Text. The "demora" wordmark is written lowercase, so it
/// stays lowercase in either mode.
///
/// Regular is the default (foundations decision F3). `@AppStorage` never
/// writes its default, so a stored value means the person picked a case in
/// onboarding or Settings, and that choice is kept.
enum TextCasing: String, CaseIterable, Identifiable {
    case lower, regular

    /// What people who never chose a case see.
    static let fallback = TextCasing.regular

    /// The stored choice, or the default when none (or an unreadable one) is stored.
    static func resolved(_ rawValue: String) -> TextCasing {
        TextCasing(rawValue: rawValue) ?? fallback
    }

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

/// Observe the "blocked / looser" ink through SwiftUI. It follows the accent:
/// brick with the blue accent, ochre with the red one, so blocked ≠ primary.
@propertyWrapper
struct AppLoosen: DynamicProperty {
    @Environment(\.demoraAccentColor) private var rawValue
    var wrappedValue: Color { Ink.loosen(for: rawValue) }
}

/// One light/dark pair of sRGB hex values. Kept as plain numbers so
/// `Tests/FoundationsContrastHarness.py` can check every pair for contrast.
struct InkPair {
    let light: UInt32
    let dark: UInt32
}

/// The foundations palette (docs/foundations-redesign.md §5.1). Edit values
/// here only, then run the contrast harness.
enum InkPalette {
    static let paper      = InkPair(light: 0xF6F3EB, dark: 0x191C1D)
    static let card       = InkPair(light: 0xFFFCF5, dark: 0x222829)
    static let cardRaised = InkPair(light: 0xFFFFFF, dark: 0x2A3133)
    static let ink        = InkPair(light: 0x252E32, dark: 0xEFEDE5)
    static let inkSoft    = InkPair(light: 0x5E6566, dark: 0xA5ADAE)
    static let hairline   = InkPair(light: 0xDCDAD0, dark: 0x363D3F)
    static let accentBlue = InkPair(light: 0x325F79, dark: 0xA0C5D9)
    static let accentRed  = InkPair(light: 0xA23B2E, dark: 0xD9877A)
    static let loosen     = InkPair(light: 0xA23B2E, dark: 0xD9877A)
    static let loosenOchre = InkPair(light: 0x8A5A12, dark: 0xD6A55C)
    static let free       = InkPair(light: 0x4F6F55, dark: 0x9DBFA3)
    /// Share of the ink laid over `card` for chip and receipt backgrounds.
    /// Dark uses 12 % too: the spec's 22 % left red and ochre text under 4.5:1.
    static let tintLight: Double = 0.12
    static let tintDark: Double = 0.12
}

enum Ink {
    static let paper      = dynamic(InkPalette.paper)
    static let card       = dynamic(InkPalette.card)
    static let cardRaised = dynamic(InkPalette.cardRaised)
    static let ink        = dynamic(InkPalette.ink)
    static let inkSoft    = dynamic(InkPalette.inkSoft)
    static let hairline   = dynamic(InkPalette.hairline)
    /// Free periods, "awake", allowed.
    static let free       = dynamic(InkPalette.free)

    // Old names, kept as thin aliases until each screen moves to the new ones.
    static let faint   = inkSoft
    static let rule    = hairline
    static let surface = card
    /// Retired by the foundations spec; still read by the current Home hero
    /// and buttons, so the old values stay until those screens move.
    static let hero = dynamic(0x222D2C, 0x303B39)
    static let heroText = Color(red: 0.97, green: 0.96, blue: 0.92)
    static let heroMuted = Color(red: 0.73, green: 0.80, blue: 0.77)
    static let buttonText = dynamic(0xFFFCF5, 0x171D1B)
    /// Old warning ink, unchanged so current screens look as they did. New
    /// work uses `loosen`, which turns ochre when the accent is red.
    static let danger = dynamic(InkPalette.loosen)

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
        dynamic(accentPair(for: value))
    }
    static func accentPair(for value: String) -> InkPair {
        value == "red" ? InkPalette.accentRed : InkPalette.accentBlue
    }

    /// Blocked, looser changes, removals. Prefer `@AppLoosen` in views.
    static func loosen(for accentValue: String) -> Color {
        dynamic(loosenPair(for: accentValue))
    }
    static func loosenPair(for accentValue: String) -> InkPair {
        accentValue == "red" ? InkPalette.loosenOchre : InkPalette.loosen
    }

    /// A chip or receipt background: the ink laid thinly over `card`. Text on
    /// a tint always uses the full-strength ink of the same pair.
    static func tint(_ pair: InkPair) -> Color {
        dynamic(InkPair(light: blend(pair.light, over: InkPalette.card.light,
                                     amount: InkPalette.tintLight),
                        dark: blend(pair.dark, over: InkPalette.card.dark,
                                    amount: InkPalette.tintDark)))
    }

    static func blend(_ top: UInt32, over bottom: UInt32, amount: Double) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { result, shift in
            let a = Double((top >> UInt32(shift)) & 0xFF)
            let b = Double((bottom >> UInt32(shift)) & 0xFF)
            let mixed = UInt32((a * amount + b * (1 - amount)).rounded())
            return result | (mixed << UInt32(shift))
        }
    }

    /// A light/dark pair as a SwiftUI colour.
    static func color(_ pair: InkPair) -> Color {
        dynamic(pair.light, pair.dark)
    }

    private static func dynamic(_ pair: InkPair) -> Color {
        color(pair)
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

/// Spacing, radius and width from docs/foundations-redesign.md §5.3.
enum DemoraSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let pageGutter: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let cardGap: CGFloat = 12
    static let sectionGap: CGFloat = 28
    static let maxContentWidth: CGFloat = 640
}

enum DemoraRadius {
    static let card: CGFloat = 20
    static let sheet: CGFloat = 28
}

// MARK: - Type

/// The type ladder from docs/foundations-redesign.md §5.2. Every style is
/// built on a Dynamic Type text style, so it scales with the user's setting.
/// Serif for names and times; SF Pro for sentences, metadata and labels.
/// SF Pro styles name `.default` explicitly so the app-wide serif design
/// (`serifDesign()` at the root) doesn't turn them into New York.
/// Apply with `.demoraType(_:)`, which also sets the style's tracking.
enum DemoraType {
    case pageTitle, hero, cardTitle, time, timeLarge, body, meta, label, chip

    var font: Font {
        switch self {
        case .pageTitle: return .system(.largeTitle, design: .serif)
        case .hero:      return .system(.title2, design: .serif)
        case .cardTitle: return .system(.headline, design: .serif).weight(.regular)
        case .time:      return .system(.title3, design: .serif).monospacedDigit()
        case .timeLarge: return .system(.largeTitle, design: .serif).monospacedDigit()
        case .body:      return .system(.body, design: .default)
        case .meta:      return .system(.subheadline, design: .default)
        case .label:     return .system(.footnote, design: .default).weight(.medium).smallCaps()
        case .chip:      return .system(.caption, design: .default).weight(.medium)
        }
    }

    /// Button labels: verb-first sentences, so SF Pro rather than the serif.
    static let button = Font.system(.body, design: .default).weight(.semibold)

    var tracking: CGFloat {
        switch self {
        case .pageTitle: return -0.6
        case .label:     return 0.6
        default:         return 0
        }
    }
}

extension View {
    /// Sets a `DemoraType` style's font and tracking.
    func demoraType(_ style: DemoraType) -> some View {
        font(style.font).tracking(style.tracking)
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
}

private struct CasedNavigationTitle: ViewModifier {
    @AppStorage("textCasing") private var textCasingRaw = TextCasing.fallback.rawValue
    let title: String

    func body(content: Content) -> some View {
        content.navigationTitle(
            TextCasing.resolved(textCasingRaw) == .lower
                ? title.lowercased() : title)
    }
}
