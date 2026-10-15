import Foundation

struct ProjectProgressMilestone: Equatable, Identifiable {
    let id: UUID
    let dayKey: String
    let label: String
}

struct ProjectProgressStory: Equatable {
    static let disclaimer = String(localized: "根据已记录的练习 · 非完成度评分")

    let headline: String
    let milestones: [ProjectProgressMilestone]

    static func make(projectId: UUID, items: [PracticeItemSnapshot]) -> ProjectProgressStory? {
        let effective = items
            .filter { $0.projectId == projectId && PracticeItemRules.isEffective($0) }
            .sorted { $0.createdAt < $1.createdAt }
        guard !effective.isEmpty else { return nil }

        let selected: [PracticeItemSnapshot]
        if effective.count <= 3 {
            selected = effective
        } else {
            selected = [effective[0], effective[effective.count / 2], effective[effective.count - 1]]
        }
        let milestones = selected.map {
            ProjectProgressMilestone(id: $0.id, dayKey: $0.practiceDayKey, label: $0.title)
        }
        return ProjectProgressStory(headline: String(localized: "练习轨迹"), milestones: milestones)
    }
}
