//
//  StatsAggregatorTests.swift
//  foxgitaTests
//

import Foundation
import SwiftData
import Testing

@testable import foxgita

@MainActor
struct StatsAggregatorTests {
    /// Fixed anchor so day/week arithmetic never depends on when tests run.
    nonisolated private static let anchor = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema([TaskItem.self, PracticeSession.self, RecordingRef.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @discardableResult
    private func insertSession(
        endedAt: Date,
        minutes: Int,
        taskId: String = "task",
        taskTitle: String = "练习",
        note: String = "",
        category: PracticeCategory = .chord,
        into context: ModelContext
    ) -> PracticeSession {
        let session = PracticeSession(
            taskId: taskId,
            taskTitle: taskTitle,
            category: category,
            startedAt: endedAt.addingTimeInterval(-Double(minutes) * 60),
            endedAt: endedAt,
            durationSec: minutes * 60,
            bpm: 80,
            timeSig: "4/4",
            steps: [],
            noteText: note
        )
        context.insert(session)
        return session
    }

    private func day(_ offset: Int, from base: Date = StatsAggregatorTests.anchor) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: base)!
    }

    // MARK: - streakDays

    @Test func streakCountsConsecutiveDaysEndingToday() throws {
        let context = try makeContext()
        for offset in [0, -1, -2] {
            insertSession(endedAt: day(offset), minutes: 10, into: context)
        }
        #expect(StatsAggregator.streakDays(from: sessions(in: context), now: Self.anchor) == 3)
    }

    @Test func streakStopsAtFirstGap() throws {
        let context = try makeContext()
        for offset in [0, -1, -3] {
            insertSession(endedAt: day(offset), minutes: 10, into: context)
        }
        #expect(StatsAggregator.streakDays(from: sessions(in: context), now: Self.anchor) == 2)
    }

    @Test func streakSurvivesAnUnpracticedToday() throws {
        let context = try makeContext()
        for offset in [-1, -2] {
            insertSession(endedAt: day(offset), minutes: 10, into: context)
        }
        #expect(StatsAggregator.streakDays(from: sessions(in: context), now: Self.anchor) == 2)
    }

    @Test func streakBreaksAfterTwoIdleDays() throws {
        let context = try makeContext()
        insertSession(endedAt: day(-2), minutes: 10, into: context)
        #expect(StatsAggregator.streakDays(from: sessions(in: context), now: Self.anchor) == 0)
    }

    @Test func streakOfNothingIsZero() throws {
        #expect(StatsAggregator.streakDays(from: [], now: Self.anchor) == 0)
    }

    @Test func weekDaysIgnoresIneffectiveSessions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let context = try makeContext()
        let tuesday = calendar.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 12))!
        let friday = calendar.date(from: DateComponents(year: 2023, month: 11, day: 17))!
        insertSession(endedAt: tuesday, minutes: 0, into: context)

        let days = StatsAggregator.weekDays(
            from: sessions(in: context),
            containing: tuesday,
            now: friday,
            calendar: calendar
        )
        #expect(days.filter(\.practiced).isEmpty)
    }

    @Test func streakIgnoresADayWithOnlyEmptySessions() throws {
        let context = try makeContext()
        insertSession(endedAt: day(0), minutes: 0, into: context)
        insertSession(endedAt: day(-1), minutes: 10, into: context)
        #expect(StatsAggregator.streakDays(from: sessions(in: context), now: Self.anchor) == 1)
    }

    // MARK: - week dots

    @Test func weekDotsCoverSevenDaysWithOneToday() throws {
        let context = try makeContext()
        insertSession(endedAt: Date(), minutes: 10, into: context)
        let dots = StatsAggregator.weekDots(from: sessions(in: context))
        #expect(dots.count == 7)
        #expect(dots.filter { $0.1 == .today }.isEmpty) // practiced today, so it reads as done
        #expect(dots.contains { $0.1 == .done })
    }

    @Test func weekDotsMarkAnUnpracticedTodayAsToday() {
        let dots = StatsAggregator.weekDots(from: [])
        #expect(dots.filter { $0.1 == .today }.count == 1)
        #expect(dots.contains { $0.1 == .done } == false)
    }

    // MARK: - weekday symbols

    @Test func weekdaySymbolsStartOnMonday() {
        let symbols = StatsAggregator.weekdaySymbols
        #expect(symbols.count == 7)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2023-11-13 is a Monday.
        let monday = calendar.date(from: DateComponents(year: 2023, month: 11, day: 13))!
        #expect(StatsAggregator.weekdaySymbol(for: monday, calendar: calendar) == symbols[0])

        let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
        #expect(StatsAggregator.weekdaySymbol(for: sunday, calendar: calendar) == symbols[6])
    }

    // MARK: - week boundaries

    @Test func weekStartsOnMondayEvenWhereTheLocaleStartsOnSunday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        // 2023-11-19 is a Sunday; its Monday-first week began on the 13th.
        let sunday = calendar.date(from: DateComponents(year: 2023, month: 11, day: 19))!
        let week = StatsAggregator.week(containing: sunday, calendar: calendar)
        #expect(calendar.component(.day, from: week.start) == 13)
        #expect(week.contains(sunday))
    }

    // MARK: - totals and deltas

    @Test func totalMinutesExcludesTheIntervalEnd() throws {
        let context = try makeContext()
        let start = Self.anchor
        let interval = DateInterval(start: start, duration: 3600)
        insertSession(endedAt: start, minutes: 10, into: context)
        insertSession(endedAt: start.addingTimeInterval(1800), minutes: 5, into: context)
        insertSession(endedAt: start.addingTimeInterval(3600), minutes: 99, into: context)
        #expect(StatsAggregator.totalMinutes(sessions(in: context), in: interval) == 15)
    }

    @Test func deltaLabelReportsGrowthAndDecline() throws {
        let context = try makeContext()
        let start = Self.anchor
        let interval = DateInterval(start: start, duration: 3600)
        insertSession(endedAt: start.addingTimeInterval(-1800), minutes: 10, into: context)
        insertSession(endedAt: start.addingTimeInterval(600), minutes: 15, into: context)
        #expect(StatsAggregator.deltaLabel(sessions(in: context), in: interval) == "+50%")

        let mirrored = DateInterval(start: start.addingTimeInterval(-3600), duration: 3600)
        insertSession(endedAt: start.addingTimeInterval(-7200), minutes: 20, into: context)
        #expect(StatsAggregator.deltaLabel(sessions(in: context), in: mirrored) == "-50%")
    }

    @Test func deltaLabelHandlesAnEmptyBaseline() throws {
        let context = try makeContext()
        let interval = DateInterval(start: Self.anchor, duration: 3600)
        #expect(StatsAggregator.deltaLabel([], in: interval) == "—")

        insertSession(endedAt: Self.anchor.addingTimeInterval(600), minutes: 10, into: context)
        #expect(StatsAggregator.deltaLabel(sessions(in: context), in: interval) == "新增")
    }

    // MARK: - per-day series

    @Test func minutesByDayEmitsOnePointPerDay() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Self.anchor)
        insertSession(endedAt: start.addingTimeInterval(3600), minutes: 10, into: context)
        insertSession(endedAt: start.addingTimeInterval(7200), minutes: 5, into: context)
        insertSession(endedAt: day(2, from: start).addingTimeInterval(3600), minutes: 7, into: context)

        let interval = DateInterval(start: start, end: day(3, from: start))
        let points = StatsAggregator.minutesByDay(sessions: sessions(in: context), in: interval)
        #expect(points.map(\.1) == [15, 0, 7])
    }

    // MARK: - task aggregates

    @Test func aggregateSummarisesEachTask() throws {
        let context = try makeContext()
        let task = TaskItem(id: "task", title: "和弦转换", subtitle: "C · G", category: .chord, targetMin: 8)
        context.insert(task)
        insertSession(endedAt: day(-1), minutes: 10, into: context)
        insertSession(endedAt: day(-3), minutes: 20, into: context)
        insertSession(endedAt: day(-2), minutes: 5, taskId: "other", into: context)

        let aggregates = StatsAggregator.aggregate(tasks: [task], sessions: sessions(in: context))
        let summary = try #require(aggregates.first)
        #expect(summary.sessionCount == 2)
        #expect(summary.totalMinutes == 30)
        #expect(summary.lastAt == day(-1))
    }

    // MARK: - duration rounding

    @Test(arguments: zip([0, 1, 60, 61, 599], [0, 1, 1, 2, 10]))
    func durationRoundsUpToWholeMinutes(seconds: Int, expected: Int) throws {
        let context = try makeContext()
        let session = PracticeSession(
            taskId: "task", taskTitle: "练习", category: .chord,
            startedAt: Self.anchor, endedAt: Self.anchor, durationSec: seconds,
            bpm: 80, timeSig: "4/4", steps: []
        )
        context.insert(session)
        #expect(session.durationMinutes == expected)
    }

    @Test func dayTaskGroupsMergesEffectiveSessionsAndDropsEmpty() throws {
        let context = try makeContext()
        let dayStart = Calendar.current.startOfDay(for: Self.anchor)
        insertSession(
            endedAt: dayStart.addingTimeInterval(3600), minutes: 1,
            taskId: "song", taskTitle: "知足", into: context
        )
        insertSession(
            endedAt: dayStart.addingTimeInterval(7200), minutes: 1,
            taskId: "song", taskTitle: "知足", into: context
        )
        for offset in 3...6 {
            insertSession(
                endedAt: dayStart.addingTimeInterval(Double(offset) * 3600),
                minutes: 0, taskId: "song", taskTitle: "知足", into: context
            )
        }
        insertSession(
            endedAt: dayStart.addingTimeInterval(100), minutes: 10,
            taskId: "other", taskTitle: "音阶", into: context
        )

        let groups = StatsAggregator.dayTaskGroups(sessions: sessions(in: context), on: dayStart)
        #expect(groups.count == 2)
        let song = try #require(groups.first { $0.taskId == "song" })
        #expect(song.title == "知足")
        #expect(song.totalMinutes == 2)
        #expect(groups.contains { $0.taskId == "other" && $0.totalMinutes == 10 })
    }

    @Test func dayTaskGroupsKeepsZeroMinuteNoteOnlySession() throws {
        let context = try makeContext()
        let dayStart = Calendar.current.startOfDay(for: Self.anchor)
        insertSession(
            endedAt: dayStart.addingTimeInterval(60), minutes: 0,
            taskId: "song", taskTitle: "知足", note: "只写了笔记", into: context
        )
        let groups = StatsAggregator.dayTaskGroups(sessions: sessions(in: context), on: dayStart)
        #expect(groups.count == 1)
        #expect(groups[0].totalMinutes == 0)
        #expect(groups[0].title == "知足")
    }

    private func sessions(in context: ModelContext) -> [PracticeSession] {
        (try? context.fetch(FetchDescriptor<PracticeSession>())) ?? []
    }
}
