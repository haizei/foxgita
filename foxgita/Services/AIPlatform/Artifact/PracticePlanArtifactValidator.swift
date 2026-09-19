import Foundation

enum PracticePlanArtifactValidator {
    static func clampBudget(_ minutes: Int) -> Int {
        min(60, max(5, minutes))
    }

    static func cap(_ raw: AIPracticeDraft.Raw, budget: Int) -> AIPracticeDraft.Raw {
        let budget = clampBudget(budget)
        var raw = raw
        let target = min(raw.targetMin ?? budget, budget)
        raw.targetMin = min(60, max(1, target))
        guard let minutes = raw.stepMinutes, let steps = raw.steps else { return raw }
        var pairs: [(String, Int)] = []
        for index in steps.indices {
            let text = steps[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = index < minutes.count ? minutes[index] : 0
            if !text.isEmpty && value >= 1 { pairs.append((text, value)) }
        }
        var sum = pairs.reduce(0) { $0 + $1.1 }
        while sum > budget && !pairs.isEmpty { sum -= pairs.removeLast().1 }
        raw.steps = pairs.map(\.0)
        raw.stepMinutes = pairs.map(\.1)
        return raw
    }
}
