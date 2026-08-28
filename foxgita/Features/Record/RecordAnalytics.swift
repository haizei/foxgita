enum RecordAnalytics {
    static var sink: ((String, [String: String]) -> Void)?

    static func viewOpened(segment: String, entry: String) {
        sink?("record_view_opened", ["segment": segment, "entry": entry])
    }

    static func dateSelected(date: String, source: String) {
        sink?("record_date_selected", ["date": date, "source": source])
    }

    static func statsOpened(granularity: String) {
        sink?("record_stats_opened", ["granularity": granularity])
    }

    static func practiceOpened(itemId: String, practiceDay: String, isToday: Bool) {
        sink?(
            "record_practice_opened",
            ["practice_item_id": itemId, "practice_day": practiceDay, "is_today": isToday ? "true" : "false"]
        )
    }
}
