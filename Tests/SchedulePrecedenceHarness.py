#!/usr/bin/env python3
"""Run: python3 Tests/SchedulePrecedenceHarness.py

Compile the actual precedence core, ScheduleShieldPlan, SharedModels and
PhraseWords declaration using
Swift/Foundation. Only unavailable framework imports and opaque tokens are
adapted. No production algorithms are rewritten and no live state is read.
Wake-active statuses are injected, not read from persistence. This verifies pure
shield composition, not Apple ManagedSettings stores or callback delivery.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def declaration(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def portable(source):
    return source.replace("import FamilyControls\n", "").replace("import ManagedSettings\n", "")


models = portable((ROOT / "Shared/SharedModels.swift").read_text())
core = portable((ROOT / "Shared/SchedulePrecedence.swift").read_text())
shield_plan = portable((ROOT / "Shared/ScheduleShieldPlan.swift").read_text())
phrases = declaration((ROOT / "Shared/PhraseWords.swift").read_text(), "enum PhraseWords {")
for forbidden in ["SharedStore.", "UserDefaults", "TimeGuard.now(", "URLSession", "ManagedSettingsStore", "DeviceActivityCenter"]:
    assert forbidden not in core, f"Pure core must not access {forbidden}"
assert 'tr("' not in core, "Localizing inside the pure core reads persisted preferences"

infrastructure = r'''
import Foundation
struct FamilyActivitySelection: Codable, Equatable {
    var includeEntireCategory = false
    var applicationTokens: Set<String> = []
    var categoryTokens: Set<String> = []
    var webDomainTokens: Set<String> = []
}
func tr(_ text: String) -> String { text }
enum TimeGuard {
    static func now() -> Date { fatalError("Inspection must not read runtime clock") }
}
'''

checks = r'''
typealias P = SchedulePrecedence
var assertions = 0
var failures: [String] = []
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !condition() { failures.append(message) }
}
func date(_ year: Int = 2026, _ month: Int = 10, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}
func selection(_ apps: Set<String> = [], categories: Set<String> = [], sites: Set<String> = []) -> FamilyActivitySelection {
    var s = FamilyActivitySelection()
    s.applicationTokens = apps; s.categoryTokens = categories; s.webDomainTokens = sites
    return s
}
func entry(_ key: String, _ layer: P.Layer = .recurring, _ kind: P.Kind = .blockSelected,
           _ s: FamilyActivitySelection = selection(["a"]), _ tie: Int = 0,
           start: Date = date(2026, 10, 3, 10), end: Date = date(2026, 10, 3, 12)) -> P.Entry {
    P.Entry(key: key, name: key, layer: layer, start: start, end: end, kind: kind, selection: s, tieOrder: tie)
}
func key(_ prefix: String, _ id: UUID) -> String { "\(prefix)-\(id.uuidString)" }

// Ordering, duplicate promotion, stale keys, stable ties and input independence.
let ordinary = [entry("session", .session), entry("planned", .planned),
                entry("later", .recurring, .free, selection(), 1),
                entry("earlier", .recurring), entry("wake", .boundary)]
expect(P.ordered(entries: ordinary, prioritizedKeys: []).map(\.key)
       == ["wake", "earlier", "later", "planned", "session"], "default ascending layers/ties")
expect(P.ordered(entries: ordinary, prioritizedKeys: ["wake", "earlier"]).map(\.key)
       == ["later", "planned", "session", "wake", "earlier"], "last promoted highest, above sessions")
expect(P.ordered(entries: ordinary, prioritizedKeys: ["wake", "earlier", "missing", "wake"]).last?.key
       == "wake", "last duplicate promotion wins; unknown key harmless")
let tied = [entry("z"), entry("b"), entry("a")]
for offset in 0..<tied.count {
    let rotated = Array(tied.dropFirst(offset)) + Array(tied.prefix(offset))
    expect(P.ordered(entries: rotated, prioritizedKeys: []).map(\.key) == ["a", "b", "z"], "deterministic key ties")
}
var duplicate = entry("a"); duplicate.isConservativeWakeWindow = true
expect(P.ordered(entries: [duplicate, entry("a")], prioritizedKeys: []).first!.isConservativeWakeWindow,
       "identical entries stable")
let occurrence = entry("a", start: date(2026, 10, 4), end: date(2026, 10, 4, 1))
expect(P.ordered(entries: [occurrence, entry("a")], prioritizedKeys: ["a"]).first!.start == date(2026, 10, 3, 10),
       "same promoted rule occurrences chronological")

// Half-open windows and conservative token/category/app-site overlap.
let block = entry("block")
let allow = entry("allow", .session, .unblock)
var findings = P.overlaps(entries: [allow, block], prioritizedKeys: [])
expect(findings.count == 1 && findings[0].scope == .knownOverlap && findings[0].winnerKey == "allow",
       "shared token block/unblock conflict has default winner")
findings = P.conflicts(entries: [allow, block], prioritizedKeys: ["block"])
expect(findings.count == 1 && findings[0].winnerKey == "block" && findings[0].higherPriorityIsPromoted,
       "explicit chosen priority wins pairwise")
expect(findings[0].label.contains("chosen priority"), "concise priority label")
let disjoint = entry("other", .session, .unblock, selection(["b"]))
findings = P.overlaps(entries: [block, disjoint], prioritizedKeys: [])
expect(findings.count == 1 && findings[0].scope == .disjoint && !findings[0].isPotentialConflict,
       "time overlap distinguished from disjoint explicit apps")
let category = entry("category", .recurring, .blockSelected, selection(categories: ["cat-a"]))
let otherCategory = entry("category-b", .session, .unblock, selection(categories: ["cat-b"]))
expect(P.conflicts(entries: [category, otherCategory], prioritizedKeys: []).first?.scope == .possibleOverlap,
       "distinct opaque categories never declared disjoint")
expect(P.conflicts(entries: [category, disjoint], prioritizedKeys: []).first?.scope == .possibleOverlap,
       "category/app membership unknown")
let site = entry("site", .session, .unblock, selection(sites: ["site-a"]))
expect(P.conflicts(entries: [block, site], prioritizedKeys: []).first?.scope == .possibleOverlap,
       "app/site attribution unknown")
expect(P.conflicts(entries: [category, site], prioritizedKeys: []).first?.scope == .possibleOverlap,
       "category/site membership unknown")
expect(P.conflicts(entries: [block, entry("empty", .session, .unblock, selection())], prioritizedKeys: []).isEmpty,
       "empty selected scope is not global")
expect(P.conflicts(entries: [block, entry("free", .session, .free, selection())], prioritizedKeys: []).count == 1,
       "empty free selection still global")
expect(P.conflicts(entries: [block, entry("all", .recurring, .blockAllExcept, selection(["a"]))], prioritizedKeys: []).count == 1,
       "all-except policy includes its allow decisions")
expect(P.conflicts(entries: [entry("all", .recurring, .blockAllExcept, selection()),
    entry("all-b", .recurring, .blockAllExcept, selection(["b"]))], prioritizedKeys: []).count == 1,
       "different all-except policies conflict")
expect(P.conflicts(entries: [block, entry("block-b")], prioritizedKeys: []).isEmpty, "same block effect not a conflict")
expect(P.overlaps(entries: [block, entry("touch", start: block.end, end: block.end.addingTimeInterval(60))],
                  prioritizedKeys: []).isEmpty, "touching endpoints are not overlap")
expect(P.overlaps(entries: [block, entry("zero", start: block.start, end: block.start)], prioritizedKeys: []).isEmpty,
       "invalid empty interval omitted")
expect(P.overlaps(entries: [block, block], prioritizedKeys: []).isEmpty, "same rule not self conflict")

// Real recurrence helpers: overnight belongs to Friday even after midnight.
var state = LatchState()
var friday = BlockSchedule(name: "Friday overnight", mode: .blockSelected, selection: selection(["a"]),
    startMinutes: 22 * 60, endMinutes: 2 * 60, recurrence: .weekly([6]), addedAt: date(2026, 10, 1))
state.schedules = [friday]
let saturday = date(2026, 10, 3, 1)
var projected = P.entries(state: state, from: saturday, through: date(2026, 10, 5))
expect(projected.count == 1 && projected[0].start == date(2026, 10, 2, 22)
    && projected[0].end == date(2026, 10, 3, 2), "actual Friday overnight occurrence from previous anchor")
expect(friday.isActive(at: saturday) && !friday.isActive(at: date(2026, 10, 4, 1)), "actual helper anchoring fixture")
state.schedules[0].recurrence = .monthlyDay(2)
expect(P.entries(state: state, from: saturday, through: date(2026, 10, 4)).count == 1, "monthly date overnight")
state.schedules[0].recurrence = .monthlyOrdinal(weekday: 6, ordinal: 1)
expect(P.entries(state: state, from: saturday, through: date(2026, 10, 4)).count == 1, "monthly ordinal overnight")
state.schedules[0].recurrence = .monthlyDay(31)
expect(P.entries(state: state, from: saturday, through: date(2026, 10, 4)).isEmpty, "nonmatching date absent")
expect(P.configuredKeys(state: state).contains(key("schedule", friday.id)), "configured keys not limited to next week")
state.schedules[0].recurrence = .daily
expect(P.entries(state: state, from: saturday, through: date(2026, 11, 1)).count == 8, "bounded seven-day horizon plus ongoing overnight")
state.schedules[0].endMinutes = state.schedules[0].startMinutes
expect(P.entries(state: state, from: saturday, through: date(2026, 10, 4)).isEmpty, "equal endpoints not all-day window")
expect(P.entries(state: state, from: saturday, through: saturday).isEmpty, "empty horizon")

// Calendar arithmetic across the spring DST transition (no 86400-second anchor).
state.schedules = [BlockSchedule(name: "DST", mode: .blockSelected, selection: selection(["a"]),
    startMinutes: 22 * 60, endMinutes: 4 * 60, recurrence: .weekly([7]))]
projected = P.entries(state: state, from: date(2026, 3, 8, 1), through: date(2026, 3, 8, 5))
expect(projected.count == 1 && projected[0].end.timeIntervalSince(projected[0].start) == 5 * 3600,
       "overnight DST uses calendar days")

// Recurring blocks/exemptions share addedAt ranking; one-offs keep array order.
state = LatchState()
let early = ExemptSchedule(name: "Early free", startMinutes: 600, endMinutes: 720, addedAt: date(2026, 10, 1))
let late = BlockSchedule(name: "Late block", mode: .blockSelected, selection: selection(["a"]),
    startMinutes: 600, endMinutes: 720, addedAt: date(2026, 10, 2))
state.exemptions = [early]; state.schedules = [late]
state.planned = [PlannedWindow(name: "Plan", kind: .free, selection: selection(),
    startsAt: date(2026, 10, 3, 10), endsAt: date(2026, 10, 3, 12)),
    PlannedWindow(name: "Past", kind: .free, selection: selection(),
    startsAt: date(2026, 10, 2), endsAt: date(2026, 10, 3))]
state.sessions = [BlockSession(name: "Session", kind: .unblock, selection: selection(["a"]),
    startedAt: date(2026, 10, 3, 9), endsAt: date(2026, 10, 3, 12))]
projected = P.entries(state: state, from: date(2026, 10, 3, 10), through: date(2026, 10, 3, 11))
expect(projected.map(\.name) == ["Early free", "Late block", "Plan", "Session"], "shared recurrence addedAt and layers")
state.prioritizedScheduleKeys = [key("exemption", early.id)]
expect(P.entries(state: state, from: date(2026, 10, 3, 10), through: date(2026, 10, 3, 11)).last?.name == "Early free",
       "entries uses only state priority contract")

// Independent wake/sleep scope resolution, fallback exclusions and cap overrides.
state = LatchState()
var limit = AppLimit(name: "Limit", selection: selection(["limit-app"], sites: ["limit-site"]),
    minutesPerDay: 10, wakeDelayMinutes: 30)
state.limits = [limit]
var explicit = DayNightGroup(); explicit.name = "Explicit"
explicit.scope.limitIDs = [limit.id]
explicit.wakeStartMinutes = 360; explicit.wakeLatestMinutes = 480
explicit.sleepEnabled = true; explicit.weekdays = [6]
explicit.weekdayWakeTimings[7] = WakeDayTiming(startMinutes: 540, waitMinutes: 0)
var sleepOnly = DayNightGroup(); sleepOnly.name = "Sleep-only"; sleepOnly.wakeEnabled = false
sleepOnly.sleepEnabled = true; sleepOnly.scope.selection = selection(["sleep-app"])
var fallback = DayNightGroup(); fallback.name = "Other"
fallback.scope.mode = .allOtherApps; fallback.scope.selection = selection(["exception"])
fallback.sleepEnabled = true
state.dayNightGroups = [explicit, sleepOnly, fallback]
state.wakeRule.enabled = true; state.wakeRule.startHour = 6; state.wakeRule.latestMinutes = 1410
state.wakeRule.scope.mode = .blockGroups; state.wakeRule.scope.groupIDs = [limit.id]
state.sleepRule.enabled = true; state.sleepRule.scope.mode = .blockAllExcept
state.sleepRule.scope.excludedLimitIDs = [limit.id]; state.sleepRule.weekdays = [6]
projected = P.entries(state: state, from: date(2026, 10, 2), through: date(2026, 10, 3, 12))
let groupKey = key("day-night", explicit.id), fallbackKey = key("day-night", fallback.id)
let groupWake = projected.first { $0.key == groupKey && $0.isConservativeWakeWindow }!
expect(groupWake.start == date(2026, 10, 2, 6) && groupWake.end == date(2026, 10, 2, 8), "named wake start to cap, not wait")
let groupSleep = projected.first { $0.key == groupKey && !$0.isConservativeWakeWindow }!
expect(groupSleep.start == date(2026, 10, 2, 22) && groupSleep.end == date(2026, 10, 3, 9),
       "sleep evening weekday and following morning override")
let fallbackWake = projected.first { $0.key == fallbackKey && $0.isConservativeWakeWindow }!
let fallbackSleep = projected.first { $0.key == fallbackKey && !$0.isConservativeWakeWindow }!
expect(fallbackWake.kind == .blockAllExcept && fallbackWake.selection.applicationTokens == ["exception", "limit-app"],
       "fallback wake excludes explicitly wake-timed groups")
expect(fallbackWake.selection.webDomainTokens == ["limit-site"], "fallback automatically exempts explicit sites")
expect(fallbackSleep.selection.applicationTokens == ["exception", "limit-app", "sleep-app"],
       "fallback sleep excludes sleep-timed groups separately")
let legacy = projected.first { $0.key == key("limit-wake", limit.id) }!
expect(legacy.start == date(2026, 10, 2) && legacy.end == date(2026, 10, 3), "legacy untapped gate midnight to midnight")
expect(projected.first { $0.key == "global-wake" }?.end == date(2026, 10, 2, 23, 30), "global 23:30 cutoff")
expect(projected.first { $0.key == "global-wake" }?.selection.applicationTokens == ["limit-app"], "global selected groups resolved")
expect(projected.first { $0.key == "global-sleep" }?.selection.webDomainTokens == ["limit-site"], "global except excluded groups union")
limit.wakeSchedule = LimitWakeSchedule(startMinutes: 60, weekdays: [6],
    dayTimings: [6: WakeDayTiming(startMinutes: 120, waitMinutes: 5, latestMinutes: 180)], latestMinutes: 300)
state.limits = [limit]
projected = P.entries(state: state, from: date(2026, 10, 2), through: date(2026, 10, 3))
expect(projected.first { $0.key == key("limit-wake", limit.id) }?.end == date(2026, 10, 2, 3), "weekday cap overrides default")
state.limits[0].wakeSchedule!.dayTimings[6]!.latestMinutes = nil
expect(P.entries(state: state, from: date(2026, 10, 2), through: date(2026, 10, 3))
    .first { $0.key == key("limit-wake", limit.id) }?.end == date(2026, 10, 3), "explicit nil weekday cap means no cap")
state.limits[0].wakeSchedule!.dayTimings[6]!.latestMinutes = 1411
expect(!P.entries(state: state, from: date(2026, 10, 2), through: date(2026, 10, 3))
    .contains { $0.key == key("limit-wake", limit.id) }, "invalid cap beyond 23:30 not projected")
state.limits[0].wakeSchedule!.dayTimings[6]!.latestMinutes = 120
expect(!P.entries(state: state, from: date(2026, 10, 2), through: date(2026, 10, 3))
    .contains { $0.key == key("limit-wake", limit.id) }, "cap must be strictly after start")
let wakeConflict = P.conflicts(entries: [groupWake, entry("free", .session, .free, selection(),
    start: groupWake.start, end: groupWake.end)], prioritizedKeys: []).first!
expect(wakeConflict.isConservativeWakeWindow && wakeConflict.label.contains("estimate"), "wake uncertainty retained in conflicts")

// Lookup APIs cover all eight key families and fail safely on stale keys.
state.schedules = [late]; state.exemptions = [early]
state.planned = [PlannedWindow(name: "Plan", kind: .free, selection: selection(), startsAt: saturday, endsAt: saturday)]
state.sessions = [BlockSession(name: "Session", kind: .free, selection: selection(), startedAt: saturday, endsAt: saturday)]
let configured = P.configuredKeys(state: state)
for ruleKey in [groupKey, key("limit-wake", limit.id), "global-wake", "global-sleep", key("schedule", late.id),
                key("exemption", early.id), key("planned", state.planned[0].id), key("session", state.sessions[0].id)] {
    expect(configured.contains(ruleKey) && P.displayName(key: ruleKey, state: state) != nil, "configured lookup \(ruleKey)")
}
expect(P.displayName(key: groupKey, state: state) == "Explicit", "display name current user label")
expect(P.displayName(key: "missing", state: state) == nil, "stale display name nil")
expect(P.displayName(key: "global-wake", state: state) == "Wake up"
    && P.displayName(key: "global-sleep", state: state) == "Sleep", "global display names are pure localization keys")
state.wakeRule.enabled = false; state.sleepRule.enabled = false; state.limits[0].wakeDelayMinutes = nil
expect(!P.configuredKeys(state: state).contains("global-wake") && !P.configuredKeys(state: state).contains("global-sleep")
    && !P.configuredKeys(state: state).contains(key("limit-wake", limit.id)), "disabled gates removed from configured keys")

// Root can reuse these pure scope helpers to construct real active entries.
var categories = AppLimit(name: "Opaque", selection: selection(["shared"], categories: ["cat-a"], sites: ["shared-site"]), minutesPerDay: 5)
var boundary = BoundaryBlockScope()
boundary.mode = .blockGroups; boundary.selection = selection(["ignored"])
boundary.groupIDs = [limit.id, categories.id]; boundary.excludedLimitIDs = [limit.id]
var resolved = P.boundaryScope(boundary, limits: [limit, categories])
expect(resolved.kind == .blockSelected && resolved.selection.applicationTokens == ["shared"], "group scope excludes selected limit IDs")
expect(resolved.selection.categoryTokens == ["cat-a"] && resolved.selection.webDomainTokens == ["shared-site"],
       "group scope includes category and site tokens")
boundary.mode = .blockSelected
boundary.selection = selection(["shared", "retained"], categories: ["cat-a", "cat-b"], sites: ["shared-site", "retained-site"])
boundary.excludedLimitIDs = [categories.id]
resolved = P.boundaryScope(boundary, limits: [limit, categories])
expect(resolved.selection.applicationTokens == ["retained"] && resolved.selection.categoryTokens == ["cat-b"]
    && resolved.selection.webDomainTokens == ["retained-site"], "selected scope subtracts exact excluded tokens only")
boundary.mode = .blockAllExcept; boundary.selection = selection(["exception"])
resolved = P.boundaryScope(boundary, limits: [categories])
expect(resolved.kind == .blockAllExcept && resolved.selection.applicationTokens == ["exception", "shared"]
    && resolved.selection.webDomainTokens == ["shared-site"] && resolved.selection.categoryTokens.isEmpty,
       "all-except group exclusions are representable app/site tokens only")
var unresolvedGroup = DayNightGroup(); unresolvedGroup.name = "Category timing"
unresolvedGroup.scope.selection = selection(categories: ["cat-a"])
state.dayNightGroups = [fallback, explicit, unresolvedGroup]
state.limits = [limit]
expect(P.dayNightSelection(explicit, wake: true, state: state).applicationTokens == ["limit-app"],
       "public explicit scope helper resolves limits")
expect(P.dayNightSelection(fallback, wake: true, state: state).categoryTokens.isEmpty,
       "fallback never invents category-wide exceptions")
let uncertainEntries = P.entries(state: state, from: date(2026, 10, 2, 6), through: date(2026, 10, 2, 7))
let categoryEntry = uncertainEntries.first { $0.key == key("day-night", unresolvedGroup.id) }!
expect(P.conflicts(entries: [categoryEntry, entry("unblock-app", .session, .unblock, selection(["unknown-app"]),
    start: categoryEntry.start, end: categoryEntry.end)], prioritizedKeys: []).first?.scope == .possibleOverlap,
       "projected opaque categories retain potential conflicts")

// Equal addedAt data (including migrated distantPast) has deterministic key order.
state = LatchState()
var tieBlock = late; var tieFree = early
tieBlock.addedAt = .distantPast; tieFree.addedAt = .distantPast
state.schedules = [tieBlock]; state.exemptions = [tieFree]
let tieProjection = P.entries(state: state, from: date(2026, 10, 3, 10), through: date(2026, 10, 3, 11))
expect(tieProjection.map(\.key) == [key("exemption", tieFree.id), key("schedule", tieBlock.id)].sorted(),
       "migrated equal addedAt order deterministic across recurring families")
state = LatchState(); state.wakeRule.enabled = true
state.wakeRule.latestMinutes = 600; state.wakeRule.weekdayLatestMinutes = [6: 480]
let weekdayProjection = P.entries(state: state, from: date(2026, 10, 2), through: date(2026, 10, 4))
expect(weekdayProjection.first { $0.key == "global-wake" }?.end == date(2026, 10, 2, 8),
       "global inspector uses actual weekday cutoff helper")
expect(weekdayProjection.last { $0.key == "global-wake" }?.end == date(2026, 10, 3, 10),
       "global inspector unspecified weekday retains default cutoff")

// Compile and exercise the root's ACTUAL ScheduleShieldPlan, without rewriting
// its apply/build algorithms. Closures represent real statuses at this instant.
let precedenceAssertions = assertions
func shield(_ state: LatchState, baseline: FamilyActivitySelection = selection(),
            at: Date = date(2026, 10, 3, 10), globalWake: Bool = false,
            limitWake: Set<UUID> = [], groupWake: Set<UUID> = []) -> ScheduleShieldPlan {
    ScheduleShieldPlan.build(state: state, baseline: baseline, at: at,
        globalWakeActive: globalWake,
        limitWakeActive: { limitWake.contains($0.id) },
        groupWakeActive: { groupWake.contains($0.id) })
}
func emptyPlan(_ plan: ScheduleShieldPlan) -> Bool {
    plan.blocked == selection() && plan.allowed == nil && plan.freed == selection() && plan.categoryShields.isEmpty
}
func cohort(_ plan: ScheduleShieldPlan, _ category: String) -> FamilyActivitySelection? {
    plan.categoryShields.first { $0.categoryTokens.contains(category) }
}
// Explicit fixture membership belongs only to the test oracle. Production
// correctly never tries to infer opaque category membership from token IDs.
func categoryBlocksApp(_ plan: ScheduleShieldPlan, _ app: String, memberships: Set<String>) -> Bool {
    plan.categoryShields.contains { !$0.categoryTokens.isDisjoint(with: memberships) && !$0.applicationTokens.contains(app) }
}
func categoryBlocksSite(_ plan: ScheduleShieldPlan, _ site: String, memberships: Set<String>) -> Bool {
    plan.categoryShields.contains { !$0.categoryTokens.isDisjoint(with: memberships) && !$0.webDomainTokens.contains(site) }
}
let spent = selection(["spent-app", "spent-other"], categories: ["spent-category"], sites: ["spent-site"])
var composition = LatchState()
composition.schedules = [BlockSchedule(name: "Allow spent", mode: .blockAllExcept, selection: spent,
    startMinutes: 0, endMinutes: 23 * 60 + 30)]
var plan = shield(composition, baseline: spent)
expect(plan.blocked == spent, "spent apps/sites/categories survive allowlist")
expect(plan.allowed?.applicationTokens == spent.applicationTokens, "all-except allowed policy coexists with spent baseline")
composition.wakeRule.enabled = true; composition.wakeRule.startHour = 6; composition.wakeRule.latestMinutes = 600
composition.wakeRule.scope.selection = selection(["wake-app"], sites: ["wake-site"])
let capTiming = WakeDayTiming(startMinutes: 360, waitMinutes: 120, latestMinutes: 600)
plan = shield(composition, baseline: spent, at: date(2026, 10, 3, 9, 59),
    globalWake: !capTiming.ceilingReached(on: date(2026, 10, 3, 9, 59)))
expect(plan.blocked.applicationTokens.contains("wake-app") && plan.blocked.webDomainTokens.contains("wake-site"),
       "active wake layered above spent baseline")
expect(plan.blocked.categoryTokens == ["spent-category"], "active wake preserves spent category")
plan = shield(composition, baseline: spent, globalWake: !capTiming.ceilingReached(on: date(2026, 10, 3, 10)))
expect(plan.blocked == spent, "wake cutoff clears wake only; spent baseline survives exactly at cutoff")
expect(plan.allowed != nil && plan.freed == selection(), "cutoff never grants an unblock exception")

// Explicit higher free/unblock deliberately lifts daily usage and wake scopes.
composition.sessions = [BlockSession(name: "Free", kind: .free, selection: selection(),
    startedAt: date(2026, 10, 3, 9), endsAt: date(2026, 10, 3, 12))]
expect(emptyPlan(shield(composition, baseline: spent, globalWake: true)), "default higher free session clears wake and spent baseline")
composition.sessions[0].kind = .unblock
composition.sessions[0].selection = selection(["spent-app", "wake-app"], categories: ["spent-category"], sites: ["spent-site", "wake-site"])
plan = shield(composition, baseline: spent, globalWake: true)
expect(plan.blocked.applicationTokens == ["spent-other"], "higher unblock lifts only selected spent/wake apps")
expect(plan.blocked.categoryTokens.isEmpty && plan.blocked.webDomainTokens.isEmpty,
       "higher category/site unblock lifts those exact baseline/wake tokens")
expect(plan.freed.applicationTokens == ["spent-app", "wake-app"]
    && plan.freed.webDomainTokens == ["spent-site", "wake-site"], "higher unblock records app/site exceptions")
expect(plan.allowed!.applicationTokens.contains("wake-app") && plan.allowed!.webDomainTokens.contains("wake-site"),
       "unblock adds exceptions to an existing all-except policy")

// Promoting only wake after free restores only its scope, not unrelated usage.
composition.sessions[0].kind = .free
composition.prioritizedScheduleKeys = ["global-wake"]
plan = shield(composition, baseline: spent, globalWake: true)
expect(plan.blocked.applicationTokens == ["wake-app"] && plan.blocked.webDomainTokens == ["wake-site"],
       "promoted wake blocks its selected apps/sites after free")
expect(!plan.blocked.applicationTokens.contains("spent-other") && plan.blocked.categoryTokens.isEmpty && plan.allowed == nil,
       "unrelated free scope survives promoted selected wake")
composition.prioritizedScheduleKeys = []
expect(emptyPlan(shield(composition, baseline: spent, globalWake: true)), "restoring wake default restores free session effect")

// Status-injected limit/named wake still applies even if inspector eligibility
// changed during an existing wait. Never use conservative inspection to decide.
composition = LatchState()
var statusLimit = AppLimit(name: "Existing wait", selection: selection(["limit-wait"]), minutesPerDay: 10,
    wakeDelayMinutes: 30, wakeSchedule: LimitWakeSchedule(startMinutes: 1200, weekdays: [6]))
var statusGroup = DayNightGroup(); statusGroup.name = "Named wait"; statusGroup.weekdays = [6]
statusGroup.wakeStartMinutes = 1200; statusGroup.scope.selection = selection(["group-wait"])
composition.limits = [statusLimit]; composition.dayNightGroups = [statusGroup]
plan = shield(composition, baseline: spent, limitWake: [statusLimit.id], groupWake: [statusGroup.id])
expect(plan.blocked.applicationTokens.isSuperset(of: ["limit-wait", "group-wait", "spent-app"]),
       "real statuses preserve waits despite edited weekdays/starts")
expect(shield(composition).blocked == selection(), "inactive statuses do not enforce conservative future wake windows")

// Per-rule promotion/restoration, repeated builds and last-promoted winner.
composition = LatchState()
let blockA = BlockSchedule(name: "A", mode: .blockSelected, selection: selection(["a"]),
    startMinutes: 600, endMinutes: 720, addedAt: date(2026, 10, 1))
let blockB = BlockSchedule(name: "B", mode: .blockSelected, selection: selection(["b"]),
    startMinutes: 600, endMinutes: 720, addedAt: date(2026, 10, 1))
composition.schedules = [blockB, blockA]
composition.sessions = [BlockSession(name: "Free both", kind: .free, selection: selection(),
    startedAt: date(2026, 10, 3, 9), endsAt: date(2026, 10, 3, 12))]
let blockAKey = key("schedule", blockA.id), blockBKey = key("schedule", blockB.id)
let freeKey = key("session", composition.sessions[0].id)
expect(emptyPlan(shield(composition, baseline: spent)), "default free beats both recurring blocks")
composition.prioritizedScheduleKeys = [blockAKey]
expect(shield(composition, baseline: spent).blocked.applicationTokens == ["a"], "promotion applies only A, not B or baseline")
composition.prioritizedScheduleKeys = [blockBKey]
expect(shield(composition, baseline: spent).blocked.applicationTokens == ["b"], "switching promotion restores A default")
composition.prioritizedScheduleKeys = [blockAKey, freeKey]
expect(emptyPlan(shield(composition, baseline: spent)), "last promoted free beats previously promoted block")
composition.prioritizedScheduleKeys = [freeKey, blockAKey]
expect(shield(composition, baseline: spent).blocked.applicationTokens == ["a"], "last promoted block beats promoted free")
composition.prioritizedScheduleKeys = []
expect(emptyPlan(shield(composition, baseline: spent)) && emptyPlan(shield(composition, baseline: spent)),
       "restoration/repeated build is idempotent; no hidden promotion state")

// Higher category blocks reset only that category's exceptions. An unrelated
// spent category retains its deliberately granted app AND website exceptions.
composition = LatchState()
let higherCategory = BlockSchedule(name: "Category", mode: .blockSelected,
    selection: selection(categories: ["new-category"]), startMinutes: 600, endMinutes: 720)
composition.schedules = [higherCategory, BlockSchedule(name: "Allowlist", mode: .blockAllExcept,
    selection: selection(), startMinutes: 600, endMinutes: 720)]
composition.sessions = [BlockSession(name: "Lower unblock", kind: .unblock,
    selection: selection(["freed-app"], sites: ["freed-site"]), startedAt: date(2026, 10, 3, 9), endsAt: date(2026, 10, 3, 12))]
let categoryBaseline = selection(categories: ["spent-category"])
plan = shield(composition, baseline: categoryBaseline)
expect(plan.freed.applicationTokens == ["freed-app"] && plan.freed.webDomainTokens == ["freed-site"],
       "default higher unblock creates category exceptions")
composition.prioritizedScheduleKeys = [key("schedule", higherCategory.id)]
plan = shield(composition, baseline: categoryBaseline)
expect(plan.blocked.categoryTokens == ["spent-category", "new-category"], "promoted category keeps daily and new category restrictions")
expect(cohort(plan, "spent-category")?.applicationTokens == ["freed-app"]
    && cohort(plan, "spent-category")?.webDomainTokens == ["freed-site"],
       "unrelated promoted category preserves spent-category app/site exceptions")
expect(cohort(plan, "new-category")?.applicationTokens.isEmpty == true
    && cohort(plan, "new-category")?.webDomainTokens.isEmpty == true,
       "promoted new category has no lower unblock exceptions")
expect(plan.freed.applicationTokens == ["freed-app"] && plan.freed.webDomainTokens == ["freed-site"],
       "global freed tracking is not a category-rendering exception set")
expect(plan.allowed != nil, "category restrictions coexist with all-except for controller auxiliary-store path")

// Counterexample: spent C + unblock A + promoted D. A remains allowed by C,
// but D still blocks A if it also belongs to D. Website behavior is identical.
composition = LatchState()
let categoryD = BlockSchedule(name: "D", mode: .blockSelected, selection: selection(categories: ["D"]),
    startMinutes: 600, endMinutes: 720)
composition.schedules = [categoryD]
composition.sessions = [BlockSession(name: "A", kind: .unblock, selection: selection(["A"], sites: ["site-A"]),
    startedAt: date(2026, 10, 3, 9), endsAt: date(2026, 10, 3, 12))]
composition.prioritizedScheduleKeys = [key("schedule", categoryD.id)]
let spentC = selection(categories: ["C"])
plan = shield(composition, baseline: spentC)
expect(!categoryBlocksApp(plan, "A", memberships: ["C"]), "A in C remains allowed after unrelated D promotion")
expect(categoryBlocksApp(plan, "A", memberships: ["C", "D"]), "A also in D is blocked by new D cohort")
expect(!categoryBlocksSite(plan, "site-A", memberships: ["C"]), "website in C retains lower unblock")
expect(categoryBlocksSite(plan, "site-A", memberships: ["C", "D"]), "website also in D blocked despite global freed tracking")
expect(plan.categoryShields.count == 2, "different exception sets remain separate cohorts")
expect(cohort(plan, "C")?.applicationTokens == ["A"] && cohort(plan, "D")?.applicationTokens.isEmpty == true,
       "C and D exceptions are category-specific")
let rebuilt = shield(composition, baseline: spentC)
expect(rebuilt.categoryShields == plan.categoryShields && rebuilt.blocked == plan.blocked && rebuilt.freed == plan.freed,
       "repeated category build is deterministic without accumulating cohorts")
composition.prioritizedScheduleKeys = []
plan = shield(composition, baseline: spentC)
expect(plan.categoryShields.count == 1 && plan.categoryShields[0].categoryTokens == ["C", "D"],
       "higher unblock grants same exceptions to both categories and equal cohorts merge")
expect(!categoryBlocksApp(plan, "A", memberships: ["C", "D"])
    && !categoryBlocksSite(plan, "site-A", memberships: ["C", "D"]), "restoring priority deliberately lifts both categories")
composition.sessions[0].kind = .free
expect(emptyPlan(shield(composition, baseline: spentC)) && emptyPlan(shield(composition, baseline: spentC)),
       "free clears category cohorts on every fresh build")
composition.prioritizedScheduleKeys = [key("schedule", categoryD.id)]
plan = shield(composition, baseline: spentC)
expect(plan.categoryShields.count == 1 && cohort(plan, "D")?.categoryTokens == ["D"] && cohort(plan, "C") == nil,
       "promoted D after free restores only D, never spent C")

// Exact same-category reset must revoke C exceptions, but preserve E. Explicit
// app/site blocks revoke only those tokens in every existing cohort.
var cohortPlan = ScheduleShieldPlan(blocked: selection(categories: ["C", "E"]))
expect(cohortPlan.categoryShields.count == 1 && cohortPlan.categoryShields[0].applicationTokens.isEmpty
    && cohortPlan.categoryShields[0].webDomainTokens.isEmpty, "baseline cohorts have no exceptions")
cohortPlan.apply(entry("unblock-A-B", .session, .unblock, selection(["A", "B"], sites: ["site-A", "site-B"])))
cohortPlan.apply(entry("reset-C", .recurring, .blockSelected, selection(categories: ["C"])))
expect(cohort(cohortPlan, "C")?.applicationTokens.isEmpty == true && cohort(cohortPlan, "C")?.webDomainTokens.isEmpty == true,
       "same-category reset revokes app and website exceptions for C")
expect(cohort(cohortPlan, "E")?.applicationTokens == ["A", "B"] && cohort(cohortPlan, "E")?.webDomainTokens == ["site-A", "site-B"],
       "same-category reset does not revoke unrelated E exceptions")
cohortPlan.apply(entry("specific-A", .session, .blockSelected, selection(["A"], sites: ["site-A"])))
expect(cohort(cohortPlan, "E")?.applicationTokens == ["B"] && cohort(cohortPlan, "E")?.webDomainTokens == ["site-B"],
       "explicit blocks remove exact app/site exceptions, preserving unrelated tokens")
expect(cohortPlan.blocked.applicationTokens == ["A"] && cohortPlan.blocked.webDomainTokens == ["site-A"],
       "explicit app/site blocks remain restrictive outside category membership")
cohortPlan.apply(entry("unblock-C", .session, .unblock, selection(categories: ["C"])))
expect(cohort(cohortPlan, "C") == nil && cohort(cohortPlan, "E") != nil && cohortPlan.blocked.categoryTokens == ["E"],
       "category unblock removes exact selected category, not unrelated cohort")
cohortPlan.apply(entry("free", .session, .free, selection()))
expect(emptyPlan(cohortPlan), "direct free clears cohorts plus all scalar plan fields")
cohortPlan.apply(entry("new-D", .session, .blockSelected, selection(categories: ["D"])))
expect(cohortPlan.categoryShields.count == 1 && cohortPlan.categoryShields[0].categoryTokens == ["D"]
    && cohortPlan.categoryShields[0].applicationTokens.isEmpty, "reusing plan after free does not inherit prior exceptions")

// Overlapping unblocks commute when adjacent, but not across an intervening
// category block: only the later unblock may exempt the newly blocked category.
let unblockAB = entry("unblock-AB", .session, .unblock, selection(["A", "B"], sites: ["site-A", "site-B"]))
let unblockBC = entry("unblock-BC", .session, .unblock, selection(["B", "C-app"], sites: ["site-B", "site-C"]))
var orderAB = ScheduleShieldPlan(blocked: spentC), orderBA = ScheduleShieldPlan(blocked: spentC)
orderAB.apply(unblockAB); orderAB.apply(unblockBC)
orderBA.apply(unblockBC); orderBA.apply(unblockAB)
expect(orderAB.categoryShields == orderBA.categoryShields && orderAB.freed == orderBA.freed,
       "adjacent overlapping unblocks commute")
expect(cohort(orderAB, "C")?.applicationTokens == ["A", "B", "C-app"]
    && cohort(orderAB, "C")?.webDomainTokens == ["site-A", "site-B", "site-C"], "overlapping app/site exceptions union without loss")
let addD = entry("add-D", .recurring, .blockSelected, selection(categories: ["D"]))
orderAB = ScheduleShieldPlan(blocked: spentC); orderBA = ScheduleShieldPlan(blocked: spentC)
orderAB.apply(unblockAB); orderAB.apply(addD); orderAB.apply(unblockBC)
orderBA.apply(unblockBC); orderBA.apply(addD); orderBA.apply(unblockAB)
expect(cohort(orderAB, "D")?.applicationTokens == ["B", "C-app"]
    && cohort(orderAB, "D")?.webDomainTokens == ["site-B", "site-C"], "new D receives only later BC unblock")
expect(cohort(orderBA, "D")?.applicationTokens == ["A", "B"]
    && cohort(orderBA, "D")?.webDomainTokens == ["site-A", "site-B"], "reversed unblock order changes only new D exceptions")
expect(cohort(orderAB, "C") == cohort(orderBA, "C"), "existing C retains both unblocks in either order")
orderAB.apply(entry("late-unblock-A", .session, .unblock, selection(["A"], sites: ["site-A"])))
expect(orderAB.categoryShields.count == 1 && orderAB.categoryShields[0].categoryTokens == ["C", "D"],
       "cohorts merge when both app and site exception sets become equal")
var siteDistinction = ScheduleShieldPlan(blocked: spentC)
siteDistinction.apply(entry("app-and-site", .session, .unblock, selection(["A"], sites: ["site-A"])))
siteDistinction.apply(addD)
siteDistinction.apply(entry("app-only", .session, .unblock, selection(["A"])))
expect(siteDistinction.categoryShields.count == 2, "matching app exceptions alone cannot merge distinct website exceptions")

// Independently active global + named fallback all-except boundaries intersect;
// one boundary's exception must not weaken another. Named explicit groups are
// automatically excluded only for their own enabled timing boundary.
composition = LatchState()
composition.wakeRule.enabled = true; composition.wakeRule.scope.mode = .blockAllExcept
composition.wakeRule.scope.selection = selection(["shared", "global-only"], sites: ["shared-site", "global-site"])
var allOther = DayNightGroup(); allOther.name = "Fallback"; allOther.scope.mode = .allOtherApps
allOther.scope.selection = selection(["shared", "fallback-only"], sites: ["shared-site", "fallback-site"])
composition.dayNightGroups = [allOther]
plan = shield(composition, baseline: spent, globalWake: true, groupWake: [allOther.id])
expect(plan.allowed!.applicationTokens == ["shared"] && plan.allowed!.webDomainTokens == ["shared-site"],
       "independent boundary fallback exceptions intersect")
expect(plan.blocked == spent, "fallback intersection never clears spent baseline")
composition.prioritizedScheduleKeys = ["global-wake"]
expect(shield(composition, globalWake: true, groupWake: [allOther.id]).allowed!.applicationTokens == ["shared"],
       "boundary promotion retains independently restrictive intersection")
composition.prioritizedScheduleKeys = [key("day-night", allOther.id)]
expect(shield(composition, globalWake: true, groupWake: [allOther.id]).allowed!.webDomainTokens == ["shared-site"],
       "opposite boundary promotion preserves site intersection")
var independent = DayNightGroup(); independent.name = "Independent"; independent.scope.selection = selection(["explicit-app"])
composition.dayNightGroups.append(independent)
composition.wakeRule.enabled = false; composition.prioritizedScheduleKeys = []
plan = shield(composition, groupWake: [allOther.id])
expect(plan.allowed!.applicationTokens.contains("explicit-app") && !plan.blocked.applicationTokens.contains("explicit-app"),
       "released explicit wake group exempted from fallback's longer wait")
plan = shield(composition, groupWake: [allOther.id, independent.id])
expect(plan.blocked.applicationTokens == ["explicit-app"] && plan.allowed!.applicationTokens.contains("explicit-app"),
       "independent active selected wake blocks despite fallback exception")
composition.sessions = [BlockSession(name: "Boundary unblock", kind: .unblock, selection: selection(["lifted"]),
    startedAt: date(2026, 10, 3, 9), endsAt: date(2026, 10, 3, 12))]
plan = shield(composition, groupWake: [allOther.id, independent.id])
expect(plan.allowed!.applicationTokens.contains("lifted"), "higher unblock deliberately expands boundary allowlists")

// Build uses actual overnight weekday recurrence, not today's weekday alone.
composition = LatchState()
composition.schedules = [friday]
expect(shield(composition, at: date(2026, 10, 2, 21, 59)).blocked.applicationTokens.isEmpty, "overnight inactive before Friday start")
expect(shield(composition, at: date(2026, 10, 2, 22)).blocked.applicationTokens == ["a"], "overnight active at Friday start")
expect(shield(composition, at: date(2026, 10, 3, 1, 59)).blocked.applicationTokens == ["a"], "Saturday continuation anchored to Friday")
expect(shield(composition, at: date(2026, 10, 3, 2)).blocked.applicationTokens.isEmpty, "overnight ends half-open exactly at cutoff")
expect(shield(composition, at: date(2026, 10, 4, 1)).blocked.applicationTokens.isEmpty, "Sunday not an extra weekday overnight")
composition.exemptions = [ExemptSchedule(name: "Friday free", startMinutes: 22 * 60, endMinutes: 2 * 60,
    recurrence: .weekly([6]), addedAt: friday.addedAt.addingTimeInterval(1))]
expect(emptyPlan(shield(composition, baseline: spent, at: saturday)), "newer Friday free lifts overnight block and baseline on Saturday")
expect(shield(composition, baseline: spent, at: date(2026, 10, 4, 1)).blocked == spent,
       "nonmatching overnight free does not lift next day's baseline")

// Equal-addedAt recurrence pairs deterministically order by key across arrays.
composition = LatchState()
var equalBlock = blockA; equalBlock.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
var equalFree = ExemptSchedule(name: "Equal free", startMinutes: 600, endMinutes: 720, addedAt: equalBlock.addedAt)
equalFree.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
composition.schedules = [equalBlock]; composition.exemptions = [equalFree]
expect(shield(composition, baseline: spent).blocked.applicationTokens == ["a"],
       "stable equal-addedAt exemption key precedes schedule key, baseline freed first")
var laterFree = equalFree; laterFree.addedAt = equalBlock.addedAt.addingTimeInterval(1)
composition.exemptions = [laterFree]
expect(emptyPlan(shield(composition, baseline: spent)), "newer exemption wins over equal-key fallback order")
composition.prioritizedScheduleKeys = [key("schedule", equalBlock.id)]
expect(shield(composition, baseline: spent).blocked.applicationTokens == ["a"], "promoted equal-addedAt schedule wins after newer free")

// Regression guard: the actual window helper reevaluates local wall time during
// autumn's repeated hour. Runtime composition must not substitute the inspector's
// single absolute Date interval for this predicate.
composition = LatchState()
let repeatedRule = BlockSchedule(name: "Autumn overnight", mode: .blockSelected, selection: selection(["a"]),
    startMinutes: 22 * 60, endMinutes: 90, recurrence: .weekly([7]))
composition.schedules = [repeatedRule]
let autumnDay = date(2026, 11, 1)
let first115 = Calendar.current.date(bySettingHour: 1, minute: 15, second: 0, of: autumnDay,
    repeatedTimePolicy: .first)!
let first145 = Calendar.current.date(bySettingHour: 1, minute: 45, second: 0, of: autumnDay,
    repeatedTimePolicy: .first)!
let second115 = Calendar.current.date(bySettingHour: 1, minute: 15, second: 0, of: autumnDay,
    repeatedTimePolicy: .last)!
expect(second115.timeIntervalSince(first115) == 3600, "autumn fixture actually repeats an hour")
for (instant, label) in [(first115, "first 01:15"), (first145, "first 01:45"), (second115, "second 01:15")] {
    expect(shield(composition, at: instant).blocked.applicationTokens.contains("a") == repeatedRule.isActive(at: instant),
           "runtime must match actual recurrence predicate at autumn \(label)")
}

for failure in failures { print("FAIL: \(failure)") }
print("Schedule precedence: \(precedenceAssertions) assertions; shield plan: \(assertions - precedenceAssertions) assertions; \(failures.count) failures")
print("Actual precedence/shield-plan/models/recurrence helpers; opaque tokens adapted; wake statuses injected; no live storage/network/Apple shields")
if !failures.isEmpty { exit(1) }
'''

with tempfile.TemporaryDirectory(prefix="demora-precedence-harness-") as directory:
    source_path = Path(directory) / "main.swift"
    binary_path = Path(directory) / "checks"
    source_path.write_text("\n".join([infrastructure, models, phrases, core, shield_plan, checks]))
    subprocess.run(["xcrun", "swiftc", str(source_path), "-o", str(binary_path)], check=True)
    subprocess.run([str(binary_path)], check=True, env={**os.environ, "TZ": "America/New_York"})
