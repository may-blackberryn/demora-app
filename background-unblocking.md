# Background unblocking: problem & fix

*Prepared for internal review. Covers changes in `ChangeEngine.swift`,
`DeviceActivityMonitorExtension.swift`, `ShieldController.swift`,
`SharedModels.swift`, `Localization.swift`, `AppDelegate.swift`, `LatchApp.swift`,
and `Latch/Info.plist`.*

## Problem

The app cannot run in the background. The only background executor iOS gives us is
the DeviceActivity monitor extension, and iOS launches it only at moments registered
in advance — the starts/ends of monitored activity intervals. Those callbacks are
best-effort: overnight, in Low Power Mode, or with the device asleep, iOS routinely
drops them.

The architecture is self-healing by design — shield state is always recomputed from
the wall clock on any wake, never stepped forward — so any wake from any source
repairs everything. The weakness was **wake density**:

- The midnight limit reset had exactly one background chance: the daily activity's
  `intervalDidStart` at 00:00.
- Each schedule window / session end had exactly one: its own `intervalDidEnd`.

Drop that single callback and nothing retries until the user opens the app. Symptom:
spent limits still shielded the next morning; schedule ends landing late unless the
app was opened.

## Fix — four independent layers

### 1. Echo activities (retries for the midnight reset)

Three fixed repeating activities (`echo-0/1/2`) whose only job is waking the
extension: 00:05–00:35, 01:00–01:30, 06:00–06:30. Each `intervalDidStart` calls
`ChangeEngine.rolloverIfNewDay()`, which is idempotent via the existing
`lastResetDay` day-key guard — a no-op when midnight already worked, a retry when it
didn't. The 06:00 sweep lands before most users pick up the phone.

Registered in `reconfigureWindowMonitoring`, swept and re-registered with the other
window activities. **Registered last**, after the schedule/exemption/planned-window
activities: under iOS's ~20-activity cap, a dropped echo is tolerated redundancy,
whereas a dropped enforcement window is real lost enforcement — so echoes must yield
the budget first. Echo registration failures log but do **not** set
`enforcementDegraded`.

### 2. `warningTime` on every schedule (~3× wake density)

Every `DeviceActivitySchedule` now passes `warningTime: DateComponents(minute: 5)`,
so iOS additionally delivers `intervalWillStartWarning` / `intervalWillEndWarning`
~5 minutes before every boundary. The monitor handles both by running
`ChangeEngine.housekeeping()` (recompute-from-clock).

Key property: a warning never acts on its own boundary early — the wall-clock check
prevents that. It acts as a free retry for anything else left stale: a dropped
session end, a due pending change, a missed day rollover. Every schedule's warnings
back up every other schedule's callbacks.

Applied to: the daily activity, recurring window segments, planned windows, session
cleanup activities, pending-change apply activities. Safe because every interval is
already floored to ≥15 min (DeviceActivity's own minimum), so a 5-min warning can
never exceed an interval and fail registration.

### 3. Fallback notification (caps the worst case)

When a limit blocks (`eventDidReachThreshold`), the extension schedules a local
notification — stable ID `latch.resetNudge` (`LatchConstants.resetNudgeID`) — for
**00:10** the next day: title "Your limits have reset", body "If any apps still look
blocked, open Demora to refresh them." (EN + ES.)

Every successful rollover (`ShieldController.clearForNewDay`, reached from midnight,
echoes, warnings, the BG task, or app foreground) cancels it — pending **and**
already-delivered. So it reaches the user only when every background reset failed,
converting the worst case from "silently broken apps" into "tap-to-fix." Repeat
blocks the same day collapse into one nudge (same ID).

The 00:10 offset is deliberate: it sits just after the 00:05 echo, so on a normal
night the midnight callback and first retry have both had a chance to succeed and
cancel it before it would fire — keeping it a "something broke" signal, not nightly
noise.

Field metric: how often this notification survives to fire ≈ the real
background-reset failure rate.

### 4. Background app refresh (an independent overnight wake)

A `BGAppRefreshTask` (id `latch.midnightReset`, `LatchConstants.bgRefreshID`), an
extra wake source that is **independent of the DeviceActivity extension** — it runs
in the main app process on iOS's own background-refresh scheduler, which tends to
fire while the device charges overnight (exactly our failure window). Different
subsystem, different failure profile, so it fails independently of layers 1–2.

- **Registered** in `AppDelegate.didFinishLaunching` (before launch completes, as
  BGTaskScheduler requires).
- **Scheduled** with `earliestBeginDate` = next 00:10 (a floor, not a promise — iOS
  picks the actual time). Re-submitted inside the handler (so the chain never dies)
  and on app background (`LatchApp` scenePhase `.background`).
- **Handler** is deliberately minimal: chain next request → `housekeeping()` →
  `setTaskCompleted`. No explicit reconfigure calls — `housekeeping()`'s
  `rolloverIfNewDay` already reconfigures monitoring when the day actually changed,
  and on a same-day run an unconditional reconfigure would pointlessly restart the
  daily monitor mid-night. Monitor restarts are the one operation with a history of
  side effects (spurious `includesPastActivity` threshold re-fires, racing the
  extension's own rollover), so we never do them without cause.
- **Threading:** the handler runs on a background queue (`register(…, using: nil)`).
  Everything it touches is thread-safe (UserDefaults, DeviceActivityCenter,
  ManagedSettings, notifications) — keep `AppModel`/`@Published` out of this path.
- Uses the BGTaskScheduler budget, **not** the ~20-activity DeviceActivity cap — so
  it doesn't compete with enforcement activities.
- Requires `UIBackgroundModes: fetch` and `BGTaskSchedulerPermittedIdentifiers`
  (both in `Latch/Info.plist`).

## Invariants to verify in review

- **Idempotency:** all reset paths (midnight `intervalDidStart`, echoes, foreground
  `rolloverIfNewDay`, BG-task handler) share the `lastResetDay` guard — no double
  clear, no loop (the reconfigure inside the reset re-fires `intervalDidStart`, which
  then no-ops).
- **No early transitions:** warnings, echoes, and the BG task only recompute state
  from the clock; nothing unshields before its real boundary.
- **Activity budget:** +3 fixed echo activities against iOS's ~20-activity cap, and
  they register **last** so enforcement activities claim the budget first. Echo
  failures intentionally don't trip `enforcementDegraded`. The BG task is on a
  separate scheduler budget and doesn't count against the cap.
- **Nudge lifecycle:** armed on block → re-arms replace (same ID) → cancelled
  (pending + delivered) by any successful rollover, including the BG-task path.
- **Target membership:** `ShieldController` calls `ChangeEngine.cancelResetNudge()`;
  safe because the whole `Shared` folder is a synchronized group in every target that
  includes it (LatchReport stays self-contained and doesn't include Shared). The BG
  task lives in the app target only (`AppDelegate`), which already links `Shared`.

## Suggested device tests

1. Spend a limit, leave the phone untouched over midnight → an echo should clear the
   shields by 06:30 without opening the app.
2. Same, but force failure (Low Power Mode / airplane overnight) → the 00:10 nudge
   should arrive; tapping it opens the app and clears; the nudge must not reappear.
3. A schedule ending mid-morning with the app closed → the end should land within
   ~5 min of the boundary (warning + end callbacks).
4. Watch the extension's logs for `echo-` wakes to confirm iOS is honoring the
   registrations on your test devices.
5. **BG task:** on a real device, pause in the debugger and run
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"latch.midnightReset"]`,
   then resume — the handler should fire and run the rollover. (Simulator never runs
   BG tasks.)

## Honest ceiling

Even with all four layers, an unlucky untouched device can stay shielded until the
06:00 echo or the 00:10 nudge. iOS offers no guaranteed background execution; this
raises the hit rate substantially and makes every remaining failure user-visible and
one tap from fixed. The in-app disclaimer on the blocking screen remains accurate,
but should trigger far less often.

Two caveats specific to layer 4 (background app refresh): iOS allocates its budget by
**how often the user opens the app**, so a rarely-opened install — exactly the one
relying on background reset — gets the least; and it does **not** run at all after a
force-quit, whereas the DeviceActivity extension (layers 1–2) still fires. So it's a
genuinely independent extra ticket, but strictly weaker than the extension layers for
the hardest cases — additive, not a replacement.
