import Testing
@testable import foxgita

struct PhotoPracticeStepTests {
    @Test func parsesAndKeepsEditedStepFields() {
        var step = PhotoPracticeStep(storedText: "和弦转换：C 到 G · 10 分钟", fallbackMinutes: 5)
        #expect(step.title == "和弦转换")
        #expect(step.detail == "C 到 G")
        #expect(step.minutes == 10)
        step.detail = "慢速循环"
        step.minutes = 8
        #expect(step.storedText == "和弦转换：慢速循环 · 8 分钟")
    }

    @Test func missingStepMinutesUsesDraftBudget() {
        let draft = AIPracticeDraft(
            title: "基础练习", category: .chord, targetMin: 15,
            steps: ["指法", "转换", "扫弦"], chords: []
        )
        let steps = PhotoPracticeStep.fromDraft(draft)
        #expect(steps.map(\.minutes) == [5, 5, 5])
        #expect(PhotoPracticeStep.valid(steps))
        #expect(!PhotoPracticeStep.valid([]))
        #expect(!PhotoPracticeStep.valid([PhotoPracticeStep(title: "  ", minutes: 5)]))
    }

    @Test func missingMinutesKeepTotalWhenBudgetHasRemainder() {
        let draft = AIPracticeDraft(
            title: "基础练习", category: .chord, targetMin: 10,
            steps: ["指法", "转换", "扫弦"], chords: []
        )
        let steps = PhotoPracticeStep.fromDraft(draft)
        #expect(steps.map(\.minutes) == [4, 3, 3])
    }
}
