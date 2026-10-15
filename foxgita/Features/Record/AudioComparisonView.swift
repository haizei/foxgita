import SwiftData
import SwiftUI

struct AudioComparisonView: View {
    let projectId: UUID

    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Query private var projects: [Project]
    @Query private var practiceItems: [PracticeItem]

    @State private var player = AudioPlayerService()
    @State private var playback = AudioComparisonPlayback()
    @State private var overrideStageId: String?
    @State private var overrideRecentId: String?
    @State private var showReplaceSheet = false
    @State private var showFragmentSheet = false
    @State private var fragmentDraft = ""
    @State private var confirmation: AudioComparisonConfirmation?
    @State private var invalidClipIds: Set<String> = []
    @State private var toast: String?
    @State private var creatingTodayLock = false
    @State private var peaksA: [Double] = []
    @State private var peaksB: [Double] = []

    init(projectId: UUID) {
        self.projectId = projectId
        _projects = Query(filter: #Predicate<Project> { $0.id == projectId && $0.deletedAt == nil })
        _practiceItems = Query(
            filter: #Predicate<PracticeItem> { $0.deletedAt == nil && $0.projectId == projectId }
        )
    }

    private var calendar: Calendar { .current }
    private var project: Project? { projects.first }

    private var snapshot: ProjectSnapshot? {
        project.map(ProjectRules.snapshot(from:))
    }

    private var allSnapshots: [PracticeItemSnapshot] {
        practiceItems.map(PracticeStore.snapshot(from:))
    }

    private var readiness: AudioBenchmarkReadiness {
        AudioBenchmarkVersion.resolve(
            stageVersionItemId: snapshot?.stageVersionItemId,
            projectId: projectId,
            items: allSnapshots,
            overrideStageClipId: overrideStageId,
            overrideRecentClipId: overrideRecentId,
            isPlayable: { clip in
                !invalidClipIds.contains(clip.id) && RecordingStore.fileExists(fileName: clip.fileName)
            }
        )
    }

    private var confirmedFragment: String? {
        guard let confirmation,
              case .ready(let stage, let recent) = readiness,
              confirmation.matches(projectId: projectId, stage: stage, recent: recent) else {
            return nil
        }
        return confirmation.fragment
    }

    private var decision: ProjectPracticeStateHandoff.Decision? {
        guard let snapshot else { return nil }
        return ProjectPracticeStateHandoff.startDecision(project: snapshot)
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                header(showsReplace: canReplaceRecording)
                if let snapshot {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(snapshot.name)
                                .font(GitaFont.callout())
                                .foregroundStyle(GitaTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                            comparisonBody
                        }
                        .padding(.horizontal, GitaTheme.pagePadding)
                        .padding(.bottom, 24)
                    }
                } else {
                    missing
                }
            }
            if let toast {
                VStack {
                    Spacer()
                    ToastBanner(text: toast).padding(.bottom, 96)
                }
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            creatingTodayLock = false
            restoreConfirmation()
        }
        .onChange(of: readiness) { _, value in
            guard let confirmation else { return }
            guard snapshot != nil else { return }
            guard case .ready(let stage, let recent) = value,
                  confirmation.matches(projectId: projectId, stage: stage, recent: recent) else {
                clearConfirmation()
                return
            }
        }
        .onDisappear { player.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.stop() }
        }
        .sheet(isPresented: $showReplaceSheet) {
            replaceSheet
        }
        .sheet(isPresented: $showFragmentSheet) {
            fragmentSheet
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let decision, snapshot?.status == .active {
                Button {
                    performHandoff()
                } label: {
                    Text(decision.buttonLabel)
                        .font(GitaFont.body(.bold))
                        .foregroundStyle(GitaTheme.brandOn)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(GitaTheme.brand500)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, GitaTheme.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(GitaTheme.bgDefault)
            }
        }
    }

    @ViewBuilder
    private var comparisonBody: some View {
        switch readiness {
        case .ready(let stage, let recent):
            readyBody(stage: stage, recent: recent)
        case .needsAnotherRecording:
            Text(AudioBenchmarkVersion.needsAnotherCopy)
                .font(GitaFont.body())
                .foregroundStyle(GitaTheme.textSecondary)
        case .selectionUnavailable:
            VStack(alignment: .leading, spacing: 12) {
                Text("所选录音不可用，请更换录音")
                    .font(GitaFont.body())
                    .foregroundStyle(GitaTheme.textSecondary)
                Button("更换录音") { showReplaceSheet = true }
                    .foregroundStyle(GitaTheme.brand500)
            }
        case .unavailable:
            Text("还没有可以对照的录音")
                .font(GitaFont.body())
                .foregroundStyle(GitaTheme.textSecondary)
        }
    }

    private func readyBody(stage: AudioBenchmarkTrack, recent: AudioBenchmarkTrack) -> some View {
        let stageItem = allSnapshots.first { $0.id == stage.itemId }
        let recentItem = allSnapshots.first { $0.id == recent.itemId }
        let notes = ProjectNoteProjection.entries(projectId: projectId, items: allSnapshots)
        return VStack(alignment: .leading, spacing: 16) {
            Text("听听这两次录音")
                .font(GitaFont.headline())
                .foregroundStyle(GitaTheme.textPrimary)
            Text("\(ProgressFirstFormat.monthDay(stage.dayKey)) → \(ProgressFirstFormat.monthDay(recent.dayKey))")
                .font(GitaFont.callout())
                .foregroundStyle(GitaTheme.textSecondary)
            fragmentStatus(stage: stage, recent: recent)
            trackBlock(
                side: .a,
                title: snapshot?.stageVersionItemId == stage.itemId ? "阶段版" : "录音 A",
                track: stage,
                peaks: peaksA
            )
            Button {
                alternate(stage: stage, recent: recent)
            } label: {
                Text("⇄ 交替听 A / B")
                    .font(GitaFont.callout(.bold))
                    .foregroundStyle(GitaTheme.brand500)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .overlay(Capsule().stroke(GitaTheme.brand500, lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            trackBlock(side: .b, title: overrideRecentId == nil ? "最近录音" : "录音 B", track: recent, peaks: peaksB)
            notesBlock(stage: stage, recent: recent, stageNote: stageItem?.note ?? "", recentNote: recentItem?.note ?? "", total: notes.count)
        }
        .task(id: stage.clip.id) {
            peaksA = loadPeaks(stage.clip)
        }
        .task(id: recent.clip.id) {
            peaksB = loadPeaks(recent.clip)
        }
        .task(id: player.playingId) {
            while player.playingId != nil, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                player.finishIfNeeded()
            }
        }
    }

    private func fragmentStatus(stage: AudioBenchmarkTrack, recent: AudioBenchmarkTrack) -> some View {
        let confirmed = confirmation?.matches(projectId: projectId, stage: stage, recent: recent) == true
        return HStack(spacing: 8) {
            Image(systemName: "info.circle")
            Text(confirmed ? "两次均为用户确认的同一片段 · \(confirmation?.fragment ?? "")" : "片段未确认 · 可先交替听")
                .frame(maxWidth: .infinity, alignment: .leading)
            if !confirmed {
                Button("确认片段") {
                    fragmentDraft = ""
                    showFragmentSheet = true
                }
                .font(GitaFont.caption(.semibold))
                .foregroundStyle(GitaTheme.brand500)
            }
        }
        .font(GitaFont.caption())
        .foregroundStyle(GitaTheme.textSecondary)
        .padding(12)
        .background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius8))
    }

    private var fragmentSheet: some View {
        NavigationStack {
            Form {
                Text("请确认 A、B 两条录音都来自同一片段，并写下片段名称。")
                    .font(GitaFont.callout())
                TextField("例如：副歌片段", text: $fragmentDraft)
            }
            .navigationTitle("确认比较片段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showFragmentSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") { confirmFragment() }
                        .disabled(fragmentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func restoreConfirmation() {
        guard let saved = AudioComparisonConfirmationStore.load(projectId: projectId) else { return }
        overrideStageId = saved.stageClipId
        overrideRecentId = saved.recentClipId
        confirmation = saved
    }

    private func confirmFragment() {
        guard case .ready(let stage, let recent) = readiness else { return }
        let value = AudioComparisonConfirmation(projectId: projectId, stage: stage, recent: recent, fragment: fragmentDraft)
        guard !value.fragment.isEmpty else { return }
        AudioComparisonConfirmationStore.save(value)
        confirmation = value
        showFragmentSheet = false
    }

    private func clearConfirmation() {
        AudioComparisonConfirmationStore.clear(projectId: projectId)
        confirmation = nil
    }

    private func notesBlock(
        stage: AudioBenchmarkTrack,
        recent: AudioBenchmarkTrack,
        stageNote: String,
        recentNote: String,
        total: Int
    ) -> some View {
        let stageBody = stageNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let recentBody = recentNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let cited = (stageBody.isEmpty ? 0 : 1) + (recentBody.isEmpty || recent.itemId == stage.itemId ? 0 : 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("▣ 我的笔记")
                    .font(GitaFont.body(.semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer(minLength: 8)
                Button("查看全部历史 ›") {
                    player.stop()
                    router.recordPath.append(.projectNotes(projectId: projectId))
                }
                .font(GitaFont.caption(.semibold))
                .foregroundStyle(GitaTheme.brand500)
                .buttonStyle(.plain)
            }
            if !stageBody.isEmpty {
                noteCitation(stageBody, itemId: stage.itemId, dayKey: stage.dayKey)
            }
            if !recentBody.isEmpty && recent.itemId != stage.itemId {
                noteCitation(recentBody, itemId: recent.itemId, dayKey: recent.dayKey)
            }
            if cited == 0 {
                Text("这两次练习没有笔记")
                    .font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            Text(ProjectNoteProjection.comparisonCitation(cited: cited, total: total))
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
    }

    private func noteCitation(_ body: String, itemId: UUID, dayKey: String) -> some View {
        Button {
            player.stop()
            router.recordPath.append(.practiceDetail(itemId: itemId))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(ProgressFirstFormat.monthDay(dayKey))
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
                Text(body)
                    .font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.brand500)
            }
            .padding(10)
            .background(GitaTheme.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius8))
        }
        .buttonStyle(.plain)
    }

    private func trackBlock(
        side: AudioComparisonPlayback.Side,
        title: String,
        track: AudioBenchmarkTrack,
        peaks: [Double]
    ) -> some View {
        let playing = playback.playing == side && player.playingId == side.rawValue
        let duration = TimeInterval(max(track.clip.durationSec, 0))
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(GitaFont.body(.semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Text("\(ProgressFirstFormat.monthDay(track.dayKey)) · \(track.createdAt.formatted(date: .omitted, time: .shortened))")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
                Text(confirmedFragment ?? "片段未确认")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 100, alignment: .leading)
            Button {
                toggle(side, track: track)
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
                    .frame(width: 40, height: 40)
                    .background(GitaTheme.brand50)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "暂停\(title)" : "播放\(title)")
            if !peaks.isEmpty {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    WaveformBars(peaks: peaks, progress: progress(for: side, duration: duration, playing: playing))
                }
                .frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)
            }
            Text(ProgressFirstFormat.clock(duration))
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textPrimary)
                .fixedSize()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .overlay(RoundedRectangle(cornerRadius: GitaTheme.radius16).stroke(GitaTheme.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
    }

    private func progress(for side: AudioComparisonPlayback.Side, duration: TimeInterval, playing: Bool) -> Double {
        if playing { return player.playbackFraction }
        guard duration > 0 else { return 0 }
        return min(1, playback.position(for: side) / duration)
    }

    private var canReplaceRecording: Bool {
        !AudioBenchmarkVersion.tracks(projectId: projectId, items: allSnapshots).isEmpty
    }

    private func header(showsReplace: Bool) -> some View {
        HStack {
            Button("返回") {
                player.stop()
                if !router.recordPath.isEmpty { router.recordPath.removeLast() }
            }
            .font(GitaFont.callout())
            .foregroundStyle(GitaTheme.textSecondary)
            .frame(minWidth: 44, alignment: .leading)
            Spacer(minLength: 0)
            Text("录音对比")
                .font(GitaFont.headline())
                .foregroundStyle(GitaTheme.textPrimary)
            Spacer(minLength: 0)
            if showsReplace {
                Button("更换录音") { showReplaceSheet = true }
                    .font(GitaFont.caption(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
                    .frame(minWidth: 44, alignment: .trailing)
            } else {
                Color.clear.frame(minWidth: 44)
            }
        }
        .frame(minHeight: 56)
        .padding(.horizontal, GitaTheme.pagePadding)
    }

    private var missing: some View {
        Text("项目不存在或已删除")
            .font(GitaFont.body())
            .foregroundStyle(GitaTheme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var replaceSheet: some View {
        let options = Array(AudioBenchmarkVersion.tracks(projectId: projectId, items: allSnapshots).reversed())
        return NavigationStack {
            List {
                Section("录音 A") {
                    ForEach(options) { track in
                        replaceRow(track, side: .a)
                    }
                }
                Section("录音 B") {
                    ForEach(options) { track in
                        replaceRow(track, side: .b)
                    }
                }
            }
            .navigationTitle("更换录音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showReplaceSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func replaceRow(_ track: AudioBenchmarkTrack, side: AudioComparisonPlayback.Side) -> some View {
        Button {
            applyReplacement(side, clipId: track.clip.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(GitaFont.body())
                    .foregroundStyle(GitaTheme.textPrimary)
                Text("\(ProgressFirstFormat.monthDay(track.dayKey)) \(track.createdAt.formatted(date: .omitted, time: .shortened)) · \(ProgressFirstFormat.recordingLabel(durationSec: track.clip.durationSec))")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
        }
    }

    private func applyReplacement(_ side: AudioComparisonPlayback.Side, clipId: String) {
        switch side {
        case .a:
            guard clipId != overrideRecentId else { return }
            if case .ready(_, let recent) = readiness, clipId == recent.clip.id { return }
            overrideStageId = clipId
            playback.positionA = 0
        case .b:
            guard clipId != overrideStageId else { return }
            if case .ready(let stage, _) = readiness, clipId == stage.clip.id { return }
            overrideRecentId = clipId
            playback.positionB = 0
        }
        player.stop()
        playback.pause()
        clearConfirmation()
        showReplaceSheet = false
    }

    private func loadPeaks(_ clip: PracticeRecordingClip) -> [Double] {
        guard !MediaReviewMedia.isVideo(fileName: clip.fileName) else { return [] }
        return WaveformSampler.peaks(
            fileURL: RecordingStore.url(for: clip.fileName),
            barCount: WaveformProgress.comparisonBarCount
        )
    }

    private func remember(_ side: AudioComparisonPlayback.Side) {
        guard player.playingId == side.rawValue else { return }
        let seconds = player.playbackSeconds
        switch side {
        case .a: playback.positionA = seconds
        case .b: playback.positionB = seconds
        }
    }

    private func toggle(_ side: AudioComparisonPlayback.Side, track: AudioBenchmarkTrack) {
        guard recordingAvailable(track) else { return }
        if playback.playing == side, player.playingId == side.rawValue {
            remember(side)
            playback.pause()
            player.stop()
            return
        }
        if let playing = playback.playing {
            remember(playing)
        }
        playback.play(side)
        let start = playback.position(for: side)
        player.play(url: RecordingStore.url(for: track.clip.fileName), id: side.rawValue, from: start)
    }

    private func alternate(stage: AudioBenchmarkTrack, recent: AudioBenchmarkTrack) {
        guard recordingAvailable(stage), recordingAvailable(recent) else { return }
        if let playing = playback.playing {
            remember(playing)
        }
        playback.alternate(
            durationA: TimeInterval(stage.clip.durationSec),
            durationB: TimeInterval(recent.clip.durationSec)
        )
        guard let side = playback.playing else { return }
        let track = side == .a ? stage : recent
        player.play(
            url: RecordingStore.url(for: track.clip.fileName),
            id: side.rawValue,
            from: playback.position(for: side)
        )
    }

    private func recordingAvailable(_ track: AudioBenchmarkTrack) -> Bool {
        guard RecordingStore.fileExists(fileName: track.clip.fileName) else {
            player.stop()
            playback.pause()
            invalidClipIds.insert(track.clip.id)
            showToast(String(localized: "录音文件不可用，请更换录音"))
            return false
        }
        return true
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

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }
}
