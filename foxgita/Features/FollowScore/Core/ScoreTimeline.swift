import Foundation

/// Built once per immutable score, rather than walking/sorting the score per frame.
nonisolated struct ScoreTimeline: Sendable {
    let barTicks: [Int]
    private let barSeconds: [Double]
    private let tempos: [ScoreTempo]
    private let secondsPerTick: [Double]
    private let lyrics: [LocatedScoreEvent]
    let shortestDuration: Int
    var totalTicks: Int { barTicks.last ?? 0 }

    init(score: ScoreDocument) {
        var ticks = [0],seconds = [0.0],rates: [Double] = [],tempos: [ScoreTempo] = [],lyrics: [LocatedScoreEvent] = []
        var tempo = score.tempo.isValid ? score.tempo : .init(bpm: 100)
        var shortest = score.ticksPerQuarter
        var foundDuration = false
        for (i,bar) in score.bars.enumerated() {
            if let next = bar.tempo,next.isValid { tempo = next }
            let rate = 60/tempo.quarterBPM/Double(max(1,score.ticksPerQuarter))
            rates.append(rate); tempos.append(tempo)
            for event in bar.events {
                if event.duration > 0 { shortest = foundDuration ? min(shortest,event.duration) : event.duration; foundDuration = true }
                if !event.isRest,event.lyric != nil { lyrics.append(.init(barIndex: i,tick: ticks.last!+event.tick,event: event)) }
            }
            ticks.append(ticks.last!+score.length(of: bar))
            seconds.append(seconds.last!+Double(score.length(of: bar))*rate)
        }
        barTicks = ticks; barSeconds = seconds; secondsPerTick = rates; self.tempos = tempos
        self.lyrics = lyrics.sorted { $0.tick == $1.tick ? $0.event.voice < $1.event.voice : $0.tick < $1.tick }
        shortestDuration = max(1,shortest)
    }
    func startTick(ofBar index: Int) -> Int { barTicks[max(0,min(barTicks.count-1,index))] }
    func barIndex(atTick tick: Int) -> Int { max(0,min(secondsPerTick.count-1,upperBound(barTicks,tick)-1)) }
    func seconds(atTick tick: Int) -> Double {
        guard !secondsPerTick.isEmpty else { return 0 }
        let tick = max(0,min(totalTicks,tick)),i = barIndex(atTick: tick)
        return barSeconds[i]+Double(tick-barTicks[i])*secondsPerTick[i]
    }
    func tick(atSeconds time: Double) -> Int {
        guard time.isFinite,time > 0,!secondsPerTick.isEmpty else { return 0 }
        if time >= barSeconds.last! { return totalTicks }
        let i = max(0,min(secondsPerTick.count-1,upperBound(barSeconds,time+0.000000001)-1))
        return min(totalTicks,barTicks[i]+Int(max(0,(time-barSeconds[i])/secondsPerTick[i]+0.00000001).rounded(.down)))
    }
    func tempo(atTick tick: Int) -> ScoreTempo { tempos.isEmpty ? .init(bpm: 100) : tempos[barIndex(atTick: tick)] }
    func lyric(atTick tick: Int) -> String? {
        var lower = 0,upper = lyrics.count
        while lower < upper { let mid = (lower+upper)/2; if lyrics[mid].tick <= tick { lower = mid+1 } else { upper = mid } }
        return lower > 0 ? lyrics[lower-1].event.lyric : nil
    }
    private func upperBound<T: Comparable>(_ values: [T],_ value: T) -> Int {
        var lower = 0,upper = values.count
        while lower < upper { let mid = (lower+upper)/2; if values[mid] <= value { lower = mid+1 } else { upper = mid } }
        return lower
    }
}

/// Interpolate between real audio-clock samples; never advance a paused transport.
nonisolated struct ScorePlaybackProjection: Sendable {
    let run: ScoreRun
    let uptime: TimeInterval
    func position(at time: TimeInterval) -> (tick: Int,loop: Int) {
        var projected = run
        projected.advance(by: max(0,min(0.15,time-uptime)))
        return (projected.tick,projected.playbackLoops)
    }
    func tick(at time: TimeInterval) -> Int { position(at: time).tick }
}
