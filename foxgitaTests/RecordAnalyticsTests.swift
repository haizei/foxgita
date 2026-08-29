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

    @Test func projectEventsMatchSpecKeys() {
        var captured: [(String, [String: String])] = []
        RecordAnalytics.sink = { captured.append(($0, $1)) }
        defer { RecordAnalytics.sink = nil }
        RecordAnalytics.projectViewOpened(projectId: "p1", hasEvidence: true)
        RecordAnalytics.projectPracticeCreateTapped(projectId: "p1")
        RecordAnalytics.projectPracticeCreated(projectId: "p1", practiceItemId: "i1", result: "success")
        RecordAnalytics.practiceProjectChanged(fromProjectId: "p1", toProjectId: "")
        RecordAnalytics.projectStageVersionChanged(projectId: "p1", practiceItemId: "i1")
        RecordAnalytics.projectFinalVersionChanged(projectId: "p1", practiceItemId: "")
        #expect(captured.map(\.0) == [
            "project_view_opened",
            "project_practice_create_tapped",
            "project_practice_created",
            "practice_project_changed",
            "project_stage_version_changed",
            "project_final_version_changed",
        ])
        #expect(captured[0].1["has_evidence"] == "true")
        #expect(captured[3].1["to_project_id"] == "")
        #expect(captured[4].1["practice_item_id"] == "i1")
        #expect(captured[5].1["practice_item_id"] == "")
    }

    @Test func projectInitEventsMatchSpecKeys() {
        var captured: [(String, [String: String])] = []
        RecordAnalytics.sink = { captured.append(($0, $1)) }
        defer { RecordAnalytics.sink = nil }
        RecordAnalytics.projectEmptyViewed(source: "segment")
        RecordAnalytics.projectSetupStarted(source: "empty", fromEmpty: true, hasExistingPractice: false)
        RecordAnalytics.projectSetupSubmitClicked(fromEmpty: true, hasFocus: false)
        RecordAnalytics.projectSetupValidationFailed(fieldName: "name", reason: "empty")
        RecordAnalytics.projectCreated(source: "empty", fromEmpty: true, hasFocus: false, durationMs: 1200)
        RecordAnalytics.projectSetupAbandoned(fromEmpty: true, durationMs: 800)
        RecordAnalytics.projectReadyViewed(projectId: "p1", hasFocus: false)
        RecordAnalytics.projectReadyActionClicked(action: "create_practice")
        RecordAnalytics.projectFirstPracticeCreated(
            projectId: "p1",
            practiceItemId: "i1",
            elapsedFromProjectCreation: 400
        )
        #expect(captured.map(\.0) == [
            "project_empty_viewed",
            "project_setup_started",
            "project_setup_submit_clicked",
            "project_setup_validation_failed",
            "project_created",
            "project_setup_abandoned",
            "project_ready_viewed",
            "project_ready_action_clicked",
            "project_first_practice_created",
        ])
        #expect(captured[1].1 == [
            "source": "empty",
            "from_empty": "true",
            "has_existing_practice": "false",
        ])
        #expect(captured[4].1["duration_ms"] == "1200")
        #expect(captured[4].1["has_focus"] == "false")
        #expect(captured[7].1["action"] == "create_practice")
        #expect(captured[8].1["elapsed_from_project_creation"] == "400")
        #expect(captured.allSatisfy { event in
            event.1.values.allSatisfy { !$0.contains("知足") && !$0.contains("副歌") }
        })
    }
}
