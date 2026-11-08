import SwiftUI
import Testing
@testable import foxgita

struct NoteDictationInteractionTests {
    private let frame = CGRect(x: 0, y: 59, width: 402, height: 815)

    @Test func ordinaryReleaseStillTranscribesDespiteHorizontalMovement() {
        #expect(NoteDictationTarget.resolve(
            translation: .init(width: -20, height: -59), location: .init(x: 40, y: 700), frame: frame
        ) == .listening)
    }

    @Test func upwardDragOnlyDiscardsOnCancelSide() {
        #expect(NoteDictationTarget.resolve(
            translation: .init(width: 0, height: -90), location: .init(x: 70, y: 610), frame: frame
        ) == .cancel)
        #expect(NoteDictationTarget.resolve(
            translation: .init(width: 230, height: -90), location: .init(x: 300, y: 610), frame: frame
        ) == .transcribe)
    }

    @Test func waveformSilenceAndInvalidSamplesStaySilent() {
        #expect(NoteDictationService.normalizedLevel(rms: 0) == 0)
        #expect(NoteDictationService.normalizedLevel(rms: -1) == 0)
        #expect(NoteDictationService.normalizedLevel(rms: .nan) == 0)
        #expect(NoteDictationService.normalizedLevel(rms: .infinity) == 0)
        #expect(NoteDictationService.normalizedLevel(rms: 0.0001) == 0)
    }

    @Test func waveformTracksAudioLevelAndCapsLoudSamples() {
        #expect(abs(NoteDictationService.normalizedLevel(rms: 0.01) - 0.2) < 0.001)
        #expect(abs(NoteDictationService.normalizedLevel(rms: 0.1) - 0.6) < 0.001)
        #expect(NoteDictationService.normalizedLevel(rms: 2) == 1)
    }
}
