import Foundation

struct AITransportResult: Equatable, Sendable {
    var content: String
    var formatRetryUsed: Bool
    var usage: RuntimeUsage

    init(content: String, formatRetryUsed: Bool, usage: RuntimeUsage = .zero) {
        self.content = content
        self.formatRetryUsed = formatRetryUsed
        self.usage = usage
    }
}

struct AITransport: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func completionsURL(from baseURL: String) -> URL? {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }
        return URL(string: trimmed + "/chat/completions")
    }

    static func stripMarkdownFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if s.hasSuffix("```") {
                s.removeLast(3)
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.lowercased().hasPrefix("json") {
                // already stripped language tag via first newline path usually
            }
        }
        return s
    }

    func complete(
        url: URL,
        apiKey: String,
        model: String,
        systemPrompt: String,
        userText: String,
        imageJPEGData: [Data],
        includeResponseFormat: Bool,
        allowsFormatRetry: Bool,
        timeout: TimeInterval?
    ) async throws -> AITransportResult {
        try await complete(
            url: url,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            userText: userText,
            imageJPEGData: imageJPEGData,
            orderedTools: [],
            includeResponseFormat: includeResponseFormat,
            allowsFormatRetry: allowsFormatRetry,
            timeout: timeout
        )
    }

    private func complete(
        url: URL,
        apiKey: String,
        model: String,
        systemPrompt: String,
        userText: String,
        imageJPEGData: [Data],
        orderedTools: [VersionedToolSchema],
        includeResponseFormat: Bool,
        allowsFormatRetry: Bool,
        timeout: TimeInterval?
    ) async throws -> AITransportResult {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let timeout {
            request.timeoutInterval = timeout
        }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try Self.buildBody(
                model: model,
                systemPrompt: systemPrompt,
                userText: userText,
                imageJPEGData: imageJPEGData,
                orderedTools: orderedTools,
                includeResponseFormat: includeResponseFormat
            )
        } catch {
            throw VisionPracticeError.transport
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            try Self.mapSessionError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw VisionPracticeError.transport
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw VisionPracticeError.unauthorized
        }
        if !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8)?.lowercased() ?? ""
            if allowsFormatRetry,
               includeResponseFormat,
               (400...499).contains(http.statusCode),
               bodyText.contains("response_format") || bodyText.contains("unknown") {
                let nested = try await complete(
                    url: url,
                    apiKey: apiKey,
                    model: model,
                    systemPrompt: systemPrompt,
                    userText: userText,
                    imageJPEGData: imageJPEGData,
                    orderedTools: orderedTools,
                    includeResponseFormat: false,
                    allowsFormatRetry: false,
                    timeout: timeout
                )
                return AITransportResult(
                    content: nested.content,
                    formatRetryUsed: true,
                    usage: nested.usage
                )
            }
            throw VisionPracticeError.httpStatus(http.statusCode)
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    var content: String?
                }
                var message: Message?
            }
            struct Usage: Decodable {
                struct PromptTokenDetails: Decodable {
                    let cacheCreationInputTokens: Int?
                    let cachedTokens: Int?

                    enum CodingKeys: String, CodingKey {
                        case cacheCreationInputTokens = "cache_creation_input_tokens"
                        case cachedTokens = "cached_tokens"
                    }
                }

                let promptTokens: Int?
                let completionTokens: Int?
                let inputTokens: Int?
                let outputTokens: Int?
                let cacheCreationInputTokens: Int?
                let cacheReadInputTokens: Int?
                let promptTokenDetails: PromptTokenDetails?

                enum CodingKeys: String, CodingKey {
                    case promptTokens = "prompt_tokens"
                    case completionTokens = "completion_tokens"
                    case inputTokens = "input_tokens"
                    case outputTokens = "output_tokens"
                    case cacheCreationInputTokens = "cache_creation_input_tokens"
                    case cacheReadInputTokens = "cache_read_input_tokens"
                    case promptTokenDetails = "prompt_tokens_details"
                }
            }
            var choices: [Choice]?
            let usage: Usage?
        }
        let chat: ChatResponse
        do {
            chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw VisionPracticeError.invalidJSON
        }
        let content = chat.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let providerUsage = chat.usage
        let usage = RuntimeUsage(
            inputTokens: providerUsage?.promptTokens ?? providerUsage?.inputTokens ?? 0,
            outputTokens: providerUsage?.completionTokens ?? providerUsage?.outputTokens ?? 0,
            cacheWriteTokens: providerUsage?.promptTokenDetails?.cacheCreationInputTokens
                ?? providerUsage?.cacheCreationInputTokens
                ?? 0,
            cacheReadTokens: providerUsage?.promptTokenDetails?.cachedTokens
                ?? providerUsage?.cacheReadInputTokens
                ?? 0
        )
        return AITransportResult(content: content, formatRetryUsed: false, usage: usage)
    }

    func complete(_ request: MessagesTransportRequest) async throws -> AITransportResult {
        guard let url = Self.completionsURL(from: request.baseURL) else {
            throw AIRuntimeError.invalidURL
        }
        do {
            return try await complete(
                url: url,
                apiKey: request.apiKey,
                model: request.model,
                systemPrompt: request.systemPrompt,
                userText: request.userText,
                imageJPEGData: [],
                orderedTools: request.orderedTools,
                includeResponseFormat: request.includeResponseFormat,
                allowsFormatRetry: request.allowsFormatRetry,
                timeout: request.timeout
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.runtimeError(from: error)
        }
    }

    private static func mapSessionError(_ error: Error) throws -> Never {
        if (error as? URLError)?.code == .timedOut { throw VisionPracticeError.timeout }
        if (error as? URLError)?.code == .cancelled { throw CancellationError() }
        throw VisionPracticeError.transport
    }

    private static func buildBody(
        model: String,
        systemPrompt: String,
        userText: String,
        imageJPEGData: [Data],
        orderedTools: [VersionedToolSchema],
        includeResponseFormat: Bool
    ) throws -> Data {
        var userContent: [[String: Any]] = [
            ["type": "text", "text": userText]
        ]
        for data in imageJPEGData {
            userContent.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(data.base64EncodedString())"
                ],
            ])
        }
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent],
            ],
        ]
        if includeResponseFormat {
            body["response_format"] = ["type": "json_object"]
        }
        if !orderedTools.isEmpty {
            body["tools"] = try orderedTools.map(providerTool)
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private nonisolated static func providerTool(_ schema: VersionedToolSchema) throws -> [String: Any] {
        let parameters = try JSONSerialization.jsonObject(with: Data(schema.json.utf8))
        guard parameters is [String: Any] else {
            throw VisionPracticeError.transport
        }
        return [
            "type": "function",
            "function": [
                "name": schema.id,
                "parameters": parameters,
            ],
        ]
    }

    private static func runtimeError(from error: Error) -> AIRuntimeError {
        if let runtimeError = error as? AIRuntimeError {
            return runtimeError
        }
        if let legacyError = error as? VisionPracticeError {
            switch legacyError {
            case .invalidURL:
                return .invalidURL
            case .unauthorized:
                return .unauthorized
            case .httpStatus(let status):
                return .httpStatus(status)
            case .emptyContent:
                return .emptyContent
            case .invalidJSON:
                return .invalidResponse
            case .timeout:
                return .timeout
            case .transport, .unregisteredSkill:
                return .transport
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return .cancelled
            case .timedOut:
                return .timeout
            default:
                return .transport
            }
        }
        return .transport
    }
}

extension AITransport: MessagesTransporting {}
