import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct ScoreAudioTests {
    @Test func continuousLoopGradingDoesNotSilentlyStopAfter999Passes() {
        let score = ScoreDocument(title: "长时间循环",tempo: .init(bpm: 120),bars: [.init(number: 1,events: [.init(tick: 0,duration: 960,tones: [.init(midi: 64)])])])
        var grader = ScorePerformanceGrader(score: score,range: score.fullRange,speed: 1,loopLimit: nil)
        for loop in 0..<1_002 {
            grader.observe(.init(pitches: [64:1],rms: 0.2,onset: true,quality: .reliable),at: Double(loop)*2)
            grader.finish(at: Double(loop)*2+0.3)
        }
        #expect(grader.summary.judgedEvents == 1_002)
        #expect(grader.summary.totalScore == 100)
    }
    @Test func oneCorrectNoteCannotClaimFullCoverageOfAWholeAttempt() {
        let score = ScoreExercises.melody
        var grader = ScorePerformanceGrader(score: score,range: score.fullRange,speed: 1,loopLimit: 5)
        grader.observe(.init(pitches: [64:1],rms: 0.2,onset: true,quality: .reliable),at: 0)
        grader.finish(at: 0.3)
        #expect(grader.summary.coverage < 0.1)
        #expect(grader.summary.totalScore == nil)
    }
    @Test func sixStringChordIncludesBassAndTrebleAndCapoHighNotesRemainDetectable() {
        let full = ScorePitchAnalyzer().analyze(samples: samples([40,47,52,56,59,64]),sampleRate: 22_050)
        #expect(Set(full.pitches.keys).isSuperset(of: [40,47,52,56,59,64]))
        let high = ScorePitchAnalyzer().analyze(samples: samples([88,92,95]),sampleRate: 22_050)
        #expect(Set(high.pitches.keys).isSuperset(of: [88,92,95]))
    }
    @Test func seekingDoesNotGradeSkippedNotesAndPauseDoesNotCloseFutureOnsets() {
        let score = ScoreDocument(title: "定位",tempo: .init(bpm: 120),bars: [
            .init(number: 1,events: [.init(tick: 0,duration: 960,tones: [.init(midi: 64)]),.init(tick: 960,duration: 960,tones: [.init(midi: 65)])])
        ])
        var grader = ScorePerformanceGrader(score: score,range: score.fullRange,speed: 1)
        grader.begin(at: 0.5)
        grader.observe(.init(pitches: [65:1],rms: 0.2,onset: true,quality: .reliable),at: 0.5)
        grader.finish(at: 0.8)
        #expect(grader.summary.expectedEvents == 1)
        #expect(grader.summary.totalScore == 100)
        var stopped = ScorePerformanceGrader(score: score,range: score.fullRange,speed: 1)
        stopped.finish(at: 0.3)
        #expect(stopped.summary.expectedEvents == 2)
    }
    private func samples(_ notes: [Int], rate: Double = 22_050) -> [Float] {
        (0..<4_096).map { i in
            var value = 0.0
            for note in notes {
                let frequency = 440 * pow(2, Double(note - 69) / 12)
                for harmonic in 1...5 {
                    value += 0.12 / Double(max(1, notes.count)) / pow(Double(harmonic), 1.3)
                        * sin(2 * .pi * frequency * Double(harmonic) * Double(i) / rate + Double(note) / 7)
                }
            }
            return Float(value)
        }
    }

    @Test func polyphonicAnalysisFindsChordFundamentalsInsteadOfOnlyOnePitch() throws {
        let analyzer = ScorePitchAnalyzer()
        let result = analyzer.analyze(samples: samples([48, 52, 55]), sampleRate: 22_050)
        #expect(result.quality == .reliable)
        let detected = Set(result.pitches.keys)
        #expect(detected.isSuperset(of: [48, 52, 55]))
        #expect(!detected.contains(56))
    }

    @Test func twoDifferentChordsProduceDifferentObservedPitchSets() {
        let analyzer = ScorePitchAnalyzer()
        let major = analyzer.analyze(samples: samples([48, 52, 55]), sampleRate: 22_050)
        let minor = analyzer.analyze(samples: samples([48, 51, 55]), sampleRate: 22_050)
        #expect(major.pitches[52] != nil)
        #expect(minor.pitches[51] != nil)
        #expect(minor.pitches[52] == nil)
    }

    @Test func silenceAndClippingCannotManufactureCorrectNotes() {
        let analyzer = ScorePitchAnalyzer()
        let silence = analyzer.analyze(samples: Array(repeating: 0, count: 4_096), sampleRate: 22_050)
        #expect(silence.quality == .silence)
        #expect(silence.pitches.isEmpty)
        let clipping = analyzer.analyze(samples: Array(repeating: 1, count: 4_096), sampleRate: 22_050)
        #expect(clipping.quality == .unreliable)
        #expect(clipping.pitches.isEmpty)
    }

    @Test func missingOnsetsCannotReceivePerfectStrummingRhythmScore() {
        let notes = [ScoreTone(midi: 48), ScoreTone(midi: 52), ScoreTone(midi: 55)]
        let score = ScoreDocument(title: "节奏", tempo: .init(bpm: 120), bars: [
            ScoreBar(number: 1, events: [
                .init(tick: 0, duration: 960, tones: notes), .init(tick: 960, duration: 960, tones: notes)
            ])
        ])
        var grader = ScorePerformanceGrader(score: score, range: score.fullRange, speed: 1)
        let held = ScorePitchObservation(pitches: [48: 1, 52: 1, 55: 1], rms: 0.2, onset: false, quality: .reliable)
        for t in [0.05, 0.2, 0.45, 0.55, 0.8, 1.0] { grader.observe(held, at: t) }
        grader.finish(at: 2)
        #expect(grader.summary.pitchAccuracy == 1)
        #expect(grader.summary.rhythmAccuracy == 0)
        #expect((grader.summary.totalScore ?? 100) < 100)
    }

    @Test func unreliableInputDoesNotCreateAZeroOrPerfectScore() {
        let score = ScoreExercises.melody
        var grader = ScorePerformanceGrader(score: score, range: score.fullRange, speed: 1)
        grader.observe(.init(pitches: [:], rms: 0.3, onset: false, quality: .unreliable), at: 0.1)
        grader.finish(at: 1)
        #expect(grader.summary.totalScore == nil)
        #expect(grader.summary.judgedEvents == 0)
    }
}
