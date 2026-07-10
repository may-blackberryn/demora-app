//
//  Keychain.swift
//  Small wrapper for the few real secrets that shouldn't live in UserDefaults
//  (which is included in device backups): the contact-crypto private key and
//  the stored Screen Time passcode. Items are AfterFirstUnlockThisDeviceOnly —
//  usable in the background, never written to iCloud/iTunes backups.
//

import Foundation
import Security

enum Keychain {
    private static let service = "app.getdemora.secrets"

    static func setData(_ data: Data?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let data, !data.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func getData(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return data
    }

    static func setString(_ string: String?, for account: String) {
        let trimmed = string?.isEmpty == false ? string : nil
        setData(trimmed.map { Data($0.utf8) }, for: account)
    }

    static func getString(for account: String) -> String? {
        getData(for: account).flatMap { String(data: $0, encoding: .utf8) }
    }
}
