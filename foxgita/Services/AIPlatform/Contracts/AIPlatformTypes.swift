import Foundation

struct ResourceRef: Hashable, Codable, Sendable {
    let kind: String
    let id: String
}

struct InvocationMediaResource: Sendable {
    let ref: ResourceRef
    let mimeType: String
    let data: Data
}

struct InteractionRequest: Sendable {
    let invocationID: UUID
    let sessionID: UUID?
    let recipeHint: String
    let inputText: String
    let selectedResources: [ResourceRef]
    let mediaResources: [InvocationMediaResource]

    init(
        invocationID: UUID,
        sessionID: UUID?,
        recipeHint: String,
        inputText: String,
        selectedResources: [ResourceRef],
        mediaResources: [InvocationMediaResource] = []
    ) {
        self.invocationID = invocationID
        self.sessionID = sessionID
        self.recipeHint = recipeHint
        self.inputText = inputText
        self.selectedResources = selectedResources
        self.mediaResources = mediaResources
    }
}

enum ApprovalPolicy: String, Codable, Sendable {
    case none
    case hostRequired
}

enum RuntimeKind: String, Codable, Sendable {
    case messages
}

struct RuntimeRequirements: Equatable, Sendable {
    let allowedKinds: Set<RuntimeKind>
    let requiresDurability: Bool

    static let messagesOnly = Self(allowedKinds: [.messages], requiresDurability: false)
}
