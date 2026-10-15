import Foundation

struct LastPracticeEvidence: Equatable {
    let itemId: UUID
    let dayKey: String
    let createdAt: Date
    let durationSeconds: Int
    let title: String
    let content: String
    let reflection: String
    let recording: PracticeRecordingClip?
    let hadRecording: Bool

    var dateAndDuration: String {
        let minutes = ProgressFirstFormat.minutes(fromSeconds: durationSeconds)
        return String(localized: "\(ProgressFirstFormat.monthDay(dayKey)) · \(minutes)分钟")
    }

    var recordingLabel: String? {
        guard let recording else { return nil }
        return ProgressFirstFormat.recordingLabel(durationSec: recording.durationSec)
    }

    static func latest(
        projectId: UUID,
        items: [PracticeItemSnapshot],
        isAvailable: (PracticeRecordingClip) -> Bool = { clip in
            RecordingStore.fileExists(fileName: clip.fileName)
        }
    ) -> LastPracticeEvidence? {
        let match = items
            .filter { $0.projectId == projectId && PracticeItemRules.isEffective($0) }
            .sorted { lhs, rhs in
                if lhs.practiceDayKey != rhs.practiceDayKey { return lhs.practiceDayKey > rhs.practiceDayKey }
                return lhs.createdAt > rhs.createdAt
            }
            .first
        guard let match else { return nil }
        return LastPracticeEvidence(
            itemId: match.id,
            dayKey: match.practiceDayKey,
            createdAt: match.createdAt,
            durationSeconds: match.durationSeconds,
            title: match.title,
            content: match.subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            reflection: match.note.trimmingCharacters(in: .whitespacesAndNewlines),
            recording: match.recordings
                .filter { !$0.fileName.isEmpty && isAvailable($0) }
                .max { $0.createdAt < $1.createdAt },
            hadRecording: match.recordingCount > 0 || !match.recordings.isEmpty
        )
    }
}
