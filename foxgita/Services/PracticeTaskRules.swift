import Foundation

enum PracticeTaskRules {
    static func localDayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0
        )
    }

    static func isVisibleToday(task: TaskItem, on date: Date, calendar: Calendar) -> Bool {
        guard let startedOn = task.startedOn else { return false }
        guard calendar.isDate(startedOn, inSameDayAs: date) else { return false }
        guard task.status == .active else { return false }
        guard task.isTemplate == false else { return false }
        guard task.deletedAt == nil else { return false }
        return PracticeRecordRules.isUserAddedTask(id: task.id)
    }

    static func snapSelectedDayIfItWasToday(
        selectedDay: Date,
        lastSeenTodayStart: Date?,
        now: Date,
        calendar: Calendar
    ) -> (selectedDay: Date, lastSeenTodayStart: Date) {
        let today = calendar.startOfDay(for: now)
        if calendar.isDate(selectedDay, inSameDayAs: today) {
            return (selectedDay: today, lastSeenTodayStart: today)
        }
        if let last = lastSeenTodayStart, calendar.isDate(selectedDay, inSameDayAs: last) {
            return (selectedDay: today, lastSeenTodayStart: today)
        }
        return (selectedDay: selectedDay, lastSeenTodayStart: today)
    }
}
