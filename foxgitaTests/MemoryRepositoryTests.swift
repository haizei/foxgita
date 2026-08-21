import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct MemoryRepositoryTests {
    private func makeRepo() throws -> SwiftDataMemoryRepository {
        let schema = Schema(versionedSchema: GitaSchemaV7.self)
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

    @Test func upsertUserRejectsAbilityEmptyAndOverlong() throws {
        let repo = try makeRepo()
        #expect(throws: StoreError.invalidInput) {
            try repo.upsertUser(profileId: "p1", kind: .ability, summaryText: "F 和弦")
        }
        #expect(throws: StoreError.invalidInput) {
            try repo.upsertUser(profileId: "p1", kind: .goal, summaryText: "   ")
        }
        #expect(throws: StoreError.invalidInput) {
            try repo.upsertUser(profileId: "p1", kind: .goal, summaryText: String(repeating: "啊", count: 121))
        }
    }

    @Test func upsertUserWritesGoalWithUserSourceAndFetches() throws {
        let repo = try makeRepo()
        let item = try repo.upsertUser(profileId: "p1", kind: .goal, summaryText: "  练晴天前奏  ")
        try repo.save()
        #expect(item.summaryText == "练晴天前奏")
        #expect(item.sourceType == "user")
        #expect(item.key.hasPrefix("user.goal."))
        #expect(item.confidence == 1)
        #expect(item.importance == 0.8)
        let rows = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows.map(\.summaryText) == ["练晴天前奏"])
    }

    @Test func updateSummaryLeavesKeyAndSoftDeleteHidesRow() throws {
        let repo = try makeRepo()
        let item = try repo.upsertUser(profileId: "p1", kind: .preference, summaryText: "每天 20 分钟")
        try repo.save()
        let key = item.key
        try repo.updateSummary(profileId: "p1", id: item.id, summaryText: "每天 30 分钟")
        try repo.save()
        let updated = try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date())
        #expect(updated[0].key == key)
        #expect(updated[0].summaryText == "每天 30 分钟")
        try repo.softDelete(profileId: "p1", id: item.id)
        try repo.save()
        #expect(try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date()).isEmpty)
    }

    @Test func setConsentRequiresProfileAndClearAllIsIsolated() throws {
        let schema = Schema(versionedSchema: GitaSchemaV7.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let repo = SwiftDataMemoryRepository(context: context)
        let p1 = LocalProfile(id: "p1")
        let p2 = LocalProfile(id: "p2", isActive: false)
        context.insert(p1)
        context.insert(p2)
        try context.save()

        #expect(throws: StoreError.invalidInput) {
            try repo.setConsent(profileId: "", .enabled)
        }
        try repo.setConsent(profileId: "p1", .enabled)
        try repo.save()
        #expect(p1.consent == .enabled)
        #expect(p1.memoryConsent == true)
        #expect(p2.consent == .undecided)

        _ = try repo.upsertUser(profileId: "p1", kind: .goal, summaryText: "A")
        _ = try repo.upsertUser(profileId: "p2", kind: .goal, summaryText: "B")
        try repo.save()
        try repo.softDeleteAll(profileId: "p1")
        try repo.save()
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)
        #expect(try repo.fetch(profileId: "p2", scopes: [.goal], matching: "", now: Date()).map(\.summaryText) == ["B"])
    }

    @Test func upsertTaskGoalRejectsEmptyIdsAndSkipsBlankTitle() throws {
        let repo = try makeRepo()
        #expect(throws: StoreError.invalidInput) {
            try repo.upsertTaskGoal(profileId: "", taskId: "custom-1", title: "练晴天")
        }
        #expect(throws: StoreError.invalidInput) {
            try repo.upsertTaskGoal(profileId: "p1", taskId: "", title: "练晴天")
        }
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: "   ")
        try repo.save()
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)
    }

    @Test func upsertTaskGoalInsertsTruncatesAndUpdatesTaskSourcedRow() throws {
        let repo = try makeRepo()
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: "  练晴天  ")
        try repo.save()
        var rows = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].key == "task.custom-1.title")
        #expect(rows[0].summaryText == "练晴天")
        #expect(rows[0].sourceType == "task")
        #expect(rows[0].sourceId == "custom-1")
        #expect(rows[0].kind == .goal)
        #expect(rows[0].confidence == 1)
        #expect(rows[0].importance == 0.6)

        let long = String(repeating: "啊", count: 121)
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: long)
        try repo.save()
        rows = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].summaryText.count == 120)
        #expect(rows[0].summaryText == String(long.prefix(120)))
    }

    @Test func upsertTaskGoalDoesNotOverwriteUserEditedOrTombstone() throws {
        let repo = try makeRepo()
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: "旧标题")
        try repo.save()
        let id = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())[0].id
        try repo.updateSummary(profileId: "p1", id: id, summaryText: "我改的")
        try repo.save()
        var rows = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows[0].sourceType == "user")
        #expect(rows[0].key == "task.custom-1.title")
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: "任务新名")
        try repo.save()
        rows = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows[0].summaryText == "我改的")
        #expect(rows[0].sourceType == "user")

        try repo.softDelete(profileId: "p1", id: id)
        try repo.save()
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: "复活？")
        try repo.save()
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)
    }

    @Test func softDeleteTaskGoalOnlyRemovesLiveTaskSourcedRow() throws {
        let repo = try makeRepo()
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: "A")
        try repo.upsertTaskGoal(profileId: "p2", taskId: "custom-2", title: "B")
        try repo.save()
        try repo.softDeleteTaskGoal(profileId: "p1", taskId: "custom-1")
        try repo.save()
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)
        #expect(try repo.fetch(profileId: "p2", scopes: [.goal], matching: "", now: Date()).map(\.summaryText) == ["B"])

        try repo.upsertTaskGoal(profileId: "p2", taskId: "custom-2", title: "B")
        try repo.save()
        let id = try repo.fetch(profileId: "p2", scopes: [.goal], matching: "", now: Date())[0].id
        try repo.updateSummary(profileId: "p2", id: id, summaryText: "用户留着")
        try repo.save()
        try repo.softDeleteTaskGoal(profileId: "p2", taskId: "custom-2")
        try repo.save()
        #expect(try repo.fetch(profileId: "p2", scopes: [.goal], matching: "", now: Date()).map(\.summaryText) == ["用户留着"])
    }
}
