import Foundation

struct PhotoPracticeStep: Identifiable, Equatable {
    let id: UUID
    var title: String
    var detail: String
    var minutes: Int

    init(id: UUID = UUID(), title: String, detail: String = "", minutes: Int) {
        self.id = id
        self.title = title
        self.detail = detail
        self.minutes = min(60, max(1, minutes))
    }

    init(storedText: String, fallbackMinutes: Int) {
        let parts = AIPracticePresentation.stepParts(storedText)
        let pieces = parts.title.split(separator: "：", maxSplits: 1).map(String.init)
        self.init(
            title: pieces.first ?? "",
            detail: pieces.count > 1 ? pieces[1] : "",
            minutes: parts.minutes ?? fallbackMinutes
        )
    }

    var storedText: String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = description.isEmpty ? name : "\(name)：\(description)"
        return "\(content) · \(minutes) 分钟"
    }

    static func fromDraft(_ draft: AIPracticeDraft) -> [PhotoPracticeStep] {
        let source = Array(draft.steps.prefix(12))
        let parsed = source.map(AIPracticePresentation.stepParts)
        let explicitMinutes = parsed.compactMap(\.minutes).reduce(0, +)
        let missingCount = parsed.filter { $0.minutes == nil }.count
        let remaining = max(missingCount, draft.targetMin - explicitMinutes)
        let base = missingCount == 0 ? 1 : max(1, remaining / missingCount)
        var extra = missingCount == 0 ? 0 : max(0, remaining - base * missingCount)
        return source.enumerated().map { index, text in
            let fallback = base + (parsed[index].minutes == nil && extra > 0 ? 1 : 0)
            if parsed[index].minutes == nil && extra > 0 { extra -= 1 }
            return PhotoPracticeStep(storedText: text, fallbackMinutes: fallback)
        }
    }

    static func valid(_ steps: [PhotoPracticeStep]) -> Bool {
        !steps.isEmpty && steps.count <= 12 && steps.allSatisfy {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...60).contains($0.minutes)
        }
    }
}
