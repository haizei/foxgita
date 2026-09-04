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
        RecordAnalytics.projectCreateEntryViewed(source: "projects_empty")
        RecordAnalytics.projectCreateStarted(source: "projects_empty")
        RecordAnalytics.projectGoalExpanded(source: "projects_empty")
        RecordAnalytics.projectCreateSubmitted(source: "projects_empty", hasGoal: false)
        RecordAnalytics.projectCreated(source: "projects_empty", hasGoal: true, durationMs: 1200)
        RecordAnalytics.projectCreatedFromPractice(linkResult: "linked", hadPreviousProject: false)
        RecordAnalytics.projectCreateFailed(source: "practice_detail", errorCode: "save_failed")
        RecordAnalytics.projectSetupAbandoned(source: "projects_list", durationMs: 800)
        RecordAnalytics.projectDetailFirstPracticeClicked(projectId: "p1")
        RecordAnalytics.projectFirstPracticeCreated(
            projectId: "p1",
            practiceItemId: "i1",
            elapsedFromProjectCreation: 400
        )
        #expect(captured.map(\.0) == [
            "project_empty_viewed",
            "project_create_entry_viewed",
            "project_create_started",
            "project_goal_expanded",
            "project_create_submitted",
            "project_created",
            "project_created_from_practice",
            "project_create_failed",
            "project_setup_abandoned",
            "project_detail_first_practice_clicked",
            "project_first_practice_created",
        ])
        #expect(captured[5].1 == [
            "source": "projects_empty",
            "has_goal": "true",
            "duration_ms": "1200",
        ])
        #expect(captured[6].1 == [
            "link_result": "linked",
            "had_previous_project": "false",
        ])
        #expect(captured.allSatisfy { event in
            event.1.values.allSatisfy { !$0.contains("知足") && !$0.contains("副歌") }
        })
    }
}
