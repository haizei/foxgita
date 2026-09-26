import CryptoKit
import Foundation

struct AITransportResult: Equatable, Sendable {
    var content: String
    var formatRetryUsed: Bool
    var usage: RuntimeUsage
    var toolCalls: [RuntimeToolCall]

    init(
        content: String,
        formatRetryUsed: Bool,
        usage: RuntimeUsage = .zero,
        toolCalls: [RuntimeToolCall] = []
    ) {
        self.content = content
        self.formatRetryUsed = formatRetryUsed
        self.usage = usage
        self.toolCalls = toolCalls
    }
}

struct AITransport: Sendable {
    private let session: URLSession

    private struct ProviderToolCall: Decodable {
        struct Function: Decodable {
            let name: String?
            let arguments: String?
        }

        let id: String?
        let function: Function?
    }

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
        let toolNameMap: ProviderToolNameMap
        do {
            toolNameMap = try ProviderToolNameMap(schemas: orderedTools)
            request.httpBody = try Self.buildBody(
                model: model,
                systemPrompt: systemPrompt,
                userText: userText,
                imageJPEGData: imageJPEGData,
                providerTools: toolNameMap.entries,
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
                    usage: nested.usage,
                    toolCalls: nested.toolCalls
                )
            }
            throw VisionPracticeError.httpStatus(http.statusCode)
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    var content: String?
                    let toolCalls: [ProviderToolCall]?

                    enum CodingKeys: String, CodingKey {
                        case content
                        case toolCalls = "tool_calls"
                    }
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
        let toolCalls = try (chat.choices?.first?.message?.toolCalls ?? []).map {
            try toolNameMap.runtimeToolCall(from: $0)
        }
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
        return AITransportResult(
            content: content,
            formatRetryUsed: false,
            usage: usage,
            toolCalls: toolCalls
        )
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
                imageJPEGData: request.imageJPEGData,
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

    func stream(
        _ request: MessagesTransportRequest,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> AITransportResult {
        guard let url = Self.completionsURL(from: request.baseURL) else { throw AIRuntimeError.invalidURL }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = request.timeout ?? 60
        urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        do {
            let toolMap = try ProviderToolNameMap(schemas: request.orderedTools)
            let body = try Self.buildBody(
                model: request.model, systemPrompt: request.systemPrompt, userText: request.userText,
                imageJPEGData: request.imageJPEGData, providerTools: toolMap.entries,
                includeResponseFormat: request.includeResponseFormat
            )
            var json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            json["stream"] = true
            json["stream_options"] = ["include_usage": true]
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: json)
        } catch { throw AIRuntimeError.transport }

        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw AIRuntimeError.transport }
            if http.statusCode == 401 || http.statusCode == 403 { throw AIRuntimeError.unauthorized }
            guard (200...299).contains(http.statusCode) else { throw AIRuntimeError.httpStatus(http.statusCode) }

            var content = ""
            var usage = RuntimeUsage.zero
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard let data = payload.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                if let choices = object["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: Any],
                   let text = delta["content"] as? String, !text.isEmpty {
                    content += text
                    onDelta(text)
                }
                if let rawUsage = object["usage"] as? [String: Any] {
                    usage = RuntimeUsage(
                        inputTokens: rawUsage["prompt_tokens"] as? Int ?? rawUsage["input_tokens"] as? Int ?? 0,
                        outputTokens: rawUsage["completion_tokens"] as? Int ?? rawUsage["output_tokens"] as? Int ?? 0,
                        cacheWriteTokens: rawUsage["cache_creation_input_tokens"] as? Int ?? 0,
                        cacheReadTokens: rawUsage["cache_read_input_tokens"] as? Int ?? 0
                    )
                }
            }
            return AITransportResult(content: content, formatRetryUsed: false, usage: usage)
        } catch is CancellationError { throw AIRuntimeError.cancelled }
        catch let error as AIRuntimeError { throw error }
        catch let error as URLError where error.code == .timedOut { throw AIRuntimeError.timeout }
        catch { throw AIRuntimeError.transport }
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
        providerTools: [ProviderToolEntry],
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
        if !providerTools.isEmpty {
            body["tools"] = try providerTools.map(providerTool)
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private nonisolated static func providerTool(_ entry: ProviderToolEntry) throws -> [String: Any] {
        let parameters = try JSONSerialization.jsonObject(with: Data(entry.schema.json.utf8))
        guard parameters is [String: Any] else {
            throw VisionPracticeError.transport
        }
        return [
            "type": "function",
            "function": [
                "name": entry.providerName,
                "parameters": parameters,
            ],
        ]
    }

    private struct ProviderToolEntry: Sendable {
        let providerName: String
        let schema: VersionedToolSchema
    }

    private struct ProviderToolNameMap: Sendable {
        let entries: [ProviderToolEntry]
        private let schemasByProviderName: [String: VersionedToolSchema]

        init(schemas: [VersionedToolSchema]) throws {
            var entries: [ProviderToolEntry] = []
            var schemasByProviderName: [String: VersionedToolSchema] = [:]
            for schema in schemas {
                let providerName = Self.providerName(for: schema)
                guard schemasByProviderName[providerName] == nil else {
                    throw ProviderToolMappingError.nameCollision
                }
                entries.append(ProviderToolEntry(providerName: providerName, schema: schema))
                schemasByProviderName[providerName] = schema
            }
            self.entries = entries
            self.schemasByProviderName = schemasByProviderName
        }

        func runtimeToolCall(
            from call: ProviderToolCall
        ) throws -> RuntimeToolCall {
            guard let id = call.id,
                  let function = call.function,
                  let providerName = function.name,
                  let schema = schemasByProviderName[providerName] else {
                throw ProviderToolMappingError.unknownToolCall
            }
            return RuntimeToolCall(
                id: id,
                toolID: schema.id,
                toolVersion: schema.version,
                argumentsJSON: function.arguments ?? ""
            )
        }

        private static func providerName(for schema: VersionedToolSchema) -> String {
            let safeIdentity = safeFragment("\(schema.id)_v_\(schema.version)")
            let digest = SHA256.hash(
                data: Data(PromptFingerprint.frame([schema.id, schema.version]).utf8)
            )
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
            let suffix = "_\(digest)"
            let prefixLimit = 64 - suffix.count
            let prefix = String(("tool_\(safeIdentity)").prefix(prefixLimit))
            return prefix + suffix
        }

        private static func safeFragment(_ text: String) -> String {
            let result = text.unicodeScalars.map { scalar -> String in
                switch scalar.value {
                case 48...57, 65...90, 97...122, 45, 95:
                    return String(scalar)
                default:
                    return "_"
                }
            }
            .joined()
            return result.isEmpty ? "tool" : result
        }
    }

    private enum ProviderToolMappingError: Error {
        case nameCollision
        case unknownToolCall
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
