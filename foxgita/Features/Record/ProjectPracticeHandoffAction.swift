import Foundation

enum ProjectPracticeHandoffAction {
    static func perform(
        projectId: UUID,
        store: PracticeStore,
        router: AppRouter,
        now: Date,
        calendar: Calendar
    ) throws {
        RecordAnalytics.projectPracticeCreateTapped(projectId: projectId.uuidString)
        let item: PracticeItem
        do {
            item = try store.createTodayPracticeItem(
                projectId: projectId,
                now: now,
                calendar: calendar
            )
        } catch {
            RecordAnalytics.projectPracticeCreated(
                projectId: projectId.uuidString,
                practiceItemId: "",
                result: "failure"
            )
            throw error
        }
        RecordAnalytics.projectPracticeCreated(
            projectId: projectId.uuidString,
            practiceItemId: item.id.uuidString,
            result: "success"
        )
        router.recordPath.append(.practiceDetail(itemId: item.id))
    }
}
