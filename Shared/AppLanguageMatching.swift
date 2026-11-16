//
//  AppLanguageMatching.swift
//  Pure device-language matching for the in-app language (no preferences, no
//  Locale lookups), so the app, its extensions and the harness agree.
//  Tests/GenerateUsageLocalization.py copies the body between the BEGIN/END
//  markers into the report extension, which can't import Shared.
//

import Foundation

// BEGIN APP LANGUAGE MATCHING
nonisolated enum AppLanguageMatching {
    /// The first preferred identifier Demora supports, else English. Walks the
    /// whole list, as iOS does for the app's own localizations.
    static func code(preferred: [String], supported: Set<String>) -> String {
        for identifier in preferred {
            if let code = code(for: identifier, supported: supported) { return code }
        }
        return "en"
    }

    /// The supported app language for one identifier such as "pt-BR",
    /// "zh-Hant-TW", "zh_HK" or "nn-NO", or nil.
    static func code(for identifier: String, supported: Set<String>) -> String? {
        let parts = identifier.replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").map(String.init)
        guard let first = parts.first?.lowercased(), !first.isEmpty else { return nil }
        let subtags = parts.dropFirst()
        let script = subtags.first { $0.count == 4 && $0.allSatisfy(\.isLetter) }?.lowercased()
        let region = subtags.first {
            ($0.count == 2 && $0.allSatisfy(\.isLetter)) || ($0.count == 3 && $0.allSatisfy(\.isNumber))
        }?.uppercased()
        let candidate: String
        switch first {
        case "zh", "yue":
            // Script first; then the regions that write Traditional Chinese.
            if script == "hant" {
                candidate = "zh-Hant"
            } else if script == "hans" {
                candidate = "zh-Hans"
            } else if let region, ["TW", "HK", "MO"].contains(region) {
                candidate = "zh-Hant"
            } else {
                candidate = first == "yue" ? "zh-Hant" : "zh-Hans"
            }
        case "no", "nb", "nn":
            candidate = "nb"
        case "iw":
            candidate = "he"
        case "in":
            candidate = "id"
        case "pa" where script == "arab", "ms" where script == "arab":
            // Shahmukhi Punjabi and Jawi Malay: Demora's tables are Gurmukhi
            // and Latin, so keep looking.
            return nil
        default:
            candidate = first
        }
        return supported.contains(candidate) ? candidate : nil
    }
}
// END APP LANGUAGE MATCHING
