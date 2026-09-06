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
        VStack(spacing: GitaTheme.s12) {
            HStack(spacing: 0) {
                entryColumn(anchor: .speed, label: String(localized: "速度")) {
                    VStack(spacing: 2) {
                        Text("\(metronome.bpm)")
                            .font(GitaFont.timer(.semibold))
                            .foregroundStyle(GitaTheme.brand500)
                        Text(MetronomeTempoName.name(for: metronome.bpm))
                            .font(GitaFont.micro())
                            .foregroundStyle(GitaTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity)

                entryColumn(anchor: .meter, label: String(localized: "拍号")) {
                    Text(meterText)
                        .font(GitaFont.timer(.semibold))
                        .foregroundStyle(GitaTheme.brand500)
                }
                .frame(maxWidth: .infinity)

                entryColumn(anchor: .subdivision, label: String(localized: "音符")) {
                    Image(metronome.subdivision.assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 18)
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
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
        .accessibilityElement(children: .contain)
    }

    private var soundColumn: some View {
        Button(action: onSoundTap) {
            VStack(spacing: 6) {
                metricLabel(String(localized: "声音"))
                Image("MetronomeSoundIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 18)
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
        let fill = barFill(for: index, isActive: isActive)
        return RoundedRectangle(cornerRadius: GitaTheme.radius8)
            .fill(GitaTheme.brand50)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: GitaTheme.radius8)
                    .fill(isActive ? GitaTheme.brand500 : GitaTheme.brand50.opacity(0.85))
                    .frame(height: 58 * fill)
            }
            .overlay {
                if metronome.flashOnAccent, isActive, accentBarFill(for: index) >= 0.72 {
                    RoundedRectangle(cornerRadius: GitaTheme.radius8)
                        .fill(Color.white.opacity(0.35))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius8))
            .animation(.easeOut(duration: 0.08), value: activeBeat)
            .accessibilityHidden(true)
    }

    private func barFill(for index: Int, isActive: Bool) -> CGFloat {
        if isActive { return accentBarFill(for: index) }
        if !metronome.isPlaying && index == 0 { return 0.18 }
        return idleBarFill(for: index)
    }

    private func accentBarFill(for index: Int) -> CGFloat {
        guard metronome.accentPattern.indices.contains(index) else { return 0.72 }
        switch metronome.accentPattern[index] {
        case .accent: return 0.72
        case .normal: return 0.52
        case .mute: return 0.28
        }
    }

    private func idleBarFill(for index: Int) -> CGFloat {
        guard metronome.accentPattern.indices.contains(index) else { return 0.12 }
        switch metronome.accentPattern[index] {
        case .accent: return 0.18
        case .normal: return 0.12
        case .mute: return 0.06
        }
    }

    private var beatTrack: some View {
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
        .animation(.easeInOut(duration: 0.12), value: activeBeat)
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
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(GitaTheme.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    MetronomeDisplayCard(
        metronome: MetronomeEngine()
    )
    .padding()
    .background(GitaTheme.bgDefault)
}
