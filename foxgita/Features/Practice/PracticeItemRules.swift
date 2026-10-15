import Foundation

struct PracticeRecordingClip: Equatable, Identifiable {
    let id: String
    let fileName: String
    let durationSec: Int
    let createdAt: Date
}

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
    let recordings: [PracticeRecordingClip]

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
        categoryRaw: String = "chord",
        subtitle: String = "",
        targetMin: Int = 0,
        recordings: [PracticeRecordingClip] = []
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
        self.recordings = recordings
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
