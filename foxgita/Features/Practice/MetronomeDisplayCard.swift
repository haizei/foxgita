//
//  MetronomeDisplayCard.swift
//  foxgita
//

import SwiftUI

struct MetronomeDisplayCard: View {
    let metronome: MetronomeEngine
    let timeSignature: String

    private var meterText: String {
        let trimmed = timeSignature.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "4/4" : trimmed
    }

    private var activeBeat: Int? {
        metronome.isPlaying ? metronome.currentBeatInBar : nil
    }

    var body: some View {
        VStack(spacing: GitaTheme.s12) {
            labelRow
            valueRow
            beatBars
            beatTrack
        }
        .padding(.horizontal, GitaTheme.s12)
        .padding(.vertical, 10)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var labelRow: some View {
        HStack(spacing: 0) {
            metricLabel(String(localized: "速度 (BPM)"))
                .frame(maxWidth: .infinity, alignment: .leading)
            metricLabel(String(localized: "拍号"))
                .frame(width: 76)
            metricLabel(String(localized: "切分"))
                .frame(width: 76, alignment: .trailing)
        }
    }

    private var valueRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
                Text("\(metronome.bpm)")
                    .font(GitaFont.timer(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
                Text(MetronomeTempoName.name(for: metronome.bpm))
                    .font(GitaFont.micro())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(meterText)
                .font(GitaFont.timer(.semibold))
                .foregroundStyle(GitaTheme.brand500)
                .frame(width: 76)

            Image(systemName: "music.note")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GitaTheme.brand500)
                .frame(width: 76)
        }
    }

    private var beatBars: some View {
        HStack(spacing: GitaTheme.s8) {
            ForEach(0..<4, id: \.self) { index in
                beatBar(index: index)
            }
        }
        .frame(height: 58)
        .animation(.easeInOut(duration: 0.12), value: activeBeat)
        .animation(.easeInOut(duration: 0.12), value: metronome.isPlaying)
    }

    private func beatBar(index: Int) -> some View {
        let isActive = activeBeat == index
        let fill = barFill(for: index, isActive: isActive)
        return RoundedRectangle(cornerRadius: GitaTheme.radius8)
            .fill(GitaTheme.brand50)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: GitaTheme.radius8)
                    .fill(isActive ? GitaTheme.brand500 : GitaTheme.brand50.opacity(0.85))
                    .frame(height: 58 * fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius8))
            .accessibilityHidden(true)
    }

    private func barFill(for index: Int, isActive: Bool) -> CGFloat {
        if isActive { return 0.72 }
        if !metronome.isPlaying && index == 0 { return 0.18 }
        return 0.12
    }

    private var beatTrack: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                let emphasized = trackDotEmphasized(index: index)
                Circle()
                    .fill(emphasized ? GitaTheme.brand500 : GitaTheme.borderInactive)
                    .frame(
                        width: emphasized ? 8 : 6,
                        height: emphasized ? 8 : 6
                    )
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, GitaTheme.s8)
        .background(GitaTheme.bgSubtle)
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.12), value: activeBeat)
    }

    private func trackDotEmphasized(index: Int) -> Bool {
        if let activeBeat { return index == activeBeat }
        return index == 0
    }

    private func metricLabel(_ text: String) -> some View {
        Text(text)
            .font(GitaFont.micro())
            .foregroundStyle(GitaTheme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(GitaTheme.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var accessibilitySummary: String {
        String(
            localized: "节拍器，\(metronome.bpm) BPM，\(meterText) 拍，四分音符",
            comment: "Metronome display card accessibility label"
        )
    }
}

#Preview {
    MetronomeDisplayCard(
        metronome: MetronomeEngine(),
        timeSignature: "4/4"
    )
    .padding()
    .background(GitaTheme.bgDefault)
}
