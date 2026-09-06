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
    private(set) var soundMode: MetronomeSoundMode = .standard
    private(set) var volume = 80
    private(set) var strongBeatBoost = true

    var timeSignatureText: String {
        MetronomeMeter.format(beats: beatsPerBar, denominator: denominator)
    }

    var accentPatternRaw: String {
        MetronomeMeter.encodeAccent(accentPattern)
    }

    var subdivisionRaw: Int { subdivision.rawValue }
    var flashOnAccent: Bool { soundMode == .drums && isPlaying }

    private static let lead = 0.15
    private static let pumpInterval = 0.05

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let format = AVAudioFormat(
        standardFormatWithSampleRate: 44_100, channels: 1
    )!
    @ObservationIgnored private let session: AudioSessionCoordinator
    @ObservationIgnored private var accentClick: AVAudioPCMBuffer?
    @ObservationIgnored private var strongAccentClick: AVAudioPCMBuffer?
    @ObservationIgnored private var beatClick: AVAudioPCMBuffer?
    @ObservationIgnored private var pump: Timer?
    @ObservationIgnored private var nextClickFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var beatIndex = 0
    @ObservationIgnored private var subClickIndex = 0
    @ObservationIgnored private var graphConfigured = false
    @ObservationIgnored private var runToken = 0
    @ObservationIgnored private var previewRemainingBeats: Int?
    @ObservationIgnored private var previewStopScheduled = false

    var hapticsEnabled = true

    var isEngineRunning: Bool { engine.isRunning }
    var hasPump: Bool { pump != nil }

    init(session: AudioSessionCoordinator = .shared) {
        self.session = session
    }

    func setBpm(_ value: Int) {
        let clamped = min(200, max(40, value))
        guard clamped != bpm else { return }
        bpm = clamped
    }

    func bump(_ delta: Int) { setBpm(bpm + delta) }

    func configureMeter(timeSignature: String?, accentRaw: String?) {
        let parsed = MetronomeMeter.parseTimeSignature(timeSignature)
        beatsPerBar = parsed.beats
        denominator = parsed.denominator
        accentPattern = MetronomeMeter.decodeAccent(accentRaw, beats: parsed.beats)
    }

    func setBeatsPerBar(_ value: Int) {
        let clamped = min(MetronomeMeter.maxBeats, max(MetronomeMeter.minBeats, value))
        guard clamped != beatsPerBar else { return }
        if clamped > beatsPerBar {
            accentPattern.append(
                contentsOf: Array(repeating: MetronomeBeatKind.normal, count: clamped - beatsPerBar)
            )
        } else {
            accentPattern = Array(accentPattern.prefix(clamped))
        }
        beatsPerBar = clamped
    }

    func bumpBeatsPerBar(_ delta: Int) { setBeatsPerBar(beatsPerBar + delta) }

    func cycleAccent(at index: Int) {
        guard accentPattern.indices.contains(index) else { return }
        accentPattern[index].cycle()
    }

    func configureSubdivision(raw: Int?) {
        subdivision = MetronomeSubdivision.decode(raw)
    }

    func setSubdivision(_ value: MetronomeSubdivision) {
        guard value != subdivision else { return }
        subdivision = value
    }

    func bumpSubdivision(_ delta: Int) {
        let all = Array(MetronomeSubdivision.allCases)
        guard let index = all.firstIndex(of: subdivision) else { return }
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
        if value == .drums { hapticsEnabled = true }
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
            currentBeatInBar = 0
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
        currentBeatInBar = 0
        runToken += 1
        previewRemainingBeats = nil
        previewStopScheduled = false
        session.release(.playback)
        metronomeLog.debug(
            "stop running=\(self.engine.isRunning, privacy: .public) other=\(AVAudioSession.sharedInstance().isOtherAudioPlaying, privacy: .public)"
        )
    }

    func toggle() {
        if isPlaying { stop() } else { try? start() }
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
              let beat = beatClick else { return }
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
            let beatInBar = beatIndex % beatsPerBar
            if subClickIndex == 0 { currentBeatInBar = beatInBar }
            let beatKind = accentPattern[beatInBar]
            if beatKind != .mute {
                let useAccent = beatKind == .accent && subClickIndex == 0
                let buffer = useAccent ? (strongBeatBoost ? strongAccent : accent) : beat
                player.scheduleBuffer(
                    buffer,
                    at: AVAudioTime(sampleTime: nextClickFrame, atRate: format.sampleRate),
                    options: [],
                    completionHandler: nil
                )
                if useAccent { scheduleDownbeatHaptic(at: nextClickFrame, now: now) }
            }
            nextClickFrame += intervalToNextClick()
            advanceClickPosition()
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
        case .acousticGuitar:
            ClickRecipe(
                accentFrequency: 1_400, accentAmplitude: 1.0,
                beatFrequency: 1_200, beatAmplitude: 0.6, decay: 120
            )
        case .drums:
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
        beatClick = Self.makeClick(
            format: format,
            frequency: recipe.beatFrequency,
            amplitude: recipe.beatAmplitude * volumeScale,
            decay: recipe.decay
        )
    }

    private func intervalToNextClick() -> AVAudioFramePosition {
        let beatDuration = 60.0 / Double(bpm)
        let offsets = subdivision.clickOffsets
        let currentOffset = offsets[subClickIndex]
        let delta: Double
        if subClickIndex + 1 < offsets.count {
            delta = offsets[subClickIndex + 1] - currentOffset
        } else {
            delta = 1.0 - currentOffset + offsets[0]
        }
        return frames(delta * beatDuration)
    }

    private func advanceClickPosition() {
        if subClickIndex + 1 < subdivision.clickOffsets.count {
            subClickIndex += 1
        } else {
            subClickIndex = 0
            beatIndex += 1
        }
    }

    private func scheduleDownbeatHaptic(at frame: AVAudioFramePosition, now: AVAudioFramePosition) {
        guard hapticsEnabled else { return }
        let token = runToken
        let delay = Double(frame - now) / format.sampleRate
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, self.runToken == token else { return }
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
