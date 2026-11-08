import Foundation

nonisolated enum ScoreRunError: Error { case mustPause, invalidConfiguration }
nonisolated enum ScoreRunState: String, Codable, Sendable { case ready, countingIn, playing, paused, finished }
nonisolated enum ScoreRunMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case practice, performance
    var id: String { rawValue }
    var title: String { self == .practice ? "练习" : "演奏" }
}
nonisolated enum ScoreNotation: String, Codable, CaseIterable, Identifiable, Sendable {
    case tablature, staff, combined
    var id: String { rawValue }
    var title: String {
        switch self { case .tablature: "六线谱"; case .staff: "五线谱"; case .combined: "双谱" }
    }
}

nonisolated struct ScoreRun: Sendable {
    let id = UUID()
    let score: ScoreDocument
    let timeline: ScoreTimeline
    private(set) var range: ScoreRange
    private(set) var speed: Double
    private(set) var loopLimit: Int?
    private(set) var state: ScoreRunState = .ready
    private(set) var completedLoops = 0
    private(set) var elapsedSeconds = 0.0
    private(set) var positionSeconds = 0.0
    private(set) var countInRemaining = 0.0
    private(set) var mode: ScoreRunMode
    private(set) var playbackLoops = 0
    private var traversedFromA = true
    private var continuous = true
    var isCompletePerformance: Bool { mode == .performance && state == .finished && continuous && completedLoops == 1 }
    var remainingTraversals: Int? { loopLimit.map { $0-completedLoops+(traversedFromA ? 0 : 1) } }

    init(score: ScoreDocument, range: ScoreRange, speed: Double, loopLimit: Int? = nil, mode: ScoreRunMode = .practice) throws {
        try score.validate()
        _ = try score.tickRange(for: range)
        guard speed.isFinite, (0.25...1.5).contains(speed), loopLimit == nil || (1...999).contains(loopLimit!) else {
            throw ScoreRunError.invalidConfiguration
        }
        self.score = score; timeline = ScoreTimeline(score: score); self.range = range; self.mode = mode
        self.speed = mode == .performance ? 1 : speed
        self.loopLimit = mode == .performance ? 1 : loopLimit
    }

    var tick: Int {
        let lower = timeline.startTick(ofBar: range.firstBar)
        if state == .finished { return timeline.startTick(ofBar: range.lastBar + 1) }
        let origin = timeline.seconds(atTick: lower)
        return timeline.tick(atSeconds: origin + positionSeconds*speed)
    }
    var rangeDuration: Double {
        let a = timeline.seconds(atTick: timeline.startTick(ofBar: range.firstBar))
        let b = timeline.seconds(atTick: timeline.startTick(ofBar: range.lastBar + 1))
        return (b-a)/speed
    }
    var countInDuration: Double {
        let index = timeline.barIndex(atTick: tick)
        return (timeline.seconds(atTick: timeline.startTick(ofBar: index+1))
            - timeline.seconds(atTick: timeline.startTick(ofBar: index)))/speed
    }

    mutating func start(countIn: Bool = true) {
        guard state != .playing && state != .countingIn else { return }
        if state == .finished { resetTraversal() }
        countInRemaining = countIn ? countInDuration : 0
        state = countInRemaining > 0 ? .countingIn : .playing
    }
    mutating func pause() {
        guard state == .playing || state == .countingIn else { return }
        if state == .playing,positionSeconds > 0 { continuous = false }
        state = .paused
        countInRemaining = 0
    }
    private mutating func resetTraversal() { positionSeconds = 0; completedLoops = 0; playbackLoops = 0; traversedFromA = true; continuous = true }
    mutating func rewind() { pause(); state = .paused; resetTraversal() }

    mutating func seek(toBar index: Int) throws {
        guard state != .playing && state != .countingIn else { throw ScoreRunError.mustPause }
        guard (range.firstBar...range.lastBar).contains(index) else { throw ScoreValidationError.invalidRange }
        if mode == .performance { mode = .practice }
        resetTraversal(); traversedFromA = index == range.firstBar; continuous = false
        positionSeconds = try score.seconds(atTick: score.startTick(ofBar: index), speed: speed)
            - score.seconds(atTick: score.startTick(ofBar: range.firstBar), speed: speed)
        state = .paused
    }

    mutating func configure(range: ScoreRange, speed: Double, loopLimit: Int?) throws {
        guard state != .playing && state != .countingIn else { throw ScoreRunError.mustPause }
        _ = try score.tickRange(for: range)
        guard speed.isFinite, (0.25...1.5).contains(speed), loopLimit == nil || (1...999).contains(loopLimit!) else {
            throw ScoreRunError.invalidConfiguration
        }
        if mode == .performance,(range != self.range || speed != 1 || loopLimit != 1) { mode = .practice }
        self.range = range; self.speed = mode == .performance ? 1 : speed
        self.loopLimit = mode == .performance ? 1 : loopLimit
        resetTraversal(); state = .paused
    }

    mutating func changeMode(_ mode: ScoreRunMode) throws {
        guard state != .playing && state != .countingIn else { throw ScoreRunError.mustPause }
        self.mode = mode
        if mode == .performance { speed = 1; loopLimit = 1 }
        resetTraversal(); state = .paused
    }

    mutating func advance(by delta: Double) {
        guard delta.isFinite, delta > 0, state == .playing || state == .countingIn else { return }
        var remaining = delta
        if state == .countingIn {
            let consumed = min(remaining, countInRemaining)
            remaining -= consumed; countInRemaining -= consumed
            if countInRemaining <= 0.0000001 { state = .playing }
        }
        guard state == .playing, remaining > 0, rangeDuration > 0 else { return }
        let duration = rangeDuration
        let available = remainingTraversals.map { Double($0) * duration - positionSeconds } ?? remaining
        let consumed = min(remaining, max(0, available))
        elapsedSeconds += consumed
        positionSeconds += consumed
        let finished = Int((positionSeconds / duration + 0.000000001).rounded(.down))
        if finished > 0 {
            completedLoops += finished-(traversedFromA ? 0 : 1)
            playbackLoops += finished; traversedFromA = true
        }
        positionSeconds -= Double(finished) * duration
        positionSeconds = max(0, positionSeconds)
        if let limit = loopLimit, completedLoops >= limit {
            completedLoops = limit; state = .finished; positionSeconds = 0
        }
    }
}
