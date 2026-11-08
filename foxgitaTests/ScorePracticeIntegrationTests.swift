import Foundation
import Testing
@testable import foxgita

@MainActor struct ScorePracticeIntegrationTests {
    @Test func completedAndHistoricalItemsCannotHaveTheirMaterialRewritten() throws {
        let store = PracticeStore(repository: InMemoryPracticeRepository(),defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.prepare()
        let now = Date()
        let old = try store.openScorePractice(score: ScoreExercises.melody,preferredItemID: nil,completedIDs: [],now: now.addingTimeInterval(-86_400),calendar: .current,origin: "old-link")
        let today = try store.openScorePractice(score: ScoreExercises.melody,preferredItemID: nil,completedIDs: [],now: now,calendar: .current,origin: "today-link")
        #expect(throws: (any Error).self) { try store.editableScorePracticeItem(id: old.id,completedIDs: [],now: now) }
        #expect(throws: (any Error).self) { try store.editableScorePracticeItem(id: today.id,completedIDs: [today.id],now: now) }
    }
    @Test func scoreElapsedCommitIsIdempotentAndPreservesExistingNoteAndSound() throws {
        let repository = InMemoryPracticeRepository()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = PracticeStore(repository: repository, defaults: defaults)
        store.prepare()
        let now = Date(), calendar = Calendar.current
        let item = try store.openScorePractice(score: ScoreExercises.strumming, preferredItemID: nil, completedIDs: [], now: now, calendar: calendar, origin: "run-1")
        try store.savePracticeItem(id: item.id, durationSeconds: 384, note: "保留笔记", now: now, metronomeVolume: 63)
        try store.commitScoreElapsed(itemID: item.id, expectedDayKey: item.practiceDayKey, absoluteSeconds: 660, now: now)
        try store.commitScoreElapsed(itemID: item.id, expectedDayKey: item.practiceDayKey, absoluteSeconds: 660, now: now)
        #expect(item.durationSeconds == 660)
        #expect(item.note == "保留笔记")
        #expect(item.metronomeVolume == 63)
    }

    @Test func completedAndHistoricalPracticesCreateNewTodayItems() throws {
        let repository = InMemoryPracticeRepository()
        let store = PracticeStore(repository: repository, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.prepare()
        let today = Date(), yesterday = today.addingTimeInterval(-86_400)
        let old = try store.openScorePractice(score: ScoreExercises.melody, preferredItemID: nil, completedIDs: [], now: yesterday, calendar: .current, origin: "old")
        let current = try store.openScorePractice(score: ScoreExercises.melody, preferredItemID: old.id, completedIDs: [], now: today, calendar: .current, origin: "today")
        #expect(current.id != old.id)
        let another = try store.openScorePractice(score: ScoreExercises.melody, preferredItemID: current.id, completedIDs: [current.id], now: today, calendar: .current, origin: "again")
        #expect(another.id != current.id)
        let duplicate = try store.openScorePractice(score: ScoreExercises.melody, preferredItemID: nil, completedIDs: [], now: today, calendar: .current, origin: "again")
        #expect(duplicate.id == another.id)
    }

    @Test func wrongDayCommitCannotWriteToAnotherDay() throws {
        let repository = InMemoryPracticeRepository()
        let store = PracticeStore(repository: repository, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.prepare()
        let item = try store.openScorePractice(score: ScoreExercises.melody, preferredItemID: nil, completedIDs: [], now: Date(), calendar: .current, origin: "today")
        #expect(throws: (any Error).self) { try store.commitScoreElapsed(itemID: item.id, expectedDayKey: "1999-01-01", absoluteSeconds: 100, now: Date()) }
        #expect(item.durationSeconds == 0)
    }
}
