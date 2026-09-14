import Foundation

enum GitaPracticeExtensionError: Error, Equatable {
    case unsupportedRecipe(String)
    case invalidArtifact
}

struct GitaPracticeExtension: AgentExtension {
    let id = "gita.practice"

    let recipes: [RecipeDefinition] = [
        recipe(for: .nextSession, approval: .hostRequired),
        recipe(for: .planFromImage, approval: .hostRequired),
        recipe(for: .reviewMedia, approval: .none),
        recipe(for: .diagnoseVideo, approval: .none),
    ]

    func staticSystem(for recipe: RecipeDefinition) throws -> String {
        try skill(for: recipe.id).systemPrompt
    }

    func decodeAndValidate(data: Data, plan: AgentExecutionPlan) throws -> AnySkillArtifact {
        let payload = try normalizedJSON(data)
        switch plan.recipe.id {
        case SkillID.nextSession, SkillID.planFromImage:
            _ = try JSONDecoder().decode(AIPracticeDraft.Raw.self, from: payload)
        case SkillID.reviewMedia:
            _ = try JSONDecoder().decode(MediaReviewDraft.Raw.self, from: payload)
        case SkillID.diagnoseVideo:
            _ = try JSONDecoder().decode(VideoDiagnosisDraft.Raw.self, from: payload)
        default:
            throw GitaPracticeExtensionError.unsupportedRecipe(plan.recipe.id)
        }

        return AnySkillArtifact(
            id: UUID(),
            invocationID: plan.invocationID,
            recipeID: plan.recipe.id,
            recipeVersion: plan.recipe.version,
            contextSnapshotID: plan.contextSnapshot.id,
            payloadData: payload,
            resourceRefs: Array(plan.seenSet.resources),
            requiresApproval: plan.recipe.approvalPolicy == .hostRequired
        )
    }

    private func skill(for recipeID: String) throws -> SkillDefinition {
        guard let skill = SkillRegistry.builtin.skill(id: recipeID) else {
            throw GitaPracticeExtensionError.unsupportedRecipe(recipeID)
        }
        return skill
    }

    private func normalizedJSON(_ data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8),
              let normalized = AITransport.stripMarkdownFences(text).data(using: .utf8) else {
            throw GitaPracticeExtensionError.invalidArtifact
        }
        return normalized
    }

    private static func recipe(
        for skill: SkillDefinition,
        approval: ApprovalPolicy
    ) -> RecipeDefinition {
        RecipeDefinition(
            id: skill.id,
            family: "gita.practice",
            version: skill.version,
            title: skill.title,
            fetchPolicy: FetchPolicy(
                allowedKinds: Self.allowedKinds(for: skill.id),
                maxItems: Self.maxItems(for: skill.id),
                maxCharactersPerItem: 6_000,
                maxTotalCharacters: 6_000
            ),
            outputSchemaID: "\(skill.id)@\(skill.version)",
            runtimeRequirements: .messagesOnly,
            approvalPolicy: approval,
            timeoutSeconds: skill.timeout ?? 60,
            allowsFormatRepair: skill.allowsFormatRetry
        )
    }

    private static func allowedKinds(for skillID: String) -> Set<String> {
        switch skillID {
        case SkillID.planFromImage: return ["image"]
        case SkillID.reviewMedia, SkillID.diagnoseVideo: return ["recording", "image", "memory"]
        default: return ["memory"]
        }
    }

    private static func maxItems(for skillID: String) -> Int {
        switch skillID {
        case SkillID.planFromImage: return 3
        case SkillID.reviewMedia, SkillID.diagnoseVideo: return 9
        default: return 1
        }
    }
}
