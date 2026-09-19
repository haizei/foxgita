import Foundation

protocol ImagePlanRunning: Sendable {
    func runImagePlan(
        imageJPEGData: [Data],
        fallbackCategory: PracticeCategory,
        credentials: RuntimeCredentials,
        invocationID: UUID
    ) async throws -> AIPracticeDraft
}

struct ImagePlanRecipeRunner: ImagePlanRunning {
    let platform: GitaAIRunner
    let log: any AIInvocationRecording

    init(
        session: URLSession = .shared,
        log: any AIInvocationRecording = EmptyAIInvocationLog()
    ) {
        self.platform = GitaAIRunner(session: session)
        self.log = log
    }

    init(platform: GitaAIRunner, log: any AIInvocationRecording = EmptyAIInvocationLog()) {
        self.platform = platform
        self.log = log
    }

    func runImagePlan(
        imageJPEGData: [Data],
        fallbackCategory: PracticeCategory,
        credentials: RuntimeCredentials,
        invocationID: UUID
    ) async throws -> AIPracticeDraft {
        let startedAt = Date()
        let sessionID = UUID()
        let refs = imageJPEGData.indices.map {
            ResourceRef(kind: "image", id: "image-\(invocationID.uuidString)-\($0 + 1)")
        }
        let media = zip(refs, imageJPEGData).map {
            InvocationMediaResource(ref: $0.0, mimeType: "image/jpeg", data: $0.1)
        }
        let skill = SkillDefinition.planFromImage
        let request = InteractionRequest(
            invocationID: invocationID,
            sessionID: sessionID,
            recipeHint: skill.id,
            inputText: skill.userPrompt ?? "",
            selectedResources: refs,
            mediaResources: media
        )
        let resources = Dictionary(uniqueKeysWithValues: refs.map {
            ($0, ContextResource(
                ref: $0,
                text: "User-selected image available as invocation-scoped binary input.",
                trusted: false,
                revision: "invocation"
            ))
        })

        do {
            let result = try await platform.run(
                request: request,
                resources: resources,
                credentials: credentials
            )
            let raw = try JSONDecoder().decode(AIPracticeDraft.Raw.self, from: result.artifact.payloadData)
            let draft = AIPracticeDraft.normalize(raw, fallbackCategory: fallbackCategory)
            await log.record(AIInvocationRecordInput(
                id: invocationID.uuidString,
                skillId: skill.id,
                skillVersion: skill.version,
                model: credentials.model,
                startedAt: startedAt,
                durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)),
                status: .success,
                errorType: nil,
                memoryIds: [],
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
            await recordFailure(.cancelled, state: .cancelled, outcome: .abandoned, invocationID: invocationID, sessionID: sessionID, model: credentials.model, startedAt: startedAt)
            throw CancellationError()
        } catch let error as AIRuntimeError where error == .cancelled {
            await recordFailure(.cancelled, state: .cancelled, outcome: .abandoned, invocationID: invocationID, sessionID: sessionID, model: credentials.model, startedAt: startedAt)
            throw CancellationError()
        } catch {
            let mapped = Self.map(error)
            await recordFailure(AIInvocationStore.errorType(from: mapped), state: .failed, outcome: .failed, invocationID: invocationID, sessionID: sessionID, model: credentials.model, startedAt: startedAt)
            throw mapped
        }
    }

    private func recordFailure(
        _ errorType: AIInvocationErrorType,
        state: AIExecutionState,
        outcome: AIDraftOutcome,
        invocationID: UUID,
        sessionID: UUID,
        model: String,
        startedAt: Date
    ) async {
        await log.record(AIInvocationRecordInput(
            id: invocationID.uuidString,
            skillId: SkillDefinition.planFromImage.id,
            skillVersion: SkillDefinition.planFromImage.version,
            model: model,
            startedAt: startedAt,
            durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)),
            status: .failure,
            errorType: errorType,
            memoryIds: [],
            formatRetryUsed: false,
            draftOutcome: outcome,
            runtime: RuntimeKind.messages.rawValue,
            executionState: state,
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
        case .transport, .cancelled: return .transport
        }
    }
}
