//
//  BetaThanksView.swift
//  Beta tester credits. Names are stored in the CloudKit public database
//  and only shown once approved (flip `approved` to 1 in CloudKit Console),
//  so submissions can be moderated before they appear for everyone.
//

import SwiftUI
import CloudKit

enum BetaThanks {
    static let containerID = "iCloud.may.latch"
    static var database: CKDatabase {
        CKContainer(identifier: containerID).publicCloudDatabase
    }

    struct Tester: Identifiable {
        let id: CKRecord.ID
        let name: String
    }

    static func submit(name: String) async throws {
        let record = CKRecord(recordType: "BetaTester")
        record["name"] = name as CKRecordValue
        record["approved"] = 0 as CKRecordValue
        _ = try await database.save(record)
    }

    static func fetchApproved() async throws -> [Tester] {
        let query = CKQuery(recordType: "BetaTester",
                            predicate: NSPredicate(format: "approved == 1"))
        let (results, _) = try await database.records(matching: query,
                                                      resultsLimit: 200)
        return results
            .compactMap { _, result -> Tester? in
                guard let record = try? result.get(),
                      let name = record["name"] as? String else { return nil }
                return Tester(id: record.recordID, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Settings page

struct BetaTestersView: View {
    @State private var testers: [BetaThanks.Tester] = []
    @State private var loading = true
    @State private var error: String?
    @State private var showJoin = false
    @AppStorage("betaThanksSubmitted") private var submitted = false

    var body: some View {
        List {
            Section {
                Text(tr("Thank you. ❤️"))
                    .font(.subheadline)
            }
            Section(tr("Beta testers")) {
                if loading {
                    ProgressView()
                } else if testers.isEmpty {
                    Text(tr("Names will appear here soon."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(testers) { tester in
                        Label(tester.name, systemImage: "heart.fill")
                    }
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !submitted {
                Section {
                    Button(tr("Add my name…")) { showJoin = true }
                }
            } else {
                Section {
                    Text(tr("Your name is in — it'll show up once approved."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .paper()
        .casedNavigationTitle(tr("Beta testers"))
        .sheet(isPresented: $showJoin) { BetaThanksPromptView() }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            testers = try await BetaThanks.fetchApproved()
            error = nil
        } catch {
            self.error = tr("Couldn't load names (check iCloud/network).")
        }
        loading = false
    }
}

// MARK: - First-launch prompt

struct BetaThanksPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("betaThanksPrompted") private var prompted = false
    @AppStorage("betaThanksSubmitted") private var submitted = false

    @State private var name = ""
    @State private var sending = false
    @State private var done = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 64)).foregroundStyle(.pink)
                Text(tr("Thanks for testing Demora!"))
                    .font(.title2.bold())
                if done {
                    Text(tr("You're in! Your name will appear in the beta testers page once it's approved."))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button(tr("Done")) { dismiss() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text(tr("Want your name in the app's beta-tester thanks page? Pick whatever you'd like to be called."))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    TextField(tr("Your name or nickname"), text: $name)
                        .textFieldStyle(.roundedBorder)
                    Text(tr("Keep it appropriate — names are reviewed, and inappropriate ones won't be added."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Button(sending ? tr("Adding…") : tr("Add me")) {
                        Task { await submit() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || sending)
                    Button(tr("No thanks")) { dismiss() }
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .onAppear { prompted = true }
        }
    }

    private func submit() async {
        sending = true
        defer { sending = false }
        do {
            try await BetaThanks.submit(
                name: name.trimmingCharacters(in: .whitespaces))
            submitted = true
            done = true
        } catch {
            self.error = tr("Couldn't submit — make sure you're signed into iCloud and try again.")
        }
    }
}
