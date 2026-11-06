import Foundation
import Testing
@testable import foxgita

@MainActor struct OriginalScorePracticeIntegrationTests {
    private var document: OriginalScoreDocument {
        .init(title: "原谱", pageCount: 1, rows: [
            .init(page: 0, box: .init(x: 0, y: 0, width: 1, height: 0.2), beats: 4)
        ])
    }

    @Test func dailyPracticeIsReusedAndElapsedCommitRemainsIdempotent() throws {
        let store = PracticeStore(repository: InMemoryPracticeRepository(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.prepare()
        let score = document, now = Date()
        let first = try store.openOriginalScorePractice(document: score, bpm: 80, preferred: nil, completed: [], now: now, calendar: .current)
        let again = try store.openOriginalScorePractice(document: score, bpm: 80, preferred: nil, completed: [], now: now, calendar: .current)
        #expect(first.id == again.id)
        try store.savePracticeItem(id: first.id, durationSeconds: 15, note: "保留笔记", now: now, metronomeVolume: 63)
        try store.commitScoreElapsed(itemID: first.id, expectedDayKey: first.practiceDayKey, absoluteSeconds: 22, now: now)
        try store.commitScoreElapsed(itemID: first.id, expectedDayKey: first.practiceDayKey, absoluteSeconds: 22, now: now)
        #expect(first.durationSeconds == 22)
        #expect(first.note == "保留笔记")
        #expect(first.metronomeVolume == 63)
    }

    @Test func historicalAndCompletedPreferencesDoNotWriteToTheOldItem() throws {
        let store = PracticeStore(repository: InMemoryPracticeRepository(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.prepare()
        let score = document, now = Date()
        let yesterday = try store.openOriginalScorePractice(document: score, bpm: 80, preferred: nil, completed: [],
            now: now.addingTimeInterval(-86_400), calendar: .current)
        let today = try store.openOriginalScorePractice(document: score, bpm: 80, preferred: yesterday.id, completed: [], now: now, calendar: .current)
        #expect(today.id != yesterday.id)
        let next = try store.openOriginalScorePractice(document: score, bpm: 80, preferred: today.id, completed: [today.id], now: now, calendar: .current)
        #expect(next.id != today.id)
        #expect(yesterday.durationSeconds == 0)
    }
}
