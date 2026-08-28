import Foundation
import Testing
@testable import foxgita

struct RecordHistoryRulesTests {
    private var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(
        year: Int, month: Int, day: Int, hour: Int, minute: Int = 0
    ) -> Date {
        shanghaiCalendar.date(from: DateComponents(
            timeZone: shanghaiCalendar.timeZone,
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    private func item(
        dayKey: String,
        createdAt: Date,
        title: String,
        durationSeconds: Int,
        note: String = "",
        recordingCount: Int = 0,
        isDeleted: Bool = false,
        categoryRaw: String = PracticeCategory.chord.rawValue
    ) -> PracticeItemSnapshot {
        PracticeItemSnapshot(
            id: UUID(),
            practiceDayKey: dayKey,
            createdAt: createdAt,
            title: title,
            durationSeconds: durationSeconds,
            isDeleted: isDeleted,
            note: note,
            recordingCount: recordingCount,
            categoryRaw: categoryRaw
        )
    }

    @Test func calendarMarksMinutesOnlyOnEffectiveDaysAndBlocksFuture() {
        let now = date(year: 2026, month: 8, day: 27, hour: 12)
        let items = [
            item(dayKey: "2026-08-27", createdAt: now, title: "A", durationSeconds: 2520),
            item(dayKey: "2026-08-27", createdAt: now, title: "B", durationSeconds: 0, note: "笔记"),
            item(dayKey: "2026-08-20", createdAt: now, title: "空", durationSeconds: 0),
            item(dayKey: "2026-09-01", createdAt: now, title: "下月", durationSeconds: 60),
        ]
        let cells = RecordHistoryRules.calendarCells(
            monthContaining: now, now: now, calendar: shanghaiCalendar, effectiveItems: items.filter(PracticeItemRules.isEffective)
        )
        let day27 = cells.first { $0.dayKey == "2026-08-27" }
        #expect(day27?.minutesLabel == "42m")
        #expect(cells.first { $0.dayKey == "2026-08-20" }?.minutesLabel == "·")
        #expect(cells.first { $0.dayKey == "2026-08-28" }?.isFuture == true)
    }

    @Test func calendarShowsZeroMinutesOnNoteOnlyEffectiveDay() {
        let now = date(year: 2026, month: 8, day: 27, hour: 12)
        let items = [
            item(dayKey: "2026-08-21", createdAt: now, title: "只记", durationSeconds: 0, note: "一句"),
            item(dayKey: "2026-08-20", createdAt: now, title: "空", durationSeconds: 0),
        ]
        let cells = RecordHistoryRules.calendarCells(
            monthContaining: now, now: now, calendar: shanghaiCalendar, effectiveItems: items.filter(PracticeItemRules.isEffective)
        )
        #expect(cells.first { $0.dayKey == "2026-08-21" }?.minutesLabel == "0m")
        #expect(cells.first { $0.dayKey == "2026-08-20" }?.minutesLabel == "·")
    }

    @Test func daySummaryJoinsTitlesNewestFirstAndDedupsTypes() {
        let t1 = date(year: 2026, month: 8, day: 27, hour: 9, minute: 24)
        let t2 = date(year: 2026, month: 8, day: 27, hour: 9, minute: 2)
        let t3 = date(year: 2026, month: 8, day: 27, hour: 8, minute: 50)
        let items = [
            PracticeItemSnapshot(id: UUID(), practiceDayKey: "2026-08-27", createdAt: t1, title: "完整跟唱摸底", durationSeconds: 1800, isDeleted: false, categoryRaw: PracticeCategory.song.rawValue),
            PracticeItemSnapshot(id: UUID(), practiceDayKey: "2026-08-27", createdAt: t2, title: "F 和弦横按", durationSeconds: 480, isDeleted: false, categoryRaw: PracticeCategory.chord.rawValue),
            PracticeItemSnapshot(id: UUID(), practiceDayKey: "2026-08-27", createdAt: t3, title: "右手扫弦热身", durationSeconds: 240, isDeleted: false, categoryRaw: PracticeCategory.rhythm.rawValue),
            PracticeItemSnapshot(id: UUID(), practiceDayKey: "2026-08-26", createdAt: t1, title: "别天", durationSeconds: 60, isDeleted: false),
        ]
        let summary = RecordHistoryRules.daySummary(dayKey: "2026-08-27", items: items)
        #expect(summary?.joinedTitles == "完整跟唱摸底 · F 和弦横按 · 右手扫弦热身")
        #expect(summary?.typeLabels == ["歌曲", "和弦", "节奏"])
        #expect(RecordMinutes.display(fromSeconds: summary?.totalSeconds ?? 0) == 42)
    }

    @Test func longestStreakIsInsideTheVisiblePeriodOnly() {
        let items = [
            item(dayKey: "2026-08-01", createdAt: date(year: 2026, month: 8, day: 1, hour: 10), title: "a", durationSeconds: 60),
            item(dayKey: "2026-08-02", createdAt: date(year: 2026, month: 8, day: 2, hour: 10), title: "b", durationSeconds: 60),
            item(dayKey: "2026-08-03", createdAt: date(year: 2026, month: 8, day: 3, hour: 10), title: "c", durationSeconds: 60),
            item(dayKey: "2026-08-05", createdAt: date(year: 2026, month: 8, day: 5, hour: 10), title: "d", durationSeconds: 60),
            item(dayKey: "2026-07-30", createdAt: date(year: 2026, month: 7, day: 30, hour: 10), title: "prev", durationSeconds: 60),
            item(dayKey: "2026-07-31", createdAt: date(year: 2026, month: 7, day: 31, hour: 10), title: "prev2", durationSeconds: 60),
        ]
        let metrics = RecordHistoryRules.monthMetrics(
            monthContaining: date(year: 2026, month: 8, day: 10, hour: 10),
            calendar: shanghaiCalendar,
            items: items
        )
        #expect(metrics.days == 4)
        #expect(metrics.longestStreak == 3)
    }

    @Test func weekStatsHideTypeBlockWhenUntypedAndOmitDeltaWhenBothZero() {
        let now = date(year: 2026, month: 8, day: 27, hour: 12)
        let empty = RecordHistoryRules.stats(
            granularity: .week, containing: now, now: now, calendar: shanghaiCalendar, items: []
        )
        #expect(empty.totalSeconds == 0)
        #expect(empty.deltaSeconds == nil)
        #expect(empty.bars.count == 7)
        #expect(empty.typeShares.isEmpty)

        let typed = [
            PracticeItemSnapshot(id: UUID(), practiceDayKey: "2026-08-26", createdAt: now, title: "弦", durationSeconds: 1920, isDeleted: false, categoryRaw: PracticeCategory.chord.rawValue),
            PracticeItemSnapshot(id: UUID(), practiceDayKey: "2026-08-27", createdAt: now, title: "无类型", durationSeconds: 600, isDeleted: false, categoryRaw: ""),
        ]
        let stats = RecordHistoryRules.stats(
            granularity: .week, containing: now, now: now, calendar: shanghaiCalendar, items: typed
        )
        #expect(stats.totalSeconds == 2520)
        #expect(stats.typeShares.map(\.category) == [.chord])
        #expect(stats.practiceDayCount == 2)
    }

    @Test func pastDayContinueDoesNotCheckInToday() {
        let now = date(year: 2026, month: 8, day: 28, hour: 12)
        let items = [
            item(dayKey: "2026-08-25", createdAt: date(year: 2026, month: 8, day: 25, hour: 10), title: "补练", durationSeconds: 2400),
        ]
        let today = RecordHistoryRules.daySummary(dayKey: "2026-08-28", items: items)
        let past = RecordHistoryRules.daySummary(dayKey: "2026-08-25", items: items)
        #expect(today == nil)
        #expect(past?.totalSeconds == 2400)
        let week = RecordTimelineState.make(allItems: items, weekContaining: now, now: now, calendar: shanghaiCalendar)
        #expect(!week.days.contains { $0.dayKey == "2026-08-28" })
        #expect(week.days.contains { $0.dayKey == "2026-08-25" })
    }

    @Test func returningFromCalendarUsesFocusedDayWeek() {
        let calendar = shanghaiCalendar
        let focus = "2026-08-25"
        let currentWeek = StatsAggregator.week(
            containing: date(year: 2026, month: 8, day: 27, hour: 10),
            calendar: calendar
        )
        let focusDate = RecordTimelineRules.date(fromDayKey: focus, calendar: calendar)!
        let target = StatsAggregator.week(containing: focusDate, calendar: calendar)
        #expect(PracticeDayKey.make(from: currentWeek.start, calendar: calendar) == "2026-08-24")
        #expect(PracticeDayKey.make(from: target.start, calendar: calendar) == "2026-08-24")
        let june = RecordTimelineRules.date(fromDayKey: "2026-06-30", calendar: calendar)!
        #expect(PracticeDayKey.make(from: StatsAggregator.week(containing: june, calendar: calendar).start, calendar: calendar) == "2026-06-29")
        #expect(
            PracticeDayKey.make(
                from: RecordHistoryRules.weekStart(forDayKey: focus, calendar: calendar)!,
                calendar: calendar
            ) == "2026-08-24"
        )
        #expect(
            PracticeDayKey.make(
                from: RecordHistoryRules.weekStart(forDayKey: "2026-06-30", calendar: calendar)!,
                calendar: calendar
            ) == "2026-06-29"
        )
    }
}
