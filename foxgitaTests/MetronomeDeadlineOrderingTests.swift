import Testing
@testable import foxgita

@MainActor
@Suite(.serialized)
struct MetronomeDeadlineOrderingTests {
    @Test func deadlineNotifiesBeforeSessionReconfiguration() async throws {
        var categoryApplications = 0
        let session = AudioSessionCoordinator(apply: { categoryApplications += 1 })
        try session.acquire(.record)
        let engine = MetronomeEngine(session: session)
        defer {
            engine.stop()
            session.release(.record)
        }
        try engine.start()
        let applicationsAtStart = categoryApplications
        var applicationsAtDeadline: Int?
        var playingAtDeadline: Bool?
        engine.armCountdownStop(after: 0.2) {
            applicationsAtDeadline = categoryApplications
            playingAtDeadline = engine.isPlaying
        }
        try await Task.sleep(for: .milliseconds(700))
        #expect(applicationsAtDeadline == applicationsAtStart)
        #expect(playingAtDeadline == false)
        #expect(!engine.hasPump)
        #expect(session.count(for: .playback) == 0)
    }

    @Test func deadlineCallbackCanRestartWithoutLosingPlaybackOwnership() async throws {
        let session = AudioSessionCoordinator(apply: { })
        let engine = MetronomeEngine(session: session)
        defer { engine.stop() }
        var didRestart = false
        var restartError: Error?
        try engine.start()
        engine.armCountdownStop(after: 0.2) {
            do {
                try engine.start()
                didRestart = true
            } catch {
                restartError = error
            }
        }
        try await Task.sleep(for: .milliseconds(700))
        #expect(restartError == nil)
        #expect(didRestart && engine.isPlaying && engine.hasPump)
        #expect(session.count(for: .playback) == 1)
    }
}
