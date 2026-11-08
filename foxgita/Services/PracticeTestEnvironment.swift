import Foundation

/// Keeps UI/unit test fixtures away from the developer's practice database and media.
nonisolated enum PracticeTestEnvironment {
    static var isActive: Bool {
        #if DEBUG
        let process = ProcessInfo.processInfo
        return process.arguments.contains("-UITesting")
            || process.arguments.contains("-DNAProgramsUITesting")
            || process.arguments.contains("-ProjectDetailUITestFixture")
            || process.environment["XCTestConfigurationFilePath"] != nil
        #else
        return false
        #endif
    }

    static var recoveryRunID: UUID? {
        #if DEBUG && targetEnvironment(simulator)
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("-UITesting"),
              process.arguments.contains("-ScoreRecoveryFixture"),
              let value = process.environment["GITA_RECOVERY_RUN_ID"] else { return nil }
        return UUID(uuidString: value)
        #else
        return nil
        #endif
    }

    static var defaults: UserDefaults {
        if let runID = recoveryRunID {
            return UserDefaults(suiteName: "gita.recovery-test." + runID.uuidString)!
        }
        if isActive, let defaults = UserDefaults(suiteName: "gita.practice-test-fixtures") { return defaults }
        return .standard
    }
}
