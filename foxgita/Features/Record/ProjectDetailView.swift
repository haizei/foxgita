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

    private var evidence: PracticeItemSnapshot? {
        ProjectRules.lastEvidence(projectId: projectId, in: allSnapshots)
    }

    private var trajectory: [PracticeItemSnapshot] {
        ProjectRules.associatedEffectiveItems(projectId: projectId, in: allSnapshots)
    }

    private var totalSeconds: Int {
        ProjectRules.totalSeconds(projectId: projectId, in: allSnapshots)
    }

    private var isPinned: Bool {
        profiles.first?.pinnedProjectId == projectId
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                header
                if let snapshot {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            identitySection(snapshot)
                            evidenceSection
                            if !snapshot.currentFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                focusSection(snapshot.currentFocus.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if snapshot.status == .active {
                                createTodayButton
                            }
                            totalsAndTrajectory
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
                    ToastBanner(text: toast).padding(.bottom, 40)
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
        }
        .onDisappear {
            player.stop()
            videoPlayURL = nil
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
                    Text("更多")
                        .font(GitaFont.callout())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(minWidth: 44, alignment: .trailing)
                }
            } else {
                Color.clear.frame(minWidth: 44)
            }
        }
        .frame(minHeight: 56)
        .padding(.horizontal, GitaTheme.pagePadding)
    }

    private func identitySection(_ project: ProjectSnapshot) -> some View {
        let stage = project.stageRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            Text(project.name)
                .font(GitaFont.title())
                .foregroundStyle(GitaTheme.textPrimary)
            Text(project.goal)
                .font(GitaFont.body())
                .foregroundStyle(GitaTheme.textSecondary)
            if !stage.isEmpty {
                Text(stage)
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("上次练到这里")
                .font(GitaFont.body(.semibold))
                .foregroundStyle(GitaTheme.textPrimary)

            if let evidence {
                evidenceBody(evidence)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("还没有练习")
                        .font(GitaFont.body(.bold))
                        .foregroundStyle(GitaTheme.textPrimary)
                    Text("创建今天的练习项，留下这个项目的第一条记录")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(GitaTheme.bgSubtle)
                .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
            }
        }
    }

    @ViewBuilder
    private func evidenceBody(_ item: PracticeItemSnapshot) -> some View {
        let note = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 10) {
            if item.recordingCount > 0 {
                Button {
                    playNewestRecording(of: item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: player.playingId == newestRecordingId(of: item) ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(GitaTheme.brand500)
                            .frame(width: 28, height: 28)
                            .background(GitaTheme.brand50)
                            .clipShape(Circle())
                        Text("播放最近一条媒体")
                            .font(GitaFont.body(.semibold))
                            .foregroundStyle(GitaTheme.textPrimary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if !note.isEmpty {
                Text(note)
                    .font(GitaFont.body())
                    .foregroundStyle(GitaTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(GitaFont.body(.bold))
                        .foregroundStyle(GitaTheme.textPrimary)
                    Text(
                        "\(RecordTimelineRules.dayTitle(dayKey: item.practiceDayKey, now: Date(), calendar: calendar)) · \(RecordMinutes.display(fromSeconds: item.durationSeconds)) 分钟"
                    )
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
    }

    private func focusSection(_ focus: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这次练什么")
                .font(GitaFont.body(.semibold))
                .foregroundStyle(GitaTheme.textPrimary)
            Text(focus)
                .font(GitaFont.body())
                .foregroundStyle(GitaTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var createTodayButton: some View {
        Button {
            createTodayPractice()
        } label: {
            Text("创建今天的练习项")
                .font(GitaFont.callout(.bold))
                .foregroundStyle(GitaTheme.brandOn)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(GitaTheme.brand500)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var totalsAndTrajectory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("累计 \(RecordMinutes.display(fromSeconds: totalSeconds)) 分钟")
                .font(GitaFont.body(.semibold))
                .foregroundStyle(GitaTheme.textPrimary)

            if !trajectory.isEmpty {
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
        }
    }

    private func createTodayPractice() {
        guard !creatingTodayLock else { return }
        creatingTodayLock = true
        defer { creatingTodayLock = false }
        RecordAnalytics.projectPracticeCreateTapped(projectId: projectId.uuidString)
        do {
            let item = try store.createTodayPracticeItem(projectId: projectId, now: Date(), calendar: calendar)
            RecordAnalytics.projectPracticeCreated(
                projectId: projectId.uuidString,
                practiceItemId: item.id.uuidString,
                result: "success"
            )
            router.recordPath.append(.practiceDetail(itemId: item.id))
        } catch {
            RecordAnalytics.projectPracticeCreated(
                projectId: projectId.uuidString,
                practiceItemId: "",
                result: "failure"
            )
            showToast(String(localized: "创建失败，请重试"))
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

    private func liveItem(id: UUID) -> PracticeItem? {
        practiceItems.first { $0.id == id }
    }

    private func newestRecording(of item: PracticeItemSnapshot) -> RecordingRef? {
        liveItem(id: item.id)?
            .recordings
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    private func newestRecordingId(of item: PracticeItemSnapshot) -> String? {
        newestRecording(of: item)?.id
    }

    private func playNewestRecording(of item: PracticeItemSnapshot) {
        guard item.recordingCount > 0, let rec = newestRecording(of: item) else {
            showToast(String(localized: "无法播放"))
            return
        }
        guard RecordingStore.fileExists(fileName: rec.fileName) else {
            showToast(String(localized: "文件不存在或已被移除"))
            return
        }
        if MediaReviewMedia.isVideo(fileName: rec.fileName) {
            player.stop()
            do {
                try AudioSessionCoordinator.shared.acquire(.playback)
                videoPlayURL = rec.fileURL
            } catch {
                showToast(String(localized: "无法播放"))
            }
        } else {
            videoPlayURL = nil
            let playingIdBefore = player.playingId
            player.toggle(url: rec.fileURL, id: rec.id)
            if RecordPlayback.startFailed(
                playingIdBefore: playingIdBefore,
                intendedId: rec.id,
                playingIdAfter: player.playingId
            ) {
                showToast(String(localized: "无法播放"))
            }
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
