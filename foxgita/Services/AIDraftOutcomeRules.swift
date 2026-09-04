import Foundation

enum AIDraftOutcomeRules {
    static func normalizedSteps(_ steps: [String]) -> [String] {
        steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func confirm(
        originalTitle: String,
        originalMinutes: Int,
        originalSteps: [String],
        editTitle: String,
        editMinutes: Int,
        editSteps: [String]
    ) -> AIDraftOutcome {
        let sameTitle =
            originalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            == editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let sameMinutes = originalMinutes == editMinutes
        let sameSteps = normalizedSteps(originalSteps) == normalizedSteps(editSteps)
        return sameTitle && sameMinutes && sameSteps ? .accepted : .edited
    }
}
