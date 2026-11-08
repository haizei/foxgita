import Accelerate
import Foundation

nonisolated enum ScoreInputQuality: String, Codable, Sendable { case reliable, silence, unreliable }
nonisolated struct ScorePitchObservation: Equatable, Sendable {
    var pitches: [Int: Double]
    var rms: Double
    var onset: Bool
    var quality: ScoreInputQuality
}

/// Bounded harmonic-template nonnegative spectral fit. It estimates simultaneous
/// fundamentals; it does not infer physical fingers or uniquely identify strings.
/// FFT API: developer.apple.com/documentation/accelerate/vdsp_dft_zop_createsetup
/// Own one instance on the analysis worker queue, never the audio render callback.
nonisolated final class ScorePitchAnalyzer {
    private struct Template { var midi: Int; var bins: [(Int, Double)]; var norm: Double }
    private let count = 4_096
    private var setup: vDSP_DFT_Setup?
    private var templates: [Template] = []
    private var previousSpectrum: [Double] = []
    private var previousRMS = 0.0
    private var rate = 0.0

    init() { setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(count), .FORWARD) }
    deinit { if let setup { vDSP_DFT_DestroySetup(setup) } }

    func analyze(samples input: [Float], sampleRate: Double) -> ScorePitchObservation {
        let unknown = ScorePitchObservation(pitches: [:], rms: 0, onset: false, quality: .unreliable)
        guard input.count >= count, sampleRate.isFinite, (8_000...96_000).contains(sampleRate), let setup else { return unknown }
        let samples = Array(input.suffix(count))
        guard samples.allSatisfy(\.isFinite) else { return unknown }
        let rms = sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(count))
        guard samples.filter({ abs($0) >= 0.98 }).count < count / 50 else { return unknown }
        if rms < 0.0015 {
            previousRMS = rms
            previousSpectrum = []
            return .init(pitches: [:], rms: rms, onset: false, quality: .silence)
        }
        var real = [Float](repeating: 0, count: count)
        for i in 0..<count { real[i] = samples[i] * Float(0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(count - 1))) }
        let imaginary = [Float](repeating: 0, count: count)
        var outR = [Float](repeating: 0, count: count), outI = outR
        vDSP_DFT_Execute(setup, real, imaginary, &outR, &outI)
        let limit = min(count / 2, Int(5_000 * Double(count) / sampleRate))
        var spectrum = [Double](repeating: 0, count: limit)
        for i in 1..<limit { spectrum[i] = hypot(Double(outR[i]), Double(outI[i])) }
        let peak = spectrum.max() ?? 0
        guard peak > 0 else { return unknown }
        for i in spectrum.indices { spectrum[i] /= peak }
        let mean = spectrum.reduce(0,+) / Double(limit)
        let geometric = exp(spectrum.reduce(0) { $0 + log(max(0.0000001,$1)) } / Double(limit))
        guard mean > 0, geometric / mean < 0.45 else { return unknown }
        let oldPower = previousSpectrum.reduce(0,+)
        var flux = 0.0
        if previousSpectrum.count == spectrum.count {
            for i in spectrum.indices { flux += max(0, spectrum[i] - previousSpectrum[i]) }
        }
        let onset = previousRMS < rms * 0.7 || (oldPower > 0 && flux / oldPower > 0.45)
        previousRMS = rms; previousSpectrum = spectrum
        if rate != sampleRate { rebuildTemplates(rate: sampleRate, limit: limit); rate = sampleRate }
        var residual = spectrum
        var activation = [Double](repeating: 0, count: templates.count)
        for _ in 0..<24 {
            for index in templates.indices {
                let template = templates[index]
                var gradient = 0.0
                for (bin, weight) in template.bins { gradient += residual[bin] * weight }
                let next = max(0, activation[index] + (gradient - 0.015) / template.norm)
                let delta = next - activation[index]
                activation[index] = next
                if abs(delta) > 0.000001 {
                    for (bin, weight) in template.bins { residual[bin] -= delta * weight }
                }
            }
        }
        let maximum = activation.max() ?? 0
        guard maximum > 0.04 else { return unknown }
        let ranked = activation.indices.sorted { activation[$0] > activation[$1] }
        var pitches: [Int: Double] = [:]
        for index in ranked.prefix(6) where activation[index] > max(0.035, maximum * 0.22) {
            pitches[templates[index].midi] = min(1, activation[index] / maximum)
        }
        return .init(pitches: pitches, rms: rms, onset: onset, quality: pitches.isEmpty ? .unreliable : .reliable)
    }

    private func rebuildTemplates(rate: Double, limit: Int) {
        templates = (36...100).map { midi in
            let fundamental = 440 * pow(2, Double(midi - 69) / 12)
            var weights: [Int: Double] = [:]
            for harmonic in 1...7 {
                let bin = fundamental * Double(harmonic) * Double(count) / rate
                if bin >= Double(limit - 3) { break }
                let center = Int(bin.rounded())
                for k in max(1,center-2)...min(limit-1,center+2) {
                    let distance = (Double(k) - bin) / 0.72
                    weights[k, default: 0] += exp(-0.5 * distance * distance) / pow(Double(harmonic),1.3)
                }
            }
            let bins = weights.sorted { $0.key < $1.key }.map { ($0.key,$0.value) }
            return Template(midi: midi, bins: bins, norm: max(0.0001, bins.reduce(0) { $0 + $1.1 * $1.1 }))
        }
    }
}
