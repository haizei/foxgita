import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct ScoreTimelineTests {
    @Test func indexedPositionMatchesMeterAndTempoChangesAtBoundaries() throws {
        var score = ScoreExercises.melody
        score.bars[2].numerator = 6; score.bars[2].denominator = 8
        score.bars[2].events = []
        score.bars[3].tempo = .init(bpm: 96,beatUnit: 8)
        score.bars[5].tempo = .init(bpm: 72,beatUnit: 2)
        let index = ScoreTimeline(score: score)
        for bar in 0...score.bars.count {
            let tick = score.startTick(ofBar: bar)
            #expect(index.startTick(ofBar: bar) == tick)
            #expect(index.barIndex(atTick: tick) == score.barIndex(atTick: tick))
            for speed in [0.25,0.75,1.0,1.5] {
                let seconds = try score.seconds(atTick: tick,speed: speed)
                #expect(abs(index.seconds(atTick: tick)/speed-seconds) < 0.000001)
                #expect(abs(index.tick(atSeconds: seconds*speed)-tick) <= 1)
            }
        }
    }
    @Test func visualProjectionMovesBetweenTransportPollsAndStopsWhenPaused() throws {
        var run = try ScoreRun(score: ScoreExercises.melody,range: ScoreExercises.melody.fullRange,speed: 1)
        run.start(countIn: false)
        let moving = ScorePlaybackProjection(run: run,uptime: 100)
        #expect(moving.tick(at: 100.016) > moving.tick(at: 100))
        #expect(moving.tick(at: 100.032) > moving.tick(at: 100.016))
        run.pause()
        let paused = ScorePlaybackProjection(run: run,uptime: 100)
        #expect(paused.tick(at: 100.1) == run.tick)
        #expect(moving.tick(at: 99) == run.tick)
    }
}
