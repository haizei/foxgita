import Foundation
import Testing
@testable import foxgita

private struct ApplyBoom: Error {}

@MainActor
@Suite(.serialized)
struct MetronomeEngineTests {
    @Test func bumpClampsAndStepsByOne() {
        let metronome = MetronomeEngine(session: AudioSessionCoordinator(apply: { }))
        #expect(metronome.bpm == 80)
        metronome.bump(1)
        metronome.bump(1)
        metronome.bump(1)
        #expect(metronome.bpm == 83)
        metronome.bump(-1)
        #expect(metronome.bpm == 82)
        metronome.setBpm(39)
        #expect(metronome.bpm == 40)
        metronome.bump(-1)
        #expect(metronome.bpm == 40)
        metronome.setBpm(201)
        #expect(metronome.bpm == 200)
        metronome.bump(1)
        #expect(metronome.bpm == 200)
    }

    @Test func startFailureLeavesIdleAndReleasesSession() {
        let session = AudioSessionCoordinator(apply: { throw ApplyBoom() })
        let metronome = MetronomeEngine(session: session)
        #expect(throws: ApplyBoom.self) {
            try metronome.start()
        }
        #expect(!metronome.isPlaying)
        #expect(!metronome.hasPump)
        #expect(session.count(for: .playback) == 0)
    }

    @Test func startStopStartRunsEngineWithoutSecondPump() throws {
        let metronome = MetronomeEngine()
        try metronome.start()
        #expect(metronome.isPlaying)
        #expect(metronome.isEngineRunning)
        #expect(metronome.hasPump)
        metronome.stop()
        #expect(!metronome.isPlaying)
        #expect(!metronome.hasPump)
        try metronome.start()
        #expect(metronome.isPlaying)
        #expect(metronome.isEngineRunning)
        #expect(metronome.hasPump)
        metronome.stop()
        #expect(!metronome.hasPump)
    }

    @Test func stopIsIdempotent() {
        let metronome = MetronomeEngine(session: AudioSessionCoordinator(apply: { }))
        metronome.stop()
        metronome.stop()
        #expect(!metronome.isPlaying)
        #expect(!metronome.hasPump)
    }

    @Test func currentBeatInBarStartsAtZero() {
        let metronome = MetronomeEngine(session: AudioSessionCoordinator(apply: { }))
        #expect(metronome.currentBeatInBar == 0)
    }

    @Test func stopResetsCurrentBeatInBar() throws {
        let metronome = MetronomeEngine()
        try metronome.start()
        metronome.stop()
        #expect(metronome.currentBeatInBar == 0)
    }

    @Test func startResetsCurrentBeatInBar() throws {
        let metronome = MetronomeEngine()
        try metronome.start()
        metronome.stop()
        try metronome.start()
        #expect(metronome.currentBeatInBar == 0)
    }

    @Test func setBpmWhilePlayingKeepsPlaying() throws {
        let metronome = MetronomeEngine()
        try metronome.start()
        metronome.setBpm(100)
        #expect(metronome.isPlaying)
        #expect(metronome.bpm == 100)
        metronome.stop()
    }

    @Test func variableBeatsPerBarUpdatesDisplayState() {
        let metronome = MetronomeEngine()
        metronome.configureMeter(timeSignature: "3/4", accentRaw: "311")
        #expect(metronome.beatsPerBar == 3)
        #expect(metronome.timeSignatureText == "3/4")
        #expect(metronome.accentPattern == [.strong, .weak, .weak])
        metronome.bumpBeatsPerBar(1)
        #expect(metronome.beatsPerBar == 4)
        #expect(metronome.accentPattern.count == 4)
    }

    @Test func cycleAccentRotatesKind() {
        let metronome = MetronomeEngine()
        metronome.configureMeter(timeSignature: "2/4", accentRaw: "31")
        metronome.cycleAccent(at: 1)
        #expect(metronome.accentPattern[1] == .medium)
        metronome.cycleAccent(at: 1)
        #expect(metronome.accentPattern[1] == .strong)
        metronome.cycleAccent(at: 1)
        #expect(metronome.accentPattern[1] == .mute)
        metronome.cycleAccent(at: 1)
        #expect(metronome.accentPattern[1] == .weak)
    }

    @Test func beatTrackModeStartsAtAllBeatsAndCyclesWithoutPersistence() {
        let metronome = MetronomeEngine()
        #expect(metronome.beatTrackMode == .allBeats)
        metronome.cycleBeatTrackMode()
        #expect(metronome.beatTrackMode == .accents)
        metronome.cycleBeatTrackMode()
        #expect(metronome.beatTrackMode == .pendulum)
    }

    @Test func visualEventsFollowScheduledMainAndSubdivisionClicks() async throws {
        let metronome = MetronomeEngine()
        metronome.hapticsEnabled = false
        metronome.setBpm(200)
        metronome.setSubdivision(.twoEighths)
        var events: [MetronomeVisualEvent] = []
        metronome.onVisualEvent = { events.append($0) }

        try metronome.start()
        try await Task.sleep(for: .milliseconds(650))
        metronome.stop()

        #expect(events.contains { $0.role == .main })
        #expect(events.contains { $0.role == .weak })
    }

    @Test func backgroundPlaybackSuppressesVisualFeedback() async throws {
        let metronome = MetronomeEngine()
        metronome.hapticsEnabled = false
        metronome.setBpm(200)
        var events: [MetronomeVisualEvent] = []
        metronome.onVisualEvent = { events.append($0) }
        metronome.foregroundFeedbackEnabled = false

        try metronome.start()
        try await Task.sleep(for: .milliseconds(450))
        metronome.stop()

        #expect(events.isEmpty)
    }

    @Test func sixteenthNotesPublishAllAudiblePulseRoles() async throws {
        let metronome = MetronomeEngine()
        metronome.hapticsEnabled = false
        metronome.setBpm(200)
        metronome.setSubdivision(.fourSixteenths)
        var events: [MetronomeVisualEvent] = []
        metronome.onVisualEvent = { events.append($0) }

        try metronome.start()
        try await Task.sleep(for: .milliseconds(450))
        metronome.stop()

        #expect(events.contains { $0.role == .main })
        #expect(events.contains { $0.role == .secondary })
        #expect(events.contains { $0.role == .weak })
    }

    @Test func leadingRestAdvancesTimelineWithoutPublishingFalseMainPulse() async throws {
        let metronome = MetronomeEngine()
        metronome.hapticsEnabled = false
        metronome.setBpm(200)
        metronome.setSubdivision(.eighthRestEighth)
        var events: [MetronomeVisualEvent] = []
        var timeline: [MetronomeTimelineEvent] = []
        metronome.onVisualEvent = { events.append($0) }
        metronome.onTimelineEvent = { timeline.append($0) }

        try metronome.start()
        try await Task.sleep(for: .milliseconds(450))
        metronome.stop()

        #expect(timeline.first?.beat == 0)
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0.role == .weak })
    }

    @Test func subdivisionChangeWhilePlayingWaitsForBarBoundary() async throws {
        let metronome = MetronomeEngine()
        metronome.hapticsEnabled = false
        metronome.setBpm(200)
        metronome.configureMeter(timeSignature: "2/4", accentRaw: "31")
        try metronome.start()
        metronome.setSubdivision(.fourSixteenths)

        #expect(metronome.isPlaying)
        #expect(metronome.subdivision == .quarter)
        #expect(metronome.configuredSubdivision == .fourSixteenths)
        #expect(metronome.hasPendingRhythmChange)

        try await Task.sleep(for: .milliseconds(850))

        #expect(metronome.subdivision == .fourSixteenths)
        #expect(!metronome.hasPendingRhythmChange)
        metronome.stop()
    }

    @Test func shrinkingSubdivisionDuringPlaybackDoesNotUseStaleStepIndex() async throws {
        let metronome = MetronomeEngine()
        metronome.hapticsEnabled = false
        metronome.setBpm(200)
        metronome.configureMeter(timeSignature: "2/4", accentRaw: "31")
        metronome.setSubdivision(.fourSixteenths)
        try metronome.start()

        metronome.setSubdivision(.quarter)

        #expect(metronome.subdivision == .fourSixteenths)
        #expect(metronome.configuredSubdivision == .quarter)
        try await Task.sleep(for: .milliseconds(850))
        #expect(metronome.subdivision == .quarter)
        #expect(metronome.isPlaying)
        metronome.stop()
    }

    @Test func meterSubdivisionAndAccentCommitAtomicallyAtBarBoundary() async throws {
        let metronome = MetronomeEngine()
        metronome.hapticsEnabled = false
        metronome.setBpm(200)
        metronome.configureMeter(timeSignature: "2/4", accentRaw: "31")
        try metronome.start()

        metronome.setBeatsPerBar(3)
        metronome.setSubdivision(.twoEighths)
        metronome.cycleAccent(at: 1)

        #expect(metronome.beatsPerBar == 2)
        #expect(metronome.subdivision == .quarter)
        #expect(metronome.accentPattern == [.strong, .weak])
        #expect(metronome.configuredBeatsPerBar == 3)
        #expect(metronome.configuredSubdivision == .twoEighths)
        #expect(metronome.configuredAccentPattern == [.strong, .medium, .weak])

        try await Task.sleep(for: .milliseconds(850))

        #expect(metronome.beatsPerBar == 3)
        #expect(metronome.subdivision == .twoEighths)
        #expect(metronome.accentPattern == [.strong, .medium, .weak])
        metronome.stop()
    }

    @Test func stoppingPromotesPendingRhythmForNextRun() throws {
        let metronome = MetronomeEngine()
        metronome.setSubdivision(.fourSixteenths)
        try metronome.start()

        metronome.setSubdivision(.quarter)
        #expect(metronome.subdivision == .fourSixteenths)
        metronome.stop()

        #expect(metronome.subdivision == .quarter)
        #expect(metronome.configuredSubdivision == .quarter)
        #expect(!metronome.hasPendingRhythmChange)
    }

    @Test func fiftyQueuedRhythmEditsUseTheLastCompleteConfiguration() async throws {
        let metronome = MetronomeEngine()
        metronome.hapticsEnabled = false
        metronome.setBpm(200)
        metronome.configureMeter(timeSignature: "2/4", accentRaw: "31")
        try metronome.start()
        let subdivisions = Array(MetronomeSubdivision.allCases)

        for index in 0..<50 {
            let beats = 2 + index % 7
            metronome.configureMeter(
                timeSignature: "\(beats)/4",
                accentRaw: "3" + String(repeating: "1", count: beats - 1)
            )
            metronome.setSubdivision(subdivisions[index % subdivisions.count])
        }

        let expectedBeats = metronome.configuredBeatsPerBar
        let expectedAccent = metronome.configuredAccentPattern
        let expectedSubdivision = metronome.configuredSubdivision
        try await Task.sleep(for: .milliseconds(850))

        #expect(metronome.beatsPerBar == expectedBeats)
        #expect(metronome.accentPattern == expectedAccent)
        #expect(metronome.subdivision == expectedSubdivision)
        #expect(!metronome.hasPendingRhythmChange)
        metronome.stop()
    }

    @Test func audioServicesResetAllowsManualRestart() throws {
        let metronome = MetronomeEngine()
        try metronome.start()

        metronome.prepareAfterAudioServicesReset()
        #expect(!metronome.isPlaying)

        try metronome.start()
        #expect(metronome.isPlaying)
        #expect(metronome.isEngineRunning)
        metronome.stop()
    }

    @Test func setSoundModeWhilePlayingKeepsPlaying() throws {
        let metronome = MetronomeEngine()
        try metronome.start()
        metronome.setSoundMode(.drums)
        #expect(metronome.isPlaying)
        #expect(metronome.soundMode == .drums)
        metronome.stop()
    }

    @Test func volumeClamps() {
        let metronome = MetronomeEngine()
        metronome.setVolume(150)
        #expect(metronome.volume == 100)
        metronome.setVolume(-5)
        #expect(metronome.volume == 0)
    }

    @Test func previewRequiresIdle() throws {
        let metronome = MetronomeEngine()
        try metronome.start()
        #expect(throws: MetronomeError.previewUnavailableWhilePlaying) {
            try metronome.preview(bars: 2)
        }
        metronome.stop()
    }

    @Test func previewStopsAfterBars() async throws {
        let metronome = MetronomeEngine()
        metronome.setBpm(200)
        metronome.configureMeter(timeSignature: "1/4", accentRaw: "2")
        try metronome.preview(bars: 1)
        #expect(metronome.isPlaying)
        try await Task.sleep(for: .seconds(1.5))
        #expect(!metronome.isPlaying)
    }
}
