//
//  MetronomeSheetAnchor.swift
//  foxgita
//

import Foundation

enum MetronomeSheetAnchor: String, Identifiable, CaseIterable {
    case speed
    case meter
    case subdivision

    var id: String { rawValue }

    var scrollSectionID: String {
        switch self {
        case .speed: return "bpmSection"
        case .meter: return "meterSection"
        case .subdivision: return "subdivisionSection"
        }
    }
}
