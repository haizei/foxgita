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

    static func projectStageVersionChanged(projectId: String, practiceItemId: String) {
        sink?("project_stage_version_changed", [
            "project_id": projectId,
            "practice_item_id": practiceItemId,
        ])
    }

    static func projectFinalVersionChanged(projectId: String, practiceItemId: String) {
        sink?("project_final_version_changed", [
            "project_id": projectId,
            "practice_item_id": practiceItemId,
        ])
    }

    static func projectEmptyViewed(source: String) {
        sink?("project_empty_viewed", ["source": source])
    }

    static func projectCreateEntryViewed(source: String) {
        sink?("project_create_entry_viewed", ["source": source])
    }

    static func projectCreateStarted(source: String) {
        sink?("project_create_started", ["source": source])
    }

    static func projectGoalExpanded(source: String) {
        sink?("project_goal_expanded", ["source": source])
    }

    static func projectCreateSubmitted(source: String, hasGoal: Bool) {
        sink?("project_create_submitted", [
            "source": source,
            "has_goal": hasGoal ? "true" : "false",
        ])
    }

    static func projectSetupValidationFailed(fieldName: String, reason: String) {
        sink?("project_setup_validation_failed", [
            "field_name": fieldName,
            "reason": reason,
        ])
    }

    static func projectCreated(source: String, hasGoal: Bool, durationMs: Int) {
        sink?("project_created", [
            "source": source,
            "has_goal": hasGoal ? "true" : "false",
            "duration_ms": String(durationMs),
        ])
    }

    static func projectCreatedFromPractice(linkResult: String, hadPreviousProject: Bool) {
        sink?("project_created_from_practice", [
            "link_result": linkResult,
            "had_previous_project": hadPreviousProject ? "true" : "false",
        ])
    }

    static func projectCreateFailed(source: String, errorCode: String) {
        sink?("project_create_failed", [
            "source": source,
            "error_code": errorCode,
        ])
    }

    static func projectSetupAbandoned(source: String, durationMs: Int) {
        sink?("project_setup_abandoned", [
            "source": source,
            "duration_ms": String(durationMs),
        ])
    }

    static func projectDetailFirstPracticeClicked(projectId: String) {
        sink?("project_detail_first_practice_clicked", ["project_id": projectId])
    }

    static func projectFirstPracticeCreated(
        projectId: String,
        practiceItemId: String,
        elapsedFromProjectCreation: Int
    ) {
        sink?("project_first_practice_created", [
            "project_id": projectId,
            "practice_item_id": practiceItemId,
            "elapsed_from_project_creation": String(elapsedFromProjectCreation),
        ])
    }
}
