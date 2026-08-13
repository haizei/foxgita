import Foundation

struct AIPracticeDraft: Equatable {
    var title: String
    var category: PracticeCategory
    var targetMin: Int
    var steps: [String]
    var chords: [String]

    struct Raw: Decodable, Equatable {
        var title: String?
        var category: String?
        var targetMin: Int?
        var steps: [String]?
        var chords: [String]?
        var stepMinutes: [Int]?
    }

    var subtitleLine: String {
        if chords.isEmpty {
            return String(localized: "AI · \(targetMin) 分钟")
        }
        return String(localized: "AI · \(targetMin) 分钟 · \(chords.joined(separator: " · "))")
    }

    static func normalize(_ raw: Raw, fallbackCategory: PracticeCategory) -> AIPracticeDraft {
        let trimmed = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = trimmed.isEmpty ? String(localized: "未命名练习") : trimmed

        let category: PracticeCategory
        if let rawCat = raw.category, let parsed = PracticeCategory(rawValue: rawCat) {
            category = parsed
        } else {
            category = fallbackCategory
        }

        let minutes: Int
        if let value = raw.targetMin {
            minutes = min(60, max(1, value))
        } else {
            minutes = 10
        }

        var steps = (raw.steps ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if steps.isEmpty {
            steps = [String(localized: "新步骤")]
        } else if steps.count > 12 {
            steps = Array(steps.prefix(12))
        }

        if let stepMinutes = raw.stepMinutes {
            steps = steps.enumerated().map { index, step in
                guard index < stepMinutes.count, stepMinutes[index] >= 1 else { return step }
                return "\(step) · \(stepMinutes[index]) 分钟"
            }
        }

        let chords = (raw.chords ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return AIPracticeDraft(
            title: title,
            category: category,
            targetMin: minutes,
            steps: steps,
            chords: chords
        )
    }
}
