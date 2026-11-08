import Foundation
import Testing
import UIKit
@testable import foxgita

@MainActor struct ScoreBarImageSlicerTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_HEADER_PAGE"] != nil))
    func suppliedTABAndTimeSignaturePrefixDoesNotBecomeAMeasure() throws {
        let path = try #require(ProcessInfo.processInfo.environment["GITA_HEADER_PAGE"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let page = try #require(ScoreImportSelection.images([data]).pages.first)
        let system = try #require(ScoreSystemImageSlicer.slices(page: page,number: 1,tabOnly: true).first)
        let slices = ScoreBarImageSlicer.slices(system: system,rejectExtendedStems: true)
        print("HEADER-BOUNDS", slices.map { [$0.region.x,$0.region.width] })
        #expect(slices.count == 5)
        #expect((slices.first?.region.x ?? 0) > 0.15)
        #expect(slices.map(\.number) == [1,2,3,4,5])
        #expect(try LocalTabReader.draft(pages: [page]).score.bars.count == 16)
        let oldSlices = ScoreBarImageSlicer.slices(system: system,rejectExtendedStems: true,includeHeaders: true)
        let oldBars = oldSlices.enumerated().map { index,slice in
            let r = slice.region
            return ScoreBar(number: index+1,events: [],source: .init(page: 1,box: [r.x,r.y,r.width,r.height]))
        }
        var old = RecognizedScoreDraft(score: .init(title: "旧草稿",bars: oldBars),issues: [],localReadings: [:])
        old.score.bars[1].events = [.init(tick: 0,duration: 3840,tones: [.init(midi: 64)])]
        let repaired = LocalTabReader.removingHeaderPanels(from: old,pages: [page])
        #expect(repaired.score.bars.count == 5)
        #expect(repaired.score.bars.first?.id == old.score.bars[1].id)
        #expect(repaired.score.bars.first?.events == old.score.bars[1].events)
        // Corrections in the header candidate are preserved for the user to resolve.
        old.score.bars[0].events = [.init(tick: 0,duration: 960,tones: [.init(midi: 60)])]
        #expect(LocalTabReader.removingHeaderPanels(from: old,pages: [page]).score == old.score)
    }

    @Test func narrowEmptyFirstMeasureWithoutTABHeaderIsPreserved() {
        let slices = ScoreBarImageSlicer.slices(system: Self.system(boundaries: [20,70,190,370,580],withStems: false),rejectExtendedStems: true)
        #expect(slices.count == 4)
        #expect(abs((slices.first?.region.x ?? 0) - (0.1 + 0.8 * 20 / 600)) < 0.003)
    }

    @Test func TABAlongsidePlayableRhythmMustNotBeDropped() throws {
        let base = Self.system(boundaries: [20,100,260,420,580],withStems: false)
        let original = try #require(UIImage(data: base.image))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        var system = base
        system.image = UIGraphicsImageRenderer(size: original.size,format: format).jpegData(withCompressionQuality: 0.98) { context in
            original.draw(at: .zero)
            let style: [NSAttributedString.Key:Any] = [.font: UIFont(name: "TimesNewRomanPSMT",size: 14)!, .foregroundColor: UIColor.black]
            for (text,y) in [("T",58),("A",75),("B",92)] {
                (text as NSString).draw(at: CGPoint(x: 45,y: y),withAttributes: style)
            }
            for y in [63,88] { ("4" as NSString).draw(at: CGPoint(x: 72,y: y),withAttributes: style) }
            UIColor.black.setFill(); context.fill(CGRect(x: 85,y: 85,width: 1,height: 45))
        }
        let slices = ScoreBarImageSlicer.slices(system: system,rejectExtendedStems: true)
        #expect(slices.count == 4)
    }

    private static func system(boundaries: [Int], withStems: Bool = true) -> ScoreSystemSlice {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 180), format: {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; return format
        }())
        let data = renderer.jpegData(withCompressionQuality: 0.98) { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 180))
            UIColor.black.setStroke(); context.cgContext.setLineWidth(1)
            for line in 0..<6 {
                context.cgContext.move(to: CGPoint(x: 20, y: 60 + line * 10))
                context.cgContext.addLine(to: CGPoint(x: 580, y: 60 + line * 10))
            }
            for x in boundaries {
                context.cgContext.move(to: CGPoint(x: x, y: 60))
                context.cgContext.addLine(to: CGPoint(x: x, y: 110))
            }
            if withStems {
                for x in stride(from: 55, through: 550, by: 35) {
                    context.cgContext.move(to: CGPoint(x: x, y: 82))
                    context.cgContext.addLine(to: CGPoint(x: x, y: 130))
                }
            }
            context.cgContext.strokePath()
            // Chord diagrams above and beat marks below must survive the crop height.
            context.cgContext.stroke(CGRect(x: 85, y: 15, width: 20, height: 25))
            context.cgContext.stroke(CGRect(x: 85, y: 150, width: 5, height: 15))
        }
        return .init(page: 3, number: 2, region: .init(x: 0.1, y: 0.2, width: 0.8, height: 0.3),
            image: data, header: Data([7]))
    }

    @Test func pairedNotationLocatesTheTabEvenWithBrokenLines() throws {
        let format=UIGraphicsImageRendererFormat();format.scale=1
        let data=UIGraphicsImageRenderer(size:.init(width:450,height:210),format:format).pngData { ctx in
            UIColor.white.setFill();ctx.fill(.init(x:0,y:0,width:450,height:210))
            UIColor.black.setFill()
            for y in [20,28,36,44,52,114,126,138,150,162,174] {
                ctx.fill(.init(x:15,y:y,width:420,height:1))
            }
            for x in [15,110,190,230,300,434] {ctx.fill(.init(x:x,y:20,width:1,height:33))}
            for x in [15,205,434] {ctx.fill(.init(x:x,y:114,width:1,height:61))}
            UIColor.white.setFill()
            for i in 0..<6 {
                for x in [75,165,285,375] {ctx.fill(.init(x:x+i,y:114+i*12,width:7,height:1))}
            }
        }
        let systems=ScoreSystemImageSlicer.slices(page:data,number:1,tabOnly:true)
        let system=try #require(systems.count==1 ? systems.first:nil)
        let bars=ScoreBarImageSlicer.slices(system:system,rejectExtendedStems:true)
        #expect(bars.count==2)
        #expect(abs((bars.first?.region.x ?? 0)*450-15)<2)
        #expect(abs((bars.last?.region.x ?? 0)*450-205)<2)
        #expect(system.region.y*210>52)
    }

    @Test func thickRepeatRuleIsNotRejectedAsArrowWings() throws {
        var input=Self.system(boundaries:[20,190,370,580],withStems:false)
        let image=try #require(UIImage(data:input.image))
        let format=UIGraphicsImageRendererFormat();format.scale=1
        input.image=UIGraphicsImageRenderer(size:.init(width:600,height:180),format:format)
            .jpegData(withCompressionQuality:0.98) { ctx in
                image.draw(at:.zero)
                UIColor.black.setFill()
                ctx.fill(.init(x:188,y:60,width:5,height:51))
            }
        let bars=ScoreBarImageSlicer.slices(system:input,rejectExtendedStems:true)
        #expect(bars.count==3)
        #expect(abs((bars[1].region.x-0.1)/0.8*600-190)<3)
    }

    @Test func fullStaffBarlinesSplitMeasuresWithoutCountingStems() throws {
        for boundaries in [[20, 190, 370, 580], [20, 130, 245, 350, 465, 580]] {
            let system = Self.system(boundaries: boundaries)
            let bars = ScoreBarImageSlicer.slices(system: system)
            #expect(bars.count == boundaries.count - 1)
            #expect(bars.map(\.number) == Array(1..<boundaries.count))
            #expect(bars.allSatisfy { $0.page == 3 && $0.system == 2 && $0.context == Data([7]) })
            #expect(bars.first?.id == "p3-s2-b1")
            for (index, bar) in bars.enumerated() {
                let crop = try #require(UIImage(data: bar.image)?.cgImage)
                #expect(crop.height == 180)
                #expect(abs(bar.region.x - (0.1 + 0.8 * Double(boundaries[index]) / 600)) < 0.003)
                #expect(bar.region.y == 0.2 && bar.region.height == 0.3)
                #expect(bar.cropRegion.x < bar.region.x)
                #expect(bar.cropRegion.x + bar.cropRegion.width > bar.region.x + bar.region.width)
                #expect(abs(Double(crop.width) / 600 * 0.8 - bar.cropRegion.width) < 0.001)
            }
        }
    }

    @Test func incompleteEdgesAndUndecodableImagesKeepTheOriginal() {
        let system = Self.system(boundaries: [190, 370])
        let bars = ScoreBarImageSlicer.slices(system: system)
        #expect(bars.count == 1)
        #expect(bars.first?.image == system.image)
        #expect(bars.first?.region == system.region)
        let invalid = ScoreSystemSlice(page: 1, number: 1, region: .fullPage, image: Data([1, 2]))
        #expect(ScoreBarImageSlicer.slices(system: invalid).first?.image == invalid.image)
    }

    @Test func doubleAndRepeatBarlinesFormOneMeasureBoundary() {
        for boundaries in [[20, 190, 198, 370, 580], [20, 28, 190, 198, 370, 378, 572, 580]] {
            let bars = ScoreBarImageSlicer.slices(system: Self.system(boundaries: boundaries))
            #expect(bars.count == 3)
            #expect(bars.map(\.number) == [1, 2, 3])
            #expect(bars.allSatisfy { $0.region.width > 0.15 })
            for (left, right) in zip(bars, bars.dropFirst()) {
                #expect(abs(left.region.x + left.region.width - right.region.x) < 0.0001)
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_BAR_PREVIEW_PATH"] != nil))
    func suppliedFirstSystemProducesFiveFullHeightCrops() throws {
        #if targetEnvironment(simulator)
        let path = try #require(ProcessInfo.processInfo.environment["GITA_BAR_PREVIEW_PATH"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let system = ScoreSystemSlice(page: 1, number: 1, region: .fullPage, image: data)
        let bars = ScoreBarImageSlicer.slices(system: system)
        #expect(bars.count == 5)
        let source = try #require(UIImage(data: data)?.cgImage)
        let directory = URL(fileURLWithPath: "/tmp/gita-score-bar-preview", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        struct Preview: Encodable {
            var id: String
            var page: Int
            var system: Int
            var number: Int
            var region: ScoreSystemRegion
            var cropRegion: ScoreSystemRegion
            var file: String
        }
        var manifest: [Preview] = []
        for bar in bars {
            let image = try #require(UIImage(data: bar.image)?.cgImage)
            #expect(image.height == source.height)
            let file = "bar-\(bar.number).jpg"
            try bar.image.write(to: directory.appendingPathComponent(file))
            manifest.append(.init(id: bar.id, page: bar.page, system: bar.system, number: bar.number,
                region: bar.region, cropRegion: bar.cropRegion, file: file))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
        #endif
    }
}
