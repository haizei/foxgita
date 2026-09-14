import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct AIInvocationStoreTests {
    private func makeStore() throws -> (AIInvocationStore, ModelContext) {
        let schema = Schema(versionedSchema: GitaSchemaV18.self)
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

    @Test func recordsPlatformMetadataAndLinksDownstreamOutcomes() throws {
        let (store, _) = try makeStore()
        let executionStartedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let executionCompletedAt = executionStartedAt.addingTimeInterval(60)

        store.record(AIInvocationRecordInput(
            id: "inv-platform",
            skillId: SkillID.nextSession,
            skillVersion: "1.0.0",
            model: "gpt-4o",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationMs: 42,
            status: .success,
            errorType: nil,
            memoryIds: ["m1"],
            formatRetryUsed: true,
            draftOutcome: nil,
            runtime: "messages",
            executionState: .presenting,
            sessionID: "session-1",
            staticPromptFingerprint: "static-fp",
            historyPrefixFingerprint: "history-fp",
            contextFingerprint: "context-fp",
            toolsetFingerprint: "tools-fp",
            usage: RuntimeUsage(
                inputTokens: 10,
                outputTokens: 20,
                cacheWriteTokens: 3,
                cacheReadTokens: 4
            )
        ))
        store.markArtifact(
            invocationID: "inv-platform",
            artifactID: "artifact-1",
            contextSnapshotID: "snapshot-1"
        )
        store.markBusinessObject(invocationID: "inv-platform", businessObjectID: "task-1")
        store.markStarted(invocationID: "inv-platform", at: executionStartedAt)
        store.markCompleted(invocationID: "inv-platform", at: executionCompletedAt)
        store.markArtifact(
            invocationID: "inv-platform",
            artifactID: "artifact-2",
            contextSnapshotID: "snapshot-2"
        )
        store.markBusinessObject(invocationID: "inv-platform", businessObjectID: "task-2")
        store.markStarted(invocationID: "inv-platform", at: executionStartedAt.addingTimeInterval(60))
        store.markCompleted(invocationID: "inv-platform", at: executionCompletedAt.addingTimeInterval(60))

        let row = try #require(store.recent().first)
        #expect(row.runtime == "messages")
        #expect(row.executionState == AIExecutionState.completed.rawValue)
        #expect(row.sessionId == "session-1")
        #expect(row.staticPromptFingerprint == "static-fp")
        #expect(row.historyPrefixFingerprint == "history-fp")
        #expect(row.contextFingerprint == "context-fp")
        #expect(row.toolsetFingerprint == "tools-fp")
        #expect(row.inputTokens == 10)
        #expect(row.outputTokens == 20)
        #expect(row.cacheWriteTokens == 3)
        #expect(row.cacheReadTokens == 4)
        #expect(row.artifactId == "artifact-1")
        #expect(row.contextSnapshotId == "snapshot-1")
        #expect(row.businessObjectId == "task-1")
        #expect(row.businessObjectStartedAt == executionStartedAt)
        #expect(row.businessObjectCompletedAt == executionCompletedAt)
    }

    @Test func debugBlobContainsFingerprintsButNoPromptOrCredentials() throws {
        let (store, _) = try makeStore()
        store.record(AIInvocationRecordInput(
            id: "inv-safe-debug",
            skillId: SkillID.nextSession,
            skillVersion: "1.0.0",
            model: "Bearer secret-token",
            startedAt: Date(),
            durationMs: 1,
            status: .success,
            errorType: nil,
            memoryIds: [],
            formatRetryUsed: false,
            draftOutcome: nil,
            staticPromptFingerprint: "/Users/person/private/media.mov",
            contextFingerprint: "sk-secret",
            toolsetFingerprint: "file:///Users/person/private/media.mov",
            refusalType: "proxy/sk-secret"
        ))

        let row = try #require(store.recent().first)
        let blob = AIInvocationStore.debugBlob(of: row)
        #expect(row.model == "redacted")
        #expect(row.refusalTypeRaw == "redacted")
        #expect(row.staticPromptFingerprint == "redacted")
        #expect(row.contextFingerprint == "redacted")
        #expect(row.toolsetFingerprint == "redacted")
        #expect(!blob.contains("Bearer"))
        #expect(!blob.contains("secret-token"))
        #expect(!blob.contains("/Users/"))
        #expect(!blob.contains("sk-secret"))
        #expect(!blob.contains("proxy/sk-"))
        #expect(!blob.contains("file:///"))
    }

    @Test func regenerateLinksBothInvocationsAndRecordsOutcome() throws {
        let (store, _) = try makeStore()
        store.record(input(id: "inv-original"))
        store.record(input(id: "inv-successor"))

        store.markRegenerated(
            invocationID: "inv-original",
            successorInvocationID: "inv-successor",
            now: Date(timeIntervalSince1970: 1_700_000_200)
        )

        let rows = Dictionary(uniqueKeysWithValues: store.recent().map { ($0.id, $0) })
        #expect(rows["inv-original"]?.draftOutcomeRaw == AIDraftOutcome.regenerated.rawValue)
        #expect(rows["inv-original"]?.successorInvocationId == "inv-successor")
        #expect(rows["inv-successor"]?.predecessorInvocationId == "inv-original")
    }

    @Test func latestInvocationFindsNewestPersistedBusinessObjectRun() throws {
        let (store, _) = try makeStore()
        store.record(input(id: "inv-old", startedAt: Date(timeIntervalSince1970: 100)))
        store.record(input(id: "inv-new", startedAt: Date(timeIntervalSince1970: 200)))
        store.markBusinessObject(invocationID: "inv-old", businessObjectID: "recording-1")
        store.markBusinessObject(invocationID: "inv-new", businessObjectID: "recording-1")

        #expect(store.latestInvocationID(
            businessObjectID: "recording-1",
            skillID: SkillID.nextSession
        ) == "inv-new")
        #expect(store.latestInvocationID(
            businessObjectID: "recording-2",
            skillID: SkillID.nextSession
        ) == nil)
    }

    @Test func latestInvocationIsIsolatedToActiveProfile() throws {
        let (store, context) = try makeStore()
        store.record(input(id: "inv-profile-1", startedAt: Date(timeIntervalSince1970: 300)))
        store.markBusinessObject(invocationID: "inv-profile-1", businessObjectID: "shared-recording")

        let profile1 = try #require(context.fetch(
            FetchDescriptor<LocalProfile>(predicate: #Predicate { $0.id == "p1" })
        ).first)
        profile1.isActive = false
        let profile2 = LocalProfile(id: "p2")
        profile2.isActive = true
        context.insert(profile2)
        try context.save()
        store.record(input(id: "inv-profile-2", startedAt: Date(timeIntervalSince1970: 200)))
        store.markBusinessObject(invocationID: "inv-profile-2", businessObjectID: "shared-recording")

        #expect(store.latestInvocationID(
            businessObjectID: "shared-recording",
            skillID: SkillID.nextSession
        ) == "inv-profile-2")
    }

    @Test func regenerateRejectsSelfLink() throws {
        let (store, _) = try makeStore()
        store.record(input(id: "inv-same"))

        store.markRegenerated(invocationID: "inv-same", successorInvocationID: "inv-same")

        let row = try #require(store.recent().first)
        #expect(row.predecessorInvocationId == nil)
        #expect(row.successorInvocationId == nil)
        #expect(row.draftOutcomeRaw.isEmpty)
    }

    @Test func recordSuccessThenPrivacyBlobHasNoSecrets() throws {
        let (store, _) = try makeStore()
        store.record(input(id: "inv-1"))
        let row = try #require(store.recent().first)
        #expect(row.statusRaw == "success")
        #expect(row.errorTypeRaw.isEmpty)
        #expect(row.skillId == SkillID.nextSession)
        #expect(row.memoryIdsRaw == "m1")
        #expect(row.runtime == nil)
        #expect(row.executionState == nil)
        #expect(row.inputTokens == nil)
        #expect(row.outputTokens == nil)
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

    @Test func failureWithoutExplicitOutcomeIsRecordedAsFailed() throws {
        let (store, _) = try makeStore()
        store.record(input(id: "inv-failed", status: .failure, error: .notConfigured))

        let row = try #require(store.recent().first)
        #expect(row.draftOutcomeRaw == AIDraftOutcome.failed.rawValue)
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
        #expect(row.businessObjectId == itemId.uuidString)
        #expect(row.businessObjectCompletedAt == first)
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
