import Foundation

protocol ArtifactDecoding: Sendable {
    func decodeAndValidate(data: Data, plan: AgentExecutionPlan) throws -> AnySkillArtifact
}

enum ArtifactValidator {
    static func validate(
        _ artifact: AnySkillArtifact,
        plan: AgentExecutionPlan
    ) throws -> AnySkillArtifact {
        guard artifact.invocationID == plan.invocationID,
              artifact.recipeID == plan.recipe.id,
              artifact.recipeVersion == plan.recipe.version,
              artifact.contextSnapshotID == plan.contextSnapshot.id else {
            throw GateRefusal.constraintViolated("artifact envelope does not match execution plan")
        }

        let requiresApproval = plan.recipe.approvalPolicy == .hostRequired
        guard artifact.requiresApproval == requiresApproval else {
            throw GateRefusal.constraintViolated("artifact approval policy does not match recipe")
        }

        for ref in artifact.resourceRefs {
            try ProvenanceGate.validate(ref, against: plan.seenSet)
        }
        return artifact
    }
}
