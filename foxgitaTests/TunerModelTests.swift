import Foundation
import Testing
@testable import foxgita

@MainActor
private final class TestTunerAudio: TunerAudioIO {
    var onObservation: ((TunerAudioObservation) -> Void)?
    var captureID = UUID()
    var now = 100.0

    func emit(_ pitch: TunerPitchEstimate?, at time: TimeInterval? = nil, capturedAt: TimeInterval? = nil, runID: UUID? = nil, sampleRate: Double = 48_000) {
        now = time ?? (now + 0.02)
        onObservation?(TunerAudioObservation(pitch: pitch, capturedAt: capturedAt ?? now, sampleRate: sampleRate, runID: runID ?? captureID))
    }
    func emitStable(_ pitch: TunerPitchEstimate?) {
        let start = now + 0.02
        for step in 0...30 { emit(pitch, at: start + Double(step) * 0.02) }
    }

    var onFailure: ((String) -> Void)?
    var permitted = true
    var permissionContinuation: CheckedContinuation<Bool, Never>?
    var delayPermission = false
    var captureStarts = 0
    var capturing = false
    var toneFrequency: Double?
    var toneCompletion: (() -> Void)?
    var failStart = false

    func requestPermission() async -> Bool {
        if delayPermission { return await withCheckedContinuation { permissionContinuation = $0 } }
        return permitted
    }
    func startCapture() throws {
        if failStart { throw CocoaError(.fileReadUnknown) }
        captureID = UUID()
        captureStarts += 1
        capturing = true
    }
    func stopCapture() { capturing = false }
    func playReference(frequency: Double, completion: @escaping () -> Void) throws {
        toneFrequency = frequency
        toneCompletion = completion
    }
    func stopReference() { toneFrequency = nil; toneCompletion = nil }
}

@MainActor
struct TunerModelTests {
    @Test func aHighQualityNonCandidateUsesTheSameHoldAsWeakInput() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        audio.emitStable(TunerPitchEstimate(frequency: 82.4069, confidence: 0.99))
        let previous = model.displayedCents
        audio.emit(TunerPitchEstimate(frequency: 60, confidence: 0.99))
        #expect(model.frequency == nil)
        #expect(model.displayedCents == previous)
        #expect(model.isHoldingReading)
        #expect(model.intonation == nil)
    }

    @Test func isolatedLargeJumpIsWithheldButPersistentManualOctaveRemainsReal() async throws {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        model.selectString(6)
        audio.emitStable(TunerPitchEstimate(frequency: 82.4069, confidence: 0.99))
        let octave = TunerPitchEstimate(frequency: 164.8138, confidence: 0.99)
        audio.emit(octave)
        #expect(model.frequency == nil)
        #expect(model.intonation == nil)
        audio.emit(octave)
        #expect(abs(try #require(model.cents) - 1200) < 0.01)
        #expect(model.intonation == .high)
    }

    @Test func recognitionExpiresWhenTheObservationStreamStops() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        audio.emit(TunerPitchEstimate(frequency: 195.9977, confidence: 0.99))
        #expect(model.isRecognizingString)
        audio.now += 0.2
        model.expireReading(at: audio.now)
        #expect(!model.isRecognizingString)
        #expect(model.isSignalUnclear)
        audio.emitStable(TunerPitchEstimate(frequency: 195.9977, confidence: 0.99))
        #expect(model.selectedStringNumber == 3)
        #expect(model.frequency != nil)
    }

    @Test func replayDuringReferenceDecayPreservesTheOriginalListeningIntent() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        model.toggleReferenceTone()
        audio.toneCompletion?()
        model.toggleReferenceTone()
        audio.toneCompletion?()
        audio.now += 0.25
        model.expireReading(at: audio.now)
        for _ in 0..<20 where !audio.capturing { await Task.yield() }
        #expect(audio.capturing)
    }

    @Test func centreCrossingAndEvidenceGapsNeverEarnAConfirmation() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        model.selectString(6)
        for step in 0...50 {
            let cents = -20 + 0.8 * Double(step)
            audio.emit(TunerPitchEstimate(frequency: 82.4069 * pow(2, cents / 1200), confidence: 0.99), at: 100.02 + Double(step) * 0.02)
            #expect(model.intonation != .inTune)
        }
        model.selectString(6)
        let pitch = TunerPitchEstimate(frequency: 82.4069, confidence: 0.99)
        let origin = audio.now + 0.02
        for step in 0...10 { audio.emit(pitch, at: origin + Double(step) * 0.02) }
        audio.emit(pitch, at: origin + 0.6)
        #expect(model.intonation != .inTune)
        audio.emit(pitch, at: origin + 0.62, capturedAt: origin + 0.6)
        #expect(model.intonation != .inTune)
        audio.emitStable(pitch)
        #expect(model.intonation == .inTune)
    }

    @Test func confirmedReadingRevokesOnRawDeviationAndRejectsPreSettingSamples() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        audio.emitStable(TunerPitchEstimate(frequency: 82.4069, confidence: 0.99))
        #expect(model.intonation == .inTune)
        audio.emit(TunerPitchEstimate(frequency: 82.4069 * pow(2, 9.0 / 1200), confidence: 0.99))
        #expect(model.intonation != .inTune)
        let oldTime = audio.now
        audio.now += 0.02
        model.setCalibration(442)
        audio.emit(TunerPitchEstimate(frequency: 82.4069, confidence: 0.99), capturedAt: oldTime)
        #expect(model.frequency == nil)
        #expect(model.intonation == nil)
    }

    @Test func continuousMovementHasSimilarLagAtDifferentObservationRates() async throws {
        var readings: [Double] = []
        for interval in [0.02, 0.04] {
            let (model, audio, _) = fixture()
            await model.start()
            model.selectString(6)
            for step in 0...Int(2 / interval) {
                let elapsed = Double(step) * interval
                audio.emit(TunerPitchEstimate(frequency: 82.4069 * pow(2, 40 * elapsed / 1200), confidence: 0.99), at: 100.02 + elapsed)
            }
            let cents = try #require(model.cents)
            #expect(abs(cents - 80) < 5)
            readings.append(cents)
            model.stop()
        }
        #expect(abs(readings[0] - readings[1]) < 1.5)
    }

    @Test func ordinaryNoiseProxyCannotLockOrConfirmAString() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        var seed: UInt64 = 42
        let rate = 48_000.0
        let samples: [Float] = (0..<96_000).map { index in
            seed = seed &* 6364136223846793005 &+ 1
            let noise = Double(seed >> 32) / Double(UInt32.max) - 0.5
            let time = Double(index) / rate
            return Float(0.003 * noise + 0.006 * sin(2 * .pi * 60 * time) + 0.002 * sin(2 * .pi * 120 * time))
        }
        for end in stride(from: 4096, through: samples.count, by: 1024) {
            let pitch = TunerPitchDetector.estimate(samples: Array(samples[(end - 4096)..<end]), sampleRate: rate)
            audio.emit(pitch, at: 100 + Double(end) / rate)
            #expect(model.intonation != .inTune)
            #expect(model.frequency == nil)
        }
        audio.emitStable(TunerPitchEstimate(frequency: 110, confidence: 0.99))
        #expect(model.selectedStringNumber == 5)
        #expect(model.intonation == .inTune)
    }

    @Test func referenceResumeWaitsForIsolationAndDoesNotAcceptItsOwnResidual() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        model.toggleReferenceTone()
        audio.toneCompletion?()
        for _ in 0..<20 { await Task.yield() }
        #expect(!audio.capturing)
        audio.now += 0.25
        model.expireReading(at: audio.now)
        for _ in 0..<20 where !audio.capturing { await Task.yield() }
        #expect(audio.capturing)
        audio.emitStable(TunerPitchEstimate(frequency: 82.4069, confidence: 0.99))
        #expect(model.frequency == nil)
        #expect(model.intonation == nil)
        audio.emit(nil)
        audio.emitStable(TunerPitchEstimate(frequency: 82.4069, confidence: 0.99))
        #expect(model.frequency != nil)
    }

    @Test func inTuneNeedsStableFreshEvidenceAndCannotSurviveSignalLoss() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        model.selectString(6)
        let pitch = TunerPitchEstimate(frequency: 82.4069, confidence: 0.99)
        audio.emit(pitch, at: 100.02)
        #expect(model.intonation == nil)
        for step in 1...19 { audio.emit(pitch, at: 100.02 + Double(step) * 0.02) }
        #expect(model.intonation == nil)
        audio.emit(pitch, at: 100.44)
        #expect(model.intonation == .inTune)
        audio.emit(nil, at: 100.46)
        #expect(model.intonation == nil)
        audio.emit(pitch, at: 100.48)
        #expect(model.intonation == nil)
    }

    @Test func weakTailBrieflyShowsPreviousReadingWithoutLiveAdviceThenExpires() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        audio.emitStable(TunerPitchEstimate(frequency: 110, confidence: 0.99))
        let previous = model.displayedCents
        audio.emit(TunerPitchEstimate(frequency: 112, confidence: 0.90))
        #expect(model.frequency == nil)
        #expect(model.cents == nil)
        #expect(model.intonation == nil)
        #expect(model.displayedCents == previous)
        #expect(model.isSignalUnclear)
        audio.now += 0.31
        model.expireReading(at: audio.now)
        #expect(model.displayedCents == nil)
        #expect(model.isSignalUnclear)
        audio.emitStable(TunerPitchEstimate(frequency: 110, confidence: 0.99))
        #expect(model.frequency != nil)
        #expect(!model.isSignalUnclear)
    }

    @Test func automaticStringRequiresContinuousEvidenceBeforeLockAndSwitch() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        audio.emit(TunerPitchEstimate(frequency: 82.4069, confidence: 0.99), at: 100)
        #expect(model.frequency == nil)
        for time in [100.02, 100.04, 100.06, 100.08, 100.10] {
            audio.emit(TunerPitchEstimate(frequency: 82.4069, confidence: 0.99), at: time)
        }
        #expect(model.selectedStringNumber == 6)
        #expect(model.frequency != nil)
        audio.emit(TunerPitchEstimate(frequency: 195.9977, confidence: 0.99), at: 100.12)
        #expect(model.selectedStringNumber == 6)
        #expect(model.frequency == nil)
        for time in [100.16, 100.20, 100.24, 100.26] {
            audio.emit(TunerPitchEstimate(frequency: 195.9977, confidence: 0.99), at: time)
        }
        #expect(model.selectedStringNumber == 3)
        #expect(model.frequency != nil)
    }

    @Test func foreignFutureAndOutOfOrderObservationsCannotChangeTheReadout() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        model.selectString(6)
        let pitch = TunerPitchEstimate(frequency: 82.4069, confidence: 0.99)
        audio.emit(pitch, at: 100, runID: UUID())
        #expect(model.frequency == nil)
        audio.emit(pitch, at: 100, capturedAt: 101)
        #expect(model.frequency == nil)
        audio.emit(pitch, at: 100.02)
        let accepted = model.frequency
        #expect(accepted != nil)
        audio.emit(TunerPitchEstimate(frequency: 110, confidence: 0.99), at: 100.04, capturedAt: 99.99)
        #expect(model.frequency == accepted)
    }

    @Test func delayedObservationCannotBecomeFreshWhenItsCallbackArrives() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        audio.emit(TunerPitchEstimate(frequency: 110, confidence: 0.99), at: 100, capturedAt: 99)
        #expect(model.frequency == nil)
        #expect(model.intonation == nil)
        #expect(model.selectedStringNumber == 6)
    }

    @Test(arguments: GuitarTuning.allCases)
    func stationaryDecayingStringReadoutDoesNotFollowNoiseJitter(_ tuning: GuitarTuning) async throws {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        model.setTuning(tuning)
        let rate = 48_000.0
        for target in tuning.targets {
            model.selectString(target.number)
            let origin = audio.now + 0.02
            let fundamental = target.frequency(a4: 440)
            var seed: UInt64 = 42
            let samples: [Float] = (0..<144_000).map { i in
                let time = Double(i) / rate
                let phase = 2 * Double.pi * fundamental * time
                seed = seed &* 6364136223846793005 &+ 1
                let noise = (Double(seed >> 32) / Double(UInt32.max) - 0.5) * 0.001
                return Float(0.02 * exp(-time / 0.65) * (0.4 * sin(phase) + 0.8 * sin(2 * phase) + 0.2 * sin(3 * phase)) + noise)
            }
            var readings: [Double] = []
            for end in stride(from: 4096, through: samples.count, by: 1024) {
                let frame = Array(samples[(end - 4096)..<end])
                let estimate = TunerPitchDetector.estimate(samples: frame, sampleRate: rate)
                audio.emit(estimate, at: origin + Double(end) / rate)
                if Double(end) / rate >= 1.5, let cents = model.cents { readings.append(cents) }
            }
            #expect(readings.count >= 12, "Tail coverage: \(tuning.title), string \(target.number)")
            #expect(try #require(readings.map(abs).max()) < 2.5)
            #expect(try #require(readings.max()) - #require(readings.min()) < 4)
        }
    }

    @Test func unreliableTailCannotKeepShowingAPreciseReading() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        audio.emitStable(TunerPitchEstimate(frequency: 110, confidence: 0.99))
        #expect(model.intonation == .inTune)
        for cents in [18.0, -22, 15] {
            audio.emit(TunerPitchEstimate(frequency: 110 * pow(2, cents / 1200), confidence: 0.91))
        }
        #expect(model.frequency == nil)
        #expect(model.intonation == nil)
        #expect(model.isSignalUnclear)
        model.expireReading(at: ProcessInfo.processInfo.systemUptime + 1)
        #expect(model.isSignalUnclear)
        model.pause()
        #expect(!model.isSignalUnclear)
    }

    @Test func uncertainTailCannotSwitchTheRecognizedString() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        audio.emitStable(TunerPitchEstimate(frequency: 82.4069, confidence: 0.99))
        audio.emit(TunerPitchEstimate(frequency: 195.9977, confidence: 0.94))
        #expect(model.selectedStringNumber == 6)
    }

    @Test func quietPeriodicLowEIsDetectedBeforeItsTargetConfirmation() async throws {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        let samples: [Float] = (0..<4800).map { i in
            Float(0.0007 * sin(2 * .pi * 82.4069 * Double(i) / 48_000))
        }
        let estimate = TunerPitchDetector.estimate(samples: samples, sampleRate: 48_000)
        audio.emitStable(try #require(estimate))
        #expect(model.selectedStringNumber == 6)
        #expect(abs(try #require(model.cents)) < 3)
        #expect(!model.isSignalUnclear)
    }

    @Test func lowerConfidenceButCoherentTuningMovementStillFollows() async throws {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        for _ in 0..<3 { audio.emitStable(TunerPitchEstimate(frequency: 82.4069, confidence: 0.99)) }
        for cents in 1...24 {
            audio.emit(TunerPitchEstimate(frequency: 82.4069 * pow(2, Double(cents) / 1200), confidence: 0.96))
            #expect(abs(try #require(model.cents) - Double(cents)) < 4)
        }
    }

    @Test func livePitchChangesMoveTheReadoutOnTheNextFrame() async throws {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        for _ in 0..<3 { audio.emitStable(TunerPitchEstimate(frequency: 82.4069, confidence: 0.99)) }
        let higher = 82.4069 * pow(2, 10.0 / 1200)
        audio.emit(TunerPitchEstimate(frequency: higher, confidence: 0.99))
        #expect(try #require(model.cents) > 0)
        audio.emit(TunerPitchEstimate(frequency: higher, confidence: 0.99))
        let followedCents = try #require(model.cents)
        #expect(abs(followedCents - 10) < 2, "Two-frame readout: \(followedCents) cent")
    }

    @Test func decayingLowETracksAContinuousTuningSweep() async throws {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        let rate = 48_000.0
        var phase = 0.0
        let samples: [Float] = (0..<57_600).map { i in
            let time = Double(i) / rate
            let cents = -20 + 40 * time
            phase += 2 * .pi * 82.4069 * pow(2, cents / 1200) / rate
            return Float(0.002 * exp(-time / 1.5) * (0.4 * sin(phase) + 0.8 * sin(2 * phase) + 0.2 * sin(3 * phase)))
        }
        for time in stride(from: 0.12, through: 1.08, by: 0.04) {
            let end = Int(time * rate)
            let frame = Array(samples[(end - 4096)..<end])
            let estimate = TunerPitchDetector.estimate(samples: frame, sampleRate: rate)
            audio.emit(try #require(estimate), at: 100 + time)
            #expect(model.selectedStringNumber == 6)
            if time >= 0.24 { #expect(abs(try #require(model.cents) - (-20 + 40 * time)) < 5) }
        }
    }

    private func fixture() -> (TunerModel, TestTunerAudio, AudioSessionCoordinator) {
        let audio = TestTunerAudio()
        let session = AudioSessionCoordinator(apply: {})
        return (TunerModel(audio: audio, session: session, now: { audio.now }), audio, session)
    }

    @Test func permissionDenialNeverStartsCapture() async {
        let (model, audio, _) = fixture()
        audio.permitted = false
        await model.start()
        defer { model.stop() }
        #expect(model.status == .permissionDenied)
        #expect(audio.captureStarts == 0)
    }

    @Test func leavingWhilePermissionIsPendingCannotRestartCapture() async {
        let (model, audio, _) = fixture()
        audio.delayPermission = true
        let start = Task { await model.start() }
        for _ in 0..<20 where audio.permissionContinuation == nil { await Task.yield() }
        model.stop()
        audio.permissionContinuation?.resume(returning: true)
        await start.value
        #expect(audio.captureStarts == 0)
        #expect(model.status == .idle)
    }

    @Test func automaticDetectionSelectsTheRealStringAndReportsCents() async throws {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        audio.emitStable(TunerPitchEstimate(frequency: 246.9417 * pow(2, -8.0 / 1200), confidence: 0.99))
        #expect(model.selectedStringNumber == 2)
        #expect(abs(try #require(model.cents) + 8) < 0.1)
        #expect(model.intonation == .low)
    }

    @Test func manualSelectionKeepsTheTargetAndNeverFoldsOctaves() async throws {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        model.selectString(6)
        audio.emit(TunerPitchEstimate(frequency: 164.8138, confidence: 0.99))
        #expect(!model.automatic)
        #expect(model.selectedStringNumber == 6)
        #expect(abs(try #require(model.cents) - 1200) < 0.1)
        #expect(model.intonation == .high)
    }

    @Test func staleAndInvalidMeasurementsCannotStayGreen() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        audio.emitStable(TunerPitchEstimate(frequency: 110, confidence: 0.99))
        #expect(model.intonation == .inTune)
        model.expireReading(at: ProcessInfo.processInfo.systemUptime + 1)
        #expect(model.frequency == nil)
        audio.emit(TunerPitchEstimate(frequency: .nan, confidence: 1))
        #expect(model.frequency == nil)
    }

    @Test func interruptionAndExitRejectOldAudioCallbacks() async {
        let (model, audio, session) = fixture()
        await model.start()
        let oldCallback = audio.onObservation
        session.notifyInterruptionForTesting(.began)
        #expect(model.status == .interrupted)
        #expect(!audio.capturing)
        oldCallback?(TunerAudioObservation(pitch: TunerPitchEstimate(frequency: 110, confidence: 1), capturedAt: audio.now, sampleRate: 48_000, runID: audio.captureID))
        #expect(model.frequency == nil)
        session.notifyInterruptionForTesting(.ended(shouldResume: true))
        #expect(audio.captureStarts == 1)
        model.stop()
        oldCallback?(TunerAudioObservation(pitch: TunerPitchEstimate(frequency: 110, confidence: 1), capturedAt: audio.now, sampleRate: 48_000, runID: audio.captureID))
        #expect(model.status == .idle)
        #expect(model.frequency == nil)
    }

    @Test func referenceTonePausesMicrophoneAndExitCancelsItsCompletion() async {
        let (model, audio, _) = fixture()
        await model.start()
        model.toggleReferenceTone()
        #expect(!audio.capturing)
        #expect(model.status == .referenceTone)
        #expect(abs((audio.toneFrequency ?? 0) - 82.4069) < 0.001)
        let completion = audio.toneCompletion
        model.stop()
        completion?()
        await Task.yield()
        #expect(model.status == .idle)
        #expect(audio.captureStarts == 1)
    }

    @Test(arguments: [false, true])
    func queuedToneResumeCannotReopenMicrophoneAfterExit(_ manualStop: Bool) async {
        let (model, audio, _) = fixture()
        await model.start()
        model.toggleReferenceTone()
        if manualStop { model.toggleReferenceTone() }
        else { audio.toneCompletion?() }
        model.stop()
        for _ in 0..<10 { await Task.yield() }
        #expect(model.status == .idle)
        #expect(!audio.capturing)
        #expect(audio.captureStarts == 1)
    }

    @Test func queuedToneResumeCannotOverrideInterruption() async {
        let (model, audio, session) = fixture()
        await model.start()
        model.toggleReferenceTone()
        audio.toneCompletion?()
        session.notifyInterruptionForTesting(.began)
        for _ in 0..<10 { await Task.yield() }
        #expect(model.status == .interrupted)
        #expect(!audio.capturing)
        #expect(audio.captureStarts == 1)
        model.stop()
    }

    @Test(arguments: [false, true])
    func referenceToneResumesListeningWhenPageRemainsActive(_ manualStop: Bool) async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        model.toggleReferenceTone()
        if manualStop { model.toggleReferenceTone() }
        else { audio.toneCompletion?() }
        audio.now += 0.25
        model.expireReading(at: audio.now)
        for _ in 0..<20 where model.status != .listening { await Task.yield() }
        #expect(model.status == .listening)
        #expect(audio.capturing)
        #expect(audio.captureStarts == 2)
    }

    @Test func backgroundPauseCancelsQueuedToneResume() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        model.toggleReferenceTone()
        audio.toneCompletion?()
        model.pause()
        for _ in 0..<10 { await Task.yield() }
        #expect(model.status == .paused)
        #expect(!audio.capturing)
        #expect(audio.captureStarts == 1)
    }

    @Test(arguments: [AudioSessionCoordinator.InterruptionEvent.outputRouteLost, .audioServicesReset])
    func audioDeviceChangesStopInputAndReferenceTone(_ event: AudioSessionCoordinator.InterruptionEvent) async {
        let (model, audio, session) = fixture()
        await model.start()
        defer { model.stop() }
        model.toggleReferenceTone()
        session.notifyInterruptionForTesting(event)
        #expect(model.status == .interrupted)
        #expect(!audio.capturing)
        #expect(audio.toneFrequency == nil)
        await model.start()
        #expect(model.status == .listening)
        session.notifyInterruptionForTesting(event)
        #expect(model.status == .interrupted)
        #expect(!audio.capturing)
    }

    @Test func calibrationAndTuningUpdateTargetsAndClearOldReadings() async {
        let (model, audio, _) = fixture()
        await model.start()
        defer { model.stop() }
        audio.emitStable(TunerPitchEstimate(frequency: 82.4069, confidence: 0.99))
        model.setCalibration(442)
        #expect(model.calibrationA4 == 442)
        #expect(model.frequency == nil)
        model.setCalibration(.nan)
        #expect(model.calibrationA4 == 442)
        model.setCalibration(900)
        #expect(model.calibrationA4 == 450)
        model.setTuning(.dropD)
        #expect(model.target.noteLabel == "D₂")
        #expect(model.frequency == nil)
    }

    @Test func failedCaptureIsVisibleAndCanBeRetried() async {
        let (model, audio, _) = fixture()
        audio.failStart = true
        await model.start()
        #expect(model.status == .failed)
        #expect(!audio.capturing)
        audio.failStart = false
        await model.start()
        #expect(model.status == .listening)
        model.pause()
        #expect(!audio.capturing)
        #expect(model.status == .paused)
        model.stop()
    }
}
