import Foundation

struct PracticeItemSnapshot: Equatable, Identifiable {
    let id: UUID
    let practiceDayKey: String
    let createdAt: Date
    let title: String
    let durationSeconds: Int
    let isDeleted: Bool
}

enum PracticeItemRules {
    static func items(for dayKey: String, in items: [PracticeItemSnapshot]) -> [PracticeItemSnapshot] {
        items
            .filter { !$0.isDeleted && $0.practiceDayKey == dayKey }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func totalDuration(for dayKey: String, in items: [PracticeItemSnapshot]) -> Int {
        Self.items(for: dayKey, in: items).reduce(0) { $0 + max(0, $1.durationSeconds) }
    }

    static func checkedInDayKeys(in items: [PracticeItemSnapshot]) -> Set<String> {
        Set(items.filter { !$0.isDeleted }.map(\.practiceDayKey))
    }
}

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
}
