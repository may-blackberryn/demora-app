# Demora iOS — primary development handoff

Updated 2026-11-11 (wake-widget follow-up). This is the iPhone/iPad handoff, not
the Mac app (the Mac app has its own handoff in the workspace root `CLAUDE.md`).
Codex reads `AGENTS.md`, which points here. Keep durable decisions current here;
put build decisions in `docs/redesign-review.md` and older implementation
evidence in `IOS_REDESIGN_STATUS.md`. New user instructions take precedence over
historical plans. Verify current source and Git state rather than treating this
snapshot as proof of what is installed or released.

## Product and collaboration

Demora is a free, delay-based screen-time blocker. Its central idea is that a
deliberate past decision should outweigh an in-the-moment impulse. Rules can
always change, but loosening normally waits through the user's chosen delay.
Public App Store name: **Demora: Screen Time Delays**. Keep internal Xcode names
such as `Latch`; renaming them adds signing/container churn without user value.

- Speak to Matias/May in English. Translate artifacts when requested, not the
  surrounding explanation.
- Prefer concise, practical updates and clear verification caveats.
- Implement requested changes, but do not silently expand into other repos or
  release operations. A diagnosis-only request is not authorization to patch.
- The 2.0 goal is a distinctive, thoughtful app, not a default Settings list or
  generic dashboard. Reuse the established warm-paper, serif and blue/red-accent
  language while improving hierarchy, spacing, accessibility and usefulness.
- Demora is free: no subscriptions, paid overrides, ads, accounts or analytics.
  Do not resurrect the retired Pro limits or purchase paths.

## Orient before editing

Read these files before iOS implementation:

1. `README.md` — product behavior, targets and constraints. Some passages
   explicitly describe the last released app rather than the 2.0 working tree.
2. `background-unblocking.md` — best-effort background execution, retries and
   monitoring-capacity model. Reconcile older details against current code.
3. Relevant sections of `IOS_REDESIGN_STATUS.md` — dated evidence and gaps.
4. For redesign work: the plan, the relevant spec and `docs/redesign-review.md`
   (see "Current state" below). The workspace root `CLAUDE.md` covers repository
   boundaries and the Mac app; the old umbrella `AGENTS.md` is gone.

Run `git status --short` and inspect the relevant diff. All current tracked and
untracked work must be preserved unless the user explicitly says otherwise.
Do not use reset/checkout to clean the tree or discard unfamiliar files.

## Current state: full redesign in progress (2026-11-09)

All redesign work is on branch **`design/full-redesign`** (You build through
`7be509d`, handoff `5c5c502`, followed by the independent verification fixes).
At the owner's explicit request on 2026-11-10, **origin/main** was fast-forwarded
from `160d285` to the verified **`da9b6d3`** for their Xcode Cloud/TestFlight
workflow. Remote SHA was checked afterward. No claim was made that Cloud
processing completed. Local main may still point at `160d285`; the working
checkout remains the redesign branch. The unfinished wake-widget changes were
excluded from that push. This one-off authorization is not standing permission
to publish later changes. The earlier 2.0 report work is committed as `862cc9c`.

The owner asked for a full redesign that keeps the intention (calm, warm paper,
serif, blue or brick ink) and moves to four tabs: **Today · Rules · Insights ·
You**. Read before any redesign work:

1. `docs/redesign-ux-plan.md` — approved plan (jobs, structure, decisions D1–D10;
   D9 has a 2026-11-02 correction).
2. Approved specs: `docs/foundations-redesign.md`, `today-redesign.md`,
   `rules-redesign.md`, `insights-redesign.md`, `you-redesign.md`,
   `onboarding-shield-widgets-redesign.md`. Each ends with the owner's answers.
3. `docs/redesign-review.md` — decision log: "Start here", one table per build,
   review-fix tables, what to try on the phone.

| Piece | State |
| --- | --- |
| Plan + six specs | Approved by the owner, committed |
| Foundations (tokens `InkPalette`/`Ink`, `DemoraType`, `DemoraComponents.swift`, text-case default, tab bar restyle) | Built, reviewed, re-verified, on the owner's iPhone |
| Today (replaces Home; `TodayView`, `TodayPresentation`, `ChangesLedgerView`, `ChangeReceiptSheet`, `LatchReport/ReportTheme.swift`) | Built, reviewed, re-verified, on the iPhone; owner said it looks good |
| Rules (behind tab 1, still labelled "Limits") | Built, reviewed, re-verified, on the iPhone |
| Insights (opened from Today until the tab switch) | Built, reviewed, re-verified, on the iPhone |
| You (behind the Settings tab), commits `4492d82..7be509d` plus verification fixes | Independently reviewed and corrected; see `docs/redesign-review.md` → Independent You verification for evidence and remaining device checks |
| Onboarding, intro and migration welcome | Built, freshly reviewed and verified; now included in the installed combined dev build. Phone locked, so interactive setup checks remain; see the dated setup build in the review log |
| Generic shield | Built, independently reviewed, verified and installed in the combined dev build. Rule naming remains behind the device spike |
| Widgets | Display/navigation and approved read-only wake reminder built, independently reviewed and verified: 33 Python harnesses, existing Swift harnesses, both localization generators and unsigned Debug/Release/signed Debug. Reader/publisher fixtures pass 903/742 assertions per environment. Device timing remains unverified; see dated follow-up |
| Four-tab switch (drop Delays/Schedules tabs, move badges, retire the legacy tutorial and its dormant code, restyle Calendar) | Not built |
| Device test pass | Partial (owner tried Today) |

### Open items to do first

- **Completed independent You checkpoint (reported before new builds).**
  App Attest was a stale suspicion: its bytes and Git blob are identical before
  and after You; no revert was needed. Five new autofill hints were removed
  from add/change-password forms (the old skip-gate hint stays). Fixed six
  duplicate `Next` dictionary keys that could crash beta-language users, stale
  contact recipients, collapsed rows after list shrink, hidden sent history and
  an obsolete revealed passcode after replacement. Fresh review rechecked the
  corrections; all 29 Python harnesses, both Swift harnesses, generated
  localization and diff checks pass. Unsigned Debug/Release and signed Debug
  pass; installed as dev demora on the owner's iPhone, but launch was denied
  because it was locked. Interactive checks remain. Details live in the log.
- **Next: four-tab switch**, one
  approved step at a time. Shield phase 1 stays generic; phase 2 naming needs
  the signed-device token spike. Follow `docs/onboarding-shield-widgets-redesign.md`
  and the owner answers. Do not change engine/model/service behavior without
  first asking the owner. No new feature was started during the You checkpoint.
- **Wake widget reminder approved 2026-11-10:** the owner authorized the
  narrowly scoped read-only wake APIs and post-wake refresh hook. The follow-up
  is verified separately, not included in `da9b6d3`. Original enforcement
  bodies stay byte-for-byte unchanged except the one display refresh after the
  shared Wake up action. Readers never repair clock anchors, flags, usage,
  monitor readiness or rules. The publisher serializes its own display writes,
  re-reads saved state rather than trusting a cached UI model, and treats
  unreadable owning runtime as unknown. This remains a snapshot, not proof
  that enforcement is healthy or a guarantee of WidgetKit delivery.
- **Owner decision pending (don't implement without asking):** should adding,
  removing or pausing contacts stop being skippable via the "Trusted contacts"
  capability, and should new contacts stop getting it by default? Both are
  engine/model changes.
- The old "dotted separator in Delays & overrides" request is superseded: that
  screen is replaced by Rules → Your waits.

### How the work is run (owner's workflow, `~/Desktop/Claude Workflow/`)

Spec first → owner approves → build from the spec, one build at a time in this
checkout → after each step run verify, then commit only that step's files by
name (never `git add -A`), never push → log every judgement call in
`docs/redesign-review.md` (Decision · Why · Done?) → a fresh reviewer that
didn't write the code looks for real bugs, each fixed with a regression check →
the lead re-runs verify, installs on the iPhone and tells the owner what to try,
in order. Make reasonable decisions without stopping; give one recommendation,
not a survey; flag what's worth the owner's review. Commits on the redesign
branch per this workflow are authorized; pushing, merging, deploying and
submitting are not.

## Source map

| Area | Main locations |
| --- | --- |
| App lifecycle, navigation, permissions | `Latch/LatchApp.swift`, `AppModel.swift`, `AppDelegate.swift` |
| Persisted rules and coordination | `Shared/SharedModels.swift`, `SharedStore.swift` |
| Delayed mutations and enforcement reconciliation | `Shared/ChangeEngine.swift`, `ShieldController.swift`, `TimeGuard.swift` |
| Activity planning/registration | `Shared/MonitoringBudget.swift`, `MonitorRegistration.swift` |
| Background callbacks | `LatchMonitor/DeviceActivityMonitorExtension.swift` |
| Today (replaces Home), change receipt, Changes ledger | `Latch/TodayView.swift`, `TodayPresentation.swift` (pure), `ChangeReceiptSheet.swift`, `ChangesLedgerView.swift`; legacy tutorial Home in `HomeView.swift`; report host `LimitsUsageReportView.swift`, `HomeReportRefreshPolicy.swift` |
| Rules tab, rule summary, editors | `Latch/RulesView.swift`, `RulesPresentation.swift` (pure), `RuleSummarySheet.swift`, `RuleEditors.swift`; older editors still in `LimitsView.swift` |
| Sessions, schedules, conflicts | `Latch/SchedulesView.swift`, `ScheduleConflictsView.swift` |
| Day/night and wake runtime | `Shared/DayNightPolicy.swift`, `DayNightWake.swift`; `Latch/DayNightViews.swift`, `WakeScheduleView.swift`, `WakeTimingEditor.swift` |
| Redesign foundations | `Latch/Theme.swift` (`InkPalette`, `Ink`, `DemoraType`), `DemoraComponents.swift`; report copy in `LatchReport/ReportTheme.swift` |
| Delay policy | `Latch/DelayPolicyViews.swift` (shown as Rules → Your waits) |
| You tab, appearance, help | `Latch/YouView.swift`, `YouPages.swift`, `YouPresentation.swift` (pure), `HowDemoraWorksView.swift`; remaining `SettingsView.swift` |
| Onboarding/migration | `Latch/OnboardingView.swift`, `RedesignWelcomeView.swift`, `RedesignIntroView.swift`, `SetupPresentation.swift` (pure welcome page identities), `MathPhraseMigrationView.swift`, setup demo helpers |
| Trusted contacts and email security | `Latch/ContactsService.swift`, `AppAttest.swift`, `ContactsOverrideViews.swift` |
| Ways to skip a wait, password/phrase challenges | `Latch/SkipWaitSheet.swift` (replaces the deleted `OverrideGateView.swift`), `SkipWayViews.swift`, `SkipWayEditors.swift`, `PhraseOverrides.swift` |
| Private usage rendering | `LatchReport/` (self-contained; does not import all of `Shared`) |
| Usage report host vs extension | `Latch/UsageInsightsView.swift` vs `LatchReport/UsageInsightsView.swift` — different responsibilities |
| Widgets/notifications | `LatchWidgets/DemoraWidgets.swift`, `WidgetTheme.swift`, generated `Localizable.xcstrings`; `Shared/DemoraWidgetSnapshot.swift` (projection/pure decisions/navigation URLs), `DemoraNotifications.swift` |
| Translations | `Shared/Localization*.swift`, generated `LatchReport/UsageInsightsLocalization.swift` |

## Non-negotiable behavior and safety

### Delays, overrides and editing

- Support separate stricter/less-strict waits, one shared wait, and immediate
  tightening with a wait only for loosening. Legacy users retain their policy.
  Policy edits obey the currently enforced policy; pending deadlines never move.
- Persist and revalidate real mutations through the normal change engine.
  A convenient UI must not create an instant bypass.
- Limit group membership edits are always treated as less strict. Preserve the
  rule ID and spent allowance. Recurring schedule selection edits similarly
  preserve identity/mode/times and leave current selection effective until due.
- Current 2.0 adds multiple named hashed passwords, phrases and per-contact
  capabilities. Permission changes are delay-gated. Knowing a password permits
  immediate secret-only changes, not broader permissions.
- Phrases use custom text or 50/100/200/500/1000 bundled EFF words, typed word by
  word with configurable error allowance. Do not enable paste/copy shortcuts or
  persist challenge/proof material. Read `Latch/WORDLIST_ATTRIBUTION.md`.
- Three daily budget portions are supported, with legacy two-portion decoding.
  Manual extra time grants actual usage minutes in ordered steps, not wall-clock
  unblocking. Each step has minutes and a wait/contact/phrase/password gate.
  It cannot bypass an early split portion, wake gate, or unrelated block.
- Developer-only skips/demos must remain excluded from Release behavior.

### Clocks, monitoring, blocks and accounting

- Document the clock domain at each boundary. Wall-clock schedules, sessions and
  DeviceActivity callbacks must agree; tamper-aware elapsed waits use the existing
  TimeGuard machinery. Do not indiscriminately replace all Date or TimeGuard uses.
- Round minute-granular DeviceActivity boundaries safely (existing ceil helper),
  never down into an early callback or countdown that loops at 0:01.
- Housekeeping reconstructs current state idempotently. Warnings/echoes are retry
  opportunities, not permission to apply a future transition early.
- Do not restart a healthy daily monitor on every foreground or display refresh.
  Re-registration has caused spurious past-usage threshold callbacks/false blocks.
- False-block recheck must not clear legitimately spent limits or reset allowance.
  Free periods use checkpoint credit; preserve credits, split accounting and
  extra-time grants through edits and transitions. Do not trust report UI as
  enforcement truth; a missing report does not mean an app is unblocked.
- Monitoring capacity is shared across app/extensions (20 activities in the
  current design). All registrations go through `MonitorRegistration`; admission
  through `MonitoringBudget` reserves current/pending/latent/stale mandatory needs.
  Never borrow capacity from a pending removal or erase usage to free capacity.
  Only a real capacity error permits bounded eviction of optional midnight echoes.
- Wake/sleep groups preserve existing deadlines. One wake tap starts all eligible
  gates without resetting running waits. Optional per-day/group latest wake times
  end only wake blocking, never sleep or spent daily budgets.
- Default effect order: wake/sleep → recurring → planned → sessions. Promotions
  are less-strict delayed edits. Preserve scoped category exception cohorts and
  cross-process shield coordination; do not globally clear stores to resolve one
  rule. Category-wide fallback exceptions are not representable; reject unsafe
  combinations, including later referenced-limit membership edits.
- iOS background execution is best-effort. A host build or stub test cannot prove
  callback timing, midnight resets or signed-device capacity behavior.

### Privacy and usage reports

- Actual usage, app labels/tokens, chart selection and derived trends stay inside
  `DeviceActivityReport`. No raw usage export, measured persistence, analytics,
  network requests, or readiness/height handshake to the host.
- Missing is unknown, not zero. Incomplete periods cannot produce complete-week
  averages/trends. Today is separate. Deduplicate source/day snapshots and use
  winning revisions; never sum app/category totals to invent screen-on totals.
- Apple's labels and opaque token identity are private. Do not recover/export app
  names or bundle IDs. Identity resets belong on labels, not the whole report.
- Manual weekly starting estimates are local, optional, dated and self-reported;
  never present them as measured history or proof of savings caused by Demora.
- The live website discloses optional trusted-contact messages through CloudKit
  or Cloudflare/Resend. Resend receives readable email content/code; hashing and
  code expiry do not imply email deletion. App Attest and Apple time checks are
  additional network exceptions. Do not restore absolute “no data sharing” copy.
- Never log contact secrets, attestations, approval codes or private usage.

### Permissions, setup, migration and environment isolation

- Apple previously rejected redirecting to Settings after Screen Time denial
  (5.1.1(iv)). Preserve approved onboarding wording and **Continue**. Respect
  denial, permit setup completion, and do not auto-open Settings/re-prompt loops.
- Authorization status can be stale at launch; inspect existing verification
  rather than assuming the banner proves permission loss.
- First-run setup, intro marker and completed-user migration welcome are distinct.
  No repeated onboarding, lost rules or reset usage on upgrade. View getters must
  not decode/write saved state. Real commits revalidate coordinated persisted state.
- Unreadable state is a recovery case, not permission to create empty defaults.
  Migration moves legacy passcode to Keychain before backup. Preserve deadlines.
- One-shot migration waivers are narrow and monotonic: optional replacement of
  enabled legacy math with scoped phrases, and initial additive day/night setup.
  They do not authorize later free edits or new extra-time capabilities.
- Setup demos use isolated drafts/temp suites, never real state/contact services,
  permissions, monitors, usage, or real completion markers.
- Debug name **dev demora**, bundle **may.latch.dev**, App Group
  **group.com.may.screentimedelay.dev**. Release name **demora**, bundle
  **may.latch**, App Group **group.com.may.screentimedelay**. Keep all five targets,
  icons, entitlements and report/widget preference reads aligned. Never enable
  DEBUG compilation conditions in Release. Archive uses Release.
- CloudKit uses the configured container with development/production environments;
  both targets currently name `iCloud.may.latch`. Do not blindly invent a new
  container to isolate local report state. TestFlight/App Store use production;
  production fields/indexes must be deployed. Missing indexes have broken approvals.
- Email has failed only in production App Attest before. Diagnose the complete
  request path and real error, not “no connection” or `/challenge` success alone.
  Do not weaken attestation as a shortcut or expose credentials in logs/docs.
- Mac/iOS trusted-contact interoperability is NOT enabled: a coordinated protocol
  security upgrade binding displayed mutation context is still a gate. Do not
  extend the legacy request-ID/decision protocol casually; consult parent AGENTS.

## Verification workflow

Use stable Xcode for archive/signing conclusions. At handoff,
`/Applications/Xcode.app` reports Xcode 27.0 (27A266a). Check the active developer
directory first; do not install/switch tools or change signing without a reason.

Full verify (run before every commit; the redesign added more harnesses):

```sh
(
verify_failed=0
for f in Tests/*Harness.py; do
  python3 "$f" || { printf 'FAIL %s\n' "$f"; verify_failed=1; }
done
swiftc Shared/PhraseWords.swift Tests/PhraseWordsHarness.swift -o /tmp/phrase-test && /tmp/phrase-test || verify_failed=1
(sed -n '/^enum ContactPermissionPresentation {/,/^}/p' Latch/ContactPermissionsEditor.swift; \
  cat Tests/ContactPermissionsPresentationHarness.swift) | swift - || verify_failed=1
python3 Tests/GenerateUsageLocalization.py --check || verify_failed=1
python3 Tests/GenerateWidgetLocalization.py --check || verify_failed=1
git diff --check || verify_failed=1
exit "$verify_failed"
)
```

Other focused harnesses cover migration, intro, demos, onboarding overrides,
day/night, wake timing/runtime, monitoring budget, schedule selection/precedence
and shield stores. Read each harness header and dependencies before running.
Some compile production fragments with stubs or render macOS synthetic SwiftUI;
source guards and stubs are not full iOS integration tests. Do not claim otherwise.

Translations: English + Spanish, German, French, Portuguese, Polish, Turkish,
Hindi (not Urdu). Update all catalogs for visible copy. Report translations are
generated from these catalogs; use the generator's `--patch` output through a
patch tool rather than hand-diverging the generated snapshot.
Widget gallery metadata is generated by `Tests/GenerateWidgetLocalization.py`
from the same catalogs; use its `--patch`/`--check` workflow too. Gallery metadata
follows the system language, while published widget copy follows in-app language.
Widget taps only navigate through `demora-dev://today|changes` (Debug) or
`demora://today|changes` (Release). Their schemes must remain configuration-
specific in both the host Info.plist/build settings and pure destination type.

Unsigned device build example (run Debug then Release sequentially; substitute
the configuration, using a task-specific local DerivedData directory):

```sh
xcodebuild -project Latch.xcodeproj -scheme Latch \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/demora-claude-derived-data \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

An unsigned build does not validate distribution entitlements, profiles, App
Attest, CloudKit production, extension embedding or TestFlight startup. Archives
previously failed when the report ExtensionKit bundle was embedded incorrectly;
check its dedicated Extensions destination rather than moving all extensions
into PlugIns. Keep the shared Latch scheme tracked for Xcode Cloud. Do not add
machine-specific provisioning-profile paths. Never “fix” signing by merging
development and production IDs or removing required entitlements.

Installing on the owner's iPhone ("iphone de may", UDID
`00008140-00192C963ED0801C`): no iOS Simulator runtime is installed on this Mac.
Build signed Debug (automatic signing, team `U2WQ5695SA`) and install with
devicectl; it installs as **dev demora** (`may.latch.dev`), separate from the App
Store app. Launch fails with "Locked" if the phone is locked; the install still
succeeds.

```sh
xcodebuild -project Latch.xcodeproj -scheme Latch -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath <path outside repo> \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008140-00192C963ED0801C \
  <path>/Build/Products/Debug-iphoneos/Latch.app
xcrun devicectl device process launch --device 00008140-00192C963ED0801C may.latch.dev
```

Signed-device release checks still needed for changed paths:

- Cold startup, intro/Continue and migration on real saved state; second launch.
- Debug and Release coinstalled: separate names, groups, limits and report inputs.
- Home report through rapid tabs, sheets, manual refresh, background/foreground,
  permission loss/regrant, midnight and app/category/site/mixed selections.
- Private app header A → B, Trends/back/week changes, missing history, large text,
  VoiceOver and Reduce Motion. Empty reports must not imply zero use.
- Session starts/ends and contact approvals while app is closed; requester must
  not crash when refreshing an approval. CloudKit production indexes are real gates.
- Free periods, spent limits, recheck, both split cutoffs/carryover, extra-time
  tiers, wake ceilings, overlapping schedules and near-capacity registrations.

## Working method

Use targeted `rg` searches and small diffs. For one-file visual fixes, work
directly. Delegate only bounded independent streams, with one writer per file;
the lead owns integration, reviews diffs and re-verifies evidence itself.

Do not launch parallel Xcode builds against the same build database. Do not
silently change version/build, dependencies, signing, backend endpoints, privacy
claims or deployed schema. Do not push/deploy/submit without instruction; commit
only per the workflow above, on the redesign branch.
Finish with what changed, exact checks run, remaining device checks and the next
smallest step. Never call “build passed” equivalent to “ready for TestFlight.”
