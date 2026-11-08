import Foundation

nonisolated struct ScoreSystemRegion: Codable, Equatable, Sendable {
    var x: Double = 0
    var y: Double
    var width: Double = 1
    var height: Double

    static let fullPage = Self(y: 0, height: 1)

    func originalBox(_ box: [Double]?) -> [Double]? {
        guard let box = ScoreSourceLocation(page: 1, box: box).validBox else { return nil }
        return [x + width * box[0], y + height * box[1], width * box[2], height * box[3]]
    }
}

nonisolated enum ScoreSystemLayout {
    /// Both projections are measured from the top of the normalized source page.
    static func regions(longLineCoverage: [Double], inkCoverage: [Double]) -> [ScoreSystemRegion] {
        guard longLineCoverage.count == inkCoverage.count, longLineCoverage.count >= 100 else { return [] }
        let height = longLineCoverage.count
        var lineCenters: [Int] = []
        var row = 0
        while row < height {
            guard longLineCoverage[row] >= 0.45 else { row += 1; continue }
            let start = row
            while row < height, longLineCoverage[row] >= 0.45 { row += 1 }
            if row - start <= 6 { lineCenters.append((start + row - 1) / 2) }
        }
        var staves: [(top: Int, bottom: Int)] = []
        var index = 0
        while index + 4 < lineCenters.count {
            let gap = lineCenters[index + 1] - lineCenters[index]
            guard (3...40).contains(gap) else { index += 1; continue }
            var count = 2
            while index + count < lineCenters.count, count < 6,
                  abs(Double(lineCenters[index + count] - lineCenters[index + count - 1] - gap)) <= max(1.5, Double(gap) * 0.25) {
                count += 1
            }
            if count >= 5 {
                staves.append((lineCenters[index], lineCenters[index + count - 1]))
                index += count
            } else { index += 1 }
        }
        guard staves.count > 1, staves.count <= 30 else { return [] }
        let first = staves[0]
        var boundaries = [max(0, first.top - Int(Double(first.bottom - first.top) * 1.5))]
        for pair in zip(staves, staves.dropFirst()) {
            let distance = pair.1.top - pair.0.bottom
            guard distance > pair.0.bottom - pair.0.top else { return [] }
            let lower = pair.0.bottom + Int(Double(distance) * 0.35)
            let upper = pair.0.bottom + Int(Double(distance) * 0.82)
            var cursor = lower, best = lower..<lower
            while cursor < upper {
                if inkCoverage[cursor] > 0.025 { cursor += 1; continue }
                let start = cursor
                while cursor < upper, inkCoverage[cursor] <= 0.025 { cursor += 1 }
                if cursor - start > best.count { best = start..<cursor }
            }
            guard best.count >= 3 else { return [] }
            boundaries.append((best.lowerBound + best.upperBound) / 2)
        }
        boundaries.append(height)
        return zip(boundaries, boundaries.dropFirst()).map {
            ScoreSystemRegion(y: Double($0.0) / Double(height), height: Double($0.1 - $0.0) / Double(height))
        }
    }
}

struct ScoreRecognizedSystem: Sendable {
    var page: Int
    var system: Int
    var region: ScoreSystemRegion
    var draft: RecognizedScoreDraft
}

enum ScoreSystemCombiner {
    static func combine(_ systems: [ScoreRecognizedSystem]) throws -> RecognizedScoreDraft {
        guard var result = systems.first?.draft else { throw ScoreRecognitionError.malformed }
        result.score.bars = []; result.issues = []; result.isConfirmed = false
        for (index, system) in systems.enumerated() {
            let score = system.draft.score
            guard system.page > 0, system.system > 0,
                  score.ticksPerQuarter == result.score.ticksPerQuarter else {
                throw ScoreRecognitionError.malformed
            }
            for (field, differs) in [("capo", score.capo != result.score.capo), ("tuning", score.tuning != result.score.tuning)] where differs {
                result.issues.append(.init(field: field,
                    message: "第\(system.page)页第\(system.system)行的\(field == "capo" ? "变调夹" : "调弦")与首段不同；已保留本行原音高和弦品，请对照原谱统一核对。",
                    page: system.page, box: [system.region.x, system.region.y, system.region.width, system.region.height]))
            }
            var bars = score.bars
            for i in bars.indices {
                bars[i].source = .init(page: system.page, box: system.region.originalBox(bars[i].source?.box))
                for j in bars[i].events.indices {
                    bars[i].events[j].source = .init(page: system.page, box: system.region.originalBox(bars[i].events[j].source?.box))
                }
            }
            if index > 0, !bars.isEmpty, bars[0].tempo == nil { bars[0].tempo = score.tempo }
            result.score.bars += bars
            result.issues += system.draft.issues.map {
                var issue = $0; issue.page = system.page; issue.box = system.region.originalBox(issue.box); return issue
            }
        }
        guard result.score.bars.count <= 2_000 else { throw ScoreRecognitionError.tooLarge }
        if systems.count > 1 {
            result.issues.append(.init(field: "layout", message: "曲谱由多个谱行合并，请核对小节编号、跨行延音和反复关系。"))
        }
        return result
    }
}
