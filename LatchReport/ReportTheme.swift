//
//  ReportTheme.swift
//  The foundations colours the report extension draws with
//  (docs/foundations-redesign.md §5.1, §8). The extension doesn't import the
//  app, so the values are copied from `InkPalette` in Latch/Theme.swift;
//  Tests/TodayPresentationHarness.py fails if the two drift apart.
//

import SwiftUI

/// One light/dark pair of sRGB hex values, as in `InkPalette`.
struct ReportInkPair {
    let light: UInt32
    let dark: UInt32
}

enum ReportPalette {
    static let ink         = ReportInkPair(light: 0x252E32, dark: 0xEFEDE5)
    static let inkSoft     = ReportInkPair(light: 0x5E6566, dark: 0xA5ADAE)
    static let hairline    = ReportInkPair(light: 0xDCDAD0, dark: 0x363D3F)
    static let accentBlue  = ReportInkPair(light: 0x325F79, dark: 0xA0C5D9)
    static let accentRed   = ReportInkPair(light: 0xA23B2E, dark: 0xD9877A)
    static let loosen      = ReportInkPair(light: 0xA23B2E, dark: 0xD9877A)
    static let loosenOchre = ReportInkPair(light: 0x8A5A12, dark: 0xD6A55C)
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
}
