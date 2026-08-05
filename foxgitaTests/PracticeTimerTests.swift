//
//  PracticeTimerTests.swift
//  foxgitaTests
//

import Foundation
import Testing

@testable import foxgita

@MainActor
struct PracticeTimerTests {
    /// Advances only when the test says so, standing in for the wall clock.
    private final class FakeClock {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        func advance(_ seconds: TimeInterval) { now += seconds }
    }

    private func makeTimer() -> (PracticeTimer, FakeClock) {
        let clock = FakeClock()
        return (PracticeTimer(now: { clock.now }), clock)
    }

    @Test func elapsedComesFromTheClockNotFromTicks() {
        let (timer, clock) = makeTimer()
        timer.start()
        clock.advance(125)
        timer.refresh()
        #expect(timer.elapsedSec == 125)
        #expect(timer.display == "02:05")
    }

    /// The bug this design replaces: a per-tick counter loses everything that
    /// happens while the app is suspended.
    @Test func timeSpentSuspendedStillCounts() {
        let (timer, clock) = makeTimer()
        timer.start()
        clock.advance(300)
        timer.pause()
        #expect(timer.elapsedSec == 300)
    }

    @Test func pausedTimeIsExcluded() {
        let (timer, clock) = makeTimer()
        timer.start()
        clock.advance(60)
        timer.pause()
        clock.advance(600)
        timer.start()
        clock.advance(30)
        timer.pause()
        #expect(timer.elapsedSec == 90)
    }

    @Test func startedAtSurvivesPauses() {
        let (timer, clock) = makeTimer()
        let begin = clock.now
        timer.start()
        clock.advance(60)
        timer.pause()
        clock.advance(60)
        timer.start()
        #expect(timer.startedAt == begin)
    }

    @Test func resetClearsEverything() {
        let (timer, clock) = makeTimer()
        timer.start()
        clock.advance(90)
        timer.reset()
        #expect(timer.elapsedSec == 0)
        #expect(timer.startedAt == nil)
        #expect(timer.isRunning == false)
    }

    @Test func startIsIdempotent() {
        let (timer, clock) = makeTimer()
        timer.start()
        clock.advance(10)
        timer.start()
        clock.advance(10)
        timer.pause()
        #expect(timer.elapsedSec == 20)
    }
}
