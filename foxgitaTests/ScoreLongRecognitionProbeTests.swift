import CryptoKit
import Foundation
import Testing
import UIKit
@testable import foxgita

/// One explicitly authorized first-system request. No normal test run uploads.
@Suite(.serialized) @MainActor struct ScoreLongRecognitionProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_SIMULATOR_MODEL_CONFIGURATION_TEST"] == "1"))
    func simulatorProviderConfiguration() throws {
        #if targetEnvironment(simulator) && DEBUG
        let defaults = UserDefaults.standard
        let endpoint = AITransport.completionsURL(from: defaults.string(forKey: LLMSettingsKey.baseURL) ?? "")
        let flags = [
            "expectedModelConfigured": defaults.string(forKey: LLMSettingsKey.model) == "qwen3.8-max",
            "secureEndpointConfigured": endpoint?.scheme == "https" && endpoint?.host != nil && endpoint?.user == nil && endpoint?.password == nil,
            "credentialPresent": !(LLMCredentialsStore().loadAPIKey() ?? "").isEmpty
        ]
        let directory = URL.documentsDirectory.appendingPathComponent("ScoreDeviceValidation", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: flags, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("simulator-configuration-report.json"), options: .atomic)
        print("[GitaSimulatorConfig] model=\(flags["expectedModelConfigured"] == true) endpoint=\(flags["secureEndpointConfigured"] == true) credential=\(flags["credentialPresent"] == true)")
        #endif
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_USER_SYSTEM_LONG_TIMEOUT_TEST"] == "1"))
    func firstSystemWithTenMinuteTimeout() async throws {
        try await runProbe(reasoningEffort: nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_USER_SYSTEM_LOW_THINKING_TEST"] == "1"))
    func firstSystemWithLowThinking() async throws {
        try await runProbe(reasoningEffort: "low")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_USER_SYSTEM_MEDIUM_THINKING_TEST"] == "1"))
    func firstSystemWithMediumThinking() async throws {
        try await runProbe(reasoningEffort: "medium")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_USER_SYSTEM_FLASH_TEST"] == "1"))
    func firstSystemWithFlashMediumThinking() async throws {
        #if targetEnvironment(simulator)
        try await runProbe(reasoningEffort: "medium", modelOverride: "qwen3.8-flash")
        #endif
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GITA_SIMULATOR_SCORE_PATH"] != nil))
    func simulatorInputPreflightWithoutUploading() throws {
        #if targetEnvironment(simulator)
        let path = try #require(ProcessInfo.processInfo.environment["GITA_SIMULATOR_SCORE_PATH"])
        _ = try Self.authorizedSlices(input: Data(contentsOf: URL(fileURLWithPath: path)))
        #endif
    }

    private static func authorizedSlices(input: Data) throws -> [ScoreSystemSlice] {
        try #require(hash(input) == "ca0ead8498808af74e51c7f3fd38831fc38282807839b4bd2600abc71e67f3e2", "Use exactly the authorized baseline score image.")
        let page = try #require(ScoreImportSelection.images([input]).pages.first)
        let slices = ScoreSystemImageSlicer.slices(page: page, number: 1)
        try #require(slices.count == 5)
        let slice = try #require(slices.first)
        #if targetEnvironment(simulator)
        // iOS 26.5 Simulator JPEG encoding differs from iOS 26.1 on the phone.
        // These hashes come from the separately inspected local fixture preview.
        let expectedHashes = [
            "bef5124ce925401df8a0e8aefe578edfabc118d324d5d07d30f807c5461ae6c1",
            "b8b973da0836aac09354f25f1107ae66db7e3017598e4523f72fa92ab9e2c67f"
        ]
        #else
        let expectedHashes = [
            "a40aaa0e2a23c675c1fcabdf2bf43c2d28ee2d042ff79e44b14f4d55a9134e27",
            "21aee327e36d2871d2d6fe5649dcd69213dc6e7627c3266212d951690d6c0c36"
        ]
        #endif
        try #require(slice.images.map(hash) == expectedHashes, "Both images must match the verified fixture for this runtime.")
        return slices
    }

    @Test(arguments: ["low", "medium"])
    func thinkingChangesOnlyOneBodyParameter(effort: String) throws {
        let baseline = try Self.probeBody(model: "test-model", userText: "same-score", images: [Data([1, 2])], reasoningEffort: nil)
        let low = try Self.probeBody(model: "test-model", userText: "same-score", images: [Data([1, 2])], reasoningEffort: effort)
        let original = try #require(JSONSerialization.jsonObject(with: baseline) as? [String: Any])
        var changed = try #require(JSONSerialization.jsonObject(with: low) as? [String: Any])
        #expect(changed.removeValue(forKey: "reasoning_effort") as? String == effort)
        #expect((changed as NSDictionary).isEqual(to: original))
        #expect(original["reasoning_effort"] == nil)
        #expect(changed["thinking_budget"] == nil)
    }

    @Test func flashChangesOnlyModelFromMediumBaseline() throws {
        let baseline = try Self.probeBody(model: "qwen3.8-max", userText: "same-score", images: [Data([1, 2])], reasoningEffort: "medium")
        let flash = try Self.probeBody(model: "qwen3.8-flash", userText: "same-score", images: [Data([1, 2])], reasoningEffort: "medium")
        var original = try #require(JSONSerialization.jsonObject(with: baseline) as? [String: Any])
        var changed = try #require(JSONSerialization.jsonObject(with: flash) as? [String: Any])
        #expect(original.removeValue(forKey: "model") as? String == "qwen3.8-max")
        #expect(changed.removeValue(forKey: "model") as? String == "qwen3.8-flash")
        #expect((changed as NSDictionary).isEqual(to: original))
    }

    private static func probeBody(model: String, userText: String, images: [Data], reasoningEffort: String?) throws -> Data {
        let baseline = try AITransport.buildBody(model: model, systemPrompt: ScoreRecognitionPrompt.system,
            userText: userText, imageJPEGData: images, includeResponseFormat: true)
        guard let reasoningEffort else { return baseline }
        var body = try #require(JSONSerialization.jsonObject(with: baseline) as? [String: Any])
        body["reasoning_effort"] = reasoningEffort
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func runProbe(reasoningEffort: String?, modelOverride: String? = nil) async throws {
        #if DEBUG
        let directory = URL.documentsDirectory.appendingPathComponent("ScoreDeviceValidation", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if targetEnvironment(simulator)
        let path = try #require(ProcessInfo.processInfo.environment["GITA_SIMULATOR_SCORE_PATH"], "The simulator requires the explicitly supplied score input path.")
        let input = try Data(contentsOf: URL(fileURLWithPath: path))
        #else
        let input = try Data(contentsOf: directory.appendingPathComponent("user-supplied-page.jpg"))
        #endif
        let slices = try Self.authorizedSlices(input: input)
        let slice = try #require(slices.first)
        let defaults = UserDefaults.standard
        let configuredModel = defaults.string(forKey: LLMSettingsKey.model) ?? ""
        try #require(configuredModel == "qwen3.8-max", "Keep the saved baseline configuration unchanged.")
        try #require(modelOverride == nil || (modelOverride == "qwen3.8-flash" && reasoningEffort == "medium"))
        let model = modelOverride ?? configuredModel
        let base = defaults.string(forKey: LLMSettingsKey.baseURL) ?? ""
        let url = try #require(AITransport.completionsURL(from: base))
        try #require(url.scheme == "https" && url.user == nil && url.password == nil)
        let key = try #require(LLMCredentialsStore().loadAPIKey())
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 600
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.probeBody(model: model,
            userText: ScoreRecognitionClient.systemUserText(for: slice, total: slices.count), images: slice.images,
            reasoningEffort: reasoningEffort)
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        try #require(body["reasoning_effort"] as? String == reasoningEffort)
        for parameter in ["enable_thinking", "thinking_budget", "temperature", "max_tokens", "stream"] {
            try #require(body[parameter] == nil)
        }
        let idle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = idle }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForResource = 600
        let timing = LongProbeNetworkTiming()
        let session = URLSession(configuration: configuration, delegate: timing, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var report = LongProbeReport(model: model, inputSHA256: Self.hash(input),
            imageSHA256: slice.images.map(Self.hash), requestBodyBytes: request.httpBody!.count,
            requestBodySHA256: Self.hash(request.httpBody!))
        report.reasoningEffort = reasoningEffort
        #if targetEnvironment(simulator)
        report.runtimeSurface = "simulator"
        #else
        report.runtimeSurface = "physical-device"
        #endif
        report.systemVersion = UIDevice.current.systemVersion
        report.systemRegion = slice.region
        let filePrefix: String
        switch (model, reasoningEffort) {
        case ("qwen3.8-flash", "medium"): filePrefix = "user-system-flash-medium"
        case (_, "low"): filePrefix = "user-system-low"
        case (_, "medium"): filePrefix = "user-system-medium"
        default: filePrefix = "user-system-long"
        }
        let reportURL = directory.appendingPathComponent("\(filePrefix)-report.json")
        func writeReport() throws {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: reportURL, options: .atomic)
        }
        try writeReport()
        let start = ContinuousClock.now
        print("[GitaLongProbe] started model=\(model) reasoning=\(reasoningEffort ?? "default") system=1/5 timeout=600 images=\(slice.images.count) bytes=\(report.requestBodyBytes)")
        do {
            let (data, response) = try await session.data(for: request)
            report.responseBytes = data.count
            report.httpStatus = (response as? HTTPURLResponse)?.statusCode
            report.status = "response-received"
            if report.httpStatus == 200 {
                let envelope = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                if let usage = envelope["usage"] as? [String: Any] {
                    for field in ["prompt_tokens", "completion_tokens", "total_tokens"] {
                        if let count = usage[field] as? Int { report.tokens[field] = count }
                    }
                    if let details = usage["completion_tokens_details"] as? [String: Any], let count = details["reasoning_tokens"] as? Int {
                        report.tokens["reasoning_tokens"] = count
                    }
                }
                let choice = try #require((envelope["choices"] as? [[String: Any]])?.first)
                // Store only standard finish categories, never arbitrary server text.
                if let finish = choice["finish_reason"] as? String, ["stop", "length", "content_filter", "tool_calls"].contains(finish) { report.finishReason = finish }
                let message = try #require(choice["message"] as? [String: Any])
                report.reasoningCharacters = (message["reasoning_content"] as? String)?.count ?? 0
                let content = AITransport.stripMarkdownFences(message["content"] as? String ?? "")
                report.contentCharacters = content.count
                report.replyShape = ScoreRecognitionClient.replyShape(content)
                try Data(content.utf8).write(to: directory.appendingPathComponent("\(filePrefix)-response.json"), options: .atomic)
                let draft = try ScoreRecognitionDecoder.decode(Data(content.utf8))
                report.schemaValid = draft.score.ticksPerQuarter == 960
                report.ticksPerQuarter = draft.score.ticksPerQuarter
                report.status = report.schemaValid ? "decoded" : "schema-invalid"; report.bars = draft.score.bars.count
                report.events = draft.score.bars.flatMap(\.events).count
                report.musicValid = report.schemaValid && (try? draft.score.validate()) != nil
                report.issues = draft.issues.map(\.message)
                // Verified only for this hash-locked first-system fixture. Other
                // scores must supply their own independently verified expectations.
                let completeness = ScoreRecognitionCompleteness.issues(for: draft.score, expectedBars: 5, expectedQuarterBeats: 20)
                report.completenessIssues = completeness.map(\.message)
                report.completenessPassed = completeness.isEmpty
                report.automatedChecksPassed = report.musicValid && completeness.isEmpty
                try JSONEncoder().encode(draft).write(to: directory.appendingPathComponent("\(filePrefix)-draft.json"), options: .atomic)
            } else { report.error = "http-status"; report.status = "failed" }
        } catch {
            report.status = "failed"
            if let error = error as? URLError { report.error = "url-error:\(error.code.rawValue)" }
            else if let error = error as? ScoreRecognitionError { report.error = String(describing: error) }
            else { report.error = "response-or-report-error" }
        }
        report.seconds = Self.seconds(start.duration(to: .now))
        // Metrics delivery can follow completion briefly; never launch another task.
        for _ in 0..<50 where timing.snapshot().transactions.isEmpty {
            // Cancellation ends only the optional metrics grace period; persist
            // the final failed/cancelled request report in all cases.
            do { try await Task.sleep(for: .milliseconds(10)) } catch { break }
        }
        report.network = timing.snapshot()
        try writeReport()
        print("[GitaLongProbe] status=\(report.status) seconds=\(report.seconds) http=\(report.httpStatus ?? 0) bars=\(report.bars) error=\(report.error ?? "none")")
        #expect(report.status == "decoded", "The ten-minute probe did not produce a decoded draft. See its own report.")
        if report.status == "decoded" {
            #expect(report.completenessPassed == true, "The verified source has five bars and twenty quarter-note beats.")
            #expect(report.musicValid, "Decoded music violates pitch/fret/timing constraints.")
        }
        #endif
    }

    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func seconds(_ duration: Duration) -> Double { Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18 }
}

nonisolated private struct LongProbeTransaction: Codable, Sendable {
    var dnsSeconds: Double?
    var connectSeconds: Double?
    var tlsSeconds: Double?
    var uploadSeconds: Double?
    var waitSeconds: Double?
    var firstResponseSeconds: Double?
    var httpStatus: Int?
    var requestBodyBytes: Int64
    var responseBodyBytes: Int64
}
nonisolated private struct LongProbeNetworkSnapshot: Codable, Sendable {
    var uploadCompletedSeconds: Double? = nil
    var uploadedBytes: Int64 = 0
    var transactions: [LongProbeTransaction] = []
}
nonisolated private final class LongProbeNetworkTiming: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let started = Date()
    private let lock = NSLock()
    private var state = LongProbeNetworkSnapshot()
    func snapshot() -> LongProbeNetworkSnapshot { lock.lock(); defer { lock.unlock() }; return state }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        lock.lock()
        state.uploadedBytes = totalBytesSent
        let completed = totalBytesExpectedToSend > 0 && totalBytesSent >= totalBytesExpectedToSend && state.uploadCompletedSeconds == nil
        if completed { state.uploadCompletedSeconds = Date().timeIntervalSince(started) }
        let seconds = state.uploadCompletedSeconds
        lock.unlock()
        if completed { print("[GitaLongProbe] upload-complete seconds=\(seconds ?? 0) bytes=\(totalBytesSent)") }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        func interval(_ start: Date?, _ end: Date?) -> Double? {
            guard let start, let end else { return nil }; return end.timeIntervalSince(start)
        }
        let transactions = metrics.transactionMetrics.map { metric in
            LongProbeTransaction(dnsSeconds: interval(metric.domainLookupStartDate, metric.domainLookupEndDate),
                connectSeconds: interval(metric.connectStartDate, metric.connectEndDate),
                tlsSeconds: interval(metric.secureConnectionStartDate, metric.secureConnectionEndDate),
                uploadSeconds: interval(metric.requestStartDate, metric.requestEndDate),
                waitSeconds: interval(metric.requestEndDate, metric.responseStartDate),
                firstResponseSeconds: metric.responseStartDate.map { $0.timeIntervalSince(started) },
                httpStatus: (metric.response as? HTTPURLResponse)?.statusCode,
                requestBodyBytes: metric.countOfRequestBodyBytesSent,
                responseBodyBytes: metric.countOfResponseBodyBytesReceived)
        }
        lock.lock(); state.transactions = transactions; lock.unlock()
    }
}
private struct LongProbeReport: Codable {
    var generatedAt = Date()
    var model: String
    var inputSHA256: String
    var imageSHA256: [String]
    var requestBodyBytes: Int
    var requestBodySHA256: String
    var timeoutSeconds = 600
    var reasoningEffort: String? = nil
    var runtimeSurface: String? = nil
    var systemVersion: String? = nil
    var systemRegion: ScoreSystemRegion? = nil
    var system = 1
    var status = "running"
    var seconds = 0.0
    var network = LongProbeNetworkSnapshot()
    var httpStatus: Int? = nil
    var responseBytes = 0
    var tokens: [String: Int] = [:]
    var finishReason: String? = nil
    var contentCharacters = 0
    var reasoningCharacters = 0
    var replyShape: String? = nil
    var bars = 0
    var events = 0
    var musicValid = false
    var schemaValid = false
    var ticksPerQuarter: Int? = nil
    var issues: [String] = []
    var expectedBars = 5
    var expectedQuarterBeats = 20
    var completenessPassed: Bool? = nil
    var completenessIssues: [String] = []
    var automatedChecksPassed = false
    var error: String? = nil
}
