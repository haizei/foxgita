//
//  MetronomeDisplayCardTests.swift
//  foxgitaTests
//

import SwiftUI
import Testing
@testable import foxgita

struct MetronomeDisplayCardTests {
    @Test func fillColorMapsEachAccentStateWhenInactive() {
        #expect(MetronomeDisplayCard.fillColor(for: .strong, isActive: false) == GitaTheme.accentStrong)
        #expect(MetronomeDisplayCard.fillColor(for: .medium, isActive: false) == GitaTheme.accentMedium)
        #expect(MetronomeDisplayCard.fillColor(for: .weak, isActive: false) == GitaTheme.accentWeak)
        #expect(MetronomeDisplayCard.fillColor(for: .mute, isActive: false) == GitaTheme.accentMute)
    }

    @Test func fillColorUsesContrastTokenWhenActiveRegardlessOfState() {
        for kind in MetronomeBeatKind.allCases {
            #expect(MetronomeDisplayCard.fillColor(for: kind, isActive: true) == GitaTheme.accentActive)
        }
    }

    @Test func fillColorFallsBackToAccentWeakWhenOutOfRange() {
        #expect(MetronomeDisplayCard.fillColor(for: nil, isActive: false) == GitaTheme.accentWeak)
    }

    @Test func beatBarBorderStaysNeutralWhileBeatIsActive() {
        #expect(MetronomeDisplayCard.borderColor(isActive: false) == GitaTheme.borderSubtle)
        #expect(MetronomeDisplayCard.borderColor(isActive: true) == GitaTheme.borderSubtle)
    }

    @Test func figmaLayoutConstantsMatchMetronomeOptimizationNode() {
        #expect(MetronomeDisplayCard.Layout.cardHeight == 243)
        #expect(MetronomeDisplayCard.Layout.horizontalPadding == 12)
        #expect(MetronomeDisplayCard.Layout.controlHeight == 68)
        #expect(MetronomeDisplayCard.Layout.barsHeight == 106)
        #expect(MetronomeDisplayCard.Layout.trackHeight == 35)
        #expect(MetronomeDisplayCard.Layout.fourBeatSpacing == 23.5)
        #expect(MetronomeDisplayCard.Layout.fourBeatSideInset == 11.75)
    }

    @Test func muteUsesOneNeutralSegmentWhileAccentStrengthKeepsItsSemanticCount() {
        #expect(MetronomeBeatKind.mute.filledBarsCount == 0)
        #expect(MetronomeDisplayCard.displayedSegmentCount(for: .mute) == 1)
        #expect(MetronomeDisplayCard.displayedSegmentCount(for: .weak) == 1)
        #expect(MetronomeDisplayCard.displayedSegmentCount(for: .medium) == 2)
        #expect(MetronomeDisplayCard.displayedSegmentCount(for: .strong) == 3)
    }

    @Test func adjacentFilledSegmentsDoNotHaveInternalGaps() {
        #expect(MetronomeDisplayCard.showsDivider(at: 1, displayedSegmentCount: 1))
        #expect(MetronomeDisplayCard.showsDivider(at: 2, displayedSegmentCount: 1))
        #expect(MetronomeDisplayCard.showsDivider(at: 1, displayedSegmentCount: 2))
        #expect(!MetronomeDisplayCard.showsDivider(at: 2, displayedSegmentCount: 2))
        #expect(!MetronomeDisplayCard.showsDivider(at: 1, displayedSegmentCount: 3))
        #expect(!MetronomeDisplayCard.showsDivider(at: 2, displayedSegmentCount: 3))
    }

    @Test func beatTrackPulsePolicyMatchesEachMode() {
        let weakMain = MetronomeVisualEvent(sequence: 1, beat: 1, kind: .weak, isSubdivision: false)
        let mediumMain = MetronomeVisualEvent(sequence: 2, beat: 1, kind: .medium, isSubdivision: false)
        let mutedMain = MetronomeVisualEvent(sequence: 3, beat: 1, kind: .mute, isSubdivision: false)
        let weakSubdivision = MetronomeVisualEvent(sequence: 4, beat: 1, kind: .weak, isSubdivision: true)
        let mutedSubdivision = MetronomeVisualEvent(sequence: 5, beat: 1, kind: .mute, isSubdivision: true)

        #expect(MetronomeDisplayCard.pulseShape(for: .allBeats, event: weakMain) == .full)
        #expect(MetronomeDisplayCard.pulseShape(for: .allBeats, event: mutedMain) == .full)
        #expect(MetronomeDisplayCard.pulseShape(for: .allBeats, event: weakSubdivision) == .none)
        #expect(MetronomeDisplayCard.pulseShape(for: .accents, event: weakMain) == .none)
        #expect(MetronomeDisplayCard.pulseShape(for: .accents, event: mediumMain) == .full)
        #expect(MetronomeDisplayCard.pulseShape(for: .pendulum, event: weakMain) == .pendulum)
        #expect(MetronomeDisplayCard.pulseShape(for: .pendulum, event: weakSubdivision) == .none)
        #expect(MetronomeDisplayCard.pulseShape(for: .accentsAndSubdivisions, event: weakMain) == .full)
        #expect(MetronomeDisplayCard.pulseShape(for: .accentsAndSubdivisions, event: weakSubdivision) == .subdivision)
        #expect(MetronomeDisplayCard.pulseShape(for: .accentsAndSubdivisions, event: mutedSubdivision) == .none)
    }
}
