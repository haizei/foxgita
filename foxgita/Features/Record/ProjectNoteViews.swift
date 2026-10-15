import SwiftData
import SwiftUI

struct ProjectNotePreviewSection: View {
    let entries: [ProjectNoteEntry]
    let onOpenList: () -> Void
    let onOpenItem: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("我的笔记")
                    .font(GitaFont.body(.semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer(minLength: 8)
                Button(action: onOpenList) {
                    Text("查看全部 ›")
                        .font(GitaFont.caption(.semibold))
                        .foregroundStyle(GitaTheme.brand500)
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    Button {
                        onOpenItem(entry.itemId)
                    } label: {
                        HStack(spacing: 10) {
                            Text(ProgressFirstFormat.monthDay(entry.dayKey))
                                .font(GitaFont.caption())
                                .foregroundStyle(GitaTheme.textSecondary)
                                .frame(minWidth: 64, alignment: .leading)
                            Rectangle()
                                .fill(GitaTheme.brand500)
                                .frame(width: 3, height: 28)
                                .clipShape(Capsule())
                            Text(entry.body)
                                .font(GitaFont.callout())
                                .foregroundStyle(GitaTheme.textPrimary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(GitaTheme.textTertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if entry.id != entries.last?.id {
                        Divider().overlay(GitaTheme.borderSubtle)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
    }
}

struct ProjectNotesListView: View {
    let projectId: UUID

    @Environment(AppRouter.self) private var router
    @Query private var projects: [Project]
    @Query private var practiceItems: [PracticeItem]

    init(projectId: UUID) {
        self.projectId = projectId
        _projects = Query(filter: #Predicate<Project> { $0.id == projectId && $0.deletedAt == nil })
        _practiceItems = Query(
            filter: #Predicate<PracticeItem> { $0.deletedAt == nil && $0.projectId == projectId }
        )
    }

    private var project: Project? { projects.first }

    private var entries: [ProjectNoteEntry] {
        ProjectNoteProjection.entries(
            projectId: projectId,
            items: practiceItems.map(PracticeStore.snapshot(from:))
        )
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let project {
                            Text(project.name)
                                .font(GitaFont.title())
                                .foregroundStyle(GitaTheme.textPrimary)
                            Text("共 \(entries.count) 条练习笔记")
                                .font(GitaFont.caption())
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                        ForEach(entries) { entry in
                            noteRow(entry)
                        }
                        Text(ProjectNoteProjection.footer)
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, GitaTheme.pagePadding)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
    }

    private var header: some View {
        HStack {
            Button("返回") {
                if !router.recordPath.isEmpty { router.recordPath.removeLast() }
            }
            .font(GitaFont.callout())
            .foregroundStyle(GitaTheme.textSecondary)
            .frame(minWidth: 44, alignment: .leading)
            Spacer(minLength: 0)
            Text("我的笔记")
                .font(GitaFont.headline())
                .foregroundStyle(GitaTheme.textPrimary)
            Spacer(minLength: 0)
            Color.clear.frame(minWidth: 44)
        }
        .frame(minHeight: 56)
        .padding(.horizontal, GitaTheme.pagePadding)
    }

    private func noteRow(_ entry: ProjectNoteEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ProgressFirstFormat.monthDay(entry.dayKey))
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
            Text(entry.title)
                .font(GitaFont.body(.bold))
                .foregroundStyle(GitaTheme.textPrimary)
            Text(entry.body)
                .font(GitaFont.body())
                .foregroundStyle(GitaTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if entry.hasRecording {
                Text("▶ 有录音")
                    .font(GitaFont.caption(.medium))
                    .foregroundStyle(GitaTheme.brand500)
            }
            Button {
                router.recordPath.append(.practiceDetail(itemId: entry.itemId))
            } label: {
                Text("查看练习记录 ›")
                    .font(GitaFont.callout(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
    }
}
