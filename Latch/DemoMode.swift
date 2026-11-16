//
//  DemoMode.swift
//  Debug-only screenshot demo for the App Store and website captures.
//  Launch with `-DemoraDemoMode 1` and optionally `-DemoraDemoScreen
//  today|receipt|changes|rules|whenwhere|insights|skip|session`.
//
//  What it does (all compiled out of Release by the #if below):
//  - `SharedStore.defaults` points at a separate local suite
//    (`DemoModeLaunch`, Shared/SharedStore.swift). `prepare()` wipes it and
//    seeds a mock setup relative to launch time. The App Group is never read
//    or written by the host while the demo runs; extensions never get the
//    launch argument.
//  - Screen Time authorization, housekeeping, monitors, shields, CloudKit and
//    the network time check are skipped (AppModel / LatchApp / AppDelegate).
//    `latch.simulating` is also set, so the engine applies no real shields
//    or monitors even if something runs.
//  - Apple's report and app tokens don't render in the simulator, so the
//    limits card, Insights and app labels are drawn here from mock numbers.
//    App tokens are fake (`demora-demo:<key>`), only so counts are right;
//    names are invented, icons are plain SF Symbol tiles, no real logos.
//  Mock text: invented app names, a first name and a 🏠 place; rule names
//  reuse existing catalog keys through tr(). No new translation keys.
//  Guarded by Tests/DemoModeReleaseHarness.py.
//

#if DEBUG
import SwiftUI
import FamilyControls
import ManagedSettings
import CryptoKit

enum DemoScreen: String {
    case today, receipt, changes, rules, whenwhere, insights, skip, session
}

enum DemoMode {
    static var isOn: Bool { DemoModeLaunch.isOn }

    static let screen: DemoScreen = DemoScreen(
        rawValue: UserDefaults.standard.string(forKey: "DemoraDemoScreen") ?? "") ?? .today

    /// The tab a screen lives on (0 Today, 1 Rules, 2 Insights, 3 You).
    static var initialTab: Int {
        switch screen {
        case .rules, .receipt: return 1
        case .insights: return 2
        case .skip: return 3
        default: return 0
        }
    }

    /// One-shot routing: true once for the launch's screen.
    private static var consumed: Set<DemoScreen> = []
    static func consume(_ target: DemoScreen) -> Bool {
        guard isOn, screen == target, !consumed.contains(target) else { return false }
        consumed.insert(target)
        return true
    }

    // MARK: Fake apps

    struct App: Identifiable {
        let key: String
        let name: String
        let symbol: String
        let color: Color
        var id: String { key }
    }

    static let apps: [App] = [
        App(key: "loopa", name: "Loopa", symbol: "play.rectangle.fill",
            color: Color(red: 0.83, green: 0.33, blue: 0.29)),
        App(key: "chatterly", name: "Chatterly", symbol: "bubble.left.and.bubble.right.fill",
            color: Color(red: 0.24, green: 0.47, blue: 0.80)),
        App(key: "wavely", name: "Wavely", symbol: "music.note",
            color: Color(red: 0.89, green: 0.55, blue: 0.20)),
        App(key: "inkpost", name: "Inkpost", symbol: "newspaper.fill",
            color: Color(red: 0.36, green: 0.42, blue: 0.47)),
        App(key: "picnook", name: "Picnook", symbol: "camera.fill",
            color: Color(red: 0.56, green: 0.34, blue: 0.72)),
        App(key: "tiles", name: "Tiles", symbol: "square.grid.3x3.fill",
            color: Color(red: 0.25, green: 0.60, blue: 0.43)),
        App(key: "pebble", name: "Pebble Run", symbol: "gamecontroller.fill",
            color: Color(red: 0.13, green: 0.58, blue: 0.62)),
    ]

    static func app(_ key: String) -> App { apps.first { $0.key == key }! }

    static func token(_ key: String) -> ApplicationToken {
        let json = #"{"data":""# + Data("demora-demo:\(key)".utf8).base64EncodedString() + #""}"#
        return try! JSONDecoder().decode(ApplicationToken.self, from: Data(json.utf8))
    }

    static func selection(_ keys: [String]) -> FamilyActivitySelection {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = Set(keys.map(token))
        return selection
    }

    /// The fake app behind a demo token, or nil for any other token.
    static func app(for token: ApplicationToken) -> App? {
        guard let json = try? JSONEncoder().encode(token),
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: String],
              let base64 = object["data"], let data = Data(base64Encoded: base64),
              let text = String(data: data, encoding: .utf8),
              text.hasPrefix("demora-demo:") else { return nil }
        let key = String(text.dropFirst("demora-demo:".count))
        return apps.first { $0.key == key }
    }

    /// Demo apps in a selection, in catalogue order.
    static func apps(in selection: FamilyActivitySelection) -> [App] {
        let keys = Set(selection.applicationTokens.compactMap { app(for: $0)?.key })
        return apps.filter { keys.contains($0.key) }
    }

    // MARK: Seed

    static let socialID = UUID(uuidString: "DE000000-0000-4000-8000-000000000001")!
    static let loopaID = UUID(uuidString: "DE000000-0000-4000-8000-000000000002")!
    static let tilesID = UUID(uuidString: "DE000000-0000-4000-8000-000000000003")!
    static let homeRuleID = UUID(uuidString: "DE000000-0000-4000-8000-000000000010")!
    static let home = (latitude: 40.4168, longitude: -3.7038)

    /// Minutes used today, shown by the stand-in limits card.
    static let usedToday: [UUID: Int] = [socialID: 32, loopaID: 24, tilesID: 6]

    /// Wipes the demo suite and writes a fresh mock setup. Call before
    /// anything reads `SharedStore` (LatchApp.init).
    static func prepare() {
        guard isOn else { return }
        let defaults = SharedStore.defaults
        defaults.removePersistentDomain(forName: DemoModeLaunch.suiteName)
        defaults.set(true, forKey: "latch.simulating")
        defaults.set(true, forKey: SharedStore.redesignMigrationKey)
        defaults.set(true, forKey: SharedStore.redesignWelcomeKey)
        defaults.set(true, forKey: SharedStore.redesignIntroKey)
        defaults.set(true, forKey: SharedStore.mathReplacementCapturedKey)
        defaults.set(false, forKey: SharedStore.mathReplacementEligibleKey)
        defaults.set(true, forKey: "latch.healedRaceCondition")
        defaults.set(true, forKey: "latch.languageExpansionUpdate.reviewRequested")
        defaults.set(true, forKey: "latch.languageExpansionUpdate.shown")
        let state = seed(now: Date())
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: LatchConstants.stateKey)
        }
    }

    private static func seed(now: Date) -> LatchState {
        let calendar = Calendar.current
        var state = LatchState()
        state.isSetUp = true
        state.dayNightSetupDone = true
        state.delayPolicy = DelayPolicy(mode: .separate, strictDelay: 5 * 60, lenientDelay: 24 * 3600)

        state.limits = [
            AppLimit(id: socialID, name: tr("Social apps"),
                     selection: selection(["chatterly", "picnook"]), minutesPerDay: 45,
                     extraTime: LimitExtraTime(minutesPerUse: 10, usesPerDay: 1, waitMinutes: 15,
                                               steps: [LimitExtraStep(minutes: 10, waitMinutes: 15)])),
            AppLimit(id: loopaID, name: "Loopa", selection: selection(["loopa"]), minutesPerDay: 30),
            AppLimit(id: tilesID, name: "Tiles", selection: selection(["tiles", "pebble"]),
                     minutesPerDay: 20),
        ]

        // A repeating block running now, a free period later today.
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let start = (minute / 15) * 15 - 60
        let blockStart = (start + 1440) % 1440
        let blockEnd = (start + 180 + 1440) % 1440
        state.schedules = [
            BlockSchedule(name: tr("Deep work"), mode: .blockSelected,
                          selection: selection(["chatterly", "picnook", "loopa"]),
                          startMinutes: blockStart, endMinutes: blockEnd,
                          recurrence: .daily, addedAt: now.addingTimeInterval(-20 * 86_400)),
        ]
        let freeStart = (blockEnd + 120) % 1440
        state.exemptions = [
            ExemptSchedule(name: tr("Free period"), startMinutes: freeStart,
                           endMinutes: (freeStart + 60) % 1440, recurrence: .daily,
                           addedAt: now.addingTimeInterval(-12 * 86_400)),
        ]

        // When & where: free time at home, or on the days that aren't today
        // (so the check-in shows one ✓ and one ✗ and is still met).
        let today = calendar.component(.weekday, from: now)
        let otherDays: Set<Int> = [1, 7].contains(today) ? Set(2...6) : [1, 7]
        state.conditionalRules = [
            ConditionalRule(id: homeRuleID, name: tr("Free time"), match: .any,
                            conditions: [
                                .place(ConditionalPlace(name: "🏠", latitude: home.latitude,
                                                        longitude: home.longitude, radiusMeters: 250)),
                                .days(otherDays),
                            ],
                            outcome: .freeTime(kind: .free, selection: FamilyActivitySelection(),
                                               maxMinutes: 60, usesPerDay: 2),
                            addedAt: now.addingTimeInterval(-5 * 86_400)),
        ]

        // Ways to skip a wait: a contact, a password and a phrase.
        var overrides = OverridesConfig()
        overrides.contactsEnabled = true
        var alex = TrustedContact(name: "Alex", kind: .latchUser(code: "K7P4QX"), accepted: true,
                                  inviteId: "demo-alex",
                                  allowed: [.limitChanges, .scheduleChanges, .sessionChanges, .extraTime])
        alex.avatar = ContactAvatar(style: .symbol, symbol: "heart.fill", colorHex: "#E5484D")
        overrides.contacts = [alex]
        let hash = SHA256.hash(data: Data("demo-only".utf8)).map { String(format: "%02x", $0) }.joined()
        overrides.passwordPolicies = [PasswordPolicy(name: tr("Password"), hash: hash,
                                                     allowed: [.limitChanges, .extraTime])]
        overrides.phrasePolicies = [PhrasePolicy(name: tr("Phrase"), kind: .random(100), allowedErrors: 2,
                                                 allowed: [.scheduleChanges, .sessionChanges])]
        state.overrides = overrides

        // Waiting changes: today, tomorrow and later.
        func pending(_ action: ChangeAction, _ direction: ChangeDirection, created: TimeInterval,
                     applies: TimeInterval) -> PendingChange {
            PendingChange(createdAt: now.addingTimeInterval(created), appliesAt: now.addingTimeInterval(applies),
                          direction: direction, summary: ChangeEngine.summary(for: action, state: state),
                          action: action)
        }
        let evening = BlockSchedule(name: tr("Evening block"), mode: .blockSelected,
                                    selection: selection(["loopa", "pebble"]),
                                    startMinutes: 21 * 60, endMinutes: 23 * 60, recurrence: .daily, addedAt: now)
        let weekends = ExemptSchedule(name: tr("Weekends"), startMinutes: 10 * 60, endMinutes: 12 * 60,
                                      recurrence: .weekly([1, 7]), addedAt: now)
        state.pending = [
            pending(.addSchedule(evening), .stricter, created: -60, applies: 4 * 60 + 10),
            pending(.updateLimitMinutes(id: socialID, minutes: 60), .lenient,
                    created: -(2 * 3600 + 46 * 60), applies: 21 * 3600 + 14 * 60),
            pending(.addExemption(weekends), .lenient,
                    created: -(20 * 3600), applies: 2 * 86_400 + 4 * 3600),
        ]
        return state
    }

    // MARK: Check-in

    /// A precise fix at the demo home, so the check-in shows a met place.
    static var homeFix: ConditionalLocationInput {
        .fix(ConditionalLocationFix(latitude: home.latitude, longitude: home.longitude,
                                    horizontalAccuracy: 12, age: 4), country: nil)
    }

    // MARK: Receipt

    /// A looser edit for the receipt shot: Loopa 30 → 45 min a day.
    static var receiptAction: ChangeAction { .updateLimitMinutes(id: loopaID, minutes: 45) }

    // MARK: Durations

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return String(format: tr("%@ min"), number(minutes)) }
        let rest = minutes % 60
        if rest == 0 { return String(format: tr("%@ h"), number(minutes / 60)) }
        return String(format: tr("%@ h %@ min"), number(minutes / 60), number(rest))
    }

    private static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = AppLanguage.current.locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - App label

/// A plain tile with the fake app's symbol and its invented name.
struct DemoAppLabel: View {
    let app: DemoMode.App
    var iconSize: CGFloat = 26

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous)
                .fill(app.color)
                .frame(width: iconSize, height: iconSize)
                .overlay(Image(systemName: app.symbol)
                    .font(.system(size: iconSize * 0.5, weight: .semibold))
                    .foregroundStyle(.white))
                .accessibilityHidden(true)
            Text(app.name).lineLimit(1)
        }
    }
}

/// Stand-in for `SelectedAppsView` / editor token rows.
struct DemoSelectedApps: View {
    let selection: FamilyActivitySelection

    var body: some View {
        ForEach(DemoMode.apps(in: selection)) { app in
            DemoAppLabel(app: app, iconSize: 22)
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(Ink.ink)
        }
    }
}

// MARK: - Today limits card

/// Draws what the report extension's `LimitsUsageView` draws, from mock minutes.
struct DemoLimitsUsageCard: View {
    @AppAccent private var accent
    @AppLoosen private var loosen
    let limits: [AppLimit]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(limits) { limit in
                    let used = DemoMode.usedToday[limit.id] ?? 0
                    let budget = limit.minutes(on: Date())
                    let spent = used >= budget
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(limit.name)
                                .font(.system(.headline, design: .serif).weight(.regular))
                                .foregroundStyle(Ink.ink)
                                .lineLimit(2)
                            Spacer()
                            Text(spent ? tr("Used up") : String(format: tr("%d of %d min"), used, budget))
                                .font(.system(.subheadline, design: .default).monospacedDigit())
                                .foregroundStyle(spent ? loosen : Ink.inkSoft)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Ink.hairline)
                                Capsule().fill(spent ? loosen : accent)
                                    .frame(width: geo.size.width * min(1, Double(used) / Double(max(1, budget))))
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .padding(.vertical, 4)
            HStack {
                Text("\(tr("Limits")) · \(limits.count)")
                    .demoraType(.meta)
                    .foregroundStyle(Ink.inkSoft)
                Spacer()
                Label(tr("Expand"), systemImage: "chevron.down")
                    .font(.caption).foregroundStyle(accent)
                    .frame(minHeight: 44)
            }
        }
        .paperCard()
    }
}

// MARK: - Insights

/// Draws the report's Day view (week bars + most used apps) from mock numbers.
struct DemoInsightsView: View {
    @AppAccent private var accent
    @Environment(\.locale) private var locale
    @Environment(\.demoraAccentColor) private var accentValue

    /// Minutes per day, oldest first; the last is today so far.
    private let week = [168, 142, 196, 121, 155, 133, 112]
    private let mostUsed: [(String, Int)] = [("loopa", 24), ("chatterly", 21), ("wavely", 17),
                                             ("inkpost", 14), ("picnook", 11), ("tiles", 6)]
    private var tint: Color { Ink.tint(Ink.accentPair(for: accentValue)) }

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                segments
                hero
                chart
                apps
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 32)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper)
    }

    private var segments: some View {
        HStack(spacing: 4) {
            ForEach(["Day", "Week", "Trends"], id: \.self) { key in
                let selected = key == "Day"
                Text(tr(key)).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .padding(.horizontal, 8)
                    .foregroundStyle(selected ? Ink.card : accent)
                    .background(selected ? accent : Color.clear, in: Capsule())
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 4).background(tint, in: Capsule())
        .frame(maxWidth: 360).frame(maxWidth: .infinity)
    }

    private var hero: some View {
        let lastWeek = week.dropLast().reduce(0, +) / 6
        return VStack(alignment: .leading, spacing: 10) {
            Text(tr("Today so far")).demoraType(.label).foregroundStyle(Ink.inkSoft)
            Text(DemoMode.duration(week.last ?? 0))
                .font(.system(size: 52, weight: .regular, design: .serif))
                .tracking(-1).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(accent)
            Text(String(format: tr("Your daily average last week: %@"), DemoMode.duration(lastWeek)))
                .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .paperCard(padding: 20)
    }

    private var chart: some View {
        let maximum = Double(week.max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.backward").frame(width: 44, height: 44)
                    .foregroundStyle(Ink.inkSoft)
                Text(String(format: tr("%@ – %@"), date(days.first!, "MMMd"), date(days.last!, "MMMd")))
                    .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                    .frame(maxWidth: .infinity)
                Image(systemName: "chevron.forward").frame(width: 44, height: 44)
                    .foregroundStyle(Ink.inkSoft).opacity(0.3)
            }
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Rectangle().fill(Ink.hairline).frame(height: 1).padding(.top, 20)
                    Spacer()
                    Rectangle().fill(Ink.hairline).frame(height: 1).padding(.bottom, 28)
                }
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { index, minutes in
                        let selected = index == week.count - 1
                        VStack(spacing: 8) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selected ? accent : accent.opacity(0.34))
                                .frame(width: 22, height: max(2, Double(minutes) / maximum * 130))
                            Text(date(days[index], "EEE")).demoraType(.chip)
                                .foregroundStyle(selected ? accent : Ink.inkSoft)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 20)
                Text(DemoMode.duration(week.max() ?? 0)).demoraType(.chip).foregroundStyle(Ink.inkSoft)
            }
            .frame(height: 180)
        }
        .paperCard()
    }

    private var apps: some View {
        let maximum = Double(mostUsed.first?.1 ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(tr("Most used apps"))
            VStack(alignment: .leading, spacing: 14) {
                ForEach(mostUsed, id: \.0) { key, minutes in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            DemoAppLabel(app: DemoMode.app(key))
                                .demoraType(.body).foregroundStyle(Ink.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(DemoMode.duration(minutes)).font(.system(.subheadline, design: .serif))
                                .monospacedDigit().foregroundStyle(accent)
                        }
                        GeometryReader { geometry in
                            Capsule().fill(tint)
                            Capsule().fill(accent.opacity(0.45))
                                .frame(width: geometry.size.width * Double(minutes) / maximum)
                        }
                        .frame(height: 4)
                    }
                    .frame(minHeight: 44)
                }
            }
            .paperCard()
            Text(tr("App times overlap, so they won't add up to your total."))
                .demoraType(.meta).foregroundStyle(Ink.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func date(_ date: Date, _ template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
#endif
