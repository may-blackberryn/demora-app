//
//  ContactCrypto.swift
//  End-to-end protection for Demora-user (CloudKit) approvals.
//
//  Each install has a Curve25519 key-agreement keypair. During the contact
//  invite handshake the two devices exchange PUBLIC keys (safe to be visible in
//  the shared database). Each side then derives the SAME private shared key via
//  ECDH — which nobody else can compute without one of the private keys. With
//  that shared key we:
//    • encrypt the request summary  → snoopers in the public DB see ciphertext
//    • sign each approval (HMAC)     → a stranger can't forge an "approved"
//
//  Backward compatible: contacts added before keys were exchanged have no shared
//  key, so requests to them stay plaintext and their approvals are accepted as
//  before. Re-adding a contact upgrades that pair to encrypted + signed.
//

import Foundation
import CryptoKit

enum ContactCrypto {
    private static let privKeyKey = "latch.ecdhPrivateKey"
    private static let peerKeysKey = "latch.peerPublicKeys"
    private static var defaults: UserDefaults { SharedStore.defaults }

    // MARK: - My keypair

    private static func privateKey() -> Curve25519.KeyAgreement.PrivateKey {
        // Migrate a key previously kept in UserDefaults (which is in backups)
        // into the device-only Keychain, then forget the old copy.
        if let legacy = defaults.data(forKey: privKeyKey) {
            Keychain.setData(legacy, for: privKeyKey)
            defaults.removeObject(forKey: privKeyKey)
        }
        if let data = Keychain.getData(for: privKeyKey),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
            return key
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        Keychain.setData(key.rawRepresentation, for: privKeyKey)
        return key
    }

    /// This install's public key (base64). Safe to publish.
    static var myPublicKey: String {
        privateKey().publicKey.rawRepresentation.base64EncodedString()
    }

    // MARK: - Peer keys (code -> their public key)

    private static func peerKeys() -> [String: String] {
        (defaults.dictionary(forKey: peerKeysKey) as? [String: String]) ?? [:]
    }
    static func storePeerKey(code: String, publicKey: String?) {
        guard let publicKey, !code.isEmpty, !publicKey.isEmpty,
              Data(base64Encoded: publicKey) != nil else { return }
        var d = peerKeys()
        d[code] = publicKey
        defaults.set(d, forKey: peerKeysKey)
    }
    static func hasKey(forCode code: String) -> Bool { peerKeys()[code] != nil }

    /// A short, human-comparable code derived from BOTH public keys (mine +
    /// this contact's), so the two people can confirm out-of-band that no one
    /// substituted a key in the public database. Both devices compute the same
    /// value (keys are sorted first). nil until both keys are known.
    static func verificationCode(forCode code: String) -> String? {
        guard let peerB64 = peerKeys()[code],
              let peer = Data(base64Encoded: peerB64) else { return nil }
        let mine = privateKey().publicKey.rawRepresentation
        let pair = mine.lexicographicallyPrecedes(peer) ? mine + peer : peer + mine
        // 64 bits of SHA-256 as 4 groups of 4 hex — easy to read aloud, and
        // finding a key that matches it is far beyond this app's threat payoff.
        let hex = SHA256.hash(data: pair).prefix(8)
            .map { String(format: "%02X", $0) }.joined()
        return stride(from: 0, to: hex.count, by: 4).map {
            let s = hex.index(hex.startIndex, offsetBy: $0)
            let e = hex.index(s, offsetBy: 4)
            return String(hex[s..<e])
        }.joined(separator: " ")
    }

    // MARK: - Shared key (ECDH + HKDF)

    private static func sharedKey(forCode code: String) -> SymmetricKey? {
        guard let peerB64 = peerKeys()[code],
              let peerData = Data(base64Encoded: peerB64),
              let peerKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerData),
              let secret = try? privateKey().sharedSecretFromKeyAgreement(with: peerKey)
        else { return nil }
        // Fixed salt/info so both sides derive the same key regardless of role.
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("demora.contact.v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32)
    }

    // MARK: - Encrypt / decrypt the summary

    static func encrypt(_ text: String, forCode code: String) -> String? {
        guard let key = sharedKey(forCode: code),
              let sealed = try? AES.GCM.seal(Data(text.utf8), using: key),
              let combined = sealed.combined
        else { return nil }
        return combined.base64EncodedString()
    }

    static func decrypt(_ cipherB64: String, forCode code: String) -> String? {
        guard let key = sharedKey(forCode: code),
              let data = Data(base64Encoded: cipherB64),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key)
        else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    // MARK: - Sign / verify an approval

    static func sign(requestId: String, decision: String, forCode code: String) -> String? {
        guard let key = sharedKey(forCode: code) else { return nil }
        let msg = Data((requestId + "|" + decision).utf8)
        return Data(HMAC<SHA256>.authenticationCode(for: msg, using: key))
            .base64EncodedString()
    }

    static func verify(_ authB64: String?, requestId: String, decision: String,
                       forCode code: String) -> Bool {
        guard let authB64, let auth = Data(base64Encoded: authB64),
              let key = sharedKey(forCode: code) else { return false }
        let msg = Data((requestId + "|" + decision).utf8)
        let expected = Data(HMAC<SHA256>.authenticationCode(for: msg, using: key))
        return ctEqual(expected, auth)
    }

    private static func ctEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}
