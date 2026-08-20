import Foundation

enum VisionPracticeError: Error, Equatable {
    case invalidURL
    case unauthorized
    case httpStatus(Int)
    case emptyContent
    case invalidJSON
    case timeout
    case transport
    case unregisteredSkill
}

typealias AIClientError = VisionPracticeError

protocol VisionGenerating: Sendable {
    func generateDraft(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        fallbackCategory: PracticeCategory
    ) async throws -> AIPracticeDraft
}

struct VisionPracticeClient: VisionGenerating {
    private let transport: AITransport
    private let registry: SkillRegistry

    init(session: URLSession = .shared, registry: SkillRegistry = .builtin) {
        self.transport = AITransport(session: session)
        self.registry = registry
    }

    static func completionsURL(from baseURL: String) -> URL? {
        AITransport.completionsURL(from: baseURL)
    }

    func generateDraft(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        fallbackCategory: PracticeCategory
    ) async throws -> AIPracticeDraft {
        guard let skill = registry.skill(id: SkillID.planFromImage) else {
            throw VisionPracticeError.unregisteredSkill
        }
        guard let url = AITransport.completionsURL(from: baseURL) else {
            throw VisionPracticeError.invalidURL
        }
        let userText = skill.userPrompt ?? ""
        let rawContent: String
        do {
            rawContent = try await transport.complete(
                url: url,
                apiKey: apiKey,
                model: model,
                systemPrompt: skill.systemPrompt,
                userText: userText,
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
            throw VisionPracticeError.emptyContent
        }
        return try Self.parseDraft(from: rawContent, fallbackCategory: fallbackCategory)
    }

    private static func parseDraft(
        from content: String,
        fallbackCategory: PracticeCategory
    ) throws -> AIPracticeDraft {
        let jsonText = AITransport.stripMarkdownFences(content)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw VisionPracticeError.invalidJSON
        }
        let raw: AIPracticeDraft.Raw
        do {
            raw = try JSONDecoder().decode(AIPracticeDraft.Raw.self, from: jsonData)
        } catch {
            throw VisionPracticeError.invalidJSON
        }
        return AIPracticeDraft.normalize(raw, fallbackCategory: fallbackCategory)
    }
}
