import Foundation
import Testing
@testable import foxgita

private struct ApplyBoom: Error {}

@MainActor
struct AudioSessionCoordinatorTests {
    @Test func acquireFailureRollsBackCount() {
        let coordinator = AudioSessionCoordinator(apply: { throw ApplyBoom() })
        #expect(throws: ApplyBoom.self) {
            try coordinator.acquire(.playback)
        }
        #expect(coordinator.count(for: .playback) == 0)
        #expect(coordinator.count(for: .record) == 0)
    }

    @Test func pairedAcquireReleaseClearsNeeds() throws {
        let coordinator = AudioSessionCoordinator(apply: { })
        try coordinator.acquire(.playback)
        #expect(coordinator.count(for: .playback) == 1)
        coordinator.release(.playback)
        #expect(coordinator.count(for: .playback) == 0)
    }

    @Test func recordNeedKeepsPlayAndRecordWhenPlaybackAcquired() throws {
        let coordinator = AudioSessionCoordinator(apply: { })
        try coordinator.acquire(.record)
        try coordinator.acquire(.playback)
        #expect(coordinator.prefersPlayAndRecord)
        coordinator.release(.playback)
        #expect(coordinator.prefersPlayAndRecord)
        coordinator.release(.record)
        #expect(!coordinator.prefersPlayAndRecord)
    }

    @Test func overlappingPlaybackNeeds() throws {
        let coordinator = AudioSessionCoordinator(apply: { })
        try coordinator.acquire(.playback)
        try coordinator.acquire(.playback)
        #expect(coordinator.count(for: .playback) == 2)
        coordinator.release(.playback)
        #expect(coordinator.count(for: .playback) == 1)
        coordinator.release(.playback)
        #expect(coordinator.count(for: .playback) == 0)
    }

    @Test func interruptionObserversReceiveBeganAndEndedIndependently() throws {
        let coordinator = AudioSessionCoordinator(apply: { })
        var first: [AudioSessionCoordinator.InterruptionEvent] = []
        var second: [AudioSessionCoordinator.InterruptionEvent] = []
        let firstToken = coordinator.addInterruptionObserver { first.append($0) }
        _ = coordinator.addInterruptionObserver { second.append($0) }
        try coordinator.acquire(.playback)

        coordinator.notifyInterruptionForTesting(.began)
        coordinator.removeInterruptionObserver(firstToken)
        coordinator.notifyInterruptionForTesting(.ended(shouldResume: true))

        #expect(first == [.began])
        #expect(second == [.began, .ended(shouldResume: true)])
        #expect(coordinator.count(for: .playback) == 0)
    }

    @Test func interruptionObserverMayRemoveItselfWhileBeingNotified() {
        let coordinator = AudioSessionCoordinator(apply: {})
        var token: UUID?
        var callCount = 0
        token = coordinator.addInterruptionObserver { _ in
            callCount += 1
            if let token { coordinator.removeInterruptionObserver(token) }
        }

        coordinator.notifyInterruptionForTesting(.began)
        coordinator.notifyInterruptionForTesting(.ended(shouldResume: true))

        #expect(callCount == 1)
    }

    @Test func routeLossAndMediaResetAreForwardedWithoutAutomaticResume() throws {
        let coordinator = AudioSessionCoordinator(apply: { })
        var events: [AudioSessionCoordinator.InterruptionEvent] = []
        _ = coordinator.addInterruptionObserver { events.append($0) }
        try coordinator.acquire(.playback)

        coordinator.notifyInterruptionForTesting(.outputRouteLost)
        #expect(coordinator.count(for: .playback) == 1)
        coordinator.notifyInterruptionForTesting(.audioServicesReset)

        #expect(events == [.outputRouteLost, .audioServicesReset])
        #expect(coordinator.count(for: .playback) == 0)
    }
}
