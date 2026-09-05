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
    @State private var showGoalEditor = false
    @State private var showStagePicker = false
    @State private var goalDraft = ""
    @State private var pickerKind: ProjectVersionKind?
    @State private var versionWriteLock = false
    @State private var pendingClearKind: ProjectVersionKind?

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

    private var totalSeconds: Int {
        ProjectRules.totalSeconds(projectId: projectId, in: allSnapshots)
    }

    private var isPinned: Bool {
        profiles.first?.pinnedProjectId == projectId
    }

    private var hasEffectivePractice: Bool {
        !ProjectRules.associatedEffectiveItems(projectId: projectId, in: allSnapshots).isEmpty
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                header
                if let snapshot {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if hasEffectivePractice {
                                identitySection(snapshot)
                                setupLaterCard(snapshot)
                                evidenceSection
                                if ProjectRules.showsThisTimeCard(snapshot) {
                                    thisTimeSection(snapshot)
                                }
                                versionSlotsSection(snapshot)
                                trajectoryLink
                                cumulativeLabel
                            } else {
                                emptyIdentityCard(snapshot)
                                setupLaterCard(snapshot)
                                firstPracticeCard
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
                        .padding(.bottom, hasEffectivePractice ? 40 : 120)
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
        .confirmationDialog(
            "清除后不会删除这条练习或媒体。",
            isPresented: Binding(
                get: { pendingClearKind != nil },
                set: { if !$0 { pendingClearKind = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("清除引用", role: .destructive) {
                if let kind = pendingClearKind {
                    applyVersion(kind: kind, itemId: nil)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(item: $pickerKind) { kind in
            ProjectVersionPickerView(
                projectId: projectId,
                kind: kind,
                selectedItemId: kind == .stage
                    ? snapshot?.stageVersionItemId
                    : snapshot?.finalVersionItemId,
                candidates: ProjectRules.versionCandidates(projectId: projectId, in: allSnapshots)
            ) { itemId in
                applyVersion(kind: kind, itemId: itemId)
            }
        }
        .sheet(isPresented: $showGoalEditor) {
            goalEditorSheet
        }
        .confirmationDialog("当前阶段", isPresented: $showStagePicker, titleVisibility: .visible) {
            ForEach(ProjectSetupRules.stages, id: \.self) { stage in
                Button(stage) { saveStage(stage) }
            }
            Button("不选择") { saveStage("") }
            Button("取消", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if snapshot != nil, !hasEffectivePractice, snapshot?.status == .active {
                emptyPracticeFooter
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

    private func emptyIdentityCard(_ project: ProjectSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(project.name)
                    .font(GitaFont.title())
                    .foregroundStyle(GitaTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(emptyStatusLabel(project))
                    .font(GitaFont.caption(.medium))
                    .foregroundStyle(project.status == .active ? GitaTheme.brand500 : GitaTheme.textSecondary)
            }
            Text("刚刚创建 · 还没有练习记录")
                .font(GitaFont.footnote())
                .foregroundStyle(GitaTheme.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
    }

    private func emptyStatusLabel(_ project: ProjectSnapshot) -> String {
        switch project.status {
        case .active: return "进行中"
        case .completed: return "已完成"
        case .archived: return "暂不练习"
        }
    }

    private func setupLaterCard(_ project: ProjectSnapshot) -> some View {
        let goal = ProjectSetupRules.trimmed(project.goal)
        let stage = ProjectSetupRules.trimmed(project.stageRaw)
        return VStack(spacing: 0) {
            Button {
                goalDraft = project.goal
                showGoalEditor = true
            } label: {
                laterFillRow(
                    label: "完成标准",
                    trailing: goal.isEmpty ? "添加  ›" : "编辑  ›",
                    trailingColor: GitaTheme.brand500,
                    summary: goal.isEmpty ? nil : goal
                )
            }
            .buttonStyle(.plain)

            Divider()
                .overlay(GitaTheme.borderSubtle)
                .padding(.leading, 18)

            Button {
                showStagePicker = true
            } label: {
                laterFillRow(
                    label: "当前阶段",
                    trailing: stage.isEmpty ? "未设置  ›" : "\(stage)  ›",
                    trailingColor: stage.isEmpty ? GitaTheme.textSecondary : GitaTheme.textPrimary,
                    summary: nil
                )
            }
            .buttonStyle(.plain)
        }
        .background(GitaTheme.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: GitaTheme.radius16)
                .stroke(GitaTheme.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
    }

    private func laterFillRow(
        label: String,
        trailing: String,
        trailingColor: Color,
        summary: String?
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(GitaFont.callout(.medium))
                .foregroundStyle(GitaTheme.textPrimary)
            Spacer(minLength: 8)
            if let summary {
                Text(summary)
                    .font(GitaFont.footnote())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(trailing)
                .font(GitaFont.footnote())
                .foregroundStyle(trailingColor)
                .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private var firstPracticeCard: some View {
        VStack(spacing: 12) {
            Text("第一次")
                .font(GitaFont.caption(.medium))
                .foregroundStyle(GitaTheme.brand500)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(GitaTheme.brand50)
                .clipShape(Capsule())
            Text("从一次真实练习开始")
                .font(GitaFont.headline())
                .foregroundStyle(GitaTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text("练习完成后，时间、笔记和录音会汇集到项目里。")
                .font(GitaFont.footnote())
                .foregroundStyle(GitaTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
    }

    private var emptyPracticeFooter: some View {
        VStack(spacing: 8) {
            Text("项目已创建，可以稍后再练")
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                createTodayPractice(replaceStack: true)
            } label: {
                Text("开始第一次练习")
                    .font(GitaFont.body(.bold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(GitaTheme.brand500)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, GitaTheme.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 26)
        .background(GitaTheme.bgDefault)
    }

    private var goalEditorSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { showGoalEditor = false }
                    .font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(minWidth: 44, alignment: .leading)
                Spacer(minLength: 0)
                Text("完成标准")
                    .font(GitaFont.body(.bold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer(minLength: 0)
                Button("保存") { saveGoal() }
                    .font(GitaFont.callout(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .padding(.horizontal, GitaTheme.s24)
            .frame(height: 56)

            TextField("", text: $goalDraft, axis: .vertical)
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
                .onChange(of: goalDraft) { _, newValue in
                    let clamped = ProjectSetupRules.clamp(newValue, max: ProjectSetupRules.goalMax)
                    if clamped != newValue {
                        goalDraft = clamped
                    }
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(GitaTheme.bgDefault)
        .presentationDetents([.medium])
    }

    private func identitySection(_ project: ProjectSnapshot) -> some View {
        let showStagePill = ProjectRules.showsVersionPill(
            itemId: project.stageVersionItemId,
            projectId: project.id,
            in: allSnapshots
        )
        let showFinalPill = ProjectRules.showsVersionPill(
            itemId: project.finalVersionItemId,
            projectId: project.id,
            in: allSnapshots
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text(project.name)
                .font(GitaFont.title())
                .foregroundStyle(GitaTheme.textPrimary)
            if showStagePill || showFinalPill {
                ChipWrap(spacing: 8) {
                    if showStagePill {
                        identityPill("阶段成果")
                    }
                    if showFinalPill {
                        identityPill("最终版本")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func identityPill(_ text: String) -> some View {
        Text(text)
            .font(GitaFont.caption())
            .foregroundStyle(GitaTheme.brand500)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(GitaTheme.brand50)
            .clipShape(Capsule())
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

    @ViewBuilder
    private func resolvedSlotCard(_ item: PracticeItemSnapshot) -> some View {
        let note = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
        HStack(alignment: .center, spacing: 10) {
            if item.recordingCount > 0 {
                Button {
                    playNewestRecording(of: item)
                } label: {
                    Image(systemName: player.playingId == newestRecordingId(of: item) ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GitaTheme.brand500)
                        .frame(width: 28, height: 28)
                        .background(GitaTheme.brand50)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放最近一条媒体")
            }
            Button {
                router.recordPath.append(.practiceDetail(itemId: item.id))
            } label: {
                Group {
                    if !note.isEmpty {
                        Text(note)
                            .font(GitaFont.body())
                            .foregroundStyle(GitaTheme.textPrimary)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
    }

    private func thisTimeSection(_ snapshot: ProjectSnapshot) -> some View {
        let focus = snapshot.currentFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 10) {
            Text("这次练什么")
                .font(GitaFont.body(.semibold))
                .foregroundStyle(GitaTheme.textPrimary)
            VStack(alignment: .leading, spacing: 12) {
                if !focus.isEmpty {
                    Text(focus)
                        .font(GitaFont.body())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if snapshot.status == .active {
                    createTodayButton
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GitaTheme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
            .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
        }
    }

    private var createTodayButton: some View {
        Button {
            createTodayPractice(replaceStack: false)
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

    private func versionSlotsSection(_ snapshot: ProjectSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            versionSlotRow(
                title: "阶段版本",
                kind: .stage,
                itemId: snapshot.stageVersionItemId,
                projectId: snapshot.id
            )
            versionSlotRow(
                title: "最终版本",
                kind: .final,
                itemId: snapshot.finalVersionItemId,
                projectId: snapshot.id
            )
        }
    }

    @ViewBuilder
    private func versionSlotRow(
        title: String,
        kind: ProjectVersionKind,
        itemId: UUID?,
        projectId: UUID
    ) -> some View {
        let slot = ProjectRules.versionSlot(itemId: itemId, projectId: projectId, in: allSnapshots)
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(GitaFont.body(.semibold))
                .foregroundStyle(GitaTheme.textPrimary)
            switch slot {
            case .empty:
                Button(kind == .stage ? "选择阶段版本" : "选择最终版本") {
                    pickerKind = kind
                }
                .font(GitaFont.callout(.semibold))
                .foregroundStyle(GitaTheme.brand500)
                .buttonStyle(.plain)
            case .resolved(let item):
                resolvedSlotCard(item)
                HStack(spacing: 16) {
                    Button("更换") { pickerKind = kind }
                    Button("清除引用") { pendingClearKind = kind }
                }
                .font(GitaFont.callout(.semibold))
                .foregroundStyle(GitaTheme.brand500)
                .buttonStyle(.plain)
            case .stale:
                Button {
                    applyVersion(kind: kind, itemId: nil, thenPick: true)
                } label: {
                    Text("已失效，请重新选择")
                        .font(GitaFont.body())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(GitaTheme.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var trajectoryLink: some View {
        Button {
            router.recordPath.append(.projectTrajectory(projectId: projectId))
        } label: {
            HStack {
                Text("查看项目练习轨迹")
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
            }
            .font(GitaFont.body())
            .foregroundStyle(GitaTheme.brand500)
        }
        .buttonStyle(.plain)
    }

    private var cumulativeLabel: some View {
        Text("累计 \(RecordMinutes.display(fromSeconds: totalSeconds)) 分钟")
            .font(GitaFont.caption())
            .foregroundStyle(GitaTheme.textSecondary)
    }

    private func applyVersion(kind: ProjectVersionKind, itemId: UUID?, thenPick: Bool = false) {
        guard !versionWriteLock else { return }
        versionWriteLock = true
        defer { versionWriteLock = false }
        do {
            switch kind {
            case .stage:
                try store.setProjectStageVersion(projectId: projectId, itemId: itemId, now: Date())
                RecordAnalytics.projectStageVersionChanged(
                    projectId: projectId.uuidString,
                    practiceItemId: itemId?.uuidString ?? ""
                )
            case .final:
                try store.setProjectFinalVersion(projectId: projectId, itemId: itemId, now: Date())
                RecordAnalytics.projectFinalVersionChanged(
                    projectId: projectId.uuidString,
                    practiceItemId: itemId?.uuidString ?? ""
                )
            }
            pickerKind = thenPick ? kind : nil
        } catch {
            showToast(String(localized: "操作失败，请重试"))
        }
    }

    private func createTodayPractice(replaceStack: Bool) {
        guard !creatingTodayLock else { return }
        creatingTodayLock = true
        defer { creatingTodayLock = false }
        if replaceStack {
            RecordAnalytics.projectDetailFirstPracticeClicked(projectId: projectId.uuidString)
        } else {
            RecordAnalytics.projectPracticeCreateTapped(projectId: projectId.uuidString)
        }
        do {
            let item = try store.createTodayPracticeItem(projectId: projectId, now: Date(), calendar: calendar)
            RecordAnalytics.projectPracticeCreated(
                projectId: projectId.uuidString,
                practiceItemId: item.id.uuidString,
                result: "success"
            )
            if replaceStack {
                router.replaceLastRecordRoute(.practiceDetail(itemId: item.id))
            } else {
                router.recordPath.append(.practiceDetail(itemId: item.id))
            }
        } catch {
            RecordAnalytics.projectPracticeCreated(
                projectId: projectId.uuidString,
                practiceItemId: "",
                result: "failure"
            )
            showToast(String(localized: "创建失败，请重试"))
        }
    }

    private func saveGoal() {
        do {
            try store.updateProjectGoal(id: projectId, goal: goalDraft, now: Date())
            showGoalEditor = false
        } catch {
            showToast(String(localized: "操作失败，请重试"))
        }
    }

    private func saveStage(_ raw: String) {
        do {
            try store.updateProjectStage(id: projectId, stageRaw: raw, now: Date())
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

private struct ChipWrap: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }
        return (origins, CGSize(width: max(maxX, 0), height: y + rowHeight))
    }
}
