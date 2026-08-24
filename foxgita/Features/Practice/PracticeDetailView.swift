//
//  PracticeDetailView.swift
//  foxgita
//

import SwiftData
import SwiftUI

struct PracticeDetailView: View {
    let taskId: String
    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @Environment(ReviewJobRunner.self) private var reviewRunner
    @Environment(MemoryConsentCoordinator.self) private var consent
    @Query private var tasks: [TaskItem]
    @Query private var sessions: [PracticeSession]
    @AppStorage(LLMSettingsKey.baseURL) private var llmBaseURL = ""
    @AppStorage(LLMSettingsKey.model) private var llmModel = ""
    private let llmCredentials = LLMCredentialsStore()

    private enum ToolMode {
        case audio, note, video
    }

    @State private var metronome = MetronomeEngine()
    @State private var practiceTimer = PracticeTimer()
    @State private var recorder = AudioRecorderService()
    @State private var video = VideoRecorderService()
    @State private var steps: [String] = []
    @State private var noteText = ""
    @State private var toolMode: ToolMode = .note
    @State private var expandedReviewId: String?
    @State private var toast: String?
    @State private var isCompleting = false
    @State private var openSessionId: String?
    @State private var didRestoreSession = false
    @State private var analysisRoute: VideoRoute?
    @State private var diagnosisRoute: VideoRoute?
    /// Set only by analysis `onReady`; presented from the analysis cover's `onDismiss`.
    @State private var pendingDiagnosisRoute: VideoRoute?
    @State private var isSourcePresented = false
    @State private var pendingCamera = false
    @State private var player = AudioPlayerService()
    @State private var videoPlayURL: URL?

    init(taskId: String) {
        self.taskId = taskId
        _tasks = Query(filter: #Predicate<TaskItem> { $0.id == taskId && $0.deletedAt == nil })
        let tid = taskId
        _sessions = Query(filter: #Predicate<PracticeSession> { $0.taskId == tid && $0.deletedAt == nil })
    }

    private var task: TaskItem? { tasks.first }

    private var visibleClips: [RecordingRef] {
        let descriptors = sessions.flatMap(\.recordings).map {
            PracticeClipDescriptor(
                id: $0.id, fileName: $0.fileName, createdAt: $0.createdAt, deletedAt: $0.deletedAt
            )
        }
        let visible = PracticeClipQuery.visible(
            clips: descriptors, videoMode: toolMode == .video
        )
        let byId = Dictionary(
            sessions.flatMap(\.recordings).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return visible.compactMap { byId[$0.id] }
    }

    private var resumeState: ResumeState {
        let sessionRows = sessions.map { session in
            ResumeSession(
                id: session.id,
                endedAt: session.endedAt,
                bpm: session.bpm,
                noteText: session.noteText,
                deletedAt: session.deletedAt,
                durationSec: session.durationSec,
                recordingCount: session.recordings.filter { $0.deletedAt == nil }.count,
                startedAt: session.startedAt
            )
        }
        let recordingRows = sessions.flatMap(\.recordings).map {
            ResumeRecording(
                id: $0.id,
                createdAt: $0.createdAt,
                deletedAt: $0.deletedAt,
                reviewNextAction: $0.reviewNextAction
            )
        }
        return PracticeResumeQuery.resume(
            sessions: sessionRows,
            recordings: recordingRows,
            defaultBpm: task?.defaultBpm ?? 80,
            skippedSessionId: PracticeResumeSkipStore.skippedSessionId(taskId: taskId)
        )
    }

    /// Anything worth losing a confirmation tap over.
    private var hasUnsavedWork: Bool {
        practiceTimer.elapsedSec > 0
            || !recorder.pending.isEmpty
            || !video.pending.isEmpty
            || !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || openSessionId != nil
    }

    var body: some View {
        ZStack {
            PageBackground()
            if let task {
                content(task)
            } else {
                Text("任务不存在").foregroundStyle(GitaTheme.textSecondary)
            }

            if let toast {
                VStack {
                    Spacer()
                    ToastBanner(text: toast).padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            guard let task else { return }
            if !didRestoreSession {
                didRestoreSession = true
                metronome.setBpm(resumeState.bpm)
                if let sid = resumeState.openSessionId {
                    openSessionId = sid
                    noteText = resumeState.noteText
                    practiceTimer.restore(
                        elapsedSec: resumeState.durationSec,
                        startedAt: resumeState.startedAt
                    )
                }
                steps = task.steps.isEmpty ? [String(localized: "新步骤")] : task.steps
            }
            AudioSessionCoordinator.shared.onInterruption = { [metronome, practiceTimer, recorder] in
                metronome.stop()
                practiceTimer.pause()
                if recorder.isRecording { recorder.stop(label: task.title) }
            }
        }
        .onDisappear {
            AudioSessionCoordinator.shared.onInterruption = nil
            practiceTimer.pause()
            metronome.stop()
            if recorder.isRecording { recorder.stop(label: task?.title ?? "") }
            player.stop()
            videoPlayURL = nil
            if let task {
                persistVisit(task: task)
            }
            recorder.discardPending()
            for clip in video.takeAll() {
                RecordingStore.delete(fileName: clip.fileName)
            }
        }
        .onChange(of: recorder.lastError) { _, value in
            if let value { show(value) }
        }
        .onChange(of: video.lastError) { _, value in
            if let value { show(value) }
        }
        .onChange(of: store.lastError) { _, value in
            if let value { show(value.localizedDescription) }
        }
        .fullScreenCover(isPresented: Binding(
            get: { video.isPresenting },
            set: { if !$0 { video.dismiss() } }
        )) {
            VideoCameraPicker(
                isPresented: Binding(
                    get: { video.isPresenting },
                    set: { if !$0 { video.dismiss() } }
                ),
                onPicked: { url in
                    video.ingest(tempURL: url, label: task?.title ?? "")
                    if let task { persistPending(task: task) }
                },
                onCancel: { video.dismiss() }
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func content(_ task: TaskItem) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("返回") { requestExit() }
                    .font(.system(size: 14))
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(minWidth: 40, alignment: .leading)
                Text(task.title)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Button("完成") { complete(task) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 16)
            .fullScreenCover(isPresented: $isSourcePresented, onDismiss: {
                if pendingCamera {
                    pendingCamera = false
                    player.stop()
                    videoPlayURL = nil
                    video.presentCamera()
                }
            }) {
                VideoSourceView(
                    taskTitle: task.title,
                    onDismiss: { isSourcePresented = false },
                    onStartCamera: {
                        pendingCamera = true
                        isSourcePresented = false
                    },
                    onImported: { clip in
                        persist(audioClip(clip), task: task)
                        isSourcePresented = false
                    },
                    onToast: { show($0) }
                )
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !AIPracticePresentation.isAIGenerated(subtitle: task.subtitle) {
                        HStack {
                            Text(task.subtitle)
                            Spacer()
                            Text(task.timeSig)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(GitaTheme.textSecondary)
                    }

                    if let line = PracticeResumeQuery.focusLine(state: resumeState) {
                        Text(line)
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)
                            .accessibilityLabel(Text(line))
                    }

                    metronomeCard
                    timerCard(task)
                    stepsCard
                    toolsRow(task)

                    if recorder.isRecording {
                        recordingActivePanel(task)
                    }

                    if toolMode == .note {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("记录一点感受…", text: $noteText, axis: .vertical)
                                .font(.system(size: 14))
                                .lineLimit(3...6)
                            Text("记录一点感受，下次继续从这里开始")
                                .font(.system(size: 12))
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GitaTheme.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    if toolMode != .note {
                        clipList(task)
                    }

                    Button { complete(task) } label: {
                        Text("完成本次练习")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(GitaTheme.brandOn)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(GitaTheme.brand500)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            // Two covers on the same view would leave only the last one live, so
            // the diagnosis cover hangs off the scroll view instead.
            .fullScreenCover(item: $diagnosisRoute) { route in
                VideoDiagnosisView(
                    recordingId: route.id,
                    taskTitle: task.title,
                    onClose: { diagnosisRoute = nil }
                )
            }
        }
        .fullScreenCover(item: $analysisRoute, onDismiss: {
            if let pending = pendingDiagnosisRoute {
                diagnosisRoute = pending
                pendingDiagnosisRoute = nil
            }
        }) { route in
            VideoAnalysisView(
                recordingId: route.id,
                taskTitle: task.title,
                durationSec: route.durationSec,
                onDismiss: { analysisRoute = nil },
                onReady: {
                    pendingDiagnosisRoute = VideoRoute(id: route.id, durationSec: route.durationSec)
                    analysisRoute = nil
                }
            )
        }
    }

    private var metronomeCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("节拍器").font(GitaFont.headline())
                Spacer()
                Text("木质短音")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            HStack {
                circleBtn("－", label: String(localized: "降低 1 BPM")) { metronome.bump(-1) }
                VStack(spacing: 0) {
                    Text("\(metronome.bpm)")
                        .font(GitaFont.timer())
                    Text("BPM")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("当前速度 \(metronome.bpm) BPM"))
                circleBtn("＋", label: String(localized: "提高 1 BPM"), accent: true) {
                    metronome.bump(1)
                }
            }
        }
        .padding(18)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }

    private func timerCard(_ task: TaskItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(practiceTimer.display)
                    .font(GitaFont.timer())
                Text("目标 \(task.targetMin):00")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            Spacer()
            Button("RESET") {
                resetTrip(task)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(GitaTheme.textSecondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(GitaTheme.bgSubtle)
            .clipShape(Capsule())

            Button(practiceTimer.isRunning ? "暂停" : "开始") { togglePlay() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GitaTheme.brandOn)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(GitaTheme.brand500)
                .clipShape(Capsule())
        }
        .padding(16)
        .frame(minHeight: 100)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("练习步骤").font(.system(size: 18, weight: .bold))
                Spacer()
                Button("新增步骤") { steps.append(String(localized: "新步骤")) }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
            }
            .padding(.bottom, 8)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(GitaTheme.brand500)
                        .frame(minWidth: 28, minHeight: 28)
                        .background(GitaTheme.brand50)
                        .clipShape(Circle())
                    TextField("步骤", text: binding(index))
                        .font(.system(size: 14))
                    if let minutes = AIPracticePresentation.stepParts(steps[index]).minutes {
                        Text("\(minutes) 分钟")
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.textSecondary)
                    }
                    if steps.count > 1 {
                        Button("删除") { steps.remove(at: index) }
                            .font(.system(size: 12))
                            .foregroundStyle(GitaTheme.textTertiary)
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func toolsRow(_ task: TaskItem) -> some View {
        HStack(spacing: 10) {
            tool(
                title: recorder.isRecording ? String(localized: "录音中") : String(localized: "录音"),
                systemImage: recorder.isRecording ? "mic.fill" : "mic",
                on: toolMode == .audio
            ) {
                Task {
                    if toolMode != .audio {
                        if recorder.isRecording {
                            recorder.stop(label: task.title)
                            persistPending(task: task)
                        }
                        toolMode = .audio
                        return
                    }
                    if recorder.isRecording {
                        recorder.stop(label: task.title)
                        persistPending(task: task)
                    } else {
                        player.stop()
                        videoPlayURL = nil
                        await recorder.start(label: task.title)
                    }
                }
            }
            tool(title: String(localized: "写笔记"), systemImage: "square.and.pencil", on: toolMode == .note) {
                if recorder.isRecording {
                    recorder.stop(label: task.title)
                    persistPending(task: task)
                }
                toolMode = .note
            }
            tool(
                title: String(localized: "录视频"),
                systemImage: "video.fill",
                on: toolMode == .video
            ) {
                if recorder.isRecording {
                    recorder.stop(label: task.title)
                    persistPending(task: task)
                }
                if toolMode != .video {
                    toolMode = .video
                    return
                }
                player.stop()
                videoPlayURL = nil
                isSourcePresented = true
            }
        }
    }

    private func clipList(_ task: TaskItem) -> some View {
        VStack(spacing: 10) {
            if visibleClips.isEmpty {
                VStack(spacing: 8) {
                    Text(
                        toolMode == .video
                            ? String(localized: "还没有视频")
                            : String(localized: "还没有录音")
                    )
                    .font(.system(size: 14, weight: .semibold))
                    Text(
                        toolMode == .video
                            ? String(localized: "点上方「录视频」即可拍摄或从相册导入")
                            : String(localized: "点上方「录音」即可留下片段")
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(GitaTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(visibleClips, id: \.id) { rec in
                    clipCard(rec, taskTitle: task.title)
                }
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
    }

    private func clipCard(_ rec: RecordingRef, taskTitle: String) -> some View {
        let video = MediaReviewMedia.isVideo(fileName: rec.fileName)
        let configured = llmCredentials.isConfigured(baseURL: llmBaseURL, model: llmModel)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(video ? GitaTheme.categoryBlue : GitaTheme.brand500)
                    .frame(width: 6, height: 6)
                Text(video ? String(localized: "视频记录") : String(localized: "录音记录"))
                    .font(.system(size: 12, weight: .semibold))
                Text("·")
                Text(PracticeClipQuery.timestamp(rec.createdAt))
                    .font(.system(size: 12))
                    .foregroundStyle(GitaTheme.textSecondary)
                Spacer()
                Button {
                    presentIfFileExists(rec) {
                        metronome.stop()
                        if MediaReviewMedia.isVideo(fileName: rec.fileName) {
                            player.stop()
                            do {
                                try AudioSessionCoordinator.shared.acquire(.playback)
                                videoPlayURL = rec.fileURL
                            } catch {
                                show(String(localized: "无法播放"))
                            }
                        } else {
                            player.toggle(url: rec.fileURL, id: rec.id)
                        }
                    }
                } label: {
                    Image(systemName: player.playingId == rec.id ? "pause.fill" : "play.fill")
                        .foregroundStyle(GitaTheme.brand500)
                        .frame(width: 36, height: 36)
                        .background(GitaTheme.brand50)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(
                        MediaReviewMedia.isVideo(fileName: rec.fileName)
                            ? String(localized: "播放这段视频")
                            : (player.playingId == rec.id
                                ? String(localized: "暂停播放")
                                : String(localized: "播放这段录音"))
                    )
                )
            }
            Text("\(taskTitle) · \(rec.durationLabel)")
                .font(.system(size: 16, weight: .semibold))
            Text(video ? String(localized: "姿势、指法与节奏分析") : String(localized: "节奏与和弦切换分析"))
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
            if !RecordingStore.fileExists(fileName: rec.fileName) {
                Text(String(localized: "文件缺失"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitaTheme.statusError)
            }
            if configured {
                aiRow(rec)
            }
            if expandedReviewId == rec.id, rec.reviewStatus == .ready, !hasDiagnosis(rec) {
                reviewFields(rec)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func aiRow(_ rec: RecordingRef) -> some View {
        let running = reviewRunner.isRunning(rec.id)
        switch rec.reviewStatus {
        case .ready:
            HStack(spacing: 12) {
                Text(String(localized: "AI 复盘已生成"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
                Spacer()
                // A diagnosis page already shows the three fields under 总结, so the
                // inline expander stays only where the page is summary-only.
                if !hasDiagnosis(rec) {
                    Button(
                        expandedReviewId == rec.id
                            ? String(localized: "收起")
                            : String(localized: "查看复盘")
                    ) {
                        expandedReviewId = expandedReviewId == rec.id ? nil : rec.id
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
                }
                if MediaReviewMedia.isVideo(fileName: rec.fileName) {
                    Button(String(localized: "查看诊断")) {
                        presentIfFileExists(rec) {
                            diagnosisRoute = VideoRoute(id: rec.id, durationSec: rec.durationSec)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
                }
            }
        case .pending where running:
            Text(String(localized: "分析中")).font(.system(size: 12, weight: .semibold))
        case .pending:
            Text(String(localized: "未完成")).font(.system(size: 12, weight: .semibold))
        case .failed:
            Text(String(localized: "生成失败")).font(.system(size: 12, weight: .semibold))
        case .none:
            EmptyView()
        }
    }

    /// A video with findings reads its summary on the diagnosis page instead of
    /// expanding the card in place.
    private func hasDiagnosis(_ rec: RecordingRef) -> Bool {
        MediaReviewMedia.isVideo(fileName: rec.fileName) && !rec.videoFindings.isEmpty
    }

    private func reviewFields(_ rec: RecordingRef) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            labeled("亮点", rec.reviewHighlight)
            labeled("优先改善", rec.reviewFocus)
            labeled("下次练法", rec.reviewNextAction)
        }
    }

    private func labeled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(GitaTheme.textSecondary)
            Text(body).font(.system(size: 14))
        }
    }

    private func presentIfFileExists(_ rec: RecordingRef, present: () -> Void) {
        guard RecordingStore.fileExists(fileName: rec.fileName) else {
            show(String(localized: "文件不存在或已被移除"))
            return
        }
        present()
    }

    private func recordingActivePanel(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(GitaTheme.statusError)
                    .frame(width: 8, height: 8)
                    .opacity(recorder.isPaused ? 0.35 : 1)
                Text(recorder.isPaused ? "已暂停" : "正在录音")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer()
                Text(recorder.elapsedDisplay)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(GitaTheme.statusError)
            }

            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(GitaTheme.statusError.opacity(recorder.isPaused ? 0.25 : 0.55))
                        .frame(width: 3, height: waveHeight(index))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)

            HStack(spacing: 10) {
                Button {
                    if recorder.isPaused { recorder.resume() } else { recorder.pause() }
                } label: {
                    Text(recorder.isPaused ? "继续" : "暂停")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GitaTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .background(GitaTheme.bgSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    recorder.stop(label: task.title)
                    persistPending(task: task)
                } label: {
                    Text("停止")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GitaTheme.brandOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .background(GitaTheme.statusError)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(GitaTheme.brand50)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(GitaTheme.statusError.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("正在录音 \(recorder.elapsedDisplay)"))
    }

    private func waveHeight(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [8, 14, 20, 12, 22, 10, 18, 14]
        let base = pattern[index % pattern.count]
        return recorder.isPaused ? max(6, base * 0.45) : base
    }

    private func circleBtn(
        _ title: String, label: String, accent: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(accent ? GitaTheme.brand500 : GitaTheme.textSecondary)
                .frame(minWidth: 48, minHeight: 48)
                .background(accent ? GitaTheme.brand50 : GitaTheme.bgSubtle)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private func tool(
        title: String, systemImage: String, on: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(on ? GitaTheme.brand500 : GitaTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(GitaTheme.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(on ? GitaTheme.brand500 : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: GitaTheme.shadowCard, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < steps.count ? steps[index] : "" },
            set: { if index < steps.count { steps[index] = $0 } }
        )
    }

    private func togglePlay() {
        if practiceTimer.isRunning {
            practiceTimer.pause()
            metronome.stop()
            return
        }
        do {
            try metronome.start()
            practiceTimer.start()
        } catch {
            show(String(localized: "节拍器无法启动"))
        }
    }

    private func requestExit() {
        practiceTimer.pause()
        metronome.stop()
        if let task {
            if recorder.isRecording { recorder.stop(label: task.title) }
            persistVisit(task: task)
        }
        leave()
    }

    private func leave() {
        router.practicePath.removeAll()
    }

    private func audioClip(_ clip: VideoRecorderService.Clip) -> AudioRecorderService.Clip {
        AudioRecorderService.Clip(
            id: clip.id, fileName: clip.fileName, bytes: clip.bytes,
            durationSec: clip.durationSec, createdAt: clip.createdAt, label: clip.label
        )
    }

    private func persist(_ clip: AudioRecorderService.Clip, task: TaskItem) {
        guard FileManager.default.fileExists(atPath: clip.url.path) else {
            show(String(localized: MediaReviewMedia.isVideo(fileName: clip.fileName) ? "录像没保存" : "录音没保存"))
            return
        }
        let end = Date()
        let elapsed = practiceTimer.elapsedSec
        let start = practiceTimer.startedAt ?? end.addingTimeInterval(TimeInterval(-elapsed))
        let sid: String?
        if let open = openSessionId {
            sid = store.appendRecording(sessionId: open, clip: clip) ? open : nil
        } else {
            sid = store.beginOpenSession(
                taskId: task.id, steps: steps, note: noteText,
                startedAt: start, endedAt: end, durationSec: elapsed,
                bpm: metronome.bpm, clip: clip
            )
        }
        guard let sid else { return }
        openSessionId = sid
        clearSkipIfResumed(taskId: task.id, sessionId: sid)
        recorder.detach(clip.id)
        video.detach(clip.id)
        if llmCredentials.isConfigured(baseURL: llmBaseURL, model: llmModel) {
            let clipId = clip.id
            let fileName = clip.fileName
            Task { @MainActor in
                guard await consent.ensureDecided() == .proceed else { return }
                store.markReviewsPending(recordingIds: [clipId])
                reviewRunner.enqueue([clipId], baseURL: llmBaseURL, model: llmModel)
                if MediaReviewMedia.isVideo(fileName: fileName) {
                    analysisRoute = VideoRoute(id: clipId, durationSec: clip.durationSec)
                }
            }
        }
    }

    private func persistPending(task: TaskItem) {
        for clip in recorder.pending { persist(clip, task: task) }
        for clip in video.pending { persist(audioClip(clip), task: task) }
    }

    private func saveOpenSession(task: TaskItem) {
        guard let openSessionId else { return }
        let end = Date()
        _ = store.updateOpenSession(
            sessionId: openSessionId,
            steps: steps,
            note: noteText,
            endedAt: end,
            durationSec: practiceTimer.elapsedSec,
            bpm: metronome.bpm
        )
    }

    @discardableResult
    private func persistVisit(task: TaskItem) -> String? {
        persistPending(task: task)
        if let open = openSessionId {
            saveOpenSession(task: task)
            clearSkipIfResumed(taskId: task.id, sessionId: open)
            return open
        }
        let leftover = recorder.consume() + video.takeAll().map { audioClip($0) }
        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let elapsed = practiceTimer.elapsedSec
        let hasRecord = elapsed > 0 || !note.isEmpty || !leftover.isEmpty
        if hasRecord {
            let end = Date()
            let savedId = store.finishSession(
                taskId: task.id, steps: steps, note: noteText,
                startedAt: practiceTimer.startedAt ?? end.addingTimeInterval(TimeInterval(-elapsed)),
                endedAt: end, durationSec: elapsed, bpm: metronome.bpm, recordings: leftover
            )
            if let savedId {
                openSessionId = savedId
                clearSkipIfResumed(taskId: task.id, sessionId: savedId)
                return savedId
            }
        }
        store.updateTaskPracticeState(task.id, steps: steps, bpm: metronome.bpm)
        return nil
    }

    private func resetTrip(_ task: TaskItem) {
        practiceTimer.pause()
        metronome.stop()
        if recorder.isRecording { recorder.stop(label: task.title) }
        let sealedId = persistVisit(task: task) ?? openSessionId ?? resumeState.openSessionId
        if let sealedId {
            PracticeResumeSkipStore.skip(taskId: task.id, sessionId: sealedId)
        }
        practiceTimer.reset()
        noteText = ""
        openSessionId = nil
    }

    private func clearSkipIfResumed(taskId: String, sessionId: String) {
        if PracticeResumeSkipStore.skippedSessionId(taskId: taskId) != sessionId {
            PracticeResumeSkipStore.clear(taskId: taskId)
        }
    }

    private func complete(_ task: TaskItem) {
        guard !isCompleting else { return }
        isCompleting = true
        if recorder.isRecording { recorder.stop(label: task.title) }
        practiceTimer.pause()
        metronome.stop()
        player.stop()
        videoPlayURL = nil
        let hadContent = hasUnsavedWork
        let stepsChanged = steps != task.steps
        let hadNote = !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let savedId = persistVisit(task: task)
        if let savedId {
            Haptics.success()
            router.returnPracticeToToday = true
            router.practicePath.removeAll()
            return
        }
        if !hadContent {
            if !stepsChanged && !hadNote {
                router.practiceToast = String(localized: "这次没有留下记录")
            }
            router.returnPracticeToToday = true
            router.practicePath.removeAll()
            return
        }
        isCompleting = false
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }
}

private struct VideoRoute: Identifiable {
    var id: String
    var durationSec: Int
}
