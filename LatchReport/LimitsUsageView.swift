//
//  LimitsUsageView.swift
//  The SwiftUI content the report extension renders — accurate per-limit
//  usage (minutes used today vs the budget), drawn as a progress bar.
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

    private var accent: Color {
        let red = accentColorRaw == "red"
        if red {
            return scheme == .dark
                ? Color(red: 0.85, green: 0.53, blue: 0.48)
                : Color(red: 0.64, green: 0.23, blue: 0.18)
        }
        return scheme == .dark
            ? Color(red: 0.63, green: 0.77, blue: 0.85)
            : Color(red: 0.20, green: 0.37, blue: 0.47)
    }

    private var warning: Color {
        scheme == .dark
            ? Color(red: 0.85, green: 0.53, blue: 0.48)
            : Color(red: 0.64, green: 0.23, blue: 0.18)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if rows.isEmpty {
                Text("No limits yet")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(rows) { r in
                let spent = r.usedMinutes >= r.budget
                let shown = max(0, r.usedMinutes)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(r.name)
                            .font(.system(.title3, design: .serif))
                            .lineLimit(2)
                        Spacer()
                        Text("\(shown)")
                            .font(.system(.title2, design: .serif).monospacedDigit())
                            .foregroundStyle(spent ? warning : accent)
                        Text("/ \(r.budget) min")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.secondary.opacity(0.2))
                                .frame(height: 1)
                            Rectangle().fill(spent ? warning : accent)
                                .frame(width: geo.size.width
                                    * min(1, Double(shown) / Double(max(1, r.budget))),
                                       height: 2)
                            HStack(spacing: 0) {
                                ForEach(0...20, id: \.self) { tick in
                                    if tick > 0 { Spacer(minLength: 0) }
                                    Rectangle().fill(Color.secondary.opacity(0.25))
                                        .frame(width: 1, height: tick % 5 == 0 ? 9 : 4)
                                }
                            }
                        }
                    }
                    .frame(height: 10)
                    if spent {
                        Label("Blocked", systemImage: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(warning)
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
