import Foundation
import Testing
@testable import foxgita

struct TunerPitchTests {
    @Test func halfStepDownPresetPreservesFlatLabelsAndCalibratedTargets() throws {
        let tuning = try #require(GuitarTuning.allCases.first { $0.title == "整体降半音" })
        #expect(GuitarTuning.allCases.count == 4)
        #expect(tuning.targets.map(\.noteLabel) == ["E♭₄", "B♭₃", "G♭₃", "D♭₃", "A♭₂", "E♭₂"])
        #expect(tuning.targets.map(\.noteName) == ["E♭", "B♭", "G♭", "D♭", "A♭", "E♭"])
        let expected = [311.1270, 233.0819, 184.9972, 138.5913, 103.8262, 77.7817]
        for (target, hz) in zip(tuning.targets, expected) {
            #expect(abs(target.frequency(a4: 440) - hz) < 0.001)
            #expect(abs(target.frequency(a4: 442) / target.frequency(a4: 440) - 442.0 / 440) < 0.000001)
        }
        #expect(tuning.summary.contains("E♭ A♭ D♭ G♭ B♭ E♭"))
    }

    @Test(arguments: [0.0007, 0.0015, 0.003])
    func quietLowEIsNotDiscardedByAnAbsoluteVolumeGate(_ amplitude: Double) throws {
        let samples = (0..<4800).map { i in Float(amplitude * sin(2 * .pi * 82.4069 * Double(i) / 48_000)) }
        let estimate = TunerPitchDetector.estimate(samples: samples, sampleRate: 48_000)
        let pitch = try #require(estimate)
        #expect(abs(1200 * log2(pitch.frequency / 82.4069)) < 4)
    }

    @Test func decayingQuietLowEWithHarmonicsAndRoomNoiseRemainsTrackable() throws {
        var seed: UInt64 = 42
        let samples: [Float] = (0..<4800).map { i in
            let time = Double(i) / 48_000
            let phase = 2 * Double.pi * 82.4069 * time
            seed = seed &* 6364136223846793005 &+ 1
            let noise = (Double(seed >> 32) / Double(UInt32.max) - 0.5) * 0.00015
            return Float(0.002 * exp(-time / 0.25) * (0.4 * sin(phase) + 0.8 * sin(2 * phase) + 0.2 * sin(3 * phase)) + noise)
        }
        let estimate = TunerPitchDetector.estimate(samples: samples, sampleRate: 48_000)
        let pitch = try #require(estimate)
        #expect(abs(1200 * log2(pitch.frequency / 82.4069)) < 5)
    }

    private func signal(_ frequency: Double, rate: Double = 48_000, harmonics: Bool = false) -> [Float] {
        (0..<Int(rate * 0.2)).map { index in
            let phase = 2 * Double.pi * frequency * Double(index) / rate
            return Float(harmonics ? 0.15 * sin(phase) + 0.7 * sin(2 * phase) + 0.12 * sin(3 * phase) : 0.4 * sin(phase))
        }
    }

    @Test(arguments: [82.4069, 110.0, 146.8324, 195.9977, 246.9417, 329.6276])
    func detectsSixOpenStrings(_ frequency: Double) throws {
        let estimate = try #require(TunerPitchDetector.estimate(samples: signal(frequency), sampleRate: 48_000))
        #expect(abs(1200 * log2(estimate.frequency / frequency)) < 3)
        #expect(estimate.confidence > 0.85)
    }

    @Test(arguments: [11_025.0, 12_000.0, 44_100.0, 48_000.0])
    func detectsDetunedLowStringAcrossSampleRates(_ rate: Double) throws {
        let frequency = 82.4069 * pow(2, -8.0 / 1200)
        let estimate = try #require(TunerPitchDetector.estimate(samples: signal(frequency, rate: rate), sampleRate: rate))
        #expect(abs(1200 * log2(estimate.frequency / 82.4069) + 8) < 3)
    }

    @Test(arguments: [82.4069, 110.0, 146.8324, 195.9977, 246.9417, 329.6276])
    func strongSecondHarmonicDoesNotHideTheFundamental(_ frequency: Double) throws {
        let estimate = try #require(TunerPitchDetector.estimate(samples: signal(frequency, harmonics: true), sampleRate: 48_000))
        #expect(abs(1200 * log2(estimate.frequency / frequency)) < 4)
    }

    @Test(arguments: [659.2551, 880.0, 950.0, 1046.502])
    func unsupportedHighFundamentalsNeverFoldIntoGuitarTargets(_ frequency: Double) {
        #expect(TunerPitchDetector.estimate(samples: signal(frequency), sampleRate: 48_000) == nil)
    }

    @Test func highPureToneSweepNeverBecomesAGuitarFundamental() {
        for frequency in stride(from: 625.0, through: 1800.0, by: 25) {
            #expect(TunerPitchDetector.estimate(samples: signal(frequency, rate: 12_000), sampleRate: 12_000) == nil)
        }
    }

    @Test func weakHighEWithOnlyASecondHarmonicKeepsItsFundamental() throws {
        let frequency = 329.6276
        let samples: [Float] = (0..<9600).map { i in
            let phase = 2 * Double.pi * frequency * Double(i) / 48_000
            return Float(0.15 * sin(phase) + 0.7 * sin(2 * phase))
        }
        let estimate = try #require(TunerPitchDetector.estimate(samples: samples, sampleRate: 48_000))
        #expect(abs(1200 * log2(estimate.frequency / frequency)) < 4)
    }

    @Test func unsupportedLowFundamentalWithStrongHarmonicIsRejected() {
        #expect(TunerPitchDetector.estimate(samples: signal(41.20345, harmonics: true), sampleRate: 48_000) == nil)
    }

    @Test func rejectsSilenceNoiseAndInvalidBuffers() {
        #expect(TunerPitchDetector.estimate(samples: Array(repeating: 0, count: 8192), sampleRate: 48_000) == nil)
        #expect(TunerPitchDetector.estimate(samples: Array(repeating: 0.2, count: 8192), sampleRate: 48_000) == nil)
        #expect(TunerPitchDetector.estimate(samples: [0, .nan, .infinity], sampleRate: 48_000) == nil)
        #expect(TunerPitchDetector.estimate(samples: signal(110), sampleRate: 0) == nil)
        var seed: UInt64 = 42
        let noise: [Float] = (0..<8192).map { _ in
            seed = seed &* 6364136223846793005 &+ 1
            return Float(Double(seed >> 32) / Double(UInt32.max) - 0.5)
        }
        #expect(TunerPitchDetector.estimate(samples: noise, sampleRate: 48_000) == nil)
    }

    @Test func standardTuningUsesCorrectOctavesAndCalibration() {
        let targets = GuitarTuning.standard.targets
        #expect(targets.map(\.number) == [1, 2, 3, 4, 5, 6])
        #expect(targets.map(\.noteLabel) == ["E₄", "B₃", "G₃", "D₃", "A₂", "E₂"])
        #expect(targets.map(\.noteName) == ["E", "B", "G", "D", "A", "E"])
        #expect(abs(targets[5].frequency(a4: 440) - 82.4069) < 0.001)
        #expect(abs(targets[5].frequency(a4: 442) / targets[5].frequency(a4: 440) - 442.0 / 440) < 0.000001)
        #expect(GuitarTuning.dropD.targets[5].noteLabel == "D₂")
        #expect(GuitarTuning.dadgad.targets[0].noteLabel == "D₄")
    }

    @Test func centsPreserveOctaveAndIntonationHasSixCentTolerance() {
        #expect(abs(TunerIntonation.cents(frequency: 164.8138, target: 82.4069) - 1200) < 0.01)
        #expect(TunerIntonation.classify(cents: -8) == .low)
        #expect(TunerIntonation.classify(cents: 6) == .inTune)
        #expect(TunerIntonation.classify(cents: 7) == .high)
    }

    @Test func referenceToneIsFiniteFadedAndAtRequestedPitch() throws {
        let samples = TunerReferenceTone.samples(frequency: 110, sampleRate: 44_100, duration: 0.3)
        #expect(samples.count == 13_230)
        #expect(abs(samples.first ?? 1) < 0.00001)
        #expect(abs(samples.last ?? 1) < 0.001)
        #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 0.2 })
        let pitch = try #require(TunerPitchDetector.estimate(samples: samples, sampleRate: 44_100))
        #expect(abs(pitch.frequency - 110) < 0.3)
        let wav = TunerReferenceTone.wav(frequency: 110)
        #expect(String(data: wav.prefix(4), encoding: .utf8) == "RIFF")
        #expect(wav.count > 44)
    }
}
