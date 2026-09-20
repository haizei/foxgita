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
        #expect(MetronomeDisplayCard.Layout.secondaryPulseWidth == 72)
        #expect(MetronomeDisplayCard.Layout.weakPulseWidth == 40)
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

    @Test func accentAccessibilityDescribesStateAndLock() {
        #expect(
            MetronomeDisplayCard.accentAccessibilityLabel(
                index: 0,
                kind: .strong,
                isLocked: false
            ) == "第 1 拍，强拍"
        )
        #expect(
            MetronomeDisplayCard.accentAccessibilityLabel(
                index: 2,
                kind: .mute,
                isLocked: true
            ) == "第 3 拍，静音拍，已锁定"
        )
    }

    @Test func beatTrackPulsePolicyMatchesEachMode() {
        let weakMain = MetronomeVisualEvent(sequence: 1, beat: 1, kind: .weak, role: .main)
        let mediumMain = MetronomeVisualEvent(sequence: 2, beat: 1, kind: .medium, role: .main)
        let mutedMain = MetronomeVisualEvent(sequence: 3, beat: 1, kind: .mute, role: .main)
        let secondary = MetronomeVisualEvent(sequence: 4, beat: 1, kind: .weak, role: .secondary)
        let weakSubdivision = MetronomeVisualEvent(sequence: 5, beat: 1, kind: .weak, role: .weak)
        let mutedSubdivision = MetronomeVisualEvent(sequence: 6, beat: 1, kind: .mute, role: .weak)
        let rest = MetronomeVisualEvent(sequence: 7, beat: 1, kind: .weak, role: .rest)

        #expect(MetronomeDisplayCard.pulseShape(for: .allBeats, event: weakMain) == .full)
        #expect(MetronomeDisplayCard.pulseShape(for: .allBeats, event: mutedMain) == .full)
        #expect(MetronomeDisplayCard.pulseShape(for: .allBeats, event: weakSubdivision) == .none)
        #expect(MetronomeDisplayCard.pulseShape(for: .accents, event: weakMain) == .none)
        #expect(MetronomeDisplayCard.pulseShape(for: .accents, event: mediumMain) == .full)
        #expect(MetronomeDisplayCard.pulseShape(for: .pendulum, event: weakMain) == .pendulum)
        #expect(MetronomeDisplayCard.pulseShape(for: .pendulum, event: weakSubdivision) == .none)
        #expect(MetronomeDisplayCard.pulseShape(for: .accentsAndSubdivisions, event: weakMain) == .full)
        #expect(MetronomeDisplayCard.pulseShape(for: .accentsAndSubdivisions, event: secondary) == .secondarySubdivision)
        #expect(MetronomeDisplayCard.pulseShape(for: .accentsAndSubdivisions, event: weakSubdivision) == .weakSubdivision)
        #expect(MetronomeDisplayCard.pulseShape(for: .accentsAndSubdivisions, event: mutedSubdivision) == .none)
        #expect(MetronomeDisplayCard.pulseShape(for: .accentsAndSubdivisions, event: rest) == .none)
    }
}
