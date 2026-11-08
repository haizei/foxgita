//
//  MetronomeDisplayCard.swift
//  foxgita
//

import SwiftUI

struct MetronomeDisplayCard: View {
    enum BeatTrackPulseShape: Equatable {
        case none
        case full
        case secondarySubdivision
        case weakSubdivision
        case pendulum

        var opacity: Double {
            switch self {
            case .full: 1
            case .secondarySubdivision: 0.72
            case .weakSubdivision: 0.46
            case .none, .pendulum: 0
            }
        }
    }

    enum Layout {
        static let cardHeight: CGFloat = 304
        static let horizontalPadding: CGFloat = 14
        static let topPadding: CGFloat = 12
        static let bottomPadding: CGFloat = 12
        static let controlHeight: CGFloat = 52
        static let controlToBarsSpacing: CGFloat = 8
        static let barsHeight: CGFloat = 130
        static let barsToTrackSpacing: CGFloat = 8
        static let trackHeight: CGFloat = 48
        static let fourBeatSpacing: CGFloat = 20
        static let fourBeatSideInset: CGFloat = 0
        static let barCornerRadius: CGFloat = 0
    }

    let metronome: MetronomeEngine
    var onEntryTap: (MetronomeSheetAnchor) -> Void = { _ in }
    var onSoundTap: () -> Void = {}
    var onTapTempo: (() -> Void)?
    var onAccentTap: (Int) -> Void = { _ in }
    var isAccentEditingLocked = false
    var onLockedAccentTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var trackPulseShape = BeatTrackPulseShape.none
    @State private var trackPulseKind = MetronomeBeatKind.weak
    @State private var pendulumAtTrailing = false
    @State private var visibleModeName: String?
    @State private var pulseResetTask: Task<Void, Never>?
    @State private var beatBarResetTask: Task<Void, Never>?
    @State private var modeNameTask: Task<Void, Never>?
    @State private var activeBeat: Int?

    private var meterText: String { metronome.configuredTimeSignatureText }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("节拍器").font(GitaFont.headline(.semibold))
                Spacer()
                Button(action: onSoundTap) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .foregroundStyle(GitaTheme.textSecondary)
                        .frame(width: 44, height: 26)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("音效与视觉设置")
                .accessibilityIdentifier("metronome.open-sound-settings")
            }
            .frame(height: typeSize.isAccessibilitySize ? nil : 26)
            .padding(.bottom, 8)

            controls

            Color.clear.frame(height: Layout.controlToBarsSpacing)
            beatBars
            Color.clear.frame(height: Layout.barsToTrackSpacing)
            beatTrack
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.top, Layout.topPadding)
        .padding(.bottom, Layout.bottomPadding)
        .frame(height: typeSize.isAccessibilitySize ? nil : Layout.cardHeight)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onChange(of: metronome.visualEvent) { _, event in
            guard let event else {
                resetPlaybackFeedback()
                return
            }
            handleVisualEvent(event)
        }
        .onChange(of: metronome.isPlaying) { _, isPlaying in
            if !isPlaying { resetPlaybackFeedback() }
        }
        .onDisappear {
            pulseResetTask?.cancel()
            beatBarResetTask?.cancel()
            modeNameTask?.cancel()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("metronome.display-card")
    }

    private var controls: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            HStack(spacing: 4) {
                Button { onEntryTap(.meter) } label: {
                    Text(meterText)
                        .font(GitaFont.metric())
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("拍号，打开节拍器设置")
                .accessibilityValue(meterText)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            HStack(spacing: 0) {
                Button { metronome.bump(-1) } label: {
                    Image(systemName: "minus").font(GitaFont.callout(.semibold))
                        .frame(width: 36, height: 36)
                        .background(GitaTheme.brand50, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("降低速度")
                .disabled(isAccentEditingLocked || metronome.bpm <= 40)
                Button { onEntryTap(.speed) } label: {
                    VStack(spacing: 0) {
                        Text("\(metronome.bpm)")
                            .font(GitaFont.largeTitle())
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        Text("BPM").font(GitaFont.micro())
                    }.frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("速度，打开调整速度")
                .accessibilityValue("\(metronome.bpm) BPM")
                .accessibilityIdentifier("metronome.open-speed")
                Button { metronome.bump(1) } label: {
                    Image(systemName: "plus").font(GitaFont.callout(.semibold))
                        .frame(width: 36, height: 36)
                        .background(GitaTheme.brand50, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("提高速度")
                .disabled(isAccentEditingLocked || metronome.bpm >= 200)
            }
            if let onTapTempo {
                Button("TAP", action: onTapTempo)
                    .font(GitaFont.caption(.semibold))
                    .frame(minWidth: 64, minHeight: 44)
                    .background(GitaTheme.brand50, in: Capsule())
                    .disabled(isAccentEditingLocked)
                    .accessibilityLabel("TAP 测速")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(GitaTheme.brand500)
        .frame(minHeight: Layout.controlHeight)
    }

    private var beatBars: some View {
        Group {
            if metronome.beatsPerBar == 4 {
                HStack(spacing: Layout.fourBeatSpacing) {
                    ForEach(0..<metronome.beatsPerBar, id: \.self) { index in
                        beatBar(index: index)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, Layout.fourBeatSideInset)
            } else if metronome.beatsPerBar > 6 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(0..<metronome.beatsPerBar, id: \.self) { index in
                            beatBar(index: index)
                                .frame(width: 44)
                        }
                    }
                }
            } else {
                HStack(spacing: GitaTheme.s8) {
                    ForEach(0..<metronome.beatsPerBar, id: \.self) { index in
                        beatBar(index: index)
                            .frame(maxWidth: metronome.beatsPerBar <= 4 ? 80 : .infinity)
                    }
                }
            }
        }
        .frame(height: Layout.barsHeight)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.12), value: activeBeat)
        .animation(.easeInOut(duration: 0.12), value: metronome.beatsPerBar)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: metronome.configuredAccentPattern)
    }

    private func beatBar(index: Int) -> some View {
        let isActive = activeBeat == index
        let kind = metronome.configuredAccentPattern.indices.contains(index)
            ? metronome.configuredAccentPattern[index]
            : MetronomeBeatKind.weak
        let displayedCount = Self.displayedSegmentCount(for: kind)
        let segmentColor = Self.fillColor(for: kind, isActive: isActive)

        return Button {
            if isAccentEditingLocked {
                onLockedAccentTap()
            } else {
                onAccentTap(index)
            }
        } label: {
            GeometryReader { proxy in
                let segmentHeight = proxy.size.height / 3
                let fillHeight = segmentHeight * CGFloat(displayedCount)

                ZStack(alignment: .top) {
                    GitaTheme.accentSlotEmpty

                    Rectangle()
                        .fill(segmentColor)
                        .frame(height: fillHeight)
                        .frame(maxHeight: .infinity, alignment: .bottom)

                    if Self.showsDivider(at: 1, displayedSegmentCount: displayedCount) {
                        Rectangle()
                            .fill(GitaTheme.accentTrackDivider)
                            .frame(height: 1)
                            .offset(y: segmentHeight)
                    }

                    if Self.showsDivider(at: 2, displayedSegmentCount: displayedCount) {
                        Rectangle()
                            .fill(GitaTheme.accentTrackDivider)
                            .frame(height: 1)
                            .offset(y: segmentHeight * 2)
                    }

                    if metronome.flashOnAccent, isActive, kind == .strong {
                        RoundedRectangle(cornerRadius: Layout.barCornerRadius)
                            .fill(Color.white.opacity(0.35))
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Layout.barCornerRadius)
                    .stroke(Self.borderColor(isActive: isActive), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Layout.barCornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .animation(.easeOut(duration: 0.08), value: activeBeat)
        .accessibilityIdentifier("metronome.accent-beat.\(index + 1)")
        .accessibilityLabel(
            Text(Self.accentAccessibilityLabel(index: index, kind: kind, isLocked: isAccentEditingLocked))
        )
        .accessibilityHint(
            Text(isAccentEditingLocked ? "变速训练中暂不可调整重音" : "轻点切换为\(kind.next.displayName)拍")
        )
    }

    static func accentAccessibilityLabel(
        index: Int,
        kind: MetronomeBeatKind,
        isLocked: Bool
    ) -> String {
        let status = isLocked ? "，已锁定" : ""
        return "第 \(index + 1) 拍，\(kind.displayName)拍\(status)"
    }

    static func fillColor(for kind: MetronomeBeatKind?, isActive: Bool) -> Color {
        if isActive {
            return GitaTheme.accentActive
        }
        switch kind {
        case nil, .weak:
            return GitaTheme.accentWeak
        case .medium:
            return GitaTheme.accentMedium
        case .strong:
            return GitaTheme.accentStrong
        case .mute:
            return GitaTheme.accentMute
        }
    }

    static func borderColor(isActive _: Bool) -> Color {
        GitaTheme.borderSubtle
    }

    static func displayedSegmentCount(for kind: MetronomeBeatKind?) -> Int {
        guard let kind else { return MetronomeBeatKind.weak.filledBarsCount }
        return kind == .mute ? 1 : kind.filledBarsCount
    }

    static func showsDivider(at boundary: Int, displayedSegmentCount: Int) -> Bool {
        switch boundary {
        case 1:
            return displayedSegmentCount < 3
        case 2:
            return displayedSegmentCount < 2
        default:
            return false
        }
    }

    static func pulseShape(
        for mode: BeatTrackMode,
        event: MetronomeVisualEvent
    ) -> BeatTrackPulseShape {
        switch mode {
        case .allBeats:
            return event.role == .main ? .full : .none
        case .accents:
            guard event.role == .main,
                  event.kind == .medium || event.kind == .strong else {
                return .none
            }
            return .full
        case .pendulum:
            return event.role == .main ? .pendulum : .none
        case .accentsAndSubdivisions:
            guard event.kind != .mute else { return .none }
            switch event.role {
            case .main: return .full
            case .secondary: return .secondarySubdivision
            case .weak: return .weakSubdivision
            case .rest: return .none
            }
        }
    }

    private var beatTrack: some View {
        Group {
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: GitaTheme.radius8)
                        .fill(GitaTheme.bgSubtle)

                    RoundedRectangle(cornerRadius: GitaTheme.radius8)
                        .fill(Self.fillColor(for: trackPulseKind, isActive: false))
                        .opacity(trackPulseShape.opacity)

                    if metronome.isPlaying, metronome.visualPreferences.pendulumEnabled {
                        RoundedRectangle(cornerRadius: GitaTheme.radius8)
                            .fill(Self.fillColor(for: trackPulseKind, isActive: false))
                            .frame(width: Layout.trackHeight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offset(x: pendulumAtTrailing ? proxy.size.width - Layout.trackHeight : 0)
                    }

                    if let visibleModeName {
                        Text(visibleModeName)
                            .font(GitaFont.micro(.medium))
                            .foregroundStyle(
                                trackPulseShape == .full
                                    ? Color.white
                                    : GitaTheme.textSecondary
                            )
                            .transition(.opacity)
                            .accessibilityHidden(true)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius8))
            }
            .frame(height: Layout.trackHeight)
        }
        .padding(.horizontal, Layout.fourBeatSideInset)
        .accessibilityIdentifier("metronome.beat-track")
        .accessibilityLabel("节拍视觉反馈")
        .overlay(alignment: .trailing) {
            if metronome.visualPreferences.barCounterVisible, let bar = metronome.displayedBar {
                Text("第 \(bar) 小节").font(GitaFont.caption(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(GitaTheme.bgSurface.opacity(0.9), in: Capsule())
                    .padding(.trailing, 8)
                    .accessibilityIdentifier("metronome.bar-counter")
            }
        }
    }

    private func handleVisualEvent(_ event: MetronomeVisualEvent) {
        let preference = metronome.visualPreferences
        if event.role == .main, preference.pendulumEnabled {
            withAnimation(reduceMotion ? nil : .linear(duration: 60.0 / Double(metronome.bpm))) {
                pendulumAtTrailing.toggle()
            }
        }
        guard preference.beatModuleEnabled, preference.highlights(event.kind) else { return }
        if event.role == .main {
            showBeatBarPulse(for: event.beat)
        }

        let shape: BeatTrackPulseShape = switch event.role {
        case .main: .full
        case .secondary: .secondarySubdivision
        case .weak: .weakSubdivision
        case .rest: .none
        }
        guard shape != .none else { return }
        trackPulseKind = event.kind

        if shape == .pendulum {
            let animation: Animation? = reduceMotion
                ? nil
                : .linear(duration: 60.0 / Double(metronome.bpm))
            withAnimation(animation) {
                pendulumAtTrailing.toggle()
            }
            return
        }

        pulseResetTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.06)) {
            trackPulseShape = shape
        }
        pulseResetTask = Task { @MainActor in
            try? await Task.sleep(for: pulseDuration(for: shape))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.1)) {
                trackPulseShape = .none
            }
        }
    }

    private func showBeatBarPulse(for beat: Int) {
        beatBarResetTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.06)) {
            activeBeat = beat
        }
        beatBarResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.08)) {
                activeBeat = nil
            }
        }
    }

    private func pulseDuration(for shape: BeatTrackPulseShape) -> Duration {
        switch shape {
        case .full: .milliseconds(180)
        case .secondarySubdivision: .milliseconds(120)
        case .weakSubdivision: .milliseconds(90)
        case .none, .pendulum: .zero
        }
    }

    private func showModeName() {
        modeNameTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
            visibleModeName = metronome.beatTrackMode.displayName
        }
        modeNameTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                visibleModeName = nil
            }
        }
    }

    private func resetPlaybackFeedback() {
        pulseResetTask?.cancel()
        beatBarResetTask?.cancel()
        trackPulseShape = .none
        pendulumAtTrailing = false
        activeBeat = nil
    }


}

#Preview("Default") {
    MetronomeDisplayCard(metronome: MetronomeEngine())
        .padding()
        .background(GitaTheme.bgDefault)
}
