# Setup, welcome, shield and widgets — redesign (proposal, 2026-11-02)

Status: **approved by the owner, 2026-11-02.**

Builds on `docs/redesign-ux-plan.md`, `docs/foundations-redesign.md` and
`docs/today-redesign.md` (all approved). Uses their tokens and components and
does not redefine them. Covers four surfaces that sit outside the four tabs:

- **First-run setup** (`Latch/OnboardingView.swift`, `OnboardingOverridesDraftView.swift`)
- **The 2.0 intro and the upgrade welcome** (`RedesignIntroView.swift`,
  `RedesignWelcomeView.swift`, `MathPhraseMigrationView.swift`, plus the
  retired `LanguageExpansionUpdateView.swift` and `BetaThanksView.swift`)
- **The shield** (`LatchShieldUI/ShieldConfigurationExtension.swift`)
- **The widgets** (`LatchWidgets/DemoraWidgets.swift`, `Shared/DemoraWidgetSnapshot.swift`)

Enforcement, the change engine, migrations, markers and timing are untouched.
This spec changes presentation, copy and two small read-only data projections.

## 0. Owner's call
- Full Mobbin-researched redesign, keeping the intention (plan §0). Plan
  diagnosis #4: "Being blocked is a dead end", and plan §5.8 asks for a
  feasibility check on naming the rule on the shield.
- Hard limits from `CLAUDE.md` → "Permissions, setup, migration and environment
  isolation": approved permission wording and **Continue**; respect denial, let
  setup finish without blocking, no Settings redirect or re-prompt loop (Apple
  5.1.1(iv)); setup, intro and welcome markers stay distinct; view getters
  never decode or write saved state; demos use isolated drafts; Debug/Release
  stay separate across all five targets; no private usage or token-derived app
  names on widgets or the shield.

## 1. Diagnosis (ranked by user impact)

1. **The shield is a dead end, and its copy over-promises.** The same screen
   appears for apps, categories and domains (`ShieldConfigurationExtension.swift:29-41`):
   "Blocked by Demora", a two-paragraph generic body and one "OK" button
   (`:13-27`). It names no rule and no time, and it doesn't point to extra
   time. Its second paragraph promises "an immediate unblock" if the user opens
   Demora (`:22`). Opening the app only re-runs reconciliation and never
   overrides a rule that is genuinely on, so this is misleading exactly when
   the user is most impatient. The dark translucent material (`:15-16`) is the
   only Demora surface outside the paper palette.
2. **The widgets probably render as an error on iOS 17+, and their gallery
   text is English-only.** The shell paints `.background(Color(...navy))`
   (`DemoraWidgets.swift:39`) and never calls `containerBackground`. Apps built
   with the iOS 17 SDK and running on iOS 17+ show Apple's "Please adopt
   containerBackground API" placeholder in that case. This is very likely but
   **not verified on a device**. The widget compiles only
   `DemoraWidgetSnapshot.swift` (pbxproj Sources phase `AC000000000000000000000A`),
   so it has no `tr()`. Content labels arrive translated inside the snapshot
   (`DemoraWidgetSnapshot.swift:153-157`), but the gallery name and description
   are hard-coded English (`DemoraWidgets.swift:127-128, 140-141`). The widgets
   also ignore the user's accent and appearance.
3. **Setup is seven pages, and its directions point to places that won't
   exist.** It has 7 steps (`OnboardingView.swift:87-97`), three of them
   optional. Its copy sends people to "Limits & blocks" (`:308, :348`),
   "Schedules → Day & night" (`:373`), "Delays → Trusted contacts" (`:386`) and
   "Settings → Help → Guide" (`:357`). None of these survive the four-tab plan.
   The upgrade welcome has the same problem: page 1 tours the *old* five-tab
   layout ("Home", "Delays & overrides", "Limits & schedules",
   `RedesignWelcomeView.swift:162-167`). It shows the math-to-phrases offer on
   two pages (`:160`, `:229`). It also promises "The optional walkthrough is
   always in Settings → Help" (`:280`), but nothing calls
   `AppModel.replayTutorial()` (`AppModel.swift:651`), and
   `Tests/UsageNavigationHarness.py:47` asserts the Guide has no replay.
4. **The intro says "2.0 — more powerful, more intuitive" to people who never
   saw 1.0.** The gate is `!welcomeSeen && !introSeen`
   (`RedesignIntroView.swift:6-9`), so fresh installs see it too, before setup.
5. **Dead one-time screens linger.** `LanguageExpansionUpdateView` and
   `BetaTestersView` / `BetaThanksPromptView` are never presented. A repo-wide
   search finds no call sites. `BetaThanks` still submits to and reads a
   CloudKit public database (`BetaThanksView.swift:22-41`), and
   `ContactsService.swift:210` borrows its `containerID` constant.
6. **Small setup defaults fight the foundations.** Setup writes lowercase as
   the default text case (`OnboardingView.swift:23`; foundations F3 makes
   regular the default). The starting-estimate draft is a full card in setup
   (`:355`) and in the welcome (`RedesignWelcomeView.swift:276`), giving a
   once-only, optional question the same weight as the rules.

## 2. Intent
- **Setup:** in two seconds the user knows *which step this is, of how many,
  and that it's optional or not*, with one action: **Continue**.
- **Welcome (upgraders):** *your rules came with you, and here's where they
  live now*, with one action: **Continue** (last page: **Open Today**).
- **Shield:** *this is your own past decision, and Demora is where you can see
  how long it lasts*, with one action: **Close**.
- **Widgets:** *what's on now and until when*, or *what changes next and
  when*, with one tap: open Demora on the matching screen.

## 3. What we took from Mobbin

Three searches used (budget 5): one onboarding flow search, the shield, the widgets.

| App | What we take | Screen |
| --- | --- | --- |
| Jomo — app setup | A thin progress bar plus Back, one question per page, and a reassuring footnote ("Start simple — more options later") under optional choices | [flow](https://mobbin.com/flows/014331e4-1af6-4da6-8ec7-47618c9a69bb) |
| Jomo — onboarding | The first rule is summarised as one card with rows (Block · Active · Unlocks) before committing; the screen-time estimate is a skippable question | [flow](https://mobbin.com/flows/743bc988-c7c6-427e-b122-518a1ee69f7c) |
| Opal — onboarding | A calm, text-only priming page before the system Screen Time prompt; one Continue at the bottom; quiet "I don't know" escape | [flow](https://mobbin.com/flows/91394aa7-8b77-461f-b95a-ad3f177e98f3) |
| Jomo — shield | Light background, centred title, and **"Blocked by: Routine"**: the rule's name on the shield, one Close button | [screen](https://mobbin.com/screens/9b6008e9-c25c-45b0-bf1e-72756afca2f5) |
| Brick — shield | Title states the fact; body says where to go ("open the Brick app"); one warm button with a humane label ("Back to living") | [screen](https://mobbin.com/screens/0338aaef-88cd-4ef4-b4e9-6e5cf45c4126) |
| Brick — widgets | One big number with a small-caps label under it and a mark in the corner; nothing else | [screen](https://mobbin.com/screens/d4e84c64-5a07-412b-9ad7-54ede0b988ef) |
| Tiimo — lock screen | A serif countdown next to a progress ring reads calm, not alarming | [screen](https://mobbin.com/screens/8171ea74-fb00-475b-9362-cb10ee63264e) |
| Jomo — widgets | Rule name plus "2 min / 2 h 15" on a tinted card. **We take the layout only.** Demora's host cannot see usage, so our widgets never show minutes used | [screen](https://mobbin.com/screens/fa1ae031-13bc-4eba-ad97-106f8f85b6f4) |

Not taken: Opal's and Jomo's social-proof, account and paywall pages (Demora is
free, with no accounts), quiz-style "how much do you use your phone"
gamification, and Jomo's app-icon shield art (it would require token-derived
app identity).

## 4. The rule that removes the repetition

| Question | Lives in (once) | Elsewhere |
| --- | --- | --- |
| How long do my changes wait? | Setup step 2; later Rules → Your waits | Setup summary repeats it as a single line only |
| What did I choose in setup? | Setup step 5 summary card | — |
| Did my rules survive the upgrade? | Welcome page 1 "Carried with you" | — |
| Can I replace math with phrases for free? | Welcome page 1 (once; was on two pages) | — |
| Weekly starting estimate | Shown in Insights → Trends; edited in Insights → About this data (Insights I5) | Setup and welcome keep a collapsed optional entry row (O6, aligned with the Insights spec §8) |
| Where is help? | You → Help & guide | Setup and welcome mention it once, on the final page |
| Why is this app blocked, until when? | Today → Now card | Shield says *which rule* only when certain (O8), otherwise points to Today |
| Can I get extra time? | The spent rule's card on Today | Shield names the path, never offers it |
| What's on now / next change? | Today | Widgets mirror it read-only; tap opens Today or Changes |

## 5. Layout, top to bottom

### 5.1 Intro (both audiences, once)
- Keep the logo → wordmark animation exactly as built (timings in
  `RedesignIntroPhase`, Reduce Motion cross-fade, VoiceOver waits for
  Continue, cancellation never consumes the marker, `:147-167`).
- **Two variants, one marker** (decision O3):
  - *Upgrader* (`model.state.isSetUp == true`): wordmark + "2.0" in `accent` +
    tagline "more powerful, more intuitive" (unchanged).
  - *Fresh install*: wordmark only, no "2.0"; tagline "Give yourself time to
    decide." (`hero`, `inkSoft`).
- The variant comes from the already-published `model.state.isSetUp` (the same
  read `RootView` already does at `LatchApp.swift:172`). The intro never
  decodes the store. It is chosen by a pure `RedesignIntroGate.variant(isSetUp:)`.
- Tokens: `paper` background, `ink` wordmark, Continue as a quiet text button
  (`body`, `inkSoft`, ≥ 48 pt), unchanged.

### 5.2 First-run setup — 7 steps become 5

`DemoraWelcomeProgress` restyled: a 4-pt capsule track in `hairline` with the
filled part in `accent`, and "Step 2 of 5" in `label` style (replaces the
monospaced caption, `OnboardingView.swift:495-498`). It sits under the navigation
bar. Back stays in the toolbar. The Language & appearance menu stays top right
(`:188-208`). Every page is a `ScrollView` on `paper`, gutter 20, max width 640,
with the bottom action pinned by `safeAreaInset` (as today, `:125-157`).

| New step | Was | Content |
| --- | --- | --- |
| 1 Welcome | 0 | `pageTitle` "Make room for what matters." · one PaperCard with the two `DemoraWelcomeEntry` rows (restyled: icon in `accent`, title `cardTitle`, detail `meta`) · footnote privacy line (§10) |
| 2 Your waits | 1 | `pageTitle` "A pause, on your terms." · the three delay modes as three selectable PaperCards (title + one-line example), the selected one with an `accent` hairline and a check · durations via the existing `DelayPicker` inside the selected card · footnote "These are your starting settings…" (unchanged) |
| 3 Permissions | 2 | **Unchanged wording and behaviour** (§5.3) |
| 4 Your first limit | 3 | Optional limit (§5.4). Secondary **Set a limit later** stays |
| 5 Make it yours | 4 + 5 + 6 | Two optional cards, then the summary and **Start using Demora** (§5.5) |

### 5.3 Step 3 — Permissions (Apple-sensitive; restyle only)
- Title and body stay **verbatim**: "Permissions" and "Demora needs Screen Time
  access to set limits and block apps, and notifications to tell you when a
  pending change is ready. iOS will ask for each." (`OnboardingView.swift:240-245`).
- The 52-pt `checkmark.shield` glyph becomes a 56-pt glyph in a 96-pt
  `tint(accent)` circle (decorative, `accessibilityHidden`).
- Flow unchanged (`:426-449`). The first **Continue** asks iOS (Screen Time,
  then notifications, `AppModel.swift:400-411`). On approval it advances. On
  denial it stays, shows the existing "That's okay…" text in a PaperCard, and
  the next **Continue** advances. There is no Settings link, no "Try again"
  button and no second prompt. The beta-language notice still never shares a
  tap with the system prompt (`:412-418`).
- Granted: a `StateChip(kind: .free, "Allowed")` replaces "Authorized ✓".

### 5.4 Step 4 — Your first limit
- `pageTitle` "Start with one boundary." · `meta` "Optional. This is a real
  limit, not a demo."
- With access: one PaperCard, modelled on Jomo's single rule card:
  - Row "Apps" → the system picker (`AppPickerSheet`), trailing "Choose" or
    "3 items" (counts only, never names).
  - Row "Name" → text field (placeholder "My first limit").
  - Row "Each day" → the allowance in `time` style with − / + steppers (5–720,
    step 5, same range as `:301`).
  - Footnote: "The selected apps share this allowance."
- Without access: the existing explanation in a PaperCard. The card is not
  shown and Continue is enabled (`:313-316`).
- Bottom: **Continue** (disabled only when a half-made limit has no apps, as
  `:136`), then quiet **Set a limit later**.

### 5.5 Step 5 — Make it yours (merges day/night, overrides and ready)
1. `pageTitle` "Make it yours." · `meta` "Both are optional. You can add them now
   without waiting."
2. **Mornings & nights** card (PaperCard, `sun.horizon` icon): one line of
   explanation and **Set up** → a sheet holding the existing
   `DayNightSetupDraftView` (`:367`). After setup the card shows the group names
   and an Edit button. Invalid groups show the existing warning in `loosen`.
3. **Ways to skip a wait** card (`person.2` icon): "A trusted contact, a
   phrase, or a password. You choose what each can approve." and **Set up** →
   a sheet holding the existing `OnboardingOverridesDraftView`. Afterwards it
   shows counts ("1 contact · 1 phrase").
4. **Your setup** summary PaperCard (replaces the old "Your next chapter."
   page): rows Waits (the `policySummary` text, `:391-402`), First limit (name
   and "30 min a day", or "Not yet"), Mornings & nights, Ways to skip. A
   footnote appears only when access is missing (existing text).
5. **Your starting point** row (optional, collapsed): "Add a rough weekly
   estimate" → expands the existing `WeeklyUsageEstimateDraft` inline. It is
   saved only after a successful setup save (existing order, `:473-479`).
6. Footnote: "How Demora works is in You → Help & guide." (one mention of help
   in setup.)
7. Bottom: **Start using Demora** (primary). Its existing disabled logic is
   kept (`:131-139`).

Why the two extras stay in setup instead of moving to "later": after setup,
adding a way to skip a wait is a *looser* change and waits the full delay.
Day/night additions also follow the policy. The setup waiver is a real benefit
of doing it now, so it stays, behind cards instead of two full pages.

### 5.6 Upgrade welcome — 4 pages become 3 (2 when day/night isn't offered)

Shown once to existing users (`model.state.isSetUp && !welcomeSeen`,
`LatchApp.swift:172`). The progress bar and toolbar match setup. Every page has
a quiet **Skip** (was "Done", `RedesignWelcomeView.swift:117`). Skip still saves
any day/night drafts first, as `complete()` does today (`:349-366`).

| Page | Content |
| --- | --- |
| 1 Your rules came with you | `pageTitle` "A clearer place for your intentions." · "Carried with you" PaperCard (the existing counts, `:200-213`; numbers in `time` style, not monospaced) · **math-to-phrases offer** PaperCard, only if eligible (`:243-259`), shown on this page only · "Four tabs now" PaperCard: Today / Rules / Insights / You, one line each (§10) |
| 2 Mornings & nights | **Only when `offersDayNight` is true** (`:32-42`); otherwise the page is skipped and the progress reads "of 2". It holds the existing one-shot additive draft and its explanation (`:300-305`) |
| 3 Changes still wait | Your waits: the existing `DelayPolicyNavigationRows()` (a real edit queues normally, `:191`) · ways-to-skip note: "Existing contacts keep their permissions. They don't gain extra-time approval automatically." (merges `:267-272`) · collapsed "Your starting point" row (existing draft, `:276`) · `hero` "You're ready. Your rules are still yours." · footnote "How Demora works is always in You → Help & guide." (You spec §8 wording) · primary **Open Today** |

Removed: the "Give your day a little shape" feature list (`:215-240`). Its
three features become one line each on page 1. The legacy-features note keeps
one sentence under "Carried with you". The walkthrough promise (`:280`)
becomes the You spec's "How Demora works" line (You Y10: no interactive
replay). "Open my limits" (`:113`) becomes the single primary **Open Today**
on the last page.

### 5.7 Math-to-phrases sheet (survives, restyled)
`MathPhraseMigrationView` keeps its logic, its draft-only contract (`:1-4`) and
its narrow waiver (pending-change permissions only, no extra time). Visual
changes: `pageTitle`, each staged phrase as a PaperCard with permissions in
`meta`, **Add phrase** as a secondary row, and **Install phrases** as the
primary button. Failure keeps the existing inline message.

### 5.8 The shield

**What it can render** (Apple API, ManagedSettingsUI, not verified on device
in this repo): a background colour and/or blur, one `UIImage` icon, a title and
subtitle (text and colour only, in the system font, with no serif and no
layout control), a primary button label and background, and an optional
secondary button label. The configuration is a still picture: no timers, no
live countdown, no links.

**Restyled screen** (all four `configuration(shielding:…)` overloads):

```
            [Demora logo, ink, 56 pt]
        Blocked by your Demora rules          ← title, ink
   Evening block is on until 21:00.           ← subtitle line 1 (only when certain, O8)
   You set this earlier so it would hold.     ← subtitle line 2
   Open Demora to see what's on, or to ask    ← subtitle line 3
   for extra time if your limit has it.
          [        Close        ]             ← primary: accent bg, white text
```

- Background: solid `paper` (light) / `paper` dark, as a dynamic `UIColor`
  (`UIColor(dynamicProvider:)`), with no blur (`backgroundBlurStyle: nil`).
  Whether the shield process follows the system dark/light trait is an
  **assumption to verify on device**. If it doesn't, ship the light palette.
- Icon: the template `DemoraLogo` asset tinted `ink`. It must be added to the
  LatchShieldUI target's asset catalog; the shield cannot read the app's
  catalog. Until then, the SF Symbol `hourglass` in `ink`.
- Title: "Blocked by your Demora rules" (`ink`). Subtitle (`inkSoft`): the
  lines above. Line 1 appears only under O8.
- Primary button "Close" on `accent`. Without a `ShieldActionDelegate`, iOS
  closes the shielded app. That is today's "OK" behaviour (`:24-25`), assumed
  unchanged.
- No secondary button in this build (decision O9). The copy says where to go.
- The "immediate unblock" paragraph (`:22`) is removed (diagnosis 1).

**Feasibility: can the shield name the rule and its end time?**

| Question | Answer | Basis |
| --- | --- | --- |
| Can the extension read the App Group? | **Yes.** It has `group.com.may.screentimedelay` (Release) / `.dev` (Debug) plus `family-controls` | Verified: `LatchShieldUI/LatchShieldUI.entitlements`, `LatchShieldUIDebug.entitlements` |
| Does it compile the shared models and `tr()`? | **Yes.** Target synchronized groups are `LatchShieldUI` + `Shared` | Verified: pbxproj `PBXNativeTarget` LatchShieldUI |
| Can it call `SharedStore.loadState()`? | **Not safely.** It writes: on success it clears `latch.stateRecoveryNeeded` if set, and on failure it stores `.corrupt` and raises recovery (`SharedStore.swift:200-229`). A display extension must not write coordinated state. It also decodes the whole blob in a small-memory extension (memory ceiling is an assumption) | Verified (code); memory is an assumption |
| Can it read the widget snapshot? | **Yes, read-only.** `DemoraWidgetSnapshot.load()` only reads and decodes (`DemoraWidgetSnapshot.swift:35-40`), and it is in `Shared/`. But it says what is on **overall**, not what blocks *this* app. A session and a spent limit can both be on for different apps, so naming from it alone can misattribute | Verified (code); misattribution is a logic fact |
| Can it know which rule blocks this app? | **Only by token matching.** The callbacks receive an `Application` (`.token`), a category token or a `WebDomain` token, never the store or rule that shielded it. Matching that token against each active rule's saved selection tokens would identify the rule. Apple's tokens are opaque but `Hashable`/`Codable`; equality across the host and extension processes on one device is an **assumption that needs a device spike**. Matching never reads or shows app names | Apple API + assumption |
| Can it show a countdown? | **No.** Static text only. An absolute time ("until 21:00") is fine; a relative one ("in 12 min") goes stale | Apple API |
| Can a button open Demora? | **No.** A `ShieldActionDelegate` (a separate extension point, not present here: `LatchShieldUI/Info.plist` declares only `shield-configuration-service`) gets the tap and may answer `.none`, `.close` or `.defer` (re-draw). It cannot open the parent app. The known workaround posts a local notification the user then taps; that needs notification permission and a **sixth target** with its own Debug/Release IDs and entitlements | Apple API; verified that no such target exists |
| Could a secondary button grant time? | It must not. A delegate that writes `ManagedSettingsStore` would be an instant bypass of the change engine | `CLAUDE.md` delays rule |

**Proposed data path for naming (O8, phase 2):** the host and monitor already
publish the widget snapshot from coordinated saves (`SharedStore.swift:101`,
`:343`, `:373`; `LatchApp.swift:57`, `:75`). Next to it they publish a small
`DemoraShieldSnapshot` (new App Group key `latch.shieldSnapshot.v1`): for each
currently effective blocking item, its rule title, kind, absolute end
(nil = until midnight or until wake) and the opaque token sets it shields. No
usage and no names. The extension loads it read-only and calls a pure
`ShieldCopy.make(snapshot:match:now:)`. When exactly one active item matches
the token, it names it and its end time. When several match, it says "2 rules
are on. The first ends at 19:30." When none match, or the snapshot is
missing or stale (`savedAt` older than the item's end), it falls back to the
generic copy. **Never guess.**

### 5.9 Widgets

Families: `systemSmall`, `systemMedium` (as today) plus lock-screen
`accessoryInline` and `accessoryRectangular` (iOS 16+, the deployment target is
16.0 for the widget, pbxproj lines 877/904) — decision O11.

Surface: `containerBackground(for: .widget) { WidgetInk.card }` on iOS 17+,
with the current `.background` fallback on iOS 16. Padding uses system content
margins. Colours come from a small `WidgetTheme` file in `LatchWidgets/` that
copies the foundations token values (as the report extension does,
foundations §8). Accent comes from `latch.accentColor` read **read-only** from
the widget's own App Group (`UserDefaults(suiteName:)`, no writes). Light and
dark follow the system. Text uses New York for rule names and times and SF Pro
for labels.

**Now & Next — small**
```
NOW                                ◷ (logo, 12 pt, inkSoft)
Evening block                      ← cardTitle serif, 2 lines max
until 21:00                        ← time serif, loosen (free: sage)
───────────────
Next 18:00 · Reading               ← meta, 1 line
```
- Nothing on: "Nothing blocked" (`cardTitle`, `ink`) and, if any, "Next
  18:00 · Reading".
- Medium: left column as small; right column "CHANGING SOON" with the next
  pending summary (1 line) and its landing time.
- Spent limits show "Used up today" (from the snapshot's existing "Limit
  reached" windows, `DemoraWidgetSnapshot.swift:141-147`), never minutes.

**Pending change — small**
```
CHANGING SOON          [Looser]    ← label · StateChip-style capsule (loosen/accent)
TikTok limit 30 → 60 min           ← cardTitle, 2 lines
3:12:04                            ← timeLarge serif, Text(timerInterval:)
Tue 14:32                          ← meta, landing time
```
- Empty: "No changes waiting" (`cardTitle`) + "Changes you make wait here."
  (`meta`).
- Direction needs one new optional `direction` field on
  `DemoraWidgetSnapshot.Pending`. It decodes as nil from old snapshots, and
  then no chip shows.

**Lock screen (O11)**
- `accessoryInline`: "Evening block until 21:00" / "Nothing blocked".
- `accessoryRectangular`: line 1 rule name, line 2 "until 21:00", or for the
  pending widget the summary plus `Text(timerInterval:)`.
- Rule names and change summaries get `.privacySensitive()`, so a locked phone
  shows the placeholder when the system redacts. The exact redaction rules on a
  locked device are an **assumption to verify**.

**Tap targets:** the whole widget opens Demora (WidgetKit's default, no URL
scheme today: no `onOpenURL`, `widgetURL` or `CFBundleURLTypes` in the repo).
Deep links to Today / Changes are decision O12. If adopted, Debug and Release
must register **different** schemes, otherwise iOS may open the wrong one of the
two co-installed apps. Links only navigate; they never act.

**Wake up (feasibility):** no interactive Wake up button. An interactive
`Button(intent:)` needs iOS 17. The intent would run in the widget process,
which has no Family Controls entitlement and doesn't compile the change
engine, `DayNightWake` or `ShieldController`. Adding them would put
enforcement logic in a second writer. The alternative, `openAppWhenRun`, is the
same as tapping the widget. Instead, when a wake is due the Now & Next widget
shows "Good morning. Tap to wake up." and opens Today, where **Wake up** is
the primary action (Today spec §5.3). That needs a `wakeDueFrom` window in the
snapshot (decision O13).

**Gallery strings:** `configurationDisplayName` / `description` move to a
generated strings catalog in the widget target, in all eight languages,
generated from `Shared/Localization*.swift` the way the report snapshot is
generated (`Tests/GenerateUsageLocalization.py`). New names: "Now & next" ·
"See what's on now and what's next." / "Changing soon" · "Your next change
and when it lands." The gallery follows the *system* language; content
follows the in-app language via the snapshot. That limitation is acceptable.

## 6. States

| Surface · state | What shows |
| --- | --- |
| Setup · loading/saving | Primary button shows a spinner, Back and preferences are disabled (existing `isCompleting` / `isRequestingAuthorization`) |
| Setup · permission denied | Step 3 explanation card, plain Continue; step 4 shows the no-access card; summary repeats one footnote. Setup completes; Today later shows the Attention card (Today §5.2) |
| Setup · save failed | Existing alert "Setup couldn't be saved", including `MonitorRegistration.rejectionMessage`; drafts kept |
| Setup · storage unavailable / recovery | Never reaches setup: `RootView` shows "Your setup is safe" first (`LatchApp.swift:154-165`) |
| Intro · backgrounded mid-animation | Resumes the current phase; the marker is written only by Continue or the final phase (existing) |
| Welcome · day/night not eligible | Page 2 skipped; 2 pages |
| Welcome · math not eligible | No offer card |
| Welcome · day/night save fails | Existing alert with Discard drafts |
| Shield · no snapshot / stale / no match | Generic copy (title + lines 2–3) |
| Shield · one match | Line 1 names the rule and its end time |
| Shield · several matches | "2 rules are on. The first ends at 19:30." |
| Shield · ends at midnight / at wake | "until midnight" / "until you wake up" |
| Widget · never published (fresh install) | "Open Demora" placeholder, as today (`DemoraWidgets.swift:60, :105`) |
| Widget · placeholder (gallery) | `redacted(reason: .placeholder)` shapes with sample text |
| Widget · nothing on / no pending | "Nothing blocked" / "No changes waiting" |
| Widget · simulating (tutorial replay) | Not published (`DemoraWidgetSnapshot.swift:83`), unchanged |

Stress tests: German and Polish titles wrap to 3 lines in setup (no
truncation; the bottom bar stays pinned). Hindi "Step 2 of 5" fits. On iPhone
SE, step 5's two cards and summary scroll, and **Start using Demora** stays
pinned. At the largest Dynamic Type, summary rows stack label above value.
Fifty pending changes: the widget shows the next one only. A long rule name is
truncated after 2 lines in widgets, while the time line is never truncated
(`fixedSize`). The shield subtitle is limited only by iOS, so keep it to 3
short lines.

Accessibility: setup progress is read as "Step 2 of 5" (existing label).
Delay-mode cards are buttons with selected traits. The intro keeps its single
combined label. The shield is a system screen, so VoiceOver reads the title,
subtitle and button. Widgets combine each block into one element ("Now,
Evening block, until 21:00"). Reduce Motion: setup pages swap without
animation (existing `move(to:)`, `OnboardingView.swift:404-407`).

## 7. Components

| Need | Use (reuse first; new only with a reason) |
| --- | --- |
| Cards, headers, chips, buttons, times | Foundations: `paperCard()`, `SectionHeader`, `StateChip`, `DemoraPrimaryButtonStyle`, `DemoraType.time` |
| Setup progress | `DemoraWelcomeProgress` restyled (capsule track, `label` text) |
| Setup entries | `DemoraWelcomeEntry` restyled to foundations type |
| Delay mode choice | Existing `DelayPolicyPicker` restyled as three option cards |
| Day/night and overrides drafts | Existing `DayNightSetupDraftView`, `OnboardingOverridesDraftView`, now hosted in sheets |
| Welcome waits editor | Existing `DelayPolicyNavigationRows` (real queue) / `MigrationDelayPreviewView` (demo) |
| Intro | `RedesignIntroView` + new `RedesignIntroGate.variant(isSetUp:)` |
| Shield copy | **New** pure `ShieldCopy.make(snapshot:match:now:)` in `Shared/`. It must run in the extension without the store |
| Shield data | **New** `DemoraShieldSnapshot` (phase 2, O8). It mirrors the existing widget snapshot publisher; the shield cannot safely decode `LatchState` |
| Widget theme | **New** `LatchWidgets/WidgetTheme.swift`. The widget doesn't compile `Theme.swift` |
| Widget sentences | **New** pure `WidgetPresentation` in `DemoraWidgetSnapshot.swift` (compiled in both targets) |

Pure logic, with tests (extend existing harnesses first):

- **`Tests/RedesignIntroHarness.py`**: `variant(isSetUp:)`, fresh vs upgrader.
  `shouldShow` truth table unchanged. Cancellation still never sets the marker.
  The intro body never references `SharedStore.loadState`.
- **`Tests/RedesignMigrationHarness.py`**: welcome page list
  `WelcomePages.make(offersMath:offersDayNight:)` → 2 or 3 pages, the math
  offer on exactly one page. Completing or skipping the welcome writes only
  `redesignWelcomeKey` (plus the existing language marker), never `isSetUp`,
  `redesignMigrationKey`, limits, usage or deadlines. Fresh setup still writes
  all three markers (`AppModel.swift:810-812`). The one-shot day/night and math
  waivers stay single-use after Skip.
- **`Tests/OnboardingOverridesHarness.py`**: five steps; the permission title
  and body strings are byte-identical to today's; `OnboardingView` contains no
  `openSettingsURLString` and no second `requestAuthorization` path; denial
  advances on the next Continue; the extras sheets never call `queue`,
  `ContactsService` or `SharedStore.save`; `textCasing` default is regular.
- **`Tests/ReleaseIsolationHarness.py`**: widget and shield entitlements stay on
  the matching group per configuration; `WidgetTheme` reads `latch.accentColor`
  only from the widget's group and never writes; if O12 lands, the Debug and
  Release URL schemes differ; if a sixth (ShieldAction) target is ever added,
  its IDs and groups follow the same Debug/Release split.
- **`Tests/DeveloperDemosHarness.py`**: the onboarding demo completes the new 5
  steps with drafts only (no App Group, no real markers); the welcome demo with
  `demoState` skips page 2 when `demoDayNightOffer == false`.
- **New `Tests/WidgetShieldPresentationHarness.py`** (pure, macOS-compiled):
  `WidgetPresentation` (now/next/free/used-up/wake-due/empty, midnight
  crossing, overlapping windows, `direction == nil` from old snapshots);
  `ShieldCopy.make` (no match → generic; one match → name + absolute time;
  several → count + earliest end; stale snapshot → generic; never a relative
  time).
- Foundations contrast harness: add the shield background/text/button pairs
  and the widget pairs (light and dark, both accents).

## 8. Changes elsewhere

- **You spec:** owns "Help & guide" and its read-only "How Demora works"
  explainer (Y10, no interactive replay). Setup and welcome point there with
  the You spec's wording. **Rules spec R10** retires the legacy tutorial after
  the four-tab switch; this spec agrees. Its callout string "…always available
  again in Settings → Help." (`OnboardingView.swift:681`) goes with it.
- **Insights spec:** the starting estimate keeps its setup and welcome entry
  (Insights §8); here it becomes a collapsed optional row. Its shared copy
  "…change it later in Insights → About this data" comes from that spec.
- **Rules spec / Insights spec:** setup and welcome copy name "Rules", "Rules →
  Day & night" and "Insights → Starting point". Those copy changes land in the
  **same integration step as the four-tab switch** (foundations §7). Until then
  the current wording stays.
- **Today spec:** the shield and widgets point to Today for "how long" and
  "extra time". The wake-due widget state relies on Today's Wake up action.
  The `NowSummary` wording should match `WidgetPresentation` wording (shared
  strings, separate code, because the widget doesn't compile the host).
- **`Shared/DemoraWidgetSnapshot.swift`:** optional `Pending.direction`,
  optional wake-due window (O13), and label strings for the new sentences. They
  stay backward-compatible with snapshots already on disk (all new fields
  optional).
- **Shield snapshot (O8 phase 2):** published from the same points as the
  widget snapshot. It is written only by host and monitor and read only by the
  shield.
- **Asset catalogs:** `DemoraLogo` template image added to the LatchShieldUI
  target (and the widget, for the corner mark).
- **Retire** `LanguageExpansionUpdateView` (whole file) and `BetaTestersView` /
  `BetaThanksPromptView` (O5). Move `BetaThanks.containerID` into
  `ContactsService` first, because `ContactsService.swift:210` uses it. Keep
  the `latch.languageExpansionUpdate.shown` marker writes untouched
  (`LatchApp.swift:175`, `AppModel.swift:812`). Never reset a marker.
- **`README.md`:** the widgets line (`:188`) and the shield description update
  with the build.
- **Translations:** every new or changed string in all eight catalogs, plus the
  widget's generated strings catalog.

## 9. Motion and haptics
- Intro: unchanged.
- Setup: page changes stay instant (existing choice for Reduce Motion and to
  keep controls still). The progress capsule fills with a 0.2 s ease, or
  instantly under Reduce Motion. Selecting a delay mode gives a light selection
  haptic.
- Extras sheets: system sheet presentation. After a successful draft the card
  cross-fades its content (0.2 s).
- Start using Demora: success haptic after the save returns true (replaces
  none).
- Shield and widgets: no motion. The widget countdown uses the system
  `timerInterval` text, the same as today.

## 10. Copy (English drafts; refine and translate into all eight languages)

Setup
- Unchanged: "Make room for what matters." · "Choose your boundaries now. Give
  yourself time before changing them later." · "A pause, on your terms." ·
  "Permissions" + the approved permission body · "That's okay. Without Screen
  Time access…" · "Start with one boundary." · "Set a limit later" · "Start
  using Demora" · "Continue".
- Privacy footnote (softened so it isn't an absolute claim): "Free. No account,
  ads, or analytics. Your app choices and usage stay on this device."
- New: "Step %d of %d" (exists) · "Allowed" · "Optional. This is a real limit,
  not a demo." · "Apps" · "Choose" · "%d items" · "Each day" · "The selected
  apps share this allowance." · "Make it yours." · "Both are optional. You can
  add them now without waiting." · "Mornings & nights" · "Ways to skip a wait"
  · "A trusted contact, a phrase, or a password. You choose what each can
  approve." · "Set up" · "Your setup" · "Waits" · "First limit" · "Not yet" ·
  "Your starting point" · "Add a rough weekly estimate" · "How Demora works
  is in You → Help & guide." · "Contact invitations are sent after setup."
  (shortened from `:386`).

Intro
- Fresh: "Give yourself time to decide." Upgrader: unchanged.

Welcome
- "A clearer place for your intentions." (kept) · "Carried with you" (kept) ·
  "Four tabs now" · "Today — what's on, what's left, what's changing." ·
  "Rules — every limit and schedule, with your waits on top." · "Insights —
  your usage and trends." · "You — ways to skip a wait, appearance and help."
  · "Changes still wait" · "Existing contacts keep their permissions. They
  don't gain extra-time approval automatically." · "You're ready. Your rules
  are still yours." (kept) · "Open Today" · "Skip".
- Replaced: "The optional walkthrough is always in Settings → Help." → "How
  Demora works is always in You → Help & guide." (You spec wording.)

Shield
- Title: "Blocked by your Demora rules"
- "%@ is on until %@." · "%@ is on until midnight." · "%@ is on until you wake
  up." · "%d rules are on. The first ends at %@."
- "You set this earlier so it would hold."
- "Open Demora to see what's on, or to ask for extra time if your limit has it."
- Button: "Close" (exists in catalogs, e.g. `Localization+German.swift:955`).

Widgets
- "Now" · "Next %@ · %@" · "Nothing blocked" · "until %@" · "Used up today" ·
  "Changing soon" · "Looser" · "Stricter" · "No changes waiting" · "Changes you
  make wait here." · "Good morning. Tap to wake up." · gallery "Now & next" /
  "See what's on now and what's next." / "Changing soon" / "Your next change
  and when it lands."

## 11. Out of scope
- Bringing back the legacy interactive walkthrough (You Y10 and Rules R10
  retire it).
- A ShieldAction extension or any shield button besides Close (O9 keeps it out).
- Live Activities / Dynamic Island for sessions (worth a later spec; needs
  ActivityKit and a push-free update plan).
- Interactive widgets of any kind (no mutation outside the app).
- App icon, App Store screenshots, the website.
- Changes to migration logic, markers, waivers, permission requests or the
  change engine.

## 12. Decisions for the owner

| # | Decision | Why |
| --- | --- | --- |
| O1 | Setup goes from 7 pages to 5: Welcome · Your waits · Permissions · First limit · Make it yours (day/night and ways to skip as optional cards, plus the summary) | Same choices, fewer pages; optional things stop looking like required steps |
| O2 | Day/night and ways to skip **stay in setup** as optional cards, not "later" | After setup, adding a way to skip waits the full loosening delay. Setup is the one free moment |
| O3 | The intro keeps one marker but has two variants: upgraders see "2.0 · more powerful, more intuitive", fresh installs see the wordmark and "Give yourself time to decide." | "More powerful than what?" means nothing to a new user |
| O4 | The upgrade welcome goes from 4 pages to 3 (2 when day/night isn't offered); math offer shown once; describes the four tabs; walkthrough promise removed | The current page 1 tours a layout that won't ship; the promise points to a feature with no caller |
| O5 | Retire `LanguageExpansionUpdateView` and the beta-tester screens (never presented); keep their markers; move the CloudKit container constant to `ContactsService` | Dead code with a public-database submission path; no user sees them |
| O6 | The weekly starting estimate stays in setup and the welcome, but as a collapsed optional row instead of a full card (aligned with Insights §8) | Setup is the natural "before" moment, but a once-only optional question shouldn't weigh as much as the rules |
| O7 | The shield moves to paper/ink with the Demora logo, new copy, and **Close** instead of OK; the "immediate unblock" promise is removed | Matches the app; stops a promise the app can't keep when a rule is genuinely on |
| O8 | Shield names the rule **only when token matching proves it**. Phase 1 ships generic copy now; phase 2 adds a read-only shield snapshot after a device spike confirms token equality across processes | Naming the wrong rule is worse than naming none; `loadState()` writes and can't be used from the shield |
| O9 | No secondary shield button and no ShieldAction extension in this redesign | A button can't open Demora; the notification workaround needs a sixth target and notification permission for a small gain |
| O10 | Widgets restyled to paper/card/ink with `containerBackground`, the user's accent, serif names and times, and localized gallery text | Fixes the likely iOS 17 placeholder and the English-only gallery; matches the app |
| O11 | Add lock-screen `accessoryInline` and `accessoryRectangular` to both widgets, with names marked privacy-sensitive | Cheap with the existing snapshot; "until 21:00" at a glance is the most-used fact |
| O12 | Widget taps deep-link to Today (Now & next) and Changes (Changing soon) through distinct Debug/Release URL schemes; links only navigate | Saves a tap; separate schemes keep the co-installed apps apart. Alternative: keep plain "open app" |
| O13 | No interactive Wake up. The widget shows "Tap to wake up" when due and opens Today | A real wake would need enforcement code in the widget process; tapping is one step and keeps one writer |

### Open questions
- **Q1 (resolved with sibling specs, needs the owner's nod):** the You spec
  (Y10) offers a read-only "How Demora works" instead of the interactive
  replay, and Rules R10 retires the legacy tutorial
  (`AppModel.replayTutorial()`, `AppModel.swift:651`, has no caller;
  `UsageNavigationHarness.py:47` forbids it in the Guide). This spec follows
  them: the welcome promises the explainer, not a walkthrough. If the owner
  wants the interactive tour back, all three specs change together.
- **Q2:** is token equality across the host and shield processes reliable on a
  signed device (O8 phase 2)? This needs a one-day spike with a session and a
  spent limit on different apps.
- **Q3:** does the shield follow the system dark/light appearance, and does
  `.privacySensitive()` redact as expected on a locked lock screen? Both are
  device checks.
- **Q4:** are the approved permission page's *title* ("Permissions") and the
  glyph part of what Apple reviewed? This spec keeps both text strings
  verbatim and changes only the glyph's container.

## Owner's answers (2026-11-02)
Approved with the recommended answers to the open questions:
- Q1: no interactive tour; the welcome promises "How Demora works".
- Q2, Q3: device checks during the build; shield phase 2 only after the token
  spike passes.
- Q4: the permission page keeps its reviewed title and text verbatim.
