import Foundation

enum PracticeRecordRules {
    static func isUserAddedTask(id: String) -> Bool {
        id.hasPrefix("custom-") || id.hasPrefix("active-")
    }

    static func isEffective(durationSec: Int, noteText: String, recordingCount: Int) -> Bool {
        if durationSec > 0 { return true }
        if !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return recordingCount > 0
    }
}

extension TaskItem {
    var isUserAdded: Bool { PracticeRecordRules.isUserAddedTask(id: id) }
}

extension PracticeSession {
    var isEffective: Bool {
        PracticeRecordRules.isEffective(
            durationSec: durationSec,
            noteText: noteText,
            recordingCount: recordings.count
        )
    }
}
