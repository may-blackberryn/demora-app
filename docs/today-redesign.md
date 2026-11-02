# Today, Changes and the change receipt — redesign (proposal, 2026-11-02)

Status: **approved by the owner, 2026-11-02.**

Builds on `docs/redesign-ux-plan.md` (approved) and `docs/foundations-redesign.md`.
Covers three things: the **Today** tab (replaces Home), the **Changes** ledger,
and the **ChangeReceiptSheet** every editor will use. Enforcement, timing and
the change engine are untouched; only presentation and navigation change.

## 0. Owner's call
- Plan jobs J1–J6 live here. Plan decisions D3 (ledger + chips), D4 (receipt,
  hold to confirm), D9 (removals confirm).

## 1. Diagnosis (current Home, ranked by user impact)
1. Pending changes are the **last** section (`HomeView.swift:325`), after
   the timeline, usage, sessions, banners and two contact sections.
2. The top third is a 43-pt date plus a 24-hour bar whose meaning needs a
   legend; the current state is never said in words.
3. Spent limits are shown inside the report, but extra time lives on another
   tab (`LimitsView.swift:157-252`).
4. Two contact sections (incoming inbox, outgoing "awaiting approval") sit far
   from the change they're about.
5. "No limits yet" switches tabs instead of starting the job; the empty
   "No pending changes" block always takes space.
6. Saving an edit gives only a haptic (`AppModel.swift:468`); the delay is a
   footnote under the editor (`LimitsView.swift:1151`).

## 2. Intent
In two seconds the user should know **what is blocked right now and until
when**, with one action: **Block now** (or **Wake up** when it's due).

## 3. What we took from Mobbin
| App | What we take | Screen |
| --- | --- | --- |
| Brick | One centred statement of the current state, one action | [home](https://mobbin.com/screens/0a3dfe67-0c4d-4d05-b139-d5d3abf76841) |
| Jomo | Usage bars per item, primary button pinned above the tab bar | [home](https://mobbin.com/screens/f7a4a7c4-cca0-4671-9493-da8989415423) |
| Structured | Vertical day thread, "now" on the line | [timeline](https://mobbin.com/screens/574482d9-3640-4553-805e-944f11f27428) |
| Lloyds, Mercury | Pending items grouped by when they land, due date per row | [Lloyds](https://mobbin.com/screens/a6626216-221f-4b1a-87e6-6e9d2c4906ef), [Mercury](https://mobbin.com/screens/7cc96da8-f0a8-4c9c-8ab5-cd2d49531a74) |
| Opal | Hold to commit; summary before editing | [editor](https://mobbin.com/screens/7bb284c6-ecb9-41f4-9c12-80bc34f02a3d) |

## 4. The rule that removes the repetition
| Question | Lives in | Not repeated in |
| --- | --- | --- |
| What's blocked now, until when? | Now card | Day thread shows it as a line item only |
| How much is left today? | Your limits (report) | Now card never quotes minutes |
| Can I get extra time? | Extra-time row under the report | Limits tab (removed there) |
| What changes next? | Changing soon (2) → Changes ledger | Rule chips just point here |
| Who am I waiting on? | The change's row in the ledger ("Waiting for Alex") | No separate "Awaiting approval" section |
| Someone needs my approval | Inbox card on Today | — |
| Usage history | Insights tab | The "Usage & trends" link is removed |

## 5. Layout, top to bottom

### 5.1 Today header
- Left: `Wordmark` (20 pt). Right: nothing, unless an approval request is
  waiting (bell with dot, scrolls to the Inbox card).
- Below: date as `label` style ("MONDAY · 2 NOVEMBER"). The 43-pt date and the
  24-hour bar are removed. Help moves to You.

### 5.2 Attention card (only when needed)
One PaperCard with `loosen` tint for the existing banners (Screen Time
permission lost, background monitoring incomplete, recovery issue). One
sentence plus one action; several issues stack as rows in the same card.
Apple 5.1.1(iv) rule unchanged: no automatic Settings redirects or re-prompts.

### 5.3 Now card (the hero)
PaperCard, 20 pt padding. Content comes from a pure function
`NowSummary.make(state:blockedLimitIDs:wakes:now:)` returning one sentence, up
to two facts and an optional action. Priority:

| # | Situation (host state) | Sentence (`hero`) | Facts (`meta`) | Action |
| --- | --- | --- | --- | --- |
| 1 | Wake tap needed | "Good morning. Your apps wait until you wake up." | Wait length per group | **Wake up** (primary, replaces Block now) |
| 2 | Wake wait running | "Your apps open at **7:42**." | CountdownText | — |
| 3 | One block active (session, planned, recurring, sleep) | "**Evening block** is on until **21:00**." | Time left; "and 2 more" if several | — |
| 4 | Several blocks active | "**3 blocks** are on. The first ends at **19:30**." | Names, comma-separated | — |
| 5 | Only spent limits | "**Games** is used up for today." | "Resets at midnight" | — |
| 6 | Free period active | "You're in a free period until **13:00**." (`free` ink) | — | — |
| 7 | Nothing | "Nothing is blocked right now." | "Next: **Evening block** at 18:00" if any | — |

- Names are the user's own rule names, never app names extracted from Apple
  tokens (privacy rule in `CLAUDE.md`).
- Times use `time` style; the time inside the sentence takes the state colour
  (`loosen` for blocks, `free` for free periods).
- Tap the card → the relevant rule's summary sheet (Rules spec); for several
  blocks → Rules filtered to active.

### 5.4 Inbox (only when someone asked for approval)
The existing `ApprovalInboxSection` restyled into one PaperCard per request:
"**Alex** asks to apply *Remove TikTok limit*", Approve (primary tint) / Deny.
Placed directly under the Now card because it is time-sensitive.

### 5.5 Your limits
- `SectionHeader("Your limits", trailing: "All rules")`.
- The existing `CompactHomeUsageReport` (report extension), restyled inside
  `LatchReport/LimitsUsageView.swift`: one row per limit — name (`cardTitle`),
  "12 of 30 min" (`meta`), 6-pt bar in `accent`; spent rows show the bar full
  in `loosen` and "Used up". Missing data reads "No data yet", never 0.
- **Extra-time row (host, new placement):** the report cannot trigger host
  actions, so under the report the host lists only limits whose
  `ExtraTimeState` is `.ready`, `.waiting` or `.active`:
  - ready: "**Games** · Get extra time (2 left)" → existing gate sheets.
  - waiting: "**Games** · extra time in" CountdownText.
  - active: "**Games** · extra time running".
- No limits: an EmptyState card "Set your first limit" with **Add a daily
  limit**, which opens the limit editor directly (not a tab switch).

### 5.6 Today's line (day thread)
- `SectionHeader("Today")`. A vertical thread (Structured-style): time on the
  left (`time`, small), a 1-pt hairline thread with dots, item on the right
  (rule name + StateChip: "On now", "18:00–21:00", "Free").
- Items, in time order: wake/sleep, recurring blocks and free periods,
  planned windows, sessions — the same sources `HomeDayTimeline` uses today
  (`HomeView.swift:678-722`), so no new scheduling logic.
- A "now" marker sits between past and upcoming items; past items fade to
  `inkSoft`. Cap at 5 items; "Full day" → Rules → Calendar.
- Hidden when there is nothing today.

### 5.7 Changing soon
- `SectionHeader("Changing soon", trailing: "All 5")` → Changes ledger.
- The next two pending changes by `appliesAt`, as **ChangeRow** (§5.9).
- Hidden when nothing is pending (the ledger keeps the empty state).

### 5.8 Bottom action
Pinned above the tab bar with `safeAreaInset(edge: .bottom)`: **Block now**
(primary capsule) → the existing `SessionStartView` sheet. Hidden while the
Wake up action is showing (one primary action per screen).

### 5.9 Changes ledger (pushed from Today)
- Title "Changes" (`pageTitle`). "Select" in the toolbar keeps the existing
  bulk Cancel N / Apply N now bar (`HomeView.swift:403-422`).
- Groups by `appliesAt` via pure `LedgerGrouping.bucket(_:now:calendar:)`:
  "Within the hour", "Later today", "Tomorrow", then weekday + date, "Later".
- **ChangeRow** (replaces `PendingChangeRow`, same inputs):
  - Line 1: StateChip "Stricter" (`accent`) / "Looser" (`loosen`), and the
    CountdownText on the right; "Applying…" when due.
  - Line 2: `change.summary` in `cardTitle`.
  - Line 3: landing time "Tue 14:32" (`meta`) · actions: **Cancel**;
    **Apply now…** only when `ChangeEngine.hasOverride` (unchanged rule).
  - If an outgoing contact request exists for this change: "Waiting for
    Alex" with the request's state; tapping opens the existing
    `ContactGateView`.
- Cancelling a single change stays immediate (as today); bulk cancel asks once.
- Empty: "No changes waiting. Changes you make wait here until they apply."

### 5.10 ChangeReceiptSheet (shared by every editor)
A medium-detent sheet shown when the user saves any edit or taps Remove,
**before** `model.queue(action)` is called.

```
[Looser change]                       ← StateChip
TikTok goes from 30 to 60 min a day   ← ChangeEngine.summary(for:state:), hero
- - - - - - - - - - - - - - - - - -
Takes effect        Tue 14:32         ← now + model.preview(action).delay
Wait                1 day
Until then nothing changes. You can cancel it from Today.
[ Hold to confirm ]                   ← HoldButton (looser) / Confirm (stricter)
Keep editing
```

- Data: `model.preview(action)` gives `(direction, delay)`;
  `ChangeEngine.summary(for:state:)` gives the sentence. Both already exist,
  so the receipt says exactly what the queued change will say.
- Delay 0 (immediate tightening): "Takes effect: right away", button
  **Confirm**, no wait line.
- Looser or removal: **HoldButton** (1.2 s). VoiceOver: the button's activate
  action opens a system confirmation ("Confirm looser change?") instead of a
  hold. Reduce Motion: same confirmation, no fill animation.
- On confirm: call `model.queue(action)`. Non-nil → dismiss the sheet and the
  editor; the rule shows its chip. Nil → keep the sheet and show the existing
  "Already pending" message inline.
- The "Takes effect" time is a preview from the current clock; the ledger
  shows the stored `appliesAt` (TimeGuard). Wording says "about" only when
  the two differ by more than a minute (never expected in normal use).

## 6. States
| State | What shows |
| --- | --- |
| First use (no rules) | Now card #7, EmptyState "Set your first limit", Block now |
| Wake due | Now card #1 with Wake up; Block now hidden |
| Report unavailable | Report card says "Usage isn't available right now"; extra-time rows still work |
| Permission lost | Attention card at top; everything else still shows saved rules |
| Recovery needed | Attention card only (existing recovery flow), no Block now |
| Many pending (50) | Today shows 2; ledger groups; Select for bulk |
| Long translated copy | Sentences wrap; chips truncate the label, never the time |

Stress: smallest iPhone (SE) — Now card, limits header and Block now must fit
the first screen; largest Dynamic Type — facts drop under the sentence, the
thread's time column moves above each item.

## 7. Components
| Need | Use |
| --- | --- |
| Cards, headers, chips, countdowns, buttons | Foundations components |
| Usage per limit | Existing `CompactHomeUsageReport` (restyled in the extension) |
| Day items | Existing segment builder in `HomeDayTimeline`, rendered as a thread |
| Session start | Existing `SessionStartView` |
| Apply now | Existing `OverrideGateView` (restyle later, behaviour same) |
| Approvals | Existing `ApprovalInboxSection`, `ContactGateView` |

Pure logic, with tests: `NowSummary.make` (each priority row, ties, midnight
crossing, several blocks), `LedgerGrouping.bucket` (hour/day boundaries, time
zone change, DST), receipt text for delay 0 / minutes / days.

## 8. Changes elsewhere
- Limits tab: the extra-time button moves to Today (removed in the Rules spec).
- Every editor that shows "%@ — takes effect in %@" (19 call sites, e.g.
  `LimitsView.swift:1154`, `SchedulesView.swift:936`, `DelayPolicyViews.swift:103`)
  switches to ChangeReceiptSheet. In this build: the limit editor and the
  Remove actions on schedules, planned, recurring and contacts (plan D9). The
  rest move with the Rules and You specs.
- Home's "Usage & trends" link and help button go away when Insights and You
  exist; until then they stay at the bottom of Today.
- Widgets: no change in this spec.

## 9. Motion and haptics
- Now card cross-fades between states (0.25 s).
- Changing soon rows slide out when cancelled.
- Receipt: HoldButton per foundations; success haptic on queue (replaces the
  current blind haptic).

## 10. Copy (English drafts; translate into all eight languages)
- "Nothing is blocked right now." / "Next: %@ at %@"
- "%@ is on until %@." / "%d blocks are on. The first ends at %@."
- "%@ is used up for today." / "Resets at midnight"
- "You're in a free period until %@."
- "Good morning. Your apps wait until you wake up." / "Your apps open at %@."
- "Get extra time (%d left)" / "Extra time in" / "Extra time running"
- "Changing soon" / "All %d" / "Changes" / "Within the hour" / "Later today" /
  "Tomorrow" / "Later"
- "Stricter" / "Looser" / "Waiting for %@"
- "Looser change" / "Stricter change" / "Takes effect" / "Right away" / "Wait"
- "Until then nothing changes. You can cancel it from Today."
- "Hold to confirm" / "Confirm" / "Keep editing" / "Confirm looser change?"
- "Set your first limit" / "Add a daily limit" / "Block now"

## 11. Out of scope
Rules, Insights and You screens; the four-tab switch; widgets; the shield;
the restyle of `OverrideGateView` and contact sheets beyond colours.

## 12. Decisions for the owner
| # | Decision | Why |
| --- | --- | --- |
| T1 | The Now card names rules ("Evening block"), not apps | Apple's app tokens are private to the report; rule names are yours |
| T2 | The 24-hour bar becomes a vertical day thread | Readable without a legend; works with large text |
| T3 | Hold to confirm lasts 1.2 s, only for looser changes and removals | Friction where Demora wants it; tightening stays one tap |
| T4 | Today hides empty sections | The page shrinks to what matters; the ledger keeps the empty message |
| T5 | Extra time moves from the Limits tab to Today, under the usage report | You look for it when you're blocked, which is where Today already is |
| T6 | "Awaiting approval" merges into the change it belongs to | One place per change |
