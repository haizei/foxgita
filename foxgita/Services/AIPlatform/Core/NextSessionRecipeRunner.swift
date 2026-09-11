import Foundation

private struct NextSessionContextReader: ContextResourceReading {
    let resource: ContextResource?

    func fetch(ref: ResourceRef, scope: ContextFetchScope) async throws -> ContextResource {
        guard scope.authorizes(ref) else { throw ContextFetchError.notAuthorized(ref) }
        guard let resource, resource.ref == ref else { throw ContextFetchError.notFound(ref) }
        return resource
    }
}

private struct StandardInputGate: InputGating {
    func validate(
        request: InteractionRequest,
        recipe: RecipeDefinition,
        snapshot: ContextSnapshot,
        prompt: PromptAssembly
    ) throws {
        guard !request.inputText.isEmpty, request.inputText.count <= 8_000 else {
            throw GateRefusal.constraintViolated("input is empty or too large")
        }
    }
}

private struct StandardPresentationGate: PresentationGating {
    func validate(artifact: AnySkillArtifact, plan: AgentExecutionPlan) throws {}
}

struct NextSessionRecipeRunner: NextSessionGenerating {
    let session: URLSession
    let memory: any MemoryContextProviding
    let log: any AIInvocationRecording

    init(
        session: URLSession = .shared,
        memory: any MemoryContextProviding = EmptyMemoryContext(),
        log: any AIInvocationRecording = EmptyAIInvocationLog()
    ) {
        self.session = session
        self.memory = memory
        self.log = log
    }

    func generateDraft(
        baseURL: String,
        model: String,
        apiKey: String,
        budgetMinutes: Int,
        fallbackCategory: PracticeCategory,
        invocationId: String
    ) async throws -> AIPracticeDraft {
        let startedAt = Date()
        let invocationID = UUID(uuidString: invocationId) ?? UUID()
        let sessionID = UUID()
        let skill = SkillDefinition.nextSession
        let budget = NextSessionClient.clampBudget(budgetMinutes)
        let memorySnapshot = await memory.snapshot(skill: skill, query: "")
        let memoryRef = memorySnapshot.block.isEmpty
            ? nil
            : ResourceRef(kind: "memory", id: "memory-\(invocationID.uuidString)")
        let resource = memoryRef.map {
            ContextResource(ref: $0, text: memorySnapshot.block, trusted: true, revision: "current")
        }
        let request = InteractionRequest(
            invocationID: invocationID,
            sessionID: sessionID,
            recipeHint: skill.id,
            inputText: (skill.userPrompt ?? "").replacingOccurrences(of: "{{minutes}}", with: "\(budget)"),
            selectedResources: memoryRef.map { [$0] } ?? []
        )
        let orchestrator = AgentOrchestrator(
            registry: try ExtensionRegistry(extensions: [GitaPracticeExtension()]),
            context: ContextFetcher(reader: NextSessionContextReader(resource: resource)),
            runtimeRouter: RuntimeRouter(messages: MessagesRuntime(transport: AITransport(session: session))),
            inputGate: StandardInputGate(),
            presentationGate: StandardPresentationGate()
        )

        do {
            let result = try await orchestrator.run(
                request: request,
                credentials: RuntimeCredentials(baseURL: baseURL, apiKey: apiKey, model: model)
            )
            let raw = try JSONDecoder().decode(AIPracticeDraft.Raw.self, from: result.artifact.payloadData)
            var draft = AIPracticeDraft.normalize(
                NextSessionClient.capRaw(raw, budget: budget),
                fallbackCategory: fallbackCategory
            )
            draft.sourceMemoryIDs = memorySnapshot.itemIds
            await log.record(AIInvocationRecordInput(
                id: invocationID.uuidString,
                skillId: skill.id,
                skillVersion: skill.version,
                model: model,
                startedAt: startedAt,
                durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)),
                status: .success,
                errorType: nil,
                memoryIds: memorySnapshot.itemIds,
                formatRetryUsed: result.formatRepairUsed,
                draftOutcome: nil,
                runtime: RuntimeKind.messages.rawValue,
                executionState: result.state,
                sessionID: sessionID.uuidString,
                staticPromptFingerprint: result.prompt.staticPromptFingerprint,
                historyPrefixFingerprint: result.prompt.historyPrefixFingerprint,
                contextFingerprint: result.prompt.contextFingerprint,
                toolsetFingerprint: result.prompt.toolsetFingerprint,
                usage: result.usage
            ))
            await log.linkArtifact(
                invocationID: invocationID.uuidString,
                artifactID: result.artifact.id.uuidString,
                contextSnapshotID: result.artifact.contextSnapshotID.uuidString
            )
            return draft
        } catch is CancellationError {
            await recordCancellation(
                invocationID: invocationID,
                sessionID: sessionID,
                model: model,
                startedAt: startedAt,
                memoryIDs: memorySnapshot.itemIds
            )
            throw CancellationError()
        } catch let error as AIRuntimeError where error == .cancelled {
            await recordCancellation(
                invocationID: invocationID,
                sessionID: sessionID,
                model: model,
                startedAt: startedAt,
                memoryIDs: memorySnapshot.itemIds
            )
            throw CancellationError()
        } catch {
            let mapped = Self.map(error)
            await log.record(AIInvocationClientRecord.make(
                id: invocationID.uuidString,
                skill: skill,
                model: model,
                startedAt: startedAt,
                status: .failure,
                error: mapped,
                memoryIds: memorySnapshot.itemIds,
                formatRetryUsed: false
            ))
            throw mapped
        }
    }

    private func recordCancellation(
        invocationID: UUID,
        sessionID: UUID,
        model: String,
        startedAt: Date,
        memoryIDs: [String]
    ) async {
        await log.record(AIInvocationRecordInput(
            id: invocationID.uuidString,
            skillId: SkillDefinition.nextSession.id,
            skillVersion: SkillDefinition.nextSession.version,
            model: model,
            startedAt: startedAt,
            durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)),
            status: .failure,
            errorType: .cancelled,
            memoryIds: memoryIDs,
            formatRetryUsed: false,
            draftOutcome: .abandoned,
            runtime: RuntimeKind.messages.rawValue,
            executionState: .cancelled,
            sessionID: sessionID.uuidString
        ))
    }

    private static func map(_ error: Error) -> VisionPracticeError {
        if let error = error as? VisionPracticeError { return error }
        guard let error = error as? AIRuntimeError else { return .invalidJSON }
        switch error {
        case .invalidURL: return .invalidURL
        case .unauthorized: return .unauthorized
        case .httpStatus(let status): return .httpStatus(status)
        case .emptyContent: return .emptyContent
        case .invalidResponse: return .invalidJSON
        case .timeout: return .timeout
        case .transport: return .transport
        case .cancelled: return .transport
        }
    }
}
