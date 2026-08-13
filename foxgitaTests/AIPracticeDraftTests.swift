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

    @Test func normalizeEncodesChordsAndStepMinutes() {
        let raw = AIPracticeDraft.Raw(
            title: "转换",
            category: "chord",
            targetMin: 10,
            steps: ["识别和弦顺序", "分段慢速转换", "完整循环练习"],
            chords: [" C ", "G", "", "Am", "F"],
            stepMinutes: [2, 4, 4, 99]
        )
        let draft = AIPracticeDraft.normalize(raw, fallbackCategory: .left)
        #expect(draft.chords == ["C", "G", "Am", "F"])
        #expect(draft.steps == [
            "识别和弦顺序 · 2 分钟",
            "分段慢速转换 · 4 分钟",
            "完整循环练习 · 4 分钟",
        ])
        #expect(draft.subtitleLine == "AI · 10 分钟 · C · G · Am · F")
    }

    @Test func normalizePairsStepMinutesByRawIndexBeforeFilteringEmptySteps() {
        let raw = AIPracticeDraft.Raw(
            title: "练习",
            category: "chord",
            targetMin: 10,
            steps: ["第一步", "", "第三步"],
            stepMinutes: [1, 2, 3]
        )
        let draft = AIPracticeDraft.normalize(raw, fallbackCategory: .left)
        #expect(draft.steps == [
            "第一步 · 1 分钟",
            "第三步 · 3 分钟",
        ])
    }

    @Test func normalizeOmitsChordsAndMinutesWhenMissing() {
        let raw = AIPracticeDraft.Raw(
            title: "音阶",
            category: "scale",
            targetMin: 8,
            steps: ["上行"],
            chords: nil,
            stepMinutes: [0, 3]
        )
        let draft = AIPracticeDraft.normalize(raw, fallbackCategory: .left)
        #expect(draft.chords.isEmpty)
        #expect(draft.steps == ["上行"])
        #expect(draft.subtitleLine == "AI · 8 分钟")
    }
}
