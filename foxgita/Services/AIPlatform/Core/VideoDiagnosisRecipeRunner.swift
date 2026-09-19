import Foundation

protocol VideoDiagnosing: Sendable {
    func generateDiagnosis(
        baseURL: String, model: String, apiKey: String, imageJPEGData: [Data],
        contextText: String, durationSec: Int, invocationId: String
    ) async throws -> VideoDiagnosisDraft
}

struct VideoDiagnosisRecipeRunner: VideoDiagnosing {
    let platform: GitaAIRunner
    let log: any AIInvocationRecording
    let memory: any MemoryContextProviding

    init(
        session: URLSession = .shared,
        memory: any MemoryContextProviding = EmptyMemoryContext(),
        log: any AIInvocationRecording = EmptyAIInvocationLog()
    ) {
        self.platform = GitaAIRunner(session: session)
        self.memory = memory
        self.log = log
    }

    init(
        platform: GitaAIRunner,
        memory: any MemoryContextProviding = EmptyMemoryContext(),
        log: any AIInvocationRecording = EmptyAIInvocationLog()
    ) {
        self.platform = platform
        self.memory = memory
        self.log = log
    }

    func generateDiagnosis(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        contextText: String,
        durationSec: Int,
        invocationId: String
    ) async throws -> VideoDiagnosisDraft {
        let startedAt = Date()
        let invocationID = UUID(uuidString: invocationId) ?? UUID()
        let sessionID = UUID()
        let recordingRef = ResourceRef(kind: "recording", id: "recording-\(invocationID.uuidString)")
        let memorySnapshot = await memory.snapshot(skill: .diagnoseVideo, query: contextText)
        let memoryRef = memorySnapshot.block.isEmpty
            ? nil : ResourceRef(kind: "memory", id: "memory-\(invocationID.uuidString)")
        let imageRefs = imageJPEGData.indices.map {
            ResourceRef(kind: "image", id: "video-frame-\(invocationID.uuidString)-\($0 + 1)")
        }
        var resourceTexts = [recordingRef: "\(contextText)\ndurationSec=\(max(durationSec, 0))"]
        if let memoryRef { resourceTexts[memoryRef] = memorySnapshot.block }
        imageRefs.forEach { resourceTexts[$0] = "Derived visual frame from the selected recording." }
        let resources = Dictionary(uniqueKeysWithValues: resourceTexts.map { ref, text in
            (ref, ContextResource(ref: ref, text: text, trusted: false, revision: "invocation"))
        })
        let media = zip(imageRefs, imageJPEGData).map {
            InvocationMediaResource(ref: $0.0, mimeType: "image/jpeg", data: $0.1)
        }
        let request = InteractionRequest(
            invocationID: invocationID,
            sessionID: sessionID,
            recipeHint: SkillID.diagnoseVideo,
            inputText: SkillDefinition.diagnoseVideo.userPrompt
                ?? "请基于本次视频证据生成分段诊断。",
            selectedResources: [recordingRef] + imageRefs + (memoryRef.map { [$0] } ?? []),
            mediaResources: media
        )
        do {
            let result = try await platform.run(
                request: request,
                resources: resources,
                credentials: RuntimeCredentials(baseURL: baseURL, apiKey: apiKey, model: model)
            )
            let raw = try JSONDecoder().decode(
                VideoDiagnosisDraft.Raw.self, from: result.artifact.payloadData
            )
            let draft = try VideoDiagnosisDraft.normalize(
                raw,
                durationSec: durationSec,
                hasDeterministicAudioEvidence: false
            )
            await log.record(AIInvocationRecordInput(
                id: invocationID.uuidString,
                skillId: SkillID.diagnoseVideo,
                skillVersion: SkillDefinition.diagnoseVideo.version,
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
                skill: .diagnoseVideo,
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
            skillId: SkillID.diagnoseVideo,
            skillVersion: SkillDefinition.diagnoseVideo.version,
            model: model,
            startedAt: startedAt,
            durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)),
            status: .failure,
            errorType: .cancelled,
            memoryIds: memoryIDs,
            formatRetryUsed: false,
            draftOutcome: nil,
            runtime: RuntimeKind.messages.rawValue,
            executionState: .cancelled,
            sessionID: sessionID.uuidString
        ))
    }

    private static func map(_ error: Error) -> VisionPracticeError {
        if let value = error as? VisionPracticeError { return value }
        if error is VideoDiagnosisDraftError { return .invalidJSON }
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
