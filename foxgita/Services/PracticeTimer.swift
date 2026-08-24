//
//  PracticeTimer.swift
//  foxgita
//

import Foundation

/// Wall-clock practice timer. Elapsed time is derived from dates rather than
/// counted per tick, so suspending the app mid-practice does not lose minutes.
/// The clock is injectable so tests can advance time without sleeping.
@Observable
final class PracticeTimer {
    private(set) var elapsedSec = 0
    private(set) var isRunning = false
    private(set) var startedAt: Date?

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var resumedAt: Date?
    @ObservationIgnored private var ticker: Timer?

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    var display: String {
        String(format: "%02d:%02d", elapsedSec / 60, elapsedSec % 60)
    }

    func start() {
        guard !isRunning else { return }
        let instant = now()
        if startedAt == nil { startedAt = instant }
        resumedAt = instant
        isRunning = true
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
    }

    func pause() {
        stopTicker()
        guard isRunning else { return }
        accumulated += now().timeIntervalSince(resumedAt ?? now())
        resumedAt = nil
        isRunning = false
        elapsedSec = Int(accumulated)
    }

    func reset() {
        pause()
        accumulated = 0
        startedAt = nil
        elapsedSec = 0
    }

    func restore(elapsedSec: Int, startedAt: Date?) {
        stopTicker()
        isRunning = false
        resumedAt = nil
        let clamped = max(0, elapsedSec)
        accumulated = TimeInterval(clamped)
        self.elapsedSec = clamped
        if clamped == 0 {
            self.startedAt = nil
        } else {
            self.startedAt = startedAt ?? now().addingTimeInterval(-TimeInterval(clamped))
        }
    }

    /// Recomputes from the clock. Called by the display ticker and by tests.
    func refresh() {
        let running = resumedAt.map { now().timeIntervalSince($0) } ?? 0
        elapsedSec = Int(accumulated + running)
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    deinit { ticker?.invalidate() }
}
