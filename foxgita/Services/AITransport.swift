import Foundation

struct AITransportResult: Equatable, Sendable {
    var content: String
    var formatRetryUsed: Bool
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
                    includeResponseFormat: false,
                    allowsFormatRetry: false,
                    timeout: timeout
                )
                return AITransportResult(content: nested.content, formatRetryUsed: true)
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
            var choices: [Choice]?
        }
        let chat: ChatResponse
        do {
            chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw VisionPracticeError.invalidJSON
        }
        let content = chat.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AITransportResult(content: content, formatRetryUsed: false)
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
        return try JSONSerialization.data(withJSONObject: body)
    }
}
