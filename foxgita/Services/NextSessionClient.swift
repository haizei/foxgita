import Foundation

protocol NextSessionGenerating: Sendable {
    func generateDraft(
        baseURL: String,
        model: String,
        apiKey: String,
        budgetMinutes: Int,
        fallbackCategory: PracticeCategory
    ) async throws -> AIPracticeDraft
}

struct NextSessionClient: NextSessionGenerating {
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

    static func clampBudget(_ minutes: Int) -> Int {
        min(60, max(5, minutes))
    }

    static func capRaw(_ raw: AIPracticeDraft.Raw, budget: Int) -> AIPracticeDraft.Raw {
        let budget = clampBudget(budget)
        var raw = raw
        let target = min(raw.targetMin ?? budget, budget)
        raw.targetMin = min(60, max(1, target))
        guard let minutes = raw.stepMinutes, let steps = raw.steps else { return raw }
        var pairs: [(String, Int)] = []
        for index in steps.indices {
            let text = steps[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = index < minutes.count ? minutes[index] : 0
            if !text.isEmpty && value >= 1 {
                pairs.append((text, value))
            }
        }
        var sum = pairs.reduce(0) { $0 + $1.1 }
        while sum > budget && !pairs.isEmpty {
            sum -= pairs.removeLast().1
        }
        raw.steps = pairs.map(\.0)
        raw.stepMinutes = pairs.map(\.1)
        return raw
    }

    func generateDraft(
        baseURL: String,
        model: String,
        apiKey: String,
        budgetMinutes: Int,
        fallbackCategory: PracticeCategory
    ) async throws -> AIPracticeDraft {
        guard let skill = registry.skill(id: SkillID.nextSession) else {
            throw VisionPracticeError.unregisteredSkill
        }
        guard let url = AITransport.completionsURL(from: baseURL) else {
            throw VisionPracticeError.invalidURL
        }
        let budget = Self.clampBudget(budgetMinutes)
        let userText = (skill.userPrompt ?? "").replacingOccurrences(of: "{{minutes}}", with: "\(budget)")
        let memoryBlock = await memory.block(skill: skill, query: "")
        let finalUserText = memoryBlock.isEmpty ? userText : userText + "\n\n" + memoryBlock
        let rawContent: String
        do {
            let result = try await transport.complete(
                url: url,
                apiKey: apiKey,
                model: model,
                systemPrompt: skill.systemPrompt,
                userText: finalUserText,
                imageJPEGData: [],
                includeResponseFormat: true,
                allowsFormatRetry: skill.allowsFormatRetry,
                timeout: skill.timeout
            )
            rawContent = result.content
        } catch let error as VisionPracticeError {
            throw error
        } catch {
            throw VisionPracticeError.transport
        }
        guard !rawContent.isEmpty else {
            throw VisionPracticeError.emptyContent
        }
        let jsonText = AITransport.stripMarkdownFences(rawContent)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw VisionPracticeError.invalidJSON
        }
        let raw: AIPracticeDraft.Raw
        do {
            raw = try JSONDecoder().decode(AIPracticeDraft.Raw.self, from: jsonData)
        } catch {
            throw VisionPracticeError.invalidJSON
        }
        return AIPracticeDraft.normalize(
            Self.capRaw(raw, budget: budget),
            fallbackCategory: fallbackCategory
        )
    }
}
