#!/usr/bin/env python3
"""Compiles the real Latch/TodayPresentation.swift with a native driver.

Checks the Now card priority (docs/today-redesign.md §5.3), the day thread,
the Changes ledger grouping (§5.9) and the change receipt text (§5.10),
including midnight, daylight saving and time-zone changes. Foundation only:
no iOS build, simulator, saved state or Screen Time data is involved.
"""
from pathlib import Path
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
presentation = ROOT / 'Latch/TodayPresentation.swift'
source = presentation.read_text()
for forbidden in ('import SwiftUI', 'UserDefaults', 'SharedStore', 'TimeGuard', 'tr(',
                  'ChangeEngine', 'FileManager', 'Calendar.current', 'Date()', 'Date.now'):
    assert forbidden not in source, ('pure presentation must not use', forbidden)

driver = r'''
import Foundation
var checks = 0
func check(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { print("FAIL: " + message); exit(1) }
    checks += 1
}
func calendar(_ zone: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zone)!
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
}
let ny = calendar("America/New_York")
func at(_ c: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}
func ny(_ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date { at(ny, 2026, m, d, h, min) }
func block(_ id: String, _ name: String, _ s: Date, _ e: Date) -> TodayItem {
    TodayItem(id: id, name: name, kind: .block, start: s, end: e)
}
func free(_ id: String, _ name: String, _ s: Date, _ e: Date) -> TodayItem {
    TodayItem(id: id, name: name, kind: .free, start: s, end: e)
}
extension TodayItem {
    func withLayer(_ layer: Int) -> TodayItem { var copy = self; copy.layer = layer; return copy }
}

// MARK: Now card — each priority row
let now = ny(11, 2, 17, 0)
let evening = block("s1", "Evening block", ny(11, 2, 18), ny(11, 2, 21))
let study = block("p1", "Study", ny(11, 2, 16), ny(11, 2, 19, 30))
let lunch = free("e1", "Lunch", ny(11, 2, 16, 30), ny(11, 2, 18))

var s = NowSummary.make(items: [study, evening], spentLimitNames: ["Games"],
    wakes: [.init(name: "Morning", waitMinutes: 20, release: nil),
            .init(name: "Social", waitMinutes: 45, release: nil),
            .init(name: "Work", waitMinutes: 5, release: nil)], now: now)
check(s.hero == .wakeNeeded && s.action == .wakeUp, "1: wake tap beats blocks")
check(s.facts == [.wakeWait(name: "Morning", minutes: 20), .wakeWait(name: "Social", minutes: 45)],
      "1: wait per group, two facts at most")
s = NowSummary.make(items: [], spentLimitNames: [],
    wakes: [.init(name: "Legacy", waitMinutes: nil, release: nil)], now: now)
check(s.hero == .wakeNeeded && s.facts.isEmpty, "1: unknown wait shows no invented fact")
s = NowSummary.make(items: [], spentLimitNames: [],
    wakes: [.init(name: "Zero", waitMinutes: 0, release: nil)], now: now)
check(s.hero == .wakeNeeded && s.facts.isEmpty, "1: a zero wait states no wait")
let unblock = TodayItem(id: "u", name: "Lift", kind: .unblock, start: ny(11, 2, 16), end: ny(11, 2, 18))
s = NowSummary.make(items: [unblock], spentLimitNames: [], wakes: [], now: now)
check(s.hero == .nothing, "an unblock session is neither a block nor a free period")
s = NowSummary.make(items: [study], spentLimitNames: [],
    wakes: [.init(name: "A", release: now.addingTimeInterval(600)),
            .init(name: "B", release: now.addingTimeInterval(1800)),
            .init(name: "Old", release: now.addingTimeInterval(-60))], now: now)
check(s.hero == .wakeRunning(opensAt: now.addingTimeInterval(1800)) && s.action == nil,
      "2: apps open when the last running wait ends")
check(s.facts == [.countdown(to: now.addingTimeInterval(1800))], "2: countdown fact")
s = NowSummary.make(items: [], spentLimitNames: [],
    wakes: [.init(name: "Old", release: now.addingTimeInterval(-1))], now: now)
check(s.hero == .nothing, "2: a released wait isn't a running wait")

s = NowSummary.make(items: [study, evening, lunch], spentLimitNames: ["Games"], wakes: [], now: now)
check(s.hero == .oneBlock(name: "Study", until: ny(11, 2, 19, 30)), "3: one active block")
check(s.facts == [.countdown(to: ny(11, 2, 19, 30))], "3: time left")

let late = block("s2", "Late", ny(11, 2, 16), ny(11, 2, 22))
let early = block("s3", "Early", ny(11, 2, 16), ny(11, 2, 19, 30))
s = NowSummary.make(items: [late, study, early], spentLimitNames: [], wakes: [], now: now)
check(s.hero == .severalBlocks(count: 3, firstEnd: ny(11, 2, 19, 30)), "4: several blocks, first end")
check(s.facts == [.names(["Early", "Study", "Late"], more: 0)], "4: tie on end broken by name")
let many = (1...5).map { block("m\($0)", "Rule \($0)", ny(11, 2, 16), ny(11, 2, 20, $0)) }
s = NowSummary.make(items: many, spentLimitNames: [], wakes: [], now: now)
check(s.facts == [.names(["Rule 1", "Rule 2", "Rule 3"], more: 2)], "4: three names and 2 more")
s = NowSummary.make(items: [study, study], spentLimitNames: [], wakes: [], now: now)
check(s.hero == .oneBlock(name: "Study", until: ny(11, 2, 19, 30)), "the same interval counts once")

s = NowSummary.make(items: [evening], spentLimitNames: ["Games", "Chat", "Games"], wakes: [], now: now)
check(s.hero == .spent(names: ["Chat", "Games"], forNow: false) && s.facts == [.resetsAtMidnight], "5: spent only")
// Review fix: a split portion reopens at its cutoff, so it never claims midnight.
s = NowSummary.make(items: [], spentLimitNames: [], portionLimitNames: ["Games"], wakes: [], now: now)
check(s.hero == .spent(names: ["Games"], forNow: true) && s.facts.isEmpty, "5: portion used up for now")
s = NowSummary.make(items: [], spentLimitNames: ["Games"], portionLimitNames: ["Games"], wakes: [], now: now)
check(s.hero == .spent(names: ["Games"], forNow: false), "5: spent for the day wins over its portion")
s = NowSummary.make(items: [], spentLimitNames: ["Chat"], portionLimitNames: ["Games"], wakes: [], now: now)
check(s.hero == .spent(names: ["Chat", "Games"], forNow: true) && s.facts.isEmpty, "5: mixed says for now")
// Review fix: a free rule on a higher layer clears blocks below it.
let recurringBlock = TodayItem(id: "r", name: "Evening block", kind: .block, layer: 1,
                               start: ny(11, 2, 16), end: ny(11, 2, 21))
let freeSession = TodayItem(id: "fs", name: "Break", kind: .free, layer: 3,
                            start: ny(11, 2, 16, 45), end: ny(11, 2, 17, 30))
s = NowSummary.make(items: [recurringBlock, freeSession], spentLimitNames: ["Games"], wakes: [], now: now)
check(s.hero == .free(until: ny(11, 2, 17, 30)), "free session clears a recurring block")
let plannedFree = TodayItem(id: "pf", name: "Trip", kind: .free, layer: 2,
                            start: ny(11, 2, 16), end: ny(11, 2, 18))
let sessionBlock = TodayItem(id: "sb", name: "Focus", kind: .block, layer: 3,
                             start: ny(11, 2, 16, 30), end: ny(11, 2, 17, 30))
s = NowSummary.make(items: [recurringBlock, plannedFree, sessionBlock], spentLimitNames: [], wakes: [], now: now)
check(s.hero == .oneBlock(name: "Focus", until: ny(11, 2, 17, 30)), "a later-layer block survives a planned free window")
s = NowSummary.make(items: [recurringBlock, lunch], spentLimitNames: [], wakes: [], now: now)
check(s.hero == .oneBlock(name: "Evening block", until: ny(11, 2, 21)), "same layer: the block is kept")
s = NowSummary.make(items: [recurringBlock, free("old", "Done", ny(11, 2, 9), ny(11, 2, 10)).withLayer(3)],
                    spentLimitNames: [], wakes: [], now: now)
check(s.hero == .oneBlock(name: "Evening block", until: ny(11, 2, 21)), "a finished free session clears nothing")
s = NowSummary.make(items: [lunch, free("x", "Long", ny(11, 2, 16), ny(11, 2, 19))],
    spentLimitNames: ["Games"], wakes: [], now: now)
check(s.hero == .free(until: ny(11, 2, 19)), "6: free period (latest end) wins over spent limits")
s = NowSummary.make(items: [evening, block("z", "Another", ny(11, 2, 18), ny(11, 2, 19)), lunch],
    spentLimitNames: [], wakes: [], now: ny(11, 2, 18, 30))
check(s.hero == .severalBlocks(count: 2, firstEnd: ny(11, 2, 19)), "blocks beat a free period")

s = NowSummary.make(items: [evening, block("y", "Alpha", ny(11, 2, 18), ny(11, 2, 20)),
                            block("old", "Done", ny(11, 2, 8), ny(11, 2, 9)), lunch],
                    spentLimitNames: [], wakes: [], now: ny(11, 2, 12))
check(s.hero == .nothing && s.facts == [.next(name: "Alpha", at: ny(11, 2, 18))],
      "7: next block, tie on start by name, past and free ignored")
s = NowSummary.make(items: [], spentLimitNames: [], wakes: [], now: now)
check(s.hero == .nothing && s.facts.isEmpty, "7: nothing at all")
check(s.facts.count <= NowSummary.maxFacts, "fact cap")

// Midnight: a block that runs past midnight ends tomorrow, and says so.
let night = block("n", "Sleep", ny(11, 2, 22), ny(11, 3, 7))
s = NowSummary.make(items: [night], spentLimitNames: [], wakes: [], now: ny(11, 2, 23, 30))
check(s.hero == .oneBlock(name: "Sleep", until: ny(11, 3, 7)), "midnight: ends tomorrow")
let en = Locale(identifier: "en_US")
let sameDay = Date.FormatStyle(date: .omitted, time: .shortened, locale: en,
                               calendar: ny, timeZone: ny.timeZone)
check(TodayTimeText.short(ny(11, 2, 21), now: now, calendar: ny, locale: en)
      == ny(11, 2, 21).formatted(sameDay), "same day: time only")
let tomorrow = TodayTimeText.short(ny(11, 3, 7), now: ny(11, 2, 23, 30), calendar: ny, locale: en)
check(tomorrow.contains("Tue") && tomorrow.contains("7:00"), "after midnight: weekday shown (\(tomorrow))")
let farAway = TodayTimeText.short(ny(11, 12, 9), now: now, calendar: ny, locale: en)
check(farAway.contains("Nov") && farAway.contains("12"), "a week or more: date shown (\(farAway))")
let yesterday = TodayTimeText.short(ny(11, 1, 22), now: now, calendar: ny, locale: en)
check(yesterday.contains("Sun"), "yesterday evening: weekday shown (\(yesterday))")

// MARK: Day thread
let day = DateInterval(start: ny(11, 2), end: ny(11, 3))
let tail = block("t", "Night", ny(11, 1, 22), ny(11, 2, 6))
let gone = block("g", "Gone", ny(11, 1, 20), ny(11, 1, 23))
let tap = TodayItem(id: "w", name: "Morning", kind: .wake, start: ny(11, 2, 6), end: ny(11, 2, 6), needsTap: true)
var thread = DayThread.make(items: [evening, study, tail, gone, lunch, tap], now: now, day: day)
check(thread.entries.map(\.item.id) == ["t", "w", "p1", "e1", "s1"], "time order, yesterday's finished rule dropped")
check(thread.entries.map(\.phase) == [.past, .now, .now, .now, .upcoming], "phases")
check(thread.nowIndex == 4 && thread.hiddenCount == 0, "now marker before upcoming")
let crowd = (0..<8).map { block("c\($0)", "C\($0)", ny(11, 2, 1 + $0), ny(11, 2, 1 + $0, 30)) }
    + [block("u1", "U1", ny(11, 2, 20), ny(11, 2, 21)), block("u2", "U2", ny(11, 2, 21), ny(11, 2, 22))]
thread = DayThread.make(items: crowd, now: ny(11, 2, 12), day: day)
check(thread.entries.map(\.item.id) == ["c5", "c6", "c7", "u1", "u2"] && thread.hiddenCount == 5,
      "cap keeps upcoming, fills with most recent past")
check(thread.nowIndex == 3, "marker after past")
thread = DayThread.make(items: (0..<7).map { block("f\($0)", "F", ny(11, 2, 13 + $0), ny(11, 2, 14 + $0)) },
                        now: ny(11, 2, 12), day: day)
check(thread.entries.count == 5 && thread.nowIndex == 0 && thread.hiddenCount == 2, "all upcoming, capped")
check(DayThread.make(items: [], now: now, day: day).entries.isEmpty, "empty day")
let dstDay = DateInterval(start: ny(3, 8), end: ny(3, 9))
check(dstDay.duration == 23 * 3600, "DST day is 23 h")
thread = DayThread.make(items: [block("d", "Late", ny(3, 8, 23), ny(3, 9, 1))], now: ny(3, 8, 12), day: dstDay)
check(thread.entries.count == 1 && thread.entries[0].phase == .upcoming, "DST day keeps its late block")

// MARK: Ledger grouping
func bucket(_ d: Date, _ n: Date, _ c: Calendar = ny) -> LedgerGrouping.Bucket {
    LedgerGrouping.bucket(d, now: n, calendar: c)
}
let base = ny(11, 2, 10)
check(bucket(base.addingTimeInterval(-90), base) == .withinHour, "due and overdue: within the hour")
check(bucket(base.addingTimeInterval(3600), base) == .withinHour, "exactly an hour")
check(bucket(base.addingTimeInterval(3601), base) == .laterToday, "just past an hour")
check(bucket(ny(11, 2, 23, 59), base) == .laterToday, "last minute of today")
check(bucket(ny(11, 3, 0, 10), ny(11, 2, 23, 30)) == .withinHour, "the hour wins across midnight")
check(bucket(ny(11, 3, 0, 31), ny(11, 2, 23, 30)) == .tomorrow, "after midnight, over an hour: tomorrow")
check(bucket(ny(11, 3, 23, 59), base) == .tomorrow, "end of tomorrow")
check(bucket(ny(11, 4, 0, 0), base) == .day(ny(11, 4)), "two days ahead: its day")
check(bucket(ny(11, 8, 23), base) == .day(ny(11, 8)), "six days ahead: its day")
check(bucket(ny(11, 9, 0, 0), base) == .later, "seven days ahead: later")
// Daylight saving: 23-hour and 25-hour days still bucket by calendar day.
check(bucket(ny(3, 9, 0, 30), ny(3, 7, 22)) == .day(ny(3, 9)), "across spring forward")
check(bucket(ny(3, 8, 23, 30), ny(3, 7, 22)) == .tomorrow, "spring-forward day is tomorrow")
check(bucket(ny(11, 1, 23, 30), ny(11, 1, 0, 30)) == .laterToday, "25-hour day: late evening is today")
check(bucket(ny(11, 1, 23, 59), ny(10, 31, 23)) == .tomorrow, "fall-back day is tomorrow")
check(bucket(ny(11, 2, 0, 30), ny(11, 1, 23, 45)) == .withinHour, "within the hour across fall back")
// Time-zone change: the same instants regroup with the calendar's zone.
let utc = calendar("UTC"), london = calendar("Europe/London"), tokyo = calendar("Asia/Tokyo")
let instant = at(utc, 2026, 11, 2, 20), lands = instant.addingTimeInterval(6 * 3600)
check(bucket(lands, instant, ny) == .laterToday, "New York: same evening")
check(bucket(lands, instant, london) == .tomorrow, "London: after midnight")
check(bucket(lands, instant, tokyo) == .laterToday, "Tokyo: same morning")
let grouped = LedgerGrouping.groups([base.addingTimeInterval(7200), base.addingTimeInterval(60),
                                     ny(11, 3, 9), base.addingTimeInterval(120), ny(11, 20)],
                                    date: { $0 }, now: base, calendar: ny)
check(grouped.map(\.bucket) == [.withinHour, .laterToday, .tomorrow, .later], "groups in landing order")
check(grouped[0].items == [base.addingTimeInterval(60), base.addingTimeInterval(120)], "items sorted in a group")
check(LedgerGrouping.groups([Date](), date: { $0 }, now: base, calendar: ny).isEmpty, "no changes, no groups")

// MARK: Receipt
var plan = ReceiptPlan.make(looser: false, delay: 0, now: base)
check(plan.takesEffect == nil && plan.wait == nil && plan.commit == .confirm, "delay 0 stricter: right away, Confirm")
plan = ReceiptPlan.make(looser: true, delay: 0, now: base)
check(plan.takesEffect == nil && plan.commit == .hold, "looser with no wait still holds")
plan = ReceiptPlan.make(looser: false, delay: 900, now: base)
check(plan.takesEffect == base.addingTimeInterval(900) && plan.wait == 900 && plan.commit == .confirm,
      "minutes: takes effect now + delay")
plan = ReceiptPlan.make(looser: true, delay: 86_400, now: base)
check(plan.takesEffect == base.addingTimeInterval(86_400) && plan.commit == .hold, "days: hold")
check(ReceiptPlan.waitText(900, locale: en) == "15 minutes", "15 minutes")
check(ReceiptPlan.waitText(86_400, locale: en) == "1 day", "1 day")
check(ReceiptPlan.waitText(2 * 86_400 + 3 * 3600 + 120, locale: en) == "2 days, 3 hours", "two units at most")
check(ReceiptPlan.waitText(30, locale: en) == "1 minute", "under a minute rounds up")
check(ReceiptPlan.waitText(9000, locale: en) == "2 hours, 30 minutes", "hours and minutes")
check(ReceiptPlan.waitText(86_400, locale: Locale(identifier: "es")) == "1 día", "Spanish units")
print("Today presentation passed: \(checks) checks — Now priority rows, ties, midnight, thread cap, ledger hour/day/DST/time-zone buckets, receipt text")
'''

with tempfile.TemporaryDirectory(prefix='demora-today-') as directory:
    main = Path(directory) / 'main.swift'
    binary = Path(directory) / 'today'
    main.write_text(driver)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', str(presentation), str(main),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

# --- Change receipt (§5.10) and where it's adopted -------------------------
import re
STRING = r'"((?:[^"\\]|\\.)*)"'


def section(text, start, end):
    assert start in text, ('missing', start)
    return text.split(start, 1)[1].split(end, 1)[0]


receipt = (ROOT / 'Latch/ChangeReceiptSheet.swift').read_text()
sheet = section(receipt, 'struct ChangeReceiptSheet: View {', '\n}\n')
assert 'model.preview(action)' in sheet, 'direction and delay come from the same policy as the queue'
assert 'ChangeEngine.summary(for: action, state: model.state)' in sheet, 'the queued change says the same'
assert 'ReceiptPlan.make(looser: direction == .lenient, delay: delay, now: now)' in sheet
assert 'HoldButton(tr("Hold to confirm"), role: .loosen,' in sheet
assert 'confirmationTitle: tr("Confirm looser change?")' in sheet
assert 'case .confirm:' in sheet and '.buttonStyle(DemoraPrimaryButtonStyle())' in sheet
assert sheet.count('model.queue(') == 1 and 'if model.queue(action) != nil {' in sheet, \
    'queues once, only on confirm'
assert 'model.queueNotice = nil' in sheet, 'a refusal stays on the receipt, not the app-wide alert'
for forbidden in ('TimeGuard', 'SharedStore', 'ChangeEngine.queue', 'applyNow'):
    assert forbidden not in receipt, ('receipt must not', forbidden)
presenter = section(receipt, 'private struct ChangeReceiptPresenter: ViewModifier {', '\n}\n')
assert 'if queued { queued = false; onQueued() }' in presenter, 'the editor closes after the receipt'

limits = (ROOT / 'Latch/LimitsView.swift').read_text()
# Rules build: the legacy tutorial keeps its own limit editor (it queues
# directly, as its steps expect); everyone else uses the rebuilt editor,
# which only ever queues through the receipt. Removing moved to the sheet.
editor = section(limits, 'struct TutorialLimitEditorView: View {', '\n/// Hosts FamilyActivityPicker')
submit = section(editor, 'private func submit(_ action: ChangeAction) {', '\n    }\n')
assert 'if model.inTutorial {' in submit and 'receipt = ChangeReceiptRequest(action: action)' in submit
assert editor.count('model.queue(') == 1, 'the tutorial editor queues only through submit'
assert 'submit(.removeLimit(id: existing.id))' in editor
rebuilt = section((ROOT / 'Latch/RuleEditors.swift').read_text(), 'struct LimitEditorView: View {',
                  '\nprivate struct WeekdayBudgetsPage')
assert 'model.queue(' not in rebuilt, 'the rebuilt limit editor queues only through the receipt'
assert 'receipt = ChangeReceiptRequest(action: existing != nil ? .configureLimit(draftLimit)' in rebuilt
assert '.changeReceipt($receipt) { dismiss() }' in rebuilt

schedules = (ROOT / 'Latch/SchedulesView.swift').read_text()
for action in ('.removePlanned(', '.removeExemption('):
    assert f'model.queue({action}' not in schedules, ('removal bypasses the receipt', action)
detail = section(schedules, 'struct ScheduledItemDetailView: View {', '\n// MARK: - Type card')
assert 'receipt = ChangeReceiptRequest(action: .removeSchedule(id: schedule.id))' in detail
recurring = section(schedules, 'struct RecurringListView: View {', '\n// MARK: - Recurrence picker')
assert 'model.queue(' in recurring and recurring.count('model.queue(') == 1 \
    and 'if model.inTutorial {\n            model.queue(action)' in recurring, 'only the tutorial queues directly'
for view in (detail, recurring, section(schedules, 'struct PlannedListView: View {', '\nstruct RecurringListView')):
    assert '.changeReceipt($receipt)' in view
# You build: contact removal moved to the one detail page (SkipWayEditors.swift).
contacts = (ROOT / 'Latch/ContactsOverrideViews.swift').read_text() + (ROOT / 'Latch/SkipWayEditors.swift').read_text()
assert 'model.queue(.removeContact(' not in contacts
assert 'case .contact: return .removeContact(id: id)' in contacts
assert 'receipt = ChangeReceiptRequest(action: removal)' in contacts and '.changeReceipt($receipt)' in contacts

# --- Every word on the new screens is translated ---------------------------
TABLES = {'es': '', 'de': '+German', 'fr': '+French', 'pt': '+Portuguese',
          'pl': '+Polish', 'tr': '+Turkish', 'hi': '+Hindi'}
TODAY_FILES = ['Latch/ChangeReceiptSheet.swift', 'Latch/ChangesLedgerView.swift', 'Latch/TodayView.swift']
keys = set()
for name in TODAY_FILES:
    path = ROOT / name
    if not path.exists():
        continue
    text = path.read_text()
    for call in re.findall(r'\btr\((?:[^()"]|"(?:[^"\\]|\\.)*")*\)', text):
        keys.update(re.findall(STRING, call))
assert keys, 'no translated strings found'
entry = re.compile(r'^\s*' + STRING + r'\s*:\s*' + STRING + r',?\s*$', re.M)
for code, suffix in TABLES.items():
    pairs = entry.findall((ROOT / f'Shared/Localization{suffix}.swift').read_text())
    seen = [k for k, _ in pairs]
    duplicates = sorted({k for k in seen if seen.count(k) > 1})
    assert not duplicates, (code, 'duplicate keys crash the dictionary literal', duplicates)
    table = dict(pairs)
    missing = sorted(k for k in keys if k not in table)
    assert not missing, (code, 'untranslated', missing)
    for key in keys:
        for spec in ('%@', '%d'):
            assert key.count(spec) == table[key].count(spec), (code, key, spec)
print(f'Today source guards passed: receipt confirm/hold and adoption; {len(keys)} strings × 7 tables, no duplicate keys')

# --- Changes ledger (§5.9) --------------------------------------------------
ledger = (ROOT / 'Latch/ChangesLedgerView.swift').read_text()
row = section(ledger, 'struct ChangeRow: View {', '\n}\n')
assert 'CountdownText(to: change.appliesAt)' in row
assert 'Text(timerInterval:' not in row and 'TimeGuard.now()' not in row, \
    'projection must live only in CountdownProjection'
assert row.index('if let frozenRemaining') < row.index('} else if change.isDue') \
    < row.index('CountdownText(to: change.appliesAt'), 'tutorial → due → countdown order kept'
assert 'Text(tr("Applying…"))' in row
assert 'if canOverride && !change.isDue {' in row, 'Apply now only when an override exists'
assert '#if DEBUG' in row and 'Skip delay (dev)' in row.split('#if DEBUG', 1)[1].split('#endif', 1)[0], \
    'the developer skip stays Debug-only'
assert 'tr(change.direction == .stricter ? "Stricter" : "Looser")' in row
ledger_view = section(ledger, 'struct ChangesLedgerView: View {', '\nprivate struct LedgerSection')
assert 'LedgerGrouping.groups(model.state.pending, date: \\.appliesAt,' in ledger_view, 'stored appliesAt'
assert 'selection.formIntersection(pendingIDs)' in ledger_view
assert 'if pendingIDs.isEmpty { selecting = false }' in ledger_view
assert 'confirmBulkCancel = true' in ledger_view and '.confirmationDialog(tr("Cancel these changes?")' in ledger_view, \
    'bulk cancel asks once'
assert 'onCancel: { model.cancel(change) }' in ledger_view, 'a single cancel stays immediate'
# You build (Y4): Apply now, the bulk bar and "Waiting for…" open one Skip the wait sheet.
assert 'onOverride: { skipTarget = .changes([change]) }' in ledger_view
assert 'skipTarget = .changes(needGate)' in ledger_view
assert 'skipTarget = .request(model.state.pending.filter { request.changeIds.contains($0.id) })' in ledger_view
assert '.skipWaitSheet($skipTarget, onDismiss: onRequestsChanged)' in ledger_view
for gone in ('OverrideGateView', 'ContactGateView', '.sheet('):
    assert gone not in ledger_view, ('one sheet, steps inside it', gone)
assert 'ChangeEngine.hasOverride(for: needGate, state: model.state)' in ledger_view
waiting = section(ledger, 'struct ChangeWaiting: Equatable {', '\n}\n')
assert '$0.changeIds.contains(change.id)' in waiting and 'contacts.first { $0.id == id }' in waiting
for forbidden in ('ContactsRelay.outgoingRequests', 'clearOutgoing', 'SharedStore'):
    assert forbidden not in ledger, ('the ledger reuses what Today loads', forbidden)
print('Ledger source guards passed: countdown projection, grouping on stored appliesAt, Select bar, waiting contact')

# --- Today layout (§5.1–5.8) ------------------------------------------------
home = (ROOT / 'Latch/HomeView.swift').read_text()
today_src = (ROOT / 'Latch/TodayView.swift').read_text()
host = (ROOT / 'Latch/LimitsUsageReportView.swift').read_text()
body = section(home, 'struct HomeView: View {', '    /// Status helpers')
today = section(body, '    private var today: some View {', '    // MARK: Legacy Home')
assert 'if model.inTutorial {\n                    legacyHome\n                } else {\n                    today' in body, \
    'the legacy tutorial keeps its Home'
order = ['TodayHeader(', 'TodayAttentionCard(', 'NowCard(', 'InboxCard(', 'limitsSection',
         'dayThread(at:', 'changingSoon', 'moreLinks']
positions = [today.index(token) for token in order]
assert positions == sorted(positions), ('Today order', order)
assert 'if !needsWakeTap {' in today and 'Label(tr("Block now")' in today and 'SessionStartView()' in today, \
    'Block now pinned, hidden while Wake up shows'
assert '.safeAreaInset(edge: .bottom)' in today
assert 'ChangesLedgerView(outgoing: activeOutgoing, onRequestsChanged: loadOutgoing,\n                                  scrollTo: ledgerTarget, navigationReset: ledgerNavigationReset)' in today
assert 'LimitEditorView(existing: nil)' in today and 'model.selectedTab = 1 } label' not in today, \
    'the empty state opens the editor, not a tab switch'
# You build (Y4): extra time opens Skip the wait on the step's own method.
assert 'case .contact(let context): skipTarget = .extraContact(context)' in home
assert 'policies: model.state.overrides).map(SkipWaitTarget.extraPassword)' in home
assert 'policies: model.state.overrides).map(SkipWaitTarget.extraPhrase)' in home
assert home.count('.skipWaitSheet($skipTarget') == 1 and 'OverrideGateView' not in home \
    and 'ContactGateView' not in home, 'one Skip the wait sheet on Today'
assert 'CompactHomeUsageReport(limits: model.state.limits,\n                                       reloadRequest: usageRefreshRequest)' in body
assert 'pending.prefix(2)' in body and 'String(format: tr("All %d"), pending.count)' in body
# You build: the Help link opens You's Help & guide page until the four-tab switch.
assert 'UsageInsightsView()' in body and 'HelpGuideView()' in body, 'kept at the bottom until the four-tab switch'
assert body.count('.task(id: model.selectedTab == 0)') == 1, 'one inbox load per Home, both layouts'
assert '.refreshable {\n                usageRefreshRequest = UUID()' in body, 'pull to refresh stays'
for forbidden in ('GlobalWake.status(', 'DayNightWake.status(', 'LimitFeatures.wakeState(',
                  'LimitFeatures.extraTimeState(', 'SharedStore.loadBlockedLimitIDs(', 'TimeGuard.now()'):
    assert forbidden not in body, ('read in event callbacks, never in the body', forbidden)
snapshot = section(home, '    private func refreshSnapshot(state: LatchState) {', '\n    }\n')
assert 'SharedStore.loadBlockedLimitIDs()' in snapshot and 'LimitFeatures.extraTimeState(for: limit)' in snapshot
assert 'guard !model.inTutorial else' in snapshot
for call in ('refreshWakePresentation(state: state)',):
    assert call in snapshot
sources = section(home, "private enum HomeDaySources {", "\nextension NowSummary {")
for forbidden in ('TimeGuard', 'SharedStore', 'Status(', '.status(', 'ApplicationToken', 'selection'):
    assert forbidden not in sources, ('day sources are rule names and times only', forbidden)
adapter = section(home, 'extension NowSummary {', '\n}\n')
assert 'state.limits' in adapter and '.map(\\.name)' in adapter, 'Now card names are rule names'
# Today's pieces draw; they don't read guarded clocks or saved state.
views = today_src.split('enum ExtraTimeRoute {', 1)[0] + today_src.split('struct ExtraTimeRows: View {', 1)[1]
for forbidden in ('TimeGuard.', 'SharedStore.', 'model.queue', 'ChangeEngine.'):
    assert forbidden not in views, ('Today views must not', forbidden)
route = section(today_src, 'enum ExtraTimeRoute {', '\n}\n')
for gate in ('step.contactRequired', 'step.passwordPolicyID != nil', 'step.phrasePolicyID != nil',
             'ContactsRelay.pendingExtraRequest(for: limit.id)'):
    assert gate in route, ('extra time keeps every gate', gate)
assert 'case .ready, .waiting, .active: return (limit, state)' in today_src, 'only ready/waiting/active rows'
assert 'CountdownText(to: until)' in today_src, 'extra-time wait is a TimeGuard release'
# Report host: refresh arrow gone (Insights I6), pull-to-refresh and refresh-on-appear kept.
assert 'arrow.clockwise' not in host and 'tr("Refresh")' not in host
assert '.onAppear { onScreen = true; requestRefresh() }' in host and '.onChange(of: reloadRequest)' in host
print('Today layout guards passed: section order, legacy tutorial routing, pinned Block now, event-only reads, rule names only, report refresh')

# --- Report restyle (§5.5) and its palette copy -----------------------------
theme = (ROOT / 'Latch/Theme.swift').read_text()
report_theme = (ROOT / 'LatchReport/ReportTheme.swift').read_text()
pair = re.compile(r'static let (\w+)\s*=\s*\w+\(light: 0x([0-9A-Fa-f]{6}), dark: 0x([0-9A-Fa-f]{6})\)')
app_palette = {name: (l.upper(), d.upper()) for name, l, d in pair.findall(section(theme, 'enum InkPalette {', '\n}\n'))}
copied = {name: (l.upper(), d.upper()) for name, l, d in pair.findall(section(report_theme, 'enum ReportPalette {', '\n}\n'))}
assert len(copied) >= 7, copied
for name, values in copied.items():
    assert app_palette.get(name) == values, ('report palette drifted from InkPalette', name, values, app_palette.get(name))
assert 'value == "red" ? ReportPalette.loosenOchre : ReportPalette.loosen' in report_theme, 'ochre with the red accent'
report_view = (ROOT / 'LatchReport/LimitsUsageView.swift').read_text()
assert 'insightsText("No data yet")' in report_view and 'r.hasData' in report_view, 'missing is unknown, not zero'
assert 'insightsText("Used up")' in report_view and 'insightsText("%d of %d min")' in report_view
assert 'Color(red:' not in report_view, 'colours come from ReportTheme'
for forbidden in ('.set(', 'removeObject', 'NotificationCenter', 'FileManager', 'URLSession', 'print('):
    assert forbidden not in report_theme, ('report theme must stay read-only', forbidden)
extension_src = (ROOT / 'LatchReport/LatchReportExtension.swift').read_text()
assert 'if let seconds = perApp[t] { used += seconds; reported = true }' in extension_src
print('Report guards passed: palette copy matches InkPalette, no-data rows, used-up rows, read-only theme')

# --- T5: extra time moved from the Limits tab to Today -----------------------
limits_tab = section((ROOT / 'Latch/LimitsView.swift').read_text(), 'struct LimitsView: View {', '\n/// A limit row')
for gone in ('extraTimeControl', 'requestExtraTimeOffMain', 'ExtraTimePasswordGate', 'ExtraTimePhraseGate',
             'extraContactTarget'):
    assert gone not in limits_tab, ('extra time lives on Today only', gone)
assert 'ExtraTimeRows(limits: model.state.limits, states: extraTimes,' in home
assert 'ChangeEngine.requestExtraTimeOffMain(limitID: id)' in home
print('Extra time guards passed: one place (Today), same gates')

# --- Review fixes ----------------------------------------------------------
rows_view = section(today_src, 'struct ExtraTimeRows: View {', '\n// MARK: - Day thread')
assert 'ContactsRelay.' not in rows_view and 'contactPending.contains(limit.id)' in rows_view, \
    'the pending contact request is read in refreshSnapshot, not while drawing'
snapshot = section(home, '    private func refreshSnapshot(state: LatchState) {', '\n    }\n')
for read in ('LimitFeatures.extraUnblockedIDs(state: state, at: now)',
             'LimitFeatures.blockedFeatureIDs(state: state, at: now, includeWake: false)',
             '!extraUnblocked.contains($0.id)', 'featureBlocked.subtracting(daily)',
             'ContactsRelay.pendingExtraRequest(for: limit.id)'):
    assert read in snapshot, ('the Now card mirrors the shield baseline', read)
for layer in ('layer: 3, start: session.startedAt', 'layer: 2, start: window.startsAt',
              'kind: .block, layer: 0, start: interval.start'):
    assert layer in home, ('day sources carry their effect layer', layer)
print('Review-fix guards passed: event-only contact read, shield-baseline spent sets, effect layers')
