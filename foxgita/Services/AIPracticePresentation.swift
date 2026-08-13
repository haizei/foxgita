import Foundation

enum AIPracticePresentation {
    static func isAIGenerated(subtitle: String) -> Bool {
        subtitle.hasPrefix("AI ·")
    }

    static func chords(fromSubtitle subtitle: String) -> [String] {
        guard isAIGenerated(subtitle: subtitle) else { return [] }
        let marker = "分钟"
        guard let range = subtitle.range(of: marker) else { return [] }
        let rest = subtitle[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard rest.hasPrefix("·") else { return [] }
        return rest.dropFirst()
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func stepParts(_ step: String) -> (title: String, minutes: Int?) {
        let pattern = /^(.+) · (\d+) 分钟$/
        if let match = step.wholeMatch(of: pattern), let minutes = Int(match.2) {
            return (String(match.1), minutes)
        }
        return (step, nil)
    }
}
