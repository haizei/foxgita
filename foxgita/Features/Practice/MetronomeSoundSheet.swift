//
//  MetronomeSoundSheet.swift
//  foxgita
//

import SwiftUI

struct MetronomeSoundSheet: View {
    let metronome: MetronomeEngine
    var onDone: () -> Void
    @State private var previewError: String?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: GitaTheme.s8), count: 3
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GitaTheme.s12) {
                    Text(String(localized: "音效选择"))
                        .font(GitaFont.headline())
                        .foregroundStyle(GitaTheme.textPrimary)

                    LazyVGrid(columns: columns, spacing: GitaTheme.s8) {
                        ForEach(MetronomeSoundPreset.allCases) { preset in
                            presetCard(preset)
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
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.visible)
        .alert(
            String(localized: "无法试听"),
            isPresented: Binding(
                get: { previewError != nil },
                set: { if !$0 { previewError = nil } }
            )
        ) {
            Button(String(localized: "知道了"), role: .cancel) { previewError = nil }
        } message: {
            Text(previewError ?? "")
        }
    }

    private func presetCard(_ preset: MetronomeSoundPreset) -> some View {
        let selected = metronome.soundPreset == preset
        return Button {
            metronome.setSoundPreset(preset)
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(preset.displayName)
                    .font(GitaFont.callout())
                    .foregroundStyle(selected ? GitaTheme.brand500 : GitaTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GitaTheme.brand500)
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(selected ? GitaTheme.brand50 : GitaTheme.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? GitaTheme.brand500 : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.displayName)
        .accessibilityValue(selected ? String(localized: "已选择") : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
            do {
                try metronome.preview(bars: 2)
            } catch {
                previewError = String(localized: "节拍声音加载失败，请重试。")
            }
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
