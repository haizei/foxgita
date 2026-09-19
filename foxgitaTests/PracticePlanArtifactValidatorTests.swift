import Testing
@testable import foxgita

struct PracticePlanArtifactValidatorTests {
    @Test func capsTargetAndDropsTrailingStepsBeyondBudget() {
        let raw = AIPracticeDraft.Raw(
            title: "今日", category: "chord", targetMin: 40,
            steps: ["热身", "重点", "收尾", "加练"], chords: nil,
            stepMinutes: [5, 10, 10, 10]
        )
        let capped = PracticePlanArtifactValidator.cap(raw, budget: 20)
        #expect(capped.targetMin == 20)
        #expect(capped.steps == ["热身", "重点"])
        #expect(capped.stepMinutes == [5, 10])
    }

    @Test func clampsTargetWhenStepMinutesAreAbsent() {
        let raw = AIPracticeDraft.Raw(
            title: "今日", category: "chord", targetMin: 40,
            steps: ["A", "B"], chords: nil, stepMinutes: nil
        )
        let capped = PracticePlanArtifactValidator.cap(raw, budget: 15)
        #expect(capped.targetMin == 15)
        #expect(capped.steps == ["A", "B"])
        #expect(capped.stepMinutes == nil)
    }

    @Test func dropsBlankAndNonPositiveSteps() {
        let raw = AIPracticeDraft.Raw(
            title: "今日", category: "left", targetMin: 20,
            steps: [" ", "有效", "零分钟"], chords: nil,
            stepMinutes: [5, 8, 0]
        )
        let capped = PracticePlanArtifactValidator.cap(raw, budget: 20)
        #expect(capped.steps == ["有效"])
        #expect(capped.stepMinutes == [8])
    }
}
