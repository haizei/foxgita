import Testing
@testable import foxgita

struct JustCompletedCopyTests {
    @Test func minutesFromDuration() {
        #expect(JustCompletedCopy.minutesLabel(durationSec: 60, hasNote: false, mediaCount: 0) == "1 分钟")
        #expect(JustCompletedCopy.minutesLabel(durationSec: 61, hasNote: false, mediaCount: 0) == "2 分钟")
        #expect(JustCompletedCopy.minutesLabel(durationSec: 0, hasNote: true, mediaCount: 0) == "不足 1 分钟")
        #expect(JustCompletedCopy.minutesLabel(durationSec: 0, hasNote: false, mediaCount: 1) == "不足 1 分钟")
    }

    @Test func summaryOmitsZeroKinds() {
        #expect(JustCompletedCopy.summary(hasNote: true, fileNames: ["a.m4a", "b.mov"]) == "笔记 · 录音 1 · 视频 1")
        #expect(JustCompletedCopy.summary(hasNote: false, fileNames: ["a.m4a"]) == "录音 1")
        #expect(JustCompletedCopy.summary(hasNote: true, fileNames: []) == "笔记")
        #expect(JustCompletedCopy.summary(hasNote: false, fileNames: []) == "")
    }
}
