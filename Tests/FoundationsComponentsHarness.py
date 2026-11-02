#!/usr/bin/env python3
"""Checks for the foundations components (docs/foundations-redesign.md §6).

Compiles the pure `CountdownProjection` from Latch/DemoraComponents.swift with
a native test driver, then runs source guards for PendingChangeRow's
countdown, HoldButton's accessible fallback and component translations.
No iOS build, simulator, defaults mutation or saved state is involved; the
guards read source text and don't prove how the views render.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
STRING = r'"((?:[^"\\]|\\.)*)"'


def section(source, start, end):
    assert start in source, ('missing', start)
    return source.split(start, 1)[1].split(end, 1)[0]


components = (ROOT / 'Latch/DemoraComponents.swift').read_text()
home = (ROOT / 'Latch/HomeView.swift').read_text()

# 1. The countdown projection, compiled and run natively.
projection = 'enum CountdownProjection {' + section(components, 'enum CountdownProjection {', '\n}\n') + '\n}\n'
driver = r'''
import Foundation
func check(_ ok: Bool, _ message: String) { if !ok { print("FAIL: " + message); exit(1) } }
''' + projection + r'''
let system = Date(timeIntervalSince1970: 2_000_000_000)
// TimeGuard and the system clock disagree in both directions (sleep, clock edits).
for skew in [-3600.0, -1.0, 0.0, 42.0, 86_400.0] {
    let guarded = system.addingTimeInterval(skew)
    let deadline = guarded.addingTimeInterval(600)
    let range = CountdownProjection.interval(until: deadline, guardedNow: guarded, systemNow: system)
    check(range.lowerBound == system, "starts at the system clock")
    check(range.upperBound.timeIntervalSince(system) == 600, "guarded remaining projected, skew \(skew)")
}
check(CountdownProjection.remaining(until: system, guardedNow: system) == 1, "due floors at 1 s")
check(CountdownProjection.remaining(until: system.addingTimeInterval(-90), guardedNow: system) == 1,
      "overdue floors at 1 s, never negative")
check(CountdownProjection.remaining(until: system.addingTimeInterval(0.4), guardedNow: system) == 1,
      "sub-second wait floors at 1 s")
check(CountdownProjection.remaining(until: system.addingTimeInterval(3661), guardedNow: system) == 3661,
      "long wait kept exactly")
let start = system, end = system.addingTimeInterval(100)
check(CountdownProjection.progress(from: start, until: end, guardedNow: system.addingTimeInterval(-5)) == 0, "before start")
check(CountdownProjection.progress(from: start, until: end, guardedNow: system.addingTimeInterval(25)) == 0.25, "quarter")
check(CountdownProjection.progress(from: start, until: end, guardedNow: system.addingTimeInterval(500)) == 1, "after end")
check(CountdownProjection.progress(from: start, until: start, guardedNow: system) == 1, "zero-length wait complete")
check(CountdownProjection.progress(from: end, until: start, guardedNow: system) == 1, "inverted wait complete")
print("Countdown projection passed: clock skew, 1 s floor, progress clamps")
'''
with tempfile.TemporaryDirectory(prefix='demora-foundations-') as directory:
    source = Path(directory) / 'Countdown.swift'
    binary = Path(directory) / 'Countdown'
    source.write_text(driver)
    subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

# 2. PendingChangeRow uses CountdownText with identical branches.
row = section(home, 'struct PendingChangeRow: View {', '\n}\n')
assert 'CountdownText(to: change.appliesAt, style: nil)' in row
assert 'Text(timerInterval:' not in row and 'TimeGuard.now()' not in row, \
    'projection must live only in CountdownProjection'
assert row.index('if let frozenRemaining') < row.index('} else if change.isDue') \
    < row.index('CountdownText(to: change.appliesAt'), 'tutorial → due → countdown order kept'
assert 'TutorialCountdownText(remaining: frozenRemaining)' in row
assert 'Text(tr("Applying…"))' in row
countdown = section(components, 'struct CountdownText: View {', '\n}\n')
assert 'guardedNow: Date = TimeGuard.now(), systemNow: Date = Date.now' in countdown
assert 'countsDown: true' in countdown
assert len(re.findall(r'^\s*let text = Text\(timerInterval:', components, re.M)) == 1, \
    'one countdown implementation'
# Review fix: the projection is a stored input captured in init (which runs on
# every parent redraw), never read from the clocks only inside body.
countdown_body = countdown.split('var body: some View {', 1)[1]
assert 'let interval: ClosedRange<Date>' in countdown
assert 'self.interval = CountdownProjection.interval(' in countdown.split('var body', 1)[0]
assert 'TimeGuard.now()' not in countdown_body and 'Date.now' not in countdown_body, \
    'body must not re-read the clocks'
assert 'Text(timerInterval: interval, countsDown: true)' in countdown_body
ring = section(components, 'struct CountdownRing: View {', '\n}\n')
assert 'CountdownText(to: deadline, guardedNow: guardedNow, systemNow: systemNow)' in ring, \
    'ring and text share one tick'
assert ring.index('let guardedNow = TimeGuard.now()') < ring.index('let systemNow = Date.now') \
    < ring.index('CountdownText(to: deadline'), 'clocks read inside the TimelineView tick'

# Natively: two inits of the real CountdownText with the same deadline take
# different projections when the guarded clock moves (the old body-only read
# gave SwiftUI identical inputs, so a skipped body kept the stale value).
text_driver = r'''
import SwiftUI
func check(_ ok: Bool, _ message: String) { if !ok { print("FAIL: " + message); exit(1) } }
enum TimeGuard { static var clock = Date(timeIntervalSince1970: 2_000_000_000); static func now() -> Date { clock } }
enum DemoraType { case time }
extension View { func demoraType(_ style: DemoraType) -> some View { self } }
''' + projection + 'struct CountdownText: View {' + countdown + '\n}\n' + r'''
let deadline = TimeGuard.clock.addingTimeInterval(3600)
let before = CountdownText(to: deadline)
check(abs(before.interval.upperBound.timeIntervalSince(before.interval.lowerBound) - 3600) < 0.001,
      "an hour away reads an hour")
TimeGuard.clock = TimeGuard.clock.addingTimeInterval(1800)
let after = CountdownText(to: deadline)
check(abs(after.interval.upperBound.timeIntervalSince(after.interval.lowerBound) - 1800) < 0.001,
      "a redraw after the guarded clock moves re-projects")
check(before.interval != after.interval, "inputs differ, so SwiftUI can't skip the redraw")
let fixed = Date(timeIntervalSince1970: 1_000)
let shared = CountdownText(to: fixed.addingTimeInterval(90), guardedNow: fixed, systemNow: fixed)
check(shared.interval == fixed...fixed.addingTimeInterval(90), "caller-supplied tick is used as given")
print("CountdownText passed: projection captured at init, re-projects per redraw, ring tick shared")
'''
with tempfile.TemporaryDirectory(prefix='demora-countdown-text-') as directory:
    source = Path(directory) / 'CountdownText.swift'
    binary = Path(directory) / 'CountdownText'
    source.write_text(text_driver)
    subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

# 2b. Review fix: DayChips follows the app's week start and language.
chips = section(components, 'struct DayChips: View {', '\n}\n')
assert '@Environment(\\.locale) private var locale' in chips
assert '@AppStorage("weekStartMonday") private var weekStartMonday = false' in chips
assert 'DayChipsCalendar.calendar(locale: locale,\n' in chips
assert 'Calendar.current' not in chips, 'device calendar must not drive order or names'
assert 'calendar.veryShortWeekdaySymbols[day - 1]' in chips
assert '.accessibilityLabel(calendar.weekdaySymbols[day - 1])' in chips
# Same key and default as the existing month calendar.
schedules = (ROOT / 'Latch/SchedulesView.swift').read_text()
assert '@AppStorage("weekStartMonday") private var weekStartMonday = false' in schedules
assert 'c.firstWeekday = weekStartMonday ? 2 : 1' in schedules
day_calendar = 'enum DayChipsCalendar {' + section(components, 'enum DayChipsCalendar {', '\n}\n') + '\n}\n'
day_driver = r'''
import Foundation
func check(_ ok: Bool, _ message: String) { if !ok { print("FAIL: " + message); exit(1) } }
''' + day_calendar + r'''
check(DayChipsCalendar.orderedDays(firstWeekday: 1) == [1, 2, 3, 4, 5, 6, 7], "Sunday first")
check(DayChipsCalendar.orderedDays(firstWeekday: 2) == [2, 3, 4, 5, 6, 7, 1], "Monday first")
// en-US starts on Sunday and es/de on Monday by locale; the app setting wins either way.
for code in ["en_US", "es", "de"] {
    for start in [false, true] {
        let calendar = DayChipsCalendar.calendar(locale: Locale(identifier: code), weekStartMonday: start)
        check(calendar.firstWeekday == (start ? 2 : 1), "\(code): app setting wins over the locale")
        check(calendar.weekdaySymbols.count == 7 && calendar.veryShortWeekdaySymbols.count == 7,
              "\(code): seven names")
    }
}
let spanish = DayChipsCalendar.calendar(locale: Locale(identifier: "es"), weekStartMonday: true)
check(spanish.weekdaySymbols[1] == "lunes", "in-app language names the days (es)")
let german = DayChipsCalendar.calendar(locale: Locale(identifier: "de"), weekStartMonday: false)
check(german.weekdaySymbols[1] == "Montag", "in-app language names the days (de)")
print("DayChips calendar passed: app week start, in-app language names, order")
'''
with tempfile.TemporaryDirectory(prefix='demora-day-chips-') as directory:
    source = Path(directory) / 'DayChips.swift'
    binary = Path(directory) / 'DayChips'
    source.write_text(day_driver)
    subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

# 2c. Review fix: EmptyStateView is its own paper card, so no screen wraps it
# in another surface (a second outline and extra padding).
wrapped = re.compile(r'EmptyStateView\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)\s*\.(demoraSurface|paperCard)\(')
empty_calls = 0
for path in (ROOT / 'Latch').glob('*.swift'):
    text = path.read_text()
    empty_calls += len(re.findall(r'\bEmptyStateView\(', text))
    assert not wrapped.search(text), (path.name, 'EmptyStateView wrapped in another surface')
assert empty_calls >= 3, empty_calls
assert wrapped.search('EmptyStateView(title: tr("a"),\n description: String(format: tr("b"), x))\n .demoraSurface()'), \
    'wrapper pattern self-test'

# 3. HoldButton: 1.2 s hold, accessible fallback, cancel on release.
hold = section(components, 'struct HoldButton: View {', '\n}\n')
assert 'var duration: TimeInterval = 1.2' in hold
assert 'if voiceOver || reduceMotion {' in hold
assert '.alert(confirmationTitle, isPresented: $confirming)' in hold
assert 'Button(tr("Cancel"), role: .cancel)' in hold
assert '.accessibilityAction { confirming = true }' in hold
assert 'onLongPressGesture(minimumDuration: duration' in hold
assert '} else if !completed {' in hold, 'early release cancels the fill'
assert 'impactOccurred()' in hold and 'notificationOccurred(.success)' in hold

# 4. Every component string is translated in all seven tables.
keys = set(re.findall(r'\btr\(\s*' + STRING, components))
assert keys, 'no component strings found'
entry = re.compile(r'^\s*' + STRING + r'\s*:', re.M)
for suffix in ('', '+German', '+French', '+Portuguese', '+Polish', '+Turkish', '+Hindi'):
    table = set(entry.findall((ROOT / f'Shared/Localization{suffix}.swift').read_text()))
    missing = sorted(keys - table)
    assert not missing, (suffix or 'Spanish', 'missing', missing)

print(f'Foundations components passed: PendingChangeRow countdown source guards, '
      f'HoldButton fallback guards, {len(keys)} component strings × 7 tables')

# 5. Tab bar restyle (§7) is visual only: the five current tabs keep their
# order, bindings, lock, badges and accessibility.
app = (ROOT / 'Latch/LatchApp.swift').read_text()
bar = section(app, 'private struct DemoraTabBar: View {', '\n}\n')
assert '''    private let items: [(Int, String, String)] = [
        (4, "Delays", "hourglass"),
        (1, "Limits", "square.stack.3d.up"),
        (0, "Home", "house.fill"),
        (2, "Schedules", "calendar"),
        (3, "Settings", "slider.horizontal.3")
    ]''' in bar, 'five tabs, same order and icons'
for guard in ('@Binding var selection: Int', 'let locked: Bool', 'let pendingCount: Int',
              'let inviteCount: Int', 'guard !locked else { return }',
              'withAnimation(.easeInOut(duration: 0.18)) { selection = item.0 }',
              'let count = item.0 == 0 ? pendingCount\n                                : (item.0 == 3 ? inviteCount : 0)',
              '.accessibilityLabel(tr(item.1))',
              '.accessibilityAddTraits(selection == item.0 ? [.isSelected] : [])',
              '.frame(maxWidth: .infinity, minHeight: 56)'):
    assert guard in bar, ('tab bar behaviour changed', guard)
assert 'DemoraTabBar(selection: $model.selectedTab,\n                         locked: model.inTutorial,' in app
assert 'design: .monospaced' not in bar, 'monospaced labels retired'
assert '? accent : Ink.inkSoft' in bar and 'Ink.hairline' in bar, 'selected = accent, others = inkSoft'
print('Tab bar passed: five tabs, order, lock, badges and accessibility unchanged; restyled colours')
