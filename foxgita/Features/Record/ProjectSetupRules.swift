import Foundation

struct ProjectSetupFields: Equatable {
    var name: String
    var goal: String
    var currentFocus: String
}

enum ProjectSetupError: Error, Equatable {
    case nameEmpty, nameTooLong, goalTooLong
    // Legacy call-site stubs; prepare never returns these.
    case goalEmpty, focusTooLong

    var fieldName: String {
        switch self {
        case .nameEmpty, .nameTooLong: return "name"
        case .goalTooLong, .goalEmpty: return "goal"
        case .focusTooLong: return "currentFocus"
        }
    }

    var reason: String {
        switch self {
        case .nameEmpty, .goalEmpty: return "empty"
        case .nameTooLong, .goalTooLong, .focusTooLong: return "too_long"
        }
    }
}

enum ProjectSetupRules {
    static let nameMax = 40
    static let goalMax = 120
    static let focusMax = 120

    static func trimmed(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clamp(_ raw: String, max: Int) -> String {
        String(raw.prefix(max))
    }

    static func hasGoal(_ raw: String) -> Bool {
        !trimmed(raw).isEmpty
    }

    static func hasFocus(_ raw: String) -> Bool {
        !trimmed(raw).isEmpty
    }

    static func showsReadyFocus(_ raw: String) -> Bool {
        hasFocus(raw)
    }

    static let kinds = ["歌曲", "技巧", "演出准备"]
    static let stages = ["熟悉内容", "分段练习", "串联整首", "稳定演奏", "完成"]

    static func isKnownKind(_ raw: String) -> Bool {
        kinds.contains(trimmed(raw))
    }

    static func isKnownStage(_ raw: String) -> Bool {
        stages.contains(trimmed(raw))
    }

    static func showsReadyStage(_ raw: String) -> Bool {
        !trimmed(raw).isEmpty
    }

    static func isCreateDirty(name: String, goal: String) -> Bool {
        !trimmed(name).isEmpty || !trimmed(goal).isEmpty
    }

    static func isCreateDirty(
        name: String,
        goal: String,
        currentFocus: String,
        kind: String,
        stage: String
    ) -> Bool {
        _ = currentFocus
        _ = kind
        _ = stage
        return isCreateDirty(name: name, goal: goal)
    }

    static func isEditDirty(
        name: String,
        goal: String,
        loadedName: String,
        loadedGoal: String
    ) -> Bool {
        trimmed(name) != trimmed(loadedName) || trimmed(goal) != trimmed(loadedGoal)
    }

    static func isEditDirty(
        name: String,
        goal: String,
        currentFocus: String,
        kind: String,
        stage: String,
        loadedName: String,
        loadedGoal: String,
        loadedFocus: String,
        loadedKind: String,
        loadedStage: String
    ) -> Bool {
        _ = currentFocus
        _ = kind
        _ = stage
        _ = loadedFocus
        _ = loadedKind
        _ = loadedStage
        return isEditDirty(
            name: name,
            goal: goal,
            loadedName: loadedName,
            loadedGoal: loadedGoal
        )
    }

    static func isFromPracticeDirty(name: String, initialName: String) -> Bool {
        trimmed(name) != trimmed(initialName)
    }

    static func prepare(name: String, goal: String) -> Result<ProjectSetupFields, ProjectSetupError> {
        let name = trimmed(name)
        let goal = trimmed(goal)
        if name.isEmpty { return .failure(.nameEmpty) }
        if name.count > nameMax { return .failure(.nameTooLong) }
        if goal.count > goalMax { return .failure(.goalTooLong) }
        return .success(ProjectSetupFields(name: name, goal: goal, currentFocus: ""))
    }

    static func prepare(name: String, goal: String, currentFocus: String) -> Result<ProjectSetupFields, ProjectSetupError> {
        _ = currentFocus
        return prepare(name: name, goal: goal)
    }
}
