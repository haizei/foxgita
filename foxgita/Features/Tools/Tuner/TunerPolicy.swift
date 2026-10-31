import Foundation

/// Engineering starting points; changes need PCM and device evidence.
nonisolated enum TunerPolicy {
    static let maximumObservationAge = 0.15
    static let allowedClockSkew = 0.01
    static let continuousGap = 0.1
    static let initialRecognitionDuration = 0.08
    static let stringSwitchDuration = 0.12
    static let stringSwitchAdvantage = 50.0
    static let automaticRange = 180.0
    static let referenceHopDuration = 1024.0 / 48_000
    static let readoutHoldDuration = 0.3
    static let confirmationDuration = 0.4
    static let confirmationEntryCents = 5.0
    static let confirmationExitCents = 8.0
    static let confirmationSpreadCents = 4.0
    static let referenceIsolationDuration = 0.2
}
