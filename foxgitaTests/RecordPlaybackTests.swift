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
}
