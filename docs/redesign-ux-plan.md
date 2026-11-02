# Demora iOS — full redesign UX plan

Status: **approved by the owner, 2026-11-02.** Detailed per-screen specs follow
in `docs/*-redesign.md`.

Scope: the iPhone/iPad app only. Behaviour, delays, privacy rules and data
stay exactly as they are (see `CLAUDE.md`). This plan changes where things
live and how they look, not what the app enforces.

## 0. Owner's call

> "I like the design intention, but not the design. Look into Mobbin. We need
> a full redesign."

What we keep: the idea ("your past decision beats today's impulse"), the
calm, unhurried tone, warm paper, a serif voice, blue or brick-red ink, and
dark mode. What we change: structure, hierarchy, density, and how the app
shows *time* — which is the one thing Demora is about.

## 1. Diagnosis of the current app (ranked by user impact)

Sources: the screen inventory of the working tree (2026-11-02) and the live
App Store screenshots.

1. **The most important fact — "what is changing, and when" — is buried.**
   Pending changes are the last section of Home. After saving a loosening
   edit, the rule keeps showing its old value and the only feedback is a
   haptic. Eight other screens just say "cancel it on the Home tab".
2. **Five tabs, with the centre one (Home) not first, and two of them
   (Delays, Settings) about configuration.** Daily jobs share space with
   one-off setup. Help is reachable from four headers.
3. **The same things live in many places.** The contact list exists four
   ways; passwords/phrases have three routes; "now & next" appears in five
   places; Usage & trends has two different "Usage details"; the invite badge
   sits on Settings while invites live under Delays.
4. **Being blocked is a dead end.** The shield says "OK" and nothing else; no
   rule name, no time, no path to extra time. In the app, extra time is only on
   the Limits tab, and only after a limit is spent.
5. **Editors read like settings lists.** Three disclosure groups in the limit
   editor, seven weekday toggles in one editor and day chips in another, save
   buttons in three different places, and the delay hint below everything.
6. **Removals queue with no confirmation** (schedules, planned, recurring,
   contacts), yet these are exactly the less-strict changes Demora exists to
   slow down.
7. **Visual hierarchy is flat.** The journal style (open rules, no surfaces,
   lowercase everywhere) makes every row weigh the same, so the eye has no
   anchor. Lowercase body text also hurts scanning and translations.

## 1b. What the user comes here for (jobs, most frequent first)

| # | Job | How often | Where it's answered (new) |
| --- | --- | --- | --- |
| J1 | "How am I doing today? What's left, what's blocked?" | Several times a day | **Today** — Now card + limits report |
| J2 | "I'm blocked. Why, until when, can I get a bit more?" | Daily for some | **Today** rule card → extra time; shield copy |
| J3 | "Wake up" (start the morning wait) | Daily, day/night users | **Today** — top action, only when due |
| J4 | "Block things now / start a focus session" | Daily–weekly | **Today** — the one primary button |
| J5 | "What's going to change, and when? Cancel it." | After every edit | **Today** — Changing soon; **Changes** ledger |
| J6 | "Approve a friend's request" | Occasional, urgent | **Today** — inbox at the top while waiting |
| J7 | "Add or change a rule" | Weekly | **Rules** |
| J8 | "Am I using my phone less?" | Weekly | **Insights** |
| J9 | "How long do my changes wait? Who/what can skip it?" | Rare | **Rules** header (waits); **You** (overrides) |
| J10 | Appearance, language, notifications, help | Rare | **You** |

## 2. Where things live (information architecture)

Four tabs instead of five. Order follows frequency; the first tab is home.

```
Today          Rules            Insights         You
─────          ─────            ────────         ───
Now card       Your waits       Daily / Weekly   Ways to skip a wait
Wake up*       Limits           Most used apps     (contacts, passwords,
Inbox*         Schedules        Trends              phrases — one list)
Your limits    Day & night      Starting point   Notifications
Today's line   Planned                           Appearance
Changing soon  Always-on blocks                  Prevent disabling
Primary: Block now   + New rule                  Help & guide
```
\* only when there is something to do.

- **Today** is a live page about *now*: what's active, what's left, what's
  coming today, and what's about to change. One primary action ("Block now").
- **Rules** is every rule in one list, grouped by kind, each a card with a
  state chip. The delay policy sits at the top because it governs every edit
  below it. Calendar and conflicts open from the Rules header.
- **Insights** is the existing report (usage, apps, trends) promoted to a tab
  so the stats are findable. No new data; it is the same report extension.
- **You** holds everything about the person, not the rules: overrides,
  notifications, appearance, prevent-disabling, help. Help lives only here
  (plus contextual "?" inside complex editors).
- **Changes ledger** (pushed from Today) lists every pending change grouped by
  when it lands ("In the next hour", "Tonight", "Tomorrow"), like a bank's
  scheduled payments. This is the only full list; everything else links to it.

### The rule that removes the repetition

| Question | Lives in (once) | Elsewhere: link only |
| --- | --- | --- |
| How much have I used / have left? | Today → Your limits (report) | Insights for history |
| What's blocked right now, until when? | Today → Now card | Rule card chip |
| What's on today? | Today → Today's line | Rules → Calendar for other days |
| What's changing and when? | Changes ledger (Today shows next 2) | Rule card chip "Loosens in 3h" |
| Can I get extra time? | The spent rule's card (Today and Rules) | Shield copy points to it |
| How long do changes wait? | Rules → Your waits | Editors show the resulting date |
| Who can approve / skip a wait? | You → Ways to skip a wait | Apply-now sheet lists the options |
| Do I need to approve someone? | Today → Inbox | You tab badge |
| Weekly starting estimate | Insights → Starting point | — |

## 3. The stats, and where each one shows

The host app cannot see usage; only the report extension can. Every usage
number therefore renders inside a report surface. Host screens show only
what the host truly knows.

| Stat | Source (real data) | Shows on |
| --- | --- | --- |
| Used / budget per limit today | Report extension | Today → Your limits |
| Limit spent ("Blocked") | Report extension | Today → Your limits |
| Screen-on time today, week, daily bars | Report extension | Insights |
| Most used apps, per-app history | Report extension | Insights |
| Week comparisons, weekday patterns | Report extension (complete periods only) | Insights → Trends |
| Starting estimate vs now | Local, self-reported | Insights → Starting point |
| Active rules and their end time | Host state | Today → Now card |
| Today's blocks/free periods/sessions | Host state | Today → Today's line |
| Pending changes + countdowns | Host change engine | Changes ledger; next 2 on Today |
| Wake waits per group | Host state | Today → Now card (while waiting) |
| Extra time steps left | Host state | Rule card |
| Delay policy | Host state | Rules → Your waits |

Unknown or missing usage is shown as "No data yet", never 0.

## 4. Design language (what we take from each reference)

| From | What we take | Mobbin |
| --- | --- | --- |
| Opal — rules grid | Each rule is a card with a live state chip ("7 left", "31m left", "Starts in 108h"), so status is visible without opening it | [screen](https://mobbin.com/screens/f6f2258d-c88e-4b70-b278-2950f8aad2bd) |
| Opal — rule detail | Tap a rule → short summary sheet (when / days / what) with one Edit button, instead of opening the form directly | [screen](https://mobbin.com/screens/20ad6235-3f7b-4ade-bd5b-f52a160fbf60) |
| Opal — rule editor | Deliberate commit gesture ("Hold to commit"); grouped rows, day chips | [screen](https://mobbin.com/screens/7bb284c6-ecb9-41f4-9c12-80bc34f02a3d) |
| Brick — schedules, add schedule | Warm neutral surfaces, one summary line per schedule, round weekday chips, overlap warning inline in the editor | [list](https://mobbin.com/screens/64828f33-882c-4cde-9692-a6168730366b), [editor](https://mobbin.com/screens/04956d6d-fdf7-4fd3-95fb-d6cf8c9f8ae5) |
| Brick — home | One big statement of the current state, centred, with one action | [screen](https://mobbin.com/screens/0a3dfe67-0c4d-4d05-b139-d5d3abf76841) |
| Structured — timeline | A vertical thread joining the day's events; now marked on the line | [screen](https://mobbin.com/screens/574482d9-3640-4553-805e-944f11f27428) |
| Lloyds / Mercury — scheduled payments | Pending items grouped by when they land, each with its due date and a quiet way to cancel | [Lloyds](https://mobbin.com/screens/a6626216-221f-4b1a-87e6-6e9d2c4906ef), [Mercury](https://mobbin.com/screens/7cc96da8-f0a8-4c9c-8ab5-cd2d49531a74) |
| Jomo — home | Per-app usage bars, then one clear primary button above the tab bar | [screen](https://mobbin.com/screens/f7a4a7c4-cca0-4671-9493-da8989415423) |
| 5 Minute Journal, Alma | Large serif headings on warm paper that still feel modern; soft, roomy cards | [5MJ](https://mobbin.com/screens/488c7a00-10fb-4673-9af3-8c9db20838dd), [Alma](https://mobbin.com/screens/6ea822ea-fbfa-46da-b996-22c85056bb6e) |

We take structure and use of colour, not looks. Demora keeps its own palette:
warm paper, ink, one accent (blue or brick), serif for headings and times.

### Visual direction in one paragraph

**"A calm paper desk with one clock on it."** Warm paper background; content
sits on soft paper cards (one step lighter, 20 pt radius, hairline border, no
heavy shadow) so the eye has anchors. Serif (New York) for page titles, rule
names and every *time* — waits and countdowns are the hero numbers. SF Pro for
body and controls, regular case by default (lowercase stays as an option).
Colour carries meaning only: accent = active/primary, brick = blocked/
loosening, sage = free/allowed, faint ink = everything else. Time is drawn as
a thread: the day line on Today, the ledger's grouping, the countdown ring on
a pending change.

## 5. Screens (block by block, top to bottom)

### 5.1 Today
1. **Header:** date in small caps ("MONDAY 2 NOVEMBER"), wordmark left, inbox
   bell right only when there's an approval request.
2. **Now card** (hero). One sentence in serif about the current state, e.g.
   "Instagram and TikTok are blocked until 21:00" or "Nothing is blocked right
   now". Below it, at most two facts (active session end, wake wait). If a
   wake-up is due, the card's action is **Wake up** and nothing else competes.
3. **Inbox** (only when needed): "Alex asks to apply 'Remove TikTok limit'" →
   Approve / Deny.
4. **Your limits** (report surface): one row per limit — name, bar, "12 of
   30 min". Spent limits show "Blocked · Extra time (2 left)" as a link.
   Header link: "All rules".
5. **Today's line:** the day thread with today's blocks, free periods and
   sessions; "now" marked. Tap an item → its rule summary sheet.
6. **Changing soon:** the next two pending changes with countdown rings and
   "See all (5)" → Changes ledger.
7. **Primary action** above the tab bar: **Block now** (start a session).

### 5.2 Changes ledger (pushed)
Grouped by landing time. Each row: direction chip (Stricter / Looser),
plain-language summary ("TikTok limit 30 → 60 min"), the exact landing time
("Tue 14:32 · in 3h 12m"), and **Cancel** (with confirmation for bulk).
"Apply now…" appears only when an override is configured.

### 5.3 Rules
1. **Your waits** strip: "Stricter: right away · Looser: 1 day" → policy
   editor.
2. Sections: **Limits**, **Schedules** (recurring blocks and free periods),
   **Day & night**, **Planned**, **Always on** (app deletion, adult sites,
   website list). Each rule is a card: name, one summary line ("30 min a day ·
   4 apps"), and a state chip (Active until 21:00 / Blocked / Starts in 2h /
   Loosens in 3h).
3. **+ New rule** → a chooser sheet: Daily limit, Block now, Plan a block,
   Repeating block, Day & night, Website.
4. Header icons: Calendar, Conflicts (badge when any).

### 5.4 Rule summary sheet → Editor
Tap a rule → summary sheet (when / days / what / extra time) with **Edit**
and **Remove**. The editor is one page in plain sections (What · How much ·
When · Extra time), with advanced options as clearly labelled rows rather than
nested disclosures. Every save ends on the **change receipt** (5.5).

### 5.5 Change receipt (new, shared by every editor and remove)
A bottom sheet that says what will happen, in Demora's voice:
"Looser change. TikTok goes from 30 to 60 min a day **on Tue 14:32**
(in 1 day). You can cancel it until then." Stricter changes that apply now
say so. Commit with **Hold to confirm** for looser changes and removals; a
plain button for stricter ones. After saving, the rule card shows the chip
immediately.

### 5.6 Insights
The existing report: Daily/Weekly, total, bar chart, Most used apps, Trends,
Starting point. One "About this data" sheet (merges the two "Usage details").

### 5.7 You
Ways to skip a wait (one list of contacts, passwords and phrases, each with
what it may do), Notifications, Appearance, Prevent disabling, Help & guide
(includes the walkthrough), About.

### 5.8 Blocked (shield)
Same system screen, better copy: "Blocked by your Demora rules. Open Demora to
see how long, or to ask for extra time if your limit allows it." Whether the
shield can name the specific rule needs a feasibility check (it receives an
app token, not the rule).

## 6. States, motion, components

- **First use / empty:** Today shows a single card "Make your first rule" with
  the two most common starts (Daily limit, Block now). No empty sections.
- **No Screen Time permission:** a calm banner on Today only; no re-prompt
  loops (Apple 5.1.1(iv)).
- **Report missing:** "Usage isn't available yet" in the report surface, never
  zeros.
- **Many items:** Today caps lists (2 changes, all limits collapsed after 4);
  Rules uses sections; ledger groups by time.
- **Motion:** countdown rings tick smoothly; the Now card cross-fades between
  states; Hold to confirm fills the button over ~1.2 s with a haptic at the
  end. Reduce Motion replaces all of it with fades.
- **Components to build once:** PaperCard, StateChip, CountdownRing,
  ChangeReceipt sheet, RuleSummary sheet, DayThread, DayChips, HoldButton,
  SectionHeader. Reuse existing editors' logic underneath.

## 7. Decisions

| # | Decision | Why |
| --- | --- | --- |
| D1 | Four tabs: Today · Rules · Insights · You (Delays and Settings tabs go away) | Daily jobs first; setup no longer takes two of five tabs |
| D2 | Delay policy moves to the top of Rules ("Your waits") | It governs every rule edit, so it belongs with the rules |
| D3 | Pending changes get their own ledger, next two on Today, and a chip on each affected rule | The defining fact of Demora should be visible right after every edit |
| D4 | Every edit and removal ends on a change receipt; looser ones use Hold to confirm | Makes the delay concrete and adds friction exactly where Demora wants it |
| D5 | Soft paper cards replace the open journal rules | Gives hierarchy and anchors while keeping the paper feel |
| D6 | Regular case by default; lowercase remains an option | Easier scanning and translation; existing lowercase users keep their choice |
| D7 | Usage stats get their own tab (Insights) | The owner wants thorough stats; today they're one link deep on Home |
| D8 | Overrides become one list in You ("Ways to skip a wait") | Removes the four contact routes and three password/phrase routes |
| D9 | Removals of schedules/sessions/contacts now confirm via the receipt | They are less-strict changes; today they queue without a check |
| D10 | Keep both light and dark; design light first, dark from the same tokens | The store screenshots are dark; the 2.0 tree is light |
