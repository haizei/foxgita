import Foundation

enum VisionPracticeError: Error, Equatable {
    case invalidURL
    case unauthorized
    case httpStatus(Int)
    case emptyContent
    case invalidJSON
    case transport
}

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

    func generateDraft(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        fallbackCategory: PracticeCategory
    ) async throws -> AIPracticeDraft {
        guard let url = Self.completionsURL(from: baseURL) else {
            throw VisionPracticeError.invalidURL
        }

        do {
            return try await perform(
                url: url,
                model: model,
                apiKey: apiKey,
                imageJPEGData: imageJPEGData,
                fallbackCategory: fallbackCategory,
                includeResponseFormat: true,
                allowFormatRetry: true
            )
        } catch let error as VisionPracticeError {
            throw error
        } catch {
            throw VisionPracticeError.transport
        }
    }

    private func perform(
        url: URL,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        fallbackCategory: PracticeCategory,
        includeResponseFormat: Bool,
        allowFormatRetry: Bool
    ) async throws -> AIPracticeDraft {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.buildBody(
            model: model,
            imageJPEGData: imageJPEGData,
            includeResponseFormat: includeResponseFormat
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw VisionPracticeError.transport
        }

        guard let http = response as? HTTPURLResponse else {
            throw VisionPracticeError.transport
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw VisionPracticeError.unauthorized
        }

        if !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8)?.lowercased() ?? ""
            if allowFormatRetry,
               includeResponseFormat,
               (400...499).contains(http.statusCode),
               bodyText.contains("response_format") || bodyText.contains("unknown") {
                return try await perform(
                    url: url,
                    model: model,
                    apiKey: apiKey,
                    imageJPEGData: imageJPEGData,
                    fallbackCategory: fallbackCategory,
                    includeResponseFormat: false,
                    allowFormatRetry: false
                )
            }
            throw VisionPracticeError.httpStatus(http.statusCode)
        }

        return try Self.parseDraft(from: data, fallbackCategory: fallbackCategory)
    }

    private static func buildBody(
        model: String,
        imageJPEGData: [Data],
        includeResponseFormat: Bool
    ) throws -> Data {
        var userContent: [[String: Any]] = [
            [
                "type": "text",
                "text": """
                请根据图片总结成吉他练习任务。只返回 JSON 对象，不要 markdown，不要其它说明。
                字段：
                - title: 字符串
                - category: 仅能为 left/right/both/chord/scale/rhythm/song 之一
                - targetMin: 整数分钟
                - steps: 字符串数组（练习步骤）
                - chords: 可选，识别到的和弦名字符串数组（如 C、G、Am）
                - stepMinutes: 可选，与 steps 按下标对齐的整数分钟；没有则省略
                """,
            ]
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
                [
                    "role": "system",
                    "content": "你是吉他练习教练。只输出合法 JSON。",
                ],
                [
                    "role": "user",
                    "content": userContent,
                ],
            ],
        ]
        if includeResponseFormat {
            body["response_format"] = ["type": "json_object"]
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private static func parseDraft(
        from data: Data,
        fallbackCategory: PracticeCategory
    ) throws -> AIPracticeDraft {
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
        guard !content.isEmpty else {
            throw VisionPracticeError.emptyContent
        }

        let jsonText = stripMarkdownFences(content)
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

    private static func stripMarkdownFences(_ text: String) -> String {
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
}
