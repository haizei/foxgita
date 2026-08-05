//
//  MetronomeEngine.swift
//  foxgita
//

import AVFoundation
import Foundation

/// Sample-accurate metronome. Clicks are scheduled onto exact audio frames a
/// short distance ahead of the audio clock, so beat spacing comes from the
/// audio hardware rather than from when the scheduling timer happens to fire.
@Observable
final class MetronomeEngine {
    private(set) var isPlaying = false
    private(set) var bpm = 80

    /// How much audio is queued in advance. Also the worst-case latency of a
    /// tempo change, so it is kept short enough to feel immediate.
    private static let lead = 0.15
    private static let pumpInterval = 0.05

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let format = AVAudioFormat(
        standardFormatWithSampleRate: 44_100, channels: 1
    )!
    @ObservationIgnored private var accentClick: AVAudioPCMBuffer?
    @ObservationIgnored private var beatClick: AVAudioPCMBuffer?
    @ObservationIgnored private var pump: Timer?
    @ObservationIgnored private var nextBeatFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var beatIndex = 0
    @ObservationIgnored private var engineStarted = false
    /// Bumped on every stop so haptics queued for future downbeats fizzle out.
    @ObservationIgnored private var runToken = 0

    var hapticsEnabled = true

    func setBpm(_ value: Int) {
        let clamped = min(200, max(40, value))
        guard clamped != bpm else { return }
        bpm = clamped
    }

    func bump(_ delta: Int) { setBpm(bpm + delta) }

    func start() {
        guard !isPlaying else { return }
        try? AudioSessionCoordinator.shared.acquire(.playback)
        prepareEngine()
        isPlaying = true
        beatIndex = 0
        runToken += 1
        player.play()
        nextBeatFrame = currentFrame() + frames(0.1)
        fill()
        pump = Timer.scheduledTimer(withTimeInterval: Self.pumpInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fill() }
        }
        if let pump { RunLoop.main.add(pump, forMode: .common) }
    }

    func stop() {
        guard isPlaying || pump != nil else { return }
        pump?.invalidate()
        pump = nil
        player.stop()
        isPlaying = false
        beatIndex = 0
        runToken += 1
        AudioSessionCoordinator.shared.release(.playback)
    }

    func toggle() { isPlaying ? stop() : start() }

    private func prepareEngine() {
        guard !engineStarted else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        accentClick = Self.makeClick(format: format, frequency: 1_000, amplitude: 0.9)
        beatClick = Self.makeClick(format: format, frequency: 800, amplitude: 0.5)
        try? engine.start()
        engineStarted = true
    }

    /// Queues every beat that falls inside the lead window at its exact frame.
    private func fill() {
        guard isPlaying, let accent = accentClick, let beat = beatClick else { return }
        let now = currentFrame()
        // A suspended app can leave the next beat far in the past; re-anchor
        // instead of firing a burst of overdue clicks.
        if nextBeatFrame < now {
            nextBeatFrame = now + frames(0.05)
            beatIndex = 0
        }
        let horizon = now + frames(Self.lead)
        let step = frames(60.0 / Double(bpm))
        while nextBeatFrame <= horizon {
            let isDownbeat = beatIndex % 4 == 0
            player.scheduleBuffer(
                isDownbeat ? accent : beat,
                at: AVAudioTime(sampleTime: nextBeatFrame, atRate: format.sampleRate),
                options: [],
                completionHandler: nil
            )
            if isDownbeat { scheduleDownbeatHaptic(at: nextBeatFrame, now: now) }
            nextBeatFrame += step
            beatIndex += 1
        }
        if !player.isPlaying { player.play() }
    }

    /// Haptics do not need sample accuracy, so they ride a plain main-queue
    /// delay keyed to the same beat frame the click was scheduled on.
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
        guard let render = player.lastRenderTime,
              let time = player.playerTime(forNodeTime: render) else { return 0 }
        return time.sampleTime
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
