import Foundation

/// The end of the sampled window, not the time its analysis callback arrived.
nonisolated struct TunerAudioObservation: Sendable {
    let pitch: TunerPitchEstimate?
    let capturedAt: TimeInterval
    let sampleRate: Double
    let runID: UUID
}
