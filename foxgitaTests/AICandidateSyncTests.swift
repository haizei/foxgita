import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct AICandidateSyncTests {
    private func make(consent: MemoryConsentState = .enabled) throws -> (
        AICandidateSync, SwiftDataMemoryRepository, ModelContext, LocalProfile
    ) {
        let schema = Schema(versionedSchema: GitaSchemaV7.self)
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
}
