#!/usr/bin/env python3
"""Generate Latch/InfoPlist.xcstrings from Shared/Localization*.swift.

The Info.plist purpose strings App Review reads are ordinary dictionary keys,
keyed by their English text (from the build settings and Latch/Info.plist), so
each language stays one file (docs/app-languages-2.0.md, Translation kit).
A language appears once its table is original or marked complete and has the
key; otherwise iOS shows the English. Never the display name: Debug and Release
differ, and one catalog value would rename one of them.

Default: print deterministic JSON. --check: compare it with the checked-in file.
--patch: print an apply_patch patch. Never writes files or uses the network.
"""

import argparse
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_languages as L  # noqa: E402

TARGET = L.ROOT / 'Latch/InfoPlist.xcstrings'
COMMENTS = {
    'CheckIn': "NSLocationTemporaryUsageDescriptionDictionary → CheckIn: iOS's one-time "
               'precise-location prompt during a When & where check.',
    'NSCameraUsageDescription': 'Camera permission prompt (a trusted contact\'s picture). '
                                'Must match INFOPLIST_KEY_NSCameraUsageDescription in English.',
    'NSLocationWhenInUseUsageDescription': 'Location permission prompt (While Using only). '
                                           'Must match INFOPLIST_KEY_NSLocationWhenInUseUsageDescription in English.',
}


def render(tables=None):
    tables = L.complete_tables() if tables is None else tables
    english = L.infoplist_keys()
    assert set(english) == set(COMMENTS), sorted(english)
    strings = {}
    for name, text in sorted(english.items()):
        values = {'en': text, **{code: table[text] for code, table in tables.items() if text in table}}
        strings[name] = {
            'comment': COMMENTS[name],
            'extractionState': 'manual',
            'localizations': {code: {'stringUnit': {'state': 'translated', 'value': value}}
                              for code, value in values.items()},
        }
    catalog = {'sourceLanguage': 'en', 'strings': strings, 'version': '1.0'}
    return json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + '\n'


def patch(source):
    previous = TARGET.read_text(encoding='utf-8')
    if previous == source:
        return ''
    lines = ['*** Begin Patch', '*** Update File: ' + str(TARGET), '@@']
    lines += ['-' + line for line in previous.splitlines()]
    lines += ['+' + line for line in source.splitlines()]
    return '\n'.join([*lines, '*** End Patch', ''])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--patch', action='store_true')
    args = parser.parse_args()
    try:
        tables = L.complete_tables()
        source = render(tables)
        if args.check:
            if TARGET.read_text(encoding='utf-8') != source:
                raise ValueError('Regenerate Latch/InfoPlist.xcstrings: apply the output of --patch')
            counts = {name: 1 + sum(text in t for t in tables.values())
                      for name, text in L.infoplist_keys().items()}
            print('Info.plist catalog matches: ' + ', '.join(f'{k} × {n}' for k, n in sorted(counts.items()))
                  + f' languages; {L.publication_note(len(tables))}')
        else:
            print(patch(source) if args.patch else source, end='')
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
