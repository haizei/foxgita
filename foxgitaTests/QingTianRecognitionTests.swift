import Foundation
import Testing
import UIKit
@testable import foxgita

@MainActor struct QingTianRecognitionTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_QINGTIAN_PAGE"] != nil))
    func legacyFullChordCandidatesUpgradeWithoutTouchingReviewedBars() throws {
        let path = try #require(ProcessInfo.processInfo.environment["GITA_QINGTIAN_PAGE"])
        let page = try #require(ScoreImportSelection.images([try Data(contentsOf: URL(fileURLWithPath: path))]).pages.first)
        let fresh = try LocalTabReader.draft(pages: [page])
        let diagrams = TabDiagramReader.diagrams(page: page)
        var old = fresh
        old.localRecognitionVersion = nil
        for index in old.score.bars.indices {
            let id = old.score.bars[index].id
            var reading = try #require(old.localReadings?[id])
            for a in reading.attacks.indices {
                reading.attacks[a].strumRange = nil
                reading.attacks[a].hammerEvidence = nil
                if let diagram = diagrams.first(where: { $0.box == reading.attacks[a].diagramBox }),
                   reading.attacks[a].marks == ["↑"] || reading.attacks[a].marks == ["↓"] {
                    reading.attacks[a].diagramBinding = diagram.resolved(reading.attacks[a].marks)
                }
            }
            old.localReadings?[id] = reading
            old.score.bars[index].events = reading.recognizedEvents(tuning: old.score.tuning,capo: 0,page: 1)
        }
        #expect(old.score.bars.filter { old.reviewState(for: $0) == .recognized }.count == 2)
        let upgraded = old.refreshingUneditedBars(from: fresh)
        #expect(upgraded.updated == 14)
        #expect(upgraded.draft.score.bars.map(\.id) == old.score.bars.map(\.id))
        #expect(upgraded.draft.score.bars.allSatisfy { upgraded.draft.reviewState(for: $0) == .recognized })
        #expect(!upgraded.draft.needsLocalRecognitionUpgrade)
        old.acknowledgeReview(of: [old.score.bars[4].id])
        #expect(old.refreshingUneditedBars(from: fresh).draft.score.bars[4] == old.score.bars[4])
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_QINGTIAN_PAGE"] != nil))
    func arrowMergedIntoRhythmStemDoesNotProveAStringRange() throws {
        let path = try #require(ProcessInfo.processInfo.environment["GITA_QINGTIAN_PAGE"])
        let page = try #require(ScoreImportSelection.images([try Data(contentsOf: URL(fileURLWithPath: path))]).pages.first)
        let slices = ScoreSystemImageSlicer.slices(page: page,number: 1,tabOnly: true).flatMap {
            ScoreBarImageSlicer.slices(system: $0,rejectExtendedStems: true)
        }
        var slice = try #require(slices.dropFirst(4).first)
        let reading = LocalTabReader.read(slice)
        let original = try #require(reading.attacks.first)
        let range = try #require(original.strumRange)
        #expect(range.crossedStrings == [3,4,5,6])
        let image = try #require(UIImage(data: slice.image))
        let x = (range.box[0]+range.box[2]/2-slice.cropRegion.x)/slice.cropRegion.width*image.size.width
        let top = (range.box[1]-slice.cropRegion.y)/slice.cropRegion.height*image.size.height
        let bottom = (range.box[1]+range.box[3]-slice.cropRegion.y)/slice.cropRegion.height*image.size.height
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let changed = UIGraphicsImageRenderer(size: image.size,format: format).image { context in
            image.draw(at: .zero)
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(.init(x: x-1,y: top,width: 2,height: bottom-top+CGFloat(range.staffSpacing)))
        }
        slice.image = try #require(changed.pngData())
        let corrupted = LocalTabReader.read(slice)
        let sameColumn = corrupted.attacks.filter { attack in
            guard let box = attack.box else { return false }
            return abs(box[0]+box[2]/2-(range.box[0]+range.box[2]/2)) < 0.003
        }
        #expect(sameColumn.allSatisfy { $0.strumRange?.crossedStrings == nil })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_QINGTIAN_PAGE"] != nil))
    func clearPrintedRangesAndHammerPairsNeedNoPerBarConfirmation() throws {
        let path = try #require(ProcessInfo.processInfo.environment["GITA_QINGTIAN_PAGE"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let page = try #require(ScoreImportSelection.images([data]).pages.first)
        let draft = try LocalTabReader.draft(pages: [page])
        #expect(draft.score.bars.count == 16)
        #expect(draft.score.bars.allSatisfy { draft.reviewState(for: $0) == .recognized })
        #expect(draft.reviewGroups.isEmpty)
        #expect(draft.reviewedBars == nil)
        #expect(!draft.isConfirmed)
        for bar in draft.score.bars.dropFirst(4) {
            let reading = try #require(draft.localReadings?[bar.id])
            for (index,attack) in reading.attacks.enumerated() {
                let shortSecond = [5,10,12,14,16].contains(bar.number) && index == 1
                let strings = index == 0 ? [3,4,5,6] : shortSecond ? [4,5] : [1,2,3,4]
                let range = try #require(attack.strumRange)
                #expect(range.crossedStrings == strings)
                #expect(range.isLocated(in: attack.box))
                #expect(bar.events[index].tones.compactMap(\.string) == strings)
                #expect(bar.events[index].tones.count == strings.count)
            }
        }
        for number in [1,3] {
            let bar = draft.score.bars[number-1]
            let reading = try #require(draft.localReadings?[bar.id])
            let attack = reading.attacks[5]
            #expect(attack.hammerEvidence?.matches(attack,next: reading.attacks[6]) == true)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_QINGTIAN_PAGE"] != nil))
    func hammerOnLabelDoesNotBecomeAnExtraThirdStringNote() throws {
        let path = try #require(ProcessInfo.processInfo.environment["GITA_QINGTIAN_PAGE"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let page = try #require(ScoreImportSelection.images([data]).pages.first)
        let draft = try LocalTabReader.draft(pages: [page])
        let expected = [["x4"],["x3"],["x2"],["x3"],["x5"],["4:0"],["4:2"],["x2"],["x3"]]
        for number in [1,3] {
            let bar = draft.score.bars[number-1]
            let reading = try #require(draft.localReadings?[bar.id])
            #expect(reading.attacks.map(\.marks) == expected)
            #expect(bar.events.count == 9)
            #expect(bar.events.allSatisfy { $0.tones.count == 1 })
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_QINGTIAN_PAGE"] != nil))
    func printedStrumDirectionsAndBeamsAreRetainedWithoutBoundaryAttacks() throws {
        let path = try #require(ProcessInfo.processInfo.environment["GITA_QINGTIAN_PAGE"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let page = try #require(ScoreImportSelection.images([data]).pages.first)
        let draft = try LocalTabReader.draft(pages: [page])
        #expect(draft.score.bars.count == 16)
        #expect(draft.score.bars.allSatisfy(draft.canReview))
        #expect(draft.score.bars.map { $0.events.count } == [9,8,9,10,11,11,10,12,10,12,10,11,10,12,10,11])
        let expected: [(Int,[Int],[String])] = [
            (5,[2,2,2,1,1,1,1,2,2,1,1],["↑","↑","↑","↑","↓","↑","↓","↑","↑","↑","↓"]),
            (6,[4,2,1,1,1,1,1,1,2,1,1],["↑","↑","↑","↓","↑","↓","↑","↓","↑","↑","↓"]),
            (7,[4,2,1,1,1,1,2,2,1,1],["↑","↑","↑","↓","↑","↓","↑","↑","↑","↓"])
        ]
        for (number,lengths,marks) in expected {
            let bar = draft.score.bars[number-1]
            let reading = try #require(draft.localReadings?[bar.id])
            #expect(reading.problem == nil)
            #expect(reading.attacks.map(\.length) == lengths)
            #expect(reading.attacks.map(\.marks) == marks.map { [$0] })
            #expect(bar.events.count == lengths.count)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_QINGTIAN_PAGE"] != nil))
    func printedOpenStringsAreNotLostAboveTheFirstTwoSystems() throws {
        let path = try #require(ProcessInfo.processInfo.environment["GITA_QINGTIAN_PAGE"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let page = try #require(ScoreImportSelection.images([data]).pages.first)
        let diagrams = TabDiagramReader.diagrams(page: page)
        #expect(diagrams.count == 32)
        // Literal transcriptions of the supplied printed diagrams, treble to bass.
        for (index, frets) in [(0,[0,3,0,2,2,0]), (1,[0,3,0,2,3,-1]),
                               (2,[3,0,0,0,2,3]), (6,[0,0,0,2,2,0]),
                               (9,[3,3,0,0,2,3]), (10,[2,3,2,0,-1,-1])] {
            #expect(diagrams[index].frets == frets)
        }
    }
}
