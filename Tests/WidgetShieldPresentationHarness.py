#!/usr/bin/env python3
"""Generic shield and read-only widget display contracts.

No saved rules, private tokens, usage, live settings or Apple UI is accessed.
Compiles the actual snapshot in both build environments; no live settings.
"""
from pathlib import Path
import hashlib
import json
import re
import sys
import subprocess
import tempfile
sys.dont_write_bytecode = True
from FoundationsContrastHarness import palette, contrast, blend

ROOT = Path(__file__).resolve().parents[1]
shield = (ROOT / 'LatchShieldUI/ShieldConfigurationExtension.swift').read_text()
foundations, _ = palette((ROOT / 'Latch/Theme.swift').read_text())
pairs = {name: {'light': int(light, 16), 'dark': int(dark, 16)} for name, light, dark in
         re.findall(r'static let (\w+)\s*=\s*Pair\(light:\s*0x([0-9A-Fa-f]{6}),\s*dark:\s*0x([0-9A-Fa-f]{6})\)', shield)}
assert set(pairs) == {'paper', 'ink', 'inkSoft', 'accentBlue', 'accentRed'}
checks = 0
for name, pair in pairs.items():
    assert pair == foundations[name], ('shield/foundations palette drift', name)
for mode in ('light', 'dark'):
    for foreground in ('ink', 'inkSoft'):
        assert contrast(pairs[foreground][mode], pairs['paper'][mode]) >= 4.5
        checks += 1
    for accent in ('accentBlue', 'accentRed'):
        assert contrast(pairs['paper'][mode], pairs[accent][mode]) >= 4.5
        checks += 1
assert contrast(0xFFFFFF, pairs['accentBlue']['dark']) < 4.5, 'white-on-dark-accent regression is detected'

assert 'backgroundBlurStyle: nil' in shield
assert 'primaryButtonLabel: .init(text: tr("Close"), color: ShieldPalette.color(ShieldPalette.paper))' in shield
assert shield.count('-> ShieldConfiguration { latchShield() }') == 4, 'all app/category/domain overloads share the same display'
for forbidden in ('SharedStore', 'loadState(', 'ManagedSettingsStore', 'ShieldAction',
                  'URLSession', 'CKContainer', 'Keychain', 'TimeGuard', '.set(',
                  'localizedDisplayName', '.domain', 'immediate unblock', 'until midnight'):
    assert forbidden not in shield, ('generic display must not read/mutate/infer enforcement', forbidden)
assert 'UserDefaults(suiteName: LatchConstants.appGroupID)?.string(forKey: "latch.accentColor")' in shield
assert 'traits.userInterfaceStyle == .dark' in shield
assert 'preparingThumbnail(of: CGSize(width: 56, height: 56))' in shield
asset = ROOT / 'LatchShieldUI/Assets.xcassets/DemoraLogo.imageset/demora-logo.png'
original = ROOT / 'Latch/Assets.xcassets/DemoraLogo.imageset/demora-logo.png'
assert hashlib.sha256(asset.read_bytes()).digest() == hashlib.sha256(original.read_bytes()).digest(), 'reuse original mark unchanged'
manifest = json.loads((asset.parent / 'Contents.json').read_text())
assert manifest['images'][0]['filename'] == asset.name

string = r'"((?:[^"\\]|\\.)*)"'
keys = set(re.findall(r'\btr\(' + string + r'\)', shield))
assert keys == {'Blocked by your Demora rules', 'You set this earlier so it would hold.',
                "Open Demora to see what's on, or to ask for extra time if your limit has it.", 'Close'}
entry = re.compile(r'(?:^|,)\s*' + string + r'\s*:\s*' + string + r'\s*(?=,|$)', re.M)
for suffix in ('', '+German', '+French', '+Portuguese', '+Polish', '+Turkish', '+Hindi'):
    rows = entry.findall((ROOT / f'Shared/Localization{suffix}.swift').read_text())
    table = dict(rows)
    assert len(table) == len(rows), (suffix, 'duplicate keys')
    assert keys <= table.keys(), (suffix, 'missing shield copy', keys - table.keys())
    if suffix == '+Turkish':
        assert table['Close'] == 'Kapat', 'Close is the action, not the adjective near'
print(f'Generic shield: five palette pairs match foundations; {checks} contrast pairs pass; four overloads, read-only accent, original logo, four copy keys × seven catalogs passed')

with tempfile.TemporaryDirectory(prefix='demora-widget-check-') as directory:
    for mode in ('Debug', 'Release'):
        executable = str(Path(directory) / mode)
        flags = ['-D', 'WIDGET_EXTENSION'] + (['-D', 'DEBUG'] if mode == 'Debug' else [])
        subprocess.run(['swiftc', '-warnings-as-errors', *flags,
                        str(ROOT / 'Shared/DemoraWidgetSnapshot.swift'),
                        str(ROOT / 'Tests/WidgetPresentationHarness.swift'), '-o', executable], check=True)
        subprocess.run([executable], check=True)

snapshot = (ROOT / 'Shared/DemoraWidgetSnapshot.swift').read_text()
publisher = snapshot.split('static func publish(state ', 1)[1].split('/// Pure display', 1)[0]
for forbidden in ('TimeGuard.now(', 'DayNightWake.status(', 'GlobalWake.status(', 'LimitFeatures.wakeState(',
                  'loadState()', 'housekeeping', 'reconcile(', 'applyNow', 'wakeUp('):
    assert forbidden not in publisher, ('widget publication must not repair/apply enforcement', forbidden)
assert 'WakeWidgetProjection.windows(state: state, at: now, calendar: cal)' in publisher
assert 'static func publish(state _: LatchState) { refresh() }' in snapshot, 'never publish a stale UI state'
assert 'guard !SharedStore.simulating' in publisher
assert 'widgetProjection.lock' in publisher and 'private static func publishLatest() -> Bool' in publisher
assert 'defaults.data(forKey: LatchConstants.stateKey) == saved' in publisher
assert 'old.wakeDue = nil' in publisher, 'unreadable setup suppresses an old wake claim, never fabricates rules'
for required in ('TimeGuard.nowForDisplay(at: now)', 'GlobalWake.statusForDisplay(',
                 'DayNightWake.statusForDisplay(', 'LimitFeatures.wakeStateForDisplay('):
    assert required in publisher, ('only owning read-safe APIs feed wake projection', required)
engine = (ROOT / 'Shared/ChangeEngine.swift').read_text()
wake_all = engine.split('static func wakeUpAllOffMain()', 1)[1].split('static func setUpInitialDayNightOffMain', 1)[0]
assert wake_all.index('ShieldController.refresh()') < wake_all.index('DemoraWidgetSnapshot.refresh()') < wake_all.index('continuation.resume(returning: changed)')

host = (ROOT / 'Latch/LatchApp.swift').read_text()
home = (ROOT / 'Latch/HomeView.swift').read_text()
handler = host.split('.onOpenURL { url in', 1)[1].split('private func requestUpdateReviewIfNeeded', 1)[0]
assert 'model.state.isSetUp' in handler and '!model.inTutorial' in handler and '!model.setupStorageUnavailable' in handler
assert 'WidgetDestination.parse(url)' in handler and 'model.selectedTab = 0' in handler
assert 'HomeView(widgetDestination: $widgetDestination)' in host
consume = home.split('private func consumeWidgetDestination()', 1)[1].split('private var today:', 1)[0]
assert 'todayPath = destination == .changes ? [.changes] : []' in consume and 'widgetDestination = nil' in consume
assert 'NavigationStack(path: $todayPath)' in home and '.navigationDestination(for: TodayRoute.self)' in home
assert 'NavigationLink(value: TodayRoute.insights)' in home and 'NavigationLink(value: TodayRoute.help)' in home
assert 'ledgerNavigationReset = UUID()' in consume
assert 'homeNotice = nil' in consume, 'a prior Home alert must not obscure the widget destination'
assert 'navigationReset: ledgerNavigationReset' in home
ledger = (ROOT / 'Latch/ChangesLedgerView.swift').read_text()
reset = ledger.split('.onChange(of: navigationReset) { _ in', 1)[1].split('}', 1)[0]
for required in ('skipTarget = nil', 'notice = nil', 'confirmBulkCancel = false', 'selecting = false', 'selection = []'):
    assert required in reset, ('deep link must clear the retained ledger modal/selection', required)
for forbidden in ('ChangeEngine', 'ContactsRelay.', 'model.cancel', 'model.applyNow'):
    assert forbidden not in reset, 'UI reset never cancels or applies stored requests'
for forbidden in ('ChangeEngine', 'SharedStore', 'applyNow', 'wakeUp('):
    assert forbidden not in handler + consume, ('links only navigate', forbidden)
assert '$(DEMORA_URL_SCHEME)' in (ROOT / 'Latch/Info.plist').read_text()
project = (ROOT / 'Latch.xcodeproj/project.pbxproj').read_text()
assert 'DEMORA_URL_SCHEME = "demora-dev";' in project and 'DEMORA_URL_SCHEME = demora;' in project
print('Widget publication and bounded navigation source contracts passed')

theme = (ROOT / 'LatchWidgets/WidgetTheme.swift').read_text()
widget_pairs = {name: {'light': int(light, 16), 'dark': int(dark, 16)} for name, light, dark in
    re.findall(r'static let (\w+)\s*=\s*WidgetInkPair\(light:\s*0x([0-9A-Fa-f]{6}),\s*dark:\s*0x([0-9A-Fa-f]{6})\)', theme)}
aliases = {'loosenBlue': 'loosen', 'loosenRed': 'loosenOchre', 'sage': 'free'}
assert len(widget_pairs) == 10
for name, pair in widget_pairs.items():
    assert pair == foundations[aliases.get(name, name)], ('widget/foundations drift', name)
widget_contrast = 0
for mode in ('light', 'dark'):
    for foreground in ('ink', 'inkSoft', 'accentBlue', 'accentRed', 'loosenBlue', 'loosenRed', 'sage'):
        assert contrast(widget_pairs[foreground][mode], widget_pairs['card'][mode]) >= 4.5
        widget_contrast += 1
    for foreground in ('accentBlue', 'accentRed', 'loosenBlue', 'loosenRed'):
        ink = widget_pairs[foreground][mode]
        assert contrast(ink, blend(ink, widget_pairs['card'][mode], 0.12)) >= 4.5
        widget_contrast += 1
assert '.set(' not in theme and '.standard' not in theme.replace('// Read only; never fall back to the other build\'s suite or .standard.', '')
assert 'group.com.may.screentimedelay.dev' in theme and 'group.com.may.screentimedelay"' in theme
print(f'Widget theme: ten palette pairs and {widget_contrast} AA text/background pairs passed')

import GenerateWidgetLocalization as gallery
assert gallery.entries('"Now": "Jetzt", "Next": "Danach",') == [('Now', 'Jetzt'), ('Next', 'Danach')]
assert gallery.entries('"Quote": "a \\"quoted\\" word",') == [('Quote', 'a "quoted" word')]
catalog = json.loads((ROOT / 'LatchWidgets/Localizable.xcstrings').read_text())
assert set(catalog['strings']) == set(gallery.GALLERY_KEYS)
assert all(set(row['localizations']) == {'en', *gallery.LANGUAGES} for row in catalog['strings'].values())
assert (ROOT / 'LatchWidgets/Localizable.xcstrings').read_text() == gallery.render()
print('Generated widget gallery: four keys × eight languages, inline/escaped fixtures passed')

views = (ROOT / 'LatchWidgets/DemoraWidgets.swift').read_text()
assert views.count('.supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular])') == 2
assert 'let kind = "demora.now-next"' in views and 'let kind = "demora.pending-change"' in views
assert '.widgetURL(WidgetDestination.today.url)' in views and '.widgetURL(WidgetDestination.changes.url)' in views
assert 'surface.containerBackground(for: .widget)' in views and 'surface.padding(16).background(WidgetInk.card)' in views
assert '.contentMarginsDisabled' not in views
assert views.count('.privacySensitive()') >= 7 and '.accessibilityLabel(' not in views, 'private names also stay private in combined accessibility elements'
for forbidden in ('SharedStore', 'FamilyControls', 'ManagedSettings', 'DeviceActivityReport',
                  'AppIntent', 'Button(', 'ChangeEngine', 'TimeGuard', 'URLSession', 'CKContainer', '.set('):
    assert forbidden not in views, ('widget cannot own data/mutation paths', forbidden)
placeholder = views.split('func placeholder(in context:', 1)[1].split('func getSnapshot(', 1)[0]
assert '.load()' not in placeholder and '.sample(at: Date(), placeholder: true)' in placeholder
preview = views.split('if context.isPreview {', 1)[1].split('} else {', 1)[0]
assert '.load()' not in preview and 'completion(.sample(at: Date()))' in preview
assert 'placeholder: Bool = false' in views and 'isPlaceholder: placeholder' in views
chip = views.split('private struct DirectionChip:', 1)[1].split('private struct PendingCountdown:', 1)[0]
assert 'direction == "lenient"' in chip and 'direction == "stricter"' in chip
assert '.fixedSize(horizontal: true, vertical: false)' in chip, 'direction is readable even alongside a long heading'
print('Widget families, privacy, preview/loading separation and chip layout contracts passed')
