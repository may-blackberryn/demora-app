#!/usr/bin/env python3
"""Run: python3 Tests/ContactActivationHarness.py

F2 (docs/fixes-2.0-batch.md): pair a trusted contact now, approve after the
wait. Compiles the real Shared/SharedModels.swift and the real
Shared/ContactActivation.swift (unchanged) on macOS and checks:

- the model: `awaitingActivation` decodes as false when missing (legacy
  contacts and legacy pending adds), round-trips, makes a contact unusable
  and is rejected by fresh setup;
- every pure step: queue saves the flagged contact and flags the action's
  copy, apply clears only the flag, apply after removal does nothing, legacy
  apply appends, remove/decline and cancel drop both, the housekeeping repair
  migrates once without touching id/createdAt/appliesAt and prunes orphans;
- source guards that the engine, AppModel and the detail page call these
  steps in the right places (Tests/WhenWhereHarness.py runs the real
  queue/apply/cancel/remove/repair bodies with stubbed storage);
- every new or changed F2 string in all seven translation tables;
- the F2 review fixes: a failed immediate removal never closes the page as
  removed, no delayed removal for a waiting contact, ghost adds dropped,
  applyDueChanges' compare-and-save, and "Paused · can approve from …".

No iOS build, saved state, relay, CloudKit or email. A two-phone pairing test
is still needed on devices.
"""
from pathlib import Path
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


models = portable((ROOT / 'Shared/SharedModels.swift').read_text())
activation = (ROOT / 'Shared/ContactActivation.swift').read_text()
engine = portable((ROOT / 'Shared/ChangeEngine.swift').read_text())
phrases = declaration((ROOT / 'Shared/PhraseWords.swift').read_text(), 'enum PhraseWords {')
code = '\n'.join(line for line in activation.splitlines() if not line.lstrip().startswith('//'))
for forbidden in ('TimeGuard', 'Date()', 'Date.now', 'SharedStore', 'UserDefaults', 'DeviceActivity',
                  'UNUserNotification', 'ContactsRelay', 'appliesAt =', 'createdAt =', 'print('):
    assert forbidden not in code, ('pure steps must not use', forbidden)

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
    static func now() -> Date { fatalError("contact activation must not read the guarded clock") }
}
'''
lifted = '\n'.join(declaration(engine, signature) for signature in (
    'static func overrideCapability(for action: ChangeAction)',
    'static func classify(_ action: ChangeAction, state: LatchState)'))
score = declaration(engine, 'func mathStrictnessScore(')

driver = r'''
import Foundation
var checks = 0
func check(_ ok: @autoclosure () -> Bool, _ message: String) {
    if !ok() { print("FAIL: " + message); exit(1) }
    checks += 1
}
let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func contact(_ name: String, code: String, accepted: Bool = false) -> TrustedContact {
    TrustedContact(name: name, kind: .latchUser(code: code), accepted: accepted, inviteId: UUID().uuidString)
}
func change(_ action: ChangeAction, in hours: Double = 3) -> PendingChange {
    PendingChange(createdAt: t0, appliesAt: t0.addingTimeInterval(hours * 3600),
                  direction: .lenient, summary: "x", action: action)
}
func bytes<T: Encodable>(_ value: T) -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return try! encoder.encode(value)
}
func flag(_ c: TrustedContact) -> TrustedContact { var c = c; c.awaitingActivation = true; return c }

// MARK: Model
let legacyJSON = #"{"name":"Old","kind":{"latchUser":{"code":"OLD001"}},"accepted":true}"#
let legacy = try! JSONDecoder().decode(TrustedContact.self, from: Data(legacyJSON.utf8))
check(!legacy.awaitingActivation && legacy.isUsable, "legacy contact decodes active")
let legacyAdd = #"{"addContact":{"_0":{"name":"New","kind":{"email":{"_0":"n@example.com"}},"accepted":false,"inviteId":"0E0C0E0C-0000-4000-8000-000000000001"}}}"#
let decodedAdd = try! JSONDecoder().decode(ChangeAction.self, from: Data(legacyAdd.utf8))
guard case .addContact(let legacyCopy) = decodedAdd else { check(false, "legacy add decodes"); exit(1) }
check(!legacyCopy.awaitingActivation, "a pending add saved before F2 decodes without the flag")
let kim = contact("Kim", code: "KIM004")
let flaggedKim = flag(kim)
let round = try! JSONDecoder().decode(TrustedContact.self, from: bytes(flaggedKim))
check(round == flaggedKim && round.awaitingActivation, "flag round-trips")
check(String(data: bytes(kim), encoding: .utf8)!.contains("\"awaitingActivation\":false"), "flag encoded")
var accepted = flaggedKim; accepted.accepted = true
check(!flaggedKim.isUsable && !accepted.isUsable, "a flagged contact is never usable, accepted or not")
accepted.awaitingActivation = false
check(accepted.isUsable, "accepted and landed: usable")
var setup = OverridesConfig(); setup.contactsEnabled = true; setup.contacts = [kim]
check(setup.isValidInitialSetup, "fresh setup takes an unconfirmed draft")
setup.contacts = [flaggedKim]
check(!setup.isValidInitialSetup, "fresh setup rejects the flag")
var enabled = OverridesConfig(); enabled.contactsEnabled = true; enabled.contacts = [flag(contact("A", code: "AAA001", accepted: true))]
check(!enabled.anyEnabled, "a waiting contact doesn't count as a way to skip")

// MARK: Queue
var state = LatchState()
let queued = ContactActivation.prepareQueue(.addContact(kim), state: &state)
check(state.overrides.contacts == [flaggedKim], "queue saves the contact, flagged, unaccepted")
check(queued.map { bytes($0) } == bytes(ChangeAction.addContact(flaggedKim)), "the action's copy carries the flag")
var again = state
check(ContactActivation.prepareQueue(.addContact(kim), state: &again) == nil
      && bytes(again) == bytes(state), "a saved id can't be added twice")
check(ContactActivation.prepareQueue(.setContactPermissions(id: kim.id, allowed: []), state: &again) == nil,
      "no permission edits while waiting")
let lee = contact("Lee", code: "LEE003", accepted: true)
state.overrides.contacts.append(lee)
var withLee = state
check(ContactActivation.prepareQueue(.setContactPermissions(id: lee.id, allowed: []), state: &withLee)
      .map { bytes($0) } == bytes(ChangeAction.setContactPermissions(id: lee.id, allowed: [])),
      "active contacts' permission edits pass")
check(ContactActivation.prepareQueue(.removeLimit(id: lee.id), state: &withLee).map { bytes($0) }
      == bytes(ChangeAction.removeLimit(id: lee.id)) && bytes(withLee) == bytes(state), "other actions pass untouched")

// MARK: Apply
let add = change(.addContact(flaggedKim))
state.pending = [add]
state.overrides.contacts[0].accepted = true
state.overrides.contacts[0].allowed = [.limitChanges]
state.overrides.contacts[0].name = "Kim (renamed)"
state.overrides.contacts[0].avatar = ContactAvatar()
var applied = state
ContactActivation.apply(flaggedKim, to: &applied)
var expected = state.overrides.contacts[0]; expected.awaitingActivation = false
check(applied.overrides.contacts == [expected, lee], "apply clears only the flag, keeps acceptance/permissions/name/avatar")
var removed = LatchState(); removed.overrides.contacts = [lee]
ContactActivation.apply(flaggedKim, to: &removed)
check(removed.overrides.contacts == [lee], "apply after removal or decline does nothing")
var legacyState = LatchState()
ContactActivation.apply(kim, to: &legacyState)
check(legacyState.overrides.contacts == [kim], "a legacy copy keeps today's append")
var noDuplicate = applied
ContactActivation.apply(kim, to: &noDuplicate)
check(noDuplicate.overrides.contacts.count == 2, "never a duplicate id")

// MARK: Remove / decline / cancel
var dropping = state
let other = change(.removeLimit(id: UUID()))
dropping.pending.append(other)
let dropped = ContactActivation.dropAwaiting(contactID: kim.id, state: &dropping)
check(dropped?.map(\.id) == [add.id], "returns the dropped add for cleanup")
check(dropping.overrides.contacts == [lee] && dropping.pending.map(\.id) == [other.id], "contact and add go together")
check(ContactActivation.dropAwaiting(contactID: lee.id, state: &dropping) == nil
      && dropping.overrides.contacts == [lee], "an active contact is not dropped this way")
check(ContactActivation.dropAwaiting(contactID: kim.id, state: &dropping) == nil, "nothing to drop twice")
var cancelling = state
cancelling.pending.append(other)
check(ContactActivation.cancel(other.id, state: &cancelling)?.id == other.id
      && cancelling.overrides.contacts.count == 2, "cancelling something else keeps contacts")
check(ContactActivation.cancel(add.id, state: &cancelling)?.id == add.id
      && cancelling.overrides.contacts == [lee] && cancelling.pending.isEmpty, "cancelling the add drops its contact")
var activeCancel = applied
activeCancel.pending = [add]
_ = ContactActivation.cancel(add.id, state: &activeCancel)
check(activeCancel.overrides.contacts.count == 2, "a contact no longer waiting is never dropped by a cancel")

// MARK: Housekeeping repair
var migrating = LatchState()
let old1 = change(.addContact(kim), in: 5)
let sam = contact("Sam", code: "SAM002")
let old2 = change(.addContact(sam), in: 1)
migrating.pending = [old1, other, old2]
migrating.overrides.contacts = [lee]
check(ContactActivation.repair(&migrating) == [], "migration changed state, dropped nothing")
check(migrating.overrides.contacts == [lee, flaggedKim, flag(sam)], "both legacy adds saved, flagged")
check(migrating.pending.map(\.id) == [old1.id, other.id, old2.id]
      && migrating.pending.map(\.createdAt) == [old1.createdAt, other.createdAt, old2.createdAt]
      && migrating.pending.map(\.appliesAt) == [old1.appliesAt, other.appliesAt, old2.appliesAt]
      && migrating.pending.map(\.summary) == [old1.summary, other.summary, old2.summary],
      "id, createdAt, appliesAt and summary unchanged")
check(bytes(migrating.pending[0].action) == bytes(ChangeAction.addContact(flaggedKim)), "copy rewritten with the flag")
let once = bytes(migrating)
check(ContactActivation.repair(&migrating) == nil && bytes(migrating) == once, "idempotent: second run changes nothing")
var orphans = migrating
orphans.pending.removeAll { $0.id == old2.id }
check(ContactActivation.repair(&orphans) == [] && orphans.overrides.contacts == [lee, flaggedKim],
      "a flagged contact whose add is gone is pruned, never activated")
var savedAlready = LatchState()
savedAlready.overrides.contacts = [lee]
savedAlready.pending = [change(.addContact(lee))]
check(ContactActivation.repair(&savedAlready) == nil && savedAlready.overrides.contacts == [lee],
      "a legacy add whose id is already saved is left alone")

// Review fix 2: no delayed removal for a waiting contact; ghost adds dropped.
var waitingOnly = LatchState()
_ = ContactActivation.prepareQueue(.addContact(kim), state: &waitingOnly)
check(ContactActivation.prepareQueue(.removeContact(id: kim.id), state: &waitingOnly) == nil,
      "a waiting contact's removal is immediate, never queued")
var leeOnly = LatchState(); leeOnly.overrides.contacts = [lee]
check(ContactActivation.prepareQueue(.removeContact(id: lee.id), state: &leeOnly).map { bytes($0) }
      == bytes(ChangeAction.removeContact(id: lee.id)), "an active contact's removal still queues")
var ghost = LatchState()
let ghostAdd = change(.addContact(flaggedKim))
ghost.pending = [ghostAdd, other]
ghost.overrides.contacts = [lee]
check(ContactActivation.repair(&ghost)?.map(\.id) == [ghostAdd.id]
      && ghost.pending.map(\.id) == [other.id] && ghost.overrides.contacts == [lee],
      "a flagged add whose contact is gone is dropped and returned for cleanup")
check(ContactActivation.repair(&ghost) == nil, "ghost repair is idempotent")

print("Contact activation passed: \(checks) checks — model, queue, apply, remove/decline/cancel, migration")
'''

with tempfile.TemporaryDirectory(prefix='demora-contact-activation-') as directory:
    folder = Path(directory)
    (folder / 'Infrastructure.swift').write_text(infrastructure + '\n' + phrases + '\n' + score
                                                + '\nenum ChangeEngine {\n' + lifted + '\n}\n')
    (folder / 'SharedModels.swift').write_text(models)
    (folder / 'ContactActivation.swift').write_text(activation)
    (folder / 'main.swift').write_text(driver)
    binary = folder / 'activation'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5',
                    *(str(folder / name) for name in ('Infrastructure.swift', 'SharedModels.swift',
                                                      'ContactActivation.swift', 'main.swift')),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

# --- Wiring: the engine, AppModel and the views call the steps -------------
queue = declaration(engine, 'private static func queueCoordinated(')
prepare = queue.index('guard let action = ContactActivation.prepareQueue(action, state: &state) else { return nil }')
# The last conflict check and append are the ordinary (delayed) path; the
# free-time check-in path above them never queues a contact action.
assert queue.rindex('let key = conflictKey(action)') < prepare < queue.index('let direction = classify(action, state: state)') \
    < queue.rindex('state.pending.append(change)') < queue.rindex('SharedStore.save(state)'), \
    'the contact is saved by the same coordinated write as its pending add, before classification'
apply_body = declaration(engine, 'private static func apply(')
assert re.search(r'case \.addContact\(let contact\):\s*ContactActivation\.apply\(contact, to: &state\)', apply_body)
assert 'state.overrides.contacts.append' not in apply_body, 'the only append is the legacy one in ContactActivation'
cancel = declaration(engine, 'static func cancel(_ change: PendingChange)')
assert 'SharedStore.coordinateStateMutation' in cancel and 'ContactActivation.cancel(change.id, state: &state)' in cancel
assert cancel.index('coordinateStateMutation') < cancel.index('DeviceActivityCenter()'), 'XPC after the write'
remove = declaration(engine, 'static func removeAwaitingContact(')
assert 'ContactActivation.dropAwaiting(contactID: id, state: &state)' in remove
assert remove.index('coordinateStateMutation') < remove.index('DeviceActivityCenter()'), 'XPC after the write'
repair = declaration(engine, 'static func repairContactActivation(')
assert 'coordinateStateMutation' in repair and 'let removed = ContactActivation.repair(&state)' in repair \
    and '!SharedStore.stateRecoveryNeeded' in repair
assert repair.index('coordinateStateMutation') < repair.index('DeviceActivityCenter()'), 'ghost cleanup XPC after the write'
# Review fix 3: applyDueChanges saves only if the bytes it read are unchanged.
due = declaration(engine, 'static func applyDueChanges(attempt: Int = 0)')
assert due.index('let snapshot = SharedStore.stateBlob()') < due.index('var state = SharedStore.loadState()')
commit = due[due.index('let committed = SharedStore.coordinateStateMutation'):]
assert commit.index('guard SharedStore.stateBlob() == snapshot else { return false }') \
    < commit.index('return SharedStore.save(state)') < commit.index('DeviceActivityCenter()'), \
    'compare-and-save under coordination, XPC after it'
assert 'if attempt < 2, SharedStore.stateBlob() != snapshot { applyDueChanges(attempt: attempt + 1) }' in due, \
    'bounded re-read only when another writer changed the state'
assert due.count('SharedStore.save(') == 1, 'one save'
assert 'static func stateBlob() -> Data?' in (ROOT / 'Shared/SharedStore.swift').read_text()
housekeeping = declaration(engine, 'static func housekeeping(')
assert housekeeping.index('repairContactActivation()') < housekeeping.index('applyDueChanges()')
for name in ('private static func contactPermitted(', 'static func hasOverride('):
    assert 'isUsable' in declaration(engine, name), ('approvals still require isUsable', name)

app = (ROOT / 'Latch/AppModel.swift').read_text()
resolve = declaration(app, 'private func resolveInvite(')
assert 'awaitingActivation' in resolve and 'removeAwaitingContact(id: contactID)' in resolve, 'decline drops the add'
model_remove = declaration(app, 'func removeAwaitingContact(id: UUID) -> Bool')
assert 'return removed' in model_remove
assert 'ChangeEngine.removeAwaitingContact(id: id)' in model_remove
invites = declaration(app, 'private func checkContactInvites()')
assert 'if contact.isPending {' in invites, 'invites go out while waiting (accepted is still false)'
emails = declaration(app, 'private func sendPendingEmailInvites()')
assert '!$0.accepted' in emails and 'awaitingActivation' not in emails, 'email codes go out while waiting'

editors = (ROOT / 'Latch/SkipWayEditors.swift').read_text()
detail = editors.split('struct SkipWayDetailView: View {', 1)[1].split('\n/// Avatar, name', 1)[0]
assert 'SkipPermissionsChecklist(allowed: $allowed, disabled: pending != nil)' in detail, \
    'the activation is the pending change: permission edits disabled'
assert '.disabled(pending != nil && awaitingContact == nil)' in detail, 'remove stays available while waiting'
assert 'let removed = model.removeAwaitingContact(id: id)' in detail and 'SkipWayRowText.canApproveFrom(' in detail
remove_now = declaration(detail, 'private func removeNow()')
assert 'ImmediateRemoval.outcome(removed: removed, contactAfter: after)' in remove_now
assert remove_now.count('dismiss()') == 1 and 'case .removed, .gone:\n            dismiss()' in remove_now, \
    'review fix 1: the page closes only when nothing is left to remove'
assert 'receipt = ChangeReceiptRequest(action: removal)' in remove_now, 'landed meanwhile: the normal receipt'
assert 'paused: !model.state.overrides.contactsEnabled' in detail, 'review fix 4: strip says paused'
assert "SectionHeaderLink(title: tr(\"See in Changes\"))" in detail, 'the strip links to Changes'
views = (ROOT / 'Latch/SkipWayViews.swift').read_text()
assert 'case .canApproveFrom(let date, let accepted, let paused):' in views and 'paused ? .neutral : .upcoming' in views
contacts = (ROOT / 'Latch/ContactsOverrideViews.swift').read_text()
for gone in ('Adding a contact goes through a delay', 'must also accept before they can approve'):
    for path in list((ROOT / 'Latch').glob('*.swift')) + [ROOT / 'Shared/SharedModels.swift']:
        assert gone not in path.read_text(), ('old copy still used', gone, path.name)
print('Contact activation wiring passed: one write per step, XPC after writes, decline/remove/cancel drop both')

# --- Strings ---------------------------------------------------------------
F2_STRINGS = [
    'Can approve from %@',
    'Waiting to accept · can approve from %@',
    'Remove this contact now?',
    "They can't approve yet, so this happens right away and cancels the waiting add.",
    '%@ gets the request now and can approve once they accept and the wait ends.',
    'They get a request to accept right away. They can approve for you once the wait ends.',
    'Paused · can approve from %@',
    'Their wait has ended, so removing them now waits like any other removal.',
    "Couldn't remove this contact. Try again.",
]
latch = '\n'.join(p.read_text() for p in (ROOT / 'Latch').glob('*.swift'))
for key in F2_STRINGS:
    assert 'tr("' + key + '")' in latch, ('used through tr()', key)
STRING = r'"((?:[^"\\]|\\.)*)"'
entry = re.compile(r'(?:^|,)\s*' + STRING + r'\s*:\s*' + STRING + r'\s*(?=,|$)', re.M)
TABLES = {'es': '', 'de': '+German', 'fr': '+French', 'pt': '+Portuguese',
          'pl': '+Polish', 'tr': '+Turkish', 'hi': '+Hindi'}
for language, suffix in TABLES.items():
    pairs = entry.findall((ROOT / f'Shared/Localization{suffix}.swift').read_text())
    table = dict(pairs)
    for key in F2_STRINGS:
        assert key in table, (language, 'untranslated', key)
        assert table[key] != key and table[key].strip(), (language, 'copy of English', key)
        assert key.count('%@') == table[key].count('%@'), (language, 'placeholder', key)
    for gone in ("They'll get a request to accept before they can approve for you. Adding a contact goes through a delay.",
                 '%@ must also accept before they can approve.'):
        assert gone not in table, (language, 'orphaned old key', gone)
print(f'Contact activation strings passed: {len(F2_STRINGS)} strings × 7 tables, placeholders match')
