import Foundation
import Testing
@testable import foxgita

struct PracticeDetailStateTests {
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

    @Test func todayItemIsEditable() {
        let today = date(year: 2026, month: 8, day: 26, hour: 10)
        let mode = PracticeDetailState.mode(
            practiceDayKey: "2026-08-26",
            today: today,
            calendar: shanghaiCalendar
        )
        #expect(mode == .editable)
        #expect(PracticeDetailState.shouldAllowTimer(mode: mode))
        #expect(PracticeDetailState.shouldAllowCapture(mode: mode))
        #expect(PracticeDetailState.shouldAllowComplete(mode: mode))
    }

    @Test func historicalDayIsReadOnly() {
        let today = date(year: 2026, month: 8, day: 26, hour: 10)
        let mode = PracticeDetailState.mode(
            practiceDayKey: "2026-08-25",
            today: today,
            calendar: shanghaiCalendar
        )
        #expect(mode == .historical)
        #expect(!PracticeDetailState.shouldAllowTimer(mode: mode))
        #expect(!PracticeDetailState.shouldAllowCapture(mode: mode))
        #expect(!PracticeDetailState.shouldAllowComplete(mode: mode))
        #expect(
            !PracticeDetailState.shouldAutoSaveOnDisappear(mode: mode, isDirty: true)
        )
    }

    @Test func recordEntryAllowsTimerOnPastDayWithoutChangingDayKey() {
        let today = date(year: 2026, month: 8, day: 28, hour: 10)
        let mode = PracticeDetailState.mode(
            practiceDayKey: "2026-08-25",
            today: today,
            calendar: shanghaiCalendar,
            allowPastDayEdits: true
        )
        #expect(mode == .editable)
        #expect(PracticeDetailState.shouldAllowTimer(mode: mode))
        #expect(PracticeDetailState.shouldAllowComplete(mode: mode))
        #expect(PracticeDetailState.shouldAutoSaveOnDisappear(mode: mode, isDirty: true))
    }

    @Test func practiceHomePastDayStaysReadOnly() {
        let today = date(year: 2026, month: 8, day: 28, hour: 10)
        let mode = PracticeDetailState.mode(
            practiceDayKey: "2026-08-25",
            today: today,
            calendar: shanghaiCalendar,
            allowPastDayEdits: false
        )
        #expect(mode == .historical)
        #expect(!PracticeDetailState.shouldAllowTimer(mode: mode))
    }

    @Test func historicalDoesNotAutoWriteEvenWhenDirty() {
        let mode = PracticeDetailMode.historical
        #expect(
            !PracticeDetailState.shouldAutoSaveOnDisappear(
                mode: mode,
                isDirty: true
            )
        )
        #expect(!PracticeDetailState.shouldAllowTimer(mode: mode))
        #expect(!PracticeDetailState.shouldAllowCapture(mode: mode))
        #expect(!PracticeDetailState.shouldAllowComplete(mode: mode))
    }

    @Test func editableSavesWhenDirtyAndSkipsClean() {
        #expect(
            PracticeDetailState.shouldAutoSaveOnDisappear(mode: .editable, isDirty: true)
        )
        #expect(
            !PracticeDetailState.shouldAutoSaveOnDisappear(mode: .editable, isDirty: false)
        )
    }

    @Test func timerStartsFromStoredDurationSeconds() {
        #expect(PracticeDetailState.initialElapsedSeconds(storedDurationSeconds: 600) == 600)
        #expect(PracticeDetailState.initialElapsedSeconds(storedDurationSeconds: 0) == 0)
        #expect(PracticeDetailState.initialElapsedSeconds(storedDurationSeconds: -12) == 0)
    }

    @Test func samePayloadTwiceIsNotDirty() {
        #expect(
            !PracticeDetailState.isDirty(
                elapsedSeconds: 600,
                note: "离开自动保存",
                storedDurationSeconds: 600,
                storedNote: "离开自动保存"
            )
        )
        #expect(
            PracticeDetailState.isDirty(
                elapsedSeconds: 601,
                note: "离开自动保存",
                storedDurationSeconds: 600,
                storedNote: "离开自动保存"
            )
        )
    }

    @Test func emptyStoredStepsBecomePlaceholder() {
        #expect(PracticeDetailState.initialSteps([]) == ["新步骤"])
        #expect(PracticeDetailState.initialSteps(["慢扫", "加速"]) == ["慢扫", "加速"])
    }

    @Test func stepEditsMakeDetailDirty() {
        #expect(
            !PracticeDetailState.isDirty(
                elapsedSeconds: 60,
                note: "",
                storedDurationSeconds: 60,
                storedNote: "",
                steps: ["慢扫"],
                storedSteps: ["慢扫"]
            )
        )
        #expect(
            PracticeDetailState.isDirty(
                elapsedSeconds: 60,
                note: "",
                storedDurationSeconds: 60,
                storedNote: "",
                steps: ["慢扫", "加速"],
                storedSteps: ["慢扫"]
            )
        )
    }

    @Test func bpmEditsMakeDetailDirty() {
        #expect(
            !PracticeDetailState.isDirty(
                elapsedSeconds: 60,
                note: "",
                storedDurationSeconds: 60,
                storedNote: "",
                bpm: 80,
                storedBpm: 80
            )
        )
        #expect(
            PracticeDetailState.isDirty(
                elapsedSeconds: 60,
                note: "",
                storedDurationSeconds: 60,
                storedNote: "",
                bpm: 63,
                storedBpm: 80
            )
        )
    }

    @Test func detailMatchesHomeItem() {
        let id = UUID()
        let created = date(year: 2026, month: 8, day: 26, hour: 9)
        let snapshot = item(
            id: id,
            dayKey: "2026-08-26",
            createdAt: created,
            title: "知足跟着原唱缝2",
            durationSeconds: 420
        )
        let home = PracticeHomeState.make(selectedDayKey: "2026-08-26", allItems: [snapshot])
        #expect(home.items.map(\.id) == [id])

        let route = PracticeRoute.detail(itemId: home.items[0].id)
        #expect(route == .detail(itemId: id))

        let loaded = PracticeDetailState.loadedItem(
            requestedId: home.items[0].id,
            candidates: [snapshot]
        )
        #expect(loaded?.id == id)
        #expect(loaded?.practiceDayKey == home.items[0].practiceDayKey)
        #expect(loaded?.title == home.items[0].title)
        #expect(loaded?.durationSeconds == 420)
    }

    @Test func twentyFifthDayItemOpensIndependentOfTodayAndSameTitle() {
        let id25 = UUID()
        let id26 = UUID()
        let t25 = date(year: 2026, month: 8, day: 25, hour: 10)
        let t26 = date(year: 2026, month: 8, day: 26, hour: 10)
        let items = [
            item(
                id: id25,
                dayKey: "2026-08-25",
                createdAt: t25,
                title: "知足跟着原唱缝2",
                durationSeconds: 600
            ),
            item(
                id: id26,
                dayKey: "2026-08-26",
                createdAt: t26,
                title: "知足跟着原唱缝2",
                durationSeconds: 120
            ),
        ]

        let home25 = PracticeHomeState.make(selectedDayKey: "2026-08-25", allItems: items)
        #expect(home25.items.map(\.id) == [id25])
        #expect(home25.items[0].practiceDayKey == "2026-08-25")

        let requested = home25.items[0].id
        let route = PracticeRoute.detail(itemId: requested)
        #expect(route == .detail(itemId: id25))
        #expect(route != .detail(itemId: id26))

        let loaded = PracticeDetailState.loadedItem(requestedId: requested, candidates: items)
        #expect(loaded?.id == id25)
        #expect(loaded?.practiceDayKey == "2026-08-25")
        #expect(loaded?.durationSeconds == 600)
        #expect(loaded?.title == "知足跟着原唱缝2")

        let today = t26
        #expect(
            PracticeDetailState.mode(
                practiceDayKey: loaded?.practiceDayKey ?? "",
                today: today,
                calendar: shanghaiCalendar
            ) == .historical
        )
        #expect(
            PracticeDetailState.mode(
                practiceDayKey: "2026-08-26",
                today: today,
                calendar: shanghaiCalendar
            ) == .editable
        )
        #expect(
            PracticeDetailState.loadedItem(requestedId: requested, candidates: items)?.id
                != id26
        )
    }
}
