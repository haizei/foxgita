import Foundation

enum RecipeMigrationState: String, Sendable {
    case legacy
    case internalPlatform
    case platformDefault
    case removed
}

struct RecipeMigrationResolver: Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func state(for recipeID: String) -> RecipeMigrationState {
        let key = "ai.recipe.migration.\(recipeID)"
        if let raw = defaults.string(forKey: key), let state = RecipeMigrationState(rawValue: raw) {
            return state
        }
        #if DEBUG
        return .internalPlatform
        #else
        return .legacy
        #endif
    }

    func usesPlatform(for recipeID: String) -> Bool {
        switch state(for: recipeID) {
        case .legacy: false
        case .internalPlatform, .platformDefault, .removed: true
        }
    }
}
