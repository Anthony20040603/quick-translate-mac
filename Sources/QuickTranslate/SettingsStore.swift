import AppKit
import Security
import TranslationCore

struct ServiceSettings: Codable {
    var endpoint = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    var model = "glm-4.7-flash"
    var direction: TranslationDirection = .automatic

    static func load() -> Self {
        guard let data = UserDefaults.standard.data(forKey: "serviceSettings"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: "serviceSettings")
    }
}

enum KeychainStore {
    private static let service = "com.anthony.quicktranslate.mac.translation"
    private static func query(endpoint: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: endpoint]
    }

    static func read(endpoint: String) throws -> String? {
        var request = query(endpoint: endpoint)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let text = String(data: data, encoding: .utf8) else {
            throw TranslationFailure.message("无法读取钥匙串中的密钥（\(status)）。请检查系统授权，或在设置中重新保存。")
        }
        return text
    }

    static func save(_ secret: String, endpoint: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(secret.utf8)]
        let status = SecItemUpdate(query(endpoint: endpoint) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(endpoint: endpoint)
            item.merge(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let inserted = SecItemAdd(item as CFDictionary, nil)
            guard inserted == errSecSuccess else {
                throw TranslationFailure.message("密钥未能保存到钥匙串（\(inserted)），设置未更新。")
            }
        } else if status != errSecSuccess {
            throw TranslationFailure.message("密钥未能更新（\(status)），设置未更新。")
        }
    }
}
