import AVFoundation
import Foundation
import os

@MainActor protocol ScoreAudioDriving: AnyObject {
    var seconds: Double { get }
    var listening: Bool { get }
    var listeningUnavailableReason: String? { get }
    var onObservation: ((ScorePitchObservation,Double) -> Void)? { get set }
    var demoVolume: Double { get set }
    var clickVolume: Double { get set }
    func start(run: ScoreRun) async throws
    func stop()
}
extension ScoreAudioDriving { var listeningUnavailableReason: String? { nil } }

nonisolated private struct ScoreVoice {
    var active = false
    var phase = 0.0
    var increment = 0.0
    var envelope = 0.0
    var decay = 1.0
    var remaining: Int64 = 0
    var age: Int64 = 0
    var click = false
}

nonisolated final class ScoreSynthRenderer: @unchecked Sendable {
    private struct State {
        var frames: Int64 = 0
        var origin: UInt64 = 0
        var playing = true
        var previousPosition: Int64 = -1
        var noteIndex = 0
        var beatIndex = 0
        var voices = Array(repeating: ScoreVoice(), count: 48)
        var demo: Double = 0.7
        var click: Double = 0.5
    }
    private struct Controls {
        var frames: Int64 = 0
        var origin: UInt64 = 0
        var playing = true
        var demo = 0.7
        var click = 0.5
    }
    // Only the single audio render callback mutates voices/scheduling.
    private var renderState = State()
    private let controls = OSAllocatedUnfairLock(initialState: Controls())
    private let plan: ScoreSynthesisPlan
    private let offset: Int64
    private let lead: Int64
    private let limit: Int64?
    private let countInBeatFrames: Int64

    init(plan: ScoreSynthesisPlan, offsetSeconds: Double, countIn: Double, countInBeats: Int, loopsRemaining: Int?) {
        self.plan = plan
        let initialOffset = max(0,min(plan.loopFrames-1,Int64(offsetSeconds*plan.sampleRate)))
        offset = initialOffset
        lead = Int64(countIn*plan.sampleRate)
        limit = loopsRemaining.map { Int64(max(1,$0))*plan.loopFrames-initialOffset }
        countInBeatFrames = max(1,lead / Int64(max(1,countInBeats)))
    }
    var seconds: Double { controls.withLock { Double($0.frames)/plan.sampleRate } }
    var originSeconds: Double? { controls.withLock { $0.origin == 0 ? nil : AVAudioTime.seconds(forHostTime: $0.origin) } }
    func stop() { controls.withLock { $0.playing = false } }
    func configure(demo: Double, click: Double) { controls.withLock { $0.demo = min(1,max(0,demo)); $0.click = min(1,max(0,click)) } }

    func render(time: UnsafePointer<AudioTimeStamp>, frameCount: AVAudioFrameCount, data: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(data)
        for buffer in buffers { if let p = buffer.mData { memset(p,0,Int(buffer.mDataByteSize)) } }
        if let snapshot = controls.withLockIfAvailable({ $0 }) {
            renderState.playing = renderState.playing && snapshot.playing
            renderState.demo = snapshot.demo; renderState.click = snapshot.click
        }
        render(time: time,frameCount: frameCount,buffers: buffers,state: &renderState)
        _ = controls.withLockIfAvailable {
            $0.frames = renderState.frames; $0.origin = renderState.origin
        }
    }
    private func render(time: UnsafePointer<AudioTimeStamp>,frameCount: AVAudioFrameCount,buffers: UnsafeMutableAudioBufferListPointer,state s: inout State) {
            guard s.playing, plan.loopFrames > 0 else { return }
            if s.origin == 0 { s.origin = time.pointee.mHostTime }
            for frame in 0..<Int(frameCount) {
                guard s.playing else { break }
                if s.frames < lead {
                    if s.frames % countInBeatFrames == 0 { activate(midi: 92, duration: Int64(plan.sampleRate*0.035), gain: 0.18, click: true, state: &s) }
                } else {
                    let official = s.frames-lead
                    if let limit, official >= limit { s.playing = false; break }
                    let position = (official+offset) % plan.loopFrames
                    if s.previousPosition < 0 || position < s.previousPosition {
                        s.noteIndex = 0; s.beatIndex = 0
                        for i in s.voices.indices { s.voices[i].active = false }
                    }
                    while s.noteIndex < plan.notes.count && plan.notes[s.noteIndex].frame <= position {
                        let note = plan.notes[s.noteIndex]
                        if note.frame+note.durationFrames > position {
                            activate(midi: note.midi,duration: note.frame+note.durationFrames-position,gain: Double(note.gain),click: false,state: &s)
                        }
                        s.noteIndex += 1
                    }
                    while s.beatIndex < plan.beatFrames.count && plan.beatFrames[s.beatIndex] <= position {
                        if position-plan.beatFrames[s.beatIndex] < 2 {
                            activate(midi: plan.downbeatFrames.contains(plan.beatFrames[s.beatIndex]) ? 96 : 90,duration: Int64(plan.sampleRate*0.025),gain: 0.14,click: true,state: &s)
                        }
                        s.beatIndex += 1
                    }
                    s.previousPosition = position
                }
                var sample = 0.0
                for i in s.voices.indices where s.voices[i].active {
                    var voice = s.voices[i]
                    let release = min(1,Double(voice.remaining)/max(1,plan.sampleRate*0.006))
                    let attack = min(1,Double(voice.age)/max(1,plan.sampleRate*0.003))
                    let wave = sin(voice.phase) + (voice.click ? 0 : 0.4*sin(2*voice.phase)+0.2*sin(3*voice.phase))
                    sample += wave*voice.envelope*release*attack*(voice.click ? s.click : s.demo)
                    voice.phase += voice.increment
                    if voice.phase > 2 * .pi { voice.phase -= 2 * .pi }
                    voice.envelope *= voice.decay
                    voice.age += 1; voice.remaining -= 1
                    if voice.remaining <= 0 { voice.active = false }
                    s.voices[i] = voice
                }
                let value = Float(max(-0.95,min(0.95,sample)))
                for buffer in buffers {
                    guard let p = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let channels = max(1,Int(buffer.mNumberChannels))
                    for channel in 0..<channels { p[frame*channels+channel] = value }
                }
                s.frames += 1
            }
    }
    private func activate(midi: Int,duration: Int64,gain: Double,click: Bool,state s: inout State) {
        let i = s.voices.firstIndex { !$0.active } ?? s.voices.indices.min { s.voices[$0].envelope < s.voices[$1].envelope } ?? 0
        let frequency = 440*pow(2,Double(midi-69)/12)
        s.voices[i] = ScoreVoice(active: true,phase: 0,increment: 2 * .pi * frequency/plan.sampleRate,
            envelope: gain,decay: exp(-(click ? 90 : 2.8)/plan.sampleRate),remaining: duration,age: 0,click: click)
    }
}

/// One bounded worker; new input coalesces instead of queuing stale analysis.
nonisolated final class ScoreAnalysisWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "gita.score.analysis",qos: .userInitiated)
    private let lock = NSLock()
    private let analyzer = ScorePitchAnalyzer()
    private var ring: [Float] = []
    private var index = 0, filled = 0, fresh = 0, generation = 0
    private var rate = 0.0, end = 0.0
    private let deliver: @Sendable (ScorePitchObservation,Double) -> Void

    private var timer: DispatchSourceTimer?
    init(sampleRate: Double,deliver: @escaping @Sendable (ScorePitchObservation,Double) -> Void) {
        self.deliver = deliver
        rate = sampleRate
        let factor = max(1,Int(ceil(sampleRate/24_000)))
        ring = Array(repeating: 0,count: 4_096*factor)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(),repeating: .milliseconds(30))
        timer.setEventHandler { [weak self] in self?.analyzePending() }
        self.timer = timer; timer.resume()
    }
    deinit { timer?.cancel() }

    func consume(_ buffer: AVAudioPCMBuffer, at endTime: Double) {
        guard let channel = buffer.floatChannelData?.pointee,buffer.frameLength > 0,
              buffer.format.sampleRate == rate,lock.try() else { return }
        defer { lock.unlock() }
        let count = Int(buffer.frameLength),capacity = ring.count
        let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        if end > 0,endTime-end > Double(count)/rate+0.025 {
            filled = 0; fresh = 0; generation += 1
        }
        for i in max(0,count-capacity)..<count { ring[index] = channel[i*stride]; index = (index+1)%capacity }
        filled = min(capacity,filled+count); fresh = min(capacity,fresh+count); end = endTime
    }
    private func analyzePending() {
        lock.lock()
        guard filled == ring.count,fresh >= ring.count/4 else { lock.unlock(); return }
        let frame = snapshotLocked() // allocation belongs to the worker, never the tap
        lock.unlock()
        let observation = analyzer.analyze(samples: frame.0,sampleRate: frame.1)
        lock.lock(); let valid = frame.3 == generation; lock.unlock()
        if valid { deliver(observation,frame.2) }
    }
    private func snapshotLocked() -> ([Float],Double,Double,Int) {
        let factor = ring.count/4_096
        var result = [Float](repeating: 0,count: 4_096)
        for i in result.indices {
            var sum: Float = 0
            for j in 0..<factor { sum += ring[(index+i*factor+j)%ring.count] }
            result[i] = sum/Float(factor)
        }
        fresh = 0
        return (result,rate/Double(factor),end-Double(ring.count)/rate/2,generation)
    }
}

@MainActor final class ScoreAudioEngine: ScoreAudioDriving {
    var onObservation: ((ScorePitchObservation,Double) -> Void)?
    private var engine: AVAudioEngine?
    private var renderer: ScoreSynthRenderer?
    private var worker: ScoreAnalysisWorker?
    private var ownership: AudioSessionCoordinator.Need?
    private var generation = UUID()
    private(set) var listening = false
    private(set) var listeningUnavailableReason: String?
    private var lead = 0.0
    private var outputLatency = 0.0
    private let permissionRequest: (() async -> Bool)?
    private let inputAvailable: @Sendable (Double,UInt32) -> Bool
    private let isolatedOutput: () -> Bool
    init(permissionRequest: (() async -> Bool)? = nil,inputAvailable: (@Sendable (Double,UInt32) -> Bool)? = nil,isolatedOutput: (() -> Bool)? = nil) {
        self.permissionRequest = permissionRequest
        self.inputAvailable = inputAvailable ?? { rate,channels in rate.isFinite && (8_000...192_000).contains(rate) && channels > 0 }
        self.isolatedOutput = isolatedOutput ?? {
            let ports = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType)
            return !ports.isEmpty && ports.allSatisfy { [.headphones,.bluetoothA2DP,.bluetoothHFP,.bluetoothLE].contains($0) }
        }
    }
    var seconds: Double { renderer?.seconds ?? 0 }
    var demoVolume = 0.7 { didSet { renderer?.configure(demo: demoVolume,click: clickVolume); refreshInputSafety() } }
    var clickVolume = 0.5 { didSet { renderer?.configure(demo: demoVolume,click: clickVolume); refreshInputSafety() } }
    private var safeToListen: Bool { (demoVolume == 0 && clickVolume == 0) || isolatedOutput() }
    private func refreshInputSafety() {
        guard worker != nil,!safeToListen else { return }
        generation = UUID(); engine?.inputNode.removeTap(onBus: 0); worker = nil; listening = false
        listeningUnavailableReason = "外放不评分，请连接耳机后手动继续"
    }

    func start(run: ScoreRun) async throws {
        stop()
        let requestToken = UUID(); generation = requestToken
        let allowed: Bool
        if !safeToListen { allowed = false }
        else if let permissionRequest { allowed = await permissionRequest() }
        else {
            allowed = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        }
        guard generation == requestToken, !Task.isCancelled else { throw CancellationError() }
        listeningUnavailableReason = safeToListen ? (allowed ? "收音暂不可用，可继续无评分跟谱" : "麦克风未开启，可继续无评分跟谱") : "外放不评分，请连接耳机或关闭示范音与节拍器"
        let need: AudioSessionCoordinator.Need = allowed ? .followScore : .playback
        try AudioSessionCoordinator.shared.acquire(need)
        ownership = need
        do {
            let engine = AVAudioEngine()
            let rate = AVAudioSession.sharedInstance().sampleRate
            guard rate.isFinite,(8_000...192_000).contains(rate),let format = AVAudioFormat(standardFormatWithSampleRate: rate,channels: 1) else { throw ScoreRunError.invalidConfiguration }
            let plan = try ScoreSynthesisPlan(score: run.score,range: run.range,speed: run.speed,sampleRate: rate)
            let renderer = ScoreSynthRenderer(plan: plan,offsetSeconds: run.positionSeconds,countIn: run.countInRemaining,
                countInBeats: run.score.bars[run.score.barIndex(atTick: run.tick)].numerator,loopsRemaining: run.remainingTraversals)
            renderer.configure(demo: demoVolume,click: clickVolume)
            let node = AVAudioSourceNode(format: format) { _, time, count, data in
                renderer.render(time: time,frameCount: count,data: data); return noErr
            }
            engine.attach(node); engine.connect(node,to: engine.mainMixerNode,format: format)
            self.renderer = renderer; self.engine = engine; lead = run.countInRemaining
            outputLatency = AVAudioSession.sharedInstance().outputLatency
            let token = UUID(); generation = token
            if allowed {
                let input = engine.inputNode, inputFormat = input.outputFormat(forBus: 0)
                if safeToListen,inputAvailable(inputFormat.sampleRate,inputFormat.channelCount) {
                let worker = ScoreAnalysisWorker(sampleRate: inputFormat.sampleRate) { [weak self] observation,capturedAt in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token, self.engine?.isRunning == true,
                              let origin = self.renderer?.originSeconds else { return }
                        guard self.safeToListen else { self.refreshInputSafety(); return }
                        self.onObservation?(observation,capturedAt-origin-self.lead-self.outputLatency)
                    }
                }
                input.installTap(onBus: 0,bufferSize: 1024,format: inputFormat) { buffer,time in
                    guard time.isHostTimeValid else { return }
                    worker.consume(buffer,at: AVAudioTime.seconds(forHostTime: time.hostTime)+Double(buffer.frameLength)/buffer.format.sampleRate)
                }
                self.worker = worker
                }
            }
            engine.prepare(); try engine.start(); listening = worker != nil
            if listening { listeningUnavailableReason = nil }
            else if !safeToListen { listeningUnavailableReason = "外放不评分，请连接耳机或关闭示范音与节拍器" }
        } catch { stop(); throw error }
    }
    func stop() {
        generation = UUID()
        renderer?.stop()
        if worker != nil { engine?.inputNode.removeTap(onBus: 0) }
        engine?.stop(); engine = nil; worker = nil; renderer = nil; listening = false
        listeningUnavailableReason = nil
        if let ownership { AudioSessionCoordinator.shared.release(ownership) }
        ownership = nil
    }
}
