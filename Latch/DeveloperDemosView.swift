// Developer-only, isolated setup previews. Never enter the legacy replay path:
// it replaces the shared state and reconfigures real Screen Time monitoring.
#if DEBUG
import SwiftUI
import FamilyControls

struct OnboardingDemo {
    let onClose: () -> Void
    let onComplete: (DelayPolicy, AppLimit?, [DayNightGroup], OverridesConfig) -> Void
}

struct DeveloperDemoNotice: View {
    var body: some View {
        Label("Demo only — nothing saves to your setup. No apps are blocked or unblocked.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.black)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.85))
            .accessibilityIdentifier("developer-demo-notice")
    }
}

private enum DeveloperDemoKind: String, Identifiable {
    case onboarding, migration
    var id: String { rawValue }
}

struct DeveloperDemosView: View {
    @State private var demo: DeveloperDemoKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DemoraPageTitle(title: "Setup demos")
                DeveloperDemoNotice()
                VStack(spacing: 0) {
                    Button { demo = .onboarding } label: {
                        GridCard(symbol: "sparkles", title: "New-user onboarding",
                                 subtitle: "the full setup, with simulated permissions and apps")
                    }
                    Button { demo = .migration } label: {
                        GridCard(symbol: "arrow.triangle.2.circlepath", title: "Migrate a previous setup",
                                 subtitle: "random old settings → real migration → 2.0 welcome")
                    }
                }
                .buttonStyle(.plain)
                Text("These previews don't reset your settings, usage, countdowns, contacts, or welcome markers. Your existing rules keep running. You can close a demo at any point.")
                    .font(.footnote).foregroundStyle(Ink.faint)
            }
            .padding(24)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .paper()
        .casedNavigationTitle("Setup demos")
        .toolbar(.visible, for: .navigationBar)
        .fullScreenCover(item: $demo) { kind in
            switch kind {
            case .onboarding: DeveloperOnboardingDemoView()
            case .migration: DeveloperMigrationDemoView()
            }
        }
    }
}

private struct DeveloperOnboardingDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var introPlayed = false
    @State private var finished = false
    @State private var policy = DelayPolicy()
    @State private var limit: AppLimit?
    @State private var dayNightGroups: [DayNightGroup] = []
    @State private var overrides = OverridesConfig()

    var body: some View {
        if !introPlayed {
            RedesignIntroView(onComplete: { introPlayed = true }, isDemo: true,
                              onClose: { dismiss() })
        } else if finished {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        DeveloperDemoNotice()
                        DemoraPageTitle(title: "Sample setup complete")
                        Text(policy.mode.label)
                            .font(.system(.title2, design: .serif))
                        Text("Tightening: \(policy.delay(for: .stricter).shortDelayLabel)")
                        Text("Loosening: \(policy.delay(for: .lenient).shortDelayLabel)")
                        if let limit {
                            Text("\(limit.name) · \(limit.minutesPerDay) min/day")
                            Text("Sample group only — no real Screen Time apps were selected.")
                                .font(.footnote).foregroundStyle(Ink.faint)
                        } else {
                            Text("No first limit selected.")
                        }
                        ForEach(dayNightGroups) { group in
                            Text("\(group.name) · \(group.waitMinutes) min wake-up wait")
                        }
                        Text("\(overrides.contacts.count) contacts · \(overrides.phrasePolicies.count) phrases · \(overrides.passwordPolicies.count) passwords")
                        Button("Try again") {
                            finished = false; introPlayed = false; dayNightGroups = []
                            overrides = OverridesConfig()
                        }
                            .buttonStyle(DemoraPrimaryButtonStyle())
                    }
                    .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
                .paper()
                .toolbar { Button("Close") { dismiss() } }
            }
        } else {
            OnboardingView(demo: OnboardingDemo(onClose: { dismiss() }, onComplete: { policy, limit, groups, overrides in
                self.policy = policy
                self.limit = limit
                self.dayNightGroups = groups
                self.overrides = overrides
                finished = true
            }))
        }
    }
}

/// Owns one randomly named local suite, never the app's App Group. Migration
/// uses exactly the production method with this explicit storage dependency.
final class DeveloperMigrationSample: ObservableObject {
    let suiteName = "demora.developer-migration." + UUID().uuidString
    private let storage: UserDefaults
    @Published private(set) var previous = LatchState()
    @Published private(set) var migrated: LatchState?
    @Published private(set) var error: String?
    private var original = Data()

    init() {
        storage = UserDefaults(suiteName: suiteName)!
        regenerate()
    }

    deinit { storage.removePersistentDomain(forName: suiteName) }

    func regenerate() {
        storage.removePersistentDomain(forName: suiteName)
        migrated = nil
        error = nil
        do {
            var state = LatchState()
            state.isSetUp = true
            state.strictDelay = [300.0, 600, 1800, 3600].randomElement()!
            state.lenientDelay = [1800.0, 3600, 7200, 86400].randomElement()!
            let names = ["Games", "Social", "Videos", "Reading"].shuffled()
            state.limits = names.prefix(Int.random(in: 2...4)).map {
                AppLimit(name: $0, selection: FamilyActivitySelection(),
                         minutesPerDay: [15, 20, 30, 60, 120].randomElement()!,
                         weekdayMinutes: [1: 90, 7: 90],
                         split: LimitSplit(cutoffMinutes: 720, beforeMinutes: 10, carryUnused: Bool.random()))
            }
            state.schedules = [BlockSchedule(name: "Evening focus", mode: .blockSelected,
                selection: FamilyActivitySelection(), startMinutes: [1080, 1200, 1320].randomElement()!,
                endMinutes: 420, recurrence: .weekly([2, 3, 4, 5, 6]))]
            state.exemptions = [ExemptSchedule(name: "Lunch break", startMinutes: 720, endMinutes: 780)]
            let tomorrow = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
            state.planned = [PlannedWindow(name: "Weekend offline", kind: .blockSelected,
                selection: FamilyActivitySelection(), startsAt: tomorrow, endsAt: tomorrow.addingTimeInterval(7200))]
            state.blockAppRemoval = Bool.random()
            state.blockAdultWebsites = Bool.random()
            state.overrides.contactsEnabled = true
            state.overrides.contacts = ["Alex", "Sam", "Robin"].shuffled().prefix(Int.random(in: 1...3)).map {
                TrustedContact(name: $0, kind: .email($0.lowercased() + "@example.invalid"))
            }
            state.overrides.mathEnabled = true
            state.overrides.passwordEnabled = true
            state.overrides.passwordHash = "sample-legacy-hash-not-a-real-secret"
            let now = Date()
            state.pending = [PendingChange(createdAt: now, appliesAt: now.addingTimeInterval(state.lenientDelay),
                direction: .lenient, summary: "Increase \(state.limits[0].name) allowance",
                action: .updateLimitMinutes(id: state.limits[0].id, minutes: state.limits[0].minutesPerDay + 10)),
                PendingChange(createdAt: now, appliesAt: now.addingTimeInterval(state.lenientDelay),
                    direction: .lenient, summary: "Enable old math override",
                    action: .setMathOverride(enabled: true, difficulty: .high, count: 5, wrong: .nothing))]

            // Recreate a pre-2.0 payload rather than encoding new defaults and
            // calling it legacy. Opaque Apple tokens cannot be fabricated;
            // sample group names intentionally carry empty selections.
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
            json.removeValue(forKey: "delayMode")
            json.removeValue(forKey: "wakeRule")
            json.removeValue(forKey: "sleepRule")
            var overrides = json["overrides"] as! [String: Any]
            overrides.removeValue(forKey: "passwordPolicies")
            overrides.removeValue(forKey: "phrasePolicies")
            var contacts = overrides["contacts"] as! [[String: Any]]
            for index in contacts.indices { contacts[index].removeValue(forKey: "allowed") }
            overrides["contacts"] = contacts
            json["overrides"] = overrides
            var limits = json["limits"] as! [[String: Any]]
            limits[0]["pacing"] = ["usageMinutes": 5, "intervalMinutes": 20, "cooldownMinutes": 15]
            json["limits"] = limits
            original = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            storage.set(original, forKey: LatchConstants.stateKey)
            previous = state
        } catch { self.error = error.localizedDescription }
    }

    func migrate() {
        guard error == nil, migrated == nil else { return }
        guard SharedStore.prepareRedesignMigration(in: storage),
              let raw = storage.data(forKey: LatchConstants.stateKey),
              let state = try? JSONDecoder().decode(LatchState.self, from: raw),
              storage.data(forKey: LatchConstants.stateKey + ".preRedesign2") == original,
              state.delayMode == .separate,
              state.strictDelay == previous.strictDelay, state.lenientDelay == previous.lenientDelay,
              state.limits == previous.limits, state.schedules == previous.schedules,
              state.exemptions == previous.exemptions, state.planned == previous.planned,
              state.overrides.contacts == previous.overrides.contacts,
              state.blockAppRemoval == previous.blockAppRemoval,
              state.blockAdultWebsites == previous.blockAdultWebsites,
              state.pending == previous.pending.filter({
                  if case .setMathOverride = $0.action { return false }
                  return true
              }),
              !state.overrides.mathEnabled, !state.overrides.passwordEnabled,
              state.limits.allSatisfy({ $0.pacing == nil }) else {
            error = "The sample migration failed its preservation checks. Your real setup wasn't touched."
            return
        }
        migrated = state
    }

    var offersMathReplacement: Bool {
        guard let migrated else { return false }
        return SharedStore.canReplaceLegacyMath(in: storage, state: migrated)
    }

    var offersDayNightSetup: Bool {
        guard let migrated else { return false }
        return SharedStore.canSetUpInitialDayNight(in: storage, state: migrated)
    }

    func installDayNight(_ groups: [DayNightGroup]) -> Bool {
        guard let migrated,
              let state = SharedStore.initialDayNightState(groups, state: migrated, in: storage),
              let raw = try? JSONEncoder().encode(state) else { return false }
        storage.set(raw, forKey: LatchConstants.stateKey)
        guard storage.data(forKey: LatchConstants.stateKey) == raw else { return false }
        self.migrated = state
        return true
    }

    func installReplacement(_ policies: [PhrasePolicy]) -> Bool {
        guard let migrated,
              let state = SharedStore.mathReplacementState(policies, state: migrated, in: storage),
              let raw = try? JSONEncoder().encode(state) else { return false }
        storage.set(raw, forKey: LatchConstants.stateKey)
        guard storage.data(forKey: LatchConstants.stateKey) == raw else { return false }
        self.migrated = state
        return true
    }
}

private struct DeveloperMigrationDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sample = DeveloperMigrationSample()
    @State private var showWelcome = false
    @State private var introPlayed = false

    var body: some View {
        if showWelcome, let migrated = sample.migrated {
            if !introPlayed {
                RedesignIntroView(onComplete: { introPlayed = true }, isDemo: true,
                                  onClose: { dismiss() })
            } else {
                RedesignWelcomeView(onComplete: { showWelcome = false }, demoState: migrated,
                                    demoMathOffer: sample.offersMathReplacement,
                                    demoInstallPhrases: sample.installReplacement,
                                    demoDayNightOffer: sample.offersDayNightSetup,
                                    demoInstallDayNight: sample.installDayNight)
            }
        } else {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        DeveloperDemoNotice()
                        DemoraPageTitle(title: sample.migrated == nil ? "A random previous setup" : "Carried into 2.0")
                        Text("Sample names and budgets, not your rules. App selections are placeholders; no real contacts are contacted.")
                            .font(.footnote).foregroundStyle(Ink.faint)
                        settings(sample.migrated ?? sample.previous)
                        if let error = sample.error {
                            Text(error).foregroundStyle(Ink.danger)
                        } else if sample.migrated != nil {
                            Label("Migration checks passed", systemImage: "checkmark.circle")
                            Text("IDs, budgets, contacts, delays, and the real-rule pending deadline are unchanged. The raw sample was backed up. Legacy math/password switches and burst pacing are retired; their obsolete pending edit is removed.")
                                .font(.footnote).foregroundStyle(Ink.faint)
                            Button("Preview the 2.0 welcome") { introPlayed = false; showWelcome = true }
                                .buttonStyle(DemoraPrimaryButtonStyle())
                        } else {
                            Text("Legacy settings: math + password on, usage-burst pacing on the first group, two-portion budgets, separate delays, and one obsolete override edit waiting.")
                                .font(.footnote).foregroundStyle(Ink.faint)
                            Button("Run sample migration") { sample.migrate() }
                                .buttonStyle(DemoraPrimaryButtonStyle())
                        }
                        Button("Generate another sample") { sample.regenerate() }
                            .frame(minHeight: 44)
                    }
                    .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
                .paper()
                .toolbar { Button("Close") { dismiss() } }
            }
        }
    }

    private func settings(_ state: LatchState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tightening: \(state.strictDelay.shortDelayLabel) · Loosening: \(state.lenientDelay.shortDelayLabel)")
            ForEach(state.limits) { limit in
                Text("\(limit.name) · \(limit.minutesPerDay) min/day · split at noon")
            }
            ForEach(state.schedules) { schedule in Text("\(schedule.name) · \(schedule.windowLabel)") }
            ForEach(state.exemptions) { period in Text("\(period.name) · \(period.windowLabel)") }
            Text("Planned windows: \(state.planned.count)")
            Text("Contacts: " + state.overrides.contacts.map(\.name).joined(separator: ", "))
            Text("App deletion: \(state.blockAppRemoval ? "blocked" : "allowed") · Adult sites: \(state.blockAdultWebsites ? "blocked" : "allowed")")
            ForEach(state.pending) { change in
                VStack(alignment: .leading, spacing: 4) {
                    Text(change.summary)
                    Text(change.appliesAt, format: .dateTime.month().day().hour().minute().second())
                        .font(.caption).foregroundStyle(Ink.faint)
                }
            }
        }
        .demoraSurface()
    }
}
#endif
