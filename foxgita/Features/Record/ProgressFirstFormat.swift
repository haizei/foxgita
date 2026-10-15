import Foundation

enum ProgressFirstFormat {
    static func monthDay(_ dayKey: String) -> String {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else {
            return dayKey
        }
        return "\(month)月\(day)日"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func minutes(fromSeconds seconds: Int) -> Int {
        let clamped = max(0, seconds)
        return Int((Double(clamped) / 60.0).rounded(.toNearestOrAwayFromZero))
    }

    static func recordingLabel(durationSec: Int) -> String {
        "录音 \(clock(TimeInterval(durationSec)))"
    }
}
