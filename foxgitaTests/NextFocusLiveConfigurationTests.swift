import Foundation
import Security
import Testing
@testable import foxgita

/// Explicit opt-in checks the simulator's existing configuration without making a request.
@MainActor
struct NextFocusLiveConfigurationTests {
    private nonisolated static var enabled: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["GITA_NEXT_FOCUS_LIVE_TEST"] == "1"
            || env["TEST_RUNNER_GITA_NEXT_FOCUS_LIVE_TEST"] == "1"
    }

    @Test(.enabled(if: enabled))
    func existingProviderIsReadyForTheLiveFlow() throws {
        let defaults = UserDefaults.standard
        let base = defaults.string(forKey: LLMSettingsKey.baseURL) ?? ""
        let model = defaults.string(forKey: LLMSettingsKey.model) ?? ""
        let endpoint = AITransport.completionsURL(from: base)
        let credentialPresent = !(LLMCredentialsStore().loadAPIKey() ?? "").isEmpty
        let credentialStatus = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.haizei.foxgita.llm",
            kSecAttrAccount as String: "apiKey",
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as CFDictionary, nil)
        let secureEndpoint = endpoint?.scheme == "https" && endpoint?.host != nil
            && endpoint?.user == nil && endpoint?.password == nil
        let report: [String: Any] = [
            "model": model, "secureEndpointConfigured": secureEndpoint,
            "credentialPresent": credentialPresent, "credentialLookupStatus": Int(credentialStatus),
            "networkRequestMade": false
        ]
        let directory = URL.documentsDirectory.appendingPathComponent("NextFocusLiveValidation", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("configuration.json"), options: .atomic)
        #expect(secureEndpoint, "Configure an HTTPS AI endpoint in this simulator before the live run.")
        #expect(!model.isEmpty, "Configure an AI model in this simulator before the live run.")
        #expect(credentialPresent, "Save the API key in the simulator app's Keychain before the live run.")
    }
}
