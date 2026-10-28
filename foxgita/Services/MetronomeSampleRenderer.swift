import AVFoundation
import os

/// A bounded output adapter: the existing scheduler supplies frames, and the
/// audio callback selects a preloaded sample only when that frame is rendered.
nonisolated final class MetronomeSampleRenderer: @unchecked Sendable {
    private struct Click {
        var frame: Int64 = 0
        var role: MetronomePulseRole = .main
        var kind: MetronomeBeatKind = .mute
    }

    private struct State {
        var samples: [[Float]] = []
        var queue = Array(repeating: Click(), count: 256)
        var read = 0
        var write = 0
        var playing = false
        var preset = 0
        var volume: Float = 0.8
        var boosted = true
        var muted = false
        var cutoff: Int64?
        var activeSample = -1
        var activeStart: Int64 = 0
        var activeGain: Float = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let sampleRate: Double
    private let origin: UInt64

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        origin = mach_absolute_time()
    }

    func frame(forHostTime host: UInt64) -> Int64 {
        guard host >= origin else { return 0 }
        return Int64(AVAudioTime.seconds(forHostTime: host - origin) * sampleRate)
    }

    func hostTime(forFrame frame: Int64) -> UInt64 {
        origin + AVAudioTime.hostTime(forSeconds: Double(max(0, frame)) / sampleRate)
    }

    func installSamples(_ samples: [[Float]]) {
        state.withLock { $0.samples = samples }
    }

    func configure(preset: Int, volume: Float, strongBeatBoost: Bool, muted: Bool) {
        state.withLock {
            $0.preset = max(0, preset)
            $0.volume = min(1, max(0, volume))
            $0.boosted = strongBeatBoost
            $0.muted = muted
        }
    }

    func start() {
        state.withLock {
            $0.read = 0; $0.write = 0; $0.activeSample = -1
            $0.cutoff = nil; $0.playing = true
        }
    }

    func stop() {
        state.withLock { $0.playing = false; $0.read = 0; $0.write = 0; $0.activeSample = -1 }
    }

    func setCutoff(_ frame: Int64?) { state.withLock { $0.cutoff = frame } }

    func schedule(frame: Int64, role: MetronomePulseRole, kind: MetronomeBeatKind) -> Bool {
        state.withLock {
            guard $0.write - $0.read < $0.queue.count else { return false }
            $0.queue[$0.write % $0.queue.count] = Click(frame: frame, role: role, kind: kind)
            $0.write += 1
            return true
        }
    }

    func render(into output: UnsafeMutablePointer<Float>, startingAt start: Int64, count: Int) {
        // The lock covers a bounded audio block. No file access, allocation,
        // queue growth, logging, or main-actor calls occur inside this block.
        state.withLock { state in
            for index in 0..<count {
                let frame = start + Int64(index)
                guard state.playing, state.cutoff.map({ frame < $0 }) ?? true else {
                    output[index] = 0
                    continue
                }
                while state.read < state.write, state.queue[state.read % 256].frame <= frame {
                    let click = state.queue[state.read % 256]
                    state.read += 1
                    let strong = click.role == .main && click.kind == .strong && state.boosted
                    state.activeSample = state.preset * 2 + (strong ? 1 : 0)
                    state.activeStart = click.frame
                    switch click.role {
                    case .main:
                        state.activeGain = click.kind == .weak ? 0.9 : click.kind == .medium ? 0.95 : click.kind == .mute ? 0 : 1
                    case .secondary: state.activeGain = 0.75
                    case .weak: state.activeGain = 0.6
                    case .rest: state.activeGain = 0
                    }
                }
                let offset = Int(frame - state.activeStart)
                if !state.muted, state.samples.indices.contains(state.activeSample),
                   state.samples[state.activeSample].indices.contains(offset) {
                    output[index] = state.samples[state.activeSample][offset] * state.activeGain * state.volume
                } else { output[index] = 0 }
            }
        }
    }
}
