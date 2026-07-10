# Demora

App Store name: "Demora: Screen Time Delays". Internal project, target,
and identifier names remain "Latch" — they're invisible to users and
renaming them would churn signing, the App Group, and CloudKit for no gain.

Delay-based screen-time app for iOS. Instead of a password, every change to the configuration is classified as **stricter** or **less strict** and has to wait out a corresponding delay before it takes effect. Timers run in the background by wall clock.

## How it works

Two delays are set during onboarding: one gates changes that tighten the rules (adding a limit, lowering minutes, adding a schedule, enabling the deletion lock), the other gates changes that loosen them (raising a limit, removing a schedule, adding a free period, enabling an override). Changes to the delays themselves and to overrides are classified the same way.

Every change shows up on the Home tab as a pending change with a live countdown and can be cancelled before it applies. Optional overrides (math problems, a password, or a trusted contact's approval) skip a pending change's countdown.

Features:

- Per-app daily time limits enforced through `DeviceActivity` usage thresholds; apps are shielded via `ManagedSettings` until midnight once the budget runs out.
- Recurring daily schedules: block everything except an allowlist, or block only selected apps. Windows can cross midnight.
- Free periods: limits don't block during the window and usage inside it doesn't count toward them. Usage is tracked with silent checkpoint events (~5-minute granularity), since DeviceActivity doesn't report used minutes directly.
- One-off sessions: block or unblock selected apps for a fixed duration. Delay-gated like everything else; the duration starts once the delay elapses.
- App-deletion lock (`denyAppRemoval`) so blocks can't be bypassed by uninstalling.

## Targets

| Target | Purpose |
|---|---|
| `Latch` | SwiftUI app |
| `LatchMonitor` | `DeviceActivityMonitor` extension: thresholds, daily reset, applying changes in the background |
| `LatchShieldUI` | `ShieldConfiguration` extension: custom block screen |
| `Shared/` | Models, persistence, change engine (compiled into all three targets) |

## Setup

1. Requires Xcode 26+ and a physical device. FamilyControls does not work in the simulator.
2. Set the signing team on all three targets. Extension bundle IDs must keep the app's bundle ID as their prefix.
3. The App Group (`group.com.may.screentimedelay`) must match across all three `.entitlements` files and `LatchConstants.appGroupID` in `Shared/SharedModels.swift`.
4. Family Controls: the development entitlement works as-is; TestFlight/App Store distribution requires the distribution entitlement (https://developer.apple.com/contact/request/family-controls-distribution) and enabling the capability on each App ID.

## Known constraints

- DeviceActivity allows roughly 20 concurrently monitored activities; each pending change uses one one-shot activity. The app also applies due changes on every foreground as a fallback.
- Free-period usage tracking is checkpoint-based, so accounting is accurate to within one checkpoint (in the user's favor).
- A "minutes used so far" display is provided by the `LatchReport`
  `DeviceActivityReport` extension (shown on the Limits tab). The in-app
  checkpoint counter was unreliable cross-process; the report reads real usage.
