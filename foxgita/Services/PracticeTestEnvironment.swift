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

    static var defaults: UserDefaults {
        if isActive, let defaults = UserDefaults(suiteName: "gita.practice-test-fixtures") { return defaults }
        return .standard
    }
}
