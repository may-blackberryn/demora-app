#!/usr/bin/env python3
"""Generate LatchWidgets/Localizable.xcstrings from Shared/Localization*.swift.

Only the four literal WidgetKit gallery keys belong in this catalog. Runtime
copy follows the in-app language through DemoraWidgetSnapshot, not this catalog.
English keys and the seven app dictionaries are the only translation sources.
Validate whole dictionaries (including inline entries) before rendering JSON.

Default: print deterministic JSON. --check: compare it with the checked-in file.
--patch: print an apply_patch patch; apply it with the patch tool to update the
file. This script never writes files, reads preferences/live data, or uses network.
"""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'LatchWidgets/Localizable.xcstrings'
LANGUAGES = {'es': '', 'de': '+German', 'fr': '+French', 'pt': '+Portuguese',
             'pl': '+Polish', 'tr': '+Turkish', 'hi': '+Hindi'}
GALLERY_KEYS = (
    'Now & next',
    "See what's on now and what's next.",
    'Changing soon',
    'Your next change and when it lands.',
)
RUNTIME_KEYS = (
    'until %@',
    'Used up today',
    'Nothing blocked',
    'Changes you make wait here.',
    'Good morning. Tap to wake up.',
    'Looser',
    'Stricter',
    'Open Demora',
    'Now',
    'Next %@ · %@',
    'No changes waiting',
)
STRING = r'"((?:[^"\\]|\\.)*)"'
# Same inline-aware entry boundary as Tests/YouPresentationHarness.py. The comma
# is consumed before an entry, but only looked ahead after it, so several pairs
# on one line are all scanned (unlike the report generator's whole-line regex).
ENTRY = re.compile(r'(?:^|,)\s*' + STRING + r'\s*:\s*' + STRING + r'\s*(?=,|$)', re.M)
PLACEHOLDER = re.compile(
    r'%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?'
    r'(?:hh|ll|[hlLzjt])?[@diuoxXfFeEgGcs%]')


def entries(source):
    return [(json.loads('"' + key + '"'), json.loads('"' + value + '"'))
            for key, value in ENTRY.findall(source)]


def placeholders(value):
    return Counter(token for token in PLACEHOLDER.findall(value) if token != '%%')


def load_tables():
    required = set(GALLERY_KEYS) | set(RUNTIME_KEYS)
    tables = {}
    for code, suffix in LANGUAGES.items():
        path = ROOT / f'Shared/Localization{suffix}.swift'
        pairs = entries(path.read_text(encoding='utf-8'))
        counts = Counter(key for key, _ in pairs)
        duplicates = sorted(key for key, count in counts.items() if count > 1)
        if duplicates:
            raise ValueError(f'{path.name}: duplicate dictionary keys: {duplicates}')
        table = dict(pairs)
        missing = sorted(required - table.keys())
        if missing:
            raise ValueError(f'{path.name}: missing widget translations: {missing}')
        # Validate every pair, not just gallery/runtime keys, so generation cannot
        # hide a duplicate-key trap or a damaged format elsewhere in the table.
        for key, value in pairs:
            if not value.strip():
                raise ValueError(f'{path.name}: empty translation for {key!r}')
            if placeholders(key) != placeholders(value):
                raise ValueError(f'{path.name}: format placeholders differ for {key!r}')
        tables[code] = table
    return tables


def render(tables=None):
    if tables is None:
        tables = load_tables()
    strings = {}
    for key in sorted(GALLERY_KEYS):
        values = {'en': key, **{code: tables[code][key] for code in LANGUAGES}}
        strings[key] = {
            'extractionState': 'manual',
            'localizations': {
                code: {'stringUnit': {'state': 'translated', 'value': value}}
                for code, value in values.items()
            },
        }
    catalog = {'sourceLanguage': 'en', 'strings': strings, 'version': '1.0'}
    return json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + '\n'


def patch(source):
    if TARGET.exists():
        previous = TARGET.read_text(encoding='utf-8')
        if previous == source:
            return ''
        lines = ['*** Begin Patch', '*** Update File: ' + str(TARGET), '@@']
        lines.extend('-' + line for line in previous.splitlines())
    else:
        lines = ['*** Begin Patch', '*** Add File: ' + str(TARGET)]
    lines.extend('+' + line for line in source.splitlines())
    return '\n'.join([*lines, '*** End Patch', ''])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true', help='verify the checked-in catalog')
    mode.add_argument('--patch', action='store_true', help='print a patch without writing files')
    args = parser.parse_args()
    try:
        tables = load_tables()
        source = render(tables)
        if args.check:
            if not TARGET.exists() or TARGET.read_text(encoding='utf-8') != source:
                raise ValueError('Regenerate LatchWidgets/Localizable.xcstrings: '
                                 'apply the output of --patch with apply_patch')
            print(f'Widget gallery catalog matches {len(GALLERY_KEYS)} keys × 8 languages; '
                  f'{len(set(GALLERY_KEYS) | set(RUNTIME_KEYS))} required widget keys × 7 tables')
            print('Full dictionary key counts: ' + ', '.join(
                f'{code}={len(table)}' for code, table in tables.items())
                  + '; no duplicates; format placeholders match')
        else:
            print(patch(source) if args.patch else source, end='')
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
