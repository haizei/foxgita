import Foundation

enum PracticeResumeSkipStore {
    private static func key(_ taskId: String) -> String {
        "gita.practice.resumeSkip.\(taskId)"
    }

    static func skippedSessionId(taskId: String, defaults: UserDefaults = .standard) -> String? {
        let value = defaults.string(forKey: key(taskId))
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func skip(taskId: String, sessionId: String, defaults: UserDefaults = .standard) {
        defaults.set(sessionId, forKey: key(taskId))
    }

    static func clear(taskId: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(taskId))
    }
}
