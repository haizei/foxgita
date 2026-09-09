//
//  MetronomeDisplayCard.swift
//  foxgita
//

import SwiftUI

struct MetronomeDisplayCard: View {
    let metronome: MetronomeEngine
    var onEntryTap: (MetronomeSheetAnchor) -> Void = { _ in }
    var onSoundTap: () -> Void = {}

    @State private var isBeatFlashing = false

    private var meterText: String { metronome.timeSignatureText }

    private var activeBeat: Int? {
        metronome.isPlaying ? metronome.currentBeatInBar : nil
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                entryColumn(anchor: .speed, label: String(localized: "速度 (BPM)")) {
                    speedValue
                }

                entryColumn(anchor: .meter, label: String(localized: "拍号")) {
                    Text(meterText)
                        .font(GitaFont.largeTitle(.bold))
                        .foregroundStyle(GitaTheme.brand500)
                        .monospacedDigit()
                        .frame(height: 40)
                }

                entryColumn(anchor: .subdivision, label: String(localized: "音符")) {
                    Image(metronome.subdivision.assetName)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(GitaTheme.brand500)
                        .frame(width: 28, height: 28)
                        .frame(height: 40)
                }

                soundColumn
            }

            beatBars
            beatTrack
        }
        .padding(.horizontal, GitaTheme.s16)
        .padding(.vertical, 12)
        .frame(height: 214)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius24))
        .overlay {
            RoundedRectangle(cornerRadius: GitaTheme.radius24)
                .stroke(GitaTheme.borderSubtle, lineWidth: 1)
        }
        .shadow(color: GitaTheme.shadowCard, radius: 16, y: 4)
        .onChange(of: metronome.currentBeatInBar) { _, _ in
            guard metronome.isPlaying else { return }
            isBeatFlashing = true
            withAnimation(.easeOut(duration: 0.18)) {
                isBeatFlashing = false
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var speedValue: some View {
        HStack(spacing: 4) {
            Image("MetronomeSpeedIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
            Text("\(metronome.bpm)")
                .font(GitaFont.largeTitle(.bold))
                .foregroundStyle(GitaTheme.brand500)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(height: 40)
    }

    private var soundColumn: some View {
        Button(action: onSoundTap) {
            VStack(spacing: 4) {
                metricLabel(String(localized: "声音"))
                Image("MetronomeSoundIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .frame(height: 40)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "声音，打开节拍提示")))
    }

    private func entryColumn<Content: View>(
        anchor: MetronomeSheetAnchor,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            onEntryTap(anchor)
        } label: {
            VStack(spacing: 4) {
                metricLabel(label)
                content()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(label)，打开节拍器设置"))
    }

    private var beatBars: some View {
        HStack(spacing: GitaTheme.s8) {
            ForEach(0..<metronome.beatsPerBar, id: \.self) { index in
                beatBar(index: index)
            }
        }
        .frame(height: 80)
        .animation(.easeInOut(duration: 0.12), value: activeBeat)
        .animation(.easeInOut(duration: 0.12), value: metronome.beatsPerBar)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: metronome.accentPattern)
    }

    private func beatBar(index: Int) -> some View {
        let isActive = activeBeat == index
        let fillRatio = barHeightRatio(for: index)
        let fillColor = barFillColor(for: index, isActive: isActive)
        let markerColor = isActive ? GitaTheme.brand500 : GitaTheme.borderSubtle

        return RoundedRectangle(cornerRadius: GitaTheme.radius8)
            .fill(GitaTheme.bgSubtle)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(markerColor)
                    .frame(height: 2)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(fillColor)
                    .frame(height: 80 * fillRatio)
            }
            .overlay {
                if metronome.flashOnAccent, isActive, fillRatio >= 0.72 {
                    RoundedRectangle(cornerRadius: GitaTheme.radius8)
                        .fill(Color.white.opacity(0.35))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: GitaTheme.radius8)
                    .stroke(GitaTheme.borderSubtle, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius8))
            .animation(.easeOut(duration: 0.08), value: activeBeat)
            .accessibilityHidden(true)
    }

    private func barHeightRatio(for index: Int) -> CGFloat {
        guard metronome.accentPattern.indices.contains(index) else {
            return 1.0 / 3.0
        }
        return metronome.accentPattern[index].heightRatio
    }

    private func barFillColor(for index: Int, isActive: Bool) -> Color {
        guard metronome.accentPattern.indices.contains(index) else {
            return GitaTheme.categoryOrangeSoft
        }
        if isActive {
            return GitaTheme.brand500
        }
        let kind = metronome.accentPattern[index]
        if kind == .mute {
            return Color.clear
        }
        return GitaTheme.categoryOrangeSoft
    }

    private var beatTrack: some View {
        RoundedRectangle(cornerRadius: GitaTheme.radius8)
            .fill(isBeatFlashing ? GitaTheme.brand500 : GitaTheme.bgSubtle)
            .frame(height: 24)
            .accessibilityHidden(true)
    }

    private func metricLabel(_ text: String) -> some View {
        Text(text)
            .font(GitaFont.micro())
            .foregroundStyle(GitaTheme.textSecondary)
            .frame(height: 22)
    }
}

#Preview("Default") {
    MetronomeDisplayCard(metronome: MetronomeEngine())
        .padding()
        .background(GitaTheme.bgDefault)
}
