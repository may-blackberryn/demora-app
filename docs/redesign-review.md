# Demora iOS full redesign — review

## Start here
- **State:** foundations and the Today build (`docs/today-redesign.md`) are on
  `design/full-redesign`; the Today build is nine commits after `8d62b11`.
  Nothing is pushed. Verify passes: all existing harnesses, the new
  `TodayPresentationHarness`, the localization check, `git diff --check`, and
  unsigned arm64 Debug and Release builds of the Latch scheme.
- **Install / run:** open `Latch.xcodeproj`, scheme **Latch**, Debug, on your
  iPhone. No simulator runtime is installed on this Mac, so nothing here was
  looked at on a screen.
- **What to try on the phone, in order:**
  1. Open the app: the first tab is now Today (the tab is still labelled
     Home). Top: wordmark, the date in small caps, then the Now card. With
     nothing active it says "Nothing is blocked right now." and, if a block
     starts later today, "Next: … at …".
  2. Start a block from the pinned **Block now** button. Once it runs, the
     Now card says "<name> is on until <time>." with an "Ends in" countdown.
     With two blocks it says "2 blocks are on. The first ends at …".
  3. Open a limit (Limits tab) and change its minutes, then **Queue change**:
     the change receipt appears. Looser: hold the button about a second (with
     VoiceOver or Reduce Motion it asks once instead). Stricter: one tap.
     "Keep editing" goes back. After confirming, the editor closes.
  4. Remove a recurring block, a planned window and a contact: each now asks
     through the receipt first (removing a contact is a plain Confirm).
  5. Back on Today: "Changing soon" shows the next two changes with chip,
     countdown, summary and landing time; **All N** opens the Changes ledger
     grouped by when they land. Try Select → Cancel N (asks once) and Apply
     N now. A change sent to a contact shows "Waiting for <name>".
  6. Your limits: one row per limit with "12 of 30 min" and a thin bar; a
     spent limit shows a full bar and "Used up"; a limit with no data yet
     says so. No refresh arrow; pull down to refresh.
  7. Spend a limit that has extra time: an extra-time row appears under the
     report ("<name> · Get extra time (2 left)") and opens the same gate as
     before. The Limits tab no longer has this button.
  8. If you use wake-up: in the morning the Now card says "Good morning…"
     with **Wake up**, and Block now hides until you tap it.
  9. Today's line shows today's rules on a thread with a "now" line; a
     friend's approval request appears as a card under the Now card with a
     bell at the top.
  10. If you ever left the old guided tutorial half-way, it still resumes on
      the old Home.
- **Decisions most worth your eye:** a free period outranks "used up"
  limits in the Now card; looser changes hold to confirm even with no wait;
  the receipt says "cancel it from Today" while the tab still reads Home;
  tapping the Now card opens Schedules or Limits until Rules exists.
- **Known limits:** nothing was checked on a screen or device; the Now card
  doesn't resolve which overlapping rule wins for each app; there's no
  "usage isn't available" state (the host can't detect it without a
  forbidden readiness signal); other editors keep their inline delay hints
  until the Rules and You builds.
- **Housekeeping:** build products are in the session scratchpad, outside
  the repo.

## Sessions
| Session | Scope | Commits | Status |
| --- | --- | --- | --- |
| Foundations build | Tokens, type, components, text case, tab bar; three review fixes | `7af8f65`, `46181bc`, `b15b244`, `d448215`, `5fad6e0`; fixes `3d25eda`, `23ba309`, `a59969f` | Done, reviewed and fixed |
| Today build | Pure logic, change receipt, Changes ledger, Today layout, report restyle, extra time moved | `82181d3`, `f3cbd3f`, `2548ac8`, `e16fe23`, `3180864`, `f38951e`; review fix `d2f8329` | Done, self-reviewed and fixed; awaiting the main session's review |

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
