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

    static func projectSetupStarted(source: String, fromEmpty: Bool, hasExistingPractice: Bool) {
        sink?("project_setup_started", [
            "source": source,
            "from_empty": fromEmpty ? "true" : "false",
            "has_existing_practice": hasExistingPractice ? "true" : "false",
        ])
    }

    static func projectSetupSubmitClicked(fromEmpty: Bool, hasFocus: Bool) {
        sink?("project_setup_submit_clicked", [
            "from_empty": fromEmpty ? "true" : "false",
            "has_focus": hasFocus ? "true" : "false",
        ])
    }

    static func projectSetupValidationFailed(fieldName: String, reason: String) {
        sink?("project_setup_validation_failed", [
            "field_name": fieldName,
            "reason": reason,
        ])
    }

    static func projectCreated(source: String, fromEmpty: Bool, hasFocus: Bool, durationMs: Int) {
        sink?("project_created", [
            "source": source,
            "from_empty": fromEmpty ? "true" : "false",
            "has_focus": hasFocus ? "true" : "false",
            "duration_ms": String(durationMs),
        ])
    }

    static func projectSetupAbandoned(fromEmpty: Bool, durationMs: Int) {
        sink?("project_setup_abandoned", [
            "from_empty": fromEmpty ? "true" : "false",
            "duration_ms": String(durationMs),
        ])
    }

    static func projectReadyViewed(projectId: String, hasFocus: Bool) {
        sink?("project_ready_viewed", [
            "project_id": projectId,
            "has_focus": hasFocus ? "true" : "false",
        ])
    }

    static func projectReadyActionClicked(action: String) {
        sink?("project_ready_action_clicked", ["action": action])
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
