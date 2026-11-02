# Demora iOS full redesign — review

## Start here
- **State:** the foundations layer (`docs/foundations-redesign.md`) is built
  on `design/full-redesign` in five commits after `862cc9c`. Nothing is
  pushed. Verify passes: the existing harnesses, the three new ones
  (`FoundationsContrastHarness`, `FoundationsComponentsHarness`,
  `TextCaseDefaultHarness`), `git diff --check`, and unsigned arm64 Debug and
  Release builds of the Latch scheme.
- **Install / run:** open `Latch.xcodeproj`, scheme **Latch**, Debug, on a
  device. No simulator runtime is installed on this Mac, so nothing here was
  looked at on screen.
- **What to try, in order:**
  1. Fresh install, or a device that never touched Settings → Text case: the
     app is now in regular case. A device where lowercase was picked stays
     lowercase.
  2. Home → pending changes: the countdown should look and tick exactly as
     before (it now goes through `CountdownText`).
  3. The tab bar: same five tabs and order; labels are SF Pro, the selected
     tab's icon and label are in the accent, and the small bar above the
     selected tab is gone.
  4. Empty states (Home with no limits, no pending changes; Limits with no
     limits): now drawn as paper cards.
  5. Any primary button: SF Pro semibold label instead of the serif.
- **Decisions most worth your eye:**
  - Dark-mode tints use 12 % instead of the spec's 22 %; 22 % left red and
    ochre chip text below 4.5:1 (3.8 and 4.3).
  - `Ink.danger` keeps the brick red even with the red accent, so today's
    screens don't change colour; new work uses `loosen`, which turns ochre.
  - Buttons use SF Pro semibold (the spec lists no button style; buttons are
    verb-first sentences, which the type ladder gives to SF Pro).
  - The tab bar restyle shipped; the four-tab switch did not (by design).
- **Known limits:** nothing was checked on a screen or device; components
  other than `CountdownText` aren't placed on screens yet; the report
  extension's own palette copy is still to do.
- **Housekeeping:** build products are in this session's scratchpad, outside
  the repo.

## Sessions
| Session | Scope | Commits | Status |
| --- | --- | --- | --- |
| Foundations build | Tokens, type, components, text case, tab bar | `7af8f65`, `46181bc`, `b15b244`, `d448215`, `5fad6e0` | Done, awaiting review |

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
