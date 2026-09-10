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

    @Test func beatKindCycleOrder() {
        var beat = MetronomeBeatKind.strong
        beat.cycle()
        #expect(beat == .medium)
        beat.cycle()
        #expect(beat == .weak)
        beat.cycle()
        #expect(beat == .mute)
        beat.cycle()
        #expect(beat == .strong)
    }

    @Test func beatKindHeightRatios() {
        #expect(MetronomeBeatKind.mute.heightRatio == 0.06)
        #expect(abs(MetronomeBeatKind.weak.heightRatio - 1.0 / 3.0) < 0.001)
        #expect(abs(MetronomeBeatKind.medium.heightRatio - 2.0 / 3.0) < 0.001)
        #expect(MetronomeBeatKind.strong.heightRatio == 1.0)
    }

    @Test func accentRoundTripFourState() {
        let pattern: [MetronomeBeatKind] = [.strong, .medium, .weak, .mute]
        let encoded = MetronomeMeter.encodeAccent(pattern)
        #expect(encoded == "3210")
        #expect(MetronomeMeter.decodeAccent(encoded, beats: 4) == pattern)
    }

    @Test func legacyAccentMigration() {
        // Legacy "2111" should migrate "2" (old strong) to .strong ("3")
        let pattern = MetronomeMeter.decodeAccent("2111", beats: 4)
        #expect(pattern == [.strong, .weak, .weak, .weak])
    }

    @Test func accentPadsAndTrimsToBeatCount() {
        #expect(MetronomeMeter.decodeAccent("3", beats: 3) == [.strong, .weak, .weak])
        #expect(MetronomeMeter.decodeAccent("3210", beats: 2) == [.strong, .medium])
    }
}
