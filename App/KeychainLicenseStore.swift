import Foundation
import Security
import Licensing

/// Keeps the licence text in the login Keychain (CLAUDE.md §11.3), one generic-password item.
///
/// The text is a signed licence, not a secret that unlocks anything on its own, but the Keychain
/// keeps it out of plain files and survives a reinstall of the app.
final class KeychainLicenseStore: LicenseStoring, @unchecked Sendable {
    private let service = "com.burnish.app.license"
    private let account = "licence"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ text: String) {
        let data = Data(text.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
