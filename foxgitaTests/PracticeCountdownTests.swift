import Foundation
import Testing

@testable import foxgita

@MainActor
struct PracticeCountdownTests {
    private final class FakeClock {
        var now = Date(timeIntervalSince1970: 1_700_000_000)

        func advance(_ seconds: TimeInterval) {
            now += seconds
        }
    }

    @Test func remainingTimeComesFromTheWallClock() {
        let clock = FakeClock()
        let countdown = PracticeCountdown(defaultMinutes: 10, now: { clock.now })

        countdown.start()
        clock.advance(61)
        countdown.refresh()

        #expect(countdown.phase == .running)
        #expect(countdown.remainingSeconds == 539)
        #expect(countdown.display == "08:59")
    }

    @Test func pausedTimeDoesNotReduceTheRemainingDuration() {
        let clock = FakeClock()
        let countdown = PracticeCountdown(defaultMinutes: 5, now: { clock.now })

        countdown.start()
        clock.advance(30)
        countdown.pause()
        clock.advance(300)
        countdown.resume()
        clock.advance(15)
        countdown.refresh()

        #expect(countdown.phase == .running)
        #expect(countdown.remainingSeconds == 255)
    }

    @Test func applyingAndResettingAPlanNeverChangesPracticeElapsedTime() {
        let clock = FakeClock()
        let countdown = PracticeCountdown(defaultMinutes: 90, now: { clock.now })

        #expect(countdown.configuredSeconds == 3_600)
        countdown.applyPlan(minutes: 5, reminderEnabled: true, startImmediately: true)
        clock.advance(40)
        countdown.pause()
        countdown.reset()

        #expect(countdown.phase == .paused)
        #expect(countdown.remainingSeconds == 300)
        #expect(countdown.reminderEnabled)

        countdown.close()
        #expect(countdown.phase == .inactive)
        #expect(!countdown.isActive)
    }

    @Test func completionFiresOncePerRunAndCanStartAgain() {
        let clock = FakeClock()
        let countdown = PracticeCountdown(defaultMinutes: 1, now: { clock.now })
        var completionCount = 0
        countdown.onCompletion = { completionCount += 1 }

        countdown.start()
        clock.advance(60)
        countdown.refresh()
        countdown.refresh()

        #expect(countdown.phase == .completed)
        #expect(countdown.remainingSeconds == 0)
        #expect(completionCount == 1)

        countdown.restart()
        clock.advance(60)
        countdown.refresh()
        #expect(completionCount == 2)
    }

    @Test func countdownNotificationIdentifierRoundTripsPracticeItem() {
        let itemId = UUID()
        let identifier = CountdownReminderScheduler.identifier(itemId: itemId)

        #expect(CountdownReminderScheduler.itemId(from: identifier) == itemId)
        #expect(CountdownReminderScheduler.itemId(from: ReminderScheduler.identifier) == nil)
    }
}
