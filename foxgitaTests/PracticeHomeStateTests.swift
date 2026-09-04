import Foundation
import Testing
@testable import foxgita

struct PracticeHomeStateTests {
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

    @Test func selectedDayExcludesOtherDays() {
        let t25 = date(year: 2026, month: 8, day: 25, hour: 10)
        let t26 = date(year: 2026, month: 8, day: 26, hour: 10)
        let items = [
            item(dayKey: "2026-08-25", createdAt: t25, title: "二十五"),
            item(dayKey: "2026-08-26", createdAt: t26, title: "二十六"),
        ]

        let state25 = PracticeHomeState.make(selectedDayKey: "2026-08-25", allItems: items)
        #expect(state25.selectedDayKey == "2026-08-25")
        #expect(state25.items.map(\.title) == ["二十五"])
        #expect(state25.items.allSatisfy { $0.practiceDayKey == "2026-08-25" })

        let state26 = PracticeHomeState.make(selectedDayKey: "2026-08-26", allItems: items)
        #expect(state26.items.map(\.title) == ["二十六"])
        #expect(!state26.items.contains { $0.practiceDayKey == "2026-08-25" })
    }

    @Test func sameItemSavedTwiceIsStillOneRow() {
        let id = UUID()
        let created = date(year: 2026, month: 8, day: 25, hour: 9)
        // Two saves overwrite the same item; the home is item-based, not session-count.
        let afterTwoSaves = item(
            id: id,
            dayKey: "2026-08-25",
            createdAt: created,
            title: "知足跟着原唱缝2",
            durationSeconds: 600
        )
        let state = PracticeHomeState.make(
            selectedDayKey: "2026-08-25",
            allItems: [afterTwoSaves]
        )
        #expect(state.items.count == 1)
        #expect(state.items[0].id == id)
        #expect(state.items[0].durationSeconds == 600)
    }

    @Test func totalDurationSumsSelectedDayItems() {
        let t25 = date(year: 2026, month: 8, day: 25, hour: 10)
        let items = [
            item(dayKey: "2026-08-25", createdAt: t25, durationSeconds: 90),
            item(dayKey: "2026-08-25", createdAt: t25.addingTimeInterval(60), durationSeconds: 40),
            item(dayKey: "2026-08-25", createdAt: t25, durationSeconds: -12),
            item(dayKey: "2026-08-26", createdAt: t25, durationSeconds: 200),
            item(dayKey: "2026-08-25", createdAt: t25, durationSeconds: 30, isDeleted: true),
        ]
        let state = PracticeHomeState.make(selectedDayKey: "2026-08-25", allItems: items)
        #expect(state.totalDurationSeconds == 130)
        #expect(state.items.count == 3)
    }

    @Test func calendarMarksComeFromTheSameCheckedInKeysAsTheList() {
        let t25 = date(year: 2026, month: 8, day: 25, hour: 10)
        let t26 = date(year: 2026, month: 8, day: 26, hour: 10)
        let items = [
            item(dayKey: "2026-08-25", createdAt: t25, title: "二十五", durationSeconds: 0),
            item(dayKey: "2026-08-26", createdAt: t26, title: "二十六", durationSeconds: 120),
            item(dayKey: "2026-08-24", createdAt: t25, title: "已删", isDeleted: true),
        ]
        let state = PracticeHomeState.make(selectedDayKey: "2026-08-25", allItems: items)

        #expect(state.items.map(\.title) == ["二十五"])
        #expect(state.totalDurationSeconds == 0)
        #expect(state.checkedInDayKeys == Set(["2026-08-25", "2026-08-26"]))
        #expect(state.checkedInDayKeys == PracticeItemRules.checkedInDayKeys(in: items))
        #expect(state.items.allSatisfy { state.checkedInDayKeys.contains($0.practiceDayKey) })
        #expect(!state.checkedInDayKeys.contains("2026-08-24"))
    }

    @Test func todayUnplayedItemUsesStartCTA() {
        #expect(PracticeHomeState.ctaTitle(isSelectedToday: true, durationSeconds: 0) == "开始")
    }

    @Test func todayPlayedItemUsesContinueCTA() {
        #expect(PracticeHomeState.ctaTitle(isSelectedToday: true, durationSeconds: 60) == "继续")
    }

    @Test func pastDayUsesViewCTA() {
        #expect(PracticeHomeState.ctaTitle(isSelectedToday: false, durationSeconds: 60) == "查看")
        #expect(PracticeHomeState.ctaTitle(isSelectedToday: false, durationSeconds: 0) == "查看")
    }

    @Test func onlyTodayAllowsSwipeDelete() {
        #expect(PracticeHomeState.allowsSwipeDelete(isSelectedToday: true))
        #expect(!PracticeHomeState.allowsSwipeDelete(isSelectedToday: false))
    }
}
