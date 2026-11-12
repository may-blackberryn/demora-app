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
    /// Local-clock ceiling for this gate, independent of tapping or elapsed wait.
    /// Missing in old state means no automatic ceiling.
    var latestMinutes: Int? = nil
    var isValid: Bool {
        (0...1410).contains(startMinutes) && (0...1440).contains(waitMinutes)
            && (latestMinutes.map { $0 > startMinutes && $0 <= 1410 } ?? true)
    }
    func ceilingReached(on date: Date) -> Bool {
        guard let latestMinutes else { return false }
        let calendar = Calendar.current
        guard let boundary = calendar.date(bySettingHour: latestMinutes / 60,
            minute: latestMinutes % 60, second: 0, of: calendar.startOfDay(for: date),
            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        else { return false }
        // Once the concrete daily ceiling passes, a repeated DST hour cannot
        // turn this gate back on. A missing spring hour uses the next valid time.
        return date >= boundary
    }
    func noLooser(than old: WakeDayTiming) -> Bool {
        startMinutes <= old.startMinutes && waitMinutes >= old.waitMinutes
            && (latestMinutes ?? 1440) >= (old.latestMinutes ?? 1440)
    }
}

struct LimitWakeSchedule: Codable, Equatable {
    var startMinutes = 0
    var weekdays: Set<Int> = Set(1...7)
    var dayTimings: [Int: WakeDayTiming] = [:]
    var latestMinutes: Int? = nil
    var isValid: Bool {
        (0...1410).contains(startMinutes) && !weekdays.isEmpty
            && (latestMinutes.map { $0 > startMinutes && $0 <= 1410 } ?? true)
            && weekdays.isSubset(of: Set(1...7))
            && dayTimings.allSatisfy { (1...7).contains($0.key) && $0.value.isValid }
    }
    func timing(on date: Date, defaultWait: Int) -> WakeDayTiming {
        dayTimings[Calendar.current.component(.weekday, from: date)]
            ?? WakeDayTiming(startMinutes: startMinutes, waitMinutes: defaultWait, latestMinutes: latestMinutes)
    }
    func eligible(on date: Date) -> Bool {
        let c = Calendar.current.dateComponents([.weekday, .hour, .minute], from: date)
        return weekdays.contains(c.weekday ?? 0)
            && (c.hour ?? 0) * 60 + (c.minute ?? 0) >= timing(on: date, defaultWait: 0).startMinutes
    }
    func noLooser(than old: LimitWakeSchedule, wait: Int, oldWait: Int) -> Bool {
        guard old.weekdays.isSubset(of: weekdays) else { return false }
        for day in old.weekdays {
            let before = old.dayTimings[day] ?? WakeDayTiming(startMinutes: old.startMinutes, waitMinutes: oldWait, latestMinutes: old.latestMinutes)
            let after = dayTimings[day] ?? WakeDayTiming(startMinutes: startMinutes, waitMinutes: wait, latestMinutes: latestMinutes)
            if !after.noLooser(than: before) { return false }
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
    var latestMinutes: Int? = nil
    var weekdayLatestMinutes: [Int: Int]? = nil

    func latest(on date: Date) -> Int? {
        weekdayLatestMinutes?[Calendar.current.component(.weekday, from: date)] ?? latestMinutes
    }

    func isValid(in state: LatchState) -> Bool {
        [0, 3, 6, 9].contains(startHour)
            && (latestMinutes.map { $0 > startHour * 60 && $0 <= 1410 } ?? true)
            && (weekdayLatestMinutes?.allSatisfy { (1...7).contains($0.key) && $0.value > startHour * 60 && $0.value <= 1410 } ?? true)
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
    var wakeLatestMinutes: Int? = nil
    var sleepStartMinutes = 22 * 60
    var weekdays: Set<Int> = Set(1...7)
    var scope = DayNightScope()
    /// Enables cannot inherit an old tap. Wait edits keep the current deadline.
    var wakeEpoch = UUID()

    var defaultWakeStart: Int { wakeStartMinutes ?? startHour * 60 }
    func wakeTiming(on date: Date) -> WakeDayTiming {
        weekdayWakeTimings[Calendar.current.component(.weekday, from: date)]
            ?? WakeDayTiming(startMinutes: defaultWakeStart, waitMinutes: waitMinutes, latestMinutes: wakeLatestMinutes)
    }
    var timingsAreValid: Bool {
        (0...1410).contains(defaultWakeStart) && (0...1440).contains(waitMinutes)
            && (wakeLatestMinutes.map { $0 > defaultWakeStart && $0 <= 1410 } ?? true)
            && weekdayWakeTimings.allSatisfy { (1...7).contains($0.key) && $0.value.isValid }
            && (!sleepEnabled || (defaultWakeStart != sleepStartMinutes
                && weekdayWakeTimings.values.allSatisfy { $0.startMinutes != sleepStartMinutes }))
    }
    func timingNoLooser(than old: DayNightGroup) -> Bool {
        for day in old.weekdays {
            let before = old.weekdayWakeTimings[day] ?? WakeDayTiming(startMinutes: old.defaultWakeStart, waitMinutes: old.waitMinutes, latestMinutes: old.wakeLatestMinutes)
            let after = weekdayWakeTimings[day] ?? WakeDayTiming(startMinutes: defaultWakeStart, waitMinutes: waitMinutes, latestMinutes: wakeLatestMinutes)
            // Changing sleep's end is conservatively less strict; a later end
            // also moves the wake gate later. Never waive that tradeoff.
            if old.sleepEnabled && after.startMinutes != before.startMinutes { return false }
            if !after.noLooser(than: before) { return false }
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
        wakeLatestMinutes = try c.decodeIfPresent(Int.self, forKey: .wakeLatestMinutes)
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
    /// Set only on the day/time branch of a When & where block rule. The rule
    /// owns it: it is added, replaced and removed only with its rule. Nil in
    /// old saved state and for every ordinary repeating block (never encoded).
    var ownerRuleID: UUID? = nil

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
        ownerRuleID = try c.decodeIfPresent(UUID.self, forKey: .ownerRuleID)
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
    /// The When & where rule whose check-in started this session. Nil for
    /// every other session and in old saved state (never encoded when nil).
    var conditionalRuleID: UUID? = nil

    // Wall clock (Date), not TimeGuard — endsAt and the DeviceActivity that
    // ends the session are both wall-clock, so a session's active state must
    // use the same clock or it won't expire when the clocks drift apart.
    var isActive: Bool { Date() < endsAt }
    /// A rule runs one session at a time, so its activity is named after the
    /// rule: the capacity reservation and the real registration are one name,
    /// and the extension's `session-` prefix cleanup works unchanged.
    var activityName: String {
        conditionalRuleID.map(ConditionalRule.sessionActivityName(for:))
            ?? "session-\(id.uuidString)"
    }

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
        conditionalRuleID = try c.decodeIfPresent(UUID.self, forKey: .conditionalRuleID)
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
    /// Promoted schedule keys, oldest promotion first. Never edited immediately.
    var prioritizedScheduleKeys: [String] = []
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
    /// When & where rules, their per-day check-in uses and the time zones
    /// recently seen. Stored optionally so a state without them encodes
    /// exactly as before (older builds simply ignore the keys).
    private(set) var conditionalRuleStore: [ConditionalRule]? = nil
    private(set) var conditionalUseStore: [ConditionalUseRecord]? = nil
    var timeZoneEvidence: TimeZoneEvidence? = nil

    var conditionalRules: [ConditionalRule] {
        get { conditionalRuleStore ?? [] }
        set { conditionalRuleStore = newValue.isEmpty ? nil : newValue }
    }
    /// Uses never decrease within a day; only records older than
    /// `ConditionalUses.retention` are pruned (on rollover or at a new start).
    var conditionalUses: [ConditionalUseRecord] {
        get { conditionalUseStore ?? [] }
        set { conditionalUseStore = newValue.isEmpty ? nil : newValue }
    }

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
        prioritizedScheduleKeys = try c.decodeIfPresent([String].self, forKey: .prioritizedScheduleKeys) ?? []
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
        conditionalRuleStore = try c.decodeIfPresent([ConditionalRule].self, forKey: .conditionalRuleStore)
        conditionalUseStore = try c.decodeIfPresent([ConditionalUseRecord].self, forKey: .conditionalUseStore)
        timeZoneEvidence = try c.decodeIfPresent(TimeZoneEvidence.self, forKey: .timeZoneEvidence)
    }
}

// MARK: - Pending changes

enum ChangeAction: Codable, Equatable {
    case setSchedulePriority(key: String, prioritized: Bool)
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
    /// When & where rules. Free-time rules are looser to add and stricter to
    /// remove; block rules the reverse. Every edit is looser and preserves the
    /// rule's ID, today's uses and any running session.
    case addConditionalRule(ConditionalRule)
    case updateConditionalRule(ConditionalRule)
    case removeConditionalRule(id: UUID)
    /// Start from a met check-in. Free time: delay 0 only when validated, never
    /// a delayed fallback. Block: the stricter wait, like Block now.
    case startConditionalSession(ConditionalStartRequest)
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

// MARK: - When & where rules (docs/conditional-sessions-redesign.md)
//
// Pure model and decision code only: no CoreLocation, persistence, monitor,
// notification or shield calls, so every harness that compiles this file
// keeps working. Location arrives later as an injected, already-read fix
// (host only); nothing here asks for it or keeps it. Unknown fails closed (C9).
//
// Clock domains: conditions and per-day uses use the guarded clock
// (`TimeGuard.now()`, passed in) in the given calendar; sessions keep the
// existing wall-clock `startedAt`/`endsAt`, because DeviceActivity ends them on
// the wall clock. A start is refused while the two disagree.

/// A saved place: the centre the user chose, never a record of where they
/// were. Sizes are a fixed choice (C10).
struct ConditionalPlace: Codable, Equatable {
    static let radiusChoices = [100, 250, 500, 1000, 2000]
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Int

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80
            && latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
            && Self.radiusChoices.contains(radiusMeters)
    }
}

/// A local calendar day in the Gregorian calendar, whatever the time zone.
struct ConditionalDay: Codable, Equatable, Hashable, Comparable {
    var year: Int
    var month: Int
    var day: Int

    static func < (l: Self, r: Self) -> Bool {
        (l.year, l.month, l.day) < (r.year, r.month, r.day)
    }
    private static var utcGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        return calendar
    }
    var isValid: Bool {
        let calendar = Self.utcGregorian
        guard (1...9999).contains(year),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return false }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return c.year == year && c.month == month && c.day == day
    }
    /// Every When & where day, weekday and time is read in this calendar, not
    /// the device's: Settings → Calendar (Buddhist, Japanese …) must not give
    /// a different day key and so reopen a spent day.
    static func gregorian(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
    static func of(_ date: Date, in zone: TimeZone) -> ConditionalDay {
        let calendar = gregorian(in: zone)
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return ConditionalDay(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }
}

enum ConditionalCondition: Codable, Equatable {
    case place(ConditionalPlace)
    /// ISO 3166-1 alpha-2, uppercase ("MX").
    case country(String)
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday (DayChips' type).
    case days(Set<Int>)
    /// Minutes after local midnight, [start, end); may wrap past midnight.
    case time(start: Int, end: Int)
    /// Inclusive local calendar days (C6).
    case dates(first: ConditionalDay, last: ConditionalDay)

    var usesLocation: Bool {
        switch self {
        case .place, .country: return true
        case .days, .time, .dates: return false
        }
    }

    var isValid: Bool {
        switch self {
        case .place(let place):
            return place.isValid
        case .country(let code):
            return code.count == 2 && code.unicodeScalars.allSatisfy { (65...90).contains($0.value) }
        case .days(let days):
            return !days.isEmpty && days.isSubset(of: Set(1...7))
        case .time(let start, let end):
            return (0...1439).contains(start) && (0...1439).contains(end) && start != end
        case .dates(let first, let last):
            return first.isValid && last.isValid && first <= last
        }
    }
}

enum ConditionalMatch: String, Codable {
    case all, any
}

enum ConditionalBlockEnd: Codable, Equatable {
    /// Until this local clock time (minutes after midnight), the next time it comes.
    case time(Int)
    case duration(minutes: Int)
}

enum ConditionalOutcome: Codable, Equatable {
    /// `.free` (everything, usage doesn't count) or `.unblock` (these apps).
    case freeTime(kind: SessionKind, selection: FamilyActivitySelection,
                  maxMinutes: Int, usesPerDay: Int)
    case block(mode: ScheduleMode, selection: FamilyActivitySelection,
               until: ConditionalBlockEnd)
}

struct ConditionalRule: Codable, Equatable, Identifiable {
    static let maximumRules = 5
    static let maximumConditions = 4
    static let maximumNameLength = 80

    var id = UUID()
    var name: String
    var match: ConditionalMatch
    var conditions: [ConditionalCondition]
    var outcome: ConditionalOutcome
    /// Precedence tie-break for owned block windows (latest added wins).
    var addedAt: Date = .distantPast
    /// Bumped by the engine on every applied edit; a check-in names the
    /// revision it checked, so a landed edit makes older check-ins stale.
    var revision = 0

    init(id: UUID = UUID(), name: String, match: ConditionalMatch,
         conditions: [ConditionalCondition], outcome: ConditionalOutcome,
         addedAt: Date = Date(), revision: Int = 0) {
        self.id = id
        self.name = name
        self.match = match
        self.conditions = conditions
        self.outcome = outcome
        self.addedAt = addedAt
        self.revision = revision
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        match = try c.decode(ConditionalMatch.self, forKey: .match)
        conditions = try c.decode([ConditionalCondition].self, forKey: .conditions)
        outcome = try c.decode(ConditionalOutcome.self, forKey: .outcome)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? .distantPast
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    }

    static func sessionActivityName(for ruleID: UUID) -> String {
        "session-cond-\(ruleID.uuidString)"
    }
    var sessionActivityName: String { Self.sessionActivityName(for: id) }

    var isFreeTime: Bool {
        if case .freeTime = outcome { return true }
        return false
    }
    /// Only an "Everything" free session pauses limit counting.
    var reservesFreeWindow: Bool {
        if case .freeTime(.free, _, _, _) = outcome { return true }
        return false
    }
    var hasLocationCondition: Bool { conditions.contains(where: \.usesLocation) }

    var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= Self.maximumNameLength,
              (1...Self.maximumConditions).contains(conditions.count),
              conditions.allSatisfy(\.isValid) else { return false }
        switch outcome {
        case .freeTime(let kind, let selection, let maxMinutes, let uses):
            guard (5...240).contains(maxMinutes), (1...5).contains(uses) else { return false }
            switch kind {
            case .free: return true
            case .unblock: return Self.hasTargets(selection)
            case .block: return false
            }
        case .block(let mode, let selection, let until):
            // v1: a check-in block is a Block now session, which can only
            // block chosen apps. A rule without a place or country should
            // be a repeating block instead. Under "any of", only time windows
            // run on their own (as owned repeating blocks).
            guard mode == .blockSelected, Self.hasTargets(selection), hasLocationCondition
            else { return false }
            switch until {
            case .time(let minute): guard (0...1439).contains(minute) else { return false }
            case .duration(let minutes): guard (1...1440).contains(minutes) else { return false }
            }
            if match == .any {
                return conditions.allSatisfy { condition in
                    if condition.usesLocation { return true }
                    if case .time = condition { return true }
                    return false
                }
            }
            return true
        }
    }

    /// Same rule apart from the engine-managed revision and addedAt.
    func sameConfiguration(as other: ConditionalRule) -> Bool {
        id == other.id && name == other.name && match == other.match
            && conditions == other.conditions && outcome == other.outcome
    }

    private static func hasTargets(_ selection: FamilyActivitySelection) -> Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    /// Stable per rule, condition position and window times: an edit that
    /// keeps them keeps the activity names (no monitor restart); one that
    /// moves a time gets new names, so the window is re-registered and the
    /// name-based monitor repair notices a stale registration.
    static func ownedScheduleID(ruleID: UUID, index: Int, start: Int, end: Int) -> UUID {
        var bytes = ruleID.uuid
        bytes.10 ^= UInt8(truncatingIfNeeded: start >> 8)
        bytes.11 ^= UInt8(truncatingIfNeeded: start)
        bytes.12 ^= UInt8(truncatingIfNeeded: end >> 8)
        bytes.13 ^= UInt8(truncatingIfNeeded: end)
        bytes.14 ^= 0xC5
        bytes.15 ^= UInt8(truncatingIfNeeded: index + 1)
        return UUID(uuid: bytes)
    }

    /// C3: under "any of", a block rule's time window runs on its own as an
    /// ordinary repeating block owned by the rule; place/country branches
    /// start only on check-in. "All of" rules own nothing.
    func ownedSchedules() -> [BlockSchedule] {
        guard match == .any, case .block(let mode, let selection, _) = outcome else { return [] }
        return conditions.enumerated().compactMap { index, condition in
            guard case .time(let start, let end) = condition else { return nil }
            var schedule = BlockSchedule(name: name, mode: mode, selection: selection,
                                         startMinutes: start, endMinutes: end,
                                         recurrence: .daily, addedAt: addedAt)
            schedule.id = Self.ownedScheduleID(ruleID: id, index: index, start: start, end: end)
            schedule.ownerRuleID = id
            return schedule
        }
    }
}

/// One rule's check-in uses for one local day key. Uses never decrease
/// within a day and are never refunded (ending early included).
struct ConditionalUseRecord: Codable, Equatable {
    var ruleID: UUID
    var day: String
    var count: Int
    /// Guarded clock time of the latest use, for pruning only.
    var lastUsedAt: Date
    var checkInIDs: [UUID] = []
}

enum ConditionalUses {
    /// A day key can stay "today" in some time zone for up to ~50 hours after
    /// a use; keep records comfortably longer than that.
    static let retention: TimeInterval = 72 * 60 * 60

    /// Same "yyyy-M-d" shape as `SharedStore.dayKey`, always Gregorian, in
    /// the given calendar's time zone.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let c = ConditionalDay.gregorian(in: calendar.timeZone)
            .dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// The highest count among the given day keys (one per recent zone).
    static func used(ruleID: UUID, dayKeys: [String], in records: [ConditionalUseRecord]) -> Int {
        records.filter { $0.ruleID == ruleID && dayKeys.contains($0.day) }
            .map(\.count).max() ?? 0
    }

    static func checkInUsed(_ checkInID: UUID, ruleID: UUID,
                            in records: [ConditionalUseRecord]) -> Bool {
        records.contains { $0.ruleID == ruleID && $0.checkInIDs.contains(checkInID) }
    }

    /// Count one use under every given day key.
    static func recording(ruleID: UUID, dayKeys: [String], checkInID: UUID, at now: Date,
                          in records: [ConditionalUseRecord]) -> [ConditionalUseRecord] {
        var result = records
        for key in Set(dayKeys).sorted() {
            if let index = result.firstIndex(where: { $0.ruleID == ruleID && $0.day == key }) {
                result[index].count += 1
                result[index].lastUsedAt = max(result[index].lastUsedAt, now)
                result[index].checkInIDs.append(checkInID)
            } else {
                result.append(ConditionalUseRecord(ruleID: ruleID, day: key, count: 1,
                                                   lastUsedAt: now, checkInIDs: [checkInID]))
            }
        }
        return result
    }

    /// Never lower a saved count: the highest count per rule and day wins and
    /// check-in IDs are combined. A record missing from `proposed` survives
    /// unless it is older than `retention` on the wall clock (so pruning still
    /// works; keeping an old day's record only ever errs on the strict side).
    static func merged(previous: [ConditionalUseRecord], proposed: [ConditionalUseRecord],
                       wallNow: Date = Date()) -> [ConditionalUseRecord] {
        var result = proposed
        for old in previous {
            if let index = result.firstIndex(where: { $0.ruleID == old.ruleID && $0.day == old.day }) {
                result[index].count = max(result[index].count, old.count)
                result[index].lastUsedAt = max(result[index].lastUsedAt, old.lastUsedAt)
                for id in old.checkInIDs where !result[index].checkInIDs.contains(id) {
                    result[index].checkInIDs.append(id)
                }
            } else if wallNow.timeIntervalSince(old.lastUsedAt) < retention {
                result.append(old)
            }
        }
        return result
    }

    /// Drops only records whose last use is older than `retention`; a record
    /// from the future (clock moved back) is kept.
    static func pruned(_ records: [ConditionalUseRecord], at now: Date) -> [ConditionalUseRecord] {
        records.filter { now.timeIntervalSince($0.lastUsedAt) < retention }
    }
}

/// The time zones Demora has seen recently (C9). If the zone changed in the
/// last 12 hours, a day/time condition must hold in every zone seen since.
struct TimeZoneEvidence: Codable, Equatable {
    static let window: TimeInterval = 12 * 60 * 60
    static let maximumEntries = 8
    var currentID: String
    /// Earlier zones and when they were last current (guarded clock).
    var lastSeen: [String: Date] = [:]

    /// Nil when nothing changed, so callers write saved state only on a change.
    static func observing(_ evidence: TimeZoneEvidence?, zoneID: String,
                          at now: Date) -> TimeZoneEvidence? {
        guard var result = evidence else { return TimeZoneEvidence(currentID: zoneID) }
        guard result.currentID != zoneID else { return nil }
        // The previous zone was current until some moment up to now; assume now.
        result.lastSeen[result.currentID] = now
        result.lastSeen[zoneID] = nil
        result.currentID = zoneID
        result.lastSeen = result.lastSeen.filter { now.timeIntervalSince($0.value) <= window }
        if result.lastSeen.count > maximumEntries {
            let kept = result.lastSeen.sorted { $0.value > $1.value }.prefix(maximumEntries)
            result.lastSeen = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        return result
    }

    /// The current zone first, then every other zone seen in the window. An
    /// unobserved change (saved zone differs) counts as having changed now.
    static func recentZoneIDs(_ evidence: TimeZoneEvidence?, current: String,
                              at now: Date) -> [String] {
        guard let evidence else { return [current] }
        var others = Set(evidence.lastSeen.filter {
            now.timeIntervalSince($0.value) <= window
        }.keys)
        if evidence.currentID != current { others.insert(evidence.currentID) }
        others.remove(current)
        return [current] + others.sorted()
    }
}

// MARK: When & where: evaluation inputs and results

/// One location fix, already read in the foreground by the host. Never saved.
struct ConditionalLocationFix: Equatable {
    var latitude: Double
    var longitude: Double
    /// Metres; iOS reports a negative value for an invalid fix.
    var horizontalAccuracy: Double
    /// Seconds since the fix was taken.
    var age: TimeInterval
    var isPrecise = true
    var isSimulated = false
    var isFromAccessory = false
}

/// The offline country lookup's answer for the fix's point.
struct ConditionalCountryLookup: Equatable {
    /// Nil when the point is in no country (open sea).
    var regionCode: String?
    var borderDistanceMeters: Double
    /// Block check-ins only (spec §5.6, "doubt favours the stricter result"):
    /// how far the point is from each country the lookup found nearby, with
    /// the dataset's allowance already taken off (0 for a country the point
    /// may be in). Nil when the lookup didn't say; free time never reads it.
    var nearbyMeters: [String: Double]? = nil
}

enum ConditionalUnknownReason: Equatable {
    case notChecked, clockChanged, timeZoneChanged, timeZoneUnknown
    case locationOff, noFix, staleFix, imprecise, needsPrecise
    case simulated, accessory, nearBorder, countryUnavailable
}

enum ConditionalLocationInput: Equatable {
    /// Location was not read (the plan decided it couldn't change the answer).
    case notRead
    case unavailable(ConditionalUnknownReason)
    case fix(ConditionalLocationFix, country: ConditionalCountryLookup?)
}

enum ConditionStatus: Equatable {
    case met, notMet, unknown, notNeeded
}

enum ConditionReason: Equatable {
    case atPlace, notAtPlace, inCountry, notInCountry
    case onDay(weekday: Int), notOnDay(weekday: Int)
    case inWindow, outsideWindow(minute: Int)
    case inDates, outsideDates
    case notNeeded
    case unknown(ConditionalUnknownReason)
    /// Block check-ins only: the fix can't rule the place or country out,
    /// so it counts as met (doubt favours the stricter result, spec §5.6).
    case nearPlace, nearCountry
}

struct ConditionResult: Equatable {
    var status: ConditionStatus
    var reason: ConditionReason
    /// For a met day/time/date condition: when it stops holding (nil = not
    /// within a week, e.g. every day). Never set for place/country.
    var windowEnd: Date? = nil

    static func unknown(_ reason: ConditionalUnknownReason) -> ConditionResult {
        ConditionResult(status: .unknown, reason: .unknown(reason))
    }
}

struct ConditionalEvaluation: Equatable {
    var results: [ConditionResult]
    var isMet: Bool
    /// True only when location was not read and reading it could still make
    /// the rule true (C8: read location only if it can change the answer).
    var locationCouldChangeVerdict: Bool
    /// The window end that caps a session started now; nil = only its length.
    var windowEnd: Date?
}

struct ConditionalClockInput {
    var guardedNow: Date
    var wallNow: Date
    /// The device calendar in the current time zone.
    var calendar: Calendar
    /// Current zone first, then other zones seen in the last 12 hours.
    var recentTimeZoneIDs: [String]

    static func current(for state: LatchState, guardedNow: Date = TimeGuard.now(),
                        wallNow: Date = Date(), calendar: Calendar = .current) -> ConditionalClockInput {
        ConditionalClockInput(
            guardedNow: guardedNow, wallNow: wallNow, calendar: calendar,
            recentTimeZoneIDs: TimeZoneEvidence.recentZoneIDs(
                state.timeZoneEvidence, current: calendar.timeZone.identifier, at: guardedNow))
    }

    /// Zones to check, the current one first; nil if any can't be resolved.
    var zones: [TimeZone]? {
        var ids = [calendar.timeZone.identifier]
        ids += recentTimeZoneIDs.filter { $0 != calendar.timeZone.identifier }
        var result: [TimeZone] = []
        for id in ids {
            guard let zone = id == calendar.timeZone.identifier ? calendar.timeZone
                    : TimeZone(identifier: id) else { return nil }
            result.append(zone)
        }
        return result
    }

    /// Day keys for today in every recent zone (current first).
    var dayKeys: [String]? {
        zones.map { zones in
            var keys: [String] = []
            for zone in zones {
                var zoned = calendar
                zoned.timeZone = zone
                let key = ConditionalUses.dayKey(for: guardedNow, calendar: zoned)
                if !keys.contains(key) { keys.append(key) }
            }
            return keys
        }
    }

    var clockAgrees: Bool {
        abs(wallNow.timeIntervalSince(guardedNow)) <= ConditionEvaluator.clockTolerance
    }
}

enum ConditionEvaluator {
    /// TimeGuard's own tolerance between wall and guarded time.
    static let clockTolerance: TimeInterval = 300
    static let maximumFixAge: TimeInterval = 15
    static let borderMargin: Double = 2000
    static let earthRadius: Double = 6_371_000

    static func evaluate(_ rule: ConditionalRule, clock: ConditionalClockInput,
                         location: ConditionalLocationInput) -> ConditionalEvaluation {
        let free = rule.isFreeTime
        var results = rule.conditions.map { condition in
            condition.usesLocation ? .unknown(.notChecked) : clockResult(condition, clock: clock)
        }
        let clockResults = zip(rule.conditions, results).filter { !$0.0.usesLocation }.map(\.1)
        let settled: Bool
        switch rule.match {
        case .all: settled = clockResults.contains { $0.status != .met }
        case .any: settled = clockResults.contains { $0.status == .met }
        }
        var notRead = false
        if case .notRead = location { notRead = true }
        for index in rule.conditions.indices where rule.conditions[index].usesLocation {
            if notRead {
                results[index] = settled ? ConditionResult(status: .notNeeded, reason: .notNeeded)
                    : .unknown(.notChecked)
            } else {
                results[index] = locationResult(rule.conditions[index], input: location, free: free)
            }
        }
        let decision = verdict(rule, statuses: results.map(\.status), windowEnds: results.map(\.windowEnd))
        return ConditionalEvaluation(
            results: results, isMet: decision.isMet,
            locationCouldChangeVerdict: notRead && rule.hasLocationCondition && !settled,
            windowEnd: decision.isMet ? decision.windowEnd : nil)
    }

    /// Unknown and not-needed never count as met. All of: every condition
    /// met; the earliest day/time/date end caps a session. Any of: one met;
    /// a met place/country branch caps only by length, otherwise the latest
    /// end of the met day/time/date branches.
    static func verdict(_ rule: ConditionalRule, statuses: [ConditionStatus],
                        windowEnds: [Date?]) -> (isMet: Bool, windowEnd: Date?) {
        guard statuses.count == rule.conditions.count, windowEnds.count == statuses.count,
              !statuses.isEmpty else { return (false, nil) }
        let indices = Array(rule.conditions.indices)
        switch rule.match {
        case .all:
            guard statuses.allSatisfy({ $0 == .met }) else { return (false, nil) }
            let ends = indices.filter { !rule.conditions[$0].usesLocation }.compactMap { windowEnds[$0] }
            return (true, ends.min())
        case .any:
            let met = indices.filter { statuses[$0] == .met }
            guard !met.isEmpty else { return (false, nil) }
            if met.contains(where: { rule.conditions[$0].usesLocation || windowEnds[$0] == nil }) {
                return (true, nil)
            }
            return (true, met.compactMap { windowEnds[$0] }.max())
        }
    }

    /// Day, time and dates on the guarded clock, in every recent zone.
    static func clockResult(_ condition: ConditionalCondition,
                            clock: ConditionalClockInput) -> ConditionResult {
        guard clock.clockAgrees else { return .unknown(.clockChanged) }
        guard let zones = clock.zones, !zones.isEmpty else { return .unknown(.timeZoneUnknown) }
        let perZone = zones.map { zone -> ConditionResult in
            singleZoneResult(condition, now: clock.guardedNow, calendar: ConditionalDay.gregorian(in: zone))
        }
        guard perZone[0].status == .met else { return perZone[0] }
        guard perZone.allSatisfy({ $0.status == .met }) else { return .unknown(.timeZoneChanged) }
        var result = perZone[0]
        let ends = perZone.compactMap(\.windowEnd)
        // A zone with no end (e.g. every day) doesn't loosen another zone's end.
        result.windowEnd = ends.min()
        return result
    }

    static func singleZoneResult(_ condition: ConditionalCondition, now: Date,
                                 calendar: Calendar) -> ConditionResult {
        switch condition {
        case .days(let days):
            let weekday = calendar.component(.weekday, from: now)
            guard days.contains(weekday) else {
                return ConditionResult(status: .notMet, reason: .notOnDay(weekday: weekday))
            }
            var day = calendar.startOfDay(for: now)
            var end: Date? = nil
            for _ in 0..<7 {
                let next = nextDayStart(after: day, calendar: calendar)
                day = next
                if !days.contains(calendar.component(.weekday, from: next)) { end = next; break }
            }
            return ConditionResult(status: .met, reason: .onDay(weekday: weekday), windowEnd: end)
        case .time(let start, let end):
            let c = calendar.dateComponents([.hour, .minute], from: now)
            let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            let inside = start < end ? (minute >= start && minute < end)
                : (minute >= start || minute < end)
            guard inside, start != end else {
                return ConditionResult(status: .notMet, reason: .outsideWindow(minute: minute))
            }
            let today = calendar.startOfDay(for: now)
            let endDay = start > end && minute >= start ? nextDayStart(after: today, calendar: calendar) : today
            guard let boundary = windowBoundary(end, on: endDay, after: now, calendar: calendar) else {
                return ConditionResult(status: .notMet, reason: .outsideWindow(minute: minute))
            }
            return ConditionResult(status: .met, reason: .inWindow, windowEnd: boundary)
        case .dates(let first, let last):
            let today = ConditionalDay.of(now, in: calendar.timeZone)
            guard first <= today, today <= last else {
                return ConditionResult(status: .notMet, reason: .outsideDates)
            }
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = calendar.timeZone
            let lastStart = gregorian.date(from: DateComponents(year: last.year, month: last.month, day: last.day))
                .map { gregorian.startOfDay(for: $0) }
            let end = lastStart.map { nextDayStart(after: $0, calendar: gregorian) }
            return ConditionResult(status: .met, reason: .inDates, windowEnd: end)
        case .place, .country:
            return .unknown(.notChecked)
        }
    }

    /// The start of the following local day, safe across DST.
    private static func nextDayStart(after dayStart: Date, calendar: Calendar) -> Date {
        let added = calendar.date(byAdding: .day, value: 1, to: dayStart)
            .map { calendar.startOfDay(for: $0) }
        guard let added, added > dayStart else { return dayStart.addingTimeInterval(86_400) }
        return added
    }

    /// A window's end on a given day. A skipped (spring) minute moves to the
    /// next valid time; a repeated (fall) hour uses its first occurrence
    /// unless that has already passed.
    static func windowBoundary(_ minute: Int, on day: Date, after now: Date,
                                       calendar: Calendar) -> Date? {
        for policy in [Calendar.RepeatedTimePolicy.first, .last] {
            if let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0,
                                        of: day, matchingPolicy: .nextTime,
                                        repeatedTimePolicy: policy, direction: .forward),
               date > now { return date }
        }
        return nil
    }

    static func locationResult(_ condition: ConditionalCondition, input: ConditionalLocationInput,
                               free: Bool) -> ConditionResult {
        let fix: ConditionalLocationFix, country: ConditionalCountryLookup?
        switch input {
        case .notRead: return .unknown(.notChecked)
        case .unavailable(let reason): return .unknown(reason)
        case .fix(let value, let lookup): fix = value; country = lookup
        }
        let accuracy = fix.horizontalAccuracy
        guard accuracy.isFinite, accuracy > 0, fix.latitude.isFinite, fix.longitude.isFinite,
              (-90...90).contains(fix.latitude), (-180...180).contains(fix.longitude)
        else { return .unknown(.noFix) }
        guard fix.age.isFinite, fix.age >= -5, fix.age <= maximumFixAge else { return .unknown(.staleFix) }
        guard !fix.isSimulated else { return .unknown(.simulated) }
        if free && fix.isFromAccessory { return .unknown(.accessory) }
        switch condition {
        case .place(let place):
            // A block also takes an approximate fix (the host already treats
            // it as at least 10 km vague): doubt favours the stricter result.
            guard fix.isPrecise || !free else { return .unknown(.needsPrecise) }
            let distance = distanceMeters(fix.latitude, fix.longitude, place.latitude, place.longitude)
            let radius = Double(place.radiusMeters)
            if free {
                // The whole accuracy circle must be inside the place.
                if distance + accuracy <= radius { return ConditionResult(status: .met, reason: .atPlace) }
                if distance - accuracy > radius { return ConditionResult(status: .notMet, reason: .notAtPlace) }
                return .unknown(.imprecise)
            }
            // A block starts if the circle touches the place; only a precise
            // fix whose point is inside reads "You're at …".
            if distance - accuracy > radius { return ConditionResult(status: .notMet, reason: .notAtPlace) }
            return ConditionResult(status: .met,
                                   reason: fix.isPrecise && distance <= radius ? .atPlace : .nearPlace)
        case .country(let code):
            guard let country, country.borderDistanceMeters.isFinite,
                  country.borderDistanceMeters >= 0 else { return .unknown(.countryUnavailable) }
            let inside = country.regionCode?.uppercased() == code.uppercased()
            if !free {
                // Inside is enough; so is a point the fix and the borders
                // can't rule out (near the country, or a spot the dataset
                // can't name next to it). Doubt favours the stricter result.
                if inside { return ConditionResult(status: .met, reason: .inCountry) }
                let reach = accuracy + borderMargin
                let near: Bool
                if let nearby = country.nearbyMeters {
                    near = nearby[code.uppercased()].map { $0.isFinite && $0 <= reach } ?? false
                } else {
                    // The lookup didn't say which country is near: any border
                    // this close leaves the answer in doubt.
                    near = country.borderDistanceMeters <= reach
                }
                return near ? ConditionResult(status: .met, reason: .nearCountry)
                    : ConditionResult(status: .notMet, reason: .notInCountry)
            }
            let clear = country.borderDistanceMeters > accuracy + borderMargin
            if inside && clear { return ConditionResult(status: .met, reason: .inCountry) }
            if !inside && clear { return ConditionResult(status: .notMet, reason: .notInCountry) }
            return .unknown(.nearBorder)
        case .days, .time, .dates:
            return .unknown(.notChecked)
        }
    }

    /// Great-circle (haversine) distance in metres.
    static func distanceMeters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let toRadians = Double.pi / 180
        let dLat = (lat2 - lat1) * toRadians, dLon = (lon2 - lon1) * toRadians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * toRadians) * cos(lat2 * toRadians) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }
}

// MARK: When & where: check-in starts

/// What a check-in proved, kept with the start request. One boolean per
/// condition; never coordinates.
struct ConditionalCheckInStamp: Codable, Equatable {
    var checkInID: UUID
    var guardedAt: Date
    var dayKey: String
    var timeZoneID: String
    var results: [Bool]

    static func make(_ evaluation: ConditionalEvaluation, clock: ConditionalClockInput,
                     checkInID: UUID = UUID()) -> ConditionalCheckInStamp {
        ConditionalCheckInStamp(
            checkInID: checkInID, guardedAt: clock.guardedNow,
            dayKey: ConditionalUses.dayKey(for: clock.guardedNow, calendar: clock.calendar),
            timeZoneID: clock.calendar.timeZone.identifier,
            results: evaluation.results.map { $0.status == .met })
    }
}

struct ConditionalStartRequest: Codable, Equatable {
    var ruleID: UUID
    var revision: Int
    /// Free time: the chosen length (1…rule max). Block: ignored (rule's end).
    var minutes: Int
    var stamp: ConditionalCheckInStamp
}

enum ConditionalStartRefusal: Error, Equatable {
    case ruleMissing, ruleChanged, clockChanged, stampStale, wrongDay, timeZoneMoved
    case conditionsNotMet, invalidLength, alreadyRunning, checkInUsed, noUsesLeft
    case windowEnded, dueChanges, unavailable
}

struct ConditionalStartPlan: Equatable {
    var session: BlockSession
    var uses: [ConditionalUseRecord]
    /// Finished sessions of the same rule, removed so their cleanup can't stop
    /// the new session's activity (both carry the rule's activity name).
    var replacedSessionIDs: [UUID]
}

enum ConditionalStart {
    static let stampLifetime: TimeInterval = 120
    static let minimumSession: TimeInterval = 60

    enum Phase { case queue, apply }

    /// Shared by queue and apply. Free time is fully revalidated in both;
    /// a block that waited its stricter delay is not stale at apply, but
    /// still needs its rule revision and (under all of) its window.
    static func plan(_ request: ConditionalStartRequest, state: LatchState,
                     clock: ConditionalClockInput, phase: Phase = .queue)
        -> Result<ConditionalStartPlan, ConditionalStartRefusal> {
        guard let rule = state.conditionalRules.first(where: { $0.id == request.ruleID })
        else { return .failure(.ruleMissing) }
        guard rule.revision == request.revision, rule.isValid else { return .failure(.ruleChanged) }
        let stamp = request.stamp
        let fresh = phase == .queue || rule.isFreeTime
        if fresh {
            guard clock.clockAgrees else { return .failure(.clockChanged) }
            let age = clock.guardedNow.timeIntervalSince(stamp.guardedAt)
            guard age >= -5, age <= stampLifetime else { return .failure(.stampStale) }
            guard stamp.timeZoneID == clock.calendar.timeZone.identifier else { return .failure(.timeZoneMoved) }
            guard stamp.dayKey == ConditionalUses.dayKey(for: clock.guardedNow, calendar: clock.calendar)
            else { return .failure(.wrongDay) }
        }
        guard stamp.results.count == rule.conditions.count else { return .failure(.conditionsNotMet) }
        // Location results come only from the check-in; day/time/dates are
        // re-evaluated now and must agree with it.
        var statuses: [ConditionStatus] = [], ends: [Date?] = []
        for (index, condition) in rule.conditions.enumerated() {
            if condition.usesLocation {
                statuses.append(stamp.results[index] ? .met : .notMet); ends.append(nil)
            } else {
                let now = ConditionEvaluator.clockResult(condition, clock: clock)
                statuses.append(now.status == .met && stamp.results[index] ? .met : .notMet)
                ends.append(now.windowEnd)
            }
        }
        let decision = ConditionEvaluator.verdict(rule, statuses: statuses, windowEnds: ends)
        guard decision.isMet else { return .failure(.conditionsNotMet) }
        guard !state.sessions.contains(where: {
            $0.conditionalRuleID == rule.id && $0.endsAt > clock.wallNow
        }) else { return .failure(.alreadyRunning) }
        let replaced = state.sessions.filter { $0.conditionalRuleID == rule.id }.map(\.id)
        let capLeft = decision.windowEnd.map { $0.timeIntervalSince(clock.guardedNow) }

        switch rule.outcome {
        case .freeTime(let kind, let selection, let maxMinutes, let usesPerDay):
            guard (1...maxMinutes).contains(request.minutes) else { return .failure(.invalidLength) }
            guard let keys = clock.dayKeys, !keys.isEmpty else { return .failure(.timeZoneMoved) }
            let records = ConditionalUses.pruned(state.conditionalUses, at: clock.guardedNow)
            guard !ConditionalUses.checkInUsed(stamp.checkInID, ruleID: rule.id, in: records)
            else { return .failure(.checkInUsed) }
            guard ConditionalUses.used(ruleID: rule.id, dayKeys: keys, in: records) < usesPerDay
            else { return .failure(.noUsesLeft) }
            let length = min(TimeInterval(request.minutes) * 60, capLeft ?? .infinity)
            guard length >= minimumSession else { return .failure(.windowEnded) }
            var session = BlockSession(name: rule.name, kind: kind,
                                       selection: kind == .free ? FamilyActivitySelection() : selection,
                                       startedAt: clock.wallNow,
                                       endsAt: clock.wallNow.addingTimeInterval(length))
            session.conditionalRuleID = rule.id
            let uses = ConditionalUses.recording(ruleID: rule.id, dayKeys: keys,
                                                 checkInID: stamp.checkInID,
                                                 at: clock.guardedNow, in: records)
            return .success(ConditionalStartPlan(session: session, uses: uses, replacedSessionIDs: replaced))
        case .block(_, let selection, let until):
            let untilLength: TimeInterval
            switch until {
            case .duration(let minutes):
                untilLength = TimeInterval(minutes) * 60
            case .time(let minute):
                // Wall clock, like the session it ends. A repeated fall hour
                // uses its second occurrence once the first has passed.
                let calendar = ConditionalDay.gregorian(in: clock.calendar.timeZone)
                let today = calendar.startOfDay(for: clock.wallNow)
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
                let candidates = ([today] + (tomorrow.map { [$0] } ?? [])).compactMap {
                    ConditionEvaluator.windowBoundary(minute, on: $0, after: clock.wallNow, calendar: calendar)
                }
                guard let end = candidates.first else {
                    return .failure(.windowEnded)
                }
                untilLength = end.timeIntervalSince(clock.wallNow)
            }
            let length = min(untilLength, capLeft ?? .infinity)
            guard length >= minimumSession else { return .failure(.windowEnded) }
            var session = BlockSession(name: rule.name, kind: .block, selection: selection,
                                       startedAt: clock.wallNow,
                                       endsAt: clock.wallNow.addingTimeInterval(length))
            session.conditionalRuleID = rule.id
            return .success(ConditionalStartPlan(session: session, uses: state.conditionalUses,
                                                 replacedSessionIDs: replaced))
        }
    }
}

// MARK: When & where: change summaries (receipt, ledger, contact requests)

/// Names only: place and country names, never coordinates or sizes.
enum ConditionalSummary {
    static func conditionText(_ condition: ConditionalCondition, locale: Locale = .current,
                              calendar: Calendar = .current) -> String {
        switch condition {
        case .place(let place):
            return String(format: tr("at %@"), place.name)
        case .country(let code):
            return String(format: tr("in %@"), locale.localizedString(forRegionCode: code) ?? code)
        case .days(let days):
            if days == Set(1...7) { return tr("every day") }
            if days == Set(2...6) { return tr("on weekdays") }
            if days == [1, 7] { return tr("on weekends") }
            let symbols = calendar.shortWeekdaySymbols
            let names = days.sorted().compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }
            return String(format: tr("on %@"), names.joined(separator: " "))
        case .time(let start, let end):
            return "\(minutesLabel(start))–\(minutesLabel(end))"
        case .dates(let first, let last):
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = calendar.timeZone
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            func text(_ day: ConditionalDay) -> String {
                gregorian.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
                    .map(formatter.string(from:)) ?? "\(day.year)-\(day.month)-\(day.day)"
            }
            return String(format: tr("%@ to %@"), text(first), text(last))
        }
    }

    static func conditionsText(_ rule: ConditionalRule, locale: Locale = .current,
                               calendar: Calendar = .current) -> String {
        let parts = rule.conditions.map { conditionText($0, locale: locale, calendar: calendar) }
        guard var result = parts.first else { return "" }
        let joiner = rule.match == .all ? tr("%@ and %@") : tr("%@ or %@")
        for part in parts.dropFirst() { result = String(format: joiner, result, part) }
        return result
    }

    static func outcomeText(_ outcome: ConditionalOutcome) -> String {
        switch outcome {
        case .freeTime(let kind, _, let minutes, let uses):
            if kind == .unblock {
                return uses == 1 ? String(format: tr("%d min unblocked, once a day"), minutes)
                    : String(format: tr("%d min unblocked, %d times a day"), minutes, uses)
            }
            return uses == 1 ? String(format: tr("%d min free, once a day"), minutes)
                : String(format: tr("%d min free, %d times a day"), minutes, uses)
        case .block(_, _, .time(let minute)):
            return String(format: tr("block until %@"), minutesLabel(minute))
        case .block(_, _, .duration(let minutes)):
            return String(format: tr("block for %d min"), minutes)
        }
    }

    /// "If at Home or 22:00–06:00: block until 07:00."
    static func sentence(_ rule: ConditionalRule, locale: Locale = .current,
                         calendar: Calendar = .current) -> String {
        String(format: tr("If %@: %@."), conditionsText(rule, locale: locale, calendar: calendar),
               outcomeText(rule.outcome))
    }
}
