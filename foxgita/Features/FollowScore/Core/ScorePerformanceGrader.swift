import Foundation

nonisolated struct ScoreGradeSummary: Equatable, Sendable {
    var judgedEvents: Int
    var expectedEvents: Int
    var pitchAccuracy: Double?
    var rhythmAccuracy: Double?
    var totalScore: Int?
    var coverage: Double { expectedEvents > 0 ? Double(judgedEvents) / Double(expectedEvents) : 0 }
}

nonisolated struct ScorePerformanceGrader: Sendable {
    private struct Unit: Sendable {
        var time: Double
        var duration: Double
        var pitches: Set<Int>
        var window: Double
        var reliable = false
        var pitch = 0.0
        var onsetDistance: Double?
        var closed = false
    }
    private var units: [Unit] = []
    private var rangeDuration = 0.0
    private var nextLoop = 1
    private var template: [Unit] = []
    private var targetEvents = 0
    private var retiredExpected = 0, retiredJudged = 0
    private var retiredPitch = 0.0, retiredRhythm = 0.0
    private(set) var feedback = "等待弹奏"

    init(score: ScoreDocument, range: ScoreRange, speed: Double,loopLimit: Int? = 1) {
        let startTick = score.startTick(ofBar: range.firstBar)
        let start = (try? score.seconds(atTick: startTick, speed: speed)) ?? 0
        rangeDuration = ((try? score.seconds(atTick: score.startTick(ofBar: range.lastBar+1), speed: speed)) ?? start) - start
        var events: [(Int, ScoreEvent)] = []
        for i in range.firstBar...range.lastBar where score.bars.indices.contains(i) {
            for event in score.bars[i].events where !event.tones.allSatisfy(\.tiedFromPrevious) || event.isRest {
                events.append((score.startTick(ofBar: i)+event.tick,event))
            }
        }
        events.sort { $0.0 < $1.0 }
        for (index, pair) in events.enumerated() {
            let time = ((try? score.seconds(atTick: pair.0, speed: speed)) ?? start) - start
            let end = ((try? score.seconds(atTick: pair.0+pair.1.duration, speed: speed)) ?? (time+start)) - start
            let nextTime = index+1 < events.count
                ? ((try? score.seconds(atTick: events[index+1].0, speed: speed)) ?? start) - start
                : rangeDuration
            let window = min(0.22,max(0.035,(nextTime-time)*0.42))
            units.append(Unit(time: time, duration: end-time, pitches: Set(pair.1.tones.filter { !$0.tiedFromPrevious }.map(\.midi)), window: window))
        }
        template = units
        targetEvents = units.count*max(1,min(999,loopLimit ?? 1))
    }

    mutating func observe(_ observation: ScorePitchObservation, at time: Double) {
        guard time.isFinite, time >= 0, rangeDuration > 0 else { return }
        expand(through: time)
        for i in units.indices where !units[i].closed && abs(time-units[i].time) <= units[i].window {
            guard observation.quality != .unreliable else { continue }
            units[i].reliable = true
            let expected = units[i].pitches
            let played = Set(observation.pitches.keys)
            let accuracy: Double
            if expected.isEmpty { accuracy = played.isEmpty ? 1 : 0 }
            else {
                let intersection = Double(expected.intersection(played).count)
                accuracy = played.isEmpty ? 0 : 2 * intersection / Double(expected.count+played.count)
            }
            units[i].pitch = max(units[i].pitch, accuracy)
            if expected.isEmpty {
                units[i].onsetDistance = played.isEmpty ? 0 : units[i].window
            } else if observation.onset {
                let distance = abs(time-units[i].time)
                units[i].onsetDistance = min(units[i].onsetDistance ?? .infinity,distance)
                feedback = accuracy >= 0.8 ? "音高正确 · 注意节奏" : "检查和弦组成音"
            }
        }
        close(through: time)
        if observation.quality == .unreliable { feedback = "暂时无法可靠判断，请检查收音环境" }
    }

    mutating func begin(at time: Double) {
        guard time.isFinite,time >= 0 else { return }
        expand(through: time)
        targetEvents -= units.filter { $0.time+$0.window < time }.count
        units.removeAll { $0.time+$0.window < time }
    }
    mutating func finish(at time: Double) {
        guard time.isFinite,time >= 0 else { return }
        // A pause can close the current onset but must not mark upcoming notes missed.
        for i in units.indices where units[i].time <= time { units[i].closed = true }
    }

    var summary: ScoreGradeSummary {
        let closed = units.filter(\.closed), judged = closed.filter(\.reliable)
        let expected = max(targetEvents,retiredExpected+units.count)
        let judgedCount = retiredJudged+judged.count
        guard judgedCount > 0 else {
            return .init(judgedEvents: 0, expectedEvents: expected, pitchAccuracy: nil, rhythmAccuracy: nil, totalScore: nil)
        }
        let pitch = (retiredPitch+judged.reduce(0) { $0 + $1.pitch }) / Double(judgedCount)
        let rhythm = (retiredRhythm+judged.reduce(0.0) { result, unit in
            result + (unit.onsetDistance.map { max(0,1-$0/unit.window) } ?? 0)
        }) / Double(judgedCount)
        let coverage = Double(judgedCount)/Double(max(1,expected))
        let total = coverage >= 0.6 ? Int((100*(pitch*0.6+rhythm*0.4)).rounded()) : nil
        return .init(judgedEvents: judgedCount, expectedEvents: expected, pitchAccuracy: pitch, rhythmAccuracy: rhythm, totalScore: total)
    }

    private mutating func expand(through time: Double) {
        guard !template.isEmpty, rangeDuration > 0 else { return }
        guard time/rangeDuration < Double(Int.max) else { return }
        let needed = Int(time/rangeDuration)
        if nextLoop <= needed {
            for unit in units where unit.closed {
                retiredExpected += 1
                if unit.reliable {
                    retiredJudged += 1; retiredPitch += unit.pitch
                    retiredRhythm += unit.onsetDistance.map { max(0,1-$0/unit.window) } ?? 0
                }
            }
            units.removeAll( where: \.closed)
        }
        while nextLoop <= needed {
            for var unit in template { unit.time += Double(nextLoop)*rangeDuration; units.append(unit) }
            nextLoop += 1
        }
    }
    private mutating func close(through time: Double) {
        for i in units.indices where units[i].time+units[i].window < time { units[i].closed = true }
    }
}
