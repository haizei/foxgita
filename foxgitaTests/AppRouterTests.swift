import Foundation
import Testing
@testable import foxgita

struct AppRouterTests {
    @Test func clearJustCompletedDropsPracticeItemId() {
        let router = AppRouter()
        router.lastCompletedPracticeItemId = UUID()
        router.clearJustCompleted()
        #expect(router.lastCompletedPracticeItemId == nil)
    }

    @Test func practiceDetailRouteCarriesItemId() {
        let itemId = UUID()
        let route = PracticeRoute.detail(itemId: itemId)
        #expect(route == .detail(itemId: itemId))

        var path: [PracticeRoute] = []
        path.append(.detail(itemId: itemId))
        #expect(path == [.detail(itemId: itemId)])
    }

    @Test func homeNavigatesByPracticeItemId() {
        let homeItemId = UUID()
        let route = PracticeDetailState.practiceRoute(itemId: homeItemId)
        #expect(route == .detail(itemId: homeItemId))
    }

    @Test func invalidRecommendSelectionDoesNotNavigate() {
        #expect(PracticeDetailState.practiceRoute(fromSheetSelection: "custom-not-a-uuid") == nil)
        #expect(PracticeDetailState.practiceRoute(fromSheetSelection: "not-a-uuid") == nil)

        let itemId = UUID()
        #expect(
            PracticeDetailState.practiceRoute(fromSheetSelection: itemId.uuidString)
                == .detail(itemId: itemId)
        )
    }

    @Test func mainTabHasNoHistoryCase() {
        let tabs: [MainTab] = [.practice, .record, .settings]
        #expect(tabs.count == 3)
    }

    @Test func recordPracticeDetailCarriesItemId() {
        let id = UUID()
        let route = RecordRoute.practiceDetail(itemId: id)
        #expect(route == .practiceDetail(itemId: id))
    }

    @Test func deeplinkWithDayOpensCalendarOnRecord() {
        let router = AppRouter()
        router.openRecord(dayKey: "2026-08-25")
        #expect(router.selectedTab == .record)
        #expect(router.recordPath == [.history(.calendar)])
        #expect(router.recordFocusDayKey == "2026-08-25")
    }

    @Test func deeplinkWithoutDayOpensRecordHome() {
        let router = AppRouter()
        router.recordPath = [.history(.stats)]
        router.openRecord(dayKey: nil)
        #expect(router.selectedTab == .record)
        #expect(router.recordPath.isEmpty)
        #expect(router.recordFocusDayKey == nil)
    }

    @Test func dismissPracticeDetailPopsRecordPathAndLeavesPracticePath() {
        let router = AppRouter()
        let itemId = UUID()
        router.practicePath = [.detail(itemId: itemId)]
        router.recordPath = [.history(.calendar), .practiceDetail(itemId: itemId)]
        router.returnPracticeToToday = false

        router.dismissPracticeDetail(fromRecord: true)

        #expect(router.recordPath == [.history(.calendar)])
        #expect(router.practicePath == [.detail(itemId: itemId)])
        #expect(router.returnPracticeToToday == false)
    }

    @Test func dismissPracticeDetailClearsPracticePathWhenRecordIsEmpty() {
        let router = AppRouter()
        let itemId = UUID()
        router.practicePath = [.detail(itemId: itemId)]
        router.recordPath = []

        router.dismissPracticeDetail(fromRecord: false)

        #expect(router.practicePath.isEmpty)
        #expect(router.recordPath.isEmpty)
    }

    @Test func dismissFromPracticeHomeLeavesLeftoverRecordDetail() {
        let router = AppRouter()
        let homeId = UUID()
        let leftoverId = UUID()
        router.practicePath = [.detail(itemId: homeId)]
        router.recordPath = [.practiceDetail(itemId: leftoverId)]

        router.dismissPracticeDetail(fromRecord: false)

        #expect(router.practicePath.isEmpty)
        #expect(router.recordPath == [.practiceDetail(itemId: leftoverId)])
    }

    @Test func recordRouteCarriesProjectPages() {
        let id = UUID()
        let itemId = UUID()
        #expect(RecordRoute.projectCreate == .projectCreate)
        #expect(RecordRoute.projectCreateFromPractice(itemId: itemId) == .projectCreateFromPractice(itemId: itemId))
        var path: [RecordRoute] = [
            .projectCreate,
            .projectDetail(projectId: id),
            .projectEdit(projectId: id),
        ]
        path.append(.practiceDetail(itemId: id))
        #expect(path.last == .practiceDetail(itemId: id))
        path.append(.projectTrajectory(projectId: id))
        #expect(path.last == .projectTrajectory(projectId: id))
    }

    @Test func projectCreateStartIgnoresWhenAlreadyOnCreate() {
        #expect(RecordProjectCreateStart.shouldPush(onto: nil))
        #expect(RecordProjectCreateStart.shouldPush(onto: .projectDetail(projectId: UUID())))
        #expect(RecordProjectCreateStart.shouldPush(onto: .projectCreate) == false)
        #expect(RecordProjectCreateStart.shouldPush(onto: .projectCreateFromPractice(itemId: UUID())) == false)
    }

    @Test func replaceLastRecordRouteReplacesTop() {
        let router = AppRouter()
        let id = UUID()
        router.recordPath = [.projectCreate]
        router.replaceLastRecordRoute(.projectDetail(projectId: id))
        #expect(router.recordPath == [.projectDetail(projectId: id)])
    }

    @Test func presentCreatedProjectReplacesCreateOnRecordStack() {
        let router = AppRouter()
        let id = UUID()
        router.recordPath = [.projectCreate]
        router.presentCreatedProject(id, fromPracticeTab: false)
        #expect(router.recordSegment == .project)
        #expect(router.recordPath == [.projectDetail(projectId: id)])
        #expect(router.projectCreatedToast)
    }

    @Test func presentCreatedProjectFromPracticeTabSwitchesTab() {
        let router = AppRouter()
        let id = UUID()
        let itemId = UUID()
        router.selectedTab = .practice
        router.practicePath = [.detail(itemId: itemId)]
        router.presentCreatedProject(id, fromPracticeTab: true)
        #expect(router.selectedTab == .record)
        #expect(router.recordSegment == .project)
        #expect(router.recordPath == [.projectDetail(projectId: id)])
        #expect(router.practicePath.isEmpty)
        #expect(router.projectCreatedToast)
    }

    @Test func dismissFromRecordLeavesPracticeHomeWhenOpenedFromRecordIsFalse() {
        let router = AppRouter()
        let itemId = UUID()
        router.recordPath = [.practiceDetail(itemId: itemId)]
        router.practicePath = [.detail(itemId: itemId)]
        router.dismissPracticeDetail(fromRecord: false)
        #expect(router.practicePath.isEmpty)
        #expect(router.recordPath == [.practiceDetail(itemId: itemId)])
    }
}
