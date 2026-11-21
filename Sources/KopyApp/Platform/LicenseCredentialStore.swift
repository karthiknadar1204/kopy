#if !KOPY_APP_STORE
import Foundation
import Security

@MainActor
final class KeychainLicenseStore: LicenseCredentialStoring {
    private let service: String
    private let defaults: UserDefaults
    private let account = "dodo-test-license"

    init(service: String, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    var offlineAllowed: Bool {
        get { !defaults.bool(forKey: "licenseRequiresOnlineValidation") }
        set { defaults.set(!newValue, forKey: "licenseRequiresOnlineValidation") }
    }

    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() throws -> LicenseCredential? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = try? JSONDecoder().decode(LicenseCredential.self, from: data) else {
            throw LicenseIssue.storage
        }
        return value
    }

    func save(_ credential: LicenseCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let attributes = [kSecValueData as String: data]
        let updated = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw LicenseIssue.storage }
        var entry = identity
        entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw LicenseIssue.storage }
    }

    func remove() throws {
        let status = SecItemDelete(identity as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw LicenseIssue.storage }
    }
}
#endif
