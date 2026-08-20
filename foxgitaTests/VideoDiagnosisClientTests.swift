import Foundation
import Testing
@testable import foxgita

final class DiagnosisMockURLProtocol: URLProtocol, @unchecked Sendable {
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
struct VideoDiagnosisClientTests {
    private func makeClient() -> VideoDiagnosisClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DiagnosisMockURLProtocol.self]
        return VideoDiagnosisClient(session: URLSession(configuration: config))
    }

    @Test func generateDiagnosisSuccess() async throws {
        let payload: [String: Any] = [
            "choices": [[
                "message": [
                    "content": #"{"highlight":"稳","focus":"F","nextAction":"慢练","findings":[{"startSec":12,"endSec":32,"title":"按弦","evidence":"杂音","cause":"离品丝","action":"靠近"}]}"#
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        DiagnosisMockURLProtocol.handler = { _ in (200, data) }
        defer { DiagnosisMockURLProtocol.handler = nil }

        let draft = try await makeClient().generateDiagnosis(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk-test",
            imageJPEGData: [Data([0xFF, 0xD8])],
            contextText: "任务：和弦转换\n时长：180秒\n媒介：录像",
            durationSec: 180
        )
        #expect(draft.focus == "F")
        #expect(draft.findings.count == 1)
        #expect(draft.findings[0].startSec == 12)
    }

    @Test func generateDiagnosisUnauthorized() async {
        DiagnosisMockURLProtocol.handler = { _ in (401, Data()) }
        defer { DiagnosisMockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.unauthorized) {
            try await makeClient().generateDiagnosis(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "bad",
                imageJPEGData: [Data([0xFF])],
                contextText: "x",
                durationSec: 10
            )
        }
    }

    @Test func generateDiagnosisInvalidJSON() async {
        let payload: [String: Any] = ["choices": [["message": ["content": "not-json"]]]]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        DiagnosisMockURLProtocol.handler = { _ in (200, data) }
        defer { DiagnosisMockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.invalidJSON) {
            try await makeClient().generateDiagnosis(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0xFF])],
                contextText: "x",
                durationSec: 10
            )
        }
    }

    @Test func generateDiagnosisRetriesWithoutResponseFormat() async throws {
        let ok: [String: Any] = [
            "choices": [[
                "message": [
                    "content": #"{"highlight":"稳","focus":"F","nextAction":"慢练","findings":[]}"#
                ]
            ]]
        ]
        let okData = try JSONSerialization.data(withJSONObject: ok)
        var calls = 0
        DiagnosisMockURLProtocol.handler = { request in
            calls += 1
            if calls == 1 {
                return (400, Data("unknown response_format".utf8))
            }
            return (200, okData)
        }
        defer { DiagnosisMockURLProtocol.handler = nil }

        let draft = try await makeClient().generateDiagnosis(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk",
            imageJPEGData: [Data([0xFF])],
            contextText: "x",
            durationSec: 10
        )
        #expect(draft.highlight == "稳")
        #expect(calls == 2)
    }

    @Test func generateDiagnosisTimedOut() async {
        DiagnosisMockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        defer { DiagnosisMockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.timeout) {
            try await makeClient().generateDiagnosis(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0xFF])],
                contextText: "x",
                durationSec: 10
            )
        }
    }

    @Test func generateDiagnosisSetsLongRequestTimeout() async throws {
        let payload: [String: Any] = [
            "choices": [[
                "message": [
                    "content": #"{"highlight":"稳","focus":"F","nextAction":"慢练","findings":[]}"#
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var seen: TimeInterval = 0
        DiagnosisMockURLProtocol.handler = { request in
            seen = request.timeoutInterval
            return (200, data)
        }
        defer { DiagnosisMockURLProtocol.handler = nil }

        _ = try await makeClient().generateDiagnosis(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk",
            imageJPEGData: [Data([0xFF])],
            contextText: "x",
            durationSec: 10
        )
        #expect(seen == VideoDiagnosisClient.requestTimeout)
        #expect(VideoDiagnosisClient.requestTimeout == 180)
    }

    @Test func generateDiagnosisUnregisteredSkillSendsNoRequest() async {
        var calls = 0
        DiagnosisMockURLProtocol.handler = { _ in
            calls += 1
            return (200, Data())
        }
        defer { DiagnosisMockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DiagnosisMockURLProtocol.self]
        let client = VideoDiagnosisClient(
            session: URLSession(configuration: config),
            registry: SkillRegistry(skills: [])
        )
        await #expect(throws: VisionPracticeError.unregisteredSkill) {
            try await client.generateDiagnosis(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0xFF])],
                contextText: "x",
                durationSec: 10
            )
        }
        #expect(calls == 0)
    }

    @Test func generateDiagnosisUsesFrozenSystemAndRuntimeContext() async throws {
        let payload: [String: Any] = [
            "choices": [[
                "message": [
                    "content": #"{"highlight":"稳","focus":"F","nextAction":"慢练","findings":[]}"#
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var bodyJSON: [String: Any] = [:]
        DiagnosisMockURLProtocol.handler = { req in
            let text = Self.requestBodyString(req)
            bodyJSON = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
            return (200, data)
        }
        defer { DiagnosisMockURLProtocol.handler = nil }

        _ = try await makeClient().generateDiagnosis(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk-test",
            imageJPEGData: [Data([0xFF, 0xD8])],
            contextText: "任务：和弦转换\n时长：180秒\n媒介：录像",
            durationSec: 180
        )
        let messages = bodyJSON["messages"] as? [[String: Any]]
        #expect(messages?[0]["content"] as? String == SkillDefinition.diagnoseVideo.systemPrompt)
        let user = messages?[1]["content"] as? [[String: Any]]
        #expect(user?[0]["text"] as? String == "任务：和弦转换\n时长：180秒\n媒介：录像")
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
