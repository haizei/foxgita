import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct ScoreSystemLayoutTests {
    @Test func conflictingCapoKeepsBothRowsAsAnEditableDraftWithoutChangingTheirPitches() throws {
        let first = try ScoreRecognitionDecoder.decode(Data(#"{"title":"Original","capo":0,"bars":[{"number":1,"events":[{"tick":0,"duration":960,"tones":[{"midi":40,"string":6,"fret":0}]}]}]}"#.utf8))
        let second = try ScoreRecognitionDecoder.decode(Data(#"{"title":"Original","capo":6,"bars":[{"number":1,"events":[{"tick":0,"duration":960,"tones":[{"midi":46,"string":6,"fret":0}]}]}]}"#.utf8))
        let merged = try ScoreSystemCombiner.combine([
            .init(page: 1, system: 1, region: .init(y: 0.2, height: 0.2), draft: first),
            .init(page: 1, system: 2, region: .init(y: 0.5, height: 0.2), draft: second)
        ])
        #expect(merged.score.bars.flatMap(\.events).flatMap(\.tones).map(\.midi) == [40, 46])
        #expect(merged.issues.contains { $0.field == "capo" && $0.page == 1 })
        #expect(!merged.isConfirmed)
        #expect(throws: ScoreValidationError.self) { try merged.score.validate() }
    }

    @Test func returningToTheInitialTempoAfterAnotherRowKeepsItsPlaybackTiming() throws {
        let systems = try [80, 90, 80].enumerated().map { index, bpm in
            let data = try JSONSerialization.data(withJSONObject: ["title": "Original", "tempo": ["bpm": bpm, "beatUnit": 4], "bars": [["number": index + 1, "events": [["tick": 0, "duration": 960, "tones": [["midi": 55]]]]]]])
            return ScoreRecognizedSystem(page: 1, system: index + 1, region: .fullPage, draft: try ScoreRecognitionDecoder.decode(data))
        }
        let merged = try ScoreSystemCombiner.combine(systems)
        #expect(merged.score.bars[2].tempo?.bpm == 80)
        #expect(abs((try merged.score.seconds(atTick: merged.score.totalTicks)) - 26.0 / 3.0) < 0.000001)
    }

    @Test func fiveSystemsKeepChordDiagramsLyricsAndNumberedMelodyTogether() {
        var lines = [Double](repeating: 0, count: 1400)
        var ink = lines
        for top in [330, 500, 715, 930, 1140] {
            for line in 0..<6 { lines[top + line * 9] = 0.8; ink[top + line * 9] = 0.8 }
            for row in (top - 50)..<(top - 5) { ink[row] = max(ink[row], 0.1) }
            for row in (top + 80)..<(top + (top == 330 ? 105 : 135)) { ink[row] = max(ink[row], 0.12) }
        }
        let regions = ScoreSystemLayout.regions(longLineCoverage: lines, inkCoverage: ink)
        #expect(regions.count == 5)
        guard regions.count == 5 else { return }
        for (region, top) in zip(regions, [330, 500, 715, 930, 1140]) {
            #expect(region.y * 1400 <= Double(top - 50))
            #expect((region.y + region.height) * 1400 >= Double(top + (top == 330 ? 105 : 135)))
        }
        for index in 1..<regions.count {
            #expect(abs(regions[index - 1].y + regions[index - 1].height - regions[index].y) < 0.000001)
        }
    }

    @Test func standardStaffAndBlankOrNonMusicalInputsAreHandledConservatively() {
        var rows = [Double](repeating: 0, count: 700)
        for top in [100, 400] { for line in 0..<5 { rows[top + line * 10] = 0.8 } }
        #expect(ScoreSystemLayout.regions(longLineCoverage: rows, inkCoverage: rows).count == 2)
        #expect(ScoreSystemLayout.regions(longLineCoverage: [], inkCoverage: []).isEmpty)
        #expect(ScoreSystemLayout.regions(longLineCoverage: [0.8, 0, 0.8], inkCoverage: [0, 0, 0]).isEmpty)
    }

    @Test func cropBoxesMapIntoTheOriginalPageAndRejectInvalidLocations() throws {
        let region = ScoreSystemRegion(x: 0.1, y: 0.4, width: 0.8, height: 0.2)
        let mapped = try #require(region.originalBox([0.25, 0.5, 0.5, 0.25]))
        for (actual, expected) in zip(mapped, [0.3, 0.5, 0.4, 0.05]) { #expect(abs(actual - expected) < 0.000001) }
        #expect(region.originalBox([0.9, 0, 0.4, 0.5]) == nil)
        #expect(region.originalBox(nil) == nil)
    }

    @Test func mergedSystemsPreserveOriginalPageAndRemapAllSourceLocations() throws {
        let data = Data(#"{"title":"Original","tempo":{"bpm":68,"beatUnit":4},"bars":[{"number":7,"source":{"page":1,"box":[0.1,0.2,0.4,0.3]},"events":[{"tick":0,"duration":960,"source":{"page":1,"box":[0.1,0.2,0.4,0.3]},"tones":[{"midi":55}]}]}],"warnings":[{"message":"review","page":1,"box":[0.1,0.2,0.4,0.3]}]}"#.utf8)
        let draft = try ScoreRecognitionDecoder.decode(data)
        let result = try ScoreSystemCombiner.combine([
            .init(page: 2, system: 1, region: .init(y: 0.2, height: 0.2), draft: draft),
            .init(page: 2, system: 2, region: .init(y: 0.5, height: 0.3), draft: draft)
        ])
        #expect(result.score.bars.count == 2)
        #expect(result.score.bars.map { $0.source?.page } == [2, 2])
        #expect(result.score.bars.map(\.number) == [7, 7])
        #expect(abs((result.score.bars[1].events[0].source?.box?[1] ?? 0) - 0.56) < 0.000001)
        #expect(result.issues.filter { $0.message == "review" }.allSatisfy { $0.page == 2 })
        #expect(!result.isConfirmed)
    }
}
