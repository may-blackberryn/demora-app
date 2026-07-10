//
//  ContactsService.swift
//  Networking for the trusted-contact override.
//
//  Email contacts: a Cloudflare Worker (Backend/worker.js) generates a
//  6-digit code, emails it to the contact, and verifies entries — the code
//  never touches this device until the contact shares it.
//
//  Latch-user contacts: requests and approvals are relayed through the
//  CloudKit public database. Each install has a short "buddy code"; an
//  override request creates an OverrideRequest record per chosen approver,
//  and approvers answer by creating an OverrideApproval record.
//

import Foundation
import CloudKit

// MARK: - Email codes (worker)

enum EmailCodeError: Error { case rateLimited(global: Bool), attestationRejected }

enum EmailCodeService {
    static var isConfigured: Bool {
        !LatchConstants.overrideWorkerURL.isEmpty
            && !LatchConstants.overrideAppToken.isEmpty
    }

    /// No paid tier — everyone is on the free email cap, which the Worker
    /// enforces server-side. Kept in the request payload for wire compatibility.
    static var isPro: Bool { false }

    static func requestCode(requestId: String, emails: [String],
                            summary: String) async throws {
        // App-Attested: the Worker rejects this call unless it carries a valid
        // assertion from a genuine app install (see AppAttest).
        _ = try await postAttested("request-code", [
            "requestId": requestId,
            "emails": emails,
            "summary": summary,
            "locale": AppLanguage.current.rawValue,
            "sender": ContactsRelay.myCode,
            "pro": isPro,
        ])
    }

    /// Email an invite code to a brand-new email contact. They share the code
    /// back, the owner enters it, and only then can the contact approve.
    /// Reuses the code infrastructure under an "invite-" requestId namespace.
    static func sendInviteCode(inviteId: String, email: String,
                               ownerName: String) async throws {
        _ = try await postAttested("request-code", [
            "requestId": "invite-" + inviteId,
            "emails": [email],
            "summary": ownerName,
            "locale": AppLanguage.current.rawValue,
            "sender": ContactsRelay.myCode,
            "pro": isPro,
            "kind": "invite",
        ])
    }

    /// Verify the invite code an email contact shared back.
    static func verifyInvite(inviteId: String, code: String) async throws -> Bool {
        try await verify(requestId: "invite-" + inviteId, code: code)
    }

    /// One-time challenge (nonce) from the Worker, for attestation/assertions.
    static func challenge() async throws -> String {
        let r = try await post("challenge", [:])
        guard let c = r["challenge"] as? String else { throw URLError(.badServerResponse) }
        return c
    }

    /// Register this device's attested public key with the Worker.
    static func registerAttestation(keyId: String, challenge: String,
                                    attestation: Data) async throws {
        _ = try await post("attest", [
            "keyId": keyId,
            "challenge": challenge,
            "attestation": attestation.base64EncodedString(),
        ])
    }

    /// Daily/monthly send counts for the send page.
    struct Usage {
        var today = 0, perDayMax = 5
        var dailyTotal = 0, dailyMax = 100
        var monthlyTotal = 0, monthlyMax = 3000
    }

    static func usage() async throws -> Usage {
        let r = try await post("usage", ["sender": ContactsRelay.myCode,
                                         "pro": isPro])
        func i(_ k: String, _ fallback: Int) -> Int { (r[k] as? Int) ?? fallback }
        return Usage(today: i("today", 0), perDayMax: i("perDayMax", 5),
                     dailyTotal: i("dailyTotal", 0), dailyMax: i("dailyMax", 100),
                     monthlyTotal: i("monthlyTotal", 0), monthlyMax: i("monthlyMax", 3000))
    }

    static func verify(requestId: String, code: String) async throws -> Bool {
        let result = try await post("verify", [
            "requestId": requestId,
            "code": code,
        ])
        return (result["valid"] as? Bool) == true
    }

    private static func post(_ path: String,
                             _ payload: [String: Any]) async throws -> [String: Any] {
        var body = payload
        body["token"] = LatchConstants.overrideAppToken
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await send(path, body: data, headers: [:])
    }

    /// Like `post`, but attaches an App Attest assertion over the exact body
    /// bytes so the Worker can confirm the call came from a genuine app install.
    private static func postAttested(_ path: String,
                                     _ payload: [String: Any]) async throws -> [String: Any] {
        var body = payload
        body["token"] = LatchConstants.overrideAppToken
        let data = try JSONSerialization.data(withJSONObject: body)
        do {
            let headers = try await AppAttest.assertionHeaders(for: data)
            return try await send(path, body: data, headers: headers)
        } catch EmailCodeError.attestationRejected {
            // The Worker didn't recognize our key (its registration was lost).
            // Re-attest and try one more time before surfacing an error.
            AppAttest.markNeedsReregistration()
            let headers = try await AppAttest.assertionHeaders(for: data)
            return try await send(path, body: data, headers: headers)
        }
    }

    private static func send(_ path: String, body data: Data,
                             headers: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: LatchConstants.overrideWorkerURL)?
            .appendingPathComponent(path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = data

        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 429 {
            let obj = (try? JSONSerialization.jsonObject(with: respData)) as? [String: Any]
            throw EmailCodeError.rateLimited(global: (obj?["scope"] as? String) == "global")
        }
        // The Worker rejects a missing/unknown attestation with 401 + scope
        // "attest". Signal it distinctly so the caller can re-register and retry.
        if http.statusCode == 401 {
            let obj = (try? JSONSerialization.jsonObject(with: respData)) as? [String: Any]
            if (obj?["scope"] as? String) == "attest" {
                throw EmailCodeError.attestationRejected
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return (try? JSONSerialization.jsonObject(with: respData) as? [String: Any]) ?? [:]
    }
}

// MARK: - Latch-user relay (CloudKit)

struct IncomingRequest: Identifiable {
    let id: CKRecord.ID
    let requestId: String
    let summary: String
    let createdAt: Date
    let requesterName: String
    let requesterCode: String
}

enum ContactsRelay {
    static var database: CKDatabase {
        CKContainer(identifier: BetaThanks.containerID).publicCloudDatabase
    }

    private static let codeKey = "latch.buddyCode"
    private static let registeredKey = "latch.buddyCodeRegistered"
    private static let handledKey = "latch.handledRequestRecords"
    private static let sentEmailKey = "latch.sentEmailRequests"
    private static let sentRelayKey = "latch.sentRelayRequests"
    private static let requestTTL: TimeInterval = 3600
    private static let nameKey = "latch.myName"

    /// Short code identifying this install; shown in Settings so a friend
    /// can add you as their approver.
    static var myCode: String {
        let defaults = SharedStore.defaults
        if let code = defaults.string(forKey: codeKey) { return code }
        let alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        let code = String((0..<6).map { _ in alphabet.randomElement()! })
        defaults.set(code, forKey: codeKey)
        return code
    }

    /// Optional display name shown to people you ask to approve, so they
    /// know who's requesting (and who has added them).
    static var myName: String {
        get { SharedStore.defaults.string(forKey: nameKey) ?? "" }
        set { SharedStore.defaults.set(newValue, forKey: nameKey) }
    }

    /// Publish my code so others can validate it when adding me.
    static func registerSelfIfNeeded() async {
        let defaults = SharedStore.defaults
        guard !defaults.bool(forKey: registeredKey) else { return }
        let record = CKRecord(recordType: "LatchUser")
        record["code"] = myCode as CKRecordValue
        if (try? await database.save(record)) != nil {
            defaults.set(true, forKey: registeredKey)
        }
    }

    static func codeExists(_ code: String) async throws -> Bool {
        let query = CKQuery(recordType: "LatchUser",
                            predicate: NSPredicate(format: "code == %@", code))
        let (results, _) = try await database.records(matching: query,
                                                      resultsLimit: 1)
        return !results.isEmpty
    }

    // MARK: Requester side

    static func sendRequests(requestId: String, approverCodes: [String],
                             summary: String) async throws {
        // Remember who we asked, so a forged approval from a code we never
        // asked is ignored (see `decisions`).
        recordAskedApprovers(requestId: requestId, codes: approverCodes)
        for approver in approverCodes {
            let record = CKRecord(recordType: "OverrideRequest")
            record["requestId"] = requestId as CKRecordValue
            record["requesterCode"] = myCode as CKRecordValue
            record["approverCode"] = approver as CKRecordValue
            // Encrypt the summary for contacts we share a key with (from the
            // invite handshake); fall back to plaintext for legacy contacts.
            if let cipher = ContactCrypto.encrypt(summary, forCode: approver) {
                record["summary"] = cipher as CKRecordValue
                record["enc"] = 1 as NSNumber
            } else {
                record["summary"] = summary as CKRecordValue
                record["enc"] = 0 as NSNumber
            }
            record["requesterName"] = myName as CKRecordValue
            record["status"] = "pending" as CKRecordValue
            _ = try await database.save(record)
        }
    }

    // Approver codes we asked per request (local, the trusted source of truth).
    private static let askedKey = "latch.askedApprovers"
    private static func recordAskedApprovers(requestId: String, codes: [String]) {
        var d = (SharedStore.defaults.dictionary(forKey: askedKey)
                 as? [String: [String]]) ?? [:]
        d[requestId] = codes
        SharedStore.defaults.set(d, forKey: askedKey)
    }
    private static func askedApprovers(requestId: String) -> [String] {
        ((SharedStore.defaults.dictionary(forKey: askedKey)
          as? [String: [String]]) ?? [:])[requestId] ?? []
    }

    struct Decisions {
        var approved = false
        var denied = false
    }

    /// Decisions made after `since` (re-sends reuse the requestId, so older
    /// denials from a previous round are ignored). Any approval unlocks.
    static func decisions(requestId: String, since: Date) async throws -> Decisions {
        let query = CKQuery(
            recordType: "OverrideApproval",
            predicate: NSPredicate(format: "requestId == %@", requestId))
        let (results, _) = try await database.records(matching: query,
                                                      resultsLimit: 20)
        let asked = Set(askedApprovers(requestId: requestId))
        var out = Decisions()
        // `since` is a local Date(); a device clock running ahead would make it
        // later than the server's real creationDate and silently drop a genuine
        // approval forever. A small negative tolerance absorbs that skew while
        // staying well inside the request's lifetime.
        let cutoff = since.addingTimeInterval(-300)
        for (_, result) in results {
            guard let record = try? result.get(),
                  let created = record.creationDate, created >= cutoff,
                  let approver = record["approverCode"] as? String,
                  let decision = record["decision"] as? String
            else { continue }
            // Only trust approvals from contacts we actually asked. (Empty set =
            // a legacy request with no record; keep old behavior.)
            if !asked.isEmpty && !asked.contains(approver) { continue }
            // For any contact we share a key with, require a valid signature —
            // this is what blocks a forged "approved". Legacy (keyless) contacts
            // fall through unsigned, as before.
            if ContactCrypto.hasKey(forCode: approver) {
                guard ContactCrypto.verify(record["auth"] as? String,
                                           requestId: requestId, decision: decision,
                                           forCode: approver) else { continue }
            }
            switch decision {
            case "approved": out.approved = true
            case "denied": out.denied = true
            default: break
            }
        }
        return out
    }

    /// Delete my own request records once resolved or abandoned.
    static func cleanup(requestId: String) async {
        let query = CKQuery(
            recordType: "OverrideRequest",
            predicate: NSPredicate(format: "requestId == %@", requestId))
        guard let (results, _) = try? await database.records(matching: query,
                                                             resultsLimit: 20)
        else { return }
        for (recordID, _) in results {
            _ = try? await database.deleteRecord(withID: recordID)
        }
    }

    // MARK: Background approval (CloudKit push)
    //
    // Without this, an approval only applies while the app is open (the app
    // polls in `checkContactApprovals`). A CloudKit subscription asks Apple's
    // servers to send a silent push when an OverrideApproval addressed to us is
    // created, waking the app briefly in the background to apply it.

    static let approvalSubscriptionID = "override-approvals-v1"
    private static let approvalSubRegisteredKey = "latch.approvalSubRegistered.v1"

    /// Register the approval push subscription once. Safe to call on every
    /// launch — it no-ops after the first success, and retries if it failed
    /// (e.g. the device wasn't signed into iCloud yet).
    static func ensureApprovalSubscription() {
        guard !SharedStore.defaults.bool(forKey: approvalSubRegisteredKey) else { return }
        let code = myCode
        guard !code.isEmpty else { return }
        let sub = CKQuerySubscription(
            recordType: "OverrideApproval",
            predicate: NSPredicate(format: "requesterCode == %@", code),
            subscriptionID: approvalSubscriptionID,
            options: [.firesOnRecordCreation])
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true   // silent (background) push
        sub.notificationInfo = info
        let op = CKModifySubscriptionsOperation(subscriptionsToSave: [sub],
                                                subscriptionIDsToDelete: [])
        op.modifySubscriptionsResultBlock = { result in
            if case .success = result {
                SharedStore.defaults.set(true, forKey: approvalSubRegisteredKey)
            }
        }
        database.add(op)
    }

    /// Fetch approvals for our outstanding relay requests and apply them via the
    /// engine (no UI), so this works from a background push. Returns whether it
    /// applied anything. Mirrors AppModel.checkContactApprovals, minus the UI.
    @discardableResult
    static func processApprovalsInBackground() async -> Bool {
        let relayRequests = outgoingRequests().filter(\.relay)
        guard !relayRequests.isEmpty else { return false }
        var appliedAny = false
        for req in relayRequests {
            let since = relaySentDate(req.requestId) ?? .distantPast
            guard let decision = try? await decisions(requestId: req.requestId, since: since),
                  decision.approved else { continue }
            clearSent(req.requestId)
            clearOutgoing(req.requestId)
            await cleanup(requestId: req.requestId)
            let state = SharedStore.loadState()
            for change in state.pending where req.changeIds.contains(change.id) {
                ChangeEngine.applyNow(change)
                appliedAny = true
            }
        }
        return appliedAny
    }

    // MARK: Approver side

    static func pendingRequestsForMe() async throws -> [IncomingRequest] {
        let query = CKQuery(
            recordType: "OverrideRequest",
            predicate: NSPredicate(format: "approverCode == %@", myCode))
        let (results, _) = try await database.records(matching: query,
                                                      resultsLimit: 50)
        let handled = handledRequestIds()
        return results.compactMap { _, result -> IncomingRequest? in
            guard let record = try? result.get(),
                  let requestId = record["requestId"] as? String,
                  let rawSummary = record["summary"] as? String,
                  let created = record.creationDate,
                  record["status"] as? String == "pending",
                  // Tracked per record (not per requestId) so a re-sent
                  // request shows up again after a denial.
                  !handled.contains(record.recordID.recordName),
                  Date().timeIntervalSince(created) < requestTTL
            else { return nil }
            let requesterCode = record["requesterCode"] as? String ?? ""
            // Decrypt with the key from the invite handshake. If we can't, the
            // contact predates key exchange — prompt a re-add.
            let summary: String
            if (record["enc"] as? Int ?? 0) == 1 {
                summary = ContactCrypto.decrypt(rawSummary, forCode: requesterCode)
                    ?? tr("Encrypted request — re-add this contact to read it.")
            } else {
                summary = rawSummary
            }
            return IncomingRequest(
                id: record.recordID, requestId: requestId, summary: summary,
                createdAt: created,
                requesterName: record["requesterName"] as? String ?? "",
                requesterCode: requesterCode)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func respond(to request: IncomingRequest, approve: Bool) async throws {
        let decision = approve ? "approved" : "denied"
        let record = CKRecord(recordType: "OverrideApproval")
        record["requestId"] = request.requestId as CKRecordValue
        record["approverCode"] = myCode as CKRecordValue
        // The requester's code, so they can subscribe for a background push when
        // an approval addressed to them lands (see ensureApprovalSubscription).
        record["requesterCode"] = request.requesterCode as CKRecordValue
        record["decision"] = decision as CKRecordValue
        // Sign with the key from the invite handshake so the requester can tell
        // a real approval from a forged one (no-op for legacy keyless contacts).
        if let auth = ContactCrypto.sign(requestId: request.requestId,
                                         decision: decision,
                                         forCode: request.requesterCode) {
            record["auth"] = auth as CKRecordValue
        }
        _ = try await database.save(record)
        markHandled(request.id.recordName)
    }

    // Request records I've already answered (so the inbox doesn't re-show
    // them — approvers can't edit the requester's records in the public DB).
    private static func handledRequestIds() -> Set<String> {
        Set(SharedStore.defaults.stringArray(forKey: handledKey) ?? [])
    }
    private static func markHandled(_ recordName: String) {
        var ids = handledRequestIds()
        ids.insert(recordName)
        SharedStore.defaults.set(Array(Array(ids).suffix(200)), forKey: handledKey)
    }

    // MARK: Sent-request memory (so approval works after the sheet closes)
    //
    // Stored as [requestId: sentAt timestamp]. The timestamp matters:
    // re-sending after a denial reuses the same requestId, so only
    // decisions created after the latest send count.

    private static func sentDict(_ key: String) -> [String: Double] {
        (SharedStore.defaults.dictionary(forKey: key) as? [String: Double]) ?? [:]
    }
    private static func saveSentDict(_ dict: [String: Double], _ key: String) {
        SharedStore.defaults.set(dict, forKey: key)
    }

    static func markSent(requestId: String, relay: Bool) {
        let key = relay ? sentRelayKey : sentEmailKey
        var dict = sentDict(key)
        dict[requestId] = Date().timeIntervalSince1970
        saveSentDict(dict, key)
    }
    static func wasSentEmail(_ requestId: String) -> Bool {
        sentDict(sentEmailKey)[requestId] != nil
    }
    static func wasSentRelay(_ requestId: String) -> Bool {
        sentDict(sentRelayKey)[requestId] != nil
    }
    static func relaySentDate(_ requestId: String) -> Date? {
        sentDict(sentRelayKey)[requestId].map(Date.init(timeIntervalSince1970:))
    }
    static func clearSent(_ requestId: String) {
        for key in [sentEmailKey, sentRelayKey] {
            var dict = sentDict(key)
            dict.removeValue(forKey: requestId)
            saveSentDict(dict, key)
        }
    }

    // MARK: - Outgoing requests (for the Home "awaiting approval" list)
    //
    // One entry per contact request you've sent that's still waiting. Keyed by
    // requestId; remembers which pending change(s) it covers so Home can reopen
    // the gate (e.g. to enter an email code) and apply them all on approval.

    private static let outgoingKey = "latch.outgoingRequests"

    struct OutgoingRequest: Codable, Identifiable {
        var requestId: String
        var changeIds: [UUID]
        var email: Bool
        var relay: Bool
        var sentAt: Double
        var id: String { requestId }
    }

    private static func outgoingDict() -> [String: OutgoingRequest] {
        guard let data = SharedStore.defaults.data(forKey: outgoingKey),
              let d = try? JSONDecoder().decode([String: OutgoingRequest].self, from: data)
        else { return [:] }
        return d
    }
    private static func saveOutgoing(_ d: [String: OutgoingRequest]) {
        if let data = try? JSONEncoder().encode(d) {
            SharedStore.defaults.set(data, forKey: outgoingKey)
        }
    }
    static func recordOutgoing(requestId: String, changeIds: [UUID],
                               email: Bool, relay: Bool) {
        #if DEBUG
        print("📤 recordOutgoing req=\(requestId.prefix(8)) changeIds=\(changeIds.count)")
        #endif
        var d = outgoingDict()
        d[requestId] = OutgoingRequest(requestId: requestId, changeIds: changeIds,
                                       email: email, relay: relay,
                                       sentAt: Date().timeIntervalSince1970)
        saveOutgoing(d)
    }
    static func outgoingRequests() -> [OutgoingRequest] {
        outgoingDict().values.sorted { $0.sentAt > $1.sentAt }
    }
    static func clearOutgoing(_ requestId: String) {
        var d = outgoingDict()
        d.removeValue(forKey: requestId)
        saveOutgoing(d)
    }

    // MARK: - Contact invites (consent)
    //
    // Adding a Demora-user contact doesn't make them an approver immediately:
    // they receive an invite and must accept first. Mirrors the request/
    // approval pattern — the inviter creates a ContactInvite, the invitee
    // answers with a ContactInviteResponse.

    private static let sentInviteKey = "latch.sentInvites"       // [toCode]
    private static let handledInviteKey = "latch.handledInvites" // [recordName]
    private static let inviteTTL: TimeInterval = 30 * 86400

    struct IncomingInvite: Identifiable {
        let id: CKRecord.ID
        let fromCode: String
        let fromName: String
        let inviteId: String
        let createdAt: Date
        let fromPubKey: String
    }

    /// Send (once per inviteId) an invite asking `toCode` to accept being my
    /// trusted contact.
    static func sendInvite(toCode: String, inviteId: String) async {
        var sent = Set(SharedStore.defaults.stringArray(forKey: sentInviteKey) ?? [])
        guard !sent.contains(inviteId) else { return }
        await registerSelfIfNeeded()
        let record = CKRecord(recordType: "ContactInvite")
        record["fromCode"] = myCode as CKRecordValue
        record["toCode"] = toCode as CKRecordValue
        record["fromName"] = myName as CKRecordValue
        record["inviteId"] = inviteId as CKRecordValue
        record["fromPubKey"] = ContactCrypto.myPublicKey as CKRecordValue
        guard (try? await database.save(record)) != nil else { return }
        sent.insert(inviteId)
        SharedStore.defaults.set(Array(sent), forKey: sentInviteKey)
    }

    static var hasSentInvites: Bool {
        !(SharedStore.defaults.stringArray(forKey: sentInviteKey) ?? []).isEmpty
    }

    /// Delete my outgoing invites whose id isn't among my current contacts
    /// (removed, or replaced by a re-add) and prune the local sent set. This is
    /// what makes me drop off the other person's "people you approve for" list.
    static func reconcileSentInvites(currentInviteIds: Set<String>) async {
        let query = CKQuery(recordType: "ContactInvite",
                            predicate: NSPredicate(format: "fromCode == %@", myCode))
        if let mine = (try? await database.records(matching: query, resultsLimit: 100))?.0 {
            for (recordID, result) in mine {
                guard let r = try? result.get() else { continue }
                let iid = r["inviteId"] as? String ?? ""
                if !currentInviteIds.contains(iid) {
                    _ = try? await database.deleteRecord(withID: recordID)
                }
            }
        }
        let pruned = Set(SharedStore.defaults.stringArray(forKey: sentInviteKey) ?? [])
            .intersection(currentInviteIds)
        SharedStore.defaults.set(Array(pruned), forKey: sentInviteKey)
    }

    /// Invites addressed to me (someone wants to add me as their contact).
    static func incomingInvites() async throws -> [IncomingInvite] {
        let query = CKQuery(recordType: "ContactInvite",
                            predicate: NSPredicate(format: "toCode == %@", myCode))
        let (results, _) = try await database.records(matching: query,
                                                      resultsLimit: 50)
        let handled = Set(SharedStore.defaults.stringArray(forKey: handledInviteKey) ?? [])
        let blocked = Set(SharedStore.defaults.stringArray(forKey: blockedCodesKey) ?? [])
        var byOwner: [String: IncomingInvite] = [:]
        for (_, result) in results {
            guard let record = try? result.get(),
                  let from = record["fromCode"] as? String,
                  let created = record.creationDate
            else { continue }
            let fromName = record["fromName"] as? String ?? ""
            let iid = record["inviteId"] as? String ?? ""
            // Blocked sender: silently decline so their request resolves, hide it.
            if blocked.contains(from) {
                if !handled.contains(record.recordID.recordName) {
                    try? await upsertResponse(ownerCode: from, accepted: false,
                                              ownerName: fromName, inviteId: iid)
                    markInviteHandled(record.recordID.recordName)
                    recordRequest(code: from, name: fromName, action: "declined")
                }
                continue
            }
            guard !handled.contains(record.recordID.recordName),
                  Date().timeIntervalSince(created) < inviteTTL
            else { continue }
            recordRequest(code: from, name: fromName, action: "received")
            // If the same owner has more than one outstanding invite, keep the
            // newest so a re-add supersedes an old one.
            if let existing = byOwner[from], existing.createdAt >= created { continue }
            byOwner[from] = IncomingInvite(id: record.recordID, fromCode: from,
                fromName: fromName, inviteId: iid, createdAt: created,
                fromPubKey: record["fromPubKey"] as? String ?? "")
        }
        return byOwner.values.sorted { $0.createdAt > $1.createdAt }
    }

    /// Accept or decline an incoming invite. Upserts a single response per
    /// (inviter → me) pair so a later revoke updates the same record.
    static func respondToInvite(_ invite: IncomingInvite, accept: Bool) async throws {
        // Trust the inviter's public key from the invite handshake (the only
        // place we accept a peer key) so future requests from them can be
        // decrypted and their approvals verified.
        if accept {
            ContactCrypto.storePeerKey(code: invite.fromCode,
                                       publicKey: invite.fromPubKey)
        }
        try await upsertResponse(ownerCode: invite.fromCode, accepted: accept,
                                 ownerName: invite.fromName, inviteId: invite.inviteId)
        markInviteHandled(invite.id.recordName)
        recordRequest(code: invite.fromCode, name: invite.fromName,
                      action: accept ? "accepted" : "declined")
    }

    private static func markInviteHandled(_ recordName: String) {
        var handled = Set(SharedStore.defaults.stringArray(forKey: handledInviteKey) ?? [])
        handled.insert(recordName)
        SharedStore.defaults.set(Array(Array(handled).suffix(200)), forKey: handledInviteKey)
    }

    /// One ContactInviteResponse per (ownerCode → me): reused for accept,
    /// decline, and revoke, so the owner always reads the latest answer. The
    /// `inviteId` ties the answer to a specific add.
    private static func upsertResponse(ownerCode: String, accepted: Bool,
                                       ownerName: String, inviteId: String) async throws {
        let query = CKQuery(
            recordType: "ContactInviteResponse",
            predicate: NSPredicate(format: "fromCode == %@ AND toCode == %@",
                                   ownerCode, myCode))
        let existing = ((try? await database.records(matching: query, resultsLimit: 5))?
            .0 ?? []).compactMap { try? $0.1.get() }.first
        let record = existing ?? CKRecord(recordType: "ContactInviteResponse")
        record["fromCode"] = ownerCode as CKRecordValue
        record["toCode"] = myCode as CKRecordValue
        record["accepted"] = (accepted ? 1 : 0) as NSNumber
        record["inviteId"] = inviteId as CKRecordValue
        record["toPubKey"] = ContactCrypto.myPublicKey as CKRecordValue
        if !ownerName.isEmpty { record["ownerName"] = ownerName as CKRecordValue }
        _ = try await database.save(record)
    }

    /// Did the contact with `code` answer THIS invite (matching `inviteId`)?
    /// true = accepted, false = declined/revoked, nil = no answer for this id
    /// (so an old answer to a previous add no longer counts).
    static func inviteResponse(forContactCode code: String,
                               inviteId: String) async throws -> Bool? {
        let query = CKQuery(
            recordType: "ContactInviteResponse",
            predicate: NSPredicate(format: "fromCode == %@ AND toCode == %@",
                                   myCode, code))
        let (results, _) = try await database.records(matching: query,
                                                      resultsLimit: 5)
        for (_, result) in results {
            guard let record = try? result.get() else { continue }
            guard (record["inviteId"] as? String ?? "") == inviteId else { continue }
            if let v = record["accepted"] as? Int {
                // Trust the approver's public key from their accept response (the
                // handshake) — used to verify their later approvals.
                if v == 1 {
                    ContactCrypto.storePeerKey(code: code,
                                               publicKey: record["toPubKey"] as? String)
                }
                return v == 1
            }
        }
        return nil
    }

    // MARK: - People who have me as their trusted contact

    struct PermissionGrant: Identifiable {
        let id: String          // the owner's buddy code
        var ownerName: String
        var inviteId: String
    }

    /// Owners who currently have me as an accepted trusted contact. A grant
    /// only counts if the owner still has a live invite to me with the same
    /// inviteId — so if they remove me, I drop off this list.
    static func grantsToMe() async throws -> [PermissionGrant] {
        // Live invites addressed to me, keyed as "owner|inviteId".
        let invQ = CKQuery(recordType: "ContactInvite",
                           predicate: NSPredicate(format: "toCode == %@", myCode))
        var live = Set<String>()
        for r in ((try? await database.records(matching: invQ, resultsLimit: 100))?
            .0 ?? []).compactMap({ try? $0.1.get() }) {
            if let o = r["fromCode"] as? String {
                live.insert(o + "|" + (r["inviteId"] as? String ?? ""))
            }
        }
        let respQ = CKQuery(recordType: "ContactInviteResponse",
                            predicate: NSPredicate(format: "toCode == %@", myCode))
        let (results, _) = try await database.records(matching: respQ, resultsLimit: 100)
        var byOwner: [String: PermissionGrant] = [:]
        for (_, result) in results {
            guard let r = try? result.get(),
                  let owner = r["fromCode"] as? String,
                  (r["accepted"] as? Int) == 1 else { continue }
            let iid = r["inviteId"] as? String ?? ""
            guard live.contains(owner + "|" + iid) else { continue }
            byOwner[owner] = PermissionGrant(
                id: owner, ownerName: (r["ownerName"] as? String) ?? "", inviteId: iid)
        }
        return Array(byOwner.values).sorted { $0.id < $1.id }
    }

    /// Stop being `ownerCode`'s trusted contact (for invite `inviteId`): sets
    /// the answer to declined, so their app drops me and tells them.
    static func revokeGrant(ownerCode: String, inviteId: String) async throws {
        try await upsertResponse(ownerCode: ownerCode, accepted: false,
                                 ownerName: "", inviteId: inviteId)
    }

    // MARK: - Blocking & request history (local, on-device only)

    private static let blockedCodesKey = "latch.blockedCodes"
    private static let historyKey = "latch.requestHistory"

    static func blockedCodes() -> [String] {
        (SharedStore.defaults.stringArray(forKey: blockedCodesKey) ?? []).sorted()
    }
    static func isBlocked(_ code: String) -> Bool {
        Set(SharedStore.defaults.stringArray(forKey: blockedCodesKey) ?? []).contains(code)
    }
    static func block(_ code: String) {
        var s = Set(SharedStore.defaults.stringArray(forKey: blockedCodesKey) ?? [])
        s.insert(code)
        SharedStore.defaults.set(Array(s), forKey: blockedCodesKey)
    }
    static func unblock(_ code: String) {
        var s = Set(SharedStore.defaults.stringArray(forKey: blockedCodesKey) ?? [])
        s.remove(code)
        SharedStore.defaults.set(Array(s), forKey: blockedCodesKey)
    }

    // MARK: - Avatars for remote contacts (grants / blocked), keyed by code
    private static let avatarsKey = "latch.contactAvatars"

    static func avatar(forCode code: String) -> ContactAvatar? {
        guard let dict = SharedStore.defaults.dictionary(forKey: avatarsKey) as? [String: Data],
              let data = dict[code] else { return nil }
        return try? JSONDecoder().decode(ContactAvatar.self, from: data)
    }
    static func setAvatar(_ avatar: ContactAvatar?, forCode code: String) {
        var dict = (SharedStore.defaults.dictionary(forKey: avatarsKey) as? [String: Data]) ?? [:]
        if let avatar, let data = try? JSONEncoder().encode(avatar) {
            dict[code] = data
        } else {
            dict.removeValue(forKey: code)
        }
        SharedStore.defaults.set(dict, forKey: avatarsKey)
    }

    // MARK: - Custom display names for remote contacts, keyed by code
    // Lets a Demora user carry one name + avatar whether they show up under
    // "people who approve for you" or "people you approve for".
    private static let namesKey = "latch.contactNames"

    /// A locally chosen display name for a Demora user, or "" if none set.
    static func name(forCode code: String) -> String {
        (SharedStore.defaults.dictionary(forKey: namesKey) as? [String: String])?[code] ?? ""
    }
    static func setName(_ name: String, forCode code: String) {
        var dict = (SharedStore.defaults.dictionary(forKey: namesKey) as? [String: String]) ?? [:]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            dict.removeValue(forKey: code)
        } else {
            dict[code] = trimmed
        }
        SharedStore.defaults.set(dict, forKey: namesKey)
    }

    // MARK: - Safety-code verification (per contact code)
    // We store the exact fingerprint the user confirmed. A contact counts as
    // verified only while its current fingerprint still equals the stored one —
    // so if the peer's key ever changes (a re-add, or a forged substitution),
    // it silently reverts to unverified.
    private static let verifiedKey = "latch.verifiedFingerprints"

    static func verifiedFingerprint(forCode code: String) -> String? {
        (SharedStore.defaults.dictionary(forKey: verifiedKey) as? [String: String])?[code]
    }
    static func setVerifiedFingerprint(_ fingerprint: String, forCode code: String) {
        var dict = (SharedStore.defaults.dictionary(forKey: verifiedKey) as? [String: String]) ?? [:]
        dict[code] = fingerprint
        SharedStore.defaults.set(dict, forKey: verifiedKey)
    }

    /// One entry per Demora id (grouped by code, not nickname). `lastAction`
    /// is "received", "accepted", or "declined".
    struct RequestRecord: Codable, Identifiable {
        var code: String
        var name: String
        var lastDate: Double
        var lastAction: String
        var id: String { code }
    }

    private static func loadHistoryDict() -> [String: RequestRecord] {
        guard let data = SharedStore.defaults.data(forKey: historyKey),
              let dict = try? JSONDecoder()
                .decode([String: RequestRecord].self, from: data)
        else { return [:] }
        return dict
    }
    private static func saveHistoryDict(_ dict: [String: RequestRecord]) {
        if let data = try? JSONEncoder().encode(dict) {
            SharedStore.defaults.set(data, forKey: historyKey)
        }
    }

    /// History of people who've asked to add me, newest first.
    static func requestHistory() -> [RequestRecord] {
        loadHistoryDict().values.sorted { $0.lastDate > $1.lastDate }
    }

    static func recordRequest(code: String, name: String, action: String) {
        var dict = loadHistoryDict()
        var entry = dict[code]
            ?? RequestRecord(code: code, name: name, lastDate: 0, lastAction: action)
        if !name.isEmpty { entry.name = name }   // keep the latest known nickname
        entry.lastDate = Date().timeIntervalSince1970
        entry.lastAction = action
        dict[code] = entry
        saveHistoryDict(dict)
    }

    // MARK: - Outgoing request history (requests I've sent to add others)

    private static let sentReqHistoryKey = "latch.sentReqHistory"

    /// One entry per Demora id I've tried to add. `status` is "pending",
    /// "accepted", or "denied".
    struct SentRecord: Codable, Identifiable {
        var code: String
        var name: String
        var lastDate: Double
        var status: String
        var id: String { code }
    }

    private static func loadSentReqDict() -> [String: SentRecord] {
        guard let data = SharedStore.defaults.data(forKey: sentReqHistoryKey),
              let d = try? JSONDecoder().decode([String: SentRecord].self, from: data)
        else { return [:] }
        return d
    }
    private static func saveSentReqDict(_ d: [String: SentRecord]) {
        if let data = try? JSONEncoder().encode(d) {
            SharedStore.defaults.set(data, forKey: sentReqHistoryKey)
        }
    }

    static func sentRequestHistory() -> [SentRecord] {
        loadSentReqDict().values.sorted { $0.lastDate > $1.lastDate }
    }

    static func recordSentRequest(code: String, name: String, status: String) {
        var d = loadSentReqDict()
        if let e = d[code], e.status == status, e.name == name { return } // no churn
        var entry = d[code]
            ?? SentRecord(code: code, name: name, lastDate: 0, status: status)
        if !name.isEmpty { entry.name = name }
        entry.status = status
        entry.lastDate = Date().timeIntervalSince1970
        d[code] = entry
        saveSentReqDict(d)
    }
}
