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
check(s.hero == .spent(names: ["Chat", "Games"]) && s.facts == [.resetsAtMidnight], "5: spent only")
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
