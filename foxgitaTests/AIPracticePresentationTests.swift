import Testing
@testable import foxgita

struct AIPracticePresentationTests {
    @Test func detectsAISubtitleAndChords() {
        #expect(AIPracticePresentation.isAIGenerated(subtitle: "AI · 10 分钟 · C · G · Am · F"))
        #expect(AIPracticePresentation.chords(fromSubtitle: "AI · 10 分钟 · C · G · Am · F") == ["C", "G", "Am", "F"])
        #expect(AIPracticePresentation.isAIGenerated(subtitle: "AI · 8 分钟"))
        #expect(AIPracticePresentation.chords(fromSubtitle: "AI · 8 分钟").isEmpty)
        #expect(AIPracticePresentation.isAIGenerated(subtitle: "自定义 · 10 分钟") == false)
        #expect(AIPracticePresentation.chords(fromSubtitle: "自定义 · 10 分钟").isEmpty)
    }

    @Test func splitsStepMinutesSuffix() {
        let timed = AIPracticePresentation.stepParts("识别和弦顺序 · 2 分钟")
        #expect(timed.title == "识别和弦顺序")
        #expect(timed.minutes == 2)
        let plain = AIPracticePresentation.stepParts("慢速按弦")
        #expect(plain.title == "慢速按弦")
        #expect(plain.minutes == nil)
    }

    @Test func roundTripsEncodedDraftStrings() {
        let raw = AIPracticeDraft.Raw(
            title: "转换",
            category: "chord",
            targetMin: 10,
            steps: ["识别和弦顺序"],
            chords: ["C", "G"],
            stepMinutes: [2]
        )
        let draft = AIPracticeDraft.normalize(raw, fallbackCategory: .left)

        #expect(AIPracticePresentation.isAIGenerated(subtitle: draft.subtitleLine))
        #expect(AIPracticePresentation.chords(fromSubtitle: draft.subtitleLine) == ["C", "G"])
        let parts = AIPracticePresentation.stepParts(draft.steps[0])
        #expect(parts.title == "识别和弦顺序")
        #expect(parts.minutes == 2)
    }
}
