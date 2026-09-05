import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct AIInvocationStoreTests {
    private func makeStore() throws -> (AIInvocationStore, ModelContext) {
        let schema = Schema(versionedSchema: GitaSchemaV14.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        profile.isActive = true
        context.insert(profile)
        try context.save()
        return (AIInvocationStore(context: context), context)
    }

    private func input(
        id: String,
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        status: AIInvocationStatus = .success,
        error: AIInvocationErrorType? = nil,
        memoryIds: [String] = ["m1"],
        outcome: AIDraftOutcome? = nil
    ) -> AIInvocationRecordInput {
        AIInvocationRecordInput(
            id: id,
            skillId: SkillID.nextSession,
            skillVersion: SkillDefinition.nextSession.version,
            model: "gpt-4o",
            startedAt: startedAt,
            durationMs: 42,
            status: status,
            errorType: error,
            memoryIds: memoryIds,
            formatRetryUsed: false,
            draftOutcome: outcome
        )
    }

    @Test func recordSuccessThenPrivacyBlobHasNoSecrets() throws {
        let (store, _) = try makeStore()
        store.record(input(id: "inv-1"))
        let row = try #require(store.recent().first)
        #expect(row.statusRaw == "success")
        #expect(row.errorTypeRaw.isEmpty)
        #expect(row.skillId == SkillID.nextSession)
        #expect(row.memoryIdsRaw == "m1")
        let blob = AIInvocationStore.debugBlob(of: row)
        #expect(!blob.contains("sk-"))
        #expect(!blob.contains("Bearer"))
        #expect(!blob.contains("BACKGROUND_MEMORY"))
        #expect(!blob.contains("data:image"))
    }

    @Test func recordFailureKeepsErrorTypeAndDuplicateInsertIsIgnored() throws {
        let (store, _) = try makeStore()
        store.record(input(id: "inv-1", status: .failure, error: .invalidJSON, outcome: .abandoned))
        store.record(input(id: "inv-1", status: .success))
        let rows = store.recent()
        #expect(rows.count == 1)
        #expect(rows[0].statusRaw == "failure")
        #expect(rows[0].errorTypeRaw == "invalidJSON")
        #expect(rows[0].draftOutcomeRaw == "abandoned")
    }

    @Test func setDraftOutcomeAndCompleteOnce() throws {
        let (store, _) = try makeStore()
        store.record(input(id: "inv-1"))
        let itemId = UUID()
        store.setDraftOutcome(id: "inv-1", outcome: .accepted, taskId: itemId.uuidString)
        let first = Date(timeIntervalSince1970: 1_700_000_100)
        store.markCompleted(taskId: itemId.uuidString, now: first)
        store.markCompleted(taskId: itemId.uuidString, now: first.addingTimeInterval(60))
        let row = try #require(store.recent().first)
        #expect(row.draftOutcomeRaw == "accepted")
        #expect(row.taskId == itemId.uuidString)
        #expect(row.completedAt == first)
    }

    @Test func pruneKeeps200NewestPerProfile() throws {
        let (store, _) = try makeStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<201 {
            store.record(input(
                id: "inv-\(i)",
                startedAt: base.addingTimeInterval(TimeInterval(i))
            ))
        }
        let rows = store.recent()
        #expect(rows.count == 200)
        #expect(rows.first?.id == "inv-200")
        #expect(rows.last?.id == "inv-1")
        #expect(!rows.contains(where: { $0.id == "inv-0" }))
    }

    @Test func mapsCancelledAndUnknownErrors() {
        #expect(AIInvocationStore.errorType(from: CancellationError()) == .cancelled)
        #expect(AIInvocationStore.errorType(from: URLError(.cancelled)) == .cancelled)
        #expect(AIInvocationStore.errorType(from: VisionPracticeError.unauthorized) == .unauthorized)
        #expect(AIInvocationStore.errorType(from: VisionPracticeError.httpStatus(502)) == .httpStatus)
        #expect(AIInvocationStore.errorType(from: NSError(domain: "x", code: 1)) == .transport)
    }
}
