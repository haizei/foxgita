import Testing
@testable import foxgita

struct AppRouterTests {
    @Test func clearJustCompletedDropsSessionId() {
        let router = AppRouter()
        router.lastCompletedSessionId = "s1"
        router.clearJustCompleted()
        #expect(router.lastCompletedSessionId == nil)
    }
}
