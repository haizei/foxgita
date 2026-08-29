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

    static func isCreateDirty(name: String, goal: String, currentFocus: String) -> Bool {
        !trimmed(name).isEmpty || !trimmed(goal).isEmpty || !trimmed(currentFocus).isEmpty
    }

    static func isEditDirty(
        name: String,
        goal: String,
        currentFocus: String,
        loadedName: String,
        loadedGoal: String,
        loadedFocus: String
    ) -> Bool {
        trimmed(name) != trimmed(loadedName)
            || trimmed(goal) != trimmed(loadedGoal)
            || trimmed(currentFocus) != trimmed(loadedFocus)
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
