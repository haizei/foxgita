import Foundation

enum ContextWarning: String, Codable, Sendable {
    case truncated
    case protocolTextNeutralized
    case controlCharactersRemoved
}

struct ContextSection: Codable, Sendable {
    let ref: ResourceRef
    let text: String
    let trusted: Bool
}

struct ContextSnapshot: Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let sections: [ContextSection]
    let warnings: [ContextWarning]
    let revision: String
}

struct SeenSet: Codable, Sendable {
    let snapshotID: UUID
    let resources: Set<ResourceRef>

    func contains(_ ref: ResourceRef) -> Bool {
        resources.contains(ref)
    }
}

struct AgentExecutionPlan: Sendable {
    let invocationID: UUID
    let sessionID: UUID
    let recipe: RecipeDefinition
    let contextSnapshot: ContextSnapshot
    let seenSet: SeenSet
    let mediaResources: [InvocationMediaResource]

    init(
        invocationID: UUID,
        sessionID: UUID,
        recipe: RecipeDefinition,
        contextSnapshot: ContextSnapshot,
        seenSet: SeenSet,
        mediaResources: [InvocationMediaResource] = []
    ) {
        self.invocationID = invocationID
        self.sessionID = sessionID
        self.recipe = recipe
        self.contextSnapshot = contextSnapshot
        self.seenSet = seenSet
        self.mediaResources = mediaResources
    }
}
