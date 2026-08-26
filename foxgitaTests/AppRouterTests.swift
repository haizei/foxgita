import Foundation
import Testing
@testable import foxgita

struct AppRouterTests {
    @Test func clearJustCompletedDropsSessionId() {
        let router = AppRouter()
        router.lastCompletedSessionId = "s1"
        router.clearJustCompleted()
        #expect(router.lastCompletedSessionId == nil)
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

    @Test func recordDetailRouteStillUsesTaskId() {
        let route = RecordRoute.detail(taskId: "legacy-task")
        #expect(route == .detail(taskId: "legacy-task"))

        var path: [RecordRoute] = []
        path.append(.detail(taskId: "warm"))
        #expect(path == [.detail(taskId: "warm")])
    }
}
