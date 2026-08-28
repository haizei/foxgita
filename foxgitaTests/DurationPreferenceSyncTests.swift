import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct DurationPreferenceSyncTests {
    private func make(consent: MemoryConsentState = .enabled) throws -> (
        DurationPreferenceSync, SwiftDataMemoryRepository, ModelContext, LocalProfile
    ) {
        let schema = Schema(versionedSchema: GitaSchemaV10.self)
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
        return (DurationPreferenceSync(repository: repo, context: context), repo, context, profile)
    }

    @Test func syncNoopsWhenDisabledOrEmptyProfile() throws {
        let (offSync, offRepo, _, _) = try make(consent: .disabled)
        offSync.sync(profileId: "p1", minutes: 20)
        #expect(try offRepo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date()).isEmpty)
        #expect(offSync.lastError == nil)

        let (onSync, onRepo, _, _) = try make(consent: .enabled)
        onSync.sync(profileId: "", minutes: 20)
        #expect(try onRepo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date()).isEmpty)
    }

    @Test func syncWritesWhenEnabled() throws {
        let (sync, repo, _, _) = try make()
        sync.sync(profileId: "p1", minutes: 20)
        let rows = try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].key == "practice.available_minutes")
        #expect(rows[0].valueJSON == "20")
        #expect(rows[0].sourceType == "user")
        #expect(sync.lastError == nil)
    }

    @Test func syncUsesPassedProfileNotActiveOne() throws {
        let (sync, repo, context, _) = try make()
        let p2 = LocalProfile(id: "p2", isActive: false)
        p2.consent = .enabled
        context.insert(p2)
        try context.save()
        sync.sync(profileId: "p2", minutes: 30)
        #expect(try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date()).isEmpty)
        #expect(
            try repo.fetch(profileId: "p2", scopes: [.preference], matching: "", now: Date())
                .map(\.valueJSON) == ["30"]
        )
    }

    @Test func syncActiveWritesActiveProfile() throws {
        let (sync, repo, _, _) = try make()
        sync.syncActive(minutes: 25)
        #expect(
            try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date())
                .map(\.valueJSON) == ["25"]
        )
    }
}
