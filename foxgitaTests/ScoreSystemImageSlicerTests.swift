import Foundation
import Testing
import UIKit
@testable import foxgita

@MainActor struct ScoreSystemImageSlicerTests {
    static func twoSystemPage() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 500))
        return renderer.jpegData(withCompressionQuality: 0.95) { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 500))
            UIColor.black.setStroke(); context.cgContext.setLineWidth(1)
            for top in [120, 350] {
                for line in 0..<6 {
                    context.cgContext.move(to: CGPoint(x: 20, y: top + line * 8))
                    context.cgContext.addLine(to: CGPoint(x: 380, y: top + line * 8))
                }
            }
            context.cgContext.strokePath()
        }
    }

    @Test func realImagePixelsProduceTwoSystemsAndKeepOriginalPageIdentity() throws {
        let slices = ScoreSystemImageSlicer.slices(page: Self.twoSystemPage(), number: 3)
        #expect(slices.count == 2)
        guard slices.count == 2 else { return }
        #expect(slices.map(\.page) == [3, 3])
        #expect(slices.map(\.number) == [1, 2])
        #expect(slices.allSatisfy { $0.header != nil && $0.images.count == 2 })
        let source = try #require(UIImage(data: Self.twoSystemPage())?.cgImage)
        let image = try #require(UIImage(data: slices[1].image)?.cgImage)
        #expect(abs(Double(image.height) / Double(source.height) - slices[1].region.height) <= 1.0 / Double(source.height))
    }

    @Test func undecodableAndSingleSystemInputsKeepTheWholeOriginal() {
        let data = Data([1, 2, 3])
        let slices = ScoreSystemImageSlicer.slices(page: data, number: 1)
        #expect(slices.count == 1)
        #expect(slices[0].image == data)
        #expect(slices[0].region == .fullPage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_SOURCE_SCORE_PATH"] != nil))
    func suppliedPagePreviewHasFiveCompleteSystems() throws {
        #if targetEnvironment(simulator)
        let path = try #require(ProcessInfo.processInfo.environment["GITA_SOURCE_SCORE_PATH"])
        let selection = try ScoreImportSelection.images([Data(contentsOf: URL(fileURLWithPath: path))])
        let slices = ScoreSystemImageSlicer.slices(page: selection.pages[0], number: 1)
        #expect(slices.count == 5)
        let directory = URL(fileURLWithPath: "/tmp/gita-score-system-preview", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for slice in slices { try slice.image.write(to: directory.appendingPathComponent("system-\(slice.number).jpg")) }
        if let header = slices.first?.header { try header.write(to: directory.appendingPathComponent("header.jpg")) }
        try JSONEncoder().encode(slices.map(\.region)).write(to: directory.appendingPathComponent("regions.json"))
        #endif
    }
}
