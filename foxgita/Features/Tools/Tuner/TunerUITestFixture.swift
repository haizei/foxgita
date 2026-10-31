#if DEBUG
import Foundation

/// Opt-in simulator input, isolated from the production microphone pipeline.
/// Its PCM signal goes through the same pitch estimator as live input.
@MainActor
enum TunerUITestFixture {
    static func makeModel() -> TunerModel? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-UITesting"), let flag = args.firstIndex(of: "-TunerFixture"),
              flag + 1 < args.count else { return nil }
        let audio = FixtureAudio(mode: args[flag + 1])
        return TunerModel(audio: audio, session: AudioSessionCoordinator(apply: {}), now: { audio.clockTime })
    }

    private final class FixtureAudio: TunerAudioIO {
        var onObservation: ((TunerAudioObservation) -> Void)?
        var captureID = UUID()
        var onFailure: ((String) -> Void)?
        private let mode: String
        private var capture: Task<Void, Never>?
        private var tone: Task<Void, Never>?
        private var captureStartedAt = 0.0
        var clockTime: TimeInterval {
            let time = ProcessInfo.processInfo.systemUptime
            // Hold simulated time for UI automation to inspect a short-lived
            // state. Production still expires after 300 ms of monotonic time.
            if mode == "tail", (3..<5).contains(time - captureStartedAt) { return captureStartedAt + 3.01 }
            return time
        }
        init(mode: String) { self.mode = mode }
        func requestPermission() async -> Bool { mode != "denied" }
        func startCapture() throws {
            stopCapture()
            captureID = UUID()
            let hz = 82.4069 * (mode == "stable" ? 1 : pow(2, -8.0 / 1200))
            let samples = (0..<2400).map { Float(0.4 * sin(2 * Double.pi * hz * Double($0) / 12_000)) }
            let pitch = mode == "silence" ? nil : TunerPitchDetector.estimate(samples: samples, sampleRate: 12_000)
            captureStartedAt = ProcessInfo.processInfo.systemUptime
            capture = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(20))
                    guard !Task.isCancelled, let self else { return }
                    let time = ProcessInfo.processInfo.systemUptime
                    let elapsed = time - self.captureStartedAt
                    let current = elapsed < 0.12 || (self.mode == "tail" && elapsed > 3) ? nil : pitch
                    self.onObservation?(TunerAudioObservation(pitch: current, capturedAt: self.clockTime, sampleRate: 12_000, runID: self.captureID))
                }
            }
        }
        func stopCapture() { capture?.cancel(); capture = nil }
        func playReference(frequency: Double, completion: @escaping () -> Void) throws {
            stopReference()
            tone = Task {
                try? await Task.sleep(for: .seconds(1.8))
                guard !Task.isCancelled else { return }
                completion()
            }
        }
        func stopReference() { tone?.cancel(); tone = nil }
    }
}
#endif
