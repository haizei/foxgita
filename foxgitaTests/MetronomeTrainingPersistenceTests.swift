import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct MetronomeTrainingPersistenceTests {
    @Test func deletingPracticeItemTrainingDataRemovesPlanAndSessions() throws {
        let schema = Schema(versionedSchema: GitaSchemaV18.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let practiceItemId = UUID()
        let settings = TempoRampSettings(startBPM: 80, targetBPM: 100)
        container.mainContext.insert(
            TempoRampPlan(
                practiceItemId: practiceItemId, settings: settings,
                meterRaw: "4/4", subdivisionRaw: 1, accentPatternRaw: "3111"
            )
        )
        container.mainContext.insert(
            MetronomeTrainingSession(
                practiceItemId: practiceItemId, settings: settings,
                timeSignature: "4/4", accentPatternRaw: "3111", subdivisionRaw: 1
            )
        )
        try container.mainContext.save()

        let repository = SwiftDataPracticeRepository(context: container.mainContext)
        try repository.deleteMetronomeTrainingData(practiceItemId: practiceItemId)
        try repository.save()

        #expect(try container.mainContext.fetch(FetchDescriptor<TempoRampPlan>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<MetronomeTrainingSession>()).isEmpty)
    }

    @Test func orphanedRunningSessionIsSettledAsInterrupted() throws {
        let schema = Schema(versionedSchema: GitaSchemaV18.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let settings = TempoRampSettings(startBPM: 80, targetBPM: 100)
        let session = MetronomeTrainingSession(
            practiceItemId: UUID(), settings: settings,
            timeSignature: "4/4", accentPatternRaw: "3111", subdivisionRaw: 1
        )
        container.mainContext.insert(session)
        try container.mainContext.save()

        let endedAt = Date(timeIntervalSince1970: 2_000_000_000)
        try MetronomeTrainingPersistence.settleOrphanedRuns(
            in: container.mainContext, now: endedAt
        )

        #expect(session.state == .completed)
        #expect(session.completionReason == .interrupted)
        #expect(session.endedAt == endedAt)
    }
}
