"""Shared language list, dictionary parser and validation for Demora's app languages.

Imported by Tests/AppLanguagesHarness.py and the catalog generators
(GenerateWidgetLocalization.py, GenerateUsageLocalization.py,
GenerateInfoPlistLocalization.py). Reads source files only; never writes files,
reads preferences or live data, or uses the network.

One file per language: Shared/Localization+<Name>.swift (Spanish lives in
Shared/Localization.swift). The Spanish table is the key reference; the
Info.plist permission strings are ordinary keys, keyed by their English text.
"""

from collections import Counter
import json
import plistlib
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

# (code, file suffix, table name, English name). English has no table.
# Order: the original eight, then the 36 added for 2.0 (docs/app-languages-2.0.md).
TABLES = [
    ('es', '', 'spanishStrings', 'Spanish'),
    ('de', '+German', 'germanStrings', 'German'),
    ('fr', '+French', 'frenchStrings', 'French'),
    ('pt', '+Portuguese', 'portugueseStrings', 'Portuguese'),
    ('pl', '+Polish', 'polishStrings', 'Polish'),
    ('tr', '+Turkish', 'turkishStrings', 'Turkish'),
    ('hi', '+Hindi', 'hindiStrings', 'Hindi'),
    ('ca', '+Catalan', 'catalanStrings', 'Catalan'),
    ('cs', '+Czech', 'czechStrings', 'Czech'),
    ('da', '+Danish', 'danishStrings', 'Danish'),
    ('el', '+Greek', 'greekStrings', 'Greek'),
    ('fi', '+Finnish', 'finnishStrings', 'Finnish'),
    ('hr', '+Croatian', 'croatianStrings', 'Croatian'),
    ('hu', '+Hungarian', 'hungarianStrings', 'Hungarian'),
    ('it', '+Italian', 'italianStrings', 'Italian'),
    ('nl', '+Dutch', 'dutchStrings', 'Dutch'),
    ('nb', '+Norwegian', 'norwegianStrings', 'Norwegian Bokmål'),
    ('ro', '+Romanian', 'romanianStrings', 'Romanian'),
    ('ru', '+Russian', 'russianStrings', 'Russian'),
    ('sk', '+Slovak', 'slovakStrings', 'Slovak'),
    ('sl', '+Slovenian', 'slovenianStrings', 'Slovenian'),
    ('sv', '+Swedish', 'swedishStrings', 'Swedish'),
    ('uk', '+Ukrainian', 'ukrainianStrings', 'Ukrainian'),
    ('id', '+Indonesian', 'indonesianStrings', 'Indonesian'),
    ('ja', '+Japanese', 'japaneseStrings', 'Japanese'),
    ('ko', '+Korean', 'koreanStrings', 'Korean'),
    ('ms', '+Malay', 'malayStrings', 'Malay'),
    ('th', '+Thai', 'thaiStrings', 'Thai'),
    ('vi', '+Vietnamese', 'vietnameseStrings', 'Vietnamese'),
    ('zh-Hans', '+ChineseSimplified', 'chineseSimplifiedStrings', 'Chinese (Simplified)'),
    ('zh-Hant', '+ChineseTraditional', 'chineseTraditionalStrings', 'Chinese (Traditional)'),
    ('bn', '+Bengali', 'bengaliStrings', 'Bengali'),
    ('gu', '+Gujarati', 'gujaratiStrings', 'Gujarati'),
    ('kn', '+Kannada', 'kannadaStrings', 'Kannada'),
    ('ml', '+Malayalam', 'malayalamStrings', 'Malayalam'),
    ('mr', '+Marathi', 'marathiStrings', 'Marathi'),
    ('or', '+Odia', 'odiaStrings', 'Odia'),
    ('pa', '+Punjabi', 'punjabiStrings', 'Punjabi'),
    ('ta', '+Tamil', 'tamilStrings', 'Tamil'),
    ('te', '+Telugu', 'teluguStrings', 'Telugu'),
    ('ar', '+Arabic', 'arabicStrings', 'Arabic'),
    ('he', '+Hebrew', 'hebrewStrings', 'Hebrew'),
    ('ur', '+Urdu', 'urduStrings', 'Urdu'),
]
ORIGINAL = ('es', 'de', 'fr', 'pt', 'pl', 'tr', 'hi')
CODES = ['en'] + [code for code, *_ in TABLES]
BY_CODE = {code: (suffix, table, name) for code, suffix, table, name in TABLES}

STRING = r'"((?:[^"\\]|\\.)*)"'
# Inline-aware entry boundary (several pairs on one line are all found).
ENTRY = re.compile(r'(?:^|,)\s*' + STRING + r'\s*:\s*' + STRING + r'\s*(?=,|$)', re.M)
PLACEHOLDER = re.compile(
    r'%(?:(\d+)\$)?([-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?'
    r'(?:hh|ll|[hlLzjt])?[@diuoxXfFeEgGcs%])')
STATUS = re.compile(r'^//\s*Translation:\s*(pending|complete)\s*$', re.M)
LEFTOVER_LIMIT = 0.10
# Stage 3 switch. While False, the generated catalogs (widget gallery, usage
# report, Info.plist) publish only the original eight, so a translator finishing
# a language in stage 2 doesn't make every generated --check stale. Stage 3 sets
# it True and regenerates; AppLanguagesHarness.py --strict requires True.
PUBLISH_NEW_LANGUAGES = True


def path(code):
    return ROOT / f'Shared/Localization{BY_CODE[code][0]}.swift'


def decode(literal):
    return json.loads('"' + literal + '"')


def table_body(code, source=None):
    """The dictionary literal text after `let <table>: [String: String] =`."""
    _, table, _ = BY_CODE[code]
    source = path(code).read_text(encoding='utf-8') if source is None else source
    head = f'let {table}: [String: String] = '
    if head not in source:
        raise ValueError(f'{path(code).name}: missing `{head.strip()}`')
    body = source.split(head, 1)[1]
    # The table is the last declaration in every file except Spanish, where
    # nothing follows it either; it ends at the first line that is just `]`.
    if body.startswith('[:]'):
        return '[:]'
    end = re.search(r'^\]\s*$', body, re.M)
    if not body.startswith('[') or not end:
        raise ValueError(f'{path(code).name}: {table} is not a `[ ... ]` literal')
    return body[:end.end()]


def entries(code, source=None):
    """Ordered (key, value) pairs, after checking nothing else is in the literal."""
    body = table_body(code, source)
    if body == '[:]':
        return []
    pairs = [(decode(k), decode(v)) for k, v in ENTRY.findall(body)]
    rest = ENTRY.sub('', body)
    rest = re.sub(r'//[^\n]*', '', rest)
    rest = re.sub(r'[\s,\[\]]', '', rest)
    if rest:
        raise ValueError(f'{path(code).name}: text the checker cannot read as '
                         f'"key": "value" pairs: {rest[:80]!r}')
    return pairs


def status(code, source=None):
    """'pending', 'complete', or 'original' (the eight reviewed/beta files)."""
    if code in ORIGINAL:
        return 'original'
    source = path(code).read_text(encoding='utf-8') if source is None else source
    found = STATUS.findall(source)
    if len(found) != 1:
        raise ValueError(f'{path(code).name}: needs exactly one '
                         '`// Translation: pending` or `// Translation: complete` line')
    return found[0]


# Non-Latin-script languages: their values should be mostly in their script.
NON_LATIN = {'el', 'ru', 'uk', 'ja', 'ko', 'th', 'zh-Hans', 'zh-Hant', 'bn', 'gu', 'kn', 'ml',
             'mr', 'or', 'pa', 'ta', 'te', 'ar', 'he', 'ur', 'hi'}
# Names that stay in Latin letters in every language (brands, products, units).
LATIN_NAMES = re.compile(
    r'Demora|demora|iPadOS|iOS|iPhone|iPad|Apple ID|Apple|Screen Time|App Store|Safari|iCloud|'
    r'CloudKit|Face ID|Touch ID|Natural Earth|Instagram|TikTok|YouTube|Trello|EFF|PIN|OK|URL|'
    r'GPS|SNS|AM|PM|ID|[Ee]-?mail|[\w.-]+@[\w.-]+|[\w-]+\.(?:com|app|org|net)\b')
REPEATED = re.compile(r'([^\W\d_]{1,4})\1{3,}')


def garble_problems(code, key, value):
    """Machine-translation noise the reviewer found in Hindi (stage 3 review)."""
    problems = []
    if REPEATED.search(value) and not REPEATED.search(key):
        problems.append(f'{key[:50]!r}: repeated-syllable noise')
    if value.startswith('Demora — ') and not key.startswith('Demora'):
        problems.append(f'{key[:50]!r}: starts "Demora — " although the English does not')
    if code in NON_LATIN:
        # iOS's own setting names may stay quoted in English; brands always do.
        text = re.sub(r'“[^”]*”|"[^"]*"', '', LATIN_NAMES.sub('', PLACEHOLDER.sub('', value)))
        letters = [c for c in text if c.isalpha()]
        latin = [c for c in letters if c.isascii()]
        if len(letters) >= 8 and len(latin) / len(letters) > 0.5:
            problems.append(f'{key[:50]!r}: mostly Latin letters in a non-Latin-script language')
    return problems


def placeholder_tokens(value):
    """[(position or None, spec)] for every format token, %% included."""
    return [(int(pos) if pos else None, spec) for pos, spec in PLACEHOLDER.findall(value)]


def placeholder_problem(key, value):
    """None, or why the value's format tokens don't match the English key."""
    want = [spec for _, spec in placeholder_tokens(key)]
    got = placeholder_tokens(value)
    stray = value.count('%') - sum(1 + (spec == '%') for _, spec in got)
    if stray:
        return 'a lone % that is not a placeholder (write %% for a percent sign)'
    if [s for _, s in got if s == '%'].__len__() != want.count('%'):
        return '%% count differs'
    want_args = [s for s in want if s != '%']
    got_args = [(p, s) for p, s in got if s != '%']
    positions = {p is not None for p, _ in got_args}
    if positions == {True}:
        mapping = {}
        for p, s in got_args:
            if mapping.get(p, s) != s:
                return f'%{p}$ is used with two types'
            mapping[p] = s
        if mapping != {i + 1: s for i, s in enumerate(want_args)}:
            return f'numbered placeholders {sorted(mapping.items())} do not match {want_args}'
        return None
    if positions == {True, False}:
        return 'mixes numbered (%1$@) and plain (%@) placeholders'
    if [s for _, s in got_args] != want_args:
        return f'placeholders {[s for _, s in got_args]} differ from {want_args} (order matters)'
    return None


def infoplist_keys():
    """{catalog key: English text} for the Info.plist strings App Review reads."""
    project = (ROOT / 'Latch.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
    found = {}
    for name in ('NSLocationWhenInUseUsageDescription', 'NSCameraUsageDescription'):
        values = set(re.findall(r'INFOPLIST_KEY_' + name + r' = "((?:[^"\\]|\\.)*)";', project))
        if len(values) != 1:
            raise ValueError(f'{name}: expected one English value in the build settings, got {values}')
        found[name] = decode(values.pop())
    info = plistlib.loads((ROOT / 'Latch/Info.plist').read_bytes())
    found['CheckIn'] = info['NSLocationTemporaryUsageDescriptionDictionary']['CheckIn']
    return found


def reference():
    """Ordered English keys every language must translate: Spanish, then Info.plist."""
    keys = [key for key, _ in entries('es')]
    for text in infoplist_keys().values():
        if text not in keys:
            keys.append(text)
    return keys


def validate(code, keys=None):
    """Return (status, table, problems, notes). Problems fail; notes inform."""
    keys = reference() if keys is None else keys
    source = path(code).read_text(encoding='utf-8')
    state = status(code, source)
    pairs = entries(code, source)
    problems, notes = [], []
    counts = Counter(key for key, _ in pairs)
    duplicates = sorted(key for key, n in counts.items() if n > 1)
    if duplicates:
        problems.append(f'duplicate keys (crash the app): {duplicates}')
    known = set(keys)
    unknown = sorted(key for key in counts if key not in known)
    if unknown:
        problems.append(f'keys not in the reference (edited or misspelt?): {unknown[:10]}'
                        + (f' … and {len(unknown) - 10} more' if len(unknown) > 10 else ''))
    for key, value in pairs:
        if not value.strip():
            problems.append(f'empty value for {key!r}')
        if '\\(' in value:
            problems.append(f'Swift interpolation \\( in {key!r}')
        why = placeholder_problem(key, value)
        if why:
            problems.append(f'{key!r}: {why}')
        problems.extend(garble_problems(code, key, value))
    table = dict(pairs)
    missing = [key for key in keys if key not in table]
    # Stage 3 found 24 files with the camera and check-in prompts swapped.
    # In English and every language checked, camera < check-in < location in
    # length, by a wide margin; an inverted order means swapped values.
    plist = infoplist_keys()
    prompts = [table.get(plist[name]) for name in
               ('NSCameraUsageDescription', 'CheckIn', 'NSLocationWhenInUseUsageDescription')]
    if all(prompts) and not len(prompts[0]) < len(prompts[1]) < len(prompts[2]):
        problems.append('Info.plist prompts look swapped: the camera value should be the '
                        'shortest and the While Using location value the longest')
    if state == 'complete':
        if missing:
            problems.append(f'marked complete but {len(missing)} keys are missing: {missing[:5]}')
        worded = [key for key in table if re.search(r'[A-Za-z]{3}', key)]
        same = [key for key in worded if table[key] == key]
        if worded and len(same) / len(worded) > LEFTOVER_LIMIT:
            problems.append(f'{len(same)} of {len(worded)} values are still English '
                            f'(limit {LEFTOVER_LIMIT:.0%}): {same[:5]}')
        elif same:
            notes.append(f'{len(same)} values equal the English (brand names, units…)')
    elif missing:
        label = 'gap' if state == 'original' else 'pending'
        notes.append(f'{label}: {len(keys) - len(missing)} of {len(keys)} keys; '
                     f'missing keys fall back to English' +
                     (f': {missing[:4]}' if state == 'original' else ''))
    return state, table, problems, notes


def complete_tables(keys=None):
    """{code: table} for the languages the generated catalogs publish: the
    original eight, plus (once PUBLISH_NEW_LANGUAGES) each 2.0 language marked complete."""
    keys = reference() if keys is None else keys
    tables = {}
    new = tuple(c for c, *_ in TABLES if c not in ORIGINAL) if PUBLISH_NEW_LANGUAGES else ()
    for code in ORIGINAL + new:
        # Pending files are never published, so a translator's half-written
        # file can't block generation; AppLanguagesHarness checks them.
        # A file without a readable status line is mid-write: also unpublished.
        try:
            if status(code) == 'pending':
                continue
        except ValueError:
            if code in ORIGINAL:
                raise
            continue
        state, table, problems, _ = validate(code, keys)
        if problems:
            raise ValueError(f'{path(code).name}: ' + '; '.join(problems[:3]))
        if state != 'pending':
            tables[code] = table
    return tables


def publication_note(published):
    """How many 2.0 languages the generated catalogs leave out, and why."""
    left = len(CODES) - 1 - published
    if not left:
        return 'all languages published'
    why = 'complete ones publish once PUBLISH_NEW_LANGUAGES' if not PUBLISH_NEW_LANGUAGES else 'still pending'
    return f'{left} languages English-only ({why})'
