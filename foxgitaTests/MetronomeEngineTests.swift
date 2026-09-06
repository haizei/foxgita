import Foundation
import Testing
@testable import foxgita

private struct ApplyBoom: Error {}

@MainActor
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
        metronome.configureMeter(timeSignature: "3/4", accentRaw: "211")
        #expect(metronome.beatsPerBar == 3)
        #expect(metronome.timeSignatureText == "3/4")
        #expect(metronome.accentPattern == [.accent, .normal, .normal])
        metronome.bumpBeatsPerBar(1)
        #expect(metronome.beatsPerBar == 4)
        #expect(metronome.accentPattern.count == 4)
    }

    @Test func cycleAccentRotatesKind() {
        let metronome = MetronomeEngine()
        metronome.configureMeter(timeSignature: "2/4", accentRaw: "21")
        metronome.cycleAccent(at: 1)
        #expect(metronome.accentPattern[1] == .mute)
        metronome.cycleAccent(at: 1)
        #expect(metronome.accentPattern[1] == .accent)
    }

    @Test func setSubdivisionWhilePlayingKeepsPlaying() throws {
        let metronome = MetronomeEngine()
        try metronome.start()
        metronome.setSubdivision(.fourSixteenths)
        #expect(metronome.isPlaying)
        #expect(metronome.subdivision == .fourSixteenths)
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
        #expect(throws: (any Error).self) {
            try metronome.preview(bars: 2)
        }
        metronome.stop()
    }
}
