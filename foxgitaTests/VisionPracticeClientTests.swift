import Foundation
import Testing
@testable import foxgita

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    static var handler: (@Sendable (URLRequest) throws -> (Int, Data))? {
        get {
            lock.lock(); defer { lock.unlock() }
            return _handler
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _handler = newValue
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.handler
        guard let handler else {
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
struct VisionPracticeClientTests {
    private func makeClient() -> VisionPracticeClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return VisionPracticeClient(session: URLSession(configuration: config))
    }

    @Test func completionsURLJoinsAndRespectsFullPath() {
        #expect(
            VisionPracticeClient.completionsURL(from: "https://api.openai.com/v1/")?
                .absoluteString == "https://api.openai.com/v1/chat/completions"
        )
        #expect(
            VisionPracticeClient.completionsURL(
                from: "https://example.com/v1/chat/completions"
            )?.absoluteString == "https://example.com/v1/chat/completions"
        )
    }

    @Test func generateDraftSuccess() async throws {
        let payload: [String: Any] = [
            "choices": [[
                "message": [
                    "content": #"{"title":"开放弦","category":"left","targetMin":8,"steps":["拨弦","换弦"]}"#
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        MockURLProtocol.handler = { _ in (200, data) }
        defer { MockURLProtocol.handler = nil }

        let draft = try await makeClient().generateDraft(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk-test",
            imageJPEGData: [Data([0xFF, 0xD8, 0xFF])],
            fallbackCategory: .song
        )
        #expect(draft.title == "开放弦")
        #expect(draft.category == .left)
        #expect(draft.targetMin == 8)
        #expect(draft.steps == ["拨弦", "换弦"])
    }

    @Test func generateDraftUnauthorized() async {
        MockURLProtocol.handler = { _ in (401, Data(#"{"error":"no"}"#.utf8)) }
        defer { MockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.unauthorized) {
            try await makeClient().generateDraft(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "bad",
                imageJPEGData: [Data([0x01])],
                fallbackCategory: .left
            )
        }
    }

    @Test func generateDraftInvalidJSONContent() async {
        let payload: [String: Any] = [
            "choices": [["message": ["content": "not-json"]]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        MockURLProtocol.handler = { _ in (200, data) }
        defer { MockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.invalidJSON) {
            try await makeClient().generateDraft(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0x01])],
                fallbackCategory: .left
            )
        }
    }

    @Test func generateDraftRetriesWithoutResponseFormat() async throws {
        // Sync counter: MockURLProtocol.handler is not async.
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func hit() {
                lock.lock(); defer { lock.unlock() }
                n += 1
            }
            func count() -> Int {
                lock.lock(); defer { lock.unlock() }
                return n
            }
        }
        let counter = Counter()
        let ok: [String: Any] = [
            "choices": [[
                "message": [
                    "content": #"{"title":"节奏","category":"rhythm","targetMin":10,"steps":["拍手"]}"#
                ]
            ]]
        ]
        let okData = try JSONSerialization.data(withJSONObject: ok)
        MockURLProtocol.handler = { req in
            counter.hit()
            let body = Self.requestBodyString(req)
            if counter.count() == 1 {
                #expect(body.contains("response_format"))
                return (400, Data(#"{"error":"unknown response_format"}"#.utf8))
            }
            #expect(!body.contains("response_format"))
            return (200, okData)
        }
        defer { MockURLProtocol.handler = nil }

        let draft = try await makeClient().generateDraft(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk",
            imageJPEGData: [Data([0x01])],
            fallbackCategory: .left
        )
        #expect(draft.category == .rhythm)
        #expect(counter.count() == 2)
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

    @Test func generateDraftTimedOut() async {
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        defer { MockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.timeout) {
            try await makeClient().generateDraft(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0x01])],
                fallbackCategory: .left
            )
        }
    }

    @Test func generateDraftUnregisteredSkillSendsNoRequest() async {
        var calls = 0
        MockURLProtocol.handler = { _ in
            calls += 1
            return (200, Data())
        }
        defer { MockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = VisionPracticeClient(
            session: URLSession(configuration: config),
            registry: SkillRegistry(skills: [])
        )
        await #expect(throws: VisionPracticeError.unregisteredSkill) {
            try await client.generateDraft(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0x01])],
                fallbackCategory: .left
            )
        }
        #expect(calls == 0)
    }

    @Test func generateDraftUsesFrozenPlanSkillPrompt() async throws {
        let payload: [String: Any] = [
            "choices": [[
                "message": [
                    "content": #"{"title":"开放弦","category":"left","targetMin":8,"steps":["拨弦"]}"#
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var bodyJSON: [String: Any] = [:]
        MockURLProtocol.handler = { req in
            let text = Self.requestBodyString(req)
            bodyJSON = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
            return (200, data)
        }
        defer { MockURLProtocol.handler = nil }

        _ = try await makeClient().generateDraft(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk-test",
            imageJPEGData: [Data([0xFF, 0xD8, 0xFF])],
            fallbackCategory: .song
        )
        let messages = bodyJSON["messages"] as? [[String: Any]]
        #expect(messages?[0]["content"] as? String == SkillDefinition.planFromImage.systemPrompt)
        let user = messages?[1]["content"] as? [[String: Any]]
        #expect(user?[0]["text"] as? String == SkillDefinition.planFromImage.userPrompt)
        let imageURL = user?[1]["image_url"] as? [String: Any]
        let dataURI = imageURL?["url"] as? String ?? ""
        #expect(dataURI.hasPrefix("data:image/jpeg;base64,"))
    }
}
