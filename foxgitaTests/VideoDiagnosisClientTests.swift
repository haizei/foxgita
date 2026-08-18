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
}
