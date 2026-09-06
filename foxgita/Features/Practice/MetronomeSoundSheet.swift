//
//  MetronomeSoundSheet.swift
//  foxgita
//

import SwiftUI

struct MetronomeSoundSheet: View {
    let metronome: MetronomeEngine
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GitaTheme.s20) {
                    Text(String(localized: "选择更适合当前练习环境的节拍声"))
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)

                    VStack(spacing: GitaTheme.s12) {
                        ForEach(MetronomeSoundMode.allCases) { mode in
                            modeCard(mode)
                        }
                    }

                    volumeSection
                    previewButton
                    strongBeatToggle
                }
                .padding(.horizontal, GitaTheme.s20)
                .padding(.bottom, GitaTheme.s24)
            }
            .background(GitaTheme.bgSurface)
            .navigationTitle(String(localized: "节拍提示"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "完成"), action: onDone)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.fraction(0.6)])
        .presentationDragIndicator(.visible)
    }

    private func modeCard(_ mode: MetronomeSoundMode) -> some View {
        let selected = metronome.soundMode == mode
        return Button {
            metronome.setSoundMode(mode)
        } label: {
            HStack(spacing: GitaTheme.s12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(modeMarkColor(mode))
                    .frame(width: 4, height: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(GitaFont.body(.semibold))
                        .foregroundStyle(GitaTheme.textPrimary)
                    Text(mode.subtitle)
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(GitaTheme.brand500)
                }
            }
            .padding(.horizontal, GitaTheme.s16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(selected ? GitaTheme.brand50 : GitaTheme.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func modeMarkColor(_ mode: MetronomeSoundMode) -> Color {
        switch mode {
        case .standard: GitaTheme.brand500
        case .acousticGuitar: Color.orange
        case .drums: Color.brown
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: GitaTheme.s8) {
            HStack {
                Text(String(localized: "音量"))
                    .font(GitaFont.body(.semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer()
                Text("\(metronome.volume)%")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { Double(metronome.volume) },
                    set: { metronome.setVolume(Int($0.rounded())) }
                ),
                in: 0...100,
                step: 1
            )
            .tint(GitaTheme.brand500)
        }
    }

    private var previewButton: some View {
        Button {
            try? metronome.preview(bars: 2)
        } label: {
            Text(String(localized: "试听节拍"))
                .font(GitaFont.body(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(GitaTheme.brand500)
        .disabled(metronome.isPlaying)
    }

    private var strongBeatToggle: some View {
        Toggle(isOn: Binding(
            get: { metronome.strongBeatBoost },
            set: { metronome.setStrongBeatBoost($0) }
        )) {
            Text(String(localized: "让每小节第一拍更突出"))
                .font(GitaFont.body())
                .foregroundStyle(GitaTheme.textPrimary)
        }
        .tint(GitaTheme.brand500)
    }
}
