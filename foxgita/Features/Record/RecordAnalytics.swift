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

    static func projectViewOpened(projectId: String, hasEvidence: Bool) {
        sink?("project_view_opened", ["project_id": projectId, "has_evidence": hasEvidence ? "true" : "false"])
    }

    static func projectPracticeCreateTapped(projectId: String) {
        sink?("project_practice_create_tapped", ["project_id": projectId])
    }

    static func projectPracticeCreated(projectId: String, practiceItemId: String, result: String) {
        sink?("project_practice_created", [
            "project_id": projectId,
            "practice_item_id": practiceItemId,
            "result": result,
        ])
    }

    static func practiceProjectChanged(fromProjectId: String, toProjectId: String) {
        sink?("practice_project_changed", [
            "from_project_id": fromProjectId,
            "to_project_id": toProjectId,
        ])
    }
}
