//
//  MetronomeSettingsSheet.swift
//  foxgita
//

import SwiftUI

struct MetronomeSettingsSheet: View {
    let metronome: MetronomeEngine
    let anchor: MetronomeSheetAnchor
    var isLocked = false
    var onDone: () -> Void

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)
    private let stepButtonSize: CGFloat = 36

    private var subdivisionCases: [MetronomeSubdivision] {
        Array(MetronomeSubdivision.allCases)
    }

    private var canDecreaseSubdivision: Bool {
        subdivisionCases.first != metronome.configuredSubdivision
    }

    private var canIncreaseSubdivision: Bool {
        subdivisionCases.last != metronome.configuredSubdivision
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: GitaTheme.s12) {
                        if isLocked {
                            Label("变速训练中，可查看但暂不能修改", systemImage: "lock.fill")
                                .font(GitaFont.caption())
                                .foregroundStyle(GitaTheme.textSecondary)
                        }
                        if metronome.hasPendingRhythmChange {
                            Label("下一小节生效", systemImage: "clock.arrow.circlepath")
                                .font(GitaFont.caption())
                                .foregroundStyle(GitaTheme.brand500)
                        }
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
                        .accessibilityIdentifier("metronome.settings.done")
                }
            }
        }
        .presentationDetents([.fraction(0.6)])
        .presentationDragIndicator(.visible)
    }

    private var meterControls: some View {
        HStack(spacing: 10) {
            controlColumn(title: String(localized: "节拍")) {
                HStack(spacing: 8) {
                    MetronomeStepButton(
                        kind: .decrease,
                        diameter: stepButtonSize,
                        enabled: !isLocked
                            && metronome.configuredBeatsPerBar > MetronomeMeter.minBeats
                    ) {
                        metronome.bumpBeatsPerBar(-1)
                    }
                    MetronomeStepButton(
                        kind: .increase,
                        diameter: stepButtonSize,
                        enabled: !isLocked
                            && metronome.configuredBeatsPerBar < MetronomeMeter.maxBeats
                    ) {
                        metronome.bumpBeatsPerBar(1)
                    }
                }
            }

            VStack(spacing: 6) {
                Text(String(localized: "拍号"))
                    .font(GitaFont.micro())
                    .foregroundStyle(GitaTheme.textSecondary)
                Text(
                    "\(metronome.configuredBeatsPerBar) / \(metronome.configuredDenominator)"
                )
                    .font(GitaFont.title(.bold))
                    .foregroundStyle(GitaTheme.brand500)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(GitaTheme.brand50)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))

            controlColumn(title: String(localized: "音符")) {
                HStack(spacing: 8) {
                    MetronomeStepButton(
                        kind: .decrease,
                        diameter: stepButtonSize,
                        enabled: !isLocked && canDecreaseSubdivision
                    ) {
                        metronome.bumpSubdivision(-1)
                    }
                    MetronomeStepButton(
                        kind: .increase,
                        diameter: stepButtonSize,
                        enabled: !isLocked && canIncreaseSubdivision
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
        VStack(alignment: .center, spacing: GitaTheme.s8) {
            Text(String(localized: "重音"))
                .font(GitaFont.footnote(.medium))
                .foregroundStyle(GitaTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            accentSequenceView
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var accentSequenceView: some View {
        if metronome.configuredBeatsPerBar <= 4 {
            HStack(spacing: 8) {
                ForEach(0..<metronome.configuredBeatsPerBar, id: \.self) { index in
                    accentBeatButton(for: index)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(GitaTheme.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<metronome.configuredBeatsPerBar, id: \.self) { index in
                        accentBeatButton(for: index)
                            .frame(width: 80)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(GitaTheme.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))
        }
    }

    private func accentBeatButton(for index: Int) -> some View {
        let kind = metronome.configuredAccentPattern.indices.contains(index)
            ? metronome.configuredAccentPattern[index]
            : MetronomeBeatKind.weak

        return Button {
            metronome.cycleAccent(at: index)
            Haptics.selection()
        } label: {
            Image(kind.assetName)
                .resizable()
                .scaledToFit()
                .frame(height: 42)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityLabel(accentAccessibilityLabel(for: index, kind: kind))
    }

    private func accentAccessibilityLabel(for index: Int, kind: MetronomeBeatKind) -> Text {
        let beat = index + 1
        return Text("第 \(beat) 拍，\(kind.displayName)拍。轻点切换为\(kind.next.displayName)拍")
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
        let selected = metronome.configuredSubdivision == value
        return Button {
            metronome.setSubdivision(value)
            Haptics.selection()
        } label: {
            ZStack {
                Rectangle()
                    .fill(selected ? GitaTheme.brand50 : GitaTheme.bgSurface)
                Image(value.assetName)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(GitaTheme.textPrimary)
                    .scaledToFit()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
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
        .disabled(isLocked)
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
