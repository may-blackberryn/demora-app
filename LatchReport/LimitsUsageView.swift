//
//  LimitsUsageView.swift
//  The SwiftUI content the report extension renders on Today — accurate
//  per-limit usage (minutes used today vs the budget) as one row per limit
//  (docs/today-redesign.md §5.5).
//

import SwiftUI

struct LimitsUsageView: View {
    let rows: [LimitUsageRow]
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage("latch.accentColor", store: UserDefaults(suiteName: AppGroup.id))
    private var accentColorRaw = "blue"

    /// Match the app's chosen appearance (shared via the App Group). The
    /// extension renders out-of-process and otherwise uses the system
    /// appearance, which can mismatch the app's forced light/dark and make
    /// the semantic text colors (.primary/.secondary) invisible.
    private var scheme: ColorScheme {
        switch UserDefaults(suiteName: AppGroup.id)?
            .string(forKey: "latch.appearance") {
        case "light": return .light
        case "dark":  return .dark
        default:      return systemScheme
        }
    }

    private func ink(_ pair: ReportInkPair) -> Color { ReportTheme.color(pair, scheme) }

    var body: some View {
        // The host owns a bounded viewport, not an estimated per-row height.
        // Scroll entirely inside the report sandbox; no usage/readiness/height
        // payload is written to the App Group or sent back to the host.
        ScrollView { reportContent }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.colorScheme, scheme)
    }

    private var reportContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if rows.isEmpty {
                Text(insightsText("No limits yet"))
                    .font(.system(.subheadline, design: .default))
                    .foregroundStyle(ink(ReportPalette.inkSoft))
            }
            ForEach(rows) { r in
                let spent = r.hasData && r.usedMinutes >= r.budget
                let shown = max(0, r.usedMinutes)
                let accent = ink(ReportTheme.accent(for: accentColorRaw))
                let loosen = ink(ReportTheme.loosen(for: accentColorRaw))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(r.name)
                            .font(.system(.headline, design: .serif).weight(.regular))
                            .foregroundStyle(ink(ReportPalette.ink))
                            .lineLimit(2)
                        Spacer()
                        // Missing is unknown, not zero.
                        Text(!r.hasData ? insightsText("No data yet")
                             : spent ? insightsText("Used up")
                             : String(format: insightsText("%d of %d min"), shown, r.budget))
                            .font(.system(.subheadline, design: .default).monospacedDigit())
                            .foregroundStyle(spent ? loosen : ink(ReportPalette.inkSoft))
                            .multilineTextAlignment(.trailing)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(ink(ReportPalette.hairline))
                            if r.hasData {
                                Capsule().fill(spent ? loosen : accent)
                                    .frame(width: geo.size.width * (spent ? 1
                                        : min(1, Double(shown) / Double(max(1, r.budget)))))
                            }
                        }
                    }
                    .frame(height: 6)
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
