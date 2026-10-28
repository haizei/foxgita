import Foundation

enum PracticeRecordRules {
    static func isUserAddedTask(id: String) -> Bool {
        id.hasPrefix("custom-") || id.hasPrefix("active-")
    }

    static func isEffective(
        durationSec: Int, noteText: String, recordingCount: Int, imageCount: Int = 0
    ) -> Bool {
        if durationSec > 0 { return true }
        if !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return recordingCount > 0 || imageCount > 0
    }
}
