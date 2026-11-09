#!/usr/bin/env python3
"""Phase-1 generic shield contracts and actual palette parity/contrast.

No saved rules, private tokens, usage, live settings or Apple UI is accessed.
Widget projection checks are added with the separately verified widget step.
"""
from pathlib import Path
import hashlib
import json
import re
import sys
sys.dont_write_bytecode = True
from FoundationsContrastHarness import palette, contrast

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
