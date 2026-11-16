#!/usr/bin/env python3
"""Read-only source checks for host/guide and self-contained report localization.

No Xcode build, defaults mutation, Screen Time query, or usage export is performed.
"""
from collections import Counter
import json
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True
from GenerateUsageLocalization import report_keys as required_report_keys
import app_languages as L

ROOT = Path(__file__).resolve().parents[1]
STRING = r'"((?:[^"\\]|\\.)*)"'
ENTRY = re.compile(r'^\s*' + STRING + r'\s*:\s*' + STRING + r',?\s*$', re.M)
PLACEHOLDER = re.compile(r'%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|[hlLzjt])?[@diuoxXfFeEgGcs%]')


def decode(value):
    return json.loads('"' + value + '"')


def entries(source):
    return [(decode(key), decode(value)) for key, value in ENTRY.findall(source)]


def calls(source, function):
    return {decode(key) for key in re.findall(r'\b' + function + r'\(\s*' + STRING, source)}


def placeholders(value):
    # Numbered placeholders (%2$@) count as their plain type.
    return Counter(re.sub(r'^%\d+\$', '%', token)
                   for token in PLACEHOLDER.findall(value) if token != '%%')


def verify_table(label, pairs, required):
    counts = Counter(key for key, _ in pairs)
    duplicates = [key for key, count in counts.items() if count != 1]
    assert not duplicates, (label, 'duplicate keys', duplicates)
    table = dict(pairs)
    missing = sorted(required - table.keys())
    assert not missing, (label, 'missing translations', missing)
    for key in required:
        value = table[key]
        assert value.strip(), (label, key, 'empty translation')
        # Shared terms, numeric formats and loanwords are valid translations.
        # Long prose identical to English is not a translation.
        if len(key.split()) > 8:
            assert value != key, (label, key, 'English prose fallback')
        assert placeholders(key) == placeholders(value), (label, key, 'format placeholders')
    return table


def main():
    host = (ROOT / 'Latch/UsageInsightsView.swift').read_text()
    settings = (ROOT / 'Latch/SettingsView.swift').read_text()
    guide = settings.split('struct GuideTopic:', 1)[1].split('// MARK: - Language', 1)[0]
    required = calls(host, 'tr') | calls(guide, 'tr') | {
        'Find practical instructions and troubleshooting in You → Help & guide → Guide.'
    }
    shared = {}
    # Published languages: the original eight plus each 2.0 language marked
    # complete (pending ones fall back to English and have no report table).
    published = L.complete_tables()
    languages = list(published)
    for code in languages:
        path = L.path(code)
        shared[code] = verify_table(path.name, list(published[code].items()), required)

    helper = (ROOT / 'LatchReport/UsageInsightsLocalization.swift').read_text()
    report_sources = [path.read_text() for path in (ROOT / 'LatchReport').glob('UsageInsights*.swift')
                      if path.name != 'UsageInsightsLocalization.swift']
    report_keys = required_report_keys()
    assert report_keys, 'No report keys found; wait for the report view to stabilize'
    for code in languages:
        block = helper.split(f'// LANGUAGE {code}\n', 1)[1].split('// END LANGUAGE', 1)[0]
        table = verify_table('report ' + code, entries(block), report_keys)
        for key in report_keys & shared[code].keys():
            assert table[key] == shared[code][key], (code, key, 'must reuse Shared translation')

    raw_values = re.findall(r'^    case \w+ = "([A-Za-z-]+)"$',
                            (ROOT / 'Shared/Localization.swift').read_text(), re.M)
    assert raw_values == L.CODES, raw_values
    assert 'nonisolated func insightsText(' in helper
    assert 'nonisolated func reportLanguageCode(' in helper
    assert 'let supported: Set<String> = [' + ', '.join(json.dumps(c) for c in L.CODES) + ']' in helper
    assert 'UserDefaults(suiteName: AppGroup.id)?.string(forKey: "latch.language")' in helper
    assert 'Locale.preferredLanguages' in helper
    text_switch = helper.split('nonisolated func insightsText(', 1)[1]
    assert set(re.findall(r'case "([A-Za-z-]+)":', text_switch)) == set(languages)
    # Preferences are read only; raw usage/state, network, logging and actor-bound
    # Shared dependencies have no place in this extension-local helper.
    code = re.sub(r'//[^\n]*', '', helper)
    code = re.sub(STRING, '""', code)
    for forbidden in (r'\.set\s*\(', r'removeObject', r'synchronize\s*\(', r'\.write\s*\(',
                      r'URLSession', r'URLRequest', r'FileManager', r'print\s*\(',
                      r'Logger', r'os_log', r'@MainActor', r'SharedStore', r'AppLanguage(?!Matching)',
                      r'JSONEncoder', r'JSONDecoder', r'data\s*\(forKey:'):
        assert not re.search(forbidden, code), ('forbidden helper operation', forbidden)
    preference_keys = re.findall(r'forKey:\s*"([^"]+)"', helper)
    assert preference_keys == ['latch.language'], preference_keys
    print(f'PASS: {len(required)} host/guide keys × {len(languages)} tables; '
          f'{len(report_keys)} report keys × {len(languages)} tables; '
          'unique keys, non-English values, format placeholders, exact Shared reuse, '
          'language raw values and read-only/nonisolated helper guards.')


if __name__ == '__main__':
    main()
