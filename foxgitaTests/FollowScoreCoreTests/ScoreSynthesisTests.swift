import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct ScoreSynthesisTests {
    @Test func tiesSustainAcrossBarsAndStartingInsideATieStillSounds() throws {
        let score = ScoreDocument(title: "延音",tempo: .init(bpm: 120),bars: [
            .init(number: 1,events: [.init(tick: 2880,duration: 960,tones: [.init(midi: 64)])]),
            .init(number: 2,events: [.init(tick: 0,duration: 1920,tones: [.init(midi: 64,tiedFromPrevious: true)])])
        ])
        let whole = try ScoreSynthesisPlan(score: score,range: score.fullRange,speed: 1,sampleRate: 48_000)
        #expect(whole.notes.count == 1)
        #expect(whole.notes.first?.durationFrames == 72_000)
        let cut = try ScoreSynthesisPlan(score: score,range: .init(firstBar: 1,lastBar: 1),speed: 1,sampleRate: 48_000)
        #expect(cut.notes.count == 1)
        #expect(cut.notes.first?.frame == 0)
        #expect(cut.downbeatFrames == [0])
        #expect(whole.downbeatFrames == [0,96_000])
    }
    @Test func scheduledSoundAndClicksShareTheSameTempoAndSelectedRange() throws {
        let score = ScoreDocument(title: "发声", tempo: .init(bpm: 120), bars: [
            .init(number: 1, events: []),
            .init(number: 2, events: [.init(tick: 960, duration: 960, tones: [.init(midi: 64)])])
        ])
        let plan = try ScoreSynthesisPlan(score: score, range: .init(firstBar: 1, lastBar: 1), speed: 0.5, sampleRate: 48_000)
        #expect(plan.loopFrames == 192_000)
        #expect(plan.notes.first?.frame == 48_000)
        #expect(plan.notes.first?.durationFrames == 48_000)
        #expect(plan.beatFrames == [0,48_000,96_000,144_000])
    }
}
