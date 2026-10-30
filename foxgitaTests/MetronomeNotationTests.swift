import Testing
@testable import foxgita

struct MetronomeNotationTests {
    @Test func mutedAccentsRemainRestsAtEveryBeatUnit() {
        for unit in [2, 4, 8, 16] {
            let muted = MetronomeNotation(beatUnit: unit, kind: .mute)
            #expect(muted.rests == [true])
            #expect(muted.noteValue == unit)
            for kind in [MetronomeBeatKind.strong, .medium, .weak] {
                #expect(MetronomeNotation(beatUnit: unit, kind: kind).rests == [false])
            }
        }
    }

    @Test func noteValuesFollowTheBeatUnit() {
        for (unit, single, pair, four) in [(2, 2, 4, 8), (4, 4, 8, 16), (8, 8, 16, 32), (16, 16, 32, 64)] {
            #expect(MetronomeNotation(subdivision: .quarter, beatUnit: unit).noteValue == single)
            #expect(MetronomeNotation(subdivision: .twoEighths, beatUnit: unit).noteValue == pair)
            #expect(MetronomeNotation(subdivision: .fourSixteenths, beatUnit: unit).noteValue == four)
            #expect(MetronomeNotation(subdivision: .triplet, beatUnit: unit).noteValue == pair)
        }
    }

    @Test func flagsAndHollowHeadsMatchNoteDuration() {
        for (unit, flags, hollow) in [(2, 0, true), (4, 0, false), (8, 1, false), (16, 2, false)] {
            let notation = MetronomeNotation(subdivision: .quarter, beatUnit: unit)
            #expect(notation.beamCount == flags)
            #expect(notation.hasHollowHead == hollow)
        }
        #expect(MetronomeNotation(subdivision: .fourSixteenths, beatUnit: 16).beamCount == 4)
    }

    @Test func restsAndTupletsSurviveUnitChanges() {
        let frontRest = MetronomeNotation(subdivision: .tripletRestFirst, beatUnit: 8)
        #expect(frontRest.rests == [true, false, false])
        #expect(frontRest.isTriplet)
        #expect(frontRest.noteValue == 16)
        let backRest = MetronomeNotation(subdivision: .tripletRestLast, beatUnit: 2)
        #expect(backRest.rests == [false, false, true])
        #expect(backRest.noteValue == 4)
        #expect(!MetronomeNotation(subdivision: .twoEighthRest, beatUnit: 4).isTriplet)
    }
}
