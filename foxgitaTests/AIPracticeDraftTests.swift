import Testing
@testable import foxgita

struct AIPracticeDraftTests {
    @Test func normalizeHappyPath() {
        let raw = AIPracticeDraft.Raw(
            title: "  F 和弦  ",
            category: "chord",
            targetMin: 15,
            steps: ["慢速", "加速", ""]
        )
        let draft = AIPracticeDraft.normalize(raw, fallbackCategory: .left)
        #expect(draft.title == "F 和弦")
        #expect(draft.category == .chord)
        #expect(draft.targetMin == 15)
        #expect(draft.steps == ["慢速", "加速"])
    }

    @Test func normalizeFallsBackCategoryAndClampsMinutes() {
        let raw = AIPracticeDraft.Raw(
            title: "   ",
            category: "nope",
            targetMin: 999,
            steps: nil
        )
        let draft = AIPracticeDraft.normalize(raw, fallbackCategory: .rhythm)
        #expect(draft.title == "未命名练习")
        #expect(draft.category == .rhythm)
        #expect(draft.targetMin == 60)
        #expect(draft.steps == ["新步骤"])
    }

    @Test func normalizeDefaultsMissingMinutesAndCapsSteps() {
        let many = (1...20).map { "步骤\($0)" }
        let raw = AIPracticeDraft.Raw(
            title: "音阶",
            category: "scale",
            targetMin: nil,
            steps: many
        )
        let draft = AIPracticeDraft.normalize(raw, fallbackCategory: .left)
        #expect(draft.targetMin == 10)
        #expect(draft.steps.count == 12)
        #expect(draft.steps.first == "步骤1")
        #expect(draft.steps.last == "步骤12")
    }
}
