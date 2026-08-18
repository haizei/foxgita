import Foundation

enum AlbumDurationVerdict: Equatable {
    case ok, tooShort, tooLong, unknown
}

enum AlbumDurationGate {
    static let minSec = 30
    static let maxSec = 600

    static func verdict(durationSec: Int) -> AlbumDurationVerdict {
        if durationSec <= 0 { return .unknown }
        if durationSec < minSec { return .tooShort }
        if durationSec > maxSec { return .tooLong }
        return .ok
    }
}
