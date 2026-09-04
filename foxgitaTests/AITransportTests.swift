import Foundation
import Testing
@testable import foxgita

final class TransportMockURLProtocol: URLProtocol, @unchecked Sendable {
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
struct AITransportTests {
    private func makeTransport() -> AITransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransportMockURLProtocol.self]
        return AITransport(session: URLSession(configuration: config))
    }

    @Test func completionsURLJoinsAndRespectsFullPath() {
        #expect(
            AITransport.completionsURL(from: "https://api.openai.com/v1/")?
                .absoluteString == "https://api.openai.com/v1/chat/completions"
        )
        #expect(
            AITransport.completionsURL(
                from: "https://example.com/v1/chat/completions"
            )?.absoluteString == "https://example.com/v1/chat/completions"
        )
        #expect(AITransport.completionsURL(from: "   ") == nil)
    }

    @Test func stripMarkdownFencesRemovesJsonFence() {
        let raw = "```json\n{\"a\":1}\n```"
        #expect(AITransport.stripMarkdownFences(raw) == "{\"a\":1}")
    }

    @Test func completeReturnsTrimmedContentWithoutStrippingFence() async throws {
        let payload: [String: Any] = [
            "choices": [["message": ["content": "```json\n{\"ok\":true}\n```"]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        TransportMockURLProtocol.handler = { _ in (200, data) }
        defer { TransportMockURLProtocol.handler = nil }

        let url = AITransport.completionsURL(from: "https://api.openai.com/v1")!
        let result = try await makeTransport().complete(
            url: url, apiKey: "sk", model: "gpt-4o",
            systemPrompt: "sys", userText: "user",
            imageJPEGData: [Data([0xFF])],
            includeResponseFormat: true, allowsFormatRetry: true, timeout: nil
        )
        #expect(result.content == "```json\n{\"ok\":true}\n```")
        #expect(result.formatRetryUsed == false)
    }

    @Test func completeUnauthorized() async {
        TransportMockURLProtocol.handler = { _ in (401, Data()) }
        defer { TransportMockURLProtocol.handler = nil }
        let url = AITransport.completionsURL(from: "https://api.openai.com/v1")!
        await #expect(throws: VisionPracticeError.unauthorized) {
            try await makeTransport().complete(
                url: url, apiKey: "bad", model: "m",
                systemPrompt: "s", userText: "u",
                imageJPEGData: [],
                includeResponseFormat: true, allowsFormatRetry: true, timeout: nil
            )
        }
    }

    @Test func completeInvalidChatJSON() async {
        TransportMockURLProtocol.handler = { _ in (200, Data("not-json".utf8)) }
        defer { TransportMockURLProtocol.handler = nil }
        let url = AITransport.completionsURL(from: "https://api.openai.com/v1")!
        await #expect(throws: VisionPracticeError.invalidJSON) {
            try await makeTransport().complete(
                url: url, apiKey: "sk", model: "m",
                systemPrompt: "s", userText: "u",
                imageJPEGData: [],
                includeResponseFormat: true, allowsFormatRetry: true, timeout: nil
            )
        }
    }

    @Test func completeTimedOut() async {
        TransportMockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        defer { TransportMockURLProtocol.handler = nil }
        let url = AITransport.completionsURL(from: "https://api.openai.com/v1")!
        await #expect(throws: VisionPracticeError.timeout) {
            try await makeTransport().complete(
                url: url, apiKey: "sk", model: "m",
                systemPrompt: "s", userText: "u",
                imageJPEGData: [],
                includeResponseFormat: true, allowsFormatRetry: true, timeout: 180
            )
        }
    }

    @Test func completeRetriesOnceWithoutResponseFormat() async throws {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func hit() { lock.lock(); n += 1; lock.unlock() }
            func count() -> Int { lock.lock(); defer { lock.unlock() }; return n }
        }
        let counter = Counter()
        let ok = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": " {\"x\":1} "]]]
        ])
        TransportMockURLProtocol.handler = { req in
            counter.hit()
            let body = Self.requestBodyString(req)
            if counter.count() == 1 {
                #expect(body.contains("response_format"))
                return (400, Data(#"{"error":"unknown response_format"}"#.utf8))
            }
            #expect(!body.contains("response_format"))
            return (200, ok)
        }
        defer { TransportMockURLProtocol.handler = nil }

        let url = AITransport.completionsURL(from: "https://api.openai.com/v1")!
        let result = try await makeTransport().complete(
            url: url, apiKey: "sk", model: "m",
            systemPrompt: "s", userText: "u",
            imageJPEGData: [],
            includeResponseFormat: true, allowsFormatRetry: true, timeout: nil
        )
        #expect(result.content == "{\"x\":1}")
        #expect(result.formatRetryUsed == true)
        #expect(counter.count() == 2)
    }

    @Test func completeDoesNotRetryTwice() async {
        TransportMockURLProtocol.handler = { _ in
            (400, Data("unknown response_format".utf8))
        }
        defer { TransportMockURLProtocol.handler = nil }
        let url = AITransport.completionsURL(from: "https://api.openai.com/v1")!
        await #expect(throws: VisionPracticeError.httpStatus(400)) {
            try await makeTransport().complete(
                url: url, apiKey: "sk", model: "m",
                systemPrompt: "s", userText: "u",
                imageJPEGData: [],
                includeResponseFormat: true, allowsFormatRetry: true, timeout: nil
            )
        }
    }

    @Test func completeAppliesTimeoutAndSnapshotShape() async throws {
        let ok = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": "{}"]]]
        ])
        var seenTimeout: TimeInterval = 0
        var bodyJSON: [String: Any] = [:]
        TransportMockURLProtocol.handler = { req in
            seenTimeout = req.timeoutInterval
            let text = Self.requestBodyString(req)
            bodyJSON = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
            return (200, ok)
        }
        defer { TransportMockURLProtocol.handler = nil }

        let url = AITransport.completionsURL(from: "https://api.openai.com/v1")!
        let result = try await makeTransport().complete(
            url: url, apiKey: "sk-test", model: "gpt-4o",
            systemPrompt: "sys-role", userText: "user-role",
            imageJPEGData: [Data([0xFF, 0xD8])],
            includeResponseFormat: true, allowsFormatRetry: true, timeout: 180
        )
        #expect(result.formatRetryUsed == false)
        #expect(seenTimeout == 180)
        #expect(bodyJSON["model"] as? String == "gpt-4o")
        let messages = bodyJSON["messages"] as? [[String: Any]]
        #expect(messages?[0]["role"] as? String == "system")
        #expect(messages?[0]["content"] as? String == "sys-role")
        #expect(messages?[1]["role"] as? String == "user")
        let rf = bodyJSON["response_format"] as? [String: Any]
        #expect(rf?["type"] as? String == "json_object")
        #expect(bodyJSON["Authorization"] == nil)
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
