//
//  ShieldConfigurationExtension.swift
//  Display-only, generic shield (redesign phase 1). No rule-name guesses,
//  state decoding, mutations or action delegate. The host owns all changes.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    private func latchShield() -> ShieldConfiguration {
        let ink = ShieldPalette.color(ShieldPalette.ink)
        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: ShieldPalette.color(ShieldPalette.paper),
            icon: shieldIcon(ink: ink),
            title: .init(text: tr("Blocked by your Demora rules"), color: ink),
            subtitle: .init(text: tr("You set this earlier so it would hold.")
                            + "\n\n"
                            + tr("Open Demora to see what's on, or to ask for extra time if your limit has it."),
                            color: ShieldPalette.color(ShieldPalette.inkSoft)),
            primaryButtonLabel: .init(text: tr("Close"), color: ShieldPalette.color(ShieldPalette.paper)),
            primaryButtonBackgroundColor: ShieldPalette.accent
        )
    }

    private func shieldIcon(ink: UIColor) -> UIImage? {
        // Use this target's own catalog. Thumbnailing bounds the display size
        // without changing the shared original asset or extracting app identity.
        let logo = UIImage(named: "DemoraLogo")?.preparingThumbnail(of: CGSize(width: 56, height: 56))
        let fallback = UIImage(systemName: "hourglass",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 56, weight: .light))
        return (logo ?? fallback)?.withTintColor(ink, renderingMode: .alwaysOriginal)
    }

    override func configuration(shielding application: Application)
        -> ShieldConfiguration { latchShield() }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory)
        -> ShieldConfiguration { latchShield() }

    override func configuration(shielding webDomain: WebDomain)
        -> ShieldConfiguration { latchShield() }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory)
        -> ShieldConfiguration { latchShield() }
}

/// Extension-local copy of the foundations palette. Parity and contrast are
/// checked without loading any rules. Appearance follows the system's traits;
/// the only shared preference read is the user's blue/brick accent.
enum ShieldPalette {
    struct Pair { let light: UInt32; let dark: UInt32 }
    static let paper = Pair(light: 0xF6F3EB, dark: 0x191C1D)
    static let ink = Pair(light: 0x252E32, dark: 0xEFEDE5)
    static let inkSoft = Pair(light: 0x5E6566, dark: 0xA5ADAE)
    static let accentBlue = Pair(light: 0x325F79, dark: 0xA0C5D9)
    static let accentRed = Pair(light: 0xA23B2E, dark: 0xD9877A)

    static var accent: UIColor {
        let choice = UserDefaults(suiteName: LatchConstants.appGroupID)?.string(forKey: "latch.accentColor")
        return color(choice == "red" ? accentRed : accentBlue)
    }

    static func color(_ pair: Pair) -> UIColor {
        UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? pair.dark : pair.light
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }
}
