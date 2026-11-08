import Foundation
import Testing
@testable import foxgita

@Suite(.serialized) @MainActor struct ScoreRecognitionClientTests {
    #if DEBUG
    @Test(arguments: ["invalid-draft", "resolution", "first-resolution"])
    func failedSystemRetriesWithoutResendingItsSuccessfulNeighbourOrChangingModelParameters(secondRowFailure: String) async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("https://score.example/v1", forKey: LLMSettingsKey.baseURL)
        defaults.set("unchanged-model", forKey: LLMSettingsKey.model)
        let credentials = LLMCredentialsStore(service: "score-system-tests.\(UUID())")
        try credentials.saveAPIKey("test-only")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScoreServiceMockProtocol.self]
        let session = URLSession(configuration: config), attempts = ScoreRecognitionAttempts()
        defer { credentials.clearAPIKey(); ScoreServiceMockProtocol.handler = nil; session.invalidateAndCancel() }
        ScoreServiceMockProtocol.handler = { request in
            #expect(request.timeoutInterval == 240)
            var bytes = request.httpBody ?? Data()
            if bytes.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; bytes.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            #expect(body["model"] as? String == "unchanged-model")
            for key in ["enable_thinking", "reasoning_effort", "thinking_budget", "temperature", "max_tokens", "stream"] { #expect(body[key] == nil) }
            let messages = try #require(body["messages"] as? [[String: Any]])
            #expect(messages.first?["content"] as? String == ScoreRecognitionPrompt.system)
            let content = try #require(messages.last?["content"] as? [[String: Any]])
            #expect(content.filter { $0["type"] as? String == "image_url" }.count == 2)
            let attempt = attempts.next()
            let valid = #"{"title":"Original","bars":[{"number":1,"events":[{"tick":0,"duration":960,"source":{"page":1,"box":[0,0,1,1]},"tones":[{"midi":55}]}]}]}"#
            let failure = secondRowFailure == "invalid-draft" ? #"{"bars":[]}"# : valid.replacingOccurrences(of: "\"title\"", with: "\"ticksPerQuarter\":480,\"title\"")
            let reply = attempt == (secondRowFailure == "first-resolution" ? 1 : 2) ? failure : valid
            return try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": reply]]]])
        }
        let client = ScoreRecognitionClient(session: session, defaults: defaults, serviceURL: nil, serviceToken: nil, credentialsStore: credentials)
        let id = UUID(), pages = [ScoreSystemImageSlicerTests.twoSystemPage()]
        do { _ = try await client.recognize(pages: pages, requestID: id); Issue.record("Second system must fail") }
        catch { #expect(error.localizedDescription.contains("第1页")) }
        let result = try await client.recognize(pages: pages, requestID: id)
        #expect(attempts.count == 3)
        #expect(result.score.bars.count == 2)
        #expect(result.score.bars.flatMap(\.events).map { $0.source?.page } == [1, 1])
        #expect((result.score.bars.last?.events.first?.source?.box?[1] ?? 0) > 0.4)
    }

    @Test func developmentRetryKeepsSuccessfulPagesAndRetriesOnlyTheFailedPage() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("https://score.example/v1", forKey: LLMSettingsKey.baseURL)
        defaults.set("test-model", forKey: LLMSettingsKey.model)
        let credentials = LLMCredentialsStore(service: "score-recognition-tests.\(UUID())")
        try credentials.saveAPIKey("test-only")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScoreServiceMockProtocol.self]
        let session = URLSession(configuration: config), attempts = ScoreRecognitionAttempts()
        defer { credentials.clearAPIKey(); ScoreServiceMockProtocol.handler = nil; session.invalidateAndCancel() }
        ScoreServiceMockProtocol.handler = { _ in
            let attempt = attempts.next()
            let content = attempt == 2 ? #"{"bars":[]}"#
                : #"{"title":"Original","bars":[{"number":1,"events":[{"tick":0,"duration":960,"tones":[{"midi":55}]}]}]}"#
            return try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        }
        let client = ScoreRecognitionClient(session: session, defaults: defaults, serviceURL: nil,
                                            serviceToken: nil, credentialsStore: credentials)
        let requestID = UUID(), pages = [Data([1]), Data([2])]
        do {
            _ = try await client.recognize(pages: pages, requestID: requestID)
            Issue.record("The second page must fail on the first attempt")
        } catch {
            #expect(error.localizedDescription.contains("第2页"))
            #expect(!error.localizedDescription.contains("第1页"))
        }
        let draft = try await client.recognize(pages: pages, requestID: requestID)
        #expect(attempts.count == 3)
        #expect(draft.score.bars.count == 2)
        #expect(draft.score.bars.map { $0.source?.page } == [1, 2])
    }

    @Test(arguments: ["timeout", "authorization", "rate-limit", "malformed", "private-error"])
    func developmentFailureShowsAnActionableSafeReason(kind: String) async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("https://score.example/v1", forKey: LLMSettingsKey.baseURL)
        defaults.set("test-model", forKey: LLMSettingsKey.model)
        let credentials = LLMCredentialsStore(service: "score-recognition-tests.\(UUID())")
        try credentials.saveAPIKey("test-only")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScoreProviderFailureProtocol.self]
        config.httpAdditionalHeaders = ["X-Test-Failure": kind]
        let session = URLSession(configuration: config)
        defer { credentials.clearAPIKey(); ScoreServiceMockProtocol.handler = nil; session.invalidateAndCancel() }
        let client = ScoreRecognitionClient(session: session, defaults: defaults, serviceURL: nil,
                                            serviceToken: nil, credentialsStore: credentials)
        var status = ""
        client.onProgress = { status = $0[1] ?? "" }
        do {
            _ = try await client.recognize(pages: [Data([1])])
            Issue.record("Failure must not produce a score")
        } catch {
            let message = error.localizedDescription
            let expected = switch kind {
            case "timeout": "超时"
            case "authorization": "授权"
            case "rate-limit": "频繁"
            case "malformed": "音乐数据"
            default: "连接"
            }
            #expect(message.contains(expected))
            #expect(status.contains(expected))
            #expect(message.contains("第1页"))
            #expect(!message.contains("PRIVATE-RESPONSE-SECRET"))
        }
    }

    @Test func developmentDiagnosticsExposeOnlyTypesNeverReplyValues() {
        let privateValue = "DO-NOT-EXPORT-REPLY-CONTENT"
        let payload = "{\"title\":\"\(privateValue)\",\"tempo\":{\"bpm\":80},\"bars\":[{\"events\":[{\"tick\":0,\"duration\":960,\"tones\":[{\"midi\":55,\"lyric\":\"\(privateValue)\"}]}]}]}"
        let shape = ScoreRecognitionClient.replyShape(payload)
        #expect(shape.contains("title:string"))
        #expect(shape.contains("midi:number"))
        #expect(!shape.contains(privateValue))
        #expect(!ScoreRecognitionClient.replyShape(privateValue).contains(privateValue))
    }
    #endif
    @Test func leavingTheViewStopsPollingAndOnlyExplicitCancellationDeletes() async throws {
        let jobID = UUID(), deletes = ScoreRecognitionAttempts()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScoreServiceMockProtocol.self]
        let session = URLSession(configuration: config)
        defer { ScoreServiceMockProtocol.handler = nil; session.invalidateAndCancel() }
        let destination = URL(string: "https://score.example")!
        let client = ScoreRecognitionClient(session: session, serviceURL: destination, serviceToken: "test-only")
        ScoreServiceMockProtocol.handler = { request in
            if request.httpMethod == "DELETE" {
                _ = deletes.next()
                #expect(request.url?.lastPathComponent == jobID.uuidString)
            }
            return try JSONSerialization.data(withJSONObject: ["id": jobID.uuidString, "status": "queued"])
        }
        var polled = false
        client.onProgress = { _ in polled = true }
        let observer = Task { try await client.recognize(pages: [Data([1])]) }
        for _ in 0..<100 where !polled { try await Task.sleep(for: .milliseconds(10)) }
        #expect(polled)
        observer.cancel()
        _ = await observer.result
        #expect(deletes.count == 0)
        await #expect(throws: ScoreRecognitionError.self) {
            try await client.cancelManagedJob(jobID, destination: URL(string: "https://different.example")!)
        }
        #expect(deletes.count == 0)
        try await client.cancelManagedJob(jobID, destination: destination)
        #expect(deletes.count == 1)
    }

    @Test func interruptionRestoresAcceptedJobWithoutResubmissionAndRetryKeepsKey() async throws {
        let profileID = UUID(), sourceID = UUID(), jobID = UUID()
        let pages = [Data([1])], destination = URL(string: "https://score.example")!
        let selection = ScoreImportSelection(id: sourceID, pages: pages, originals: pages, names: ["fixture"])
        let directory = ScoreSourceVault.directory(profileID: profileID, sourceID: sourceID)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try ScoreSourceVault.save(selection, profileID: profileID)
        var consent = ScoreSourceVault.RecognitionRequest(destination: destination, requestID: sourceID)
        try ScoreSourceVault.saveRequest(consent, profileID: profileID, sourceID: sourceID)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScoreServiceMockProtocol.self]
        let session = URLSession(configuration: config)
        defer { ScoreServiceMockProtocol.handler = nil; session.invalidateAndCancel() }
        let attempts = ScoreRecognitionAttempts()
        ScoreServiceMockProtocol.handler = { request in
            switch attempts.next() {
            case 1, 4:
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == sourceID.uuidString)
                return try JSONSerialization.data(withJSONObject: ["id": jobID.uuidString])
            case 2:
                #expect(request.httpMethod == "GET")
                throw URLError(.networkConnectionLost)
            case 3:
                #expect(request.httpMethod == "GET")
                #expect(request.url?.lastPathComponent == jobID.uuidString)
                return Data(#"{"status":"failed","pages":[{"page":1,"status":"failed"}]}"#.utf8)
            default:
                #expect(request.httpMethod == "GET")
                return Data(#"{"status":"succeeded","draft":{"title":"recovered","bars":[{"events":[{"tick":0,"duration":960,"tones":[{"midi":64}]}]}]}}"#.utf8)
            }
        }
        let client = ScoreRecognitionClient(session: session, serviceURL: destination, serviceToken: "test")
        do {
            _ = try await client.recognize(pages: pages, requestID: sourceID, onJobAccepted: { id in
                consent.jobID = id
                try ScoreSourceVault.saveRequest(consent, profileID: profileID, sourceID: sourceID)
            }, onRetryRequired: { Issue.record("A lost connection must preserve the accepted job") })
            Issue.record("Expected lost connection")
        } catch let error as URLError { #expect(error.code == .networkConnectionLost) }
        let restored = try #require(try ScoreSourceVault.recognitionRequest(profileID: profileID, sourceID: sourceID))
        #expect(restored == consent)
        #expect(restored.jobID == jobID)
        #expect(try ScoreSourceVault.recognitionRequest(profileID: UUID(), sourceID: sourceID) == nil)
        let reopened = ScoreRecognitionClient(session: session, serviceURL: destination, serviceToken: "test")
        var mayRetry = false
        do {
            _ = try await reopened.recognize(pages: pages, requestID: restored.requestID, existingJobID: restored.jobID,
                                             onRetryRequired: { mayRetry = true })
            Issue.record("Expected terminal failure")
        } catch ScoreRecognitionError.pages(let failed) { #expect(failed == [1]) }
        #expect(mayRetry)
        let draft = try await reopened.recognize(pages: pages, requestID: restored.requestID)
        #expect(draft.score.title == "recovered")
        #expect(attempts.count == 5)
    }

    @Test func lostSubmissionResponseReplaysPersistedConsentKeyAndOriginalPages() async throws {
        let profileID = UUID(), sourceID = UUID(), jobID = UUID()
        let destination = URL(string: "https://score.example")!
        let pages = [Data([1, 2, 3])]
        let selection = ScoreImportSelection(id: sourceID, pages: pages, originals: pages, names: ["fixture"])
        try ScoreSourceVault.save(selection, profileID: profileID)
        defer {
            let dir = ScoreSourceVault.directory(profileID: profileID, sourceID: sourceID)
            try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
        }
        try ScoreSourceVault.saveRequest(.init(destination: destination, requestID: sourceID), profileID: profileID, sourceID: sourceID)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScoreServiceMockProtocol.self]
        let session = URLSession(configuration: config)
        defer { ScoreServiceMockProtocol.handler = nil; session.invalidateAndCancel() }
        let attempts = ScoreRecognitionAttempts()
        ScoreServiceMockProtocol.handler = { request in
            switch attempts.next() {
            case 1:
                #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == sourceID.uuidString)
                throw URLError(.networkConnectionLost)
            case 2:
                #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == sourceID.uuidString)
                return try JSONSerialization.data(withJSONObject: ["id": jobID.uuidString])
            default:
                #expect(request.httpMethod == "GET")
                #expect(request.url?.lastPathComponent == jobID.uuidString)
                return Data(#"{"status":"succeeded","draft":{"title":"same job","bars":[{"events":[{"tick":0,"duration":960,"tones":[{"midi":64}]}]}]}}"#.utf8)
            }
        }
        let original = ScoreRecognitionClient(session: session, serviceURL: destination, serviceToken: "test")
        await #expect(throws: URLError.self) {
            try await original.recognize(pages: pages, requestID: sourceID)
        }
        let restored = try #require(try ScoreSourceVault.recognitionRequest(profileID: profileID, sourceID: sourceID))
        #expect(restored.jobID == nil)
        let restoredPages = try ScoreSourceVault.pages(profileID: profileID, sourceID: sourceID)
        #expect(restoredPages == pages)
        let reopened = ScoreRecognitionClient(session: session, serviceURL: destination, serviceToken: "test")
        let result = try await reopened.recognize(pages: restoredPages, requestID: restored.requestID, existingJobID: restored.jobID)
        #expect(result.score.title == "same job")
        #expect(attempts.count == 3)
    }

    @Test func managedServiceUploadsPagesThenPublishesOnlyTheReturnedDraft() async throws {
        let jobID = UUID(), requestID = UUID()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScoreServiceMockProtocol.self]
        let session = URLSession(configuration: config)
        ScoreServiceMockProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
            if request.httpMethod == "POST" {
                #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == requestID.uuidString)
                #expect(request.url?.path == "/v1/recognitions")
                return try JSONSerialization.data(withJSONObject: ["id":jobID.uuidString,"status":"queued"])
            }
            #expect(request.url?.lastPathComponent == jobID.uuidString)
            return try JSONSerialization.data(withJSONObject: ["id":jobID.uuidString,"status":"succeeded","draft":[
                "title":"服务返回曲谱","bars":[["number":1,"events":[["tick":0,"duration":960,"tones":[["midi":64]]]]]]
            ]])
        }
        defer { ScoreServiceMockProtocol.handler = nil; session.invalidateAndCancel() }
        let client = ScoreRecognitionClient(session: session,defaults: UserDefaults(suiteName: UUID().uuidString)!,serviceURL: URL(string: "https://score.example"),serviceToken: "test-only")
        let draft = try await client.recognize(pages: [Data([1,2,3])],requestID: requestID)
        #expect(draft.score.title == "服务返回曲谱")
        #expect(!draft.isConfirmed)
        #expect(draft.score.bars[0].events[0].tones[0].midi == 64)
    }
    @Test func unconfiguredManagedServiceDoesNotPretendRecognitionSucceeded() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let client = ScoreRecognitionClient(defaults: defaults,serviceURL: nil,serviceToken: nil)
        await #expect(throws: ScoreRecognitionError.self) { try await client.recognize(pages: [Data([1,2,3])]) }
    }
    @Test func insecureRemoteEndpointIsRejectedBeforeAnyPageOrCredentialIsSent() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let client = ScoreRecognitionClient(defaults: defaults,serviceURL: URL(string: "http://example.com"),serviceToken: "test-only")
        await #expect(throws: ScoreRecognitionError.self) { try await client.recognize(pages: [Data([1,2,3])]) }
    }
}

nonisolated private final class ScoreRecognitionAttempts: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}

nonisolated final class ScoreServiceMockProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: (@Sendable (URLRequest) throws -> Data)?
    static var handler: (@Sendable (URLRequest) throws -> Data)? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let data = try handler(request)
            client?.urlProtocol(self,didReceive: HTTPURLResponse(url: request.url!,statusCode: 200,httpVersion: nil,headerFields: nil)!,cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self,didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self,didFailWithError: error) }
    }
    override func stopLoading() {}
}

// No real requests or shared provider credentials are used by these fixtures.
nonisolated private final class ScoreProviderFailureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let kind = request.value(forHTTPHeaderField: "X-Test-Failure")
        if kind == "timeout" || kind == "private-error" {
            let error: Error = kind == "timeout" ? URLError(.timedOut) : NSError(domain: "PRIVATE-RESPONSE-SECRET", code: 17)
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let status = kind == "authorization" ? 401 : (kind == "rate-limit" ? 429 : 200)
        let data = status == 200
            ? Data(#"{"choices":[{"message":{"content":"{\"bars\":[]}"}}]}"#.utf8)
            : Data("PRIVATE-RESPONSE-SECRET".utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
