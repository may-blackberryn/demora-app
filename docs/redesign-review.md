# Demora iOS full redesign — review

## Start here
- **When & where step 4 (2026-11-12):** places and the one-shot location
  check (`f4aa920` + review fixes `ab2c566`, `3387a4d`): Add condition → Place opens a
  place sheet (centre from where you are now, 100 m–2 km, copy from another
  rule); Check in reads one foreground fix only when a place could change the
  answer (`3387a4d` adds: and uses are left), after an in-app card the first time; the iOS prompts are translated
  in all eight languages. Countries (step 5) and block check-ins (step 6) are
  still later; block rules can't be saved yet. Nothing seen on a screen or
  tried with a real location. See "When & where step 4" at the end for
  decisions, phone checks, privacy notes and what step 5 needs.
- **When & where step 3 (2026-11-12):** check-in and Today rows (`bf2d2ed` +
  review fixes `4784fe8`): Check in is on; the check-in sheet checks day,
  time and dates (no location yet), shows ✓/✗/? with reasons and starts free
  time with a hold; Today lists "Check in" rows under your limits; a running
  check-in session lives on its rule with End early. See "When & where
  step 3" at the end for decisions, phone checks and what step 4 needs.
- **When & where step 2 (2026-11-11):** editor, Rules card and summary sheet
  (`79e51ba` + review fixes `af71cf8`): When & where section after Schedules,
  New rule row, one-page editor (days, time, dates; place/country explained
  as later), summary sheet with Edit/Remove and Check in switched off. Block
  rules can't be saved until places arrive. See "When & where step 2" at the
  end for decisions, phone checks and what step 3 needs.
- **When & where step 1 (2026-11-11):** engine only (model, evaluator,
  check-in starts, per-day uses, capacity, `Tests/WhenWhereHarness.py`),
  `9151393` + review fixes `da7fe64`. No UI or location yet. See "When &
  where step 1" at the end for decisions worth the owner's eye and what
  step 2 needs.
- **State (2026-11-11):** every redesign build is now on `design/full-redesign`,
  ending with the **four-tab switch** (`748c488..afcf685`; see
  "Four-tab switch" below). Nothing pushed. Verify passes: all 34
  `Tests/*Harness.py`, both Swift harnesses, both localization checks,
  `git diff --check`, unsigned arm64 Debug and Release, then signed Debug.
- **Install:** signed Debug (**dev demora**, `may.latch.dev`) built and passed
  `codesign --verify --deep --strict`, but **it is not installed**: devicectl
  reported "iphone de may" as *unavailable* (error 4016), not locked. Connect
  or unlock the phone on the same network, then run the install command in
  `CLAUDE.md`. No simulator runtime is installed, so **nothing in the switch
  was seen on a screen**.
- **What to try on the phone, in order (four tabs):**
  1. Open dev demora. The bar shows **Today · Rules · Insights · You** (sun,
     list, chart, person). No Delays/Limits/Schedules/Settings tabs. Make
     text very large in iOS Settings once: labels wrap, they don't shrink.
  2. **Today**: no Insights/Help links at the bottom any more. Tap **Full
     day** next to "Today": the Calendar opens as a sheet with **Done**. Tap
     a day, then an item → its summary sheet. If it has a waiting change, **See
     in Changes** must close the Calendar and land on that change.
  3. Still in Calendar from Today: open a limit with extra time ready → **Get
     extra time on Today**. Both sheets must close and leave Today showing.
  4. **Rules**: Calendar and Conflicts in the header; New rule at the bottom.
     Open the Calendar there and repeat step 2 (it pushes inside Rules).
  5. **Insights**: opens the report directly as a tab. Switch to another tab
     and back: it must not reload from scratch. Open ⓘ About this data, then
     tap a widget: it lands on Today with the About sheet gone.
  6. **You**: as before (Ways to skip a wait, Approving for others,
     Notifications, App). Change **Language** in You → Appearance: every tab
     must switch language and You must stay on the Appearance page.
  7. **Dots**: ask someone to send you an approval request — Today's tab shows
     a dot (also while you are on Rules/You, within ~30 s). Approve or deny on
     Today: the dot goes. An invite to be someone's contact puts the dot on
     You instead. With VoiceOver the tab reads "…, Approval request waiting".
     Turn on Airplane mode: existing dots and rows stay, they don't flicker off.
  8. With a contact request already sent for a change, cold-launch the app
     offline: Changing soon must still show "Waiting for …" right away.
  9. Widgets: tap Now & next and Changing soon from Rules, Insights and You;
     each lands on Today / Changes with no stale sheet.
  10. Upgrade welcome (only if you reset the welcome marker or use **You →
      Developer → Setup demos (debug)** → migration): the card is "Four tabs
      now" with one line per tab, and day/night says "Rules → Day & night".
- **Decisions most worth your eye:** a language change still rebuilds the
  tabs (and so re-queries the private reports) — I kept this from before the
  switch so every string follows the language; the welcome's four tab lines
  show once instead of name + "Name — …"; the Day & night and Group wake-up
  list pages are gone (their rules are on Rules and the summary sheet);
  "Developer → Reset app (debug)" stays, DEBUG only.
- **Known limits:** nothing seen on a phone; no live contact/invite round
  trip; ~380 catalog keys are no longer used literally in source (some are
  used through variables), not pruned here.

### You: what to try on the phone (2026-11-08)
- **State:** foundations, Today, Rules, Insights and now the You build
  (`docs/you-redesign.md`) are on `design/full-redesign`; the You build is
  the commits after `d7dd92e` (see Sessions). Nothing is pushed. Verify
  passes: every `Tests/*Harness.py`, the two Swift harnesses, the
  localization check, `git diff --check`, and unsigned arm64 Debug and
  Release builds of the Latch scheme.
- **Install / run:** open `Latch.xcodeproj`, scheme **Latch**, Debug, on your
  iPhone. No simulator runtime is installed on this Mac, so nothing in the
  You build was looked at on a screen, and no live contact, email or relay
  round trip was made.
- **What to try on the phone, in order (You):**
  1. Tap the last tab (still labelled **Settings** until the four-tab
     switch). It opens **You**: Ways to skip a wait, Approving for others,
     Notifications, App, and a footer with the version, Privacy and Word list
     credits. With no ways yet the card says "Nothing can skip a wait yet."
  2. **Add a way to skip a wait → A password.** Name it, type it twice, tick
     only **Limits**, Continue. The receipt is the last step inside the same
     sheet: "Looser change", the landing time, **Hold to confirm**. Hold. The
     row appears dimmed with "Added …"; tapping it opens Changes on that
     change.
  3. Add **Someone you trust** with a friend's Demora code (Your code is
     shown under Approving for others). Without email configured there is no
     Email/Demora switch. If contacts were paused, the receipt has a second
     line, "Also turns on contact approvals". The row then reads "Waiting to
     accept" until they accept.
  4. Once a way exists (or skip the wait with **Skip delay (dev)**), open its
     row: the checklist shows what it may skip **now**. Change it, **Save
     changes** → receipt. Narrowing a contact is a stricter, one-tap
     Confirm; a password or phrase edit stays "Looser change" (owner answer
     1). The page then shows "From …: …" above the unchanged checklist,
     with **See in Changes**.
  5. On a password, **Change the password**: current, new, confirm, **Change
     now**. It changes right away; what it may skip doesn't. A wrong current
     password says so.
  6. **Remove…** on any row → receipt with a plain **Confirm** (stricter).
  7. With a looser change waiting and a way that may skip it, tap **Apply
     now…** in Changes (Today → All, or a rule's pending line). One sheet
     opens: the change on top, then only the allowed ways. With exactly one
     usable way it opens straight on it. Type the password: wrong clears the
     field and says so; right closes the sheet and the change lands.
  8. Phrase: the word-by-word entry shows "Word 1 of 50" and mistakes left;
     paste is not offered.
  9. Contact: send a request, close the sheet, then tap "Waiting for …" on
     the change: it reopens on "Sent · waiting". Apply now on the same change
     still lists your password and phrase. Approve on the other phone.
  10. Extra time on Today with a password/phrase/contact step opens the same
      sheet on that step ("Extra time · Games · +15 min").
  11. **Contacts can approve · On** row → receipt: off is Confirm, on is Hold.
      While off, contact rows say "Paused" and Apply now lists no contacts.
  12. Ask someone to add you as their contact: an invite card appears at the
      top of You (the tab shows a dot). **Block** asks once.
  13. Notifications: the two toggles sit on You. **Appearance**: theme tiles,
      Blue/Brick swatches, Regular/lowercase and week start apply at once;
      the preview card follows. **Prevent disabling**: one page; Request
      access goes through the receipt; "Enter passcode" stays immediate.
  14. **Help & guide → How Demora works**: four pages. The Guide now names
      Today, Rules, Insights and You.
  15. The **Delays** tab still has its delay rows; its override part is one
      row that opens You.
- **Decisions most worth your eye:** the "Changes to your ways can never be
  skipped" line was false and now reads "Changes to passwords, phrases and
  what anyone may skip can never be skipped early." — adding, removing or
  pausing **contacts** can be skipped early by a way allowed "Trusted
  contacts", which new contacts are by default (engine unchanged; see the You
  review fixes); tapping one contact in the skip sheet checks only that
  contact; the tab label stays "Settings" until the switch.
- **Known limits:** nothing checked on a phone; no contact/email round trip;
  the walkthrough's remaining branches and the legacy Limits/Schedules
  screens go at the four-tab switch (list in "You build").
- **Housekeeping:** build products are in the session scratchpad, outside the
  repo.

### Insights: what to try on the phone (2026-11-04)
- **State:** foundations, Today, Rules and now the Insights build
  (`docs/insights-redesign.md`) are on `design/full-redesign`; the Insights
  build is the commits after `32abd2a` (see Sessions). Nothing is pushed.
  Verify passes: every `Tests/*Harness.py`, the two Swift harnesses, the
  localization check, `git diff --check`, and unsigned arm64 Debug and Release
  builds of the Latch scheme.
- **Install / run:** open `Latch.xcodeproj`, scheme **Latch**, Debug, on your
  iPhone. No simulator runtime is installed on this Mac, so nothing here was
  looked at on a phone screen; the report was only rendered as synthetic macOS
  pictures.
- **What to try on the phone, in order (Insights):**
  1. On Today, scroll to the bottom and tap **Insights** (still a link there
     until the four-tab switch). The page opens with **Insights**, a refresh
     arrow and an ⓘ. While iOS draws the report you should briefly see
     "Loading your usage…"; once the report appears it must be gone. If the
     line stays visible *behind* drawn charts, tell me: that drops decision I9.
  2. **Day** (selected first): the big total says "Today so far", with "Your
     daily average last week" under it when last week is fully reported. The
     chart card pages with ‹ ›; tap a bar to see that day. A day iOS only
     partly reported shows a "Partly reported" chip; full days show nothing.
  3. **Week**: "LAST 7 FULL DAYS · dates", the total, "… a day", and one
     sentence such as "↓ 2 h 10 min less than the week before (−9%)" in plain
     ink. Tap an older bar in **Four weeks**: the title switches to its dates,
     and the oldest says "No earlier week to compare."
  4. **Trends**: the same Four weeks card on top, then Compared with the week
     before, Day by day (tap a day for both figures), Highs and lows, Weekday
     patterns, Biggest app changes, Your starting point and How complete this
     is (the calendar of dots and the three counts). Pick another week above:
     every card follows it. There is no "Back to usage" any more.
  5. In **Most used apps** (Day or Week) tap an app: the whole view scopes to
     it (name + **All apps** under the switch), Most used disappears, and
     Day/Week/Trends all stay on that app. **All apps** returns.
  6. Tap ⓘ **About this data**: five short sections, then **Your starting
     point** with Add or Edit. Add an estimate, Save, close the sheet: Trends →
     Your starting point shows it ("You estimated 21 h a week…"). Edit again and
     switch it off to remove it; Trends then shows the one-line hint instead.
  7. Tap the refresh arrow a few times quickly: one light tap each, the report
     refreshes without blinking away or looping.
  8. Change appearance (dark), accent (red) and language (try Deutsch and
     हिन्दी) and come back: report colours and words follow; long German lines
     wrap, numbers never truncate.
  9. Largest text size: the switch spans the width, bars scroll sideways with
     big targets, figures stack. VoiceOver: switch → scope → hero (one element)
     → chart bars (date, value, "Partly reported" only when it applies).
  10. Debug build without Screen Time access (or after revoking it): Insights
      shows "Insights needs Screen Time access." with **Go to Today**.
  11. Onboarding/welcome estimate step and the Guide's **Insights** entry now
      point to "Insights → About this data".
- **Decisions most worth your eye:** "Insights" is translated as a stats word
  (Estadísticas, Einblicke, Statistiques…); "The week before" is translated as
  "the 7 days before" so it can't read as a calendar week; under a minute
  reads "0 min"; a change under 1 % drops the percentage; Today's link now
  reads "Insights"; About this data keeps the approved "Demora can't read,
  save or send it." (the reviewer suggested softer wording).
- **Known limits:** nothing checked on a phone; the loading line's behaviour
  needs the device check (I9); `canRefresh` still uses Today's tab until the
  four-tab switch; highs-and-lows weekdays aren't bold.
- **Housekeeping:** build products and preview pictures are in the session
  scratchpad, outside the repo.

## Sessions
| Session | Scope | Commits | Status |
| --- | --- | --- | --- |
| Foundations build | Tokens, type, components, text case, tab bar; three review fixes | `7af8f65`, `46181bc`, `b15b244`, `d448215`, `5fad6e0`; fixes `3d25eda`, `23ba309`, `a59969f` | Done, reviewed and fixed |
| Today build | Pure logic, change receipt, Changes ledger, Today layout, report restyle, extra time moved | `82181d3`, `f3cbd3f`, `2548ac8`, `e16fe23`, `3180864`, `f38951e`; review fix `d2f8329` | Done, self-reviewed and fixed; awaiting the main session's review |
| Rules build | Pure logic, Rules tab, summary sheet, editors, receipts and Changes copy, dead editor removed | `90e5f42`, `660ec07`, `b4345ae`, `f5d7e54`, `ea16ed1`, `c79d334`; review fixes `61681ee` | Done, reviewed and fixed; awaiting the main session's review |
| Insights build | Pure logic, host header/loading line/About sheet, Day · Week · Trends report, copy elsewhere, README/status | `46eb366`, `680d09e`, `619a77d`, `a20433e`, `d065979`; review fixes `ec80259` | Done, reviewed and fixed; awaiting the main session's review |
| You build | Pure logic, You page, Skip the wait sheet, add/edit/remove with receipts, Help and Guide copy, duplicate screens removed | `4492d82`, `562bc69`, `f8994c9`, `41e7d00`, `b62f699`, `e86f704`; review fixes `17ec17f` | Done, reviewed and fixed; awaiting the main session's review |
| Four-tab switch | Dead beta/language screens, four tabs + tutorial retirement + Calendar restyle, dead list pages, copy; started by Codex, finished by Claude | `748c488`, `9a7d236`, `f061030`, `5cc01b1`; review fixes `afcf685` | Done, reviewed and fixed; signed build not yet installed (phone unavailable) |
| When & where step 2 | Editor, Rules card and section, summary sheet, owned windows, copy, presentation harness | `79e51ba`; review fixes `af71cf8` | Done, reviewed and fixed; nothing seen on a screen |

## Foundations build (2026-11-02)
| Decision | Why | Done? |
| --- | --- | --- |
| Palette lives in `InkPalette` as plain hex pairs; `Ink` builds colours from it | One place to edit, and the contrast harness reads the same numbers the app uses | Yes |
| Dark tint 12 % (spec: 22 %) | At 22 %, red text on its tint is 3.81:1 and ochre 4.33:1, under the 4.5:1 body target; 12 % passes all 92 pairs (tightest 4.56:1) | Yes |
| `faint`, `rule`, `surface` alias the new `inkSoft`, `hairline`, `card` | Spec: thin aliases. `inkSoft` and `hairline` differ slightly from the old values (darker secondary text for contrast; slightly lighter rules) | Yes |
| `danger`, `hero*`, `buttonText` keep their old values | They're retired in the spec but still drawn by current screens; changing them now would restyle screens outside this step | Yes — remove when screens move |
| `loosen` follows the accent through `@AppLoosen` | Same reactive pattern as `@AppAccent`, so changing the accent updates views without a defaults read | Yes |
| Contrast harness also checks paper labels on full-strength fills and large serif ≥ 3:1 | Buttons and the HoldButton fill put paper-coloured text on accent/loosen; every pair meets 4.5:1, so 3:1 large is implied but kept explicit | Yes |
| `DemoraType` is an enum of styles with `.demoraType(_:)` applying font and tracking | Tracking (−0.6 page title, +0.6 label) can't live in a `Font` | Yes |
| SF Pro styles name `design: .default` explicitly | The app root applies `.fontDesign(.serif)`; an explicit design is needed to get SF Pro. Not checked on screen | Yes — confirm on device |
| Components go in a new `Latch/DemoraComponents.swift`, tokens and type stay in `Theme.swift` | Keeps `Theme.swift` readable; spec §8 names `Theme.swift` for both | Yes |
| `DemoraPrimaryButtonStyle` and `EmptyStateView` moved into the components file | One home for the shared components; their names and call sites are unchanged | Yes |
| `CountdownProjection` is a pure enum; `CountdownText(to:style:)` uses it; `style: nil` leaves the font to the caller | `PendingChangeRow` keeps its exact title2 serif look; the projection is tested natively | Yes |
| `CountdownText` reads `Date.now` once instead of twice | Both ends of the interval share one system instant; the old code's two reads differed by microseconds | Yes |
| `CountdownText` holds at 0:01 and leaves the due state to the caller; `CountdownRing` shows the existing "Applying…" when due | Matches the row's current behaviour and reuses a translated string | Yes |
| `HoldButton`: VoiceOver or Reduce Motion → a plain button with one alert; Switch/Voice Control get the alert through an accessibility action | Spec §9 and today §5.10; people who can't hold still get a deliberate step | Yes |
| `HoldButton` takes the confirmation question from the caller | The question depends on the change ("Confirm looser change?" belongs to the receipt, built with Today) | Yes |
| `StateChip`: active = accent, blocked/loosening = loosen, free = free, upcoming/neutral = inkSoft with a hairline outline | Spec §4 colour rules; inkSoft has no tint pair, so an outline keeps it quiet | Yes |
| `DayChips` uses `Set<Int>` (1 = Sunday … 7 = Saturday) and the user's first weekday; the last day can't be cleared unless `allowsEmpty` | Matches the saved rule models (`weekdays: Set<Int>`) and their non-empty validation | Yes |
| Day chip circles inscribe in their cell (44 pt where there's room) | On the narrowest phones seven 44 pt circles plus gutters don't fit; the cell keeps a 44 pt height. Not checked on an SE | Yes — check on SE |
| Buttons (primary, HoldButton, empty-state action) use SF Pro semibold | The spec gives sentences to SF Pro and lists no button style | Yes — owner may prefer serif |
| `EmptyStateView` is now a paper card with an optional action, at all three current call sites | Spec: restyled into a PaperCard with one action. Home's "No limits yet" still sits inside its old ruled section until Today is built | Yes |
| Only "Confirm" was added to the string tables | Other component strings reuse "Cancel" and "Applying…"; screen copy comes with each screen | Yes |
| Text case: default is regular via `TextCasing.fallback`; unreadable stored values also fall back to regular | `@AppStorage` never writes its default, so a stored value is a real choice and is kept (F3). A corrupt value isn't a choice | Yes |
| Tab bar restyled in place: SF labels, accent selected, inkSoft others, equal 18 pt icons, hairline, selection bar removed, badge dot in `loosen` | Visual only: same five items, order, bindings, lock, badge counts and accessibility; a source guard checks that | Yes |
| Four-tab switch not done | Out of scope (spec §7: last integration step) | Follow-up |
| Report extension palette copy not done | Brief: don't touch `LatchReport/`; spec §8 asks for it | Follow-up |
| No fade-in on cards (spec §9 "cards appear with a 0.2 s fade") | That's a screen transition; it belongs with each screen's build | Follow-up |
| No visual check of anything | No iOS Simulator runtime on this Mac and no device in this session | Limit |

## Foundations review fixes
| Bug | Fix | Test |
| --- | --- | --- |
| `CountdownText` read the clocks only in `body`; with an unchanged deadline SwiftUI could skip it and keep a stale projection (e.g. 0:00 after a clock change while not yet due) | The projection is taken in `init` (runs on every parent redraw) and stored as the view's input; `CountdownRing` passes its tick's clocks so ring and text agree (`3d25eda`) | `FoundationsComponentsHarness`: compiles the real `CountdownText` and checks a redraw after the guarded clock moves re-projects; guards that `body` doesn't read the clocks |
| `DayChips` used the device calendar for week order and day names, ignoring the in-app "week starts on Monday" setting and the in-app language | Pure `DayChipsCalendar` builds the calendar from the environment locale with `firstWeekday` from `weekStartMonday`, as the month calendar does (`23ba309`) | `FoundationsComponentsHarness`: natively checks order for both week starts and Spanish/German names; guards against `Calendar.current` in `DayChips` |
| Home's "No limits yet" card was still wrapped in `demoraSurface()`, drawing a second rule and extra padding | Removed the wrapper (`a59969f`) | `FoundationsComponentsHarness`: fails if any screen wraps `EmptyStateView` in another surface (confirmed it catches the old code) |

## Today build (2026-11-02)
| Decision | Why | Done? |
| --- | --- | --- |
| Pure decisions live in `Latch/TodayPresentation.swift` (Foundation only): `NowSummary`, `DayThread`, `LedgerGrouping`, `ReceiptPlan`, `TodayTimeText` | `TodayPresentationHarness` compiles the file as it is, with no stubs; the views only translate and draw | Yes |
| The spec's `NowSummary.make(state:blockedLimitIDs:wakes:now:)` is a thin adapter in `HomeView.swift` over a pure `make(items:spentLimitNames:wakes:now:)` | The adapter needs `LatchState`; the priority logic doesn't, so it can be tested natively | Yes |
| A running free period outranks spent limits (table row 6 before row 5) | Limits don't block in a free period, so "Games is used up" would be wrong there. Active blocks still lead | Yes — owner may check |
| "and N more" is used on row 4 (three names, then "and 2 more"); row 3 shows only the time left | Row 3 is exactly one block, so "and 2 more" can only belong to the several-blocks list | Yes |
| "Your apps open at" uses the latest of the running wake waits | Some apps open earlier, but the sentence says when your apps (all of them) open | Yes |
| A wake group with a 0-minute wait shows no "wait" fact | A 0-minute wait opens on the tap; "wait 1 minute" would be invented | Yes |
| Unblock sessions are their own item kind: on the day thread, but neither a block nor a free period in the Now card | An unblock session lifts blocks on chosen apps; calling it a free period would overstate it | Yes |
| The Now card drops blocks under an active free rule on a higher layer (sleep 0, recurring 1, planned 2, session 3); on the same layer, and for schedule priorities you chose, it keeps the block | Matches how the shield plan layers them without re-implementing per-app precedence, which depends on opaque selections | Limit — same-layer ranks and promotions not resolved |
| "Used up" mirrors the shield's baseline, read in event callbacks: the monitor's blocked list and 0-minute limits, minus limits with extra time running; a blocked split portion reads "used up for now" with no "Resets at midnight" | Same sets `ShieldController.apply` uses; the host never sees usage | Yes |
| Sleep blocks join the day sources: global sleep from its start to the wake hour (as the shield plan reads it); day & night groups mirror `sleepIsActive` | Spec lists sleep in rows 3 and in the thread; the old day line had no sleep, so this reuses the existing rule logic as intervals | Yes |
| Times on another day carry their weekday ("until Tue 07:00"); a week or more away carries the date | Otherwise a block past midnight reads "until 07:00", which looks like this morning | Yes |
| Tapping the Now card opens Schedules (blocks, free periods) or Limits (used up) | The Rules summary sheets don't exist yet; wake states aren't tappable | Interim — Rules build |
| Now-card countdowns use `Text(timerInterval:)`; extra-time waits use `CountdownText` | Block ends and projected wake releases are wall-clock; the extra-time release is a TimeGuard deadline | Yes |
| Day thread: at most 5 items, keeping everything on now and upcoming first, then the most recent past; "now" sits before the first upcoming item; "Full day" always shows and opens Schedules | Today is about now and next; the calendar lives on Schedules until Rules exists | Interim — Rules build |
| Ledger groups and landing times use the stored `appliesAt` (spec); the countdown keeps its TimeGuard projection; "Later" starts 7 days ahead; due changes count as "Within the hour" | Spec §5.9 and §5.10; the two only differ after a clock change | Yes |
| Receipt: looser changes always hold to confirm, even with no wait; stricter removals (a contact, a recurring free period) confirm with one tap | T3 and plan D9's 2026-11-02 correction; a 0-minute looser wait is still a loosening | Yes — owner may check |
| Receipt never says "about" | The preview uses the same policy and clock offset as the queue, so it can't differ from the stored time by a minute | Yes |
| Receipt refreshes its "Takes effect" each minute while open; a refusal (already pending, monitoring limit) shows on the receipt and clears the app-wide alert | §5.10: keep the sheet and show the message inline | Yes |
| The legacy tutorial keeps queueing directly from the limit editor and recurring list, and keeps its inline delay hints | Its steps advance on the queued change and highlight specific buttons; a receipt sheet would break the scripted flow | Yes |
| Receipt copy says "You can cancel it from Today" while the tab is still labelled Home; the app-wide "already pending" notice still says "Home tab" | Approved copy; the tab rename comes with the four-tab switch, when both should be reread | Flag for owner |
| HoldButton's success haptic and `model.queue`'s success haptic both fire on a held confirm | Changing `AppModel.queue` would change every other editor's feedback | Limit |
| `ChangeRow` takes `PendingChangeRow`'s inputs plus the waiting request; the legacy tutorial Home keeps `PendingChangeRow` | The tutorial Home must render unchanged | Yes — retire with the tutorial |
| Bulk cancel in the ledger asks once ("Cancel these changes?"); a single Cancel stays immediate | Spec §5.9 | Yes |
| "Waiting for Alex" uses the saved contact names on the sent request (joined with commas); with no name it says "Waiting for approval…" | The request stores contact IDs; the stored name is what the app already shows | Yes |
| The ledger owns its override and contact sheets | Sheets attached to Today's root don't reliably present over a pushed page | Yes |
| The ledger shipped unwired in its own commit and was wired into Today in the next | Steps were built and verified in the brief's order | Yes |
| Legacy Home now keeps only what it showed during the tutorial; the old wake button, usage card, sessions list and 24-hour bar (`HomeDayTimeline`, segment helpers) are gone | Those branches never rendered in the tutorial and are replaced on Today. `HomePresentationHarness` drops the segment checks and now checks the Now card's Wake up and the wait each tap starts | Yes |
| Attention card holds the Screen Time permission and background-monitoring banners | Recovery is handled at the app root, which doesn't show Home | Yes |
| No "Usage isn't available right now" state | The host can't tell a missing report from an empty one without a readiness signal, which the privacy rules forbid; the report's own note covers it | Limit |
| Inbox card reads "A contact asks to apply …" when the requester has no name | Never show an empty name | Yes |
| Usage report card: no header or refresh arrow (Amendment I6), "Your limits" header above it, paper card, note now says "pull down to refresh" | The old note pointed at the removed Refresh button | Yes |
| Extra-time gate routing moved into `ExtraTimeRoute`; a pending contact request shows "Waiting for a trusted contact" and reopens it | Same steps and gates as the Limits tab had | Yes |
| Report rows: "No data yet" when none of the limit's apps or categories appear in today's data; spent rows are a full `loosen` bar with "Used up"; a 0-minute limit reads "Used up" | Missing is unknown, not zero. A site-only limit was never counted by this report, so it now says "No data yet" instead of "0 of 30 min" | Yes |
| `LatchReport/ReportTheme.swift` copies only the seven `InkPalette` pairs the report draws with; the harness fails if any drifts | The extension doesn't import the app (foundations §8) | Yes |
| The report localization generator now also scans `LimitsUsageView.swift` | Its copy ("No limits yet", "Blocked") was never translated | Yes |
| Home's bulk-apply notice is now translated | Its key had no entry in any table (the tables held an older wording) | Yes |
| No visual check of anything | No iOS Simulator runtime on this Mac and no device in this session | Limit |

## Today review fixes
A fresh reviewer read the whole Today diff. Fixed (`d2f8329`), each with a regression check in `TodayPresentationHarness`:

| Bug | Fix | Test |
| --- | --- | --- |
| Extra-time rows read the sent contact request (which decodes saved state and reads TimeGuard) while drawing | Today reads it in `refreshSnapshot` and passes a set to the rows | Source guard: no `ContactsRelay.` in `ExtraTimeRows` |
| A free session over a recurring block still said "<block> is on until …" | Items carry their effect layer; an active free rule on a higher layer clears lower blocks | Native: free session over recurring → free period; later-layer block survives a planned free window; same layer keeps the block; a finished free session clears nothing |
| A limit with extra time running still read "used up for today"; a blocked split portion read "Nothing is blocked" | Spent sets mirror `ShieldController.apply`; portions read "used up for now" | Native: portion only / day wins over portion / mixed; source guard on the snapshot reads |
| "Add a daily time limit." (first-limit card) had no translation in any table | Added in all seven | Every `tr()` key in the Today files is checked in all seven tables |

Not changed: removing a contact or a free period confirms with one tap (plan D9 correction); the ledger groups by the stored `appliesAt` (spec §5.9), so after a clock change its group can disagree with the countdown — logged above.

## Rules build (2026-11-02)
| Decision | Why | Done? |
| --- | --- | --- |
| Steps built in the brief's order, one commit each: pure logic, Rules tab, summary sheet, editors, receipts/copy, dead editor removal | Each verified before the next | Yes |
| Pure decisions in `Latch/RulesPresentation.swift`; `RulesPresentationHarness` compiles it with the real `SharedModels` and `SchedulePrecedence` | §7 names these functions; only opaque tokens and the guarded clock are stood in | Yes |
| Next start, window activity and the four editors' validity were lifted and checked for equivalence against frozen copies of the old view code (23k time comparisons, 1,152 limit and 512 repeating drafts, every planned and session case) | §7/§8: no logic moves except pure lifts with equivalence tests | Yes |
| Pure Rules logic takes a `translate` closure instead of calling `tr` | The harness then checks the exact English lines ("30 min a day · 4 apps, 1 category") with no app | Yes |
| Counts say "1 website" / "%d websites", not the spec's "%d sites" | The existing German "%d sites" entry reads "%d-Standorte" (locations); a new key avoids it | Yes |
| Polish counts read "Aplikacje: %d" | Polish needs three plural forms; the app's tables have one entry per key | Yes — native speaker may refine |
| Fixed "OK" in German, French, Polish and Turkish (was "- Ich bin nicht mehr da.", "Très bien.", "Dobrze.", "iyi") | Machine-translation slips; Rules' recheck alert shows this button | Yes |
| Tab 1 keeps its "Limits" label and icon until the four-tab switch | The tab bar is part of that switch (foundations §7) and FoundationsComponentsHarness guards the five tabs | Flag for owner |
| The Blocked chip uses the same sets as Today's Now card: spent for the day unless extra time is running, plus split portions blocked for now | Spec says `loadBlockedLimitIDs()` or 0 minutes; the Today review fix (d2f8329) showed that set disagrees with the shield when extra time runs | Yes |
| No read-only "recovery" Rules | The app root already replaces every tab with "Your setup is safe" while state can't be read, so Rules never shows then | Yes |
| The ledger's `scrollTo:` came with the Rules tab (spec step 5) | Card pending lines need it from the first Rules commit | Yes |
| The Conflicts dot and the editor's overlap note use `SchedulePrecedence.conflicts` | Same definition as the Conflicts page: two blocks of the same kind on the same apps don't conflict | Yes |
| Rules reads sent contact requests for the ledger but doesn't clear finished ones | Clearing stays with Today, which already does it on each load | Yes |
| A queued "Block now" is its own card (`RuleRef.queuedSession`, by change ID) | A session only gets its ID when it starts | Yes |
| Queued planned windows and sessions show as dashed cards at the end of Planned | Spec §5.4 shows queued additions; §5.3's Planned row didn't list them | Yes |
| `EmptyStateView` gained an optional second action | Rules' first use offers "Add a daily limit" and "Repeating block" (§6); default unchanged | Yes |
| Day & night chip: "Opens 7:42" only while a wait runs; a group waiting for its tap has no chip | Wake up lives on Today; a chip saying "Opens" without a time would be invented | Yes |
| Your waits pending line reads "Changes in …" | The spec's pending verbs are about rules; a delay-policy change is neither looser nor stricter on a rule | Yes |
| Now card: one block or a free period opens that rule's sheet; several blocks, or more than one used-up limit, switch to Rules | The sentence names one rule only in those cases; a list of rules belongs to Rules | Yes |
| Today items map to rules by their existing IDs (`RuleRef(todayItemID:)`, tested) | No new identity is stored; the thread already carries each rule's ID | Yes |
| Calendar items open the sheet outside the tutorial; on the Schedules tab "See in Changes" goes to Today | The Schedules tab has no ledger of its own until the four-tab switch | Interim — four-tab switch |
| "Get extra time on Today" switches to Today but doesn't scroll to the extra-time row | Scrolling another tab needs new cross-tab state; the row sits right under Your limits near the top | Limit |
| The summary sheet's per-limit wake-up row pushes the existing group wake editor inside the sheet | R7: only limits that already use it, kept editable | Yes |
| The legacy tutorial keeps the old limit and recurring editors (`TutorialLimitEditorView`, `TutorialScheduleEditorView`) | Its steps highlight the old Remove button and expect a direct queue (R10); both go at the four-tab switch | Interim — four-tab switch |
| The first-problem line shows only after something in the draft changed | A fresh "New daily limit" would otherwise open with "Give it a name." before you've typed; Review change is disabled either way | Yes |
| Sheet editors with an edited draft can't be swiped away | Cancel asks "Discard your changes?"; a swipe would skip that question | Yes |
| Pushed editors (Your waits, priority, per-limit wake-up, legacy wake/sleep from the Schedules tab) have no Cancel or discard question | The back button leaves them; a custom back button would replace the system one | Yes |
| DurationControl: − / + snap to 5 minutes, hold repeats on iOS 17+, tapping the value shows the existing wheels | iOS 16 has no repeat behaviour for buttons; the wheels still reach any value | Yes |
| The wake wait uses DurationControl everywhere `WakeTimingEditor` is used (day & night, per-limit, onboarding) | Spec §5.7 lists the wake wait as a DurationControl user; one control for durations | Yes |
| `WakeTimingEditor` weekdays use DayChips | Replaces seven toggles; same `Set<Int>`; DayChips can't clear the last day, which an empty set would have made invalid anyway | Yes |
| Plan a block's three types are a check list, not a segmented control | "Only these apps / All except these / Free period" overflow a segmented control in German and Hindi | Yes |
| New repeating block keeps the old defaults: "All except these", 22:00–07:00, every day | Behaviour unchanged; the overlap note and receipt show what it will do | Yes — owner may prefer "Only these apps" |
| Legacy wake/sleep: an invalid app scope reads "Choose at least one app." | The old editor only disabled its button; the scope can fail for several reasons, this is the common one | Yes |
| The day & night editor's first problem reuses its existing error sentences verbatim, in the old order | Category-wide fallback errors must stay exactly as they were | Yes |
| ChangeReceiptRequest gained `note` (session length) and `canQueue` (re-check before queueing) | Spec §5.7 D asks for the session line; §5.7 E asks for guards before the receipt and again before `queue` | Yes |
| Conflicts page and priority editor restyled with the new page; the bounded list of 40 kept | §5.8, §5.7 J | Yes |
| Calendar itself is not restyled beyond its items opening the summary sheet | Visual-only work outside the critical path; kept for a later pass | Follow-up |
| The Schedules tab's Sessions list and Day & night page stay until the four-tab switch, but their End early and Remove group now use the receipt | §8: Schedules keeps working until then; §5.9 site 18 and D9 | Yes |
| The tutorial's own limit and recurring editors keep their inline delay hints (`TutorialLimitEditorView`, `TutorialScheduleEditorView`) | Today build decision: the scripted steps rely on them; they go with the tutorial | Interim — four-tab switch |
| The old "…Cancel it on the Home tab first…" key stays in the tables, unused | Spec §8/§10 removes orphaned keys only after the You build | Follow-up |
| `PreventDisablingView`'s "Home tab" copy is untouched | It belongs to the You spec, not §8's list | Follow-up (You) |

## Rules review fixes
A fresh reviewer read the whole Rules diff (5aa9c3d..c79d334). Fixed in `61681ee`, each with a guard in `RulesPresentationHarness`:

| Bug | Fix | Test |
| --- | --- | --- |
| Today's "Set your first limit" card lost its "Add a daily limit" button: `EmptyStateView`'s new `secondaryAction` captured the unlabelled trailing closure (backward matching), leaving `action` nil | Label `action:` at the call | Every `EmptyStateView` with `actionTitle:` must label `action:` and take no trailing closure (confirmed it catches the old call) |
| The summary sheet refreshed from the state about to be replaced (`$state` publishes before the change), so chips and the extra-time row lagged one refresh | `refresh($0)` with the published state, as Rules does | Source guard on `.onReceive(model.$state) { refresh($0) }` |
| An open sheet for a queued Block now said "This rule has been removed." the moment the session started (it gets a new ID) | The sheet remembers the queued change and follows it to its session (same name, kind, apps, started after queueing) | Native: follows when applied; unchanged while waiting; ignores an older same-named session; nothing remembered → unchanged |
| Removing an extra-time use read `steps[index]` from rows that can outlive the removal for one update | Bounds-checked `step(_:)`, `update(_:)` and `field(_:_:)` | Source guard: no other `steps[index]` reads on that page |
| Legacy wake/sleep said "Choose at least one app." for any invalid rule | Wake names a bad latest time; sleep names a start equal to the wake-up hour | Source guards on both messages |
| Websites: a site could be queued twice ("www.reddit.com" vs "reddit.com"), a waiting row showed the raw text, and a waiting add read "Tightens in" | Queue the normalized address (the engine saves it normalized anyway), check waiting adds in `canAdd`, label "Added in" / "Removed in" | Source guards on the normalized queue and `canAdd` |
| A harness check ("each editor uses its lifted validity") passed if the call appeared anywhere in the file | Check only inside each editor | The check itself |

## Insights build (2026-11-04)
| Decision | Why | Done? |
| --- | --- | --- |
| Steps built in the brief's order, one commit each: pure logic, host, report, copy, docs | Each verified before the next | Yes |
| Pure display logic in a new `LatchReport/UsageFormat.swift` (`UsageFormat`, `UsageComparisonText`, `UsageWeekComparison`, `UsageCoverageLabel`, `UsagePeriodName`); the segment model `UsageInsightsSelection` sits with `UsageDashboardPresentation` | Foundation only, so the harnesses compile the real files with no stubs; the views only draw | Yes |
| Pure text takes a `translate` closure (the views pass `insightsText`) | The harnesses check the exact English sentences; same pattern as the Rules build | Yes |
| The localization generator also scans `UsageFormat.swift` and `UsageDashboardPresentation.swift` for `translate(…)`, `format(…)`, returned and assigned literals; SF Symbol names are skipped | Keys that live in pure logic would otherwise go untranslated in the report | Yes |
| The generator's `--patch` output is applied with a small checker (`apply_report_patch.py`, scratchpad) that refuses unless every `-` line matches the file | No `apply_patch` tool on this Mac; the snapshot is still never hand-edited | Yes |
| Durations: whole minutes, "%@ h" for exact hours ("21 h"), "%@ h %@ min" otherwise; under a minute reads "0 min" | Spec examples ("21 h a week"); floor matches the old helpers and the shield's minute accounting | Yes — owner may prefer "<1 min" |
| Missing durations read "No data yet" in sentences and VoiceOver, "—" in tight chart captions | Spec §5.4 / §6; a dash is never a zero | Yes |
| Comparison: within one minute either way is "About the same as the week before"; the percentage is omitted when the week before was zero or when it rounds to under 1 % | "(0%)" next to "3 min less" reads as a contradiction | Yes |
| Signed values use the real minus sign (−) | Typography; VoiceOver reads it as minus | Yes |
| "Daily average: 3 h 6 min (−19 min)" uses a signed duration, not an arrow | An arrow character inside text is read as "down arrow"; the main sentence keeps the SF Symbol hidden from VoiceOver | Yes |
| Estimate comparison within a minute reads "%@: about the same as your estimate." (new key) | Spec gives only less/more; "0 min less" would be odd | Yes |
| `baselineDifference(for:)` replaces `baselineDifferenceMinutes`; nil without an estimate, for an incomplete or non-seven-day period; app scopes never carry an estimate (`configuration(baseline: nil)`) | One rule for Trends and the model; any complete selected week compares, not just the latest | Yes |
| Week hero without a total: "No full week yet" until any past day has data, then "No data yet" | The spec's "No full week yet" is for a new install; for an old empty week it would be wrong | Yes |
| "Last 7 full days" names the latest period; "The week before" names the period right before the picked one; others use their dates | Spec I10; the review showed a fixed "The week before" clashed with the sentence once an older week was picked | Yes |
| Heaviest weekday: only weekdays with two or more full days; ties keep the first weekday in calendar order | Spec §5.7.5 and §7 | Yes |
| The segment control's pill is 36 pt inside a 44 pt track (56 in a 64 pt track at accessibility sizes); the whole 44/64 pt row is the tap target | Spec's 44 pt height with a visible track around the pill | Yes |
| Day bars and day-by-day pairs drop their gaps (each bar keeps a 44 pt target) | Seven 44 pt targets plus gaps overflowed a 390 pt phone and clipped the first bar (seen in the synthetic render) | Yes |
| Day bars show the short weekday ("Wed") under each bar; the date range sits between the ‹ › buttons | Spec: weekday label; the full date is in VoiceOver | Yes |
| Highs and lows: plain sentences, weekday not bold | Bold inside a translated format string needs per-language markup | Yes |
| Highs and lows with one full day shows only the heaviest sentence | "Heaviest" and "lightest" on the same day reads oddly | Yes |
| Trends: the Four weeks card is the parent's, shared with Week; `UsageTrendsView` is now cards only, with no scroll, header, back button or `onBack` | I1: Trends is a segment; the report can't drive host navigation | Yes |
| Host header: page title, Refresh and About as 44 pt icon buttons in `inkSoft`; Refresh is hidden without Screen Time access | Nothing to refresh then; About still explains the data | Yes |
| Refresh goes through the Today report's coalescing (`HomeReportRefreshPolicy`: one request, 2 s apart, one soft retry); `refresh()` keeps its name and body | Spec §5.1; `UsageNavigationHarness` parses `refresh()` | Yes |
| `canRefresh` still checks `model.selectedTab == 0` | Insights is pushed from Today until the four-tab switch, which must swap in the Insights tab identity (spec §5.1) | Interim — four-tab switch |
| The "Loading your usage…" line sits behind the report and is hidden from VoiceOver | VoiceOver would otherwise read it under a drawn report; needs the device check from I9 | Limit — confirm on device |
| About this data: Starting point row pushes the unchanged estimate editor inside the sheet; Cancel and Save return to the sheet (system back hidden) | Owner's answer 1; same save/verify/remove/"Couldn't save" behaviour | Yes |
| Go to Today: sets tab 0 and pops the pushed page | Works pushed (today) and as a tab (after the switch) | Yes |
| Today's link now reads "Insights" | The page is called Insights; the link stays until the four-tab switch | Yes |
| 65 retired keys removed from all seven tables (the spec's list plus the old report and host strings), each only after no Swift source used it; "Expanded"/"Compact" stay (Today uses them) | Spec §10 | Yes |
| Translations: "Insights" as a stats word (Estadísticas, Einblicke, Statistiques, Estatísticas, Statystyki, İstatistikler, आँकड़े); "The week before" as "the 7 days before"; "Partly reported" reuses each table's "partial data" wording | A rolling period must not read as a calendar week; same terms as the existing tables | Yes — native speakers may refine |
| Polish/Turkish/Hindi "%d of %d days have full data." reorder as "Full data: %d of %d" | Their grammar can't keep the English order with one plural form | Yes |
| German abbreviations ("Min.") before a sentence's full stop collapse to one "." in `UsageFormat.format` | Seen in the synthetic German render ("42 Min..") | Yes |
| Turkish "Week" fixed to "Hafta" (was lowercase) | It's now a segment label | Yes |
| "Private by design" copy kept as approved ("Demora can't read, save or send it.") | The reviewer noted the app stores limit-reached flags; those come from threshold events, not the measured usage the sentence is about. Owner may prefer softer wording | Flag for owner |
| Synthetic preview fixtures: `initialSegment:` replaces `initiallyWeekly`/`initiallyShowingTrends`; modes added: noestimate, onlytoday, redaccent | Spec §8 fixtures for the three segments, app scope, no estimate and partial | Yes |
| Synthetic macOS renders (light/dark, English/German/Hindi, Day/Week/Trends, app scope, partial, empty, large type) | No iOS simulator runtime; renders check layout only, not iOS or report delivery | Limit |
| No visual check on a phone | No device in this session | Limit |

## Insights review fixes
A fresh reviewer read the whole Insights diff (32abd2a..d065979) with no conclusions from the build. Fixed in `ec80259`, each with a regression check:

| Bug | Fix | Test |
| --- | --- | --- |
| With an older week picked, the hero and Trends called the picked week "The week before" while the sentence compared it with the week before it | "The week before" now names the period right before the picked one | `UsageTrendsHarness`: picked week is never "The week before", its predecessor is, latest keeps "Last 7 full days", oldest has none (fails on the old naming) |
| Today's bar was drawn with the complete fill and no notch, and VoiceOver read only the minutes | `drawsComplete` uses `isComplete` (false for today); VoiceOver adds "Today so far" | `UsageTrendsHarness` native checks; `UsageDashboardHarness` source guard |
| Weekday names started sentences lowercase in Spanish, French, Portuguese and Polish ("jueves suele ser…") | Standalone weekday symbols, first letter capitalised | Native `sentenceStart` check and a source guard |
| Turkish segment label read "hafta" | "Hafta" | Localization check (regenerated snapshot) |

Not changed: the approved "Private by design" sentence (logged above for the owner).

## You build (2026-11-08)
| Decision | Why | Done? |
| --- | --- | --- |
| Steps built in the brief's order, one commit each: pure logic, You page, Skip the wait, receipts and detail pages, Help and Guide, duplicate removal | Each verified before the next | Yes |
| Pure logic in Latch/YouPresentation.swift; harness lifts the engine's real overrideCapability/hasOverride/classify by source extraction (no stub copies) | eligibility must match hasOverride exactly | Yes |
| Summary uses separate lowercase list-form keys ("schedules") after the first capitalised item | spec copy "Limits, schedules · extra time"; German keeps nouns capitalised | Yes |
| "Can't reach" chip uses StateChip .blocked (loosen ink, dot) | spec asks for loosen; .loosening would add an arrow meaning "looser" | Yes |
| ContactPermissionsPresentationHarness not extended: the new decisions need SharedModels and the engine capability map, which that sed/stub harness can't compile; YouPresentationHarness covers them | Brief: extend it where it fits | Yes |
| Contacts switch row shows when any contact row exists (saved or waiting to be added) | spec "≥1 contact"; a waiting contact added while paused also queues "turn on" | Yes |
| Add plan never queues the switch when any switch change is already pending | engine refuses a second change with the same conflict key | Yes |
| Fixed French "Protection" (was "Protection des personnes") and Turkish "koruma" → "Koruma" | used as a section/checklist label | Yes |
| Tapping a contact in the skip menu opens the request with that contact checked; others can be added | spec says all checked by default for the step; when opened from a specific row the tap is the choice | Yes — owner may check |
| Extra-time contact list now excludes paused/unaccepted contacts (shown before, failed on send) | same outcome, no dead end | Yes |
| Tab bar label stays "Settings" (FoundationsComponentsHarness guards five tabs); four-tab switch renames | | Interim |
| Step 2 (`562bc69`): You page behind tab 3; SettingsView root, notifications page, help hub, contact/roadmap pages and appearance grid deleted (replaced) | brief placement | Yes |
| `settingsPath`/`SettingsRoute` → `youPath`/`YouRoute`; `openSettings(to:)` removed (no caller) | spec §8 | Yes |
| Page title is plain `Text("You")` in `pageTitle` (like Rules), no wordmark | spec §5 "no wordmark"; DemoraPageTitle draws the wordmark | Yes |
| Empty state title/description split: "Nothing can skip a wait yet." / "That's the strictest setup." | EmptyStateView has title + description | Yes |
| "People you approve for" count fetched with grantsToMe on appear/refresh; shows no value until loaded | count lives on the relay | Yes |
| "Requests you sent" link shows with any saved contact or any sent history | spec: hidden when no contacts and no history | Yes |
| Delays tab: keeps title, tagline and DelayPolicyNavigationRows; its override section is one "Ways to skip a wait · Open You" row that switches to tab 3 (no invite dot there, Y7) | brief: Delays stays working until the switch | Interim — four-tab switch removes the tab |
| Today/Limits/Schedules "Help" links now open You's Help & guide page | HelpHubView removed; links stay until the four-tab switch | Interim |
| Guide/locale harnesses split the Guide at a new "// MARK: - Language" marker (the Contact page they split on was removed) | guard intent unchanged | Yes |
| Prevent disabling: Request access and the passcode look go through the receipt (same actions); "Enter passcode" stays immediate with the existing replace warning; status re-reads each second via TimelineView | spec §5.11; owner answer 3 | Yes |
| Prevent disabling waiting copy: new sentence "Access requested. It opens after your looser wait. Track it in Changes on Today…" | spec copy fix "track it in Changes on Today" | Yes |
| Appearance: theme tiles drawn with real tokens under a forced colour scheme; Text/Week segmented; colour swatches 44 pt; preview card is a static sample ("Evening block", "On until…", a countdown) | spec §5.8 | Yes |
| Footer Privacy link: https://getdemora.app/privacy-policy.html (the website's page); Word list credits reads the bundled WORDLIST_ATTRIBUTION.md, English | spec §5.7 | Yes |
| Added "%d words" to the five tables that lacked it | was untranslated in the phrase editor | Yes |
| Step 3 (`f8994c9`): SkipWaitSheet replaces OverrideGateView, PasswordChangeGate, PhraseChangeGate, ContactGateView, ExtraTimePasswordGate, ExtraTimePhraseGate and TutorialContactGateView (all deleted); MathGateView/PasswordGateView (retired, unused) left for step 6 | Y4 | Yes |
| The contact request/poll/verify/finish code, password hash+apply and phrase entry/apply moved into the sheet line for line; only layout and copy changed | brief: gate logic unchanged | Yes |
| Where the sheet opens is decided once when it opens (plan computed by the presenter) | steps must not jump when a change lands underneath | Yes |
| A sent request always reopens on its status, also for extra time when contacts were paused since | otherwise the waiting request would be stranded | Yes |
| Unreachable contacts and email contacts without email are listed but disabled, in the menu and in the request step | spec §5.13; before, unreachable contacts could be selected | Yes — stricter |
| Waiting step shows one status line ("Sent · waiting" / "Denied"), not one row per contact | the relay returns approved/denied for the request, not per contact | Limit |
| "Enter the code %@ received" names the email contact when exactly one was asked; otherwise the existing sentence | names unknown after resume | Yes |
| Phrase entry: "Word 12 of 100" in the time style, "%d mistakes left" when mistakes are limited (unlimited keeps "Mistakes: %d"); error haptic on a reset | spec §5.13 | Yes |
| Password field keeps .textContentType(.password) as before | gate unchanged | Yes |
| Translated eight older gate/extra-time messages missing from fr/pt/pl/tr/hi | they show in the new sheet | Yes |
| Step 4 (`41e7d00`): AddSkipWaySheet (choose → details → ChangeReceiptView pushed), SkipWayDetailView, SkipPermissionsChecklist, PasswordSecretChangeView, PhraseWordsChangeView | §5.9, §5.10, Y5, Y11 | Yes |
| Receipt extension: ChangeReceiptView (embeddable, several actions) + .changeReceiptBatch sheet; ChangeReceiptSheet left untouched (its guards) | spec §7 extension a+b | Yes |
| Batch receipt queues actions in order; a refusal after the first stays on the receipt with "Part of this was saved and is waiting in Changes…" and never re-queues a done part | engine has no dry run | Yes — owner may check |
| New contact form hides the type picker unless EmailCodeService.isConfigured (owner answer 2); duplicate check also covers contacts still waiting to be added | old form only checked saved contacts | Yes |
| Password plain text is hashed on Continue, fields cleared then and on disappear; going back from the receipt means typing it again | no plaintext kept in drafts | Yes |
| Contact may be narrowed to nothing (as before); a password or phrase needs ≥1 capability ("Choose at least one thing it can skip.") | engine rejects empty for those | Yes |
| Detail page disables the checklist, Change the words and Remove while a change to that item waits; "A change is already waiting" | engine refuses a second change (conflict key) | Yes |
| GrantProfileView "Add as trusted contact" now ends on the batch receipt (was a direct queue) | Y11 | Yes |
| PasswordPolicyEditor / PhrasePolicyEditor / AddContactView keep their (now unreachable) direct-queue paths: onboarding and the migration welcome use them with onStage/onAdd, and OnboardingOverridesHarness guards their structure | | Limit — onboarding spec should make staging required |
| Step 5 (`b62f699`): How Demora works = 4 static pages (TabView, symbols); no state, guard checks it | Y10 | Yes |
| Guide: 11 bodies + 2 topic titles/1 summary rewritten for Today/Rules/Insights/You; topic ids unchanged; harness now forbids old route names in the Guide | §8 | Yes |
| Also repointed: welcome line (:280), onboarding help/contacts lines, language update line, add-contact code hint — routes that this build removed | §8 | Yes |
| Not repointed (tabs still exist until the switch): onboarding "Limits & blocks", "Schedules → Day & night", Day & night "Wake up tap on Home" | onboarding spec / four-tab switch | Interim |
| Walkthrough: replayTutorial and beginTutorial deleted (nothing called them; `tutorial` is in-memory so nothing can resume it); replay recovery (restoreFromReplay on launch) kept for a replay interrupted in an older build | owner answer 4; brief: delete only if nothing can resume | Yes |
| Remaining tutorial branches (legacyHome, LimitsView, tutorial editors, Schedules tutorial routing, TutorialCallout/Blocker/FinishView, AppModel step machine, harness guards on them) stay for the four-tab switch, which retires those screens anyway | removing them touches Today/Rules/Schedules files and their guards | Interim — four-tab switch |
| 119 replaced strings removed from the seven tables after checking no source uses them | | Yes |
| Step 6 (`e86f704`): removed ExtraOverridesView, FineTuneOverridesView, PasswordPoliciesView, PhrasePoliciesView, OverridesGridView, RulesGridView, DelaysGridView, ContactsOverrideEditor, ContactsHubView, ContactsDetailView, TrustedContactApprovalRow, ContactProfileView, EmailContactProfileView, ContactApprovalSummary, ContactPermissionsEditor (view), PreventDisablingGateView, PreventGuideGateView, PasscodeHubView, PasscodeViewGateView, MathGateView, PasswordGateView, MathOverrideEditor, PasswordOverrideEditor, queueSection, DelayEditorView, addTutorialContact; 108 strings only they used left the tables | §8, once nothing routed to them | Yes |
| **Still on the Delays tab for the four-tab switch to remove:** `DelaysOverridesTabView` (title "Delays & overrides", tagline, `DelayPolicyNavigationRows` — a duplicate of Rules → Your waits — and one "Ways to skip a wait · Open You" row); tab 4 in `LatchApp`; the "Delays" item in `DemoraTabBar`; the old dotted-separator request in `CLAUDE.md` goes with `DelayPolicyNavigationRows` | brief placement | Interim — four-tab switch |
| **Walkthrough remnants for the four-tab switch:** `HomeView.legacyHome`, `LimitsView` and `TutorialLimitEditorView`, `TutorialScheduleEditorView` and the Schedules tutorial routing, `TutorialCallout`/`TutorialBlocker`/`TutorialDemoBanner`/`TutorialFinishView`, `tutorialHighlight`/`TutorialHoleKey`/`TutorialCountdownText`, `AppModel` step machine (`tutorial`, `advanceTutorial`, `freezePending`, `skipTutorial`, `finishTutorial`), the onboarding overlay line "It's always available again in Settings → Help.", and the harness guards that keep them | nothing can reach them; they share files and guards with the legacy tabs | Interim — four-tab switch |
| Tab 3 keeps the "Settings" label and slider icon; the invite dot already sits on it (Y7) | FoundationsComponentsHarness guards the five-tab bar | Interim — four-tab switch |
| `ContactPermissionPresentation` stays in `ContactPermissionsEditor.swift` with no caller | the verify command compiles it from that file | Limit |
| Synthetic renders not made; no simulator, no device | | Limit |

## You review fixes
A fresh reviewer read the whole You diff (d7dd92e..e86f704) with no conclusions from the build. It found no new way to bypass a wait, no secret leakage and no gate that skips verification. Fixed in `17ec17f`, each with a regression check in `YouPresentationHarness`:

| Bug | Fix | Test |
| --- | --- | --- |
| After a contact request was sent, Apply now opened on the request and the password/phrase for the same change were unreachable | Only "Waiting for…" (`SkipWaitTarget.request`) reopens on the status; Apply now always shows every eligible way (the contact step still resumes the sent request) | Pure: a sent request with a password still opens the menu; source: ledger and Today use `.request(` only for Waiting for… |
| The sheet's plan was recomputed on every state refresh, so the root could swap under a pushed step or drop a typed password | The plan is computed once when the target is set and kept with it (`PresentedSkip`) | Source: `plan(for:)` called once, in the target's `onChange`; the sheet presents `presented` |
| After Save changes → Confirm, the checklist showed the queued permissions as if live | The receipt's `onQueued` resets the checklist to the current permissions | Source guard |
| "Changes to your ways to skip a wait can never be skipped." was false: the engine maps adding, removing and pausing contacts to `.contactChanges`, so a way allowed "Trusted contacts" can skip them | Copy now says "Changes to passwords, phrases and what anyone may skip can never be skipped early."; engine unchanged (brief) | Guard: the old sentence can't return |
| (Found while fixing) You's `onReceive(model.$state)` read the state it was about to replace | Reads the published value | Source guard |

Not changed: a new phrase defaults to 0 allowed mistakes — the reviewer thought this was new, but the old editor also set 0 for new phrases. **Owner decision:** should adding/removing/pausing contacts stop being skippable (engine returns no capability for them), and should new contacts stop getting "Trusted contacts" by default? Both are engine/model changes outside this build.

## Independent You verification — 2026-11-08

Scope: `4492d82..7be509d`, including the first commit's changes (compared
against `d7dd92e`), and the handoff at `5c5c502`. No new feature build is part
of this checkpoint. The lead read the approved plan, all six specs and this
log. A separate read-only reviewer audited the You/request/receipt flows,
then re-reviewed the corrections without writing them.

| Decision / finding | Why | Done? |
| --- | --- | --- |
| Leave `AppAttest.swift` untouched | Contrary to the handoff suspicion, the file has the identical Git blob at `d7dd92e`, `7be509d` and the handoff HEAD (`bf09932454f25633ed0ffa2365ab84ee9eff93d5`). No commit in the You range changes it. Its last change is the pre-existing July recovery fix `48187ef`; reverting that would change production email behavior | Verified, no patch |
| Remove five newly introduced `.password` / `.newPassword` hints from the add and secret-change forms | These forms had no such hints before You. Keep the two SecureFields/three SecureFields, hashing, validation and clearing unchanged. The skip gate's `.password` hint existed in both old change and extra-time gates, so it is retained, not silently changed | Fixed; source regression detects all five original hints |
| Remove the new standalone `Next` entries in six catalogs, keeping the original inline translations | `b62f699` added a second key in German, French, Portuguese, Polish, Turkish and Hindi. Swift warns, but a dictionary initializer can trap at runtime. The old whole-line regex missed `"Now": …, "Next": …` | Fixed; scanner detects every old duplicate, plus a warnings-as-errors native check compiles and initializes all seven real dictionaries without app preferences |
| Keep sheet navigation fixed, but revalidate contact recipients against current consent/scopes | The opening plan captured contacts even after removal, revocation or pause. Choice rows now follow current eligibility; Send reads persisted state and rechecks after async registration/email work before disclosing the relay request. Only the actual relay-recipient subset is recorded. No engine authorization or relay protocol changes | Fixed; pure current-recipient tests cover removal, revocation, pause, consent, extra-time scope, updated identity, reachability, a newly added contact and one/all recipients removed during suspension; source guards cover send/recheck/record wiring |
| Ignore remembered collapse state at twelve rows or fewer | At thirteen rows a user could collapse a kind; after a removal the expand header disappeared but its rows stayed hidden | Fixed; native large → small/empty regressions and view wiring guard |
| Show Requests you sent independently of an empty ways list | Removing the last way must not hide retained sent history | Fixed; source guard checks the link is outside both list branches |
| Clear a previous passcode reveal when the entry sheet closes, on Save or Cancel | Otherwise replacing a passcode left the old secret labelled Saved passcode. Clearing even on Cancel matches the old separate-screen lifetime conservatively; neither new nor old passcode is revealed automatically | Fixed; source guard checks the dismissal callback, no storage/gate change |
| Keep the contact-capability/default-permissions decision deferred | The owner requires asking before engine/model changes. This checkpoint changes no classification, delays, accounting, contact service, App Attest, schema, signing configuration or environment identifiers | Preserved |

Re-review found no further concrete regressions in these patches. Native
presentation tests and source guards do not simulate a real suspended CloudKit
send or interactive iOS passcode sheet. Device follow-up for this checkpoint:
switch to each beta language; add/change a password; revoke one/all selected
contacts before Send and during registration; collapse 13 ways then shrink to
12; remove the last way with history; reveal → replace/save and reveal →
entry/Cancel. Both passcode cases must require a new delayed viewing request.

Verification rerun: all **29** `Tests/*Harness.py` passed, including **3,748**
You checks (3,360 eligibility comparisons against the extracted real engine).
Both standalone Swift harnesses passed (phrase challenges; contact presentation,
9 assertions). Generated report localization matches 67 keys × seven tables;
the actual seven app translation dictionaries compile with warnings-as-errors
and initialize safely. The improved scanner detects all six duplicate keys in
the original You revision; Swift rejects the original French table under
warnings-as-errors. The new autofill guard detects the original five hints.
`git diff --check` passed. Full-run output: `/tmp/demora-takeover-full-verify.log`.
The runner now retains failure status rather than turning a failed harness into
a successful `echo`, and the handoff command follows that behavior.

Final unsigned arm64 **Debug and Release builds both passed**, sequentially,
using stable Xcode 27.0 (27A266a). Debug emitted no warnings; Release emitted
only the skipped AppIntents metadata extraction warning. The built Release
bundle identifies as `demora` / `may.latch`. Logs:
`/tmp/demora-takeover-debug.log` and `/tmp/demora-takeover-release.log`.
These builds do not establish TestFlight startup, production App Attest,
CloudKit round trips or interactive iOS behavior. No engine/model/service,
project/signing, identifier, version or build-number changes were made.

Signed Debug also passed (same metadata-extraction warning; log
`/tmp/demora-takeover-signed-debug.log`). Verified the signed host and all four
embedded extensions use the development App Group and `may.latch.dev` bundle
family; the report remains in its dedicated `Extensions` destination. Installed
successfully on **iphone de may** as **dev demora**. Launch was refused by iOS
because the phone was **Locked** — this was a device launch denial, not an
observed app crash. No interactive phone check or live contact/email round trip
was performed. The owner can unlock the phone and open the installed dev app;
the App Store app remains separate. Nothing was pushed, merged or submitted.

## Setup, intro and welcome build — 2026-11-09

First step of `docs/onboarding-shield-widgets-redesign.md`. Shield, widgets,
dead beta/language-screen cleanup and the tab switch are separate following
steps; this build does not claim them complete.

| Decision | Why | Done? |
| --- | --- | --- |
| Five setup steps; optional mornings/nights and ways-to-skip sheets on Make it yours, followed by the summary | Approved O1/O2: preserve every choice and the one-time setup benefit without treating extras as required pages. Drafts remain in the parent view and invalid groups/overrides still prevent the final commit | Yes |
| Preserve permission text verbatim, Continue, the single authorization path and denial-then-Continue behavior | Apple-sensitive copy and 5.1.1(iv); beta-language notices remain a separate tap from permission requests and final saving | Yes |
| Use the shared selected-card delay picker and existing wheel bindings | Same policy edits and validation, clearer selection; durations are inside the selected card. The picker is also used by Your waits and local migration previews | Yes |
| Fresh/upgrader intro variants derive only from the published isSetUp value; demos explicitly choose their variant | O3: fresh users never see 2.0 or an upgrade slogan. Timing, intrinsic wordmark reveal, accessibility/cancellation and intro completion marker remain unchanged | Yes |
| Welcome uses stable rules/dayNight/changes page identities, not mutable array offsets | An optional day/night offer disappears after a successful save. Advancing explicitly to Changes prevents skipping/duplicating a page when the array shrinks. Back remains useful if eligibility changes; all saves/Skip still use the existing one-shot guards | Yes |
| Math replacement appears once, on the first welcome page; final page offers the ordinary delayed policy editor | O4: no duplicated offer, no new waiver. The demo still opens only a local policy draft | Yes |
| Optional estimate is collapsed in setup and welcome | O6: the existing draft persists only after the original successful setup/welcome path, not when expanded or edited. Demos cannot save it | Yes |
| Summary uses localized category labels plus counts, hiding zero kinds and using Not yet when empty | Avoids “1 contacts” and incorrect plural forms; translated labels work without inventing plural rules for Polish and other languages | Yes |
| New setup titles omit the repeated logo; optional actions explicitly use plain text, progress is a 4-point capsule, successful setup gives a haptic only after saving succeeds | Approved presentation; one primary action remains pinned. No implicit page animation or added authorization prompt | Yes |
| Restore missing Passwords translations in all seven catalogs and Phrases in five | The broader setup-copy guard exposed pre-existing omissions; current setup/intro/welcome/math copy is checked across 121 keys × seven catalogs | Yes |
| Existing five-tab route copy stays temporarily; four-tab descriptions land with the actual switch | Spec §8 requires truthful paths at each integration point. The welcome introduction uses an interim Your setup header, not “Four tabs now” before the switch | Interim — four-tab switch |
| Staging callbacks and initial/migration commit APIs are unchanged | No engine/model/service, deadlines, accounting, markers, waiver or contact-policy changes are authorized here. Existing real drafts, consent validation, retry behavior and demo isolation remain | Preserved |

A fresh read-only reviewer checked the step and rechecked the summary/layout/
translation refinements without writing them; no concrete functional regression
was found. The lead inspected native macOS synthetic renders of the actual
setup body/components in light/English (390 pt), dark/red/German (320 pt) and
Hindi (320 pt). These are not iOS screenshots or proof of device Dynamic Type,
VoiceOver, permission prompts or sheet transitions. The fixture uses no real
rules, tokens, usage, preferences or contact services; its saved group names and
delay string are synthetic. `Tests/RenderSetupPreview.py` reproduces the renders.

Final verification: all **30 Python harnesses**, both standalone Swift harnesses,
generated report localization (67 keys × seven tables) and `git diff --check`
passed. Setup adds 26 pure page-identity/routing checks; intro keeps its 16 gate
combinations, phase timings and intrinsic glyph/layout checks. The complete
setup/intro/welcome/math key scan covers 121 keys × seven catalogs. Existing
initial-setup/migration, waiver, permission, demo-isolation and enforcement
regressions remain green; no engine/model/service files changed.

Sequential unsigned arm64 Debug and Release builds passed with stable Xcode
27.0 (27A266a), followed by signed Debug. Debug emitted no warnings; Release
and signed Debug emitted only skipped AppIntents metadata extraction. Logs and
synthetic PNGs are now under
`/Users/matiasmoran/Library/Logs/DemoraRedesign/` (`onboarding-verify.log`,
`onboarding-debug.log`, `onboarding-release.log`, `onboarding-signed-debug.log`,
`setup-light.png`, `setup-german-dark.png`, `setup-hindi.png`), rather than the
cleared temporary directory. DerivedData is outside the repository.

The owner's iPhone was **unavailable** on 2026-11-09, so this step was not
installed or interactively checked. When connected, install the signed Debug
artifact and try You (still labelled Settings) → Developer → Setup demos:
New-user (five pages, both permission responses, optional extras, Back and
estimate), then migration (math offer once, 2/3 pages, Skip, day/night save,
delayed policy editor). Demos must never change real rules or welcome markers.
Fresh-install permission sheets, iOS large text/VoiceOver, the pinned footer and
extras' pushed editor dismissal remain device checks. Nothing pushed or merged.

## Generic shield build — 2026-11-09

Phase 1 of O7–O9 only. Rule names/end times remain behind the signed-device
token-equality spike; the widget's overall active rule cannot identify what
blocked a particular app.

| Decision | Why | Done? |
| --- | --- | --- |
| Solid paper/ink, bounded 56-point original Demora mark, generic explanation and Close | Remove the obsolete immediate-unblock promise; all four application/category/domain callbacks return the same honest display | Yes |
| Read only the configuration-specific App Group accent, not the saved rules | Display must not call `SharedStore.loadState()` (recovery writes), inspect private tokens, or change enforcement | Yes |
| Paper-colored primary label rather than the proposal's literal white | White fails AA against the pale dark-mode accents. The matching light/dark paper foreground passes on both accents, as in app foundations | Yes |
| Reuse the unmodified app PNG in the extension's own synchronized catalog; thumbnail and SF Symbol fallback | The extension cannot read the host catalog; no new target/project/signing change is needed | Yes |
| Translate the generic copy and correct Turkish Close from “near” to the action Kapat | Seven catalogs plus English fallback; keep the shared action semantically correct | Yes |
| No secondary button, action extension, instant grant or guessed rule details | Approved phase-1 scope, not an enforcement or capability change | Preserved |

Fresh independent read-only review found no concrete bugs. The built Debug
`LatchShieldUI.appex/Assets.car` contains DemoraLogo; its source bytes match the
original SHA-256. `WidgetShieldPresentationHarness.py` checks five exact
foundation palette pairs, eight AA contrast pairs, all four callbacks, read-only
accent/group selection, asset identity and four strings × seven catalogs.
The full **31 Python harnesses**, both Swift harnesses, generated report
localization and diff checks passed (`shield-verify.log`). System trait
propagation, logo sizing/tint, localized wrapping and default Close behavior
remain signed-device checks, not established by source guards or compilation.

API references: [ManagedSettingsUI](https://developer.apple.com/documentation/managedsettingsui),
[shield blur](https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration/backgroundblurstyle),
[primary button fill](https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration/primarybuttonbackgroundcolor).

Sequential unsigned arm64 Debug and Release passed (`shield-debug.log`,
`shield-release.log`). Debug emitted only the skipped AppIntents metadata
warning; Release emitted no warnings. These are compilation checks, not the
token spike or proof of system shield behavior. No engine/model/service,
project/signing or version changes, and nothing pushed or merged.

Signed Debug also passed with only skipped AppIntents metadata extraction;
`codesign --verify --deep --strict` passed. The phone appeared paired, but the
install connection was reset and launch could not acquire device services.
This shield build was **not installed or interactively verified**. When the
phone is connected, try light/dark and blue/red, a blocked app and website,
German/Hindi wrapping and Close. Use existing rules; do not reset state for
the check. This does not complete the separate token-equality spike.

## Widget display and navigation build — 2026-11-09

O10–O12 implemented; O13's live wake observation remains **deferred pending
owner approval** of a read-safe engine boundary. The optional schema and
renderer support a wake interval, but every live publisher currently writes
nil. Do not describe the reminder as enabled.

| Decision | Why | Done? |
| --- | --- | --- |
| Paper/card/ink, the chosen blue/brick accent, serif rule names/times and system labels | Match foundations without compiling the host theme/engine into widgets. Ten palette pairs and 22 AA text/background combinations are checked | Yes |
| iOS 17 container background/system margins; padded iOS 16 fallback | Adopt WidgetKit's presentation rather than baking a navy rectangle behind it. Accessory families have no painted card background | Yes |
| Small/medium Now & next and Changing soon; inline/rectangular Lock Screen families | Same existing widget kinds/configurations, no interactive intents or new target. Only the app may act on rules | Yes |
| Optional style/direction/copy fields; old snapshots decode with nil styles/directions and no guessed chip | Add presentation semantics without changing the persisted rule schema or breaking installed widget configurations | Yes |
| Empty Now copy stays No timed rule active rather than Nothing blocked | The projection does not contain every permanent general or sleep block; absence of a timed item is not evidence all apps are available | Yes |
| Next shows a future start or change, not the current item's end again | Until already displays that end. End boundaries remain timeline entries, so they still trigger a display transition | Yes |
| Names/summaries and combined accessibility groups marked privacy-sensitive | Keep private user-written rule content inside the system redaction boundary. Actual Lock Screen redaction remains a device check | Yes |
| Loading placeholders are redacted; gallery snapshots are readable, synthetic and never load saved rules | A useful preview must not be a permanent skeleton or disclose real configuration | Yes |
| Four gallery strings generated from the seven existing dictionaries plus English | Gallery metadata follows system language; published copy follows the in-app language. Generator checks inline entries, duplicates and format placeholders | Yes |
| Separate demora-dev / demora URL schemes, only today/changes hosts, no query/path/fragment/user/port/foreign scheme | Route to a specific screen without IDs or mutation commands. Setup/recovery/tutorial gates remain in place | Yes |
| Today owns an explicit navigation path; widget taps reset transient Home and ledger UI | Opening Today/Changes must not restore an unrelated report, approval sheet or alert. No Home .id/remount, saved cancellation or rule action | Yes |
| Accent changes request widget timeline reloads | Read-only palette preferences need a refresh request; the system still controls render timing | Yes |
| Defer new wake publishing rather than calling status readers from the snapshot or publishing cached full UI state | Those readers can repair clocks, degradation or split readiness. A cached Home publication can overwrite newer monitor data; copying private runtime formats would create a second semantics implementation | Owner approval requested |

A fresh independent read-only reviewer found a retained ledger override modal
and a retained Home alert on repeated widget navigation; both now reset using
an explicit transient ledger token. These changes never cancel/apply saved
requests. The reviewer also identified permanently redacted gallery snapshots;
only loading placeholders now redact. Lead inspection of synthetic native
macOS renders caught a truncated Looser chip; fixed horizontal chip sizing and
allowed the heading to wrap. Re-review found no outstanding actionable issue.

`WidgetShieldPresentationHarness.py` compiles the **actual snapshot** with
WIDGET_EXTENSION for both Debug and Release: 40 checks each, including legacy
decoding, nil directions, future starts, overlaps/free/spent/empty, fifty
unordered changes, deduplicated transitions, current-day wake support and DST
23/25-hour midnights/first repeated ceilings. Wake test data is synthetic, not
evidence of live publication. Source guards cover family/configuration
stability, read-only preferences, privacy, no engine/network/interactive paths,
separate schemes, bounded URL parsing, transient navigation resets and gallery
preview/loading separation. The Home lifetime fixture was updated for the
new binding and still proves the actual root retains Home on seven switches;
no weakened lifecycle assertion or report remount was introduced.

`Tests/RenderWidgetPreview.py` reproduces the inspected English/light,
German/dark/red and Hindi/light layouts. It excludes the provider, substitutes
fixture-only color/family environments (accessory families are unavailable on
macOS), and never loads real preferences/rules/usage. These are **not iOS
WidgetKit screenshots** or proof of system margins, tint, traits, live timeline
delivery, Lock Screen privacy, Dynamic Type or VoiceOver behavior.

References: [widget backgrounds](https://developer.apple.com/documentation/widgetkit/displaying-the-right-widget-background),
[widget privacy](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension),
[navigation links](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity).

Final verification: all **31 Python harnesses**, both pre-existing standalone
Swift harnesses, the actual widget model's 40 checks in each build environment,
both generated-localization checks and `git diff --check` passed. The first
full run exposed a native Home-lifetime fixture missing the new binding; its
stub now models that binding and all original retention assertions still run.
Logs are in `/Users/matiasmoran/Library/Logs/DemoraRedesign/`:
`widget-verify-final.log`, `widget-debug.log`, `widget-release.log`,
`widget-signed-debug.log` and the three `widget-preview-*.png` fixtures.

Sequential unsigned arm64 Debug and Release passed with no warnings, followed
by signed Debug (only skipped AppIntents metadata extraction).
`codesign --verify --deep --strict` passed. Built host Info.plists contain only
their own navigation scheme and retain **dev demora** / **demora** names; the
widget bundle contains all eight compiled Localizable.strings resources.
No enforcement, saved-rule model/store, AppModel, AppAttest or contact-service
file changed. Project changes are only the two host navigation-scheme values;
no signing, entitlement, target, dependency or version changes.

Installed successfully on **iphone de may** as `may.latch.dev`; launch was
denied because the phone was **Locked**, not an observed crash. This combined
artifact includes the setup and generic-shield steps, but their interactive
checks remain unperformed. No production email/contact round trip was sent.
Nothing pushed, merged, uploaded or submitted.

When unlocked: add both Home Screen sizes and Lock Screen families; try the
blue/red accent in light/dark, long German/Hindi names, empty/pending states,
system tint and sensitive-content redaction. Tap each widget from another
tab, from Today → Insights/Help, and while a Changes override sheet or alert
is open. It must land on Today/Changes with no stale modal and without acting
on a rule. Confirm the co-installed App Store app does not open. Then check
the generic shield/Close and Setup demos described above. No reset of saved
rules, markers, authorization or real device data is required for these checks.

## Read-only wake reminder follow-up — 2026-11-11

Owner approval: 2026-11-10, narrowly scoped read-only wake-status APIs and a
post-wake widget refresh, with no change to waits, blocking or wake behavior.
This is separate from the verified `da9b6d3` pushed to origin/main at the
owner's one-off request for Xcode Cloud. No later push is authorized.

| Decision | Why | Done? |
| --- | --- | --- |
| Add display readers in TimeGuard, GlobalWake, DayNightWake and LimitFeatures, beside their owning keys/types | Reuse runtime formats without calling repair-capable readers or copying schemas into the widget. Unreadable relevant runtime is unknown; valid absent first-cycle state remains untapped. Reads never anchor clocks or change warnings, readiness, usage or deadlines | Yes |
| Keep existing enforcement bodies byte-for-byte; add only the approved refresh after the shared Wake up finishes shield work | Reminder refresh is not a second wake implementation. The exact baseline-restoration guard protects all four engine files | Yes |
| Serialize widget publications on a separate display lock, decode current saved bytes inside it, recheck bytes before writing, and reload WidgetKit after releasing it | Never republish an old UI model; reject a known interleaving save. This does not prove cross-process UserDefaults visibility or OS delivery | Yes |
| Only this local day's untapped intervals, including starts later today, bounded by ceiling/midnight | No forecast of tomorrow's tap. Waiting or completed gates never request another tap; separate intervals preserve gaps | Yes |
| Omit a gate on a day when its configured start has different first/last occurrences | Fresh review found the existing minute predicate can go inactive in a repeated hour. Conservative display omission preserves enforcement rather than inventing a continuous interval | Yes |
| A reminder describes a configured untapped gate, not enforcement health | A failed unrelated monitor does not mean awake. The broad degraded-flag filter was removed after review distinguished that policy from a false needsTap; no general engine callbacks were added | Yes |
| Recovering/unreadable saved state only clears the optional wake observation | Never manufacture an empty setup or overwrite saved rules. Widget taps remain navigation-only, and free periods retain display precedence | Yes |

Fresh independent review found and rechecked the repeated-hour issue; after
the conservative fix and clarified health contract, no actionable production
finding remained. The same reviewer inspected the new publication harness's
fixture boundaries and coverage without writing or executing it.

Final checks: all **33 Python harnesses**, both existing standalone Swift
harnesses, both generated-localization checks and diff checks passed. The
actual read-only readers/status/tap bodies pass **903 assertions per build
environment**; the actual publisher/projection passes **742 per environment**.
The latter uses thin model/reader fixtures and deterministic coordination, not
actual enforcement or cross-process locking. Reader tests preserve preferences,
runtime bytes/mtime, flags and effect counts and include positive controls for
the original repair behavior. Three unfinished fixture errors were corrected:
an injected self-referential clock, an optional dictionary initialization and
calling the valid empty UUID-map encoding corrupt. Floating-point epoch
round-trip expectations use a 10-microsecond tolerance; the comparison with
the actual original clock remains exact. Existing day/night assertions remain
unchanged; its fake defaults gained the read-only object lookup needed to
compile the added API.

Stable Xcode 27.0: sequential unsigned Debug/Release and signed Debug passed.
Final unsigned builds had no warnings; signed Debug had only skipped AppIntents
metadata extraction. Deep/strict signature verification passed. Logs live in
`/Users/matiasmoran/Library/Logs/DemoraRedesign/`, prefixed `wake-`, including
`wake-verify-final-2026-11-11.log`. No version, signing, entitlement, target,
CloudKit, email, approval-policy or saved-rule-schema changes.

Device checks still required: actual WidgetKit delivery after a tap, foreground
and midnight; current/future-today groups with different ceilings; after-tap
waits surviving relaunch; overlapping free periods; protected-file reads and
cross-process preference visibility. Static widget snapshots cannot guarantee
instant update, and the reminder is not evidence that blocking is healthy.
There is no simulator runtime installed; no iOS UI verification is claimed.

Installed this combined dev build successfully on **iphone de may** as
`may.latch.dev`. iOS denied launch because the phone was **Locked**; this was
not an observed crash. Unlock and open dev demora to perform the device checks.
No production contacts/emails were sent. Nothing pushed or uploaded in this step.

## Four-tab switch (2026-11-11)
Codex started this step and left it uncommitted (36 files); Claude audited it
against foundations §7, rules §5.8/§8/R10, insights §8, you §8/Y7/Y10 and
onboarding §8/O4/O5, finished it and split it into commits that each pass
verify and an unsigned Debug build (intermediate states were built in a
detached scratch worktree; this checkout was never reset or stashed).

| Decision | Why | Done? |
| --- | --- | --- |
| Tabs Today · Rules · Insights · You (tags 0–3), spec icons, never locked, labels wrap at large text | foundations §7; the lock only served the tutorial | Yes |
| Today dot = approval requests waiting; You dot = invites (Y7) | spec; the old Today dot counted pending changes | Yes |
| Off Today, the root polls the same read-only `pendingRequestsForMe` every 30 s while active; Today polls only while visible | the dot must appear on other tabs; one poll at a time | Yes |
| Insights is a retained tab built on first visit (like Today), hidden copies take no taps/VoiceOver; About closes on any tab switch | keep the private report alive across tabs; a widget must not land under a stale sheet | Yes |
| Insights/Help links left Today; Full day opens the Calendar as a sheet from Today | tab 2 now means Insights; Help lives in You | Yes |
| Legacy tutorial deleted (step machine, frozen countdowns, highlight/blocker/callout/banner/finish, tutorial editors, contact tutorial mode, intro-gate flag) | R10/Y10/owner answer 4: nothing could start or resume it | Yes |
| `restoreFromReplay` kept byte-for-byte minus two UI assignments; still runs at launch and on retry. `LegacyReplayRecoveryHarness` compiles the real body (10 scenarios, 90 assertions) and pins every other AppModel method to `2732883` | a replay interrupted in an older build must still get its real setup back | Yes |
| **Restored** `debugFullReset` (DEBUG only; only the two tutorial assignments removed) | Codex deleted it while You → Developer still called it: Debug did not compile | Yes |
| **Restored** the language-change rebuild (`.id(model.language)` on the tabs, not on tab switches) | Codex dropped it; child views that call `tr()` in their own body would keep the old language. Paths that must survive (You) live in AppModel; reports re-query on language change anyway | Yes — owner may check |
| Calendar restyled with tokens, 44 pt day cells/arrows, horizontal scroll instead of shrinking at large text; a new harness guard covers it | rules §5.8 known limit | Yes |
| Calendar restyle committed with the tutorial retirement | same struct and file as the retired Schedules page; splitting would need a hybrid never-shipped version | Limit |
| Removed dead screens: SchedulesView page, LimitsView/LimitRow, Delays tab, Day & night list (`DayNightSchedulesView`), Group wake-up list (`WakeScheduleView`, `GroupWakeAction`), `RecurrencePicker`, `DemoraDayLine`, `DemoraTimelineMark`, beta-thanks and language-update screens (O5) | only after checking nothing routes to them; their rules stay reachable from Rules and the summary sheet | Yes |
| CloudKit container constant moved into `ContactsRelay` (same `iCloud.may.latch`); `latch.languageExpansionUpdate.shown` writes untouched | O5 | Yes |
| Welcome: "Four tabs now" with one self-labelled line per tab (title no longer repeated); "Rules → Day & night", "later in Rules", "Wake up tap on Today" in all eight languages; replaced keys removed | O4 / onboarding §8; spec copy already names the tab | Yes |
| New Guide-harness guard: no visible `tr()` string may name a retired tab | stops the old routes coming back | Yes |
| Orphaned catalog keys from deleted screens not pruned | ~380 keys aren't found literally in source, but some are used through variables; pruning needs its own careful pass | Limit — follow-up |
| No engine, enforcement, monitoring, persisted schema, contacts/email/App Attest service or signing change | brief | Preserved |

## Four-tab switch review fixes
A fresh reviewer read the whole uncommitted diff with no conclusions from the
lead. It found no engine/schema/Release-separation change, no lost route to a
pending change, and no migration regression (nothing at `2732883` ever set
`tutorial`, so every `tutorial == nil` branch was already the live one).
Fixed in `afcf685`, each with a regression check:

| Bug | Fix | Test |
| --- | --- | --- |
| "Waiting for …" rows (Changing soon, Changes) appeared only after a CloudKit fetch returned; offline, they were missing for a long time | Today reads outgoing requests locally on appear and before each fetch | `HomePresentationHarness`: local read precedes `loadInbox`, and runs on appear |
| Today → Full day → a limit → **Get extra time on Today** left the Calendar sheet covering Today | `AppModel.openToday()` (navigation only) bumps `todayRequest`; Today closes its Calendar on it | `RulesPresentationHarness` guard |
| The Today dot could disagree with Today's rows (rows lost on a language rebuild, dot kept) | one in-memory list `AppModel.approvalInbox` feeds both; a failed fetch keeps it | `HomePresentationHarness` runs the real loader against it; `HomeReportReliabilityHarness` root guard |
| An offline invite fetch cleared the You dot | keep the last count on failure (AppModel and You) | `LegacyReplayRecoveryHarness` allows exactly this one-line change |
| Tab dots were colour only for VoiceOver | `accessibilityValue` "Approval request waiting" / "Invite waiting", all eight languages | `FoundationsComponentsHarness` guard |
| (Recheck) The DEBUG reset left old approval rows/dot in memory | `debugFullReset` also clears `approvalInbox` | `LegacyReplayRecoveryHarness` allows exactly that line |

The same reviewer rechecked the fixes and found no new high or medium issue
(it also caught a trailing space that would have failed `git diff --check`).
Left as limits: while offline for over an hour, kept rows can outlive the
relay's one-hour request lifetime until the next successful fetch (pruning
needs the TTL exposed from `ContactsService`, which this step doesn't touch);
Calendar → summary → **Get extra time on Today** closes two stacked sheets in
one update, so it is a device check (Start here step 3). If the Calendar stays
up, close it from the summary's `onDismiss` instead.

Final verification on `afcf685`: all 34 Python harnesses, both Swift
harnesses, report (67 keys × 7) and widget (4 keys × 8) localization checks,
full-catalog duplicate/placeholder check and `git diff --check` passed.
Sequential unsigned arm64 Debug and Release with stable Xcode 27.0 (27A266a)
succeeded with no warnings; signed Debug succeeded (only the usual skipped
AppIntents metadata note) and passed deep/strict signature verification, with
bundle `may.latch.dev` named **dev demora**. Each earlier commit
(`748c488`, `9a7d236`, `f061030`, `5cc01b1`) also passed the full verify and an
unsigned Debug build on its own. Install on **iphone de may** failed because
devicectl reported the device **unavailable** (not connected), so nothing was
installed or launched. Nothing pushed, merged or uploaded.

## When & where step 1 (2026-11-11)
Step 1 of the approved `docs/conditional-sessions-redesign.md` (C15: model +
engine + capacity + harness). No UI, no CoreLocation, no Info.plist change.
Evidence: `Tests/WhenWhereHarness.py` compiles the real models, evaluator,
start plan, `MonitoringBudget`, `SchedulePrecedence` and the complete
production `classify`/`summary`/`conflictKey`/`queue`/`queueCoordinated`/
`apply`/`applyDueChanges` and the new entry point with stubbed storage, clock,
monitors and tokens; a second binary compiles `SharedModels.swift` at
`b188742` and decodes blobs written by the new code. Nothing device-level is
proven (callbacks, real fixes, iOS capacity).

| Decision | Why | Done? |
| --- | --- | --- |
| All pure When & where code (rule model, evaluator, per-day uses, time-zone record, start plan, summaries) lives at the end of `Shared/SharedModels.swift`; the engine glue is in `ChangeEngine.swift` | Eight existing harnesses compile `SharedModels.swift` alone and `ScheduleSelectionHarness` compiles the real queue/apply; a new file would have meant editing them ("keep passing unchanged") | Yes |
| New saved fields are optional storage (`conditionalRuleStore`, `conditionalUseStore`, `timeZoneEvidence`, `BlockSchedule.ownerRuleID`, `BlockSession.conditionalRuleID`) behind non-optional accessors | A state without the feature encodes exactly the old keys; older builds ignore the new keys | Yes — harness checks the key set and decodes with `b188742` models |
| An older build can't decode a state holding a **pending** When & where change (unknown action) and enters the existing recovery state (raw blob kept, nothing lost) | Same as every earlier added action (e.g. day/night groups). App Store can't downgrade; TestFlight can | Limit — owner's eye |
| Free-time start: one pure `ConditionalStart.plan` validates at the entry point, inside `queueCoordinated` (the only zero-delay path) and again at apply. Any failure returns nil: no delayed fallback, nothing to override | Spec §5.8, C2, Q3 | Yes |
| Place/country results reach the engine only as the check-in stamp's booleans (no coordinates); day/time/dates are re-evaluated at queue and apply and must agree with the stamp | C8: the engine never sees where the user was | Yes |
| Stamp valid ≤ 2 min (5 s skew), same day key, zone and rule revision; each check-in ID can start once (kept with the day's uses) | §5.5 step 7, §5.6 "two checks racing" | Yes |
| Every start (place-only included) is refused while wall and guarded clocks differ by > 300 s | Sessions end on the wall clock; a changed clock could stretch one | Yes |
| Time zones: recorded with the rule, at check-in and in housekeeping (one write only on a change, only while rules exist). Every zone seen in the last 12 h must agree; a change not yet recorded counts as just now. **The daily cap uses the same rule**: a use counts under each recent zone's day key | §5.6; without the cap part, switching zone across midnight would reopen a spent day | Yes — the cap extension is worth the owner's eye |
| Use records are kept 72 h, pruned on rollover; counts never decrease or refund | A day key can stay "today" in some zone for ~50 h | Yes |
| Session end: all-of → earliest end of its day/time/date conditions; any-of → latest end of the met clock branches, length only when a place/country branch is met; "every day" adds no cap; spring gap → next valid time; repeated fall hour → first occurrence unless already past | §5.6 "window that allowed it", DST stress tests | Yes |
| A start with < 60 s left is refused instead of spending a use | Otherwise "23:59:50" spends today's use on 10 seconds | Yes |
| One session per rule, activity `session-cond-<ruleID>` (reservation = real name); finished sessions of the same rule are removed when the next starts | Their cleanup would otherwise stop the new session's activity | Yes |
| Capacity: each rule reserves its latent session; "Everything" free rules (with an allowance) reserve `latch.freewin`; a block rule's owned windows count as schedules; removal is a repair; pending removals free nothing. Five rules worst case: 8 names | §5.9 | Yes |
| Block outcome v1: only "block chosen apps"; needs a place or country; under any-of only **time windows** run on their own (owned daily `BlockSchedule`) | A check-in block is a Block now session, which can't express "all except"; standalone days/dates branches would need all-day or dated windows that today's schedule types can't represent. Examples 1–3 unaffected | Limit — owner's eye (spec allowed all-except) |
| A check-in block applies after its stricter wait without a staleness check, but needs the same rule revision and, under all-of, must still be inside its window (else dropped) | "Ends at the earlier of until and the window end"; a landed edit waited its own delay | Yes |
| Owned windows change only with their rule: `removeSchedule`/`updateScheduleSelection` on them and `addSchedule` claiming an owner are rejected | One rule, one decision | Yes |
| Edits keep ID and `addedAt`, bump `revision` (today's uses and a running session carry over); a no-op edit is rejected; removing a free rule lets its session finish (C14) | §5.8 | Yes |
| Five-rule cap counts pending additions; conflict keys `conditional-<id>` / `conditionalStart-<id>` | §5.3, §5.8 | Yes |
| Receipt summaries: "Add When & where rule: %@. If … : …." with names only; weekday and country names come from the system locale, like `Recurrence.label` | `ChangeEngine.summary` must compile in harnesses that don't have `AppLanguage` | Limit |
| `RulePending` maps the new actions to nil for now | `RuleRef.conditional` arrives with the Rules card (step 2) | Follow-up |
| No change to existing rule kinds, delays, overrides, Block now, sessions or schedule behaviour; additions to `housekeeping`/`rolloverIfNewDay` are no-ops without rules/records | Brief | Preserved |
| `Tests/WakeWidgetReadOnlyHarness.py` froze `ChangeEngine.swift` byte for byte against `da9b6d3`; its guard now also accepts **pure line insertions that name When & where symbols** (any edited or deleted original line still fails; checked by mutation). Every engine change was made an insertion; the free start's zero-delay path is inlined in `queueCoordinated` so `MigrationDelayPresentationHarness`'s delay pins and `ScheduleSelectionHarness`'s compile stay unchanged | The spec requires new `ChangeAction` cases in the engine's exhaustive switches, which that freeze can't allow | Yes — the one edit to an existing harness; worth the lead's eye |

## When & where step 1 review fixes
A fresh reviewer read the uncommitted diff and spec with no conclusions from
the lead. It confirmed no start without a met check-in, no override path,
correct directions, tolerant decoding and matching capacity names. Fixed,
each with a regression check in `Tests/WhenWhereHarness.py` that fails
without the fix:

| Bug | Fix | Test |
| --- | --- | --- |
| **High:** day keys used the device calendar, so switching Settings → Calendar (Gregorian → Buddhist → Japanese …) gave a fresh key and reopened a spent day | Day keys, weekdays and times are always read in a Gregorian calendar in the zone (`ConditionalDay.gregorian`) | Five calendars give one key; a spent day stays spent under Buddhist/Japanese/Hebrew; day/time results unchanged |
| Editing an owned block window's times kept its activity names, so it was never re-registered (block starts late, or stays on past its new end) and the name-based repair couldn't notice | `ownedScheduleID` includes the window's start and end | A time edit changes the ID, re-registers windows and leaves no stale names; a rename keeps the ID |
| A writer holding an older snapshot (app vs extension) could save a lower use count, refunding a use | `SharedStore.saveCoordinated` merges uses with the saved state: highest count per rule and day, check-in IDs combined; records older than 72 h are not resurrected | Pure merge table + source guard that the real save merges before encoding |
| A check-in block "until 02:30" started in the repeated fall hour (second 02:10) ran until the next day | The end uses the same first-then-second-occurrence rule as window ends | Madrid 2026-10-25, both 02:10s end at their own 02:30 |

The same reviewer rechecked the fixes and found no new high or medium issue.
Left as limits: the stale-save race can still drop a just-started session (the
same race exists for every session; the use is no longer refunded, so the
user can lose, never gain, free time); an older build never stops
`session-cond-*` activities after a downgrade; a promotion of an owned window
(no UI yet) is lost when its times change, because its ID changes.

Verification on `da7fe64`: all 35 `Tests/*Harness.py` (When & where: 34
scenarios, 272 assertions, plus the `b188742` decode check), both Swift
harnesses, both localization checks, `git diff --check`, then sequential
unsigned arm64 Debug and Release builds with stable Xcode 27.0 (27A266a), no
warnings. `9151393` passed the same verify on its own. Not installed; nothing
here is visible on a phone yet.

**What step 2 needs (editor, Rules card, summary):** `RuleRef.conditional`
and the `RulePending.ref` mapping (now nil); hide owned windows
(`ownerRuleID != nil`) from Schedules, Calendar and Conflicts or show them
under their rule; build drafts with `addedAt = Date()`, `revision = 0` and
validate with `ConditionalRule.isValid` (it already encodes the block v1
limits); queue `.addConditionalRule` / `.updateConditionalRule` /
`.removeConditionalRule` through the receipt. Step 3 (check-in) calls
`ConditionalClockInput.current(for:)`, `ConditionEvaluator.evaluate`
(`locationCouldChangeVerdict` says whether to read location),
`ConditionalCheckInStamp.make` and `ChangeEngine.startConditionalSessionOffMain`,
and maps `ConditionalStartRefusal` / `ConditionReason` to copy (no strings yet).

## When & where step 2 (2026-11-11)
Step 2 of the approved `docs/conditional-sessions-redesign.md` (C15: editor,
Rules card, summary sheet). No check-in, no CoreLocation, no Info.plist
change; engine and model untouched (`git diff 2e3f8f3 -- Shared/ChangeEngine.swift
Shared/SharedModels.swift` is empty). Commits `79e51ba` + review fixes `af71cf8`. Evidence: `Tests/WhenWhereRulesHarness.py`
compiles the real `RulesPresentation.swift` with the real models and
`SchedulePrecedence`, checks the pending mapping, section, card line, chip,
facts, both choosers and a 21,450-draft table where the editor's "no problem"
equals `ConditionalRule.isValid`, plus source guards and translations.
Nothing was seen on a screen (no simulator runtime on this Mac).

| Decision | Why | Done? |
| --- | --- | --- |
| **Owned block windows** (`ownerRuleID != nil`): hidden from Rules → Schedules; still drawn in the Calendar and Today's day thread under the rule's name, and tapping them opens the **When & where rule** (`RuleCatalog.resolve` maps an owned `.schedule` to `.conditional(owner)`); Conflicts still lists their overlaps (they are real enforcement) but gives them no Priority row or link | One rule, one decision (spec §5.2/§5.8). The engine already rejects Edit apps / Remove block on them, so the schedule sheet would have offered actions that fail; a priority on an owned window would be lost when the rule's times change (step-1 limit) | Yes |
| A check-in start (`.startConditionalSession`) maps to **no** card line | Its conflict key differs from the rule's, so mapping it would lock Edit/Remove while the engine allows them. Free starts never wait; a waiting check-in block (step 6) shows in Changes only | Yes — step 6 may add a "Starts in" line |
| Card line: conditions joined by ", " (all of) or ", or " (any of), first letter capitalised in the app's language, then " · " and the outcome: "1 hr free", "2 × 30 min free", "30 min unblocked", "blocks 1 app". Lengths use the app's duration words, so 60 min reads "1 hr" | Spec §5.3 with the existing `RuleText.minutes` wording | Yes — wording worth your eye |
| Chip: free time shows **"1 left today" / "None left today"** (neutral) from the engine's own count (`ConditionalUses.used` over every recent zone's day key, read in events); unknown count → no chip; an all-of rule whose days/dates exclude today, or whose same-day time window has ended, → no chip; a running session → "Free until" / "On until"; a block rule → "On until" only while its own time window runs | Spec §5.3: never "conditions met", unknown is not a number | Yes |
| New rule chooser: **When & where** is the seventh row, disabled at five rules counting queued additions (the engine's count) | §5.3 | Yes — sheet keeps its medium/large detents; check on SE |
| Editor starts with no conditions. **Add condition** lists Place, Country, Days, Time, Dates with example lines; **Place and Country are greyed: "Arrives in a later update."** Defaults: weekends; 22:00–00:00 (with an "After 22:00" shortcut); the coming seven days | Brief: placeholders only until steps 4–5 | Yes |
| First problem above Review change, in page order: name → name length → no conditions → more than four → per condition (no days, same times, last day before the first) → only-these-apps free time without apps → block needs a place/country → any-of block with days/dates → block without apps → anything else `isValid` refuses ("Check this rule's settings.") → no-op edit (no message) | R12; the editor can never offer a draft the engine refuses | Yes — harness table |
| **Block outcome is in the editor with its v1 limits explained, but can't be saved yet**: `isValid` needs a place or country for a block, and those arrive in steps 4–5. The problem line says so and suggests a repeating block | Brief asked for the block outcome and its limits in-editor; the engine encodes them | Limit — worth your eye |
| "Everything" free time saves an empty selection | Stray picks don't travel with it (as Block now's Free) | Yes |
| New drafts: `addedAt` = when the page opened, `revision` 0. Edits keep ID, `addedAt` and revision (the engine bumps it). The editor reads the live rule and won't review if the rule is gone or a change to it waits | Brief; a stale sheet can't recreate a removed rule | Yes |
| Summary sheet: **If (all of)/(any of)** with one row per condition (symbol + words; a place adds "within 250 m"), **Then** in two lines (opens the apps page when apps are chosen), **Today "1 of 1 left"** only for a saved free-time rule with a known count that can still hold today (same rule as the chip); **Check in shown switched off** with "Check in arrives in a later update."; **Edit** (secondary) and **Remove rule** (quiet) through the receipt | §5.4; Check in is step 3 | Yes |
| "Check in" is translated as "verify" (Comprobar, Vérifier, Verificar, Sprawdź, Kontrol et); German "Einchecken", Hindi "चेक इन" | The action checks your conditions; "register" words read wrong | Worth your eye |
| Fixed two existing Hindi strings with stray Chinese/Korean characters ("Apps to unblock", shown in this editor, and "Unlock viewing the stored passcode"); the new harness rejects CJK in the Hindi table | Visible on the new page | Yes |
| `FromToRows` (time rows) is now shared instead of private | Reuse the repeating editor's From/To rows (§7) | Yes |
| No change to the engine, model, capacity or any existing rule's behaviour | Brief | Preserved |

## When & where step 2 review fixes
A fresh reviewer read `79e51ba` and the spec with none of the lead's
conclusions. It found **no bypass**: every add, edit and remove goes through
the receipt, the editor never queues, Check in can't start anything, and
owned windows can't be edited, removed or prioritised outside their rule.
Fixed in `af71cf8`, each with a check in `Tests/WhenWhereRulesHarness.py`
(the two behavioural ones were mutation-checked: they fail without the fix):

| Finding | Fix | Check |
| --- | --- | --- |
| **Medium (unverified on a device):** condition cards used `ForEach($conditions)` index bindings; deleting a card while a date/time picker was still committing could crash ("Index out of range") or write to the card that moved into its place | Each card's binding finds its condition by ID on every read and write; a removed card reads a harmless value and writes nothing | Source guard: no `ForEach($conditions)`, ID binding with a guarded write |
| The sheet's **Today "1 of 1 left"** showed on a day the rule can't hold, while the card showed nothing; an all-of rule whose same-day window had ended still showed "1 left today" | One helper (`ConditionalText.usedForToday`) for chip and sheet; an ended non-wrapping window rules the day out (a 22:00–06:00 window doesn't) | Chip before/inside/after a 09:00–10:00 window, a wrapping window, helper table |
| A stale editor (opened while an edit waited, edit then landed) enabled Review on the old draft: a silent revert, still delayed | The page says "This rule changed while you were editing. Close it and open it again." and won't review; Cancel now also asks after an all-of/any-of or block-end change | Source guards |
| A sheet opened from an owned window (Today, Calendar) would read "removed" after a time edit changed the window's ID | The sheet remembers the owning rule | Source guard |
| Uses chip and Today row could stay on yesterday's count past midnight | Rules and the sheet re-read live state when the day key changes | Source guard |
| A Block draft asked for apps before saying a block needs a place (impossible in this build) | Place/country and any-of problems come before apps | Table: no place + no apps → place first |
| The harness's translation scan was partly hand-listed | It now scans every `tr()` in the editor, sheet and Rules tab and every editor problem message | 167 strings × 7 tables |

Left as limits: the chip's "can it hold today" reads the wall clock and the
current zone only (the engine uses the guarded clock and every recent zone),
so after a zone change a card can say "1 left today" when a check-in would be
refused; the chip never claims conditions are met, and the check-in decides.
Nothing in step 2 was rendered or tapped on a screen.

Verification on `af71cf8`: all 36 `Tests/*Harness.py` (new
`WhenWhereRulesHarness`: 112 checks, a 21,450-draft validity table, source
guards, 167 strings × 7 tables; `WhenWhereHarness` unchanged and passing),
both Swift harnesses, both localization checks, `git diff --check`, then
sequential unsigned arm64 Debug and Release builds with stable Xcode 27.0
(27A266a), no warnings. Not installed; no simulator runtime on this Mac.

### When & where step 2: what to try on the phone
1. **Rules → New rule**: a seventh row **When & where** ("Free time or a
   block that depends on place, day or time"). On an iPhone SE check that
   all seven rows fit or the sheet scrolls.
2. Name it "Sunday in Mexico". **Add condition**: Place and Country are
   greyed with "Arrives in a later update."; Days, Time and Dates show an
   example line. Pick **Days** (weekends preselected), leave only Sunday.
3. **Then → Free time**, **Everything** (note about lifting every block),
   **Up to** 1 hr, **Times a day** 1. Clear the name: "Give it a name." shows
   above **Review change**, which is off.
4. Review change → the receipt says **Looser change** with "Add When & where
   rule: Sunday in Mexico. If on Sun: 60 min free, once a day." Hold.
5. Rules now has **When & where** after Schedules, with a dashed card and
   "Added in …". Once it lands (or **Skip delay (dev)**), the card reads
   "On Sun · 1 hr free"; on a Sunday the chip says **1 left today**, on other
   days there is no chip.
6. Open it: **If (all of)** with a calendar icon line, **Then** "Free time,
   up to 1 hr / Once a day · everything unblocked", **Today 1 of 1 left**
   (Sundays only). **Check in** is visibly off with "Check in arrives in a
   later update." **Edit** and **Remove rule** sit under it.
7. Edit → add a **Time** condition (22:00–00:00, "After 22:00" shortcut),
   switch to **Any of these**: the small labels between cards change from
   "and" to "or". Review change: always **Looser change**. The card shows
   "Loosens in …" and the sheet's Edit/Remove are off until it lands.
8. Add four conditions: **Add condition** greys out with "You can add up to
   four conditions." Delete cards from the middle, including one whose date
   picker is open: no crash, the others keep their values.
9. Switch **Then** to **Block**: the notes explain the v1 limits and the
   problem line says a block needs a place or country, so it can't be saved
   in this build (expected until steps 4–5).
10. **Remove rule** → receipt: removing free time is **stricter** (one-tap
    Confirm with your stricter wait).
11. Make five rules: the chooser row reads "You can have up to five When &
    where rules." and is off.
12. Languages: German, Polish and Hindi card lines truncate at one line on the
    card and wrap on the sheet; country/weekday names follow the app language.

### What step 3 needs (check-in with day/time + Today rows)
- **Switch Check in on** in `RuleSummarySheet` (now
  `primary(tr("Check in")) {}.disabled(true)`, pinned by
  `WhenWhereRulesHarness` — update that guard) and remove the two "arrives in
  a later update" notes (sheet and editor's free-time note).
- Build `CheckInSheet` on `ConditionalClockInput.current(for:)`,
  `ConditionEvaluator.evaluate(…, location: .notRead)`,
  `ConditionalCheckInStamp.make` and `ChangeEngine.startConditionalSessionOffMain`;
  map `ConditionalStartRefusal` and `ConditionReason` to copy (none exists yet).
  `ConditionRow` (read-only symbol + words) is ready to gain a ✓/✗/? status.
- Today rows (`ConditionalAvailability.todayRows`, spec §5.3) under extra time;
  `RuleLiveReads.conditionalUsed` already gives the engine's count per rule.
- Decide where a **running conditional session** shows: today `RuleCatalog`
  also lists every running `BlockSession` under **Planned**, so a check-in
  session would appear twice (When & where chip "Free until" and a Planned
  card with End early). Recommended: hide sessions with `conditionalRuleID`
  from Planned and put **End early** on the When & where sheet.
- A waiting check-in block (step 6) has no card line (`RulePending` maps
  `.startConditionalSession` to nil); add one with step 6 if wanted.

## When & where step 3 (2026-11-12)
Step 3 of the approved `docs/conditional-sessions-redesign.md` (C15: check-in
with day/time/dates only + Today rows). No CoreLocation, no Info.plist change,
engine and model untouched (`git diff ec7234a -- Shared/ChangeEngine.swift
Shared/SharedModels.swift` is empty). Commits `bf2d2ed` + review fixes
`4784fe8`. Evidence: new `Tests/WhenWhereCheckInHarness.py` compiles the real
`RulesPresentation.swift` with the real models and checks every sheet state,
that the stamp the sheet builds is accepted by the engine's own
`ConditionalStart.plan` (and refused when stale, after midnight or after a
clock change), reason copy for every reason, Today rows and the Planned
mapping, plus source guards and 103 strings × 7 tables. Nothing was seen on
a screen (no simulator runtime on this Mac).

| Decision | Why | Done? |
| --- | --- | --- |
| **Check in** is on in the summary sheet (primary) and stays available while an edit of the rule waits; it opens `CheckInSheet` on top of the summary sheet | §5.4: the enforced rule keeps working until its edit lands | Yes |
| The sheet checks on open: `ConditionalClockInput.current` → `ConditionEvaluator.evaluate(…, location: .notRead)` → per-condition ✓ / ✗ / ? / – rows with a reason (`ConditionRow` gained a status and reason) → if met, Hold to start sends that check's `ConditionalCheckInStamp` through `startConditionalSessionOffMain`, which validates it again | §5.5; C2: no start without a met evaluation and a fresh stamp | Yes |
| **Location is never read** (`ConditionalCheckIn.locationAvailable = false`). A rule whose verdict a place or country could still change says **"This rule needs your location."** / "Location checks arrive in a later update."; its row reads "Needs your location — arrives in a later update." and nothing can start. A met any-of rule (e.g. "in Mexico **or** on Sundays" on a Sunday) starts on its day/time branch | Brief; C8 already says location is read only when it can change the answer | Yes |
| **Block rules** show the same "needs your location" state, even inside their own time window, and get no Today row | Check-in blocks are step 6; block rules can't be saved yet anyway | Limit until step 6 |
| Verdict order: removed → running → refusal → rule changed → block → clock changed → needs location → not met → uses unknown → used up → under a minute left → met. "Not met" wins over "used up" | §5.5 step 6 lists "used up" only for a met rule; on a day it can't hold, the ✗ rows say more | Yes |
| **Freshness**: a check is re-run on its own (10 s timer) once it is 110 s old, the window it relied on has closed, the day or zone changed, or the rule changed/was removed (state publish). A hold on a check that only aged re-runs it and sends the new one if it is still met for the same rule version, day and zone; any other change is shown with "Checked again. Hold again to start." | 110 s keeps a margin under the engine's 120 s stamp lifetime; a pre-midnight or pre-edit check is never sent | Yes — the aged-only resend is worth your eye (the alternative is always needing a second hold) |
| **One start in flight**: `starting` is set on the main actor before the request leaves it, the hold is disabled while it runs, and a refused or started result removes the hold (Try again builds a new check with a new check-in ID). The engine's conflict key and one-use check-in IDs back this up | Double taps, VoiceOver confirm + hold | Yes |
| **How long**: `DurationControl` from 5 (or the cap if smaller) to the cap = min(rule's max, whole minutes left in the window); the sent length is clamped to 1…cap; "Ends at 15:20 · 1 of 1 today" (use number = today's count + 1) | §5.5; the wheels can overshoot the range | Yes |
| No receipt for a free start: **Hold to start free time** (free ink, 1.2 s); with VoiceOver or Reduce Motion one confirmation "Start free time now?" | §5.5 step 6: nothing waits, the hold is the deliberate moment | Yes |
| Every `ConditionalStartRefusal` (14) has its own plain line under **"Free time didn't start."** with Try again / Done; an unexpected queued start reads "Free time didn't start. It's waiting in Changes instead."; "Free time is on until …" comes only from saved sessions | Brief: a refusal must never read as success | Yes |
| Reasons: ✓/✗ day "It's Sunday" (weekday in the app's language), ✓ time "Until 06:00", ✗ time "It's 14:05; this starts at 22:00", dates "Today is (isn't) one of these dates" (the dates are on the line above), "Not needed"; every unknown reason (clock changed, zone changed, the location ones for step 4) has a line | §5.5 step 5 | Yes — wording worth your eye |
| Haptics: one success or warning when you open or Try again; the hold's own success on a start; none on background re-checks | §9 | Yes |
| **Today**: Check in rows sit in their own card directly under the Your limits section (so they also show with no limits), same row style as extra time: "**Sunday in Mexico** · 1 left today · Check in ›" → opens the check-in itself. Shown for free-time rules with a known count and uses left, nothing of theirs running, day/time/dates holding now and at least a minute left; three at most, then "All in Rules". Counts come from `RuleLiveReads.conditionalUsed` (now shared by Rules, the sheet and Today), the clock from an event read (guarded offset + recent zones), so nothing reads the guarded clock while drawing | §5.3 | Yes |
| **Running check-in sessions** live on their rule: hidden from Planned while the rule exists; the Now card, day thread and Calendar open the When & where sheet ("Free until" chip, **End early** through the receipt, delayed like any session, or the waiting End early); the rule's card shows a waiting End early. After the rule is removed (C14) the session shows under Planned again with its own End early | "What step 3 needs" recommendation; Q1: ending early stays a delayed looser change | Yes |
| Editor's free-time note now says "You start it with Check in on the rule or on Today."; the two step-2 "arrives in a later update" check-in strings are removed from all tables; Place/Country in Add condition still say later | Brief | Yes |
| "Ends at" is phrased "Ends at: 15:20"-style in the other languages ("Termina: %@", "Ende: %@"…), keeping the English argument order | Times past midnight carry a weekday ("Mon 00:10"); arguments are not positional | Yes |
| Recovery: Check in isn't disabled up front; the engine refuses (`.unavailable`) and the sheet says nothing changed | No engine change; rare | Limit |
| No change to the engine, model, capacity or any existing rule's behaviour | Brief | Preserved |

## When & where step 3 review fixes
A fresh reviewer read `bf2d2ed` and the spec with none of the lead's
conclusions. It found **no high-severity bug**: no start without a met check,
no override path, one request in flight, stale sheets re-checked, refusals
never shown as success, the session mapping keeps End early reachable, and no
guarded-clock reads while drawing; all new translations keep placeholder
count and order. Fixed in `4784fe8`, each with a check in
`Tests/WhenWhereCheckInHarness.py` that fails without the fix
(mutation-checked):

| Finding | Fix | Check |
| --- | --- | --- |
| Borderline medium: a hold on a check that had just aged past 110 s re-checked silently, played two success haptics and started nothing | Aged-only checks are re-run and sent; other changes show "Checked again. Hold again to start." with no extra haptic | `mayStartAfterRecheck`: aged → send; after midnight, edited, not met, running → never |
| "Free time is on until …" could outlive a session ended elsewhere | Running state comes only from saved sessions | Started but not saved → not running |
| A check whose window had just closed kept its ✓ rows and said "under a minute left" | `needsRecheck` when the window end has passed | 12:00–12:30 window: 12:29:50 fresh, 12:30:10 re-check |
| A waiting End early showed on no Rules card (its session card is hidden) | `RulePending.cardChange` gives the rule's card its running session's End early (the rule's own change first) | Card table |
| The sheet's End early read `Date()` in the body | It follows the sheet's own clock | Source guard |

The same reviewer rechecked `4784fe8` and found no high or medium issue (the
re-check path sends only a fresh, met check for the same rule version, day
and zone; one start in flight still holds). Low, left: when a hold lands on a
re-check that is no longer met, the hold button's own success haptic still
plays (the screen shows the not-met verdict).

Left as limits: an engine-side race refused inside the queue or at apply comes
back as `.unavailable`, so it reads "iOS may not be able to track another
session right now. Nothing changed." (engine unchanged); Today's rows use a
count and clock offset up to 30 s old and refresh each minute, so a row can
stay up to a minute after its window ends (the sheet decides).

Verification on `4784fe8`: all 37 `Tests/*Harness.py` (new
`WhenWhereCheckInHarness`: 192 checks, source guards, 103 strings × 7
tables; `WhenWhereHarness` and `WhenWhereRulesHarness` passing, the latter's
Check-in guard updated to "on"), both Swift harnesses, both localization
checks, `git diff --check`, then sequential unsigned arm64 Debug and Release
builds with stable Xcode 27.0 (27A266a), DerivedData outside the repo, no
warnings. `bf2d2ed` passed the same verify on its own. Not installed; no
simulator runtime on this Mac.

### When & where step 3: what to try on the phone
1. Make (or keep) a rule "Sundays": **Days** Sunday only, **Free time**,
   Everything, up to 1 hr, once a day. Let it land (or **Skip delay (dev)**).
2. On a Sunday, **Today** shows a card under Your limits: "**Sundays** · 1
   left today · Check in ›". On another day there is no row.
3. Tap it: "Sundays", **You can have free time now.**, "Free time needs all
   of these.", a ✓ row "On Sun / It's Sunday". Change **How long** to 30 min:
   "Ends at … · 1 of 1 today" moves. Hold **Hold to start free time**.
4. The sheet says **Free time is on until …** with Done. Today's Now card says
   you're in a free period; the Check in row is gone; Rules → Planned does
   **not** list the session; the When & where card chip reads "Free until …".
5. Tap the Now card: the **Sundays** sheet opens with **End early**. Tap it:
   the receipt says Looser change and waits your looser delay; after Confirm
   the sheet and the card show the waiting End early.
6. After the session ends, Check in again: **You've used today's free time.**
   / "Resets at midnight". Monday: **Not right now.** with ✗ "It's Monday".
7. Try a double hold, or hold then quickly tap again: only one session starts.
   Open the check-in, wait 2–3 minutes, then hold: it starts (re-checked).
   Open it at 23:58 on a rule that holds every day and hold after midnight:
   "Checked again. Hold again to start."
8. Add a **Time** 22:00–00:00 condition (all of): at 23:30 How long caps at
   30 min and ends at 00:00; at 23:59:30 "Less than a minute is left…".
9. Change the iPhone's time by hand (Settings → General → Date & Time): the
   rows show "?" "Your clock was changed recently" and nothing starts.
10. With VoiceOver on: the hold becomes one button asking "Start free time
    now?"; each row reads "Met, On Sun, It's Sunday".
11. Remove the rule while its session runs: the session appears under
    Planned with End early (C14).
12. Languages: German/Polish/Hindi rows and refusal lines wrap, never cut the
    mark; weekday names follow the app language.

### What step 4 needs (places + location permission)
- Flip `ConditionalCheckIn.locationAvailable` (Today rows then also list rules
  that location could make true) and turn the `.needsLocation` state into a
  real read: when `evaluation.locationCouldChangeVerdict`, run the one-shot
  `LocationCheck` (host only) and evaluate again with `.fix`/`.unavailable`.
  `CheckInResult.make` hardcodes `location: .notRead` today: give it the
  location input, and make the stamp come from that evaluation.
- The aged-only resend in `CheckInSheet.start` re-evaluates without location:
  for a rule that needed a fix it would come back not met and show "Checked
  again"; re-read location there (or require a new check).
- `unknownKey(.notChecked)` still says "Needs your location — arrives in a
  later update."; add the spinner row "Checking where you are", the
  permission card, and enable Place in `ConditionKind.disabledReason`.
- The location reason strings (location off, no fix, imprecise, needs precise,
  simulated, accessory, border, country unknown) already exist and are
  translated; the permission prompt strings and `InfoPlist.xcstrings` don't.
- Update the "no CoreLocation / NSLocation" source guards in
  `Tests/WhenWhereRulesHarness.py` and `Tests/WhenWhereCheckInHarness.py`.
- Block check-ins (Review → receipt, Today rows for block rules) stay step 6.

## When & where step 4 (2026-11-12)
Step 4 of the approved `docs/conditional-sessions-redesign.md` (C15: places +
location permission + Info.plist strings in 8 languages). Engine, saved-data
model and capacity untouched (`git diff 8c0447c -- Shared/ChangeEngine.swift
Shared/SharedModels.swift Shared/MonitoringBudget.swift` is empty). Commit
`f4aa920` + review fixes `ab2c566` and `3387a4d` (below). Evidence: new
`Tests/WhenWhereLocationHarness.py` compiles the real `RulesPresentation.swift`
with the real models and runs CoreLocation-shaped samples through the trust
rules into the engine's own evaluator and `ConditionalStart.plan`, plus source
guards on the only CoreLocation file and on the permission strings; the step 2
and 3 harnesses' "no CoreLocation / NSLocation" guards now state the new
intent (location only in `Latch/LocationCheck.swift`, used only by the
check-in and place sheets; While Using only). CoreLocation itself is not
compiled by any harness, so **no real fix, prompt or timing was seen**: no
simulator runtime on this Mac, and the phone wasn't used.

| Decision | Why | Done? |
| --- | --- | --- |
| **`LocationCheck`** (`Latch/LocationCheck.swift`, host only, `@MainActor`): `requestWhenInUseAuthorization` only when never asked, one `requestLocation()` per read with `kCLLocationAccuracyBest` and a 15 s timeout, `stopUpdatingLocation()` the moment it resolves or is cancelled; one reader per sheet (`@StateObject`), cancelled on dismiss. No updates, monitoring, regions, visits, background modes, geocoder or map; nothing printed, logged or saved | C8; spec §5.5 step 4 and §11 | Yes — harness source guards |
| The sheet always checks day/time/dates first (`location: .notRead`), then reads **only if one fix could make the rule true** (`ConditionalCheckIn.fixCouldDecide`): a place could; a country can't until its lookup (step 5); block check-ins are step 6. All of with a failed day → no read, no prompt; any of with a met day → no read | C8: read only when it changes the answer | Yes |
| A read only on the user's tap: opening the sheet (it opens only from **Check in** / a Today **Check in ›** row), **Try again**, **Allow location**, or a hold on an aged check. The 10 s freshness timer and state publishes **never read**: a location check refreshed on its own shows "This rule needs your location." / "Check in again to check where you are." | No background-ish reads while a sheet sits open | Yes |
| `CheckInResult.make` now takes the location input (no default) and keeps only `readLocation` and per-condition results; the **stamp comes from the evaluation that used the fix**, on a clock read after the fix arrives. Coordinates never leave the read's local scope | Step-3 note; C8 "never stored" | Yes |
| The **aged-only resend** in `start`: a check that read location is never re-run from the clock alone; the hold reads one new fix, re-evaluates, and sends only if `mayStartAfterRecheck` (same rule version, day, zone, still met). Walked away meanwhile → shown with "Checked again. Hold again to start." | Step-3 "What step 4 needs" | Yes — worth your eye (alternative: always a second hold) |
| Permission: **never asked** → in-sheet card ("Demora checks where you are once, when you tap Check in. It doesn't save or send your location.") with **Allow location** / **Not now**; iOS's prompt only after that tap. **Denied/restricted** → the place row reads "?" "Location is off for Demora. You can turn it on in Settings." — text only, no button, no redirect, no re-prompt | Spec §5.5 step 3; the 5.1.1(iv) history in CLAUDE.md | Yes — restricted uses the same words (Settings can't change it there); engine has one reason |
| Trust (C9), host side `LocationTrust.checkInInput`: denial → location off; timeout/no fix/cancel → "Couldn't get your location…"; `sourceInformation.isSimulatedBySoftware` / `isProducedByAccessory` carried to the engine (simulated → "?"; accessory → "?" for free time); Approximate Location → iOS is asked once for temporary precise (purpose key `CheckIn`), declined → "Needs precise location". The engine then requires age ≤ 15 s, accuracy > 0 and the **whole circle inside** (distance + accuracy ≤ radius); a fix vaguer than the place is never met | C9 | Yes — harness: centre, 200 + 40 m in, 200 + 60 m "?", 320 − 60 m out, 3 km accuracy, simulated, accessory, approximate, 20 s old, invalid, denied, timeout |
| **`sourceInformation == nil` is treated as a real fix** | Unknown whether iOS fills it for every ordinary fix; failing closed on nil could make every check-in read "looks simulated" | Limit — check on the phone (step 4 below) |
| Countries in step 4: Add condition still says "Arrives in a later update."; a rule that only a country could decide shows "This rule can't be checked yet." / "Checking which country you're in arrives in a later update." and gets no Today row; a fix gives `country: nil` → "Couldn't tell which country you're in" | Brief: countries are step 5 | Limit until step 5 |
| **Block rules stay unsaveable** (new editor problem "Blocks that start when you check in arrive in a later update. For now, use a repeating block or Block now."), now that places would make them valid; a day/time-only block still reads "Use a repeating block for rules without a place." (spec §5.10 wording) | Otherwise a saved block rule would have a check-in that can't run; block outcome is step 6 | Limit until step 6 |
| **Place editor** (`Latch/PlaceEditor.swift`, its own sheet): Name, **Centre** ("Set to where I am now": card before iOS's prompt, then one fix), **Size** as five rows "100 m · About a house and its street" … "2 km · A small town centre" (C10, no free entry), **Use a place from another rule** (saved or waiting rules, de-duplicated, never this rule's own; a value copy, C11), **Use this place**. Choosing Place in Add condition opens it; a place card has **Change place** | Spec §5.7 | Yes |
| A centre needs a fresh, precise, real fix **good to 100 m** (the smallest place); rounded to 5 decimals (~1 m). Simulated, accessory, approximate, stale or vaguer fixes are refused with the check-in's words ("Location from an accessory can't set a place" is new) | C12; a centre off by more than the place is useless | Yes |
| **Show on map: deferred** | iOS 16 SwiftUI `Map` has no circle overlay or draggable pin; it needs an `MKMapView` wrapper, and it is the first Apple Maps network use to disclose. Not cheap; the spec makes it optional | Logged as deferred |
| `NSLocationWhenInUseUsageDescription` as `INFOPLIST_KEY_…` in the host's Debug **and** Release settings (identical); `NSLocationTemporaryUsageDescriptionDictionary` → `CheckIn` in `Latch/Info.plist` (shared by both). No Always, no location background mode; extensions get nothing | Brief; spec §8 | Yes — harness compares both configurations; both built apps' Info.plist checked |
| New `Latch/InfoPlist.xcstrings` with exactly those two keys in all 8 languages (English equal to the plist values, so no raw key ever shows). Never `CFBundleDisplayName` (Debug "dev demora" vs Release "demora" would collide). The camera string stays English | Brief; display names must stay per configuration | Yes — both builds emit 8 `.lproj/InfoPlist.strings`; display names still "dev demora"/"demora". Camera translation: possible follow-up |
| The temporary-precise string is localized under its purpose key (`CheckIn`), as Apple's `requestTemporaryFullAccuracyAuthorization` docs describe | Apple's documented route | Check on the phone in another language |
| `PrivacyInfo.xcprivacy` **unchanged**: CoreLocation is not a required-reason API, and location never leaves the device, so it isn't a collected data type | Brief: confirm and log. The spec's optional comment line was not added | Yes — harness asserts no location data type |
| No network: no geocoder, no address search, no map | C5/C12 defaults | Yes |
| Hero/row wording: spinner row "Checking where you are"; unread place "Not checked yet"; step-3 placeholders "Needs your location — arrives in a later update." and "Location checks arrive in a later update." removed from code and all tables | Brief | Yes |

## When & where step 4 review fixes
A fresh reviewer read `f4aa920` and the spec with none of the lead's
conclusions. It found **no high-severity bug**: no read at launch, in the
background or on a timer; one `requestLocation()` stopped on resolve; the
creation callback ignored; nothing kept, logged or sent; spoofed, approximate,
stale and invalid fixes fail closed; the stamp comes from the fix's own
evaluation; no re-prompt after denial; Debug = Release; the catalog never
touches the display name. Fixed in `ab2c566`, each with a source guard in
`Tests/WhenWhereLocationHarness.py` that fails without the fix
(mutation-checked):

| Finding | Fix | Check |
| --- | --- | --- |
| **Medium:** **Try again** never read location, so after a timeout ("Couldn't get your location") or an aged check it only ever showed "Check in again to check where you are." — a dead end until the sheet was reopened | Try again is the user's tap: it runs the full check (one new fix when a place could decide; denied stays "off", never re-prompted) | Try again passes `userAsked: true`; three user-asked entry points |
| Low: a read waiting on iOS's temporary-precise prompt couldn't be cancelled; after the sheet closed it still started a fix (≤ 15 s, no screen) | A read token bumped by every cancel; checked after the prompt, before `requestLocation()`; an older waiter is always ended | Order guard: token → prompt → check → request |
| Low: a fix arriving after "Use a place from another rule" replaced the copied centre | The copy cancels the read in flight | Copy menu cancels before setting the centre |
| Low: a double tap on **Allow location** left the card up after permission was granted | One permission request at a time; the button is disabled while iOS's prompt is up (both sheets) | Guard + `.disabled(requestingPermission)` |
| Low: with Location Services off for the whole iPhone, iOS shows no prompt and never answers, so the wait never ended | Checked first (off the main thread); counts as "location off"; closing a sheet also ends any permission wait (`stop()`) | Guards on `requestPermission` and `stop()` |

The same reviewer rechecked `ab2c566`: all five fixes correct, nothing new
of high severity. Fixed in `3387a4d`:

| Finding | Fix | Check |
| --- | --- | --- |
| **Medium (from `f4aa920`, more frequent after Try again):** a rule whose uses were spent, or whose free time was already on, still showed the card or read a fix before saying "You've used today's free time" — a read that can't change the answer (C8) | `locationStep` returns none when uses are spent or unknown or this rule's session runs; the screen says "used up" / "couldn't count" before asking | Table: spent, running, other rule's session, unknown count |
| Low: a sheet closed during the Location Services check could still show iOS's prompt | The read token is checked after that check | Order guard |

Left as limits (low): "Location services off for the whole iPhone" is only
re-checked when the sheet is reopened, and reads with the same words as
"off for Demora" (the engine has one reason; text only, as before);
restricted (parental controls) also says "You can turn it on in Settings".

Verification on `3387a4d`: all 38 `Tests/*Harness.py` (new
`WhenWhereLocationHarness`: 106 checks, source guards, permission strings
2 × 8 languages, 37 strings × 7 tables; `WhenWhereCheckInHarness` 202 and
`WhenWhereRulesHarness` 116 checks with their location guards updated), both
Swift harnesses, both localization checks, `git diff --check`, then
sequential unsigned arm64 Debug and Release builds with stable Xcode 27.0
(27A266a), DerivedData outside the repo, no compiler warnings; both built
apps carry the location purpose string, the `CheckIn` purpose and eight
`.lproj/InfoPlist.strings`, with display names "dev demora" / "demora".
`f4aa920` and `ab2c566` passed the same verify. Every review fix was
mutation-checked against its guard. Not installed; no simulator runtime.

### When & where step 4: what to try on the phone
1. Make a rule "Home": **Add condition → Place** opens the place sheet. Name
   it Home, tap **Set to where I am now**: the card "Demora reads where you
   are once…" appears with **Allow location**; tap it → iOS asks (While Using
   / Once / Don't Allow). Allow: "Checking where you are", then "Centre set…".
   Pick **250 m**. **Use this place**. Add **Days** = today. Free time, 30 min.
   Let it land (or **Skip delay (dev)**).
2. At home, **Check in** (Today row or the rule's sheet): spinner row
   "Checking where you are", then ✓ "You're at Home" and **You can have free
   time now.** Hold to start.
3. Walk ~400 m away and check in again: ✗ "You're not at Home". Near the edge
   (~230 m): "?" "Location isn't precise enough here" (doubt fails).
4. Indoors with poor signal: either ✓, "?" imprecise, or after ≤ 15 s
   "Couldn't get your location…". **If every check reads "This location looks
   simulated", tell me** (the nil-source decision above).
5. Settings → Demora → Location → **Never**: Check in shows "?" "Location is
   off for Demora…" with Try again / Done; no prompt, no jump to Settings.
   Set **Precise Location** off: Check in asks once for precise ("Demora needs
   your precise location for this check…"); decline → "Needs precise location".
6. Open a check-in, wait 2 minutes without holding: the rows turn into "This
   rule needs your location. Check in again…" (no new read on its own). Hold
   right after a met check that is 1:50–2:00 old: it reads once more, then starts.
7. Close the sheet while "Checking where you are" spins: the location arrow
   in the status bar should go away right after.
8. Make a second rule and **Use a place from another rule** → Home: same
   centre and size; change its size there and check the first rule is still
   250 m.
9. Monday (or any day the Days condition fails): no read at all — the place
   row says "Not needed"; no prompt if you never allowed location.
10. iPhone language Spanish/German/Hindi: both iOS prompts are translated.
    Rules → New rule → Block with a place: the problem line says blocks that
    start on check-in come later.
11. Fresh install: nothing about location at launch or in onboarding.

### Privacy notes for the owner (step 4)
- New permission: **Location While Using**, asked only from Check in or Set
  to where I am now, after an in-app card. Never Always, never background.
- Read once per tap, in the foreground, checked on the device. Coordinates
  are never saved, logged or sent; only ✓/✗ results reach the start request.
- Saved places keep only name, centre (rounded to ~1 m) and size, in the App
  Group state; they are in the device backup like other app data.
- Place **names** appear in change summaries, so a trusted contact approving
  a rule change sees "at Home" (CloudKit, or the email relay, which can read
  the email). Never coordinates or sizes.
- No new network traffic: no map, geocoder or address search in this build.
- `PrivacyInfo.xcprivacy` and the App Store privacy label: no change expected
  (nothing leaves the device). Confirm before submission.
- **Website (still to write, separate repo, your deploy):** keep "We do not
  collect … location data" and add a short "Location (optional)" section —
  draft: "If you use a When & where rule with a place, Demora asks for your
  location while you use the app. It reads it once when you tap Check in or
  set a place, checks it on your iPhone, and never sends it to us. A saved
  place keeps only its name, centre and size on your device (and in your
  device backup). If a trusted contact approves a change, they see the
  place's name." Add one line about Apple Maps only if a map ships later.

### What step 5 needs (countries)
- Flip `ConditionalCheckIn.countryLookupAvailable` (Add condition opens
  Country; `fixCouldDecide` then lets a fix decide countries; Today rows
  follow) and pass the bundled lookup's `ConditionalCountryLookup` instead of
  `country: nil` in `LocationTrust.checkInInput` (one place).
- The reason override for an unread country ("Arrives in a later update." in
  `ConditionalCheckIn.reason`) and `.arrivesLater(.country)` then disappear;
  update the guards in `WhenWhereCheckInHarness` / `WhenWhereLocationHarness`
  that pin them.
- "Use the country I'm in" can reuse `LocationCheck.readOnce` (it doesn't
  need precise: pass `wantsPrecise: false`); a country check shouldn't ask for
  temporary precise unless a place also needs it.
- Step 6: remove `EditorProblem.blockLater` (and the harness's
  `draft.isFreeTime` exception in the validation table), then add block
  check-ins.
