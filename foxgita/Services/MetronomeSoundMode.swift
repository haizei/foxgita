//
//  MetronomeSoundMode.swift
//  foxgita
//

import Foundation

enum MetronomeSoundMode: String, CaseIterable, Identifiable, Equatable {
    case standard
    case penetrating
    case highNoise

    @available(*, deprecated, renamed: "penetrating")
    static var acousticGuitar: Self { .penetrating }

    @available(*, deprecated, renamed: "highNoise")
    static var drums: Self { .highNoise }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: String(localized: "标准")
        case .penetrating: String(localized: "穿透")
        case .highNoise: String(localized: "高噪声")
        }
    }

    var subtitle: String {
        switch self {
        case .standard: String(localized: "清晰、均衡，适合安静练习")
        case .penetrating: String(localized: "更亮、更短促，适合吉他练习")
        case .highNoise: String(localized: "更强辨认度，适合合奏或嘈杂环境")
        }
    }

    var iconAssetName: String {
        switch self {
        case .standard: "MetronomeSoundModeStandard"
        case .penetrating: "MetronomeSoundModeAcousticGuitar"
        case .highNoise: "MetronomeSoundModeDrums"
        }
    }

    static func decode(_ raw: String?) -> MetronomeSoundMode {
        switch raw {
        case standard.rawValue: .standard
        case penetrating.rawValue, "acousticGuitar": .penetrating
        case highNoise.rawValue, "drums": .highNoise
        default: .standard
        }
    }
}
