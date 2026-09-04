import Foundation

protocol MediaReviewing: Sendable {
    func generateReview(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        contextText: String,
        invocationId: String
    ) async throws -> MediaReviewDraft
}

struct MediaReviewClient: MediaReviewing {
    private let transport: AITransport
    private let registry: SkillRegistry
    private let memory: any MemoryContextProviding
    private let log: any AIInvocationRecording

    init(
        session: URLSession = .shared,
        registry: SkillRegistry = .builtin,
        memory: any MemoryContextProviding = EmptyMemoryContext(),
        log: any AIInvocationRecording = EmptyAIInvocationLog()
    ) {
        self.transport = AITransport(session: session)
        self.registry = registry
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
        guard let skill = registry.skill(id: SkillID.reviewMedia) else {
            await log.record(AIInvocationClientRecord.make(
                id: invocationId,
                skill: SkillDefinition.reviewMedia,
                model: model,
                startedAt: startedAt,
                status: .failure,
                error: VisionPracticeError.unregisteredSkill,
                memoryIds: [],
                formatRetryUsed: false
            ))
            throw VisionPracticeError.unregisteredSkill
        }
        guard let url = AITransport.completionsURL(from: baseURL) else {
            await log.record(AIInvocationClientRecord.make(
                id: invocationId,
                skill: skill,
                model: model,
                startedAt: startedAt,
                status: .failure,
                error: VisionPracticeError.invalidURL,
                memoryIds: [],
                formatRetryUsed: false
            ))
            throw VisionPracticeError.invalidURL
        }
        let userText = skill.userPrompt ?? contextText
        let snap = await memory.snapshot(skill: skill, query: contextText)
        let finalUserText = snap.block.isEmpty ? userText : userText + "\n\n" + snap.block
        let result: AITransportResult
        do {
            result = try await transport.complete(
                url: url,
                apiKey: apiKey,
                model: model,
                systemPrompt: skill.systemPrompt,
                userText: finalUserText,
                imageJPEGData: imageJPEGData,
                includeResponseFormat: true,
                allowsFormatRetry: skill.allowsFormatRetry,
                timeout: skill.timeout
            )
        } catch {
            let thrown = AIInvocationClientRecord.thrownError(from: error)
            await log.record(AIInvocationClientRecord.make(
                id: invocationId,
                skill: skill,
                model: model,
                startedAt: startedAt,
                status: .failure,
                error: thrown,
                memoryIds: snap.itemIds,
                formatRetryUsed: false
            ))
            throw thrown
        }
        guard !result.content.isEmpty else {
            await log.record(AIInvocationClientRecord.make(
                id: invocationId,
                skill: skill,
                model: model,
                startedAt: startedAt,
                status: .failure,
                error: VisionPracticeError.invalidJSON,
                memoryIds: snap.itemIds,
                formatRetryUsed: result.formatRetryUsed
            ))
            throw VisionPracticeError.invalidJSON
        }
        do {
            let draft = try Self.parseDraft(from: result.content)
            await log.record(AIInvocationClientRecord.make(
                id: invocationId,
                skill: skill,
                model: model,
                startedAt: startedAt,
                status: .success,
                error: nil,
                memoryIds: snap.itemIds,
                formatRetryUsed: result.formatRetryUsed
            ))
            return draft
        } catch {
            let thrown = (error as? VisionPracticeError) ?? .invalidJSON
            await log.record(AIInvocationClientRecord.make(
                id: invocationId,
                skill: skill,
                model: model,
                startedAt: startedAt,
                status: .failure,
                error: thrown,
                memoryIds: snap.itemIds,
                formatRetryUsed: result.formatRetryUsed
            ))
            throw thrown
        }
    }

    private static func parseDraft(from content: String) throws -> MediaReviewDraft {
        let jsonText = AITransport.stripMarkdownFences(content)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw VisionPracticeError.invalidJSON
        }
        let raw: MediaReviewDraft.Raw
        do {
            raw = try JSONDecoder().decode(MediaReviewDraft.Raw.self, from: jsonData)
        } catch {
            throw VisionPracticeError.invalidJSON
        }
        do {
            return try MediaReviewDraft.normalize(raw)
        } catch {
            throw VisionPracticeError.invalidJSON
        }
    }
}
