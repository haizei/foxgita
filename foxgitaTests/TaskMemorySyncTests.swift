import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct TaskMemorySyncTests {
    private func make() throws -> (TaskMemorySync, SwiftDataMemoryRepository, ModelContext, LocalProfile) {
        let schema = Schema(versionedSchema: GitaSchemaV14.self)
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

    @MainActor
    private final class BackfillUpsertStub: MemoryRepository {
        private(set) var upsertedTitles: [String] = []
        private(set) var saveCallCount = 0

        func fetch(
            profileId: String,
            scopes: [MemoryScope],
            matching query: String,
            now: Date
        ) throws -> [MemoryItem] { [] }

        func upsertDebug(_ item: MemoryItem) throws {}

        func save() throws { saveCallCount += 1 }

        func upsertUser(
            profileId: String, kind: MemoryScope, summaryText: String
        ) throws -> MemoryItem {
            MemoryItem(
                profileId: profileId, kind: kind, key: "stub", summaryText: summaryText,
                sourceType: "stub", sourceId: "stub", confidence: 1, importance: 0.5
            )
        }

        func updateSummary(profileId: String, id: String, summaryText: String) throws {}

        func softDelete(profileId: String, id: String) throws {}

        func softDeleteAll(profileId: String) throws {}

        func setConsent(profileId: String, _ state: MemoryConsentState) throws {}

        func upsertTaskGoal(profileId: String, taskId: String, title: String) throws {
            if taskId == "custom-a" { throw StoreError.saveFailed }
            upsertedTitles.append(title)
        }

        func softDeleteTaskGoal(profileId: String, taskId: String) throws {}

        func upsertAICandidate(
            profileId: String, recordingId: String, summaryText: String, valueJSON: String
        ) throws {}

        func upsertDurationPreference(profileId: String, minutes: Int) throws {}
    }

    @Test func backfillContinuesAfterNonInputUpsertError() throws {
        let schema = Schema(versionedSchema: GitaSchemaV14.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        profile.consent = .enabled
        context.insert(profile)
        context.insert(customTask(id: "custom-a", title: "A"))
        context.insert(customTask(id: "custom-b", title: "B"))
        context.insert(customTask(id: "custom-c", title: "C"))
        try context.save()

        let stub = BackfillUpsertStub()
        let sync = TaskMemorySync(repository: stub, context: context)
        sync.backfill(profileId: "p1")

        #expect(sync.lastError == .saveFailed)
        #expect(Set(stub.upsertedTitles) == ["B", "C"])
        #expect(stub.saveCallCount == 1)
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

    private func makeWired(consent: MemoryConsentState = .enabled) throws -> (
        PracticeStore, MemoryStore, SwiftDataMemoryRepository, LocalProfile
    ) {
        let schema = Schema(versionedSchema: GitaSchemaV14.self)
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
        let sync = TaskMemorySync(repository: memoryRepo, context: context)
        let defaults = UserDefaults(suiteName: "foxgita.tests.\(UUID().uuidString)")!
        defaults.set(true, forKey: SeedData.seededKey)
        let store = PracticeStore(
            repository: SwiftDataPracticeRepository(context: context),
            defaults: defaults,
            taskMemorySync: sync
        )
        let memoryStore = MemoryStore(
            repository: memoryRepo, context: context, taskMemorySync: sync
        )
        memoryStore.reload()
        return (store, memoryStore, memoryRepo, profile)
    }

    @Test func practiceStoreWritesGoalOnlyWhenEnabled() throws {
        let (store, _, repo, profile) = try makeWired(consent: .disabled)
        let id = store.createCustomTask(name: "关着建的", minutes: 10, category: .chord)
        #expect(id != nil)
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)

        profile.consent = .enabled
        let (onStore, _, onRepo, _) = try makeWired(consent: .enabled)
        let onId = onStore.createCustomTask(name: "开着建的", minutes: 10, category: .chord)!
        let rows = try onRepo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows.map(\.summaryText) == ["开着建的"])
        #expect(rows[0].key == "task.\(onId).title")
    }

    @Test func practiceStoreRenameAndDeleteFollowTaskUntilUserEdits() throws {
        let (store, memoryStore, repo, _) = try makeWired()
        let id = store.createCustomTask(name: "原名", minutes: 10, category: .chord)!
        store.updateTask(id, title: "新名", subtitle: "", minutes: 10)
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).map(\.summaryText) == ["新名"])

        memoryStore.reload()
        let memId = memoryStore.items[0].id
        #expect(memoryStore.updateSummary(id: memId, summary: "用户名"))
        store.updateTask(id, title: "任务又改了", subtitle: "", minutes: 10)
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).map(\.summaryText) == ["用户名"])

        store.softDeleteTask(id)
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).map(\.summaryText) == ["用户名"])
    }

    @Test func practiceStoreDeleteRemovesUneditedTaskGoal() throws {
        let (store, _, repo, _) = try makeWired()
        let id = store.createCustomTask(name: "要删", minutes: 10, category: .chord)!
        store.softDeleteTask(id)
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)
    }

    @Test func createFromAIDraftWritesTaskGoal() throws {
        let (store, _, repo, _) = try makeWired()
        let draft = AIPracticeDraft(
            title: "AI 草稿", category: .song, targetMin: 15,
            steps: ["慢练"], chords: []
        )
        let id = store.createFromAIDraft(draft)!
        let rows = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows[0].summaryText == "AI 草稿")
        #expect(rows[0].key == "task.\(id).title")
    }
}
