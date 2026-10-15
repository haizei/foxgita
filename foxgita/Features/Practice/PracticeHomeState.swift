import Foundation

struct PracticeHomeState: Equatable {
    let selectedDayKey: String
    let items: [PracticeItemSnapshot]
    let totalDurationSeconds: Int
    let checkedInDayKeys: Set<String>

    static func make(selectedDayKey: String, allItems: [PracticeItemSnapshot]) -> Self {
        PracticeHomeState(
            selectedDayKey: selectedDayKey,
            items: PracticeItemRules.items(for: selectedDayKey, in: allItems),
            totalDurationSeconds: PracticeItemRules.totalDuration(for: selectedDayKey, in: allItems),
            checkedInDayKeys: PracticeItemRules.checkedInDayKeys(in: allItems)
        )
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
