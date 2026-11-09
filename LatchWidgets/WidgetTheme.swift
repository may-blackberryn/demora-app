import SwiftUI
import UIKit

// Local copies of the foundations in Latch/Theme.swift. The widget does not
// compile the host theme, localization engine, or rule engine.
struct WidgetInkPair {
    let light: UInt32
    let dark: UInt32
}

enum WidgetPalette {
    static let paper      = WidgetInkPair(light: 0xF6F3EB, dark: 0x191C1D)
    static let card       = WidgetInkPair(light: 0xFFFCF5, dark: 0x222829)
    static let ink        = WidgetInkPair(light: 0x252E32, dark: 0xEFEDE5)
    static let inkSoft    = WidgetInkPair(light: 0x5E6566, dark: 0xA5ADAE)
    static let hairline   = WidgetInkPair(light: 0xDCDAD0, dark: 0x363D3F)
    static let accentBlue = WidgetInkPair(light: 0x325F79, dark: 0xA0C5D9)
    static let accentRed  = WidgetInkPair(light: 0xA23B2E, dark: 0xD9877A)
    // Suffix denotes the selected accent, not the resulting warning color.
    static let loosenBlue = WidgetInkPair(light: 0xA23B2E, dark: 0xD9877A)
    static let loosenRed  = WidgetInkPair(light: 0x8A5A12, dark: 0xD6A55C)
    static let sage       = WidgetInkPair(light: 0x4F6F55, dark: 0x9DBFA3)
    static let tintLight: Double = 0.12
    static let tintDark: Double = 0.12
}

enum WidgetTheme {
    /// Read only; never fall back to the other build's suite or .standard.
    static func accentValue() -> String {
        #if DEBUG
        let groupID = "group.com.may.screentimedelay.dev"
        #else
        let groupID = "group.com.may.screentimedelay"
        #endif
        return UserDefaults(suiteName: groupID)?.string(forKey: "latch.accentColor") == "red"
            ? "red" : "blue"
    }

    static func color(_ pair: WidgetInkPair) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? pair.dark : pair.light
            return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                           green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        })
    }

    static func tint(_ pair: WidgetInkPair) -> Color {
        color(WidgetInkPair(
            light: blend(pair.light, over: WidgetPalette.card.light, amount: WidgetPalette.tintLight),
            dark: blend(pair.dark, over: WidgetPalette.card.dark, amount: WidgetPalette.tintDark)))
    }

    private static func blend(_ top: UInt32, over bottom: UInt32, amount: Double) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { result, shift in
            let a = Double((top >> UInt32(shift)) & 0xFF)
            let b = Double((bottom >> UInt32(shift)) & 0xFF)
            return result | (UInt32((a * amount + b * (1 - amount)).rounded()) << UInt32(shift))
        }
    }
}

enum WidgetInk {
    static let paper = WidgetTheme.color(WidgetPalette.paper)
    static let card = WidgetTheme.color(WidgetPalette.card)
    static let ink = WidgetTheme.color(WidgetPalette.ink)
    static let inkSoft = WidgetTheme.color(WidgetPalette.inkSoft)
    static let hairline = WidgetTheme.color(WidgetPalette.hairline)
    static let sage = WidgetTheme.color(WidgetPalette.sage)

    static func accentPair(for value: String) -> WidgetInkPair {
        value == "red" ? WidgetPalette.accentRed : WidgetPalette.accentBlue
    }

    static func loosenPair(for value: String) -> WidgetInkPair {
        value == "red" ? WidgetPalette.loosenRed : WidgetPalette.loosenBlue
    }
}

enum WidgetType {
    case cardTitle, time, timeLarge, meta, label, chip

    var font: Font {
        switch self {
        case .cardTitle: return .system(.headline, design: .serif).weight(.regular)
        case .time: return .system(.title3, design: .serif).monospacedDigit()
        case .timeLarge: return .system(.largeTitle, design: .serif).monospacedDigit()
        case .meta: return .system(.subheadline, design: .default)
        case .label: return .system(.footnote, design: .default).weight(.medium).smallCaps()
        case .chip: return .system(.caption, design: .default).weight(.medium)
        }
    }
}

extension View {
    func widgetType(_ type: WidgetType) -> some View {
        font(type.font).tracking(type == .label ? 0.6 : 0)
    }
}
