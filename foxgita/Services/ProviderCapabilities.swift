import Foundation

/// Resolves request features before a paid request is sent. Unknown providers
/// use the conservative JSON-prompt path; they are never probed by a second
/// model call merely to discover support.
struct ProviderCapabilities: Equatable, Sendable {
    var supportsResponseFormat: Bool

    static let conservative = ProviderCapabilities(supportsResponseFormat: false)
}

enum ProviderCapabilityResolver {
    private static let preferenceKey = "gita.ai.providerCapabilities.responseFormat"

    static func resolve(baseURL: String, model: String, defaults: UserDefaults = .standard) -> ProviderCapabilities {
        let key = "\(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(model.lowercased())"
        if let configured = (defaults.dictionary(forKey: preferenceKey)?[key] as? Bool) {
            return ProviderCapabilities(supportsResponseFormat: configured)
        }
        let host = URL(string: baseURL)?.host?.lowercased() ?? ""
        if host == "api.openai.com" || host.hasSuffix(".openai.azure.com") {
            return ProviderCapabilities(supportsResponseFormat: true)
        }
        return .conservative
    }
}
