import CryptoKit
import Foundation
import Security

enum LocalHistoryKey {
    static func load(service: String, createIfMissing: Bool) throws -> SymmetricKey {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "clipboard-history"
        ]
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecSuccess, let data = value as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound, createIfMissing else { throw AccessError(status: status) }

        let key = SymmetricKey(size: .bits256)
        var entry = identity
        entry[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        let result = SecItemAdd(entry as CFDictionary, nil)
        if result == errSecDuplicateItem { return try load(service: service, createIfMissing: false) }
        guard result == errSecSuccess else { throw AccessError(status: result) }
        return key
    }

    struct AccessError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            "Kopy couldn’t read or create the history key in Keychain (\(status))."
        }
    }
}
