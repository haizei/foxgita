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
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateDiagnosis(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        contextText: String,
        durationSec: Int
    ) async throws -> VideoDiagnosisDraft {
        guard let url = VisionPracticeClient.completionsURL(from: baseURL) else {
            throw VisionPracticeError.invalidURL
        }
        do {
            return try await perform(
                url: url, model: model, apiKey: apiKey,
                imageJPEGData: imageJPEGData, contextText: contextText,
                durationSec: durationSec,
                includeResponseFormat: true, allowFormatRetry: true
            )
        } catch let error as VisionPracticeError {
            throw error
        } catch {
            throw VisionPracticeError.transport
        }
    }

    private func perform(
        url: URL, model: String, apiKey: String,
        imageJPEGData: [Data], contextText: String, durationSec: Int,
        includeResponseFormat: Bool, allowFormatRetry: Bool
    ) async throws -> VideoDiagnosisDraft {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.buildBody(
            model: model, imageJPEGData: imageJPEGData, contextText: contextText,
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
            if allowFormatRetry, includeResponseFormat,
               (400...499).contains(http.statusCode),
               bodyText.contains("response_format") || bodyText.contains("unknown") {
                return try await perform(
                    url: url, model: model, apiKey: apiKey,
                    imageJPEGData: imageJPEGData, contextText: contextText,
                    durationSec: durationSec,
                    includeResponseFormat: false, allowFormatRetry: false
                )
            }
            throw VisionPracticeError.httpStatus(http.statusCode)
        }
        return try Self.parseDraft(from: data, durationSec: durationSec)
    }

    private static func buildBody(
        model: String, imageJPEGData: [Data], contextText: String, includeResponseFormat: Bool
    ) throws -> Data {
        var userContent: [[String: Any]] = [["type": "text", "text": contextText]]
        for data in imageJPEGData {
            userContent.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"],
            ])
        }
        var body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    你是吉他练习诊断教练。根据练习录像关键帧和可选波形，给出可定位的分段诊断。只返回 JSON，不要 markdown。
                    字段：highlight、focus、nextAction（各一句话），findings（数组，可空）。
                    每条 finding 字段：startSec、endSec（整数秒，必须落在 0 到视频时长之间）、title、evidence、cause、action。
                    evidence 写看到或听到的具体现象。证据不足就少写或不写 finding，不要编造时间点，不要承诺精确音准鉴定。最多 5 条。
                    """,
                ],
                ["role": "user", "content": userContent],
            ],
        ]
        if includeResponseFormat {
            body["response_format"] = ["type": "json_object"]
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private static func parseDraft(from data: Data, durationSec: Int) throws -> VideoDiagnosisDraft {
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { var content: String? }
                var message: Message?
            }
            var choices: [Choice]?
        }
        let chat = (try? JSONDecoder().decode(ChatResponse.self, from: data))
        let content = chat?.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { throw VisionPracticeError.invalidJSON }
        var s = content
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if s.hasSuffix("```") { s.removeLast(3) }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let jsonData = s.data(using: .utf8),
              let raw = try? JSONDecoder().decode(VideoDiagnosisDraft.Raw.self, from: jsonData),
              let draft = try? VideoDiagnosisDraft.normalize(raw, durationSec: durationSec)
        else {
            throw VisionPracticeError.invalidJSON
        }
        return draft
    }
}
