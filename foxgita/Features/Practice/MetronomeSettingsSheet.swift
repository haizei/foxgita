//
//  MetronomeSettingsSheet.swift
//  foxgita
//

import SwiftUI

struct MetronomeSettingsSheet: View {
    let metronome: MetronomeEngine
    let anchor: MetronomeSheetAnchor
    var onDone: () -> Void

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)
    private let stepButtonSize: CGFloat = 36

    private var subdivisionCases: [MetronomeSubdivision] {
        Array(MetronomeSubdivision.allCases)
    }

    private var canDecreaseSubdivision: Bool {
        subdivisionCases.first != metronome.subdivision
    }

    private var canIncreaseSubdivision: Bool {
        subdivisionCases.last != metronome.subdivision
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: GitaTheme.s12) {
                        meterControls
                            .id(MetronomeSheetAnchor.meter.scrollSectionID)
                        accentSection
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

    private var meterControls: some View {
        HStack(spacing: 10) {
            controlColumn(title: String(localized: "节拍")) {
                HStack {
                    MetronomeStepButton(
                        kind: .decrease,
                        diameter: stepButtonSize,
                        enabled: metronome.beatsPerBar > MetronomeMeter.minBeats
                    ) {
                        metronome.bumpBeatsPerBar(-1)
                    }
                    MetronomeStepButton(
                        kind: .increase,
                        diameter: stepButtonSize,
                        enabled: metronome.beatsPerBar < MetronomeMeter.maxBeats
                    ) {
                        metronome.bumpBeatsPerBar(1)
                    }
                }
            }

            VStack(spacing: 4) {
                Text(String(localized: "拍号"))
                    .font(GitaFont.micro())
                    .foregroundStyle(GitaTheme.textSecondary)
                Text("\(metronome.beatsPerBar) / \(metronome.denominator)")
                    .font(GitaFont.metric(.bold))
                    .foregroundStyle(GitaTheme.brand500)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(GitaTheme.brand50)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))

            controlColumn(title: String(localized: "音符")) {
                HStack {
                    MetronomeStepButton(
                        kind: .decrease,
                        diameter: stepButtonSize,
                        enabled: canDecreaseSubdivision
                    ) {
                        metronome.bumpSubdivision(-1)
                    }
                    MetronomeStepButton(
                        kind: .increase,
                        diameter: stepButtonSize,
                        enabled: canIncreaseSubdivision
                    ) {
                        metronome.bumpSubdivision(1)
                    }
                }
            }
        }
    }

    private func controlColumn<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(GitaFont.micro())
                .foregroundStyle(GitaTheme.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .padding(GitaTheme.s8)
        .background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))
    }

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: GitaTheme.s8) {
            Text(String(localized: "重音"))
                .font(GitaFont.footnote(.medium))
                .foregroundStyle(GitaTheme.textPrimary)

            HStack(spacing: 0) {
                ForEach(0..<metronome.beatsPerBar, id: \.self) { index in
                    Button {
                        metronome.cycleAccent(at: index)
                    } label: {
                        accentBeatIcon(for: index)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accentAccessibilityLabel(for: index))
                }
            }
            .padding(.horizontal, GitaTheme.s16)
            .frame(height: 48)
            .background(GitaTheme.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))
        }
    }

    @ViewBuilder
    private func accentBeatIcon(for index: Int) -> some View {
        let kind = metronome.accentPattern.indices.contains(index)
            ? metronome.accentPattern[index]
            : MetronomeBeatKind.normal

        VStack(spacing: 2) {
            Group {
                switch kind {
                case .accent, .normal:
                    Image(systemName: "music.note")
                        .font(.system(size: 22))
                        .foregroundStyle(GitaTheme.brand500)
                case .mute:
                    Image(systemName: "music.note")
                        .font(.system(size: 22))
                        .foregroundStyle(GitaTheme.textTertiary.opacity(0.45))
                        .overlay {
                            Image(systemName: "slash.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(GitaTheme.textTertiary)
                        }
                }
            }

            if kind == .accent {
                Text("›")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GitaTheme.brand500)
                    .offset(y: -2)
            } else {
                Color.clear.frame(height: 12)
            }
        }
        .frame(height: 42)
    }

    private func accentAccessibilityLabel(for index: Int) -> Text {
        let beat = index + 1
        guard metronome.accentPattern.indices.contains(index) else {
            return Text("第 \(beat) 拍")
        }
        switch metronome.accentPattern[index] {
        case .accent:
            return Text("第 \(beat) 拍，强拍")
        case .normal:
            return Text("第 \(beat) 拍，弱拍")
        case .mute:
            return Text("第 \(beat) 拍，静音")
        }
    }

    private var subdivisionSection: some View {
        LazyVGrid(columns: gridColumns, spacing: 0) {
            ForEach(MetronomeSubdivision.allCases) { value in
                subdivisionCell(value)
            }
        }
        .background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))
        .overlay {
            RoundedRectangle(cornerRadius: GitaTheme.radius12)
                .stroke(GitaTheme.borderSubtle, lineWidth: 0)
        }
    }

    private func subdivisionCell(_ value: MetronomeSubdivision) -> some View {
        let selected = metronome.subdivision == value
        return Button {
            metronome.setSubdivision(value)
        } label: {
            ZStack {
                Rectangle()
                    .fill(selected ? GitaTheme.brand50 : GitaTheme.bgSurface)
                Image(value.assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 103.5)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(GitaTheme.brand500, lineWidth: 2)
                } else {
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(GitaTheme.borderSubtle, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(value.accessibilityLabel))
        .accessibilityAddTraits(selected ? .isSelected : [])
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
