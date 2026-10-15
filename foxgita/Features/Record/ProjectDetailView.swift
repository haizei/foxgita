//
//  ProjectDetailView.swift
//  foxgita
//

import SwiftData
import SwiftUI

struct ProjectDetailView: View {
    let projectId: UUID

    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Query private var projects: [Project]
    @Query private var practiceItems: [PracticeItem]
    @Query(filter: #Predicate<LocalProfile> { $0.isActive == true })
    private var profiles: [LocalProfile]

    @State private var toast: String?
    @State private var player = AudioPlayerService()
    @State private var videoPlayURL: URL?
    @State private var creatingTodayLock = false
    @State private var showCompleteConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showFocusEditor = false
    @State private var focusDraft = ""

    private var calendar: Calendar { .current }

    init(projectId: UUID) {
        self.projectId = projectId
        _projects = Query(
            filter: #Predicate<Project> { $0.id == projectId && $0.deletedAt == nil }
        )
        _practiceItems = Query(
            filter: #Predicate<PracticeItem> { $0.deletedAt == nil && $0.projectId == projectId }
        )
    }

    private var project: Project? { projects.first }

    private var snapshot: ProjectSnapshot? {
        project.map(ProjectRules.snapshot(from:))
    }

    private var allSnapshots: [PracticeItemSnapshot] {
        practiceItems.map(PracticeStore.snapshot(from:))
    }

    private var evidence: LastPracticeEvidence? {
        LastPracticeEvidence.latest(projectId: projectId, items: allSnapshots)
    }

    private var story: ProjectProgressStory? {
        ProjectProgressStory.make(projectId: projectId, items: allSnapshots)
    }

    private var notePreview: [ProjectNoteEntry] {
        ProjectNoteProjection.preview(projectId: projectId, items: allSnapshots)
    }

    private var benchmark: AudioBenchmarkReadiness {
        AudioBenchmarkVersion.resolve(
            stageVersionItemId: snapshot?.stageVersionItemId,
            projectId: projectId,
            items: allSnapshots
        )
    }

    private var isPinned: Bool {
        profiles.first?.pinnedProjectId == projectId
    }

    private func decision(for snapshot: ProjectSnapshot) -> ProjectPracticeStateHandoff.Decision {
        ProjectPracticeStateHandoff.startDecision(project: snapshot)
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                header
                if let snapshot {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            identity(snapshot)
                            if snapshot.status != .active {
                                endedProjectCard(snapshot)
                            }
                            if let story {
                                ProjectProgressStoryView(story: story) { itemId in
                                    player.stop()
                                    router.recordPath.append(.practiceDetail(itemId: itemId))
                                }
                            } else {
                                Text("完成第一次练习后，这里会留下练习轨迹")
                                    .font(GitaFont.callout())
                                    .foregroundStyle(GitaTheme.textSecondary)
                            }
                            if let evidence {
                                LastPracticeEvidenceCard(
                                    evidence: evidence,
                                    benchmark: benchmark,
                                    player: player,
                                    onCompare: {
                                        player.stop()
                                        router.recordPath.append(.audioComparison(projectId: projectId))
                                    },
                                    onPlayVideo: { url in
                                        videoPlayURL = url
                                    },
                                    onPlaybackFailed: { showToast(String(localized: "无法播放")) }
                                )
                            }
                            if snapshot.status == .active {
                                NextPracticeFocusCard(
                                    decision: decision(for: snapshot),
                                    onHandoff: performHandoff,
                                    onEditFocus: {
                                        focusDraft = snapshot.currentFocus
                                        showFocusEditor = true
                                    }
                                )
                            }
                            if !notePreview.isEmpty {
                                ProjectNotePreviewSection(
                                    entries: notePreview,
                                    onOpenList: {
                                        player.stop()
                                        router.recordPath.append(.projectNotes(projectId: projectId))
                                    },
                                    onOpenItem: { itemId in
                                        player.stop()
                                        router.recordPath.append(.practiceDetail(itemId: itemId))
                                    }
                                )
                            } else if evidence != nil {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("我的笔记")
                                        .font(GitaFont.headline())
                                        .foregroundStyle(GitaTheme.textPrimary)
                                    Text("还没有练习笔记")
                                        .font(GitaFont.callout())
                                        .foregroundStyle(GitaTheme.textSecondary)
                                }
                            }
                        }
                        .padding(.horizontal, GitaTheme.pagePadding)
                        .padding(.bottom, 32)
                    }
                } else {
                    Text("项目不存在或已删除")
                        .font(GitaFont.body())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if let toast {
                VStack {
                    Spacer()
                    ToastBanner(text: toast)
                        .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            creatingTodayLock = false
            RecordAnalytics.projectViewOpened(
                projectId: projectId.uuidString,
                hasEvidence: evidence != nil
            )
            if router.projectCreatedToast {
                showToast(String(localized: "项目已创建"))
                router.projectCreatedToast = false
            }
        }
        .onDisappear {
            player.stop()
            videoPlayURL = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                player.stop()
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { videoPlayURL != nil },
            set: { if !$0 { videoPlayURL = nil } }
        )) {
            if let videoPlayURL {
                SystemVideoPlayer(url: videoPlayURL) {
                    self.videoPlayURL = nil
                }
                .ignoresSafeArea()
            }
        }
        .confirmationDialog("标记为已完成？", isPresented: $showCompleteConfirm, titleVisibility: .visible) {
            Button("完成") { setStatus(.completed) }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "删除项目不会删除已经发生的练习，这些练习会保留为独立练习。",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { deleteProject() }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showFocusEditor) {
            focusEditorSheet
        }
    }

    private func identity(_ project: ProjectSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.name)
                .font(GitaFont.largeTitle())
                .foregroundStyle(GitaTheme.textPrimary)
            let goal = ProjectSetupRules.trimmed(project.goal)
            if !goal.isEmpty {
                Text(project.goal)
                    .font(GitaFont.body())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func endedProjectCard(_ project: ProjectSnapshot) -> some View {
        let final = ProjectRules.versionSlot(
            itemId: project.finalVersionItemId,
            projectId: projectId,
            in: allSnapshots
        )
        return VStack(alignment: .leading, spacing: 12) {
            Text(project.status == .completed ? "项目已完成" : "项目已归档")
                .font(GitaFont.headline())
                .foregroundStyle(GitaTheme.textPrimary)
            if case .resolved(let item) = final, project.status == .completed {
                Button("回看最终版本 · \(item.title)") {
                    router.recordPath.append(.practiceDetail(itemId: item.id))
                }
                .font(GitaFont.callout(.semibold))
                .foregroundStyle(GitaTheme.brand500)
            } else {
                Text("可以回看已有的练习记录")
                    .font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            Button("重新开启项目") { setStatus(.active) }
                .font(GitaFont.callout(.semibold))
                .foregroundStyle(GitaTheme.brand500)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.categoryOrangeSoft)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
    }

    private var header: some View {
        HStack {
            Button {
                if !router.recordPath.isEmpty {
                    router.recordPath.removeLast()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(GitaFont.headline())
                    .foregroundStyle(GitaTheme.textPrimary)
                    .frame(minWidth: 44, alignment: .leading)
            }
            .accessibilityLabel("返回")

            Spacer(minLength: 0)

            Text("项目详情")
                .font(GitaFont.headline())
                .foregroundStyle(GitaTheme.textPrimary)

            Spacer(minLength: 0)

            if let snapshot {
                Menu {
                    Button("编辑") {
                        router.recordPath.append(.projectEdit(projectId: projectId))
                    }
                    if snapshot.status == .active {
                        if isPinned {
                            Button("取消固定") { setPinned(nil) }
                        } else {
                            Button("设为当前项目") { setPinned(projectId) }
                        }
                        Button("完成") { showCompleteConfirm = true }
                        Button("暂不练习") { setStatus(.archived) }
                    } else {
                        Button("重新开启") { setStatus(.active) }
                    }
                    Button("删除", role: .destructive) { showDeleteConfirm = true }
                } label: {
                    Text("•••")
                        .font(GitaFont.callout(.bold))
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(minWidth: 44, alignment: .trailing)
                }
                .accessibilityLabel("更多")
            } else {
                Color.clear.frame(minWidth: 44)
            }
        }
        .frame(minHeight: 56)
        .padding(.horizontal, GitaTheme.pagePadding)
    }

    private var focusEditorSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { showFocusEditor = false }
                    .font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(minWidth: 44, alignment: .leading)
                Spacer(minLength: 0)
                Text("项目当前重点")
                    .font(GitaFont.body(.bold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer(minLength: 0)
                Button("保存") { saveFocus() }
                    .font(GitaFont.callout(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .padding(.horizontal, GitaTheme.s24)
            .frame(height: 56)

            TextField("这次想练什么", text: $focusDraft, axis: .vertical)
                .font(GitaFont.callout())
                .foregroundStyle(GitaTheme.textPrimary)
                .tint(GitaTheme.brand500)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .frame(minHeight: 96, alignment: .topLeading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(GitaTheme.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: GitaTheme.radius12)
                        .stroke(GitaTheme.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))
                .padding(.horizontal, GitaTheme.s24)
                .onChange(of: focusDraft) { _, newValue in
                    let clamped = ProjectSetupRules.clamp(newValue, max: ProjectSetupRules.focusMax)
                    if clamped != newValue { focusDraft = clamped }
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(GitaTheme.bgDefault)
        .presentationDetents([.medium])
    }

    private func performHandoff() {
        guard !creatingTodayLock else { return }
        creatingTodayLock = true
        player.stop()
        do {
            try ProjectPracticeHandoffAction.perform(
                projectId: projectId,
                store: store,
                router: router,
                now: Date(),
                calendar: calendar
            )
        } catch {
            creatingTodayLock = false
            showToast(String(localized: "创建失败，请重试"))
        }
    }

    private func saveFocus() {
        do {
            try store.updateProjectFocus(id: projectId, currentFocus: focusDraft, now: Date())
            showFocusEditor = false
        } catch {
            showToast(String(localized: "操作失败，请重试"))
        }
    }

    private func setPinned(_ id: UUID?) {
        do {
            try store.setPinnedProjectId(id)
        } catch {
            showToast(String(localized: "操作失败，请重试"))
        }
    }

    private func setStatus(_ status: ProjectStatus) {
        do {
            try store.setProjectStatus(id: projectId, status: status, now: Date())
        } catch {
            showToast(String(localized: "操作失败，请重试"))
        }
    }

    private func deleteProject() {
        do {
            try store.deleteProject(id: projectId, now: Date())
            if !router.recordPath.isEmpty {
                router.recordPath.removeLast()
            }
        } catch {
            showToast(String(localized: "删除失败，请重试"))
        }
    }

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }
}
