//
//  TodayPresentation.swift
//  Pure decisions for Today, the Changes ledger and the change receipt
//  (docs/today-redesign.md §5.3, §5.6, §5.9, §5.10). Foundation only, so
//  Tests/TodayPresentationHarness.py compiles this file as it is.
//  Presentation only: nothing here reads or writes saved state, starts a
//  monitor or decides enforcement. The views translate every word shown.
//

import Foundation

// MARK: - Today's items

/// One rule interval as Today shows it. Built from the same sources as the
/// legacy day line (sessions, planned windows, recurring blocks and free
/// periods, wake-up gates) plus sleep blocks. Names are the user's own rule
/// names, never app names.
struct TodayItem: Equatable {
    /// `unblock` is a session lifting blocks on chosen apps: shown on the
    /// thread, but neither a block nor a free period for the Now card.
    enum Kind: Equatable { case block, free, unblock, wake }

    let id: String
    let name: String
    /// The rule kind's label ("Block only…", "Free period"), for the legacy line.
    var detail: String = ""
    let kind: Kind
    /// Default effect order: sleep 0, recurring 1, planned 2, session 3. An
    /// active free rule on a higher layer clears blocks below it, as the
    /// shield plan applies them.
    var layer: Int = 1
    /// Wall-clock interval, not clipped to the day.
    let start: Date
    let end: Date
    /// A wake-up gate waiting for its tap; `end` is now, not a predicted unlock.
    var needsTap = false

    func isActive(at now: Date) -> Bool { start <= now && now < end }
}

// MARK: - Now card

/// The Now card's content: one sentence, up to two facts, an optional action.
struct NowSummary: Equatable {
    enum Hero: Equatable {
        case wakeNeeded
        case wakeRunning(opensAt: Date)
        case oneBlock(name: String, until: Date)
        case severalBlocks(count: Int, firstEnd: Date)
        /// `forNow` when a split portion, not the whole day, is used up.
        case spent(names: [String], forNow: Bool)
        case free(until: Date)
        case nothing
    }

    enum Fact: Equatable {
        /// A group waiting for its wake tap and how long its wait will be.
        case wakeWait(name: String, minutes: Int)
        case countdown(to: Date)
        /// Rule names, with how many more weren't listed.
        case names([String], more: Int)
        case resetsAtMidnight
        case next(name: String, at: Date)
    }

    enum Action: Equatable { case wakeUp }

    /// A wake-up gate as Home already projects it in event callbacks.
    struct Wake: Equatable {
        let name: String
        /// The wait a tap would start; nil when it isn't known.
        var waitMinutes: Int?
        /// Projected wall-clock release; nil means a tap is needed.
        let release: Date?
    }

    let hero: Hero
    let facts: [Fact]
    let action: Action?

    static let maxFacts = 2
    static let maxNames = 3

    /// Spec §5.3 priority. Rows are checked top to bottom; the first match wins.
    /// An active free period means limits aren't blocking, so spent limits
    /// only lead when no free period is running.
    static func make(items: [TodayItem], spentLimitNames: [String],
                     portionLimitNames: [String] = [],
                     wakes: [Wake], now: Date) -> NowSummary {
        // 1. A wake tap is needed.
        let needsTap = wakes.filter { $0.release == nil }
        if !needsTap.isEmpty {
            // A zero wait opens on the tap, so it has no wait to state.
            let facts = needsTap.compactMap { wake -> Fact? in
                guard let minutes = wake.waitMinutes, minutes > 0 else { return nil }
                return .wakeWait(name: wake.name, minutes: minutes)
            }
            return NowSummary(hero: .wakeNeeded, facts: Array(facts.prefix(maxFacts)),
                              action: .wakeUp)
        }
        // 2. Wake waits are running: apps open when the last one ends.
        let releases = wakes.compactMap(\.release).filter { $0 > now }
        if let opens = releases.max() {
            return NowSummary(hero: .wakeRunning(opensAt: opens),
                              facts: [.countdown(to: opens)], action: nil)
        }
        // 3–4. Blocks active now, first to end first; ties by name. A free
        // rule on a higher layer (a free session over a recurring block)
        // clears them; on the same layer the block is kept, to stay cautious.
        let freeLayer = items.filter { $0.kind == .free && $0.isActive(at: now) }.map(\.layer).max()
        let blocks = unique(items.filter {
            $0.kind == .block && $0.isActive(at: now) && $0.layer >= (freeLayer ?? Int.min)
        }).sorted { ($0.end, $0.name) < ($1.end, $1.name) }
        if let first = blocks.first {
            if blocks.count == 1 {
                return NowSummary(hero: .oneBlock(name: first.name, until: first.end),
                                  facts: [.countdown(to: first.end)], action: nil)
            }
            let names = blocks.map(\.name)
            return NowSummary(hero: .severalBlocks(count: blocks.count, firstEnd: first.end),
                              facts: [.names(Array(names.prefix(maxNames)),
                                             more: max(0, names.count - maxNames))],
                              action: nil)
        }
        // 6 before 5: free lasts until the latest end among those active now.
        let free = items.filter { $0.kind == .free && $0.isActive(at: now) }
        if let until = free.map(\.end).max() {
            return NowSummary(hero: .free(until: until), facts: [], action: nil)
        }
        // 5. Only spent limits. A split portion reopens at its cutoff, so it
        // never claims midnight.
        let daily = Set(spentLimitNames)
        let spent = Array(daily.union(portionLimitNames)).sorted()
        if !spent.isEmpty {
            let forNow = !Set(portionLimitNames).isSubset(of: daily)
            return NowSummary(hero: .spent(names: spent, forNow: forNow),
                              facts: forNow ? [] : [.resetsAtMidnight], action: nil)
        }
        // 7. Nothing: name the next block starting later, if any.
        let next = unique(items.filter { $0.kind == .block && $0.start > now })
            .sorted { ($0.start, $0.name) < ($1.start, $1.name) }.first
        return NowSummary(hero: .nothing,
                          facts: next.map { [.next(name: $0.name, at: $0.start)] } ?? [],
                          action: nil)
    }

    /// One entry per rule interval; the same rule can't be counted twice.
    private static func unique(_ items: [TodayItem]) -> [TodayItem] {
        var seen = Set<String>()
        return items.filter { seen.insert("\($0.id)|\($0.start.timeIntervalSinceReferenceDate)").inserted }
    }
}

// MARK: - Times

enum TodayTimeText {
    /// "14:32" today, "Tue 07:00" within the coming week, "9 Nov, 07:00" later.
    /// Times past midnight always carry their day, so "until 07:00" is never
    /// read as this morning.
    static func short(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened,
                                     locale: locale, calendar: calendar,
                                     timeZone: calendar.timeZone)
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(style) }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        style = days > -7 && days < 7
            ? style.weekday(.abbreviated)
            : style.day().month(.abbreviated)
        return date.formatted(style)
    }
}

// MARK: - Day thread

enum DayThread {
    enum Phase: Equatable { case past, now, upcoming }

    struct Entry: Equatable {
        let item: TodayItem
        let phase: Phase
    }

    struct Result: Equatable {
        let entries: [Entry]
        /// Where the "now" marker sits: before this entry (== count: at the end).
        let nowIndex: Int
        /// Items left out by the cap ("Full day" shows them).
        let hiddenCount: Int
    }

    /// Today's items in time order, capped. Active and upcoming items are kept
    /// first; spare slots go to the most recent past items.
    static func make(items: [TodayItem], now: Date, day: DateInterval, cap: Int = 5) -> Result {
        let today = items.filter { item in
            item.needsTap || (item.end > day.start && item.start < day.end && item.end > item.start)
        }.sorted { ($0.start, $0.name, $0.id) < ($1.start, $1.name, $1.id) }
        let all = today.map { item -> Entry in
            let phase: Phase = item.needsTap || item.isActive(at: now) ? .now
                : (item.end <= now ? .past : .upcoming)
            return Entry(item: item, phase: phase)
        }
        let current = all.filter { $0.phase != .past }
        let kept = Array(current.prefix(cap))
        let pastSlots = max(0, cap - kept.count)
        let recentPast = Array(all.filter { $0.phase == .past }.suffix(pastSlots))
        let entries = (recentPast + kept).sorted {
            ($0.item.start, $0.item.name, $0.item.id) < ($1.item.start, $1.item.name, $1.item.id)
        }
        let nowIndex = entries.firstIndex { $0.phase == .upcoming } ?? entries.count
        return Result(entries: entries, nowIndex: nowIndex, hiddenCount: all.count - entries.count)
    }
}

// MARK: - Changes ledger

enum LedgerGrouping {
    enum Bucket: Hashable {
        case withinHour, laterToday, tomorrow
        /// Start of a day two to six days ahead.
        case day(Date)
        case later
    }

    /// Groups by when a change lands, in the given calendar's time zone.
    /// Due and overdue changes count as within the hour.
    static func bucket(_ date: Date, now: Date, calendar: Calendar) -> Bucket {
        if date.timeIntervalSince(now) <= 3600 { return .withinHour }
        if calendar.isDate(date, inSameDayAs: now) { return .laterToday }
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        if days <= 1 { return .tomorrow }
        return days < 7 ? .day(target) : .later
    }

    /// Buckets in landing order, each with its items in landing order.
    static func groups<T>(_ items: [T], date: (T) -> Date, now: Date,
                          calendar: Calendar) -> [(bucket: Bucket, items: [T])] {
        var result: [(bucket: Bucket, items: [T])] = []
        for item in items.sorted(by: { date($0) < date($1) }) {
            let bucket = bucket(date(item), now: now, calendar: calendar)
            if let last = result.indices.last, result[last].bucket == bucket {
                result[last].items.append(item)
            } else {
                result.append((bucket, [item]))
            }
        }
        return result
    }
}

// MARK: - Change receipt

/// What the receipt says before a change is queued. The delay and direction
/// come from `model.preview(action)`, the same policy the queue uses, so the
/// receipt and the queued change agree.
struct ReceiptPlan: Equatable {
    enum Commit: Equatable { case hold, confirm }

    let looser: Bool
    /// Nil means right away.
    let takesEffect: Date?
    /// Nil when it takes effect right away.
    let wait: TimeInterval?
    let commit: Commit

    /// Looser changes (including looser removals) always hold to confirm, even
    /// with no wait; stricter ones, such as removing a contact, confirm with one
    /// tap (plan D9 as corrected 2026-11-02).
    static func make(looser: Bool, delay: TimeInterval, now: Date) -> ReceiptPlan {
        let waits = delay > 0
        return ReceiptPlan(looser: looser,
                           takesEffect: waits ? now.addingTimeInterval(delay) : nil,
                           wait: waits ? delay : nil,
                           commit: looser ? .hold : .confirm)
    }

    /// "45 minutes", "2 hours, 30 minutes", "1 day". Rounded up to the minute
    /// so a short wait never reads as zero.
    static func waitText(_ seconds: TimeInterval, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        let minutes = max(1, (seconds / 60).rounded(.up))
        return formatter.string(from: minutes * 60) ?? ""
    }
}
