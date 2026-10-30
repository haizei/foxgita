import Foundation

struct PracticeHomeState: Equatable {
    let selectedDayKey: String
    let items: [PracticeItemSnapshot]
    let totalDurationSeconds: Int
    let checkedInDayKeys: Set<String>

    static func make(
        selectedDayKey: String,
        allItems: [PracticeItemSnapshot],
        todayDayKey: String = PracticeDayKey.make(from: .now, calendar: .current)
    ) -> Self {
        let effective = allItems.filter(PracticeItemRules.isEffective)
        let visible = selectedDayKey == todayDayKey
            ? allItems.filter { !($0.originId?.hasPrefix("program.routine.") ?? false) }
            : effective
        return PracticeHomeState(
            selectedDayKey: selectedDayKey,
            items: PracticeItemRules.items(for: selectedDayKey, in: visible),
            totalDurationSeconds: PracticeItemRules.totalDuration(for: selectedDayKey, in: visible),
            checkedInDayKeys: Set(effective.map(\.practiceDayKey))
        )
    }

    static func sourceLabel(for item: PracticeItemSnapshot) -> String {
        if item.originId?.hasPrefix("program.routine.") == true { return String(localized: "方案练习") }
        if item.originId?.hasPrefix("program.checklist.") == true { return String(localized: "清单训练") }
        return String(localized: "日常练习")
    }

    static func ctaTitle(isSelectedToday: Bool, durationSeconds: Int) -> String {
        guard isSelectedToday else { return String(localized: "查看") }
        return durationSeconds > 0 ? String(localized: "继续") : String(localized: "开始")
    }

    static func allowsSwipeDelete(isSelectedToday: Bool) -> Bool {
        isSelectedToday
    }

    static func allowsSwipeEdit(isSelectedToday: Bool) -> Bool {
        isSelectedToday
    }

    static func initialTargetMin(_ value: Int) -> Int {
        min(60, max(1, value == 0 ? 10 : value))
    }

    static func cardMinutesLabel(
        isSelectedToday: Bool,
        targetMin: Int,
        durationSeconds: Int
    ) -> String {
        if isSelectedToday {
            return String(localized: "\(initialTargetMin(targetMin)) 分钟")
        }
        let minutes: Int = {
            let clamped = max(0, durationSeconds)
            guard clamped > 0 else { return 0 }
            return max(1, Int((Double(clamped) / 60.0).rounded(.up)))
        }()
        return String(localized: "已练 \(minutes) 分钟")
    }
}
