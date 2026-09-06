//
//  MetronomeSoundMode.swift
//  foxgita
//

import Foundation

enum MetronomeSoundMode: String, CaseIterable, Identifiable, Equatable {
    case standard
    case acousticGuitar
    case drums

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: String(localized: "标准")
        case .acousticGuitar: String(localized: "木吉他")
        case .drums: String(localized: "打鼓")
        }
    }

    var subtitle: String {
        switch self {
        case .standard: String(localized: "清晰、均衡，适合安静练习")
        case .acousticGuitar: String(localized: "更亮的瞬态，穿透木吉他声")
        case .drums: String(localized: "短促鼓点，适合高噪声练习")
        }
    }

    static func decode(_ raw: String?) -> MetronomeSoundMode {
        guard let raw, let value = MetronomeSoundMode(rawValue: raw) else { return .standard }
        return value
    }
}
