import Foundation

private struct MediaReviewContextReader: ContextResourceReading {
    let resources: [ResourceRef: String]

    func fetch(ref: ResourceRef, scope: ContextFetchScope) async throws -> ContextResource {
        guard scope.authorizes(ref) else { throw ContextFetchError.notAuthorized(ref) }
        guard let text = resources[ref] else { throw ContextFetchError.notFound(ref) }
        return ContextResource(ref: ref, text: text, trusted: false, revision: "invocation")
    }
}

struct MediaReviewRecipeRunner: MediaReviewing {
    let session: URLSession
    let log: any AIInvocationRecording
    let memory: any MemoryContextProviding

    init(
        session: URLSession = .shared,
        memory: any MemoryContextProviding = EmptyMemoryContext(),
        log: any AIInvocationRecording = EmptyAIInvocationLog()
    ) {
        self.session = session
        self.memory = memory
        self.log = log
    }

    func generateReview(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        contextText: String,
        invocationId: String
    ) async throws -> MediaReviewDraft {
        let startedAt = Date()
        let invocationID = UUID(uuidString: invocationId) ?? UUID()
        let sessionID = UUID()
        let recordingRef = ResourceRef(kind: "recording", id: "recording-\(invocationID.uuidString)")
        let memorySnapshot = await memory.snapshot(skill: .reviewMedia, query: contextText)
        let memoryRef = memorySnapshot.block.isEmpty ? nil : ResourceRef(
            kind: "memory", id: "memory-\(invocationID.uuidString)"
        )
        let imageRefs = imageJPEGData.indices.map {
            ResourceRef(kind: "image", id: "media-\(invocationID.uuidString)-\($0 + 1)")
        }
        var resources = [recordingRef: contextText]
        if let memoryRef { resources[memoryRef] = memorySnapshot.block }
        imageRefs.forEach { resources[$0] = "Derived visual evidence for selected recording." }
        let media = zip(imageRefs, imageJPEGData).map {
            InvocationMediaResource(ref: $0.0, mimeType: "image/jpeg", data: $0.1)
        }
        let request = InteractionRequest(
            invocationID: invocationID,
            sessionID: sessionID,
            recipeHint: SkillID.reviewMedia,
            inputText: SkillDefinition.reviewMedia.userPrompt ?? "请基于本次媒体证据生成练习复盘。",
            selectedResources: [recordingRef] + imageRefs + (memoryRef.map { [$0] } ?? []),
            mediaResources: media
        )
        let orchestrator = AgentOrchestrator(
            registry: try ExtensionRegistry(extensions: [GitaPracticeExtension()]),
            context: ContextFetcher(reader: MediaReviewContextReader(resources: resources)),
            runtimeRouter: RuntimeRouter(messages: MessagesRuntime(transport: AITransport(session: session))),
            inputGate: StandardInputGate(),
            presentationGate: StandardPresentationGate()
        )

        do {
            let result = try await orchestrator.run(
                request: request,
                credentials: RuntimeCredentials(baseURL: baseURL, apiKey: apiKey, model: model)
            )
            let raw = try JSONDecoder().decode(MediaReviewDraft.Raw.self, from: result.artifact.payloadData)
            let draft = try MediaReviewDraft.normalize(raw)
            await log.record(AIInvocationRecordInput(
                id: invocationID.uuidString, skillId: SkillID.reviewMedia,
                skillVersion: SkillDefinition.reviewMedia.version, model: model,
                startedAt: startedAt, durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)),
                status: .success, errorType: nil, memoryIds: memorySnapshot.itemIds,
                formatRetryUsed: result.formatRepairUsed, draftOutcome: nil,
                runtime: RuntimeKind.messages.rawValue, executionState: result.state,
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
            await recordCancellation(invocationID: invocationID, sessionID: sessionID, model: model, startedAt: startedAt, memoryIDs: memorySnapshot.itemIds)
            throw CancellationError()
        } catch let error as AIRuntimeError where error == .cancelled {
            await recordCancellation(invocationID: invocationID, sessionID: sessionID, model: model, startedAt: startedAt, memoryIDs: memorySnapshot.itemIds)
            throw CancellationError()
        } catch {
            let mapped = Self.map(error)
            await log.record(AIInvocationClientRecord.make(
                id: invocationID.uuidString, skill: .reviewMedia, model: model,
                startedAt: startedAt, status: .failure, error: mapped,
                memoryIds: memorySnapshot.itemIds, formatRetryUsed: false
            ))
            throw mapped
        }
    }

    private func recordCancellation(
        invocationID: UUID, sessionID: UUID, model: String, startedAt: Date, memoryIDs: [String]
    ) async {
        await log.record(AIInvocationRecordInput(
            id: invocationID.uuidString, skillId: SkillID.reviewMedia,
            skillVersion: SkillDefinition.reviewMedia.version, model: model,
            startedAt: startedAt, durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)),
            status: .failure, errorType: .cancelled, memoryIds: memoryIDs,
            formatRetryUsed: false, draftOutcome: nil,
            runtime: RuntimeKind.messages.rawValue, executionState: .cancelled,
            sessionID: sessionID.uuidString
        ))
    }

    private static func map(_ error: Error) -> VisionPracticeError {
        if let value = error as? VisionPracticeError { return value }
        if error is MediaReviewDraftError { return .invalidJSON }
        guard let value = error as? AIRuntimeError else { return .invalidJSON }
        switch value {
        case .invalidURL: return .invalidURL
        case .unauthorized: return .unauthorized
        case .httpStatus(let code): return .httpStatus(code)
        case .emptyContent: return .emptyContent
        case .invalidResponse: return .invalidJSON
        case .timeout: return .timeout
        case .transport, .cancelled: return .transport
        }
    }
}
