//
//  MetronomeSettingsSheet.swift
//  foxgita
//

import SwiftUI

struct MetronomeSettingsSheet: View {
    let metronome: MetronomeEngine
    let anchor: MetronomeSheetAnchor
    let meterText: String
    var onDone: () -> Void

    private let subdivisionCellCount = 8
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: GitaTheme.s20) {
                        bpmSection
                            .id(MetronomeSheetAnchor.speed.scrollSectionID)
                        meterSection
                            .id(MetronomeSheetAnchor.meter.scrollSectionID)
                        subdivisionSection
                            .id(MetronomeSheetAnchor.subdivision.scrollSectionID)
                    }
                    .padding(.horizontal, GitaTheme.s20)
                    .padding(.bottom, GitaTheme.s24)
                }
                .onAppear {
                    scrollToAnchor(proxy)
                }
            }
            .background(GitaTheme.bgSurface)
            .navigationTitle(String(localized: "节拍器设置"))
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

    private var bpmSection: some View {
        VStack(spacing: GitaTheme.s8) {
            HStack {
                stepButton("－", accent: false, enabled: metronome.bpm > 40) {
                    metronome.bump(-1)
                }
                VStack(spacing: 2) {
                    Text("\(metronome.bpm)")
                        .font(GitaFont.timer(.semibold))
                        .foregroundStyle(GitaTheme.brand500)
                    Text(MetronomeTempoName.name(for: metronome.bpm))
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                stepButton("＋", accent: true, enabled: metronome.bpm < 200) {
                    metronome.bump(1)
                }
            }
        }
        .padding(.top, GitaTheme.s8)
    }

    private var meterSection: some View {
        VStack(alignment: .leading, spacing: GitaTheme.s8) {
            sectionHeader(String(localized: "拍号"), comingSoon: true)
            HStack(spacing: GitaTheme.s12) {
                disabledStepperPlaceholder
                VStack(spacing: 4) {
                    Text(String(localized: "拍号"))
                        .font(GitaFont.micro())
                        .foregroundStyle(GitaTheme.textSecondary)
                    Text(meterText)
                        .font(GitaFont.title(.semibold))
                        .foregroundStyle(GitaTheme.brand500)
                }
                .frame(maxWidth: .infinity)
                disabledStepperPlaceholder
            }
            Text(String(localized: "重音"))
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
            HStack(spacing: GitaTheme.s12) {
                ForEach(0..<4, id: \.self) { index in
                    Image(systemName: "music.note")
                        .font(.system(size: 22))
                        .foregroundStyle(index == 0 ? GitaTheme.brand500 : GitaTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, GitaTheme.s8)
        }
        .opacity(0.45)
        .allowsHitTesting(false)
    }

    private var subdivisionSection: some View {
        VStack(alignment: .leading, spacing: GitaTheme.s8) {
            sectionHeader(String(localized: "切分"), comingSoon: true)
            LazyVGrid(columns: gridColumns, spacing: 0) {
                ForEach(0..<subdivisionCellCount, id: \.self) { index in
                    ZStack {
                        RoundedRectangle(cornerRadius: GitaTheme.radius8)
                            .stroke(
                                index == 0 ? GitaTheme.brand500 : Color.clear,
                                lineWidth: 2
                            )
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                            .foregroundStyle(index == 0 ? GitaTheme.brand500 : GitaTheme.textSecondary)
                    }
                    .frame(height: 52)
                }
            }
        }
        .opacity(0.45)
        .allowsHitTesting(false)
    }

    private func sectionHeader(_ title: String, comingSoon: Bool) -> some View {
        HStack(spacing: GitaTheme.s8) {
            Text(title)
                .font(GitaFont.headline())
            if comingSoon {
                Text(String(localized: "即将支持"))
                    .font(GitaFont.micro())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
        }
    }

    private var disabledStepperPlaceholder: some View {
        HStack(spacing: GitaTheme.s8) {
            circlePlaceholder
            circlePlaceholder
        }
    }

    private var circlePlaceholder: some View {
        Circle()
            .fill(GitaTheme.bgSubtle)
            .frame(width: 36, height: 36)
            .overlay {
                Text("±")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.textTertiary)
            }
    }

    private func stepButton(
        _ title: String,
        accent: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(accent ? GitaTheme.brand500 : GitaTheme.textSecondary)
                .frame(width: 44, height: 44)
                .background(accent ? GitaTheme.brand50 : GitaTheme.bgSubtle)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(Text(accent ? String(localized: "提高 1 BPM") : String(localized: "降低 1 BPM")))
    }

    private func scrollToAnchor(_ proxy: ScrollViewProxy) {
        let target = anchor.scrollSectionID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }
}
