import Foundation

nonisolated enum ScoreValidationError: Error, Equatable, LocalizedError {
    case invalidMetadata, invalidBar(Int), invalidEvent(Int), invalidFret(Int), invalidRange
    var errorDescription: String? {
        switch self {
        case .invalidMetadata: "请检查曲名、速度、调弦和曲谱内容。"
        case .invalidBar(let bar): "第\(bar)小节的拍号或速度无效。"
        case .invalidEvent(let bar): "第\(bar)小节的音符或时值需要校正。"
        case .invalidFret(let bar): "第\(bar)小节的音高与弦品不一致，请对照原谱校正。"
        case .invalidRange: "请选择当前曲谱中有效的小节范围。"
        }
    }
}

nonisolated struct ScoreTempo: Codable, Equatable, Sendable {
    var bpm: Double
    var beatUnit: Int = 4
    var quarterBPM: Double { bpm * 4 / Double(beatUnit) }
    var isValid: Bool { bpm.isFinite && (20...300).contains(bpm) && [2, 4, 8, 16].contains(beatUnit) }
}

nonisolated struct ScoreTone: Codable, Equatable, Sendable {
    var midi: Int
    var string: Int? = nil
    var fret: Int? = nil
    var finger: Int? = nil
    var tiedFromPrevious: Bool = false
}

nonisolated struct ScoreSourceLocation: Codable, Equatable, Sendable {
    var page: Int
    /// Normalized x,y,width,height on the original page, when confidently located.
    var box: [Double]? = nil
    var validBox: [Double]? {
        guard let box,box.count == 4,box.allSatisfy({ $0.isFinite && (0...1).contains($0) }),box[2] > 0,box[3] > 0,box[0]+box[2] <= 1.001,box[1]+box[3] <= 1.001 else { return nil }
        return box
    }
}

nonisolated struct ScoreEvent: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var tick: Int
    var duration: Int
    var tones: [ScoreTone]
    var chord: String? = nil
    var lyric: String? = nil
    var voice: Int = 1
    var source: ScoreSourceLocation? = nil
    var isRest: Bool { tones.isEmpty }
}

nonisolated enum ScoreBarContent: String, Codable, Sendable { case confirmed, sourceOnly }

nonisolated struct ScoreBar: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var number: Int
    var numerator: Int = 4
    var denominator: Int = 4
    var events: [ScoreEvent]
    var tempo: ScoreTempo? = nil
    var section: String? = nil
    var source: ScoreSourceLocation? = nil
    /// Missing content preserves the confirmed meaning of legacy bars.
    var content: ScoreBarContent? = nil
    var isSourceOnly: Bool { content == .sourceOnly }
}

nonisolated struct ScoreRange: Codable, Equatable, Sendable {
    /// Zero-based, inclusive indices within an immutable score version.
    var firstBar: Int
    var lastBar: Int
}

nonisolated struct LocatedScoreEvent: Equatable, Sendable {
    var barIndex: Int
    var tick: Int
    var event: ScoreEvent
}

nonisolated struct ScoreDocument: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var versionID: UUID = UUID()
    var title: String
    var composer: String = "原创练习"
    var ticksPerQuarter: Int = 960
    var tempo: ScoreTempo = .init(bpm: 100)
    /// Bass to treble, sounding MIDI pitches before capo.
    var tuning: [Int] = [40, 45, 50, 55, 59, 64]
    var capo: Int = 0
    var bars: [ScoreBar]
    var sourceID: UUID? = nil

    var totalTicks: Int { bars.reduce(0) { $0 + length(of: $1) } }
    var fullRange: ScoreRange { .init(firstBar: 0, lastBar: max(0, bars.count - 1)) }
    var confirmedBarCount: Int { bars.filter { !$0.isSourceOnly }.count }
    var hasSourceOnlyBars: Bool { bars.contains(where: \.isSourceOnly) }
    var soundingEvents: [LocatedScoreEvent] {
        var start = 0
        var result: [LocatedScoreEvent] = []
        for (index, bar) in bars.enumerated() {
            for event in bar.events where !event.isRest {
                result.append(LocatedScoreEvent(barIndex: index, tick: start + event.tick, event: event))
            }
            start += length(of: bar)
        }
        return result.sorted {
            if $0.tick == $1.tick { return $0.event.voice < $1.event.voice }
            return $0.tick < $1.tick
        }
    }

    func length(of bar: ScoreBar) -> Int {
        guard (24...61_440).contains(ticksPerQuarter),(1...32).contains(bar.numerator),[2,4,8,16].contains(bar.denominator) else { return 0 }
        return ticksPerQuarter * 4 * bar.numerator / bar.denominator
    }

    func startTick(ofBar index: Int) -> Int { bars.prefix(max(0, index)).reduce(0) { $0 + length(of: $1) } }

    func barIndex(atTick tick: Int) -> Int {
        var start = 0
        for (index, bar) in bars.enumerated() {
            start += length(of: bar)
            if tick < start { return index }
        }
        return max(0, bars.count - 1)
    }

    func tickRange(for range: ScoreRange) throws -> Range<Int> {
        guard range.firstBar >= 0, range.lastBar >= range.firstBar, range.lastBar < bars.count else {
            throw ScoreValidationError.invalidRange
        }
        return startTick(ofBar: range.firstBar)..<startTick(ofBar: range.lastBar + 1)
    }

    func seconds(atTick tick: Int, speed: Double = 1) throws -> Double {
        guard speed.isFinite, (0.25...1.5).contains(speed), ticksPerQuarter > 0, tempo.isValid else {
            throw ScoreValidationError.invalidMetadata
        }
        var start = 0, elapsed = 0.0, currentTempo = tempo
        for bar in bars {
            if let change = bar.tempo { currentTempo = change }
            guard currentTempo.isValid else { throw ScoreValidationError.invalidBar(bar.number) }
            let count = max(0, min(length(of: bar), tick - start))
            elapsed += Double(count) / Double(ticksPerQuarter) * 60 / currentTempo.quarterBPM / speed
            start += length(of: bar)
            if start >= tick { break }
        }
        return elapsed
    }

    func tick(atSeconds seconds: Double, speed: Double = 1) throws -> Int {
        guard seconds.isFinite, seconds >= 0 else { throw ScoreValidationError.invalidMetadata }
        _ = try self.seconds(atTick: 0, speed: speed)
        var remaining = seconds, start = 0, currentTempo = tempo
        for bar in bars {
            if let change = bar.tempo { currentTempo = change }
            guard currentTempo.isValid else { throw ScoreValidationError.invalidBar(bar.number) }
            let secondsPerTick = 60 / currentTempo.quarterBPM / Double(ticksPerQuarter) / speed
            let duration = Double(length(of: bar)) * secondsPerTick
            if remaining + 0.000000001 < duration {
                return start + Int((remaining / secondsPerTick + 0.00000001).rounded(.down))
            }
            remaining -= duration
            start += length(of: bar)
        }
        return totalTicks
    }

    func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 200, !bars.isEmpty, bars.count <= 2_000,
              (24...61_440).contains(ticksPerQuarter), tempo.isValid,
              tuning.count == 6, tuning.allSatisfy({ (24...88).contains($0) }), (0...12).contains(capo) else {
            throw ScoreValidationError.invalidMetadata
        }
        var ids = Set<UUID>()
        for bar in bars {
            guard (1...32).contains(bar.numerator), [2, 4, 8, 16].contains(bar.denominator),
                  ticksPerQuarter * 4 * bar.numerator % bar.denominator == 0,
                  bar.tempo?.isValid != false else { throw ScoreValidationError.invalidBar(bar.number) }
            if bar.isSourceOnly {
                guard bar.events.isEmpty, let source = bar.source, source.validBox != nil,
                      source.page >= 1, sourceID != nil else { throw ScoreValidationError.invalidBar(bar.number) }
            }
            guard bar.events.count <= 256 else { throw ScoreValidationError.invalidEvent(bar.number) }
            for event in bar.events {
                guard ids.insert(event.id).inserted, event.tick >= 0, event.duration > 0,
                      event.tick < length(of: bar), event.duration <= length(of: bar) - event.tick,
                      event.tones.count <= 6, (1...8).contains(event.voice) else {
                    throw ScoreValidationError.invalidEvent(bar.number)
                }
                var strings = Set<Int>()
                for tone in event.tones {
                    guard (24...108).contains(tone.midi) else { throw ScoreValidationError.invalidEvent(bar.number) }
                    if let string = tone.string, let fret = tone.fret {
                        guard (1...6).contains(string), (0...24).contains(fret), strings.insert(string).inserted,
                              tuning[6 - string] + capo + fret == tone.midi else {
                            throw ScoreValidationError.invalidFret(bar.number)
                        }
                    } else if tone.string != nil || tone.fret != nil {
                        throw ScoreValidationError.invalidFret(bar.number)
                    }
                    if let finger = tone.finger, !(0...4).contains(finger) { throw ScoreValidationError.invalidFret(bar.number) }
                }
            }
        }
    }
}
