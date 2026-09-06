//
//  MetronomeMeter.swift
//  foxgita
//

import Foundation

enum MetronomeBeatKind: Int, CaseIterable, Equatable {
    case mute = 0
    case normal = 1
    case accent = 2

    mutating func cycle() {
        switch self {
        case .accent: self = .normal
        case .normal: self = .mute
        case .mute: self = .accent
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
        return (0..<beats).map { $0 == 0 ? .accent : .normal }
    }

    static func encodeAccent(_ pattern: [MetronomeBeatKind]) -> String {
        pattern.map { String($0.rawValue) }.joined()
    }

    static func decodeAccent(_ raw: String?, beats: Int) -> [MetronomeBeatKind] {
        guard beats > 0 else { return [] }
        guard let raw, !raw.isEmpty else {
            return defaultAccentPattern(beats: beats)
        }
        var pattern = raw.compactMap { char -> MetronomeBeatKind? in
            guard let value = Int(String(char)) else { return nil }
            return MetronomeBeatKind(rawValue: value)
        }
        if pattern.count < beats {
            pattern.append(contentsOf: Array(repeating: MetronomeBeatKind.normal, count: beats - pattern.count))
        }
        if pattern.count > beats {
            pattern = Array(pattern.prefix(beats))
        }
        return pattern
    }
}
