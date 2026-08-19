import Foundation
import Testing
@testable import foxgita

struct PracticeTaskRulesTests {
    private func shanghai() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour
        ))!
    }

    private func makeTask(
        id: String = "custom-1",
        startedOn: Date?,
        status: TaskStatus = .active,
        isTemplate: Bool = false,
        deletedAt: Date? = nil
    ) -> TaskItem {
        let task = TaskItem(
            id: id, title: "t", subtitle: "s",
            category: .chord, targetMin: 5,
            status: status, startedOn: startedOn,
            isTemplate: isTemplate
        )
        task.deletedAt = deletedAt
        return task
    }

    @Test func localDayKeyUsesCalendarComponentsNotUTC() {
        let cal = shanghai()
        let late = date(2026, 8, 19, 23, calendar: cal)
        let early = date(2026, 8, 20, 0, calendar: cal)
        #expect(PracticeTaskRules.localDayKey(for: late, calendar: cal) == "2026-08-19")
        #expect(PracticeTaskRules.localDayKey(for: early, calendar: cal) == "2026-08-20")
    }

    @Test func localDayKeyCrossesMonthAndYear() {
        let cal = shanghai()
        #expect(
            PracticeTaskRules.localDayKey(
                for: date(2026, 8, 31, 23, calendar: cal), calendar: cal
            ) == "2026-08-31"
        )
        #expect(
            PracticeTaskRules.localDayKey(
                for: date(2026, 9, 1, 0, calendar: cal), calendar: cal
            ) == "2026-09-01"
        )
        #expect(
            PracticeTaskRules.localDayKey(
                for: date(2026, 12, 31, 23, calendar: cal), calendar: cal
            ) == "2026-12-31"
        )
        #expect(
            PracticeTaskRules.localDayKey(
                for: date(2027, 1, 1, 0, calendar: cal), calendar: cal
            ) == "2027-01-01"
        )
    }

    @Test func visibleTodayRequiresSameLocalDay() {
        let cal = shanghai()
        let today = date(2026, 8, 19, 10, calendar: cal)
        let yesterday = date(2026, 8, 18, 10, calendar: cal)
        #expect(
            PracticeTaskRules.isVisibleToday(
                task: makeTask(startedOn: today), on: today, calendar: cal
            )
        )
        #expect(
            PracticeTaskRules.isVisibleToday(
                task: makeTask(startedOn: yesterday), on: today, calendar: cal
            ) == false
        )
    }

    @Test func visibleTodayRejectsNilTemplateDeletedDoneAndSeed() {
        let cal = shanghai()
        let today = date(2026, 8, 19, 10, calendar: cal)
        #expect(
            PracticeTaskRules.isVisibleToday(
                task: makeTask(startedOn: nil), on: today, calendar: cal
            ) == false
        )
        #expect(
            PracticeTaskRules.isVisibleToday(
                task: makeTask(startedOn: today, isTemplate: true),
                on: today, calendar: cal
            ) == false
        )
        #expect(
            PracticeTaskRules.isVisibleToday(
                task: makeTask(startedOn: today, deletedAt: today),
                on: today, calendar: cal
            ) == false
        )
        #expect(
            PracticeTaskRules.isVisibleToday(
                task: makeTask(startedOn: today, status: .done),
                on: today, calendar: cal
            ) == false
        )
        #expect(
            PracticeTaskRules.isVisibleToday(
                task: makeTask(id: "warm", startedOn: today),
                on: today, calendar: cal
            ) == false
        )
    }

    @Test func snapMovesSelectedDayOnlyWhenItWasToday() {
        let cal = shanghai()
        let aug18 = cal.startOfDay(for: date(2026, 8, 18, calendar: cal))
        let aug17 = cal.startOfDay(for: date(2026, 8, 17, calendar: cal))
        let aug19 = date(2026, 8, 19, 0, calendar: cal)

        let rolled = PracticeTaskRules.snapSelectedDayIfItWasToday(
            selectedDay: aug18, lastSeenTodayStart: aug18, now: aug19, calendar: cal
        )
        #expect(cal.isDate(rolled.selectedDay, inSameDayAs: aug19))
        #expect(cal.isDate(rolled.lastSeenTodayStart, inSameDayAs: aug19))

        let browsing = PracticeTaskRules.snapSelectedDayIfItWasToday(
            selectedDay: aug17, lastSeenTodayStart: aug18, now: aug19, calendar: cal
        )
        #expect(cal.isDate(browsing.selectedDay, inSameDayAs: aug17))
        #expect(cal.isDate(browsing.lastSeenTodayStart, inSameDayAs: aug19))
    }
}
