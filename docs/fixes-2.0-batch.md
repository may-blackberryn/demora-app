# 2.0 fixes batch: clock, contacts, Today thread, small polish, iPhone Duo

Status: **approved by the owner on 2026-11-13** ("Approve, ship in 2.0.0"). Written 2026-11-13 from
the owner's report and screenshots: Changes list, Today thread, blank "Your
limits" card. Code was read by three investigations; file:line references
below are from HEAD `4c41c5d`.

Decisions are F1–F6. Questions for the owner are Q1–Q3, each with a
recommendation.

---

## F1. The protected clock stops while the phone sleeps (bug, engine)

**What the owner saw.** At 11:55 the Changes list showed "Change limit:
games" landing at 11:19 AM with 1:44 left, and the change was not applied.
Both cards were off by the same 37 min 43 s.

**Cause.**
- `TimeGuard.now()` (`Shared/TimeGuard.swift:26-47`) is computed as
  `anchorWall + (systemUptime − anchorUptime)`.
- `ProcessInfo.systemUptime` does **not** advance while an iPhone sleeps.
- After more than 300 s of sleep since the last anchor, the guard treats
  the wall clock as tampered with and returns the slow derived time.
- Every "is it due?" check and every countdown uses that slow clock, so
  locked time never counts.
- A network re-sync fixes it only about once an hour.
- The background apply activity is scheduled on the wall clock with a
  30-minute window (`ChangeEngine.swift:2436-2461`). It fires while the
  guard still says "not due", and it is never rescheduled.
- The App Store build very likely has the same bug, because `TimeGuard`
  has barely changed since July.

**Fix.**
1. **Clock.** Base `TimeGuard` on a clock that keeps running during sleep
   but still resets on reboot: `clock_gettime_nsec_np(CLOCK_MONOTONIC)`
   (Darwin's monotonic clock includes sleep). Do this for `now()` and
   `nowForDisplay()`.
   - Migrate the stored anchors once, using a version key and a re-anchor.
     The re-anchor must never move a deadline earlier.
   - Reboot detection, the "don't shorten waits after clock changes"
     invariant and the uptime-versus-wall distinction are kept.
   - The fix only makes waits end at their true real-world time instead of
     late.
2. **Apply activity.** In `scheduleApplyActivity`, convert the guarded
   deadline to wall time the way `scheduleRelease` already does
   (`ChangeEngine.swift:107-110`). Reschedule apply activities for pending
   changes that aren't due yet in housekeeping.
3. **Foreground re-sync.** In `AppModel.tick()`, skip the hourly limit on
   the network re-sync when the wall clock and the guarded clock disagree
   by more than 5 min. Run that check before applying due changes.
4. **Changes card.** Read every time on the card from the same clock: the
   landing time, the group header and the countdown.
5. **Regression harness.** Anchor, move wall time 40 min ahead with uptime
   moving 2 min, and the continuous clock moving 40 min. Assert `now()`
   follows real time and the change counts as due. Also assert a
   wall-clock jump forward with no real elapsed time is still rejected.

---

## F2. Trusted contacts: pair now, approve after the wait

**Owner's rule.** Adding and verifying a contact happens immediately. The
wait applies only to when that contact's approvals start to count.

**Today.** The whole add is the delayed `.addContact` change. The contact
isn't saved until it lands, so no invite, email code or safety code can go
out for hours.

**Change.**
1. **Model.** `TrustedContact` gets `awaitingActivation: Bool`. It decodes
   as `false`, so existing contacts are unaffected.
   - `isUsable` becomes `accepted && !awaitingActivation`.
   - That one property already guards every approval path:
     `contactPermitted`, `hasOverride`, skip eligibility, the extra-time
     gate and the rule editors.
2. **Queue.** Queuing `.addContact` saves the contact at once, with the
   flag set, in the same coordinated write as the pending change. The
   existing invite and email loops then send right away.
3. **Apply.** Applying the change clears the flag on the saved contact.
   - If that contact was removed or declined in the meantime, nothing
     happens; it never comes back.
   - "Apply now…" works the same way through the existing skip gate.
4. **While waiting.** The You list shows "Can approve from Tue 2:32 pm"
   (with "Waiting to accept · …" if they haven't accepted yet).
   - The detail page shows the same strip, with a link to it in Changes.
   - Permission edits are disabled until activation.
5. **Remove before activation.** This cancels the pending add and drops the
   contact in one write, immediately.
   - That's allowed because removing is stricter.
   - The CloudKit invite is cleaned up by the existing reconcile.
   - A decline also drops the pending add.
6. **Migration.** Adds already waiting are converted once, in housekeeping:
   the contact is saved with the flag set, and its `appliesAt` is
   unchanged. Invites go out earlier; nobody can approve sooner.
7. **Copy.** Update the wording in all 8 languages: "Adding a contact goes
   through a delay" becomes "They can approve once the wait ends".
8. **Backend.** None. CloudKit records and the Worker are unchanged, and
   activation is enforced only on the owner's device.

---

## F3. Today thread: positions that match today's clock

**What's wrong.**
- Rows are ordered and labelled by each occurrence's raw start time.
- Yesterday's overnight block ("thu 10:00 pm", ended 5 am) sits at the top
  of Friday's card with yesterday's label.
- Rows that are on now sit above the now line, mixed in with ended rows.
- The chip repeats the label's time.
- Every dot looks the same.

**New rules** (amends `docs/today-redesign.md` §5.6). Three bands, each in
its own order:

| Band | Which rows | Order | Left label | Chip | Dot |
| --- | --- | --- | --- | --- | --- |
| Ended earlier today | end ≤ now, ended today | by end | end time ("5:00 am") | "ended", plus soft "since thu 10:00 pm" if it began before today | small, dim, filled |
| *now line* | | | current time | | |
| On now | started, not ended (or waiting for a wake tap) | soonest end first | none | "until 3:00 pm" / "until sat 5:00 am" | filled, state colour |
| Later today | starts later today | by start | start time | only the end: "until 11:30 pm" / "until sat 5:00 am" | hollow, state colour |

**Rules for all bands**
- The left column has a fixed width and only ever shows today's clock;
  weekdays go in the chip.
- At most 2 ended rows are shown.
- With 5 rows max, keep rows in this order: on now, then later today, then
  ended (most recent first).
- The thread line stops at the last dot.
- "full day" shows only when rows were hidden.
- VoiceOver reads one sentence per row, e.g. "bad apps, ended at 5:00 am".

**Tests.** Update `Tests/TodayPresentationHarness.py` with these cases:
- an ongoing overnight tail at 3 am;
- an ended tail at noon;
- tonight's block running past midnight;
- the cap;
- a 23-hour daylight-saving day.

---

## F4. "Block now" becomes "New session"

- Rename the Rules add-menu item, editor title and Home action from
  "Block now" to **"New session"** in all 8 languages. The subtitle stays
  "Block apps for a set time, starting soon", so it's still clear the
  session blocks.
- Internal names (`.blockNow`) are unchanged.

---

## F5. Blank "Your limits" card

**Why it happens.**
- The card's contents are drawn by Apple's Screen Time report extension,
  in a process the app can't see into.
- iOS sometimes renders nothing, with no signal the app can detect.
- It can't be fully prevented.

**Mitigation.**
1. Draw a quiet line behind the report: "Your limits will show here. Pull
   down to refresh if it stays empty." When the report renders, its opaque
   background covers it.
   - The builder confirms that the report extension's root background is
     opaque, or makes it opaque.
2. Retry once automatically about 3 s after the card appears, using the
   existing refresh-by-filter mechanism; no view recreation.
3. Remove the old dismissible note, since the line in item 1 replaces it.

---

## F6. iPhone Duo

**What's needed.**
- Apps fill the inner display only when built with the **iOS 27.1 SDK
  (Xcode 27.1)**.
- Built with the 27.0 SDK, apps use most of the screen but leave blank
  space.
- Older builds are letterboxed.
- This Mac has Xcode 27.0 and no simulator runtimes.

**Change.**
1. The owner installs **Xcode 27.1**, plus the iOS 27.1 simulator runtime
   for the iPhone Duo device in Device Hub. If 2.0.0 is built by Xcode
   Cloud, also set its workflow to Xcode 27.1.
2. **Code.**
   - Replace the two `userInterfaceIdiom` checks
     (`Latch/UsageInsightsView.swift:87`, `Latch/LatchApp.swift:41`) with
     size-class checks.
   - Make sure screens keep a readable maximum width on the wide inner
     display, as on iPad.
   - Confirm that nothing uses `UIScreen.main`.
3. **Check in the Duo simulator.** Test folded and open, Split View on each
   side, the sheets, the Today thread, the report card and the tab bar.
   Run Xcode's App Resizability check.
4. iPhone stays portrait-only. The inner display may ignore that, and the
   app has to look right either way.

---

## Build order (one writer at a time, verify and commit per step)

1. F1 clock: engine; needs the strongest review.
2. F2 contacts.
3. F3 + F4 + F5: Today and copy.
4. F6 Duo, once Xcode 27.1 is installed.

After that:
- a fresh reviewer for each step;
- the decision log in `docs/redesign-review.md`;
- install on the iPhone, then the owner's test list:
  - lock the phone across a change's deadline;
  - add a contact;
  - check the Today thread at night and at noon.

## Questions for the owner (answered)

- **Q1. Ship these in 2.0.0 or 2.0.1?**
  - Recommendation: **2.0.0**, as build 68. The 2.0.0 build isn't uploaded
    yet.
  - F1 breaks the app's core promise: changes land late after the phone
    sleeps.
- **Q2. Can an existing trusted contact skip the activation wait for a new
  contact?**
  - Recommendation: **yes, as today.** The "Trusted contacts" skip already
    covers contact changes.
  - The new contact can never approve their own activation.
- **Q3. Is installing Xcode 27.1 OK?**
  - It's a large download from the Mac App Store or developer.apple.com.
  - You install it; F6 waits for it. F1–F5 don't need it.

### Owner's answers (2026-11-13)

- Q1: **2.0.0**, build 68, before the upload.
- Q2: recommendation accepted by approving the plan: an existing trusted
  contact may skip a new contact's activation wait, as today.
- Q3: the owner installs Xcode 27.1; F6 waits for it.
