import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct ScoreRecognitionRefreshTests {
    @Test func upgradeVersionTracksSuccessfulRecognitionWithoutPublishingOrReplacingEdits() throws {
        var (old,fresh) = pair()
        #expect(old.needsLocalRecognitionUpgrade)
        fresh.localRecognitionVersion = RecognizedScoreDraft.currentLocalRecognitionVersion
        old.score.bars[0].events = [.init(tick: 0,duration: 960,tones: [.init(midi: 60)])]
        let result = old.refreshingUneditedBars(from: fresh)
        #expect(result.updated == 0)
        #expect(!result.draft.needsLocalRecognitionUpgrade)
        #expect(result.draft.score == old.score)
        #expect(!result.draft.isConfirmed)
        let restored = try JSONDecoder().decode(RecognizedScoreDraft.self,from: JSONEncoder().encode(result.draft))
        #expect(!restored.needsLocalRecognitionUpgrade)
        old.isConfirmed = true
        #expect(!old.needsLocalRecognitionUpgrade)
    }
    private func pair() -> (RecognizedScoreDraft,RecognizedScoreDraft) {
        let source = ScoreSourceLocation(page: 1,box: [0.2,0.3,0.2,0.1])
        let oldBar = ScoreBar(number: 1,events: [],source: source)
        let newBar = ScoreBar(number: 1,events: [.init(tick: 0,duration: 3840,tones: [.init(midi: 64,string: 1,fret: 0)])],source: source)
        let old = RecognizedScoreDraft(score: .init(title: "我的曲名",bars: [oldBar]),issues: [],localReadings: [oldBar.id:.init(problem: "未识别")])
        let fresh = RecognizedScoreDraft(score: .init(title: "新识别",bars: [newBar]),issues: [],localReadings: [newBar.id:.init(attacks: [.init(start: 0,length: 16,marks: ["1:0"])])])
        return (old,fresh)
    }

    @Test func refreshFillsUntouchedBarsAndPreservesIdentityAndSetup() {
        var (old,fresh) = pair()
        old.score.capo = 2
        let result = old.refreshingUneditedBars(from: fresh)
        #expect(result.updated == 1)
        #expect(result.draft.score.title == "我的曲名")
        #expect(result.draft.score.bars[0].id == old.score.bars[0].id)
        #expect(result.draft.score.bars[0].events[0].tones[0].midi == 66)
        #expect(result.draft.localReadings?[old.score.bars[0].id]?.problem == nil)
        #expect(!result.draft.isConfirmed)
    }

    @Test func manualEventsAndReviewedBarsAreNeverReplaced() {
        var (old,fresh) = pair()
        old.score.bars[0].events = [.init(tick: 0,duration: 960,tones: [.init(midi: 60)])]
        #expect(old.refreshingUneditedBars(from: fresh).updated == 0)
        old.score.bars[0].events = []
        old.reviewedBars = [old.score.bars[0].id:old.score.bars[0]]
        #expect(old.refreshingUneditedBars(from: fresh).updated == 0)
    }

    @Test func publishedDraftsAndEditedMeterOrArrowsArePreserved() {
        var (old,fresh) = pair()
        old.isConfirmed = true
        #expect(old.refreshingUneditedBars(from: fresh).updated == 0)
        old.isConfirmed = false; old.score.bars[0].numerator = 3
        #expect(old.refreshingUneditedBars(from: fresh).updated == 0)
        old.score.bars[0].numerator = 4
        old.localReadings?[old.score.bars[0].id]?.attacks = [.init(start: 0,length: 16,marks: ["↑"],correctedArrow: "↓")]
        #expect(old.refreshingUneditedBars(from: fresh).updated == 0)
    }

    @Test func manualDeletionAndLessCompleteRetriesPreserveExistingWork() {
        var (old,fresh) = pair()
        let id = old.score.bars[0].id
        let complete = TabReading(attacks: [.init(start: 0,length: 16,marks: ["1:0"])])
        old.localReadings?[id] = complete
        #expect(old.refreshingUneditedBars(from: fresh).updated == 0)
        old.score.bars[0].events = complete.recognizedEvents(tuning: old.score.tuning,capo: 0,page: 1)
        fresh.localReadings?[fresh.score.bars[0].id]?.attacks[0].length = 8
        #expect(old.refreshingUneditedBars(from: fresh).updated == 0)
    }
}
