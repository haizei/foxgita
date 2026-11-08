import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct ScoreDocumentTests {
    @Test func optionalContentRoundTripsIncludingLegacyAndConfirmedBars() throws {
        var score = try sourceOnlyScore()
        score.bars = [
            .init(number: 1, events: []),
            .init(number: 2, events: [.init(tick: 0, duration: 3_840, tones: [])], content: .confirmed),
            score.bars[1]
        ]
        score.bars[2].number = 3
        try score.validate()
        let data = try JSONEncoder().encode(score)
        let encoded = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let bars = try #require(encoded["bars"] as? [[String: Any]])
        #expect(bars.map { $0["content"] as? String } == [nil, "confirmed", "sourceOnly"])
        let decoded = try JSONDecoder().decode(ScoreDocument.self, from: data)
        #expect(decoded == score)
        #expect(decoded.bars.map(\.content) == [nil, .confirmed, .sourceOnly])
        #expect(decoded.bars.map(\.isSourceOnly) == [false, false, true])
    }

    @Test func legacyJSONWithoutContentKeepsEmptyBarsConfirmed() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "versionID": "00000000-0000-0000-0000-000000000002",
          "title": "旧曲谱", "composer": "测试", "ticksPerQuarter": 960,
          "tempo": {"bpm": 120, "beatUnit": 4},
          "tuning": [40, 45, 50, 55, 59, 64], "capo": 0,
          "bars": [
            {
              "id": "00000000-0000-0000-0000-000000000004",
              "number": 1, "numerator": 4, "denominator": 4, "events": []
            },
            {
              "id": "00000000-0000-0000-0000-000000000005",
              "number": 2, "numerator": 4, "denominator": 4,
              "events": [{
                "id": "00000000-0000-0000-0000-000000000006",
                "tick": 0, "duration": 960, "voice": 1,
                "tones": [{"midi": 64, "tiedFromPrevious": false}]
              }]
            }
          ]
        }
        """
        let score = try JSONDecoder().decode(ScoreDocument.self, from: Data(json.utf8))
        try score.validate()
        #expect(score.bars.map(\.content) == [nil, nil])
        #expect(score.bars.map(\.isSourceOnly) == [false, false])
        #expect(score.confirmedBarCount == 2)
        #expect(!score.hasSourceOnlyBars)
        #expect(score.soundingEvents.count == 1)
    }

    @Test func mixedContentCountsLegacyAndConfirmedRestBars() throws {
        var score = try sourceOnlyScore()
        #expect(score.confirmedBarCount == 0)
        #expect(score.hasSourceOnlyBars)
        score.bars.insert(.init(number: 3, events: []), at: 0)
        score.bars.insert(.init(number: 4, events: [.init(tick: 0, duration: 3_840, tones: [])], content: .confirmed), at: 1)
        try score.validate()
        #expect(score.confirmedBarCount == 2)
        #expect(score.hasSourceOnlyBars)
        #expect(!score.bars[1].isSourceOnly)
        score.bars.removeLast(2)
        score.sourceID = nil
        try score.validate()
        #expect(score.confirmedBarCount == 2)
        #expect(!score.hasSourceOnlyBars)
    }

    @Test(arguments: [false, true])
    func sourceOnlyBarsRejectEveryEventIncludingRests(isRest: Bool) throws {
        var score = try sourceOnlyScore()
        score.bars[1].number = 9
        score.bars[1].events = [.init(tick: 0, duration: 960, tones: isRest ? [] : [.init(midi: 64)])]
        #expect(throws: ScoreValidationError.invalidBar(9)) { try score.validate() }
    }

    @Test func sourceOnlyBarsRequireASourceLocation() throws {
        var score = try sourceOnlyScore()
        score.bars[1].number = 9
        score.bars[1].source = nil
        #expect(throws: ScoreValidationError.invalidBar(9)) { try score.validate() }
    }

    @Test(arguments: [
        nil, [], [0.1, 0.2, 0.3], [0.1, 0.2, 0, 0.3], [0.1, 0.2, 0.3, 0],
        [0.9, 0.2, 0.3, 0.3], [0.1, 0.9, 0.3, 0.3], [-0.1, 0.2, 0.3, 0.3],
        [Double.nan, 0.2, 0.3, 0.3]
    ] as [[Double]?])
    func sourceOnlyBarsRequireAValidBox(box: [Double]?) throws {
        var score = try sourceOnlyScore()
        score.bars[1].number = 9
        score.bars[1].source?.box = box
        #expect(throws: ScoreValidationError.invalidBar(9)) { try score.validate() }
    }

    @Test(arguments: [0, -1])
    func sourceOnlyBarsRequireOneBasedPages(page: Int) throws {
        var score = try sourceOnlyScore()
        score.bars[1].number = 9
        score.bars[1].source?.page = page
        #expect(throws: ScoreValidationError.invalidBar(9)) { try score.validate() }
    }

    @Test func sourceOnlyBarsRequireTheDocumentSourceID() throws {
        var score = try sourceOnlyScore()
        score.bars[0].number = 7
        score.sourceID = nil
        #expect(throws: ScoreValidationError.invalidBar(7)) { try score.validate() }
    }

    @Test func anEntireSourceOnlyScoreCanRunToCompletion() throws {
        let score = try sourceOnlyScore()
        var run = try ScoreRun(score: score, range: score.fullRange, speed: 1, loopLimit: 1)
        run.start(countIn: false)
        run.advance(by: 4)
        #expect(run.state == .finished)
        #expect(run.completedLoops == 1)
        #expect(run.tick == 7_680)
        #expect(run.elapsedSeconds == 4)
    }

    @Test func anEntireSourceOnlyScoreSynthesizesOnlyBeatPoints() throws {
        let score = try sourceOnlyScore()
        let plan = try ScoreSynthesisPlan(score: score, range: score.fullRange, speed: 1, sampleRate: 48_000)
        #expect(score.soundingEvents.isEmpty)
        #expect(plan.notes.isEmpty)
        #expect(plan.beatFrames == [0, 24_000, 48_000, 72_000, 96_000, 120_000, 144_000, 168_000])
        #expect(plan.downbeatFrames == [0, 96_000])
        #expect(plan.loopFrames == 192_000)
    }

    @Test func anEntireSourceOnlyScoreNeverProducesAGrade() throws {
        let score = try sourceOnlyScore()
        var grader = ScorePerformanceGrader(score: score, range: score.fullRange, speed: 1)
        grader.observe(.init(pitches: [:], rms: 0, onset: false, quality: .reliable), at: 0)
        grader.observe(.init(pitches: [64: 1], rms: 0.2, onset: true, quality: .reliable), at: 2)
        grader.finish(at: 4)
        #expect(grader.summary.expectedEvents == 0)
        #expect(grader.summary.judgedEvents == 0)
        #expect(grader.summary.totalScore == nil)
    }

    private func sourceOnlyScore() throws -> ScoreDocument {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "versionID": "00000000-0000-0000-0000-000000000002",
          "title": "原谱跟练", "composer": "测试", "ticksPerQuarter": 960,
          "tempo": {"bpm": 120, "beatUnit": 4},
          "tuning": [40, 45, 50, 55, 59, 64], "capo": 0,
          "sourceID": "00000000-0000-0000-0000-000000000003",
          "bars": [
            {
              "id": "00000000-0000-0000-0000-000000000004",
              "number": 1, "numerator": 4, "denominator": 4, "events": [],
              "content": "sourceOnly", "source": {"page": 1, "box": [0.1, 0.2, 0.3, 0.4]}
            },
            {
              "id": "00000000-0000-0000-0000-000000000005",
              "number": 2, "numerator": 4, "denominator": 4, "events": [],
              "content": "sourceOnly", "source": {"page": 2, "box": [0.5, 0.2, 0.3, 0.4]}
            }
          ]
        }
        """
        return try JSONDecoder().decode(ScoreDocument.self, from: Data(json.utf8))
    }

    @Test func eighthNoteTempoIsNotMistakenForQuarterNoteTempo() throws {
        let score = ScoreDocument(title: "六八拍", tempo: .init(bpm: 120, beatUnit: 8), bars: [
            ScoreBar(number: 1, numerator: 6, denominator: 8, events: [])
        ])
        try score.validate()
        #expect(abs(try score.seconds(atTick: 2_880) - 3) < 0.000001)
    }

    @Test func slowerPlaybackAndBarTempoChangesUseTheSameMapping() throws {
        let score = ScoreDocument(title: "变速", tempo: .init(bpm: 120), bars: [
            ScoreBar(number: 1, events: []),
            ScoreBar(number: 2, events: [], tempo: .init(bpm: 60))
        ])
        #expect(abs(try score.seconds(atTick: 7_680) - 6) < 0.000001)
        #expect(abs(try score.seconds(atTick: 7_680, speed: 0.5) - 12) < 0.000001)
        #expect(try score.tick(atSeconds: 4, speed: 0.5) == 3_840)
    }

    @Test func invalidFretPitchCannotBecomeAPlayableScore() throws {
        let wrong = ScoreTone(midi: 60, string: 6, fret: 0)
        let score = ScoreDocument(title: "错弦品", bars: [
            ScoreBar(number: 1, events: [.init(tick: 0, duration: 960, tones: [wrong])])
        ])
        #expect(throws: ScoreValidationError.self) { try score.validate() }
    }

    @Test func noteCannotRunPastItsBarWithoutAnExplicitTie() {
        let score = ScoreDocument(title: "错误时值", bars: [
            ScoreBar(number: 1, events: [.init(tick: 3_000, duration: 960, tones: [.init(midi: 40, string: 6, fret: 0)])])
        ])
        #expect(throws: ScoreValidationError.self) { try score.validate() }
    }

    @Test func importedRangeIsInclusiveAndCannotPointOutsideTheVersion() throws {
        let score = ScoreDocument(title: "四小节", bars: (1...4).map { ScoreBar(number: $0, events: []) })
        let range = ScoreRange(firstBar: 1, lastBar: 2)
        #expect(try score.tickRange(for: range) == 3_840..<11_520)
        #expect(throws: ScoreValidationError.self) { try score.tickRange(for: .init(firstBar: 3, lastBar: 4)) }
    }

    @Test func unsafeTempoAndEmptyScoresAreRejected() {
        #expect(throws: ScoreValidationError.self) { try ScoreDocument(title: "空", bars: []).validate() }
        let score = ScoreDocument(title: "零速度", tempo: .init(bpm: 0), bars: [.init(number: 1, events: [])])
        #expect(throws: ScoreValidationError.self) { try score.validate() }
    }

    @Test func originalExercisesHaveStableIdentityAndPlayableContent() throws {
        let first = ScoreExercises.documents
        let second = ScoreExercises.documents
        #expect(first.count == 3)
        #expect(first.map(\.versionID) == second.map(\.versionID))
        #expect(first == second)
        for score in first {
            try score.validate()
            #expect(!score.soundingEvents.isEmpty)
            #expect(score.soundingEvents.allSatisfy { !$0.event.tones.isEmpty })
        }
    }
}
