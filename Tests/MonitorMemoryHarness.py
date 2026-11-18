"""Monitor extension memory guard (2.0.1).

iOS caps the DeviceActivity monitor extension at 6 MB. With all 43 translation
tables compiled in (about 2.3 MB of static data), the phone's log showed
LatchMonitor killed 67 times in 18 hours with JETSAM per-process-limit, about
50 ms after spawn and before any callback ran. Limits, schedules and sessions
then never applied in the background.

Source checks (always): the monitor target excludes every Localization+*.swift
catalog, builds with MONITOR_EXTENSION in Debug and Release, the Spanish table
and the compiled-table switch are hidden from it, and tr() in the monitor reads
the host-published copy. The host publishes at launch, on foreground and on a
language change.

Binary check (optional): DEMORA_MONITOR_BINARY=<path to a built LatchMonitor>
asserts its __DATA segment stays small and it holds no catalog symbols.
"""

import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
project = (ROOT / 'Latch.xcodeproj/project.pbxproj').read_text()
localization = (ROOT / 'Shared/Localization.swift').read_text()

# --- The monitor target never compiles the catalogs ----------------------
catalogs = sorted(p.name for p in (ROOT / 'Shared').glob('Localization+*.swift'))
assert len(catalogs) >= 42, catalogs
block = re.search(
    r'/\* Exceptions for "Shared" folder in "LatchMonitor" target \*/ = \{(.*?)\n\t\t\};',
    project, re.S)
assert block, 'Shared exception set for LatchMonitor'
excluded = re.findall(r'"(Localization\+\w+\.swift)"', block.group(1))
assert sorted(excluded) == catalogs, set(catalogs) ^ set(excluded)
assert 'target = BB0000000000000000000002 /* LatchMonitor */;' in block.group(1)
shared_group = project.split('AA0000000000000000000004 /* Shared */ = {', 1)[1].split('};', 1)[0]
assert 'Exceptions for "Shared" folder in "LatchMonitor" target' in shared_group
assert 'Localization.swift' not in excluded, 'tr() itself stays in the monitor'

for bundle in ('may.latch.dev.monitor', 'may.latch.monitor'):
    config = project.split(f'PRODUCT_BUNDLE_IDENTIFIER = {bundle};', 1)[1].split('name = ', 1)[0]
    assert 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "MONITOR_EXTENSION $(inherited)";' in config, bundle
assert project.count('MONITOR_EXTENSION') == 2, 'only the monitor target sets the flag'

# --- Localization.swift hides every table from the monitor ---------------
tr_body = localization.split('func tr(_ key: String) -> String {', 1)[1].split('\n}\n', 1)[0]
assert '#if MONITOR_EXTENSION\n    return PublishedStrings.table(for: AppLanguage.current)?[key] ?? key' in tr_body
assert '#else\n    return compiledTable(for: AppLanguage.current)?[key] ?? key' in tr_body
assert "#if !MONITOR_EXTENSION\n/// The language's compiled-in table" in localization, 'switch hidden from the monitor'
spanish_head, spanish_tail = localization.split('let spanishStrings: [String: String] = [', 1)
assert spanish_head.rstrip().endswith('#if !MONITOR_EXTENSION'), 'Spanish table hidden from the monitor'
assert spanish_tail.rstrip().endswith(']\n#endif'), 'Spanish table closes the #if'
published = localization.split('enum PublishedStrings {', 1)[1].split('\n}\n', 1)[0]
monitor_side = published.split('#if MONITOR_EXTENSION', 1)[1].split('#else', 1)[0]
assert 'compiledTable' not in monitor_side and 'Strings' not in monitor_side.replace('PublishedStrings', '')
assert 'guard language != .english' in monitor_side, 'English never reads the file'
assert 'plist[languageKey] as? String == language.rawValue' in monitor_side, 'another language falls back to English'
host_side = published.split('#else', 1)[1]
assert 'plist[buildKey] as? String == build' in host_side, 'republished after an update'
assert ".atomic" in host_side

# --- The host keeps the published copy current ---------------------------
delegate = (ROOT / 'Latch/AppDelegate.swift').read_text()
app = (ROOT / 'Latch/LatchApp.swift').read_text()
launch = delegate.split('didFinishLaunchingWithOptions', 1)[1].split('return true', 1)[0]
assert 'PublishedStrings.publish()' in launch.split('#if DEBUG', 1)[0], 'published before the demo early return'
active = app.split('if phase == .active {', 1)[1][:600]
assert 'PublishedStrings.publish()' in active
setter = localization.split('static var current: AppLanguage {', 1)[1].split('static func deviceMatch', 1)[0]
assert 'PublishedStrings.publish()' in setter.split('set {', 1)[1]
print(f'Monitor memory sources passed: {len(catalogs)} catalogs excluded, flag in Debug/Release, '
      'tables hidden, host publishes at launch/foreground/language change')

# --- Optional: the built binary ------------------------------------------
binary = os.environ.get('DEMORA_MONITOR_BINARY')
if binary:
    sizes = subprocess.run(['size', '-m', binary], capture_output=True, text=True, check=True).stdout
    data = int(re.search(r'^Segment __DATA: (\d+)', sizes, re.M).group(1))
    assert data < 512 * 1024, f'__DATA is {data} bytes'
    symbols = subprocess.run(['nm', '-j', binary], capture_output=True, text=True, check=True).stdout
    assert not re.search(r'(spanish|arabic|japanese|german)Strings', symbols), 'catalog symbols linked'
    print(f'Monitor binary passed: __DATA {data:,} bytes, no catalog symbols')
