// Run on macOS without an iOS SDK:
// swiftc Shared/PhraseWords.swift Tests/PhraseWordsHarness.swift -o /tmp/demora-phrase-test
// /tmp/demora-phrase-test
import Foundation

enum OverrideCapability: Hashable { case extraTime }
enum PhraseKind: Equatable { case custom(String), random(Int) }
struct PhrasePolicy: Equatable {
    var id = UUID()
    var name: String
    var kind: PhraseKind
    var allowedErrors: Int?
    var allowed: Set<OverrideCapability>
}

@main
private enum PhraseWordsHarness {
    static func main() {
        let scope = PhraseChallenges.Scope.extraTime(limitID: UUID(), day: "today", step: 0)
        var policy = PhrasePolicy(name: "test", kind: .custom("alpha beta gamma"),
                                  allowedErrors: 0, allowed: [.extraTime])
        precondition(PhraseWords.isValid(policy))
        precondition(PhraseWords.split("Alpha\n beta  GAMMA") == ["alpha", "beta", "gamma"])
        precondition(!PhraseWords.isValid(PhrasePolicy(name: "bad", kind: .random(51),
                                                         allowedErrors: 0,
                                                         allowed: [.extraTime])))
        guard let first = PhraseChallenges.start(policy: policy, scope: scope) else {
            fatalError("challenge not created")
        }
        precondition(first.words == ["alpha", "beta", "gamma"])
        if case .reset = PhraseChallenges.submit(word: "wrong", to: first.id) {
            // Expected: zero mistakes allowed.
        } else { fatalError("did not reset") }
        if case .unavailable = PhraseChallenges.submit(word: "alpha", to: first.id) {
        } else { fatalError("reset challenge remained valid") }

        guard let second = PhraseChallenges.start(policy: policy, scope: scope) else {
            fatalError("challenge not recreated")
        }
        if case .next(index: 1, mistakes: 0) = PhraseChallenges.submit(word: "alpha", to: second.id) {
        } else { fatalError("first word") }
        if case .next(index: 2, mistakes: 0) = PhraseChallenges.submit(word: "beta", to: second.id) {
        } else { fatalError("second word") }
        let proof: UUID
        if case .completed(let id) = PhraseChallenges.submit(word: "gamma", to: second.id) {
            proof = id
        } else { fatalError("third word") }
        precondition(PhraseChallenges.consume(proof, policy: policy, scope: scope))
        precondition(!PhraseChallenges.consume(proof, policy: policy, scope: scope))

        guard let third = PhraseChallenges.start(policy: policy, scope: scope) else {
            fatalError("challenge not created")
        }
        _ = PhraseChallenges.submit(word: "alpha", to: third.id)
        _ = PhraseChallenges.submit(word: "beta", to: third.id)
        let staleProof: UUID
        if case .completed(let id) = PhraseChallenges.submit(word: "gamma", to: third.id) {
            staleProof = id
        } else { fatalError("proof not issued") }
        policy.allowedErrors = 1 // A queued policy edit took effect.
        precondition(!PhraseChallenges.consume(staleProof, policy: policy, scope: scope))
        print("Phrase challenge checks passed")
    }
}
