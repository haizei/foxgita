import Foundation
import Testing
@testable import foxgita

struct PracticeResumeSkipStoreTests {
    @Test func skipRoundTripAndClear() {
        let suiteName = "PracticeResumeSkipStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(PracticeResumeSkipStore.skippedSessionId(taskId: "t1", defaults: defaults) == nil)
        PracticeResumeSkipStore.skip(taskId: "t1", sessionId: "s1", defaults: defaults)
        #expect(PracticeResumeSkipStore.skippedSessionId(taskId: "t1", defaults: defaults) == "s1")
        PracticeResumeSkipStore.clear(taskId: "t1", defaults: defaults)
        #expect(PracticeResumeSkipStore.skippedSessionId(taskId: "t1", defaults: defaults) == nil)
    }

    @Test func tasksAreIsolated() {
        let suiteName = "PracticeResumeSkipStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        PracticeResumeSkipStore.skip(taskId: "a", sessionId: "sa", defaults: defaults)
        PracticeResumeSkipStore.skip(taskId: "b", sessionId: "sb", defaults: defaults)
        #expect(PracticeResumeSkipStore.skippedSessionId(taskId: "a", defaults: defaults) == "sa")
        #expect(PracticeResumeSkipStore.skippedSessionId(taskId: "b", defaults: defaults) == "sb")
    }
}
