import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct ScoreRecognitionTests {
    @Test func unknownNullableMetadataUsesReviewableDefaultsNotAParsingFailure() throws {
        let raw = #"{"title":"Original","composer":null,"tempo":null,"tuning":null,"capo":null,"bars":[{"number":1,"numerator":4,"denominator":4,"events":[{"tick":0,"duration":960,"tones":[{"midi":55}]}]}]}"#
        let draft = try ScoreRecognitionDecoder.decode(Data(raw.utf8))
        #expect(draft.score.composer == "导入曲谱")
        #expect(draft.score.tempo.bpm == 100)
        #expect(draft.score.tuning == [40,45,50,55,59,64])
        #expect(draft.score.capo == 0)
        for field in ["tempo","tuning","capo"] {
            #expect(draft.issues.contains { $0.field == field })
        }
        #expect(!draft.isConfirmed)
    }
    @Test func warningsAndNotesRetainOriginalPageAndSourceBox() throws {
        let raw: [String:Any] = ["title":"定位","warnings":[["message":"核对升号","page":2,"box":[0.1,0.2,0.3,0.2]]],
            "bars":[["number":1,"events":[["tick":0,"duration":960,"source":["page":2,"box":[0.1,0.2,0.3,0.2]],"tones":[["midi":64]]]]]]]
        let draft = try ScoreRecognitionDecoder.decode(JSONSerialization.data(withJSONObject: raw))
        #expect(draft.issues.last?.page == 2)
        #expect(draft.issues.last?.box == [0.1,0.2,0.3,0.2])
        #expect(draft.score.bars[0].events[0].source?.page == 2)
    }
    private let payload = #"{"title":"单音练习","tempo":{"bpm":80,"beatUnit":4},"bars":[{"number":1,"events":[{"tick":0,"duration":960,"tones":[{"midi":40,"string":6,"fret":0}]}]}]}"#

    @Test func providerMusicWithoutInternalUUIDsBecomesAnUnpublishedEditableDraft() throws {
        let draft = try ScoreRecognitionDecoder.decode(Data(payload.utf8))
        try draft.score.validate()
        #expect(draft.score.bars[0].events[0].tones[0].midi == 40)
        #expect(!draft.isConfirmed)
    }

    @Test func inconsistentMusicIsKeptForCorrectionRatherThanSilentlyRepaired() throws {
        let data = Data(payload.replacingOccurrences(of: #""midi":40"#, with: #""midi":60"#).utf8)
        let draft = try ScoreRecognitionDecoder.decode(data)
        #expect(draft.score.bars[0].events[0].tones[0].midi == 60)
        #expect(throws: ScoreValidationError.self) { try draft.score.validate() }
        #expect(!draft.issues.isEmpty)
    }

    @Test func missingTempoRequiresReviewAndDoesNotClaimRecognizedOriginalSpeed() throws {
        let data = Data(#"{"title":"缺速度","bars":[{"number":1,"events":[]}]}"#.utf8)
        let draft = try ScoreRecognitionDecoder.decode(data)
        #expect(draft.issues.contains { $0.field == "tempo" })
        #expect(!draft.isConfirmed)
    }

    @Test func nonMusicAndOversizedResponsesAreRejected() {
        #expect(throws: (any Error).self) { try ScoreRecognitionDecoder.decode(Data("not-json".utf8)) }
        #expect(throws: (any Error).self) { try ScoreRecognitionDecoder.decode(Data(#"{"title":"假结果","bars":[]}"#.utf8)) }
        #expect(throws: (any Error).self) { try ScoreRecognitionDecoder.decode(Data(repeating: 32, count: 4_000_001)) }
    }
}
