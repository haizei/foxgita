import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct ScoreRecognitionCompletenessTests {
    private func score(barCount: Int, numerator: Int = 4) -> ScoreDocument {
        .init(title: "Original", bars: (0..<barCount).map { .init(number: $0 + 1, numerator: numerator, events: []) })
    }

    @Test func numericallyValidThreeBarDraftDoesNotPassFiveBarSourceExpectation() throws {
        let draft = score(barCount: 3)
        try draft.validate()
        let issues = ScoreRecognitionCompleteness.issues(for: draft, expectedBars: 5, expectedQuarterBeats: 20)
        #expect(issues.contains { $0.field == "bar-count" })
        #expect(issues.contains { $0.field == "score-duration" })
    }

    @Test func mergedLongerBarsDoNotHideAMissingBarBoundary() {
        let draft = score(barCount: 4, numerator: 5)
        let issues = ScoreRecognitionCompleteness.issues(for: draft, expectedBars: 5, expectedQuarterBeats: 20)
        #expect(issues.contains { $0.field == "bar-count" })
        #expect(!issues.contains { $0.field == "score-duration" })
    }

    @Test func fiveBarsWithWrongMeterDoNotPassDurationExpectation() {
        let issues = ScoreRecognitionCompleteness.issues(for: score(barCount: 5, numerator: 3), expectedBars: 5, expectedQuarterBeats: 20)
        #expect(!issues.contains { $0.field == "bar-count" })
        #expect(issues.contains { $0.field == "score-duration" })
    }

    @Test func completeStructurePassesWithoutClaimingPitchOrRhythmAccuracy() {
        #expect(ScoreRecognitionCompleteness.issues(for: score(barCount: 5), expectedBars: 5, expectedQuarterBeats: 20).isEmpty)
        #expect(!ScoreRecognitionCompleteness.issues(for: score(barCount: 0), expectedBars: 0).isEmpty)
    }
}
