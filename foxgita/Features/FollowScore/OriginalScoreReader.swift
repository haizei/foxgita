import Foundation
import CoreGraphics
import ImageIO
import Vision

nonisolated enum OriginalScoreReadingError: Error, LocalizedError {
    case unreadablePage(Int)
    var errorDescription: String? {
        switch self {
        case .unreadablePage(let page):
            "第 \(page) 页暂未读清完整谱行和小节线。请换用清晰、正向的六线谱或五线谱图片/PDF 后重试。"
        }
    }
}

/// Reads layout and measure boundaries locally. It does not claim note-level OMR.
nonisolated enum OriginalScoreReader {
    static func read(pages: [Data], document: OriginalScoreDocument) async throws -> OriginalScoreDocument {
        let worker = Task.detached(priority: .userInitiated) { try analyze(pages: pages, document: document) }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
    }

    private static func analyze(pages: [Data], document: OriginalScoreDocument) throws -> OriginalScoreDocument {
        guard pages.count == document.pageCount, !pages.isEmpty else { throw OriginalScoreError.invalidDocument }
        var result = document
        result.rows = []
        result.manuallyOrdered = false
        result.startingBeat = 0
        var measureCount = 0
        let meter = try readMeter(pages[0])
        if let meter { result.numerator = meter.0; result.denominator = meter.1 }
        for (page, data) in pages.enumerated() {
            try Task.checkCancellation()
            let tab = ScoreSystemImageSlicer.slices(page: data, number: page + 1, tabOnly: true)
            let isTab = tab.contains { $0.region != .fullPage }
            let systems = isTab ? tab : ScoreSystemImageSlicer.slices(page: data, number: page + 1)
            for system in systems {
                try Task.checkCancellation()
                let bars = ScoreBarImageSlicer.slices(system: system, rejectExtendedStems: isTab)
                // The slicer's whole-system fallback carries no measured boundaries.
                // Never turn detection failure into an invented one-measure row.
                guard !bars.isEmpty, bars.allSatisfy({ $0.region.width < $0.cropRegion.width }) else {
                    throw OriginalScoreReadingError.unreadablePage(page + 1)
                }
                let left = bars.map(\.region.x).min()!
                let right = bars.map { $0.region.x + $0.region.width }.max()!
                result.rows.append(.init(page: page, box: .init(x: left, y: system.region.y,
                    width: right - left, height: system.region.height), beats: Double(bars.count * result.numerator)))
                measureCount += bars.count
            }
        }
        try Task.checkCancellation()
        result.sortRows()
        let meterNote = meter == nil ? "拍号沿用 \(result.numerator)/\(result.denominator)" : "拍号 \(result.numerator)/\(result.denominator)"
        result.readingNote = "自动读取 \(result.rows.count) 行、\(measureCount) 小节 · \(meterNote) · 按整小节匀速跟线"
        try result.validate()
        return result
    }

    private static func readMeter(_ data: Data) throws -> (Int, Int)? {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(data: data).perform([request])
        try Task.checkCancellation()
        let observations = (request.results ?? []).filter { $0.boundingBox.midY > 0.6 }
        for item in observations {
            guard let text = item.topCandidates(1).first?.string else { continue }
            let pattern = #"(?<!\d)([2-9]|1[0-2])\s*[/／]\s*(2|4|8|16)(?!\d)"#
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            let values = text[range].replacingOccurrences(of: "／", with: "/").split(separator: "/").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if values.count == 2 { return (values[0], values[1]) }
        }
        // Printed time signatures often have vertically stacked digits, not a slash.
        let numberPattern = try NSRegularExpression(pattern: #"(?<!\d)([2-9]|1[0-2]|16)(?!\d)"#)
        let digits: [(Int, CGRect)] = observations.flatMap { item -> [(Int, CGRect)] in
            guard let candidate = item.topCandidates(1).first else { return [] }
            let text = candidate.string
            return numberPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> (Int, CGRect)? in
                guard let range = Range(match.range, in: text), let value = Int(text[range]),
                      let box = try? candidate.boundingBox(for: range)?.boundingBox,
                      box.midX < 0.35 else { return nil }
                return (value, box)
            }
        }
        for (upper, box) in digits where (2...12).contains(upper) {
            for (lower, lowerBox) in digits where [2,4,8,16].contains(lower) {
                let gap = box.minY - lowerBox.maxY
                if gap >= -box.height * 0.3, gap < box.height,
                   abs(box.midX - lowerBox.midX) < max(box.width, lowerBox.width) * 0.45 {
                    return (upper, lower)
                }
            }
        }
        return try readKeyAdjacentMeter(data, observations: observations)
    }

    /// Small printed fractions are often merged with “1=G”. Read each digit
    /// separately only after finding a real horizontal fraction rule beside the key.
    private static func readKeyAdjacentMeter(_ data: Data, observations: [VNRecognizedTextObservation]) throws -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        for observation in observations {
            try Task.checkCancellation()
            guard let candidate = observation.topCandidates(1).first,
                  let range = candidate.string.range(of: #"1\s*[=＝]\s*[A-Ga-g](?:[#b♯♭])?"#, options: .regularExpression),
                  let anchor = try? candidate.boundingBox(for: range)?.boundingBox else { continue }
            let height = anchor.height * Double(image.height)
            let areaRect = CGRect(x: anchor.maxX * Double(image.width),
                y: (1 - anchor.midY) * Double(image.height) - height, width: height * 2, height: height * 2)
                .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let area = image.cropping(to: areaRect), area.width >= 8, area.height >= 8, area.width <= 256, area.height <= 256 else { continue }
            var pixels = [UInt8](repeating: 255, count: area.width * area.height)
            let rendered = pixels.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: area.width, height: area.height,
                    bitsPerComponent: 8, bytesPerRow: area.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
                context.draw(area, in: CGRect(x: 0, y: 0, width: area.width, height: area.height))
                return true
            }
            guard rendered else { continue }
            var rule = (length: 0, y: 0, left: 0)
            for y in (area.height * 3 / 10)..<(area.height * 7 / 10) {
                var start = 0, run = 0
                for x in 0..<area.width {
                    if pixels[y * area.width + x] < 170 {
                        if run == 0 { start = x }; run += 1
                        if run > rule.length { rule = (run, y, start) }
                    } else { run = 0 }
                }
            }
            guard rule.length >= 4, rule.y > 2, rule.y + 3 < area.height else { continue }
            let left = max(0, rule.left - 3), right = min(area.width, rule.left + rule.length + 3)
            guard let upper = area.cropping(to: CGRect(x: left, y: 0, width: right - left, height: rule.y - 1)),
                  let lower = area.cropping(to: CGRect(x: left, y: rule.y + 2, width: right - left, height: area.height - rule.y - 2)),
                  let numerator = try readMeterDigit(upper), (2...12).contains(numerator),
                  let denominator = try readMeterDigit(lower), [2,4,8,16].contains(denominator) else { continue }
            return (numerator, denominator)
        }
        return nil
    }

    private static func readMeterDigit(_ image: CGImage) throws -> Int? {
        try Task.checkCancellation()
        guard let context = CGContext(data: nil, width: image.width * 6, height: image.height * 6,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width * 6, height: image.height * 6))
        guard let enlarged = context.makeImage() else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.recognitionLanguages = ["en-US"]; request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: enlarged).perform([request])
        try Task.checkCancellation()
        guard let text = request.results?.first?.topCandidates(1).first?.string else { return nil }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
