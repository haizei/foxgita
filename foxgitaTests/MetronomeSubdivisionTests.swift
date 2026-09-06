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
            #expect(!subdivision.clickOffsets.isEmpty)
            #expect(subdivision.clickOffsets.allSatisfy { (0..<1).contains($0) })
        }
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
