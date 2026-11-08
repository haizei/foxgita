import Foundation
import Testing
@testable import foxgita

@MainActor private final class EarlyFocusPersistence: NextFocusPersisting {
    var files: [UUID: Data] = [:]
    var failWrites = false
    func read(profileID: UUID) throws -> Data? { files[profileID] }
    func write(_ data: Data, profileID: UUID) throws {
        if failWrites { throw CocoaError(.fileWriteOutOfSpace) }
        files[profileID] = data
    }
    func removeAll() throws { files.removeAll() }
}

@MainActor private final class EarlyFocusGenerator: NextFocusGenerating {
    var calls = 0
    func generate(context: NextFocusContext, supplement: String, baseURL: String,
                  model: String, apiKey: String) async throws -> NextFocusOutput {
        calls += 1
        try await Task.sleep(for: .seconds(30))
        return .init(recap: "已记录", focus: "继续C到G", basis: "练习对象")
    }
}

@MainActor private final class FailingEarlyFocusGenerator: NextFocusGenerating {
    var calls = 0
    var failure: CheckedContinuation<NextFocusOutput, any Error>?
    func generate(context: NextFocusContext, supplement: String, baseURL: String,
                  model: String, apiKey: String) async throws -> NextFocusOutput {
        calls += 1
        return try await withCheckedThrowingContinuation { failure = $0 }
    }
}

@MainActor struct NextFocusEarlyStartTests {
    private func fixture(_ disk: EarlyFocusPersistence) throws -> (PracticeStore, PracticeItem) {
        let repo = InMemoryPracticeRepository()
        let store = PracticeStore(repository: repo, defaults: UserDefaults(suiteName: "early-focus.\(UUID())")!,
                                  suggestions: NextFocusStore(persistence: disk))
        store.prepare()
        let item = try store.createPracticeItem(input: .init(title: "C到G", category: .chord,
            source: .custom, originId: nil, bpm: 80, timeSignature: "4/4", steps: ["C到G"]), now: .now, calendar: .current)
        try store.savePracticeItem(id: item.id, durationSeconds: 42, note: "第3小节仍有停顿", now: .now)
        return (store, item)
    }

    @Test func startsBeforeEditorAndDoesNotDuplicateTheRequest() async throws {
        let (store, item) = try fixture(EarlyFocusPersistence())
        let client = EarlyFocusGenerator()
        #expect(try store.startNextFocusAfterCompletion(itemID: item.id, enabled: true,
            baseURL: "https://example.invalid/v1", model: "test", apiKey: "test", client: client))
        let context = try store.nextFocusContext(itemID: item.id)
        #expect(store.suggestions.isGenerating(context))
        #expect(try !store.startNextFocusAfterCompletion(itemID: item.id, enabled: true,
            baseURL: "https://example.invalid/v1", model: "test", apiKey: "test", client: client))
        for _ in 0..<100 where client.calls == 0 { await Task.yield() }
        #expect(client.calls == 1)
        try store.suggestions.reset()
    }

    @Test func disabledOrMissingCredentialsDoNotStartOrCreateDrafts() throws {
        let (store, item) = try fixture(EarlyFocusPersistence())
        #expect(try !store.startNextFocusAfterCompletion(itemID: item.id, enabled: false,
            baseURL: "https://example.invalid/v1", model: "test", apiKey: "test"))
        #expect(try !store.startNextFocusAfterCompletion(itemID: item.id, enabled: true,
            baseURL: "https://example.invalid/v1", model: "test", apiKey: nil))
        #expect(store.suggestions.documents.isEmpty)
    }

    @Test func existingEditsRemainUntouched() throws {
        let (store, item) = try fixture(EarlyFocusPersistence())
        _ = try store.suggestions.prepare(store.nextFocusContext(itemID: item.id))
        try store.suggestions.edit(profileID: item.profileId, sourceID: item.id, text: "我改练主歌")
        #expect(try !store.startNextFocusAfterCompletion(itemID: item.id, enabled: true,
            baseURL: "https://example.invalid/v1", model: "test", apiKey: "test"))
        #expect(try store.suggestions.document(item.profileId).drafts[item.id.uuidString]?.text == "我改练主歌")
    }

    @Test func startupFailureDoesNotUndoSavedPracticeFacts() throws {
        let disk = EarlyFocusPersistence()
        let (store, item) = try fixture(disk)
        disk.failWrites = true
        #expect(throws: (any Error).self) {
            try store.startNextFocusAfterCompletion(itemID: item.id, enabled: true,
                baseURL: "https://example.invalid/v1", model: "test", apiKey: "test")
        }
        #expect(item.durationSeconds == 42)
        #expect(item.note == "第3小节仍有停顿")
    }

    @Test func failedErrorPersistenceStillRequiresExplicitRetry() async throws {
        let disk = EarlyFocusPersistence()
        let (store, item) = try fixture(disk)
        let client = FailingEarlyFocusGenerator()
        #expect(try store.startNextFocusAfterCompletion(itemID: item.id, enabled: true,
            baseURL: "https://example.invalid/v1", model: "test", apiKey: "test", client: client))
        for _ in 0..<100 where client.failure == nil { await Task.yield() }
        let failure = try #require(client.failure)
        disk.failWrites = true
        failure.resume(throwing: URLError(.timedOut))
        let context = try store.nextFocusContext(itemID: item.id)
        for _ in 0..<100 where store.suggestions.isGenerating(context) { await Task.yield() }
        #expect(!store.suggestions.isGenerating(context))
        #expect(store.suggestions.generationError(context) != nil)
        disk.failWrites = false
        #expect(try !store.startNextFocusAfterCompletion(itemID: item.id, enabled: true,
            baseURL: "https://example.invalid/v1", model: "test", apiKey: "test", client: client))
        #expect(client.calls == 1)
        try store.suggestions.reset()
    }
}
