import Foundation
import Observation

nonisolated enum TunerStatus: Equatable {
    case idle, preparing, listening, permissionDenied, paused, interrupted, failed, referenceTone, referenceDecay
}

nonisolated enum TunerReadingState: Equatable {
    case waiting, recognizing, tracking, settling, inTune, holding, unclear
}

@MainActor @Observable
final class TunerModel {
    private(set) var status: TunerStatus = .idle
    private(set) var selectedStringNumber = 6
    private(set) var automatic = true
    private(set) var calibrationA4 = 440.0
    private(set) var tuning = GuitarTuning.standard
    private(set) var frequency: Double?
    private(set) var readingState: TunerReadingState = .waiting
    private(set) var isWaitingForReferenceSilence = false
    private var heldFrequency: Double?
    var isSignalUnclear: Bool { readingState == .holding || readingState == .unclear }
    var isRecognizingString: Bool { readingState == .recognizing }
    var isHoldingReading: Bool { readingState == .holding }
    private(set) var errorMessage: String?
    var target: TunerString { tuning.targets.first { $0.number == selectedStringNumber } ?? tuning.targets[5] }
    var targetFrequency: Double { target.frequency(a4: calibrationA4) }
    var cents: Double? { frequency.map { TunerIntonation.cents(frequency: $0, target: targetFrequency) } }
    var displayedCents: Double? {
        (frequency ?? heldFrequency).map { TunerIntonation.cents(frequency: $0, target: targetFrequency) }
    }
    var intonation: TunerIntonation? {
        guard let cents else { return nil }
        if readingState == .inTune { return .inTune }
        let direction = TunerIntonation.classify(cents: cents)
        return direction == .inTune ? nil : direction
    }

    @ObservationIgnored private let audio: TunerAudioIO
    @ObservationIgnored private let session: AudioSessionCoordinator
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var active = false
    @ObservationIgnored private var observer: UUID?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var lastPitchAt = 0.0
    @ObservationIgnored private var trackedFrequency: Double?
    @ObservationIgnored private var recentFrequencies: [Double] = []
    @ObservationIgnored private var lastObservationAt = -Double.infinity
    @ObservationIgnored private var observationSampleRate: Double?
    @ObservationIgnored private var lockedStringNumber: Int?
    @ObservationIgnored private var stringCandidate: (number: Int, since: TimeInterval, lastAt: TimeInterval)?
    @ObservationIgnored private var stableSince: TimeInterval?
    @ObservationIgnored private var lastConfirmationAt: TimeInterval?
    @ObservationIgnored private var stableRange: ClosedRange<Double>?
    @ObservationIgnored private var referenceResumeAt: TimeInterval?
    @ObservationIgnored private var resumeAfterReference = false
    @ObservationIgnored private var referenceReturnStatus = TunerStatus.paused

    init(audio: TunerAudioIO, session: AudioSessionCoordinator, defaults: UserDefaults? = nil,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.audio = audio; self.session = session; self.defaults = defaults
        self.now = now
        if let value = defaults?.object(forKey: "gita.tuner.a4") as? Double, value.isFinite {
            calibrationA4 = min(450, max(430, value))
        }
    }

    convenience init() {
        self.init(audio: TunerAudioService(), session: .shared, defaults: PracticeTestEnvironment.defaults)
    }

    func start(afterReference: Bool = false) async {
        guard status != .preparing, status != .listening else { return }
        active = true
        if observer == nil {
            observer = session.addInterruptionObserver { [weak self] event in self?.handle(event) }
        }
        generation += 1
        let attempt = generation
        stopAudio()
        clearReading()
        isWaitingForReferenceSilence = afterReference
        lastObservationAt = -Double.infinity
        observationSampleRate = nil
        errorMessage = nil
        status = .preparing
        let allowed = await audio.requestPermission()
        guard active, generation == attempt, !Task.isCancelled else { return }
        guard allowed else { status = .permissionDenied; return }
        audio.onObservation = { [weak self] observation in
            guard let self, self.active, self.generation == attempt, self.status == .listening else { return }
            let now = self.now()
            guard observation.runID == self.audio.captureID,
                  observation.capturedAt.isFinite,
                  observation.sampleRate.isFinite, (4_000...192_000).contains(observation.sampleRate),
                  observation.capturedAt > self.lastObservationAt,
                  observation.capturedAt <= now + TunerPolicy.allowedClockSkew,
                  now - observation.capturedAt <= TunerPolicy.maximumObservationAge else { return }
            if self.observationSampleRate != observation.sampleRate { self.clearReading() }
            self.observationSampleRate = observation.sampleRate
            self.lastObservationAt = observation.capturedAt
            if self.isWaitingForReferenceSilence {
                // A fixed timer alone cannot prove that speaker reverberation
                // is over. Require a new non-pitched window before accepting
                // another string, even if the residual is perfectly periodic.
                if observation.pitch == nil { self.isWaitingForReferenceSilence = false }
                self.clearReading()
                return
            }
            self.receive(observation.pitch, at: observation.capturedAt)
        }
        audio.onFailure = { [weak self] message in
            guard let self, self.active, self.generation == attempt else { return }
            self.pause()
            self.errorMessage = message
            self.status = .failed
        }
        do {
            try audio.startCapture()
            status = .listening
            monitorExpiry(attempt: attempt)
        } catch {
            stopAudio()
            errorMessage = String(localized: "无法开启麦克风，请检查音频设备后重试。")
            status = .failed
        }
    }

    func stop() {
        active = false
        pause()
        if let observer { session.removeInterruptionObserver(observer); self.observer = nil }
        status = .idle
    }

    func pause() {
        generation += 1
        stopAudio()
        clearReading()
        status = .paused
    }

    private func stopAudio() {
        expiryTask?.cancel(); expiryTask = nil
        audio.onObservation = nil; audio.onFailure = nil
        audio.stopCapture(); audio.stopReference()
        referenceResumeAt = nil
        isWaitingForReferenceSilence = false
        resumeAfterReference = false
    }

    func selectString(_ number: Int) {
        guard tuning.targets.contains(where: { $0.number == number }) else { return }
        stopToneForSettingChange()
        selectedStringNumber = number
        automatic = false
        clearReading()
        lastObservationAt = max(lastObservationAt, now())
    }

    func setAutomatic(_ value: Bool) {
        stopToneForSettingChange()
        automatic = value
        clearReading()
        lastObservationAt = max(lastObservationAt, now())
    }

    func setCalibration(_ value: Double) {
        guard value.isFinite else { return }
        stopToneForSettingChange()
        calibrationA4 = min(450, max(430, value))
        defaults?.set(calibrationA4, forKey: "gita.tuner.a4")
        clearReading()
        lastObservationAt = max(lastObservationAt, now())
    }

    func setTuning(_ value: GuitarTuning) {
        stopToneForSettingChange()
        tuning = value
        clearReading()
        lastObservationAt = max(lastObservationAt, now())
    }

    private func stopToneForSettingChange() {
        if status == .referenceTone || status == .referenceDecay { pause() }
    }

    private func clearReading(resetSignalHint: Bool = true, resetTarget: Bool = true,
                              finalState: TunerReadingState? = nil) {
        let keepUnclear = !resetSignalHint && isSignalUnclear
        frequency = nil
        heldFrequency = nil
        readingState = finalState ?? (keepUnclear ? .unclear : .waiting)
        trackedFrequency = nil
        recentFrequencies.removeAll(keepingCapacity: true)
        resetConfirmation()
        if resetTarget {
            lockedStringNumber = nil
            stringCandidate = nil
        }
    }

    private func acceptAutomaticTarget(_ pitch: TunerPitchEstimate, at time: TimeInterval) -> Bool {
        guard automatic else { return true }
        let candidate = tuning.targets.min {
            abs(TunerIntonation.cents(frequency: pitch.frequency, target: $0.frequency(a4: calibrationA4)))
                < abs(TunerIntonation.cents(frequency: pitch.frequency, target: $1.frequency(a4: calibrationA4)))
        }!
        let distance = abs(TunerIntonation.cents(frequency: pitch.frequency, target: candidate.frequency(a4: calibrationA4)))
        guard distance <= TunerPolicy.automaticRange else {
            loseSignal(at: time, unclear: true)
            return false
        }
        if candidate.number == lockedStringNumber {
            stringCandidate = nil
            return true
        }
        frequency = nil
        heldFrequency = nil
        readingState = .recognizing
        resetConfirmation()
        if lockedStringNumber != nil,
           abs(TunerIntonation.cents(frequency: pitch.frequency, target: targetFrequency)) - distance < TunerPolicy.stringSwitchAdvantage {
            stringCandidate = nil
            return false
        }
        if let current = stringCandidate, current.number == candidate.number,
           time - current.lastAt <= TunerPolicy.continuousGap + 0.000001 {
            stringCandidate = (current.number, current.since, time)
        } else {
            stringCandidate = (candidate.number, time, time)
        }
        let duration = lockedStringNumber == nil ? TunerPolicy.initialRecognitionDuration : TunerPolicy.stringSwitchDuration
        guard let current = stringCandidate, time - current.since + 0.000001 >= duration else { return false }
        clearReading(resetTarget: false)
        selectedStringNumber = candidate.number
        lockedStringNumber = candidate.number
        stringCandidate = nil
        return true
    }

    private func loseSignal(at time: TimeInterval, unclear: Bool) {
        let hadReading = frequency != nil || heldFrequency != nil || trackedFrequency != nil || isSignalUnclear
        if let frequency { heldFrequency = frequency }
        frequency = nil
        recentFrequencies.removeAll(keepingCapacity: true)
        stringCandidate = nil
        resetConfirmation()
        if heldFrequency != nil, time - lastPitchAt < TunerPolicy.readoutHoldDuration {
            readingState = .holding
        } else {
            clearReading(finalState: unclear || hadReading ? .unclear : .waiting)
        }
    }

    private func resetConfirmation() {
        stableSince = nil
        lastConfirmationAt = nil
        stableRange = nil
    }

    private func updateConfirmation(rawFrequency: Double, at time: TimeInterval) {
        guard let shown = cents else { return }
        let raw = TunerIntonation.cents(frequency: rawFrequency, target: targetFrequency)
        let continuous = lastConfirmationAt.map { time - $0 <= TunerPolicy.continuousGap + 0.000001 } ?? false
        if readingState == .inTune, continuous,
           abs(raw) <= TunerPolicy.confirmationExitCents,
           abs(shown) <= TunerPolicy.confirmationExitCents {
            lastConfirmationAt = time
            return
        }
        guard abs(raw) <= TunerPolicy.confirmationEntryCents,
              abs(shown) <= TunerPolicy.confirmationEntryCents else {
            resetConfirmation()
            readingState = .tracking
            return
        }
        let lower = min(stableRange?.lowerBound ?? raw, raw)
        let upper = max(stableRange?.upperBound ?? raw, raw)
        if !continuous || upper - lower > TunerPolicy.confirmationSpreadCents {
            stableSince = time
            stableRange = raw...raw
        } else {
            stableRange = lower...upper
        }
        lastConfirmationAt = time
        readingState = time - (stableSince ?? time) + 0.000001 >= TunerPolicy.confirmationDuration ? .inTune : .settling
    }

    private func receive(_ pitch: TunerPitchEstimate?, at now: TimeInterval) {
        expireReading(at: now)
        guard let pitch else {
            loseSignal(at: now, unclear: false)
            return
        }
        guard pitch.frequency.isFinite, (55...600).contains(pitch.frequency),
              pitch.confidence.isFinite, (0.95...1).contains(pitch.confidence) else {
            loseSignal(at: now, unclear: true)
            return
        }
        guard acceptAutomaticTarget(pitch, at: now) else { return }
        recentFrequencies.append(pitch.frequency)
        if recentFrequencies.count > 4 { recentFrequencies.removeFirst() }
        if let previous = trackedFrequency {
            let change = TunerIntonation.cents(frequency: pitch.frequency, target: previous)
            let quality = min(1, max(0, (pitch.confidence - 0.95) / 0.04))
            let previousRaw = recentFrequencies.dropLast().last
            let sustainedStep = recentFrequencies.count >= 3 && previousRaw.map {
                abs(TunerIntonation.cents(frequency: pitch.frequency, target: $0)) < 1.5
            } == true
            let responsiveWeight = abs(change) > 3 && sustainedStep ? 0.78 : 0.25
            var weight = 0.08 + (responsiveWeight - 0.08) * quality * quality
            var coherentMovement = false
            // A sustained, similarly sized progression is evidence of tuning;
            // one noisy jump is not. Keep weak but coherent movement responsive.
            let steps = zip(recentFrequencies, recentFrequencies.dropFirst()).map {
                TunerIntonation.cents(frequency: $0.1, target: $0.0)
            }
            if steps.count == 3,
               steps.allSatisfy({ (0.35...6).contains(abs($0)) }),
               steps.allSatisfy({ $0 > 0 }) || steps.allSatisfy({ $0 < 0 }),
               let smallest = steps.map(abs).min(), let largest = steps.map(abs).max(),
               largest <= smallest * 2.5 {
                weight = max(weight, 0.45)
                coherentMovement = true
            }
            if abs(change) >= 100, !sustainedStep, !coherentMovement {
                frequency = nil
                heldFrequency = nil
                readingState = .tracking
                resetConfirmation()
                return
            }
            let elapsed = min(TunerPolicy.continuousGap, max(0, now - lastPitchAt))
            weight = 1 - pow(1 - weight, elapsed / TunerPolicy.referenceHopDuration)
            trackedFrequency = abs(change) >= 100 ? pitch.frequency : previous * pow(2, change * weight / 1200)
        } else {
            trackedFrequency = pitch.frequency
        }
        frequency = trackedFrequency
        heldFrequency = nil
        updateConfirmation(rawFrequency: pitch.frequency, at: now)
        lastPitchAt = now
    }

    func expireReading(at now: TimeInterval) {
        if status == .referenceDecay, let deadline = referenceResumeAt, now >= deadline {
            referenceResumeAt = nil
            let attempt = generation
            Task { [weak self] in
                guard let self, self.active, self.generation == attempt, self.status == .referenceDecay else { return }
                await self.start(afterReference: true)
            }
            return
        }
        guard status == .listening else { return }
        if (isRecognizingString || (readingState == .tracking && frequency == nil)),
           now - lastObservationAt > TunerPolicy.continuousGap {
            loseSignal(at: now, unclear: true)
            return
        }
        if (frequency != nil && now - lastPitchAt > TunerPolicy.continuousGap)
            || (isHoldingReading && now - lastPitchAt >= TunerPolicy.readoutHoldDuration) {
            loseSignal(at: now, unclear: true)
        }
    }

    func toggleReferenceTone() {
        guard active, status != .preparing else { return }
        if status == .referenceTone {
            let resume = resumeAfterReference
            let previous = referenceReturnStatus
            pause()
            if resume { queueResume(attempt: generation) }
            else { status = previous }
            return
        }
        let previous = status
        let resume = status == .listening || status == .referenceDecay
        pause()
        let attempt = generation
        status = .referenceTone
        resumeAfterReference = resume
        referenceReturnStatus = previous == .permissionDenied ? .permissionDenied : .paused
        do {
            try audio.playReference(frequency: targetFrequency) { [weak self] in
                guard let self, self.active, self.generation == attempt else { return }
                self.status = previous == .permissionDenied ? .permissionDenied : .paused
                if resume { self.queueResume(attempt: attempt) }
            }
        } catch {
            errorMessage = String(localized: "标准音暂时无法播放，请检查音频设备后重试。")
            status = .failed
        }
    }

    private func queueResume(attempt: Int) {
        guard active, generation == attempt else { return }
        status = .referenceDecay
        referenceResumeAt = now() + TunerPolicy.referenceIsolationDuration
        monitorExpiry(attempt: attempt)
    }

    private func monitorExpiry(attempt: Int) {
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, self.generation == attempt else { return }
                self.expireReading(at: self.now())
            }
        }
    }

    private func handle(_ event: AudioSessionCoordinator.InterruptionEvent) {
        guard event != .ended(shouldResume: false), event != .ended(shouldResume: true), active else { return }
        pause()
        status = .interrupted
    }
}
