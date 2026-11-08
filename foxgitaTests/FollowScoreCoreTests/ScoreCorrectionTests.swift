import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct ScoreCorrectionTests {
    @Test func correctingMissingBarlinePreservesSoundAndTiesTheCrossingNote() throws {
        var score = ScoreDocument(title: "小节线",bars: [.init(number: 1,events: [.init(tick: 960,duration: 1920,tones: [.init(midi: 64)])])])
        let before = score.totalTicks
        try ScoreCorrection.split(score: &score,barIndex: 0,afterBeats: 2)
        try score.validate()
        #expect(score.totalTicks == before)
        #expect(score.bars.count == 2)
        #expect(score.bars[0].events[0].duration == 960)
        #expect(score.bars[1].events[0].tick == 0)
        #expect(score.bars[1].events[0].tones[0].tiedFromPrevious)
        try ScoreCorrection.mergeWithNext(score: &score,barIndex: 0)
        try score.validate()
        #expect(score.totalTicks == before)
        let sound = try ScoreSynthesisPlan(score: score,range: score.fullRange,speed: 1,sampleRate: 48_000)
        #expect(sound.notes.count == 1)
    }
    @Test func barlineCorrectionCannotEraseAMeterOrTempoChange() {
        var score = ScoreDocument(title: "不同拍号",bars: [.init(number: 1,events: []),.init(number: 2,denominator: 8,events: [])])
        #expect(throws: ScoreValidationError.self) { try ScoreCorrection.mergeWithNext(score: &score,barIndex: 0) }
        #expect(throws: ScoreValidationError.self) { try ScoreCorrection.split(score: &score,barIndex: 0,afterBeats: 4) }
        #expect(score.bars.count == 2)
    }

    @Test func splittingSourceOnlyBarDividesItsBoxByBeats() throws {
        var score = sourceScore()
        let original = score.bars[0]
        try ScoreCorrection.split(score: &score,barIndex: 0,afterBeats: 1)
        try score.validate()
        #expect(score.bars.map(\.numerator) == [1,3])
        #expect(score.bars.map(\.number) == [1,2])
        #expect(score.bars.map(\.content) == [.sourceOnly,.sourceOnly])
        #expect(score.bars.map(\.source) == [
            .init(page: 2,box: [0.125,0.25,0.125,0.125]),
            .init(page: 2,box: [0.25,0.25,0.375,0.125])
        ])
        #expect(score.bars[0].id == original.id)
        #expect(score.bars[1].id != original.id)
        #expect(score.totalTicks == 3840)
    }

    @Test func splittingMappedConfirmedBarPreservesContentAndTiedSound() throws {
        var score = sourceScore()
        score.bars[0].content = .confirmed
        score.bars[0].events = [.init(tick: 0,duration: 1920,tones: [.init(midi: 64)])]
        try ScoreCorrection.split(score: &score,barIndex: 0,afterBeats: 1)
        try score.validate()
        #expect(score.bars.map(\.content) == [.confirmed,.confirmed])
        #expect(score.bars[1].source == .init(page: 2,box: [0.25,0.25,0.375,0.125]))
        #expect(score.bars[0].events[0].duration == 960)
        #expect(score.bars[1].events[0].duration == 960)
        #expect(score.bars[1].events[0].tones[0].tiedFromPrevious)
    }

    @Test func splittingPageOnlyConfirmedBarCopiesItsPageWithoutInventingABox() throws {
        var score = ScoreDocument(title: "页码",bars: [.init(number: 1,events: [],source: .init(page: 3))])
        try ScoreCorrection.split(score: &score,barIndex: 0,afterBeats: 1)
        #expect(score.bars.map(\.source) == [.init(page: 3),.init(page: 3)])
        #expect(score.bars.map(\.content) == [nil,nil])
    }

    @Test func mergingSourceOnlyBarsUnionsBoxesAtHalfOfTheSmallerHeight() throws {
        var score = sourceScore()
        score.bars[0].source = .init(page: 2,box: [0.125,0.25,0.25,0.125])
        score.bars.append(.init(number: 2,events: [],source: .init(page: 2,box: [0.375,0.3125,0.5,0.25]),content: .sourceOnly))
        let firstID = score.bars[0].id
        try ScoreCorrection.mergeWithNext(score: &score,barIndex: 0)
        try score.validate()
        #expect(score.bars.count == 1)
        #expect(score.bars[0].source == .init(page: 2,box: [0.125,0.25,0.75,0.3125]))
        #expect(score.bars[0].content == .sourceOnly)
        #expect(score.bars[0].id == firstID)
        #expect(score.bars[0].numerator == 8)
    }

    @Test(arguments: [
        ScoreSourceLocation(page: 3,box: [0.125,0.25,0.5,0.125]),
        ScoreSourceLocation(page: 2,box: [0.125,0.3126,0.5,0.125]),
        ScoreSourceLocation(page: 2,box: [0.125,0.5,0.5,0.125])
    ])
    func mergingDifferentPagesOrRowsRejectsWithoutMutation(source: ScoreSourceLocation) {
        var score = sourceScore()
        score.bars.append(.init(number: 2,events: [],source: source,content: .sourceOnly))
        let original = score
        #expect(throws: ScoreValidationError.invalidBar(1)) { try ScoreCorrection.mergeWithNext(score: &score,barIndex: 0) }
        #expect(score == original)
    }

    @Test(arguments: [false,true],[false,true])
    func mergingSourceOnlyAndConfirmedBarsRejectsWithoutMutation(sourceOnlyFirst: Bool,legacyConfirmed: Bool) {
        var score = sourceScore()
        score.bars.append(.init(number: 2,events: [],source: score.bars[0].source,content: .confirmed))
        if !sourceOnlyFirst { score.bars[0].content = .confirmed; score.bars[1].content = .sourceOnly }
        if legacyConfirmed { score.bars[sourceOnlyFirst ? 1 : 0].content = nil }
        let original = score
        #expect(throws: ScoreValidationError.invalidBar(1)) { try ScoreCorrection.mergeWithNext(score: &score,barIndex: 0) }
        #expect(score == original)
    }

    @Test(arguments: [
        ScoreSourceLocation(page: 0,box: [0.125,0.25,0.5,0.125]),
        ScoreSourceLocation(page: 2,box: [0.125,0.25,-0.5,0.125]),
        ScoreSourceLocation(page: 2,box: [0.125,0.25,0.5])
    ])
    func splittingInvalidMappedConfirmedBarRejectsWithoutMutation(source: ScoreSourceLocation) {
        var score = ScoreDocument(title: "定位无效",bars: [.init(number: 1,events: [],source: source)])
        let original = score
        #expect(throws: ScoreValidationError.invalidBar(1)) { try ScoreCorrection.split(score: &score,barIndex: 0,afterBeats: 1) }
        #expect(score == original)
    }

    @Test(arguments: [0,1,2,3])
    func splittingInvalidSourceOnlyBarRejectsWithoutMutation(invalidCase: Int) {
        var score = sourceScore()
        switch invalidCase {
        case 0: score.sourceID = nil
        case 1: score.bars[0].source = nil
        case 2: score.bars[0].source?.box = nil
        default: score.bars[0].events = [.init(tick: 0,duration: 960,tones: [.init(midi: 64)])]
        }
        let original = score
        #expect(throws: ScoreValidationError.invalidBar(1)) { try ScoreCorrection.split(score: &score,barIndex: 0,afterBeats: 1) }
        #expect(score == original)
    }

    @Test(arguments: [0,1,2,3,4])
    func mergingUnverifiableMappedConfirmedBarsRejectsWithoutMutation(invalidCase: Int) {
        var score = sourceScore()
        score.bars[0].content = nil
        score.bars.append(.init(number: 2,events: [],source: score.bars[0].source,content: .confirmed))
        switch invalidCase {
        case 0: score.bars[0].source = nil
        case 1: score.bars[1].source = nil
        case 2: score.bars[1].source?.box = nil
        case 3: score.bars[1].source?.box = [0,0,0,0]
        default: score.bars[1].source?.page = 0
        }
        let original = score
        #expect(throws: ScoreValidationError.invalidBar(1)) { try ScoreCorrection.mergeWithNext(score: &score,barIndex: 0) }
        #expect(score == original)
    }

    @Test(arguments: [false,true])
    func mergingInvalidSourceOnlyContentRejectsWithoutMutation(missingSourceID: Bool) {
        var score = sourceScore()
        score.bars.append(.init(number: 2,events: [],source: score.bars[0].source,content: .sourceOnly))
        if missingSourceID { score.sourceID = nil }
        else { score.bars[1].events = [.init(tick: 0,duration: 960,tones: [.init(midi: 64)])] }
        let original = score
        #expect(throws: ScoreValidationError.invalidBar(1)) { try ScoreCorrection.mergeWithNext(score: &score,barIndex: 0) }
        #expect(score == original)
    }

    @Test func mergingMappedConfirmedBarsPreservesMusicAndLegacyConfirmedMeaning() throws {
        var score = sourceScore()
        score.bars[0].content = nil
        score.bars[0].events = [.init(tick: 0,duration: 960,tones: [.init(midi: 64)])]
        score.bars.append(.init(number: 2,events: [.init(tick: 0,duration: 960,tones: [.init(midi: 67)])],source: .init(page: 2,box: [0.625,0.25,0.25,0.125]),content: .confirmed))
        try ScoreCorrection.mergeWithNext(score: &score,barIndex: 0)
        try score.validate()
        #expect(score.bars[0].content == nil)
        #expect(score.bars[0].source == .init(page: 2,box: [0.125,0.25,0.75,0.125]))
        #expect(score.bars[0].events.map(\.tick) == [0,3840])
        #expect(score.bars[0].events.flatMap(\.tones).map(\.midi) == [64,67])
    }

    @Test func removingBarDecrementsFollowingNumbersAndPreservesRemainingBars() throws {
        var score = sourceScore()
        score.bars.append(.init(number: 2,events: [.init(tick: 0,duration: 960,tones: [.init(midi: 64)])]))
        score.bars.append(.init(number: 3,events: [],source: score.bars[0].source,content: .sourceOnly))
        let first = score.bars[0]
        var last = score.bars[2]
        last.number = 2
        let versionID = score.versionID
        try ScoreCorrection.remove(score: &score,barIndex: 1)
        try score.validate()
        #expect(score.bars == [first,last])
        #expect(score.versionID == versionID)
    }

    @Test func removingFirstBarRenumbersTheRemainingConfirmedBar() throws {
        var score = ScoreDocument(title: "删除首小节",bars: [
            .init(number: 1,events: []),
            .init(number: 2,events: [.init(tick: 0,duration: 960,tones: [.init(midi: 67)])])
        ])
        var remaining = score.bars[1]
        remaining.number = 1
        try ScoreCorrection.remove(score: &score,barIndex: 0)
        #expect(score.bars == [remaining])
    }

    @Test(arguments: [-1,0,1])
    func removingLastOrInvalidBarRejectsWithoutMutation(barIndex: Int) {
        var score = sourceScore()
        let original = score
        #expect(throws: ScoreValidationError.invalidRange) { try ScoreCorrection.remove(score: &score,barIndex: barIndex) }
        #expect(score == original)
    }

    @Test func removingFinalPositionFromMultipleBarsIsAllowed() throws {
        var score = sourceScore()
        score.bars.append(.init(number: 2,events: []))
        let remaining = score.bars[0]
        try ScoreCorrection.remove(score: &score,barIndex: 1)
        #expect(score.bars == [remaining])
    }

    @Test func splittingToleratedEdgeBoxRejectsAnInvalidResultWithoutMutation() throws {
        var score = sourceScore()
        score.bars[0].source?.box = [0.999,0.25,0.002,0.125]
        try score.validate()
        let original = score
        #expect(throws: ScoreValidationError.invalidBar(1)) { try ScoreCorrection.split(score: &score,barIndex: 0,afterBeats: 3) }
        #expect(score == original)
    }

    @Test func mergingToleratedEdgeBoxesRejectsAnInvalidUnionWithoutMutation() throws {
        var score = sourceScore()
        score.bars[0].source?.box = [0,0.25,0.5,0.125]
        score.bars.append(.init(number: 2,events: [],source: .init(page: 2,box: [0.5,0.25,0.501,0.125]),content: .sourceOnly))
        try score.validate()
        let original = score
        #expect(throws: ScoreValidationError.invalidBar(1)) { try ScoreCorrection.mergeWithNext(score: &score,barIndex: 0) }
        #expect(score == original)
    }

    @Test func removingWithUnrepresentableFollowingNumberRejectsWithoutMutation() {
        var score = sourceScore()
        score.bars.append(.init(number: Int.min,events: []))
        let original = score
        #expect(throws: ScoreValidationError.invalidBar(Int.min)) { try ScoreCorrection.remove(score: &score,barIndex: 0) }
        #expect(score == original)
    }

    @Test(arguments: [0,1,2])
    func correctionsDoNotValidateUnrelatedDraftBars(operation: Int) throws {
        let unrelated = ScoreBar(number: 3,events: [],content: .sourceOnly)
        var score = ScoreDocument(title: "待校正草稿",bars: [.init(number: 1,events: []),.init(number: 2,events: []),unrelated])
        switch operation {
        case 0: try ScoreCorrection.split(score: &score,barIndex: 0,afterBeats: 1)
        case 1: try ScoreCorrection.mergeWithNext(score: &score,barIndex: 0)
        default: try ScoreCorrection.remove(score: &score,barIndex: 0)
        }
        #expect(score.bars.last?.id == unrelated.id)
        #expect(score.bars.last?.isSourceOnly == true)
        #expect(score.bars.last?.source == nil)
    }

    @Test(arguments: [false,true])
    func invalidEventsRejectAfterGeometryWithoutMutation(merging: Bool) {
        var score = sourceScore()
        score.bars[0].content = .confirmed
        let invalid = ScoreEvent(tick: 0,duration: 5000,tones: [.init(midi: 64)])
        if merging { score.bars.append(.init(number: 2,events: [invalid],source: score.bars[0].source)) }
        else { score.bars[0].events = [invalid] }
        let original = score
        #expect(throws: ScoreValidationError.invalidEvent(merging ? 2 : 1)) {
            if merging { try ScoreCorrection.mergeWithNext(score: &score,barIndex: 0) }
            else { try ScoreCorrection.split(score: &score,barIndex: 0,afterBeats: 1) }
        }
        #expect(score == original)
    }

    private func sourceScore() -> ScoreDocument {
        ScoreDocument(title: "原谱小节",bars: [.init(number: 1,events: [],source: .init(page: 2,box: [0.125,0.25,0.5,0.125]),content: .sourceOnly)],sourceID: UUID())
    }

}
