# App languages for 2.0.0: every App Store language

Status: **approved by the owner on 2026-11-16** ("Approve it"): Q1 all 36 in 2.0.0, Q2 one Portuguese and one Spanish (recommendations accepted).

The owner moved "translate the app into every App Store language" from after
2.0.0 into 2.0.0 itself.

The App Store listing is already in 50 App Store Connect locales
(`../AppStore/locales/`). The app UI is in 8 languages: en, es, de, fr, pt,
pl, tr, hi.

Decisions are L1–L9. Questions for the owner are Q1–Q2.

## L1. Which languages

Add **36 languages**, so the app speaks every language the listing does.

| Group | Languages |
|---|---|
| Europe | ca, cs, da, el, fi, hr, hu, it, nl, nb (Norwegian), ro, ru, sk, sl, sv, uk |
| Asia | id, ja, ko, ms, th, vi, zh-Hans, zh-Hant |
| South Asia | bn, gu, kn, ml, mr, or, pa, ta, te, ur |
| RTL | ar, he, ur |

Regional store variants share one app language:

- en-US/GB/CA/AU → en
- es-ES/MX → es
- fr-FR/CA → fr
- pt-BR/PT → pt

Chinese needs two app languages: Simplified (zh-Hans) and Traditional
(zh-Hant).

## L2. How

Keep Demora's own system: the `AppLanguage` enum, `tr()`, and one
`Shared/Localization+<Language>.swift` dictionary per language.

1. Add each language to `AppLanguage`.
   - Its label is the language's own name ("日本語", "Русский").
   - Device-language matching must handle scripts. `zh-Hans` and `zh-Hant`
     need more than `languageCode`. Norwegian `nb`/`no` maps to `nb`.
2. Every language gets all app strings. That covers:
   - the main dictionary (about 1,650 keys);
   - `Latch/InfoPlist.xcstrings`, including the Screen Time and location
     permission text, which App Review reads;
   - the widget catalog and the usage-report strings, through their
     generators;
   - the shield, notifications and widgets.
   - Every `--check` script is extended to cover all 44 languages:
     placeholders match, no keys missing or duplicated.
3. `knownRegions` in the project lists all of them, so iOS shows the app's
   languages correctly on the App Store page and in Settings.
4. The new languages are marked as beta translations (`isBetaTranslation`),
   so they get the existing "feedback on this translation" invite, like de,
   fr, pt, pl, tr and hi.

## L3. Right-to-left (ar, he, ur)

- The app sets the SwiftUI layout direction from `AppLanguage`.
- Custom-drawn pieces are checked one by one in the simulator:
  - the Today thread
  - countdown rings
  - chips
  - the tab bar
  - Hold to confirm
  - day chips (week order)
  - the change receipt
  - the photo cropper
- Arrows and chevrons that mean "back/forward" mirror; clocks and charts
  don't.

## L4. Fonts and text length

- Latin, Greek and Cyrillic keep the serif.
- Other scripts fall back to the system font for that script, as Hindi does
  today.
- Long languages (de, fi, ru, ta, ml) are checked for truncation on the
  smallest iPhone and at large text sizes. Fixed widths that cut text get
  scaled or wrapped.

## L5. Translation quality

- Translations come from the English source (and match the reviewed Spanish
  for meaning).
- The app's own vocabulary is used consistently: Today / Rules / Insights /
  You, "wait", "delay", "New session", "When & where", "Hold to confirm". Use
  the same words the store listing already uses for each language
  (`../AppStore/locales/`).
- Each language gets a second pass checking:
  - tone: calm and plain;
  - format placeholders;
  - plural and gender forms;
  - length.
- **Not checked by native speakers.** The in-app feedback invite is the
  safety net. The README and the store copy note this.

## L6. Build order

1. **Infrastructure (one session).**
   - Enum, matching, picker, `knownRegions`, RTL environment.
   - The generators and checks extended to read per-language source files.
   - A placeholder file per language that falls back to English, so the app
     builds before translations land.
2. **Translations (parallel sessions).** Each session handles one group of
   languages and writes only that group's own files:
   - `Localization+<Lang>.swift`;
   - per-language source files for the Info.plist, widget and report
     strings, which the generators merge.
   - No two sessions touch the same file.
3. **Merge + checks.** All checks, the RTL and length simulator pass, then a
   fresh reviewer that spot-checks a sample of each language and the
   infrastructure.
4. **Screenshots** in every language: the screenshot session reruns its
   script.

## L7. Cost and time

- About 60,000 strings to translate.
- The translation sessions run in parallel on Sonnet, with an Opus reviewer.
- This delays the 2.0.0 upload by roughly a day.
- Build time grows a little because of the larger dictionaries.

## L8. What stays the same

- Engine behaviour and stored data are unchanged.
- The language choice still lives in `latch.language`.
- English stays the fallback for any missing key.

## L9. Store copy

Once the app speaks every language, the listings lose their "the app itself
is in English, Spanish…" line. That's a small App Store Connect edit at upload
time; the description files in `../AppStore/locales/` are updated together.

## Questions for the owner

- **Q1. Ship all 36 in 2.0.0, or start with the biggest markets?**
  - Recommendation: **all 36.** The machinery is the same, and the listing
    already promises them.
- **Q2. Keep one Portuguese (Brazil-style) and one Spanish for every store
  region?**
  - Recommendation: **yes.**

## Translation kit (stage 2)

Written by the infrastructure session (stage 1) on 2026-11-16.

### One file per language

Each language is **one file**: `Shared/Localization+<Name>.swift`. A stage-2
session writes only its own languages' files. Nothing else.

The other catalogs are **generated** from these files in stage 3. Translators
don't touch or regenerate them:

- `LatchWidgets/Localizable.xcstrings` (widget gallery);
- `LatchReport/UsageInsightsLocalization.swift` (usage report);
- `Latch/InfoPlist.xcstrings` (the location and camera permission text App
  Review reads). These purpose strings are ordinary keys in the dictionary.

| Code | File (`Shared/…`) | Table | Store vocabulary (`../AppStore/locales/`) |
|---|---|---|---|
| ca | `Localization+Catalan.swift` | `catalanStrings` | `ca.md` |
| cs | `Localization+Czech.swift` | `czechStrings` | `cs.md` |
| da | `Localization+Danish.swift` | `danishStrings` | `da.md` |
| el | `Localization+Greek.swift` | `greekStrings` | `el.md` |
| fi | `Localization+Finnish.swift` | `finnishStrings` | `fi.md` |
| hr | `Localization+Croatian.swift` | `croatianStrings` | `hr.md` |
| hu | `Localization+Hungarian.swift` | `hungarianStrings` | `hu.md` |
| it | `Localization+Italian.swift` | `italianStrings` | `it.md` |
| nl | `Localization+Dutch.swift` | `dutchStrings` | `nl-NL.md` |
| nb | `Localization+Norwegian.swift` | `norwegianStrings` | `no.md` |
| ro | `Localization+Romanian.swift` | `romanianStrings` | `ro.md` |
| ru | `Localization+Russian.swift` | `russianStrings` | `ru.md` |
| sk | `Localization+Slovak.swift` | `slovakStrings` | `sk.md` |
| sl | `Localization+Slovenian.swift` | `slovenianStrings` | `sl.md` |
| sv | `Localization+Swedish.swift` | `swedishStrings` | `sv.md` |
| uk | `Localization+Ukrainian.swift` | `ukrainianStrings` | `uk.md` |
| id | `Localization+Indonesian.swift` | `indonesianStrings` | `id.md` |
| ja | `Localization+Japanese.swift` | `japaneseStrings` | `ja.md` |
| ko | `Localization+Korean.swift` | `koreanStrings` | `ko.md` |
| ms | `Localization+Malay.swift` | `malayStrings` | `ms.md` |
| th | `Localization+Thai.swift` | `thaiStrings` | `th.md` |
| vi | `Localization+Vietnamese.swift` | `vietnameseStrings` | `vi.md` |
| zh-Hans | `Localization+ChineseSimplified.swift` | `chineseSimplifiedStrings` | `zh-Hans.md` |
| zh-Hant | `Localization+ChineseTraditional.swift` | `chineseTraditionalStrings` | `zh-Hant.md` |
| bn | `Localization+Bengali.swift` | `bengaliStrings` | `bn-IN.md` |
| gu | `Localization+Gujarati.swift` | `gujaratiStrings` | `gu.md` |
| kn | `Localization+Kannada.swift` | `kannadaStrings` | `kn.md` |
| ml | `Localization+Malayalam.swift` | `malayalamStrings` | `ml.md` |
| mr | `Localization+Marathi.swift` | `marathiStrings` | `mr.md` |
| or | `Localization+Odia.swift` | `odiaStrings` | `or.md` |
| pa | `Localization+Punjabi.swift` | `punjabiStrings` | `pa.md` |
| ta | `Localization+Tamil.swift` | `tamilStrings` | `ta.md` |
| te | `Localization+Telugu.swift` | `teluguStrings` | `te.md` |
| ar | `Localization+Arabic.swift` | `arabicStrings` | `ar-SA.md` |
| he | `Localization+Hebrew.swift` | `hebrewStrings` | `he.md` |
| ur | `Localization+Urdu.swift` | `urduStrings` | `ur.md` |

### Steps for a translator

1. Print a complete skeleton. It has every key, English values, and the
   Spanish file's section comments:
   `python3 Tests/AppLanguagesHarness.py --template ja`
2. Replace the language's placeholder file with it, then translate every value.
   - Read the reviewed Spanish (`Shared/Localization.swift`) for meaning.
   - Read the store copy (table above) and reuse its words: the four tabs
     (Today · Rules · Insights · You), wait / delay, New session, When & where,
     Hold to confirm, the app name **demora**.
3. When every value is done, change the header line `// Translation: pending`
   to `// Translation: complete`.
4. Run the check for your languages only:
   `python3 Tests/AppLanguagesHarness.py --language ja`
5. Commit only your own files, staging them by name. Never push.

### Rules the check enforces

- **Keys.** Every key in the Spanish reference table, and no other key.
  - Keys are the exact English text: same apostrophes, `…`, `·`, `→`, case
    and spacing.
  - Never edit a key.
  - No duplicate keys. A duplicate crashes the app.
- **Placeholders.** `%@`, `%d` and `%%` must match the English exactly, in
  order.
  - To reorder them, number every placeholder in that value: `%2$@ … %1$@`.
  - Never mix numbered and plain placeholders in one value.
- **Values.**
  - No empty values.
  - No Swift interpolation: `\(`.
  - Escape `"` as `\"` and `\` as `\\`.
- **Leftover English.** When a file is marked complete, at most 10% of its
  values may equal the English. The real share is about 1–2%: `OK`, `%@ h`,
  brand names.
- **Pending.** A pending file may be partial. The check still rejects
  duplicates, unknown keys and placeholder mismatches in the entries present.
  It reports progress as "pending: n of N".

### Writing rules (L5)

- Calm, plain, second person. Use the informal "you" wherever the language
  has one (as the Spanish does), unless the store copy uses the formal form.
- **Plurals.** The app has no plural engine: one value serves every count.
  Phrase counts neutrally where the grammar needs forms (ru, uk, pl, cs, sk,
  sl, hr, ar, he), for example "Days: %d".
- **Gender.** Avoid gendered forms for the user.
- **Length.** Labels sit on chips and buttons. Keep them near the English
  length; prefer the shorter of two good options.
- **Not ours to change.**
  - Brand names: demora, Screen Time / Apple's own term for it.
  - The EFF word list.
  - The fixed phrase text users type.
- **RTL (ar, he, ur).**
  - Write naturally.
  - Don't add direction marks.
  - The layout mirrors by itself.

### After stage 2 (stage 3)

1. Regenerate the three generated catalogs:
   - `python3 Tests/GenerateWidgetLocalization.py --patch`
   - `python3 Tests/GenerateUsageLocalization.py --patch`
   - `python3 Tests/GenerateInfoPlistLocalization.py --patch`
2. Apply each patch.
3. `python3 Tests/AppLanguagesHarness.py --strict` must pass, then the full
   verify.
