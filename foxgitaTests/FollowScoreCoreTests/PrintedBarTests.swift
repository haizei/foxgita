import Foundation
import Testing
#if canImport(GitaScoreCore)
@testable import GitaScoreCore
#else
@testable import foxgita
#endif

struct PrintedBarTests {
    private func options(tuning: [Int] = [40, 45, 50, 55, 59, 64], capo: Int = 0) -> PrintedBarCompileOptions {
        .init(title: "可见六线谱", tempo: .init(bpm: 100), tuning: tuning, capo: capo)
    }

    @Test func pitchUsesPrintedStringAndConfirmedTuningCapoAndFret() throws {
        let symbols = (1...6).map { string in
            PrintedBarSymbol(kind: .fret, string: string, fret: string + 1, tick: 0, duration: 3840, voice: 1)
        }
        let bar = PrintedBar(barID: "page-1-system-1-bar-1", symbols: symbols, chord: "Am")
        let result = try PrintedBarCompiler.compile([bar], options: options(tuning: [38, 45, 50, 55, 59, 64], capo: 2))
        #expect(result.canPractice)
        #expect(result.draft.issues.isEmpty)
        #expect(result.draft.score.bars[0].events.count == 1)
        #expect(result.draft.score.bars[0].events[0].tones.map(\.midi) == [68, 64, 61, 57, 53, 47])
        #expect(result.draft.score.bars[0].events[0].tones.map(\.string) == [1, 2, 3, 4, 5, 6])
        #expect(result.draft.score.bars[0].events[0].chord == "Am")
        #expect(!result.draft.isConfirmed)
    }

    @Test func nullUnknownsRoundTripWithoutBeingOmittedOrReplacedByChordNotes() throws {
        let data = Data(#"{"barID":"bar-1","symbols":[{"kind":"fret","string":null,"fret":null,"toFret":null,"tick":null,"duration":null,"voice":null,"box":null}],"chord":"C","warnings":[]}"#.utf8)
        let bar = try PrintedBarDecoder.decode(data, expectedBarID: "bar-1")
        let encoded = try JSONEncoder().encode(bar)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let symbols = try #require(object["symbols"] as? [[String: Any]])
        for key in ["string", "fret", "toFret", "tick", "duration", "voice", "box"] {
            #expect(symbols[0][key] is NSNull)
        }
        let result = try PrintedBarCompiler.compile([bar], options: options())
        #expect(!result.canPractice)
        #expect(result.printedBars == [bar])
        #expect(result.draft.score.bars[0].events.isEmpty)
        #expect(!result.draft.issues.isEmpty)
        #expect(result.derivedTones.isEmpty)
    }

    @Test func knownFretsDerivePitchBeforeUnknownTimingWithoutPublishingEvents() throws {
        let bar = PrintedBar(barID: "untimed", symbols: [
            .init(kind: .fret, string: 6, fret: 3),
            .init(kind: .hammerOn, string: 3, fret: 0, toFret: 2),
            .init(kind: .muted, string: 1, fret: 7),
            .init(kind: .unknown, string: 2, fret: 5),
            .init(kind: .fret, string: 1)
        ], chord: "Am")
        let result = try PrintedBarCompiler.compile([bar], options: options(capo: 2))
        #expect(!result.canPractice)
        #expect(result.draft.score.bars[0].events.isEmpty)
        #expect(result.printedBars == [bar])
        #expect(result.derivedTones == [
            .init(barID: "untimed", symbolIndex: 0, string: 6, fret: 3, midi: 45, role: .fret),
            .init(barID: "untimed", symbolIndex: 1, string: 3, fret: 0, midi: 57, role: .hammerOnFrom),
            .init(barID: "untimed", symbolIndex: 1, string: 3, fret: 2, midi: 59, role: .hammerOnTo)
        ])
    }

    @Test func unsupportedMarksAreRetainedAndBlockExactTraining() throws {
        let symbols: [PrintedBarSymbol] = [
            .init(kind: .fret, string: 6, fret: 0, tick: 0, duration: 960, voice: 1),
            .init(kind: .muted, string: 3, tick: 960, duration: 960, voice: 1),
            .init(kind: .strum, tick: 1920, duration: 960, voice: 1),
            .init(kind: .hammerOn, string: 1, fret: 2, toFret: 4, tick: 2880, duration: 480, voice: 1),
            .init(kind: .unknown, tick: 3360, duration: 480, voice: 1)
        ]
        let bar = PrintedBar(barID: "bar-1", symbols: symbols)
        let result = try PrintedBarCompiler.compile([bar], options: options())
        #expect(result.printedBars[0].symbols == symbols)
        #expect(result.draft.issues.count == 4)
        #expect(!result.canPractice)
        #expect(result.draft.score.bars[0].events.count == 1)
    }

    @Test func wrongIdentityMissingKeysAndMIDIAreRejected() throws {
        let encoded = try JSONEncoder().encode(PrintedBar(barID: "bar-2", symbols: []))
        #expect(throws: PrintedBarError.wrongBarID) {
            try PrintedBarDecoder.decode(encoded, expectedBarID: "bar-1")
        }
        let malformed = [
            #"{"barID":"bar-1","symbols":[],"warnings":[]}"#,
            #"{"barID":"bar-1","symbols":[],"chord":null,"warnings":[],"midi":60}"#,
            #"{"barID":"bar-1","symbols":[{"kind":"fret","string":1,"fret":0,"toFret":null,"tick":0,"duration":960,"voice":1,"box":null,"midi":64}],"chord":null,"warnings":[]}"#,
            #"{"barID":"bar-1","symbols":[{"kind":"fret","string":true,"fret":0,"toFret":null,"tick":0,"duration":960,"voice":1,"box":null}],"chord":null,"warnings":[]}"#
        ]
        for json in malformed {
            #expect(throws: PrintedBarError.malformed) {
                try PrintedBarDecoder.decode(Data(json.utf8), expectedBarID: "bar-1")
            }
        }
    }

    @Test func multipleVoicesAndRestsRetainTheirOwnTiming() throws {
        let bar = PrintedBar(barID: "bar-1", symbols: [
            .init(kind: .fret, string: 1, fret: 3, tick: 0, duration: 480, voice: 1),
            .init(kind: .fret, string: 6, fret: 0, tick: 0, duration: 1920, voice: 2),
            .init(kind: .rest, tick: 480, duration: 480, voice: 1),
            .init(kind: .fret, string: 2, fret: 1, tick: 960, duration: 960, voice: 1),
            .init(kind: .rest, tick: 1920, duration: 1920, voice: 1),
            .init(kind: .rest, tick: 1920, duration: 1920, voice: 2)
        ])
        let result = try PrintedBarCompiler.compile([bar], options: options())
        let events = result.draft.score.bars[0].events
        #expect(result.canPractice)
        #expect(events.map(\.voice) == [1, 2, 1, 1, 1, 2])
        #expect(events.map(\.tick) == [0, 0, 480, 960, 1920, 1920])
        #expect(events.map(\.duration) == [480, 1920, 480, 960, 1920, 1920])
        #expect(events[2].isRest)
    }

    @Test func invalidKnownRangesBoxesAndOutOfBarTimingAreRejected() throws {
        let invalidSymbols: [PrintedBarSymbol] = [
            .init(kind: .fret, string: 0), .init(kind: .fret, string: 7),
            .init(kind: .fret, fret: -1), .init(kind: .hammerOn, toFret: 25),
            .init(kind: .unknown, tick: -1), .init(kind: .unknown, duration: 0),
            .init(kind: .unknown, voice: 9),
            .init(kind: .unknown, box: [0, 0, .nan, 0.1]),
            .init(kind: .unknown, box: [0, 0, .infinity, 0.1]),
            .init(kind: .unknown, box: [0.9, 0, 0.2, 0.1]),
            .init(kind: .unknown, box: [0, 0, 0, 0.1])
        ]
        for symbol in invalidSymbols {
            #expect(throws: PrintedBarError.invalidSymbol(0)) {
                try PrintedBarCompiler.compile([.init(barID: "bar-1", symbols: [symbol])], options: options())
            }
        }
        for symbol in [
            PrintedBarSymbol(kind: .fret, string: 1, fret: 0, tick: 3840, duration: 1, voice: 1),
            .init(kind: .fret, string: 1, fret: 0, tick: 3839, duration: 2, voice: 1),
            .init(kind: .unknown, duration: 3841)
        ] {
            #expect(throws: PrintedBarError.invalidTiming(0)) {
                try PrintedBarCompiler.compile([.init(barID: "bar-1", symbols: [symbol])], options: options())
            }
        }
    }

    @Test func warningsEmptyBarsAndConflictingStringsBlockExactTraining() throws {
        let bar = PrintedBar(barID: "bar-1", symbols: [
            .init(kind: .fret, string: 1, fret: 0, tick: 0, duration: 3840, voice: 1),
            .init(kind: .fret, string: 1, fret: 2, tick: 0, duration: 3840, voice: 1)
        ], warnings: ["请核对这一品位"])
        let result = try PrintedBarCompiler.compile([bar], options: options())
        #expect(!result.canPractice)
        #expect(result.printedBars == [bar])
        #expect(result.draft.issues.count == 2)
        #expect(result.draft.score.bars[0].events[0].tones.count == 1)
        #expect(try !PrintedBarCompiler.compile([.init(barID: "empty", symbols: [])], options: options()).canPractice)
    }

    @Test func overlappingSameStringAndRestNoteIntervalsBlockExactTraining() throws {
        let note = PrintedBarSymbol(kind: .fret, string: 1, fret: 0, tick: 0, duration: 960, voice: 1)
        let conflicts: [[PrintedBarSymbol]] = [
            [note, .init(kind: .fret, string: 1, fret: 2, tick: 480, duration: 960, voice: 1)],
            [note, .init(kind: .rest, tick: 480, duration: 960, voice: 1)],
            [.init(kind: .rest, tick: 0, duration: 960, voice: 1),
             .init(kind: .fret, string: 1, fret: 2, tick: 480, duration: 960, voice: 1)]
        ]
        for symbols in conflicts {
            for orderedSymbols in [symbols, Array(symbols.reversed())] {
                let bar = PrintedBar(barID: "overlap", symbols: orderedSymbols)
                let result = try PrintedBarCompiler.compile([bar], options: options())
                #expect(!result.canPractice)
                #expect(result.printedBars == [bar])
                #expect(result.draft.issues.filter { $0.field.hasSuffix(".timing") }.count == 1)
            }
        }
    }

    @Test func chordStringsIndependentVoicesAndAdjacentIntervalsRemainPlayable() throws {
        let bar = PrintedBar(barID: "valid-intervals", symbols: [
            .init(kind: .fret, string: 1, fret: 0, tick: 0, duration: 960, voice: 1),
            .init(kind: .fret, string: 2, fret: 1, tick: 0, duration: 960, voice: 1),
            .init(kind: .fret, string: 6, fret: 2, tick: 480, duration: 960, voice: 2),
            .init(kind: .rest, tick: 0, duration: 3840, voice: 3),
            .init(kind: .fret, string: 1, fret: 3, tick: 960, duration: 960, voice: 1),
            .init(kind: .rest, tick: 1920, duration: 1920, voice: 1),
            .init(kind: .rest, tick: 0, duration: 480, voice: 2),
            .init(kind: .rest, tick: 1440, duration: 2400, voice: 2)
        ])
        let result = try PrintedBarCompiler.compile([bar], options: options())
        #expect(result.canPractice)
        #expect(result.draft.issues.isEmpty)
        #expect(result.draft.score.bars[0].events[0].tones.count == 2)
        #expect(result.draft.score.bars[0].events.count == 7)
    }

    @Test func overlappingGuitarStringsConflictAcrossVoicesWhileRestsRemainVoiceLocal() throws {
        let symbols: [PrintedBarSymbol] = [
            .init(kind: .fret, string: 1, fret: 0, tick: 0, duration: 960, voice: 1),
            .init(kind: .fret, string: 1, fret: 2, tick: 480, duration: 960, voice: 2)
        ]
        for orderedSymbols in [symbols, Array(symbols.reversed())] {
            let bar = PrintedBar(barID: "cross-voice-string", symbols: orderedSymbols)
            let result = try PrintedBarCompiler.compile([bar], options: options())
            #expect(!result.canPractice)
            #expect(result.printedBars == [bar])
            #expect(result.draft.issues.filter { $0.field.hasSuffix(".timing") }.count == 1)
        }
        let independentRest = PrintedBar(barID: "voice-local-rest", symbols: [
            .init(kind: .fret, string: 1, fret: 0, tick: 0, duration: 3840, voice: 1),
            .init(kind: .rest, tick: 0, duration: 3840, voice: 2)
        ])
        let restResult = try PrintedBarCompiler.compile([independentRest], options: options())
        #expect(restResult.canPractice)
        #expect(restResult.draft.issues.isEmpty)
    }

    @Test func emptyBarsPartialBarsAndPerVoiceGapsBlockExactTraining() throws {
        let incomplete: [[PrintedBarSymbol]] = [
            [],
            [.init(kind: .fret, string: 1, fret: 0, tick: 0, duration: 960, voice: 1)],
            [.init(kind: .fret, string: 1, fret: 0, tick: 960, duration: 2880, voice: 1)],
            [.init(kind: .fret, string: 1, fret: 0, tick: 0, duration: 960, voice: 1),
             .init(kind: .fret, string: 2, fret: 1, tick: 1920, duration: 1920, voice: 1)],
            [.init(kind: .fret, string: 1, fret: 0, tick: 0, duration: 3840, voice: 1),
             .init(kind: .fret, string: 6, fret: 0, tick: 0, duration: 960, voice: 2)]
        ]
        for symbols in incomplete {
            let bar = PrintedBar(barID: "incomplete", symbols: symbols)
            let result = try PrintedBarCompiler.compile([bar], options: options())
            #expect(!result.canPractice)
            #expect(result.printedBars == [bar])
            #expect(result.draft.issues.contains { $0.field == "printed.symbols" || $0.field.hasSuffix(".coverage") })
        }
    }

    @Test func coverageUsesIntervalUnionAndAllRestBarsRequireMusicElsewhere() throws {
        let music = PrintedBar(barID: "music", symbols: [
            .init(kind: .fret, string: 1, fret: 0, tick: 0, duration: 2880, voice: 1),
            .init(kind: .fret, string: 2, fret: 1, tick: 960, duration: 2880, voice: 1)
        ])
        let rest = PrintedBar(barID: "rest", symbols: [.init(kind: .rest, tick: 0, duration: 3840, voice: 1)])
        let musicResult = try PrintedBarCompiler.compile([music], options: options())
        #expect(musicResult.canPractice)
        #expect(musicResult.draft.issues.isEmpty)
        let restResult = try PrintedBarCompiler.compile([rest], options: options())
        #expect(!restResult.canPractice)
        #expect(restResult.draft.issues.contains { $0.field == "printed.playback" })
        let combined = try PrintedBarCompiler.compile([rest, music], options: options())
        #expect(combined.canPractice)
        #expect(combined.draft.issues.isEmpty)
    }

    @Test func invalidConfirmedMetadataAndDuplicateIDsReject() {
        let bar = PrintedBar(barID: "bar-1", symbols: [])
        #expect(throws: PrintedBarError.invalidOptions) {
            try PrintedBarCompiler.compile([bar], options: options(tuning: [40]))
        }
        #expect(throws: PrintedBarError.invalidOptions) {
            try PrintedBarCompiler.compile([bar], options: options(capo: Int.max))
        }
        #expect(throws: PrintedBarError.invalidOptions) {
            try PrintedBarCompiler.compile([bar, bar], options: options())
        }
    }
}
