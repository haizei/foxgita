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
}
