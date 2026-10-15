import Testing
@testable import foxgita

struct RecordPlaybackTests {
    @Test func pauseSameIdIsNotFailure() {
        #expect(
            RecordPlayback.startFailed(
                playingIdBefore: "clip-1",
                intendedId: "clip-1",
                playingIdAfter: nil
            ) == false
        )
    }

    @Test func startFailsWhenPlayingIdIsNotIntended() {
        #expect(
            RecordPlayback.startFailed(
                playingIdBefore: nil,
                intendedId: "clip-1",
                playingIdAfter: nil
            )
        )
        #expect(
            RecordPlayback.startFailed(
                playingIdBefore: "other",
                intendedId: "clip-1",
                playingIdAfter: nil
            )
        )
    }

    @Test func startSucceedsWhenPlayingIdMatches() {
        #expect(
            RecordPlayback.startFailed(
                playingIdBefore: nil,
                intendedId: "clip-1",
                playingIdAfter: "clip-1"
            ) == false
        )
        #expect(
            RecordPlayback.startFailed(
                playingIdBefore: "other",
                intendedId: "clip-1",
                playingIdAfter: "clip-1"
            ) == false
        )
    }

    @Test func comparisonPlaybackIsExclusiveAndAlternatesAtTheSameProgress() {
        var playback = AudioComparisonPlayback()
        playback.play(.a)
        playback.play(.b)
        #expect(playback.playing == .b)

        playback.positionA = 10
        playback.positionB = 0
        playback.play(.a)
        playback.alternate(durationA: 120, durationB: 60)
        #expect(playback.playing == .b)
        #expect(playback.positionB == 10)

        playback.positionA = 90
        playback.play(.a)
        playback.alternate(durationA: 120, durationB: 60)
        #expect(playback.playing == .b)
        #expect(playback.positionB == 45)

        var cold = AudioComparisonPlayback(playing: .a, positionA: 12, positionB: 0)
        cold.alternate(durationA: 0, durationB: 40)
        #expect(cold.playing == .b)
        #expect(cold.positionB == 0)
    }

    @Test func waveformHighlightFollowsProgressAcrossTwentyTwoBars() {
        #expect(WaveformProgress.evidenceBarCount == 22)
        #expect(WaveformProgress.comparisonBarCount == 32)
        #expect(WaveformProgress.highlightCount(progress: 0, barCount: 22) == 0)
        #expect(WaveformProgress.highlightCount(progress: 0.5, barCount: 22) == 11)
        #expect(WaveformProgress.highlightCount(progress: 1, barCount: 22) == 22)
        #expect(WaveformProgress.highlightCount(progress: 1, barCount: 32) == 32)
    }
}
