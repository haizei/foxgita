import Foundation
import Testing
import UIKit
@testable import foxgita

@MainActor struct OriginalScoreReaderTests {
    @Test func readsRowsAndMeasureCountsWithoutManualMarks() async throws {
        let page = OriginalScoreUITestPage.data
        let input = OriginalScoreDocument(title: "自动读取", pageCount: 1, initialBPM: 92)
        let result = try await OriginalScoreReader.read(pages: [page], document: input)
        #expect(result.rows.count == 4)
        #expect(result.rows.allSatisfy { $0.beats == 16 && $0.box.isValid && $0.page == 0 })
        #expect(result.initialBPM == 92)
        #expect(result.totalBeats == 64)
        #expect(result.readingNote?.contains("4 行") == true)
        try result.validate()
    }

    @Test func readsStackedSixSixteenthMeterInsteadOfInheritingFourFour() async throws {
        let source = try #require(UIImage(data: OriginalScoreUITestPage.data))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let page = UIGraphicsImageRenderer(size: source.size, format: format).jpegData(withCompressionQuality: 0.95) { context in
            source.draw(at: .zero)
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 115))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 28), .foregroundColor: UIColor.black]
            ("6" as NSString).draw(at: CGPoint(x: 65, y: 18), withAttributes: attributes)
            ("16" as NSString).draw(at: CGPoint(x: 57, y: 50), withAttributes: attributes)
        }
        let result = try await OriginalScoreReader.read(pages: [page], document: .init(title: "竖排拍号", pageCount: 1))
        #expect(result.numerator == 6)
        #expect(result.denominator == 16)
        #expect(result.totalBeats == 96)
    }

    @Test func keyWithoutAFractionKeepsTheExplicitInheritedMeter() async throws {
        let source = try #require(UIImage(data: OriginalScoreUITestPage.data))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let page = UIGraphicsImageRenderer(size: source.size, format: format).jpegData(withCompressionQuality: 0.95) { context in
            source.draw(at: .zero)
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 115))
            ("1=G" as NSString).draw(at: CGPoint(x: 40, y: 25), withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black])
        }
        let result = try await OriginalScoreReader.read(pages: [page], document: .init(title: "没有拍号", pageCount: 1, numerator: 6, denominator: 8))
        #expect(result.numerator == 6 && result.denominator == 8)
        #expect(result.totalBeats == 96)
        #expect(result.readingNote?.contains("拍号沿用 6/8") == true)
    }

    @Test func blankAndUnmeasuredPagesNeverBecomeInventedOneBarRows() async throws {
        let page = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 900)).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 900))
        }
        await #expect(throws: OriginalScoreReadingError.self) {
            try await OriginalScoreReader.read(pages: [page], document: .init(title: "空白", pageCount: 1))
        }
        await #expect(throws: OriginalScoreReadingError.self) {
            try await OriginalScoreReader.read(pages: [ScoreSystemImageSlicerTests.twoSystemPage()], document: .init(title: "没有小节线", pageCount: 1))
        }
        await #expect(throws: OriginalScoreReadingError.self) {
            try await OriginalScoreReader.read(pages: [OriginalScoreUITestPage.data, page], document: .init(title: "缺页", pageCount: 2))
        }
    }

    @Test func cancelledReadingDoesNotReturnAPublishableDocument() async {
        let task = Task {
            try await OriginalScoreReader.read(pages: [OriginalScoreUITestPage.data], document: .init(title: "取消", pageCount: 1))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_ORIGINAL_SCORE_PAGE"] != nil))
    func readsSuppliedQingTianPageWithoutMarking() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["GITA_ORIGINAL_SCORE_PAGE"])
        let selection = try ScoreImportSelection.images([Data(contentsOf: URL(fileURLWithPath: path))])
        let result = try await OriginalScoreReader.read(pages: selection.pages, document: .init(title: "晴天", pageCount: 1))
        print("AUTO_SCORE_RESULT rows=\(result.rows.count) beats=\(result.totalBeats) meter=\(result.numerator)/\(result.denominator)")
        #expect(result.rows.count == 4)
        #expect(result.totalBeats == 64)
        #expect(result.numerator == 4 && result.denominator == 4)
        if ProcessInfo.processInfo.environment["GITA_ORIGINAL_SCORE_METER_REQUIRED"] == "1" {
            #expect(result.readingNote?.contains("沿用") == false)
        }
    }
}
