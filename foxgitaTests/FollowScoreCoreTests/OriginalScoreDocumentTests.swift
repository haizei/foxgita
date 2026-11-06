import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct OriginalScoreDocumentTests {
    @Test func hugeBeatCountsAreRejectedBeforeAudioFrameConversion() {
        let row = OriginalScoreRow(page: 0, box: .init(x: 0, y: 0, width: 1, height: 0.2), beats: 1e20)
        let document = OriginalScoreDocument(title: "超大输入", pageCount: 1, rows: [row])
        #expect(throws: OriginalScoreError.self) { try document.validate() }
    }
    @Test func invalidFractionsAndOutOfPageBoxesCannotBePublished() {
        var score = OriginalScoreDocument(title: "校验", pageCount: 1, rows: [
            .init(page: 0, box: .init(x: 0, y: 0, width: 1, height: 0.2), beats: 0.25)
        ])
        #expect(throws: OriginalScoreError.self) { try score.validate() }
        score.rows[0].beats = 1.5
        score.rows[0].box.x = 0.5
        #expect(throws: OriginalScoreError.self) { try score.validate() }
    }
    @Test func sixEightUsesEighthNoteBeatsAndPreservesWeakPickupAcrossRows() throws {
        let first = OriginalScoreRow(page: 0, box: .init(x: 0.1, y: 0.1, width: 0.8, height: 0.1), beats: 1)
        let second = OriginalScoreRow(page: 0, box: .init(x: 0.1, y: 0.4, width: 0.8, height: 0.1), beats: 12)
        let score = OriginalScoreDocument(title: "弱起", pageCount: 1, numerator: 6, denominator: 8,
                                          startingBeat: 5, initialBPM: 80, rows: [first, second])
        try score.validate()
        #expect(try score.duration(of: second.id, bpm: 80) == 9)
        #expect(try score.phase(rowID: second.id, beat: 0) == 0)
    }
}
