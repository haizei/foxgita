import Foundation

struct PracticeItemSnapshot: Equatable, Identifiable {
    let id: UUID
    let practiceDayKey: String
    let createdAt: Date
    let title: String
    let durationSeconds: Int
    let isDeleted: Bool
    let projectId: UUID?
    let note: String
    let recordingCount: Int
    let categoryRaw: String

    init(
        id: UUID,
        practiceDayKey: String,
        createdAt: Date,
        title: String,
        durationSeconds: Int,
        isDeleted: Bool,
        projectId: UUID? = nil,
        note: String = "",
        recordingCount: Int = 0,
        categoryRaw: String = PracticeCategory.chord.rawValue
    ) {
        self.id = id
        self.practiceDayKey = practiceDayKey
        self.createdAt = createdAt
        self.title = title
        self.durationSeconds = durationSeconds
        self.isDeleted = isDeleted
        self.projectId = projectId
        self.note = note
        self.recordingCount = recordingCount
        self.categoryRaw = categoryRaw
    }
}

enum PracticeItemRules {
    static func isEffective(_ item: PracticeItemSnapshot) -> Bool {
        guard !item.isDeleted else { return false }
        return PracticeRecordRules.isEffective(
            durationSec: item.durationSeconds,
            noteText: item.note,
            recordingCount: item.recordingCount
        )
    }

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

    static func ctaTitle(isSelectedToday: Bool, durationSeconds: Int) -> String {
        guard isSelectedToday else { return String(localized: "查看") }
        return durationSeconds > 0 ? String(localized: "继续") : String(localized: "开始")
    }

    static func allowsSwipeDelete(isSelectedToday: Bool) -> Bool {
        isSelectedToday
    }
}
