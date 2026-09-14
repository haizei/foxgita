//
//  MetronomeSubdivisionTests.swift
//  foxgitaTests
//

import Testing
@testable import foxgita

struct MetronomeSubdivisionTests {
    @Test func allCasesHaveClickOffsets() {
        #expect(MetronomeSubdivision.allCases.count == 8)
        for subdivision in MetronomeSubdivision.allCases {
            #expect(!subdivision.steps.isEmpty)
            #expect(subdivision.steps.first?.offset == 0)
            #expect(subdivision.steps.allSatisfy { (0..<1).contains($0.offset) })
            #expect(!subdivision.clickOffsets.isEmpty)
            #expect(subdivision.clickOffsets.allSatisfy { (0..<1).contains($0) })
        }
    }

    @Test func rhythmPatternsUseNaturalPulseHierarchyAndExplicitRests() {
        #expect(MetronomeSubdivision.quarter.steps.map(\.role) == [.main])
        #expect(MetronomeSubdivision.twoEighths.steps.map(\.role) == [.main, .weak])
        #expect(MetronomeSubdivision.eighthRestEighth.steps.map(\.role) == [.rest, .weak])
        #expect(MetronomeSubdivision.triplet.steps.map(\.role) == [.main, .weak, .weak])
        #expect(MetronomeSubdivision.tripletRestFirst.steps.map(\.role) == [.rest, .weak, .weak])
        #expect(MetronomeSubdivision.tripletRestLast.steps.map(\.role) == [.main, .weak, .rest])
        #expect(MetronomeSubdivision.twoEighthRest.steps.map(\.role) == [.main, .weak, .rest])
        #expect(
            MetronomeSubdivision.fourSixteenths.steps.map(\.role)
                == [.main, .weak, .secondary, .weak]
        )
    }

    @Test func allRhythmPatternOffsetsMatchTheirNotation() {
        #expect(MetronomeSubdivision.quarter.steps.map(\.offset) == [0])
        #expect(MetronomeSubdivision.twoEighths.steps.map(\.offset) == [0, 0.5])
        #expect(MetronomeSubdivision.eighthRestEighth.steps.map(\.offset) == [0, 0.5])
        #expect(MetronomeSubdivision.triplet.steps.map(\.offset) == [0, 1.0 / 3.0, 2.0 / 3.0])
        #expect(
            MetronomeSubdivision.tripletRestFirst.steps.map(\.offset)
                == [0, 1.0 / 3.0, 2.0 / 3.0]
        )
        #expect(
            MetronomeSubdivision.tripletRestLast.steps.map(\.offset)
                == [0, 1.0 / 3.0, 2.0 / 3.0]
        )
        #expect(
            MetronomeSubdivision.twoEighthRest.steps.map(\.offset)
                == [0, 1.0 / 3.0, 2.0 / 3.0]
        )
        #expect(MetronomeSubdivision.fourSixteenths.steps.map(\.offset) == [0, 0.25, 0.5, 0.75])

        #expect(MetronomeSubdivision.eighthRestEighth.clickOffsets == [0.5])
        #expect(MetronomeSubdivision.tripletRestLast.clickOffsets == [0, 1.0 / 3.0])
        #expect(MetronomeSubdivision.twoEighthRest.clickOffsets == [0, 1.0 / 3.0])
    }

    @Test func pulseRolesHaveDescendingPerceptualGain() {
        #expect(MetronomePulseRole.main.relativeGain == 1)
        #expect(MetronomePulseRole.secondary.relativeGain == 0.85)
        #expect(MetronomePulseRole.weak.relativeGain == 0.65)
        #expect(MetronomePulseRole.rest.relativeGain == 0)
    }

    @Test func decodeFallsBackToQuarter() {
        #expect(MetronomeSubdivision.decode(nil) == .quarter)
        #expect(MetronomeSubdivision.decode(99) == .quarter)
        #expect(MetronomeSubdivision.decode(3) == .triplet)
    }

    @MainActor
    @Test func bumpSubdivisionStepsThroughCases() {
        let metronome = MetronomeEngine()
        #expect(metronome.subdivision == .quarter)
        metronome.bumpSubdivision(1)
        #expect(metronome.subdivision == .twoEighths)
        metronome.bumpSubdivision(-1)
        #expect(metronome.subdivision == .quarter)
        metronome.bumpSubdivision(-1)
        #expect(metronome.subdivision == .quarter)
    }
}
