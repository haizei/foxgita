import Foundation
import Testing
@testable import foxgita

private struct StubNextSessionClient: NextSessionGenerating {
    var draft: AIPracticeDraft?
    var error: VisionPracticeError?

    func generateDraft(
        baseURL: String,
        model: String,
        apiKey: String,
        budgetMinutes: Int,
        fallbackCategory: PracticeCategory,
        invocationId: String
    ) async throws -> AIPracticeDraft {
        if let error { throw error }
        return draft ?? AIPracticeDraft(
            title: "草稿", category: fallbackCategory, targetMin: budgetMinutes,
            steps: ["一步"], chords: []
        )
    }
}

final class CountingNextSessionClient: NextSessionGenerating, @unchecked Sendable {
    private(set) var calls = 0

    func generateDraft(
        baseURL: String,
        model: String,
        apiKey: String,
        budgetMinutes: Int,
        fallbackCategory: PracticeCategory,
        invocationId: String
    ) async throws -> AIPracticeDraft {
        calls += 1
        Issue.record("should not be called")
        throw VisionPracticeError.transport
    }
}

@MainActor
struct NextSessionGeneratorTests {
    @Test func notConfiguredWhenKeyMissing() async {
        let store = LLMCredentialsStore(service: "foxgita.tests.\(UUID().uuidString)")
        defer { store.clearAPIKey() }
        let generator = NextSessionGenerator(
            client: StubNextSessionClient(),
            credentials: store
        )
        await #expect(throws: NextSessionGeneratorError.notConfigured) {
            try await generator.generate(
                budgetMinutes: 20,
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                fallbackCategory: .chord,
                invocationId: "inv-test"
            )
        }
    }

    @Test func mapsVisionUnauthorized() async throws {
        let store = LLMCredentialsStore(service: "foxgita.tests.\(UUID().uuidString)")
        defer { store.clearAPIKey() }
        try store.saveAPIKey("sk-test")
        let generator = NextSessionGenerator(
            client: StubNextSessionClient(error: .unauthorized),
            credentials: store
        )
        do {
            _ = try await generator.generate(
                budgetMinutes: 20,
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                fallbackCategory: .chord,
                invocationId: "inv-test"
            )
            Issue.record("expected throw")
        } catch let error as NextSessionGeneratorError {
            #expect(error.userMessage == "API Key 无效或无权限")
        }
    }

    @Test func notConfiguredRecordsAndDoesNotCallClient() async {
        let spy = InvocationLogSpy()
        let client = CountingNextSessionClient()
        let generator = NextSessionGenerator(
            client: client,
            credentials: LLMCredentialsStore(service: "foxgita.tests.\(UUID().uuidString)"),
            log: spy
        )
        await #expect(throws: NextSessionGeneratorError.notConfigured) {
            try await generator.generate(
                budgetMinutes: 20, baseURL: "", model: "", fallbackCategory: .chord,
                invocationId: "inv-cfg"
            )
        }
        #expect(spy.inputs.first?.errorType == .notConfigured)
        #expect(client.calls == 0)
    }
}
