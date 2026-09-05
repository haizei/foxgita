import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct PracticeStoreInvocationTests {
    private func makeStores() throws -> (PracticeStore, AIInvocationStore) {
        let schema = Schema(versionedSchema: GitaSchemaV14.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile()
        profile.isActive = true
        context.insert(profile)
        try context.save()
        let invocationStore = AIInvocationStore(context: context)
        let store = PracticeStore(
            repository: SwiftDataPracticeRepository(context: context),
            invocationStore: invocationStore
        )
        return (store, invocationStore)
    }

    @Test func savePracticeItemMarksInvocationCompleteOnce() throws {
        let (store, invocationStore) = try makeStores()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let item = try store.createPracticeItem(
            input: PracticeItemInput(
                title: "开放弦",
                category: .left,
                source: .custom,
                originId: nil,
                bpm: nil,
                timeSignature: nil
            ),
            now: now,
            calendar: calendar
        )
        invocationStore.record(
            AIInvocationRecordInput(
                id: "inv-1",
                skillId: SkillID.nextSession,
                skillVersion: SkillDefinition.nextSession.version,
                model: "gpt-4o",
                startedAt: now,
                durationMs: 42,
                status: .success,
                errorType: nil,
                memoryIds: ["m1"],
                formatRetryUsed: false,
                draftOutcome: nil
            )
        )
        invocationStore.setDraftOutcome(
            id: "inv-1",
            outcome: .accepted,
            taskId: item.id.uuidString
        )

        try store.savePracticeItem(id: item.id, durationSeconds: 0, note: "", now: now)
        #expect(invocationStore.recent().first?.completedAt == nil)
        try store.savePracticeItem(id: item.id, durationSeconds: 60, note: "", now: now)
        let first = try #require(invocationStore.recent().first?.completedAt)
        try store.savePracticeItem(id: item.id, durationSeconds: 90, note: "", now: now.addingTimeInterval(60))
        #expect(invocationStore.recent().first?.completedAt == first)
    }
}
