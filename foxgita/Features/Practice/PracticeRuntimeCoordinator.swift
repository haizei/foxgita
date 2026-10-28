import Foundation

@MainActor
protocol PracticePlaybackControlling: AnyObject {
    var isPlaying: Bool { get }
    var isPreviewing: Bool { get }
    func start() throws
    func stop()
    func stopPreview()
    func pausePlayback()
    func resumePlayback() throws
    func armCountdownStop(after seconds: TimeInterval, onReached: @escaping () -> Void)
}

extension PracticePlaybackControlling {
    var isPreviewing: Bool { false }
    func pausePlayback() { stop() }
    func stopPreview() { stop() }
    func resumePlayback() throws { try start() }
    func armCountdownStop(after seconds: TimeInterval, onReached: @escaping () -> Void) {}
}

@MainActor
protocol PracticeRecordingControlling: AnyObject {
    var isRecording: Bool { get }
    var isPaused: Bool { get }
    func pause()
    func resume()
    func stop(label: String)
}

extension MetronomeEngine: PracticePlaybackControlling {}
extension AudioRecorderService: PracticeRecordingControlling {}

/// Coordinates user intent without treating an audio engine as the practice clock.
@MainActor @Observable
final class PracticeRuntimeCoordinator {
    let timer: PracticeTimer
    let countdown: PracticeCountdown
    private(set) var metronomeEnabled = true
    @ObservationIgnored var onCountdownStarted: ((TimeInterval) -> Void)?
    @ObservationIgnored private let playback: any PracticePlaybackControlling
    @ObservationIgnored private let recording: any PracticeRecordingControlling
    @ObservationIgnored private var resumeRecordingWithPractice = false
    @ObservationIgnored private var handledCountdownCompletion = false

    init(
        timer: PracticeTimer, countdown: PracticeCountdown,
        playback: any PracticePlaybackControlling,
        recording: any PracticeRecordingControlling
    ) {
        self.timer = timer
        self.countdown = countdown
        self.playback = playback
        self.recording = recording
    }

    func startPractice() throws {
        defer { synchronizeCountdown() }
        timer.start()
        handledCountdownCompletion = false
        if countdown.phase == .completed { countdown.restart() }
        else if countdown.phase == .paused { countdown.resume() }
        if resumeRecordingWithPractice, recording.isRecording, recording.isPaused {
            recording.resume()
        }
        resumeRecordingWithPractice = false
        if metronomeEnabled {
            if playback.isPreviewing { playback.stopPreview() }
            try playback.resumePlayback()
        }
    }

    func resumePractice() throws { try startPractice() }

    func pausePractice() {
        if recording.isRecording, !recording.isPaused {
            recording.pause()
            resumeRecordingWithPractice = true
        }
        countdown.pause()
        timer.pause()
        playback.pausePlayback()
    }

    func pauseRecordingOnly() {
        resumeRecordingWithPractice = false
        recording.pause()
    }

    func resumeRecordingOnly() {
        resumeRecordingWithPractice = false
        recording.resume()
        if recording.isRecording, !recording.isPaused { recordingStarted() }
    }

    func recordingStarted() {
        timer.start()
        if countdown.phase == .paused {
            handledCountdownCompletion = false
            countdown.resume()
        }
        synchronizeCountdown()
    }

    func saveCountdownPlan(minutes: Int, reminderEnabled: Bool) {
        pausePractice()
        countdown.applyPlan(minutes: minutes, reminderEnabled: reminderEnabled, startImmediately: false)
    }

    func beginVideoPresentation(label: String) {
        if recording.isRecording { recording.stop(label: label) }
        metronomeEnabled = false
        playback.pausePlayback()
        recordingStarted()
    }

    @discardableResult
    func handleCountdownCompletion(label: String = "") -> Bool {
        guard countdown.phase == .completed, !handledCountdownCompletion else { return false }
        handledCountdownCompletion = true
        playback.stop()
        timer.pause(at: countdown.completionDate)
        if recording.isRecording { recording.stop(label: label) }
        resumeRecordingWithPractice = false
        return true
    }

    func setMetronomeEnabled(_ enabled: Bool) throws {
        defer { synchronizeCountdown() }
        metronomeEnabled = enabled
        if enabled, timer.isRunning {
            if playback.isPreviewing { playback.stopPreview() }
            try playback.resumePlayback()
        }
        if !enabled { playback.stop() }
    }

    private func synchronizeCountdown() {
        guard countdown.phase == .running else { return }
        let remaining = countdown.remainingTimeInterval
        if playback.isPlaying, !playback.isPreviewing {
            playback.armCountdownStop(after: remaining) { [weak countdown] in countdown?.complete() }
        }
        if countdown.reminderEnabled { onCountdownStarted?(remaining) }
    }
}
