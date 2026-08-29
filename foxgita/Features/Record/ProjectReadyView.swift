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
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    readyHeader
                    successHero
                }
                .padding(.horizontal, GitaTheme.pagePadding)
                .background(GitaTheme.bgSurface)

                VStack(spacing: 16) {
                    if let project {
                        createdProjectCard(project)
                    }
                    if let error {
                        Text(error)
                            .font(GitaFont.callout())
                            .foregroundStyle(GitaTheme.brand500)
                    }
                    Spacer(minLength: 0)
                    Button(action: createToday) {
                        Text("创建今天的练习项")
                            .font(GitaFont.body())
                            .foregroundStyle(GitaTheme.brandOn)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(GitaTheme.brand500)
                            .clipShape(Capsule())
                            .opacity(creatingLock || project == nil ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(creatingLock || project == nil)
                    Button("先返回项目列表") { returnToList() }
                        .font(GitaFont.callout())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .padding(.vertical, 10)
                }
                .padding(.horizontal, GitaTheme.pagePadding)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
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

    private var readyHeader: some View {
        HStack {
            Color.clear.frame(width: 28, height: 22)
            Spacer(minLength: 0)
            Text("项目已创建")
                .font(GitaFont.title())
                .foregroundStyle(GitaTheme.textPrimary)
            Spacer(minLength: 0)
            Button("完成", action: returnToList)
                .font(GitaFont.callout())
                .foregroundStyle(GitaTheme.brand500)
        }
        .frame(height: 56)
    }

    private var successHero: some View {
        VStack(spacing: 8) {
            Text("✓")
                .font(GitaFont.title())
                .foregroundStyle(GitaTheme.brand500)
                .frame(width: 64, height: 64)
                .background(GitaTheme.brand50)
                .clipShape(Circle())
            Text("长期目标已经有了方向")
                .font(GitaFont.headline())
                .foregroundStyle(GitaTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text("接下来从一次真实练习开始")
                .font(GitaFont.callout())
                .foregroundStyle(GitaTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func createdProjectCard(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(project.name)
                    .font(GitaFont.title())
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer(minLength: 0)
                if ProjectSetupRules.showsReadyStage(project.stageRaw) {
                    Text(project.stageRaw)
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(GitaTheme.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius8))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("完成目标")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.brand500)
                Text(project.goal)
                    .font(GitaFont.body())
                    .foregroundStyle(GitaTheme.textPrimary)
            }
            if ProjectSetupRules.showsReadyFocus(project.currentFocus) {
                GitaTheme.borderSubtle
                    .frame(height: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("第一次练什么")
                        .font(GitaFont.callout())
                        .foregroundStyle(GitaTheme.brand500)
                    Text(project.currentFocus)
                        .font(GitaFont.body())
                        .foregroundStyle(GitaTheme.textPrimary)
                    Text("会作为今天练习项的初始关注点")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GitaTheme.brand50)
                .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius24))
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
            creatingLock = false
            RecordAnalytics.projectPracticeCreated(
                projectId: project.id.uuidString,
                practiceItemId: "",
                result: "failure"
            )
            self.error = String(localized: "创建失败，请重试")
        }
    }
}
