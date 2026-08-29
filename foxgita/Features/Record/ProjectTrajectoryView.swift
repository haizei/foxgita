import SwiftData
import SwiftUI

struct ProjectTrajectoryView: View {
    let projectId: UUID

    @Environment(AppRouter.self) private var router
    @Query private var projects: [Project]
    @Query(filter: #Predicate<PracticeItem> { $0.deletedAt == nil })
    private var practiceItems: [PracticeItem]

    private var calendar: Calendar { .current }

    init(projectId: UUID) {
        self.projectId = projectId
        _projects = Query(
            filter: #Predicate<Project> { $0.id == projectId && $0.deletedAt == nil }
        )
    }

    private var project: Project? { projects.first }

    private var allSnapshots: [PracticeItemSnapshot] {
        let items: [PracticeItem]
        if let profileId = project?.profileId {
            items = practiceItems.filter { $0.profileId == profileId }
        } else {
            items = practiceItems
        }
        return items.map(PracticeStore.snapshot(from:))
    }

    private var trajectory: [PracticeItemSnapshot] {
        ProjectRules.associatedEffectiveItems(projectId: projectId, in: allSnapshots)
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                header
                if trajectory.isEmpty {
                    Text("还没有练习")
                        .font(GitaFont.body())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        trajectoryList
                            .padding(.horizontal, GitaTheme.pagePadding)
                            .padding(.bottom, 32)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: popIfProjectGone)
        .onChange(of: projects.count) { _, count in
            if count == 0, router.recordPath.last == .projectTrajectory(projectId: projectId) {
                router.recordPath.removeLast()
            }
        }
    }

    private var header: some View {
        HStack {
            Button("返回") {
                if !router.recordPath.isEmpty {
                    router.recordPath.removeLast()
                }
            }
            .font(GitaFont.callout())
            .foregroundStyle(GitaTheme.textSecondary)
            .frame(minWidth: 44, alignment: .leading)

            Spacer(minLength: 0)

            Text("项目练习轨迹")
                .font(GitaFont.headline())
                .foregroundStyle(GitaTheme.textPrimary)

            Spacer(minLength: 0)

            Color.clear.frame(minWidth: 44)
        }
        .frame(minHeight: 56)
        .padding(.horizontal, GitaTheme.pagePadding)
    }

    private var trajectoryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(trajectory.enumerated()), id: \.element.id) { index, item in
                Button {
                    router.recordPath.append(.practiceDetail(itemId: item.id))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(GitaFont.body(.bold))
                                .foregroundStyle(GitaTheme.textPrimary)
                                .multilineTextAlignment(.leading)
                            Text(
                                "\(RecordTimelineRules.dayTitle(dayKey: item.practiceDayKey, now: Date(), calendar: calendar)) · \(RecordMinutes.display(fromSeconds: item.durationSeconds)) 分钟"
                            )
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GitaTheme.iconSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < trajectory.count - 1 {
                    Divider()
                        .overlay(GitaTheme.borderSubtle)
                        .padding(.leading, 16)
                }
            }
        }
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
    }

    private func popIfProjectGone() {
        if projects.first == nil, router.recordPath.last == .projectTrajectory(projectId: projectId) {
            router.recordPath.removeLast()
        }
    }
}
