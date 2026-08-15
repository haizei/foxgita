import Foundation
import Security

enum LLMSettingsKey {
    static let baseURL = "gita.llm.baseURL"
    static let model = "gita.llm.model"
}

final class LLMCredentialsStore: Sendable {
    private let service: String
    private let account = "apiKey"

    init(service: String = "com.haizei.foxgita.llm") {
        self.service = service
    }

    func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func clearAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func missingFieldLabels(baseURL: String, model: String) -> [String] {
        var missing: [String] = []
        if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("Base URL")
        }
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("Model")
        }
        let key = loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if key.isEmpty {
            missing.append("API Key")
        }
        return missing
    }

    func isConfigured(baseURL: String, model: String) -> Bool {
        missingFieldLabels(baseURL: baseURL, model: model).isEmpty
    }
}
