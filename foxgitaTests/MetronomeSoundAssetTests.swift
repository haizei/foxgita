import AVFoundation
import Testing
@testable import foxgita

struct MetronomeSoundAssetTests {
    @Test func allPresetSamplesMeetTheBundleFormatContract() throws {
        for preset in MetronomeSoundPreset.allCases {
            for name in [preset.beatResourceName, preset.strongResourceName] {
                let url = try #require(Bundle.main.url(forResource: name, withExtension: "wav"))
                let file = try AVAudioFile(forReading: url)
                #expect(file.fileFormat.sampleRate == 44_100)
                #expect(file.fileFormat.channelCount == 1)
                #expect(file.length > 0)
                #expect(Double(file.length) / file.fileFormat.sampleRate <= 0.071)
                #expect(file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int == 16)
            }
        }
    }

    @Test func allPresetSamplesKeepOneDecibelOfPeakHeadroom() throws {
        let maximumPeak = pow(10.0, -1.0 / 20.0)
        for preset in MetronomeSoundPreset.allCases {
            for name in [preset.beatResourceName, preset.strongResourceName] {
                let url = try #require(Bundle.main.url(forResource: name, withExtension: "wav"))
                let file = try AVAudioFile(forReading: url)
                let buffer = try #require(AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(file.length)
                ))
                try file.read(into: buffer)
                let channel = try #require(buffer.floatChannelData?[0])
                var peak = 0.0
                for frame in 0..<Int(buffer.frameLength) {
                    peak = max(peak, Double(abs(channel[frame])))
                }
                #expect(peak <= maximumPeak + 0.000_1, "\(name) peak was \(peak)")
            }
        }
    }
}
