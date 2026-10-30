// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security

/// Where the API keeps the SHA-256 hash of each client's token. The Keychain
/// in the app; a dictionary in tests.
protocol SecretStore: AnyObject, Sendable {
    func save(_ secret: Data, account: String) -> Bool
    func load(account: String) -> Data?
    func delete(account: String)
}

final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]

    func save(_ secret: Data, account: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        items[account] = secret
        return true
    }

    func load(account: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return items[account]
    }

    func delete(account: String) {
        lock.lock(); defer { lock.unlock() }
        items[account] = nil
    }
}

/// Generic-password items in the login Keychain, available only while the
/// Mac is unlocked and never synced.
final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service: String

    init(service: String = "me.rkck.Notched.api") {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func save(_ secret: Data, account: String) -> Bool {
        delete(account: account)
        var item = query(account)
        item[kSecValueData as String] = secret
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func load(account: String) -> Data? {
        var item = query(account)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
