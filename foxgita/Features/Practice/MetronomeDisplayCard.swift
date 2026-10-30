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
        static let cardHeight: CGFloat = 243
        static let horizontalPadding: CGFloat = 12
        static let topPadding: CGFloat = 10
        static let bottomPadding: CGFloat = 13
        static let controlHeight: CGFloat = 60
        static let controlToBarsSpacing: CGFloat = 3
        static let barsHeight: CGFloat = 95
        static let barsToTrackSpacing: CGFloat = 5
        static let trackHeight: CGFloat = 56
        static let fourBeatSpacing: CGFloat = 23.5
        static let fourBeatSideInset: CGFloat = 11.75
        static let barCornerRadius: CGFloat = 0
    }

    let metronome: MetronomeEngine
    var onEntryTap: (MetronomeSheetAnchor) -> Void = { _ in }
    var onSoundTap: () -> Void = {}
    var onAccentTap: (Int) -> Void = { _ in }
    var isAccentEditingLocked = false
    var onLockedAccentTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    private var valueHeight: CGFloat { typeSize.isAccessibilitySize ? 76 : 40 }
    @State private var trackPulseShape = BeatTrackPulseShape.none
    @State private var trackPulseKind = MetronomeBeatKind.weak
    @State private var pendulumAtTrailing = false
    @State private var visibleModeName: String?
    @State private var pulseResetTask: Task<Void, Never>?
    @State private var beatBarResetTask: Task<Void, Never>?
    @State private var modeNameTask: Task<Void, Never>?
    @State private var activeBeat: Int?

    private var meterText: String { metronome.timeSignatureText }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                entryColumn(anchor: .meter, label: String(localized: "拍号")) {
                    Text(meterText)
                        .font(GitaFont.largeTitle(.bold))
                        .foregroundStyle(GitaTheme.brand500)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(height: valueHeight)
                }

                VStack(spacing: 0) {
                    metricLabel(String(localized: "速度 (BPM)"))
                    HStack(spacing: 0) {
                        Button { metronome.bump(-1) } label: {
                            Image(systemName: "minus.circle").frame(width: 44, height: 44)
                        }.accessibilityLabel("降低速度")
                            .disabled(isAccentEditingLocked || metronome.bpm <= 40)
                        Button { onEntryTap(.speed) } label: { speedValue }
                            .accessibilityLabel("速度，打开调整速度")
                            .accessibilityIdentifier("metronome.open-speed")
                        Button { metronome.bump(1) } label: {
                            Image(systemName: "plus.circle").frame(width: 44, height: 44)
                        }.accessibilityLabel("提高速度")
                            .disabled(isAccentEditingLocked || metronome.bpm >= 200)
                    }
                    .foregroundStyle(GitaTheme.brand500)
                }.frame(width: 132)

                entryColumn(anchor: .subdivision, label: String(localized: "细分")) {
                    Image(metronome.subdivision.assetName)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(GitaTheme.brand500)
                        .frame(width: 32, height: 32)
                        .frame(height: 40)
                }

            }
            .frame(height: Layout.controlHeight + (typeSize.isAccessibilitySize ? 60 : 0))

            Color.clear.frame(height: Layout.controlToBarsSpacing)
            beatBars
            Color.clear.frame(height: Layout.barsToTrackSpacing)
            beatTrack
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.top, Layout.topPadding)
        .padding(.bottom, Layout.bottomPadding)
        .frame(height: Layout.cardHeight + (typeSize.isAccessibilitySize ? 60 : 0))
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius8))
        .overlay {
            RoundedRectangle(cornerRadius: GitaTheme.radius8)
                .stroke(GitaTheme.borderSubtle, lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onSoundTap) {
                Image(systemName: "gearshape").font(.system(size: 15))
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("音效与视觉设置")
            .accessibilityIdentifier("metronome.open-sound-settings")
        }
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

    private var speedValue: some View {
        Text("\(metronome.bpm)")
            .font(GitaFont.largeTitle(.bold))
            .foregroundStyle(GitaTheme.brand500)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        .frame(height: valueHeight)
    }

    private var soundColumn: some View {
        Button(action: onSoundTap) {
            VStack(spacing: 6) {
                metricLabel(String(localized: "声音"))
                Image("MetronomeSoundIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .frame(height: 40)
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
