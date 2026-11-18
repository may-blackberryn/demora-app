# 2.0.1 blocking fixes

Owner request (2026-11-17): blocking got much less reliable in 2.0. A spent
limit ("socials", Used up) was not blocked even with the app open, and the
"Background blocking may be incomplete" banner showed with only three limits,
one wake/sleep group, one schedule and one When & where rule. After a full
review of the blocking code (seven areas, findings checked against source),
the owner said: "implement the full sweep of fixes". No JetsamEvent reports
exist on the phone this month, so extension memory is not treated as a cause.

Branch `fix/blocking-2.0.1` from `5cc0eba` (2.0.0, in App Review). The real
1.x baseline is `7fa886d` (1.1.7), not `160d285`. Engine behaviour changes
below are authorized by that request; everything else in `CLAUDE.md` stands.

## Root causes (summary)

1. Callbacks applied shields last, after widget/notification publishing and
   other optional work; a killed extension left nothing blocked.
2. Shield refresh read spent limits from the defaults copy, which can lag the
   locked file the extension writes; the open app's refresh could drop a
   fresh block.
3. Free-time usage after a free period really ended was credited as free,
   raising the limit's threshold. Checkpoints were not capped by elapsed time.
4. The daily monitor was stopped before being restarted, and only the app
   foreground repaired a missing one.
5. A missing or unreadable state wiped every shield (incl. deletion lock).
6. Read-modify-write saves outside the state lock could undo a just-queued or
   just-applied change (e.g. Block now).
7. The app could be suspended while holding the cross-process lock.
8. Sessions end up to ~11–17 min late, get one end callback, and a failed
   cleanup registration is never repaired.
9. Wake waits started on the guarded clock (can end early after a sync).
10. A late midnight rollover cleared blocks and wake taps already earned today.
11. One failing wake-gate preparation stalled every due change.
12. `enforcementDegraded` was a sticky catch-all set in 22 places, cleared only
    by the daily restart, and it also disabled extra time.
13. Split monitors rebuilt concurrently could carry a stale epoch (portion
    never enforced); limit edits wiped credits, wake taps and grants.
14. One window iOS rejects made every foreground tear down and re-register all
    window monitors; daily blocks starting after 23:44 had no start callback.
15. The report's "Used up" double-counted apps inside selected categories and
    ignored free credit.

## Build steps

### Step 1 — block first, survive interruptions
- Defer widget/notification publishing during monitor callbacks; publish once
  after shields are applied (`DisplayPublishing`).
- Refresh shields right after the day rollover in every interval callback, and
  again at the end (idempotent, clock-derived).
- `loadBlockedLimitIDs` reads the atomically written file (defaults fallback).
- `housekeeping` re-registers the daily monitor only when it is missing (a
  healthy monitor is never restarted). The stop-before-start in
  `reconfigureDailyMonitoring` stays (review: replacing in place may not
  re-fire already-fired events and could leave yesterday's events running).
- Shield refresh leaves app shields untouched when saved state is missing or
  can't be decoded, but lifts the deletion lock (the app can't recover by
  itself then, and reinstalling must stay possible).
- `applyDueChanges` refreshes shields straight after committing.
- Prune and `applyNow` read-modify-write inside the state lock.
- Host work that takes the state lock runs inside a background-task assertion.

### Step 2 — free time, sessions, wake, due changes
- Free-window credit per limit is capped at the minutes the window was open
  (until the latest known end of its free sources), and checkpoints are capped
  by elapsed time.
- Session cleanup activity spans the session end (E … E+15 min): callbacks at
  E, E+10 and E+15. `intervalDidStart` of a `session-` prunes. Housekeeping
  re-registers a missing cleanup activity for any active session. Failures are
  logged, not swallowed.
- Wake waits (global, day/night, per-limit) start at `looseningStart`.
- The rollover keeps per-limit wake/split/extra entries already keyed to
  today's wall-clock day. (Daily blocks are not kept: the re-registration
  with `includesPastActivity` right after re-fires genuinely spent limits,
  and keeping them risked carrying yesterday's thresholds into today.)
- A wake-gate change that can't be prepared stays pending; the rest of the due
  batch applies.

### Step 3 — honest warning and diagnostics
- Replace the Bool with failures recorded per area (activity name, error,
  time). Each area clears on its next successful registration. The banner
  shows while any area fails; extra time only depends on the daily area.
- Banner copy no longer blames the number of rules unless capacity was the
  error. A Diagnostics page (You → help area) lists running monitors and
  recorded failures. New strings translated into every catalog.

### Step 4 — split, schedules, Used up
- Split rebuilds run one at a time across processes (`splitRebuild.lock`), so
  concurrent rebuilds can't leave a bucket with a stale epoch.
- Limit edits reset only what the edit invalidates (selection change: credits
  and grants; split change: split markers; wake change: wake tap).
- Window repair by difference: stop extra names, start missing ones; never a
  full teardown for one rejected window. Daily windows starting after 23:44
  use the spanning registration like weekly ones; short monthly windows padded.
- Report: count category time once (skip its apps), include web domains, and
  add the limit's free-time credit to the budget shown.

## Second batch (2.0.1, owner: "start on that as 2.0.1")
Version: these fixes ship as 2.0.0 (owner, 2026-11-17: nothing released yet; the version was set back from 2.0.1 to 2.0.0). "2.0.1" in code comments and docs names this fix round, not a release.
- **50-token shield cap.** Apple shields at most 50 app and 50 site tokens per
  store setting (documented for sites, categories and exceptions; developers
  report >50 apps shields nothing). Up to 50 everything stays in `latch.main`;
  above, tokens spread over `latch.main` + `latch.overflow.1…4` (stable hash,
  next store with room), so up to 250 apps and 250 sites. Exception lists
  ("all except", category cohorts) are capped at 50 (extra allowed apps stay
  blocked). Any trim is recorded for Details. Category cohorts drop from 46 to
  42 to stay under the 50-store ceiling; 2.0.0's cohorts 42–45 are swept once.
- **Late and short windows.** A daily/weekly segment starting after 23:44 is
  registered 23:44–23:59 with its warning at the real start; short windows are
  padded with the end warning at the real end; monthly windows are fitted the
  same way (they were unpadded, so short ones were refused).
- **"All except" can't keep categories**: editor message, queue validation
  for new schedules/plans and selection edits.
- **When & where owned windows keep their priority** across a time edit
  (owned IDs encode their times); removed rules drop their keys.

Decided not to change (owner can override):
- Conflict-screen winner naming: cosmetic; needs a UI decision on how to show
  "a stricter block still applies on top of All except".
- Extra-time step edits re-basing thresholds: bounded by the edit's own wait;
  fixing it would either mint or burn requests.
- Legacy wake/sleep on pre-release installs: both already show as their own
  cards in Rules and can be removed there.
- `DayNightPolicy` is unused production code still covered by its harness;
  retiring it is test work, not a user-facing fix.
- Slimming the extension binary: no JetsamEvent reports.

## Verification
Full verify after each step; commit per step by name; fresh reviewer at the
end; signed Debug install. Device checks with the app closed are required for
every timing claim (see `docs/redesign-review.md` → 2.0.1 blocking fixes).
