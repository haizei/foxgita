import Testing
@testable import foxgita

struct VideoFrameSamplerTests {
    @Test func shortClipStillHasThreeAnchors() {
        let times = VideoFrameSampler.sampleSeconds(duration: 12)
        #expect(times.count >= 3)
        #expect(times.first == 0)
        #expect(times.contains { abs($0 - 6) < 0.01 })
        #expect(times.contains(8))
    }

    @Test func longClipCapsAtTenAndIncludesInterval() {
        let times = VideoFrameSampler.sampleSeconds(duration: 480)
        #expect(times.count == 10)
        #expect(times.contains(8))
        #expect(times.first == 0)
        #expect(times.last! > 400)
    }

    @Test func zeroDurationReturnsZero() {
        #expect(VideoFrameSampler.sampleSeconds(duration: 0) == [0])
    }
}
