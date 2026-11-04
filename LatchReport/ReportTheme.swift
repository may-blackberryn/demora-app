//
//  ReportTheme.swift
//  The foundations tokens the report extension draws with
//  (docs/foundations-redesign.md §5.1–5.2, §8; docs/insights-redesign.md §7).
//  The extension doesn't import the app, so the values are copied from
//  `InkPalette` and `DemoraType` in Latch/Theme.swift;
//  Tests/TodayPresentationHarness.py and Tests/UsageDashboardHarness.py fail
//  if the copies drift apart. Preferences are only read here, never written.
//

import SwiftUI

/// One light/dark pair of sRGB hex values, as in `InkPalette`.
struct ReportInkPair {
    let light: UInt32
    let dark: UInt32
}

enum ReportPalette {
    static let paper       = ReportInkPair(light: 0xF6F3EB, dark: 0x191C1D)
    static let card        = ReportInkPair(light: 0xFFFCF5, dark: 0x222829)
    static let ink         = ReportInkPair(light: 0x252E32, dark: 0xEFEDE5)
    static let inkSoft     = ReportInkPair(light: 0x5E6566, dark: 0xA5ADAE)
    static let hairline    = ReportInkPair(light: 0xDCDAD0, dark: 0x363D3F)
    static let accentBlue  = ReportInkPair(light: 0x325F79, dark: 0xA0C5D9)
    static let accentRed   = ReportInkPair(light: 0xA23B2E, dark: 0xD9877A)
    static let loosen      = ReportInkPair(light: 0xA23B2E, dark: 0xD9877A)
    static let loosenOchre = ReportInkPair(light: 0x8A5A12, dark: 0xD6A55C)
    static let free        = ReportInkPair(light: 0x4F6F55, dark: 0x9DBFA3)
    /// Share of the ink laid over `card` for chip and receipt backgrounds.
    static let tintLight: Double = 0.12
    static let tintDark: Double = 0.12
}

enum ReportTheme {
    static func color(_ pair: ReportInkPair, _ scheme: ColorScheme) -> Color {
        let rgb = scheme == .dark ? pair.dark : pair.light
        return Color(red: Double((rgb >> 16) & 0xFF) / 255,
                     green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }

    /// The accent the person picked ("blue" or "red").
    static func accent(for value: String) -> ReportInkPair {
        value == "red" ? ReportPalette.accentRed : ReportPalette.accentBlue
    }

    /// Blocked / used up: brick, or ochre when the accent itself is red.
    static func loosen(for value: String) -> ReportInkPair {
        value == "red" ? ReportPalette.loosenOchre : ReportPalette.loosen
    }

    /// A chip or card tint: the ink laid thinly over `card`, as `Ink.tint`.
    static func tint(_ pair: ReportInkPair, _ scheme: ColorScheme) -> Color {
        color(ReportInkPair(light: blend(pair.light, over: ReportPalette.card.light, amount: ReportPalette.tintLight),
                            dark: blend(pair.dark, over: ReportPalette.card.dark, amount: ReportPalette.tintDark)), scheme)
    }

    static func blend(_ top: UInt32, over bottom: UInt32, amount: Double) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { result, shift in
            let a = Double((top >> UInt32(shift)) & 0xFF)
            let b = Double((bottom >> UInt32(shift)) & 0xFF)
            let mixed = UInt32((a * amount + b * (1 - amount)).rounded())
            return result | (mixed << UInt32(shift))
        }
    }
}

/// The app's appearance, accent and language, read (never written) from the
/// App Group, so the report draws like the app around it.
struct ReportPreferences {
    let scheme: ColorScheme
    let accentValue: String
    let locale: Locale

    static func read(system: ColorScheme) -> ReportPreferences {
        let defaults = UserDefaults(suiteName: AppGroup.id)
        let scheme: ColorScheme
        switch defaults?.string(forKey: "latch.appearance") {
        case "light": scheme = .light
        case "dark": scheme = .dark
        default: scheme = system
        }
        let supported = ["en", "es", "de", "fr", "pt", "pl", "tr", "hi"]
        let locale: Locale
        if let saved = defaults?.string(forKey: "latch.language"), supported.contains(saved) {
            locale = Locale(identifier: saved)
        } else {
            let preferred = Locale.preferredLanguages.first ?? "en"
            let code = Locale(identifier: preferred).language.languageCode?.identifier ?? String(preferred.prefix(2))
            locale = Locale(identifier: supported.contains(code) ? code : "en")
        }
        return ReportPreferences(scheme: scheme,
                                 accentValue: defaults?.string(forKey: "latch.accentColor") == "red" ? "red" : "blue",
                                 locale: locale)
    }
}

/// Resolved colours for one render.
struct ReportColors {
    let scheme: ColorScheme
    let accentValue: String
    var paper: Color { ReportTheme.color(ReportPalette.paper, scheme) }
    var card: Color { ReportTheme.color(ReportPalette.card, scheme) }
    var ink: Color { ReportTheme.color(ReportPalette.ink, scheme) }
    var inkSoft: Color { ReportTheme.color(ReportPalette.inkSoft, scheme) }
    var hairline: Color { ReportTheme.color(ReportPalette.hairline, scheme) }
    var accent: Color { ReportTheme.color(ReportTheme.accent(for: accentValue), scheme) }
    var accentTint: Color { ReportTheme.tint(ReportTheme.accent(for: accentValue), scheme) }
}

/// Foundations §5.2 type styles, copied from `DemoraType`.
enum ReportType {
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

    var tracking: CGFloat {
        switch self {
        case .pageTitle: return -0.6
        case .label:     return 0.6
        default:         return 0
        }
    }
}

extension View {
    func reportType(_ style: ReportType) -> some View {
        font(style.font).tracking(style.tracking)
    }

    /// The foundations paper card: card fill, 20 pt continuous corners,
    /// hairline border, no shadow.
    func reportCard(_ colors: ReportColors, padding: CGFloat = 16, fill: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill ?? colors.card, in: shape)
            .overlay(shape.strokeBorder(colors.hairline, lineWidth: 1))
    }
}

/// A quiet section label, as the app's `SectionHeader`.
struct ReportSectionHeader: View {
    let title: String
    let colors: ReportColors

    var body: some View {
        Text(title)
            .reportType(.label)
            .foregroundStyle(colors.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The neutral `StateChip`: inkSoft text in a hairline capsule. It marks
/// only what's incomplete ("Partly reported", decision I8).
struct ReportChip: View {
    let text: String
    let colors: ReportColors
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 24

    var body: some View {
        Text(text)
            .reportType(.chip)
            .lineLimit(1)
            .foregroundStyle(colors.inkSoft)
            .padding(.horizontal, 10)
            .frame(minHeight: height)
            .overlay(Capsule().strokeBorder(colors.hairline, lineWidth: 1))
    }
}
