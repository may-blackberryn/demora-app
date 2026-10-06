# iOS redesign status (2026-09-28)

This file records the requested product behavior and prevents a UI-only card from
being mistaken for a working enforcement feature. `demora-app` is the only iOS
repository; preserve its existing user data and pending changes.

## Implemented in the working tree

- Schedules links to Sessions, Day & night, and Calendar on one page;
  Now & Next and New session remain. Planned/recurring destinations
  are under Sessions. Limits uses collapsed advanced editors and no longer
  hosts wake/sleep controls. Existing group wake policies move unchanged to
  Schedules → Day & night → legacy Wake up, with per-group duration controls.
  One shared tap includes eligible legacy gates and the new named groups.
  Focused wake edits do not reset usage/extra/split state or current waits;
  healthy daily fingerprints are rebased without restarting monitors.
- Enabled legacy math users may install one batch of scoped replacement
  phrases without a delay during the update welcome. This excludes extra-time
  scopes and cannot be reused after completion/installation. The debug
  migration preview exercises the offer only in its isolated suite. Monotonic
  guards reject stale pre-replacement saves; widget/notification publication
  runs after state coordination releases. General state mutations are not
  claimed to be transactional.

- Debug-only Settings → Setup demos previews fresh onboarding and migration
  of randomized legacy settings. Onboarding simulates permissions and sample
  apps; migration exercises the actual method in an isolated defaults suite.
  The live configuration, usage, enforcement, contacts, and welcome flags are
  not replaced. `python3 Tests/DeveloperDemosHarness.py` passed 200 randomized
  migration/regeneration/isolation cases plus structural UI safety checks;
  `RedesignMigrationHarness.py` still passed 37 scenarios. Device interaction
  and layout checks remain required.

- Delay policy supports separate waits, a shared wait, and immediate tightening
  with a less-strict-only wait. Effective waits are enforced in previews and
  queueing, not merely hidden in the UI. Reducing either wait is less strict,
  all delay edits conflict, and old queued deadlines remain unchanged.
- First-run setup now uses seven short real-configuration pages, with an optional
  first limit, day/night rules and scoped contacts/phrases/passwords, plus a
  skippable permission request. The demo remains in Help.
  Existing users have a separate four-page 2.0 introduction (read-only except
  the explicit legacy-math replacement and initial day/night offers), marked
  seen only after completion, without a second legacy-language launch promotion.
- Migration defaults missing delay mode to separate and keeps identifiers,
  budgets, contact scopes, and deadlines. The raw settings backup precedes
  re-encoding but follows verified Keychain migration of any legacy Screen Time
  passcode; the backup never deliberately duplicates that secret. A failed
  decode or unverified migration shows recovery UI instead of resetting setup.

- Home shows a localized date, the actual Screen Time usage report, today's
  one-off/active sessions, and pending changes. Delays and override summaries
  no longer occupy Home.
- Limits & Blocks lists configured limits, keeps safe manual recheck, and shows
  app deletion, adult-site filtering, and custom website blocking directly.
- Global wake-up and sleep rules have queued, delay-gated editors. They can be
  limited to weekdays and selected apps, all except selected apps, or existing
  limit groups, with group exclusions. Wake-up starts at 00:00/03:00/06:00/09:00;
  sleep ends at that boundary. The Home tap starts a persisted TimeGuard wait.
  DeviceActivity activities wake the extension at boundaries/release, subject
  to iOS scheduling limits. Group exclusions never clear spent daily limits.
- Schedules previews the coming week, offers See all, a recurring-session list,
  and Now/Planned/Recurring creation.
- Settings release UI has Appearance, Notifications, Help, and Fine-tune
  overrides. Help omits Beta testers. Appearance can switch between muted
  blue and brick red. Fine-tune links to contacts, passwords, and phrases.
- Delays & Overrides has an Extra overrides destination with password and
  phrase policies.
- The 2.0 visual direction now uses an open daily journal: warm paper,
  blue/brick ink, fine rules, a clock-position day line, session and pending
  change threads, and large typographic waits. Repeated rounded card shells,
  dashboard navigation grids, and the dark floating tab-bar pill are removed
  from the active redesign paths. Usage is on Home; Limits & Blocks holds
  editable rules. Contact identities and menu destinations use open rows.
  Circular check controls replace stock switches. Schedule lists, details, and all four new-session
  editors use app-owned open scroll layouts instead of stock Forms/Lists.
  Notification preferences, the delay editor, contact code, add-contact and
  approval-request flows, contact profiles/history, and the onboarding
  contact sheet and stored-passcode entry use the same surfaces. The iOS-owned
  Screen Time permission prompt and FamilyActivity picker remain native.
- Manual extra time now accepts an ordered sequence of up to five uses with
  independent usage-minute amounts and waits. Legacy uniform rules decode to
  repeated steps. The registered Screen Time thresholds are cumulative across
  the new steps, and each request uses that step's persisted wait.
- Multiple named passwords can be added, edited, or removed through queued
  changes, each with its own permitted change categories and optional
  extra-time permission. Knowing the current password can change just its
  secret immediately. A pending-change password approval re-reads the policy
  and scope on the serialized application queue. An extra-time use can require
  its selected password instead of a wait; a missing policy fails closed.
- Multiple named custom or 50/100/200/500/1000-word random phrase policies
  have independent scopes and 0/1/5/10/unlimited mistake allowances. A phrase
  gate checks each word in order; reset redraws random words. The one-use proof
  is bound to the exact pending changes or limit/day/extra-time step and is
  consumed only after the current policy is rechecked. Missing/changed policies
  fail closed. The bundled EFF wordlist stays on-device. A normal paste menu
  and text drops are disabled, but iOS cannot prove physical keystrokes.
- Each trusted contact now has delay-gated pending-change permissions. Old
  contacts retain their former pending-change scope on decode. An in-app
  approval is matched to the exact requested contact code; email requests
  require every recipient of the shared code to remain permitted. Both paths
  recheck scopes on the serialized apply queue before skipping a delay.
- Contact permissions are directly reachable from the two-contact preview in
  Delays, the main contact settings, the contact list, both email/in-app
  profiles, and Fine-tune overrides. Each shows current scope and opt-in
  extra time; queued edits show current versus future permissions and retain
  the former scope until the deadline. All five scoped authorization paths
  reconcile due policy edits before validating an approval or extra-time grant.
  They fail closed if another policy becomes due during slow cleanup, and
  revalidate the exact policy/source before committing. Extra-time validation
  also runs after monitor lookup and inside runtime-file coordination, checking
  the current day, limit, step, and source. These fences do not make the existing
  cross-process settings store transactional.
- Recurring blocking schedules have selection-only edits from their list,
  Now & Next, and calendar details. All app/category/website selection edits
  use the less-strict delay, share removal's conflict key, and preserve the
  schedule ID, mode, name, recurrence, and times. The old selection remains
  active until apply; a stale edit never recreates a deleted schedule.
- Ordered extra-time steps can require a trusted contact. The request is
  persisted with its exact limit, day, step index, and step snapshot. The
  existing CloudKit background approval consumer can grant it with the UI
  closed; email contacts still require code entry. A stale day, changed step,
  missing contact permission, spent request, or absent daily monitor fails
  closed. Older saved steps decode `contactRequired` as false.

## Required before the redesign can be considered complete

1. Password, phrase, and contact-scope methods still need physical-device
   testing and an explicit rate-limit/security review.
2. Test contact-gated extra time on two signed devices (both in-app and email
   approval) while the requester app is open, backgrounded, and terminated.
   Test cancellation, expired requests, duplicate approvals, midnight, and a
   permission edit arriving while approval is in flight. No device result is
   available yet, so do not treat this as release-ready.
3. Verify the EFF wordlist's attribution/license terms before public release
   and test the 500/1000-word paged challenge with VoiceOver and on-device
   keyboard input. Blocking the standard paste menu does not prove manual
   typing; preserve accessible alternatives where possible.
4. Review the whole navigation path on iPhone and iPad with light/dark,
   red/blue, Dynamic Type, VoiceOver, and all supported languages. Reachable
   app-owned screens no longer use stock Forms/Lists; only unreachable legacy
   math/password editors and the retired beta-credits screen still contain
   them. The September 30 visual pass compiled in
   Debug and Release for iOS Simulator with signing disabled. The October 1
   journal redesign compiled in Debug for iOS with signing disabled. This Mac has
   no installed simulator runtime; there is no running-app screenshot or
   signed-device result yet.
   System-owned Screen Time pickers/prompts stay native.
5. Day/night now supports distinct timing per named group, plus one fallback.
   Weekdays still select on/off days, not a different duration for each weekday.
   Check overlapping groups, linked-limit edits/removals, fallback exclusions,
   and existing legacy gates on a device before describing this as release-ready.
6. Test wake/sleep and extra-time on a signed physical device with the app
   closed: midnight, 03:00/06:00/09:00 starts, sleep start/end, skipped
   weekdays, 23:30 sleep start, clock/time-zone change, missed callback,
   overlapping schedules/free periods, and the 20 activity cap. Simulator
   compilation is not proof of background enforcement.

## Password/extra-time checks before release

- Create two passwords with disjoint permissions. Confirm each can apply only
  its own pending-change categories; mixed bulk changes require one password
  that permits every change.
- Change a password secret with the current value; confirm permission edits
  still wait. Remove the policy while a gate is open; the stale gate must fail.
- Spend a limit, use a password-only step, and confirm exactly its usage-minute
  threshold unblocks. Wrong password, missing policy, repeated taps, absent
  daily monitor, and already-used step must not grant time.
- Test a saved pre-redesign uniform extra-time rule and an in-flight wait on
  upgrade. Confirm no decoding wipe, midnight reset, or accidental extra grant.

Do not advertise the unfinished methods or per-step grants as available in
App Store copy until those paths are enforced and tested.

## Verification of phrase work (2026-09-28)

- `swiftc -frontend -parse` succeeded for all Swift sources.
- `Tests/PhraseWordsHarness.swift` compiled and passed on macOS: word order,
  zero-error reset, one-use proof, and rejection after a policy edit.
- The bundled list has 7,776 unique words.
- A full iOS build and signed-device test were unavailable: this Mac currently
  has only Command Line Tools, not Xcode. Resource copying, UI behavior,
  background enforcement, and App Store readiness remain unverified.
- Contact-scope authorization was traced through both relay and email-code
  approval paths and Swift syntax parsed, but it still needs a full iOS build
  and two-device test, especially approval racing a queued permission edit.
- Earlier phrase-policy keys still need a localization completeness review.
  The October 1 contact permission and schedule-selection additions are
  translated in all seven non-English languages.

## Visual-pass build check (2026-09-30)

- Full `Latch` Debug and Release iOS Simulator builds succeeded with code
  signing disabled after replacing an unsupported `UIDropInteraction.isEnabled`
  call with `removeInteraction` in the phrase field.
- The current environment has Xcode 27 but no available simulator runtime,
  so the redesigned screens still need visual QA on an iPhone and iPad.

## Journal redesign and selection checks (2026-10-01)

- Full `Latch` Debug iOS device compilation succeeded with signing disabled,
  including the report, monitor, shield and widget extensions. The initial
  simulator compile exhausted disk space; only that attempt's temporary
  derived build directory was removed, then the existing device cache was used.
  No app was installed or launched by this work.
- `Tests/ScheduleSelectionHarness.py` passed 44 queued selection combinations,
  60 authorization cases around due policy edits, and 168 grant-latency/source
  cases, plus validation, conflict, persistence, deleted-schedule, and zero-delay
  checks. It extracts the actual relevant Swift logic, including due-change
  dispatch; platform monitoring and storage are substituted. Latency checks
  advance clocks during cleanup, monitor lookup, and file coordination, and
  check source identity, mixed batches, changed policies/steps, and midnight.
- A separate read-only review found no actionable bypass, deadlock, or regression
  in these patched authorization paths. This is not a replacement for signed,
  two-device or cross-process runtime testing.
- Contact permission presentation passed nine assertions. Localization
  additions passed duplicate-key, format-placeholder, and syntax checks.
- No working iOS simulator runtime is installed. Appearance, language wrapping,
  VoiceOver, large text, real Screen Time, and two-device approvals still need
  runtime testing. Compilation and these isolated tests do not prove them.

## Appearance and contact navigation follow-up (2026-10-02)

- The selected accent is propagated from the root through a SwiftUI environment
  value and the `AppAccent` dynamic property. Dependent controls redraw on a color
  change without changing view identity or resetting navigation/edit state.
  Schedule colors are no longer cached in static constants. The report extension
  observes the shared color preference too; iOS still owns report-process timing.
- Delays no longer duplicates My code or the approvers/blocked hub. Contact
  settings has direct links to My code, People you approve for, and Blocked users.
  Approval scopes, pending changes, and tutorial gates are unchanged.
- Full unsigned Debug iOS device build succeeded. Eleven source-level appearance
  and navigation assertions and whitespace checks passed. There is still no
  available simulator runtime, so tap-to-repaint latency and navigation continuity
  need an on-device check; no app was installed or launched.

## Delay policy, onboarding, and migration checks (2026-10-02)

- `ScheduleSelectionHarness.py`: 390 scenarios passed, including 118 delay-policy
  cases and the prior 272 selection/authorization checks. Tests cover every mode,
  switching modes behind the original wait, unchanged existing deadlines, legacy
  queued edits, conflict prevention, normalized persistence, and invalid durations.
- `RedesignMigrationHarness.py`: 37 scenarios passed with real models and extracted
  migration/setup/replay methods. Tests exercise exact backups, repeat/interrupted
  migration, usage side-store preservation, existing scopes/IDs/budgets/deadlines,
  corrupt state, rejected writes, verified Keychain redaction, failed replay restore,
  and the restriction that initial setup cannot overwrite an existing installation.
  Storage, Keychain, tokens, and platform effects are isolated or substituted; these
  are not cross-process durability or physical-device upgrade results.
- 123 in-scope strings are covered in all seven non-English dictionaries; new copy
  passed duplicate-key and format-placeholder checks. Approved permission wording
  is unchanged. Onboarding flow inspection passed ten source-level checks.
- Debug and Release unsigned iOS device builds succeeded. No app was installed or
  launched. Still test fresh setup, denied access, force-quit/relaunch during the
  welcome, a signed upgrade with real selections, and switching modes while a
  pending change is running. Check language wrapping, large text, and VoiceOver.
- Design inputs: [one sec's intention-centered approach](https://one-sec.app/) and
  [Opal's rule-creation/onboarding notes](https://apps.apple.com/us/app/opal-screen-time-control/id1497465230).
  Demora uses its own five-step flow and journal visual language, with no account,
  paywall, analytics, or invented usage/savings statistics.

## Schedule organization and math replacement checks (2026-10-02)

- `ScheduleSelectionHarness.py`: prior 390 cases plus 29 focused wake cases
  passed. Coverage includes nil/zero/bounded waits, strictness, conflicts,
  delayed application, persisted actions, unchanged budgets/splits/extra-time
  policies, and fingerprint rebasing without blessing stale fingerprints.
- `RedesignMigrationHarness.py`: 47 scenarios passed, including actual async
  phrase installation with a failed redundant marker, rejected stale writer
  snapshots, excluded new permissions, recovery fences, and deferred service
  publication outside state coordination.
- `DeveloperDemosHarness.py`: 200 randomized migration/regeneration/isolation
  cases passed, including one-shot phrase replacements and denied extra-time
  scopes. Live-store canaries remain unchanged.
- `WakeRuntimeHarness.py`: real temporary-file coordination and readback checks
  passed. Enabling clears only the old tap; corrupt runtime remains untouched,
  and failure stays closed. Zero/10/120/1440-minute waits, repeat taps and release
  deadlines passed. These tests substitute monitor effects and opaque tokens;
  they do not establish iOS protected-storage or cross-process durability.
- All new copy is translated in the seven non-English dictionaries, with
  placeholder, duplicate-key and syntax checks. Still test device navigation,
  large-text wrapping, migration interruption, overlapping general/group wake
  policies, and wake-only edits during active extra-time and split budgets.

## First-open animation (2026-10-03)

- Fresh setup and the existing-user welcome share a four-stage intro: original
  logo → expanding wordmark → 2.0 → localized “more powerful, more intuitive”.
  The completed-intro flag is independent of the completed-welcome flag. Root
  routing displays these directly, without briefly exposing Home underneath.
- The roughly four-second sequence is skippable with Continue. Backgrounding
  cancels its task without consuming the marker; returning resumes the current
  phase. Reduce Motion uses fixed-geometry crossfades. VoiceOver does not
  auto-advance past the final phrase. Both isolated debug previews replay it.
- `RedesignIntroHarness.py`: the actual gate passed all 16 Boolean combinations,
  plus phase-order/timing checks. Root routing, task cancellation guards,
  accessibility, demo isolation and seven translations passed structural checks.
  Existing developer-demo tests passed 200 randomized cases; migration tests
  passed 47 scenarios. These are not visual or physical-device lifecycle tests.
- Final unsigned Debug and Release device builds succeeded. No app was
  installed or launched; this Mac has no installed simulator runtime.
- Check the wordmark alignment, animation pacing, landscape/large text,
  VoiceOver and interrupted first-run flow on a device before release.

## Compact intro and single-page Schedules correction (2026-10-03)

- Intro branding is capped at 52 points instead of 90, with a smaller initial
  logo, a 34-point-at-most version label and a subheadline slogan. The version
  appears on the same baseline as the logo/wordmark; timing and once-only
  completion are unchanged. Reduce Motion still uses fixed-geometry crossfades.
- Schedules now presents Sessions, Day & night and Calendar as navigation rows
  on one page, without inner tabs. Sessions contains Now, Planned, Recurring
  and Free periods; Day & night contains Wake up and Sleep. Now & Next and the
  New session menu remain on the root. The practice walkthrough retains its
  old direct, highlighted Recurring/Calendar actions.
- Intro gate/timing and compact inline-version checks passed; single-page hub,
  nested lists, quick actions and tutorial routing passed source-level checks.
  Unsigned Debug and Release device builds succeeded. Device visual/navigation
  testing is still required; no app was installed or launched.

## Named day/night groups and setup (2026-10-05)

- Fresh onboarding has six pages; the migration welcome has four. Both offer
  day/night groups with a checklist of existing limits and extra apps. Up to
  five named groups have independent waits, wake-day starts, sleep starts and
  weekdays. One optional all-other-apps fallback has its own timing and explicit
  exclusions, automatically exempting selected groups for the matching boundary.
- One Home/Day & night Wake up action starts all eligible new and legacy gates.
  Repeat taps, renamed groups and wait/start-hour edits retain today's deadline;
  re-enabling wake uses a new epoch. Legacy gates and general rules remain intact.
  Initial migration setup is immediate, additive and one-shot; verified state
  consumes the allowance and stale snapshots cannot reopen it. Recovery or
  unverified migration disables the offer. Lost eligibility has an explicit
  draft-discard path rather than trapping Continue/Done.
- Two additional named ManagedSettings stores compose boundaries restrictively
  with spent daily limits. Explicit free/unblock actions affect the new stores
  too. Fallback/category exceptions are rejected, including referenced-limit
  selection changes at queue/apply time. Daily usage monitors are not restarted
  just for a day/night edit or wake tap.
- Boundary activities are deduplicated by minute; one release activity advances
  through the earliest outstanding wait. Cached wall-clock/calendar/time-zone
  projections repair material shifts without restarting healthy monitors.
  Early callbacks consume/rearm the one-shot without granting early access.
  Corrupt runtime and monitor failures set the enforcement-degraded warning.
  Overnight weekday anchoring uses calendar-day arithmetic across DST.
- `DayNightHarness.py`: 30 scenarios / 212 assertions passed, using actual models,
  policy/runtime and migration helpers with opaque-token/monitor/coordination
  stubs. Includes overlaps, free/unblock, one-shot/failure cases, independent
  deadlines, clock projection repairs and DST recurrence.
  Developer demos passed 200 randomized isolated cases, now also checking
  initial day/night setup. The actual migration/persistence harness passed 50
  scenarios, including stale-save rejection, failed initial group writes and
  fresh setup with groups. Existing selection/delay/authorization/latency/group
  wake and runtime harnesses passed. Navigation and intro structural checks
  passed; all new strings have seven translations with placeholder checks.
- Final unsigned Debug and Release iOS device builds succeeded. `git diff
  --check` passed. There is no signed installation or running-app result.
- Still verify on a signed device: background release, sleep and wake boundaries,
  skipped weekdays, midnight, timezone/clock changes, free-period overlaps,
  legacy gates, named-store composition and monitoring-capacity degradation.
  Five groups do not guarantee enough DeviceActivity slots alongside many
  schedules, splits, pending changes and sessions. Stubbed tests do not prove
  cross-process durability or device callback delivery. No app was installed.

## Monitoring capacity admission and consolidation (2026-10-05)

- `MonitoringBudget` is a pure resource planner shared by expected window,
  split and day/night names. Ordinary daily/weekly windows share daily
  registrations, with two segments for overnight windows. Very-late weekly
  overnight starts keep the old weekday-spanning shape to preserve the evening
  wake and minimum interval. Monthly registrations remain unchanged. Skipped-day
  free-period callbacks reconcile the actual predicate before tracking usage.
- New queue admission runs under state coordination, with DeviceActivity and
  notification effects outside that coordination and only after verified save.
  Initial setup and the migration day/night batch use the same capacity policy.
  Reservations cover current and accumulated/individual pending projections,
  latent wake/extra/free tracking, shared split buckets and stale mandatory
  registrations. Pending removals do not promise future room. Explicit reducing
  edits remain queueable on old over-budget installs under their normal delays;
  previously admitted changes and saved state are never discarded for capacity.
- `MonitorRegistration` is the only actual registration entry point. Echoes
  yield reserved space. Essential registration first asks Apple; only a capacity
  error permits one bounded retry after releasing known optional echoes, never
  daily usage or enforcement monitors. Other errors do not evict echoes. Due
  apply one-shots are cleaned up after verified save and before replacement
  tracking starts. The rejection alert has a capacity-specific localized title
  and explanation in all seven non-English languages.
- `MonitoringBudgetHarness.py`: 34 scenarios / 171 assertions passed with actual
  production planner, models and registration bodies. Tests use opaque tokens,
  disposable defaults and fault-injected XPC adapters; they cover 20/21 slots,
  shared names, skipped/overnight/DST recurrence, late-weekly fallback, pending
  conjunctions/reordered approvals, stale duplicate releases, latent reservations,
  explicit repairs, replacement events and bounded echo-only retry.
- `ScheduleSelectionHarness.py` passed its prior selection (44 combinations),
  delay (118), authorization (60), latency/source (168) and focused-wake (29)
  cases, plus seven real queue capacity/write-failure/repair cases. Day/night
  passed 30 scenarios / 212 assertions; migration passed 50 scenarios; developer
  demos passed 200 randomized isolated cases. Wake runtime, navigation and the
  16 intro-gate combinations passed. New localization keys have seven entries
  each; both unsigned Debug and Release arm64 iOS builds succeeded, with no
  compiler warnings in these build logs. `git diff --check` passed.
- Real-device OS registration, old-weekday upgrade, background delivery near the
  cap and cross-process races remain unverified. A pre-existing separate risk
  remains: `applyDueChanges` reads its snapshot outside state coordination, so
  a later save can overwrite a concurrently queued change. These single-process
  harnesses do not establish transactional safety for that path. The capacity
  patch does not change those existing semantics or claim to fix all persistence
  races. No app was installed/launched; nothing was committed, pushed or deployed.

## Per-day wake timing, intro reveal and session navigation (2026-10-05)

- Named day/night groups and limit/group wake gates now have minute-granular
  default starts, default waits, selected weekdays and optional per-day start/wait
  overrides. The shared editor also appears in both setup paths for named groups.
  Wake starts are bounded to 00:00–23:30 so their boundary sentinels can meet
  DeviceActivity's minimum interval. Missing fields retain old group hours and
  midnight/every-day limit defaults, not newly chosen defaults. Sleep ends at
  the following wake start using that morning's custom time, with the sleep
  evening's weekday and calendar arithmetic retaining overnight/DST anchoring.
- Day & night exposes the limit/group wake editor whenever limits exist, not
  only for installations that already had legacy wake gates. Preserved general
  wake/sleep rules retain separate editors. Existing scopes and delays still
  apply. `setGroupWakeSchedule` shares limit conflicts and limit-change approval
  permissions, validates queue/application and performs a focused mutation.
  Reductions in active days/waits or moving a wake start later are less strict;
  sleep-end tradeoffs are conservatively less strict. A same-day persisted wait
  takes precedence over edited eligibility and is never recalculated by a tap.
- Distinct per-day starts participate in the shared monitor budget; identical
  starts across groups/limits deduplicate. A positive weekday wait reserves its
  release slot even when the default wait is zero. Wait-only focused edits do
  not restart healthy daily/window monitoring; changed boundary names do. A
  batch removing the final shared contributors also removes their sentinel.
- The intro uses a small intrinsic-size SwiftUI Layout for its reveal instead
  of a guessed text width. At 52pt the measured trailing glyph ink extends to
  143.2pt, beyond the old 135.2pt clip. The compact logo/name/2.0 row and existing
  intro gates, Reduce Motion and demo isolation remain unchanged.
- Sessions now has Now, Planned and Recurring only. The redundant Free periods
  destination and recurring-kind submenu were removed; the unified recurring
  editor has Block/Free period types. Immediate/planned free sessions and stored
  recurring exemptions remain available and visible. No rules were removed.
- Tests: day/night passed 34 scenarios / 245 assertions, including old-key
  decode, custom-minute boundaries, per-day waits, countdown edits, next-morning
  sleep and DST. Monitoring budget passed 35 scenarios / 178 assertions, including
  positive weekday waits and boundary dedup/reservations. Selection/delay/scope/
  latency tests passed their prior cases plus 20 scheduled-wake cases alongside
  29 original focused-wake cases. Real runtime-file checks passed weekday waits,
  skipped/pre-start days, existing-deadline preservation and rollover. Migration
  passed 50 scenarios; developer demos passed 200 randomized cases. Intro gates
  passed all 16 combinations plus 25 font sizes × 7 reveal fractions, glyph bounds
  and seven compact widths. Editor/localization checks passed seven keys in all
  seven languages with matching placeholders; session navigation checks passed.
  These are production-body tests with stated platform adapters and source/layout
  checks, not interactive signed-iOS verification.
- Final unsigned arm64 Debug and Release device builds both succeeded, with no
  compiler warnings in the final logs. `git diff --check` passed. Nothing was
  installed, committed, pushed or deployed. On a signed device, still verify
  per-day background starts and releases, overnight sleep across differently
  timed mornings, skipped weekdays, midnight/time-zone changes, capacity
  pressure, existing spent limits, and the intro's final glyph at small and
  large text sizes. Mac/website/backend repositories were not changed.

## Optional initial overrides and paired delays (2026-10-06)

- Fresh setup now includes an optional seventh-page flow: contacts, named
  phrases and named passwords are drafted before confirmation. Each has
  selectable permissions, including opt-in extra time. Contact drafts can be
  removed or have scopes edited; phrase/password drafts can be edited or
  removed without queueing real changes. The existing-user welcome and its
  narrower math-replacement allowance are unchanged.
- `OnboardingOverridesDraftView` reuses staged policy editors and the contact
  entry form. Passwords stage only hashes. `completeInitialSetup` validates
  scopes/policies, duplicate IDs/destinations and unconfirmed contact invitations
  before the verified one-time save. Invitations follow the existing AppModel
  consent flow after setup; normal later edits still use their delays.
- The developer onboarding preview now includes these drafts in its final
  summary. Contact entry skips quota/code-service calls and own-code storage in
  demo mode. No preview invitation, policy save or delayed edit is issued.
- `DelayPolicyNavigationRows` presents More strict and Less strict in one
  equal-width row; shared mode still has one summary, and immediate-tightening
  mode retains its Immediately label. Existing navigation and delay semantics
  are unchanged. New onboarding copy is present in all seven translated tables.
- Verification: `RedesignMigrationHarness.py` passed 67 scenarios (including
  actual fresh-setup acceptance, invalid override rejection, unconfirmed consent,
  no pending edits and repeated-setup rejection). `DeveloperDemosHarness.py`
  passed 200 randomized cases. `OnboardingOverridesHarness.py` passed source
  checks for staging, secret handling, demo/service guards, migration isolation,
  localization and paired navigation layout. These are not signed device UI or
  contact-delivery tests.
- Final unsigned arm64 Debug and Release builds succeeded without compiler
  warnings; `git diff --check` passed. An initial overlapping Debug invocation
  hit Xcode's build-database lock; rerunning sequentially passed. No installation,
  commit, push or deployment was performed. Still check compact/large-text
  layout and real email/in-app invitation confirmation on a signed device.

## Release name and welcome-render hang patch (2026-10-06)

- Restored the Release display name to `demora`; Debug remains `dev demora`.
  All five targets retain their separate debug/production bundle IDs,
  entitlement files and App Groups. The user's existing build-number change
  to 67 is preserved. Built Info.plists confirm `may.latch.dev` / `dev demora`
  for Debug and `may.latch` / `demora` for Release, both version 2.0.0 build 67.
- Two supplied production build-1 reports show watchdog termination on exit
  after an unresponsive UI. The matching archive dSYM places one main-thread
  stack in JSON decoding through `SharedStore.loadState` and welcome-screen
  eligibility/rendering; the other is in SwiftUI's render graph. The user also
  observed Continue not responding on the first launch, followed by crashes
  on reopen. These support a render-feedback-loop diagnosis, but do not prove
  that the new signed build resolves every launch issue.
- Welcome offer getters now use AppModel's published state, not full saved-blob
  decoding during rendering. Actual math replacement and day/night commits
  still revalidate persisted state. Healthy state reads no longer rewrite an
  already-false recovery flag; repeated corrupt reads preserve unchanged raw
  bytes without repeating preference writes. Recovery transitions, migration
  guards, saved rules, deadlines and one-shot allowances remain intact.
- `RedesignMigrationHarness.py` passed 71 scenarios, including repeated
  healthy/corrupt reads, one-time recovery transitions and read-only welcome
  eligibility. `DeveloperDemosHarness.py` passed 200 randomized cases.
  `ReleaseIsolationHarness.py` passed name/ID/group/entitlement, archive-config
  and snapshot-only welcome source checks. `git diff --check` passed.
- Sequential unsigned arm64 Debug and Release builds succeeded. Debug emitted
  only an App Intents metadata-extraction-skipped tool warning; Release had no
  warnings. No signed installation, commit, push or deployment was performed.
  A new TestFlight archive must still be tested over the affected installation,
  without deleting its data, through Continue, welcome completion and relaunch.
