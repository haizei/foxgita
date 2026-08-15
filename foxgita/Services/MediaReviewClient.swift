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
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateReview(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        contextText: String
    ) async throws -> MediaReviewDraft {
        guard let url = VisionPracticeClient.completionsURL(from: baseURL) else {
            throw VisionPracticeError.invalidURL
        }

        do {
            return try await perform(
                url: url,
                model: model,
                apiKey: apiKey,
                imageJPEGData: imageJPEGData,
                contextText: contextText,
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
        contextText: String,
        includeResponseFormat: Bool,
        allowFormatRetry: Bool
    ) async throws -> MediaReviewDraft {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.buildBody(
            model: model,
            imageJPEGData: imageJPEGData,
            contextText: contextText,
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
                    contextText: contextText,
                    includeResponseFormat: false,
                    allowFormatRetry: false
                )
            }
            throw VisionPracticeError.httpStatus(http.statusCode)
        }

        return try Self.parseDraft(from: data)
    }

    private static func buildBody(
        model: String,
        imageJPEGData: [Data],
        contextText: String,
        includeResponseFormat: Bool
    ) throws -> Data {
        var userContent: [[String: Any]] = [
            [
                "type": "text",
                "text": contextText,
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
                    "content": """
                    你是吉他练习陪伴教练。根据波形图或练习画面帧给出简短复盘。只返回 JSON，不要 markdown。
                    字段：highlight（亮点）、focus（优先改善）、nextAction（下次练法）。
                    每段一句话，不要编造时间戳（如 01:18），不要承诺精确音准鉴定。
                    """,
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

    private static func parseDraft(from data: Data) throws -> MediaReviewDraft {
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
            throw VisionPracticeError.invalidJSON
        }

        let jsonText = stripMarkdownFences(content)
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
