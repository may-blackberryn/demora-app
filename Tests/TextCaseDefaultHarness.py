#!/usr/bin/env python3
"""Text case default (foundations decision F3).

People who never chose a text case get regular case; a stored choice is kept.
Compiles the real `TextCasing` enum natively against SwiftUI with a `tr` stub,
then checks every `@AppStorage("textCasing")` declaration, the root
`.textCase` application and that nothing writes the key on its own. Reads
source only; no defaults are read or written.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]

theme = (ROOT / 'Latch/Theme.swift').read_text()
casing = 'enum TextCasing:' + theme.split('enum TextCasing:', 1)[1].split('\n}\n', 1)[0] + '\n}\n'
driver = r'''
import SwiftUI
func tr(_ text: String) -> String { text }
func check(_ ok: Bool, _ message: String) { if !ok { print("FAIL: " + message); exit(1) } }
''' + casing + r'''
check(TextCasing.fallback == .regular, "never-chosen default is regular")
check(TextCasing.resolved("lower") == .lower, "a stored lowercase choice is kept")
check(TextCasing.resolved("regular") == .regular, "a stored regular choice is kept")
check(TextCasing.resolved("") == .regular, "empty value falls back to regular")
check(TextCasing.resolved("LOWER") == .regular, "unreadable value falls back to regular")
check(TextCasing.lower.textCase == .lowercase, "lowercase still applies app-wide")
check(TextCasing.regular.textCase == nil, "regular leaves text as written")
print("TextCasing passed: regular default, stored choices kept, unreadable values fall back")
'''
with tempfile.TemporaryDirectory(prefix='demora-text-case-') as directory:
    source = Path(directory) / 'TextCase.swift'
    binary = Path(directory) / 'TextCase'
    source.write_text(driver)
    subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

sources = {path: path.read_text() for folder in ('Latch', 'Shared', 'LatchMonitor', 'LatchReport',
                                                  'LatchWidgets', 'LatchShieldUI')
           for path in (ROOT / folder).rglob('*.swift')}
declarations = [(path.name, line) for path, text in sources.items()
                for line in re.findall(r'@AppStorage\("textCasing"[^\n]*', text)]
assert len(declarations) >= 4, declarations
for name, line in declarations:
    # Same (standard) store everywhere, and the shared default.
    assert line == '@AppStorage("textCasing") private var textCasingRaw = TextCasing.fallback.rawValue', \
        (name, line)
everything = '\n'.join(sources.values())
assert 'TextCasing.lower.rawValue' not in everything, 'old lowercase default left behind'
assert not re.search(r'TextCasing\(rawValue: textCasingRaw\) \?\? \.lower', everything)
root = (ROOT / 'Latch/LatchApp.swift').read_text()
assert root.count('.textCase(TextCasing.resolved(textCasingRaw).textCase)') == 1, 'root application'
assert 'TextCasing.resolved(textCasingRaw) == .lower' in theme, 'navigation titles follow the setting'
# Only explicit choices write the value: You → Appearance (the Settings row moved there).
writers = [(path.name, m) for path, text in sources.items()
           for m in re.findall(r'(?<!var )textCasingRaw = [^\n]*', text)]
assert [name for name, _ in writers] == ['YouPages.swift'], writers
assert not re.search(r'(set|removeObject)\([^\n]*"textCasing"', everything), 'no silent writes'
assert len(re.findall(r'"textCasing"', everything)) == len(declarations), 'no other key access'
print(f'Text case default passed: {len(declarations)} @AppStorage declarations, root application, '
      'explicit-choice-only writes')
