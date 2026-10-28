import Foundation

enum PracticeCountdownPhase: Equatable, Sendable {
    case inactive
    case running
    case paused
    case completed
}

/// Wall-clock countdown for the current practice visit. This state is kept
/// separate from `PracticeTimer`, which remains the durable elapsed-time fact.
@Observable
final class PracticeCountdown {
    private(set) var phase: PracticeCountdownPhase = .inactive
    private(set) var configuredSeconds: Int
    private(set) var remainingSeconds: Int
    private(set) var reminderEnabled = false
    private(set) var completionDate: Date?
    @ObservationIgnored var onCompletion: (() -> Void)?

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var deadline: Date?
    @ObservationIgnored private var ticker: Timer?

    init(defaultMinutes: Int, now: @escaping () -> Date = Date.init) {
        let minutes = min(60, max(1, defaultMinutes))
        let seconds = minutes * 60
        configuredSeconds = seconds
        remainingSeconds = seconds
        self.now = now
    }

    var display: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var isActive: Bool { phase != .inactive }
    var remainingTimeInterval: TimeInterval {
        deadline.map { max(0, $0.timeIntervalSince(now())) } ?? TimeInterval(remainingSeconds)
    }

    func applyPlan(minutes: Int, reminderEnabled: Bool, startImmediately: Bool) {
        stopTicker()
        completionDate = nil
        let clampedMinutes = min(60, max(1, minutes))
        configuredSeconds = clampedMinutes * 60
        remainingSeconds = configuredSeconds
        self.reminderEnabled = reminderEnabled
        deadline = nil
        phase = .paused
        if startImmediately { start() }
    }

    func start() {
        guard phase != .running else { return }
        completionDate = nil
        deadline = now().addingTimeInterval(TimeInterval(remainingSeconds))
        phase = .running
        startTicker()
    }

    func pause() {
        guard phase == .running else { return }
        refresh()
        guard phase == .running else { return }
        deadline = nil
        phase = .paused
        stopTicker()
    }

    func resume() {
        guard phase == .paused, remainingSeconds > 0 else { return }
        start()
    }

    func reset() {
        stopTicker()
        completionDate = nil
        deadline = nil
        remainingSeconds = configuredSeconds
        phase = .paused
    }

    func restart() {
        remainingSeconds = configuredSeconds
        phase = .paused
        start()
    }

    func complete() {
        guard phase == .running else { return }
        stopTicker()
        completionDate = deadline ?? now()
        deadline = nil
        remainingSeconds = 0
        phase = .completed
        onCompletion?()
    }

    func close() {
        stopTicker()
        completionDate = nil
        deadline = nil
        remainingSeconds = configuredSeconds
        reminderEnabled = false
        phase = .inactive
    }

    func refresh() {
        guard phase == .running, let deadline else { return }
        remainingSeconds = max(0, Int(ceil(deadline.timeIntervalSince(now()))))
        if remainingSeconds == 0 {
            complete()
        }
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
