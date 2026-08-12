import Foundation
import Testing
@testable import foxgita

struct LLMCredentialsStoreTests {
    private func makeStore() -> LLMCredentialsStore {
        LLMCredentialsStore(service: "com.haizei.foxgita.llm.tests.\(UUID().uuidString)")
    }

    @Test func saveLoadClearRoundTrip() throws {
        let store = makeStore()
        defer { store.clearAPIKey() }
        #expect(store.loadAPIKey() == nil)
        try store.saveAPIKey("sk-test-123")
        #expect(store.loadAPIKey() == "sk-test-123")
        store.clearAPIKey()
        #expect(store.loadAPIKey() == nil)
    }

    @Test func isConfiguredRequiresAllFields() throws {
        let store = makeStore()
        defer { store.clearAPIKey() }
        #expect(store.isConfigured(baseURL: "https://api.openai.com/v1", model: "gpt-4o") == false)
        try store.saveAPIKey("sk-x")
        #expect(store.isConfigured(baseURL: "  ", model: "gpt-4o") == false)
        #expect(store.isConfigured(baseURL: "https://api.openai.com/v1", model: "") == false)
        #expect(store.isConfigured(baseURL: "https://api.openai.com/v1", model: "gpt-4o") == true)
    }
}
