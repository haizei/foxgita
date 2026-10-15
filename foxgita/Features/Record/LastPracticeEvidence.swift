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

    var dateAndDuration: String {
        let minutes = ProgressFirstFormat.minutes(fromSeconds: durationSeconds)
        return String(localized: "\(ProgressFirstFormat.monthDay(dayKey)) · \(minutes)分钟")
    }

    var recordingLabel: String? {
        guard let recording else { return nil }
        return ProgressFirstFormat.recordingLabel(durationSec: recording.durationSec)
    }

    static func latest(projectId: UUID, items: [PracticeItemSnapshot]) -> LastPracticeEvidence? {
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
            recording: match.recordings.first { !$0.fileName.isEmpty }
        )
    }
}
