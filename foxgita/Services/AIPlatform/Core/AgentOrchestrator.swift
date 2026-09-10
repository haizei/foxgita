import Foundation

protocol ContextSnapshotting: Sendable {
    func fetch(
        refs: [ResourceRef],
        policy: FetchPolicy,
        scope: ContextFetchScope
    ) async throws -> (ContextSnapshot, SeenSet)
}

extension ContextFetcher: ContextSnapshotting {}

protocol InputGating: Sendable {
    func validate(
        request: InteractionRequest,
        recipe: RecipeDefinition,
        snapshot: ContextSnapshot,
        prompt: PromptAssembly
    ) throws
}

protocol PresentationGating: Sendable {
    func validate(artifact: AnySkillArtifact, plan: AgentExecutionPlan) throws
}

struct OrchestrationResult: Sendable {
    let state: AIExecutionState
    let artifact: AnySkillArtifact
    let prompt: PromptAssembly
    let usage: RuntimeUsage
}

struct AgentOrchestrator: Sendable {
    let registry: ExtensionRegistry
    let context: any ContextSnapshotting
    let runtimeRouter: RuntimeRouter
    let inputGate: any InputGating
    let presentationGate: any PresentationGating

    func run(
        request: InteractionRequest,
        credentials: RuntimeCredentials
    ) async throws -> OrchestrationResult {
        let resolved = try registry.resolve(recipeID: request.recipeHint)
        guard let sessionID = request.sessionID else {
            throw GateRefusal.constraintViolated("execution requires a session")
        }

        let scope = ContextFetchScope(
            invocationID: request.invocationID,
            sessionID: sessionID,
            authorizedResources: Set(request.selectedResources)
        )
        let (snapshot, seenSet) = try await context.fetch(
            refs: request.selectedResources,
            policy: resolved.recipe.fetchPolicy,
            scope: scope
        )
        let snapshotResources = Set(snapshot.sections.map(\.ref))
        let authorizedResources = Set(request.selectedResources)
        guard seenSet.snapshotID == snapshot.id,
              seenSet.resources == snapshotResources,
              snapshotResources.isSubset(of: authorizedResources) else {
            throw GateRefusal.constraintViolated("context snapshot and seen set are outside request scope")
        }

        let plan = AgentExecutionPlan(
            invocationID: request.invocationID,
            sessionID: sessionID,
            recipe: resolved.recipe,
            contextSnapshot: snapshot,
            seenSet: seenSet
        )
        let prompt = PromptAssembler.assemble(
            tools: [],
            staticSystem: try resolved.agentExtension.staticSystem(for: resolved.recipe),
            dynamicContext: dynamicContext(from: snapshot),
            history: [],
            currentInput: request.inputText
        )
        try inputGate.validate(request: request, recipe: resolved.recipe, snapshot: snapshot, prompt: prompt)

        let runtime = try runtimeRouter.runtime(for: resolved.recipe.runtimeRequirements)
        let output = try await runtimeOutput(from: runtime.execute(plan: plan, prompt: prompt, credentials: credentials))
        let decoded = try resolved.agentExtension.decodeAndValidate(
            data: output.data,
            recipe: resolved.recipe,
            seenSet: seenSet
        )
        let artifact = try ArtifactValidator.validate(decoded, plan: plan)
        try presentationGate.validate(artifact: artifact, plan: plan)

        return OrchestrationResult(
            state: .presenting,
            artifact: artifact,
            prompt: prompt,
            usage: output.usage
        )
    }

    private func runtimeOutput(
        from stream: AsyncThrowingStream<RuntimeEvent, Error>
    ) async throws -> (data: Data, usage: RuntimeUsage) {
        var artifactData: Data?
        var usage = RuntimeUsage.zero

        for try await event in stream {
            switch event {
            case .artifactProduced(let data):
                guard artifactData == nil else { throw AIRuntimeError.invalidResponse }
                artifactData = data
            case .completed(let completedUsage):
                usage = completedUsage
            case .failed(let error):
                throw error
            case .cancelled:
                throw AIRuntimeError.cancelled
            case .accepted, .started, .modelDelta:
                break
            }
        }

        guard let artifactData else { throw AIRuntimeError.invalidResponse }
        return (artifactData, usage)
    }

    private func dynamicContext(from snapshot: ContextSnapshot) -> String {
        snapshot.sections.map { section in
            "kind=\(encodeMetadata(section.ref.kind))\nid=\(encodeMetadata(section.ref.id))\ntext=\(section.text)"
        }.joined(separator: "\n\n")
    }

    private func encodeMetadata(_ value: String) -> String {
        let fenced = ContextFencer.fence(value, limit: 128)
        let escaped = fenced.text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "\"\(escaped)\""
    }
}
