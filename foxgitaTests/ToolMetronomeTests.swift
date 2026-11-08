import Foundation
import Testing
@testable import foxgita

@MainActor
struct ToolMetronomeTests {
    @Test func failedStartReportsErrorAndReleasesAudioSession() {
        enum TestError: Error { case unavailable }
        let session = AudioSessionCoordinator(apply: { throw TestError.unavailable })
        let model = ToolMetronomeModel(session: session)
        model.activate()
        defer { model.deactivate() }
        model.togglePlayback()
        #expect(!model.engine.isPlaying)
        #expect(model.playbackError != nil)
        #expect(session.count(for: .playback) == 0)
    }

    @Test func deactivationClearsPendingTempoAndStopsPlayback() throws {
        let session = AudioSessionCoordinator(apply: { })
        let model = ToolMetronomeModel(session: session)
        model.activate()
        model.togglePlayback()
        #expect(model.engine.isPlaying)
        model.controller.applyMeasuredTempo(112)
        #expect(model.controller.pendingTempo == 112)
        model.deactivate()
        #expect(!model.engine.isPlaying)
        #expect(!model.engine.hasPump)
        #expect(model.controller.pendingTempo == nil)
        #expect(session.count(for: .playback) == 0)
    }

    @Test func interruptionStopsWithoutAutomaticallyRestarting() {
        let session = AudioSessionCoordinator(apply: { })
        let model = ToolMetronomeModel(session: session)
        model.activate()
        defer { model.deactivate() }
        model.togglePlayback()
        #expect(model.engine.isPlaying)
        model.controller.applyMeasuredTempo(112)
        session.notifyInterruptionForTesting(.began)
        #expect(!model.engine.isPlaying)
        #expect(model.controller.pendingTempo == nil)
        session.notifyInterruptionForTesting(.ended(shouldResume: true))
        #expect(!model.engine.isPlaying)
        #expect(session.count(for: .playback) == 0)
    }

    @Test func routeLossStopsAndRemovesObserverOnExit() {
        let session = AudioSessionCoordinator(apply: { })
        let model = ToolMetronomeModel(session: session)
        model.activate()
        model.activate()
        model.togglePlayback()
        model.controller.applyMeasuredTempo(112)
        session.notifyInterruptionForTesting(.outputRouteLost)
        #expect(!model.engine.isPlaying)
        #expect(model.controller.pendingTempo == nil)
        model.deactivate()
        let previousError = model.playbackError
        session.notifyInterruptionForTesting(.began)
        #expect(model.playbackError == previousError)
        #expect(session.count(for: .playback) == 0)
    }

    @Test func toolConfigurationDoesNotChangeAnotherEngine() {
        let session = AudioSessionCoordinator(apply: { })
        let practiceEngine = MetronomeEngine(session: session)
        practiceEngine.setBpm(120)
        practiceEngine.setSoundPreset(.electronicMetronome)
        let model = ToolMetronomeModel(session: session)
        model.controller.setTempo(95)
        #expect(model.engine.bpm == 95)
        #expect(practiceEngine.bpm == 120)
        #expect(practiceEngine.soundPreset == .electronicMetronome)
    }

    @Test(arguments: [false, true])
    func pausingSettlesAdoptedTempoWithOrWithoutBoundaryPublication(_ boundaryConsumed: Bool) {
        let session = AudioSessionCoordinator(apply: { })
        let model = ToolMetronomeModel(session: session)
        model.activate()
        defer { model.deactivate() }
        model.togglePlayback()
        model.controller.applyMeasuredTempo(112)
        if boundaryConsumed { model.engine.applyQueuedTempoForTesting() }
        model.togglePlayback()
        #expect(!model.engine.isPlaying)
        #expect(model.controller.pendingTempo == nil)
        #expect(model.engine.bpm == 112)
        model.togglePlayback()
        #expect(model.engine.isPlaying)
        #expect(model.engine.bpm == 112)
    }
}
