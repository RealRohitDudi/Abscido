import Foundation
import Security

enum Keychain {
    private static let service = "com.abscido.app"

    /// Saves a string value to the Keychain under the given key.
    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw AbscidoError.keychainError(status: errSecParam)
        }

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AbscidoError.keychainError(status: status)
        }
    }

    /// Loads a string value from the Keychain for the given key.
    static func load(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw AbscidoError.keychainError(status: status)
        }

        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw AbscidoError.keychainError(status: errSecDecode)
        }

        return string
    }

    /// Deletes the value stored under the given key from the Keychain.
    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AbscidoError.keychainError(status: status)
        }
    }

    /// Returns the last 4 characters of a stored key value, for UI display.
    static func maskedValue(key: String) -> String? {
        guard let value = try? load(key: key), value.count >= 4 else {
            return nil
        }
        let lastFour = String(value.suffix(4))
        return "••••••••\(lastFour)"
    }
}
