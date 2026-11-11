# When & where rules: free time or blocks based on place, day and time (proposal, 2026-11-11)

Status: **approved by the owner, 2026-11-11.**

Builds on the approved `docs/redesign-ux-plan.md`, `docs/foundations-redesign.md`
(tokens, PaperCard, StateChip, CountdownText, HoldButton, DayChips),
`docs/rules-redesign.md` (Rules tab, New rule chooser, RuleCard, summary sheet,
RuleEditorPage, receipt for every save) and `docs/today-redesign.md` (Now card,
extra-time rows, Changes ledger, ChangeReceiptSheet). Unlike those specs, this
one **adds a new kind of rule and new change actions**. It changes engine and
model behaviour and adds the app's first location permission, so every part
below needs the owner's yes before a build starts (CLAUDE.md: "Do not change
engine/model/service behavior without first asking the owner").

Working name for the feature in the UI: **When & where**. Internal name:
`ConditionalRule`.

## 0. Owner's call
- "I want conditional sessions/blocking with an AND/OR functionality, and I
  want to add location." Examples:
  1. In **Mexico** AND it's **Sunday** → **one free session a day, 1 hour max**.
  2. At **my house** (a place with a radius) OR **after 22:00** → **Instagram
     is blocked**.
  3. At **school** AND it's a **weekend** → **two free sessions of 30 minutes a
     day**.
- "This would **start manually**: the user goes to a place in the app, and it
  lets them verify whether the conditions are met or not. So we don't need
  background location or anything like that."

## 1. Diagnosis: what Demora can and can't do today (ranked by user impact)

1. **Every free session waits the full looser delay, wherever you are.** Block
   now → Free queues `.startSession(kind: .free)` (`Latch/RuleEditors.swift:1187-1195`),
   which is classified looser (`Shared/ChangeEngine.swift:623-625`, "unblocking
   now = lenient") and delayed by `state.delayPolicy.delay(for:)`
   (`ChangeEngine.swift:977-978`). With a 1-day looser wait, "an hour off on
   Sunday in Mexico" has to be requested on Saturday, and the session then
   starts at apply time, not when the user is ready
   (`ChangeEngine.swift:1443-1449`: "The delay already ran … session starts
   now"). The only way around it is an override (password, phrase, contact)
   with the `sessionChanges` capability (`ChangeEngine.swift:425`), which is an
   in-the-moment skip, not a past decision.
2. **No rule can depend on where you are.** Nothing in the app imports
   CoreLocation; there is no location usage string in the project (only
   `NSCameraUsageDescription`, `Latch.xcodeproj/project.pbxproj:641`). Blocks
   and free periods can depend only on clock time (`BlockSchedule`,
   `ExemptSchedule`, `PlannedWindow`, `SharedModels.swift:819-946`).
3. **Free periods can't be limited to "N times a day".** A recurring free
   period (`ExemptSchedule`) is a fixed window; a session has a length but no
   per-day count. The only per-day counter in the app is extra time
   (`LimitFeatureEntry.extraRequests`, `Shared/LimitFeatures.swift:36`), keyed
   by `SharedStore.dayKey(for: TimeGuard.now())` (`LimitFeatures.swift:290`,
   `Shared/SharedStore.swift:548`), and it grants usage minutes on one limit,
   not a free period.
4. **Conditions can't be combined.** A rule has one time window and one
   recurrence. "Weekend AND at school" or "at home OR after 22:00" need two
   rules today, or can't be expressed at all.

What already exists and is reused unchanged: `BlockSession` with kinds `.free`
and `.unblock` (`SharedModels.swift:948-1000`), session registration and cleanup
(`ChangeEngine.swift:1951-1970`, extension `session-` prefix handling,
`LatchMonitor/DeviceActivityMonitorExtension.swift:78`), free-window credit
(`ChangeEngine.swift:1245-1260`, `pruneExpiredSessions` `:1980`), monitoring
admission for sessions (`Shared/MonitoringBudget.swift:133-136`, `:206-210`), the
Now card's free row (`Latch/TodayPresentation.swift:125-128`), DayChips
(`Latch/DemoraComponents.swift:391`), the receipt and the ledger.

## 2. Intent

A When & where rule is **a past decision about when free time is allowed, or
when a block should start**. The decision waits like any looser change; using
it later is instant, but only when the conditions really hold.

In two seconds the user should know: **"Can I have free time here, right now —
and if not, which condition is missing?"**, with one action: **Check in**.

### 2.1 The model in one paragraph

A rule has **up to four conditions**, joined by **all of** (AND) or **any of**
(OR), and **one outcome**: *free time* (max length, max times per day) or a
*block* (apps, until a time). Creating, editing or removing a rule goes through
the change receipt and the normal delay (looser rules wait the looser delay).
Once a rule is in effect, the user opens it and taps **Check in**: Demora checks
day and time on the guarded clock and, only if needed, reads the location once.
Each condition shows ✓ or ✗ with a reason. If the rule is met, **free time
starts immediately** (no new wait, no override) and counts as one of today's
uses; a **block** starts like Block now. Location is read in the foreground,
once, never stored, never sent.

### 2.2 How free sessions are delayed today, and exactly what changes

| | Today: Block now → Free | When & where free time |
| --- | --- | --- |
| What waits | Each session: queued `.startSession(.free)`, looser delay (`ChangeEngine.swift:623-625`, `:977-978`) | The **rule**: `.addConditionalRule` / `.updateConditionalRule`, looser delay, through the receipt |
| Starting | When the wait ends (apply time) | When the user checks in and the conditions hold: delay **0** |
| Can it be skipped? | Yes, with a `sessionChanges` override | Creating/editing the rule: yes, with a `scheduleChanges` override (same as other rules). Starting: nothing to skip; **conditions can never be overridden** |
| Per-day cap | None | 1–5 uses per day, counted on the guarded clock |
| Length | 1 min–24 h | 5–240 min, and never past the end of the day/time window that allowed it |
| Kept? | Yes, unchanged, for anything a rule doesn't cover | — |

The new instant path is not a bypass because (a) its permission was itself a
looser change that waited, (b) it is bounded (length × uses per day), (c) the
conditions are rechecked at the moment of use and fail closed, and (d) nothing
in it accepts a password, phrase or contact as a substitute for a condition.

## 3. What we took from Mobbin

Four searches (budget five).

| App | What we take | Screen |
| --- | --- | --- |
| Quicken — create rule | Conditions stacked as cards with a small **OR** label between them; "Then make these changes" as a second block; one bottom **Continue to review** | [screen](https://mobbin.com/screens/9b1f3e96-e2dd-4766-9bc3-015c98c26367) |
| Quicken — review rule | The whole rule read back as one sentence ("If … OR … THEN …") before saving: our receipt headline | [screen](https://mobbin.com/screens/cdfc35cc-b5a9-40b2-922a-cec0f1852b4c) |
| Obsidian — filter | One plain selector at the top of the group: "All the following are true" / "Any…"; we skip "filter group" nesting | [screen](https://mobbin.com/screens/db1b63be-15e0-4c87-bdef-bbeea0d126ce) |
| Shopify — conditions | Dashed **Add condition** row under the existing ones; trash per condition | [screen](https://mobbin.com/screens/6de4fbf6-4820-4bc0-8935-f32316ebb627) |
| Google Home — add starter | Condition-type chooser as rows, each a title plus one example line ("Like 6:00 PM on weekdays") | [screen](https://mobbin.com/screens/29594098-2c40-470f-a3d6-126f48ab0e4d) |
| Linktree — rules | "If **Location** is … / Then …" with Location described as "The country they are in" | [screen](https://mobbin.com/screens/babfd250-764a-4950-b6bd-0f5cec447694) |
| Too Good To Go — choose location | A distance slider with the value in words, **Use my current location** as the main way to set the centre | [screen](https://mobbin.com/screens/ab7bd402-ae53-47ff-a5e7-26088ec3ac4e) |
| SmartThings / Todoist — geolocation | Radius shown as a circle around a pin; radius value written next to the control ("Radius: 250 m") | [SmartThings](https://mobbin.com/screens/dcb05838-d2de-4dc4-8ecd-5f47f987f531), [Todoist](https://mobbin.com/screens/34b823a4-c3fd-4877-a0e8-2bd2574edf00) |
| Citizen — alert radius | "Up to 2 km away": a capped radius phrased for people, not metres | [screen](https://mobbin.com/screens/49553e85-ce93-46c1-801f-1204acac14d8) |
| X — check back later | Requirement checklist: ✓ met, ⊗ not met, each on its own line with the fact; the page title states the verdict | [screen](https://mobbin.com/screens/596dda19-5f73-4207-b118-3b2dca5ffce1) |
| Cash App — verified | Success state: one statement, short ✓ list, one action | [screen](https://mobbin.com/screens/9e49fcb9-09c1-47c3-af91-b59ec492be6a) |

Not taken: full-screen maps as the default (komoot, Too Good To Go) because a
map loads Apple Maps tiles over the network (§5.7, C12); Obsidian's nested
groups; Quicken's purple and Binance's modal. Demora keeps paper, serif, ink.

## 4. The rule that removes the repetition

| Question | Lives in (once) | Elsewhere: link only |
| --- | --- | --- |
| Which When & where rules do I have? | Rules → **When & where** section | — |
| What does this rule allow, and when? | Rule summary sheet ("If…" / "Then…") | Card summary line (one line) |
| Can I use it right now? | **Check-in sheet** (✓/✗ per condition) | Today row and summary sheet open the same sheet |
| How many uses are left today? | Card chip and Today row ("1 left today") | Check-in sheet footer |
| Am I in free time now, until when? | Today's Now card (existing free row) | Rule card chip "Free until 14:20" |
| Is a change to the rule waiting? | Rule card pending line → Changes ledger | Summary sheet one line |
| Why does creating the rule wait? | ChangeReceiptSheet | Nowhere else |
| What does Demora do with my location? | One line on the location prompt card + help page in You | Privacy policy (website) |

## 5. Layout and behaviour

### 5.1 Condition grammar (recommended: one level, all-of or any-of)

```
ConditionalRule
  name              String (user's own, e.g. "Sunday in Mexico")
  match             .all | .any
  conditions        1…4 of:
    .place(name, latitude, longitude, radius)   radius ∈ {100, 250, 500, 1000, 2000} m
    .country(regionCode)                         ISO 3166-1 alpha-2, e.g. "MX"
    .days(Set<Int>)                              Calendar weekdays 1…7 (DayChips' type)
    .time(start, end)                            minutes after midnight; may wrap (22:00–06:00)
    .dates(firstDay, lastDay)                    optional (C6), local calendar days
  outcome           one of:
    .freeTime(kind: .free | .unblock, selection, maxMinutes 5…240, usesPerDay 1…5)
    .block(mode: .blockSelected | .blockAllExcept, selection, until: .time(min) | .duration(min))
  addedAt, revision (bumped on every applied edit)
```

Why this grammar:
- **It covers all three examples** with one level: (1) all-of {country MX,
  days {Sun}}; (2) any-of {place Home, time 22:00–06:00}; (3) all-of {place
  School, days {Sat, Sun}}. "Weekend" is one `days` condition, so the OR
  inside a set of days never needs a second level.
- **Groups** ("(A and B) or C") would need nested cards, indentation and a
  second all/any picker (Obsidian's "Add filter group"), roughly doubling the
  editor and the evaluator's test table. The rare case is two rules.
- **No NOT.** "Not at home" is true almost everywhere, so it is a weak, easily
  met condition for free time; and the UI cost of negation is high.
- **At most four conditions** keeps the check-in sheet on one screen and the
  evaluator's truth table small. **At most five rules** (same cap as day &
  night groups, `RulesPresentation.swift:1030`) bounds monitoring capacity (§5.9).
- **Time has a start and an end.** "After 22:00" is a preset that fills
  22:00–00:00; the user can drag the end to 06:00. A block needs an end, and
  free time needs a window end to cap a session (§5.6).

### 5.2 Outcomes

**Free time** (examples 1 and 3)
- Kind: **Everything** (`SessionKind.free`: nothing blocks, usage doesn't count)
  or **Only these apps** (`SessionKind.unblock` with a selection). Default
  Everything, matching the owner's "free session".
- **Up to** (DurationControl, 5–240 min, default 60) and **Times a day**
  (stepper 1–5, default 1).
- A use is started only by check-in. One running session per rule at a time.

**Block** (example 2). Recommended meaning (C3):
- **Day/time-only branches run on their own**, like a repeating block. In
  example 2, "after 22:00" blocks Instagram every night 22:00–06:00 without any
  check-in. Under the hood this branch is a `BlockSchedule` owned by the rule
  (`ownerRuleID`), so it uses the existing schedule enforcement, shields,
  precedence and capacity accounting.
- **Branches with a place or country start when you check in**: "I'm home" →
  the block starts (same strict-delay rule as Block now, C4) and runs **until**
  the chosen end ("until 07:00" default, or "for 3 h"). Demora can't see that
  you're home unless you tell it; the rule makes telling it one tap.
- Ending the block early is the existing `.endSessionEarly` (looser, waits).
  Leaving the place does not end it (no background location; C9).
- Under **all of** with a place (e.g. "at school AND weekdays 08:00–15:00"),
  nothing runs on its own; check-in starts the block, which ends at the
  earlier of its "until" and the window end (15:00).

Why not "conditions gate the block" (the block exists only while you can prove
you're home)? It would make the block depend on the user choosing to prove it,
so it would be weaker than Block now, and it would need a check-out to end,
which is a looser action keyed on location: an easy spoof target. Why not "the
block applies everywhere unless you prove you're away"? That turns example 2
into "Instagram is blocked all day except after an away check-in", which isn't
what the owner described.

### 5.3 Where it lives

```
Rules                                   [cal] [⑂]
YOUR WAITS  Stricter: right away · Looser: 1 day ›
LIMITS …
SCHEDULES …
WHEN & WHERE
┌─────────────────────────────────────────────┐
│ Sunday in Mexico               [1 left today]│
│ In Mexico, on Sundays · 60 min free         │
└─────────────────────────────────────────────┘
┌─────────────────────────────────────────────┐
│ Instagram at home      [On until 06:00]      │
│ At Home, or 22:00–06:00 · blocks 1 app      │
│ ◷ Loosens in 21h 40m                        │
└─────────────────────────────────────────────┘
DAY & NIGHT · PLANNED · ALWAYS ON
```

- **Rules**: new section **When & where** after Schedules (C7), new
  `RuleSection.conditional` (`RulesPresentation.swift:391`), new
  `RuleRef.conditional(UUID)` (`:21`). Cards use `RuleCard` unchanged.
- **Summary line** (pure `RuleSummaryLine.make`): conditions joined by ", " for
  all-of and ", or " for any-of, then " · " outcome ("60 min free", "2 × 30
  min free", "blocks 1 app"). Place and country names only, never distances.
- **Chip** (`RuleChip.live`): running free session → **Free until 14:20**
  (`free`); running block or active day/time branch → **On until 06:00**
  (`active`); free time with uses left → **1 left today** (`neutral`); none left
  → **None left today** (`neutral`); a day/time-only all-of rule that can't hold
  today → none (summary carries the days). No chip ever says "conditions met":
  location is unknown until check-in.
- **Pending line, pending addition**: as every rule (rules §5.4).
- **New rule chooser** (`NewRuleKind`, `RulesPresentation.swift:1024`): seventh
  row **When & where** (`mappin.and.ellipse`) — "Free time or a block that
  depends on place, day or time". Disabled with a reason at five rules, or
  while a change to a When & where rule is waiting for the same rule only (not
  for all, unlike day & night). The chooser sheet moves from medium to large
  detent at default type if seven rows no longer fit (check on SE).
- **Today**: new **Check in** rows directly under the extra-time rows
  (`Latch/TodayView.swift:299`), same row style, because both answer "can I get
  time now?" (today §4). Shown only for rules that could be usable now:
  free-time rules with uses left whose day/time/date conditions don't already
  rule them out (pure `ConditionalAvailability.todayRows`), and block rules with
  a place/country branch. Row: "**Sunday in Mexico** · 1 left today ·
  Check in ›". Hidden when none qualify. Max three rows; "All in Rules" after.
- **Summary sheet**: primary **Check in** (§5.5).

### 5.4 Rule summary sheet (`RuleSummarySheet`, `Latch/RuleSummarySheet.swift:65`)

```
WHEN & WHERE                         [1 left today]
Sunday in Mexico                                ← hero
- - - - - - - - - - - - - - - - - - - - - - - - -
If (all of)   ◉ In Mexico
              ▦ Sundays
Then          Free time, up to 60 min
              Once a day · everything unblocked
Today         1 of 1 left
- - - - - - - - - - - - - - - - - - - - - - - - -
[ Check in ]                                    ← primary
Edit                                            ← secondary
Remove rule                                     ← quiet, loosen ink (free rule)
```

- Fact rows: **If** with "(all of)" / "(any of)" and one line per condition,
  each with its symbol (`mappin` place, `globe` country, `calendar` days,
  `clock` time, `calendar.badge.clock` dates). Place lines read "At Home ·
  within 250 m". **Then** in words. **Today** for free time only.
- Actions: **Check in** (primary) → check-in sheet; **Edit** → editor;
  **Remove rule** → receipt. Edit is allowed (unlike free periods, rules R5)
  because `.updateConditionalRule` exists and is always looser (§5.8).
- Pending: same "A change is already waiting…" rule as other kinds, but
  **Check in stays available**: the enforced rule keeps working until its edit
  lands.

### 5.5 Check-in sheet (`CheckInSheet(rule:)`) — the manual verification

Medium/large detent sheet opened from Today, the summary sheet, or the card.

```
Sunday in Mexico
Free time needs all of these.
- - - - - - - - - - - - - - - - - - - - - -
✓  It's Sunday                    (instant)
…  Checking where you are         (spinner, ≤ 15 s)
✓  You're in Mexico
- - - - - - - - - - - - - - - - - - - - - -
How long      [ − ]  60 min  [ + ]   up to 60
Ends at 15:20 · 1 of 1 today
[ Hold to start free time ]          ← HoldButton, free ink
Not now
```

Order of work (pure `CheckInPlan.make(rule:now:)` decides it):
1. **Day, time and dates first**, on the guarded clock (§5.6). No permission,
   no location.
2. **Read location only if it can change the answer**: all-of where a
   day/time condition already failed → don't read ("It's Monday"); any-of where
   a day/time condition already passed → don't read. This keeps location reads
   to the minimum.
3. **First time only**: an in-sheet card before the system prompt — "Demora
   checks where you are once, when you tap Check in. It doesn't save or send
   your location." **Allow location** → system "While Using the App" prompt.
   If declined: place/country rows show ✗ "Location is off for Demora. You can
   turn it on in Settings." (text only, no automatic redirect or re-prompt
   loop; same caution as the 5.1.1(iv) history in CLAUDE.md).
4. **One fix**: `CLLocationManager.requestLocation()` (iOS 16 target,
   `project.pbxproj:565`), best accuracy, 15 s timeout. Accept only a fix that
   is ≤ 15 s old, has `horizontalAccuracy > 0`, and is **not**
   `sourceInformation.isSimulatedBySoftware` (iOS 15+). If iOS gives
   approximate location, request **temporary precise location** for this
   check (purpose key `CheckIn`); declined → place rows ✗ "Needs precise
   location"; country rows can still pass (§5.6).
5. **Each condition gets ✓, ✗ or "?"** with one line of reason:
   - ✓ "You're at Home" / "You're in Mexico" / "It's Sunday" / "It's after 22:00".
   - ✗ "You're not at Home" / "It's Monday" / "It's 14:05; this starts at 22:00".
   - ? (counts as ✗) "Location isn't precise enough here" / "Too close to a
     border to tell" / "This location looks simulated" / "Your clock was changed
     recently" / "Couldn't get your location. Try again outside or near a window."
   For any-of rules rows that weren't needed read "Not needed".
6. **Verdict line** in the sheet header, `hero`:
   - Met, free time: "You can have free time now." (`free`). Controls: How long
     (DurationControl capped at the rule's max and at the window end), "Ends at
     15:20 · 1 of 1 today", **Hold to start free time** (HoldButton, 1.2 s;
     Reduce Motion/VoiceOver → one confirmation, foundations §9). No receipt:
     nothing waits, and the hold is the deliberate moment.
   - Met, block: "Block Instagram until 07:00?" → **Review** → ChangeReceiptSheet
     with the stricter Confirm (it may wait the stricter delay, C4).
   - Not met: "Not right now." + the ✗ lines. Actions **Try again**, **Done**.
     No "Skip a wait", no Apply now, no override of any kind.
   - Met but no uses left: "You've used today's free time." Resets at midnight.
   - Met but a session of this rule is running: "Free time is on until 15:20."
7. **Freshness**: a result is valid for 2 minutes; Start after that re-runs the
   check. Closing the sheet discards the coordinates and the result.

### 5.6 Trust, clocks and bypass — conservative defaults

| Risk | Default |
| --- | --- |
| Spoofed GPS (Xcode, simulators, some accessories) | `isSimulatedBySoftware` → "?" (fail). `isProducedByAccessory` → "?" for free time. Jailbreak-level spoofing is out of reach; say so in help, as with other self-control limits |
| Huge radius drawn to cover a city | Radius is a choice of 100 / 250 / 500 m / 1 / 2 km (C10); no free entry, cap 2 km |
| Place moved after creation | Adding or editing a rule, including any place inside it, is always a looser change with the full wait (same precedent as selection edits, `SharedModels.swift:1156-1159` and `:1183-1185`) |
| GPS uncertainty at the edge | Free time: met only if the **whole** accuracy circle is inside (distance + accuracy ≤ radius). Block: met if the circle **touches** the place (distance − accuracy ≤ radius). Doubt always favours the stricter result |
| Country near a border | Free time: met only if the point is inside and farther than accuracy + 2 km from any border; else "Too close to a border to tell". Block: inside is enough |
| Device clock changed to "Sunday" or "23:00" | Day/time/date conditions use `TimeGuard.now()` in `Calendar.current`. If `abs(Date() − TimeGuard.now())` exceeds TimeGuard's own 300 s tolerance (`Shared/TimeGuard.swift:23`), day/time rows show "?" "Your clock was changed recently". Known residual gap: clock change + reboot (`TimeGuard.swift:8`) |
| Time zone changed to make it "after 22:00" | The app records the time zone it last saw and when (TimeGuard). If it changed in the last 12 h, a day/time condition must hold **in both** zones. Real travel (arriving in Mexico on Sunday) still works on the same weekday |
| "Per day" across midnight | Uses count on `SharedStore.dayKey(for: TimeGuard.now())` at start, like extra time (`LimitFeatures.swift:290`). The count is persisted in `LatchState` and never decreases within a day; ending early does not refund |
| Session running past the window that allowed it | A free session ends at the **earlier** of its length and the end of the day/time/date window that made the rule true (example 1 at 23:30 Sunday ends at 00:00, not 00:30). Location-only branches cap at the length |
| Conditions stop holding mid-session | Not rechecked (no background location). Bounded by length and window end. Ending early = existing `.endSessionEarly` |
| Edit waiting while a session runs | The running session keeps its end; the enforced rule version keeps working for new check-ins until the edit applies |
| Rule removed while a session runs | The session keeps its end (at most 4 h) — simpler and bounded; End early is available. Alternative: removal also ends it (C14) |
| Two checks racing | `conflictKey` "conditional-<id>" (one start at a time) and the per-day count re-validated inside the state mutation |
| Monitoring capacity full | Capacity is reserved when the rule is added (§5.9), so a later check-in doesn't depend on luck; if admission still fails: "iOS can't track another session now." |
| Due changes not yet applied | Check-in refuses while `hasUnappliedDueChanges` (`ChangeEngine.swift:1089`), like extra time, so a just-landed stricter change applies first |

### 5.7 Places and countries

**Place editor** (sub-page of the rule editor):
```
Name          Home
Centre        ◉ Set to where I am now        ← one-shot read, same rules as §5.5
Size          (100 m)(250 m)(500 m)(1 km)(2 km)
              "About a house and its street"  ← words for each size
              Show on map ›                   ← optional, loads Apple Maps (C12)
```
- The centre is set **from the current location** (Too Good To Go's "Use my
  current location"). Optional **Show on map** opens a MapKit map with the
  circle (SmartThings/Todoist) where the pin can be dragged; one line above it:
  "Apple Maps loads the map for this area." No address search in v1 (it sends
  the text to Apple; C12).
- Stored on the device only: name, latitude, longitude (rounded to 5 decimals,
  ~1 m), radius. Nothing about when the user was there.
- "Use a place from another rule" copies its centre and size (no shared place
  library in v1: a shared place would make one edit loosen several rules; C11).

**Country picker**: searchable list of `Locale` region names (localized by iOS
in all eight languages), plus **Use the country I'm in** (one-shot read +
offline lookup). Recommended lookup: **bundled, simplified country borders**
(Natural Earth 1:50m admin-0, public domain), point-in-polygon on device (C5):

| Option | Network | Works abroad without data | Size / cost | Accuracy | Verdict |
| --- | --- | --- | --- | --- | --- |
| **Bundled borders, offline lookup** | None | Yes | ~0.5–1 MB in the app (to measure); a pure lookup with tests | ~1 km at 1:50m; border margin handles it | **Recommended** |
| `CLGeocoder.reverseGeocodeLocation` | Sends coordinates to Apple each check | No | No bundle; rate-limited | Good | Fallback only if C5 is "no" |
| `Locale.current.region` / time zone | None | Yes | None | Is a setting, not a location; trivially changed | Rejected |
| Country as a 2 km place | None | Yes | None | Can't cover a country | Rejected |

Disputed areas follow the dataset's default borders and read as "Too close to a
border to tell" within the margin; Demora never draws borders on screen.

### 5.8 Changes and the engine (new actions; all through the receipt)

| Action (new) | Direction | Delay | Conflict key | Override capability |
| --- | --- | --- | --- | --- |
| `.addConditionalRule(rule)` | Free time → looser; Block → stricter | Policy | `conditional-<id>` | `scheduleChanges` |
| `.updateConditionalRule(rule)` | **Always looser** (preserves id, today's count, running session) | Looser | `conditional-<id>` | `scheduleChanges` |
| `.removeConditionalRule(id)` | Free time → stricter; Block → looser | Policy | `conditional-<id>` | `scheduleChanges` |
| `.startConditionalSession(ruleID, revision, minutes, stamp)` | Free time → looser **with delay 0 when validated**; Block → stricter (policy) | 0 / strict | `conditionalStart-<id>` | `sessionChanges` (no effect at delay 0) |

- `stamp` = check-in id, guarded time, day key, time-zone id, and one boolean
  per condition. **No coordinates.**
- Queue (`queueCoordinated`, `ChangeEngine.swift:879`): validate the rule is
  enforced with that `revision`, the stamp is ≤ 2 min old and its day key is
  today, day/time conditions re-evaluate true now, uses < max, no session of
  this rule is running, no unapplied due changes; then delay 0 for free time.
  Any failure returns nil (no fallback to a delayed free session).
- Apply (`ChangeEngine.swift:1313`): re-validate the same facts; append a
  `BlockSession` with new optional `conditionalRuleID`, `endsAt` = min(length,
  window end), and increment `state.conditionalUses[ruleID]` (day key + count)
  in the same saved state. Stale → dropped, nothing applied.
- `BlockSession.activityName` becomes `session-cond-<ruleID>` for conditional
  sessions (one per rule at a time), so the extension's `session-` prefix
  cleanup (`DeviceActivityMonitorExtension.swift:78`) works unchanged and the
  reservation name equals the real one.
- `ChangeEngine.summary` reads the rule back as one sentence (Quicken review):
  "If you're in Mexico and it's Sunday: 60 min free, once a day." Place and
  country **names only**.
- `RulePending.index` (exhaustive switch) maps the three rule actions to
  `.conditional(id)`.
- Housekeeping: `conditionalUses` entries from earlier days are pruned on
  rollover; never rewritten within the day.

### 5.9 Monitoring capacity (20 activities, `MonitoringBudget.swift:5`)

- A free-time rule reserves its latent session `session-cond-<ruleID>` and,
  with limits present, `latch.freewin` (same latent-needs principle as
  `MonitoringBudget.swift:128-129`). `profile`, `project` and `isRepair` gain
  the new cases; `.removeConditionalRule` is a repair.
- A block rule reserves its owned schedule windows (via `windows(prefix:…)`,
  1–2 names) and `session-cond-<ruleID>`.
- Worst case for five rules: ~10–15 names. The chooser and the receipt refuse
  with today's capacity message if admission fails; no eviction except the
  existing optional midnight echoes.

### 5.10 Editor (`ConditionalRuleEditor`, on `RuleEditorPage`)

```
New When & where rule                       Cancel
Name     [Sunday in Mexico              ]
IF
  ( All of these | Any of these )            ← segmented (Obsidian)
  ┌ ◉ In Mexico                       🗑 ┐
  └────────────────────────────────────┘
               and                           ← small label (Quicken)
  ┌ ▦ Sundays                         🗑 ┐
  ┌ ┄ + Add condition ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ ┐   ← dashed (Shopify)
THEN
  ( Free time | Block )
  Free:   Everything / Only these apps · Up to 60 min · Times a day 1
  Block:  Apps ›  · Until 07:00
[ Review change ]
```
- **Add condition** opens a small chooser (Google Home): Place — "Like home or
  school"; Country — "Like Mexico"; Days — "Like weekends"; Time — "Like after
  22:00"; Dates — "Like a trip". Disabled at four conditions.
- Days: DayChips with **Weekdays** / **Weekend** shortcuts. Time: From/To
  dotted thread (rules §5.7 B) with an **After 22:00**-style shortcut.
- Block + any-of with a day/time branch: one note — "From 22:00 this blocks on
  its own. At Home it starts when you check in."
- Free time with **Everything**: one note — "Free time lifts every block,
  including day & night, while it runs."
- Validation (`EditorValidation.conditional`): ≥1 condition; place has a
  centre; time start ≠ end; dates last ≥ first; free time ≥ 5 min; apps chosen
  for Only these apps / Block; a block rule with only day/time conditions →
  "Use a repeating block for rules without a place." (no duplicate kinds).
- Review change → ChangeReceiptSheet; headline is the one-sentence summary.

## 6. States

| State | What shows |
| --- | --- |
| Loading | Never blank (state is local). Check-in rows evaluate day/time instantly; location row shows a spinner ≤ 15 s |
| Empty / first use | No section in Rules; the chooser row is the entry point. Today shows no Check in rows |
| Location never asked | In-sheet card before the system prompt (§5.5 step 3) |
| Location denied / restricted | ✗ rows with "Location is off for Demora…"; day/time-only rules keep working |
| Approximate location only | Temporary precise request; declined → places ✗, countries can pass |
| No GPS fix / timeout | "?" row, **Try again** |
| Simulated location / clock changed | "?" rows with reason; fail closed |
| Conditions met / not met / no uses left / already running | §5.5 step 6 |
| Rule edit waiting | Card pending line; Check in still uses the enforced version |
| Recovery needed | Rules read-only; Check in disabled with the existing recovery message |
| Capacity full | Receipt/Check in show today's capacity message |
| Rule removed while sheet open | "This rule has been removed." + Done |

Stress tests: German/Polish/Hindi condition lines wrap (two lines max, then
truncate the place name, never the ✓/✗); four conditions + outcome controls fit
the large detent on SE at default type; largest Dynamic Type stacks the How long
control under its label; five rules in Rules and three Today rows; a rule
crossing midnight (22:00–06:00) on DST change nights; a Sunday session started
at 23:50 (ends 00:00); time-zone change Madrid → Mexico City on a Sunday.

## 7. Components

| Need | Use (reuse first; new only with a reason) |
| --- | --- |
| Cards, chips, countdowns, hold button, day chips, duration | Foundations components; `DurationControl` |
| Rule card, summary sheet, editor scaffold, receipt, ledger | Rules/Today specs, unchanged |
| Apps | `AppsRow`, `AppPickerSheet` |
| Time window | The repeating editor's From/To rows |
| **ConditionRow** (new) | Icon + text + trash; reused by editor (editable) and summary/check-in (read-only, with ✓/✗/?) — one row in three places |
| **CheckInSheet** (new) | The verification flow; nothing existing checks conditions |
| **PlaceEditor** (new) | Centre from current location, size chips, optional map |
| **LocationCheck** (new service, host only) | One-shot `CLLocationManager` wrapper with timeout, freshness, simulated/accuracy checks; returns a fix in memory only. Never in extensions |
| **CountryLookup** (new, pure + bundled data) | Offline point-in-polygon with border distance |

Pure logic, with tests (new `Tests/ConditionalRulesHarness.py`, style of the
presentation harnesses, compiling Shared fragments with stubs):
- `ConditionEvaluator.evaluate(rule:now:calendar:zones:fix:outcome:)` → per
  condition ✓/✗/?/not needed; all/any; "?" fails; edge geometry asymmetry
  (free vs block); midnight-wrapping time; DST; dates; two-zone rule.
- `CheckInPlan.make` → whether to read location (the four all/any × pass/fail cases).
- `ConditionalSessionPlan.end(start:minutes:rule:calendar:)` → window caps.
- `ConditionalUses` → day key on guarded clock, monotonic count, rollover prune.
- `ChangeEngine.classify` / `conflictKey` / `summary` for the four actions;
  queue/apply validation table (stale revision, old stamp, wrong day, uses
  spent, running session, due changes).
- `MonitoringBudget.profile/project/isRepair` for the new cases, five-rule
  worst case.
- `CountryLookup` fixtures: Mexico City, Tijuana near the US border, open sea,
  a point within the margin; size budget of the bundled file.
- `RuleSummaryLine`, `RuleChip.live`, `ConditionalAvailability.todayRows`,
  `EditorValidation.conditional`.
Device-only checks (no simulator runtime on this Mac): permission prompts,
precise/approximate, real fix timing, temporary precise, session start and
end while the app is closed.

## 8. Changes elsewhere

- **Model**: `LatchState.conditionalRules`, `conditionalUses`, last-seen time
  zone; `BlockSession.conditionalRuleID`; `BlockSchedule.ownerRuleID` (all
  optional, tolerant decode). No migration of existing rules.
- **Engine**: four `ChangeAction` cases (§5.8); apply/queue validation;
  housekeeping prune; owned schedule removed in the same change as its rule.
- **Info.plist (host only)**: `NSLocationWhenInUseUsageDescription` — "Demora
  checks your location once when you tap Check in, to see if a rule's place
  applies. It isn't saved or sent." and
  `NSLocationTemporaryUsageDescriptionDictionary` (`CheckIn`). These strings are
  shown by iOS, so they need an `InfoPlist.xcstrings` in all eight languages —
  the camera string today is English-only (`project.pbxproj:641`). No
  background modes, no "Always".
- **Privacy manifest** (`Latch/PrivacyInfo.xcprivacy`): no required-reason API
  for CoreLocation; collected data types unchanged **if** nothing leaves the
  device (C5, C12). Add a comment saying location is processed on device only.
- **App Store privacy label**: unchanged under the offline recommendation
  (data processed only on device isn't "collected"). If C5 picks the geocoder
  or C12 keeps a map: to be confirmed by the owner against Apple's current
  definitions; I would not declare Apple's own Maps/geocoding as our collection,
  but it must be disclosed in the policy.
- **Website** (`demora-website/privacy-policy.html:147-150` says "We do not
  collect … location data"): still true, but add a short "Location
  (optional)" section: read only when you tap Check in; checked on your device;
  saved places stay on your device (and in your device backup); never sent to
  us; if you open the map, Apple Maps loads that area. Separate repo and
  deploy, owner's call.
- **Trusted contacts / email**: approval requests carry `change.summary` to
  contacts (CloudKit, encrypted for keyed contacts, `Latch/ContactsService.swift:273-276`;
  email via the relay, `:66`). Summaries therefore contain **place names** but
  never coordinates or sizes. Flag in help: "A contact approving this change
  sees the place's name."
- **App Review notes**: how to test with a place near the reviewer (they won't
  be in Mexico); location requested only on Check in.
- **Today**: Check in rows; Now card unchanged (free sessions already show as
  row 6, `TodayPresentation.swift:125-128`; name = rule name).
- **You → How Demora works**: one help page "When & where" (privacy lines,
  limits of location checks).
- **Widgets, shield, report extension, Insights**: no change.
- **Localization**: all eight catalogs; country and weekday names come from
  iOS.

## 9. Motion and haptics
- Check-in rows resolve one by one (0.2 s fade per row); the spinner is the
  system one. Reduce Motion: rows appear at once.
- ✓ light haptic per met row is noise — **one** success haptic on the verdict
  "You can have free time now", one warning haptic on "Not right now".
- HoldButton per foundations; free-time hold uses `free` ink.

## 10. Copy (draft; refine and translate into all eight languages)
- Chooser: "When & where" — "Free time or a block that depends on place, day or time" / "You can have up to five When & where rules."
- Section/kind: "When & where" / "WHEN & WHERE"
- Editor: "If" / "Then" / "All of these" / "Any of these" / "and" / "or" / "Add condition" / "Place" — "Like home or school" / "Country" — "Like Mexico" / "Days" — "Like weekends" / "Time" — "Like after 22:00" / "Dates" — "Like a trip" / "Free time" / "Block" / "Everything" / "Only these apps" / "Up to" / "Times a day" / "Until" / "Weekdays" / "Weekend" / "After %@"
- Notes: "From %@ this blocks on its own. At %@ it starts when you check in." / "Free time lifts every block, including day & night, while it runs." / "Use a repeating block for rules without a place."
- Place: "Set to where I am now" / "About a house and its street" (100 m) / "A building and its grounds" (250 m) / "A campus or a few blocks" (500 m) / "A neighbourhood" (1 km) / "A small town centre" (2 km) / "Show on map" / "Apple Maps loads the map for this area." / "Use a place from another rule" / "Use the country I'm in"
- Summary: "At %@" / "In %@" / "On %@" / "%@–%@" / "%@ to %@" / "%d min free" / "%d × %d min free" / "blocks %d apps" / "%d left today" / "None left today" / "%d of %d left"
- Check-in: "Check in" / "Free time needs all of these." / "Free time needs any of these." / "Checking where you are" / "You're at %@" / "You're not at %@" / "You're in %@" / "You're not in %@" / "It's %@" / "Not needed" / "Location isn't precise enough here" / "Needs precise location" / "Too close to a border to tell" / "This location looks simulated" / "Your clock was changed recently" / "Couldn't get your location. Try again outside or near a window." / "You can have free time now." / "Not right now." / "You've used today's free time." / "Free time is on until %@." / "Ends at %@ · %d of %d today" / "Hold to start free time" / "Block %@ until %@?" / "Try again" / "Not now"
- Permission: "Demora checks where you are once, when you tap Check in. It doesn't save or send your location." / "Allow location" / "Location is off for Demora. You can turn it on in Settings."
- Receipt summaries: "If %@: %@." (one sentence assembled from the parts above)

## 11. Out of scope
- Background location, geofencing (`CLMonitor`/region monitoring), "Always"
  permission, automatic start on arrival or end on leaving.
- Nested condition groups, NOT, more than four conditions, more than five rules.
- A shared place library; address search; Wi-Fi/Bluetooth/Focus conditions;
  iOS Shortcuts/Focus automations as triggers.
- Mac app (separate product; no location there).
- Changing Block now → Free (it keeps its full wait).
- Using conditions to gate extra time, removals or setting changes.

## 12. Decisions for the owner

| # | Decision | Why |
| --- | --- | --- |
| C1 | Add **When & where** as a new rule kind: up to 4 conditions joined by **all of** or **any of**, one outcome (free time or block). No groups, no NOT | One level covers all three examples; groups double the editor and tests; NOT on places is too easy to meet |
| C2 | **Creating or editing a rule waits** (free-time rules: looser delay; block rules: stricter); **starting free time from a met check-in is instant**, capped by length and times per day, and **never overridable** | The rule is the past decision; the instant start is bounded and rechecked, so it's not a new bypass |
| C3 | A **block** rule's day/time-only branch runs on its own (like a repeating block); a place/country branch **starts on check-in** and runs until a chosen end; leaving doesn't end it | Matches example 2 without background location; a block that needs proof to exist would be weaker than Block now |
| C4 | A check-in block follows your **stricter** wait, exactly like Block now (instant when your policy tightens instantly) | Keeps "tightening follows the configured policy" with no special case. Alternative: always instant |
| C5 | **Country by bundled offline borders** (Natural Earth, public domain, ~0.5–1 MB), not Apple's reverse geocoder | No network, works abroad without data, privacy promise intact. Cost: app size and a data file to maintain |
| C6 | Include **Dates** ("between 20 and 27 Dec") as a fifth condition type | Cheap (pure calendar check) and fits trips; drop if you want the smallest v1 |
| C7 | Rules section **When & where** after Schedules; **Check in** rows on Today under extra time; **Check in** as the summary sheet's primary action | Owner asked for "a place in the app" to verify; Today is where "can I get time now?" already lives |
| C8 | Location is read **only when you tap Check in, only when it changes the answer**, "While Using" only, one fix, never stored or logged; places store only name, centre and size | Minimum location use; no history |
| C9 | Conservative trust defaults: fail closed on unknown; simulated locations rejected; whole GPS circle must be inside for free time; 2 km border margin; guarded clock; time-zone change in last 12 h → must hold in both zones; session ends at the window end; uses never refund | Each closes a cheap bypass without hurting normal use |
| C10 | Place size is a choice of **100 / 250 / 500 m / 1 / 2 km**, cap 2 km | Stops "radius = whole city"; the words make sizes understandable |
| C11 | Places live **inside each rule** (with "use a place from another rule" copying it); no shared library in v1 | One edit can't silently loosen several rules |
| C12 | Set a place from **where you are now**; **Show on map** is optional and says Apple Maps loads the area; no address search | Default path sends nothing; map tiles and search are Apple network requests to disclose |
| C13 | Free time outcome offers **Everything** (default) or **Only these apps** | Matches "free session"; the narrower option exists in the engine already |
| C14 | Removing a free-time rule lets a running session finish (≤ 4 h) | Simple and bounded. Alternative: removal ends it at once |
| C15 | Build order in separate sessions: (1) model + engine + capacity + harness; (2) editor, Rules card, summary; (3) check-in with day/time only + Today rows; (4) places + location permission + Info.plist strings in 8 languages; (5) countries (bundled data); (6) block outcome | Each step is verifiable alone; location arrives only after the engine is proven |

### Open questions (with my recommended answer)

| # | Question | Recommended answer |
| --- | --- | --- |
| Q1 | Should a check-in ever end a block early ("I've left home")? | **No** in v1 — a location-keyed loosening is the easiest thing to spoof; End early waits as today |
| Q2 | Should the conditional free time count toward / be blocked by a pending stricter change (e.g. a new limit due in 5 min)? | **No extra rule**: check-in already refuses while due changes are unapplied; future pending changes don't affect enforced state |
| Q3 | Should trusted contacts be able to approve a check-in that failed? | **No** — conditions are never overridable (C2); contacts can still approve the rule's creation via `scheduleChanges` |
| Q4 | Should disputed borders follow Apple's region list or the dataset? | Dataset's default borders for lookup, Apple's names for display, "can't tell" within the margin; revisit if App Review raises it |
| Q5 | Is the website privacy update needed before shipping? | **Yes**: ship the policy section with the release (owner deploys `demora-website`) |
| Q6 | Show the place's map in the summary sheet? | **No** — it would load Apple Maps every time the sheet opens; text "At Home · within 250 m" is enough |
| Q7 | Allow the same rule to start free time while another rule's free time runs? | **Yes** (they're independent, each capped); only one running session per rule |

### Changes to Demora's privacy promise (flag for the owner)

1. **New permission**: Location "While Using the App" (first location use in
   the app). Purpose strings must be localized (new `InfoPlist.xcstrings`).
2. **Location data at rest on the device**: saved place centres (no history)
   in the App Group state; included in the device backup like other app data.
3. **No new network traffic** under C5 + C12 defaults. If you choose the
   geocoder (C5 "no") or use the optional map/search, coordinates or map areas
   go to **Apple**; disclose it.
4. **Place names reach trusted contacts** inside approval summaries
   (CloudKit, or email through the relay, which can read the email).
5. **Website privacy policy** needs a "Location (optional)" section; the
   existing "We do not collect … location data" sentence stays true.
6. **App Store privacy label and privacy manifest**: no change expected under
   the offline defaults; confirm before submission.

## Owner's answers (2026-11-11)
Approved as written, including decisions C1–C15 and the recommended answer to
every open question (Q1–Q7): check-in never ends a block early; no extra rule
for pending stricter changes; contacts can't approve a failed check-in;
dataset borders with Apple's names and a "can't tell" margin; the website
privacy section ships with the release; no map in the summary sheet; separate
rules' free time may run at once (one session per rule). Build in the C15
order, one session at a time.
