#if DEBUG
import Foundation

/// Test data is only installed with -UITesting in an in-memory store.
@MainActor
enum PracticeHistoryUITestFixture {
    static func seedIfRequested(store: PracticeStore) throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITesting"), arguments.contains("-PracticeHistoryFixture") else { return }
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let previousMonday = calendar.date(byAdding: .day, value: -7, to: StatsAggregator.week(containing: now).start)!
        func create(_ title: String, at date: Date, seconds: Int = 0, note: String = "", origin: String? = nil) throws {
            let item = try store.createPracticeItem(input: PracticeItemInput(
                title: title, category: .chord, source: .custom, originId: origin,
                bpm: nil, timeSignature: nil, targetMin: 10
            ), now: date, calendar: calendar)
            if seconds > 0 || !note.isEmpty {
                try store.savePracticeItem(id: item.id, durationSeconds: seconds, note: note, now: date)
            }
        }
        try create("今日日常计划", at: now)
        if arguments.contains("-PracticeHistoryLongList") {
            for index in 1...8 { try create("今日长列表练习 \(index)", at: now) }
        }
        try create("昨日日常练习", at: yesterday, seconds: 600, note: "日常历史笔记")
        try create("昨天方案分段", at: yesterday, seconds: 90, note: "方案历史笔记", origin: "program.routine.fixture.stage.history")
        try create("昨天未开始计划", at: yesterday)
        try create("上周一练习", at: previousMonday, seconds: 180)
    }
}
#endif
