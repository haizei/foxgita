import SwiftUI

struct AIAudioObservationCard: View {
    let observation: AIAudioObservation
    let onSeek: (AIAudioCue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AIAudioObservation.header)
                .font(GitaFont.body(.semibold))
                .foregroundStyle(GitaTheme.textPrimary)
            Text(observation.conclusion)
                .font(GitaFont.body())
                .foregroundStyle(GitaTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if observation.usesAudioTimestamps {
                HStack(spacing: 12) {
                    cueButton(observation.stageCue)
                    cueButton(observation.recentCue)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("分段预览")
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                    WaveformBars(
                        peaks: Array(repeating: 0.45, count: 12),
                        progress: 0.34
                    )
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius16))
        .shadow(color: GitaTheme.shadowCard, radius: 6, y: 3)
    }

    private func cueButton(_ cue: AIAudioCue) -> some View {
        Button {
            onSeek(cue)
        } label: {
            Text("▶ \(cue.caption)")
                .font(GitaFont.caption(.semibold))
                .foregroundStyle(GitaTheme.brand500)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(GitaTheme.brand50)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
