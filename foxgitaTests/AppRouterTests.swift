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
}
