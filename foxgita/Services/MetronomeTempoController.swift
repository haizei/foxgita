import Foundation

struct TapTempoAttempt: Equatable {
    private(set) var tapTimes: [TimeInterval] = []
    private(set) var estimatedBPM: Int?
    private(set) var rejectedCount = 0
    private(set) var retainedIntervalCount = 0

    var tapCount: Int { tapTimes.count }
    var isStable: Bool { tapCount >= 4 && retainedIntervalCount >= 2 && estimatedBPM != nil }

    mutating func registerTap(at time: TimeInterval) -> Int? {
        if let last = tapTimes.last, time - last > 2 {
            reset()
        }
        if let last = tapTimes.last {
            let interval = time - last
            guard (0.25...1.5).contains(interval) else {
                rejectedCount += 1
                return estimatedBPM
            }
        }
        tapTimes.append(time)
        if tapTimes.count > 8 { tapTimes.removeFirst() }
        let estimate = Self.estimate(from: tapTimes)
        estimatedBPM = estimate.bpm
        retainedIntervalCount = estimate.retainedCount
        return estimatedBPM
    }

    mutating func reset() {
        tapTimes.removeAll(keepingCapacity: true)
        estimatedBPM = nil
        rejectedCount = 0
        retainedIntervalCount = 0
    }

    private static func estimate(from taps: [TimeInterval]) -> (bpm: Int?, retainedCount: Int) {
        guard taps.count >= 2 else { return (nil, 0) }
        let intervals = zip(taps, taps.dropFirst()).map { $1 - $0 }
        let sorted = intervals.sorted()
        let median: Double
        if sorted.count.isMultiple(of: 2) {
            median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            median = sorted[sorted.count / 2]
        }
        let retained = intervals.filter { abs($0 - median) <= median * 0.2 }
        guard !retained.isEmpty else { return (nil, 0) }
        let mean = retained.reduce(0, +) / Double(retained.count)
        return (Int((60 / mean).rounded()), retained.count)
    }
}

struct TempoRampSettings: Equatable, Codable, Sendable {
    var startBPM: Int
    var targetBPM: Int
    var barsPerStage: Int
    var stepBPM: Int
    var countInBars: Int

    init(
        startBPM: Int,
        targetBPM: Int,
        barsPerStage: Int = 4,
        stepBPM: Int = 5,
        countInBars: Int = 1
    ) {
        self.startBPM = startBPM
        self.targetBPM = targetBPM
        self.barsPerStage = barsPerStage
        self.stepBPM = stepBPM
        self.countInBars = countInBars
    }

    var validationError: String? {
        guard (40...200).contains(startBPM), (40...200).contains(targetBPM) else {
            return String(localized: "速度需在 40–200 BPM 之间")
        }
        guard startBPM < targetBPM else { return String(localized: "目标速度需高于起始速度") }
        guard [1, 2, 4, 8, 16].contains(barsPerStage),
              [1, 2, 5, 10].contains(stepBPM),
              (0...2).contains(countInBars) else {
            return String(localized: "请检查变速设置")
        }
        return nil
    }

    static func suggested(currentBPM: Int) -> Self {
        let start = min(199, max(40, currentBPM))
        return Self(startBPM: start, targetBPM: min(200, start + 20))
    }
}

enum TempoRampState: String, Equatable, Codable, Sendable {
    case idle, countIn, running, paused, targetHold, interrupted, cancelled
}

enum TempoManualChangeChoice: Equatable {
    case adjustCurrentStage, endTraining, cancel
}

struct MetronomeTimelineEvent: Equatable, Sendable {
    let beat: Int
    let bar: Int
    var appliedBPM: Int? = nil
}

@MainActor
@Observable
final class MetronomeTempoController {
    let engine: MetronomeEngine
    private(set) var tapAttempt = TapTempoAttempt()
    private(set) var tapReadyToApply = false
    private(set) var pendingTempo: Int?
    private(set) var rampState: TempoRampState = .idle
    private(set) var rampSettings: TempoRampSettings?
    private(set) var completedBarsInStage = 0
    private(set) var completedBars = 0
    private(set) var completedStageCount = 0
    private(set) var stableMaxBPM = 0
    private(set) var pauseCount = 0
    private(set) var interruptionCount = 0
    private(set) var completedCountInBars = 0
    private(set) var currentStageBPM = 0
    private(set) var didRequireUserResume = false
    private(set) var interruptionRecoveryAvailable = false
    var savedRampSettings: TempoRampSettings?
    private var playbackOverride: Bool?
    private var tapReadyTask: Task<Void, Never>?
    private var awaitingRampBoundary = false
    private var hasSeenRampBoundary = false
    private var subdivisionBeforeCountIn: MetronomeSubdivision?
    private var stateBeforePauseOrInterruption: TempoRampState?

    var isRampActive: Bool {
        [.countIn, .running, .paused, .targetHold, .interrupted].contains(rampState)
    }

    var remainingBarsInStage: Int {
        max(0, (rampSettings?.barsPerStage ?? 0) - completedBarsInStage)
    }

    var nextStageBPM: Int {
        guard let rampSettings else { return engine.bpm }
        return min(rampSettings.targetBPM, currentStageBPM + rampSettings.stepBPM)
    }

    init(engine: MetronomeEngine) {
        self.engine = engine
        engine.onTimelineEvent = { [weak self] event in
            self?.handleAudibleBeat(
                beat: event.beat, bar: event.bar, appliedBPM: event.appliedBPM
            )
        }
    }

    convenience init() { self.init(engine: MetronomeEngine()) }

    func registerTap(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int? {
        guard !isRampActive else { return nil }
        pendingTempo = nil
        tapReadyTask?.cancel()
        tapReadyToApply = false
        let estimate = tapAttempt.registerTap(at: time)
        if tapAttempt.isStable {
            tapReadyTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                self?.tapReadyToApply = true
            }
        }
        return estimate
    }

    func resetTap() {
        tapReadyTask?.cancel()
        tapAttempt.reset()
        tapReadyToApply = false
    }

    func applyMeasuredTempo(_ bpm: Int) {
        let value = min(200, max(40, bpm))
        if isPlaying {
            pendingTempo = value
            engine.queueBpmAtNextBar(value)
        } else {
            engine.setBpm(value)
            pendingTempo = nil
        }
    }

    func setTempo(_ bpm: Int) {
        guard !isRampActive else { return }
        engine.setBpm(bpm)
    }

    func bump(_ delta: Int) {
        guard !isRampActive else { return }
        engine.bump(delta)
    }

    func startRamp(_ settings: TempoRampSettings) {
        guard settings.validationError == nil else { return }
        rampSettings = settings
        completedBarsInStage = 0
        completedBars = 0
        completedStageCount = 0
        stableMaxBPM = settings.startBPM
        currentStageBPM = settings.startBPM
        pauseCount = 0
        interruptionCount = 0
        completedCountInBars = 0
        hasSeenRampBoundary = false
        didRequireUserResume = false
        interruptionRecoveryAvailable = false
        stateBeforePauseOrInterruption = nil
        awaitingRampBoundary = isPlaying
        if !isPlaying {
            engine.setBpm(settings.startBPM)
        } else {
            engine.queueBpmAtNextBar(settings.startBPM)
        }
        if !isPlaying, settings.countInBars > 0 {
            subdivisionBeforeCountIn = engine.subdivision
            engine.setSubdivision(.quarter)
            rampState = .countIn
        } else {
            rampState = .running
        }
    }

    func handleAudibleBeat(beat: Int, bar: Int, appliedBPM: Int? = nil) {
        guard beat == 0 else { return }
        if let appliedBPM, pendingTempo == appliedBPM, !isRampActive {
            self.pendingTempo = nil
        }
        guard let settings = rampSettings else { return }
        if awaitingRampBoundary {
            engine.setBpm(settings.startBPM)
            awaitingRampBoundary = false
            hasSeenRampBoundary = true
            queueUpcomingRampTempoIfNeeded(settings)
            return
        }
        if !hasSeenRampBoundary {
            hasSeenRampBoundary = true
            queueUpcomingRampTempoIfNeeded(settings)
            return
        }
        switch rampState {
        case .countIn:
            completedCountInBars += 1
            if completedCountInBars >= settings.countInBars {
                if let subdivisionBeforeCountIn { engine.setSubdivision(subdivisionBeforeCountIn) }
                subdivisionBeforeCountIn = nil
                rampState = .running
                completedBarsInStage = 0
                queueUpcomingRampTempoIfNeeded(settings)
            }
        case .running:
            let completedStageBPM = currentStageBPM
            completedBarsInStage += 1
            completedBars += 1
            guard completedBarsInStage >= settings.barsPerStage else {
                queueUpcomingRampTempoIfNeeded(settings)
                return
            }
            completedBarsInStage = 0
            completedStageCount += 1
            stableMaxBPM = max(stableMaxBPM, completedStageBPM)
            if completedStageBPM >= settings.targetBPM {
                rampState = .targetHold
            } else {
                currentStageBPM = appliedBPM ?? engine.bpm
                queueUpcomingRampTempoIfNeeded(settings)
            }
        default:
            break
        }
    }

    func pauseRamp() {
        guard rampState == .running || rampState == .countIn else { return }
        stateBeforePauseOrInterruption = rampState
        rampState = .paused
        completedBarsInStage = 0
        engine.cancelQueuedTempo()
        pauseCount += 1
    }

    func resumeRamp() {
        guard rampState == .paused || rampState == .interrupted else { return }
        guard rampState != .interrupted || interruptionRecoveryAvailable else { return }
        rampState = stateBeforePauseOrInterruption ?? .running
        stateBeforePauseOrInterruption = nil
        completedBarsInStage = 0
        hasSeenRampBoundary = false
        didRequireUserResume = false
        interruptionRecoveryAvailable = false
    }

    func handleInterruption() {
        resetTap()
        pendingTempo = nil
        engine.cancelQueuedTempo()
        guard isRampActive, rampState != .interrupted else { return }
        if rampState != .paused {
            stateBeforePauseOrInterruption = rampState
        }
        rampState = .interrupted
        completedBarsInStage = 0
        interruptionCount += 1
        didRequireUserResume = true
        interruptionRecoveryAvailable = false
    }

    func handleInterruptionEnded() {
        guard rampState == .interrupted else { return }
        interruptionRecoveryAvailable = true
    }

    func handleManualChange(_ value: Int, choice: TempoManualChangeChoice) {
        switch choice {
        case .adjustCurrentStage:
            let adjusted = min(rampSettings?.targetBPM ?? 200, max(40, value))
            engine.setBpm(adjusted)
            currentStageBPM = adjusted
            completedBarsInStage = 0
        case .endTraining:
            endRamp()
        case .cancel:
            break
        }
    }

    func endRamp(cancelled: Bool = false) {
        rampState = cancelled ? .cancelled : .idle
        rampSettings = nil
        completedBarsInStage = 0
        completedCountInBars = 0
        awaitingRampBoundary = false
        hasSeenRampBoundary = false
        stateBeforePauseOrInterruption = nil
        interruptionRecoveryAvailable = false
        if let subdivisionBeforeCountIn { engine.setSubdivision(subdivisionBeforeCountIn) }
        subdivisionBeforeCountIn = nil
    }

    func setPlaybackForTesting(_ value: Bool) { playbackOverride = value }

    private var isPlaying: Bool { playbackOverride ?? engine.isPlaying }

    private func queueUpcomingRampTempoIfNeeded(_ settings: TempoRampSettings) {
        guard rampState == .running,
              completedBarsInStage == settings.barsPerStage - 1,
              currentStageBPM < settings.targetBPM else { return }
        engine.queueBpmAtNextBar(min(settings.targetBPM, currentStageBPM + settings.stepBPM))
    }
}
