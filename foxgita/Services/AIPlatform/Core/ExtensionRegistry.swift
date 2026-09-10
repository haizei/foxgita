import Foundation

enum ExtensionRegistryError: Error, Equatable, Sendable {
    case duplicateRecipeID(String)
    case recipeNotFound(String)
}

struct ResolvedAgentRecipe: Sendable {
    let agentExtension: any AgentExtension
    let recipe: RecipeDefinition
}

struct ExtensionRegistry: Sendable {
    private let recipesByID: [String: ResolvedAgentRecipe]

    init(extensions: [any AgentExtension]) throws {
        var recipesByID: [String: ResolvedAgentRecipe] = [:]

        for agentExtension in extensions {
            for recipe in agentExtension.recipes {
                guard recipesByID[recipe.id] == nil else {
                    throw ExtensionRegistryError.duplicateRecipeID(recipe.id)
                }
                recipesByID[recipe.id] = ResolvedAgentRecipe(
                    agentExtension: agentExtension,
                    recipe: recipe
                )
            }
        }

        self.recipesByID = recipesByID
    }

    func resolve(recipeID: String) throws -> ResolvedAgentRecipe {
        guard let resolved = recipesByID[recipeID] else {
            throw ExtensionRegistryError.recipeNotFound(recipeID)
        }
        return resolved
    }
}
