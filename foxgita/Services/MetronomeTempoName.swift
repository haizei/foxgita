//
//  MetronomeTempoName.swift
//  foxgita
//

import Foundation

enum MetronomeTempoName {
    static func name(for bpm: Int) -> String {
        let clamped = min(200, max(40, bpm))
        switch clamped {
        case 40...59: return "Largo"
        case 60...75: return "Adagio"
        case 76...87: return "Andantino"
        case 88...107: return "Moderato"
        case 108...119: return "Allegretto"
        case 120...139: return "Allegro"
        default: return "Presto"
        }
    }
}
