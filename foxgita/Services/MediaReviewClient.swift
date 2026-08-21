import Foundation

protocol MediaReviewing: Sendable {
    func generateReview(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        contextText: String
    ) async throws -> MediaReviewDraft
}

struct MediaReviewClient: MediaReviewing {
    private let transport: AITransport
    private let registry: SkillRegistry
    private let memory: any MemoryContextProviding

    init(
        session: URLSession = .shared,
        registry: SkillRegistry = .builtin,
        memory: any MemoryContextProviding = EmptyMemoryContext()
    ) {
        self.transport = AITransport(session: session)
        self.registry = registry
        self.memory = memory
    }

    func generateReview(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        contextText: String
    ) async throws -> MediaReviewDraft {
        guard let skill = registry.skill(id: SkillID.reviewMedia) else {
            throw VisionPracticeError.unregisteredSkill
        }
        guard let url = AITransport.completionsURL(from: baseURL) else {
            throw VisionPracticeError.invalidURL
        }
        let userText = skill.userPrompt ?? contextText
        let memoryBlock = await memory.block(skill: skill, query: contextText)
        let finalUserText = memoryBlock.isEmpty ? userText : userText + "\n\n" + memoryBlock
        let rawContent: String
        do {
            rawContent = try await transport.complete(
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
        } catch let error as VisionPracticeError {
            throw error
        } catch {
            throw VisionPracticeError.transport
        }
        guard !rawContent.isEmpty else {
            throw VisionPracticeError.invalidJSON
        }
        return try Self.parseDraft(from: rawContent)
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
