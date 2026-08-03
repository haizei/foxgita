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
        guard let lastAt else { return "尚未练习" }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: lastAt),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0
        if days == 0 { return "今天" }
        if days == 1 { return "昨天" }
        return "\(days) 天前"
    }
}

struct DaySummary {
    let dayStart: Date
    let totalMinutes: Int
    let categories: [PracticeCategory]
    let sessions: [PracticeSession]
}

enum StatsAggregator {
    static func streakDays(from sessions: [PracticeSession], now: Date = .now) -> Int {
        let cal = Calendar.current
        let days = Set(sessions.map { cal.startOfDay(for: $0.endedAt) })
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
        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else {
            return labels.map { ($0, .empty) }
        }
        // Make Monday-first
        var start = week.start
        let wd = cal.component(.weekday, from: start) // 1=Sun
        if wd != 2 {
            let shift = (wd + 5) % 7
            start = cal.date(byAdding: .day, value: -shift, to: start) ?? start
        }
        let today = cal.startOfDay(for: now)
        return (0..<7).map { i in
            let day = cal.date(byAdding: .day, value: i, to: start).map { cal.startOfDay(for: $0) } ?? today
            let practiced = sessions.contains { cal.isDate($0.endedAt, inSameDayAs: day) }
            let label = labels[i]
            if day > today { return (label, .future) }
            if cal.isDate(day, inSameDayAs: today) { return (label, practiced ? .done : .today) }
            return (label, practiced ? .done : .empty)
        }
    }

    static func weekPracticeCount(from sessions: [PracticeSession], now: Date = .now) -> Int {
        weekDots(from: sessions, now: now).filter { $0.1 == .done || ($0.1 == .today) }.count
    }

    static func aggregate(tasks: [TaskItem], sessions: [PracticeSession]) -> [TaskAggregate] {
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
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
}
