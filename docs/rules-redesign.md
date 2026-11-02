# Rules, rule summary and editors — redesign (proposal, 2026-11-02)

Status: **approved by the owner, 2026-11-02.**

Builds on `docs/redesign-ux-plan.md` §5.3–5.5 (approved),
`docs/foundations-redesign.md` (tokens, PaperCard, SectionHeader, StateChip,
CountdownText, HoldButton, DayChips) and `docs/today-redesign.md` (the
**ChangeReceiptSheet**, §5.10, and the Changes ledger, §5.9). Those are reused,
not redefined. Enforcement, the change engine, monitoring and every
`ChangeAction` stay exactly as they are: this spec moves and redraws, it adds
no new kind of change.

Covers: the **Rules** tab, the **rule summary sheet**, the **New rule chooser**,
and every rule **editor** (limit, repeating block / free period, planned,
session, day & night group, legacy wake / sleep, per-limit wake-up, website
list, always-on toggles, schedule priority, delay policy).

## 0. Owner's call
- Plan: "Rules is every rule in one list, grouped by kind, each a card with a
  state chip. The delay policy sits at the top… Calendar and conflicts open from
  the Rules header." Tap a rule → summary sheet with Edit and Remove; editors are
  one plain page; every save and remove ends on the change receipt.
- Plan decisions this spec carries out: D2 (waits at the top of Rules), D3
  (chip on each affected rule), D4 + D9 (receipt for every edit and removal),
  Today T5 (extra time leaves the Limits tab).

## 1. Diagnosis (ranked by user impact)

1. **"What will loosen, and when" is invisible on the rules themselves.** No rule
   row shows a pending change: after a looser edit, `LimitRow`
   (`LimitsView.swift:603`) still shows the old minutes and only "N apps, N
   categories" (`:617`). Recurring, planned and free-period rows show an
   "ACTIVE" badge at most (`SchedulesView.swift:540`). Only day & night says
   "pending" (`DayNightViews.swift:63-66`). The one fact Demora exists for is
   absent where the user looks for it.
2. **Removing a rule is one tap with no check and no stated wait.** Remove
   limit queues and dismisses (`LimitsView.swift:786-789`); "Remove…" queues
   immediately for recurring blocks (`SchedulesView.swift:471`, `:719`), planned
   (`:657`) and free periods (`:748`); "End early…" (`:581`), "Queue: remove"
   site (`SettingsView.swift:987`) and the on/off toggles (`:946`) likewise.
   Only day & night groups confirm (`DayNightViews.swift:110`). These are the
   less-strict changes Demora is meant to slow down.
3. **Rules are scattered across three tabs and up to four levels.** Limits are
   on the Limits tab; a recurring block is Schedules → Sessions → Recurring
   (`SchedulesView.swift:286`, `:342`); day & night is another push
   (`:293`); the per-limit "Group wake-up" hides inside day & night with the
   subtitle "Limits & blocks" (`DayNightViews.swift:95-98`); general blocks
   appear twice (Limits `LimitsView.swift:112` and Settings → Rules → General
   blocking `SettingsView.swift:852`); waits live on the Delays tab.
4. **Editors read like settings lists, each built differently.** The limit
   editor has three disclosure groups plus seven weekday steppers
   (`LimitsView.swift:862-1056`); day & night uses seven toggles
   (`DayNightViews.swift:486`); the wake editor uses capsule chips
   (`LimitsView.swift:293`); the recurrence picker uses circles
   (`SchedulesView.swift:816`). Save is "Queue change" in the toolbar in six
   editors but an inline button in five others (wake, sleep, group wake, delay
   policy, priority), and the delay hint sits at the very bottom
   (`LimitsView.swift:1145`).
5. **What can be edited is inconsistent and unexplained.** A recurring block
   can only change its apps (`ScheduleSelectionEditorView`,
   `SchedulesView.swift:878`); planned windows and free periods cannot be edited
   at all; the only detail page (`ScheduledItemDetailView`, `:423`) is reachable
   from "now & next" but not from the lists.
6. **Explanations crowd the content.** Day & night opens with four paragraphs
   (`DayNightViews.swift:600-612`); Conflicts with five lines before any content
   (`ScheduleConflictsView.swift:29-42`); every list ends with a footnote that
   restates the delays (`SchedulesView.swift:592`, `:668`, `:757`).
7. **Dead and legacy paths add noise.** `ExemptionEditorView`
   (`SchedulesView.swift:1119`) has no callers. Legacy wake/sleep editors
   (`LimitsView.swift:398`, `:502`) are reachable only through "Existing
   wake/sleep settings" (`DayNightViews.swift:175`).

## 2. Intent
In two seconds the user should know **every rule they have, what each one is
doing right now, and which are about to loosen**, with one action: **New rule**.

## 3. What we took from Mobbin

Four searches used this session (budget was five); the first five rows were
already cited in the plan.

| App | What we take | Screen |
| --- | --- | --- |
| Opal — rules grid | A card per rule with a live state chip; status readable without opening | [screen](https://mobbin.com/screens/f6f2258d-c88e-4b70-b278-2950f8aad2bd) |
| Opal — rule detail | Tap → short summary (when / days / what), one Edit | [screen](https://mobbin.com/screens/20ad6235-3f7b-4ade-bd5b-f52a160fbf60) |
| Opal — editor | From/To rows joined by a dotted thread; day chips with a "Mon, Wed, Fri" readout; deliberate commit at the bottom | [screen](https://mobbin.com/screens/7bb284c6-ecb9-41f4-9c12-80bc34f02a3d), [variant](https://mobbin.com/screens/8aaab4be-9d25-4f9f-a005-54f6602da20e) |
| Brick — schedules / add schedule | One summary line per schedule; overlap warning inline in the editor | [list](https://mobbin.com/screens/64828f33-882c-4cde-9692-a6168730366b), [editor](https://mobbin.com/screens/04956d6d-fdf7-4fd3-95fb-d6cf8c9f8ae5) |
| Brick — edit mode | Grouped card: name row, two-option behaviour switch, Apps and Websites rows with count + chevron; primary Save, quiet text "Delete" under it | [screen](https://mobbin.com/screens/6c2d47f4-28d9-4865-a582-2647a0eb1e5c) |
| Yazio — "What would you like to create?" | Chooser as cards, each a title + one example line, so the type is chosen by meaning | [screen](https://mobbin.com/screens/57a3e8db-7015-42bb-a4c7-f6ef0ebec4f6) |
| Spotify — create sheet | Icon in a soft circle, title, one plain line; six options in one sheet without scrolling | [screen](https://mobbin.com/screens/817d6761-615b-4c16-a9f8-59e457e58f20) |
| Jomo — add limit | One large number with − / + and a computed readout ("= 15 min/day"); advanced options behind one plain link | [screen](https://mobbin.com/screens/13c9a155-2090-4c9a-a157-fe5e3886eccb) |
| Forest — Time Guard plan | Section headers that read as a sentence ("I want to limit usage of…") over an apps preview row | [screen](https://mobbin.com/screens/69ba2402-c594-4bad-b748-63a22786f084) |
| Opal — Never Allowed | Always-on items as one list: built-in toggle row, entries with a remove control, an "Add" row at the end | [screen](https://mobbin.com/screens/99eb07c9-d6f6-435d-a344-931f64c1b2c9) |

Not taken: Opal's dark glass, Jomo's mascot, Brick's black buttons. Demora keeps
paper, ink, serif and its one accent.

## 4. The rule that removes the repetition

| Question | Lives in (once) | Elsewhere: link only |
| --- | --- | --- |
| What rules do I have? | Rules, grouped by kind | Today's limits header "All rules" |
| Is this rule on / blocked now? | Rule card's StateChip | Today Now card (sentence) |
| Is this rule about to change? | Rule card pending line → Changes ledger | Summary sheet: one line + "See in Changes" |
| Exactly what does this rule do? | Rule summary sheet | Calendar / Today line items open the same sheet |
| How long do my changes wait? | Rules → Your waits strip | Receipt shows the resulting time |
| Can I get extra time now? | Today, under the report (T5) | Summary sheet's Extra time row links to Today |
| Which rules overlap? | Conflicts (header icon) | Repeating-block editor: inline overlap note for the draft only |
| What's on another day? | Calendar (header icon) | — |
| Why is a delay applied? | ChangeReceiptSheet | No inline "takes effect in" hints anywhere |

## 5. Layout, top to bottom

```
Rules                               [cal] [⑂•]
┌─────────────────────────────────────────────┐
│ YOUR WAITS   Stricter: right away ·         │
│              Looser: 1 day               ›  │
└─────────────────────────────────────────────┘
LIMITS
┌─────────────────────────────────────────────┐
│ Social               [Blocked]              │
│ 30 min a day · 4 apps, 1 category           │
│ ◷ Loosens in 3h 12m                         │
└─────────────────────────────────────────────┘
┌ Games                [Starts in 2h] ┐ …
SCHEDULES
┌─────────────────────────────────────────────┐
│ Evening block        [On until 21:00]       │
│ Weekdays 18:00–21:00 · only 3 apps          │
└─────────────────────────────────────────────┘
DAY & NIGHT · PLANNED · ALWAYS ON
┌ App deletion [On] ┐ ┌ Adult websites [Off] ┐ ┌ Websites  4 sites [On] ┐

        [ +  New rule ]          ← pinned above the tab bar
```

### 5.1 Header
- `DemoraPageTitle("Rules")` (`pageTitle`, no wordmark). Trailing: two 44-pt
  icon buttons, `calendar` → **Calendar** and `arrow.triangle.branch` →
  **Conflicts**. Conflicts shows a `loosen` dot when
  `SchedulePrecedence.conflicts(…)` is non-empty (computed once on appear and
  on state change, not per frame).
- No help button (help lives in You; complex editors get a contextual "?").
- When `model.enforcementDegraded`: one slim PaperCard with `loosen` tint under
  the header — "iOS can't watch all your rules in the background. Removing a few
  restores full blocking." (replaces `EnforcementBanner`, `LimitsView.swift:585`;
  Today's attention card links here).

### 5.2 Your waits strip
- PaperCard, one row, 16 pad. `label` "YOUR WAITS"; value in `meta` with
  durations in `time` (small): by `DelayPolicy.mode` —
  separate: "Stricter: 5 min · Looser: 1 day"; shared: "Every change: 1 day";
  lenientOnly: "Stricter: right away · Looser: 1 day". Chevron.
- If a delay-policy change is pending: pending line "◷ Changes in 3h"
  (CountdownText) → ledger.
- Tap → **Delay policy editor** (§5.7 K). Replaces `DelayPolicyNavigationRows`
  (`DelayPolicyViews.swift:50`) and the retired `DemoraDelayRow`.

### 5.3 Sections
`SectionHeader` per kind, in this order; a section is **hidden when empty**
(except on first use, §6). Gap between cards 12, between sections 28.

| Section | Cards, in order | Source |
| --- | --- | --- |
| **Limits** | `state.limits` in saved order, then pending additions | `AppLimit`, `.addLimit` |
| **Schedules** | Recurring blocks, then recurring free periods, each by start time; then pending additions | `schedules`, `exemptions`, `.addSchedule`, `.addExemption` |
| **Day & night** | Groups in saved order; pending new group; legacy "Wake-up" / "Sleep" cards only when non-default (same test as `hasLegacyWake/Sleep`, `DayNightViews.swift:156-173`) | `dayNightGroups`, `wakeRule`, `sleepRule` |
| **Planned** | Running sessions (ends soonest first), then planned windows by start; past windows hidden | `sessions.filter(isActive)`, `planned` |
| **Always on** | App deletion, Adult websites, Websites (always shown, they are switches) | `blockAppRemoval`, `blockAdultWebsites`, `blockedDomains` |

The Limits section footer holds the quiet text button **Recheck blocked limits**
(today's card, `LimitsView.swift:58-75`), shown only when at least one limit
reads Blocked; result messages stay as alerts (`:138-145`).

### 5.4 Rule card (`RuleCard`)
- PaperCard, 16 pad, whole card is one button (44 pt+), opens the summary sheet.
- Line 1: rule name (`cardTitle`, 2 lines max) · StateChip trailing.
- Line 2: one summary line (`meta`, `inkSoft`, 1 line, tail-truncated), from
  pure `RuleSummaryLine.make` (§7):
  - Limit: "30 min a day · 4 apps, 1 category"; weekday budgets → "20–60 min a
    day"; 0 → "Blocked all day"; suffixes "· split", "· extra time" when set.
  - Repeating block: "Weekdays 18:00–21:00 · only 3 apps" / "Every day
    22:00–07:00 · all except 2 apps"; monthly → "15th of each month 09:00–12:00".
  - Free period: "Every day 13:00–14:00 · free period".
  - Day & night: "Wake 7:00 + 20 min · Sleep 23:00 · Every day".
  - Planned: "Sat 9 Nov 09:00 → Sun 18:00 · only 3 apps".
  - Session: "Block · 3 apps" / "Free period".
  - Always on: "Any app" / "Apple's filter" / "4 sites".
- **StateChip (live state)** from pure `RuleChip.live(…)`, one per card:

  | Kind | Condition | Chip |
  | --- | --- | --- |
  | Limit | id ∈ `SharedStore.loadBlockedLimitIDs()` or today's minutes = 0 | **Blocked** (`blocked`) |
  | Block (recurring, planned, session, sleep) | active now | **On until 21:00** (`active`) |
  | Free period / free session / unblock session | active now | **Free until 13:00** (`free`) |
  | Day & night | wake gate waiting | **Opens 7:42** (`loosening`) |
  | Any timed rule | next start within 24 h | **Starts in 2h** (`upcoming`) |
  | Any timed rule | otherwise | none (summary line carries the days) |
  | Always on | — | **On** (`active`) / **Off** (`neutral`) |
  | Limit | otherwise | none (usage minutes are never shown: the host can't see them) |

- **Pending line (line 3, only when a change for this rule waits)** from pure
  `RulePending.index(state.pending)`: clock glyph + "Loosens in" / "Removed in"
  (`loosen`) or "Tightens in" (`accent`) + CountdownText to `appliesAt`. One
  line even if the rule has one change (the engine allows one per conflict key).
  Tap on the line → Changes ledger scrolled to that change; the rest of the card
  still opens the summary.
- **Pending addition** (rule queued but not yet existing): same card, hairline
  drawn dashed, name in `inkSoft`, pending line "Starts in 4m" / "Added in 4m".
  Tap → summary sheet in "waiting" mode (facts from the queued action, only
  "See in Changes" as action).

### 5.5 New rule button and chooser
- **New rule** is the screen's one primary action, pinned with
  `safeAreaInset(edge: .bottom)` above the tab bar (same placement as Today's
  Block now). Hidden while `model.inTutorial` (tutorial keeps its own anchors,
  §8).
- Tap → **NewRuleChooser**, medium-detent sheet, title "New rule" (`hero`), six
  rows, each: 40-pt `card`-tinted circle with symbol, title (`cardTitle`), one
  line (`meta`). Order by frequency:

  | Row | Line | Opens | Disabled when (reason shown in the row) |
  | --- | --- | --- | --- |
  | Daily limit (`hourglass`) | "A daily time budget for some apps" | Limit editor (new) | — |
  | Block now (`play.circle`) | "Block apps for a set time, starting soon" | Session editor | — |
  | Repeating block (`repeat`) | "Every day, some days, or monthly — or a free period" | Repeating editor | — |
  | Plan a block (`calendar.badge.clock`) | "One time: a trip, an exam, a weekend" | Planned editor | — |
  | Day & night (`sun.horizon`) | "A wake-up wait and a sleep time" | Day & night editor (new) | 5 groups exist; or a day & night change is pending |
  | Website (`globe`) | "Block a site by its address" | Website list, add field focused | — |

  (Plan order kept except Repeating moves above Plan, because recurring rules are
  far more common than one-offs — R2.)
- Choosing a row dismisses the chooser and presents the editor as a full sheet.

### 5.6 Rule summary sheet (`RuleSummarySheet(ref: RuleRef)`)
Opened from a rule card, Today's Now card / day thread (today §5.3, §5.6) and
Calendar. Medium and large detents. It **reads the live rule from
`model.state` on every render** (like `ScheduleSelectionEditorView`,
`SchedulesView.swift:890`), so a stale sheet never shows or edits a removed rule.

```
DAILY LIMIT                          [Blocked]
Social                                  ← hero
- - - - - - - - - - - - - - - - - - - - - - -
How much     30 min a day (Sat–Sun 60)
Days         (S)(M)(T)(W)(T)(F)(S)      ← DayChips, read-only
What         4 apps, 1 category       ›
Split        Morning 10 · Evening 20
Extra time   2 uses · 2 left today
             Get extra time on Today  ›
Wake-up      7:00 + 10 min            ›  ← only if already set (R7)
- - - - - - - - - - - - - - - - - - - - - - -
◷ Looser change waiting · lands Tue 14:32
  See in Changes ›
[ Edit ]                                ← secondary prominent, full width
Remove limit                            ← quiet, loosen ink
```

- Header: kind as `label` ("DAILY LIMIT", "REPEATING BLOCK", "FREE PERIOD",
  "DAY & NIGHT", "PLANNED", "SESSION", "ALWAYS ON"), name in `hero`, the card's
  StateChip.
- Fact rows (`FactRow`: label `meta inkSoft` left, value `body` right, wraps
  under at large type). Only rows that apply:
  - **When**: window "18:00–21:00", recurrence, or planned start → end; session
    "Until 21:00".
  - **Days**: read-only DayChips for weekly recurrence and day & night groups;
    "Every day" text otherwise.
  - **What**: "Block only 3 apps" / "Block all except 2 apps" / "4 apps, 1
    category, 2 sites" → push a list rendered with `SelectedAppsView`
    (`LimitsView.swift:685`). Day & night: scope mode + limit names.
  - **How much** (limits): budget; per-weekday values when set.
  - **Split** (limits with `split`): portions in order.
  - **Extra time** (limits with `extraTime`): number of uses and their gates in
    words; today's state from `LimitFeatures.extraTimeState` ("2 left today",
    "none left today"); when `.ready`, a link "Get extra time on Today" (switches
    to Today and scrolls to the extra-time row; no gate starts here — T5).
  - **Wake-up** (day & night: start, wait, latest; limit: per-limit wake only
    when already configured, R7).
- Pending block (only if pending): one line in `loosen` / `accent` with landing
  time, and "See in Changes" (ledger is the only place to cancel — plan §2).
- Actions (bottom, thumb zone). By kind, using **existing** change actions only:

  | Kind | Primary | Quiet action | Action queued (via receipt) |
  | --- | --- | --- | --- |
  | Limit | **Edit** → limit editor | Remove limit | `.configureLimit` / `.removeLimit` |
  | Repeating block | **Edit apps** → apps editor (R5) | Remove block | `.updateScheduleSelection` / `.removeSchedule` |
  | Free period | — | Remove free period | `.removeExemption` |
  | Planned | — | Remove | `.removePlanned` |
  | Session | — | End early | `.endSessionEarly` |
  | Day & night group | **Edit** → group editor | Remove group | `.upsertDayNightGroup` / `.removeDayNightGroup` |
  | Legacy wake / sleep | **Edit** | — (turning off is inside the editor) | `.setWakeRule` / `.setSleepRule` |
  | App deletion / Adult websites | **Turn off** / **Turn on** | — | `.setBlockAppRemoval` / `.setBlockAdultWebsites` |
  | Websites | **Edit list** → website list | — | `.addBlockedDomain` / `.removeBlockedDomain` |

  Free period and planned show one sentence where Edit would be: "To change it,
  remove it and add a new one." (R5).
- When a change for this rule is already pending (same `ChangeEngine.conflictKey`;
  for day & night, any collection change), Edit/Remove are disabled and one line
  says: "A change is already waiting. Cancel it in Changes to make a different
  one." (replaces "…Cancel it on the Home tab first…", e.g.
  `SchedulesView.swift:476`).
- Remove / End early / Turn on-off → **ChangeReceiptSheet** on top of this sheet;
  on confirm both sheets dismiss and the card shows its pending line.
- If the rule disappears while open (removal applied): "This rule has been
  removed." and Done.

### 5.7 Editors — one plain page each

**Shared scaffold (`RuleEditorPage`)**, used by every editor below:
- Full sheet with `NavigationStack`; inline title ("New daily limit" or the
  rule's name); toolbar **Cancel** only. Cancel with an edited draft asks once:
  "Discard your changes?" (Discard / Keep editing).
- Body: PaperCards under `SectionHeader`s in this fixed order, each only when
  it applies: **WHAT · HOW MUCH · WHEN · EXTRA TIME**. Section headers read as a
  plain label, not a sentence (translations).
- **Advanced options are rows, not disclosures**: "Different limit per day ·
  Off ›" pushes a sub-page inside the sheet. A sub-page's edits belong to the
  same draft; nothing is queued from a sub-page.
- Bottom, pinned: primary **Review change** (full width capsule). Disabled
  while the draft is unchanged or invalid; above it, one line with the **first**
  problem from pure `EditorValidation` (e.g. "Choose at least one app.").
  Tapping opens **ChangeReceiptSheet** with the editor's action; confirm →
  `model.queue(action)` → dismiss receipt and editor. No inline delay text
  anywhere (foundations §4).
- If the setting already has a pending change: the button is replaced by the
  "A change is already waiting…" line (same rule as §5.6).
- A "?" button in the nav bar only for day & night, split budget and conflicts;
  it opens a short help sheet holding the paragraphs that today sit above the
  content.

**A. Daily limit** (`LimitEditorView`, `LimitsView.swift:703`)
- Name (new only, as today `:733`; existing limits keep their name).
- WHAT: row "Apps · 4 selected ›" → `AppPickerSheet`; under it up to six token
  labels and "and 3 more". When the selection changes on an existing limit, one
  line: "Changing apps always counts as a looser change." (the engine already
  classifies it so; spent allowance and the rule ID are preserved by
  `.configureLimit`, `SharedModels.swift:1161`).
- HOW MUCH: `DurationControl` — the budget in `timeLarge` ("30 min", "1 h 15
  min", "Blocked all day" at 0) with − / + (5-min steps, repeat on hold), tap the
  value for the existing wheels (`DurationPicker`, `:644`, 0–12 h). Rows:
  - "Different limit per day · Off ›" → sub-page: seven rows (weekday · value),
    each opening the same DurationControl; one "Same every day" reset. Replaces
    the steppers at `:867-876`; data unchanged (`weekdayMinutes`).
  - "Split the day · Off ›" → sub-page: a 24-hour bar with cutoff marks and the
    portions labelled, then the existing fields (on/off, three portions, cutoffs,
    first/middle minutes, carry unused). Same clamps as `:893-952`. The callback
    timing note (`:776`) moves here as one footnote.
- EXTRA TIME: row "Extra time · 2 uses ›" → sub-page: each use is a small card
  "Use 1 · 20 min · after a 5-min wait" with minutes, gate (Wait / password /
  phrase / trusted contact — same menu and filters as `:980-1036`) and wait;
  "Add another use" up to five; remove use. Footer: "Extra time opens only after
  the whole day's budget is spent, and resets at midnight."
- iOS < 17.4: the dismissible counting note (`LimitsView.swift:50-57`) moves to
  the HOW MUCH card.
- **Remove is not in the editor** — it lives on the summary sheet (R6).
- Action: `.addLimit(draft)` / `.configureLimit(draft)` — `draftLimit` and
  `isValid` (`:1068-1131`) reused unchanged.

**B. Repeating block / free period** (`ScheduleEditorView`, `SchedulesView.swift:969`; new only)
- Name. Type: segmented **Block** / **Free period** (free in `free` ink, with
  "Limits won't block and usage won't count during this time.").
- WHAT (block only): two-option segmented "Only these apps" / "All except
  these"; Apps row.
- WHEN: **From** and **To** rows joined by a dotted thread (Opal), compact time
  pickers; "Ends next day" note when To < From. **Repeats**: segmented Every day
  / Some days / Monthly. Some days → DayChips (replaces the circles at `:816`).
  Monthly → "Day of month" or "Nth weekday" menus (`:837-851`). Monthly-across-
  midnight error inline (`:1044`).
- Inline overlap note (Brick): "Overlaps with Evening block on Mon, Wed." from
  `SchedulePrecedence.conflicts` run on state + draft; informational, never
  blocks saving; "See conflicts ›".
- Action: `.addSchedule` / `.addExemption` (existing drafts `:1082-1098`).

**B2. Edit apps of a repeating block** (`ScheduleSelectionEditorView`, `:878`)
- Same scaffold; WHEN and Type shown read-only at the top as fact rows; WHAT
  editable. The note "Changing apps always waits your looser delay. The current
  block stays in effect until then." (`:939`) stays as one line.
- Action `.updateScheduleSelection` with the existing `acceptsSelection` check.

**C. Plan a block** (`PlannedEditorView`, `:1209`; new only)
- Name. Type: three options (Only these apps / All except these / Free period).
- WHAT (not free). WHEN: Starts / Ends date + time rows (starts ≥ now, ends >
  starts, as today `:1262-1267`).
- Action `.addPlanned` (validity `:1308` unchanged — note it ignores website
  tokens in the count `:1248`; kept, see §11).

**D. Block now / session** (`SessionStartView`, `:1318`)
- Name (optional, placeholder "Deep work"). Type: Block / Unblock / Free.
  WHAT (not free), with the existing one-line explanations for Unblock and Free.
- HOW LONG: DurationControl, 1 min–24 h.
- Receipt adds one line under "Takes effect": "Then runs for 60 min." (replaces
  "%@ — session starts in %@, then runs %d min", `:1389`).
- Also opened by Today's Block now. Action `.startSession` unchanged.

**E. Day & night group** (`DayNightGroupEditor`, `DayNightViews.swift:332`)
- Keep the injected API (`canSave`, `onSave`, `isDemo`, `canChooseApps`):
  onboarding and the upgrade welcome use it with drafts
  (`DayNightSetupDraftView`, `:265`) and must stay store-free. Only the live
  wrapper (`DayNightQueuedEditor`, `:225`) gains the receipt: its Save becomes
  **Review change** and presents the receipt with
  `.upsertDayNightGroup(draft)`; the existing validity guards (`:254-258`) run
  before the receipt and again before `queue`.
- WHAT: two-option "Chosen limits and apps" / "Everything except…"; limit
  checklist (`:518`); apps row; every category / fallback error stays verbatim
  and blocks saving (category-wide fallback exceptions remain unrepresentable).
- WHEN: **Wake-up** card — toggle "Ask me to tap Wake up", start time, wait
  after tap (DurationControl), latest wake-up (`WakeCeilingPicker`). **Sleep**
  card — toggle, sleep begins. **Days**: DayChips (replaces seven toggles,
  `:486`) with the line "Days apply to the morning you wake and the evening
  sleep starts." Row "Different times per day ›" → sub-page (the disclosure in
  `WakeTimingEditor.swift:35`).
- "?" help: the four paragraphs of `DayNightExplanation` (`:600`).
- The Day & night list page (`DayNightSchedulesView`, `:6`) is retired: groups
  are cards in Rules, Wake up is on Today, add is in the chooser, the 5-group cap
  and "one change at a time" become chooser / summary reasons.

**F. Legacy wake-up / sleep** (`WakeBlockEditor` `LimitsView.swift:398`, `SleepBlockEditor` `:502`)
- Only reachable from their legacy cards. Same scaffold; `BoundaryWeekdaysEditor`
  (`:293`) → DayChips; `BoundaryScopeEditor` (`:321`) logic unchanged, drawn as
  WHAT. The inline "Queue change" button (`:484`, `:565`) becomes Review change.
  All guards (`boundaryChangePending`, wake ≠ sleep start, `isValid`) unchanged.

**G. Per-limit wake-up** (`GroupWakeDelayEditor`, `WakeScheduleView.swift:81`)
- Opened from the limit summary sheet's Wake-up row (only when the limit already
  has `wakeDelayMinutes`, R7). Uses `WakeTimingEditor`; keeps the two notes
  about running waits and spent usage (`:110-113`) as one footnote. Action
  `.setGroupWakeSchedule` (its own conflict key shares `limit-<id>`, so it stays
  a separate save from the limit editor). `WakeScheduleView` list is retired.

**H. Website list** (`WebsiteBlockerEditor`, `SettingsView.swift:967`)
- Pushed page "Websites". Top card: text field "reddit.com" + **Add** →
  receipt (`.addBlockedDomain`, stricter → plain Confirm). Then one row per
  domain with a quiet **Remove** → receipt (`.removeBlockedDomain`, HoldButton).
  Rows with a pending add/remove show a pending line. One footnote: "Blocking any
  site also turns on Apple's adult-content filter." `canAdd` unchanged.

**I. App deletion / Adult websites** (`BlockToggleEditor`, `SettingsView.swift:924`)
- No page of their own: the summary sheet shows the explanation (today's
  footers `:894`, `:905`) and Turn on / Turn off → receipt.

**J. Schedule priority** (`SchedulePriorityEditor`, `ScheduleConflictsView.swift:96`)
- Inside Conflicts. Page: name, current priority, one line "Default order:
  wake-up → recurring → planned → sessions.", button **Prioritize this** /
  **Restore default** → receipt (`.setSchedulePriority`). Pending guard
  unchanged.

**K. Your waits** (`DelayPolicySettingsView`, `DelayPolicyViews.swift:81`)
- Title "Your waits". One line "New waits follow your current waits. Countdowns
  already running keep their time." `DelayPolicyPicker` restyled with cards; the
  inline Queue button (`:106`) becomes Review change → receipt
  (`.setDelayPolicy`). Pending guard unchanged.

### 5.8 Calendar and Conflicts (header destinations)
- **Calendar** (`CalendarView`, `SchedulesView.swift:1438`): restyled with
  tokens only; tapping an item opens the summary sheet instead of
  `ScheduledItemDetailView`.
- **Conflicts** (`ScheduleConflictsView`, `ScheduleConflictsView.swift:8`):
  title, one line "Rules that overlap in the next 7 days.", "?" for the four
  rule paragraphs (`:29-42`). Each overlap a PaperCard: both names, time range
  in `time` style, "Applies last: X", "Possible overlap" chip when uncertain,
  two links to priority. Bounded to 40 as today (`:48`). Then **Priority** list.
- "now & next" (`SchedulesView.swift:106`) and "This week" (`:386`) are retired:
  Today's Now card and day thread answer "now"; Calendar answers "next".

### 5.9 Every `"%@ — takes effect in %@"` call site, and where it goes
`grep -rn 'takes effect in %@' Latch` → 19 sites (checked 2026-11-02).

| # | Site | What it is | Moves to |
| --- | --- | --- | --- |
| 1 | `SettingsView.swift:950` | `BlockToggleEditor` hint | Rules §5.7 I — receipt |
| 2 | `SettingsView.swift:1165` | `PasswordOverrideEditor.delayHint` | **You spec** — receipt |
| 3 | `SettingsView.swift:1179` | shared `queueSection` (math / password override) | **You spec** — receipt; delete `queueSection` when unused |
| 4 | `WakeScheduleView.swift:120` | `GroupWakeDelayEditor` | Rules §5.7 G — receipt |
| 5 | `DelayPolicyViews.swift:103` | `DelayPolicySettingsView` | Rules §5.7 K — receipt |
| 6 | `ContactPermissionsEditor.swift:139` | contact permissions hint | **You spec** — receipt |
| 7 | `ContactPermissionsEditor.swift:217` | **live countdown of an already queued change**, not a pre-save hint | **You spec** — CountdownText, not a receipt |
| 8 | `ScheduleConflictsView.swift:112` | `SchedulePriorityEditor` | Rules §5.7 J — receipt |
| 9 | `ContactsOverrideViews.swift:724` | contacts override on/off | **You spec** — receipt |
| 10 | `ContactsOverrideViews.swift:1641` | `AddContactView` | **You spec** — receipt |
| 11 | `LimitsView.swift:480` | `WakeBlockEditor` | Rules §5.7 F — receipt |
| 12 | `LimitsView.swift:561` | `SleepBlockEditor` | Rules §5.7 F — receipt |
| 13 | `LimitsView.swift:1154` | `LimitEditorView.delayHintText` (both the save hint `:784/796` and the remove hint `:792`) | Rules §5.7 A (save) and §5.6 (remove) — receipt. Today §8 may already have wired this; the Rules build then only relays out |
| 14 | `SchedulesView.swift:936` | `ScheduleSelectionEditorView` | Rules §5.7 B2 — receipt |
| 15 | `SchedulesView.swift:1051` | `ScheduleEditorView` | Rules §5.7 B — receipt |
| 16 | `SchedulesView.swift:1156` | `ExemptionEditorView` — **no callers** | Delete the view (free periods are created in B) |
| 17 | `SchedulesView.swift:1272` | `PlannedEditorView` | Rules §5.7 C — receipt |
| 18 | `DayNightViews.swift:123` | remove-group alert | Rules §5.6 Remove group — receipt replaces the alert |
| 19 | `DayNightViews.swift:247` | `DayNightQueuedEditor.saveExplanation` | Rules §5.7 E — receipt |

Queue calls with **no** hint today that also move behind the receipt (plan D9):
`LimitsView.swift:787` remove limit; `SchedulesView.swift:472`, `:720`
remove schedule; `:658` remove planned; `:749` remove free period; `:582` end
session early; `:1408` start session (different format string, `:1389`);
`SettingsView.swift:947` toggles; `:988` remove site; `:1002` add site.
(`SettingsView.swift:766`, `:774` password policies belong to the You spec.)
When every Rules site is done, the `"%@ — takes effect in %@"` key stays only
until the You spec removes sites 2, 3, 6, 9, 10; then it is deleted from all
eight catalogs.

## 6. States

| State | What shows |
| --- | --- |
| Loading | Never blank: state is local and loaded synchronously; spent state reads `loadBlockedLimitIDs()` once per refresh (`model.tick()`), not per card |
| Empty / first use | Your waits strip, then one EmptyState card "No rules yet" with **Add a daily limit** and **Repeating block**; Always on section still shown (its switches are real); New rule pinned |
| Screen Time not authorized | Rules still list; editors show today's "App selection is unavailable until Screen Time access is allowed." on the Apps row; no Settings redirect (5.1.1(iv)) |
| Background monitoring incomplete | Slim attention card under the header (§5.1) |
| Report / usage missing | Not applicable: Rules never shows minutes used; Blocked comes from the shield store |
| Recovery needed | Rules shows saved rules read-only; New rule, Edit, Remove disabled with the existing recovery message |
| A change already pending | Pending line on the card; Edit/Remove disabled with one reason line |
| Queue returns nil (raced) | Receipt keeps itself open with "Already waiting" (today §5.10) |
| Rule removed while its sheet is open | "This rule has been removed." + Done |
| Tutorial running | Old screen anchors keep working (§8, R10) |

Stress tests:
- **Long translated copy** (German, Polish, Hindi): names wrap to two lines;
  summary line truncates; chips truncate the label, never the time; fact rows
  stack label over value at accessibility sizes.
- **One rule**: one section; other sections hidden.
- **Fifty rules** (e.g. 20 limits, 20 schedules, 10 planned): sections scroll
  in a `LazyVStack`; `RulePending.index` is one pass over `state.pending`;
  conflicts computed once per state change.
- **Smallest iPhone (SE)**: the Your waits strip and the first rule card fit
  above the pinned New rule button; chooser's six rows fit the medium detent at
  default type and scroll at larger type.
- **Largest Dynamic Type**: card chip moves under the name; DurationControl's
  − / + move below the value; DayChips wrap to two rows of 4 + 3.
- **Midnight / DST / time-zone change**: "Starts in" and "On until" come from
  pure functions with a `now` and `calendar` parameter (tested).

## 7. Components

| Need | Use (reuse first; new only with a reason) |
| --- | --- |
| Page title, cards, section headers, chips, countdowns, primary/hold buttons, day chips | Foundations components |
| Receipt for every save and remove | **ChangeReceiptSheet** (today §5.10), plus one optional extra line for sessions ("Then runs for 60 min.") |
| Ledger deep link | Changes ledger (today §5.9) with a `scrollTo: PendingChange.ID` parameter |
| App lists | Existing `SelectedAppsView`, `AppPickerSheet` |
| Duration wheels | Existing `DurationPicker`, wrapped by DurationControl |
| Wake timing | Existing `WakeTimingEditor`, `WakeCeilingPicker` (DayChips inside) |
| Validation and drafts | Existing `draftLimit`, `isValid`, `acceptsSelection`, `dayNightDraftIsValid`, `DayNightGroup.isValidCollection` — moved, not rewritten |
| **RuleCard** (new) | PaperCard + name + StateChip + summary + pending line. Needed in four sections and by Calendar; nothing existing has the pending line |
| **RuleSummarySheet** + **FactRow** (new) | Plan §6 lists it; replaces `ScheduledItemDetailView` (`SchedulesView.swift:423`) |
| **NewRuleChooser** (new) | Replaces the "New session" menu (`SchedulesView.swift:43`) and "New limit" button (`LimitsView.swift:41`) |
| **RuleEditorPage** (new scaffold) | One layout for 11 editors: sections, pinned Review change, first-problem line, discard check |
| **DurationControl** (new) | Hero value + − / +, falls back to `DurationPicker`; used by limit, per-day, session, wake wait |
| `RecurrencePicker` | Kept as logic, redrawn over DayChips and a segmented control |

Retired after the move: `LimitsView`, `LimitRow`, `SchedulesView` (page),
`OverviewItem`, `UpcomingWeekView`, `ScheduledItemDetailView`, `TypeCard`,
`ActiveBadge`, `SessionsListView`, `PlannedListView`, `RecurringListView`,
`ExemptionEditorView`, `DayNightSchedulesView` (page), `DayNightGroupSummary`,
`DayNightExplanation` (moves into help), `WakeScheduleView` (list),
`GeneralBlockingCards`, `GeneralBlockingView`, `BlockToggleEditor`,
`RulesGridView`, `DelayPolicyNavigationRows`, `EnforcementBanner`,
`BoundaryWeekdaysEditor`.

**Pure logic, with tests** (new harness `Tests/RulesPresentationHarness.py`, in
the style of the existing presentation harnesses):
- `RuleCatalog.sections(state:blockedLimitIDs:now:calendar:)` → ordered
  sections and cards incl. pending additions, legacy wake/sleep visibility,
  past planned hidden, empty sections dropped.
- `RulePending.index(_ pending: [PendingChange])` → `[RuleRef: PendingChange]`;
  an **exhaustive switch over `ChangeAction`** (no `default:`), so a new case
  fails to compile until mapped; non-rule actions (overrides, contacts,
  unlocks) map to nil. Tests: every rule action → its ref; add vs. edit vs.
  remove; day & night upsert of an existing id vs. a new id.
- `RuleChip.live(ref:state:blockedLimitIDs:now:calendar:)` → each row of the
  §5.4 table; midnight-wrapping windows; monthly recurrence; DST day; 0-minute
  limit; unblock session counts as free.
- `RulePending.label(change:now:)` → "Loosens in" / "Removed in" / "Tightens
  in" / "Added in" / "Starts in" by action and `direction`.
- `RuleSummaryLine.make(…)` → every kind; weekday range "20–60 min"; counts
  with apps/categories/sites; 12 h vs 24 h locale.
- `RuleSummaryFacts.make(…)` → which rows appear per kind; extra-time gate
  wording for wait / password / phrase / contact.
- `NextStart.after(now:)` for schedules and free periods (lifted out of the
  view code at `SchedulesView.swift:242-277`; same results).
- `EditorValidation.firstProblem(…)` for limit, repeating, planned, session —
  must agree with the existing `isValid` predicates on a table of drafts
  (same accept/reject set, plus the message).
- `DraftOverlap.notes(state:draft:)` built on `SchedulePrecedence.conflicts`.
- `WaitsSummary.text(policy:)` for the three `DelayMode`s.

## 8. Changes elsewhere

- **Tabs**: Rules replaces the Limits and Schedules tabs at the four-tab switch
  (foundations §7); until then Rules can be built behind the existing tab 1 and
  Schedules keeps working.
- **Limits tab extra-time UI** (`LimitsView.swift:157-252`) is removed; it
  lives on Today (T5). The gate sheets (`ExtraTimePasswordGate`, phrase,
  contact) stay where Today uses them.
- **General blocks** leave the Limits tab (`:108-114`) and Settings → Rules
  (`SettingsView.swift:852`); `RulesGridView` (`:828`) splits: Delays → Your
  waits, Overrides → You, General blocking → Always on.
- **Today**: day-thread items and the Now card open `RuleSummarySheet`; Block
  now opens the restyled session editor; "All rules" switches to Rules.
- **Changes ledger** gains `scrollTo:` for links from cards and sheets.
- **Copy**: every "Cancel it on the Home tab first…" becomes "…Cancel it in
  Changes…" (sites at `SchedulesView.swift:476`, `:727`, `:941`,
  `ScheduleConflictsView.swift:115`, `DelayPolicyViews.swift:98`, and the
  shared fallback message at `AppModel.swift:507`).
- **Onboarding / upgrade**: `DayNightGroupEditor` is restyled for everyone,
  including `DayNightSetupDraftView` (`DayNightViews.swift:265`); its
  store-free draft API is unchanged. Coordinate with the onboarding spec.
- **Legacy tutorial** (`TutorialStep`, `AppModel.swift:17`): steps target
  screens that go away ("limits", "limitEditor", "schedulesRoot", "recurring",
  "calendar"). `replayTutorial()` (`AppModel.swift:651`) has no UI caller in
  this tree, but a user mid-tutorial could still be in it. See R10.
- **CLAUDE.md pending UI request** (dotted separator in
  `DelayPolicyNavigationRows`): that view is retired by the Your waits strip; if
  the Delays tab ships before Rules, the fix is still needed there.
- **Localization**: new and changed strings in all eight catalogs; remove
  orphaned keys only after the You spec lands (§5.9).
- **Harnesses**: existing schedule-selection, precedence, day/night, wake and
  monitoring-budget harnesses must keep passing unchanged (no logic moves
  except the pure lifts above, which get equivalence tests).
- **Widgets, shield, report extension**: no change.

## 9. Motion and haptics
- Cards fade in (0.2 s); no springs. A card whose rule gets a pending change
  cross-fades its new pending line in after the receipt closes.
- Pending lines tick each second with tabular digits (CountdownText).
- DurationControl: light haptic per step; none on the wheel.
- Chooser: standard sheet. Editors: standard full sheet.
- Receipt: HoldButton per foundations; success haptic on queue (replaces the
  blind haptic in `AppModel.swift:468`).
- Reduce Motion: no fades; HoldButton → one confirmation (foundations §9).

## 10. Copy (draft; refine and translate into all eight languages)
- "Rules" / "Your waits" / "Stricter: %@ · Looser: %@" / "Every change: %@" /
  "right away"
- Sections: "Limits" / "Schedules" / "Day & night" / "Planned" / "Always on"
- Chips: "Blocked" / "On until %@" / "Free until %@" / "Opens %@" / "Starts in
  %@" / "On" / "Off"
- Pending: "Loosens in" / "Tightens in" / "Removed in" / "Added in" /
  "Starts in" / "See in Changes"
- Summary: "%d min a day" / "%d–%d min a day" / "Blocked all day" / "only %d
  apps" / "all except %d apps" / "free period" / "Wake %@ + %@ · Sleep %@" /
  "Any app" / "Apple's filter" / "%d sites"
- Chooser: "New rule" / "Daily limit" — "A daily time budget for some apps" /
  "Block now" — "Block apps for a set time, starting soon" / "Repeating block"
  — "Every day, some days, or monthly — or a free period" / "Plan a block" —
  "One time: a trip, an exam, a weekend" / "Day & night" — "A wake-up wait and a
  sleep time" / "Website" — "Block a site by its address" / "You can have up to
  five day & night groups." / "Wait for the day & night change that's already
  waiting."
- Sheet: "When" / "Days" / "What" / "How much" / "Split" / "Extra time" /
  "Wake-up" / "%d uses · %d left today" / "Get extra time on Today" / "Edit" /
  "Edit apps" / "Edit list" / "Remove limit" / "Remove block" / "Remove free
  period" / "Remove" / "End early" / "Turn on" / "Turn off" / "To change it,
  remove it and add a new one." / "A change is already waiting. Cancel it in
  Changes to make a different one." / "This rule has been removed."
- Editors: "Review change" / "Discard your changes?" / "Discard" / "Keep
  editing" / "Different limit per day" / "Same every day" / "Split the day" /
  "Changing apps always counts as a looser change." / "Then runs for %d min." /
  "Ends next day" / "Overlaps with %@ on %@." / "Ask me to tap Wake up" / "Days
  apply to the morning you wake and the evening sleep starts." / "Different
  times per day" / "Choose at least one app." / "Recheck blocked limits"
- Attention: "iOS can't watch all your rules in the background. Removing a few
  restores full blocking."

## 11. Out of scope
- New change kinds (editing times of recurring blocks, editing planned windows,
  renaming limits). They would be behaviour changes; R5 asks whether to spec one
  later.
- The You tab's overrides, contacts and passwords (call sites 2, 3, 6, 7, 9, 10).
- Today, Changes ledger and receipt internals (approved separately).
- Fixing `PlannedEditorView`'s selection count / validity ignoring website
  tokens (`SchedulesView.swift:1248`, `:1310`) — a behaviour question noted for
  a follow-up, not part of a visual rebuild.
- iPad multi-column, widgets, shield copy, the tutorial's own redesign.

## 12. Decisions for the owner

| # | Decision | Why |
| --- | --- | --- |
| R1 | One Rules tab with five sections (Limits, Schedules, Day & night, Planned, Always on); Calendar and Conflicts as header icons; the Day & night, Sessions, Planned and Recurring list pages go away | Every rule in one place, one level deep; ends the three-tab split |
| R2 | New rule is the pinned primary button; the chooser lists six types with a one-line meaning, Repeating block above Plan a block | One action per screen in the thumb zone; recurring rules are more common than one-offs |
| R3 | A card shows **two** separate facts: live state chip (Blocked / On until / Free until / Starts in) **and**, when present, a pending line (Loosens in / Removed in / Tightens in) | "Blocked" and "loosens in 3h" are both true and both matter; one chip would hide one of them. Alternative: one chip with pending winning |
| R4 | The summary sheet only links to the ledger for a pending change ("See in Changes"); cancelling stays in Changes | Plan: the ledger is the only full list; one place to cancel |
| R5 | Keep today's edit powers: recurring blocks edit apps only; planned and free periods can only be removed ("remove it and add a new one") | Editing times would be a new delayed mutation (behaviour change). Ask: spec an `updateSchedule` change later? |
| R6 | Remove leaves the editors and lives on the summary sheet, always via the receipt with Hold to confirm | One place to remove; removals are looser and get friction |
| R7 | The per-limit wake-up ("Group wake-up") is shown only on limits that already use it; new users get wake-ups through Day & night | Two wake systems confuse; existing settings stay reachable and editable |
| R8 | Advanced limit options (per-day budgets, split day, extra time) become plain rows that open a sub-page; no disclosure groups | Plan §5.4; the main page stays short, nothing is hidden behind "On/Off" arrows |
| R9 | "Recheck blocked limits" moves to the Limits section footer and appears only when a limit is Blocked | It's a repair action for a blocked state; no permanent card |
| R10 | Legacy tutorial: keep its steps working on the old screens until the four-tab switch, then retire it (no UI calls `replayTutorial()` today); new help lives in You | Avoid rebuilding anchors for a flow nobody can start; needs the onboarding spec's agreement |
| R11 | The day & night editor is restyled for onboarding too (same component, same draft-only API) | One editor, one look; onboarding saves drafts, not receipts |
| R12 | Editors show the first problem in one line above a disabled Review change, and no delay text; the delay appears only on the receipt | Foundations §4: one place explains the wait; fewer footnotes |

## Owner's answers (2026-11-02)
Approved as written, with the main session's recommendations:
- Planned blocks and free periods keep today's edit powers (R5); an
  `updateSchedule` change for editing times is a possible later spec.
- The legacy interactive tutorial is retired when the four tabs ship (R10, with
  You Y10 and onboarding Q1); its dormant code is deleted then.
- Receipts follow the engine's direction: removals the engine classes as
  stricter (e.g. removing a contact) get a plain Confirm, not Hold to confirm.
