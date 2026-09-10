import Foundation

protocol AgentExtension: ArtifactDecoding {
    var id: String { get }
    var recipes: [RecipeDefinition] { get }

    func staticSystem(for recipe: RecipeDefinition) throws -> String
}
