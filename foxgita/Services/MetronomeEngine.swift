//
//  MetronomeEngine.swift
//  foxgita
//

import AVFoundation
import Foundation

@Observable
final class MetronomeEngine {
    private(set) var isPlaying = false
    private(set) var bpm: Int = 80

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var clickBuffer: AVAudioPCMBuffer?
    private var timer: Timer?
    private var beatIndex = 0

    func setBpm(_ value: Int) {
        let clamped = min(200, max(40, value))
        guard clamped != bpm else { return }
        bpm = clamped
        if isPlaying { restartTicker() }
    }

    func bump(_ delta: Int) { setBpm(bpm + delta) }

    func start() {
        guard !isPlaying else { return }
        configureSession()
        prepareEngineIfNeeded()
        isPlaying = true
        beatIndex = 0
        scheduleClick()
        restartTicker()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        isPlaying = false
        beatIndex = 0
    }

    func toggle() { isPlaying ? stop() : start() }

    deinit {
        timer?.invalidate()
        engine?.stop()
    }

    private func restartTicker() {
        timer?.invalidate()
        let interval = 60.0 / Double(bpm)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scheduleClick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func prepareEngineIfNeeded() {
        if engine != nil { return }
        let eng = AVAudioEngine()
        let node = AVAudioPlayerNode()
        eng.attach(node)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        eng.connect(node, to: eng.mainMixerNode, format: format)
        clickBuffer = Self.makeClickBuffer(format: format)
        try? eng.start()
        node.play()
        engine = eng
        player = node
    }

    private func scheduleClick() {
        guard let player, let clickBuffer else { return }
        player.volume = beatIndex % 4 == 0 ? 1.0 : 0.55
        beatIndex += 1
        player.scheduleBuffer(clickBuffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private static func makeClickBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * 0.03)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return buffer }
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            channel[i] = Float(sin(2 * .pi * 1000 * t) * exp(-t * 90) * 0.75)
        }
        return buffer
    }
}

@Observable
final class PracticeTimer {
    private(set) var elapsedSec = 0
    private(set) var isRunning = false
    private(set) var startedAt: Date?
    private var timer: Timer?

    func start() {
        guard !isRunning else { return }
        if startedAt == nil { startedAt = Date() }
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsedSec += 1 }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func reset() {
        pause()
        elapsedSec = 0
        startedAt = nil
    }

    var display: String {
        String(format: "%02d:%02d", elapsedSec / 60, elapsedSec % 60)
    }
}
