import Foundation

/// A literal transcription of visible TAB marks. Pitch is intentionally absent from this protocol.
nonisolated struct PrintedBar: Codable, Equatable, Sendable {
    var barID: String
    var symbols: [PrintedBarSymbol]
    var chord: String?
    var warnings: [String]

    enum CodingKeys: String, CodingKey { case barID, symbols, chord, warnings }

    init(barID: String, symbols: [PrintedBarSymbol], chord: String? = nil, warnings: [String] = []) {
        self.barID = barID
        self.symbols = symbols
        self.chord = chord
        self.warnings = warnings
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        barID = try values.decode(String.self, forKey: .barID)
        symbols = try values.decode([PrintedBarSymbol].self, forKey: .symbols)
        chord = try values.decode(String?.self, forKey: .chord)
        warnings = try values.decode([String].self, forKey: .warnings)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(barID, forKey: .barID)
        try values.encode(symbols, forKey: .symbols)
        try values.encode(chord, forKey: .chord)
        try values.encode(warnings, forKey: .warnings)
    }
}

nonisolated enum PrintedBarSymbolKind: String, Codable, Sendable {
    case fret, muted, strum, hammerOn, rest, unknown
}

nonisolated struct PrintedBarSymbol: Codable, Equatable, Sendable {
    var kind: PrintedBarSymbolKind
    /// Printed string number: 1 is the highest string, 6 the lowest.
    var string: Int?
    var fret: Int?
    var toFret: Int?
    var tick: Int?
    var duration: Int?
    var voice: Int?
    /// Normalized x, y, width, height in the supplied bar image, or null if unresolved.
    var box: [Double]?

    enum CodingKeys: String, CodingKey { case kind, string, fret, toFret, tick, duration, voice, box }

    init(kind: PrintedBarSymbolKind, string: Int? = nil, fret: Int? = nil, toFret: Int? = nil,
         tick: Int? = nil, duration: Int? = nil, voice: Int? = nil, box: [Double]? = nil) {
        self.kind = kind
        self.string = string
        self.fret = fret
        self.toFret = toFret
        self.tick = tick
        self.duration = duration
        self.voice = voice
        self.box = box
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(PrintedBarSymbolKind.self, forKey: .kind)
        string = try values.decode(Int?.self, forKey: .string)
        fret = try values.decode(Int?.self, forKey: .fret)
        toFret = try values.decode(Int?.self, forKey: .toFret)
        tick = try values.decode(Int?.self, forKey: .tick)
        duration = try values.decode(Int?.self, forKey: .duration)
        voice = try values.decode(Int?.self, forKey: .voice)
        box = try values.decode([Double]?.self, forKey: .box)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        try values.encode(string, forKey: .string)
        try values.encode(fret, forKey: .fret)
        try values.encode(toFret, forKey: .toFret)
        try values.encode(tick, forKey: .tick)
        try values.encode(duration, forKey: .duration)
        try values.encode(voice, forKey: .voice)
        try values.encode(box, forKey: .box)
    }
}

nonisolated enum PrintedBarError: Error, Equatable, LocalizedError {
    case malformed, wrongBarID, invalidSymbol(Int), invalidOptions, invalidTiming(Int)

    var errorDescription: String? {
        switch self {
        case .malformed: "小节转录不是完整有效的可见符号数据。"
        case .wrongBarID: "小节转录标识与请求不一致。"
        case .invalidSymbol(let index): "第\(index + 1)个可见符号的数据范围无效。"
        case .invalidOptions: "请先确认曲名、速度、拍号、调弦和变调夹位置。"
        case .invalidTiming(let index): "第\(index + 1)个可见符号的时值超出当前小节。"
        }
    }
}

nonisolated enum PrintedBarDecoder {
    static func decode(_ data: Data, expectedBarID: String) throws -> PrintedBar {
        guard data.count <= 1_000_000 else { throw PrintedBarError.malformed }
        let bar: PrintedBar
        do {
            // Reject invented fields such as MIDI instead of quietly accepting a different protocol.
            guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(raw.keys) == Set(["barID", "symbols", "chord", "warnings"]),
                  let symbols = raw["symbols"] as? [[String: Any]],
                  symbols.allSatisfy({ Set($0.keys) == Set(["kind", "string", "fret", "toFret", "tick", "duration", "voice", "box"]) }) else {
                throw PrintedBarError.malformed
            }
            bar = try JSONDecoder().decode(PrintedBar.self, from: data)
        } catch { throw PrintedBarError.malformed }
        guard bar.barID == expectedBarID else { throw PrintedBarError.wrongBarID }
        try validate(bar)
        return bar
    }

    static func validate(_ bar: PrintedBar) throws {
        guard !bar.barID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              bar.barID.count <= 200, bar.symbols.count <= 1_536,
              bar.chord.map({ $0.count <= 200 }) ?? true,
              bar.warnings.count <= 100, bar.warnings.allSatisfy({ $0.count <= 500 }) else {
            throw PrintedBarError.malformed
        }
        for (index, symbol) in bar.symbols.enumerated() {
            guard symbol.string.map({ (1...6).contains($0) }) ?? true,
                  symbol.fret.map({ (0...24).contains($0) }) ?? true,
                  symbol.toFret.map({ (0...24).contains($0) }) ?? true,
                  symbol.tick.map({ (0...8_000_000).contains($0) }) ?? true,
                  symbol.duration.map({ (1...8_000_000).contains($0) }) ?? true,
                  symbol.voice.map({ (1...8).contains($0) }) ?? true else {
                throw PrintedBarError.invalidSymbol(index)
            }
            if let box = symbol.box {
                guard box.count == 4, box.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                      box[2] > 0, box[3] > 0, box[0] + box[2] <= 1.001, box[1] + box[3] <= 1.001 else {
                    throw PrintedBarError.invalidSymbol(index)
                }
            }
        }
    }
}

/// Values supplied and confirmed outside the visual transcription call.
nonisolated struct PrintedBarCompileOptions: Sendable {
    var title: String
    var ticksPerQuarter: Int = 960
    var tempo: ScoreTempo
    var tuning: [Int]
    var capo: Int
    var numerator: Int = 4
    var denominator: Int = 4
    var page: Int = 1
    var firstBarNumber: Int = 1
}

nonisolated struct PrintedBarCompilation: Sendable {
    var draft: RecognizedScoreDraft
    /// Keep every original symbol, including marks that have no playback representation.
    var printedBars: [PrintedBar]
    /// Deterministic sounding pitches from confirmed literal string/fret values, independent of rhythm.
    var derivedTones: [PrintedBarDerivedTone]
    /// False whenever literal transcription contains unresolved or unsupported music.
    var canPractice: Bool
}

nonisolated enum PrintedBarDerivedToneRole: String, Codable, Sendable {
    case fret, hammerOnFrom, hammerOnTo
}

nonisolated struct PrintedBarDerivedTone: Codable, Equatable, Sendable {
    var barID: String
    /// Zero-based index in the original, unfiltered symbols array.
    var symbolIndex: Int
    var string: Int
    var fret: Int
    var midi: Int
    var role: PrintedBarDerivedToneRole
}

nonisolated enum PrintedBarCompiler {
    private struct EventKey: Hashable {
        var tick: Int
        var duration: Int
        var voice: Int
    }

    static func compile(_ bars: [PrintedBar], options: PrintedBarCompileOptions) throws -> PrintedBarCompilation {
        guard !options.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              options.title.count <= 200, (24...61_440).contains(options.ticksPerQuarter),
              options.tempo.isValid, options.tuning.count == 6,
              options.tuning.allSatisfy({ (24...88).contains($0) }), (0...12).contains(options.capo),
              (1...32).contains(options.numerator), [2, 4, 8, 16].contains(options.denominator),
              options.ticksPerQuarter * 4 * options.numerator % options.denominator == 0,
              (1...20).contains(options.page), (1...1_000_000).contains(options.firstBarNumber),
              !bars.isEmpty, bars.count <= 2_000, Set(bars.map(\.barID)).count == bars.count else {
            throw PrintedBarError.invalidOptions
        }
        let length = options.ticksPerQuarter * 4 * options.numerator / options.denominator
        var issues: [ScoreRecognitionIssue] = []
        var scoreBars: [ScoreBar] = []
        var derivedTones: [PrintedBarDerivedTone] = []
        for (barIndex, bar) in bars.enumerated() {
            try PrintedBarDecoder.validate(bar)
            let number = options.firstBarNumber + barIndex
            func issue(_ field: String, _ message: String, _ box: [Double]? = nil) {
                issues.append(.init(field: field, message: message, bar: number, page: options.page, box: box))
            }
            for warning in bar.warnings { issue("printed.warning", warning) }
            if bar.symbols.isEmpty { issue("printed.symbols", "本小节未转录任何可见音符或休止符，请对照原谱核对。") }
            var events: [ScoreEvent] = []
            var eventIndices: [EventKey: Int] = [:]
            for (symbolIndex, symbol) in bar.symbols.enumerated() {
                let field = "printed.symbols[\(symbolIndex)]"
                // Validate known timing even when the other timing field remains unknown.
                if let tick = symbol.tick, tick >= length { throw PrintedBarError.invalidTiming(symbolIndex) }
                if let duration = symbol.duration, duration > length { throw PrintedBarError.invalidTiming(symbolIndex) }
                if let tick = symbol.tick, let duration = symbol.duration, duration > length - tick {
                    throw PrintedBarError.invalidTiming(symbolIndex)
                }
                func derive(_ fret: Int?, role: PrintedBarDerivedToneRole) throws {
                    guard let string = symbol.string, let fret else { return }
                    let midi = options.tuning[6 - string] + options.capo + fret
                    guard (24...108).contains(midi) else { throw PrintedBarError.invalidSymbol(symbolIndex) }
                    derivedTones.append(.init(barID: bar.barID, symbolIndex: symbolIndex, string: string,
                                              fret: fret, midi: midi, role: role))
                }
                switch symbol.kind {
                case .fret:
                    try derive(symbol.fret, role: .fret)
                case .hammerOn:
                    try derive(symbol.fret, role: .hammerOnFrom)
                    try derive(symbol.toFret, role: .hammerOnTo)
                case .muted, .strum, .rest, .unknown:
                    break
                }
                guard let tick = symbol.tick, let duration = symbol.duration, let voice = symbol.voice else {
                    issue(field + ".timing", "可见符号的节奏或声部尚未确定，请对照原谱校正。", symbol.box)
                    continue
                }
                let tones: [ScoreTone]
                switch symbol.kind {
                case .fret:
                    guard let string = symbol.string, let fret = symbol.fret, symbol.toFret == nil else {
                        issue(field + ".fret", "可见弦品尚未确定或包含未支持的连奏标记。", symbol.box)
                        continue
                    }
                    let midi = options.tuning[6 - string] + options.capo + fret
                    guard (24...108).contains(midi) else { throw PrintedBarError.invalidSymbol(symbolIndex) }
                    tones = [.init(midi: midi, string: string, fret: fret)]
                case .rest:
                    guard symbol.string == nil, symbol.fret == nil, symbol.toFret == nil else {
                        issue(field + ".rest", "休止符同时包含弦品数据，请对照原谱校正。", symbol.box)
                        continue
                    }
                    tones = []
                case .muted, .strum, .hammerOn, .unknown:
                    issue(field + ".kind", "本小节保留了\(symbol.kind.rawValue)可见标记，当前精确训练尚不能表示此符号。", symbol.box)
                    continue
                }
                let hasTemporalConflict = events.contains { existing in
                    guard existing.tick < tick + duration,
                          tick < existing.tick + existing.duration else { return false }
                    // Rests silence only their voice; one physical string cannot ring twice across voices.
                    if tones.isEmpty || existing.isRest { return existing.voice == voice }
                    return existing.tones.contains { previousTone in
                        tones.contains { $0.string == previousTone.string }
                    }
                }
                guard !hasTemporalConflict else {
                    issue(field + ".timing", "同弦音符或同一声部的休止符时值相互重叠，请对照原谱校正。", symbol.box)
                    continue
                }
                let key = EventKey(tick: tick, duration: duration, voice: voice)
                if let eventIndex = eventIndices[key] {
                    let existing = events[eventIndex]
                    guard !tones.isEmpty, !existing.tones.isEmpty,
                          !existing.tones.contains(where: { $0.string == tones[0].string }), existing.tones.count < 6 else {
                        issue(field + ".voice", "同一声部的弦品或休止符相互冲突，请对照原谱校正。", symbol.box)
                        continue
                    }
                    events[eventIndex].tones += tones
                } else {
                    eventIndices[key] = events.count
                    events.append(.init(tick: tick, duration: duration, tones: tones, chord: bar.chord,
                                        voice: voice, source: .init(page: options.page)))
                }
            }
            for voice in Set(bar.symbols.compactMap(\.voice)).sorted() {
                let intervals = bar.symbols.compactMap { symbol -> Range<Int>? in
                    guard symbol.voice == voice, let tick = symbol.tick, let duration = symbol.duration else { return nil }
                    return tick..<(tick + duration)
                }.sorted { $0.lowerBound < $1.lowerBound }
                var coveredUntil = 0
                var hasGap = false
                for interval in intervals {
                    if interval.lowerBound > coveredUntil { hasGap = true }
                    coveredUntil = max(coveredUntil, interval.upperBound)
                }
                if hasGap || coveredUntil < length {
                    issue("printed.voices[\(voice)].coverage", "第\(voice)声部未覆盖完整小节，请核对缺失的音符、时值或明确休止符。")
                }
            }
            events.sort {
                if $0.tick != $1.tick { return $0.tick < $1.tick }
                if $0.voice != $1.voice { return $0.voice < $1.voice }
                return $0.duration < $1.duration
            }
            guard events.count <= 256 else { throw PrintedBarError.malformed }
            scoreBars.append(.init(number: number, numerator: options.numerator, denominator: options.denominator,
                                   events: events, source: .init(page: options.page)))
        }
        let score = ScoreDocument(title: options.title, composer: "导入曲谱", ticksPerQuarter: options.ticksPerQuarter,
                                  tempo: options.tempo, tuning: options.tuning, capo: options.capo, bars: scoreBars)
        try score.validate()
        if score.soundingEvents.isEmpty {
            issues.append(.init(field: "printed.playback", message: "当前曲谱没有可训练的发声音符，请对照原谱补全后再开始。"))
        }
        return .init(draft: .init(score: score, issues: issues), printedBars: bars,
                     derivedTones: derivedTones, canPractice: issues.isEmpty)
    }
}
