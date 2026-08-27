//
//  PracticeDetailView.swift
//  foxgita
//

import SwiftData
import SwiftUI

enum PracticeDetailMode: Equatable {
    case editable
    case historical
}

enum PracticeDetailState {
    static func practiceRoute(itemId: UUID) -> PracticeRoute {
        .detail(itemId: itemId)
    }

    static func practiceRoute(fromSheetSelection raw: String) -> PracticeRoute? {
        guard let itemId = UUID(uuidString: raw) else { return nil }
        return .detail(itemId: itemId)
    }

    static func mode(
        practiceDayKey: String,
        today: Date = Date(),
        calendar: Calendar = .current,
        allowPastDayEdits: Bool = false
    ) -> PracticeDetailMode {
        if allowPastDayEdits { return .editable }
        return practiceDayKey == PracticeDayKey.make(from: today, calendar: calendar)
            ? .editable
            : .historical
    }

    static func initialElapsedSeconds(storedDurationSeconds: Int) -> Int {
        max(0, storedDurationSeconds)
    }

    static func isDirty(
        elapsedSeconds: Int,
        note: String,
        storedDurationSeconds: Int,
        storedNote: String
    ) -> Bool {
        max(0, elapsedSeconds) != max(0, storedDurationSeconds) || note != storedNote
    }

    static func shouldAutoSaveOnDisappear(mode: PracticeDetailMode, isDirty: Bool) -> Bool {
        mode == .editable && isDirty
    }

    static func shouldAllowTimer(mode: PracticeDetailMode) -> Bool {
        mode == .editable
    }

    static func shouldAllowCapture(mode: PracticeDetailMode) -> Bool {
        mode == .editable
    }

    static func shouldAllowComplete(mode: PracticeDetailMode) -> Bool {
        mode == .editable
    }

    static func loadedItem(
        requestedId: UUID,
        candidates: [PracticeItemSnapshot]
    ) -> PracticeItemSnapshot? {
        candidates.first { $0.id == requestedId && !$0.isDeleted }
    }
}

struct PracticeDetailView: View {
    let itemId: UUID
    var allowPastDayEdits: Bool = false
    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @Environment(ReviewJobRunner.self) private var reviewRunner
    @Environment(MemoryConsentCoordinator.self) private var consent
    @Query private var items: [PracticeItem]
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
    @State private var noteText = ""
    @State private var storedNote = ""
    @State private var storedDurationSeconds = 0
    @State private var toolMode: ToolMode = .note
    @State private var expandedReviewId: String?
    @State private var toast: String?
    @State private var isCompleting = false
    @State private var didLoadItem = false
    @State private var analysisRoute: VideoRoute?
    @State private var diagnosisRoute: VideoRoute?
    /// Set only by analysis `onReady`; presented from the analysis cover's `onDismiss`.
    @State private var pendingDiagnosisRoute: VideoRoute?
    @State private var isSourcePresented = false
    @State private var pendingCamera = false
    @State private var player = AudioPlayerService()
    @State private var videoPlayURL: URL?
    @FocusState private var noteFocused: Bool

    init(itemId: UUID, allowPastDayEdits: Bool = false) {
        self.itemId = itemId
        self.allowPastDayEdits = allowPastDayEdits
        let identifier = itemId
        _items = Query(filter: #Predicate<PracticeItem> { $0.id == identifier && $0.deletedAt == nil })
    }

    private var item: PracticeItem? { items.first }

    private var mode: PracticeDetailMode {
        guard let item else { return .historical }
        return PracticeDetailState.mode(
            practiceDayKey: item.practiceDayKey,
            allowPastDayEdits: allowPastDayEdits
        )
    }

    private var isDirty: Bool {
        PracticeDetailState.isDirty(
            elapsedSeconds: practiceTimer.elapsedSec,
            note: noteText,
            storedDurationSeconds: storedDurationSeconds,
            storedNote: storedNote
        )
    }

    private var visibleClips: [RecordingRef] {
        guard let item else { return [] }
        let descriptors = item.recordings.map {
            PracticeClipDescriptor(
                id: $0.id, fileName: $0.fileName, createdAt: $0.createdAt, deletedAt: $0.deletedAt
            )
        }
        let visible = PracticeClipQuery.visible(
            clips: descriptors, videoMode: toolMode == .video
        )
        let byId = Dictionary(
            item.recordings.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return visible.compactMap { byId[$0.id] }
    }

    /// Anything worth losing a confirmation tap over.
    private var hasUnsavedWork: Bool {
        isDirty || !recorder.pending.isEmpty || !video.pending.isEmpty
    }

    var body: some View {
        ZStack {
            PageBackground()
            if let item {
                content(item)
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
            guard let item else { return }
            if !didLoadItem {
                didLoadItem = true
                noteText = item.note
                storedNote = item.note
                storedDurationSeconds = PracticeDetailState.initialElapsedSeconds(
                    storedDurationSeconds: item.durationSeconds
                )
                practiceTimer.restore(elapsedSec: storedDurationSeconds, startedAt: nil)
                metronome.setBpm(item.bpm ?? 80)
            }
            AudioSessionCoordinator.shared.onInterruption = { [metronome, practiceTimer, recorder] in
                metronome.stop()
                practiceTimer.pause()
                if recorder.isRecording { recorder.stop(label: item.title) }
            }
        }
        .onDisappear {
            AudioSessionCoordinator.shared.onInterruption = nil
            practiceTimer.pause()
            metronome.stop()
            if recorder.isRecording { recorder.stop(label: item?.title ?? "") }
            player.stop()
            videoPlayURL = nil
            if let item {
                persistPending(item: item)
                saveItemIfNeeded(item)
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
                    video.ingest(tempURL: url, label: item?.title ?? "")
                    if let item { persistPending(item: item) }
                },
                onCancel: { video.dismiss() }
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func content(_ item: PracticeItem) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("返回") { requestExit() }
                    .font(.system(size: 14))
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(minWidth: 40, alignment: .leading)
                Text(item.title)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Button("完成") { complete(item) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
                    .frame(minWidth: 40, alignment: .trailing)
                    .disabled(!PracticeDetailState.shouldAllowComplete(mode: mode))
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
                    taskTitle: item.title,
                    onDismiss: { isSourcePresented = false },
                    onStartCamera: {
                        pendingCamera = true
                        isSourcePresented = false
                    },
                    onImported: { clip in
                        persist(audioClip(clip), item: item)
                        isSourcePresented = false
                    },
                    onToast: { show($0) }
                )
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let timeSig = item.timeSignature, !timeSig.isEmpty {
                        HStack {
                            Spacer()
                            Text(timeSig)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(GitaTheme.textSecondary)
                    }

                    metronomeCard
                    timerCard
                    toolsRow(item)

                    if recorder.isRecording {
                        recordingActivePanel(item)
                    }

                    if toolMode == .note {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("记录一点感受…", text: $noteText, axis: .vertical)
                                .font(.system(size: 14))
                                .lineLimit(3...6)
                                .focused($noteFocused)
                                .disabled(mode == .historical)
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
                        clipList(item)
                    }

                    Button { complete(item) } label: {
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
                    .disabled(!PracticeDetailState.shouldAllowComplete(mode: mode))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            // Two covers on the same view would leave only the last one live, so
            // the diagnosis cover hangs off the scroll view instead.
            .fullScreenCover(item: $diagnosisRoute) { route in
                VideoDiagnosisView(
                    recordingId: route.id,
                    taskTitle: item.title,
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
                taskTitle: item.title,
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
                circleBtn("－", label: String(localized: "降低 1 BPM")) {
                    noteFocused = false
                    metronome.bump(-1)
                }
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
                    noteFocused = false
                    metronome.bump(1)
                }
            }
        }
        .padding(18)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }

    private var timerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(practiceTimer.display)
                    .font(GitaFont.timer())
            }
            Spacer()
            Button("RESET") {
                resetTrip()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(GitaTheme.textSecondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(GitaTheme.bgSubtle)
            .clipShape(Capsule())
            .disabled(mode == .historical)

            Button(practiceTimer.isRunning ? "暂停" : "开始") { togglePlay() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GitaTheme.brandOn)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(GitaTheme.brand500)
                .clipShape(Capsule())
                .disabled(mode == .historical)
        }
        .padding(16)
        .frame(minHeight: 100)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }

    /// Historical items stay view-only: notes, existing clips, and review remain;
    /// 录音 / 录视频 / import and the complete CTA must not start capture or persist.
    private func toolsRow(_ item: PracticeItem) -> some View {
        HStack(spacing: 10) {
            tool(
                title: recorder.isRecording ? String(localized: "录音中") : String(localized: "录音"),
                systemImage: recorder.isRecording ? "mic.fill" : "mic",
                on: toolMode == .audio
            ) {
                noteFocused = false
                Task {
                    if toolMode != .audio {
                        if recorder.isRecording {
                            recorder.stop(label: item.title)
                            persistPending(item: item)
                        }
                        toolMode = .audio
                        return
                    }
                    guard PracticeDetailState.shouldAllowCapture(mode: mode) else { return }
                    if recorder.isRecording {
                        recorder.stop(label: item.title)
                        persistPending(item: item)
                    } else {
                        player.stop()
                        videoPlayURL = nil
                        await recorder.start(label: item.title)
                    }
                }
            }
            .disabled(!PracticeDetailState.shouldAllowCapture(mode: mode) && toolMode == .audio)
            tool(title: String(localized: "写笔记"), systemImage: "square.and.pencil", on: toolMode == .note) {
                noteFocused = false
                if recorder.isRecording {
                    recorder.stop(label: item.title)
                    persistPending(item: item)
                }
                toolMode = .note
            }
            tool(
                title: String(localized: "录视频"),
                systemImage: "video.fill",
                on: toolMode == .video
            ) {
                noteFocused = false
                if recorder.isRecording {
                    recorder.stop(label: item.title)
                    persistPending(item: item)
                }
                if toolMode != .video {
                    toolMode = .video
                    return
                }
                guard PracticeDetailState.shouldAllowCapture(mode: mode) else { return }
                player.stop()
                videoPlayURL = nil
                isSourcePresented = true
            }
            .disabled(!PracticeDetailState.shouldAllowCapture(mode: mode) && toolMode == .video)
        }
    }

    private func clipList(_ item: PracticeItem) -> some View {
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
                    clipCard(rec, taskTitle: item.title)
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

    private func recordingActivePanel(_ item: PracticeItem) -> some View {
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
                    recorder.stop(label: item.title)
                    persistPending(item: item)
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

    private func togglePlay() {
        guard PracticeDetailState.shouldAllowTimer(mode: mode) else { return }
        noteFocused = false
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
        noteFocused = false
        practiceTimer.pause()
        metronome.stop()
        if let item {
            if recorder.isRecording { recorder.stop(label: item.title) }
            persistPending(item: item)
            saveItemIfNeeded(item)
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

    private func persist(_ clip: AudioRecorderService.Clip, item: PracticeItem) {
        guard PracticeDetailState.shouldAllowCapture(mode: mode) else { return }
        guard FileManager.default.fileExists(atPath: clip.url.path) else {
            show(String(localized: MediaReviewMedia.isVideo(fileName: clip.fileName) ? "录像没保存" : "录音没保存"))
            return
        }
        let recording = RecordingRef(
            id: clip.id, fileName: clip.fileName, bytes: clip.bytes,
            durationSec: clip.durationSec, createdAt: clip.createdAt, label: clip.label
        )
        do {
            try store.attachRecording(recording, toPracticeItemId: item.id)
        } catch {
            show(store.lastError?.localizedDescription ?? error.localizedDescription)
            return
        }
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

    private func persistPending(item: PracticeItem) {
        guard PracticeDetailState.shouldAllowCapture(mode: mode) else { return }
        for clip in recorder.pending { persist(clip, item: item) }
        for clip in video.pending { persist(audioClip(clip), item: item) }
    }

    private func saveItemIfNeeded(_ item: PracticeItem) {
        guard PracticeDetailState.shouldAutoSaveOnDisappear(mode: mode, isDirty: isDirty) else {
            return
        }
        do {
            try store.savePracticeItem(
                id: item.id,
                durationSeconds: practiceTimer.elapsedSec,
                note: noteText,
                now: Date()
            )
            storedDurationSeconds = max(0, practiceTimer.elapsedSec)
            storedNote = noteText
        } catch {
            show(store.lastError?.localizedDescription ?? error.localizedDescription)
        }
    }

    private func resetTrip() {
        guard PracticeDetailState.shouldAllowTimer(mode: mode) else { return }
        noteFocused = false
        practiceTimer.pause()
        metronome.stop()
        practiceTimer.restore(elapsedSec: storedDurationSeconds, startedAt: nil)
        noteText = storedNote
    }

    private func complete(_ item: PracticeItem) {
        guard PracticeDetailState.shouldAllowComplete(mode: mode) else { return }
        guard !isCompleting else { return }
        noteFocused = false
        isCompleting = true
        if recorder.isRecording { recorder.stop(label: item.title) }
        practiceTimer.pause()
        metronome.stop()
        player.stop()
        videoPlayURL = nil
        persistPending(item: item)
        saveItemIfNeeded(item)
        let hadContent = hasUnsavedWork
            || storedDurationSeconds > 0
            || !storedNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !item.recordings.filter({ $0.deletedAt == nil }).isEmpty
        if hadContent {
            Haptics.success()
        } else {
            router.practiceToast = String(localized: "这次没有留下记录")
        }
        router.returnPracticeToToday = true
        router.practicePath.removeAll()
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
