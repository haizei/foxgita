//
//  MetronomeSubdivision.swift
//  foxgita
//

import Foundation

/// Eight rhythm patterns aligned with `metronome-subdivision-sprite.png` / note-1…note-8 assets.
enum MetronomeSubdivision: Int, CaseIterable, Identifiable, Equatable {
    case quarter = 0
    case twoEighths = 1
    case eighthRestEighth = 2
    case triplet = 3
    case tripletRestFirst = 4
    case tripletRestLast = 5
    case twoEighthRest = 6
    case fourSixteenths = 7

    var id: Int { rawValue }

    var assetName: String { "MetronomeSubdivision\(rawValue)" }

    var accessibilityLabel: String {
        switch self {
        case .quarter: String(localized: "四分音符")
        case .twoEighths: String(localized: "两个八分音符")
        case .eighthRestEighth: String(localized: "八分休止加八分")
        case .triplet: String(localized: "三连音")
        case .tripletRestFirst: String(localized: "三连音前休")
        case .tripletRestLast: String(localized: "三连音后休")
        case .twoEighthRest: String(localized: "两八分加休止")
        case .fourSixteenths: String(localized: "四个十六分")
        }
    }

    /// Click positions within one beat interval, as fractions from 0 (inclusive) to 1 (exclusive).
    var clickOffsets: [Double] {
        switch self {
        case .quarter: [0]
        case .twoEighths: [0, 0.5]
        case .eighthRestEighth: [0.5]
        case .triplet: [0, 1.0 / 3.0, 2.0 / 3.0]
        case .tripletRestFirst: [1.0 / 3.0, 2.0 / 3.0]
        case .tripletRestLast: [0, 1.0 / 3.0]
        case .twoEighthRest: [0, 0.5]
        case .fourSixteenths: [0, 0.25, 0.5, 0.75]
        }
    }

    static func decode(_ raw: Int?) -> MetronomeSubdivision {
        guard let raw, let value = MetronomeSubdivision(rawValue: raw) else { return .quarter }
        return value
    }
}
