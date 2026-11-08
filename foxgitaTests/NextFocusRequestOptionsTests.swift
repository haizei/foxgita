import Foundation
import Testing
@testable import foxgita

private final class FocusOptionsURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

@Suite(.serialized) @MainActor
struct NextFocusRequestOptionsTests {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FocusOptionsURLProtocol.self]
        return URLSession(configuration: config)
    }

    private nonisolated static func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: 1024)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func response() throws -> Data {
        let content = #"{"recap":"已保存 C 到 G 和弦练习","focus":"继续 C 到 G 和弦切换","basis":"依据练习对象"}"#
        return try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
    }

    @Test func qwenRecapUsesBoundedNonThinkingRequest() async throws {
        let result = try response()
        FocusOptionsURLProtocol.handler = { request in
            let body = try Self.body(request)
            #expect(body["enable_thinking"] as? Bool == false)
            #expect(body["max_completion_tokens"] as? Int == 1024)
            #expect(body["reasoning_effort"] == nil)
            #expect(body["model"] as? String == "qwen3.8-max")
            return (200, result)
        }
        defer { FocusOptionsURLProtocol.handler = nil }
        let context = NextFocusContext(profileID: UUID(), sourceID: UUID(), sourceDay: "2026-11-07",
                                       title: "C to G chord transition", categoryRaw: "chord")
        let output = try await NextFocusClient(session: session()).generate(context: context, supplement: "",
            baseURL: "https://example.invalid/v1", model: "qwen3.8-max", apiKey: "test")
        #expect(!output.focus.isEmpty)
    }

    @Test func defaultTransportDoesNotAddRecapOptions() async throws {
        let result = try response()
        FocusOptionsURLProtocol.handler = { request in
            let body = try Self.body(request)
            #expect(body["enable_thinking"] == nil)
            #expect(body["max_completion_tokens"] == nil)
            return (200, result)
        }
        defer { FocusOptionsURLProtocol.handler = nil }
        _ = try await AITransport(session: session()).complete(url: URL(string: "https://example.invalid/v1")!,
            apiKey: "test", model: "qwen3.8-max", systemPrompt: "JSON", userText: "test", imageJPEGData: [],
            includeResponseFormat: true, allowsFormatRetry: true, timeout: 60)
    }

    @Test func formatFallbackRetainsNonThinkingAndOutputLimit() async throws {
        let result = try response()
        FocusOptionsURLProtocol.handler = { request in
            let body = try Self.body(request)
            #expect(body["enable_thinking"] as? Bool == false)
            #expect(body["max_completion_tokens"] as? Int == 1024)
            if body["response_format"] != nil { return (400, Data("unsupported response_format".utf8)) }
            return (200, result)
        }
        defer { FocusOptionsURLProtocol.handler = nil }
        let options = NextFocusClient.completionOptions(for: "qwen3.8-max")
        let output = try await AITransport(session: session()).complete(url: URL(string: "https://example.invalid/v1")!,
            apiKey: "test", model: "qwen3.8-max", systemPrompt: "JSON", userText: "test", imageJPEGData: [],
            includeResponseFormat: true, allowsFormatRetry: true, timeout: 60, options: options)
        #expect(output.formatRetryUsed)
    }

    @Test func unknownModelsKeepTheirExistingRequestContract() {
        let other = NextFocusClient.completionOptions(for: "another-provider-model")
        #expect(other.enableThinking == nil)
        #expect(other.maxCompletionTokens == nil)
        #expect(NextFocusClient.completionOptions(for: "qwen3.8-max-0902").enableThinking == false)
        #expect(NextFocusClient.completionOptions(for: "qwen3.8-flash").enableThinking == false)
        #expect(NextFocusClient.completionOptions(for: "qwen3.8-2.4t-a95b").enableThinking == nil)
    }

    @Test func recapModelPolicyOnlySubstitutesUnpinnedMax() {
        #expect(NextFocusClient.preferredModel(for: "qwen3.8-max") == "qwen3.8-flash")
        #expect(NextFocusClient.preferredModel(for: "qwen3.8-flash") == "qwen3.8-flash")
        #expect(NextFocusClient.preferredModel(for: "qwen3.8-max-0902") == "qwen3.8-max-0902")
        #expect(NextFocusClient.preferredModel(for: "another-provider-model") == "another-provider-model")
    }
}
