//
//  SharedModels.swift
//  Latch
//

import Foundation
import FamilyControls
import ManagedSettings

// MARK: - Constants

enum LatchConstants {
    /// Debug and production use distinct App Groups. Compile-time selection is
    /// intentional: a display-name or bundle-setting mistake must never make a
    /// build open the other environment's limits.
#if DEBUG
    static let appGroupID = "group.com.may.screentimedelay.dev"
#else
    static let appGroupID = "group.com.may.screentimedelay"
#endif
    static let stateKey = "latch.state.v1"
    static let blockedKey = "latch.blockedLimitIDs.v1"
    static let dailyActivityName = "latch.daily"
    static let applyActivityPrefix = "latch.apply."
    /// Identifier of the post-midnight "still blocked?" fallback notification.
    static let resetNudgeID = "latch.resetNudge"
    /// BGAppRefreshTask id — an extra background wake source (independent of the
    /// DeviceActivity extension) to retry the daily rollover overnight. Must
    /// match BGTaskSchedulerPermittedIdentifiers in Latch/Info.plist.
    static let bgRefreshID = "latch.midnightReset"

    /// Email-code service. Set both after deploying Backend/worker.js
    /// (see Backend/SETUP.md). Empty URL hides the email-contact option.
    static let overrideWorkerURL = "https://latch-codes.r68n49gwrt.workers.dev/"
    static let overrideAppToken = "218c7dddb5c9b7a59f1481f73b4c312e3f58cad3bea307c8"
}

// MARK: - Strictness

/// Every change is classified as one of these, which decides which delay gates it.
enum ChangeDirection: String, Codable {
    case stricter   // gated by `strictDelay`
    case lenient    // gated by `lenientDelay`

    var label: String {
        switch self {
        case .stricter: return tr("More strict")
        case .lenient:  return tr("Less strict")
        }
    }
}

// MARK: - Overrides

enum MathDifficulty: Int, Codable, CaseIterable, Comparable, Identifiable {
    // Raw values are stable for migration: old easy/medium/hard (1/2/3) map
    // onto elementary/middle/high.
    case elementary = 1, middle = 2, high = 3, college = 4

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .elementary: return tr("Very easy")
        case .middle:     return tr("Easy")
        case .high:       return tr("Medium")
        case .college:    return tr("Hard")
        }
    }
    /// Default number of problems when the user hasn't picked a count.
    var defaultCount: Int {
        switch self {
        case .elementary: return 3
        case .middle:     return 5
        case .high:       return 5
        case .college:    return 8
        }
    }
    static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
}

/// How many problems a user can choose to solve for one math override.
let mathQuestionCountOptions = [1, 3, 5, 10]

/// What happens when a math answer is wrong, mid-override.
enum MathWrongBehavior: Int, Codable, CaseIterable, Identifiable {
    case nothing = 0, removeOne = 1, restart = 2

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .nothing:   return tr("Nothing — just a new problem")
        case .removeOne: return tr("Lose one correct answer")
        case .restart:   return tr("Restart from zero")
        }
    }
}

/// A custom avatar for a contact — exactly one of: an SF Symbol (with a
/// color), an emoji, or a photo thumbnail. `style` decides which is shown.
struct ContactAvatar: Codable, Equatable {
    enum Style: String, Codable { case symbol, emoji, photo }
    var style: Style = .symbol
    var symbol: String = "person.fill"
    var colorHex: String = "#0E8C7F"   // Ink.accent-ish default
    var emoji: String = ""
    var imageData: Data? = nil          // small JPEG thumbnail

    /// The symbols offered in the picker.
    static let symbolChoices = [
        "person.fill", "heart.fill", "star.fill", "house.fill",
        "graduationcap.fill", "briefcase.fill", "figure.2.and.child.holdinghands",
        "pawprint.fill", "leaf.fill", "flame.fill", "bolt.fill", "moon.fill",
        "gamecontroller.fill", "book.fill", "music.note", "camera.fill",
        "cup.and.saucer.fill", "gift.fill", "crown.fill", "face.smiling",
    ]
    /// The colors offered in the picker (hex).
    static let colorChoices = [
        "#0E8C7F", "#E5484D", "#F76808", "#F5A623", "#30A46C",
        "#3E63DD", "#8E4EC6", "#D6409F", "#E54666", "#5B5BD6",
        "#0091FF", "#12A594", "#46A758", "#9C6B30", "#687076",
    ]
}

/// A person who can approve skipping a pending change's countdown —
/// either by email (they receive a one-time code) or as a Demora user
/// (they approve from their own app).
struct TrustedContact: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var kind: Kind
    /// For Demora-user contacts, whether they've accepted the invite to be
    /// your trusted contact. Email contacts are always treated as accepted.
    /// Defaults to true so contacts saved before this field existed stay active.
    var accepted: Bool = true
    /// Identifies this particular add. A re-add gets a fresh id, so an old
    /// acceptance (with a different id) no longer counts. Empty for email.
    var inviteId: String = ""
    /// Optional custom avatar (icon+color, emoji, or photo).
    var avatar: ContactAvatar? = nil
    /// Capabilities this person may approve. Legacy contacts retain the
    /// pending-change permissions they already had; extra time is opt-in.
    var allowed: Set<OverrideCapability> = Set(
        OverrideCapability.allCases.filter { $0 != .extraTime })

    enum Kind: Codable, Equatable {
        case email(String)
        case latchUser(code: String)
    }

    init(id: UUID = UUID(), name: String, kind: Kind,
         accepted: Bool = true, inviteId: String = "",
         allowed: Set<OverrideCapability> = Set(
             OverrideCapability.allCases.filter { $0 != .extraTime })) {
        self.id = id
        self.name = name
        self.kind = kind
        self.accepted = accepted
        self.inviteId = inviteId
        self.allowed = allowed
    }

    /// Tolerant decode: contacts saved before these fields existed keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(Kind.self, forKey: .kind)
        accepted = try c.decodeIfPresent(Bool.self, forKey: .accepted) ?? true
        inviteId = try c.decodeIfPresent(String.self, forKey: .inviteId) ?? ""
        avatar = try c.decodeIfPresent(ContactAvatar.self, forKey: .avatar)
        allowed = try c.decodeIfPresent(Set<OverrideCapability>.self, forKey: .allowed)
            ?? Set(OverrideCapability.allCases.filter { $0 != .extraTime })
    }

    var detail: String {
        switch kind {
        case .email(let address): return address
        case .latchUser(let code): return "Demora · \(code)"
        }
    }
    var isEmail: Bool {
        if case .email = kind { return true }
        return false
    }
    var latchUserCode: String? {
        if case .latchUser(let code) = kind { return code }
        return nil
    }
    /// Not yet usable as an approver: Demora users until they accept the
    /// invite, email contacts until they confirm with the emailed code.
    /// (Contacts saved before `accepted` existed decode as true, so they
    /// stay active.)
    var isPending: Bool { !accepted }
    /// Usable as an approver right now.
    var isUsable: Bool { accepted }
}

struct OverridesConfig: Codable, Equatable {
    var mathEnabled = false
    var mathDifficulty: MathDifficulty? = nil
    var mathQuestionCount: Int = 3
    var mathWrongBehavior: MathWrongBehavior = .nothing

    /// Problems to solve for one math override (chosen count, or the
    /// difficulty's default for legacy configs).
    var mathProblemCount: Int {
        mathQuestionCount > 0 ? mathQuestionCount : (mathDifficulty?.defaultCount ?? 3)
    }

    var passwordEnabled = false
    var passwordHash: String? = nil   // SHA-256, hex

    var contactsEnabled = false
    var contacts: [TrustedContact] = []
    var passwordPolicies: [PasswordPolicy] = []
    var phrasePolicies: [PhrasePolicy] = []

    var anyEnabled: Bool {
        (contactsEnabled && contacts.contains { $0.isUsable })
            || !passwordPolicies.isEmpty
    }

    init() {}

    /// Fresh setup accepts only the new scoped policies and unconfirmed
    /// contact drafts. This is not a waiver for edits after setup completes.
    var isValidInitialSetup: Bool {
        guard !mathEnabled, !passwordEnabled, passwordHash == nil,
              contactsEnabled == !contacts.isEmpty,
              Set(contacts.map(\.id)).count == contacts.count,
              Set(contacts.map(\.inviteId)).count == contacts.count,
              Set(passwordPolicies.map(\.id)).count == passwordPolicies.count,
              Set(phrasePolicies.map(\.id)).count == phrasePolicies.count else { return false }
        var destinations = Set<String>()
        for contact in contacts {
            guard !contact.accepted, UUID(uuidString: contact.inviteId) != nil,
                  !contact.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return false }
            let destination: String
            switch contact.kind {
            case .email(let address):
                guard address.contains("@"), !address.contains(where: \.isWhitespace) else { return false }
                destination = "email:" + address.lowercased()
            case .latchUser(let code):
                guard code.count == 6, !code.contains(where: \.isWhitespace) else { return false }
                destination = "app:" + code.uppercased()
            }
            guard destinations.insert(destination).inserted else { return false }
        }
        return passwordPolicies.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.allowed.isEmpty && $0.hash.count == 64
                && $0.hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        } && phrasePolicies.allSatisfy { PhraseWords.isValid($0) }
    }

    /// Tolerant decode so configs saved before newer fields existed load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Retire legacy self-overrides on upgrade. Keep the fields in the
        // schema so older saved states can still decode without losing rules.
        mathEnabled = false
        mathDifficulty = nil
        mathQuestionCount = 3
        mathWrongBehavior = .nothing
        passwordEnabled = false
        passwordHash = nil
        contactsEnabled = try c.decodeIfPresent(Bool.self, forKey: .contactsEnabled) ?? false
        contacts = try c.decodeIfPresent([TrustedContact].self, forKey: .contacts) ?? []
        passwordPolicies = try c.decodeIfPresent([PasswordPolicy].self,
                                                 forKey: .passwordPolicies) ?? []
        phrasePolicies = try c.decodeIfPresent([PhrasePolicy].self,
                                               forKey: .phrasePolicies) ?? []
    }
}

enum OverrideCapability: String, Codable, CaseIterable, Hashable, Identifiable {
    case limitChanges, scheduleChanges, sessionChanges, delayChanges
    case protectionChanges, contactChanges, extraTime

    var id: String { rawValue }
    var label: String {
        switch self {
        case .limitChanges: return tr("Limit changes")
        case .scheduleChanges: return tr("Schedule changes")
        case .sessionChanges: return tr("Session changes")
        case .delayChanges: return tr("Delay changes")
        case .protectionChanges: return tr("Protection changes")
        case .contactChanges: return tr("Contact changes")
        case .extraTime: return tr("Extra time")
        }
    }
}

struct PasswordPolicy: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var hash: String
    var allowed: Set<OverrideCapability>
}

enum PhraseKind: Codable, Equatable {
    case custom(String)
    case random(Int)

    var wordCount: Int {
        switch self {
        case .custom(let text): return PhraseWords.split(text).count
        case .random(let count): return count
        }
    }
}

struct PhrasePolicy: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var kind: PhraseKind
    /// Number of wrong words permitted before starting over; nil = unlimited.
    var allowedErrors: Int?
    var allowed: Set<OverrideCapability>
}

// MARK: - App limits

/// A second, independent usage budget for the part of the day before a local
/// clock time. `beforeMinutes` is capped by the day's effective total budget.
/// When carryUnused is false, the later part has its own (total - before)
/// budget; otherwise the ordinary whole-day budget governs it.
struct LimitSplit: Codable, Equatable {
    var cutoffMinutes: Int
    var beforeMinutes: Int
    var carryUnused: Bool
    /// When present, this is a three-portion split. Older saved two-portion
    /// rules leave both new fields nil and keep their original behavior.
    var secondCutoffMinutes: Int? = nil
    var middleMinutes: Int? = nil
}

/// A manually requested, delay-gated addition to the day's usage budget.
/// Each request grants usage minutes, not a wall-clock unblocking session.
struct LimitExtraStep: Codable, Equatable {
    var minutes: Int
    var waitMinutes: Int
    /// Nil means a wait-gated grant. A selected password verifies locally;
    /// it never uses waitMinutes as a fallback if the policy disappears.
    var passwordPolicyID: UUID? = nil
    var phrasePolicyID: UUID? = nil
    var contactRequired: Bool = false

    init(minutes: Int, waitMinutes: Int, passwordPolicyID: UUID? = nil,
         phrasePolicyID: UUID? = nil, contactRequired: Bool = false) {
        self.minutes = minutes
        self.waitMinutes = waitMinutes
        self.passwordPolicyID = passwordPolicyID
        self.phrasePolicyID = phrasePolicyID
        self.contactRequired = contactRequired
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minutes = try c.decode(Int.self, forKey: .minutes)
        waitMinutes = try c.decode(Int.self, forKey: .waitMinutes)
        passwordPolicyID = try c.decodeIfPresent(UUID.self, forKey: .passwordPolicyID)
        phrasePolicyID = try c.decodeIfPresent(UUID.self, forKey: .phrasePolicyID)
        contactRequired = try c.decodeIfPresent(Bool.self, forKey: .contactRequired) ?? false
    }
}

/// The exact extra-time use requested from a contact. Persisted with the
/// outgoing request so a CloudKit push can finish it while the UI is closed.
struct ExtraContactContext: Codable, Equatable, Identifiable {
    var requestID: String
    var limitID: UUID
    var day: String
    var stepIndex: Int
    var step: LimitExtraStep
    var limitName: String
    var id: String { requestID }
}

struct LimitExtraTime: Codable, Equatable {
    /// Legacy uniform rule. Keep these fields so already-saved limits and
    /// pending changes remain decodable after the ordered-step migration.
    var minutesPerUse: Int
    var usesPerDay: Int
    var waitMinutes: Int
    var steps: [LimitExtraStep]? = nil

    var effectiveSteps: [LimitExtraStep] {
        steps ?? Array(repeating: LimitExtraStep(minutes: minutesPerUse,
                                                waitMinutes: waitMinutes),
                       count: max(0, min(usesPerDay, 6)))
    }
}

/// A usage burst followed by a pause. DeviceActivity thresholds are the source
/// of truth; the interval is a minimum time between fresh usage allowances.
struct LimitPacing: Codable, Equatable {
    var usageMinutes: Int
    var intervalMinutes: Int
    var cooldownMinutes: Int
}

/// Local calendar eligibility is separate from the tamper-aware elapsed wait.
struct WakeDayTiming: Codable, Equatable {
    var startMinutes = 0
    var waitMinutes = 10
    var isValid: Bool { (0...1410).contains(startMinutes) && (0...1440).contains(waitMinutes) }
}

struct LimitWakeSchedule: Codable, Equatable {
    var startMinutes = 0
    var weekdays: Set<Int> = Set(1...7)
    var dayTimings: [Int: WakeDayTiming] = [:]
    var isValid: Bool {
        (0...1410).contains(startMinutes) && !weekdays.isEmpty
            && weekdays.isSubset(of: Set(1...7))
            && dayTimings.allSatisfy { (1...7).contains($0.key) && $0.value.isValid }
    }
    func timing(on date: Date, defaultWait: Int) -> WakeDayTiming {
        dayTimings[Calendar.current.component(.weekday, from: date)]
            ?? WakeDayTiming(startMinutes: startMinutes, waitMinutes: defaultWait)
    }
    func eligible(on date: Date) -> Bool {
        let c = Calendar.current.dateComponents([.weekday, .hour, .minute], from: date)
        return weekdays.contains(c.weekday ?? 0)
            && (c.hour ?? 0) * 60 + (c.minute ?? 0) >= timing(on: date, defaultWait: 0).startMinutes
    }
    func noLooser(than old: LimitWakeSchedule, wait: Int, oldWait: Int) -> Bool {
        guard old.weekdays.isSubset(of: weekdays) else { return false }
        for day in old.weekdays {
            let before = old.dayTimings[day] ?? WakeDayTiming(startMinutes: old.startMinutes, waitMinutes: oldWait)
            let after = dayTimings[day] ?? WakeDayTiming(startMinutes: startMinutes, waitMinutes: wait)
            if after.startMinutes > before.startMinutes || after.waitMinutes < before.waitMinutes { return false }
        }
        return true
    }
}

struct AppLimit: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String                       // user label, e.g. "Instagram"
    var selection: FamilyActivitySelection // apps/categories it covers
    var minutesPerDay: Int
    /// Overrides for individual local weekdays, 1=Sunday ... 7=Saturday.
    var weekdayMinutes: [Int: Int] = [:]
    /// Nil means no wake gate; 0 means tapping Wake up unlocks immediately.
    var wakeDelayMinutes: Int? = nil
    /// Missing in older builds means midnight, every day, and the saved wait.
    var wakeSchedule: LimitWakeSchedule? = nil
    var split: LimitSplit? = nil
    var pacing: LimitPacing? = nil
    var extraTime: LimitExtraTime? = nil

    init(id: UUID = UUID(), name: String, selection: FamilyActivitySelection,
         minutesPerDay: Int, weekdayMinutes: [Int: Int] = [:],
         wakeDelayMinutes: Int? = nil, wakeSchedule: LimitWakeSchedule? = nil, split: LimitSplit? = nil,
         pacing: LimitPacing? = nil, extraTime: LimitExtraTime? = nil) {
        self.id = id
        self.name = name
        self.selection = selection
        self.minutesPerDay = minutesPerDay
        self.weekdayMinutes = weekdayMinutes
        self.wakeDelayMinutes = wakeDelayMinutes
        self.wakeSchedule = wakeSchedule
        self.split = split
        self.pacing = nil // retired; keep the initializer label for old callers
        self.extraTime = extraTime
    }

    func minutes(on date: Date) -> Int {
        let day = Calendar.current.component(.weekday, from: date)
        return max(0, weekdayMinutes[day] ?? minutesPerDay)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        selection = try c.decode(FamilyActivitySelection.self, forKey: .selection)
        minutesPerDay = try c.decode(Int.self, forKey: .minutesPerDay)
        weekdayMinutes = try c.decodeIfPresent([Int: Int].self, forKey: .weekdayMinutes) ?? [:]
        wakeDelayMinutes = try c.decodeIfPresent(Int.self, forKey: .wakeDelayMinutes)
        wakeSchedule = try c.decodeIfPresent(LimitWakeSchedule.self, forKey: .wakeSchedule)
        split = try c.decodeIfPresent(LimitSplit.self, forKey: .split)
        pacing = nil // retire saved usage-burst rules on upgrade
        extraTime = try c.decodeIfPresent(LimitExtraTime.self, forKey: .extraTime)
    }
}

/// Which apps a global wake/sleep rule covers. Group IDs are resolved against
/// the current limits, so editing a group's apps updates the rule as well.
enum BoundaryBlockMode: String, Codable, CaseIterable, Identifiable {
    case blockSelected, blockAllExcept, blockGroups

    var id: String { rawValue }
    var label: String {
        switch self {
        case .blockSelected: return tr("Block only")
        case .blockAllExcept: return tr("Block except")
        case .blockGroups: return tr("Block created groups")
        }
    }
}

struct BoundaryBlockScope: Codable, Equatable {
    var mode: BoundaryBlockMode = .blockSelected
    var selection = FamilyActivitySelection()
    var groupIDs: Set<UUID> = []
    /// A group's apps can be excluded from the boundary without disabling
    /// its ordinary usage limit. This is deliberately separate from groupIDs.
    var excludedLimitIDs: Set<UUID> = []

    func isValid(in state: LatchState) -> Bool {
        switch mode {
        case .blockSelected:
            return !selection.applicationTokens.isEmpty
                || !selection.categoryTokens.isEmpty
                || !selection.webDomainTokens.isEmpty
        case .blockAllExcept:
            // ManagedSettings' all-except allowlist cannot express category
            // tokens, so never accept a category-only exception or a group
            // exclusion that would silently fail to allow its category apps.
            return (!selection.applicationTokens.isEmpty
                || !selection.webDomainTokens.isEmpty)
                && !state.limits.contains(where: {
                    excludedLimitIDs.contains($0.id)
                        && !$0.selection.categoryTokens.isEmpty
                })
        case .blockGroups:
            return state.limits.contains { groupIDs.contains($0.id) }
        }
    }
}

struct WakeBlockRule: Codable, Equatable {
    var enabled = false
    /// Local clock hour when a new wake day starts: 00:00, 03:00, 06:00, 09:00.
    var startHour = 6
    var waitMinutes = 120
    var weekdays: Set<Int> = Set(1...7)
    var scope = BoundaryBlockScope()

    func isValid(in state: LatchState) -> Bool {
        [0, 3, 6, 9].contains(startHour)
            && (!enabled || ((0...1440).contains(waitMinutes)
                            && !weekdays.isEmpty && scope.isValid(in: state)))
    }
}

struct SleepBlockRule: Codable, Equatable {
    var enabled = false
    var startMinutes = 22 * 60
    /// Weekday of the evening when sleep starts, not the following morning.
    var weekdays: Set<Int> = Set(1...7)
    var scope = BoundaryBlockScope()

    func isValid(in state: LatchState, wakeHour: Int) -> Bool {
        // Daily DeviceActivity intervals need at least 15 minutes before
        // midnight; 23:45+ would otherwise miss the sleep-start callback.
        !enabled || ((0...(23 * 60 + 30)).contains(startMinutes)
                     && startMinutes != wakeHour * 60
                     && !weekdays.isEmpty && scope.isValid(in: state))
    }
}

// MARK: - Independent day/night groups

enum DayNightScopeMode: String, Codable, CaseIterable, Identifiable {
    case selected, allOtherApps
    var id: String { rawValue }
}

struct DayNightScope: Codable, Equatable {
    var mode: DayNightScopeMode = .selected
    var limitIDs: Set<UUID> = []
    /// Extra selected apps, or exceptions when using all-other-apps mode.
    var selection = FamilyActivitySelection()
    var excludedLimitIDs: Set<UUID> = []

    func resolved(limits: [AppLimit]) -> FamilyActivitySelection {
        var result = selection
        let ids = mode == .selected ? limitIDs : excludedLimitIDs
        for limit in limits where ids.contains(limit.id) {
            result.applicationTokens.formUnion(limit.selection.applicationTokens)
            result.categoryTokens.formUnion(limit.selection.categoryTokens)
            result.webDomainTokens.formUnion(limit.selection.webDomainTokens)
        }
        return result
    }
}

struct DayNightGroup: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = ""
    var wakeEnabled = true
    var sleepEnabled = false
    var startHour = 6
    var waitMinutes = 120
    /// Nil preserves the old hour-based start without rewriting it on upgrade.
    var wakeStartMinutes: Int? = nil
    var weekdayWakeTimings: [Int: WakeDayTiming] = [:]
    var sleepStartMinutes = 22 * 60
    var weekdays: Set<Int> = Set(1...7)
    var scope = DayNightScope()
    /// Enables cannot inherit an old tap. Wait edits keep the current deadline.
    var wakeEpoch = UUID()

    var defaultWakeStart: Int { wakeStartMinutes ?? startHour * 60 }
    func wakeTiming(on date: Date) -> WakeDayTiming {
        weekdayWakeTimings[Calendar.current.component(.weekday, from: date)]
            ?? WakeDayTiming(startMinutes: defaultWakeStart, waitMinutes: waitMinutes)
    }
    var timingsAreValid: Bool {
        (0...1410).contains(defaultWakeStart) && (0...1440).contains(waitMinutes)
            && weekdayWakeTimings.allSatisfy { (1...7).contains($0.key) && $0.value.isValid }
            && (!sleepEnabled || (defaultWakeStart != sleepStartMinutes
                && weekdayWakeTimings.values.allSatisfy { $0.startMinutes != sleepStartMinutes }))
    }
    func timingNoLooser(than old: DayNightGroup) -> Bool {
        for day in old.weekdays {
            let before = old.weekdayWakeTimings[day] ?? WakeDayTiming(startMinutes: old.defaultWakeStart, waitMinutes: old.waitMinutes)
            let after = weekdayWakeTimings[day] ?? WakeDayTiming(startMinutes: defaultWakeStart, waitMinutes: waitMinutes)
            // Changing sleep's end is conservatively less strict; a later end
            // also moves the wake gate later. Never waive that tradeoff.
            if old.sleepEnabled && after.startMinutes != before.startMinutes { return false }
            if after.startMinutes > before.startMinutes || after.waitMinutes < before.waitMinutes { return false }
        }
        return true
    }

    func sleepIsActive(at date: Date) -> Bool {
        guard sleepEnabled else { return false }
        let calendar = Calendar.current
        for offset in [-1, 0] {
            guard let anchor = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)),
                  weekdays.contains(calendar.component(.weekday, from: anchor)),
                  let start = calendar.date(bySettingHour: sleepStartMinutes / 60,
                    minute: sleepStartMinutes % 60, second: 0, of: anchor) else { continue }
            let sameDayEnd = wakeTiming(on: anchor).startMinutes
            let endDay = sameDayEnd > sleepStartMinutes ? anchor
                : (calendar.date(byAdding: .day, value: 1, to: anchor) ?? anchor)
            let endMinute = wakeTiming(on: endDay).startMinutes
            guard let end = calendar.date(bySettingHour: endMinute / 60,
                minute: endMinute % 60, second: 0, of: endDay) else { continue }
            if date >= start && date < end { return true }
        }
        return false
    }

    func isValid(limits: [AppLimit]) -> Bool {
        let targets = scope.resolved(limits: limits)
        let known = Set(limits.map(\.id))
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 80, wakeEnabled || sleepEnabled,
              timingsAreValid,
              (0...1410).contains(sleepStartMinutes),
              !weekdays.isEmpty, weekdays.isSubset(of: Set(1...7)),
              scope.limitIDs.isSubset(of: known), scope.excludedLimitIDs.isSubset(of: known)
        else { return false }
        if scope.mode == .allOtherApps { return targets.categoryTokens.isEmpty }
        return !targets.applicationTokens.isEmpty || !targets.categoryTokens.isEmpty
            || !targets.webDomainTokens.isEmpty || !scope.limitIDs.isEmpty
    }

    static func isValidCollection(_ groups: [DayNightGroup], limits: [AppLimit]) -> Bool {
        guard groups.count <= 5, Set(groups.map(\.id)).count == groups.count,
              groups.allSatisfy({ $0.isValid(limits: limits) }),
              groups.filter({ $0.scope.mode == .allOtherApps }).count <= 1 else { return false }
        // A fallback must exempt explicitly timed groups. Screen Time cannot
        // express a category-wide exception, so don't promise that combination.
        return supportsLimitSelections(groups, limits: limits)
    }

    /// Referenced limits remain editable, but cannot introduce an exception
    /// that Screen Time cannot represent for the all-other-apps boundary.
    static func supportsLimitSelections(_ groups: [DayNightGroup], limits: [AppLimit]) -> Bool {
        guard groups.contains(where: { $0.scope.mode == .allOtherApps }) else { return true }
        return groups.allSatisfy { $0.scope.resolved(limits: limits).categoryTokens.isEmpty }
    }
}

extension DayNightGroup {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        wakeEnabled = try c.decode(Bool.self, forKey: .wakeEnabled)
        sleepEnabled = try c.decode(Bool.self, forKey: .sleepEnabled)
        startHour = try c.decode(Int.self, forKey: .startHour)
        waitMinutes = try c.decode(Int.self, forKey: .waitMinutes)
        wakeStartMinutes = try c.decodeIfPresent(Int.self, forKey: .wakeStartMinutes)
        weekdayWakeTimings = try c.decodeIfPresent([Int: WakeDayTiming].self, forKey: .weekdayWakeTimings) ?? [:]
        sleepStartMinutes = try c.decode(Int.self, forKey: .sleepStartMinutes)
        weekdays = try c.decode(Set<Int>.self, forKey: .weekdays)
        scope = try c.decode(DayNightScope.self, forKey: .scope)
        wakeEpoch = try c.decode(UUID.self, forKey: .wakeEpoch)
    }
}

// MARK: - Schedules & sessions

/// Is the current time inside a daily [start, end) window (minutes after
/// midnight)? Supports windows that wrap past midnight (e.g. 22:00–02:00).
func windowContains(_ date: Date, start: Int, end: Int) -> Bool {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
    if start == end { return false }
    return start < end ? (m >= start && m < end) : (m >= start || m < end)
}

func minutesLabel(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

enum ScheduleMode: String, Codable, CaseIterable, Identifiable {
    case blockAllExcept   // block everything except the selected apps
    case blockSelected    // block only the selected apps

    var id: String { rawValue }
    var label: String {
        switch self {
        case .blockAllExcept: return tr("Block all except…")
        case .blockSelected:  return tr("Block only…")
        }
    }
}

/// When a recurring window repeats.
enum Recurrence: Codable, Equatable {
    case daily
    case weekly(Set<Int>)                            // weekdays, 1=Sun…7=Sat
    case monthlyDay(Int)                             // e.g. the 15th
    case monthlyOrdinal(weekday: Int, ordinal: Int)  // e.g. 2nd Monday

    /// Does the window that *starts* on `date`'s day occur under this rule?
    func matches(dayOf date: Date) -> Bool {
        let cal = Calendar.current
        switch self {
        case .daily:
            return true
        case .weekly(let days):
            return days.contains(cal.component(.weekday, from: date))
        case .monthlyDay(let d):
            return cal.component(.day, from: date) == d
        case .monthlyOrdinal(let weekday, let ordinal):
            return cal.component(.weekday, from: date) == weekday
                && cal.component(.weekdayOrdinal, from: date) == ordinal
        }
    }

    var label: String {
        switch self {
        case .daily:
            return tr("Every day")
        case .weekly(let days):
            let symbols = Calendar.current.shortWeekdaySymbols
            return days.sorted().map { symbols[$0 - 1] }.joined(separator: " ")
        case .monthlyDay(let d):
            return String(format: tr("Day %d of every month"), d)
        case .monthlyOrdinal(let weekday, let ordinal):
            let name = Calendar.current.weekdaySymbols[weekday - 1]
            return String(format: tr("%@ #%d of every month"), name, ordinal)
        }
    }
}

/// True when `date` falls inside the window AND the day the window started
/// matches the recurrence rule (windows wrapping midnight belong to the day
/// they started).
func windowActive(at date: Date, start: Int, end: Int,
                  recurrence: Recurrence) -> Bool {
    guard windowContains(date, start: start, end: end) else { return false }
    var anchor = date
    if start >= end {   // wraps midnight
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if m < end {
            // A calendar day is not always 24 hours across daylight saving.
            anchor = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
    }
    return recurrence.matches(dayOf: anchor)
}

/// Recurring blocking window.
struct BlockSchedule: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var mode: ScheduleMode
    var selection: FamilyActivitySelection // allowlist or blocklist, per mode
    var startMinutes: Int                  // minutes after midnight
    var endMinutes: Int
    var recurrence: Recurrence = .daily
    /// When this was added — used to break ties between conflicting recurring
    /// windows (the most recently added wins). Old data decodes as distantPast.
    var addedAt: Date = .distantPast

    /// An empty allowlist blocks everything; an empty blocklist blocks nothing.
    /// Categories and websites are valid selections, not just applications.
    func acceptsSelection(_ candidate: FamilyActivitySelection) -> Bool {
        mode == .blockAllExcept
            || !candidate.applicationTokens.isEmpty
            || !candidate.categoryTokens.isEmpty
            || !candidate.webDomainTokens.isEmpty
    }

    func isActive(at date: Date = Date()) -> Bool {
        windowActive(at: date, start: startMinutes, end: endMinutes,
                     recurrence: recurrence)
    }
    var windowLabel: String {
        "\(minutesLabel(startMinutes))–\(minutesLabel(endMinutes))"
    }

    init(name: String, mode: ScheduleMode, selection: FamilyActivitySelection,
         startMinutes: Int, endMinutes: Int, recurrence: Recurrence = .daily,
         addedAt: Date = Date()) {
        self.name = name
        self.mode = mode
        self.selection = selection
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.recurrence = recurrence
        self.addedAt = addedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mode = try c.decode(ScheduleMode.self, forKey: .mode)
        selection = try c.decode(FamilyActivitySelection.self, forKey: .selection)
        startMinutes = try c.decode(Int.self, forKey: .startMinutes)
        endMinutes = try c.decode(Int.self, forKey: .endMinutes)
        recurrence = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence) ?? .daily
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? .distantPast
    }
}

/// Recurring "free period": limits don't block during the window and
/// usage inside it doesn't count toward them (tracked via checkpoints).
struct ExemptSchedule: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var startMinutes: Int
    var endMinutes: Int
    var recurrence: Recurrence = .daily
    var addedAt: Date = .distantPast   // for conflict tie-breaking (latest wins)

    func isActive(at date: Date = Date()) -> Bool {
        windowActive(at: date, start: startMinutes, end: endMinutes,
                     recurrence: recurrence)
    }
    var windowLabel: String {
        "\(minutesLabel(startMinutes))–\(minutesLabel(endMinutes))"
    }

    init(name: String, startMinutes: Int, endMinutes: Int,
         recurrence: Recurrence = .daily, addedAt: Date = Date()) {
        self.name = name
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.recurrence = recurrence
        self.addedAt = addedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        startMinutes = try c.decode(Int.self, forKey: .startMinutes)
        endMinutes = try c.decode(Int.self, forKey: .endMinutes)
        recurrence = try c.decodeIfPresent(Recurrence.self, forKey: .recurrence) ?? .daily
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? .distantPast
    }
}

/// One-off window planned ahead for specific dates ("airport tomorrow
/// morning", "friend's place this weekend"). Does not repeat.
enum PlannedKind: String, Codable, CaseIterable, Identifiable {
    case blockSelected
    case blockAllExcept
    case free

    var id: String { rawValue }
    var label: String {
        switch self {
        case .blockSelected:  return tr("Block only…")
        case .blockAllExcept: return tr("Block all except…")
        case .free:           return tr("Free period")
        }
    }
}

struct PlannedWindow: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: PlannedKind
    var selection: FamilyActivitySelection // unused for .free
    var startsAt: Date
    var endsAt: Date

    // Wall clock (Date), not TimeGuard: startsAt/endsAt are set in wall-clock
    // time and enforced by DeviceActivity, which is also wall-clock. Using
    // TimeGuard here made the window's active state disagree with when it
    // actually starts/ends once the clocks drift (e.g. after the device sleeps).
    var isActive: Bool {
        let now = Date()
        return now >= startsAt && now < endsAt
    }
    var isPast: Bool { Date() >= endsAt }
    var activityName: String { "planned-\(id.uuidString)" }
}

enum SessionKind: String, Codable {
    case block     // temporarily block apps (stricter)
    case unblock   // temporarily lift blocks on apps (lenient)
    case free      // temporary free period: nothing blocks, usage doesn't count

    var label: String {
        switch self {
        case .block: return tr("Block")
        case .unblock: return tr("Unblock")
        case .free: return tr("Free period")
        }
    }
}

/// One-off session ("block/unblock these apps for X minutes"). Unplanned,
/// but still delay-gated like every other change: starting a block session
/// waits the strict delay; an unblock session waits the lenient delay.
/// Ending early flips accordingly.
struct BlockSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: SessionKind = .block
    var selection: FamilyActivitySelection
    var startedAt: Date
    var endsAt: Date

    // Wall clock (Date), not TimeGuard — endsAt and the DeviceActivity that
    // ends the session are both wall-clock, so a session's active state must
    // use the same clock or it won't expire when the clocks drift apart.
    var isActive: Bool { Date() < endsAt }
    var activityName: String { "session-\(id.uuidString)" }

    init(name: String, kind: SessionKind, selection: FamilyActivitySelection,
         startedAt: Date, endsAt: Date) {
        self.name = name
        self.kind = kind
        self.selection = selection
        self.startedAt = startedAt
        self.endsAt = endsAt
    }

    /// Tolerant decode: sessions saved before `kind` existed default to .block.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(SessionKind.self, forKey: .kind) ?? .block
        selection = try c.decode(FamilyActivitySelection.self, forKey: .selection)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endsAt = try c.decode(Date.self, forKey: .endsAt)
    }
}

// MARK: - Delay policy

enum DelayMode: String, Codable, CaseIterable, Identifiable {
    case separate, shared, lenientOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .separate: return tr("Two delays")
        case .shared: return tr("One delay for all changes")
        case .lenientOnly: return tr("Only less-strict changes wait")
        }
    }
    var explanation: String {
        switch self {
        case .separate: return tr("Choose a different wait for tightening and loosening your rules.")
        case .shared: return tr("The same wait applies whether you tighten or loosen a rule.")
        case .lenientOnly: return tr("Tighten a rule immediately. Loosening it still waits.")
        }
    }
}

struct DelayPolicy: Codable, Equatable {
    var mode: DelayMode = .separate
    var strictDelay: TimeInterval = 300
    var lenientDelay: TimeInterval = 900

    var isValid: Bool {
        let maximum: TimeInterval = 366 * 24 * 60 * 60
        guard strictDelay.isFinite, (0...maximum).contains(strictDelay),
              lenientDelay.isFinite, (60...maximum).contains(lenientDelay) else { return false }
        return mode != .separate
            || (strictDelay.isFinite && (60...maximum).contains(strictDelay))
    }
    var normalized: DelayPolicy {
        switch mode {
        case .separate: return self
        case .shared: return DelayPolicy(mode: mode, strictDelay: lenientDelay, lenientDelay: lenientDelay)
        case .lenientOnly: return DelayPolicy(mode: mode, strictDelay: 0, lenientDelay: lenientDelay)
        }
    }
    func delay(for direction: ChangeDirection) -> TimeInterval {
        direction == .lenient ? lenientDelay : normalized.strictDelay
    }
    func direction(comparedTo old: DelayPolicy) -> ChangeDirection {
        delay(for: .stricter) < old.delay(for: .stricter)
            || delay(for: .lenient) < old.delay(for: .lenient) ? .lenient : .stricter
    }
    /// Legacy queued edits still decode, but follow the selected policy when
    /// applied. They cannot create an unadvertised second shared delay.
    func replacing(_ direction: ChangeDirection, with seconds: TimeInterval) -> DelayPolicy {
        var result = self
        if mode == .shared || direction == .lenient { result.lenientDelay = seconds }
        else if mode == .separate { result.strictDelay = seconds }
        return result.normalized
    }
}

// MARK: - Active state

/// The *currently enforced* configuration. Only the ChangeEngine mutates this,
/// and only when a pending change's timer has elapsed (or was overridden).
struct LatchState: Codable {
    var isSetUp = false
    /// One-shot replacement of an enabled legacy math override during the
    /// upgrade welcome. Committed in the same blob as the replacement phrases.
    var mathPhraseReplacementDone = false
    var strictDelay: TimeInterval = 0   // gates "more strict" changes
    var lenientDelay: TimeInterval = 0  // gates "less strict" changes
    var delayMode: DelayMode = .separate
    var delayPolicy: DelayPolicy {
        get { DelayPolicy(mode: delayMode, strictDelay: strictDelay, lenientDelay: lenientDelay).normalized }
        set {
            let policy = newValue.normalized
            delayMode = policy.mode
            strictDelay = policy.strictDelay
            lenientDelay = policy.lenientDelay
        }
    }
    var limits: [AppLimit] = []
    var overrides = OverridesConfig()
    var wakeRule = WakeBlockRule()
    var sleepRule = SleepBlockRule()
    var dayNightGroups: [DayNightGroup] = []
    var dayNightSetupDone = false
    var pending: [PendingChange] = []
    var schedules: [BlockSchedule] = []
    var exemptions: [ExemptSchedule] = []
    var sessions: [BlockSession] = []
    var planned: [PlannedWindow] = []
    var blockAppRemoval = false
    var blockAdultWebsites = false
    /// Custom website blocklist (raw domains, e.g. "reddit.com"). Applied via
    /// ManagedSettings' web-content filter, which also enables adult-site
    /// blocking as a side effect of Apple's API.
    var blockedDomains: [String] = []
    /// When non-nil and in the past, the "Prevent disabling" help page is
    /// unlocked for a single open; opening it re-locks (clears this). When in
    /// the future, access is still counting down the less-strict delay.
    var preventUnlockAt: Date? = nil
    /// Same one-shot mechanics as `preventUnlockAt`, but for VIEWING the
    /// stored Screen Time passcode — its own delayed gate, separate from the
    /// guide's, so looking up the code always costs its own wait.
    var passwordViewUnlockAt: Date? = nil
    /// The Screen Time passcode a friend set, stored so it isn't lost. Viewing
    /// it lives behind the prevent-disabling delay gate, so it can't be looked
    /// up on impulse to turn Demora off.
    var screenTimeCode: String = ""

    init() {}

    /// Tolerant decoding so state saved by older app versions (without the
    /// newer keys) still loads instead of wiping the user's setup.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isSetUp = try c.decodeIfPresent(Bool.self, forKey: .isSetUp) ?? false
        mathPhraseReplacementDone = try c.decodeIfPresent(Bool.self, forKey: .mathPhraseReplacementDone) ?? false
        strictDelay = try c.decodeIfPresent(TimeInterval.self, forKey: .strictDelay) ?? 0
        lenientDelay = try c.decodeIfPresent(TimeInterval.self, forKey: .lenientDelay) ?? 0
        delayMode = try c.decodeIfPresent(DelayMode.self, forKey: .delayMode) ?? .separate
        limits = try c.decodeIfPresent([AppLimit].self, forKey: .limits) ?? []
        overrides = try c.decodeIfPresent(OverridesConfig.self, forKey: .overrides) ?? OverridesConfig()
        wakeRule = try c.decodeIfPresent(WakeBlockRule.self, forKey: .wakeRule) ?? WakeBlockRule()
        sleepRule = try c.decodeIfPresent(SleepBlockRule.self, forKey: .sleepRule) ?? SleepBlockRule()
        dayNightGroups = try c.decodeIfPresent([DayNightGroup].self, forKey: .dayNightGroups) ?? []
        dayNightSetupDone = try c.decodeIfPresent(Bool.self, forKey: .dayNightSetupDone) ?? false
        pending = (try c.decodeIfPresent([PendingChange].self, forKey: .pending) ?? [])
            .filter { change in
                switch change.action {
                case .setMathOverride, .setPasswordOverride: return false
                default: return true
                }
            }
        schedules = try c.decodeIfPresent([BlockSchedule].self, forKey: .schedules) ?? []
        exemptions = try c.decodeIfPresent([ExemptSchedule].self, forKey: .exemptions) ?? []
        sessions = try c.decodeIfPresent([BlockSession].self, forKey: .sessions) ?? []
        planned = try c.decodeIfPresent([PlannedWindow].self, forKey: .planned) ?? []
        blockAppRemoval = try c.decodeIfPresent(Bool.self, forKey: .blockAppRemoval) ?? false
        blockAdultWebsites = try c.decodeIfPresent(Bool.self, forKey: .blockAdultWebsites) ?? false
        blockedDomains = try c.decodeIfPresent([String].self, forKey: .blockedDomains) ?? []
        preventUnlockAt = try c.decodeIfPresent(Date.self, forKey: .preventUnlockAt)
        passwordViewUnlockAt = try c.decodeIfPresent(Date.self, forKey: .passwordViewUnlockAt)
        screenTimeCode = try c.decodeIfPresent(String.self, forKey: .screenTimeCode) ?? ""
    }
}

// MARK: - Pending changes

enum ChangeAction: Codable, Equatable {
    case setDelayPolicy(DelayPolicy)
    case addLimit(AppLimit)
    case updateLimitMinutes(id: UUID, minutes: Int)
    /// A selection edit is always less strict, even when the same edit also
    /// changes the minute budget. Keep the legacy minutes-only case so already
    /// queued changes from older builds continue to decode and apply.
    case updateLimit(id: UUID, selection: FamilyActivitySelection, minutes: Int)
    /// Atomic edit of the whole limit, preserving its ID and spent markers.
    case configureLimit(AppLimit)
    case setGroupWakeDelay(id: UUID, minutes: Int?)
    case setGroupWakeSchedule(id: UUID, minutes: Int?, schedule: LimitWakeSchedule)
    case removeLimit(id: UUID)
    case setStrictDelay(TimeInterval)
    case setLenientDelay(TimeInterval)
    case setMathOverride(enabled: Bool, difficulty: MathDifficulty?,
                         count: Int, wrong: MathWrongBehavior)
    case setPasswordOverride(enabled: Bool, passwordHash: String?)
    case upsertPasswordPolicy(PasswordPolicy)
    case removePasswordPolicy(id: UUID)
    case upsertPhrasePolicy(PhrasePolicy)
    case removePhrasePolicy(id: UUID)
    case setContactsOverride(enabled: Bool)
    case setWakeRule(WakeBlockRule)
    case setSleepRule(SleepBlockRule)
    case upsertDayNightGroup(DayNightGroup)
    case removeDayNightGroup(id: UUID)
    case addContact(TrustedContact)
    case removeContact(id: UUID)
    case setContactPermissions(id: UUID, allowed: Set<OverrideCapability>)
    case addSchedule(BlockSchedule)
    /// Selection-only edit: preserve identity, recurrence, window, mode and
    /// addedAt precedence. Every selection change uses the less-strict delay.
    case updateScheduleSelection(id: UUID, selection: FamilyActivitySelection)
    case removeSchedule(id: UUID)
    case addExemption(ExemptSchedule)
    case removeExemption(id: UUID)
    case addPlanned(PlannedWindow)
    case removePlanned(id: UUID)
    case startSession(name: String, kind: SessionKind,
                      selection: FamilyActivitySelection, minutes: Int)
    case endSessionEarly(id: UUID)
    case setBlockAppRemoval(Bool)
    case setBlockAdultWebsites(Bool)
    case addBlockedDomain(String)
    case removeBlockedDomain(String)
    /// Unlock a single view of the "Prevent disabling" guide. Gaining access
    /// is a loosening change, so it waits the less-strict delay (and can be
    /// passed with an override like any other pending change).
    case unlockPreventGuide
    /// Unlock a single look at the stored Screen Time passcode. Its own gate,
    /// separate from the guide's — same lenient-delay + one-use mechanics.
    case unlockPasswordView
}

struct PendingChange: Codable, Identifiable, Equatable {
    var id = UUID()
    var createdAt: Date
    var appliesAt: Date
    var direction: ChangeDirection
    var summary: String
    var action: ChangeAction

    var isDue: Bool { TimeGuard.now() >= appliesAt }
    var activityName: String { LatchConstants.applyActivityPrefix + id.uuidString }
}

// MARK: - Formatting helpers

extension TimeInterval {
    var shortDelayLabel: String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day, .hour, .minute]
        f.unitsStyle = .abbreviated
        return f.string(from: self) ?? "\(Int(self))s"
    }
}
