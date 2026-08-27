import Foundation
import Testing
@testable import foxgita

struct RecordTimelineRulesTests {
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
        isDeleted: Bool = false
    ) -> PracticeItemSnapshot {
        PracticeItemSnapshot(
            id: UUID(),
            practiceDayKey: dayKey,
            createdAt: createdAt,
            title: title,
            durationSeconds: durationSeconds,
            isDeleted: isDeleted,
            note: note,
            recordingCount: recordingCount
        )
    }

    @Test func minutesRoundHalfAwayFromZero() {
        #expect(RecordMinutes.display(fromSeconds: 0) == 0)
        #expect(RecordMinutes.display(fromSeconds: 29) == 0)
        #expect(RecordMinutes.display(fromSeconds: 30) == 1)
        #expect(RecordMinutes.display(fromSeconds: 90) == 2)
    }

    @Test func weekOfAug24IsMondayToSunday() {
        let wednesday = date(year: 2026, month: 8, day: 26, hour: 10)
        let interval = StatsAggregator.week(containing: wednesday, calendar: shanghaiCalendar)
        #expect(PracticeDayKey.make(from: interval.start, calendar: shanghaiCalendar) == "2026-08-24")
        #expect(RecordTimelineRules.weekTitle(interval: interval, calendar: shanghaiCalendar) == "8 月 24 日–30 日")
    }

    @Test func crossMonthWeekTitle() {
        let day = date(year: 2026, month: 6, day: 30, hour: 10)
        let interval = StatsAggregator.week(containing: day, calendar: shanghaiCalendar)
        #expect(RecordTimelineRules.weekTitle(interval: interval, calendar: shanghaiCalendar) == "6 月 29 日–7 月 5 日")
    }

    @Test func timelineKeepsOnlyEffectiveItemsInTheWeekNewestDayFirst() {
        let now = date(year: 2026, month: 8, day: 27, hour: 12)
        let items = [
            item(dayKey: "2026-08-27", createdAt: date(year: 2026, month: 8, day: 27, hour: 9, minute: 24), title: "完整跟唱摸底", durationSeconds: 1800),
            item(dayKey: "2026-08-27", createdAt: date(year: 2026, month: 8, day: 27, hour: 8, minute: 50), title: "右手扫弦热身", durationSeconds: 240),
            item(dayKey: "2026-08-26", createdAt: date(year: 2026, month: 8, day: 26, hour: 19, minute: 35), title: "完整跟唱摸底", durationSeconds: 1800),
            item(dayKey: "2026-08-27", createdAt: date(year: 2026, month: 8, day: 27, hour: 7), title: "空", durationSeconds: 0),
            item(dayKey: "2026-08-20", createdAt: date(year: 2026, month: 8, day: 20, hour: 10), title: "上周", durationSeconds: 600),
            item(dayKey: "2026-08-27", createdAt: date(year: 2026, month: 8, day: 27, hour: 10), title: "删", durationSeconds: 600, isDeleted: true),
        ]
        let state = RecordTimelineState.make(
            allItems: items,
            weekContaining: now,
            now: now,
            calendar: shanghaiCalendar
        )
        #expect(state.hasAnyEffectiveItem)
        #expect(state.days.map(\.dayKey) == ["2026-08-27", "2026-08-26"])
        #expect(state.days[0].items.map(\.title) == ["完整跟唱摸底", "右手扫弦热身"])
        #expect(state.days[0].totalSeconds == 2040)
        #expect(RecordTimelineRules.dayTitle(dayKey: "2026-08-27", now: now, calendar: shanghaiCalendar) == "今天 · 8 月 27 日")
        #expect(RecordTimelineRules.dayTitle(dayKey: "2026-08-26", now: now, calendar: shanghaiCalendar) == "昨天 · 8 月 26 日")
        #expect(RecordTimelineRules.dayTitle(dayKey: "2026-08-25", now: now, calendar: shanghaiCalendar) == "8 月 25 日")
    }

    @Test func emptyWeekStillKnowsTheAppHasHistory() {
        let now = date(year: 2026, month: 8, day: 27, hour: 12)
        let items = [
            item(dayKey: "2026-08-10", createdAt: date(year: 2026, month: 8, day: 10, hour: 10), title: "更早", durationSeconds: 120),
        ]
        let state = RecordTimelineState.make(
            allItems: items,
            weekContaining: now,
            now: now,
            calendar: shanghaiCalendar
        )
        #expect(state.days.isEmpty)
        #expect(state.hasAnyEffectiveItem)
    }

    @Test func neverPracticed() {
        let now = date(year: 2026, month: 8, day: 27, hour: 12)
        let state = RecordTimelineState.make(
            allItems: [],
            weekContaining: now,
            now: now,
            calendar: shanghaiCalendar
        )
        #expect(state.days.isEmpty)
        #expect(state.hasAnyEffectiveItem == false)
    }

    @Test func shiftWeekMovesSevenDays() {
        let now = date(year: 2026, month: 8, day: 27, hour: 12)
        let thisWeek = StatsAggregator.week(containing: now, calendar: shanghaiCalendar)
        let prev = RecordTimelineRules.shiftWeek(interval: thisWeek, byWeeks: -1, calendar: shanghaiCalendar)
        #expect(PracticeDayKey.make(from: prev.start, calendar: shanghaiCalendar) == "2026-08-17")
    }
}
