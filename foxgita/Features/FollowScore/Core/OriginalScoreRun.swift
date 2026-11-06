import Foundation

nonisolated struct OriginalScoreProgress: Codable, Equatable, Sendable {
    var versionID: UUID
    var rowID: UUID
    var rowBeat: Double = 0
    var bpm: Double
    var range: OriginalScoreRange
    var looping = false
    var metronome = false
    var finished = false
}

nonisolated struct OriginalScoreRun: Sendable {
    enum State: String, Sendable { case idle, preparing, playing, paused, completed }
    let document: OriginalScoreDocument
    private(set) var range: OriginalScoreRange
    private(set) var bpm: Double
    private(set) var looping = false
    private(set) var state: State = .idle
    private(set) var preparationRemaining = 0.0
    private(set) var elapsedSeconds = 0.0
    private(set) var position = 0.0

    init(document: OriginalScoreDocument, progress: OriginalScoreProgress? = nil, resumeAtRowStart: Bool = true) throws {
        try document.validate()
        self.document = document
        guard let full = document.fullRange else { throw OriginalScoreError.invalidRange }
        range = full
        bpm = document.initialBPM
        if let progress {
            guard progress.versionID == document.versionID else { throw OriginalScoreError.invalidRange }
            _ = try document.indices(for: progress.range)
            guard progress.bpm.isFinite, (40...200).contains(progress.bpm) else { throw OriginalScoreError.invalidDocument }
            range = progress.range; bpm = progress.bpm; looping = progress.looping
            let indices = try document.indices(for: range)
            guard let index = document.rows.firstIndex(where: { $0.id == progress.rowID }), indices.contains(index) else {
                throw OriginalScoreError.invalidRange
            }
            guard progress.rowBeat.isFinite, (0...document.rows[index].beats).contains(progress.rowBeat) else {
                throw OriginalScoreError.invalidRange
            }
            // A persisted session always resumes at the beginning of its row.
            if !progress.finished {
                position = document.rows[indices.lowerBound..<index].reduce(0) { $0 + $1.beats }
                if !resumeAtRowStart { position += progress.rowBeat }
            }
        }
    }

    var selectedRows: ArraySlice<OriginalScoreRow> {
        guard let indices = try? document.indices(for: range) else { return [] }
        return document.rows[indices]
    }
    var rangeBeats: Double { selectedRows.reduce(0) { $0 + $1.beats } }
    var startBeat: Double { (try? document.beats(before: range.first)) ?? 0 }
    private var location: (row: OriginalScoreRow, beat: Double) {
        var remaining = position
        for row in selectedRows {
            if remaining < row.beats { return (row, max(0, remaining)) }
            remaining -= row.beats
        }
        let last = selectedRows.last!
        return (last, last.beats)
    }
    var row: OriginalScoreRow { location.row }
    var rowBeat: Double { location.beat }
    var rowFraction: Double { min(1, max(0, rowBeat / row.beats)) }

    mutating func play() {
        if state == .completed { position = 0 }
        preparationRemaining = 0; state = .playing
    }
    mutating func prepare() {
        guard state != .playing else { return }
        if state == .completed { position = 0 }
        preparationRemaining = 3; state = .preparing
    }
    mutating func pause() { preparationRemaining = 0; state = .paused }
    mutating func advance(seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        var delta = seconds
        if state == .preparing {
            let lead = min(delta, preparationRemaining)
            preparationRemaining -= lead; delta -= lead
            if preparationRemaining <= 0 { state = .playing }
        }
        guard state == .playing, delta > 0 else { return }
        let secondsLeft = max(0, rangeBeats - position) * 60 / bpm
        let consumed = looping ? delta : min(delta, secondsLeft)
        elapsedSeconds += consumed
        position += consumed * bpm / 60
        if position >= rangeBeats - 0.000000001 {
            if looping { position = position.truncatingRemainder(dividingBy: rangeBeats) }
            else { position = rangeBeats; state = .completed }
        }
    }
    mutating func setBPM(_ value: Double) throws {
        guard value.isFinite, (40...200).contains(value) else { throw OriginalScoreError.invalidDocument }
        pause(); bpm = value
    }
    mutating func setRange(_ value: OriginalScoreRange) throws {
        _ = try document.indices(for: value)
        pause(); range = value; position = 0
    }
    mutating func setLooping(_ value: Bool) { looping = value }
    mutating func rewind() { pause(); position = 0 }

    func progress(metronome: Bool) -> OriginalScoreProgress {
        .init(versionID: document.versionID, rowID: row.id, rowBeat: rowBeat, bpm: bpm,
              range: range, looping: looping, metronome: metronome, finished: state == .completed)
    }
}
