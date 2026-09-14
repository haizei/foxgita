import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct CandidateMemoryApprovalTests {
    private func harness(consent: MemoryConsentState = .enabled) throws -> (
        PracticeStore, SwiftDataMemoryRepository, SwiftDataPracticeRepository, UserDefaults
    ) {
        let schema = Schema(versionedSchema: GitaSchemaV18.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        profile.consent = consent
        context.insert(profile)
        try context.save()
        let memory = SwiftDataMemoryRepository(context: context)
        let practice = SwiftDataPracticeRepository(context: context)
        let defaults = UserDefaults(suiteName: "candidate-memory.\(UUID().uuidString)")!
        defaults.set(true, forKey: SeedData.seededKey)
        let store = PracticeStore(
            repository: practice,
            defaults: defaults,
            aiCandidateSync: AICandidateSync(repository: memory, context: context),
            candidateApprovalGate: CandidateMemoryApprovalGate(secret: Data("candidate-test".utf8))
        )
        let taskID = try #require(store.createCustomTask(name: "和弦", minutes: 10, category: .chord))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = store.finishSession(
            taskId: taskID, steps: ["慢练"], note: "",
            startedAt: now, endedAt: now.addingTimeInterval(60),
            durationSec: 60, bpm: 80, recordings: []
        )
        let session = try #require(practice.sessions().first)
        session.recordings.append(
            RecordingRef(id: "clip-1", fileName: "take.m4a", bytes: 8, durationSec: 12)
        )
        try practice.save()
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳定", focus: "换弦速度", nextAction: "慢练")
        )
        return (store, memory, practice, defaults)
    }

    @Test func reviewStagesCandidateWithoutImplicitMemoryWrite() throws {
        let (store, memory, _, _) = try harness()

        let draft = try #require(store.candidateMemoryDraft(recordingId: "clip-1"))

        #expect(draft.evidenceID == "clip-1")
        #expect(draft.semantic == "换弦速度")
        #expect(draft.evidenceSummary.contains("录音"))
        #expect(try memory.fetch(
            profileId: "p1", scopes: [.ability], matching: "", now: Date()
        ).isEmpty)
    }

    @Test func rememberRequiresBoundApprovalAndCannotReplay() async throws {
        let (store, memory, _, _) = try harness()
        let draft = try #require(store.candidateMemoryDraft(recordingId: "clip-1"))
        let token = store.issueCandidateMemoryApproval(
            draft, userID: "p1", sessionID: "screen-1"
        )

        try await store.rememberCandidateMemory(
            draft, token: token, userID: "p1", sessionID: "screen-1"
        )

        let rows = try memory.fetch(
            profileId: "p1", scopes: [.ability], matching: "", now: Date()
        )
        #expect(rows.map(\.summaryText) == ["换弦速度"])
        #expect(store.candidateMemoryDraft(recordingId: "clip-1") == nil)
        await #expect(throws: GateRefusal.approvalReplayed) {
            try await store.rememberCandidateMemory(
                draft, token: token, userID: "p1", sessionID: "screen-1"
            )
        }
    }

    @Test func editedOrExpiredCandidateCannotBeRemembered() async throws {
        let (store, memory, _, _) = try harness()
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let draft = try #require(store.candidateMemoryDraft(recordingId: "clip-1"))
        let token = store.issueCandidateMemoryApproval(
            draft, userID: "p1", sessionID: "screen-1", now: now
        )
        var edited = draft
        edited.semantic = "节奏稳定性"

        await #expect(throws: GateRefusal.approvalMismatch) {
            try await store.rememberCandidateMemory(
                edited, token: token, userID: "p1", sessionID: "screen-1", now: now
            )
        }
        let expired = store.issueCandidateMemoryApproval(
            draft, userID: "p1", sessionID: "screen-2", now: now
        )
        await #expect(throws: GateRefusal.approvalExpired) {
            try await store.rememberCandidateMemory(
                draft, token: expired, userID: "p1", sessionID: "screen-2",
                now: now.addingTimeInterval(301)
            )
        }
        #expect(try memory.fetch(
            profileId: "p1", scopes: [.ability], matching: "", now: Date()
        ).isEmpty)
    }

    @Test func ignoreSuppressesSameEvidenceAndSemanticButNotNewEvidence() throws {
        let (store, _, practice, _) = try harness()
        let draft = try #require(store.candidateMemoryDraft(recordingId: "clip-1"))

        store.ignoreCandidateMemory(draft)
        #expect(store.candidateMemoryDraft(recordingId: "clip-1") == nil)

        let session = try #require(practice.sessions().first)
        session.recordings.append(
            RecordingRef(id: "clip-2", fileName: "take-2.m4a", bytes: 8, durationSec: 12)
        )
        try practice.save()
        store.applyReview(
            recordingId: "clip-2",
            draft: MediaReviewDraft(highlight: "稳定", focus: "换弦速度", nextAction: "慢练")
        )
        #expect(store.candidateMemoryDraft(recordingId: "clip-2") != nil)
    }

    @Test func disabledConsentDoesNotOfferCandidate() throws {
        let (store, _, _, _) = try harness(consent: .disabled)
        #expect(store.candidateMemoryDraft(recordingId: "clip-1") == nil)
    }
}
