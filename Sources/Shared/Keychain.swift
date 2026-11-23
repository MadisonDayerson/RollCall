import Foundation
import Security

/// Keeps a key (the Beeper access token, the road alerts key) in the login keychain rather than a plain file.
/// It's read from the keychain once and then remembered, so drawing Settings or reading a chat never waits on a
/// keychain prompt again.
final class Keychain: @unchecked Sendable {
    static let beeper = Keychain(account: "beeper-desktop-api", service: "au.madiday.motorides.beeper")
    static let roads = Keychain(account: "road-alerts", service: "au.madiday.motorides.roads")

    let account: String
    let service: String
    /// nil until the keychain has been read; then the key, or .some(nil) when there isn't one.
    private var remembered: String??

    private init(account: String, service: String) {
        self.account = account
        self.service = service
    }

    func save(_ key: String) {
        delete()
        remembered = key
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(key.utf8),
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    func read() -> String? {
        if let remembered { return remembered }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        let key = status == errSecSuccess ? (out as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
        // A denied or cancelled keychain prompt isn't remembered, so the next read can ask again.
        if status == errSecSuccess || status == errSecItemNotFound { remembered = .some(key) }
        return key
    }

    func delete() {
        remembered = .some(nil)
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
