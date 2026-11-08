import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct ScoreRecognitionSafetyTests {
    @Test func structurallyInvalidTonesAndUnsafeNumbersRejectInsteadOfBecomingRests() throws {
        let malformed: [[String:Any]] = [
            ["title":"x","bars":[["events":[["tick":0,"duration":960,"tones":[60,64,67]]]]]],
            ["title":"x","capo":Int.max,"bars":[["events":[]]]],
            ["title":"x","bars":[["number":Int.max,"events":[]]]],
            ["title":"x","bars":[["numerator":Int.min,"events":[]]]],
            ["title":"x","bars":[["events":[["tick":Int.max,"duration":960,"tones":[]]]]]]
        ]
        for raw in malformed { #expect(throws: ScoreRecognitionError.self) { try ScoreRecognitionDecoder.decode(JSONSerialization.data(withJSONObject: raw)) } }
    }
    @Test func extremeDraftMeterCannotOverflowTimelineBeforeCorrection() {
        let score = ScoreDocument(title: "校正",bars: [.init(number: 1,numerator: Int.max,denominator: 4,events: [])])
        #expect(score.length(of: score.bars[0]) == 0)
        #expect(throws: ScoreValidationError.self) { try score.validate() }
    }
    @Test func malformedTuningCannotCrashTheSixStringCorrectionForm() {
        let data = Data(#"{"title":"坏调弦","tuning":[40],"bars":[{"number":1,"events":[]}]}"#.utf8)
        #expect(throws: ScoreRecognitionError.self) { try ScoreRecognitionDecoder.decode(data) }
    }
    @Test func internalTickResolutionMustBeSafeBeforeAnyPreviewArithmetic() {
        let data = Data(#"{"title":"坏时基","ticksPerQuarter":9223372036854775807,"bars":[{"number":1,"events":[]}]}"#.utf8)
        #expect(throws: ScoreRecognitionError.self) { try ScoreRecognitionDecoder.decode(data) }
    }
}
