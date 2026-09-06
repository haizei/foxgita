//
//  MetronomeDisplayCard.swift
//  foxgita
//

import SwiftUI

struct MetronomeDisplayCard: View {
    let metronome: MetronomeEngine
    var onEntryTap: (MetronomeSheetAnchor) -> Void = { _ in }
    var onSoundTap: () -> Void = {}

    private var meterText: String { metronome.timeSignatureText }

    private var activeBeat: Int? {
        metronome.isPlaying ? metronome.currentBeatInBar : nil
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                entryColumn(anchor: .speed, label: String(localized: "速度 (BPM)")) {
                    speedValue
                }
                .frame(maxWidth: .infinity)

                entryColumn(anchor: .meter, label: String(localized: "拍号")) {
                    Text(meterText)
                        .font(GitaFont.largeTitle(.bold))
                        .foregroundStyle(GitaTheme.brand500)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)

                entryColumn(anchor: .subdivision, label: String(localized: "音符")) {
                    Image(metronome.subdivision.assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
                .frame(maxWidth: .infinity)

                soundColumn
                    .frame(maxWidth: .infinity)
            }

            beatBars
            beatTrack
        }
        .padding(.horizontal, GitaTheme.s12)
        .padding(.vertical, 10)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius24))
        .overlay {
            RoundedRectangle(cornerRadius: GitaTheme.radius24)
                .stroke(GitaTheme.borderSubtle, lineWidth: 1)
        }
        .shadow(color: GitaTheme.shadowCard, radius: 16, y: 4)
        .accessibilityElement(children: .contain)
    }

    private var speedValue: some View {
        HStack(spacing: 0) {
            Image("MetronomeSpeedIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            Text("\(metronome.bpm)")
                .font(GitaFont.largeTitle(.bold))
                .foregroundStyle(GitaTheme.brand500)
                .monospacedDigit()
        }
        .frame(height: 40)
    }

    private var soundColumn: some View {
        Button(action: onSoundTap) {
            VStack(spacing: 6) {
                metricLabel(String(localized: "声音"))
                Image("MetronomeSoundIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
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
            VStack(spacing: 6) {
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
        .frame(height: 58)
        .animation(.easeInOut(duration: 0.12), value: activeBeat)
        .animation(.easeInOut(duration: 0.12), value: metronome.beatsPerBar)
        .animation(.easeInOut(duration: 0.12), value: metronome.accentPattern)
    }

    private func beatBar(index: Int) -> some View {
        let isActive = activeBeat == index
        let fillHeight = barFill(for: index, isActive: isActive)
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
                    .frame(height: 58 * fillHeight)
            }
            .overlay {
                if metronome.flashOnAccent, isActive, accentBarFill(for: index) >= 0.72 {
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

    private func barFillColor(for index: Int, isActive: Bool) -> Color {
        guard metronome.accentPattern.indices.contains(index) else {
            return GitaTheme.categoryOrangeSoft
        }
        if isActive, metronome.accentPattern[index] == .accent {
            return GitaTheme.brand500
        }
        return GitaTheme.categoryOrangeSoft
    }

    private func barFill(for index: Int, isActive: Bool) -> CGFloat {
        if isActive { return accentBarFill(for: index) }
        if !metronome.isPlaying && index == 0 { return 38 / 58 }
        return idleBarFill(for: index)
    }

    private func accentBarFill(for index: Int) -> CGFloat {
        guard metronome.accentPattern.indices.contains(index) else { return 0.72 }
        switch metronome.accentPattern[index] {
        case .accent: return 38 / 58
        case .normal: return 22 / 58
        case .mute: return 0.12
        }
    }

    private func idleBarFill(for index: Int) -> CGFloat {
        guard metronome.accentPattern.indices.contains(index) else { return 0.12 }
        switch metronome.accentPattern[index] {
        case .accent: return 22 / 58
        case .normal: return 56 / 58
        case .mute: return 0.06
        }
    }

    private var beatTrack: some View {
        Group {
            if metronome.beatsPerBar == 4 {
                beatTrackAsset
            } else {
                beatTrackProgrammatic
            }
        }
        .animation(.easeInOut(duration: 0.12), value: activeBeat)
    }

    private static let beatTrackDotPositions: [CGFloat] = [44 / 346, 131 / 346, 219 / 346, 307 / 346]

    private var beatTrackAsset: some View {
        GeometryReader { geo in
            ZStack {
                Image("MetronomeBeatTrack")
                    .resizable()
                    .scaledToFill()

                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(GitaTheme.bgSubtle)
                        .frame(width: 10, height: 10)
                        .position(
                            x: geo.size.width * Self.beatTrackDotPositions[index],
                            y: geo.size.height * (14 / 24)
                        )
                }

                ForEach(0..<4, id: \.self) { index in
                    let emphasized = trackDotEmphasized(index: index)
                    Circle()
                        .fill(emphasized ? GitaTheme.brand500 : GitaTheme.borderInactive)
                        .frame(
                            width: emphasized ? 8 : 6,
                            height: emphasized ? 8 : 6
                        )
                        .position(
                            x: geo.size.width * Self.beatTrackDotPositions[index],
                            y: geo.size.height * (14 / 24)
                        )
                }
            }
        }
        .frame(height: 24)
    }

    private var beatTrackProgrammatic: some View {
        HStack(spacing: 0) {
            ForEach(0..<metronome.beatsPerBar, id: \.self) { index in
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
    }

    private func trackDotEmphasized(index: Int) -> Bool {
        if let activeBeat { return index == activeBeat }
        guard metronome.accentPattern.indices.contains(index) else { return index == 0 }
        return metronome.accentPattern[index] == .accent
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
