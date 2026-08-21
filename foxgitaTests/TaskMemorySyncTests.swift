import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct TaskMemorySyncTests {
    private func make() throws -> (TaskMemorySync, SwiftDataMemoryRepository, ModelContext, LocalProfile) {
        let schema = Schema(versionedSchema: GitaSchemaV7.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        profile.consent = .enabled
        context.insert(profile)
        try context.save()
        let repo = SwiftDataMemoryRepository(context: context)
        return (TaskMemorySync(repository: repo, context: context), repo, context, profile)
    }

    private func customTask(
        id: String = "custom-1",
        title: String = "练晴天",
        profileId: String = "p1",
        deleted: Bool = false
    ) -> TaskItem {
        let task = TaskItem(
            id: id, title: title, subtitle: "",
            category: .chord, targetMin: 10, profileId: profileId
        )
        if deleted { task.deletedAt = Date() }
        return task
    }

    @Test func syncUpsertNoopsWhenDisabledOrNotCustom() throws {
        let (sync, repo, _, profile) = try make()
        profile.consent = .disabled
        sync.syncUpsert(task: customTask())
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)

        profile.consent = .enabled
        let template = TaskItem(
            id: "tpl-1", title: "模板", subtitle: "",
            category: .chord, targetMin: 8, isTemplate: true, profileId: "p1"
        )
        sync.syncUpsert(task: template)
        let daily = TaskItem(
            id: "active-tpl-1-20260821", title: "每日激活", subtitle: "",
            category: .chord, targetMin: 8, profileId: "p1"
        )
        sync.syncUpsert(task: daily)
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)
    }

    @Test func syncUpsertWritesCustomTaskWhenEnabled() throws {
        let (sync, repo, _, _) = try make()
        sync.syncUpsert(task: customTask())
        let rows = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows.map(\.summaryText) == ["练晴天"])
        #expect(rows[0].key == "task.custom-1.title")
        #expect(sync.lastError == nil)
    }

    @Test func syncDeleteRemovesTaskSourcedEvenWhenConsentDisabled() throws {
        let (sync, repo, _, profile) = try make()
        sync.syncUpsert(task: customTask())
        profile.consent = .disabled
        sync.syncDelete(taskId: "custom-1", profileId: "p1")
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)
    }

    @Test func backfillFillsGapsAndSkipsTombstonesAndOtherProfiles() throws {
        let (sync, repo, context, profile) = try make()
        let p2 = LocalProfile(id: "p2", isActive: false)
        p2.consent = .enabled
        context.insert(p2)
        context.insert(customTask(id: "custom-old", title: "旧任务"))
        context.insert(customTask(id: "custom-b", title: "别人的", profileId: "p2"))
        let template = TaskItem(
            id: "tpl-1", title: "模板", subtitle: "",
            category: .chord, targetMin: 8, isTemplate: true, profileId: "p1"
        )
        context.insert(template)
        try context.save()

        profile.consent = .disabled
        sync.backfill(profileId: "p1")
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)

        profile.consent = .enabled
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-gone", title: "已删")
        try repo.save()
        try repo.softDeleteTaskGoal(profileId: "p1", taskId: "custom-gone")
        try repo.save()
        context.insert(customTask(id: "custom-gone", title: "已删任务还在"))
        try context.save()

        sync.backfill(profileId: "p1")
        let mine = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(Set(mine.map(\.summaryText)) == ["旧任务"])
        #expect(try repo.fetch(profileId: "p2", scopes: [.goal], matching: "", now: Date()).isEmpty)
    }
}
