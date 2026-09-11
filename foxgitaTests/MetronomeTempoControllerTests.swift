import Foundation
import Testing
@testable import foxgita

@MainActor
struct MetronomeTempoControllerTests {
    @Test func tapEstimatorPublishesPreviewThenStableValue() {
        var attempt = TapTempoAttempt()
        #expect(attempt.registerTap(at: 0) == nil)
        #expect(attempt.registerTap(at: 0.5) == 120)
        #expect(attempt.isStable == false)
        _ = attempt.registerTap(at: 1.0)
        #expect(attempt.registerTap(at: 1.5) == 120)
        #expect(attempt.isStable)
    }

    @Test func tapEstimatorRejectsOutlierAndResetsAfterTwoSeconds() {
        var attempt = TapTempoAttempt()
        [0.0, 0.5, 1.0, 1.9, 2.4].forEach { _ = attempt.registerTap(at: $0) }
        #expect(attempt.estimatedBPM == 120)
        #expect(attempt.registerTap(at: 4.5) == nil)
        #expect(attempt.tapCount == 1)
    }

    @Test func invalidTapIsRejectedWithoutReplacingLastValidSample() {
        var attempt = TapTempoAttempt()
        _ = attempt.registerTap(at: 0)
        #expect(attempt.registerTap(at: 0.1) == nil)
        #expect(attempt.rejectedCount == 1)
        #expect(attempt.tapCount == 1)
        #expect(attempt.registerTap(at: 0.5) == 120)
    }

    @Test func fastestValidTapPreviewsRawTempoBeforeAdoptionClamp() {
        var attempt = TapTempoAttempt()
        _ = attempt.registerTap(at: 0)
        #expect(attempt.registerTap(at: 0.25) == 240)
    }

    @Test func applyingTapWhilePlayingWaitsForAudibleBarBoundary() {
        let engine = MetronomeEngine(session: AudioSessionCoordinator(apply: { }))
        let controller = MetronomeTempoController(engine: engine)
        controller.setPlaybackForTesting(true)
        controller.applyMeasuredTempo(112)
        #expect(engine.bpm == 80)
        #expect(controller.pendingTempo == 112)
        controller.handleAudibleBeat(beat: 1, bar: 0)
        #expect(engine.bpm == 80)
        controller.handleAudibleBeat(beat: 0, bar: 1)
        #expect(engine.bpm == 112)
        #expect(controller.pendingTempo == nil)
    }

    @Test func continuingTapRevokesPendingBoundaryChange() {
        let engine = MetronomeEngine(session: AudioSessionCoordinator(apply: { }))
        let controller = MetronomeTempoController(engine: engine)
        controller.setPlaybackForTesting(true)
        controller.applyMeasuredTempo(112)
        #expect(controller.pendingTempo == 112)
        _ = controller.registerTap(at: 0)
        #expect(controller.pendingTempo == nil)
    }

    @Test func rampAdvancesAfterCompleteIntervalsAndHoldsAtTarget() {
        let engine = MetronomeEngine(session: AudioSessionCoordinator(apply: { }))
        let controller = MetronomeTempoController(engine: engine)
        controller.startRamp(
            TempoRampSettings(startBPM: 80, targetBPM: 90, barsPerStage: 2, stepBPM: 5, countInBars: 0)
        )
        #expect(controller.rampState == .running)
        #expect(engine.bpm == 80)
        controller.handleAudibleBeat(beat: 0, bar: 0)
        controller.handleAudibleBeat(beat: 0, bar: 1)
        #expect(engine.bpm == 80)
        controller.handleAudibleBeat(beat: 0, bar: 2)
        #expect(engine.bpm == 85)
        controller.handleAudibleBeat(beat: 0, bar: 3)
        controller.handleAudibleBeat(beat: 0, bar: 4)
        #expect(engine.bpm == 90)
        controller.handleAudibleBeat(beat: 0, bar: 5)
        controller.handleAudibleBeat(beat: 0, bar: 6)
        #expect(controller.rampState == .targetHold)
        #expect(engine.bpm == 90)
        #expect(controller.completedBars == 6)
        #expect(controller.completedStageCount == 3)
        #expect(controller.stableMaxBPM == 90)
    }

    @Test func countInUsesPrimaryBeatThenRestoresSubdivision() {
        let engine = MetronomeEngine(session: AudioSessionCoordinator(apply: { }))
        engine.setSubdivision(.twoEighths)
        let controller = MetronomeTempoController(engine: engine)
        controller.startRamp(
            TempoRampSettings(startBPM: 80, targetBPM: 90, barsPerStage: 2, stepBPM: 5, countInBars: 1)
        )
        #expect(controller.rampState == .countIn)
        #expect(engine.subdivision == .quarter)
        #expect(controller.registerTap(at: 0) == nil)
        #expect(controller.tapAttempt.tapCount == 0)

        controller.handleAudibleBeat(beat: 0, bar: 0)
        controller.handleAudibleBeat(beat: 0, bar: 1)

        #expect(controller.rampState == .running)
        #expect(engine.subdivision == .twoEighths)
        #expect(controller.completedBars == 0)
    }

    @Test func pauseAndInterruptionDiscardOnlyPartialStageProgress() {
        let engine = MetronomeEngine(session: AudioSessionCoordinator(apply: { }))
        let controller = MetronomeTempoController(engine: engine)
        controller.startRamp(
            TempoRampSettings(startBPM: 80, targetBPM: 90, barsPerStage: 4, stepBPM: 5, countInBars: 0)
        )
        controller.handleAudibleBeat(beat: 0, bar: 0)
        controller.handleAudibleBeat(beat: 0, bar: 1)
        #expect(controller.completedBarsInStage == 1)
        #expect(controller.completedBars == 1)

        controller.pauseRamp()
        #expect(controller.completedBarsInStage == 0)
        #expect(controller.completedBars == 1)
        #expect(controller.pauseCount == 1)
        controller.resumeRamp()
        controller.handleInterruption()
        #expect(controller.rampState == .interrupted)
        #expect(controller.interruptionCount == 1)
        #expect(controller.didRequireUserResume)
    }

    @Test func rampValidationRequiresAscendingPlan() {
        #expect(TempoRampSettings(startBPM: 100, targetBPM: 100).validationError != nil)
        #expect(TempoRampSettings(startBPM: 100, targetBPM: 120).validationError == nil)
    }
}
