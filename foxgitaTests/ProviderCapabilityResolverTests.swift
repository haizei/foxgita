import Foundation
import Testing
@testable import foxgita

struct ProviderCapabilityResolverTests {
    @Test func explicitUserChoiceWinsOverKnownProvider() {
        let defaults = UserDefaults(suiteName: "ProviderCapabilityResolverTests")!
        defaults.removePersistentDomain(forName: "ProviderCapabilityResolverTests")
        let url = "https://api.openai.com/v1"
        let key = "\(url.lowercased())|gpt-4o-mini"
        defaults.set([key: false], forKey: "gita.ai.providerCapabilities.responseFormat")

        #expect(!ProviderCapabilityResolver.resolve(baseURL: url, model: "gpt-4o-mini", defaults: defaults).supportsResponseFormat)
    }

    @Test func unknownProviderDoesNotNeedATrialRequest() {
        let defaults = UserDefaults(suiteName: "ProviderCapabilityResolverTests.unknown")!
        defaults.removePersistentDomain(forName: "ProviderCapabilityResolverTests.unknown")
        #expect(!ProviderCapabilityResolver.resolve(baseURL: "https://compatible.example/v1", model: "vision", defaults: defaults).supportsResponseFormat)
    }
}
