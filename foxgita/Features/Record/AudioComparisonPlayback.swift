import Foundation

struct AudioComparisonPlayback: Equatable {
    enum Side: String, Equatable {
        case a
        case b

        var other: Side { self == .a ? .b : .a }
    }

    var playing: Side?
    var positionA: TimeInterval = 0
    var positionB: TimeInterval = 0

    static func mappedPosition(
        sourcePosition: TimeInterval,
        sourceDuration: TimeInterval,
        targetDuration: TimeInterval
    ) -> TimeInterval {
        guard sourceDuration > 0, targetDuration > 0 else { return 0 }
        if sourcePosition <= targetDuration {
            return max(0, sourcePosition)
        }
        return sourcePosition / sourceDuration * targetDuration
    }

    mutating func play(_ side: Side) {
        playing = side
    }

    mutating func pause() {
        playing = nil
    }

    mutating func alternate(durationA: TimeInterval, durationB: TimeInterval) {
        switch playing {
        case .a:
            positionB = Self.mappedPosition(
                sourcePosition: positionA,
                sourceDuration: durationA,
                targetDuration: durationB
            )
            playing = .b
        case .b:
            positionA = Self.mappedPosition(
                sourcePosition: positionB,
                sourceDuration: durationB,
                targetDuration: durationA
            )
            playing = .a
        case nil:
            playing = .a
        }
    }

    mutating func seekAndPlay(_ side: Side, seconds: TimeInterval, duration: TimeInterval) {
        let upper = duration > 0 ? duration : max(0, seconds)
        let clamped = min(max(0, seconds), upper)
        switch side {
        case .a: positionA = clamped
        case .b: positionB = clamped
        }
        playing = side
    }

    func position(for side: Side) -> TimeInterval {
        side == .a ? positionA : positionB
    }
}

enum WaveformProgress {
    static let evidenceBarCount = 22
    static let comparisonBarCount = 32

    static func highlightCount(progress: Double, barCount: Int) -> Int {
        guard barCount > 0 else { return 0 }
        let clamped = min(1, max(0, progress))
        if clamped >= 0.999 { return barCount }
        return Int(clamped * Double(barCount))
    }
}
