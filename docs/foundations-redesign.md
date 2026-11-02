# Foundations — redesign (proposal, 2026-11-02)

Status: **approved by the owner, 2026-11-02.**

Builds on the approved plan `docs/redesign-ux-plan.md`. This spec defines the
shared language every screen spec uses: colour, type, spacing, surfaces and
the reusable components. No screen layouts here except the tab bar.

## 0. Owner's call
- Keep the intention (calm, paper, serif, ink); replace the look. Plan
  decisions D5 (paper cards), D6 (regular case), D10 (light and dark).

## 1. Diagnosis (what the current `Theme.swift` gets wrong)
1. **No surfaces.** `demoraSurface()` is a top hairline plus padding, so every
   block on every screen has the same weight; nothing anchors the eye.
2. **One accent does three jobs.** `accent` marks primary actions, stricter
   changes and active states; `Ink.danger` is the same hex as the red accent,
   so with the red accent "blocked" and "primary" become the same colour.
3. **Type has no ladder.** Sizes are set ad hoc (`42`, `43`, `38`, `title3`),
   monospaced captions are used as headers, and lowercase is the default.
4. **Components are named for old jobs** (`GridCard` draws a journal row) and
   each editor rebuilds rows, hints and buttons its own way.

## 2. Intent
In two seconds the user should feel *calm paper with one clock on it*: soft
cards on warm paper, serif for names and times, colour only where it means
something.

## 3. What we took from Mobbin
| App | What we take | Screen |
| --- | --- | --- |
| Brick | Warm neutral surfaces, generous radius, quiet secondary text | [schedules](https://mobbin.com/screens/64828f33-882c-4cde-9692-a6168730366b) |
| Opal | State chips on cards; deliberate "hold to commit" control | [rules](https://mobbin.com/screens/f6f2258d-c88e-4b70-b278-2950f8aad2bd), [editor](https://mobbin.com/screens/7bb284c6-ecb9-41f4-9c12-80bc34f02a3d) |
| 5 Minute Journal, Alma | Large serif on warm paper that stays modern | [5MJ](https://mobbin.com/screens/488c7a00-10fb-4673-9af3-8c9db20838dd), [Alma](https://mobbin.com/screens/6ea822ea-fbfa-46da-b996-22c85056bb6e) |
| Structured | A thread joining time-based items | [timeline](https://mobbin.com/screens/574482d9-3640-4553-805e-944f11f27428) |

## 4. The rule that removes the repetition
| Question | Where it lives |
| --- | --- |
| What colour is "blocked / looser"? | `Ink.loosen` only |
| What colour is "free / allowed"? | `Ink.free` only |
| What colour is the primary action? | `accent` only (one per screen) |
| How is a time shown? | `DemoraTime` styles only (serif, tabular digits) |
| How is a delay explained before saving? | `ChangeReceipt` only (no inline hints) |

## 5. Tokens

### 5.1 Colour (`Ink`, light / dark)
| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `paper` | `#F6F3EB` | `#191C1D` | Page background (unchanged) |
| `card` | `#FFFCF5` | `#222829` | PaperCard fill (was `surface`) |
| `cardRaised` | `#FFFFFF` | `#2A3133` | Sheets, receipt |
| `ink` | `#252E32` | `#EFEDE5` | Primary text |
| `inkSoft` | `#5E6566` | `#A5ADAE` | Secondary text (was `faint`; darkened for ≥ 4.5:1 on paper) |
| `hairline` | `#DCDAD0` | `#363D3F` | Card borders, dividers |
| `accent` (blue) | `#325F79` | `#A0C5D9` | Primary action, active, "stricter" |
| `accent` (red option) | `#A23B2E` | `#D9877A` | Same, when the user picks red |
| `loosen` | `#A23B2E` | `#D9877A` | Blocked, looser changes, removals |
| `loosen` (when accent is red) | `#8A5A12` | `#D6A55C` | Ochre, so blocked ≠ primary |
| `free` | `#4F6F55` | `#9DBFA3` | Free periods, "awake", allowed |
| `tint(x)` | 12 % of x on card | 22 % of x on card | Chip and receipt backgrounds |

Text on a tint always uses the full-strength token of the same family.
Contrast targets: body ≥ 4.5:1 on `paper` and `card`; large serif ≥ 3:1.
`hero`, `heroText`, `heroMuted` and `buttonText` are retired; the Now card is
a normal PaperCard.

### 5.2 Type (`DemoraType`, all Dynamic Type)
| Style | Font | Base | Use |
| --- | --- | --- | --- |
| `pageTitle` | New York, regular, −0.6 tracking | largeTitle (34) | Tab page titles |
| `hero` | New York, regular | title2 (22) | The Now sentence, receipt headline |
| `cardTitle` | New York, regular | headline size (17) | Rule names, change summaries |
| `time` | New York, tabular digits | title3 (20) | Countdowns, landing times |
| `timeLarge` | New York, tabular digits | largeTitle (34) | One per screen at most |
| `body` | SF Pro | body (17) | Sentences |
| `meta` | SF Pro | subheadline (15) | Card second lines |
| `label` | SF Pro, medium, small caps, +0.6 tracking | footnote (13) | Section headers |
| `chip` | SF Pro, medium | caption (12) | State chips |

Monospaced captions are retired. Text case defaults to **regular**; the
existing lowercase setting stays and keeps applying app-wide. Existing users
who never touched the setting move to regular (decision F3).

### 5.3 Spacing, radius, elevation
- 4-pt grid: 4 · 8 · 12 · 16 · 20 · 24 · 32. Page gutter 20; card padding 16;
  gap between cards 12; between sections 28.
- Radius: card 20, sheet 28, button capsule, chip capsule. Continuous corners.
- Elevation: hairline border only on cards; no shadows on paper. Sheets use
  the system sheet. Dark mode never uses shadows.
- Max content width 640 on iPad (unchanged).

## 6. Components (reuse first)
| Need | Use | Notes |
| --- | --- | --- |
| Card | **PaperCard** (new modifier `paperCard()`) | Replaces `demoraSurface()` call by call |
| Section header | **SectionHeader** (title, optional trailing link) | Replaces `DemoraSectionTitle` |
| Page title | **DemoraPageTitle** (restyled) | Drops the wordmark from every tab except Today |
| State chip | **StateChip** (kind: active/blocked/loosening/free/upcoming/neutral, text) | Non-interactive; 24 pt tall |
| Countdown | **CountdownText** (to: Date, style) | Wraps the existing TimeGuard-projection logic from `PendingChangeRow` so every countdown uses it |
| Countdown ring | **CountdownRing** (from created to appliesAt) | 28 pt ring + time; progress = elapsed share |
| Primary button | **DemoraPrimaryButtonStyle** (restyled) | One per screen |
| Hold to confirm | **HoldButton** (duration 1.2 s, tint) | Fills left→right; success haptic at end; cancels on release |
| Day chips | **DayChips** (Set<Weekday>) | Replaces 7 toggles and steppers wherever days are picked |
| Toggle | **DemoraToggleStyle** (kept) | Already 48 pt |
| Change receipt | **ChangeReceiptSheet** (action) | Defined in `today-redesign.md` §5.5 |
| Empty state | **EmptyStateView** (restyled into a PaperCard with one action) | |
| Tab bar | **DemoraTabBar** (restyled, 4 items) | §7 |
| Wordmark | **Wordmark** (kept) | Today header only |

Retired after the screens move over: `GridCard`, `DemoraDelayRow`,
`DemoraDayLine`, `DemoraTimelineMark`, `demoraSurface()`. Tutorial helpers stay
(legacy replay recovery).

Pure logic, with tests: contrast check of every token pair in §5.1 (light and
dark, both accents) in a harness, so a palette edit can't silently fail AA.

## 7. Tab bar
Four items, equal width, icon above label, on `paper` with a top hairline:
**Today** (`sun.horizon`), **Rules** (`list.bullet.rectangle`), **Insights**
(`chart.bar`), **You** (`person.crop.circle`). Selected = `accent`; others
`inkSoft`. Badges: Today shows a dot for an approval request waiting; You shows
a dot for a contact invite. The switch from five tabs to four happens only when
Rules, Insights and You are built (last integration step); until then the
current bar stays and Today replaces Home in place.

## 8. Changes elsewhere
- `Theme.swift`: new tokens and components; old names kept as thin aliases
  until each screen moves, then removed.
- Report extension (`LatchReport/`) reads the same palette: copy the token
  values into its own small theme file (it doesn't import all of `Shared`).
- Widgets and shield adopt `paper`/`card`/`ink` in their own specs.

## 9. Motion and haptics
- Countdowns tick each second with tabular digits (no layout jitter).
- Cards appear with a 0.2 s fade; no springs on paper.
- HoldButton: linear fill, light haptic at start, success haptic at end.
- Reduce Motion: no fills or fades, instant state changes; HoldButton becomes
  a button that asks for one confirmation.

## 10. Copy
Sentence case, contractions, verb-first buttons ("Block now", "Keep it as it
is"). Every new string goes through `tr()` in all eight languages.

## 11. Out of scope
Screen layouts (their own specs), app icon, App Store screenshots, iPad
multi-column layouts.

## 12. Decisions for the owner
| # | Decision | Why |
| --- | --- | --- |
| F1 | Add a third ink, sage green (`free`), for free periods and "awake" | Today accent means both "active block" and "free", which reads backwards |
| F2 | With the red accent, "blocked/looser" becomes ochre instead of brick | Otherwise blocked and the primary button are the same colour |
| F3 | Users who never changed text case move to regular case; anyone who picked lowercase keeps it | Plan D6, without overriding a deliberate choice |
| F4 | Hairline-bordered cards, no shadows | Keeps the paper feel; shadows look like a generic dashboard |
| F5 | Every time in the app uses the serif with tabular digits | Time is Demora's subject; it should look the same everywhere |
