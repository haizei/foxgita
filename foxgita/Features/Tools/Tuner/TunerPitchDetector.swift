import Accelerate
import Foundation

nonisolated struct TunerPitchEstimate: Equatable, Sendable {
    let frequency: Double
    let confidence: Double
}

/// YIN difference / cumulative mean normalized difference, with fractional-lag
/// interpolation. Analysis is bounded to 1,024 samples at at most 12 kHz.
/// Reference: de Cheveigné & Kawahara, JASA 111 (2002), 1917–1930.
nonisolated enum TunerPitchDetector {
    static let analysisSampleCount = 1024

    static func estimate(samples input: [Float], sampleRate: Double) -> TunerPitchEstimate? {
        guard sampleRate.isFinite, (4_000...192_000).contains(sampleRate), input.count >= 512 else { return nil }
        let factor = max(1, Int(ceil(sampleRate / 12_000)))
        let raw = input.suffix(analysisSampleCount * factor)
        guard raw.allSatisfy(\.isFinite) else { return nil }
        var samples = [Double]()
        samples.reserveCapacity(raw.count / factor)
        var sum = 0.0, count = 0
        for value in raw {
            sum += Double(value)
            count += 1
            if count == factor {
                samples.append(sum / Double(factor))
                sum = 0; count = 0
            }
        }
        let rate = sampleRate / Double(factor)
        let window = samples.count / 2
        // Search the first true period before applying the supported guitar range.
        // Starting at 600 Hz's lag can mistake E5's second period for an E4.
        let maxLag = min(window - 2, Int(rate / 30))
        let minLag = 2
        guard window >= 256, maxLag > minLag + 2 else { return nil }
        let mean = samples.reduce(0, +) / Double(samples.count)
        for i in samples.indices { samples[i] -= mean }
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count))
        guard rms >= 0.0002 else { return nil }

        var normalized = Array(repeating: 1.0, count: maxLag + 2)
        var running = 0.0
        samples.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!
            for lag in 1...maxLag + 1 {
                var difference = 0.0
                vDSP_distancesqD(base, 1, base.advanced(by: lag), 1, &difference, vDSP_Length(window))
                running += difference
                normalized[lag] = running > 0 ? difference * Double(lag) / running : 1
            }
        }
        var candidate: Int?
        var lag = minLag
        while lag <= maxLag {
            if normalized[lag] < 0.10 {
                while lag < maxLag, normalized[lag + 1] < normalized[lag] { lag += 1 }
                candidate = lag
                break
            }
            lag += 1
        }
        guard var best = candidate else { return nil }
        func interpolatedFrequency(at lag: Int) -> Double {
            let left = normalized[lag - 1], mid = normalized[lag], right = normalized[lag + 1]
            let denominator = 2 * (left - 2 * mid + right)
            let shift = abs(denominator) > 1e-12 ? max(-1, min(1, (left - right) / denominator)) : 0
            return rate / (Double(lag) + shift)
        }
        let left = normalized[best - 1], mid = normalized[best], right = normalized[best + 1]
        let curvature = left - 2 * mid + right
        let fittedMinimum = curvature > 1e-12 ? mid - pow(left - right, 2) / (8 * curvature) : mid
        // A strong second/third harmonic may create an early shallow minimum.
        // Use fitted residual, since integer-lag error also makes a pure tone's
        // later period look cleaner. Pure tones must retain their real octave.
        if fittedMinimum > 0.03 {
            for multiple in 2...3 {
                let center = best * multiple
                guard center + 2 <= maxLag else { continue }
                let range = max(minLag, center - 2)...min(maxLag, center + 2)
                if let longer = range.min(by: { normalized[$0] < normalized[$1] }),
                   normalized[longer] < normalized[best] * 0.2 {
                    best = longer
                    break
                }
            }
        }
        let frequency = interpolatedFrequency(at: best)
        guard frequency.isFinite, (55...600).contains(frequency) else { return nil }
        return TunerPitchEstimate(frequency: frequency, confidence: max(0, min(1, 1 - normalized[best])))
    }
}
