import SwiftData
import SwiftUI

struct AudioComparisonView: View {
    let projectId: UUID

    @Environment(AppRouter.self) private var router
    @Environment(PracticeStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Query private var projects: [Project]
    @Query(filter: #Predicate<PracticeItem> { $0.deletedAt == nil })
    private var practiceItems: [PracticeItem]

    @State private var player = AudioPlayerService()
    @State private var playback = AudioComparisonPlayback()
    @State private var overrideStageId: UUID?
    @State private var overrideRecentId: UUID?
    @State private var replacing: ReplaceSide?
    @State private var toast: String?
    @State private var creatingTodayLock = false
    @State private var peaksA: [Double] = []
    @State private var peaksB: [Double] = []

    private enum ReplaceSide: String, Identifiable {
        case stage
        case recent
        var id: String { rawValue }
    }

    init(projectId: UUID) {
        self.projectId = projectId
        _projects = Query(filter: #Predicate<Project> { $0.id == projectId && $0.deletedAt == nil })
    }

    private var calendar: Calendar { .current }
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

    private var readiness: AudioBenchmarkReadiness {
        AudioBenchmarkVersion.resolve(
            stageVersionItemId: snapshot?.stageVersionItemId,
            projectId: projectId,
            items: allSnapshots,
            overrideStageItemId: overrideStageId,
            overrideRecentItemId: overrideRecentId
        )
    }

    private var decision: ProjectPracticeStateHandoff.Decision? {
        guard let snapshot else { return nil }
        return ProjectPracticeStateHandoff.decide(
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
                        VStack(alignment: .leading, spacing: 16) {
                            Text(AudioBenchmarkVersion.subtitle(projectName: snapshot.name, focus: snapshot.currentFocus))
                                .font(GitaFont.callout())
                                .foregroundStyle(GitaTheme.textSecondary)
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
        .onDisappear { player.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.stop() }
        }
        .sheet(item: $replacing) { side in
            replaceSheet(side)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let decision, snapshot?.status == .active {
                Button {
                    runHandoff(decision)
                } label: {
                    Text(decision.buttonLabel)
                        .font(GitaFont.body(.bold))
                        .foregroundStyle(GitaTheme.brandOn)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
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
        case .unavailable:
            Text("还没有可以对照的录音")
                .font(GitaFont.body())
                .foregroundStyle(GitaTheme.textSecondary)
        }
    }

    private func readyBody(stage: AudioBenchmarkTrack, recent: AudioBenchmarkTrack) -> some View {
        let stageItem = allSnapshots.first { $0.id == stage.itemId }
        let recentItem = allSnapshots.first { $0.id == recent.itemId }
        let audioReady = stage.clip.durationSec > 0 && recent.clip.durationSec > 0
            && RecordingStore.fileExists(fileName: stage.clip.fileName)
            && RecordingStore.fileExists(fileName: recent.clip.fileName)
        let observation = AIAudioObservationRules.observe(
            stageNote: stageItem?.note ?? "",
            recentNote: recentItem?.note ?? "",
            stageDuration: TimeInterval(stage.clip.durationSec),
            recentDuration: TimeInterval(recent.clip.durationSec),
            audioAvailable: audioReady
        )
        let notes = ProjectNoteProjection.entries(projectId: projectId, items: allSnapshots)
        let cited = [stageItem?.note ?? "", recentItem?.note ?? ""]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        return VStack(alignment: .leading, spacing: 16) {
            Text(AudioBenchmarkVersion.listenHeadline(focus: snapshot?.currentFocus ?? ""))
                .font(GitaFont.headline())
                .foregroundStyle(GitaTheme.textPrimary)
            Text(AudioBenchmarkVersion.spanLine(stageDayKey: stage.dayKey, recentDayKey: recent.dayKey))
                .font(GitaFont.callout())
                .foregroundStyle(GitaTheme.textSecondary)
            Text(AudioBenchmarkVersion.sameFragmentNote)
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
            trackBlock(side: .a, title: "阶段版", track: stage, peaks: peaksA)
            trackBlock(side: .b, title: "最近录音", track: recent, peaks: peaksB)
            Button {
                alternate(stage: stage, recent: recent)
            } label: {
                Text("⇄ 交替听 A / B")
                    .font(GitaFont.callout(.bold))
                    .foregroundStyle(GitaTheme.brand500)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(GitaTheme.brand50)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            HStack(spacing: 16) {
                Button("更换录音") { replacing = .stage }
                Button("更换最近") { replacing = .recent }
            }
            .font(GitaFont.callout(.semibold))
            .foregroundStyle(GitaTheme.brand500)
            .buttonStyle(.plain)
            AIAudioObservationCard(observation: observation) { cue in
                let track = cue.side == .a ? stage : recent
                seek(cue, track: track)
            }
            notesBlock(cited: cited, total: notes.count)
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

    private func notesBlock(cited: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
            Text(ProjectNoteProjection.comparisonCitation(cited: cited, total: total))
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
    }

    private func trackBlock(
        side: AudioComparisonPlayback.Side,
        title: String,
        track: AudioBenchmarkTrack,
        peaks: [Double]
    ) -> some View {
        let playing = playback.playing == side && player.playingId == side.rawValue
        let duration = TimeInterval(max(track.clip.durationSec, 0))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(GitaFont.body(.semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer(minLength: 8)
                Text(ProgressFirstFormat.monthDay(track.dayKey))
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            Text(track.title)
                .font(GitaFont.callout())
                .foregroundStyle(GitaTheme.textPrimary)
            HStack(spacing: 10) {
                Button {
                    toggle(side, track: track)
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GitaTheme.brand500)
                        .frame(width: 28, height: 28)
                        .background(GitaTheme.brand50)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Text(ProgressFirstFormat.recordingLabel(durationSec: track.clip.durationSec))
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            if !peaks.isEmpty {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    WaveformBars(peaks: peaks, progress: progress(for: side, duration: duration, playing: playing))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
    }

    private func progress(for side: AudioComparisonPlayback.Side, duration: TimeInterval, playing: Bool) -> Double {
        if playing { return player.playbackFraction }
        guard duration > 0 else { return 0 }
        return min(1, playback.position(for: side) / duration)
    }

    private var header: some View {
        HStack {
            Button("返回") {
                player.stop()
                if !router.recordPath.isEmpty { router.recordPath.removeLast() }
            }
            .font(GitaFont.callout())
            .foregroundStyle(GitaTheme.textSecondary)
            .frame(minWidth: 44, alignment: .leading)
            Spacer(minLength: 0)
            Text("对照")
                .font(GitaFont.headline())
                .foregroundStyle(GitaTheme.textPrimary)
            Spacer(minLength: 0)
            Color.clear.frame(minWidth: 44)
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

    private func replaceSheet(_ side: ReplaceSide) -> some View {
        let options = Array(AudioBenchmarkVersion.tracks(projectId: projectId, items: allSnapshots).reversed())
        return NavigationStack {
            List(options) { track in
                Button {
                    applyReplacement(side, itemId: track.itemId)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(GitaFont.body())
                            .foregroundStyle(GitaTheme.textPrimary)
                        Text("\(ProgressFirstFormat.monthDay(track.dayKey)) · \(ProgressFirstFormat.recordingLabel(durationSec: track.clip.durationSec))")
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)
                    }
                }
            }
            .navigationTitle("更换录音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { replacing = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func applyReplacement(_ side: ReplaceSide, itemId: UUID) {
        switch side {
        case .stage:
            guard itemId != overrideRecentId else { return }
            if case .ready(_, let recent) = readiness, itemId == recent.itemId { return }
            overrideStageId = itemId
        case .recent:
            guard itemId != overrideStageId else { return }
            if case .ready(let stage, _) = readiness, itemId == stage.itemId { return }
            overrideRecentId = itemId
        }
        player.stop()
        playback.pause()
        replacing = nil
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

    private func seek(_ cue: AIAudioCue, track: AudioBenchmarkTrack) {
        guard let seconds = cue.seconds else { return }
        playback.seekAndPlay(cue.side, seconds: seconds, duration: TimeInterval(track.clip.durationSec))
        player.play(
            url: RecordingStore.url(for: track.clip.fileName),
            id: cue.side.rawValue,
            from: playback.position(for: cue.side)
        )
    }

    private func runHandoff(_ decision: ProjectPracticeStateHandoff.Decision) {
        guard !creatingTodayLock else { return }
        creatingTodayLock = true
        defer { creatingTodayLock = false }
        player.stop()
        do {
            try ProjectPracticeHandoffAction.perform(
                projectId: projectId,
                decision: decision,
                store: store,
                router: router,
                now: Date(),
                calendar: calendar
            )
        } catch {
            showToast("创建失败，请重试")
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
