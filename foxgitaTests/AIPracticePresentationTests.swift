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
}
