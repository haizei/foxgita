import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct MemoryRepositoryTests {
    private func makeRepo() throws -> SwiftDataMemoryRepository {
        let schema = Schema(versionedSchema: GitaSchemaV6.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return SwiftDataMemoryRepository(context: ModelContext(container))
    }

    private func item(
        profileId: String,
        kind: MemoryScope,
        key: String,
        summary: String,
        importance: Double = 0.5,
        expiresAt: Date? = nil
    ) -> MemoryItem {
        MemoryItem(
            profileId: profileId, kind: kind, key: key, summaryText: summary,
            sourceType: "debug_seed", sourceId: key,
            confidence: 1, importance: importance, expiresAt: expiresAt
        )
    }

    @Test func fetchRequiresProfileId() throws {
        let repo = try makeRepo()
        #expect(throws: StoreError.invalidInput) {
            try repo.fetch(profileId: "", scopes: [.goal], matching: "", now: Date())
        }
    }

    @Test func fetchIsolatesProfilesAndSkipsDeletedExpiredAndOtherScopes() throws {
        let repo = try makeRepo()
        let now = Date()
        try repo.upsertDebug(item(profileId: "a", kind: .goal, key: "goal.current_song", summary: "A歌"))
        try repo.upsertDebug(item(profileId: "b", kind: .goal, key: "goal.current_song", summary: "B歌"))
        let deleted = item(profileId: "a", kind: .preference, key: "practice.available_minutes", summary: "删")
        deleted.deletedAt = now
        try repo.upsertDebug(deleted)
        try repo.upsertDebug(item(
            profileId: "a", kind: .ability, key: "technique.barre_chord.F",
            summary: "过期", expiresAt: now.addingTimeInterval(-1)
        ))
        try repo.save()

        let rows = try repo.fetch(profileId: "a", scopes: [.goal], matching: "", now: now)
        #expect(rows.map(\.summaryText) == ["A歌"])
        let b = try repo.fetch(profileId: "b", scopes: [.goal], matching: "", now: now)
        #expect(b.map(\.summaryText) == ["B歌"])
    }

    @Test func upsertDebugOverwritesSameKey() throws {
        let repo = try makeRepo()
        try repo.upsertDebug(item(profileId: "a", kind: .goal, key: "goal.current_song", summary: "旧"))
        try repo.upsertDebug(item(profileId: "a", kind: .goal, key: "goal.current_song", summary: "新"))
        try repo.save()
        let rows = try repo.fetch(profileId: "a", scopes: [.goal], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].summaryText == "新")
    }
}
