import Foundation

enum ProjectPracticeScope: Equatable {
    case segmented
    case connected
    case complete

    var phrase: String {
        switch self {
        case .segmented: return String(localized: "分段练")
        case .connected: return String(localized: "连贯弹")
        case .complete: return String(localized: "完整弹一遍")
        }
    }

    static func classify(_ text: String) -> ProjectPracticeScope? {
        let complete = ["完整", "整首", "跟唱摸底", "录音对比"]
        let connected = ["串联", "连贯", "提速", "爬格子"]
        let segmented = ["分段", "小节", "副歌专项", "慢练", "和弦转换"]
        if complete.contains(where: { text.contains($0) }) { return .complete }
        if connected.contains(where: { text.contains($0) }) { return .connected }
        if text.contains("弹唱") { return .complete }
        if segmented.contains(where: { text.contains($0) }) { return .segmented }
        return nil
    }
}

struct ProjectProgressMilestone: Equatable, Identifiable {
    let id: UUID
    let dayKey: String
    let label: String
    let scope: ProjectPracticeScope?
}

struct ProjectProgressStory: Equatable {
    static let disclaimer = String(localized: "根据已记录的练习范围 · 非完成度评分")
    static let emptyMessage = String(localized: "完成第一次练习以生成轨迹")

    let headline: String
    let milestones: [ProjectProgressMilestone]

    static func make(projectId: UUID, items: [PracticeItemSnapshot]) -> ProjectProgressStory? {
        let effective = items
            .filter { $0.projectId == projectId && PracticeItemRules.isEffective($0) }
            .sorted { $0.createdAt < $1.createdAt }
        guard !effective.isEmpty else { return nil }

        var groups: [(item: PracticeItemSnapshot, scope: ProjectPracticeScope)] = []
        var lastScope: ProjectPracticeScope?
        for item in effective {
            let text = [item.title, item.subtitle, item.note].joined(separator: " ")
            guard let scope = ProjectPracticeScope.classify(text) else { continue }
            if scope != lastScope {
                groups.append((item, scope))
                lastScope = scope
            }
        }

        if groups.isEmpty, let first = effective.first {
            let label = displayLabel(title: first.title, fallback: first.title)
            return ProjectProgressStory(
                headline: label,
                milestones: [
                    ProjectProgressMilestone(id: first.id, dayKey: first.practiceDayKey, label: label, scope: nil)
                ]
            )
        }

        var picked = groups
        if picked.count > 3 {
            let middle = picked[picked.count / 2]
            var reduced = [picked[0], middle, picked[picked.count - 1]]
            var seen = Set<UUID>()
            reduced = reduced.filter { seen.insert($0.item.id).inserted }
            picked = reduced
        }

        let milestones = picked.map { pair in
            ProjectProgressMilestone(
                id: pair.item.id,
                dayKey: pair.item.practiceDayKey,
                label: displayLabel(title: pair.item.title, fallback: pair.scope.phrase),
                scope: pair.scope
            )
        }
        return ProjectProgressStory(headline: headline(for: milestones), milestones: milestones)
    }

    private static func displayLabel(title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func headline(for milestones: [ProjectProgressMilestone]) -> String {
        guard let first = milestones.first?.scope else {
            return milestones.first?.label ?? ""
        }
        guard let last = milestones.last?.scope, milestones.count > 1, first != last else {
            return first.phrase
        }
        return String(localized: "从\(first.phrase)，到\(last.phrase)")
    }
}
