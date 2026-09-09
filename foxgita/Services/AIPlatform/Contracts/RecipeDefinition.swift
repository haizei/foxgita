import Foundation

struct FetchPolicy: Equatable, Sendable {
    let allowedKinds: Set<String>
    let maxItems: Int
    let maxCharactersPerItem: Int
    let maxTotalCharacters: Int

    static let empty = Self(
        allowedKinds: [],
        maxItems: 0,
        maxCharactersPerItem: 0,
        maxTotalCharacters: 0
    )
}

struct RecipeDefinition: Equatable, Sendable {
    let id: String
    let family: String
    let version: String
    let title: String
    let fetchPolicy: FetchPolicy
    let outputSchemaID: String
    let runtimeRequirements: RuntimeRequirements
    let approvalPolicy: ApprovalPolicy
    let timeoutSeconds: TimeInterval
    let allowsFormatRepair: Bool
}
