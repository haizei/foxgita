import Foundation

nonisolated enum OriginalScoreError: Error, LocalizedError {
    case invalidDocument, invalidRow, invalidRange, missingVersion, conflict, unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .invalidDocument: "请检查曲名、谱页、拍号与速度（40–200 BPM）。"
        case .invalidRow: "请检查谱行区域和总拍数，拍数最少 0.5 拍、按半拍递增。"
        case .invalidRange: "练习范围已失效，请重新选择谱行。"
        case .missingVersion: "找不到对应原谱版本或谱页。"
        case .conflict: "原谱已有新版本，请重新打开后修订。标记草稿已保留。"
        case .unsupportedVersion: "原谱库版本不兼容，请升级 App。原文件已保留。"
        }
    }
}

nonisolated struct OriginalScoreBox: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite)
            && x >= 0 && y >= 0 && width > 0 && height > 0
            && x + width <= 1.000001 && y + height <= 1.000001
    }
}

nonisolated struct OriginalScoreRow: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var page: Int
    var box: OriginalScoreBox
    var beats: Double
}

nonisolated struct OriginalScoreRange: Codable, Equatable, Sendable {
    var first: UUID
    var last: UUID
}

nonisolated struct OriginalScoreDocument: Codable, Identifiable, Equatable, Sendable {
    // Keeps half-beats exact and seconds/host-frame conversions representable,
    // including the slowest tempo. This exceeds any practical 20-page score.
    static let maximumBeats = 1_000_000_000.0
    var id = UUID()
    var versionID = UUID()
    var parentVersionID: UUID?
    var sourceID = UUID()
    var title: String
    var pageCount: Int
    var numerator = 4
    var denominator = 4
    /// Zero-based position in a bar, measured in denominator beats.
    var startingBeat = 0.0
    var initialBPM = 80.0
    var rows: [OriginalScoreRow] = []
    var createdAt = Date()
    var manuallyOrdered: Bool? = nil

    var fullRange: OriginalScoreRange? {
        guard let first = rows.first, let last = rows.last else { return nil }
        return .init(first: first.id, last: last.id)
    }
    var totalBeats: Double { rows.reduce(0) { $0 + $1.beats } }
    var rowNumbers: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset + 1) })
    }

    func validate(allowEmpty: Bool = false) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 120,
              (1...20).contains(pageCount), (2...12).contains(numerator), [2, 4, 8, 16].contains(denominator),
              initialBPM.isFinite, (40...200).contains(initialBPM),
              startingBeat.isFinite, startingBeat >= 0, startingBeat < Double(numerator),
              Self.isHalfBeat(startingBeat), (allowEmpty || !rows.isEmpty),
              Set(rows.map(\.id)).count == rows.count else { throw OriginalScoreError.invalidDocument }
        for row in rows {
            guard (0..<pageCount).contains(row.page), row.box.isValid, row.beats.isFinite,
                  row.beats >= 0.5, Self.isHalfBeat(row.beats) else { throw OriginalScoreError.invalidRow }
        }
        guard totalBeats.isFinite, totalBeats <= Self.maximumBeats else { throw OriginalScoreError.invalidRow }
    }

    static func isHalfBeat(_ value: Double) -> Bool {
        value.isFinite && (value * 2).isFinite && value * 2 == (value * 2).rounded()
    }

    func indices(for range: OriginalScoreRange) throws -> ClosedRange<Int> {
        guard let first = rows.firstIndex(where: { $0.id == range.first }),
              let last = rows.firstIndex(where: { $0.id == range.last }), first <= last else {
            throw OriginalScoreError.invalidRange
        }
        return first...last
    }

    func beats(before rowID: UUID) throws -> Double {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { throw OriginalScoreError.invalidRange }
        return rows.prefix(index).reduce(0) { $0 + $1.beats }
    }

    func phase(rowID: UUID, beat: Double) throws -> Double {
        (startingBeat + (try beats(before: rowID)) + beat).truncatingRemainder(dividingBy: Double(numerator))
    }

    func duration(of rowID: UUID, bpm: Double) throws -> Double {
        guard bpm.isFinite, (40...200).contains(bpm), let row = rows.first(where: { $0.id == rowID }) else {
            throw OriginalScoreError.invalidRange
        }
        return row.beats * 60 / bpm
    }

    mutating func sortRows() {
        rows = rows.enumerated().sorted {
            if $0.element.page != $1.element.page { return $0.element.page < $1.element.page }
            if $0.element.box.y != $1.element.box.y { return $0.element.box.y < $1.element.box.y }
            if $0.element.box.x != $1.element.box.x { return $0.element.box.x < $1.element.box.x }
            return $0.offset < $1.offset
        }.map(\.element)
    }

    func hasSameTiming(as other: Self) -> Bool {
        numerator == other.numerator && denominator == other.denominator && startingBeat == other.startingBeat
            && rows.map(\.id) == other.rows.map(\.id) && rows.map(\.beats) == other.rows.map(\.beats)
    }
}
