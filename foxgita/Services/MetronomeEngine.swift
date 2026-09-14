//
//  MetronomeEngine.swift
//  foxgita
//

import AVFoundation
import Foundation
import os

enum MetronomeError: Error, Equatable {
    case engineNotRunning
    case previewUnavailableWhilePlaying
}

private let metronomeLog = Logger(subsystem: "com.haizei.foxgita", category: "metronome")

private struct MetronomeRhythmConfiguration: Equatable {
    var beatsPerBar: Int
    var denominator: Int
    var accentPattern: [MetronomeBeatKind]
    var subdivision: MetronomeSubdivision
}

/// Sample-accurate metronome. Clicks are scheduled onto exact audio frames a
/// short distance ahead of the audio clock, so beat spacing comes from the
/// audio hardware rather than from when the scheduling timer happens to fire.
@Observable
final class MetronomeEngine {
    private(set) var isPlaying = false
    private(set) var bpm = 80
    private(set) var currentBeatInBar = 0
    private(set) var beatsPerBar = 4
    private(set) var denominator = MetronomeMeter.defaultDenominator
    private(set) var accentPattern: [MetronomeBeatKind] = MetronomeMeter.defaultAccentPattern(beats: 4)
    private(set) var subdivision: MetronomeSubdivision = .quarter
    private(set) var configuredBeatsPerBar = 4
    private(set) var configuredDenominator = MetronomeMeter.defaultDenominator
    private(set) var configuredAccentPattern: [MetronomeBeatKind] = MetronomeMeter.defaultAccentPattern(beats: 4)
    private(set) var configuredSubdivision: MetronomeSubdivision = .quarter
    private(set) var hasPendingRhythmChange = false
    private(set) var soundMode: MetronomeSoundMode = .standard
    private(set) var volume = 80
    private(set) var strongBeatBoost = true
    private(set) var beatTrackMode = BeatTrackMode.allBeats
    private(set) var visualEvent: MetronomeVisualEvent?
    var onTimelineEvent: ((MetronomeTimelineEvent) -> Void)?
    var onVisualEvent: ((MetronomeVisualEvent) -> Void)?

    var timeSignatureText: String {
        MetronomeMeter.format(beats: beatsPerBar, denominator: denominator)
    }

    var accentPatternRaw: String {
        MetronomeMeter.encodeAccent(accentPattern)
    }

    var configuredTimeSignatureText: String {
        MetronomeMeter.format(
            beats: configuredBeatsPerBar, denominator: configuredDenominator
        )
    }

    var configuredAccentPatternRaw: String {
        MetronomeMeter.encodeAccent(configuredAccentPattern)
    }

    var subdivisionRaw: Int { subdivision.rawValue }
    var configuredSubdivisionRaw: Int { configuredSubdivision.rawValue }
    var flashOnAccent: Bool { soundMode == .highNoise && isPlaying }

    private static let lead = 0.15
    private static let pumpInterval = 0.05

    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private var player = AVAudioPlayerNode()
    @ObservationIgnored private let format = AVAudioFormat(
        standardFormatWithSampleRate: 44_100, channels: 1
    )!
    @ObservationIgnored private let session: AudioSessionCoordinator
    @ObservationIgnored private var accentClick: AVAudioPCMBuffer?
    @ObservationIgnored private var strongAccentClick: AVAudioPCMBuffer?
    @ObservationIgnored private var mediumAccentClick: AVAudioPCMBuffer?
    @ObservationIgnored private var beatClick: AVAudioPCMBuffer?
    @ObservationIgnored private var secondarySubdivisionClick: AVAudioPCMBuffer?
    @ObservationIgnored private var weakSubdivisionClick: AVAudioPCMBuffer?
    @ObservationIgnored private var pump: Timer?
    @ObservationIgnored private var nextClickFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var beatIndex = 0
    @ObservationIgnored private var subClickIndex = 0
    @ObservationIgnored private var graphConfigured = false
    @ObservationIgnored private var runToken = 0
    @ObservationIgnored private var previewRemainingBeats: Int?
    @ObservationIgnored private var previewStopScheduled = false
    @ObservationIgnored private var scheduledBarIndex = 0
    @ObservationIgnored private var schedulerBPM = 80
    @ObservationIgnored private var pendingBoundaryBPM: Int?
    @ObservationIgnored private var pendingBoundarySubdivision: MetronomeSubdivision?
    @ObservationIgnored private var subdivisionBoundaryCountdown = 0
    @ObservationIgnored private var visualEventSequence = 0
    @ObservationIgnored private var pendingRhythmChange: MetronomeRhythmConfiguration?

    var hapticsEnabled = true
    var foregroundFeedbackEnabled = true

    var isEngineRunning: Bool { engine.isRunning }
    var hasPump: Bool { pump != nil }

    init(session: AudioSessionCoordinator) {
        self.session = session
    }

    convenience init() { self.init(session: .shared) }

    func setBpm(_ value: Int) {
        let clamped = min(200, max(40, value))
        guard clamped != bpm else { return }
        bpm = clamped
        schedulerBPM = clamped
        pendingBoundaryBPM = nil
    }

    /// Applies spacing before scheduling the next bar, while publishing the
    /// visible BPM only when that bar's downbeat becomes audible.
    func queueBpmAtNextBar(_ value: Int) {
        pendingBoundaryBPM = min(200, max(40, value))
    }

    func cancelQueuedTempo() { pendingBoundaryBPM = nil }

    func applyQueuedTempoForTesting() {
        guard let pendingBoundaryBPM else { return }
        schedulerBPM = pendingBoundaryBPM
        bpm = pendingBoundaryBPM
        self.pendingBoundaryBPM = nil
    }

    func bump(_ delta: Int) { setBpm(bpm + delta) }

    func configureMeter(timeSignature: String?, accentRaw: String?) {
        let parsed = MetronomeMeter.parseTimeSignature(timeSignature)
        let pattern = MetronomeMeter.decodeAccent(accentRaw, beats: parsed.beats)
        configuredBeatsPerBar = parsed.beats
        configuredDenominator = parsed.denominator
        configuredAccentPattern = pattern
        if isPlaying {
            queueConfiguredRhythmChange()
        } else {
            applyConfiguredRhythm()
        }
    }

    func setBeatsPerBar(_ value: Int) {
        let clamped = min(MetronomeMeter.maxBeats, max(MetronomeMeter.minBeats, value))
        guard clamped != configuredBeatsPerBar else { return }
        if clamped > configuredBeatsPerBar {
            configuredAccentPattern.append(
                contentsOf: Array(
                    repeating: MetronomeBeatKind.weak,
                    count: clamped - configuredBeatsPerBar
                )
            )
        } else {
            configuredAccentPattern = Array(configuredAccentPattern.prefix(clamped))
        }
        configuredBeatsPerBar = clamped
        if isPlaying {
            queueConfiguredRhythmChange()
        } else {
            applyConfiguredRhythm()
        }
    }

    func bumpBeatsPerBar(_ delta: Int) { setBeatsPerBar(configuredBeatsPerBar + delta) }

    func cycleAccent(at index: Int) {
        guard configuredAccentPattern.indices.contains(index) else { return }
        configuredAccentPattern[index].cycle()
        if isPlaying {
            queueConfiguredRhythmChange()
        } else {
            applyConfiguredRhythm()
        }
    }

    func cycleBeatTrackMode() {
        beatTrackMode.cycle()
    }

    func configureSubdivision(raw: Int?) {
        configuredSubdivision = MetronomeSubdivision.decode(raw)
        if isPlaying {
            queueConfiguredRhythmChange()
        } else {
            applyConfiguredRhythm()
        }
    }

    func setSubdivision(_ value: MetronomeSubdivision) {
        guard value != configuredSubdivision else { return }
        configuredSubdivision = value
        cancelQueuedSubdivision()
        if isPlaying {
            queueConfiguredRhythmChange()
        } else {
            applyConfiguredRhythm()
        }
    }

    /// Restores a subdivision before scheduling the downbeat that follows the
    /// requested number of complete bars. This keeps count-in quarter notes
    /// from dropping the first subdivision click in the first training bar.
    func queueSubdivision(_ value: MetronomeSubdivision, afterBars bars: Int) {
        configuredSubdivision = value
        pendingBoundarySubdivision = value
        subdivisionBoundaryCountdown = max(0, bars)
    }

    func cancelQueuedSubdivision() {
        pendingBoundarySubdivision = nil
        subdivisionBoundaryCountdown = 0
    }

    func advanceSubdivisionBoundaryForTesting() {
        applyPendingSubdivisionAtDownbeatIfNeeded()
    }

    func bumpSubdivision(_ delta: Int) {
        let all = Array(MetronomeSubdivision.allCases)
        guard let index = all.firstIndex(of: configuredSubdivision) else { return }
        let next = index + delta
        guard all.indices.contains(next) else { return }
        setSubdivision(all[next])
    }

    func configureSound(modeRaw: String?, volume: Int?, strongBeatBoost: Bool?) {
        setSoundMode(MetronomeSoundMode.decode(modeRaw))
        setVolume(volume ?? 80)
        setStrongBeatBoost(strongBeatBoost ?? true)
    }

    func setSoundMode(_ value: MetronomeSoundMode) {
        guard value != soundMode else { return }
        soundMode = value
        rebuildClickBuffers()
    }

    func setVolume(_ value: Int) {
        let clamped = min(100, max(0, value))
        guard clamped != volume else { return }
        volume = clamped
        rebuildClickBuffers()
    }

    func setStrongBeatBoost(_ value: Bool) {
        guard value != strongBeatBoost else { return }
        strongBeatBoost = value
        rebuildClickBuffers()
    }

    func preview(bars: Int = 2) throws {
        guard !isPlaying else { throw MetronomeError.previewUnavailableWhilePlaying }
        previewRemainingBeats = bars * beatsPerBar
        try start()
    }

    func start() throws {
        guard !isPlaying else { return }
        var acquired = false
        do {
            try session.acquire(.playback)
            acquired = true
            configureGraphIfNeeded()
            if !engine.isRunning {
                try engine.start()
            }
            guard engine.isRunning else { throw MetronomeError.engineNotRunning }
            player.stop()
            beatIndex = 0
            subClickIndex = 0
            scheduledBarIndex = 0
            currentBeatInBar = 0
            visualEvent = nil
            runToken += 1
            player.play()
            nextClickFrame = currentFrame() + frames(0.1)
            isPlaying = true
            fill()
            pump = Timer.scheduledTimer(withTimeInterval: Self.pumpInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.fill() }
            }
            if let pump { RunLoop.main.add(pump, forMode: .common) }
            metronomeLog.debug(
                "start bpm=\(self.bpm, privacy: .public) running=\(self.engine.isRunning, privacy: .public)"
            )
        } catch {
            isPlaying = false
            previewRemainingBeats = nil
            previewStopScheduled = false
            pump?.invalidate()
            pump = nil
            if acquired { session.release(.playback) }
            metronomeLog.error("start failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func stop() {
        guard isPlaying || pump != nil else { return }
        pump?.invalidate()
        pump = nil
        player.stop()
        isPlaying = false
        beatIndex = 0
        subClickIndex = 0
        scheduledBarIndex = 0
        currentBeatInBar = 0
        visualEvent = nil
        runToken += 1
        previewRemainingBeats = nil
        previewStopScheduled = false
        applyConfiguredRhythm()
        session.release(.playback)
        metronomeLog.debug(
            "stop running=\(self.engine.isRunning, privacy: .public) other=\(AVAudioSession.sharedInstance().isOtherAudioPlaying, privacy: .public)"
        )
    }

    func toggle() {
        if isPlaying { stop() } else { try? start() }
    }

    func prepareAfterAudioServicesReset() {
        stop()
        engine.stop()
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        graphConfigured = false
        metronomeLog.notice("audio graph reset after media-services reset")
    }

    private func configureGraphIfNeeded() {
        guard !graphConfigured else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        rebuildClickBuffers()
        graphConfigured = true
    }

    private func fill() {
        guard isPlaying, !previewStopScheduled,
              let accent = accentClick,
              let strongAccent = strongAccentClick,
              let mediumAccent = mediumAccentClick,
              let beat = beatClick,
              let secondarySubdivision = secondarySubdivisionClick,
              let weakSubdivision = weakSubdivisionClick else { return }
        let now = currentFrame()
        if nextClickFrame < now {
            nextClickFrame = now + frames(0.05)
            beatIndex = 0
            subClickIndex = 0
            currentBeatInBar = 0
        }
        let horizon = now + frames(Self.lead)
        while nextClickFrame <= horizon {
            let scheduledFrame = nextClickFrame
            var beatInBar = beatIndex % beatsPerBar
            var appliedBPM: Int?
            if subClickIndex == 0, beatInBar == 0 {
                applyPendingSubdivisionAtDownbeatIfNeeded()
                if applyPendingRhythmAtDownbeatIfNeeded() {
                    beatInBar = 0
                }
                if let pendingBoundaryBPM {
                    schedulerBPM = pendingBoundaryBPM
                    appliedBPM = pendingBoundaryBPM
                    self.pendingBoundaryBPM = nil
                }
            }
            let step = subdivision.steps[subClickIndex]
            if subClickIndex == 0 {
                scheduleTimelineEvent(
                    MetronomeTimelineEvent(
                        beat: beatInBar, bar: scheduledBarIndex, appliedBPM: appliedBPM
                    ),
                    at: scheduledFrame,
                    now: now
                )
            }
            let beatKind = accentPattern[beatInBar]
            if step.role != .rest, (beatKind != .mute || step.role == .main) {
                scheduleVisualEvent(
                    beat: beatInBar,
                    kind: beatKind,
                    role: step.role,
                    at: scheduledFrame,
                    now: now
                )
            }
            if beatKind != .mute,
               let buffer = clickBuffer(
                   for: step.role,
                   beatKind: beatKind,
                   accent: accent,
                   strongAccent: strongAccent,
                   mediumAccent: mediumAccent,
                   beat: beat,
                   secondarySubdivision: secondarySubdivision,
                   weakSubdivision: weakSubdivision
               ) {
                player.scheduleBuffer(
                    buffer,
                    at: AVAudioTime(sampleTime: nextClickFrame, atRate: format.sampleRate),
                    options: [],
                    completionHandler: nil
                )
                if beatKind == .strong && step.role == .main {
                    scheduleDownbeatHaptic(at: nextClickFrame, now: now)
                }
            }
            nextClickFrame += intervalToNextClick()
            advanceClickPosition()
            if subClickIndex == 0, beatInBar == beatsPerBar - 1 { scheduledBarIndex += 1 }
            if subClickIndex == 0, let remaining = previewRemainingBeats {
                previewRemainingBeats = remaining - 1
                if remaining <= 1 {
                    previewStopScheduled = true
                    schedulePreviewStop(at: scheduledFrame + frames(0.03), now: now)
                    return
                }
            }
        }
        if !player.isPlaying { player.play() }
    }

    private func scheduleTimelineEvent(
        _ event: MetronomeTimelineEvent,
        at frame: AVAudioFramePosition,
        now: AVAudioFramePosition
    ) {
        let token = runToken
        let delay = Double(frame - now) / format.sampleRate
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, self.runToken == token else { return }
                if let appliedBPM = event.appliedBPM { self.bpm = appliedBPM }
                self.currentBeatInBar = event.beat
                self.onTimelineEvent?(event)
            }
        }
    }

    private func scheduleVisualEvent(
        beat: Int,
        kind: MetronomeBeatKind,
        role: MetronomePulseRole,
        at frame: AVAudioFramePosition,
        now: AVAudioFramePosition
    ) {
        let token = runToken
        let delay = Double(frame - now) / format.sampleRate
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, self.runToken == token else { return }
                guard self.foregroundFeedbackEnabled else { return }
                self.visualEventSequence += 1
                let event = MetronomeVisualEvent(
                    sequence: self.visualEventSequence,
                    beat: beat,
                    kind: kind,
                    role: role
                )
                self.visualEvent = event
                self.onVisualEvent?(event)
            }
        }
    }

    private func schedulePreviewStop(
        at frame: AVAudioFramePosition, now: AVAudioFramePosition
    ) {
        let token = runToken
        let delay = Double(frame - now) / format.sampleRate
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, self.runToken == token else { return }
                self.stop()
            }
        }
    }

    private struct ClickRecipe {
        let accentFrequency: Double
        let accentAmplitude: Double
        let beatFrequency: Double
        let beatAmplitude: Double
        let decay: Double
    }

    private func recipe(for mode: MetronomeSoundMode) -> ClickRecipe {
        switch mode {
        case .standard:
            ClickRecipe(
                accentFrequency: 1_000, accentAmplitude: 0.9,
                beatFrequency: 800, beatAmplitude: 0.5, decay: 90
            )
        case .penetrating:
            ClickRecipe(
                accentFrequency: 1_400, accentAmplitude: 1.0,
                beatFrequency: 1_200, beatAmplitude: 0.6, decay: 120
            )
        case .highNoise:
            ClickRecipe(
                accentFrequency: 200, accentAmplitude: 1.0,
                beatFrequency: 180, beatAmplitude: 0.7, decay: 90
            )
        }
    }

    private var volumeScale: Double { Double(volume) / 100.0 }

    private func rebuildClickBuffers() {
        let recipe = recipe(for: soundMode)
        accentClick = Self.makeClick(
            format: format,
            frequency: recipe.accentFrequency,
            amplitude: recipe.accentAmplitude * volumeScale,
            decay: recipe.decay
        )
        strongAccentClick = Self.makeClick(
            format: format,
            frequency: recipe.accentFrequency,
            amplitude: min(1.0, recipe.accentAmplitude * volumeScale * 1.4),
            decay: recipe.decay
        )
        mediumAccentClick = Self.makeClick(
            format: format,
            frequency: (recipe.accentFrequency + recipe.beatFrequency) / 2.0,
            amplitude: recipe.accentAmplitude * volumeScale * 0.75,
            decay: recipe.decay
        )
        beatClick = Self.makeClick(
            format: format,
            frequency: recipe.beatFrequency,
            amplitude: recipe.beatAmplitude * volumeScale,
            decay: recipe.decay
        )
        secondarySubdivisionClick = Self.makeClick(
            format: format,
            frequency: (recipe.accentFrequency + recipe.beatFrequency) / 2.0,
            amplitude: recipe.beatAmplitude * volumeScale
                * MetronomePulseRole.secondary.relativeGain,
            decay: recipe.decay
        )
        weakSubdivisionClick = Self.makeClick(
            format: format,
            frequency: recipe.beatFrequency,
            amplitude: recipe.beatAmplitude * volumeScale
                * MetronomePulseRole.weak.relativeGain,
            decay: recipe.decay
        )
    }

    private func intervalToNextClick() -> AVAudioFramePosition {
        let beatDuration = 60.0 / Double(schedulerBPM)
        let steps = subdivision.steps
        let currentOffset = steps[subClickIndex].offset
        let delta: Double
        if subClickIndex + 1 < steps.count {
            delta = steps[subClickIndex + 1].offset - currentOffset
        } else {
            delta = 1.0 - currentOffset + steps[0].offset
        }
        return frames(delta * beatDuration)
    }

    private func clickBuffer(
        for role: MetronomePulseRole,
        beatKind: MetronomeBeatKind,
        accent: AVAudioPCMBuffer,
        strongAccent: AVAudioPCMBuffer,
        mediumAccent: AVAudioPCMBuffer,
        beat: AVAudioPCMBuffer,
        secondarySubdivision: AVAudioPCMBuffer,
        weakSubdivision: AVAudioPCMBuffer
    ) -> AVAudioPCMBuffer? {
        switch role {
        case .main:
            switch beatKind {
            case .strong: return strongBeatBoost ? strongAccent : accent
            case .medium: return mediumAccent
            case .weak: return beat
            case .mute: return nil
            }
        case .secondary:
            return secondarySubdivision
        case .weak:
            return weakSubdivision
        case .rest:
            return nil
        }
    }

    private func applyPendingSubdivisionAtDownbeatIfNeeded() {
        guard let pendingBoundarySubdivision else { return }
        if subdivisionBoundaryCountdown > 0 {
            subdivisionBoundaryCountdown -= 1
            return
        }
        subdivision = pendingBoundarySubdivision
        self.pendingBoundarySubdivision = nil
    }

    private var currentRhythm: MetronomeRhythmConfiguration {
        MetronomeRhythmConfiguration(
            beatsPerBar: beatsPerBar,
            denominator: denominator,
            accentPattern: accentPattern,
            subdivision: subdivision
        )
    }

    private var configuredRhythm: MetronomeRhythmConfiguration {
        MetronomeRhythmConfiguration(
            beatsPerBar: configuredBeatsPerBar,
            denominator: configuredDenominator,
            accentPattern: configuredAccentPattern,
            subdivision: configuredSubdivision
        )
    }

    private func queueConfiguredRhythmChange() {
        let target = configuredRhythm
        if target == currentRhythm {
            pendingRhythmChange = nil
            hasPendingRhythmChange = false
        } else {
            pendingRhythmChange = target
            hasPendingRhythmChange = true
        }
    }

    private func applyConfiguredRhythm() {
        apply(configuredRhythm)
        pendingRhythmChange = nil
        hasPendingRhythmChange = false
    }

    @discardableResult
    private func applyPendingRhythmAtDownbeatIfNeeded() -> Bool {
        guard let pendingRhythmChange else { return false }
        apply(pendingRhythmChange)
        self.pendingRhythmChange = nil
        hasPendingRhythmChange = false
        beatIndex = 0
        subClickIndex = 0
        return true
    }

    private func apply(_ rhythm: MetronomeRhythmConfiguration) {
        beatsPerBar = rhythm.beatsPerBar
        denominator = rhythm.denominator
        accentPattern = rhythm.accentPattern
        subdivision = rhythm.subdivision
    }

    private func advanceClickPosition() {
        if subClickIndex + 1 < subdivision.steps.count {
            subClickIndex += 1
        } else {
            subClickIndex = 0
            beatIndex += 1
        }
    }

    private func scheduleDownbeatHaptic(at frame: AVAudioFramePosition, now: AVAudioFramePosition) {
        guard hapticsEnabled, foregroundFeedbackEnabled else { return }
        let token = runToken
        let delay = Double(frame - now) / format.sampleRate
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, self.runToken == token else { return }
                guard self.foregroundFeedbackEnabled else { return }
                Haptics.downbeat()
            }
        }
    }

    private func currentFrame() -> AVAudioFramePosition {
        if let render = player.lastRenderTime,
           let time = player.playerTime(forNodeTime: render) {
            return time.sampleTime
        }
        if let render = engine.outputNode.lastRenderTime {
            return render.sampleTime
        }
        return 0
    }

    private func frames(_ seconds: Double) -> AVAudioFramePosition {
        AVAudioFramePosition(seconds * format.sampleRate)
    }

    private static func makeClick(
        format: AVAudioFormat, frequency: Double, amplitude: Double, decay: Double = 90
    ) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * 0.03)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return buffer }
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            channel[i] = Float(sin(2 * .pi * frequency * t) * exp(-t * decay) * amplitude)
        }
        return buffer
    }

    deinit {
        pump?.invalidate()
        engine.stop()
    }
}
