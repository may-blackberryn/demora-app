#!/usr/bin/env python3
"""Check Demora's 44 app-language dictionaries (docs/app-languages-2.0.md).

  python3 Tests/AppLanguagesHarness.py              all languages; pending is allowed
  python3 Tests/AppLanguagesHarness.py --strict     stage 3 gate: nothing pending, no gaps
  python3 Tests/AppLanguagesHarness.py --language ja [--language ko …]
                                                    a translator's own files only
  python3 Tests/AppLanguagesHarness.py --template ja
                                                    print a full skeleton to translate

Rules (see the Translation kit in the spec): every key of the Spanish
reference plus the Info.plist permission strings, no others, no duplicates,
placeholders identical in order (or all numbered, %2$@), no empty values or
Swift interpolation; a file marked complete may keep at most 10% English.
Each checked non-empty file must also type-check on its own with swiftc.

Reads source files only; never writes files, reads preferences or uses network.
"""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_languages as L  # noqa: E402


def literal(text):
    return json.dumps(text, ensure_ascii=False)


def template(code):
    if code not in L.BY_CODE or code in L.ORIGINAL:
        raise ValueError(f'{code}: not one of the 36 new languages')
    _, table, name = L.BY_CODE[code]
    keys = L.reference()
    plist = L.infoplist_keys()
    lines = ['//', f'//  {L.path(code).name}',
             f'//  {name} ({code}) in-app localization table. Missing keys fall back to English.',
             '//  Translation: pending', '//', '', 'import Foundation', '',
             f'let {table}: [String: String] = [']
    # Keep the Spanish file's order and section comments as context.
    body = L.table_body('es')
    for raw in body.splitlines()[1:]:
        stripped = raw.strip()
        if stripped.startswith('//'):
            lines.append('    ' + stripped)
            continue
        for key, _ in L.ENTRY.findall(raw):
            key = L.decode(key)
            lines.append(f'    {literal(key)}: {literal(key)},')
    extra = [key for key in keys if key not in dict(L.entries('es'))]
    if extra:
        lines.append('    // Info.plist permission text (App Review reads these; generated into Latch/InfoPlist.xcstrings).')
        for key in extra:
            lines.append(f'    {literal(key)}: {literal(key)},')
    lines.append(']')
    found = [k for k in keys if f'    {literal(k)}: ' not in '\n'.join(lines)]
    assert not found, ('template lost keys', found[:3])
    assert set(plist.values()) <= set(keys)
    return '\n'.join(lines) + '\n'


def typecheck(codes):
    files = [L.path(c) for c in codes if L.entries(c)]
    if not files:
        return
    with tempfile.TemporaryDirectory(prefix='demora-languages-') as folder:
        # Each table must compile on its own (they are separate files in the app).
        result = subprocess.run(['xcrun', 'swiftc', '-typecheck', '-warnings-as-errors',
                                 '-module-cache-path', str(Path(folder) / 'cache'),
                                 *map(str, files)], capture_output=True, text=True)
    if result.returncode:
        raise ValueError('swiftc rejected the dictionaries:\n' + (result.stderr or result.stdout)[-2000:])


def check(codes, strict):
    keys = L.reference()
    failed = False
    summary = {'original': 0, 'complete': 0, 'pending': 0}
    for code in codes:
        state, table, problems, notes = L.validate(code, keys)
        summary[state] += 1
        if strict and state == 'pending':
            problems.append('still pending (strict mode)')
        if strict and state == 'original':
            missing = [key for key in keys if key not in table]
            if missing:
                problems.append(f'{len(missing)} reference keys missing: {missing[:5]}')
        name = L.path(code).name
        if problems:
            failed = True
            print(f'FAIL {code:8} {name}')
            for problem in problems[:20]:
                print('     - ' + problem)
            if len(problems) > 20:
                print(f'     … {len(problems) - 20} more')
        else:
            print(f'ok   {code:8} {state:8} {len(table):5} keys'
                  + (' · ' + '; '.join(notes) if notes else ''))
    if not failed:
        typecheck([c for c in codes if c not in L.ORIGINAL])
    print(f'{len(codes)} tables checked against {len(keys)} reference keys: '
          + ', '.join(f'{n} {s}' for s, n in summary.items())
          + (' · strict' if strict else ''))
    return 1 if failed else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--strict', action='store_true')
    parser.add_argument('--language', action='append', metavar='CODE')
    parser.add_argument('--template', metavar='CODE')
    args = parser.parse_args()
    try:
        if args.template:
            print(template(args.template), end='')
            return 0
        codes = args.language or [code for code, *_ in L.TABLES]
        unknown = [c for c in codes if c not in L.BY_CODE]
        if unknown:
            raise ValueError(f'unknown language codes {unknown}; known: {L.CODES[1:]}')
        for code, *_ in L.TABLES:
            if not L.path(code).exists():
                raise ValueError(f'{L.path(code).name} is missing')
        return check(codes, args.strict)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
