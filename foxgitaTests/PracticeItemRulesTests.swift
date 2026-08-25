import Foundation
import Testing
@testable import foxgita

struct PracticeItemRulesTests {
    private var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(
        year: Int, month: Int, day: Int, hour: Int, minute: Int = 0
    ) -> Date {
        shanghaiCalendar.date(from: DateComponents(
            timeZone: shanghaiCalendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    @Test func sameCalendarDayYieldsSameKey() {
        let calendar = shanghaiCalendar
        let morning = date(year: 2026, month: 8, day: 16, hour: 0, minute: 1)
        let evening = date(year: 2026, month: 8, day: 16, hour: 23, minute: 59)
        #expect(PracticeDayKey.make(from: morning, calendar: calendar) == "2026-08-16")
        #expect(PracticeDayKey.make(from: evening, calendar: calendar) == "2026-08-16")
        #expect(
            PracticeDayKey.make(from: morning, calendar: calendar)
                == PracticeDayKey.make(from: evening, calendar: calendar)
        )
    }

    @Test func midnightBoundaryYieldsDifferentKeys() {
        let calendar = shanghaiCalendar
        let beforeMidnight = date(year: 2026, month: 8, day: 16, hour: 23, minute: 59)
        let afterMidnight = date(year: 2026, month: 8, day: 17, hour: 0)
        #expect(PracticeDayKey.make(from: beforeMidnight, calendar: calendar) == "2026-08-16")
        #expect(PracticeDayKey.make(from: afterMidnight, calendar: calendar) == "2026-08-17")
    }

    private func item(
        id: UUID = UUID(),
        dayKey: String,
        createdAt: Date,
        title: String = "练习",
        durationSeconds: Int = 60,
        isDeleted: Bool = false
    ) -> PracticeItemSnapshot {
        PracticeItemSnapshot(
            id: id,
            practiceDayKey: dayKey,
            createdAt: createdAt,
            title: title,
            durationSeconds: durationSeconds,
            isDeleted: isDeleted
        )
    }

    @Test func itemsExcludeDeletedAndOtherDaysNewestFirst() {
        let t0 = date(year: 2026, month: 8, day: 16, hour: 8)
        let t1 = date(year: 2026, month: 8, day: 16, hour: 10)
        let t2 = date(year: 2026, month: 8, day: 16, hour: 12)
        let newer = item(dayKey: "2026-08-16", createdAt: t2, title: "new")
        let older = item(dayKey: "2026-08-16", createdAt: t0, title: "old")
        let mid = item(dayKey: "2026-08-16", createdAt: t1, title: "mid")
        let deleted = item(dayKey: "2026-08-16", createdAt: t2, title: "gone", isDeleted: true)
        let otherDay = item(dayKey: "2026-08-17", createdAt: t2, title: "next")
        let visible = PracticeItemRules.items(
            for: "2026-08-16",
            in: [older, deleted, otherDay, newer, mid]
        )
        #expect(visible.map(\.title) == ["new", "mid", "old"])
    }

    @Test func totalDurationExcludesDeletedAndClampsNegatives() {
        let t0 = date(year: 2026, month: 8, day: 16, hour: 8)
        let items = [
            item(dayKey: "2026-08-16", createdAt: t0, durationSeconds: 90),
            item(dayKey: "2026-08-16", createdAt: t0, durationSeconds: -12),
            item(dayKey: "2026-08-16", createdAt: t0, durationSeconds: 40, isDeleted: true),
            item(dayKey: "2026-08-17", createdAt: t0, durationSeconds: 200),
        ]
        #expect(PracticeItemRules.totalDuration(for: "2026-08-16", in: items) == 90)
    }

    @Test func checkedInKeysKeepZeroDurationAndDropDeleted() {
        let t0 = date(year: 2026, month: 8, day: 16, hour: 8)
        let items = [
            item(dayKey: "2026-08-16", createdAt: t0, durationSeconds: 0),
            item(dayKey: "2026-08-17", createdAt: t0, durationSeconds: 30, isDeleted: true),
            item(dayKey: "2026-08-18", createdAt: t0, durationSeconds: 10),
        ]
        #expect(
            PracticeItemRules.checkedInDayKeys(in: items) == Set(["2026-08-16", "2026-08-18"])
        )
    }
}
