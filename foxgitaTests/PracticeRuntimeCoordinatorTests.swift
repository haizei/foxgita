import Foundation
import Testing
@testable import foxgita

@MainActor
struct PracticeRuntimeCoordinatorTests {
    @Test func countdownCapsElapsedAtDeadlineAndCompletesOnlyOnce() throws {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let timer = PracticeTimer(now: { now })
        let countdown = PracticeCountdown(defaultMinutes: 1, now: { now })
        let recording = Recording()
        let runtime = PracticeRuntimeCoordinator(timer: timer, countdown: countdown, playback: Playback(), recording: recording)
        countdown.applyPlan(minutes: 1, reminderEnabled: false, startImmediately: false)
        try runtime.setMetronomeEnabled(false)
        try runtime.startPractice()
        #expect(countdown.phase == .running)
        now += 75
        countdown.refresh()
        #expect(runtime.handleCountdownCompletion())
        #expect(!runtime.handleCountdownCompletion())
        #expect(timer.elapsedSec == 60)
        #expect(!timer.isRunning)
        #expect(!recording.isRecording)
    }

    private final class Playback: PracticePlaybackControlling {
        var isPlaying = false
        var cutoff: TimeInterval?
        func start() { isPlaying = true }
        func stop() { isPlaying = false }
        func armCountdownStop(after seconds: TimeInterval, onReached: @escaping () -> Void) { cutoff = seconds }
    }

    private final class Recording: PracticeRecordingControlling {
        var isRecording = true
        var isPaused = false
        var canResume = true
        func pause() { isPaused = true }
        func resume() { if canResume { isPaused = false } }
        func stop(label: String) { isRecording = false }
    }

    @Test func failedRecordingResumeDoesNotStartPracticeClock() {
        let recording = Recording()
        recording.isPaused = true
        recording.canResume = false
        let timer = PracticeTimer()
        let runtime = PracticeRuntimeCoordinator(timer: timer, countdown: PracticeCountdown(defaultMinutes: 10), playback: Playback(), recording: recording)
        runtime.resumeRecordingOnly()
        #expect(recording.isPaused)
        #expect(!timer.isRunning)
    }

    @Test func alternateCountdownEntriesRearmDeadlineAndReminder() throws {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let recording = Recording()
        let playback = Playback()
        let countdown = PracticeCountdown(defaultMinutes: 1, now: { now })
        let runtime = PracticeRuntimeCoordinator(timer: PracticeTimer(now: { now }), countdown: countdown, playback: playback, recording: recording)
        var notifications: [TimeInterval] = []
        runtime.onCountdownStarted = { notifications.append($0) }
        runtime.saveCountdownPlan(minutes: 1, reminderEnabled: true)
        try runtime.setMetronomeEnabled(false)
        runtime.recordingStarted()
        #expect(countdown.phase == .running)
        #expect(notifications == [60])
        now += 10.5
        try runtime.setMetronomeEnabled(true)
        #expect(playback.cutoff == 49.5)
        #expect(notifications.last == 49.5)
        runtime.saveCountdownPlan(minutes: 5, reminderEnabled: false)
        #expect(countdown.phase == .paused)
        #expect(!runtime.timer.isRunning)
        #expect(!playback.isPlaying)
    }

    @Test func mainPauseRestoresOnlyRecordingItPaused() throws {
        let recording = Recording()
        let runtime = PracticeRuntimeCoordinator(
            timer: PracticeTimer(), countdown: PracticeCountdown(defaultMinutes: 10),
            playback: Playback(), recording: recording
        )
        try runtime.startPractice()
        runtime.pausePractice()
        #expect(recording.isPaused)
        try runtime.resumePractice()
        #expect(!recording.isPaused)
        recording.pause()
        runtime.pausePractice()
        try runtime.resumePractice()
        #expect(recording.isPaused)
        runtime.pausePractice()
    }

    @Test func silentPracticeCountsActualTimeAndExcludesPause() throws {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let timer = PracticeTimer(now: { now })
        let countdown = PracticeCountdown(defaultMinutes: 10, now: { now })
        let runtime = PracticeRuntimeCoordinator(
            timer: timer, countdown: countdown,
            playback: MetronomeEngine(), recording: AudioRecorderService()
        )
        try runtime.setMetronomeEnabled(false)
        try runtime.startPractice()
        now += 120
        runtime.pausePractice()
        now += 60
        #expect(timer.elapsedSec == 120)
        #expect(!timer.isRunning)
        try runtime.resumePractice()
        now += 30
        runtime.pausePractice()
        #expect(timer.elapsedSec == 150)
    }
}
