import Foundation

protocol VideoDiagnosing: Sendable {
    func generateDiagnosis(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        contextText: String,
        durationSec: Int
    ) async throws -> VideoDiagnosisDraft
}

struct VideoDiagnosisClient: VideoDiagnosing {
    static let requestTimeout: TimeInterval = 180

    private let transport: AITransport
    private let registry: SkillRegistry
    private let memory: any MemoryContextProviding

    init(
        session: URLSession = VideoDiagnosisClient.makeSession(),
        registry: SkillRegistry = .builtin,
        memory: any MemoryContextProviding = EmptyMemoryContext()
    ) {
        self.transport = AITransport(session: session)
        self.registry = registry
        self.memory = memory
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout
        return URLSession(configuration: config)
    }

    func generateDiagnosis(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        contextText: String,
        durationSec: Int
    ) async throws -> VideoDiagnosisDraft {
        guard let skill = registry.skill(id: SkillID.diagnoseVideo) else {
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
            let result = try await transport.complete(
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
            rawContent = result.content
        } catch let error as VisionPracticeError {
            throw error
        } catch {
            if (error as? URLError)?.code == .timedOut {
                throw VisionPracticeError.timeout
            }
            throw VisionPracticeError.transport
        }
        guard !rawContent.isEmpty else {
            throw VisionPracticeError.invalidJSON
        }
        return try Self.parseDraft(from: rawContent, durationSec: durationSec)
    }

    private static func parseDraft(from content: String, durationSec: Int) throws -> VideoDiagnosisDraft {
        let jsonText = AITransport.stripMarkdownFences(content)
        guard let jsonData = jsonText.data(using: .utf8),
              let raw = try? JSONDecoder().decode(VideoDiagnosisDraft.Raw.self, from: jsonData),
              let draft = try? VideoDiagnosisDraft.normalize(raw, durationSec: durationSec)
        else {
            throw VisionPracticeError.invalidJSON
        }
        return draft
    }
}
