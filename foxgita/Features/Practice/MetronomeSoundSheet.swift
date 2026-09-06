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
                VStack(alignment: .leading, spacing: GitaTheme.s12) {
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
                    strongBeatCard
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
                modeIcon(mode, selected: selected)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(GitaFont.headline())
                        .foregroundStyle(GitaTheme.textPrimary)
                    Text(mode.subtitle)
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(GitaTheme.brand500)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(selected ? GitaTheme.brand50 : GitaTheme.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func modeIcon(_ mode: MetronomeSoundMode, selected: Bool) -> some View {
        ZStack(alignment: .bottom) {
            Image(mode.iconAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
            RoundedRectangle(cornerRadius: 2)
                .fill(audibilityMarkColor(mode: mode, selected: selected))
                .frame(width: audibilityMarkWidth(mode: mode, selected: selected), height: 4)
                .offset(y: -10)
        }
        .frame(width: 36, height: 36)
    }

    private func audibilityMarkColor(mode: MetronomeSoundMode, selected: Bool) -> Color {
        if mode == .acousticGuitar, selected {
            return GitaTheme.brandOn
        }
        return GitaTheme.brand500
    }

    private func audibilityMarkWidth(mode: MetronomeSoundMode, selected: Bool) -> CGFloat {
        if mode == .acousticGuitar, selected { return 18 }
        return 13
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: GitaTheme.s8) {
            HStack {
                Text(String(localized: "音量"))
                    .font(GitaFont.headline())
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer()
                Text("\(metronome.volume)%")
                    .font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.brand500)
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
        .padding(.top, GitaTheme.s8)
    }

    private var previewButton: some View {
        Button {
            try? metronome.preview(bars: 2)
        } label: {
            Text(String(localized: "试听节拍"))
                .font(GitaFont.headline())
                .foregroundStyle(GitaTheme.brandOn)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(GitaTheme.brand500)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(metronome.isPlaying)
        .opacity(metronome.isPlaying ? 0.4 : 1)
    }

    private var strongBeatCard: some View {
        HStack(alignment: .center, spacing: GitaTheme.s12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "强拍增强"))
                    .font(GitaFont.headline())
                    .foregroundStyle(GitaTheme.textPrimary)
                Text(String(localized: "让每小节第一拍更突出"))
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { metronome.strongBeatBoost },
                set: { metronome.setStrongBeatBoost($0) }
            ))
            .labelsHidden()
            .tint(GitaTheme.brand500)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    MetronomeSoundSheet(metronome: MetronomeEngine(), onDone: {})
}
