import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct ScoreRunTests {
    @Test func alteringPerformanceRangeEndsThePerformanceAttempt() throws {
        var run = try ScoreRun(score: score,range: score.fullRange,speed: 1,mode: .performance)
        try run.configure(range: .init(firstBar: 1,lastBar: 2),speed: 1,loopLimit: 1)
        #expect(run.mode == .practice)
    }
    @Test func seekingSuffixCannotCountAsACompleteLoopOrPerformance() throws {
        var run = try ScoreRun(score: score,range: score.fullRange,speed: 1,loopLimit: 1,mode: .performance)
        try run.seek(toBar: 3)
        #expect(run.mode == .practice)
        run.start(countIn: false); run.advance(by: 2)
        #expect(run.completedLoops == 0)
        #expect(run.state == .playing)
        run.advance(by: 8)
        #expect(run.completedLoops == 1)
        #expect(run.state == .finished)
        #expect(!run.isCompletePerformance)
    }
    @Test func interruptedPerformanceIsRetainedAsPartial() throws {
        var run = try ScoreRun(score: score,range: score.fullRange,speed: 1,mode: .performance)
        run.start(countIn: false); run.advance(by: 2); run.pause()
        run.start(countIn: false); run.advance(by: 6)
        #expect(run.state == .finished)
        #expect(!run.isCompletePerformance)
    }
    @Test func switchingToPerformanceResetsThePassAtOriginalSpeedWithoutLosingElapsed() throws {
        var run = try ScoreRun(score: ScoreExercises.melody,range: ScoreExercises.melody.fullRange,speed: 0.5,loopLimit: 5)
        run.start(countIn: false); run.advance(by: 2); run.pause()
        try run.changeMode(.performance)
        #expect(run.speed == 1)
        #expect(run.loopLimit == 1)
        #expect(run.positionSeconds == 0)
        #expect(run.elapsedSeconds == 2)
        run.start(countIn: false)
        #expect(throws: ScoreRunError.self) { try run.changeMode(.practice) }
    }
    private var score: ScoreDocument {
        .init(title: "循环", tempo: .init(bpm: 120), bars: (1...4).map { .init(number: $0, events: []) })
    }

    @Test func countInAndPausedTimeNeverCountAsPracticeOrCompletedLoops() throws {
        var run = try ScoreRun(score: score, range: .init(firstBar: 1, lastBar: 2), speed: 1, loopLimit: 2)
        run.start()
        run.advance(by: 2)
        #expect(run.state == .playing)
        #expect(run.elapsedSeconds == 0)
        #expect(run.completedLoops == 0)
        run.advance(by: 3)
        #expect(run.elapsedSeconds == 3)
        #expect(run.completedLoops == 0)
        run.pause()
        run.advance(by: 100)
        #expect(run.elapsedSeconds == 3)
        #expect(run.state == .paused)
    }

    @Test func onlyCompleteInclusiveRangeIncrementsLoopAndFiniteRunStopsAtEnd() throws {
        var run = try ScoreRun(score: score, range: .init(firstBar: 1, lastBar: 2), speed: 0.5, loopLimit: 2)
        run.start(countIn: false)
        run.advance(by: 7.9)
        #expect(run.completedLoops == 0)
        run.advance(by: 0.1)
        #expect(run.completedLoops == 1)
        #expect(run.tick == 3_840)
        run.advance(by: 100)
        #expect(run.completedLoops == 2)
        #expect(run.state == .finished)
        #expect(abs(run.elapsedSeconds - 16) < 0.000001)
        #expect(run.tick == 11_520)
    }

    @Test func resumeAndRewindDoNotEraseAccumulatedPracticeTime() throws {
        var run = try ScoreRun(score: score, range: score.fullRange, speed: 1)
        run.start(countIn: false)
        run.advance(by: 3)
        run.pause()
        run.rewind()
        #expect(run.elapsedSeconds == 3)
        #expect(run.tick == 0)
        #expect(run.state == .paused)
        run.start(countIn: false)
        run.advance(by: 2)
        #expect(run.elapsedSeconds == 5)
    }

    @Test func changingRangeRequiresPauseAndResetsLoopCountOnly() throws {
        var run = try ScoreRun(score: score, range: .init(firstBar: 0, lastBar: 0), speed: 1)
        run.start(countIn: false)
        run.advance(by: 3)
        #expect(throws: ScoreRunError.self) { try run.configure(range: .init(firstBar: 1, lastBar: 1), speed: 0.75, loopLimit: 5) }
        run.pause()
        try run.configure(range: .init(firstBar: 1, lastBar: 1), speed: 0.75, loopLimit: 5)
        #expect(run.tick == 3_840)
        #expect(run.elapsedSeconds == 3)
        #expect(run.completedLoops == 0)
    }
}
