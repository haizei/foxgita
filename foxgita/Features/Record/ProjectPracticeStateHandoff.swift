import Foundation

enum ProjectPracticeStateHandoff {
    enum Stage: Equatable {
        case notStarted
        case resume(PracticeItemSnapshot)
        case createAnother(PracticeItemSnapshot)
    }

    enum Action: Equatable {
        case createNew(title: String)
        case resume(UUID)
        case createAnother(title: String, completedItemId: UUID)
    }

    struct Decision: Equatable {
        let buttonLabel: String
        let focusTitle: String
        let instruction: String
        let stage: Stage
        let action: Action
    }

    static func startDecision(project: ProjectSnapshot) -> Decision {
        let focus = project.currentFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        return Decision(
            buttonLabel: String(localized: "开始这项练习"),
            focusTitle: focus.isEmpty ? String(localized: "尚未设置当前重点") : focus,
            instruction: focus.isEmpty
                ? String(localized: "可先设置项目当前重点")
                : String(localized: "创建一条新的今日练习"),
            stage: .notStarted,
            action: .createNew(title: project.practiceTitle)
        )
    }

    static func stage(
        projectId: UUID,
        todayKey: String,
        in items: [PracticeItemSnapshot],
        completedItemIds: Set<UUID>
    ) -> Stage {
        let todayItems = items.filter {
            !$0.isDeleted && $0.projectId == projectId && $0.practiceDayKey == todayKey
        }.sorted { $0.createdAt > $1.createdAt }

        guard let latestToday = todayItems.first else {
            return .notStarted
        }
        if completedItemIds.contains(latestToday.id) {
            return .createAnother(latestToday)
        }
        return .resume(latestToday)
    }

    static func decide(
        project: ProjectSnapshot,
        todayKey: String,
        items: [PracticeItemSnapshot],
        completedItemIds: Set<UUID>
    ) -> Decision {
        let focusTitle = project.practiceTitle
        let stage = stage(
            projectId: project.id,
            todayKey: todayKey,
            in: items,
            completedItemIds: completedItemIds
        )
        switch stage {
        case .notStarted:
            return Decision(
                buttonLabel: String(localized: "开始今天的练习"),
                focusTitle: focusTitle,
                instruction: String(localized: "用当前重点开始今天的练习"),
                stage: stage,
                action: .createNew(title: focusTitle)
            )
        case .resume(let item):
            return Decision(
                buttonLabel: String(localized: "继续这次练习"),
                focusTitle: focusTitle,
                instruction: String(localized: "今天这条还没完成，接着练，不会新建空白练习"),
                stage: stage,
                action: .resume(item.id)
            )
        case .createAnother(let item):
            return Decision(
                buttonLabel: String(localized: "再练一次"),
                focusTitle: focusTitle,
                instruction: String(localized: "今天这条已经完成，再练会另开一条"),
                stage: stage,
                action: .createAnother(title: focusTitle, completedItemId: item.id)
            )
        }
    }
}
