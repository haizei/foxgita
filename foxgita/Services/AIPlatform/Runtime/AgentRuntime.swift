import Foundation

struct RuntimeCredentials: Sendable {
    let baseURL: String
    let apiKey: String
    let model: String
}

struct RuntimeUsage: Equatable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheWriteTokens: Int
    let cacheReadTokens: Int

    static let zero = Self(
        inputTokens: 0,
        outputTokens: 0,
        cacheWriteTokens: 0,
        cacheReadTokens: 0
    )
}

enum AIRuntimeError: Error, Equatable, Sendable {
    case invalidURL
    case unauthorized
    case httpStatus(Int)
    case emptyContent
    case invalidResponse
    case timeout
    case transport
    case cancelled
}

struct RuntimeToolCall: Equatable, Sendable {
    let id: String
    let toolID: String
    let toolVersion: String
    let argumentsJSON: String
}

enum RuntimeEvent: Equatable, Sendable {
    case accepted
    case started
    case modelDelta(String)
    case artifactProduced(Data)
    case formatRepairUsed
    case completed(RuntimeUsage)
    case failed(AIRuntimeError)
    case cancelled
}

protocol AgentRuntime: Sendable {
    func execute(
        plan: AgentExecutionPlan,
        prompt: PromptAssembly,
        credentials: RuntimeCredentials
    ) -> AsyncThrowingStream<RuntimeEvent, Error>
}

struct MessagesTransportRequest: Sendable {
    let baseURL: String
    let apiKey: String
    let model: String
    let systemPrompt: String
    let userText: String
    let imageJPEGData: [Data]
    let orderedTools: [VersionedToolSchema]
    let includeResponseFormat: Bool
    let allowsFormatRetry: Bool
    let timeout: TimeInterval?
}

protocol MessagesTransporting: Sendable {
    func complete(_ request: MessagesTransportRequest) async throws -> AITransportResult
    func stream(
        _ request: MessagesTransportRequest,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> AITransportResult
}

extension MessagesTransporting {
    func stream(
        _ request: MessagesTransportRequest,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> AITransportResult {
        try await complete(request)
    }
}
