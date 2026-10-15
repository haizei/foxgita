import Foundation

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
