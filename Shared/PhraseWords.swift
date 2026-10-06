import Foundation

enum PhraseWords {
    static func split(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { String($0).lowercased() }
    }

    static func isValid(_ policy: PhrasePolicy) -> Bool {
        guard !policy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !policy.allowed.isEmpty,
              policy.allowedErrors.map({ [0, 1, 5, 10].contains($0) }) ?? true
        else { return false }
        switch policy.kind {
        case .custom(let text):
            let words = split(text)
            return (1...1000).contains(words.count)
                && words.allSatisfy { !$0.isEmpty && $0.count <= 64 }
        case .random(let count):
            return [50, 100, 200, 500, 1000].contains(count)
        }
    }

    /// Stored in the app bundle; random challenges never require a server.
    static func randomChallenge(count: Int) -> [String]? {
        guard [50, 100, 200, 500, 1000].contains(count),
              let url = Bundle.main.url(forResource: "eff_long_words", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let dictionary = contents.split(whereSeparator: \.isNewline).map(String.init)
        guard dictionary.count == 7776 else { return nil }
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in
            dictionary[Int.random(in: dictionary.indices, using: &generator)]
        }
    }
}

/// An in-memory, one-use proof. The UI cannot obtain a proof without entering
/// every word in order. Neither the random challenge nor its proof is persisted.
enum PhraseChallenges {
    enum Scope: Equatable {
        case changes([UUID])
        case extraTime(limitID: UUID, day: String, step: Int)
    }

    enum Submission {
        case next(index: Int, mistakes: Int)
        case wrong(mistakes: Int)
        case reset
        case completed(proofID: UUID)
        case unavailable
    }

    private struct Challenge {
        var policy: PhrasePolicy
        var scope: Scope
        var words: [String]
        var index = 0
        var mistakes = 0
        var expiresAt: Date
    }

    private struct Proof {
        let policy: PhrasePolicy
        let scope: Scope
        let expiresAt: Date
    }

    private static let lock = NSLock()
    private static var challenges: [UUID: Challenge] = [:]
    private static var proofs: [UUID: Proof] = [:]

    static func start(policy: PhrasePolicy, scope: Scope) -> (id: UUID, words: [String])? {
        guard PhraseWords.isValid(policy) else { return nil }
        let words: [String]
        switch policy.kind {
        case .custom(let text): words = PhraseWords.split(text)
        case .random(let count):
            guard let generated = PhraseWords.randomChallenge(count: count) else { return nil }
            words = generated
        }
        lock.lock()
        defer { lock.unlock() }
        // Bound memory if many challenges were abandoned without an app restart.
        let now = Date()
        challenges = challenges.filter { $0.value.expiresAt > now }
        proofs = proofs.filter { $0.value.expiresAt > now }
        guard challenges.count < 20 else { return nil }
        let id = UUID()
        challenges[id] = Challenge(policy: policy, scope: scope, words: words,
                                   expiresAt: now.addingTimeInterval(3600))
        return (id, words)
    }

    static func abandon(_ id: UUID) {
        lock.lock()
        challenges.removeValue(forKey: id)
        lock.unlock()
    }

    static func submit(word: String, to id: UUID) -> Submission {
        lock.lock()
        defer { lock.unlock() }
        guard var challenge = challenges[id], challenge.expiresAt > Date(),
              challenge.words.indices.contains(challenge.index) else {
            challenges.removeValue(forKey: id)
            return .unavailable
        }
        if PhraseWords.split(word) == [challenge.words[challenge.index]] {
            challenge.index += 1
            if challenge.index == challenge.words.count {
                challenges.removeValue(forKey: id)
                let proofID = UUID()
                proofs[proofID] = Proof(policy: challenge.policy,
                                        scope: challenge.scope,
                                        expiresAt: Date().addingTimeInterval(120))
                return .completed(proofID: proofID)
            }
            challenges[id] = challenge
            return .next(index: challenge.index, mistakes: challenge.mistakes)
        }
        challenge.mistakes += 1
        if let allowed = challenge.policy.allowedErrors,
           challenge.mistakes > allowed {
            challenges.removeValue(forKey: id)
            return .reset
        }
        challenges[id] = challenge
        return .wrong(mistakes: challenge.mistakes)
    }

    /// Always consumes the proof, including when the policy was removed or
    /// narrowed during entry. No stale challenge can authorize a new scope.
    static func consume(_ id: UUID, policy: PhrasePolicy, scope: Scope) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let proof = proofs.removeValue(forKey: id) else { return false }
        return proof.expiresAt > Date() && proof.policy == policy && proof.scope == scope
    }
}
