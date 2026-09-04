import Foundation
import Testing
@testable import foxgita

struct AIInvocationLogPresentationTests {
    @Test func mapsSuccessWithoutErrorAndEmptyOutcome() {
        let log = AIInvocationLog(
            id: "1", profileId: "p", skillId: SkillID.nextSession,
            skillVersion: "1.0.0", model: "gpt-4o",
            startedAt: Date(), durationMs: 12, statusRaw: "success"
        )
        let row = AIInvocationLogPresentation.row(log)
        #expect(row.skillTitle == "下次练习安排")
        #expect(row.statusText == "成功")
        #expect(row.errorText == nil)
        #expect(row.outcomeText == "仅调用")
        #expect(row.completedText == "未完成")
        #expect(!row.skillTitle.contains("Skill"))
        #expect(!AIInvocationStore.debugBlob(of: log).contains("BACKGROUND_MEMORY"))
    }

    @Test func mapsFailureAndAcceptedComplete() {
        let log = AIInvocationLog(
            id: "2", profileId: "p", skillId: SkillID.planFromImage,
            skillVersion: "1.1.0", model: "gpt-4o",
            startedAt: Date(), durationMs: 9, statusRaw: "failure",
            errorTypeRaw: "invalidJSON", draftOutcomeRaw: "accepted",
            taskId: "x", completedAt: Date()
        )
        let row = AIInvocationLogPresentation.row(log)
        #expect(row.skillTitle == "图片转练习")
        #expect(row.statusText == "失败")
        #expect(row.errorText == "invalidJSON")
        #expect(row.outcomeText == "已接受")
        #expect(row.completedText == "已完成")
    }
}
