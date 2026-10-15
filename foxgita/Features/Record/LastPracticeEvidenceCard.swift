import SwiftUI

struct LastPracticeEvidenceCard: View {
    let evidence: LastPracticeEvidence
    let benchmark: AudioBenchmarkReadiness
    var player: AudioPlayerService
    let onCompare: () -> Void
    let onPlayVideo: (URL) -> Void
    let onPlaybackFailed: () -> Void

    @State private var peaks: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("♫")
                    .font(GitaFont.body())
                    .foregroundStyle(GitaTheme.brand500)
                Text("上次练习")
                    .font(GitaFont.body(.semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
            }
            Text(evidence.dateAndDuration)
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
            Text(evidence.title)
                .font(GitaFont.body(.bold))
                .foregroundStyle(GitaTheme.textPrimary)
            if !evidence.content.isEmpty, evidence.content != evidence.title {
                Text(evidence.content)
                    .font(GitaFont.body())
                    .foregroundStyle(GitaTheme.textPrimary)
            }
            if !evidence.reflection.isEmpty {
                Text(evidence.reflection)
                    .font(GitaFont.body())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            if let recording = evidence.recording {
                playerBlock(recording)
                switch benchmark {
                case .ready:
                    Button(action: onCompare) {
                        Text(AudioBenchmarkVersion.compareLink)
                            .font(GitaFont.callout(.semibold))
                            .foregroundStyle(GitaTheme.brand500)
                    }
                    .buttonStyle(.plain)
                case .needsAnotherRecording:
                    Text(AudioBenchmarkVersion.needsAnotherCopy)
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                case .unavailable:
                    EmptyView()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
        .task(id: evidence.recording?.id) {
            guard let recording = evidence.recording, !MediaReviewMedia.isVideo(fileName: recording.fileName) else {
                peaks = []
                return
            }
            let url = RecordingStore.url(for: recording.fileName)
            peaks = WaveformSampler.peaks(fileURL: url, barCount: WaveformProgress.evidenceBarCount)
        }
        .task(id: player.playingId) {
            while player.playingId == evidence.recording?.id, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                player.finishIfNeeded()
            }
        }
    }

    @ViewBuilder
    private func playerBlock(_ recording: PracticeRecordingClip) -> some View {
        let playing = player.playingId == recording.id
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    toggle(recording)
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GitaTheme.brand500)
                        .frame(width: 28, height: 28)
                        .background(GitaTheme.brand50)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playing ? "暂停" : "播放")
                if let label = evidence.recordingLabel {
                    Text(label)
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
            }
            if !MediaReviewMedia.isVideo(fileName: recording.fileName), !peaks.isEmpty {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    WaveformBars(
                        peaks: peaks,
                        progress: playing ? player.playbackFraction : 0
                    )
                }
            }
        }
    }

    private func toggle(_ recording: PracticeRecordingClip) {
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
