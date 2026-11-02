# Insights — redesign (proposal, 2026-11-02)

Status: **approved by the owner, 2026-11-02.**

Builds on `docs/redesign-ux-plan.md` (approved: §5.6, decision D7),
`docs/foundations-redesign.md` (tokens and components, approved) and
`docs/today-redesign.md` (approved). Covers the **Insights** tab: the host
chrome around the usage report, the report itself (Day, Week, Trends), the
merged **About this data** sheet and the **Starting point**. No new data and
no new report scene: it is the same `UsageInsightsReport` extension, restyled
and reorganised. Privacy rules in `CLAUDE.md` ("Privacy and usage reports")
are unchanged and constrain every block below.

## 0. Owner's call
- "We need a full redesign" and the app should be thorough on stats. Plan
  job J8 ("Am I using my phone less?"), decision D7 (Insights gets its own
  tab), one "About this data" sheet, starting estimate only here, one refresh
  control, and the report restyled with the foundations palette.

## 1. Diagnosis (ranked by user impact)

1. **The one question people bring here is never answered on the first
   screen.** "Am I using my phone less?" needs the comparison with the week
   before, but the dashboard only shows a total and a coverage caption
   (`LatchReport/UsageInsightsView.swift:142-166`). It computes the
   comparison (`:72-78`) and then uses it only for a footnote inside the
   collapsed details (`:400`). The answer sits one tap away in Trends, where
   it leads with a bare percentage (`LatchReport/UsageTrendsView.swift:88-99`)
   and change in raw minutes ("+190 min", `:366`).
2. **Insights is hard to find and is built as a pushed page.** It is a link
   under Home's usage card (`Latch/HomeView.swift:178-189`). Its refresh only
   works while Home is the selected tab (`Latch/UsageInsightsView.swift:66`,
   `model.selectedTab == 0`), so moving it to its own tab without changing
   that guard would leave a tab that never refreshes. Trends is a fake push
   inside the report with its own "Back to usage" button
   (`UsageTrendsView.swift:69-72`). The report can't drive host navigation,
   so two different back affordances end up stacked.
3. **The same explanations repeat everywhere, in technical language.**
   "Full/Partial reported coverage" is printed under the hero, every partial
   app row and every bar's VoiceOver value (`UsageInsightsView.swift:152-154`,
   `:337-339`, `:374`). There are two different "Usage details": a host sheet
   (`Latch/UsageInsightsView.swift:131-149`) and a report disclosure
   (`LatchReport/UsageInsightsView.swift:385-405`). Trends says "Today is
   excluded from trends" twice (`UsageTrendsView.swift:114`, `:340`) and the
   missing-data disclaimer twice (`:185`, `:339`).
4. **The starting estimate is in three places, plus a permanent button.** It
   appears in the host details sheet (`Latch/UsageInsightsView.swift:138-144`),
   the Trends card (`UsageTrendsView.swift:303-315`) and a capsule pinned
   under the report on every visit (`Latch/UsageInsightsView.swift:106-117`),
   though most people set it once or never. Onboarding and Guide copy point
   at "Home → Usage & trends" (`Latch/UsageInsightsView.swift:44`,
   `Latch/SettingsView.swift:341-342`).
5. **There are three refresh controls for two reports.** Home's card arrow
   (`Latch/LimitsUsageReportView.swift:103-110`), Home pull-to-refresh
   (`Latch/HomeView.swift:457`) and the Usage & trends toolbar
   (`Latch/UsageInsightsView.swift:126-128`).
6. **The hierarchy is flat and the palette is out of date.** Every heading
   is `subheadline.semibold` (`UsageInsightsView.swift:406`,
   `UsageTrendsView.swift:359`). There are no surfaces, so eight Trends
   sections all carry the same weight (`UsageTrendsView.swift:48-57`). The
   report hard-codes the old colours (`UsageInsightsView.swift:51-59`;
   `muted` is lighter than the foundations `inkSoft`, and there is no `card`).
   It also still uses a 9-pt monospaced scale label (`:236`), a style
   foundations retires.

## 2. Intent
In two seconds the user should know **how much they used their phone in the
period they're looking at, and whether that's more or less than before**.
The one action is to **switch the view** (Day · Week · Trends). Everything
else, such as picking a bar, an app or a week, refines that view.

## 3. What we took from Mobbin
Three searches (budget 5, kept low because the owner's Mobbin usage is high).

| App | What we take | Screen |
| --- | --- | --- |
| Forest | Day/Week segmented control on top, date range with ‹ › pager above the chart, chart in its own card, Most used directly below | [screen](https://mobbin.com/screens/275c3559-e666-4d63-b6f2-f55c26e19654) |
| Jomo | Most used rows: icon + name left, time right, thin proportional bar under the name | [screen](https://mobbin.com/screens/7af61157-8994-4849-bfe0-43a98ced0dca) |
| YouTube | Under the chart, short plain rows ("Today", "Last 7 days") and one sentence about where the data comes from, with "Learn more" → our About this data | [screen](https://mobbin.com/screens/ccc65abb-f486-47ec-953e-2c6da12d1eee) |
| Pillow | Trends as stacked cards, each opening with **one summary sentence** ("This week's average is 5 h 9 min") above a small chart | [screen](https://mobbin.com/screens/89e346e5-4094-4f03-8feb-67cc34a555e9) |
| WHOOP | "Weekly Trends" page: one card per metric, the selected day's column highlighted | [screen](https://mobbin.com/screens/c21e12b1-e57d-427e-bc1d-2f3afd510edc) |
| Bevel | Trends table where a period without data shows a **dash, not zero**; explanation text under it; "Last data point on…" date | [table](https://mobbin.com/screens/b360074e-6c34-4e6b-8d63-691bbc2354d6), [sheet](https://mobbin.com/screens/8e5b6b0d-c29f-42b4-a1c6-1c89c747b6fb) |
| Bevel | Trend cards: one big value, then a single short status line | [screen](https://mobbin.com/screens/4398dbfe-241b-4880-b6ef-9eafaab69861) |
| Gentler Streak | "This week vs last week": the previous value printed small under the current one, with a direction arrow | [screen](https://mobbin.com/screens/81ddb60b-a773-448c-b64a-92cef5221268) |
| Noom | Serif section titles, each followed by one plain number sentence ("1396 average daily calories") | [screen](https://mobbin.com/screens/bc828129-6dd9-43ee-8ed6-5105f6193034) |
| Opal | Highs and lows as a sentence ("Your most … day was Friday with …"). We take the sentence form, **not** the moral words ("productive"/"distracting") or the red/green | [screen](https://mobbin.com/screens/ea59c327-1787-47dc-b850-15708c5e337d) |

We take structure and use of colour, not looks: warm paper, ink, one accent,
serif for numbers and times (foundations §5).

## 4. The rule that removes the repetition
| Question | Lives in (once) | Not repeated in |
| --- | --- | --- |
| How much did I use today / that day? | Day → hero card | Today tab shows per-limit usage only |
| Am I using it less than the week before? | Week → hero card, comparison line | Trends repeats it only as the detailed "Compared with the week before" card, with this/previous figures |
| Which apps take my time? | Day/Week → Most used apps | Trends shows only *changes* per app |
| How does a single app look over time? | Tap an app → the whole Insights view scopes to it | — |
| Which weekdays are heavy? Highs and lows? | Trends | — |
| How complete is the data (counts, calendar)? | Trends → "How complete this is" | Elsewhere only a quiet "Partly reported" tag on the affected item |
| Why might data be missing? What counts? | About this data sheet (host, static text) | Every in-report disclaimer except one footnote per card |
| What was my starting estimate, and how does it compare? | Trends → Starting point card (report) | Host details sheet (removed) |
| How do I add or change the estimate? | About this data → "Your starting point" row (host) | Bottom capsule (removed); onboarding keeps its own entry |
| Refresh | Insights header button | Report text only *names* it ("Tap Refresh at the top") |

## 5. Layout, top to bottom

Ownership is fixed by the platform: the **host** draws only the header, the
sheets and the background. Everything with a measured number is drawn by the
**report** in its own process, and the report also owns the vertical scroll
(no nested host scroll, no height or readiness signal;
`Latch/UsageInsightsView.swift:100-104`).

```
┌──────────────────────────────────────┐
│ Insights                    ⟳   ⓘ    │ ← host header (fixed)
├──────────────────────────────────────┤
│  ( Day │ Week │ Trends )             │ ← report from here down
│ ┌──────────────────────────────────┐ │
│ │ Last 7 full days · 26 Oct – 1 Nov│ │
│ │ 21 h 40 min                      │ │ ← timeLarge
│ │ 3 h 6 min a day                  │ │
│ │ ↓ 2 h 10 min less than the week  │ │
│ │   before (−9%)                   │ │
│ └──────────────────────────────────┘ │
│ ┌ Four weeks ──────────────────────┐ │
│ │  ▇    ▆    ▇    ▅                │ │
│ │ 5 Oct 12 Oct 19 Oct 26 Oct       │ │
│ └──────────────────────────────────┘ │
│ MOST USED APPS                       │
│ ┌──────────────────────────────────┐ │
│ │ ◻ Safari              6 h 2 min  │ │
│ │ ▬▬▬▬▬▬▬▬▬▬▬                      │ │
│ │ ◻ Messages            3 h 15 min │ │
│ │ … (5)            See all 14 apps │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

### 5.1 Host header (`Latch/UsageInsightsView.swift`)
- Purpose: name the tab and hold the two host-only controls.
- Content: `DemoraPageTitle("Insights")` left. On the right, two 44-pt icon
  buttons in `inkSoft`: **Refresh** (`arrow.clockwise`) and **About this
  data** (`info.circle`). No wordmark (foundations: wordmark is Today only).
- Tokens: `pageTitle`, page gutter 20, background `paper`, hairline under the
  header only once the report is present (static; the host can't see report
  scroll).
- It's a fixed row, not a large navigation title: the scroll view belongs to
  the report process, so a large title would never collapse and would cost
  about 96 pt for good.
- Behaviour: Refresh sets `refreshedAt = Date()` through the existing
  `refresh()` (keep its name and body; `Tests/UsageNavigationHarness.py:37-38`
  parses it). It goes through the same coalescing as Home: one request at a
  time, at least two seconds apart, one soft retry after three seconds
  (`HomeReportRefreshPolicy`). The header also refreshes automatically when
  the tab becomes visible, on foreground, and on appearance/accent/language
  change (existing `onChange` hooks, `:152-157`).
- Visibility guard: `canRefresh` must check "Insights is the visible tab"
  through the tab identity that exists after the four-tab switch, not
  `selectedTab == 0`. Retained hidden tabs don't get `onDisappear`, so the
  tab check is the guard that matters. Until the switch, Insights is still
  pushed from Today and keeps the current guard.

### 5.2 Host background placeholder (new, no handshake)
- Behind the `DeviceActivityReport` (a `ZStack` underneath it), the host
  draws a quiet centred line in `meta`/`inkSoft`: "Loading your usage… If
  this stays empty, tap Refresh."
- The report paints an opaque `paper` background
  (`LatchReport/UsageInsightsView.swift:92`), so once iOS renders it the
  placeholder is covered. Nothing is signalled back to the host.
- Device check needed: confirm the report view is transparent before its
  first render. If it isn't, drop this block (decision I9).

### 5.3 View switch (report)
- A capsule segmented control with three parts: **Day · Week · Trends**.
  It replaces the two-part Daily/Weekly control (`UsageInsightsView.swift:121-140`)
  and the "Explore trends" card (`:267-279`). Trends becomes the third
  segment, so the in-report "Back to usage" button goes away.
- Tokens: track `tint(accent)`, selected pill `accent` with `card`-coloured
  text, `chip`-weight label at `meta` size, 44 pt tall (64 at accessibility
  sizes), max width 360, centred. At accessibility sizes it spans the full
  width.
- State carried across segments: the selected app scope, the selected week
  (Week ↔ Trends share it, as `selectedPeriod` does today, `:87`), and the
  day pager page.
- Directly under it, when an app is selected: a **scope row**: the private
  Apple label (`cardTitle`) and a quiet **All apps** capsule (existing
  `applicationScope`, `:243-252`).

### 5.4 Day segment
1. **Hero card** (`paperCard`, 20 padding):
   - `label`: the selected day ("TODAY SO FAR", or "MONDAY 26 OCTOBER").
   - Total in `timeLarge` (`accent`), monospaced digits, one line, scales
     down to 0.5. Missing → "No data yet" in `hero`/`inkSoft`.
   - One `meta` line, shown only when last week is fully reported: "Your
     daily average last week: 3 h 6 min". It uses the existing
     `UsageDashboardPresentation.average(usage.lastSevenDays)`; nothing new
     is invented. It's hidden otherwise.
   - If that day is partly reported: a neutral StateChip "Partly reported"
     (today: no chip; the label already says "so far").
2. **Chart card** (`paperCard`):
   - Header row: date range in `meta` ("27 Oct – 2 Nov") between ‹ › pager
     buttons (44 pt, `inkSoft`, disabled at the ends; existing `page`,
     `:174-177`).
   - Seven bars (existing `bar`, `:346-376`), restyled. Selected bar is
     `accent`. Others are `accent` at 34 %, partial ones at 18 % with the
     existing paper notch, so partial is never shown by colour alone. A
     reported zero is a hollow dot and missing data is a dashed outline,
     both kept. Weekday label under each bar in `chip`, selected in
     `accent`.
   - Scale: the top hairline carries the max value in `chip`/`inkSoft`
     (replaces the 9-pt monospaced label, `:236`).
   - No footnote. "Tap a bar…" hints go; the selected bar and VoiceOver
     traits do that job.
3. **Most used apps** (§5.6) for the selected day.

### 5.5 Week segment
Weeks are the existing **rolling seven-day periods ending yesterday**
(`LatchReport/UsageInsightsModel.swift:180-185`), not calendar weeks, so they
are always named by date range. The latest is "Last 7 full days", the one
before it is "The week before", and older ones are labelled by their dates.
Never "This week".

1. **Hero card**:
   - `label`: "LAST 7 FULL DAYS · 26 OCT – 1 NOV" (or that period's range).
   - Total in `timeLarge`. Under it in `meta`: "3 h 6 min a day" (only
     when the period is complete; existing `average`).
   - **Comparison line** (`body`, `ink`), only when
     `UsageInsightsTrend.compare` returns a value for this period and the
     one before it (`UsageDashboardPresentation.preceding`):
     "↓ 2 h 10 min less than the week before (−9%)", "↑ … more …", or
     "About the same as the week before" (within one minute). The arrow is
     an SF Symbol hidden from VoiceOver. The colour stays neutral (`ink`),
     with no green for less or brick for more (decision I2). The percentage
     is omitted when the previous period was zero.
   - Otherwise, one `meta` line: "No comparison yet: both weeks need full
     data." For the oldest week: "No earlier week to compare."
2. **Four weeks card**: four tappable bars (existing weekly branch of
   `chart`, `:213-220`) with the total above each in `chip`. Tapping one
   selects that period for the hero, Most used apps and Trends.
3. **Most used apps** (§5.6) for the selected period.

### 5.6 Most used apps (Day and Week, all-apps scope only)
- `SectionHeader("Most used apps")`. The card holds the top five ranked by
  the existing `UsageDashboardPresentation.rankedApplications` (`:280-283`).
  Each row has the private label (`body`) on the left, the time in `time`
  style at `meta` size (`accent`) on the right, and a 4-pt capsule bar under
  it (`accent` 45 %, selected 100 %). Rows are at least 44 pt (64 at
  accessibility sizes). A partly reported row gets a "Partly reported"
  `chip` under the bar.
- **See all 14 apps** / **Show fewer** in `accent` expands in place, as today
  (`:300-305`). The count is the number of ranked apps; unknown apps are
  never counted as zero.
- Tapping a row scopes **all three segments** to that app (existing
  `selectApplication`), and the view scrolls to the top (existing,
  `:113-117`). Under an app scope this section is hidden, since it would
  list only that app.
- One footnote in `meta`/`inkSoft`: "App times overlap, so they won't add up
  to your total." It replaces the two separate notes (`:306-310`).
- Empty: "No app times reported for this day." / "…for these 7 days."

### 5.7 Trends segment
Today never counts here; that is said once, in the first card's footnote.
Every card is a `paperCard` with a `SectionHeader`, a **summary sentence**
in `body` (the Pillow/Noom pattern) and then its chart or figures. One
footnote per card at most. Order follows the question people bring:

1. **Week picker**: the Four weeks card from §5.5, shared, so Trends always
   says which period it describes.
2. **Compared with the week before**: summary sentence as in §5.5. Two
   figures side by side (`time`): "Last 7 full days 21 h 40 min" and "The
   week before 23 h 50 min" (the Gentler Streak pattern; they stack at large
   sizes, using the existing `ViewThatFits`). Then "Daily average: 3 h 6 min
   (↓ 19 min)". When there is no trend: "No trend yet" (`hero`) and "A trend
   needs two weeks with full data." Footnote: "Today isn't included in
   trends."
3. **Day by day**: sentence "Each day next to the same day the week before."
   Paired bars (existing `dailyComparison`, `:166-187`), with the legend
   dots "Last 7 full days" / "The week before". Tapping a day shows both
   figures beneath.
4. **Highs and lows**: sentence form (the Opal pattern without the judging
   words). "Your heaviest day was **Thursday**: 4 h 50 min." and "Your
   lightest day was **Sunday**: 1 h 40 min." Only fully reported days count
   (existing `UsageTrendsModel.extremes`). Footnote only if the week is
   partial: "Only fully reported days count."
5. **Weekday patterns**: sentence naming the heaviest weekday when at least
   one weekday has 2+ samples, then seven rows (weekday, average, "3 days" in
   `chip`, 4-pt bar; existing `weekdayPatterns`, `:230-256`). Footnote:
   "Averages use only days with full data." The date-range caption uses the
   report calendar instead of a force-unwrap (`:236`).
6. **Biggest app changes** (all-apps scope): up to five rows with label,
   "↓ 1 h 5 min" (`accent`) and "3 h 10 min → 2 h 5 min" in `meta`; tap to
   scope (existing `appChanges`, `:281-302`). One footnote combines the two
   current ones: "Only apps with full data in both weeks. App changes don't
   add up to your overall change."
7. **Your starting point** (all-apps scope, only if an estimate exists;
   existing `baselineComparison`, `:303-315`), using `tint(accent)` card
   fill like the receipt:
   - "You estimated **21 h a week** before using Demora." (`body`), recorded
     date in `meta`.
   - If the selected period is complete: "Last 7 full days: 2 h 40 min
     less than your estimate." Otherwise: "Needs a week with full data to
     compare."
   - Always: "This is your own estimate, not measured Screen Time. It
     doesn't measure time saved by Demora."
   - No estimate: a single quiet line instead of the card: "Want a starting
     point? Add an estimate in About this data (ⓘ at the top)."
8. **How complete this is** (was "Report coverage", `:316-342`): sentence
   "24 of 28 days have full data." The calendar of dots stays, with filled
   = full, ring = partly reported and dashed = no data, plus the three
   counts. Footnote: "Missing days aren't counted as zero." This card takes
   over the measured counts from the old report disclosure (`:394-402`).

### 5.8 About this data (host sheet, merges both "Usage details")
System sheet, medium and large detents, `cardRaised`, title "About this
data", **Done**. Static text only; no measured numbers (those stay in Trends
§5.7.8). Sections use `SectionHeader` + `body`:

- **What you see**: "Your Screen Time from the last 28 days plus today, as
  iOS reports it. Today is shown on its own and never counts in weekly
  comparisons."
- **Missing isn't zero**: "iOS sometimes reports late or only part of a day.
  Days without data are marked, never counted as zero. If Insights looks
  empty, tap Refresh."
- **Apps and totals**: "App times overlap, so they won't add up to your
  total screen time."
- **Other devices**: "If Screen Time is shared over iCloud, other devices of
  the same kind may be included."
- **Private by design**: "Your usage stays inside Apple's Screen Time report.
  Demora can't read, save or send it."
- **Your starting point** row (`cardTitle` + trailing **Add** or **Edit**
  in `accent`, 48 pt) → pushes the existing "Your starting point" editor
  (`WeeklyUsageEstimateDraft` + Save/Cancel, `Latch/UsageInsightsView.swift:158-181`)
  inside the sheet's navigation stack. Its behaviour (save, verify, remove,
  "Couldn't save") is unchanged. The row shows no value; the value is shown
  once, in Trends.

### 5.9 iPad
Report content max width 640 (foundations §5.3; today 740, `:108`). Same
single column; larger cards breathe, no multi-column (foundations out of
scope).

## 6. States
| State | What shows |
| --- | --- |
| Loading (report not drawn yet) | Host placeholder §5.2 under the report; nothing else |
| Empty / first use (no data at all) | Day hero card: "No data yet" (`hero`) + "iOS hasn't reported any usage for this period. That doesn't mean zero use." Chart, apps and Trends cards still render with dashed bars and "—" so the layout is learnable; Trends cards show their "No trend yet" sentences |
| Only today so far (new install) | Day shows today; Week hero "No full week yet"; Trends shows "No trend yet" and the coverage calendar |
| Partly reported period | Values shown, "Partly reported" chip; no averages, comparisons or app changes for that period |
| App scope, app disappeared after refresh | Existing: label kept, values "No data yet", never silently switched to all apps |
| No estimate | Starting point card replaced by the one-line hint (§5.7.7) |
| Screen Time not authorised | Host shows an EmptyState card instead of the report: "Insights needs Screen Time access." + "You can turn it on from Today." with **Go to Today** (host tab switch). No prompt, no Settings redirect (Apple 5.1.1(iv)). Today owns the permission banner (plan §6) |
| Error / offline | Not applicable: no network. Unreadable preferences fall back to system appearance, blue accent and device language (existing) |

Stress tests:
- **Longer copy** (German, Hindi, Polish): the segment labels are short words
  (Tag/Woche/Trends). Summary sentences wrap, and chips truncate the label,
  never the number.
- **One app vs fifty**: top five then See all; LazyVStack expands in place.
  Fifty rows scroll inside the report's own scroll.
- **Smallest iPhone (SE, 320 pt content)**: the header, segment control and
  hero total fit the first screen. Charts scroll horizontally with 44-pt
  targets (existing).
- **Largest Dynamic Type**: bars use 64-pt targets (existing), figures
  stack, and the segment control goes full width. The hero total scales down
  but stays on one line.
- **Reduce Motion / VoiceOver**: covered in §9 and §7.

## 7. Components
| Need | Use (reuse first; new only with a reason) |
| --- | --- |
| Host page title, header buttons | `DemoraPageTitle`, standard 44-pt icon buttons |
| About this data | System sheet + `SectionHeader`; existing estimate editor pushed inside |
| Not authorised | `EmptyStateView` (foundations restyle) |
| Report colours, type, card | **New `LatchReport/ReportTheme.swift`**: the report can't import `Shared` or `Theme.swift`, so it gets a copy of the foundations §5.1 tokens (`paper`, `card`, `ink`, `inkSoft`, `hairline`, `accent` blue/red, `loosen`, `free`, `tint`), the §5.2 type styles as `Font` helpers, a `reportCard()` modifier (card fill, 20 radius, hairline, 16 padding) and `ReportSectionHeader`. It also takes over the appearance/accent/locale preference reads now inline at `UsageInsightsView.swift:36-59`. Shared with `LimitsUsageView` (Today spec §5.5); whichever build lands first creates it |
| Chips in the report | Report-local `ReportChip` mirroring `StateChip` (neutral kind only here) |
| Bars, paired bars, coverage dots | Existing `bar`, `stem`, coverage grid, restyled with theme tokens |
| App labels and identity | Existing `applicationLabel` / `applicationIdentity` closures; label-only identity reset unchanged |
| Duration text | **New Foundation-only `UsageFormat`** (in `LatchReport/`): `duration`, `signedDuration` (h + min, "−2 h 10 min"), `percent`. It replaces the duplicated private helpers (`UsageInsightsView.swift:411-431`, `UsageTrendsView.swift:360-381`) so both pages read the same |
| Comparison sentence | **New pure `UsageComparisonText.make(trend:)`** → direction (less/more/same) + magnitude + optional percent |

Pure logic, with tests (extend the existing harnesses; no live usage, no
App Group reads):
- `Tests/UsageDashboardHarness.py`: `UsageFormat` (0, 59 s, 59/60/61 min,
  23 h 59 min, negative signed values, nil/NaN/negative → "No data yet",
  locale digits), the segment state carry-over (app scope and selected week
  survive Day ↔ Week ↔ Trends), Day hero "daily average last week" shown
  only for a complete `lastSevenDays`, and a token-parity check that
  `ReportTheme.swift` values equal `Theme.swift` §5.1 values (light/dark,
  both accents). Update the source guards at `:75-76` (`showingUsageInfo`
  becomes the About sheet flag; still no `reportHeight`).
- `Tests/UsageTrendsHarness.py`: `UsageComparisonText.make` (less, more,
  same within one minute, previous zero → no percent, nil trend → no
  sentence), "heaviest weekday" sentence only with ≥ 2 samples, ties choose
  the first calendar weekday, weekday caption without force-unwrap.
- `Tests/UsageInsightsHarness.py`: one `baselineDifference(for:)` used by
  both Trends and the model (replaces the `lastSevenDays`-only
  `baselineDifferenceMinutes`, `UsageInsightsModel.swift:77-83`): nil for a
  partial period and for an app scope, correct sign, never shown as savings.
- `Tests/ApplicationUsageHarness.py`: "See all N apps" count equals the
  ranked list (unknown apps excluded), and the hidden Most used section
  under app scope.
- `Tests/UsageLocalizationHarness.py` and `GenerateUsageLocalization.py
  --check`: every new/renamed report key exists in all eight languages.
  `report_keys()` must also scan `UsageFormat`/`UsageComparisonText` if
  they call `insightsText`.
- `Tests/UsageNavigationHarness.py`: `refresh()` still follows `Date()`
  (backwards clock) and still does nothing while hidden. The estimate editor
  is reachable only from About this data. No bottom estimate button remains.

## 8. Changes elsewhere
- **Today / Home**: the "Usage & trends" link (`Latch/HomeView.swift:178-189`)
  goes when the Insights tab exists (already in Today spec §8). **Proposal
  for the Today build:** drop the usage card's refresh arrow
  (`LimitsUsageReportView.swift:103-110`) and keep pull-to-refresh
  (`HomeView.swift:457`) as Today's only refresh. Then each report surface
  has exactly one manual refresh. The Today spec is approved and doesn't
  cover this, so it needs the owner's yes (I6).
- **Tab bar** (foundations §7): Insights = `chart.bar`. When the four-tab
  switch lands, `canRefresh` uses the Insights tab identity (§5.1).
- **Onboarding** keeps its estimate entry (`OnboardingView.swift:355`,
  `RedesignWelcomeView.swift:276`). Only the shared copy changes:
  "…change it later in Home → Usage & trends" → "…change it later in
  Insights → About this data" (`Latch/UsageInsightsView.swift:44`), in all
  eight catalogs.
- **Guide** (`Latch/SettingsView.swift:338-342`): rename the entry to
  "Insights" and update both paths (Usage reports, Weekly baseline). Guide
  moves to You in that spec; the copy change happens here.
- **Report extension**: `LatchReport/UsageInsightsView.swift` and
  `UsageTrendsView.swift` restyled; Trends is rendered as a segment, not a
  page switch with `onBack`. `LimitsUsageView.swift` adopts `ReportTheme`
  in the Today build. `LatchReportExtension.swift` is unchanged.
- **Translations**: new/changed strings go into `Shared/Localization*.swift`
  (host and Guide) and the report snapshot is regenerated with
  `python3 Tests/GenerateUsageLocalization.py --patch` applied through a
  patch tool, never hand-edited.
- **Synthetic previews** (`Tests/UsageDashboardPreview.swift`): add the
  three segments, app scope, no-estimate and partial fixtures.
- **README / IOS_REDESIGN_STATUS.md**: record the new structure after build.

## 9. Motion and haptics
- Segment change: 0.2 s cross-fade of the content below the control; the
  pill slides 0.18 s ease-in-out (existing timing). No springs.
- Selecting a bar, week or app: the selection colour changes immediately,
  and the chart scrolls the selection into view (existing).
- Scoping to an app scrolls to top (existing).
- No haptics inside the report: it runs in Apple's remote process, and
  feedback generators there are unverified. The host Refresh button gives a
  light haptic.
- Reduce Motion: every animation is `nil` (existing checks at
  `UsageInsightsView.swift:114`, `:132`; `UsageTrendsView.swift:143`).
  Segment and selection changes are instant.
- VoiceOver order: segment control → scope → hero (combined element:
  label, total, average, comparison) → chart (each bar: date, value, "partly
  reported" only when it applies) → cards in order. Headers carry
  `.isHeader`. Selected items carry `.isSelected`.

## 10. Copy (English drafts; translate into all eight languages)
Host:
- "Insights" / "Refresh" / "About this data" / "Done"
- "Loading your usage… If this stays empty, tap Refresh."
- "Insights needs Screen Time access." / "You can turn it on from Today." /
  "Go to Today"
- About sheet: "What you see" / "Missing isn't zero" / "Apps and totals" /
  "Other devices" / "Private by design" / "Your starting point" / "Add" /
  "Edit" (body text as in §5.8)
- Estimate draft footnote: "This is your estimate, not a measurement or a
  limit. It stays on your device. You can skip it or change it later in
  Insights → About this data."

Report:
- "Day" / "Week" / "Trends" / "All apps"
- "Today so far" / "Last 7 full days" / "The week before"
- "Your daily average last week: %@" / "%@ a day"
- "%@ less than the week before" / "%@ more than the week before" /
  "About the same as the week before" / "(%@%%)"
- "No comparison yet: both weeks need full data." / "No earlier week to
  compare." / "No full week yet"
- "Partly reported" / "No data yet" / "iOS hasn't reported any usage for
  this period. That doesn't mean zero use."
- "Most used apps" / "See all %d apps" / "Show fewer" / "App times overlap,
  so they won't add up to your total." / "No app times reported for this
  day." / "No app times reported for these 7 days."
- "Four weeks" / "Compared with the week before" / "No trend yet" / "A trend
  needs two weeks with full data." / "Today isn't included in trends." /
  "Daily average: %@"
- "Day by day" / "Each day next to the same day the week before."
- "Highs and lows" / "Your heaviest day was %@: %@." / "Your lightest day
  was %@: %@." / "Only fully reported days count."
- "Weekday patterns" / "%@ tends to be your heaviest day." / "%d days" /
  "Averages use only days with full data."
- "Biggest app changes" / "No comparable app changes yet." / "Only apps with
  full data in both weeks. App changes don't add up to your overall change."
- "Your starting point" / "You estimated %@ a week before using Demora." /
  "Recorded %@" / "%@: %@ less than your estimate." / "%@: %@ more than your
  estimate." / "Needs a week with full data to compare." / "This is your own
  estimate, not measured Screen Time. It doesn't measure time saved by
  Demora." / "Want a starting point? Add an estimate in About this data (ⓘ
  at the top)."
- "How complete this is" / "%d of %d days have full data." / "Full data" /
  "Partly reported" / "No data" / "Missing days aren't counted as zero."

Retired keys (remove from the catalogs after build): "Usage details",
"Explore trends", "Back to usage", "Your time, in perspective.", "Tap a bar
to see that day/week.", "Tap an app to see its daily and weekly usage.",
"28 completed days plus today", "Edit weekly estimate", "Full reported
coverage" (replaced by marking only the partial case).

## 11. Out of scope
- New measurements: pickups, notifications, first pickup and categories.
  Apple's report data has them, but each needs its own accumulator,
  revision and coverage rules and privacy review (a separate spec if the
  owner wants them).
- Longer history (months, 90 days). iOS gives about 28 days plus today, and
  persisting measured usage to extend it is forbidden.
- Calendar-week (Mon–Sun) periods: the model stays rolling (I10).
- Goals, streaks, "time saved", sharing/export, widgets or notifications
  showing usage (all blocked by the privacy rules or the "never proof of
  savings" rule).
- The Today usage card's restyle (Today spec), the tab-bar switch
  (foundations §7) and the You tab.

## 12. Decisions for the owner
| # | Decision | Why |
| --- | --- | --- |
| I1 | One control, **Day · Week · Trends**; Trends stops being a pushed page with its own "Back to usage" | One obvious way to switch. It also removes a fake back button the host can't coordinate, since the report can't drive host navigation |
| I2 | The Week view leads with one plain sentence, "↓ 2 h 10 min less than the week before (−9%)", in **neutral ink** (no green for less, no brick for more) | Answers J8 on the first screen. Brick already means "blocked/looser", and a calm app shouldn't grade the user |
| I3 | Changes in hours and minutes first, percentage second | "−2 h 10 min" is easier to feel than "−9%" or "−130 min" |
| I4 | One **About this data** host sheet with static explanations. The measured coverage counts move to Trends → "How complete this is", and the report's expandable "Usage details" is removed | Merges the two "Usage details" while keeping every measured number inside the report |
| I5 | Starting point: comparison card in Trends (all apps, complete weeks only). **Add/Edit lives in About this data**; the pinned bottom capsule goes | The estimate is shown once. A once-ever task no longer costs about 64 pt on every visit |
| I6 | One manual **Refresh** in the Insights header (plus auto-refresh on show). Proposed for Today: keep pull-to-refresh, drop the card arrow | One refresh per report surface. Insights can't use pull-to-refresh because its scroll belongs to the report process |
| I7 | New `LatchReport/ReportTheme.swift`, a copy of the foundations tokens with a parity test against `Theme.swift` | The extension can't import `Shared`; the test stops the two palettes drifting |
| I8 | Mark only what is incomplete ("Partly reported"); complete data carries no label | Removes the "Full reported coverage" caption from almost every element |
| I9 | Host draws a "Loading your usage…" line *behind* the report | Gives feedback while iOS renders, with no readiness handshake. Needs a device check that the report is transparent before it renders |
| I10 | Weeks stay rolling seven-day periods, always named by dates ("Last 7 full days", "The week before") | Calendar weeks would always include a partial current week, and incomplete periods must never trend |
| I11 | Without Screen Time access, Insights shows a calm card with **Go to Today**, no prompt | Today owns the permission banner (plan §6); Apple 5.1.1(iv) |

Open questions for the owner:
1. Starting point Add/Edit inside About this data (recommended), or a
   visible quiet row at the bottom of Trends that the host draws?
2. Is the neutral colouring for "less/more" right, or should "less" use the
   sage `free` ink?
3. Should a later spec add pickups and notifications (Apple provides them)
   for "thorough stats"?
4. OK to remove the usage card's refresh arrow on Today (changes the approved
   Today spec slightly)?

## Owner's answers (2026-11-02)
Approved with the recommended answers to the open questions:
1. Starting point Add/Edit lives inside About this data.
2. "Less/more" stays in neutral ink.
3. Pickups and notifications: not now; a possible later spec.
4. Today's usage card drops its refresh arrow and keeps pull-to-refresh
   (amends `today-redesign.md`).
