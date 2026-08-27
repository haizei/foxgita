import Foundation

enum RecordMinutes {
    static func display(fromSeconds seconds: Int) -> Int {
        let clamped = max(0, seconds)
        return Int((Double(clamped) / 60.0).rounded(.toNearestOrAwayFromZero))
    }
}

struct RecordTimelineDayGroup: Equatable {
    let dayKey: String
    let items: [PracticeItemSnapshot]
    let totalSeconds: Int
}

struct RecordTimelineState: Equatable {
    let weekInterval: DateInterval
    let days: [RecordTimelineDayGroup]
    let hasAnyEffectiveItem: Bool

    static func make(
        allItems: [PracticeItemSnapshot],
        weekContaining: Date,
        now: Date,
        calendar: Calendar
    ) -> Self {
        let interval = StatsAggregator.week(containing: weekContaining, calendar: calendar)
        let effective = allItems.filter(PracticeItemRules.isEffective)
        let inWeek = effective.filter { item in
            guard let day = RecordTimelineRules.date(fromDayKey: item.practiceDayKey, calendar: calendar)
            else { return false }
            return day >= interval.start && day < interval.end
        }
        let grouped = Dictionary(grouping: inWeek, by: \.practiceDayKey)
        let days = grouped.keys.sorted(by: >).map { key in
            let items = (grouped[key] ?? []).sorted { $0.createdAt > $1.createdAt }
            return RecordTimelineDayGroup(
                dayKey: key,
                items: items,
                totalSeconds: items.reduce(0) { $0 + max(0, $1.durationSeconds) }
            )
        }
        return RecordTimelineState(
            weekInterval: interval,
            days: days,
            hasAnyEffectiveItem: !effective.isEmpty
        )
    }
}

enum RecordTimelineRules {
    static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func weekTitle(interval: DateInterval, calendar: Calendar) -> String {
        let start = interval.start
        let endDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        let sm = calendar.component(.month, from: start)
        let sd = calendar.component(.day, from: start)
        let em = calendar.component(.month, from: endDay)
        let ed = calendar.component(.day, from: endDay)
        if sm == em {
            return "\(sm) 月 \(sd) 日–\(ed) 日"
        }
        return "\(sm) 月 \(sd) 日–\(em) 月 \(ed) 日"
    }

    static func dayTitle(dayKey: String, now: Date, calendar: Calendar) -> String {
        let todayKey = PracticeDayKey.make(from: now, calendar: calendar)
        guard let day = date(fromDayKey: dayKey, calendar: calendar) else { return dayKey }
        let month = calendar.component(.month, from: day)
        let dateNum = calendar.component(.day, from: day)
        let dated = "\(month) 月 \(dateNum) 日"
        if dayKey == todayKey { return "今天 · \(dated)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) {
            if dayKey == PracticeDayKey.make(from: yesterday, calendar: calendar) {
                return "昨天 · \(dated)"
            }
        }
        return dated
    }

    static func shiftWeek(interval: DateInterval, byWeeks: Int, calendar: Calendar) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: byWeeks * 7, to: interval.start) ?? interval.start
        return StatsAggregator.week(containing: start, calendar: calendar)
    }
}
