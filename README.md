# Demora

App Store name: "Demora: Screen Time Delays". Internal project, target,
and identifier names remain "Latch" — they're invisible to users and
renaming them would churn signing, the App Group, and CloudKit for no gain.

Delay-based screen-time app for iOS. Every change to the configuration is classified as **stricter** or **less strict** and follows the user's delay policy. Timers run in the background by wall clock.

## How it works

The working-tree 2.0 setup offers three policies: separate waits for tightening
and loosening rules, one shared wait, or immediate tightening with a wait only
for loosening. Older installations keep their separate waits. Changing policy
is queued through the currently enforced policy; reducing either effective wait
is less strict. Pending countdowns keep their original deadlines. Changes to
overrides are classified in the same way as other rule edits.

Every change shows up on the Home tab as a pending change with a live countdown and can be cancelled before it applies. The only optional override is approval from a trusted contact. Saved math/password overrides and queued enable actions are retired on upgrade.

The in-progress redesign adds multiple scoped password and phrase overrides,
plus per-contact permissions for pending changes. The sentence
above describes the last released app, not this working tree.

Features:

- A once-only 2.0 opening before fresh setup or the upgrade welcome: the
  original Demora logo expands into the wordmark, followed by 2.0 and
  “more powerful, more intuitive”. Completion has its own marker, so closing
  later setup pages does not replay it. Reduce Motion uses gentle transitions;
  VoiceOver users continue at their own pace. Both debug setup previews replay
  it without changing real welcome markers or rules.
- A seven-step real first-run setup: purpose, delay policy, permissions, optional
  first limit, optional day/night groups, optional trusted contacts/phrases/passwords,
  and confirmation. Each override's allowed uses can be chosen before committing
  setup. Contacts remain unconfirmed and invitations follow the normal consent
  flow after setup; passwords persist only as hashes. Developer previews stage
  these choices without persistence or contact-service calls. Screen Time denial is respected; setup can
  finish without blocking. The sample walkthrough stays available in Help.
- Existing users get a separate four-page 2.0 introduction once
  completed. Migration keeps rule IDs, budgets, contact scopes, and pending
  deadlines, and backs up the saved blob before re-encoding. A legacy saved
  Screen Time passcode is verified in Keychain and removed from the blob before
  that backup. Unreadable state is retained and shown as a recovery issue rather
  than silently replaced with a fresh setup.
  Users with an enabled legacy math override also see an optional one-time
  phrase replacement: stage up to five phrases, choose their pending-change
  scopes, then install them together without a delay. This never grants new
  extra-time permission. Completing the welcome closes the offer; later
  additions/edits use normal delays. Stale pre-replacement saves are rejected.
  Configuration writes coordinate across app/extension processes, with
  notification/widget publication deferred until state coordination releases.
  The welcome also allows one immediate, additive initial day/night setup.
  It cannot change legacy gates, usage or pending deadlines, and its persisted
  completion flag rejects stale snapshots that would reopen the allowance.
  Skipping or completing the welcome closes the offer; later edits are delayed.

- Per-app daily time limits enforced through `DeviceActivity` usage thresholds; apps are shielded via `ManagedSettings` until midnight once the budget runs out.
- The apps, categories, and websites in an existing limit can be edited. Any
  selection change uses the less-strict delay, even if the minute budget also
  changes in that edit. A spent limit stays spent until midnight rather than
  receiving a fresh allowance from an edit.
- Limits can use a different budget for each weekday. A daily wake-up gate can
  keep the selected apps blocked until the user taps Wake up in Demora and the
  configured wait elapses. That tap is an intended daily action, not a rule
  edit; the gate and deadline survive app restarts.
- Schedules → Day & night supports up to five named groups. Each checks existing
  limits and/or selects extra apps, with its own wake wait, minute-granular
  day start, sleep start and weekdays. Optional per-weekday start/wait overrides
  fall back to the default times. Starts range from 00:00 to 23:30 so a boundary
  registration still fits Apple's minimum interval before midnight.
  Sleep ends at the following wake start, using that morning's custom time;
  sleep weekdays still refer to the evening when it starts.
  One Wake up tap starts all
  eligible groups, including legacy gates; repeated taps do not reset deadlines.
  One optional all-other-apps group has its own timing and additional exclusions,
  automatically exempting explicitly timed groups for the matching boundary.
  Overlapping explicit groups use the strictest rule. Screen Time cannot express
  category-wide exceptions, so fallback/category combinations are rejected,
  including later edits to referenced limits. A released wake wait does not clear
  a spent daily limit. New groups use separate named shield stores and shared,
  deduplicated boundary/release monitors; registration failures show the existing
  enforcement warning. Free periods/unblock sessions retain their explicit scope.
  Outside initial setup these changes follow Demora's delays. Physical-device
  background timing still requires testing.
- The Wake up page also configures each group's own daily wait, formerly
  inside the limit editor. Existing gates still default to midnight every day
  with their previous waits; new controls configure start, wait and weekdays,
  including per-day overrides, without resetting a running deadline. They
  participate in the shared tap; preserved general rules retain their own hour/weekdays.
  Overlapping gates both apply. Focused group edits retain budgets, usage,
  split credits, extra-time grants and the current wake deadline; new waits
  apply to the next tap. Enabling clears only its old tap, failing closed on
  runtime-write failure. Healthy daily fingerprints are rebased rather than
  restarting monitors; stale/missing monitors still self-heal normally.
- Limit editing keeps apps and daily allowance up front, with collapsed
  weekday, split-budget and extra-time settings. Schedules has one page with
  links to Sessions, Day & night and Calendar, not an inner tab selector.
  Sessions contains Now, Planned and Recurring. Free periods are a kind of
  immediate/planned/recurring session, not a separate menu. Existing recurring
  free periods remain visible in Recurring. Now & Next and
  New session remain available on the main Schedules page. The practice
  walkthrough keeps its direct highlighted Recurring and Calendar links.
- A split budget can divide the daily total into three time-of-day portions,
  with two whole-hour cutoffs and optional carryover. Existing two-portion
  limits remain readable and editable.
- Optional manual extra time adds actual app-usage minutes only after the
  whole-day budget is spent. Users configure an ordered sequence of up to
  five uses, each with its own minutes and wait. Previously saved uniform
  rules load as repeated steps. Requests and waits survive app restarts;
  unused requests reset at midnight. This is not an instant override of an
  early split portion or a wake-up gate. Individual steps can now require a
  named password, phrase, or trusted-contact approval. A contact request
  remembers the exact limit, day, and use; a background CloudKit approval can
  grant that usage even when Demora's window is closed. Email contacts still
  require entering their short code in Demora.
- Phrase overrides can be custom or use 50/100/200/500/1000 words drawn
  on-device from the bundled EFF long wordlist. They are typed word by word,
  with a configurable mistake allowance. Challenges and one-use proofs stay
  in memory, and phrase permissions are delay-gated. See
  `Latch/WORDLIST_ATTRIBUTION.md` before distributing the asset.
- Each contact has delay-gated approval scopes, including an opt-in extra-time
  scope. Existing contacts retain their old pending-change permissions but
  do not automatically acquire permission to grant extra time.
- Recurring daily schedules: block everything except an allowlist, or block only selected apps. Windows can cross midnight.
- Existing recurring blocking schedules have an Edit apps action from the
  recurring list, Now & Next, and calendar details. Every selection change
  follows the less-strict delay, just like a limit-group membership edit.
  The schedule keeps its identity, mode, recurrence, and times; its current
  apps remain effective until the queued edit applies. Editing and removal
  share a conflict key. Empty selections are valid only for block-all-except.
- Free periods: limits don't block during the window and usage inside it doesn't count toward them. Usage is tracked with silent checkpoint events (~5-minute granularity), since DeviceActivity doesn't report used minutes directly.
- One-off sessions: block or unblock selected apps, or make a free period, for
  a fixed duration. Delay-gated like everything else; the duration starts
  once the delay elapses.
- App-deletion lock (`denyAppRemoval`) so blocks can't be bypassed by uninstalling.
- Five-minute limit warnings from DeviceActivity's threshold warning callback (not an
  estimated usage counter); suppressed for limits of 5 minutes or less and while
  a free period is active. Optional five-minute free-period boundary reminders.
- Read-only Now & Next and Pending Change home-screen widgets. They consume a
  small App Group projection, never FamilyControls tokens or raw usage.

## Targets

| Target | Purpose |
|---|---|
| `Latch` | SwiftUI app |
| `LatchMonitor` | `DeviceActivityMonitor` extension: thresholds, daily reset, applying changes in the background |
| `LatchShieldUI` | `ShieldConfiguration` extension: custom block screen |
| `LatchWidgets` | WidgetKit extension: Now & Next, Pending Change |
| `Shared/` | Models, persistence, change engine (compiled into app and Screen Time extensions); the widget compiles only its read-only snapshot model |

## Setup

Debug builds include **Settings → Setup demos (debug)**. New-user setup uses
the real onboarding screens with simulated Allow/Don't Allow responses and a
sample group, without requesting permissions or saving rules. Migration creates
random pre-2.0 settings in a separate temporary UserDefaults suite, runs the
production migration, verifies preservation, and previews the existing-user
welcome. Neither demo replaces live state, resets usage, reconfigures monitors,
sends contact requests, or marks the real welcome as seen. The yellow demo
notice stays visible on each page; closing or retrying is safe. These are UI
and local migration previews, not real-token or Screen Time enforcement tests.

1. Requires Xcode 26+ and a physical device. FamilyControls does not work in the simulator.
2. Set the signing team on all targets. Extension bundle IDs must keep the app's bundle ID as their prefix.
3. The production App Group (`group.com.may.screentimedelay`) must match across the app, Screen Time, report, and widget entitlements and `LatchConstants.appGroupID` in `Shared/SharedModels.swift`. Debug uses the `.dev` group and bundle-ID family.
4. Family Controls: the development entitlement works as-is; TestFlight/App Store distribution requires the distribution entitlement (https://developer.apple.com/contact/request/family-controls-distribution) and enabling the capability on each App ID.

## Known constraints

- Apple limits DeviceActivity to [20 registered activities per app and its
  extensions](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/excessiveactivities),
  including future one-shot activities. This is not a limit of 20 apps or
  app groups: daily limits share one activity. Ordinary weekly schedules and
  free periods use one daily registration (two for overnight windows), with
  selected weekdays checked against the real rule. Very late overnight weekly
  starts retain their original weekday-spanning registrations to preserve the
  evening callback and Apple's minimum interval.
- `MonitoringBudget` reserves current, pending and latent enforcement needs
  before setup or a new change is saved. It includes shared split buckets,
  free-period tracking, wake/extra-time releases and session cleanup. Pending
  removals cannot promise room because approvals may arrive out of order;
  stale mandatory OS registrations still count. This is deliberately
  conservative, not a claim that every projected activity is running now.
  Over-capacity changes show an explanation without saving the draft. Existing
  state and deadlines are retained, and explicit reductions remain queueable
  under the existing delay policy even on an over-budget installation.
- All registration uses `MonitorRegistration`. Optional midnight echoes use
  spare capacity; an essential registration that receives Apple's capacity
  error may release only known echoes and retry once. It never evicts usage or
  enforcement activities. Other errors do not remove echoes. Admission cannot
  guarantee callback delivery or eliminate cross-process registration races;
  failed essential registrations still report degraded enforcement, and
  foreground maintenance remains a fallback.
- Free-period usage tracking is checkpoint-based, so accounting is accurate to within one checkpoint (in the user's favor).
- Editing a limit's selection discards that limit's previously banked
  free-period credit for the day: the old credit belongs to a different token
  set and cannot safely be carried over. During an active free period, Demora
  re-arms checkpoint tracking for the edited selection.
- Split budgets use repeating activities for their phases; extra time uses
  daily tier events and a one-shot release wake per request. iOS limits
  concurrent activities; registration failures set the degraded-enforcement
  banner, and split rules fail closed until their monitors can be
  established. Inspect
  that banner and test combinations with many schedules on a real device.
- When a free period crosses a split cutoff, Screen Time's checkpoint events
  cannot attribute exact usage to each side. Demora credits each side by the
  smaller of total recorded usage and elapsed free-window time on that side.
  This avoids a false block but can give a little extra allowance. As with
  other Screen Time boundaries, callback delivery is best-effort, so a missed
  callback may be repaired only when another wake or app foreground occurs.
- A "minutes used so far" display is provided by the `LatchReport`
  `DeviceActivityReport` extension (shown on the Limits tab). The in-app
  checkpoint counter was unreliable cross-process; the report reads real usage.
- Free-period reminders use repeating calendar notifications for daily/weekly
  rules. Monthly and one-off reminders are queued in a bounded rolling window
  (refreshed whenever Demora opens or its rules change) to stay under iOS's
  pending-notification cap. Screen Time's five-minute threshold callback is
  best-effort and can arrive late or not at all on some iOS versions.

## Advanced-limit device checks before release

- Wake gate: tap once, force-quit and reopen during the wait, then cross
  midnight. The wait must not shorten and the next day must require a new tap.
- Weekday budgets: set different Friday/Saturday caps, spend Friday's cap,
  leave Demora closed overnight, and verify Saturday's cap on a real device.
- Split budget: test both carryover modes, zero-minute first/middle/final
  portions, free periods crossing both cutoffs, and an existing saved
  two-portion limit. Confirm a spent whole-day limit stays blocked.
- Extra time: spend the daily total, request usage, leave Demora closed until
  the wait ends, consume exactly one additional tier, and repeat until the
  daily request count is exhausted. Test alongside split budgets, wake-up,
  overlapping rules, free periods, a midnight reset, and a failed monitor.
