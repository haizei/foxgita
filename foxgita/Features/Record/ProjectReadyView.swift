import SwiftData
import SwiftUI

struct ProjectReadyView: View {
    let projectId: UUID

    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @Query private var projects: [Project]
    @State private var creatingLock = false
    @State private var error: String?

    private var calendar: Calendar { .current }

    init(projectId: UUID) {
        self.projectId = projectId
        _projects = Query(
            filter: #Predicate<Project> { $0.id == projectId && $0.deletedAt == nil }
        )
    }

    private var project: Project? { projects.first }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(alignment: .leading, spacing: 16) {
                Button("关闭") { returnToList() }
                Text("项目已创建")
                    .font(GitaFont.title())
                if let project {
                    Text(project.name)
                        .font(GitaFont.body(.bold))
                        .foregroundStyle(GitaTheme.textPrimary)
                    Text(project.goal)
                        .font(GitaFont.callout())
                        .foregroundStyle(GitaTheme.textSecondary)
                    if ProjectSetupRules.showsReadyFocus(project.currentFocus) {
                        Text(project.currentFocus)
                            .font(GitaFont.callout())
                            .foregroundStyle(GitaTheme.textPrimary)
                    }
                }
                if let error {
                    Text(error).foregroundStyle(GitaTheme.brand500)
                }
                Button("创建今天的练习项") { createToday() }
                    .disabled(creatingLock || project == nil)
                Button("返回项目列表") { returnToList() }
                    .foregroundStyle(GitaTheme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(GitaTheme.pagePadding)
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if let project {
                RecordAnalytics.projectReadyViewed(
                    projectId: project.id.uuidString,
                    hasFocus: ProjectSetupRules.hasFocus(project.currentFocus)
                )
            }
        }
    }

    private func returnToList() {
        RecordAnalytics.projectReadyActionClicked(action: "return_projects")
        if !router.recordPath.isEmpty {
            router.recordPath.removeLast()
        }
    }

    private func createToday() {
        guard !creatingLock, let project else { return }
        creatingLock = true
        defer { creatingLock = false }
        RecordAnalytics.projectReadyActionClicked(action: "create_practice")
        RecordAnalytics.projectPracticeCreateTapped(projectId: project.id.uuidString)
        do {
            let item = try store.createTodayPracticeItem(
                projectId: project.id,
                now: Date(),
                calendar: calendar
            )
            RecordAnalytics.projectPracticeCreated(
                projectId: project.id.uuidString,
                practiceItemId: item.id.uuidString,
                result: "success"
            )
            let elapsed = Int((Date().timeIntervalSince(project.createdAt) * 1000).rounded())
            RecordAnalytics.projectFirstPracticeCreated(
                projectId: project.id.uuidString,
                practiceItemId: item.id.uuidString,
                elapsedFromProjectCreation: elapsed
            )
            router.replaceLastRecordRoute(.practiceDetail(itemId: item.id))
        } catch {
            RecordAnalytics.projectPracticeCreated(
                projectId: project.id.uuidString,
                practiceItemId: "",
                result: "failure"
            )
            self.error = String(localized: "创建失败，请重试")
        }
    }
}
