import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct AICandidateSyncTests {
    private func make(consent: MemoryConsentState = .enabled) throws -> (
        AICandidateSync, SwiftDataMemoryRepository, ModelContext, LocalProfile
    ) {
        let schema = Schema(versionedSchema: GitaSchemaV11.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        profile.consent = consent
        context.insert(profile)
        try context.save()
        let repo = SwiftDataMemoryRepository(context: context)
        return (AICandidateSync(repository: repo, context: context), repo, context, profile)
    }

    @Test func syncFocusNoopsWhenDisabledOrDenySkill() throws {
        let (offSync, offRepo, _, _) = try make(consent: .disabled)
        offSync.syncFocus(
            profileId: "p1", focus: "压弦", recordingId: "clip-1",
            skill: .reviewMedia
        )
        #expect(try offRepo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)

        let (onSync, onRepo, _, _) = try make(consent: .enabled)
        onSync.syncFocus(
            profileId: "p1", focus: "压弦", recordingId: "clip-1",
            skill: .planFromImage
        )
        #expect(try onRepo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)
        #expect(SkillDefinition.planFromImage.memoryWritePolicy == .deny)
        #expect(onSync.lastError == nil)
    }

    @Test func syncFocusWritesReviewThenOverwritesWithDiagnosis() throws {
        let (sync, repo, _, _) = try make()
        sync.syncFocus(
            profileId: "p1", focus: "  压弦  ", recordingId: "clip-1",
            skill: .reviewMedia
        )
        var rows = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].summaryText == "压弦")
        #expect(rows[0].sourceType == "ai")
        #expect(rows[0].sourceId == "clip-1")
        #expect(rows[0].valueJSON == "practice.review.media@1.1.0")
        #expect(rows[0].confidence == 0.4)
        #expect(sync.lastError == nil)

        sync.syncFocus(
            profileId: "p1", focus: "节奏", recordingId: "clip-2",
            skill: .diagnoseVideo
        )
        rows = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].summaryText == "节奏")
        #expect(rows[0].sourceId == "clip-2")
        #expect(rows[0].valueJSON == "practice.diagnose.video@1.1.0")
    }

    @Test func syncFocusUsesPassedProfileNotActiveOne() throws {
        let (sync, repo, context, _) = try make()
        let p2 = LocalProfile(id: "p2", isActive: false)
        p2.consent = .enabled
        context.insert(p2)
        try context.save()
        sync.syncFocus(
            profileId: "p2", focus: "别人的重点", recordingId: "clip-b",
            skill: .reviewMedia
        )
        #expect(try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)
        #expect(
            try repo.fetch(profileId: "p2", scopes: [.ability], matching: "", now: Date())
                .map(\.summaryText) == ["别人的重点"]
        )
    }

    @Test func syncFocusNoopsEmptyProfileId() throws {
        let (sync, repo, _, _) = try make()
        sync.syncFocus(
            profileId: "", focus: "压弦", recordingId: "clip-1",
            skill: .reviewMedia
        )
        #expect(try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)
        #expect(sync.lastError == nil)
    }

    private func makeWired(consent: MemoryConsentState = .enabled) throws -> (
        PracticeStore, SwiftDataMemoryRepository, SwiftDataPracticeRepository, LocalProfile
    ) {
        let schema = Schema(versionedSchema: GitaSchemaV11.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        profile.consent = consent
        context.insert(profile)
        try context.save()
        let memoryRepo = SwiftDataMemoryRepository(context: context)
        let practiceRepo = SwiftDataPracticeRepository(context: context)
        let defaults = UserDefaults(suiteName: "foxgita.tests.\(UUID().uuidString)")!
        defaults.set(true, forKey: SeedData.seededKey)
        let store = PracticeStore(
            repository: practiceRepo,
            defaults: defaults,
            aiCandidateSync: AICandidateSync(repository: memoryRepo, context: context)
        )
        return (store, memoryRepo, practiceRepo, profile)
    }

    private func addReadyClip(
        store: PracticeStore,
        practiceRepo: SwiftDataPracticeRepository,
        recordingId: String
    ) throws {
        let taskId = store.createCustomTask(name: "练晴天", minutes: 10, category: .chord)!
        let now = Date()
        #expect(store.finishSession(
            taskId: taskId, steps: ["慢练"], note: "笔记",
            startedAt: now, endedAt: now, durationSec: 60, bpm: 80,
            recordings: []
        ) != nil)
        let session = try practiceRepo.sessions()[0]
        session.recordings.append(
            RecordingRef(id: recordingId, fileName: "y.m4a", bytes: 2, durationSec: 20)
        )
        try practiceRepo.save()
    }

    @Test func applyReviewWritesCandidateOnlyWhenEnabled() throws {
        let (offStore, offRepo, offPractice, _) = try makeWired(consent: .disabled)
        try addReadyClip(store: offStore, practiceRepo: offPractice, recordingId: "clip-off")
        offStore.applyReview(
            recordingId: "clip-off",
            draft: MediaReviewDraft(highlight: "稳", focus: "压弦", nextAction: "慢练")
        )
        #expect(try offPractice.recording(id: "clip-off")?.reviewStatus == .ready)
        #expect(try offRepo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)

        let (onStore, onRepo, onPractice, _) = try makeWired(consent: .enabled)
        try addReadyClip(store: onStore, practiceRepo: onPractice, recordingId: "clip-on")
        onStore.applyReview(
            recordingId: "clip-on",
            draft: MediaReviewDraft(highlight: "稳", focus: "压弦", nextAction: "慢练")
        )
        let rows = try onRepo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].summaryText == "压弦")
        #expect(rows[0].sourceType == "ai")
        #expect(rows[0].sourceId == "clip-on")
        #expect(rows[0].valueJSON.contains("practice.review.media@1.1.0"))
        #expect(rows[0].confidence == 0.4)
        #expect(rows[0].importance == 0.4)
    }

    @Test func applyVideoDiagnosisOverwritesSameKey() throws {
        let (store, repo, practice, _) = try makeWired()
        try addReadyClip(store: store, practiceRepo: practice, recordingId: "clip-1")
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳", focus: "压弦", nextAction: "慢练")
        )
        store.applyVideoDiagnosis(
            recordingId: "clip-1",
            draft: VideoDiagnosisDraft(
                highlight: "稳", focus: "节奏", nextAction: "70", findings: []
            )
        )
        let rows = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].summaryText == "节奏")
        #expect(rows[0].valueJSON.contains("practice.diagnose.video@1.1.0"))
        #expect(try practice.recording(id: "clip-1")?.reviewStatus == .ready)
    }

    @Test func markReviewsFailedDoesNotWriteCandidate() throws {
        let (store, repo, practice, _) = try makeWired()
        try addReadyClip(store: store, practiceRepo: practice, recordingId: "clip-fail")
        store.markReviewsFailed(recordingIds: ["clip-fail"])
        #expect(try practice.recording(id: "clip-fail")?.reviewStatus == .failed)
        #expect(try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)
    }

    @Test func deletedCandidateDoesNotResurrectOnReview() throws {
        let (store, repo, practice, _) = try makeWired()
        try addReadyClip(store: store, practiceRepo: practice, recordingId: "clip-1")
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳", focus: "压弦", nextAction: "慢练")
        )
        let id = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())[0].id
        try repo.softDelete(profileId: "p1", id: id)
        try repo.save()
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳", focus: "新重点", nextAction: "慢练")
        )
        #expect(try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)
        #expect(try practice.recording(id: "clip-1")?.reviewStatus == .ready)
    }

    @Test func userEditedCandidateIsNotOverwritten() throws {
        let (store, repo, practice, _) = try makeWired()
        try addReadyClip(store: store, practiceRepo: practice, recordingId: "clip-1")
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳", focus: "压弦", nextAction: "慢练")
        )
        let id = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())[0].id
        try repo.updateSummary(profileId: "p1", id: id, summaryText: "用户重点")
        try repo.save()
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳", focus: "新重点", nextAction: "慢练")
        )
        let rows = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
        #expect(rows[0].summaryText == "用户重点")
        #expect(rows[0].sourceType == "user")
    }

    @Test func emptySessionProfileIdSkipsCandidate() throws {
        let (store, repo, practice, _) = try makeWired()
        try addReadyClip(store: store, practiceRepo: practice, recordingId: "clip-1")
        try practice.sessions()[0].profileId = ""
        try practice.save()
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳", focus: "压弦", nextAction: "慢练")
        )
        #expect(try practice.recording(id: "clip-1")?.reviewStatus == .ready)
        #expect(try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)
    }

    @Test func memorySaveFailureDoesNotRollbackReview() throws {
        let schema = Schema(versionedSchema: GitaSchemaV11.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        profile.consent = .enabled
        context.insert(profile)
        try context.save()
        let practiceRepo = SwiftDataPracticeRepository(context: context)
        let defaults = UserDefaults(suiteName: "foxgita.tests.\(UUID().uuidString)")!
        defaults.set(true, forKey: SeedData.seededKey)
        let store = PracticeStore(
            repository: practiceRepo,
            defaults: defaults,
            aiCandidateSync: AICandidateSync(
                repository: SaveFailingMemoryRepository(), context: context
            )
        )
        try addReadyClip(store: store, practiceRepo: practiceRepo, recordingId: "clip-1")
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳", focus: "压弦", nextAction: "慢练")
        )
        #expect(try practiceRepo.recording(id: "clip-1")?.reviewStatus == .ready)
        #expect(store.lastError == .saveFailed)
    }
}

@MainActor
private final class SaveFailingMemoryRepository: MemoryRepository {
    func fetch(
        profileId: String, scopes: [MemoryScope], matching query: String, now: Date
    ) throws -> [MemoryItem] { [] }
    func upsertDebug(_ item: MemoryItem) throws {}
    func save() throws { throw StoreError.saveFailed }
    func upsertUser(profileId: String, kind: MemoryScope, summaryText: String) throws -> MemoryItem {
        throw StoreError.invalidInput
    }
    func updateSummary(profileId: String, id: String, summaryText: String) throws {}
    func softDelete(profileId: String, id: String) throws {}
    func softDeleteAll(profileId: String) throws {}
    func setConsent(profileId: String, _ state: MemoryConsentState) throws {}
    func upsertTaskGoal(profileId: String, taskId: String, title: String) throws {}
    func softDeleteTaskGoal(profileId: String, taskId: String) throws {}
    func upsertAICandidate(
        profileId: String, recordingId: String, summaryText: String, valueJSON: String
    ) throws {}
    func upsertDurationPreference(profileId: String, minutes: Int) throws {}
}
