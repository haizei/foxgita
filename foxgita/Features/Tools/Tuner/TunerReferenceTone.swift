import Foundation

nonisolated enum TunerReferenceTone {
    static func samples(frequency: Double, sampleRate: Double = 44_100, duration: Double = 1.8) -> [Float] {
        guard frequency.isFinite, (40...1000).contains(frequency), sampleRate >= 4_000,
              sampleRate.isFinite, duration.isFinite, (0.05...3).contains(duration) else { return [] }
        let count = Int(sampleRate * duration)
        let fade = Int(sampleRate * 0.02)
        return (0..<count).map { i in
            let envelope = min(1, Double(min(i, count - 1 - i)) / Double(fade))
            return Float(0.18 * envelope * sin(2 * .pi * frequency * Double(i) / sampleRate))
        }
    }

    static func wav(frequency: Double) -> Data {
        let values = samples(frequency: frequency)
        var data = Data()
        func append<T: FixedWidthInteger>(_ number: T) {
            var value = number.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); append(UInt32(36 + values.count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(44_100)); append(UInt32(88_200)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: "data".utf8); append(UInt32(values.count * 2))
        for sample in values { append(Int16((sample * Float(Int16.max)).rounded())) }
        return data
    }
}
