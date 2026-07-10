//
//  ShieldConfigurationExtension.swift
//  LatchShieldUI — custom appearance for the block screen shown over
//  apps whose daily limit has been reached.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    private func latchShield() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.6),
            icon: UIImage(systemName: "hourglass.circle.fill"),
            title: .init(text: tr("Blocked by Demora"),
                         color: .white),
            subtitle: .init(text: tr("This app is blocked right now — by a limit, a schedule, or a session. Changing your rules takes a delay; open Demora to queue a change."),
                            color: UIColor.white.withAlphaComponent(0.8)),
            primaryButtonLabel: .init(text: tr("OK"), color: .black),
            primaryButtonBackgroundColor: .white
        )
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
