import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct ScoreDraftReviewTests {
    @Test func measuredSweepCrossingsResolveOnlyClearStringBoundaries() {
        let box = [0.12,0.12,0.05,0.12]
        var evidence = TabStrumRangeEvidence(top: -0.1,bottom: 3.4,staffSpacing: 15,shaftCoverage: 1,clearEnds: true,box: box)
        #expect(evidence.crossedStrings == [1,2,3,4])
        evidence.top = 2; evidence.bottom = 5.4
        #expect(evidence.crossedStrings == [3,4,5,6])
        evidence.top = 3; evidence.bottom = 4.4
        #expect(evidence.crossedStrings == [4,5])
        evidence.top = 3.23
        #expect(evidence.crossedStrings == nil)
        evidence.top = 0; evidence.staffSpacing = 8
        #expect(evidence.crossedStrings == nil)
        evidence.staffSpacing = 15; evidence.clearEnds = false
        #expect(evidence.crossedStrings == nil)
        evidence.clearEnds = true; evidence.shaftCoverage = 0.9
        #expect(evidence.crossedStrings == nil)
        evidence.shaftCoverage = 1; evidence.top = .nan
        #expect(evidence.crossedStrings == nil)
    }

    @Test func provenSweepRangeMustMatchTheGeneratedNotesAndSourcePosition() {
        var value = draft(events: [.init(tick: 0,duration: 3840,tones: [.init(midi: 64,string: 1,fret: 0),.init(midi: 59,string: 2,fret: 0)])])
        let id = value.score.bars[0].id
        let range = TabStrumRangeEvidence(top: 0,bottom: 1.4,staffSpacing: 15,shaftCoverage: 1,clearEnds: true,box: [0.12,0.12,0.05,0.12])
        value.localReadings = [id:.init(attacks: [.init(start: 0,length: 16,marks: ["↑"],box: [0.1,0.1,0.2,0.2],diagramBinding: ["1:0","2:0"],diagramBox: [0.1,0.1,0.2,0.2],strumRange: range)])]
        #expect(value.reviewState(for: value.score.bars[0]) == .recognized)
        value.localReadings?[id]?.attacks[0].strumRange?.bottom = 2.4
        #expect(value.reviewConcerns(for: value.score.bars[0]) == [.strumRange])
        value.localReadings?[id]?.attacks[0].strumRange = range
        value.localReadings?[id]?.attacks[0].strumRange?.box = [0.6,0.6,0.1,0.1]
        #expect(value.reviewConcerns(for: value.score.bars[0]) == [.strumRange])
        value.localReadings?[id]?.attacks[0].strumRange = range
        value.score.bars[0].events[0].tones.removeLast()
        #expect(value.reviewConcerns(for: value.score.bars[0]) == [.strumRange])
    }

    @Test func explicitMuteAndRangeEvidenceSurviveReloadWithoutAcknowledgement() throws {
        var value = draft(events: [.init(tick: 0,duration: 3840,tones: [.init(midi: 55,string: 3,fret: 0)])])
        let id = value.score.bars[0].id
        let range = TabStrumRangeEvidence(top: 1,bottom: 2.4,staffSpacing: 15,shaftCoverage: 1,clearEnds: true,box: [0.12,0.12,0.05,0.12],mutedStrings: [2])
        value.localReadings = [id:.init(attacks: [.init(start: 0,length: 16,marks: ["↓"],box: [0.1,0.1,0.2,0.2],diagramBinding: ["3:0"],diagramBox: [0.1,0.1,0.2,0.2],strumRange: range)])]
        let restored = try JSONDecoder().decode(RecognizedScoreDraft.self,from: JSONEncoder().encode(value))
        #expect(restored.reviewState(for: restored.score.bars[0]) == .recognized)
        #expect(restored.reviewedBars == nil)
        #expect(!restored.isConfirmed)
        value.localReadings?[id]?.attacks[0].strumRange?.mutedStrings = [6]
        #expect(value.reviewConcerns(for: value.score.bars[0]) == [.strumRange])
    }

    @Test func clearHammerEvidenceAcceptsOnlyItsLocatedUnchangedPair() {
        let reading = TabReading(attacks: [
            .init(start: 0,length: 8,marks: ["4:0"],box: [0.1,0.1,0.1,0.2],hammerString: 4,
                  hammerEvidence: .init(string: 4,fromFret: 0,toFret: 2,box: [0.1,0.12,0.3,0.1],clearLabelAndArc: true)),
            .init(start: 8,length: 8,marks: ["4:2"],box: [0.3,0.1,0.1,0.2])
        ])
        let bar = ScoreBar(number: 1,events: reading.recognizedEvents(tuning: [40,45,50,55,59,64],capo: 0,page: 1))
        var value = RecognizedScoreDraft(score: .init(title: "击弦",bars: [bar]),issues: [],localReadings: [bar.id:reading])
        #expect(value.reviewState(for: bar) == .recognized)
        value.localReadings?[bar.id]?.attacks[0].hammerEvidence?.clearLabelAndArc = false
        #expect(value.reviewConcerns(for: bar) == [.hammerOn])
        value.localReadings?[bar.id] = reading
        value.localReadings?[bar.id]?.attacks[1].marks = ["4:3"]
        #expect(value.reviewConcerns(for: bar) == [.hammerOn])
        value.localReadings?[bar.id] = reading
        value.score.bars[0].events[1].tones[0].fret = 3
        #expect(value.reviewConcerns(for: value.score.bars[0]) == [.hammerOn])
    }

    private func boundDraft(mark: String) -> RecognizedScoreDraft {
        var value = draft(events: [.init(tick: 0,duration: 3840,tones: [.init(midi: 64,string: 1,fret: 0)])])
        let id = value.score.bars[0].id
        value.localReadings = [id:.init(attacks: [.init(start: 0,length: 16,marks: [mark],diagramBinding: ["1:0"],diagramBox: [0.1,0.1,0.2,0.2])])]
        return value
    }

    @Test func exactStringBindingIsRecognizedButSweepRangeRemainsASpecificDoubt() {
        let exact = boundDraft(mark: "x1")
        #expect(exact.reviewState(for: exact.score.bars[0]) == .recognized)
        let sweep = boundDraft(mark: "↑")
        #expect(sweep.reviewConcerns(for: sweep.score.bars[0]) == [.strumRange])
        var unknown = boundDraft(mark: "?")
        #expect(unknown.reviewState(for: unknown.score.bars[0]) == .needsCorrection)
        unknown.localReadings?[unknown.score.bars[0].id]?.attacks[0].marks = ["x2"]
        #expect(unknown.reviewState(for: unknown.score.bars[0]) == .needsCorrection)
    }

    @Test func setupWarningsAreHandledOnceRatherThanMarkingEveryBarUncertain() {
        var value = boundDraft(mark: "x1")
        value.score.bars[0].source = .init(page: 1)
        value.issues = [.init(field: "tempo",message: "核对速度",page: 1)]
        #expect(value.reviewState(for: value.score.bars[0]) == .recognized)
        value.issues.append(.init(field: "recognition",message: "核对音符",bar: 1,page: 1))
        #expect(value.reviewConcerns(for: value.score.bars[0]) == [.recognitionWarning])
    }

    @Test func aGroupOnlyAcknowledgesItsOwnUnchangedDoubtAndSurvivesReload() throws {
        var value = boundDraft(mark: "↑")
        let first = value.score.bars[0]
        var second = first; second.id = UUID(); second.number = 2
        second.events = second.events.map { event in var copy = event; copy.id = UUID(); return copy }
        value.score.bars.append(second)
        let firstReading = value.localReadings?[first.id]
        value.localReadings?[second.id] = firstReading
        let group = try #require(value.reviewGroups.first)
        #expect(group.barIDs.count == 2)
        var stale = value
        stale.localReadings?[first.id]?.attacks[0].durationNeedsReview = true
        let staleEvidenceAccepted = stale.confirmReviewGroup(group)
        #expect(!staleEvidenceAccepted)
        stale = value
        stale.score.bars[0].events[0].tones[0].fret = 1
        stale.score.bars[0].events[0].tones[0].midi = 65
        let staleMusicAccepted = stale.confirmReviewGroup(group)
        #expect(!staleMusicAccepted)
        let accepted = value.confirmReviewGroup(group)
        #expect(accepted)
        #expect(value.score.bars.allSatisfy { value.reviewState(for: $0) == .recognized })
        var restored = try JSONDecoder().decode(RecognizedScoreDraft.self,from: JSONEncoder().encode(value))
        #expect(restored.score.bars.allSatisfy { restored.reviewState(for: $0) == .recognized })
        restored.localReadings?[first.id]?.attacks[0].durationNeedsReview = true
        #expect(restored.reviewState(for: restored.score.bars[0]) == .needsCorrection)
    }

    @Test func manuallyChangedHammerPairsAreNotGroupedAsIdentical() {
        let reading = TabReading(attacks: [
            .init(start: 0,length: 8,marks: ["1:0"],hammerString: 1),
            .init(start: 8,length: 8,marks: ["1:2"])
        ])
        let events = reading.recognizedEvents(tuning: [40,45,50,55,59,64],capo: 0,page: 1)
        let a = ScoreBar(number: 1,events: events)
        var b = a; b.id = UUID(); b.number = 2
        b.events = reading.recognizedEvents(tuning: [40,45,50,55,59,64],capo: 0,page: 1)
        var value = RecognizedScoreDraft(score: .init(title: "击弦",bars: [a,b]),issues: [],localReadings: [a.id:reading,b.id:reading])
        #expect(value.reviewGroups.count == 1)
        value.score.bars[0].events[0].tones[0].midi = 65
        value.score.bars[0].events[0].tones[0].fret = 1
        #expect(value.reviewConcerns(for: value.score.bars[0]) == [.hammerOn])
        #expect(value.reviewGroups.isEmpty)
    }

    private func draft(events: [ScoreEvent]) -> RecognizedScoreDraft {
        .init(score: .init(title: "校正", bars: [.init(number: 1, events: events)]), issues: [])
    }

    @Test func emptyBarIsUnrecognizedButExplicitWholeBarRestIsRecognized() {
        let empty = draft(events: [])
        #expect(empty.reviewState(for: empty.score.bars[0]) == .unrecognized)
        let rest = draft(events: [.init(tick: 0, duration: 3840, tones: [])])
        #expect(rest.reviewState(for: rest.score.bars[0]) == .recognized)
    }

    @Test func gapsOverlapsAndInvalidPitchNeedCorrection() {
        for events: [ScoreEvent] in [
            [.init(tick: 0, duration: 960, tones: [.init(midi: 64)])],
            [.init(tick: 0, duration: 3840, tones: []), .init(tick: 960, duration: 960, tones: [])],
            [.init(tick: 0, duration: 3840, tones: [.init(midi: 60, string: 1, fret: 0)])]
        ] {
            let value = draft(events: events)
            #expect(value.reviewState(for: value.score.bars[0]) == .needsCorrection)
        }
    }

    @Test func simultaneousVoicesAreReviewedIndependently() {
        let value = draft(events: [
            .init(tick: 0, duration: 3840, tones: [.init(midi: 64)], voice: 1),
            .init(tick: 0, duration: 3840, tones: [.init(midi: 40)], voice: 2)
        ])
        #expect(value.reviewState(for: value.score.bars[0]) == .recognized)
    }

    @Test func sustainedNotesOnDifferentStringsCanOverlapInOneVoice() {
        let value = draft(events: [
            .init(tick: 0, duration: 2880, tones: [.init(midi: 64, string: 1, fret: 0)]),
            .init(tick: 960, duration: 2880, tones: [.init(midi: 60, string: 2, fret: 1)])
        ])
        #expect(value.reviewState(for: value.score.bars[0]) == .recognized)
    }

    @Test func conflictingFretsAcrossVoicesNeedCorrection() {
        let value = draft(events: [
            .init(tick: 0, duration: 3840, tones: [.init(midi: 64, string: 1, fret: 0)], voice: 1),
            .init(tick: 0, duration: 3840, tones: [.init(midi: 66, string: 1, fret: 2)], voice: 2)
        ])
        #expect(value.reviewState(for: value.score.bars[0]) == .needsCorrection)
    }

    @Test func localTabCapoUpdatesDerivedPitchWithoutBlockingReview() {
        var value = draft(events: [.init(tick: 0, duration: 3840, tones: [.init(midi: 64, string: 1, fret: 0)])])
        value.localReadings = [:]
        value.score.capo = 2
        #expect(value.reviewState(for: value.score.bars[0]) == .recognized)
        value.updateLocalPitches()
        #expect(value.score.bars[0].events[0].tones[0].midi == 66)
    }

    @Test func uncertainContentRequiresReviewAndEditingInvalidatesAcknowledgement() throws {
        var value = draft(events: [.init(tick: 0, duration: 3840, tones: [.init(midi: 64)])])
        value.issues = [.init(field: "recognition", message: "核对音高", bar: 1)]
        let bar = value.score.bars[0]
        #expect(value.reviewState(for: bar) == .needsCorrection)
        value.reviewedBars = [bar.id: bar]
        #expect(value.reviewState(for: bar) == .recognized)
        let restored = try JSONDecoder().decode(RecognizedScoreDraft.self, from: JSONEncoder().encode(value))
        #expect(restored.reviewState(for: bar) == .recognized)
        value.score.bars[0].events[0].tones[0].midi = 65
        #expect(value.reviewState(for: value.score.bars[0]) == .needsCorrection)
    }

    @Test func localRhythmCandidatesAndPageScopedWarningsAreNotLost() {
        var value = draft(events: [.init(tick: 0, duration: 3840, tones: [])])
        let id = value.score.bars[0].id
        value.localReadings = [id: .init(attacks: [.init(start: 0, length: 4, marks: ["1:0"], durationNeedsReview: true)])]
        #expect(value.reviewState(for: value.score.bars[0]) == .needsCorrection)
        value.localReadings = nil
        value.score.bars[0].source = .init(page: 2)
        value.issues = [.init(field: "recognition", message: "其他页", bar: 1, page: 1)]
        #expect(value.reviewState(for: value.score.bars[0]) == .recognized)
    }
}
