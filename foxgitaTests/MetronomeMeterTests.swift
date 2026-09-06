//
//  MetronomeMeterTests.swift
//  foxgitaTests
//

import Testing
@testable import foxgita

struct MetronomeMeterTests {
    @Test func parseDefaultsInvalidToFourFour() {
        #expect(MetronomeMeter.parseTimeSignature(nil).beats == 4)
        #expect(MetronomeMeter.parseTimeSignature("bad").beats == 4)
        #expect(MetronomeMeter.parseTimeSignature("3/4").beats == 3)
    }

    @Test func clampsBeatCount() {
        #expect(MetronomeMeter.parseTimeSignature("1/4").beats == 2)
        #expect(MetronomeMeter.parseTimeSignature("20/4").beats == 12)
    }

    @Test func accentRoundTrip() {
        let pattern: [MetronomeBeatKind] = [.accent, .normal, .mute, .normal]
        let encoded = MetronomeMeter.encodeAccent(pattern)
        #expect(encoded == "2101")
        #expect(MetronomeMeter.decodeAccent(encoded, beats: 4) == pattern)
    }

    @Test func accentPadsAndTrimsToBeatCount() {
        #expect(MetronomeMeter.decodeAccent("2", beats: 3) == [.accent, .normal, .normal])
        #expect(MetronomeMeter.decodeAccent("210101", beats: 3) == [.accent, .normal, .mute])
    }
}
