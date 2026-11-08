import Foundation

nonisolated struct ScoreDaySlice: Equatable, Sendable {
    var dayKey: String
    var seconds: Double
    var date: Date
}
nonisolated enum ScoreDayPartition {
    static func key(_ date: Date,calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year,.month,.day],from: date)
        return String(format: "%04d-%02d-%02d",parts.year ?? 0,parts.month ?? 0,parts.day ?? 0)
    }
    static func split(endingAt end: Date,seconds: Double,calendar: Calendar) -> [ScoreDaySlice] {
        guard seconds.isFinite, seconds > 0, seconds < 7*86_400 else { return [] }
        var result: [ScoreDaySlice] = [], cursor = end.addingTimeInterval(-seconds)
        while cursor < end {
            guard let day = calendar.dateInterval(of: .day,for: cursor) else { break }
            let boundary = min(end,day.end)
            guard boundary > cursor else { break }
            result.append(.init(dayKey: key(cursor,calendar: calendar),seconds: boundary.timeIntervalSince(cursor),date: cursor))
            cursor = boundary
        }
        return result
    }
}
