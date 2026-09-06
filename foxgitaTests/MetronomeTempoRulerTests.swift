//
//  MetronomeTempoRulerTests.swift
//  foxgitaTests
//

import Testing
@testable import foxgita

struct MetronomeTempoRulerTests {
    @Test func fractionAtRangeEdges() {
        #expect(MetronomeTempoRuler.fraction(for: 40) == 0)
        #expect(MetronomeTempoRuler.fraction(for: 160) == 1)
    }

    @Test func fractionAtMidpoint() {
        #expect(abs(MetronomeTempoRuler.fraction(for: 80) - 1 / 3) < 0.001)
    }

    @Test func fractionClampsAboveRulerMax() {
        #expect(MetronomeTempoRuler.fraction(for: 200) == 1)
    }

    @Test func fractionClampsBelowRulerMin() {
        #expect(MetronomeTempoRuler.fraction(for: 20) == 0)
    }

    @Test func bpmFromFractionRoundTrip() {
        #expect(MetronomeTempoRuler.bpm(forFraction: 0) == 40)
        #expect(MetronomeTempoRuler.bpm(forFraction: 1) == 160)
        #expect(MetronomeTempoRuler.bpm(forFraction: 0.5) == 100)
    }

    @Test func bpmFromFractionClampsOutOfRangeInput() {
        #expect(MetronomeTempoRuler.bpm(forFraction: -0.5) == 40)
        #expect(MetronomeTempoRuler.bpm(forFraction: 1.5) == 160)
    }

    @Test func thumbFractionMatchesVisualClamp() {
        #expect(MetronomeTempoRuler.thumbFraction(for: 180) == 1)
        #expect(MetronomeTempoRuler.thumbFraction(for: 80) == MetronomeTempoRuler.fraction(for: 80))
    }
}
