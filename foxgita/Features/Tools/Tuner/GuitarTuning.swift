import Foundation

nonisolated struct TunerString: Identifiable, Equatable, Sendable {
    let number: Int
    let midiNote: Int
    let usesFlats: Bool
    init(number: Int, midiNote: Int, usesFlats: Bool = false) {
        self.number = number; self.midiNote = midiNote; self.usesFlats = usesFlats
    }
    var id: Int { number }
    var noteName: String { String(noteLabel.dropLast()) }
    var noteLabel: String {
        let names = usesFlats
            ? ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
            : ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let octaves = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈"]
        return names[midiNote % 12] + octaves[midiNote / 12 - 1]
    }
    func frequency(a4: Double) -> Double { a4 * pow(2, Double(midiNote - 69) / 12) }
}

nonisolated enum GuitarTuning: String, CaseIterable, Identifiable, Sendable {
    case standard, dropD, dadgad, halfStepDown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: String(localized: "标准调弦")
        case .dropD: "Drop D"
        case .dadgad: "DADGAD"
        case .halfStepDown: String(localized: "整体降半音")
        }
    }
    var targets: [TunerString] {
        let notes: [Int]
        switch self {
        case .standard: notes = [64, 59, 55, 50, 45, 40]
        case .dropD: notes = [64, 59, 55, 50, 45, 38]
        case .dadgad: notes = [62, 57, 55, 50, 45, 38]
        case .halfStepDown: notes = [63, 58, 54, 49, 44, 39]
        }
        return notes.enumerated().map {
            TunerString(number: $0.offset + 1, midiNote: $0.element, usesFlats: self == .halfStepDown)
        }
    }
    var summary: String {
        title + "  " + targets.reversed().map(\.noteName).joined(separator: " ")
    }
}

nonisolated enum TunerIntonation: Equatable, Sendable {
    case low, inTune, high
    static func cents(frequency: Double, target: Double) -> Double { 1200 * log2(frequency / target) }
    static func classify(cents: Double) -> Self {
        if cents < -6 { return .low }
        if cents > 6 { return .high }
        return .inTune
    }
}
