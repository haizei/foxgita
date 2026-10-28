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
    case soundAssetUnavailable(String)
    case soundAssetInvalid(String)
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
    private(set) var currentBar = 0
    private var excludedCountInBars = 0
    var displayedBar: Int? {
        currentBar > excludedCountInBars ? currentBar - excludedCountInBars : nil
    }
    func configureCountInBars(_ bars: Int) { excludedCountInBars = max(0, bars) }
    private(set) var beatsPerBar = 4
    private(set) var denominator = MetronomeMeter.defaultDenominator
    private(set) var accentPattern: [MetronomeBeatKind] = MetronomeMeter.defaultAccentPattern(beats: 4)
    private(set) var subdivision: MetronomeSubdivision = .quarter
    private(set) var configuredBeatsPerBar = 4
    private(set) var configuredDenominator = MetronomeMeter.defaultDenominator
    private(set) var configuredAccentPattern: [MetronomeBeatKind] = MetronomeMeter.defaultAccentPattern(beats: 4)
    private(set) var configuredSubdivision: MetronomeSubdivision = .quarter
    private(set) var hasPendingRhythmChange = false
    private(set) var soundPreset: MetronomeSoundPreset = .realMetronome
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
    var flashOnAccent: Bool { visualPreferences.flashEnabled && isPlaying }
    private(set) var visualPreferences = MetronomeVisualPreferences()
    private(set) var isTemporarilyMuted = false
    var isPreviewing: Bool { previewRemainingBeats != nil }

    func applyVisualPreferences(_ preference: MetronomeVisualPreferences) {
        visualPreferences = preference
        hapticsEnabled = preference.hapticsEnabled
    }

    func setTemporarilyMuted(_ muted: Bool) {
        isTemporarilyMuted = muted
        updateRenderConfiguration()
    }

    private static let lead = 0.15
    private static let pumpInterval = 0.05

    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?
    @ObservationIgnored private let renderer = MetronomeSampleRenderer(sampleRate: 44_100)
    @ObservationIgnored private var cutoffPlayer = AVAudioPlayerNode()
    @ObservationIgnored private let format = AVAudioFormat(
        standardFormatWithSampleRate: 44_100, channels: 1
    )!
    @ObservationIgnored private let session: AudioSessionCoordinator
    @ObservationIgnored private let soundBank: MetronomeSoundBank
    @ObservationIgnored private var pump: Timer?
    @ObservationIgnored private var nextClickFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var beatIndex = 0
    @ObservationIgnored private var subClickIndex = 0
    @ObservationIgnored private var graphConfigured = false
    @ObservationIgnored private var runToken = 0
    @ObservationIgnored private var previewRemainingBeats: Int?
    @ObservationIgnored private var previewStopScheduled = false
    @ObservationIgnored private var scheduledBarIndex = 0
    private struct PausedPosition {
        let beat: Int
        let bar: Int
    }
    @ObservationIgnored private var pausedPosition: PausedPosition?
    private struct PreviewReturnState {
        let position: PausedPosition?
        let bar: Int
        let countIn: Int
    }
    @ObservationIgnored private var previewReturnState: PreviewReturnState?
    @ObservationIgnored private var schedulerBPM = 80
    @ObservationIgnored private var pendingBoundaryBPM: Int?
    @ObservationIgnored private var pendingBoundarySubdivision: MetronomeSubdivision?
    @ObservationIgnored private var subdivisionBoundaryCountdown = 0
    @ObservationIgnored private var visualEventSequence = 0
    @ObservationIgnored private var pendingRhythmChange: MetronomeRhythmConfiguration?
    @ObservationIgnored private var cutoffFrame: AVAudioFramePosition?
    @ObservationIgnored private var cutoffToken = 0
    @ObservationIgnored private var cutoffCompletion: (() -> Void)?
    @ObservationIgnored private var cutoffBuffer: AVAudioPCMBuffer?

    var hapticsEnabled = true
    var foregroundFeedbackEnabled = true

    var isEngineRunning: Bool { engine.isRunning }
    var hasPump: Bool { pump != nil }
    var hasArmedCountdownStop: Bool { cutoffFrame != nil }

    init(
        session: AudioSessionCoordinator,
        soundBank: MetronomeSoundBank = MetronomeSoundBank()
    ) {
        self.session = session
        self.soundBank = soundBank
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

    func setDenominator(_ value: Int) {
        guard MetronomeMeter.supportedDenominators.contains(value) else { return }
        configuredDenominator = value
        if isPlaying { queueConfiguredRhythmChange() } else { applyConfiguredRhythm() }
    }

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
        setSoundPreset(MetronomeSoundPreset.decode(modeRaw))
        setVolume(volume ?? 80)
        setStrongBeatBoost(strongBeatBoost ?? true)
    }

    func setSoundPreset(_ value: MetronomeSoundPreset) {
        guard value != soundPreset else { return }
        soundPreset = value
        updateRenderConfiguration()
    }

    func setVolume(_ value: Int) {
        let clamped = min(100, max(0, value))
        guard clamped != volume else { return }
        volume = clamped
        updateRenderConfiguration()
    }

    func setStrongBeatBoost(_ value: Bool) {
        guard value != strongBeatBoost else { return }
        strongBeatBoost = value
        updateRenderConfiguration()
    }

    func preview(bars: Int = 2) throws {
        if isPreviewing { stopPreview() }
        guard !isPlaying else { throw MetronomeError.previewUnavailableWhilePlaying }
        let previous = PreviewReturnState(position: pausedPosition, bar: currentBar, countIn: excludedCountInBars)
        previewReturnState = previous
        previewRemainingBeats = bars * beatsPerBar
        do { try start() }
        catch {
            pausedPosition = previous.position
            currentBar = previous.bar
            excludedCountInBars = previous.countIn
            previewReturnState = nil
            throw error
        }
    }

    func stopPreview() {
        let previous = previewReturnState
        stop()
        if let previous {
            pausedPosition = previous.position
            currentBar = previous.bar
            excludedCountInBars = previous.countIn
        }
    }

    func start() throws {
        pausedPosition = nil
        try start(from: nil)
    }

    func resumePlayback() throws {
        let position = pausedPosition
        pausedPosition = nil
        try start(from: position)
    }

    func pausePlayback() {
        guard isPlaying else { return }
        guard !isPreviewing else { stop(); return }
        let bar = currentBar
        let countIn = excludedCountInBars
        let nextBeat = bar == 0 ? 0 : (currentBeatInBar + 1) % configuredBeatsPerBar
        let nextBar = max(0, bar - 1) + (bar > 0 && nextBeat == 0 ? 1 : 0)
        stop()
        pausedPosition = PausedPosition(beat: nextBeat, bar: nextBar)
        currentBar = bar
        excludedCountInBars = countIn
    }

    private func start(from position: PausedPosition?) throws {
        guard !isPlaying else { return }
        var acquired = false
        do {
            try session.acquire(.playback)
            acquired = true
            try configureGraphIfNeeded()
            if !engine.isRunning {
                try engine.start()
            }
            guard engine.isRunning else { throw MetronomeError.engineNotRunning }
            renderer.start()
            cancelArmedCountdownStop()
            beatIndex = position?.beat ?? 0
            subClickIndex = 0
            scheduledBarIndex = position?.bar ?? 0
            currentBeatInBar = position?.beat ?? 0
            if position == nil, !isPreviewing { currentBar = 0 }
            visualEvent = nil
            runToken += 1
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
            renderer.stop()
            engine.pause()
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
        previewReturnState = nil
        pausedPosition = nil
        currentBar = 0
        excludedCountInBars = 0
        guard isPlaying || pump != nil else { return }
        cancelArmedCountdownStop()
        pump?.invalidate()
        pump = nil
        renderer.stop()
        engine.pause()
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

    /// Arms a hard stop on the audio sample timeline. `fill()` also clamps its
    /// scheduling horizon so no click can be queued at or beyond the cutoff.
    func armCountdownStop(after seconds: TimeInterval, onReached: @escaping () -> Void) {
        guard isPlaying, seconds > 0 else { return }
        cancelArmedCountdownStop()
        let frame = currentFrame() + frames(seconds)
        cutoffFrame = frame
        renderer.setCutoff(frame)
        cutoffCompletion = onReached
        cutoffToken += 1
        let token = cutoffToken
        guard let buffer = cutoffBuffer else { return }
        cutoffPlayer.scheduleBuffer(
            buffer,
            at: AVAudioTime(hostTime: renderer.hostTime(forFrame: frame)),
            options: [],
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.finishArmedCountdownStop(token: token)
                }
            }
        }
        if !cutoffPlayer.isPlaying { cutoffPlayer.play() }
    }

    func cancelArmedCountdownStop() {
        cutoffToken += 1
        cutoffFrame = nil
        renderer.setCutoff(nil)
        cutoffCompletion = nil
        cutoffPlayer.stop()
    }

    func prepareAfterAudioServicesReset() {
        stop()
        engine.stop()
        engine = AVAudioEngine()
        sourceNode = nil
        cutoffPlayer = AVAudioPlayerNode()
        graphConfigured = false
        metronomeLog.notice("audio graph reset after media-services reset")
    }

    private func configureGraphIfNeeded() throws {
        guard !graphConfigured else { return }
        try soundBank.preloadAll(expectedFormat: format)
        var samples: [[Float]] = []
        for preset in MetronomeSoundPreset.allCases {
            guard let buffers = soundBank.buffers(for: preset) else { throw MetronomeError.soundAssetUnavailable(preset.rawValue) }
            for buffer in [buffers.beat, buffers.strong] {
                guard let channel = buffer.floatChannelData?[0] else { throw MetronomeError.soundAssetInvalid(preset.rawValue) }
                samples.append(Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
            }
        }
        renderer.installSamples(samples)
        let renderer = renderer
        let source = AVAudioSourceNode(format: format) { silence, timestamp, count, buffers in
            silence.pointee = false
            let start = renderer.frame(forHostTime: timestamp.pointee.mHostTime)
            for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
                if let data = buffer.mData {
                    renderer.render(into: data.assumingMemoryBound(to: Float.self), startingAt: start, count: Int(count))
                }
            }
            return noErr
        }
        sourceNode = source
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.attach(cutoffPlayer)
        engine.connect(cutoffPlayer, to: engine.mainMixerNode, format: format)
        cutoffBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)
        cutoffBuffer?.frameLength = 1
        cutoffBuffer?.floatChannelData?[0][0] = 0
        updateRenderConfiguration()
        graphConfigured = true
    }

    private func fill() {
        guard isPlaying, !previewStopScheduled else { return }
        let now = currentFrame()
        if let cutoffFrame, now >= cutoffFrame {
            finishArmedCountdownStop(token: cutoffToken)
            return
        }
        if nextClickFrame < now {
            nextClickFrame = now + frames(0.05)
            beatIndex = 0
            subClickIndex = 0
            currentBeatInBar = 0
        }
        let normalHorizon = now + frames(Self.lead)
        let horizon = cutoffFrame.map { min(normalHorizon, $0 - 1) } ?? normalHorizon
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
            if beatKind != .mute, step.role != .rest {
                guard renderer.schedule(frame: nextClickFrame, role: step.role, kind: beatKind) else {
                    metronomeLog.error("audio scheduling queue exhausted")
                    stop()
                    return
                }
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
                    schedulePreviewStop(at: scheduledFrame + frames(0.075), now: now)
                    return
                }
            }
        }
    }

    private func finishArmedCountdownStop(token: Int) {
        guard token == cutoffToken, cutoffFrame != nil else { return }
        let completion = cutoffCompletion
        cutoffFrame = nil
        cutoffCompletion = nil
        cutoffToken += 1
        cutoffPlayer.stop()
        stop()
        completion?()
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
                guard !self.isPreviewing else { return }
                self.currentBar = event.bar + 1
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
                self.stopPreview()
            }
        }
    }

    private func updateRenderConfiguration() {
        let index = Array(MetronomeSoundPreset.allCases).firstIndex(of: soundPreset) ?? 0
        renderer.configure(preset: index, volume: Float(volume) / 100, strongBeatBoost: strongBeatBoost, muted: isTemporarilyMuted)
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
        renderer.frame(forHostTime: mach_absolute_time())
    }

    private func frames(_ seconds: Double) -> AVAudioFramePosition {
        AVAudioFramePosition(seconds * format.sampleRate)
    }

}
