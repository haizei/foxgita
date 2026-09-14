//
//  MetronomeSubdivision.swift
//  foxgita
//

import Foundation

enum MetronomePulseRole: Equatable {
    case main
    case secondary
    case weak
    case rest

    var relativeGain: Double {
        switch self {
        case .main: return 1.0
        case .secondary: return 0.85
        case .weak: return 0.65
        case .rest: return 0
        }
    }
}

struct MetronomeSubdivisionStep: Equatable {
    let offset: Double
    let role: MetronomePulseRole
}

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

    /// Timed positions within one beat. Rest positions remain in the sequence so
    /// beat boundaries never depend on the first audible click.
    var steps: [MetronomeSubdivisionStep] {
        switch self {
        case .quarter:
            [MetronomeSubdivisionStep(offset: 0, role: .main)]
        case .twoEighths:
            [
                MetronomeSubdivisionStep(offset: 0, role: .main),
                MetronomeSubdivisionStep(offset: 0.5, role: .weak),
            ]
        case .eighthRestEighth:
            [
                MetronomeSubdivisionStep(offset: 0, role: .rest),
                MetronomeSubdivisionStep(offset: 0.5, role: .weak),
            ]
        case .triplet:
            [
                MetronomeSubdivisionStep(offset: 0, role: .main),
                MetronomeSubdivisionStep(offset: 1.0 / 3.0, role: .weak),
                MetronomeSubdivisionStep(offset: 2.0 / 3.0, role: .weak),
            ]
        case .tripletRestFirst:
            [
                MetronomeSubdivisionStep(offset: 0, role: .rest),
                MetronomeSubdivisionStep(offset: 1.0 / 3.0, role: .weak),
                MetronomeSubdivisionStep(offset: 2.0 / 3.0, role: .weak),
            ]
        case .tripletRestLast, .twoEighthRest:
            [
                MetronomeSubdivisionStep(offset: 0, role: .main),
                MetronomeSubdivisionStep(offset: 1.0 / 3.0, role: .weak),
                MetronomeSubdivisionStep(offset: 2.0 / 3.0, role: .rest),
            ]
        case .fourSixteenths:
            [
                MetronomeSubdivisionStep(offset: 0, role: .main),
                MetronomeSubdivisionStep(offset: 0.25, role: .weak),
                MetronomeSubdivisionStep(offset: 0.5, role: .secondary),
                MetronomeSubdivisionStep(offset: 0.75, role: .weak),
            ]
        }
    }

    var clickOffsets: [Double] {
        steps.filter { $0.role != .rest }.map(\.offset)
    }

    static func decode(_ raw: Int?) -> MetronomeSubdivision {
        guard let raw, let value = MetronomeSubdivision(rawValue: raw) else { return .quarter }
        return value
    }
}
