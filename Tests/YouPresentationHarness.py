#!/usr/bin/env python3
"""Compiles the real Latch/YouPresentation.swift with the real SharedModels,
TodayPresentation (ReceiptPlan) and the engine's own `overrideCapability`,
`hasOverride` and `classify`, lifted unchanged from Shared/ChangeEngine.swift.

Checks the one "Ways to skip a wait" list (docs/you-redesign.md §5.3): chip
priority, removal + edit on one item, paused contacts, pending additions,
empty and fifty items, legacy contacts without `allowed`; the permission
summary for all 2⁷ capability sets; skip eligibility against the real
`hasOverride` (non-empty exactly when it is true); where the Skip the wait
sheet opens; the add plan (Y3); and the receipt direction and commit for
override actions (add, narrow, widen, remove, pause, resume).
Presentation only: no iOS build, simulator, saved state, relay or secret.
"""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True

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


presentation = (ROOT / 'Latch/YouPresentation.swift').read_text()
code = '\n'.join(line for line in presentation.splitlines() if not line.lstrip().startswith('//'))
for forbidden in ('import SwiftUI', 'UserDefaults', 'SharedStore', 'TimeGuard', 'tr(',
                  'FileManager', 'Calendar.current', 'Date()', 'Date.now', 'ContactsRelay',
                  'EmailCodeService', 'AppModel', 'hash(', 'Keychain', 'print('):
    assert forbidden not in code, ('pure presentation must not use', forbidden)
# The only engine call is the pure capability map.
assert set(re.findall(r'ChangeEngine\.(\w+)', code)) == {'overrideCapability'}

engine = portable((ROOT / 'Shared/ChangeEngine.swift').read_text())
lifted = '\n'.join(declaration(engine, signature) for signature in (
    'static func overrideCapability(for action: ChangeAction)',
    'static func hasOverride(for changes: [PendingChange], state: LatchState)',
    'static func classify(_ action: ChangeAction, state: LatchState)'))
score = declaration(engine, 'func mathStrictnessScore(')
models = portable((ROOT / 'Shared/SharedModels.swift').read_text())
phrases = declaration((ROOT / 'Shared/PhraseWords.swift').read_text(), 'enum PhraseWords {')
today = (ROOT / 'Latch/TodayPresentation.swift').read_text()

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
    static func now() -> Date { fatalError("You presentation must not read the guarded clock") }
}
'''

driver = r'''
import Foundation
var checks = 0
func check(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { print("FAIL: " + message); exit(1) }
    checks += 1
}
let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func change(_ action: ChangeAction, _ direction: ChangeDirection = .lenient,
            in hours: Double = 3) -> PendingChange {
    PendingChange(createdAt: t0, appliesAt: t0.addingTimeInterval(hours * 3600),
                  direction: direction, summary: "x", action: action)
}
let all = Set(OverrideCapability.allCases)
let noExtra = all.subtracting([.extraTime])
let hash = String(repeating: "a", count: 64)
func contact(_ name: String, code: String? = nil, email: String? = nil, accepted: Bool = true,
             allowed: Set<OverrideCapability> = noExtra) -> TrustedContact {
    TrustedContact(name: name, kind: email.map { .email($0) } ?? .latchUser(code: code ?? "ABC123"),
                   accepted: accepted, inviteId: UUID().uuidString, allowed: allowed)
}
func password(_ name: String, _ allowed: Set<OverrideCapability>) -> PasswordPolicy {
    PasswordPolicy(name: name, hash: hash, allowed: allowed)
}
func phrase(_ name: String, _ kind: PhraseKind, _ allowed: Set<OverrideCapability>) -> PhrasePolicy {
    PhrasePolicy(name: name, kind: kind, allowedErrors: 0, allowed: allowed)
}
let id = { (s: String) in s }

// MARK: Permission summary (§5.3, §7) — all 2⁷ subsets
let areas = OverrideCapability.allCases
var keys = Set<String>()
var recording: (String) -> String = { key in keys.insert(key); return key }
for mask in 0..<(1 << areas.count) {
    let set = Set(areas.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
    let text = SkipWayPermissionText.summary(set, translate: recording)
    check(!text.isEmpty, "summary non-empty for \(mask)")
    // Every word comes from a translation key; only ", " and " · " join them.
    let words = text.components(separatedBy: ", ").flatMap { $0.components(separatedBy: " · ") }
    check(words.allSatisfy { keys.contains($0) }, "summary uses translation keys only: \(text)")
}
check(SkipWayPermissionText.summary([], translate: id) == "Nothing", "nothing")
check(SkipWayPermissionText.summary(all, translate: id) == "Everything", "everything")
check(SkipWayPermissionText.summary(noExtra, translate: id) == "Everything except extra time", "all but extra")
check(SkipWayPermissionText.summary([.extraTime], translate: id) == "Only extra time", "only extra")
check(SkipWayPermissionText.summary([.scheduleChanges, .limitChanges, .extraTime], translate: id)
      == "Limits, schedules · extra time", "spec example")
check(SkipWayPermissionText.summary([.contactChanges, .delayChanges], translate: id)
      == "Your waits, trusted contacts", "checklist order, first capitalised")
check(Set(SkipWayPermissionText.changeAreas + [.extraTime]) == all
      && SkipWayPermissionText.changeAreas.count == 6, "checklist covers every capability once")
check(keys.count == 16, "summary keys (limits is always first): \(keys.sorted())")

// MARK: The one list (§5.3)
var config = OverridesConfig()
let alex = contact("Alex", code: "ALEX01")
let sam = contact("Sam", code: "SAM002", accepted: false)
let lee = contact("Lee", code: "LEE003")
let mo = contact("Mo", email: "mo@example.com", allowed: [.extraTime])
let work = password("Work password", [.limitChanges])
let longPhrase = phrase("Long phrase", .random(100), [.extraTime])
let mine = phrase("Mine", .custom("one two three"), [.limitChanges, .scheduleChanges])
config.contactsEnabled = true
config.contacts = [alex, sam, lee, mo]
config.passwordPolicies = [work]
config.phrasePolicies = [longPhrase, mine]

let empty = SkipWayList.make(overrides: OverridesConfig(), pending: [], unavailableCodes: [])
check(empty.isEmpty && empty.contactsSwitch == nil && !empty.collapsesKinds, "first use: empty, no switch")

var list = SkipWayList.make(overrides: config, pending: [], unavailableCodes: ["LEE003"])
check(list.rows.map(\.name) == ["Alex", "Sam", "Lee", "Mo", "Work password", "Long phrase", "Mine"],
      "contacts, passwords, phrases in stored order")
check(list.rows.map(\.kind) == [.contact, .contact, .contact, .contact, .password, .phrase, .phrase], "kinds")
check(list.rows[0].chip == nil, "active is the normal state: no chip")
check(list.rows[1].chip == .waitingToAccept, "not accepted")
check(list.rows[2].chip == .cantReach, "unreachable")
check(list.rows[3].chip == nil, "email contacts have no code to reach")
check(list.rows[5].phrase == .words(100) && list.rows[6].phrase == .custom && list.rows[4].phrase == nil,
      "phrase details")
check(list.contactsSwitch == SkipWayList.ContactsSwitch(enabled: true, pendingChangeID: nil,
                                                       pendingAppliesAt: nil), "switch row")
check(list.rows.allSatisfy { !$0.isPendingAddition }, "saved rows")

// Paused: every contact without a stronger state says Paused.
var paused = config
paused.contactsEnabled = false
list = SkipWayList.make(overrides: paused, pending: [], unavailableCodes: ["LEE003"])
check(list.rows[0].chip == .paused && list.rows[3].chip == .paused, "paused")
check(list.rows[1].chip == .waitingToAccept && list.rows[2].chip == .cantReach,
      "waiting/unreachable outrank paused")
check(list.rows[4].chip == nil, "passwords are never paused")
check(list.contactsSwitch?.enabled == false, "switch shows off")

// Chip priority: removal > change > waiting > unreachable > paused.
let narrow = change(.setContactPermissions(id: sam.id, allowed: [.limitChanges]), .stricter, in: 1)
let removeSam = change(.removeContact(id: sam.id), .stricter, in: 2)
list = SkipWayList.make(overrides: paused, pending: [narrow], unavailableCodes: [])
check(list.rows[1].chip == .changes(narrow.appliesAt) && list.rows[1].pendingChangeID == narrow.id,
      "a queued permission change outranks waiting to accept")
list = SkipWayList.make(overrides: paused, pending: [narrow, removeSam], unavailableCodes: [])
check(list.rows[1].chip == .removed(removeSam.appliesAt) && list.rows[1].pendingChangeID == removeSam.id,
      "removal outranks a change on the same item, whatever the queue order")
let lee2 = change(.removeContact(id: lee.id), .stricter)
list = SkipWayList.make(overrides: paused, pending: [lee2], unavailableCodes: ["LEE003"])
check(list.rows[2].chip == .removed(lee2.appliesAt), "removal outranks unreachable")
let pwEdit = change(.upsertPasswordPolicy(password("Work password", [.limitChanges, .extraTime])))
let pwEditSame = PasswordPolicy(id: work.id, name: "Work", hash: hash, allowed: [.extraTime])
let pwChange = change(.upsertPasswordPolicy(pwEditSame))
let phraseRemoval = change(.removePhrasePolicy(id: mine.id), .stricter)
list = SkipWayList.make(overrides: config, pending: [pwChange, phraseRemoval], unavailableCodes: [])
check(list.rows[4].chip == .changes(pwChange.appliesAt), "password secret/permission change")
check(list.rows[6].chip == .removed(phraseRemoval.appliesAt), "phrase removal")
check(list.rows[5].chip == nil, "other phrase untouched")

// Pending additions appear dimmed after the saved rows of their kind.
let newContact = contact("Kim", code: "KIM004")
let addKim = change(.addContact(newContact))
list = SkipWayList.make(overrides: config, pending: [pwEdit, addKim], unavailableCodes: [])
check(list.rows.map(\.name) == ["Alex", "Sam", "Lee", "Mo", "Kim", "Work password", "Work password",
                                "Long phrase", "Mine"], "additions follow their kind")
check(list.rows[4].isPendingAddition && list.rows[4].chip == .added(addKim.appliesAt)
      && list.rows[4].pendingChangeID == addKim.id, "added contact")
check(list.rows[6].isPendingAddition && list.rows[6].id != work.id, "a new password is an addition")
check(!list.rows[5].isPendingAddition && list.rows[5].chip == nil, "saved password unchanged")

// Only pending additions: rows and a switch, nothing usable.
var none = OverridesConfig()
list = SkipWayList.make(overrides: none, pending: [addKim], unavailableCodes: [])
check(list.rows.count == 1 && list.rows[0].isPendingAddition, "only additions")
check(list.contactsSwitch?.enabled == false, "switch shows with a waiting contact")
let turnOn = change(.setContactsOverride(enabled: true))
list = SkipWayList.make(overrides: none, pending: [addKim, turnOn], unavailableCodes: [])
check(list.contactsSwitch?.pendingChangeID == turnOn.id && list.contactsSwitch?.pendingAppliesAt == turnOn.appliesAt,
      "a queued switch change shows on its row")
none.passwordPolicies = [work]
list = SkipWayList.make(overrides: none, pending: [turnOn], unavailableCodes: [])
check(list.contactsSwitch == nil, "no contacts, no switch row")

// Fifty items: no cap; kinds collapse above 12 rows.
var many = OverridesConfig()
many.contactsEnabled = true
many.contacts = (0..<20).map { contact("C\($0)", code: String(format: "C%05d", $0)) }
many.passwordPolicies = (0..<15).map { password("P\($0)", [.limitChanges]) }
many.phrasePolicies = (0..<15).map { phrase("F\($0)", .random(50), [.extraTime]) }
list = SkipWayList.make(overrides: many, pending: [], unavailableCodes: [])
check(list.rows.count == 50 && list.collapsesKinds, "fifty rows, collapsible")
check(list.rows(of: .contact).count == 20 && list.rows(of: .password).count == 15
      && list.rows(of: .phrase).count == 15, "per kind")
let twelve = SkipWayList.make(overrides: { var c = many; c.contacts = Array(c.contacts.prefix(12));
    c.passwordPolicies = []; c.phrasePolicies = []; return c }(), pending: [], unavailableCodes: [])
check(!twelve.collapsesKinds, "twelve rows stay flat")

// Legacy contacts saved before `allowed` decode without extra time.
let legacyJSON = #"{"name":"Old","kind":{"latchUser":{"code":"OLD001"}},"accepted":true}"#
let legacy = try! JSONDecoder().decode(TrustedContact.self, from: Data(legacyJSON.utf8))
check(legacy.allowed == noExtra, "legacy decode default")
var legacyConfig = OverridesConfig()
legacyConfig.contactsEnabled = true
legacyConfig.contacts = [legacy]
list = SkipWayList.make(overrides: legacyConfig, pending: [], unavailableCodes: [])
check(SkipWayPermissionText.summary(list.rows[0].allowed, translate: id) == "Everything except extra time",
      "legacy contact reads Everything except extra time")

// Queued edit strip and pending lookup.
check(SkipWayList.queuedEdit(of: sam.id, kind: .contact, pending: [removeSam, narrow])?.allowed == [.limitChanges],
      "queued contact permissions")
check(SkipWayList.queuedEdit(of: sam.id, kind: .contact, pending: [removeSam]) == nil, "removal is not an edit")
check(SkipWayList.queuedEdit(of: work.id, kind: .password, pending: [pwChange])?.allowed == [.extraTime],
      "queued password permissions")
check(SkipWayList.queuedEdit(of: work.id, kind: .phrase, pending: [pwChange]) == nil, "kinds don't mix")
check(SkipWayList.pendingChange(for: mine.id, kind: .phrase, pending: [pwChange, phraseRemoval])?.id
      == phraseRemoval.id, "pending for phrase")
check(SkipWayList.pendingChange(for: alex.id, kind: .contact, pending: [narrow, removeSam]) == nil, "other contact")

// MARK: Eligibility (§5.13, Y4) against the real hasOverride
func state(_ overrides: OverridesConfig) -> LatchState { var s = LatchState(); s.overrides = overrides; return s }
let sample: [ChangeAction] = [
    .removeLimit(id: UUID()), .removeSchedule(id: UUID()), .endSessionEarly(id: UUID()),
    .setStrictDelay(60), .setBlockAppRemoval(false), .unlockPreventGuide, .removeContact(id: UUID()),
    .setContactsOverride(enabled: true), .addContact(newContact),
    .upsertPasswordPolicy(work), .removePasswordPolicy(id: work.id), .upsertPhrasePolicy(mine),
    .removePhrasePolicy(id: mine.id), .setContactPermissions(id: alex.id, allowed: all),
]
let configs: [OverridesConfig] = [config, paused, many, legacyConfig, OverridesConfig(), {
    var c = OverridesConfig(); c.contactsEnabled = true; c.contacts = [sam]; return c }(), {
    var c = OverridesConfig(); c.phrasePolicies = [mine]; return c }(), {
    var c = OverridesConfig(); c.passwordPolicies = [password("Only waits", [.delayChanges])]; return c }()]
var compared = 0
for overrides in configs {
    for a in sample.indices {
        for b in [nil] + sample.indices.map(Optional.some) {
            let changes = [change(sample[a])] + (b.map { [change(sample[$0])] } ?? [])
            for email in [true, false] {
                let ways = SkipWayEligibility.ways(for: changes, overrides: overrides,
                                                   unavailableCodes: ["ALEX01"], emailAvailable: email)
                check(!ways.isEmpty == ChangeEngine.hasOverride(for: changes, state: state(overrides)),
                      "eligible exactly when hasOverride: \(sample[a]) \(String(describing: b))")
                compared += 1
            }
        }
    }
}
check(SkipWayEligibility.ways(for: [], overrides: config, unavailableCodes: [], emailAvailable: true).isEmpty,
      "nothing to skip")
// Override edits are never eligible, even with every capability.
var everything = OverridesConfig()
everything.contactsEnabled = true
everything.contacts = [contact("All", allowed: all)]
everything.passwordPolicies = [password("All", all)]
everything.phrasePolicies = [phrase("All", .random(50), all)]
for action in [ChangeAction.upsertPasswordPolicy(work), .removePasswordPolicy(id: work.id),
               .upsertPhrasePolicy(mine), .removePhrasePolicy(id: mine.id),
               .setContactPermissions(id: alex.id, allowed: [])] {
    check(SkipWayEligibility.ways(for: [change(action)], overrides: everything, unavailableCodes: [],
                                  emailAvailable: true).isEmpty, "never skippable: \(action)")
    check(SkipWayEligibility.ways(for: [change(.removeLimit(id: UUID())), change(action)],
                                  overrides: everything, unavailableCodes: [], emailAvailable: true).isEmpty,
          "a bulk selection with an override edit is not skippable")
}
let limitChange = change(.removeLimit(id: UUID()))
var ways = SkipWayEligibility.ways(for: [limitChange], overrides: config, unavailableCodes: ["ALEX01"],
                                   emailAvailable: false)
check(ways.map(\.way.id) == [alex.id, lee.id, work.id, mine.id],
      "accepted contacts allowed limits, then passwords and phrases; Sam (not accepted) and Mo (extra time only) excluded")
check(ways[0].unavailable == .cantReach && ways[1].unavailable == nil, "unreachable listed but unavailable")
ways = SkipWayEligibility.ways(for: [limitChange], overrides: paused, unavailableCodes: [], emailAvailable: true)
check(!ways.contains { $0.way.kind == .contact }, "paused contacts never listed")
// Mixed-capability bulk selection: every change's capability is needed.
let scheduleChange = change(.removeSchedule(id: UUID()))
ways = SkipWayEligibility.ways(for: [limitChange, scheduleChange], overrides: config, unavailableCodes: [],
                               emailAvailable: true)
check(ways.map(\.way.id) == [alex.id, lee.id, mine.id], "the password allows limits only")
var emailOnly = OverridesConfig()
emailOnly.contactsEnabled = true
emailOnly.contacts = [contact("Mo", email: "mo@example.com")]
ways = SkipWayEligibility.ways(for: [limitChange], overrides: emailOnly, unavailableCodes: [], emailAvailable: false)
check(ways.count == 1 && ways[0].unavailable == .emailNotAvailable, "email without email is unavailable")
// Extra time requires .extraTime and a usable, unpaused contact.
let extra = SkipWayEligibility.extraTimeContacts(overrides: config, unavailableCodes: [], emailAvailable: true)
check(extra.map(\.id) == [mo.id], "only contacts allowed extra time")
check(SkipWayEligibility.extraTimeContacts(overrides: paused, unavailableCodes: [], emailAvailable: true).isEmpty,
      "paused contacts can't approve extra time")

// MARK: Where the sheet opens
let onePassword = [EligibleWay(way: .password(work), unavailable: nil)]
check(SkipWayStart.initial(onePassword, requestSent: false) == .way(.password(work)), "one way opens directly")
check(SkipWayStart.initial([EligibleWay(way: .contact(alex), unavailable: nil)], requestSent: false)
      == .contactRequest(selected: [alex.id]), "one contact opens the request")
check(SkipWayStart.initial([EligibleWay(way: .contact(alex), unavailable: .cantReach)], requestSent: false)
      == .menu, "an unusable only way shows why")
check(SkipWayStart.initial([], requestSent: false) == .none, "none eligible")
check(SkipWayStart.initial(onePassword + [EligibleWay(way: .phrase(mine), unavailable: nil)], requestSent: false)
      == .menu, "two ways: menu")
check(SkipWayStart.initial([EligibleWay(way: .contact(alex), unavailable: nil),
                            EligibleWay(way: .contact(lee), unavailable: .cantReach)] + onePassword,
                           requestSent: true) == .contactRequest(selected: [alex.id]),
      "a sent request reopens on its status")
check(SkipWayStart.start(for: .phrase(mine)) == .way(.phrase(mine)), "phrase step")

// MARK: Add plan (Y3)
let addAlex = SkipWayDraft.contact(newContact)
check(SkipWayAddPlan.actions(adding: addAlex, overrides: config, pending: []) == [.addContact(newContact)],
      "contacts on: just the contact")
check(SkipWayAddPlan.actions(adding: addAlex, overrides: paused, pending: [])
      == [.addContact(newContact), .setContactsOverride(enabled: true)], "paused: also turn on")
check(SkipWayAddPlan.actions(adding: addAlex, overrides: paused, pending: [turnOn]) == [.addContact(newContact)],
      "a switch change already waiting is not queued twice")
for draft in [SkipWayDraft.password(work), .phrase(mine)] {
    for overrides in [config, paused] {
        let actions = SkipWayAddPlan.actions(adding: draft, overrides: overrides, pending: [])
        check(actions.count == 1 && !actions.contains { if case .setContactsOverride = $0 { return true }; return false },
              "passwords and phrases never touch the switch")
    }
}
for overrides in [config, paused, OverridesConfig()] {
    for draft in [addAlex, .password(work), .phrase(mine)] {
        check(!SkipWayAddPlan.actions(adding: draft, overrides: overrides, pending: []).contains(
            .setContactsOverride(enabled: false)), "never turns the switch off")
    }
}
check(SkipWayAddPlan.passwordIsValid(name: "Work", password: "x", confirm: "x", allowed: [.limitChanges]), "valid")
check(!SkipWayAddPlan.passwordIsValid(name: " ", password: "x", confirm: "x", allowed: [.limitChanges]), "name")
check(!SkipWayAddPlan.passwordIsValid(name: "W", password: "x", confirm: "y", allowed: [.limitChanges]), "match")
check(!SkipWayAddPlan.passwordIsValid(name: "W", password: "", confirm: "", allowed: [.limitChanges]), "empty")
check(!SkipWayAddPlan.passwordIsValid(name: "W", password: "x", confirm: "x", allowed: []), "a capability")
check(SkipWayAddPlan.secretChangeIsValid(current: "a", new: "b", confirm: "b"), "secret change")
check(!SkipWayAddPlan.secretChangeIsValid(current: "", new: "b", confirm: "b"), "needs current")
check(!SkipWayAddPlan.secretChangeIsValid(current: "a", new: "b", confirm: "c"), "needs match")

// MARK: Edit what it may skip
check(SkipWayEdit.canSave(kind: .contact, current: noExtra, draft: [], hasPending: false), "a contact may be narrowed to nothing")
check(!SkipWayEdit.canSave(kind: .password, current: [.limitChanges], draft: [], hasPending: false), "a password needs one")
check(!SkipWayEdit.canSave(kind: .phrase, current: [.limitChanges], draft: [.limitChanges], hasPending: false), "unchanged")
check(!SkipWayEdit.canSave(kind: .phrase, current: [.limitChanges], draft: [.extraTime], hasPending: true),
      "a change already waiting")

// MARK: Receipts for override actions: direction from the real classify
var s = state(config)
s.delayPolicy = DelayPolicy(mode: .separate, strictDelay: 0, lenientDelay: 3600)
func plan(_ action: ChangeAction) -> ReceiptPlan {
    let direction = ChangeEngine.classify(action, state: s)
    return ReceiptPlan.make(looser: direction == .lenient, delay: s.delayPolicy.delay(for: direction), now: t0)
}
check(plan(.addContact(newContact)).commit == .hold && plan(.addContact(newContact)).wait == 3600, "add contact: looser, holds")
check(plan(.setContactPermissions(id: alex.id, allowed: [.limitChanges])).commit == .confirm
      && plan(.setContactPermissions(id: alex.id, allowed: [.limitChanges])).takesEffect == nil,
      "narrowing a contact: stricter, right away with a 0 stricter wait")
check(plan(.setContactPermissions(id: alex.id, allowed: all)).commit == .hold, "widening a contact: looser")
check(plan(.removeContact(id: alex.id)).commit == .confirm, "removing a contact: stricter (plan D9 correction)")
check(plan(.removePasswordPolicy(id: work.id)).commit == .confirm, "removing a password: stricter")
check(plan(.removePhrasePolicy(id: mine.id)).commit == .confirm, "removing a phrase: stricter")
check(plan(.setContactsOverride(enabled: false)).commit == .confirm, "pausing contacts: stricter")
check(plan(.setContactsOverride(enabled: true)).commit == .hold, "resuming contacts: looser")
check(plan(.upsertPasswordPolicy(PasswordPolicy(id: work.id, name: work.name, hash: hash, allowed: []))).commit == .hold,
      "narrowing a password stays looser (owner answer 1)")
check(plan(.upsertPhrasePolicy(PhrasePolicy(id: mine.id, name: mine.name, kind: mine.kind, allowedErrors: 0,
                                            allowed: [.limitChanges]))).commit == .hold,
      "narrowing a phrase stays looser (owner answer 1)")
let batch = ReceiptBatch.plan([(looser: true, delay: 3600), (looser: true, delay: 1800)], now: t0)
check(batch.looser && batch.wait == 3600 && batch.commit == .hold, "one receipt for two looser actions")
check(ReceiptBatch.plan([(looser: false, delay: 0)], now: t0).commit == .confirm, "a single stricter part")
check(ReceiptBatch.plan([(looser: false, delay: 0), (looser: true, delay: 60)], now: t0).commit == .hold,
      "any looser part holds")

// MARK: Invite dot (Y7)
check(YouInvites.showsDot(onTab: 3, inviteCount: 1), "You carries the dot")
check(!YouInvites.showsDot(onTab: 4, inviteCount: 1) && !YouInvites.showsDot(onTab: 3, inviteCount: 0), "only You, only with an invite")

print("You presentation passed: \(checks) checks — 128 summaries, \(compared) eligibility/hasOverride comparisons, list chips, routing, add plan, receipts")
'''

with tempfile.TemporaryDirectory(prefix='demora-you-') as directory:
    folder = Path(directory)
    (folder / 'Infrastructure.swift').write_text(infrastructure + '\n' + phrases + '\n' + score
                                                + '\nenum ChangeEngine {\n' + lifted + '\n}\n')
    (folder / 'SharedModels.swift').write_text(models)
    (folder / 'TodayPresentation.swift').write_text(today)
    (folder / 'YouPresentation.swift').write_text(presentation)
    (folder / 'main.swift').write_text(driver)
    binary = folder / 'you'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5',
                    *(str(folder / name) for name in ('Infrastructure.swift', 'SharedModels.swift',
                                                      'TodayPresentation.swift', 'YouPresentation.swift',
                                                      'main.swift')),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

# --- Skip the wait (Y4): the checks underneath are the existing ones -------
sheet = (ROOT / 'Latch/SkipWaitSheet.swift').read_text()
for forbidden in ('model.applyNow(', 'applyNowOffMain(', 'applyNowAndWait(', 'print(', 'UIPasteboard',
                  'UserDefaults', 'SharedStore.save', 'Keychain', 'OverrideGateView', 'TutorialContactGateView'):
    assert forbidden not in sheet, ('Skip the wait never bypasses a check or logs', forbidden)
for required in (
        # Contact: approval re-checked on the serialized queue, then confirmed applied.
        'await ContactsRelay.applyKnownApproval(requestId: reqId)',
        'await ContactsRelay.consumeVerifiedEmailRequest(requestId: reqId)',
        'guard requestWasApplied else {', 'try await EmailCodeService.verify(',
        'ContactsRelay.recordOutgoing(requestId: requestId,', 'ContactsRelay.recordOutgoingExtra(extraContext,',
        # Password: only a hash leaves the field, the field clears after every attempt.
        'let hash = AppModel.hash(password)', 'password = ""',
        'ChangeEngine.applyNowWithPasswordOffMain(', 'limitID: extraTime.limitID, candidateHash: hash)',
        # Phrase: the word-by-word entry with its own scope.
        'PhraseEntry(policy: policy,', 'ChangeEngine.applyNowWithPhraseOffMain(',
        'limitID: limitID, phraseProofID: proofID)'):
    assert required in sheet, ('gate logic kept', required)
assert sheet.count('ok = count == changes.count') == 1 and 'if count == changes.count {' in sheet, \
    'success only when every change applied'
phrase_src = (ROOT / 'Latch/PhraseOverrides.swift').read_text()
assert 'if action == #selector(paste(_:)) || action == #selector(cut(_:)) {' in phrase_src
assert 'field.removeInteraction(dropInteraction)' in phrase_src and 'override func paste(_ sender: Any?) {}' in phrase_src
assert 'NoPasteWordField(text: $input, onSubmit: submit)' in phrase_src
for gone in ('struct OverrideGateView', 'struct PasswordChangeGate', 'struct PhraseChangeGate',
             'struct ContactGateView', 'struct ExtraTimePasswordGate', 'struct ExtraTimePhraseGate'):
    for path in (ROOT / 'Latch').glob('*.swift'):
        assert gone not in path.read_text(), ('replaced by SkipWaitSheet', gone, path.name)
assert not (ROOT / 'Latch/OverrideGateView.swift').exists(), 'the retired gates file is gone'
print('Skip the wait guards passed: no direct apply, no logging, contact/password/phrase checks unchanged')

# --- Adding, editing and removing a way: receipt only (Y5, Y11) ------------
editors = (ROOT / 'Latch/SkipWayEditors.swift').read_text()
for forbidden in ('model.queue(', 'ChangeEngine.queue', 'print(', 'UserDefaults', 'Keychain', 'applyNow'):
    assert forbidden not in editors, ('every change goes through the receipt, nothing logged', forbidden)
assert editors.count('updatePasswordPolicySecretNow(') == 1, 'one immediate path: the secret only'
secret = editors.split('private struct PasswordSecretChangeView: View {', 1)[1].split('\n// MARK:', 1)[0]
assert 'updatePasswordPolicySecretNow(id: id, current: current,' in secret and 'allowed' not in secret, \
    'knowing a password changes only the secret'
assert 'current = ""; new = ""; confirm = ""' in secret
add_password = editors.split('private struct AddPasswordDetails: View {', 1)[1].split('\n/// The phrase fields', 1)[0]
assert 'hash: AppModel.hash(password)' in add_password and 'password = ""' in add_password
assert '.onDisappear { password = ""; confirm = "" }' in add_password, 'plain passwords never outlive the page'
for action in ('.setContactPermissions(id: id, allowed: allowed)', '.upsertPasswordPolicy(policy)',
               '.upsertPhrasePolicy(policy)', '.removeContact(id: id)', '.removePasswordPolicy(id: id)',
               '.removePhrasePolicy(id: id)', 'ChangeReceiptRequest(action: .upsertPhrasePolicy(changed))'):
    assert action in editors, ('receipt for', action)
assert 'receipt = ChangeReceiptRequest(action: removal)' in editors and 'receipt = ChangeReceiptRequest(action: action)' in editors
assert 'SkipWayAddPlan.actions(adding: draft, overrides: model.state.overrides,' in editors
assert 'guard value != ContactsRelay.myCode else {' in editors and 'ContactsRelay.codeExists(value)' in editors, \
    'own-code and code-exists checks kept'
assert 'if EmailCodeService.isConfigured {\n                        Picker(tr("Type")' in editors, \
    'email contacts offered only when this build can send email (owner answer 2)'
receipt_src = (ROOT / 'Latch/ChangeReceiptSheet.swift').read_text()
batch = receipt_src.split('struct ChangeReceiptView: View {', 1)[1].split('\n/// A horizontal line', 1)[0]
assert batch.count('model.queue(') == 1 and 'guard model.queue(actions[queuedCount]) != nil else {' in batch, \
    'the batch receipt queues each action once, in order, only on confirm'
assert 'let plan = ReceiptBatch.plan(parts, now: now)' in batch and 'model.preview(action)' in batch
contacts_src = (ROOT / 'Latch/ContactsOverrideViews.swift').read_text()
grant = contacts_src.split('struct GrantProfileView: View {', 1)[1].split('\n// MARK:', 1)[0]
assert 'model.queue(' not in grant and '.changeReceiptBatch($receipt) { added = true }' in grant, \
    'adding someone you approve for ends on the receipt'
you_src = (ROOT / 'Latch/YouView.swift').read_text() + (ROOT / 'Latch/SkipWayViews.swift').read_text()
assert 'model.queue(' not in you_src and 'ChangeReceiptRequest(action: .setContactsOverride(enabled: enabled))' in you_src
print('Receipt guards passed: adds, permission edits, removals and pause end on the receipt; secret-only immediate change')

# --- Step 6: one place for each fact (§4, §8) -------------------------------
latch = '\n'.join(path.read_text() for path in (ROOT / 'Latch').glob('*.swift'))
for gone in ('ExtraOverridesView', 'FineTuneOverridesView', 'PasswordPoliciesView', 'PhrasePoliciesView',
             'OverridesGridView', 'RulesGridView', 'ContactsOverrideEditor', 'ContactsDetailView',
             'ContactsHubView', 'TrustedContactApprovalRow', 'ContactProfileView', 'EmailContactProfileView',
             'ContactApprovalSummary', 'struct ContactPermissionsEditor', 'PreventDisablingGateView',
             'PreventGuideGateView', 'PasscodeHubView', 'PasscodeViewGateView', 'HelpHubView',
             'MathOverrideEditor', 'PasswordOverrideEditor', 'func queueSection', 'struct SettingsView',
             'SettingsRoute', 'settingsPath', 'func replayTutorial', 'func beginTutorial'):
    assert gone not in latch, ('duplicate screen removed', gone)
print('One-place guards passed: duplicate contact, password, phrase, prevent-disabling and help screens are gone')

# --- Every word You shows is translated, in all seven tables ----------------
STRING = r'"((?:[^"\\]|\\.)*)"'
keys = set(re.findall(r'translate\(' + STRING + r'\)', code))
keys.update(k for k in re.findall(r'return ' + STRING, code))
for pair in re.findall(r'translate\(extra \? ' + STRING + r' : ' + STRING + r'\)', code):
    keys.update(pair)
YOU_FILES = [p for p in ('Latch/YouView.swift', 'Latch/YouPages.swift', 'Latch/SkipWayViews.swift',
                         'Latch/SkipWayEditors.swift', 'Latch/SkipWaitSheet.swift', 'Latch/ChangeReceiptSheet.swift',
                         'Latch/HowDemoraWorksView.swift') if (ROOT / p).exists()]
for name in YOU_FILES:
    text = (ROOT / name).read_text()
    for call in re.findall(r'\btr\((?:[^()"]|"(?:[^"\\]|\\.)*")*\)', text):
        keys.update(re.findall(STRING, call))
assert len(keys) >= 16, sorted(keys)
TABLES = {'es': '', 'de': '+German', 'fr': '+French', 'pt': '+Portuguese',
          'pl': '+Polish', 'tr': '+Turkish', 'hi': '+Hindi'}
entry = re.compile(r'^\s*' + STRING + r'\s*:\s*' + STRING + r',?\s*$', re.M)
for language, suffix in TABLES.items():
    pairs = entry.findall((ROOT / f'Shared/Localization{suffix}.swift').read_text())
    seen = [k for k, _ in pairs]
    duplicates = sorted({k for k in seen if seen.count(k) > 1})
    assert not duplicates, (language, 'duplicate keys crash the dictionary literal', duplicates)
    table = dict(pairs)
    missing = sorted(k for k in keys if k not in table)
    assert not missing, (language, 'untranslated', missing)
    for key in keys:
        for spec in ('%@', '%d'):
            assert key.count(spec) == table[key].count(spec), (language, key, spec)
print(f'You strings passed: {len(keys)} keys × 7 tables, no duplicates, placeholders match')
