import Foundation

struct ResourceRef: Hashable, Codable, Sendable {
    let kind: String
    let id: String
}

struct InteractionRequest: Sendable {
    let invocationID: UUID
    let sessionID: UUID?
    let recipeHint: String
    let inputText: String
    let selectedResources: [ResourceRef]
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
