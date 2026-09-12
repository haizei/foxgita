//
//  MetronomeMeter.swift
//  foxgita
//

import Foundation

enum MetronomeBeatKind: Int, CaseIterable, Equatable {
    case mute = 0
    case weak = 1
    case medium = 2
    case strong = 3

    mutating func cycle() {
        switch self {
        case .strong: self = .medium
        case .medium: self = .weak
        case .weak:   self = .mute
        case .mute:   self = .strong
        }
    }

    var heightRatio: CGFloat {
        switch self {
        case .mute: return 0.06
        case .weak: return 1.0 / 3.0
        case .medium: return 2.0 / 3.0
        case .strong: return 1.0
        }
    }

    var filledBarsCount: Int {
        switch self {
        case .mute: return 0
        case .weak: return 1
        case .medium: return 2
        case .strong: return 3
        }
    }

    var assetName: String {
        switch self {
        case .strong: return "MetronomeAccentStrong"
        case .medium: return "MetronomeAccentMedium"
        case .weak:   return "MetronomeAccentWeak"
        case .mute:   return "MetronomeAccentMute"
        }
    }

    var displayName: String {
        switch self {
        case .mute: return String(localized: "静音")
        case .weak: return String(localized: "普通")
        case .medium: return String(localized: "次强")
        case .strong: return String(localized: "强")
        }
    }
}

enum MetronomeMeter {
    static let minBeats = 2
    static let maxBeats = 12
    static let defaultDenominator = 4

    static func parseTimeSignature(_ raw: String?) -> (beats: Int, denominator: Int) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return (4, defaultDenominator) }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let beats = Int(parts[0]),
              let denominator = Int(parts[1]),
              beats > 0, denominator > 0 else {
            return (4, defaultDenominator)
        }
        return (
            min(maxBeats, max(minBeats, beats)),
            denominator
        )
    }

    static func format(beats: Int, denominator: Int = defaultDenominator) -> String {
        "\(min(maxBeats, max(minBeats, beats)))/\(denominator)"
    }

    static func defaultAccentPattern(beats: Int) -> [MetronomeBeatKind] {
        guard beats > 0 else { return [] }
        return (0..<beats).map { $0 == 0 ? .strong : .weak }
    }

    static func encodeAccent(_ pattern: [MetronomeBeatKind]) -> String {
        pattern.map { String($0.rawValue) }.joined()
    }

    static func decodeAccent(_ raw: String?, beats: Int) -> [MetronomeBeatKind] {
        guard beats > 0 else { return [] }
        guard let raw, !raw.isEmpty else {
            return defaultAccentPattern(beats: beats)
        }

        // Backward compatibility migration:
        // In legacy versions, '2' was used for strong accent. If string has no '3' and contains '2',
        // promote legacy '2' to '3' (.strong).
        let isLegacyFormat = !raw.contains("3") && raw.contains("2")

        var pattern = raw.compactMap { char -> MetronomeBeatKind? in
            guard let value = Int(String(char)) else { return nil }
            if isLegacyFormat && value == 2 {
                return .strong
            }
            return MetronomeBeatKind(rawValue: value)
        }
        if pattern.count < beats {
            pattern.append(contentsOf: Array(repeating: MetronomeBeatKind.weak, count: beats - pattern.count))
        }
        if pattern.count > beats {
            pattern = Array(pattern.prefix(beats))
        }
        return pattern
    }
}
