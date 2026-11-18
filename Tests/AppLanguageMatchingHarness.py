#!/usr/bin/env python3
"""Device-language matching and the AppLanguage list (docs/app-languages-2.0.md L2).

Compiles the real Shared/AppLanguageMatching.swift (pure; no preferences or
Locale lookups) with a test driver on this Mac and checks scripts (zh-Hans /
zh-Hant, zh-HK/TW/MO), Norwegian (no/nb/nn → nb), legacy codes, regional
variants and the walk through the preferred list. Also checks that AppLanguage,
tr(), the 44 dictionary files, the report extension's generated copy of the
matcher and the RTL set all agree. Source checks; not an iOS run.
"""

import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_languages as L  # noqa: E402

ROOT = L.ROOT
matcher = (ROOT / 'Shared/AppLanguageMatching.swift').read_text()
localization = (ROOT / 'Shared/Localization.swift').read_text()

# --- AppLanguage cases = the 44 codes, each wired into tr() ----------------
enum = localization.split('enum AppLanguage', 1)[1].split('\n}\n', 1)[0]
cases = re.findall(r'^    case (\w+) = "([^"]+)"$', enum, re.M)
assert [code for _, code in cases] == L.CODES, ([c for _, c in cases], L.CODES)
labels = dict(re.findall(r'case \.(\w+): return "([^"]+)"', enum))
assert set(labels) == {name for name, _ in cases}, 'every language has a native label'
assert len(set(labels.values())) == len(labels), 'labels are distinct'
assert labels['japanese'] == '日本語' and labels['chineseTraditional'] == '繁體中文', labels
tr_body = localization.split('func compiledTable(for language: AppLanguage) -> [String: String]? {', 1)[1].split('\n}\n', 1)[0]
wired = dict(re.findall(r'case \.(\w+): table = (\w+)', tr_body))
assert 'case .english: table = nil' in tr_body
for (name, code) in cases[1:]:
    assert wired.get(name) == L.BY_CODE[code][1], (name, wired.get(name))
assert 'self != .english && self != .spanish' in enum, 'every new language is a beta translation'
assert re.search(r'var isRightToLeft: Bool \{\s*self == \.arabic \|\| self == \.hebrew \|\| self == \.urdu\s*\}', enum)
assert 'return deviceMatch(Locale.preferredLanguages)' in enum, 'current follows the shared matcher'
for code in L.CODES[1:]:
    assert L.path(code).exists(), code
print(f'AppLanguage passed: {len(cases)} languages, native labels, tr() wired, RTL = ar/he/ur')

# --- The matcher itself, compiled and run --------------------------------
CASES = [
    # (preferred list, expected)
    (['en-US'], 'en'), (['en-GB', 'fr'], 'en'), (['es-MX'], 'es'), (['es-419'], 'es'),
    (['pt-BR'], 'pt'), (['pt-PT'], 'pt'), (['fr-CA'], 'fr'), (['de-AT'], 'de'),
    (['zh-Hans-CN'], 'zh-Hans'), (['zh-Hant-TW'], 'zh-Hant'), (['zh-Hant-HK'], 'zh-Hant'),
    (['zh-HK'], 'zh-Hant'), (['zh-TW'], 'zh-Hant'), (['zh-MO'], 'zh-Hant'), (['zh_TW'], 'zh-Hant'),
    (['zh-CN'], 'zh-Hans'), (['zh-SG'], 'zh-Hans'), (['zh'], 'zh-Hans'),
    (['zh-Hans-HK'], 'zh-Hans'), (['yue-Hant-HK'], 'zh-Hant'), (['yue'], 'zh-Hant'),
    (['nb-NO'], 'nb'), (['no'], 'nb'), (['nn-NO'], 'nb'), (['NO'], 'nb'),
    (['iw-IL'], 'he'), (['he'], 'he'), (['in-ID'], 'id'), (['id-ID'], 'id'),
    (['ar-SA'], 'ar'), (['ar-001'], 'ar'), (['ur-PK'], 'ur'), (['ur-IN'], 'ur'),
    (['pa-IN'], 'pa'), (['pa-Guru-IN'], 'pa'), (['pa-Arab-PK', 'ur'], 'ur'), (['pa-Arab'], 'en'),
    (['ms-MY'], 'ms'), (['ms-Arab', 'en'], 'en'), (['bn-IN'], 'bn'), (['or-IN'], 'or'),
    (['ja-JP'], 'ja'), (['ko-KR'], 'ko'), (['th-TH'], 'th'), (['vi-VN'], 'vi'),
    (['el-GR'], 'el'), (['ru-RU'], 'ru'), (['uk-UA'], 'uk'), (['ca-ES'], 'ca'),
    # Walk the whole list, as iOS does: first supported wins.
    (['sw-KE', 'es-ES'], 'es'), (['fil-PH', 'ja'], 'ja'), (['sr-Latn-RS', 'hr'], 'hr'),
    (['sw', 'xx'], 'en'), ([], 'en'), ([''], 'en'), (['-'], 'en'),
]
driver = ('let supported: Set<String> = ' + json.dumps(L.CODES) + '\n'
          'let cases: [[String]] = ' + json.dumps([p for p, _ in CASES]) + '\n'
          'for preferred in cases { print(AppLanguageMatching.code(preferred: preferred, supported: supported)) }\n'
          'print(AppLanguageMatching.code(for: "fr-CA", supported: ["en"]) == nil ? "nil" : "bad")\n')
with tempfile.TemporaryDirectory(prefix='demora-language-match-') as folder:
    folder = Path(folder)
    (folder / 'main.swift').write_text(driver)
    binary = folder / 'match'
    subprocess.run(['xcrun', 'swiftc', '-warnings-as-errors', '-module-cache-path', str(folder / 'cache'),
                    str(ROOT / 'Shared/AppLanguageMatching.swift'), str(folder / 'main.swift'),
                    '-o', str(binary)], check=True)
    output = subprocess.run([str(binary)], check=True, capture_output=True, text=True).stdout.split()
for (preferred, expected), got in zip(CASES, output):
    assert got == expected, (preferred, expected, got)
assert output[-1] == 'nil' and len(output) == len(CASES) + 1, output
print(f'Device-language matching passed: {len(CASES)} preferred lists (scripts, Norwegian, legacy codes, list walk)')

# --- Pure: no preferences, no Locale; the report copies it verbatim --------
body = matcher.split('// BEGIN APP LANGUAGE MATCHING\n', 1)[1].split('// END APP LANGUAGE MATCHING', 1)[0]
for word in ('UserDefaults', 'SharedStore', 'Locale', 'Bundle'):
    assert word not in body, word
report = (ROOT / 'LatchReport/UsageInsightsLocalization.swift').read_text()
assert body in report, 'report extension carries the same matcher (regenerate the report snapshot)'
assert 'AppLanguageMatching.code(preferred: Locale.preferredLanguages' in report
theme = (ROOT / 'LatchReport/ReportTheme.swift').read_text()
assert 'reportLanguageCode()' in theme and 'let supported = [' not in theme, 'report locale uses the shared matcher'
print('Matcher copies passed: pure, and identical in the report extension')

# --- The project and bundle list every app language ------------------------
import plistlib
project = (ROOT / 'Latch.xcodeproj/project.pbxproj').read_text()
regions = re.search(r'knownRegions = \((.*?)\);', project, re.S).group(1)
regions = [r.strip().strip('"') for r in regions.split(',') if r.strip()]
assert regions == L.CODES + ['Base'], regions
info = plistlib.loads((ROOT / 'Latch/Info.plist').read_bytes())
assert info['CFBundleLocalizations'] == L.CODES, info['CFBundleLocalizations']
print(f'Project passed: knownRegions and CFBundleLocalizations list all {len(L.CODES)} languages')

# --- RTL: one direction from AppLanguage, everywhere it can reach (L3) -----
app = (ROOT / 'Latch/LatchApp.swift').read_text()
assert '.environment(\\.layoutDirection, model.language.layoutDirection)' in app, 'root follows the app language'
assert 'AppLanguage.current.applyUIKitLayoutDirection()' in app.split('var body: some Scene', 1)[0], 'UIKit set before windows'
assert 'language.applyUIKitLayoutDirection()' in app and 'forceRightToLeft : .forceLeftToRight' in app
assert 'var layoutDirection: LayoutDirection { isRightToLeft ? .rightToLeft : .leftToRight }' in app
snapshot = (ROOT / 'Shared/DemoraWidgetSnapshot.swift').read_text()
assert 'var rightToLeft: Bool? = nil' in snapshot and 'rightToLeft: AppLanguage.current.isRightToLeft' in snapshot
widgets = (ROOT / 'LatchWidgets/DemoraWidgets.swift').read_text()
assert widgets.count('.rightToLeft == true ? .rightToLeft : .leftToRight)') == 2, 'both widgets mirror with the app'
theme = (ROOT / 'LatchReport/ReportTheme.swift').read_text()
assert 'layoutDirection: reportIsRightToLeft() ? .rightToLeft : .leftToRight' in theme
assert '.environment(\\.layoutDirection, preferences.layoutDirection)' in (ROOT / 'LatchReport/UsageInsightsView.swift').read_text()
assert 'reportIsRightToLeft() ? .rightToLeft : .leftToRight' in (ROOT / 'LatchReport/LimitsUsageView.swift').read_text()
# Charts never mirror: the time-series bars (and their week arrows) stay left to right.
for name in ('UsageInsightsView.swift', 'UsageTrendsView.swift'):
    assert '// Charts never mirror' in (ROOT / 'LatchReport' / name).read_text() and \
        '.environment(\\.layoutDirection, .leftToRight)' in (ROOT / 'LatchReport' / name).read_text(), name
# Back/forward chevrons are the semantic, mirroring symbols.
for folder in ('Latch', 'LatchReport', 'LatchWidgets', 'Shared'):
    for source in (ROOT / folder).glob('*.swift'):
        text = source.read_text()
        assert '"chevron.right"' not in text and '"chevron.left"' not in text, (source.name, 'use chevron.forward/backward')
print('RTL passed: root + UIKit + widgets + report follow the app language; charts stay LTR; chevrons mirror')

# --- Picker: 44 entries, applied language first, then by name --------------
picker = (ROOT / 'Latch/SettingsView.swift').read_text().split('struct LanguagePickerView: View {', 1)[1].split('\nstruct ', 1)[0]
assert 'AppLanguage.pickerOrder(applied: model.language)' in picker and '.searchable(text: $search)' in picker
assert 'LazyVStack' in picker and 'language.name(in: model.language)' in picker
onboarding = (ROOT / 'Latch/OnboardingView.swift').read_text()
assert 'ForEach(AppLanguage.pickerOrder(applied: model.language))' in onboarding and '.pickerStyle(.menu)' in onboarding
assert 'static func pickerOrder(applied: AppLanguage) -> [AppLanguage]' in localization
print('Language picker passed: ordered, searchable, native names; onboarding uses a submenu')

# "Open" arrows (GridCard, the Theme time card, the contacts row) mirror in RTL (stage 3 simulator pass).
for name, count in (('Latch/Theme.swift', 2), ('Latch/ContactsOverrideViews.swift', 1)):
    text = (ROOT / name).read_text()
    assert text.count('Image(systemName: "arrow.up.right")') == count, name
    mirrored = re.findall(r'Image\(systemName: "arrow\.up\.right"\)\n(?:\s*//[^\n]*\n)?\s*\.flipsForRightToLeftLayoutDirection\(true\)', text)
    assert len(mirrored) == count, (name, len(mirrored))
print('Open arrows mirror in RTL')

# --- Stage 3 follow-ups ----------------------------------------------------
# The beta invite survives applying a language: Language is a path route (an
# untracked NavigationLink page was dropped when the stack rebuilt), and the
# picker's alert is driven by a model flag, so a rebuilt page still shows it.
you = (ROOT / 'Latch/YouView.swift').read_text()
pages = (ROOT / 'Latch/YouPages.swift').read_text()
model_src = (ROOT / 'Latch/AppModel.swift').read_text()
assert 'case appearance, preventDisabling, help, credits, language' in you
assert 'case .language: LanguagePickerView()' in you
assert 'model.youPath.append(.language)' in pages and 'NavigationLink { LanguagePickerView() }' not in pages
assert '@Published var betaNoticeLanguage: AppLanguage?' in model_src
assert 'model.betaNoticeLanguage != nil' in picker and 'tr("Translation in beta")' in picker
assert 'model.betaNoticeLanguage = selectedLanguage' in picker
assert 'showLanguageBetaNotice' not in (ROOT / 'Latch/SettingsView.swift').read_text()
# Dates, times and counts format in the app language, not the device region.
assert 'func appFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle)' in localization
for folder in ('Latch',):
    for source in (ROOT / folder).glob('*.swift'):
        for line in source.read_text().splitlines():
            if re.search(r'\.formatted\(\s*date:', line) or re.search(r'\.formatted\(\)', line):
                raise AssertionError((source.name, 'use appFormatted or pass the app locale', line.strip()))
assert 'localeIdentifier: AppLanguage.current.rawValue' in snapshot
assert widgets.count('.appLocale(WidgetPresentation.copy(snapshot: entry.snapshot).localeIdentifier)') == 2
print('Stage 3 follow-ups passed: beta invite on the You stack, app-language formatting, widget locale')
