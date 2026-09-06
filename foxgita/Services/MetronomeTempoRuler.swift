//
//  MetronomeTempoRuler.swift
//  foxgita
//

import CoreGraphics
import Foundation

enum MetronomeTempoRuler {
    static let rangeMin = 40
    static let rangeMax = 160

    static func fraction(for bpm: Int) -> CGFloat {
        let clamped = min(rangeMax, max(rangeMin, bpm))
        return CGFloat(clamped - rangeMin) / CGFloat(rangeMax - rangeMin)
    }

    static func bpm(forFraction fraction: CGFloat) -> Int {
        let clamped = min(1, max(0, fraction))
        let value = CGFloat(rangeMin) + clamped * CGFloat(rangeMax - rangeMin)
        return Int(round(value))
    }

    static func thumbFraction(for bpm: Int) -> CGFloat {
        fraction(for: bpm)
    }
}
