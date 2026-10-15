import SwiftUI

struct LastPracticeEvidenceCard: View {
    let evidence: LastPracticeEvidence
    let benchmark: AudioBenchmarkReadiness
    var player: AudioPlayerService
    let onCompare: () -> Void
    let onPlayVideo: (URL) -> Void
    let onPlaybackFailed: () -> Void

    @State private var peaks: [Double] = []
    @State private var recordingBecameUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("上次练习")
                    .font(GitaFont.headline())
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer(minLength: 8)
                Text(evidence.dateAndDuration)
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(GitaTheme.brand500)
                        .frame(width: 44, height: 44)
                        .background(GitaTheme.brand50)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(evidence.title)
                            .font(GitaFont.body(.semibold))
                            .foregroundStyle(GitaTheme.textPrimary)
                        if !evidence.content.isEmpty, evidence.content != evidence.title {
                            Text(evidence.content)
                                .font(GitaFont.caption())
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                        if !evidence.reflection.isEmpty {
                            Text(evidence.reflection)
                                .font(GitaFont.caption())
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                    }
                }
                if let recording = evidence.recording, !recordingBecameUnavailable {
                    playerBlock(recording)
                    if case .needsAnotherRecording = benchmark,
                       !MediaReviewMedia.isVideo(fileName: recording.fileName) {
                        Text(AudioBenchmarkVersion.needsAnotherCopy)
                            .font(GitaFont.caption())
                            .foregroundStyle(GitaTheme.textSecondary)
                    }
                } else if recordingBecameUnavailable || evidence.hadRecording {
                    Text("录音文件不可用，可在原练习记录中检查")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GitaTheme.bgSurface)
            .overlay(RoundedRectangle(cornerRadius: GitaTheme.radius12).stroke(GitaTheme.brand500.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))
        }
        .task(id: evidence.recording?.id) {
            recordingBecameUnavailable = false
            guard let recording = evidence.recording, !MediaReviewMedia.isVideo(fileName: recording.fileName) else {
                peaks = []
                return
            }
            peaks = WaveformSampler.peaks(
                fileURL: RecordingStore.url(for: recording.fileName),
                barCount: WaveformProgress.evidenceBarCount
            )
        }
        .task(id: player.playingId) {
            while player.playingId == evidence.recording?.id, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                player.finishIfNeeded()
            }
        }
    }

    private func playerBlock(_ recording: PracticeRecordingClip) -> some View {
        let playing = player.playingId == recording.id
        let canCompare: Bool = {
            guard !MediaReviewMedia.isVideo(fileName: recording.fileName) else { return false }
            if case .ready = benchmark { return true }
            return false
        }()
        return HStack(spacing: 8) {
            Button {
                toggle(recording)
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(width: 36, height: 36)
                    .background(GitaTheme.brand500)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "暂停上次录音" : "播放上次录音")
            if !peaks.isEmpty {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    WaveformBars(peaks: peaks, progress: playing ? player.playbackFraction : 0)
                }
                .frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)
            }
            if let label = evidence.recordingLabel {
                Text(label)
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .fixedSize()
            }
            if canCompare {
                Button(AudioBenchmarkVersion.compareLink, action: onCompare)
                    .font(GitaFont.caption(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 32)
                    .overlay(Capsule().stroke(GitaTheme.brand500, lineWidth: 1))
                    .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(GitaTheme.bgDefault)
        .clipShape(Capsule())
    }

    private func toggle(_ recording: PracticeRecordingClip) {
        guard RecordingStore.fileExists(fileName: recording.fileName) else {
            player.stop()
            recordingBecameUnavailable = true
            onPlaybackFailed()
            return
        }
        let url = RecordingStore.url(for: recording.fileName)
        if MediaReviewMedia.isVideo(fileName: recording.fileName) {
            player.stop()
            onPlayVideo(url)
            return
        }
        if player.playingId == recording.id {
            player.stop()
            return
        }
        let before = player.playingId
        player.play(url: url, id: recording.id, from: nil)
        if RecordPlayback.startFailed(
            playingIdBefore: before,
            intendedId: recording.id,
            playingIdAfter: player.playingId
        ) {
            onPlaybackFailed()
        }
    }
}
