import Foundation
import Testing
@testable import foxgita

final class ReviewMockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    static var handler: (@Sendable (URLRequest) throws -> (Int, Data))? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); defer { lock.unlock() }; _handler = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct MediaReviewClientTests {
    private struct StubMemoryContext: MemoryContextProviding {
        var text: String
        func block(skill: SkillDefinition, query: String) async -> String { text }
    }
    private func makeClient() -> MediaReviewClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReviewMockURLProtocol.self]
        return MediaReviewClient(session: URLSession(configuration: config))
    }

    @Test func generateReviewSuccess() async throws {
        let payload: [String: Any] = [
            "choices": [[
                "message": [
                    "content": #"{"highlight":"稳","focus":"F 慢","nextAction":"70 BPM"}"#
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        ReviewMockURLProtocol.handler = { _ in (200, data) }
        defer { ReviewMockURLProtocol.handler = nil }

        let draft = try await makeClient().generateReview(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk-test",
            imageJPEGData: [Data([0xFF, 0xD8])],
            contextText: "任务：和弦转换"
        )
        #expect(draft.highlight == "稳")
        #expect(draft.focus == "F 慢")
        #expect(draft.nextAction == "70 BPM")
    }

    @Test func generateReviewUnauthorized() async {
        ReviewMockURLProtocol.handler = { _ in (401, Data()) }
        defer { ReviewMockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.unauthorized) {
            try await makeClient().generateReview(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "bad",
                imageJPEGData: [Data([0xFF])],
                contextText: "x"
            )
        }
    }

    @Test func generateReviewInvalidJSON() async {
        let payload: [String: Any] = ["choices": [["message": ["content": "not-json"]]]]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        ReviewMockURLProtocol.handler = { _ in (200, data) }
        defer { ReviewMockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.invalidJSON) {
            try await makeClient().generateReview(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0xFF])],
                contextText: "x"
            )
        }
    }

    @Test func generateReviewRetriesWithoutResponseFormat() async throws {
        let ok: [String: Any] = [
            "choices": [[
                "message": ["content": #"{"highlight":"a","focus":"b","nextAction":"c"}"#]
            ]]
        ]
        let okData = try JSONSerialization.data(withJSONObject: ok)
        var calls = 0
        ReviewMockURLProtocol.handler = { request in
            calls += 1
            if calls == 1 {
                return (400, Data("unknown response_format".utf8))
            }
            return (200, okData)
        }
        defer { ReviewMockURLProtocol.handler = nil }

        let draft = try await makeClient().generateReview(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk",
            imageJPEGData: [Data([0xFF])],
            contextText: "x"
        )
        #expect(draft.highlight == "a")
        #expect(calls == 2)
    }

    @Test func generateReviewTimedOut() async {
        ReviewMockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        defer { ReviewMockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.timeout) {
            try await makeClient().generateReview(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0xFF])],
                contextText: "x"
            )
        }
    }

    @Test func generateReviewUnregisteredSkillSendsNoRequest() async {
        var calls = 0
        ReviewMockURLProtocol.handler = { _ in
            calls += 1
            return (200, Data())
        }
        defer { ReviewMockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReviewMockURLProtocol.self]
        let client = MediaReviewClient(
            session: URLSession(configuration: config),
            registry: SkillRegistry(skills: [])
        )
        await #expect(throws: VisionPracticeError.unregisteredSkill) {
            try await client.generateReview(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0xFF])],
                contextText: "任务：和弦转换"
            )
        }
        #expect(calls == 0)
    }

    @Test func generateReviewUsesFrozenSystemAndRuntimeContext() async throws {
        let payload: [String: Any] = [
            "choices": [[
                "message": ["content": #"{"highlight":"稳","focus":"F 慢","nextAction":"70 BPM"}"#]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var bodyJSON: [String: Any] = [:]
        ReviewMockURLProtocol.handler = { req in
            let text = Self.requestBodyString(req)
            bodyJSON = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
            return (200, data)
        }
        defer { ReviewMockURLProtocol.handler = nil }

        _ = try await makeClient().generateReview(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk-test",
            imageJPEGData: [Data([0xFF, 0xD8])],
            contextText: "任务：和弦转换"
        )
        let messages = bodyJSON["messages"] as? [[String: Any]]
        #expect(messages?[0]["content"] as? String == SkillDefinition.reviewMedia.systemPrompt)
        let user = messages?[1]["content"] as? [[String: Any]]
        #expect(user?[0]["text"] as? String == "任务：和弦转换")
    }

    @Test func generateReviewAppendsMemoryBlock() async throws {
        let payload: [String: Any] = [
            "choices": [["message": ["content": #"{"highlight":"稳","focus":"节奏","nextAction":"慢练"}"#]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var bodyJSON: [String: Any] = [:]
        ReviewMockURLProtocol.handler = { req in
            let text = Self.requestBodyString(req)
            bodyJSON = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
            return (200, data)
        }
        defer { ReviewMockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReviewMockURLProtocol.self]
        let client = MediaReviewClient(
            session: URLSession(configuration: config),
            memory: StubMemoryContext(text: "<<<BACKGROUND_MEMORY>>>\n- [ability] F 和弦按弦清晰度仍需改善\n<<<END_BACKGROUND_MEMORY>>>")
        )
        _ = try await client.generateReview(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk",
            imageJPEGData: [Data([0xFF])],
            contextText: "任务：晴天"
        )
        let messages = bodyJSON["messages"] as? [[String: Any]]
        #expect(messages?[0]["content"] as? String == SkillDefinition.reviewMedia.systemPrompt)
        let user = messages?[1]["content"] as? [[String: Any]]
        let userText = user?[0]["text"] as? String ?? ""
        #expect(userText.contains("任务：晴天"))
        #expect(userText.contains("[ability]"))
    }

    private static func requestBodyString(_ request: URLRequest) -> String {
        if let data = request.httpBody {
            return String(data: data, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
