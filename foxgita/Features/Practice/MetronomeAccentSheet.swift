//
//  MetronomeAccentSheet.swift
//  foxgita
//

import SwiftUI

struct MetronomeAccentSheet: View {
    let metronome: MetronomeEngine
    var onDone: () -> Void

    private let cardWidth: CGFloat = 76
    private let cardHeight: CGFloat = 132
    private let cardSpacing: CGFloat = 16

    private var showsScrollHint: Bool {
        metronome.beatsPerBar > 4
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GitaTheme.s16) {
                header
                meterText
                ruleHint
                accentCardsRow
                accessibilityHint
                if showsScrollHint {
                    scrollHintBanner
                }
                doneButton
            }
            .padding(.horizontal, GitaTheme.s20)
            .padding(.top, GitaTheme.s16)
            .padding(.bottom, GitaTheme.s24)
        }
        .background(GitaTheme.bgSurface)
        .presentationDetents([.fraction(0.6)])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            Text(String(localized: "每拍重音"))
                .font(GitaFont.title(.bold))
                .foregroundStyle(GitaTheme.textPrimary)
            Spacer()
            Button(String(localized: "完成"), action: onDone)
                .font(GitaFont.callout(.medium))
                .foregroundStyle(GitaTheme.brand500)
        }
    }

    private var meterText: some View {
        Text(metronome.timeSignatureText)
            .font(GitaFont.largeTitle(.bold))
            .foregroundStyle(GitaTheme.textPrimary)
            .monospacedDigit()
    }

    private var ruleHint: some View {
        Text(String(localized: "点击每拍循环：强 → 次强 → 普通 → 静音"))
            .font(GitaFont.footnote())
            .foregroundStyle(GitaTheme.textSecondary)
    }

    @ViewBuilder
    private var accentCardsRow: some View {
        if metronome.beatsPerBar <= 4 {
            HStack(spacing: cardSpacing) {
                ForEach(0..<metronome.beatsPerBar, id: \.self) { index in
                    accentCard(index: index)
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: cardSpacing) {
                    ForEach(0..<metronome.beatsPerBar, id: \.self) { index in
                        accentCard(index: index)
                    }
                }
            }
        }
    }

    private func accentCard(index: Int) -> some View {
        let kind = metronome.accentPattern.indices.contains(index)
            ? metronome.accentPattern[index]
            : MetronomeBeatKind.weak
        return Button {
            metronome.cycleAccent(at: index)
            Haptics.selection()
        } label: {
            VStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(cardForegroundColor(for: kind))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(cardSymbol(for: kind))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(cardForegroundColor(for: kind))
                Text(kind.displayName)
                    .font(GitaFont.footnote(.medium))
                    .foregroundStyle(cardForegroundColor(for: kind))
            }
            .padding(10)
            .frame(width: cardWidth, height: cardHeight)
            .background(cardBackgroundColor(for: kind))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accentAccessibilityLabel(beat: index + 1, kind: kind))
    }

    private func cardSymbol(for kind: MetronomeBeatKind) -> String {
        switch kind {
        case .strong: return "●"
        case .medium: return "◉"
        case .weak: return "○"
        case .mute: return "×"
        }
    }

    private func cardBackgroundColor(for kind: MetronomeBeatKind) -> Color {
        switch kind {
        case .strong: return GitaTheme.accentCardStrongBg
        case .medium: return GitaTheme.accentCardMediumBg
        case .weak: return GitaTheme.accentCardWeakBg
        case .mute: return GitaTheme.accentCardMuteBg
        }
    }

    private func cardForegroundColor(for kind: MetronomeBeatKind) -> Color {
        switch kind {
        case .strong: return .white
        case .medium: return GitaTheme.accentCardMediumText
        case .weak: return GitaTheme.textPrimary
        case .mute: return .white
        }
    }

    private func accentAccessibilityLabel(beat: Int, kind: MetronomeBeatKind) -> Text {
        Text("第 \(beat) 拍，\(kind.displayName)，可调节")
    }

    private var accessibilityHint: some View {
        Text(String(localized: "状态同时使用文字、符号与颜色；VoiceOver 示例：“第 2 拍，次强，可调节”"))
            .font(.system(size: 11))
            .foregroundStyle(GitaTheme.textSecondary)
    }

    private var scrollHintBanner: some View {
        Text("\(metronome.beatsPerBar) 拍时横向滚动 · 每格 ≥ 44 pt")
            .font(GitaFont.footnote(.medium))
            .foregroundStyle(GitaTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(GitaTheme.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Text(String(localized: "完成"))
                .font(GitaFont.headline())
                .foregroundStyle(GitaTheme.brandOn)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(GitaTheme.brand500)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview("4 beats") {
    MetronomeAccentSheet(metronome: MetronomeEngine(), onDone: {})
}

#Preview("12 beats, scroll hint") {
    let engine = MetronomeEngine()
    engine.configureMeter(timeSignature: "12/8", accentRaw: nil)
    return MetronomeAccentSheet(metronome: engine, onDone: {})
}
