import Foundation

enum RecordHistoryGranularity: Hashable {
    case week, month, year
}

struct RecordCalendarCell: Equatable {
    let dayKey: String?
    let dayNumber: Int
    let minutesLabel: String
    let isCurrentMonth: Bool
    let isFuture: Bool
}

struct RecordDaySummary: Equatable {
    let dayKey: String
    let totalSeconds: Int
    let joinedTitles: String
    let typeLabels: [String]
}

struct RecordTypeShare: Equatable {
    let category: PracticeCategory
    let seconds: Int
}

struct RecordStatsState: Equatable {
    let totalSeconds: Int
    let practiceDayCount: Int
    let longestStreak: Int
    let deltaSeconds: Int?
    let bars: [(label: String, seconds: Int)]
    let typeShares: [RecordTypeShare]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.totalSeconds == rhs.totalSeconds
            && lhs.practiceDayCount == rhs.practiceDayCount
            && lhs.longestStreak == rhs.longestStreak
            && lhs.deltaSeconds == rhs.deltaSeconds
            && lhs.bars.map(\.label) == rhs.bars.map(\.label)
            && lhs.bars.map(\.seconds) == rhs.bars.map(\.seconds)
            && lhs.typeShares == rhs.typeShares
    }
}

enum RecordHistoryRules {
    static func calendarCells(
        monthContaining: Date,
        now: Date,
        calendar: Calendar,
        effectiveItems: [PracticeItemSnapshot]
    ) -> [RecordCalendarCell] {
        let today = calendar.startOfDay(for: now)
        let secondsByDay = secondsByDayKey(effectiveItems)
        let comps = calendar.dateComponents([.year, .month], from: monthContaining)
        guard let monthStart = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: monthStart)
        else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let pad = (weekday + 5) % 7
        var dates: [Date] = []
        if pad > 0, let first = calendar.date(byAdding: .day, value: -pad, to: monthStart) {
            for offset in 0..<pad {
                if let d = calendar.date(byAdding: .day, value: offset, to: first) {
                    dates.append(d)
                }
            }
        }
        for day in range {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                dates.append(d)
            }
        }
        while dates.count % 7 != 0 {
            if let last = dates.last, let extra = calendar.date(byAdding: .day, value: 1, to: last) {
                dates.append(extra)
            } else { break }
        }
        let month = calendar.component(.month, from: monthStart)
        return dates.map { date in
            let start = calendar.startOfDay(for: date)
            let key = PracticeDayKey.make(from: start, calendar: calendar)
            let seconds = secondsByDay[key] ?? 0
            let label = seconds > 0 ? "\(RecordMinutes.display(fromSeconds: seconds))m" : "·"
            return RecordCalendarCell(
                dayKey: key,
                dayNumber: calendar.component(.day, from: date),
                minutesLabel: label,
                isCurrentMonth: calendar.component(.month, from: date) == month,
                isFuture: start > today
            )
        }
    }

    static func daySummary(dayKey: String, items: [PracticeItemSnapshot]) -> RecordDaySummary? {
        let dayItems = items
            .filter { $0.practiceDayKey == dayKey && PracticeItemRules.isEffective($0) }
            .sorted { $0.createdAt > $1.createdAt }
        guard !dayItems.isEmpty else { return nil }
        var labels: [String] = []
        var seen = Set<String>()
        for item in dayItems {
            guard let category = PracticeCategory(rawValue: item.categoryRaw),
                  seen.insert(category.rawValue).inserted
            else { continue }
            labels.append(category.label)
        }
        return RecordDaySummary(
            dayKey: dayKey,
            totalSeconds: dayItems.reduce(0) { $0 + max(0, $1.durationSeconds) },
            joinedTitles: dayItems.map(\.title).joined(separator: " · "),
            typeLabels: labels
        )
    }

    static func monthMetrics(
        monthContaining: Date,
        calendar: Calendar,
        items: [PracticeItemSnapshot]
    ) -> (days: Int, seconds: Int, longestStreak: Int) {
        let keys = dayKeys(inMonthContaining: monthContaining, calendar: calendar, items: items)
        let seconds = items
            .filter { keys.contains($0.practiceDayKey) && PracticeItemRules.isEffective($0) }
            .reduce(0) { $0 + max(0, $1.durationSeconds) }
        return (keys.count, seconds, longestStreak(in: keys, calendar: calendar))
    }

    static func stats(
        granularity: RecordHistoryGranularity,
        containing: Date,
        now: Date,
        calendar: Calendar,
        items: [PracticeItemSnapshot]
    ) -> RecordStatsState {
        let interval = period(granularity: granularity, containing: containing, calendar: calendar)
        let effective = items.filter(PracticeItemRules.isEffective)
        let current = effective.filter { inPeriod($0, interval: interval, calendar: calendar) }
        let previousInterval = shifted(interval, by: -1, granularity: granularity, calendar: calendar)
        let previous = effective.filter { inPeriod($0, interval: previousInterval, calendar: calendar) }
        let currentSeconds = current.reduce(0) { $0 + max(0, $1.durationSeconds) }
        let previousSeconds = previous.reduce(0) { $0 + max(0, $1.durationSeconds) }
        let delta: Int? = (currentSeconds == 0 && previousSeconds == 0) ? nil : currentSeconds - previousSeconds
        return RecordStatsState(
            totalSeconds: currentSeconds,
            practiceDayCount: Set(current.map(\.practiceDayKey)).count,
            longestStreak: longestStreak(in: Set(current.map(\.practiceDayKey)), calendar: calendar),
            deltaSeconds: delta,
            bars: bars(granularity: granularity, interval: interval, calendar: calendar, items: current),
            typeShares: typeShares(in: current)
        )
    }

    static func shiftPeriod(
        granularity: RecordHistoryGranularity,
        containing: Date,
        by: Int,
        calendar: Calendar
    ) -> Date {
        switch granularity {
        case .week:
            return calendar.date(byAdding: .day, value: by * 7, to: containing) ?? containing
        case .month:
            return calendar.date(byAdding: .month, value: by, to: containing) ?? containing
        case .year:
            return calendar.date(byAdding: .year, value: by, to: containing) ?? containing
        }
    }

    static func weekStart(forDayKey dayKey: String, calendar: Calendar) -> Date? {
        guard let date = RecordTimelineRules.date(fromDayKey: dayKey, calendar: calendar) else { return nil }
        return StatsAggregator.week(containing: date, calendar: calendar).start
    }

    private static func secondsByDayKey(_ items: [PracticeItemSnapshot]) -> [String: Int] {
        Dictionary(grouping: items.filter(PracticeItemRules.isEffective), by: \.practiceDayKey)
            .mapValues { $0.reduce(0) { $0 + max(0, $1.durationSeconds) } }
    }

    private static func dayKeys(
        inMonthContaining date: Date,
        calendar: Calendar,
        items: [PracticeItemSnapshot]
    ) -> Set<String> {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        return Set(
            items.filter { item in
                guard PracticeItemRules.isEffective(item),
                      let day = RecordTimelineRules.date(fromDayKey: item.practiceDayKey, calendar: calendar)
                else { return false }
                return calendar.component(.month, from: day) == month
                    && calendar.component(.year, from: day) == year
            }.map(\.practiceDayKey)
        )
    }

    private static func longestStreak(in keys: Set<String>, calendar: Calendar) -> Int {
        let dates = keys.compactMap { RecordTimelineRules.date(fromDayKey: $0, calendar: calendar) }
            .map { calendar.startOfDay(for: $0) }
            .sorted()
        guard !dates.isEmpty else { return 0 }
        var best = 1
        var run = 1
        for index in 1..<dates.count {
            let gap = calendar.dateComponents([.day], from: dates[index - 1], to: dates[index]).day ?? 0
            if gap == 1 {
                run += 1
                best = max(best, run)
            } else if gap > 1 {
                run = 1
            }
        }
        return best
    }

    private static func period(
        granularity: RecordHistoryGranularity,
        containing: Date,
        calendar: Calendar
    ) -> DateInterval {
        switch granularity {
        case .week:
            return StatsAggregator.week(containing: containing, calendar: calendar)
        case .month:
            return calendar.dateInterval(of: .month, for: containing)
                ?? DateInterval(start: containing, duration: 86400)
        case .year:
            return calendar.dateInterval(of: .year, for: containing)
                ?? DateInterval(start: containing, duration: 86400)
        }
    }

    private static func shifted(
        _ interval: DateInterval,
        by: Int,
        granularity: RecordHistoryGranularity,
        calendar: Calendar
    ) -> DateInterval {
        period(
            granularity: granularity,
            containing: shiftPeriod(granularity: granularity, containing: interval.start, by: by, calendar: calendar),
            calendar: calendar
        )
    }

    private static func inPeriod(
        _ item: PracticeItemSnapshot,
        interval: DateInterval,
        calendar: Calendar
    ) -> Bool {
        guard let day = RecordTimelineRules.date(fromDayKey: item.practiceDayKey, calendar: calendar)
        else { return false }
        return day >= interval.start && day < interval.end
    }

    private static func bars(
        granularity: RecordHistoryGranularity,
        interval: DateInterval,
        calendar: Calendar,
        items: [PracticeItemSnapshot]
    ) -> [(label: String, seconds: Int)] {
        let seconds = secondsByDayKey(items)
        switch granularity {
        case .week:
            return (0..<7).map { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: interval.start) ?? interval.start
                let key = PracticeDayKey.make(from: day, calendar: calendar)
                return (StatsAggregator.weekdaySymbols[offset], seconds[key] ?? 0)
            }
        case .month:
            var cursor = interval.start
            var result: [(String, Int)] = []
            while cursor < interval.end {
                let key = PracticeDayKey.make(from: cursor, calendar: calendar)
                result.append(("\(calendar.component(.day, from: cursor))", seconds[key] ?? 0))
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? interval.end
            }
            return result
        case .year:
            return (1...12).map { month in
                let monthSeconds = items.reduce(0) { total, item in
                    guard let day = RecordTimelineRules.date(fromDayKey: item.practiceDayKey, calendar: calendar),
                          calendar.component(.month, from: day) == month
                    else { return total }
                    return total + max(0, item.durationSeconds)
                }
                return ("\(month)", monthSeconds)
            }
        }
    }

    private static func typeShares(in items: [PracticeItemSnapshot]) -> [RecordTypeShare] {
        var bucket: [PracticeCategory: Int] = [:]
        for item in items {
            guard let category = PracticeCategory(rawValue: item.categoryRaw) else { continue }
            bucket[category, default: 0] += max(0, item.durationSeconds)
        }
        return bucket
            .map { RecordTypeShare(category: $0.key, seconds: $0.value) }
            .filter { $0.seconds > 0 }
            .sorted { $0.seconds > $1.seconds }
    }
}
