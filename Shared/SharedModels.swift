//
//  SharedModels.swift
//  Latch
//

import Foundation
import FamilyControls
import ManagedSettings

// MARK: - Constants

enum LatchConstants {
    /// App Group for shared state. The dev build (a separate app with a `.dev`
    /// bundle id) uses its own group so it never shares — or corrupts — the
    /// production app's data. Derived from the bundle id, so this is inert
    /// until the dev bundle id actually exists; both must be listed in the
    /// entitlements / registered for the build to use them.
    static let appGroupID: String = {
        let base = "group.com.may.screentimedelay"
        let id = Bundle.main.bundleIdentifier ?? ""
        let isDev = id.hasSuffix(".dev") || id.contains(".dev.")
        return isDev ? base + ".dev" : base
    }()
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

    enum Kind: Codable, Equatable {
        case email(String)
        case latchUser(code: String)
    }

    init(id: UUID = UUID(), name: String, kind: Kind,
         accepted: Bool = true, inviteId: String = "") {
        self.id = id
        self.name = name
        self.kind = kind
        self.accepted = accepted
        self.inviteId = inviteId
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

    var anyEnabled: Bool {
        mathEnabled || passwordEnabled
            || (contactsEnabled && contacts.contains { $0.isUsable })
    }

    init() {}

    /// Tolerant decode so configs saved before newer fields existed load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mathEnabled = try c.decodeIfPresent(Bool.self, forKey: .mathEnabled) ?? false
        mathDifficulty = try c.decodeIfPresent(MathDifficulty.self, forKey: .mathDifficulty)
        mathQuestionCount = try c.decodeIfPresent(Int.self, forKey: .mathQuestionCount) ?? 3
        mathWrongBehavior = try c.decodeIfPresent(MathWrongBehavior.self, forKey: .mathWrongBehavior) ?? .nothing
        passwordEnabled = try c.decodeIfPresent(Bool.self, forKey: .passwordEnabled) ?? false
        passwordHash = try c.decodeIfPresent(String.self, forKey: .passwordHash)
        contactsEnabled = try c.decodeIfPresent(Bool.self, forKey: .contactsEnabled) ?? false
        contacts = try c.decodeIfPresent([TrustedContact].self, forKey: .contacts) ?? []
    }
}

// MARK: - App limits

struct AppLimit: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String                       // user label, e.g. "Instagram"
    var selection: FamilyActivitySelection // apps/categories it covers
    var minutesPerDay: Int
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
        if m < end { anchor = date.addingTimeInterval(-86400) }
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

// MARK: - Active state

/// The *currently enforced* configuration. Only the ChangeEngine mutates this,
/// and only when a pending change's timer has elapsed (or was overridden).
struct LatchState: Codable {
    var isSetUp = false
    var strictDelay: TimeInterval = 0   // gates "more strict" changes
    var lenientDelay: TimeInterval = 0  // gates "less strict" changes
    var limits: [AppLimit] = []
    var overrides = OverridesConfig()
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
        strictDelay = try c.decodeIfPresent(TimeInterval.self, forKey: .strictDelay) ?? 0
        lenientDelay = try c.decodeIfPresent(TimeInterval.self, forKey: .lenientDelay) ?? 0
        limits = try c.decodeIfPresent([AppLimit].self, forKey: .limits) ?? []
        overrides = try c.decodeIfPresent(OverridesConfig.self, forKey: .overrides) ?? OverridesConfig()
        pending = try c.decodeIfPresent([PendingChange].self, forKey: .pending) ?? []
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
    case addLimit(AppLimit)
    case updateLimitMinutes(id: UUID, minutes: Int)
    case removeLimit(id: UUID)
    case setStrictDelay(TimeInterval)
    case setLenientDelay(TimeInterval)
    case setMathOverride(enabled: Bool, difficulty: MathDifficulty?,
                         count: Int, wrong: MathWrongBehavior)
    case setPasswordOverride(enabled: Bool, passwordHash: String?)
    case setContactsOverride(enabled: Bool)
    case addContact(TrustedContact)
    case removeContact(id: UUID)
    case addSchedule(BlockSchedule)
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
