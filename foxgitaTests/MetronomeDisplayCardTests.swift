//
//  MetronomeDisplayCardTests.swift
//  foxgitaTests
//

import SwiftUI
import Testing
@testable import foxgita

struct MetronomeDisplayCardTests {
    @Test func fillColorMapsEachAccentStateWhenInactive() {
        #expect(MetronomeDisplayCard.fillColor(for: .strong, isActive: false) == GitaTheme.brand500)
        #expect(MetronomeDisplayCard.fillColor(for: .medium, isActive: false) == GitaTheme.accentMedium)
        #expect(MetronomeDisplayCard.fillColor(for: .weak, isActive: false) == GitaTheme.accentWeak)
        #expect(MetronomeDisplayCard.fillColor(for: .mute, isActive: false) == Color.clear)
    }

    @Test func fillColorIsAlwaysBrandWhenActiveRegardlessOfState() {
        for kind in MetronomeBeatKind.allCases {
            #expect(MetronomeDisplayCard.fillColor(for: kind, isActive: true) == GitaTheme.brand500)
        }
    }

    @Test func fillColorFallsBackToAccentWeakWhenOutOfRange() {
        #expect(MetronomeDisplayCard.fillColor(for: nil, isActive: false) == GitaTheme.accentWeak)
    }
}
