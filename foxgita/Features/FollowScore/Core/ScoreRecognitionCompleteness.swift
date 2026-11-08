import Foundation

/// Verified expected playback structure, including repeat expansion, independent
/// of the model's own output. This does not certify individual notes or rhythms.
nonisolated enum ScoreRecognitionCompleteness {
    static func issues(for score: ScoreDocument, expectedBars: Int, expectedQuarterBeats: Int? = nil) -> [ScoreRecognitionIssue] {
        guard (1...2_000).contains(expectedBars), expectedQuarterBeats.map({ $0 > 0 }) ?? true else {
            return [.init(field: "source-expectation", message: "请先从原谱确认有效的小节数和时长基准。")]
        }
        var issues: [ScoreRecognitionIssue] = []
        if score.bars.count != expectedBars {
            issues.append(.init(field: "bar-count", message: "原谱预期\(expectedBars)个小节，识谱返回\(score.bars.count)个，请核对缺失或合并的小节。"))
        }
        if let expectedQuarterBeats {
            let actual = score.bars.reduce(0.0) { $0 + Double($1.numerator) * 4 / Double($1.denominator) }
            if !actual.isFinite || abs(actual - Double(expectedQuarterBeats)) > 0.000001 {
                issues.append(.init(field: "score-duration", message: "原谱预期\(expectedQuarterBeats)个四分音符拍，识谱小节合计\(actual)拍，请核对拍号及小节完整性。"))
            }
        }
        return issues
    }
}
