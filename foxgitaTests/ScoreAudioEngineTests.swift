import AVFoundation
import Testing
@testable import foxgita

@MainActor struct ScoreAudioEngineTests {
    // This owns the process-wide AVAudioSession; run independently of existing
    // metronome/tuner hardware tests, which Swift Testing otherwise parallelizes.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_SCORE_DEVICE_AUDIO_TEST"] == "1"))
    func unavailableMicrophoneStillRendersUnscoredPlayback() async throws {
        let engine = ScoreAudioEngine(permissionRequest: { true },inputAvailable: { _,_ in false },isolatedOutput: { true })
        var run = try ScoreRun(score: ScoreExercises.melody,range: ScoreExercises.melody.fullRange,speed: 1,loopLimit: 1)
        run.start(countIn: false)
        try await engine.start(run: run)
        defer { engine.stop() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!engine.listening)
        #expect(engine.seconds > 0)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_SCORE_DEVICE_AUDIO_TEST"] == "1"))
    func speakerDemonstrationCannotListenToItselfAndManufactureScores() async throws {
        var askedPermission = false
        let engine = ScoreAudioEngine(permissionRequest: { askedPermission = true; return true },isolatedOutput: { false })
        var run = try ScoreRun(score: ScoreExercises.melody,range: ScoreExercises.melody.fullRange,speed: 1)
        run.start(countIn: false)
        try await engine.start(run: run); defer { engine.stop() }
        try await Task.sleep(for: .milliseconds(150))
        #expect(!askedPermission)
        #expect(!engine.listening)
        #expect(engine.listeningUnavailableReason?.contains("外放不评分") == true)
        #expect(engine.seconds > 0)
    }
    @Test func rendererClockAndStopSurviveConcurrentControlChanges() async throws {
        try await Task.detached {
        let plan = try ScoreSynthesisPlan(score: ScoreExercises.melody,range: ScoreExercises.melody.fullRange,speed: 1,sampleRate: 48_000)
        let renderer = ScoreSynthRenderer(plan: plan,offsetSeconds: 0,countIn: 0,countInBeats: 4,loopsRemaining: 1)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000,channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 480)!
        buffer.frameLength = 480
        var timestamp = AudioTimeStamp(); timestamp.mHostTime = AVAudioTime.hostTime(forSeconds: 1)
        let controls = Task.detached { for _ in 0..<1_000 { renderer.configure(demo: 0.5,click: 0.3); _ = renderer.seconds } }
        var audible = false
        for _ in 0..<100 {
            renderer.render(time: &timestamp,frameCount: 480,data: buffer.mutableAudioBufferList)
            if let samples = buffer.floatChannelData?.pointee { audible = audible || (0..<480).contains { abs(samples[$0]) > 0.001 } }
        }
        await controls.value
        #expect(audible)
        #expect(abs(renderer.seconds-1) < 0.011)
        renderer.stop(); let stoppedAt = renderer.seconds
        renderer.render(time: &timestamp,frameCount: 480,data: buffer.mutableAudioBufferList)
        #expect(renderer.seconds == stoppedAt)
        #expect((0..<480).allSatisfy { buffer.floatChannelData!.pointee[$0] == 0 })
        }.value
    }
}
