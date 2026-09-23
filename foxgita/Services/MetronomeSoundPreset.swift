//
//  MetronomeSoundPreset.swift
//  foxgita
//

import Foundation

/// The persisted sound choice and the stable prefix of its bundled PCM pair.
enum MetronomeSoundPreset: String, CaseIterable, Identifiable, Sendable {
    case realMetronome
    case electronicMetronome
    case windChime
    case woodblock
    case drumKit1
    case drumKit2
    case handClap

    var id: String { rawValue }

    var beatResourceName: String { "\(rawValue)-beat" }
    var strongResourceName: String { "\(rawValue)-strong" }

    var displayName: String {
        switch self {
        case .realMetronome: String(localized: "真实节拍器")
        case .electronicMetronome: String(localized: "电子节拍器")
        case .windChime: String(localized: "风铃声")
        case .woodblock: String(localized: "木鱼声")
        case .drumKit1: String(localized: "架子鼓1")
        case .drumKit2: String(localized: "架子鼓2")
        case .handClap: String(localized: "拍手")
        }
    }

    static func decode(_ raw: String?) -> Self {
        if let raw, let preset = Self(rawValue: raw) { return preset }
        return switch raw {
        case "penetrating", "acousticGuitar": .electronicMetronome
        case "highNoise", "drums": .handClap
        default: .realMetronome
        }
    }
}
