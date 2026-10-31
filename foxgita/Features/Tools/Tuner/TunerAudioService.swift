import AVFoundation
import Foundation

@MainActor
protocol TunerAudioIO: AnyObject {
    var onObservation: ((TunerAudioObservation) -> Void)? { get set }
    var captureID: UUID { get }
    var onFailure: ((String) -> Void)? { get set }
    func requestPermission() async -> Bool
    func startCapture() throws
    func stopCapture()
    func playReference(frequency: Double, completion: @escaping () -> Void) throws
    func stopReference()
}

/// Keep continuous PCM in a bounded ring even while analysis is busy. A single
/// background job coalesces to the latest window instead of queuing old audio.
nonisolated final class TunerPitchWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "gita.tuner.pitch", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var ring: [Float] = []
    private var writeIndex = 0
    private var filled = 0
    private var freshSamples = 0
    private var rate = 0.0
    private var hop = 0
    private var capturedAt = -Double.infinity
    private var formatGeneration = 0
    private let runID: UUID
    private let deliver: @Sendable (TunerAudioObservation) -> Void

    init(runID: UUID = UUID(), deliver: @escaping @Sendable (TunerAudioObservation) -> Void) {
        self.runID = runID; self.deliver = deliver
    }

    func consume(_ buffer: AVAudioPCMBuffer, capturedAt endTime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let channel = buffer.floatChannelData?.pointee, buffer.frameLength > 0 else { return }
        let sampleRate = buffer.format.sampleRate
        guard sampleRate.isFinite, (4_000...192_000).contains(sampleRate), endTime.isFinite else { return }
        let factor = max(1, Int(ceil(sampleRate / 12_000)))
        let needed = TunerPitchDetector.analysisSampleCount * factor
        let count = Int(buffer.frameLength)
        let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        lock.lock()
        guard endTime > capturedAt else { lock.unlock(); return }
        if rate != sampleRate {
            ring = Array(repeating: 0, count: needed)
            writeIndex = 0; filled = 0; freshSamples = 0
            rate = sampleRate
            hop = needed / 4
            formatGeneration += 1
        }
        capturedAt = endTime
        for i in max(0, count - needed)..<count {
            ring[writeIndex] = channel[i * stride]
            writeIndex = (writeIndex + 1) % needed
        }
        filled = min(needed, filled + count)
        freshSamples = min(needed, freshSamples + count)
        guard !busy, filled == needed, freshSamples >= hop else { lock.unlock(); return }
        busy = true
        let frame = snapshotLocked()
        lock.unlock()
        queue.async { [self] in analyze(frame) }
    }

    // All ring state is protected by lock; no DSP or delivery runs under it.
    private func snapshotLocked() -> (samples: [Float], rate: Double, endTime: TimeInterval, format: Int) {
        var samples: [Float] = []
        samples.reserveCapacity(ring.count)
        samples.append(contentsOf: ring[writeIndex...])
        samples.append(contentsOf: ring[..<writeIndex])
        freshSamples = 0
        return (samples, rate, capturedAt, formatGeneration)
    }

    private func analyze(_ initial: (samples: [Float], rate: Double, endTime: TimeInterval, format: Int)) {
        var frame = initial
        while true {
            let result = TunerPitchDetector.estimate(samples: frame.samples, sampleRate: frame.rate)
            lock.lock()
            let currentRate = formatGeneration == frame.format
            lock.unlock()
            if currentRate {
                deliver(TunerAudioObservation(pitch: result, capturedAt: frame.endTime, sampleRate: frame.rate, runID: runID))
            }
            lock.lock()
            guard filled == ring.count, freshSamples >= hop else {
                busy = false
                lock.unlock()
                return
            }
            frame = snapshotLocked()
            lock.unlock()
        }
    }
}

@MainActor
final class TunerAudioService: TunerAudioIO {
    var onObservation: ((TunerAudioObservation) -> Void)?
    var onFailure: ((String) -> Void)?
    private let session: AudioSessionCoordinator
    private var engine: AVAudioEngine?
    private var worker: TunerPitchWorker?
    private var ownsTuning = false
    private var ownsPlayback = false
    private var generation = UUID()
    var captureID: UUID { generation }
    private var player: AVAudioPlayer?
    private var referenceTask: Task<Void, Never>?
    private var configurationObserver: NSObjectProtocol?

    init(session: AudioSessionCoordinator = .shared) { self.session = session }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    func startCapture() throws {
        stopCapture()
        try session.acquire(.tuning)
        ownsTuning = true
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            stopCapture()
            throw CocoaError(.featureUnsupported)
        }
        let token = UUID()
        generation = token
        let worker = TunerPitchWorker(runID: token) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.engine?.isRunning == true else { return }
                self.onObservation?(result)
            }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            guard time.isHostTimeValid else {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.stopCapture()
                    self.onFailure?(String(localized: "无法获取音频采样时间，请重新开始调音。"))
                }
                return
            }
            let endTime = AVAudioTime.seconds(forHostTime: time.hostTime) + Double(buffer.frameLength) / buffer.format.sampleRate
            worker.consume(buffer, capturedAt: endTime)
        }
        self.engine = engine
        self.worker = worker
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.stopCapture()
                self.onFailure?(String(localized: "音频设备已变化，请重新开始调音。"))
            }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            stopCapture()
            throw error
        }
    }

    func stopCapture() {
        generation = UUID()
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        worker = nil
        if ownsTuning { session.release(.tuning); ownsTuning = false }
    }

    func playReference(frequency: Double, completion: @escaping () -> Void) throws {
        stopReference()
        try session.acquire(.playback)
        ownsPlayback = true
        do {
            let player = try AVAudioPlayer(data: TunerReferenceTone.wav(frequency: frequency))
            player.prepareToPlay()
            guard player.play() else { throw CocoaError(.featureUnsupported) }
            self.player = player
            referenceTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(player.duration))
                guard !Task.isCancelled, let self else { return }
                self.stopReference()
                completion()
            }
        } catch {
            stopReference()
            throw error
        }
    }

    func stopReference() {
        referenceTask?.cancel()
        referenceTask = nil
        player?.stop()
        player = nil
        if ownsPlayback { session.release(.playback); ownsPlayback = false }
    }
}
