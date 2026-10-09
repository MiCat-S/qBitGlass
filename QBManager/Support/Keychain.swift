import Foundation
import Security

/// 密碼 / API Key 存在 Keychain；若側載簽章缺少 Keychain 權限則退回 UserDefaults。
enum Keychain {
    private static let service = "com.micat.qbmanager"
    private static let fallbackPrefix = "secret.fallback."

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let s = String(data: data, encoding: .utf8) {
            return s
        }
        return UserDefaults.standard.string(forKey: fallbackPrefix + account)
    }

    static func set(_ value: String?, for account: String) {
        delete(account)
        guard let value, !value.isEmpty else { return }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(value.utf8),
        ]
        if SecItemAdd(attrs as CFDictionary, nil) != errSecSuccess {
            UserDefaults.standard.set(value, forKey: fallbackPrefix + account)
        }
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackPrefix + account)
    }
}
