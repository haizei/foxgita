//
//  MetronomeEngine.swift
//  foxgita
//

import AVFoundation
import Foundation
import os

enum MetronomeError: Error, Equatable {
    case engineNotRunning
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

    var timeSignatureText: String {
        MetronomeMeter.format(beats: beatsPerBar, denominator: denominator)
    }

    var accentPatternRaw: String {
        MetronomeMeter.encodeAccent(accentPattern)
    }

    private static let lead = 0.15
    private static let pumpInterval = 0.05

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let format = AVAudioFormat(
        standardFormatWithSampleRate: 44_100, channels: 1
    )!
    @ObservationIgnored private let session: AudioSessionCoordinator
    @ObservationIgnored private var accentClick: AVAudioPCMBuffer?
    @ObservationIgnored private var beatClick: AVAudioPCMBuffer?
    @ObservationIgnored private var pump: Timer?
    @ObservationIgnored private var nextBeatFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var beatIndex = 0
    @ObservationIgnored private var graphConfigured = false
    @ObservationIgnored private var runToken = 0

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
            currentBeatInBar = 0
            runToken += 1
            player.play()
            nextBeatFrame = currentFrame() + frames(0.1)
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
        currentBeatInBar = 0
        runToken += 1
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
        accentClick = Self.makeClick(format: format, frequency: 1_000, amplitude: 0.9)
        beatClick = Self.makeClick(format: format, frequency: 800, amplitude: 0.5)
        graphConfigured = true
    }

    private func fill() {
        guard isPlaying, let accent = accentClick, let beat = beatClick else { return }
        let now = currentFrame()
        if nextBeatFrame < now {
            nextBeatFrame = now + frames(0.05)
            beatIndex = 0
            currentBeatInBar = 0
        }
        let horizon = now + frames(Self.lead)
        let step = frames(60.0 / Double(bpm))
        while nextBeatFrame <= horizon {
            let beatInBar = beatIndex % beatsPerBar
            currentBeatInBar = beatInBar
            let kind = accentPattern[beatInBar]
            if kind != .mute {
                let buffer = kind == .accent ? accent : beat
                player.scheduleBuffer(
                    buffer,
                    at: AVAudioTime(sampleTime: nextBeatFrame, atRate: format.sampleRate),
                    options: [],
                    completionHandler: nil
                )
                if kind == .accent { scheduleDownbeatHaptic(at: nextBeatFrame, now: now) }
            }
            nextBeatFrame += step
            beatIndex += 1
        }
        if !player.isPlaying { player.play() }
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
        format: AVAudioFormat, frequency: Double, amplitude: Double
    ) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * 0.03)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return buffer }
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            channel[i] = Float(sin(2 * .pi * frequency * t) * exp(-t * 90) * amplitude)
        }
        return buffer
    }

    deinit {
        pump?.invalidate()
        engine.stop()
    }
}
