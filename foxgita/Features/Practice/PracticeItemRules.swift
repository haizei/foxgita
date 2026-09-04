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
    let subtitle: String
    let targetMin: Int

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
        categoryRaw: String = PracticeCategory.chord.rawValue,
        subtitle: String = "",
        targetMin: Int = 0
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
        self.subtitle = subtitle
        self.targetMin = targetMin
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
