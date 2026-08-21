import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct MemoryStoreTests {
    private func makeStore() throws -> (MemoryStore, LocalProfile) {
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
        let store = MemoryStore(repository: repo, context: context)
        store.reload()
        return (store, profile)
    }

    @Test func addFailsWhenConsentIsNotEnabled() throws {
        let (store, _) = try makeStore()
        #expect(store.setConsent(.disabled))
        #expect(store.add(kind: .goal, summary: "练晴天") == false)
        #expect(store.lastError == .invalidInput)
        #expect(store.items.isEmpty)
    }

    @Test func addAndDeleteRoundTrip() throws {
        let (store, _) = try makeStore()
        #expect(store.add(kind: .goal, summary: "练晴天前奏"))
        #expect(store.items.map(\.summaryText) == ["练晴天前奏"])
        let id = store.items[0].id
        #expect(store.updateSummary(id: id, summary: "练间奏"))
        #expect(store.items[0].summaryText == "练间奏")
        #expect(store.delete(id: id))
        #expect(store.items.isEmpty)
    }

    @Test func enablingBackfillsExistingCustomTaskAndClearAllStaysGone() throws {
        let schema = Schema(versionedSchema: GitaSchemaV7.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        profile.consent = .disabled
        context.insert(profile)
        let task = TaskItem(
            id: "custom-old", title: "关着建的", subtitle: "",
            category: .chord, targetMin: 10, profileId: "p1"
        )
        context.insert(task)
        try context.save()
        let repo = SwiftDataMemoryRepository(context: context)
        let sync = TaskMemorySync(repository: repo, context: context)
        let store = MemoryStore(repository: repo, context: context, taskMemorySync: sync)
        store.reload()
        #expect(store.setConsent(.enabled))
        #expect(store.consent == .enabled)
        #expect(store.items.map(\.summaryText) == ["关着建的"])

        #expect(store.clearAll())
        #expect(store.items.isEmpty)
        #expect(store.setConsent(.disabled))
        #expect(store.setConsent(.enabled))
        #expect(store.items.isEmpty)
    }
}
