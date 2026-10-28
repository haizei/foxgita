import AVFoundation
import Darwin
import UIKit
import XCTest
@testable import foxgita

/// Opt-in hardware checks. Run in isolation with -UITesting so captured takes
/// never enter the normal library. See the device acceptance runbook for setup.
@MainActor
final class PracticeDeviceAcceptanceTests: XCTestCase {
    private func requireDevice() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GITA_DEVICE_ACCEPTANCE"] == "1")
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical iPhone required; simulator input is not acceptance evidence")
        #endif
        _ = try XCTUnwrap(PracticeTestEnvironment.isActive ? true : nil, "Isolated -UITesting environment is required")
    }

    func testMicrophoneMeteringPauseOwnershipAndDecodableTake() async throws {
        try requireDevice()
        let recorder = AudioRecorderService()
        let engine = MetronomeEngine()
        let timer = PracticeTimer()
        let runtime = PracticeRuntimeCoordinator(
            timer: timer, countdown: PracticeCountdown(defaultMinutes: 10),
            playback: engine, recording: recorder
        )
        defer {
            runtime.pausePractice()
            recorder.stop()
            recorder.discardPending()
        }
        engine.configureSound(modeRaw: nil, volume: 25, strongBeatBoost: true)
        try runtime.startPractice()
        await recorder.start(label: "Hardware acceptance — discarded")
        guard recorder.isRecording else {
            XCTFail("Microphone did not start: \(recorder.lastError ?? "unknown")")
            return
        }
        runtime.recordingStarted()
        try await Task.sleep(for: .seconds(3))
        XCTAssertEqual(recorder.inputLevels.count, 32)
        XCTAssertTrue(recorder.inputLevels.allSatisfy { $0.isFinite && (0...1).contains($0) })
        XCTAssertTrue(recorder.inputLevels.contains { $0 > 0 }, "No live microphone energy; provide an audible input")

        runtime.pauseRecordingOnly()
        let levels = recorder.inputLevels
        let recordedSeconds = recorder.elapsedSec
        let practiceSeconds = timer.elapsedSec
        try await Task.sleep(for: .seconds(2))
        XCTAssertEqual(recorder.inputLevels, levels, "Paused waveform must freeze")
        XCTAssertEqual(recorder.elapsedSec, recordedSeconds)
        XCTAssertGreaterThan(timer.elapsedSec, practiceSeconds, "Recording pause must not pause practice")
        runtime.pausePractice()
        try runtime.resumePractice()
        XCTAssertTrue(recorder.isPaused, "Main resume must preserve a manually paused take")

        runtime.resumeRecordingOnly()
        try await Task.sleep(for: .seconds(2))
        runtime.pausePractice()
        XCTAssertTrue(recorder.isPaused)
        try runtime.resumePractice()
        XCTAssertFalse(recorder.isPaused, "Main resume must restore the take it paused")
        try await Task.sleep(for: .seconds(2))
        recorder.stop()
        XCTAssertTrue(recorder.inputLevels.isEmpty)
        let clip = try XCTUnwrap(recorder.pending.first)
        XCTAssertGreaterThan(clip.bytes, 0)
        let file = try AVAudioFile(forReading: clip.url)
        XCTAssertGreaterThan(file.length, 0)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
        try file.read(into: buffer)
        XCTAssertGreaterThan(buffer.frameLength, 0)
        XCTAssertGreaterThanOrEqual(clip.durationSec, 6)
        XCTAssertLessThanOrEqual(clip.durationSec, 9, "Paused wall time must not enter recorded duration")
        recorder.discardPending()
        XCTAssertFalse(FileManager.default.fileExists(atPath: clip.url.path))
    }

    func testSoundPresetTimelineAtSlowAndDenseFastTempos() async throws {
        try requireDevice()
        let engine = MetronomeEngine()
        engine.hapticsEnabled = false
        var beats = 0
        engine.onTimelineEvent = { _ in beats += 1 }
        defer { engine.stop() }
        for bpm in [40, 200] {
            engine.stop()
            engine.setBpm(bpm)
            engine.configureSubdivision(raw: bpm == 200 ? MetronomeSubdivision.fourSixteenths.rawValue : 0)
            try engine.start()
            for preset in MetronomeSoundPreset.allCases {
                let before = beats
                engine.configureSound(modeRaw: preset.rawValue, volume: 25, strongBeatBoost: true)
                try await Task.sleep(for: .seconds(3))
                XCTAssertEqual(engine.soundPreset, preset)
                XCTAssertTrue(engine.isPlaying && engine.isEngineRunning && engine.hasPump)
                XCTAssertGreaterThan(beats, before, "Timeline stopped for \(preset.rawValue) at \(bpm) BPM")
            }
        }
    }

    func testOneMinuteCountdownStopsEngineAndRecordedTake() async throws {
        try requireDevice()
        let recorder = AudioRecorderService()
        let engine = MetronomeEngine()
        let timer = PracticeTimer()
        let countdown = PracticeCountdown(defaultMinutes: 1)
        let runtime = PracticeRuntimeCoordinator(timer: timer, countdown: countdown, playback: engine, recording: recorder)
        defer {
            runtime.pausePractice()
            recorder.stop()
            recorder.discardPending()
        }
        var stoppedAt: TimeInterval?
        countdown.onCompletion = {
            _ = runtime.handleCountdownCompletion()
            stoppedAt = ProcessInfo.processInfo.systemUptime
        }
        defer { countdown.onCompletion = nil }
        engine.configureSound(modeRaw: nil, volume: 25, strongBeatBoost: true)
        await recorder.start()
        guard recorder.isRecording else {
            XCTFail("Microphone permission/input required for actual countdown recording check")
            return
        }
        runtime.saveCountdownPlan(minutes: 1, reminderEnabled: false)
        let startedAt = ProcessInfo.processInfo.systemUptime
        try runtime.startPractice()
        try await Task.sleep(for: .seconds(62))
        XCTAssertEqual(countdown.phase, .completed)
        XCTAssertEqual(timer.elapsedSec, 60)
        XCTAssertFalse(timer.isRunning)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.pending.count, 1)
        XCTAssertEqual(try XCTUnwrap(stoppedAt) - startedAt, 60, accuracy: 0.5, "Observed service completion deadline")
        let clip = try XCTUnwrap(recorder.pending.first)
        let file = try AVAudioFile(forReading: clip.url)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        XCTAssertEqual(duration, 60, accuracy: 0.5, "Recorded media must exclude post-deadline wall time")
        XCTAssertFalse(runtime.handleCountdownCompletion(), "Completion must remain idempotent")
    }

    func testTwoHourForegroundTimeline() async throws {
        try requireDevice()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GITA_DEVICE_SOAK"] == "1")
        executionTimeAllowance = 7_800
        let oldIdle = UIApplication.shared.isIdleTimerDisabled
        let oldBatteryMonitoring = UIDevice.current.isBatteryMonitoringEnabled
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        let engine = MetronomeEngine()
        engine.hapticsEnabled = false
        engine.setBpm(120)
        engine.configureSound(modeRaw: nil, volume: 25, strongBeatBoost: true)
        var beats = 0
        var previousBeat: TimeInterval?
        var maximumCallbackGap: TimeInterval = 0
        engine.onTimelineEvent = { _ in
            let instant = ProcessInfo.processInfo.systemUptime
            if let previousBeat { maximumCallbackGap = max(maximumCallbackGap, instant - previousBeat) }
            previousBeat = instant
            beats += 1
        }
        defer {
            engine.stop()
            UIApplication.shared.isIdleTimerDisabled = oldIdle
            UIDevice.current.isBatteryMonitoringEnabled = oldBatteryMonitoring
        }
        let started = ProcessInfo.processInfo.systemUptime
        var checkpoints: [[String: Double]] = []
        try engine.start()
        for minute in 1...120 {
            let previousCount = beats
            try await Task.sleep(for: .seconds(60))
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            let checkpoint: [String: Double] = [
                "minute": Double(minute), "elapsed_seconds": elapsed, "beats": Double(beats),
                "max_callback_gap_seconds": maximumCallbackGap,
                "thermal_state": Double(ProcessInfo.processInfo.thermalState.rawValue),
                "resident_bytes": try residentBytes(),
                "battery_fraction": Double(UIDevice.current.batteryLevel)
            ]
            checkpoints.append(checkpoint)
            print("DEVICE_SOAK \(checkpoint)")
            guard UIApplication.shared.applicationState == .active,
                  engine.isPlaying && engine.isEngineRunning && engine.hasPump && beats > previousCount else {
                XCTFail("Playback lost progress at minute \(minute)")
                attachCheckpoints(checkpoints)
                return
            }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        XCTAssertGreaterThanOrEqual(elapsed, 7_200)
        XCTAssertEqual(Double(beats), elapsed * 2, accuracy: 4, "120 BPM timeline drift")
        XCTAssertLessThan(maximumCallbackGap, 1, "Foreground callback stall; not an acoustic loopback measurement")
        attachCheckpoints(checkpoints)
    }

    private func residentBytes() throws -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        _ = try XCTUnwrap(result == KERN_SUCCESS ? true : nil, "Resident memory sample failed")
        return Double(info.resident_size)
    }

    private func attachCheckpoints(_ checkpoints: [[String: Double]]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: checkpoints, options: [.prettyPrinted, .sortedKeys])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "Two-hour foreground timeline checkpoints"
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Could not serialize soak evidence: \(error)")
        }
    }
}
