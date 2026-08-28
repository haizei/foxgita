import Testing
@testable import foxgita

struct RecordAnalyticsTests {
    @Test func viewOpenedEmitsSegmentAndEntry() {
        var captured: [(String, [String: String])] = []
        RecordAnalytics.sink = { captured.append(($0, $1)) }
        defer { RecordAnalytics.sink = nil }
        RecordAnalytics.viewOpened(segment: "practice", entry: "tab")
        #expect(captured.count == 1)
        #expect(captured[0].0 == "record_view_opened")
        #expect(captured[0].1 == ["segment": "practice", "entry": "tab"])
    }

    @Test func dateSelectedAndPracticeOpenedIncludeSpecKeys() {
        var captured: [(String, [String: String])] = []
        RecordAnalytics.sink = { captured.append(($0, $1)) }
        defer { RecordAnalytics.sink = nil }
        RecordAnalytics.dateSelected(date: "2026-08-25", source: "calendar")
        RecordAnalytics.statsOpened(granularity: "week")
        RecordAnalytics.practiceOpened(itemId: "id-1", practiceDay: "2026-08-25", isToday: false)
        #expect(captured.map(\.0) == [
            "record_date_selected",
            "record_stats_opened",
            "record_practice_opened",
        ])
        #expect(captured[2].1["is_today"] == "false")
    }
}
