import AVFoundation
import Foundation

@MainActor struct OriginalScoreSettings {
    var bpm = 80.0
    var numerator = 4
    var denominator = 4
    var enabled = false
    var preset: MetronomeSoundPreset = .realMetronome
    var accents: [MetronomeBeatKind] = MetronomeMeter.defaultAccentPattern(beats: 4)
    var subdivision: MetronomeSubdivision = .quarter
    var volume = 80
    var boost = true

    init() {}
    init(engine: MetronomeEngine) {
        bpm = Double(engine.bpm); numerator = engine.configuredBeatsPerBar
        denominator = engine.configuredDenominator; enabled = engine.isPlaying
        preset = engine.soundPreset; accents = engine.configuredAccentPattern
        subdivision = engine.configuredSubdivision; volume = engine.volume; boost = engine.strongBeatBoost
    }
}

/// Uses the same host clock for PCM scheduling and the visible musical position.
/// Muting only changes output gain; the clock and scheduled pulse grid continue.
@MainActor final class OriginalScoreAudio {
    private let renderer = MetronomeSampleRenderer(sampleRate: 44_100)
    private let bank = MetronomeSoundBank()
    private var engine: AVAudioEngine?
    private var ownership = false
    private var origin: UInt64 = 0
    private var plan: OriginalScoreRun?
    private var settings = OriginalScoreSettings()
    private var scheduledThrough = -0.000001
    private var enabled = false

    var seconds: Double {
        guard origin > 0 else { return 0 }
        let now = mach_absolute_time()
        return now >= origin ? AVAudioTime.seconds(forHostTime: now - origin) : 0
    }

    func start(run: OriginalScoreRun, settings: OriginalScoreSettings, enabled: Bool) throws {
        stop()
        try AudioSessionCoordinator.shared.acquire(.playback)
        ownership = true
        do {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
                throw OriginalScoreError.invalidDocument
            }
            try bank.preloadAll(expectedFormat: format)
            var samples: [[Float]] = []
            for preset in MetronomeSoundPreset.allCases {
                guard let pair = bank.buffers(for: preset) else { throw MetronomeError.soundAssetUnavailable(preset.rawValue) }
                for buffer in [pair.beat, pair.strong] {
                    guard let channel = buffer.floatChannelData?[0] else { throw MetronomeError.soundAssetInvalid(preset.rawValue) }
                    samples.append(Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
                }
            }
            renderer.installSamples(samples)
            self.settings = settings
            if self.settings.accents.count != run.document.numerator {
                self.settings.accents = MetronomeMeter.defaultAccentPattern(beats: run.document.numerator)
            }
            self.enabled = enabled; plan = run; scheduledThrough = -0.000001
            let engine = AVAudioEngine()
            let renderer = renderer
            let source = AVAudioSourceNode(format: format) { _, time, count, buffers in
                let first = renderer.frame(forHostTime: time.pointee.mHostTime)
                for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
                    if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                        renderer.render(into: data, startingAt: first, count: Int(count))
                    }
                }
                return noErr
            }
            engine.attach(source); engine.connect(source, to: engine.mainMixerNode, format: format)
            engine.prepare()
            origin = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.03)
            renderer.start(); configureOutput()
            if !run.looping {
                let end = origin + AVAudioTime.hostTime(forSeconds: (run.rangeBeats - run.position) * 60 / run.bpm)
                renderer.setCutoff(renderer.frame(forHostTime: end))
            }
            schedule()
            self.engine = engine
            try engine.start()
        } catch { stop(); throw error }
    }

    func mute(_ muted: Bool) { enabled = !muted; configureOutput() }
    private func configureOutput() {
        let index = MetronomeSoundPreset.allCases.firstIndex(of: settings.preset) ?? 0
        renderer.configure(preset: index, volume: Float(settings.volume) / 100,
                           strongBeatBoost: settings.boost, muted: !enabled)
    }

    func schedule() {
        guard let run = plan, origin > 0 else { return }
        let end = seconds + 0.2
        let rate = run.bpm / 60
        let length = run.rangeBeats
        let lower = max(0, run.position + scheduledThrough * rate)
        let upper = run.position + end * rate
        let firstCycle = Int(floor(lower / length))
        let lastCycle = Int(floor(upper / length))
        let phase = (run.document.startingBeat + run.startBeat)
            .truncatingRemainder(dividingBy: Double(run.document.numerator))
        for cycle in firstCycle...lastCycle {
            if !run.looping && cycle > 0 { break }
            let base = Double(cycle) * length
            let localLow = max(0, lower - base)
            let localHigh = min(length, upper - base)
            guard localHigh >= localLow else { continue }
            for beat in Int(floor(phase + localLow))...Int(ceil(phase + localHigh)) {
                for step in settings.subdivision.steps where step.role != .rest {
                    let local = Double(beat) + step.offset - phase
                    let time = (base + local - run.position) / rate
                    guard local >= 0, local < length, time >= 0,
                          time > scheduledThrough + 0.00000001, time <= end else { continue }
                    let kind = settings.accents[beat % run.document.numerator]
                    guard kind != .mute else { continue }
                    let host = origin + AVAudioTime.hostTime(forSeconds: time)
                    guard renderer.schedule(frame: renderer.frame(forHostTime: host), role: step.role, kind: kind) else { continue }
                }
            }
        }
        scheduledThrough = end
    }

    func stop() {
        renderer.stop(); engine?.stop(); engine = nil; plan = nil; origin = 0
        if ownership { AudioSessionCoordinator.shared.release(.playback); ownership = false }
    }
}
