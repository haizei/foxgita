import Foundation

struct ProjectSetupFields: Equatable {
    var name: String
    var goal: String
    var currentFocus: String
}

enum ProjectSetupError: Error, Equatable {
    case nameEmpty, goalEmpty, nameTooLong, goalTooLong, focusTooLong

    var fieldName: String {
        switch self {
        case .nameEmpty, .nameTooLong: return "name"
        case .goalEmpty, .goalTooLong: return "goal"
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

    static func isCreateDirty(
        name: String,
        goal: String,
        currentFocus: String,
        kind: String,
        stage: String
    ) -> Bool {
        !trimmed(name).isEmpty
            || !trimmed(goal).isEmpty
            || !trimmed(currentFocus).isEmpty
            || !trimmed(kind).isEmpty
            || !trimmed(stage).isEmpty
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
        trimmed(name) != trimmed(loadedName)
            || trimmed(goal) != trimmed(loadedGoal)
            || trimmed(currentFocus) != trimmed(loadedFocus)
            || trimmed(kind) != trimmed(loadedKind)
            || trimmed(stage) != trimmed(loadedStage)
    }

    static func prepare(
        name: String,
        goal: String,
        currentFocus: String
    ) -> Result<ProjectSetupFields, ProjectSetupError> {
        let name = trimmed(name)
        let goal = trimmed(goal)
        let focus = trimmed(currentFocus)
        if name.isEmpty { return .failure(.nameEmpty) }
        if goal.isEmpty { return .failure(.goalEmpty) }
        if name.count > nameMax { return .failure(.nameTooLong) }
        if goal.count > goalMax { return .failure(.goalTooLong) }
        if focus.count > focusMax { return .failure(.focusTooLong) }
        return .success(ProjectSetupFields(name: name, goal: goal, currentFocus: focus))
    }
}
