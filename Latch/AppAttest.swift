//
//  AppAttest.swift
//  Apple App Attest: proves to the override Worker that a request comes from a
//  genuine, unmodified copy of Demora on a real Apple device. This means a
//  leaked app token alone can't be used to drive the email sender — the Worker
//  also requires a per-request assertion that only the real app can produce.
//
//  Flow: generate a key once, register it with the server (attestation), then
//  sign each protected request with an assertion over (challenge + body).
//

import Foundation
import DeviceCheck
import CryptoKit

enum AppAttestError: Error { case unsupported }

enum AppAttest {
    private static let service = DCAppAttestService.shared
    private static let keyIdKey = "latch.attestKeyId"
    private static let registeredKey = "latch.attestRegistered"
    private static var defaults: UserDefaults { SharedStore.defaults }

    /// False on the Simulator and pre-iOS-14 devices. Real App Store devices
    /// all support it.
    static var isSupported: Bool { service.isSupported }

    /// Headers carrying a fresh assertion over `body`, registering the device on
    /// first use. Throws `.unsupported` where App Attest isn't available — the
    /// caller should surface that as "this device can't send approval emails".
    ///
    /// Self-healing: if the stored key no longer exists in the Secure Enclave
    /// (common after a reinstall where the app-group `keyId` persisted but the
    /// key itself was destroyed with the old install), the first assertion/attest
    /// call throws `DCError.invalidKey`. We discard the stale key, generate a
    /// fresh one, and try once more — otherwise the app is stuck failing forever.
    static func assertionHeaders(for body: Data) async throws -> [String: String] {
        guard isSupported else { throw AppAttestError.unsupported }
        do {
            return try await buildHeaders(for: body)
        } catch let error as DCError where error.code == .invalidKey {
            resetKey()
            return try await buildHeaders(for: body)
        }
    }

    /// Forget the "registered" flag so the next send re-attests the key with the
    /// server. Called when the Worker reports it doesn't recognize our key
    /// (e.g. its stored registration was lost), so the app can recover instead
    /// of failing every send.
    static func markNeedsReregistration() {
        defaults.set(false, forKey: registeredKey)
    }

    /// Drop the stored key entirely so a brand-new one is generated + attested.
    private static func resetKey() {
        defaults.removeObject(forKey: keyIdKey)
        defaults.set(false, forKey: registeredKey)
    }

    private static func buildHeaders(for body: Data) async throws -> [String: String] {
        try await ensureRegistered()
        let keyId = try await currentKeyId()
        let challenge = try await EmailCodeService.challenge()
        let clientDataHash = Data(SHA256.hash(data: challengeData(challenge) + body))
        let assertion = try await service.generateAssertion(keyId,
                                                            clientDataHash: clientDataHash)
        return [
            "X-Attest-Key": keyId,
            "X-Attest-Challenge": challenge,
            "X-Attest-Assertion": assertion.base64EncodedString(),
        ]
    }

    // MARK: - Registration

    private static func ensureRegistered() async throws {
        guard !defaults.bool(forKey: registeredKey) else { return }
        let keyId = try await currentKeyId()
        let challenge = try await EmailCodeService.challenge()
        let clientDataHash = Data(SHA256.hash(data: challengeData(challenge)))
        let attestation = try await service.attestKey(keyId,
                                                      clientDataHash: clientDataHash)
        try await EmailCodeService.registerAttestation(
            keyId: keyId, challenge: challenge, attestation: attestation)
        defaults.set(true, forKey: registeredKey)
    }

    /// The device's App Attest key id, generated (and persisted) once per install.
    private static func currentKeyId() async throws -> String {
        if let id = defaults.string(forKey: keyIdKey) { return id }
        let id = try await service.generateKey()
        defaults.set(id, forKey: keyIdKey)
        defaults.set(false, forKey: registeredKey)   // a fresh key needs registering
        return id
    }

    /// Decode the server challenge (standard base64) to the exact bytes both
    /// sides hash. Falls back to raw UTF-8 if it isn't base64.
    private static func challengeData(_ challenge: String) -> Data {
        Data(base64Encoded: challenge) ?? Data(challenge.utf8)
    }
}
