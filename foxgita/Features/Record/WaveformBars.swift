import AVFoundation
import SwiftUI

struct WaveformBars: View {
    let peaks: [Double]
    let progress: Double

    var body: some View {
        let lit = WaveformProgress.highlightCount(progress: progress, barCount: peaks.count)
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(peaks.enumerated()), id: \.offset) { index, peak in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < lit ? GitaTheme.brand500 : GitaTheme.borderInactive)
                    .frame(width: 3, height: max(4, CGFloat(peak) * 28))
            }
        }
        .frame(height: 28)
        .accessibilityLabel("波形")
    }
}

enum WaveformSampler {
    static func peaks(fileURL: URL, barCount: Int) -> [Double] {
        let fallback = Array(repeating: 0.4, count: max(0, barCount))
        guard barCount > 0, let file = try? AVAudioFile(forReading: fileURL) else { return fallback }
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)
        else { return fallback }
        do {
            try file.read(into: buffer)
        } catch {
            return fallback
        }
        guard let channel = buffer.floatChannelData?[0] else { return fallback }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return fallback }
        var samples = [Double](repeating: 0, count: barCount)
        let chunk = max(1, frames / barCount)
        for bar in 0..<barCount {
            let start = bar * chunk
            if start >= frames {
                samples[bar] = 0.15
                continue
            }
            let end = min(frames, start + chunk)
            var peak: Float = 0
            for index in start..<end {
                peak = max(peak, abs(channel[index]))
            }
            samples[bar] = Double(peak)
        }
        let maxPeak = samples.max() ?? 0
        guard maxPeak > 0 else { return Array(repeating: 0.2, count: barCount) }
        return samples.map { max(0.12, $0 / maxPeak) }
    }
}
