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
                    .font(GitaFont.headline())
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer(minLength: 8)
                Button("查看全部 ›", action: onOpenList)
                    .font(GitaFont.caption(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
            }
            ForEach(entries) { entry in
                Button {
                    onOpenItem(entry.itemId)
                } label: {
                    HStack(spacing: 12) {
                        Text(ProgressFirstFormat.monthDay(entry.dayKey))
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)
                            .frame(width: 62, alignment: .leading)
                        Rectangle()
                            .fill(GitaTheme.borderSubtle)
                            .frame(width: 1, height: 22)
                        Text(entry.body)
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(GitaTheme.textTertiary)
                    }
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if entry.id != entries.last?.id {
                    Divider().overlay(GitaTheme.borderSubtle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                if let project {
                    Text(project.name)
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                    Text("共 \(entries.count) 条练习笔记")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .padding(.top, 4)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if entries.isEmpty {
                            Text("还没有练习笔记")
                                .font(GitaFont.callout())
                                .foregroundStyle(GitaTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 48)
                        }
                        ForEach(entries) { entry in
                            noteRow(entry)
                            Divider().overlay(GitaTheme.borderSubtle)
                        }
                        if !entries.isEmpty {
                            Label(ProjectNoteProjection.footer.replacingOccurrences(of: "ⓘ ", with: ""), systemImage: "info.circle")
                                .font(GitaFont.caption())
                                .foregroundStyle(GitaTheme.textSecondary)
                                .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, GitaTheme.pagePadding)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background(PageBackground())
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private var header: some View {
        HStack {
            Button {
                if !router.recordPath.isEmpty { router.recordPath.removeLast() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(GitaFont.headline())
                    .foregroundStyle(GitaTheme.textPrimary)
                    .frame(minWidth: 44, alignment: .leading)
            }
            .accessibilityLabel("返回")
            Spacer(minLength: 0)
            Text("我的笔记")
                .font(GitaFont.headline())
                .foregroundStyle(GitaTheme.textPrimary)
                .accessibilityIdentifier("project-notes.title")
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44)
        }
        .frame(minHeight: 56)
        .padding(.horizontal, GitaTheme.pagePadding)
    }

    private func noteRow(_ entry: ProjectNoteEntry) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(ProgressFirstFormat.monthDay(entry.dayKey))
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
                .frame(width: 62, alignment: .leading)
            Rectangle()
                .fill(GitaTheme.borderSubtle)
                .frame(width: 1)
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.title)
                    .font(GitaFont.body(.semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Text(entry.body)
                    .font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    if entry.hasRecording {
                        Text("▶ 有录音")
                            .font(GitaFont.caption(.medium))
                            .foregroundStyle(GitaTheme.brand500)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(GitaTheme.brand50)
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                    Button("查看练习记录 ›") {
                        router.recordPath.append(.practiceDetail(itemId: entry.itemId))
                    }
                    .font(GitaFont.caption(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
                }
                .frame(minHeight: 30)
            }
        }
        .padding(.vertical, 18)
    }
}
