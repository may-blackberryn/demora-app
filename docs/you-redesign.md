# You, ways to skip a wait, and the skip-the-wait sheet — redesign (proposal, 2026-11-02)

Status: **approved by the owner, 2026-11-02.**

Builds on `docs/redesign-ux-plan.md` (approved), `docs/foundations-redesign.md`
(tokens, components) and `docs/today-redesign.md` (ChangeRow, Changes ledger and
**ChangeReceiptSheet**, today §5.10 — reused here, not redefined). Covers:

- the **You** tab (replaces the Delays and Settings tabs, except the delay
  policy, which moves to Rules → "Your waits");
- **Ways to skip a wait** — trusted contacts, passwords and phrases as one list,
  with their add / edit / remove flows;
- the **Skip the wait** sheet (today's "Apply now" `OverrideGateView` and the
  extra-time gates) and the contact request flow inside it.

Behaviour, delays, change directions, the contact relay protocol and privacy
rules stay exactly as they are (`CLAUDE.md`). This spec changes where things live
and how they read.

## 0. Owner's call
- Plan §5.7 and decision **D8**: overrides become one list in You, removing the
  four contact routes and three password/phrase routes. Plan **D9**: contact
  removals confirm through the receipt. Plan **J9/J10** live here.
- The walkthrough is promised in "Settings → Help" but nothing starts it — decide
  what Help offers instead (decision Y10).

## 1. Diagnosis (ranked by user impact)

1. **The same people and secrets live in many places.** The contact list is
   reachable four ways: the Delays tab shows two contacts inline
   (`SettingsView.swift:568-585`), "See all" → `ContactsDetailView`
   (`ContactsOverrideViews.swift:848`), "Contact settings" → `ContactsOverrideEditor`
   (`ContactsOverrideViews.swift:624`, `SettingsView.swift:588`), and Fine-tune →
   Trusted contacts (`SettingsView.swift:653`). Passwords and phrases have three
   routes: Delays → Extra overrides (`SettingsView.swift:597`, `:628`), Delays →
   Fine-tune (`:605`, `:649`) and Settings → Fine-tune (`:46`). A fifth hub,
   `ContactsHubView` (`ContactsOverrideViews.swift:771`), is not reachable from
   anywhere. Each copy shows slightly different facts, so nobody knows which is
   "the" list.
2. **"What can this contact or password actually do?" is hard to answer.** A
   contact's permissions sit one push below its row (`ContactPermissionsEditor.swift:38`),
   labelled "Pending changes: Limit changes, …" even for *current* permissions
   (`ContactPermissionsEditor.swift:51`). Password rows join raw capability labels
   with dots (`SettingsView.swift:685`). There is also a hidden master switch,
   "Trusted-contact override On/Off" (`ContactsOverrideViews.swift:709`,
   `SharedModels.swift:213`): you can add a contact and still have nobody able to
   approve, because the switch is separate and lives on only one of the four
   screens.
3. **Skipping a wait stacks sheets on sheets, and can lead nowhere.**
   Apply now opens `OverrideGateView` (`OverrideGateView.swift:10`), which opens
   `ContactGateView`, `PasswordChangeGate` or `PhraseChangeGate` as a second sheet
   (`OverrideGateView.swift:106-127`). "Ask a trusted contact" shows whenever
   contacts exist and the switch is on (`OverrideGateView.swift:57-63`), even if
   no contact may approve *this* change; the next sheet then lists nobody
   (`ContactsOverrideViews.swift:1857-1866`). Extra time uses three more
   look-alike gates (`LimitsView.swift:129-135`, `:1163`; `PhraseOverrides.swift:139`).
4. **Edits and removals queue with no receipt, and two kinds of edit share one
   form.** "Remove…" on a contact queues immediately (`ContactsOverrideViews.swift:997`,
   `:1121`); "Remove password" too (`SettingsView.swift:773`). The password editor
   mixes an *immediate* secret-only change (current password → "Change password
   now", `SettingsView.swift:735-751`) with a *delayed* permission change ("Queue
   change", `:762`) in one scroll, with the delay hint as a footnote
   (`ContactsOverrideViews.swift:724`).
5. **The invite badge points to the wrong tab.** The Settings tab shows a dot for
   incoming contact invites (`LatchApp.swift:272`, tab index 3), but invites are
   answered only inside Delays → Contact settings (`ContactsOverrideViews.swift:731`,
   dot at `SettingsView.swift:595`).
6. **Two different screens are both called "Request history":** requests you sent
   (`SentHistoryView`, `ContactsOverrideViews.swift:1331`) and requests others sent
   you (`RequestHistoryView`, `:1384`).
7. **Settings rows hide their options.** Theme, Text case, Week starts and App
   color cycle their value on tap with no list of choices
   (`SettingsView.swift:449-476`). Help is a grid of five squares that mixes
   reading (Guide, Limitations), contact links and a protection feature (Prevent
   disabling, `SettingsView.swift:181`).
8. **The promised walkthrough doesn't exist.** The welcome says "The optional
   walkthrough is always in Settings → Help" (`RedesignWelcomeView.swift:280`),
   but `replayTutorial()` (`AppModel.swift:651`) has no caller, and the tour it
   would start is wired to the old five-tab screens (`SettingsView.swift:29-35`,
   `ContactsOverrideViews.swift:636`).
9. **Guide copy points at routes that will stop existing** ("Delays → Extra
   overrides, or Settings → Fine-tune overrides", `SettingsView.swift:334`; "Home →
   Usage & trends", `:341`; "Settings → Notifications", `:356`; "track it on the
   Home tab", `PreventDisablingView.swift:154`, `:318`).

## 2. Intent
In two seconds the user should know **who or what can skip a wait, and what
each one is allowed to skip**, with one action: **Add a way to skip a wait**.
Everything else on You (notifications, appearance, protection, help) is quiet
and one tap away.

In the skip-the-wait sheet: **what you're skipping, and which of your ways can
do it**, with one action per step.

## 3. What we took from Mobbin
| App | What we take | Screen |
| --- | --- | --- |
| stoic. | A personal page titled with the person, small-caps section labels, grouped rounded cards; "you" as a calm hub, not a settings dump | [profile](https://mobbin.com/screens/aa5298d8-b311-4b09-bcbc-224a2b317aa6) |
| Ten Percent Happier | Warm off-white page, grouped cards with plain section names (Manage / Connect / Support), one row per destination | [settings](https://mobbin.com/screens/0d67c88e-600f-4abe-8bb0-cf9a941a4bc1) |
| Google Account ("How you sign in") | Every method in **one** list, each row = name + a one-line status ("On", "Last changed…", "Add a recovery email"); add more methods from chips below the list | [Gmail](https://mobbin.com/screens/5ca47a68-08a5-46fa-b01b-9533915c9f84), [Calendar](https://mobbin.com/screens/330e2f20-4248-4bcb-8bb7-7ee822a60711) |
| Apple Health — emergency contacts | Contact row anatomy: name, detail, a small tag for the relationship/role; "Add" as the last row of the same card | [edit contacts](https://mobbin.com/screens/ec7b4e98-dcc7-41c8-a259-1b7fe98dceb9) |
| Bolt — trusted contacts | One sentence above the list saying what these people are for; quiet "Add another contact" link instead of a big button | [trusted contacts](https://mobbin.com/screens/180a5087-5026-42ba-b3d8-f0950b3f03a5) |
| Withings — choose a verification method | A sheet that lists the available methods with a one-line explanation each, then one button; unavailable methods explain why | [method sheet](https://mobbin.com/screens/0cb9755c-dbf5-44ff-bedc-1e5221411819) |
| talabat — "Choose how to get your code" | Short question as the sheet title, a radio list, one primary button at the bottom | [code sheet](https://mobbin.com/screens/28b15874-1b06-40dc-b012-13453d1eef82) |
| Starling — App theme | Theme choices shown inline as three small previews with a radio under each, instead of a value that cycles | [app theme](https://mobbin.com/screens/04c68fec-c0bb-4a00-aa1d-817d8922fd22) |
| Joi — Appearance | A live preview card at the top that updates as you change style options below | [appearance](https://mobbin.com/screens/41961fb1-776b-4dc1-9bdb-8544fe5c02c7) |

We take structure, not looks: Demora keeps warm paper, PaperCards, serif names
and its blue/brick ink.

## 4. The rule that removes the repetition
| Question | Lives in (once) | Elsewhere: link only |
| --- | --- | --- |
| Who or what can skip a wait? | You → Ways to skip a wait | Skip-the-wait sheet lists only the eligible ones |
| What may this contact / password / phrase skip? | Its row's second line; full list on its detail page | — |
| Is a change to one of them waiting? | Its row's StateChip ("Changes in 3h") | Changes ledger row (the actual change, cancellable) |
| Can my contacts approve at all (master switch)? | Footer row of the contacts part of the list (§5.3) | Contact rows show "Paused" |
| Someone wants me as their trusted contact | Invite card at the top of You | You tab dot |
| Someone asks me to approve a change | Today → Inbox (today §5.4) | — (not on You) |
| Who have I asked, and what happened? | Ways to skip a wait → "Requests you sent" | Ledger row "Waiting for Alex" for the live one |
| Who has me as a contact? | You → Approving for others | — |
| My Demora code and name | You → Approving for others → Your code | Add-contact form shows "Your code" hint |
| How long do changes wait? | Rules → Your waits (Rules spec) | Receipt shows the resulting date |
| Theme, colour, case, week start, language | You → Appearance | — |
| Help, guide, limitations, contact | You → Help & guide | Contextual "?" in complex editors only |

## 5. Layout, top to bottom

Page: `paper` background, gutter 20, cards 12 apart, sections 28 apart, max
width 640 (foundations §5.3). Title `DemoraPageTitle("You")` (`pageTitle`), no
wordmark (foundations §6). No bottom primary capsule: the one action is the
accent "Add" row inside the list (5.3), which sits in the first screen.

```
You
┌ Invite (only when someone asked) ─────────────┐
│ Alex (code 7KQ2PX) wants you as their trusted │
│ contact.         [Accept]  Decline · Block    │
└───────────────────────────────────────────────┘
WAYS TO SKIP A WAIT
These can let a change apply before its wait ends.
┌───────────────────────────────────────────────┐
│ (A) Alex                          [Active]    │
│     Limits, schedules · extra time            │
│ (S) Sam                  [Waiting to accept]  │
│     Everything except extra time              │
│ ─────────────────────────────────────────────│
│ Contacts can approve                   On  >  │
│ ═════════════════════════════════════════════ │
│ (key) Work password        [Changes in 3h]    │
│     Limits                                    │
│ (¶) Long phrase · 100 words                   │
│     Extra time                                │
│ ─────────────────────────────────────────────│
│ + Add a way to skip a wait                    │  ← accent
└───────────────────────────────────────────────┘
Requests you sent >                                ← quiet link
APPROVING FOR OTHERS
┌ Your code   7KQ2PX                         >  ┐
│ People you approve for     2               >  │
│ Blocked                    0               >  │
└───────────────────────────────────────────────┘
NOTIFICATIONS
┌ 5 minutes left on a limit             [ on ]  ┐
│ Free period starts or ends            [off ]  │
└───────────────────────────────────────────────┘
APP
┌ Appearance         Light · Blue · Regular  >  ┐
│ Prevent disabling                          >  │
│ Help & guide                               >  │
└───────────────────────────────────────────────┘
demora 2.0.0 (67) · Privacy · Word list credits
```

### 5.1 Header
- `DemoraPageTitle("You")`. Nothing on the right (help is a row, §5.7).

### 5.2 Invite card (only when an invite is waiting)
- Source: `ContactsRelay.incomingInvites()` (today fetched only in
  `ContactsOverrideEditor.task`, `ContactsOverrideViews.swift:694-702`, and by
  `AppModel.refreshIncomingInviteCount`, `AppModel.swift:198`). You's `.task` and
  pull-to-refresh fetch them and update `model.incomingInviteCount`.
- One PaperCard per invite, `accent` tint at 12 %: sentence in `body` (existing
  strings "%@ (code %@) wants to add you as their trusted contact." / the
  unnamed variant), then **Accept** (accent capsule, small) and quiet text
  buttons **Decline** · **Block**. Block asks once ("Block this person? They
  can't send you requests.") — today it acts on tap (`ContactsOverrideViews.swift:746`).
- Accepting moves the person to "People you approve for"; the card fades out.
- This is the **only** place invites are answered (decision Y7).

### 5.3 Ways to skip a wait (the one list)
- `SectionHeader("Ways to skip a wait")`, then one `meta`/`inkSoft` sentence:
  "These can let a change apply before its wait ends. Changes to them wait too."
- One PaperCard, rows separated by hairlines, grouped by kind without sub-headers
  (contacts, then passwords, then phrases; within a kind, creation order — the
  stored array order). A heavier hairline (`hairline` 1 pt, 8 pt gap) separates
  kinds so the eye sees three bands without three cards.
- **Row** (`SkipWayRow`, min 60 pt, whole row taps → detail page, chevron):
  - Leading: contact `ContactAvatarView` 36 pt (existing), or a 36 pt circle with
    `key` / `text.quote` symbol in `inkSoft` for passwords / phrases.
  - Line 1: name in `cardTitle`; for phrases append " · 100 words" or
    " · custom" in `meta`.
  - Line 2 (`meta`, `inkSoft`): what it may skip, from
    `SkipWayPermissionText.summary` (§7): "Limits, schedules · extra time",
    "Everything except extra time", "Only extra time".
  - Trailing StateChip, at most one, priority order:
    1. Removal queued (a stricter change, so not `loosen`) → `upcoming`,
       "Removed Tue 14:32" (date from the pending change).
    2. Permission/secret change queued → `upcoming`, "Changes in 3h"
       (CountdownText short form).
    3. Contact not accepted → `neutral`, "Waiting to accept".
    4. Contact unreachable (`model.unavailableContactCodes`) → `loosen`,
       "Can't reach".
    5. Contacts paused (master switch off) → `neutral`, "Paused".
    6. Otherwise none (no "Active" chip: active is the normal state).
- **Contacts footer row** (only when ≥ 1 contact): "Contacts can approve" with
  value "On"/"Off" and chevron. Tap → ChangeReceiptSheet for
  `.setContactsOverride(enabled: !current)` (turning on = looser, Hold to confirm;
  off = stricter, Confirm). This replaces `overrideCard`
  (`ContactsOverrideViews.swift:709`). See Y3.
- **Add row** (last row, accent text + `plus.circle`): "Add a way to skip a
  wait" → Add sheet (§5.9).
- Below the card, quiet link (`meta`, accent): **Requests you sent** →
  `SentHistoryView` renamed (Y6). Hidden when there are no contacts and no
  history.
- Pending *additions* (an added contact/password/phrase still waiting) appear
  as rows too, dimmed to `inkSoft`, chip `upcoming` "Added Tue 14:32", so the
  list shows what you just did (plan D3). Tapping one opens the ledger filtered
  to it rather than a detail page (nothing exists yet to edit).

### 5.4 Approving for others
- `SectionHeader("Approving for others")`. One PaperCard, three rows:
  - **Your code** — value `ContactsRelay.myCode` in `time` style (tabular) →
    `MyInfoView` (name + code + "Share this code…", existing,
    `ContactsOverrideViews.swift:803`), retitled "Your code".
  - **People you approve for** — count → `ApproveForView` (`:1179`); its history
    link is renamed **Requests you received** (Y6).
  - **Blocked** — count → `BlockedUsersView` (`:1455`). Hidden when 0.
- These are not overrides of your rules, so they're kept out of §5.3.

### 5.5 Notifications (inline)
- `SectionHeader("Notifications")`. The two existing toggles move onto You as
  rows in one PaperCard (`DemoraToggleStyle`), each with its existing footnote as
  a `meta` second line (`SettingsView.swift:113-122`). Same `@AppStorage` keys,
  same permission request on first enable, same free-boundary reschedule.
- When iOS notifications are off, a `loosen`-tinted line under the card: "iOS
  notifications for Demora are off. You can turn them on in iOS Settings." No
  button, no automatic redirect (same rule as 5.1.1(iv), applied conservatively).
- Saves one push for a two-switch screen (Y8).

### 5.6 App
- `SectionHeader("App")`, one PaperCard with three navigation rows:
  - **Appearance** — value summary "Light · Blue · Regular" (`meta`) → §5.8.
  - **Prevent disabling** — value "Passcode saved" / nothing → §5.11.
  - **Help & guide** → §5.12.
- `#if DEBUG` only: a fourth card "Developer" with Setup demos and Reset app
  (moved from `SettingsView.swift:52-63`), unchanged and excluded from Release.

### 5.7 Footer
- Centered `meta`/`inkSoft`: "demora 2.0.0 (67)" (from the bundle), then links
  **Privacy** (website privacy page, existing URL) and **Word list credits**
  (`WORDLIST_ATTRIBUTION.md` text). Privacy copy must not claim "no data
  sharing"; the footer only links.

### 5.8 Appearance (pushed)
- Title "Appearance". Top: a **live preview** PaperCard (Joi-style): a sample
  rule card ("Evening block", StateChip "On until 21:00", a CountdownText) drawn
  with the current choices, so case, colour and theme are visible as they change.
- Below, each setting shows its options inline (no cycling):
  - **Theme** — three 88 × 120 pt preview tiles (System / Light / Dark) with a
    radio under each (Starling). Same `appearance` key, `Appearance` enum
    (`Theme.swift:12`).
  - **Colour** — two 44 pt swatches, "Blue" / "Brick", selected ring in `ink`.
    Same `latch.accentColor` key. Footnote when brick is selected: "Blocked items
    use ochre so they don't look like buttons." (foundations F2).
  - **Text** — segmented control "Regular" / "lowercase" (`TextCasing`,
    `Theme.swift:38`; defaults per foundations F3).
  - **Week starts on** — segmented "Monday" / "Sunday" (`weekStartMonday`).
  - **Language** — row with the current language → existing `LanguagePickerView`
    (`SettingsView.swift:485`), keeps its "Apply language" step and beta alert.
- Changes apply immediately (local display preferences, not rules; no receipt).

### 5.9 Add a way to skip a wait (sheet)
One `.large` sheet with its own NavigationStack; steps push inside it — never a
second sheet.

1. **Choose** (talabat/Withings pattern). Title "Add a way to skip a wait".
   Three option rows in one card, each with a one-line `meta` explanation:
   - **Someone you trust** — "They approve from their Demora app." (adds "or with
     a code you email them" only when `EmailCodeService.isConfigured`).
   - **A password** — "Best if someone else keeps it, or it's written down
     somewhere out of reach."
   - **A phrase** — "Typed word by word. Slow on purpose."
2. **Details** (pushed), per kind — reusing the existing forms' logic, restyled:
   - Contact: existing `AddContactView` fields (`ContactsOverrideViews.swift:1542`):
     name, Demora code (or email when available; the type picker is hidden when
     email isn't configured, instead of showing "Email contacts aren't available
     yet in this build"), code-exists check, own-code check.
   - Password: name, password, confirm (SecureFields; hashed with
     `AppModel.hash` on Continue; fields cleared on disappear; never stored or
     logged in plain text).
   - Phrase: existing `PhrasePolicyEditor` fields (`PhraseOverrides.swift:32`):
     name, Random words (50/100/200/500/1000) / Custom phrase, mistakes before
     restart, and the existing note "The exact custom phrase is saved on this
     device…".
   - All kinds: **What it can skip** — the capability checklist (§5.10.2).
   - Bottom: **Continue** (primary), disabled until valid (same validation as
     today: name, ≥ 1 capability, matching passwords, `PhraseWords.isValid`).
3. **Receipt** (pushed, last step): the ChangeReceipt content embedded in the
   sheet (`ChangeReceiptView`, §7), "Looser change · Adds Alex, who can approve
   limits and schedules · Takes effect Tue 14:32". **Hold to confirm**. If a
   contact is added while contacts are paused, the receipt lists a second line
   "Also turns on contact approvals" and queues both actions (Y3). For contacts:
   "Alex must also accept before they can approve."
- On confirm the sheet closes and the new row appears dimmed with "Added Tue
  14:32" (§5.3).

### 5.10 Detail page (pushed from a row)
Title = the name. Three blocks, top to bottom.

1. **Identity card.** Contact: avatar (tap → existing `AvatarEditorView`), name
   field (rename is local metadata, immediate, as today
   `ContactsOverrideViews.swift:966-974`), code or email, state line ("Waiting for
   them to accept in their Demora app." / "Can't reach this contact right now…").
   Email contact still waiting: the existing 6-digit confirm field
   (`ContactsOverrideViews.swift:1086-1100`). Password: name and "Password set".
   Phrase: name, kind ("100 random words" / "Custom phrase"), mistakes allowed.
2. **What it can skip** (the capability checklist, shared by add and edit):
   - Group "Changes that wait": Limits, Schedules, Sessions, Your waits,
     Protection (app deletion lock, websites, prevent-disabling access), Trusted
     contacts — `DemoraToggleStyle` rows, one per `OverrideCapability`
     except `extraTime` (`SharedModels.swift:277`).
   - Group "Extra time": one toggle, with `meta`: "Also needs a limit whose extra
     time asks for this." (existing rule).
   - Fixed `meta` line under the groups: "Changes to your ways to skip a wait can
     never be skipped." (true today: these actions map to no capability,
     `ChangeEngine.swift:405-407`).
   - If a change to this item is queued: a `upcoming`-tinted strip above the
     checklist, "From Tue 14:32: Limits, schedules" + CountdownText, link
     **See in Changes** (the ledger owns Cancel). The checklist shows the
     *current* permissions; it never pretends the queued ones are live.
   - **Save changes** (primary, appears only when the checklist differs) →
     ChangeReceiptSheet for `.setContactPermissions` / `.upsertPasswordPolicy` /
     `.upsertPhrasePolicy`. Direction comes from `model.preview` — narrowing a
     contact is stricter (Confirm); password/phrase edits are always looser in
     today's engine (`ChangeEngine.swift:545-551`), and the receipt says so (open
     question 1).
3. **Actions.**
   - Password only: **Change the password** row → pushed page with Current,
     New, Confirm, button **Change now**. `meta`: "Takes effect right away. What
     it can skip stays the same." Calls `updatePasswordPolicySecretNow`
     (`SettingsView.swift:739`); wrong current or pending change → existing
     error. No receipt: knowing the password permits only a secret change
     (`CLAUDE.md`). This splits the two edits that share a form today (Y5).
   - Phrase only: **Change the words** → the phrase fields in a pushed page →
     receipt (queued, looser).
   - Contact (Demora user): **Safety code** row → existing
     `ContactVerificationSection` content on its own page.
   - **Remove…** (destructive text, bottom) → ChangeReceiptSheet for
     `.removeContact` / `.removePasswordPolicy` / `.removePhrasePolicy` (stricter,
     Confirm; "Takes effect right away" when the stricter wait is 0). Replaces the
     unconfirmed removals (plan D9).

### 5.11 Prevent disabling (pushed)
- One page instead of a two-square hub (`PreventDisablingView.swift:102`):
  intro sentence (existing), then two PaperCards:
  - **Setup guide** — state from existing flags: "Request access" (→ receipt for
    the existing `requestPreventAccess` action, looser, Hold to confirm) /
    "Opens Tue 14:32" with CountdownText / "Ready — opens once" with **Open the
    guide** (consumes the single open, unchanged).
  - **Screen Time passcode** — "Saved" / "None saved"; **Enter passcode**
    (immediate, local Keychain, as today) and **View passcode** (same delayed
    one-look flow, `PreventDisablingView.swift:288`).
- Copy fix: "track it on the Home tab" → "track it in Changes on Today".

### 5.12 Help & guide (pushed)
One PaperCard list, then a small "Contact" card:
- **How Demora works** — a read-only 4-page explainer (new, Y10): "Your past
  decision wins", "Stricter is quick, looser waits", "Changes wait in Changes",
  "Ways to skip a wait". Static text and illustrations; touches no state.
- **Guide** — the 10 existing topics (`SettingsView.swift:290-361`), copy updated
  for the new places (§8).
- **Limitations** — existing.
- **Contact & feedback** — merges `ContactView` and `SoftwareRoadmapView`
  (`SettingsView.swift:235`, `:395`): Report a bug, Request a feature, General
  help (mail), Feature roadmap, Bug tracker, Website, Instagram.

### 5.13 Skip the wait (sheet; replaces Apply now and the extra-time gates)
Opened from: the ledger row's **Apply now…** and the bulk "Apply N now" bar
(today §5.9), the ledger's "Waiting for Alex" (opens straight on the request
status), and Today's extra-time row (today §5.5). One sheet, medium → large
detent, its own NavigationStack; every step pushes inside it (Y4).

```
Skip the wait                                   Close
[Looser]  TikTok limit 30 → 60 min
Lands Tue 14:32 · in 3h 12m
- - - - - - - - - - - - - - - - - - - - - - - - - - -
WHO OR WHAT CAN SKIP IT
(A) Alex          asks in their Demora app      >
(S) Sam           gets an email code            >
(key) Work password                             >
(¶) Long phrase   100 words, typed one by one   >
Only ways allowed to skip this change are listed.
```

- **Header.** One change: StateChip + `change.summary` (`cardTitle`) + landing
  time and CountdownText (`time`). Several: "3 changes" + their summaries in
  `meta`, the latest landing time. Extra time: "Extra time · Games · +15 min"
  (from `ExtraContactContext`).
- **List of eligible ways** from pure `SkipWayEligibility.ways(for:state:)`:
  contacts that are accepted, not paused and allowed every change's capability;
  passwords/phrases allowed every change's capability. Second line says how it
  works. Unreachable contacts show but are disabled with "Can't reach right
  now". Fixes the empty-contacts dead end (diagnosis 3).
- **Exactly one eligible way → open it directly** (no one-row menu). For extra
  time the step names its method, so the sheet always opens directly on it.
- **None eligible** (rare: the ledger only offers Apply now when
  `ChangeEngine.hasOverride` is true, `ChangeEngine.swift:412`): "None of your
  ways can skip this change." + quiet link "Ways to skip a wait" (switches to
  You and closes the sheet).
- **Contact request** (pushed; logic of `ContactGateView`,
  `ContactsOverrideViews.swift:1815`, restyled):
  1. Choose: eligible contacts as checkable rows (all checked by default),
     `meta` "Any one approval is enough.", optional message field ("Why you're
     asking — they'll see it"), email send-limit bars only when an email contact
     is selected. **Send request** (primary).
  2. Waiting: per contact a status row ("Sent · waiting", "Denied"), the email
     code field for email contacts ("Enter the code Sam received. It expires in
     15 minutes."), and the existing auto-check note ("Checks every few seconds.
     The request expires after 1 hour."). **Ask again** (quiet) cancels and
     returns to step 1. The sheet can be closed; the ledger row keeps "Waiting
     for Alex" and reopens here.
  3. Approved: success haptic, sheet closes, ledger row slides out.
  - Codes are never logged or persisted beyond the existing relay state; the
    message is relayed through the disclosed CloudKit/Cloudflare/Resend paths as
    today. Mac/iOS contact interop stays disabled.
- **Password** (pushed): name of the selected password as title, one
  SecureField, **Skip the wait** (primary). Wrong → "That password doesn't match,
  or this change is no longer waiting." The field clears after every attempt
  (existing). Uses `applyNowWithPasswordOffMain` / the extra-time password path
  unchanged.
- **Phrase** (pushed): existing `PhraseEntry` (`PhraseOverrides.swift:205`) with
  `NoPasteWordField` (`:300`): one word at a time, no paste/copy, no stored
  challenge. Shows "Word 12 of 100" in `time` and "2 mistakes left" in `meta`.
  Uses `applyNowWithPhraseOffMain` / extra-time scope unchanged.
- **Failure that isn't the user's** ("This change is no longer available",
  "Extra time could not be started safely…"): stays on the step, existing copy,
  no retry loop.

## 6. States
| State | What shows |
| --- | --- |
| First use (no ways) | §5.3 card holds an EmptyState: "Nothing can skip a wait yet. That's the strictest setup." + **Add a way to skip a wait**. No "Requests you sent" link. |
| Only pending additions | Dimmed rows with "Added Tue 14:32"; Skip-the-wait never offers them |
| Contacts paused | Contact rows chip "Paused"; footer row "Contacts can approve · Off"; skip sheet lists no contacts |
| Contact not accepted / unreachable | Chip "Waiting to accept" / "Can't reach"; disabled in skip sheet |
| Email not configured in this build | Email never offered in add/skip flows; existing email contacts show "Email approvals aren't available in this version" on their detail page |
| Invite waiting | Invite card on top; You tab dot |
| Offline / relay error | Invite card absent (fetch failed silently, as today); contact request step shows the existing error text inline with **Try again** |
| Change already pending for an item | Detail strip "From Tue 14:32…"; Save disabled with "A change is already waiting" (engine returns nil today) |
| Tutorial / demo | No replay entry (Y10); DEBUG demos keep isolated drafts |
| Notifications denied by iOS | Toggles stay; loosen line under the card; no redirect |

Stress tests:
- **Long translated copy** (German, Polish, Hindi): row line 2 wraps to two
  lines, then truncates with "…"; chips truncate the label, never the time.
  Section headers in small caps wrap.
- **One item / fifty items:** the list has no cap; above 12 rows, kinds become
  collapsible headers ("Contacts (20)"); the Add row stays last and the page keeps
  its pull-to-refresh. Skip sheet scrolls; header pinned.
- **Smallest iPhone (SE):** the invite card plus the first three ways and the Add
  row fit the first screen; the skip sheet opens at `.medium` showing the header
  and two ways, drag to large.
- **Largest Dynamic Type:** avatars stay 36 pt, chips drop below line 2, theme
  tiles become a vertical list with radios.
- **iPad:** max width 640, centred (unchanged).

## 7. Components
| Need | Use (reuse first; new only with a reason) |
| --- | --- |
| Cards, headers, chips, countdowns, buttons, toggles | Foundations: PaperCard, SectionHeader, StateChip, CountdownText, DemoraPrimaryButtonStyle, HoldButton, DemoraToggleStyle, EmptyStateView |
| Receipt for every add / edit / remove / pause | **ChangeReceiptSheet** (today §5.10), plus two small extensions: (a) `ChangeReceiptView`, the same content embeddable as the last step of a sheet's stack; (b) a list of actions, for "add contact + turn on approvals" (both looser, one Hold) |
| List row | **SkipWayRow** (new): one row type for three kinds; needed because today each kind has its own row (`TrustedContactApprovalRow`, `GridCard`) with different facts |
| Capability checklist | **SkipPermissionsChecklist** (new): replaces the three copies of "Allowed uses" toggles (`SettingsView.swift:753`, `PhraseOverrides.swift` editor, `ContactsOverrideViews.swift:1649`) and `ContactPermissionsEditor` |
| Skip sheet | **SkipWaitSheet** (new container) hosting existing logic: `ContactGateView` request/poll/verify, `PasswordChangeGate` / `ExtraTimePasswordGate` checks, `PhraseEntry` — restyled, not rewritten |
| Avatar, avatar editor, safety code | Existing `ContactAvatarView`, `AvatarEditorView`, `ContactVerificationSection` |
| Language picker | Existing `LanguagePickerView` |
| Appearance previews | **ThemePreviewTile** (new, small): no existing equivalent |

Pure logic, with tests:
- `SkipWayList.make(overrides:pending:unavailableCodes:)` → ordered rows (kind,
  name, permission text, at most one chip by the §5.3 priority), including
  pending additions. Tests: each chip priority, removal + permission change on the
  same item, master switch off, empty, 50 items, legacy contacts without
  `allowed` (decode default excludes extra time).
- `SkipWayPermissionText.summary(_ allowed:)` → "Everything", "Everything except
  extra time", "Only extra time", "Limits, schedules · extra time", "Nothing".
  Tests: all 2⁷ subsets produce non-empty, localized-key-only output.
- `SkipWayEligibility.ways(for: .changes([...]) | .extraTime(...), state:)` →
  eligible contacts/passwords/phrases. Tests: **non-empty exactly when
  `ChangeEngine.hasOverride` is true** for change contexts; unusable and paused
  contacts excluded; mixed-capability bulk selections; extra time requires
  `.extraTime`; changes with no capability (override edits) are never eligible.
- `SkipWayAddPlan.actions(adding:state:)` → `[.addContact]` or
  `[.addContact, .setContactsOverride(enabled: true)]`; never adds the switch for
  passwords/phrases; never turns the switch off.
- Existing receipt-text tests extended for override actions (add, permission
  narrow/widen, remove, pause/resume).

## 8. Changes elsewhere
- **Tab bar** (`LatchApp.swift:241-256`): handled by the foundations four-tab
  switch. You's badge = `model.incomingInviteCount > 0` (moves from the Settings
  index 3 check at `LatchApp.swift:272`). Today's dot stays approval requests.
- **Delays tab** (`DelaysOverridesTabView`, `SettingsView.swift:549`): its delay
  rows go to Rules → Your waits (Rules spec); everything else on it is replaced by
  You and removed with `ExtraOverridesView` (`:628`), `FineTuneOverridesView`
  (`:649`), `PasswordPoliciesView` (`:674`), `OverridesGridView` (`:797`),
  `ContactsOverrideEditor` (`ContactsOverrideViews.swift:624`),
  `ContactsDetailView` (`:848`) and the orphan `ContactsHubView` (`:771`).
  `RulesGridView` / `GeneralBlockingView` (`SettingsView.swift:828`, `:867`) move
  to the Rules spec. The pending "dotted separator" request (`CLAUDE.md`) goes
  away with `DelayPolicyNavigationRows` there.
- **Settings tab** (`SettingsView.swift:15`): replaced by You. `settingsPath` /
  `SettingsRoute` become `youPath` / `YouRoute`; `replayTutorial()` stops popping
  `settingsPath` (or is removed with the tour, Y10).
- **Today / ledger** (today §5.9): "Apply now…", the bulk bar and "Waiting for
  Alex" open `SkipWaitSheet` instead of `OverrideGateView` / standalone
  `ContactGateView` (`HomeView.swift:471`). Extra-time row (today §5.5) opens
  `SkipWaitSheet(.extraTime)` instead of `LimitsView.swift:129-135`.
- **Welcome copy** `RedesignWelcomeView.swift:280`: "The optional walkthrough is
  always in Settings → Help." → "How Demora works is always in You → Help &
  guide."
- **Guide and help copy** that names old routes (24 strings found across
  `SettingsView.swift`, `PreventDisablingView.swift` and catalogs): Delays,
  Settings → Fine-tune, Home → Usage & trends, "on the Home tab", Limits &
  blocks. Rewrite to Today / Rules / Insights / You.
- **Localization:** every new or changed string in all eight catalogs
  (`Shared/Localization*.swift`); report-generated strings are not affected.
- **No changes** to `ChangeEngine`, `ContactsRelay`, `ContactsService`,
  `AppAttest`, `EmailCodeService`, CloudKit schema, password hashing, phrase
  word lists or the Mac adapter.

## 9. Motion and haptics
- Invite card and dimmed "Added…" rows fade in/out (0.2 s).
- Steps inside the add and skip sheets use the standard push; no custom springs.
- Receipt: HoldButton per foundations (1.2 s, success haptic on queue).
- Skip success: success haptic, sheet dismisses, the ledger row slides out
  (today §9). Wrong password / phrase reset: one error haptic, no shake.
- Appearance preview cross-fades (0.25 s) on each change.
- Reduce Motion: no fades or fills; HoldButton becomes a confirmation (foundations
  §9). VoiceOver: each row reads "Alex, can skip limits and schedules and extra
  time, waiting to accept, button"; the skip sheet header is read first.

## 10. Copy (English drafts; refine and translate into all eight languages)
- "You" / "Ways to skip a wait" / "These can let a change apply before its wait
  ends. Changes to them wait too."
- "Add a way to skip a wait" / "Someone you trust" / "They approve from their
  Demora app." / "…or with a code you email them." / "A password" / "Best if
  someone else keeps it, or it's written down somewhere out of reach." / "A
  phrase" / "Typed word by word. Slow on purpose."
- "What it can skip" / "Changes that wait" / "Limits" / "Schedules" / "Sessions"
  / "Your waits" / "Protection" / "Trusted contacts" / "Extra time" / "Also needs
  a limit whose extra time asks for this." / "Changes to your ways to skip a wait
  can never be skipped."
- "Everything" / "Everything except extra time" / "Only extra time" / "Nothing"
- "Waiting to accept" / "Can't reach" / "Paused" / "Changes in %@" / "Added %@" /
  "Removed %@" / "From %@: %@" / "See in Changes"
- "Contacts can approve" / "Also turns on contact approvals" / "%@ must also
  accept before they can approve."
- "Change the password" / "Change now" / "Takes effect right away. What it can
  skip stays the same." / "Change the words" / "Safety code" / "Remove…"
- "Nothing can skip a wait yet. That's the strictest setup."
- "Requests you sent" / "Requests you received" / "Approving for others" / "Your
  code" / "People you approve for" / "Blocked" / "Block this person? They can't
  send you requests."
- "Skip the wait" / "Who or what can skip it" / "Only ways allowed to skip this
  change are listed." / "asks in their Demora app" / "gets an email code" / "%d
  words, typed one by one" / "None of your ways can skip this change." / "Any one
  approval is enough." / "Why you're asking — they'll see it" / "Send request" /
  "Sent · waiting" / "Denied" / "Ask again" / "Enter the code %@ received. It
  expires in 15 minutes." / "That password doesn't match, or this change is no
  longer waiting." / "Word %d of %d" / "%d mistakes left"
- "Appearance" / "Theme" / "Colour" / "Blue" / "Brick" / "Blocked items use ochre
  so they don't look like buttons." / "Text" / "Week starts on"
- "iOS notifications for Demora are off. You can turn them on in iOS Settings."
- "Help & guide" / "How Demora works" / "Contact & feedback" / "Word list
  credits" / "How Demora works is always in You → Help & guide."
- Existing strings reused as is where they already say the right thing (invite
  sentences, email code expiry, safety-code explanation, prevent-disabling steps).

## 11. Out of scope
- The delay policy editor and "Your waits" (Rules spec); Insights; Today.
- Any change to how overrides work: capability mapping, directions (including
  "password/phrase edits are always looser"), relay protocol, email enablement,
  App Attest, CloudKit indexes, rate limits.
- Mac/iOS trusted-contact interoperability (stays disabled).
- Rebuilding the interactive tour for four tabs (only if the owner picks it in
  Y10; it would be its own spec).
- Widgets, shield, App Store assets.

## 12. Decisions for the owner
| # | Decision | Why |
| --- | --- | --- |
| Y1 | You is one page: invite (when any) → Ways to skip a wait → Approving for others → Notifications → App (Appearance, Prevent disabling, Help & guide) → footer | Everything about the person in one place, most-used first; replaces the Delays and Settings tabs |
| Y2 | Contacts, passwords and phrases share **one list**; each row says what it may skip, with at most one state chip | One answer to "who or what can skip a wait" (plan D8); Google's single sign-in-methods list |
| Y3 | The hidden "Trusted-contact override" switch becomes a visible "Contacts can approve" row under the contacts, and adding a contact while it's off queues "turn on" in the same receipt | Today you can add a contact who can never approve, without knowing why |
| Y4 | Skip the wait is **one** sheet with steps pushed inside it, listing only ways that can skip this change; one eligible way opens directly | Removes sheet-on-sheet and the empty-contacts dead end |
| Y5 | A password's "change the secret now" and "change what it can skip" become two separate actions on its page | They follow different rules (immediate vs delay-gated); one form blurred that |
| Y6 | Rename the two "Request history" screens: **Requests you sent** (under Ways to skip a wait) and **Requests you received** (under People you approve for) | Two different screens had the same name |
| Y7 | Contact invites are answered only on You, and the You tab carries the invite dot | The dot sat on Settings while invites lived under Delays |
| Y8 | Notifications' two toggles sit directly on You instead of a pushed page | A screen for two switches is a wasted tap |
| Y9 | Appearance shows every option inline with a live preview (theme tiles, colour swatches, segmented case and week start) | Today tapping a row silently cycles a hidden value |
| Y10 | Help offers a read-only **How Demora works** explainer; the old interactive replay is not wired into You | `replayTutorial()` has no caller, stashes and restores real state, and is built around the five-tab screens; a static explainer touches no state |
| Y11 | Removing a contact, password or phrase, and pausing contacts, always end on the receipt | Plan D9; today they queue on one tap |
| Y12 | Prevent disabling becomes one page with its two parts (setup guide, stored passcode), behaviour unchanged | Replaces a two-square hub behind another hub |

### Open questions
1. **Narrowing a password or phrase counts as looser.** `upsertPasswordPolicy` /
   `upsertPhrasePolicy` are always `.lenient` (`ChangeEngine.swift:545-551`), so
   taking a permission away from a password waits like loosening, while the same
   edit on a contact is stricter (`:574-577`). This spec keeps behaviour and lets
   the receipt say "Looser change". Should the engine treat a narrowing-only edit
   (same secret or words, fewer capabilities) as stricter, as a separate,
   tested engine change?
2. **Email contacts.** This build hides email when `EmailCodeService.isConfigured`
   is false. Is email meant to ship in 2.0? It changes the add copy and the skip
   sheet's second lines.
3. **Prevent disabling guide gate.** In Help, the setup guide itself sits behind
   the looser wait (it also explains how to undo the lock). Keep, or show the setup
   steps freely and gate only the "how to undo" part?
4. **Interactive tour.** If How Demora works is accepted (Y10), may the dormant
   tutorial code (`beginTutorial`, tutorial routes in `SettingsView.swift:29-35`
   and `ContactsOverrideViews.swift:636-648`) be deleted when You ships, or kept
   for a later four-tab tour?

## Owner's answers (2026-11-02)
Approved with the recommended answers to the open questions:
1. Narrowing a password or phrase keeps today's behaviour (classed looser);
   making it stricter would be a separate, tested engine change, not part of
   this redesign.
2. Email contacts stay as now: shown only when `EmailCodeService.isConfigured`.
3. Prevent disabling: the setup guide stays behind the looser wait.
4. The dormant tutorial code is deleted when You ships.
