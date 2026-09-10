import Foundation

struct AnySkillArtifact: Sendable {
    let id: UUID
    let invocationID: UUID
    let recipeID: String
    let recipeVersion: String
    let contextSnapshotID: UUID
    let payloadData: Data
    let resourceRefs: [ResourceRef]
    let requiresApproval: Bool
}
