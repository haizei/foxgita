//
//  StatsAggregator.swift
//  foxgita
//

import Foundation

struct TaskAggregate: Identifiable {
    let id: String
    let task: TaskItem
    let weekCount: Int
    let totalMinutes: Int
    let lastAt: Date?
    let sessionCount: Int

    var lastLabel: String {
        guard let lastAt else { return String(localized: "尚未练习") }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: lastAt),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0
        if days == 0 { return String(localized: "今天") }
        if days == 1 { return String(localized: "昨天") }
        return String(localized: "\(days) 天前")
    }
}

struct DaySummary {
    let dayStart: Date
    let totalMinutes: Int
    let categories: [PracticeCategory]
    let sessions: [PracticeSession]
}

enum StatsAggregator {
    /// Weekday symbols in the user's locale, reordered so Monday comes first.
    static var weekdaySymbols: [String] {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        return Array(symbols[1...6]) + [symbols[0]]
    }

    /// One cell in the home week strip: weekday label + calendar day number.
    struct WeekDay: Identifiable, Equatable {
        var id: Date { date }
        let date: Date
        let weekdayLabel: String
        let dayNumber: Int
        let isToday: Bool
        let isFuture: Bool
        let practiced: Bool
    }

    struct DayTaskGroup: Identifiable, Equatable {
        var id: String { taskId }
        let taskId: String
        let title: String
        let totalMinutes: Int
        let category: PracticeCategory
    }

    static func weekDays(
        from sessions: [PracticeSession],
        containing weekDate: Date = .now,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [WeekDay] {
        let labels = weekdaySymbols
        let start = week(containing: weekDate, calendar: calendar).start
        let today = calendar.startOfDay(for: now)
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? today
            let practiced = sessions.contains {
                $0.isEffective && calendar.isDate($0.endedAt, inSameDayAs: date)
            }
            return WeekDay(
                date: date,
                weekdayLabel: labels[offset],
                dayNumber: calendar.component(.day, from: date),
                isToday: calendar.isDate(date, inSameDayAs: today),
                isFuture: date > today,
                practiced: practiced
            )
        }
    }

    static func weekDays(
        checkedInDayKeys: Set<String>,
        containing weekDate: Date = .now,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [WeekDay] {
        let labels = weekdaySymbols
        let start = week(containing: weekDate, calendar: calendar).start
        let today = calendar.startOfDay(for: now)
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start) ?? today
            let practiced = checkedInDayKeys.contains(
                PracticeDayKey.make(from: date, calendar: calendar)
            )
            return WeekDay(
                date: date,
                weekdayLabel: labels[offset],
                dayNumber: calendar.component(.day, from: date),
                isToday: calendar.isDate(date, inSameDayAs: today),
                isFuture: date > today,
                practiced: practiced
            )
        }
    }

    static func dayTaskGroups(
        sessions: [PracticeSession],
        on day: Date,
        calendar: Calendar = .current
    ) -> [DayTaskGroup] {
        let effective = sessions.filter {
            $0.isEffective && calendar.isDate($0.endedAt, inSameDayAs: day)
        }
        let grouped = Dictionary(grouping: effective, by: \.taskId)
        return grouped.map { taskId, items in
            let latest = items.max(by: { $0.endedAt < $1.endedAt })!
            return DayTaskGroup(
                taskId: taskId,
                title: latest.taskTitle,
                totalMinutes: items.reduce(0) { $0 + $1.durationMinutes },
                category: latest.category
            )
        }
        .sorted { lhs, rhs in
            let left = grouped[lhs.taskId]!.map(\.endedAt).max()!
            let right = grouped[rhs.taskId]!.map(\.endedAt).max()!
            return left > right
        }
    }

    /// Mondays from `weeks` lookback through the week containing `now` (inclusive).
    static func weekStarts(
        back weeks: Int,
        from now: Date = .now,
        calendar: Calendar = .current
    ) -> [Date] {
        let current = week(containing: now, calendar: calendar).start
        return (0...weeks).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset * 7, to: current)
        }
    }

    /// Keep `selected` when it already sits in the week; otherwise today (if
    /// that week contains today) or the week's Monday.
    static func clampedDay(
        selected: Date,
        inWeekStarting weekStart: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let interval = week(containing: weekStart, calendar: calendar)
        let day = calendar.startOfDay(for: selected)
        // DateInterval.contains is closed at `end` (next Monday 00:00), so a
        // Monday would otherwise still belong to the previous week.
        if day >= interval.start && day < interval.end { return day }
        let today = calendar.startOfDay(for: now)
        if today >= interval.start && today < interval.end { return today }
        return calendar.startOfDay(for: interval.start)
    }


    static func weekdaySymbol(for date: Date, calendar: Calendar = .current) -> String {
        weekdaySymbols[mondayOffset(of: date, calendar: calendar)]
    }

    /// Monday-first week containing `now`. The app presents every week starting
    /// on Monday, so this is used instead of the locale's week definition.
    static func week(containing now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -mondayOffset(of: today, calendar: calendar), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    /// 0 for Monday … 6 for Sunday.
    private static func mondayOffset(of date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7 // .weekday is 1 = Sunday
    }

    static func streakDays(from sessions: [PracticeSession], now: Date = .now) -> Int {
        let cal = Calendar.current
        let days = Set(
            sessions.filter(\.isEffective).map { cal.startOfDay(for: $0.endedAt) }
        )
        var cursor = cal.startOfDay(for: now)
        if !days.contains(cursor) {
            guard let y = cal.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = y
            if !days.contains(cursor) { return 0 }
        }
        var n = 0
        while days.contains(cursor) {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
    }

    /// Mon…Sun of current week: done / today / future
    enum WeekDot { case done, today, future, empty }

    static func weekDots(from sessions: [PracticeSession], now: Date = .now) -> [(String, WeekDot)] {
        let cal = Calendar.current
        let labels = weekdaySymbols
        let start = week(containing: now, calendar: cal).start
        let today = cal.startOfDay(for: now)
        return (0..<7).map { i in
            let day = cal.date(byAdding: .day, value: i, to: start) ?? today
            let practiced = sessions.contains {
                $0.isEffective && cal.isDate($0.endedAt, inSameDayAs: day)
            }
            let label = labels[i]
            if cal.isDate(day, inSameDayAs: today) { return (label, practiced ? .done : .today) }
            if day > today { return (label, .future) }
            return (label, practiced ? .done : .empty)
        }
    }

    static func weekPracticeCount(from sessions: [PracticeSession], now: Date = .now) -> Int {
        weekDots(from: sessions, now: now).filter { $0.1 == .done || ($0.1 == .today) }.count
    }

    static func aggregate(tasks: [TaskItem], sessions: [PracticeSession]) -> [TaskAggregate] {
        let weekStart = week().start
        return tasks.map { task in
            let related = sessions.filter { $0.taskId == task.id }
            return TaskAggregate(
                id: task.id, task: task,
                weekCount: related.filter { $0.endedAt >= weekStart }.count,
                totalMinutes: related.reduce(0) { $0 + $1.durationMinutes },
                lastAt: related.map(\.endedAt).max(),
                sessionCount: related.count
            )
        }
        .sorted { ($0.lastAt ?? .distantPast) > ($1.lastAt ?? .distantPast) }
    }

    static func daySummaries(sessions: [PracticeSession], month: Date) -> [Date: DaySummary] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let monthStart = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: monthStart) else { return [:] }
        var result: [Date: DaySummary] = [:]
        for d in range {
            guard let date = cal.date(byAdding: .day, value: d - 1, to: monthStart) else { continue }
            let start = cal.startOfDay(for: date)
            let daySessions = sessions.filter { cal.isDate($0.endedAt, inSameDayAs: start) }
            guard !daySessions.isEmpty else { continue }
            var seen = Set<String>()
            var cats: [PracticeCategory] = []
            for s in daySessions where seen.insert(s.categoryRaw).inserted {
                cats.append(s.category)
            }
            result[start] = DaySummary(
                dayStart: start,
                totalMinutes: daySessions.reduce(0) { $0 + $1.durationMinutes },
                categories: cats,
                sessions: daySessions
            )
        }
        return result
    }

    static func minutesByDay(sessions: [PracticeSession], in interval: DateInterval) -> [(Date, Int)] {
        let cal = Calendar.current
        var cursor = cal.startOfDay(for: interval.start)
        let end = cal.startOfDay(for: interval.end)
        var points: [(Date, Int)] = []
        while cursor < end {
            let mins = sessions.filter { cal.isDate($0.endedAt, inSameDayAs: cursor) }
                .reduce(0) { $0 + $1.durationMinutes }
            points.append((cursor, mins))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return points
    }

    static func totalMinutes(_ sessions: [PracticeSession], in interval: DateInterval) -> Int {
        sessions.filter { $0.endedAt >= interval.start && $0.endedAt < interval.end }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    /// Minutes in `interval` compared with the equally long span before it.
    static func deltaLabel(_ sessions: [PracticeSession], in interval: DateInterval) -> String {
        let current = totalMinutes(sessions, in: interval)
        let previous = totalMinutes(
            sessions,
            in: DateInterval(
                start: interval.start.addingTimeInterval(-interval.duration),
                end: interval.start
            )
        )
        guard previous > 0 else { return current > 0 ? String(localized: "新增") : "—" }
        let pct = Int((Double(current - previous) / Double(previous) * 100).rounded())
        return pct >= 0 ? "+\(pct)%" : "\(pct)%"
    }
}
