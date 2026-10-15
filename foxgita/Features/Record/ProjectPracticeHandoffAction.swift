import Foundation

enum ProjectPracticeHandoffAction {
    static func perform(
        projectId: UUID,
        decision: ProjectPracticeStateHandoff.Decision,
        store: PracticeStore,
        router: AppRouter,
        now: Date,
        calendar: Calendar
    ) throws {
        let opened: PracticeStore.TodayPracticeOpen
        do {
            opened = try store.openTodayPractice(
                projectId: projectId,
                now: now,
                calendar: calendar,
                completedItemIds: router.completedPracticeItemIds
            )
        } catch {
            if case .resume = decision.action {
                throw error
            }
            RecordAnalytics.projectPracticeCreated(
                projectId: projectId.uuidString,
                practiceItemId: "",
                result: "failure"
            )
            throw error
        }
        if opened.created {
            RecordAnalytics.projectPracticeCreateTapped(projectId: projectId.uuidString)
            RecordAnalytics.projectPracticeCreated(
                projectId: projectId.uuidString,
                practiceItemId: opened.item.id.uuidString,
                result: "success"
            )
        }
        router.recordPath.append(.practiceDetail(itemId: opened.item.id))
    }
}
