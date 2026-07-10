//
//  LimitsUsageView.swift
//  The SwiftUI content the report extension renders — accurate per-limit
//  usage (minutes used today vs the budget), drawn as a progress bar.
//

import SwiftUI

struct LimitsUsageView: View {
    let rows: [LimitUsageRow]
    @Environment(\.colorScheme) private var systemScheme

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if rows.isEmpty {
                Text("No limits yet")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(rows) { r in
                let spent = r.usedMinutes >= r.budget
                let shown = min(r.usedMinutes, r.budget)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(r.name).font(.headline)
                        Spacer()
                        if spent {
                            Label("Blocked", systemImage: "lock.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                        } else {
                            Text("\(shown) / \(r.budget) min")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.25))
                            Capsule().fill(spent ? Color.orange : Color.accentColor)
                                .frame(width: max(3, geo.size.width
                                    * min(1, Double(shown) / Double(max(1, r.budget)))))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding()
        .serifIfAvailable()
        .environment(\.colorScheme, scheme)
    }
}

private extension View {
    /// `.fontDesign(.serif)` is iOS 16.1+; no-op on 16.0 (the extension's
    /// deployment target) so the usage report still builds and renders.
    @ViewBuilder func serifIfAvailable() -> some View {
        if #available(iOS 16.1, *) { self.fontDesign(.serif) } else { self }
    }
}
