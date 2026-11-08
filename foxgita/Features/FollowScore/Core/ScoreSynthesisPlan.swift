import Foundation

nonisolated struct ScoreSynthesisNote: Sendable {
    var frame: Int64
    var durationFrames: Int64
    var midi: Int
    var gain: Float
}
nonisolated struct ScoreSynthesisPlan: Sendable {
    var notes: [ScoreSynthesisNote]
    var beatFrames: [Int64]
    var downbeatFrames: [Int64]
    var loopFrames: Int64
    var sampleRate: Double

    init(score: ScoreDocument, range: ScoreRange, speed: Double, sampleRate: Double) throws {
        try score.validate()
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate) else { throw ScoreRunError.invalidConfiguration }
        let bounds = try score.tickRange(for: range)
        let origin = try score.seconds(atTick: bounds.lowerBound, speed: speed)
        self.sampleRate = sampleRate
        loopFrames = Int64(((try score.seconds(atTick: bounds.upperBound,speed: speed))-origin)*sampleRate)
        notes = []; beatFrames = []; downbeatFrames = []
        var lastVoice: [String:Int] = [:]
        for index in range.firstBar...range.lastBar {
            let bar = score.bars[index], start = score.startTick(ofBar: index)
            let beatTicks = score.ticksPerQuarter * 4 / bar.denominator
            for beat in 0..<bar.numerator {
                let time = try score.seconds(atTick: start+beat*beatTicks,speed: speed)-origin
                beatFrames.append(Int64((time*sampleRate).rounded()))
                if beat == 0 { downbeatFrames.append(Int64((time*sampleRate).rounded())) }
            }
            for event in bar.events {
                let time = try score.seconds(atTick: start+event.tick,speed: speed)-origin
                let end = try score.seconds(atTick: start+event.tick+event.duration,speed: speed)-origin
                let frame = Int64((time*sampleRate).rounded())
                let endFrame = Int64((end*sampleRate).rounded())
                for tone in event.tones {
                    let key = "\(event.voice):\(tone.string ?? 0):\(tone.midi)"
                    if tone.tiedFromPrevious, let previous = lastVoice[key],
                       abs(notes[previous].frame+notes[previous].durationFrames-frame) <= 1 {
                        notes[previous].durationFrames = endFrame-notes[previous].frame
                    } else {
                        // A range beginning inside a sustained note must still sound.
                        lastVoice[key] = notes.count
                        notes.append(.init(frame: frame,durationFrames: max(1,endFrame-frame),midi: tone.midi,gain: 0.09))
                    }
                }
            }
        }
        notes.sort { $0.frame < $1.frame }
    }
}
