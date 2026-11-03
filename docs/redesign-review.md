# Demora iOS full redesign — review

## Start here
- **State:** foundations, Today and now the Rules build (`docs/rules-redesign.md`)
  are on `design/full-redesign`; the Rules build is the commits after `5aa9c3d`
  (see Sessions). Nothing is pushed. Verify passes: every `Tests/*Harness.py`
  (including the new `RulesPresentationHarness`), the two Swift harnesses, the
  localization check, `git diff --check`, and unsigned arm64 Debug and Release
  builds of the Latch scheme.
- **Install / run:** open `Latch.xcodeproj`, scheme **Latch**, Debug, on your
  iPhone. No simulator runtime is installed on this Mac, so nothing here was
  looked at on a screen.
- **What to try on the phone, in order (Rules):**
  1. Tap the second tab (still labelled **Limits**): it is now **Rules** —
     title, calendar and conflicts icons, a **Your waits** strip, then your
     rules in sections (Limits, Schedules, Day & night, Planned, Always on).
     Each card shows one summary line and, where it applies, a chip
     ("Blocked", "On until 21:00", "Starts in 2 hr", "On"/"Off").
  2. Tap **New rule** (pinned at the bottom): six choices. Try **Daily
     limit**: name, Apps, the big minutes value with − / + (tap the value for
     the wheels), then **Different limit per day**, **Split the day** and
     **Extra time** rows, each a sub-page. **Review change** opens the receipt.
  3. After confirming, the new limit appears as a dashed card with "Added in
     …". Tap the countdown line: the Changes ledger opens at that change.
  4. Tap any rule card: the summary sheet says what it does (When, Days,
     What, How much, Split, Extra time…) with **Edit** and a quiet Remove.
     Remove asks through the receipt (hold for looser). With a change already
     waiting, Edit and Remove are disabled and it says to cancel in Changes.
  5. **Repeating block**: From/To with a dotted thread, "Ends next day" when it
     wraps, Every day / Some days / Monthly. Make one overlap another block of a
     different kind — "Overlaps with … on …" appears under the form.
  6. **Day & night**: name, What, Wake-up (Ask me to tap Wake up, start, wait,
     latest), Sleep, Days as round chips, "Different times per day" sub-page,
     "?" for the long explanation. Check onboarding's day & night step still
     saves without a receipt (Debug: developer demos).
  7. **Always on**: tap App deletion / Adult websites → Turn on/off through
     the receipt; Websites → Edit list, add a site (receipt), remove one.
  8. **Your waits** strip → the waits page, Review change → receipt.
  9. Conflicts icon (dot when rules overlap) → restyled Conflicts, "?" help,
     priority rows → Prioritize this → receipt.
  10. On Today: tap the Now card while one block runs → its summary sheet; with
      several blocks → Rules. Tap an item on the day thread → its summary.
  11. If you still use the old wake-up / sleep settings, they appear as
      "Wake-up" / "Sleep" cards under Day & night; their editors keep every
      old check.
- **Decisions most worth your eye:** tab 1 still says "Limits" until the
  four-tab switch; counts say "websites" (the old German "sites" entry was
  wrong); a new repeating block still defaults to "All except these"; the
  first problem line only shows once you've changed something; sheet editors
  with edits can't be swiped away (Cancel asks).
- **Known limits:** nothing was checked on a screen or device; the Calendar
  page itself isn't restyled; "Get extra time on Today" switches tabs but
  doesn't scroll; the Schedules tab's pages (Sessions, Planned, Recurring,
  Day & night, now & next) stay until the four-tab switch; the legacy tutorial
  keeps its old limit and recurring editors; the old "Home tab" pending key is
  left unused until the You build.
- **Housekeeping:** build products are in the session scratchpad, outside
  the repo.

## Sessions
| Session | Scope | Commits | Status |
| --- | --- | --- | --- |
| Foundations build | Tokens, type, components, text case, tab bar; three review fixes | `7af8f65`, `46181bc`, `b15b244`, `d448215`, `5fad6e0`; fixes `3d25eda`, `23ba309`, `a59969f` | Done, reviewed and fixed |
| Today build | Pure logic, change receipt, Changes ledger, Today layout, report restyle, extra time moved | `82181d3`, `f3cbd3f`, `2548ac8`, `e16fe23`, `3180864`, `f38951e`; review fix `d2f8329` | Done, self-reviewed and fixed; awaiting the main session's review |
| Rules build | Pure logic, Rules tab, summary sheet, editors, receipts and Changes copy, dead editor removed | `90e5f42`, `660ec07`, `b4345ae`, `f5d7e54`, `ea16ed1`, `c79d334`; review fixes `61681ee` | Done, reviewed and fixed; awaiting the main session's review |

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
