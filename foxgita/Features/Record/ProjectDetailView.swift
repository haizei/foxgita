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
    @Query(filter: #Predicate<PracticeItem> { $0.deletedAt == nil })
    private var practiceItems: [PracticeItem]
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
    }

    private var project: Project? { projects.first }

    private var snapshot: ProjectSnapshot? {
        project.map(ProjectRules.snapshot(from:))
    }

    private var allSnapshots: [PracticeItemSnapshot] {
        let items: [PracticeItem]
        if let profileId = project?.profileId {
            items = practiceItems.filter { $0.profileId == profileId }
        } else {
            items = practiceItems
        }
        return items.map(PracticeStore.snapshot(from:))
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
        ProjectPracticeStateHandoff.decide(
            project: snapshot,
            todayKey: PracticeDayKey.make(from: Date(), calendar: calendar),
            items: allSnapshots,
            completedItemIds: router.completedPracticeItemIds
        )
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
                            ProjectProgressStoryView(story: story)
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
                                    onPlaybackFailed: { showToast("无法播放") }
                                )
                            }
                            NextPracticeFocusCard(
                                decision: decision(for: snapshot),
                                showsAction: snapshot.status == .active,
                                onHandoff: { runHandoff(snapshot) },
                                onEditFocus: {
                                    focusDraft = snapshot.currentFocus
                                    showFocusEditor = true
                                }
                            )
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
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            RecordAnalytics.projectViewOpened(
                projectId: projectId.uuidString,
                hasEvidence: evidence != nil
            )
            if router.projectCreatedToast {
                showToast("项目已创建")
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

    private func runHandoff(_ snapshot: ProjectSnapshot) {
        guard !creatingTodayLock else { return }
        creatingTodayLock = true
        defer { creatingTodayLock = false }
        player.stop()
        do {
            try ProjectPracticeHandoffAction.perform(
                projectId: projectId,
                decision: decision(for: snapshot),
                store: store,
                router: router,
                now: Date(),
                calendar: calendar
            )
        } catch {
            showToast("创建失败，请重试")
        }
    }

    private func saveFocus() {
        do {
            try store.updateProjectFocus(id: projectId, currentFocus: focusDraft, now: Date())
            showFocusEditor = false
        } catch {
            showToast("操作失败，请重试")
        }
    }

    private func setPinned(_ id: UUID?) {
        do {
            try store.setPinnedProjectId(id)
        } catch {
            showToast("操作失败，请重试")
        }
    }

    private func setStatus(_ status: ProjectStatus) {
        do {
            try store.setProjectStatus(id: projectId, status: status, now: Date())
        } catch {
            showToast("操作失败，请重试")
        }
    }

    private func deleteProject() {
        do {
            try store.deleteProject(id: projectId, now: Date())
            if !router.recordPath.isEmpty {
                router.recordPath.removeLast()
            }
        } catch {
            showToast("删除失败，请重试")
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
