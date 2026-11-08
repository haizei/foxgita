import Foundation
import Testing
@testable import foxgita

private actor FocusLatencyLog: AIInvocationRecording {
    var latest: AIInvocationRecordInput?
    func record(_ input: AIInvocationRecordInput) async { latest = input }
}

/// A single sequential baseline/optimized comparison; ordinary test runs never send these requests.
@MainActor
struct NextFocusLatencyLiveTests {
    private nonisolated static var enabled: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["GITA_NEXT_FOCUS_LATENCY_TEST"] == "1"
            || env["TEST_RUNNER_GITA_NEXT_FOCUS_LATENCY_TEST"] == "1"
    }

    private struct Sample: Codable {
        var elapsedSeconds: Double
        var output: NextFocusOutput?
        var formatRetryUsed: Bool?
        var errorType: String?
    }

    private struct Report: Codable {
        var model: String
        var samplesPerConfiguration = 1
        var baselineRunsFirst = true
        var practice: String
        var bpm: Int
        var actualPracticeSeconds: Int
        var optimizedEnableThinking: Bool
        var optimizedMaxCompletionTokens: Int
        var baseline: Sample
        var optimized: Sample
        var speedup: Double?
        var reductionPercent: Double?
    }

    @Test(.enabled(if: enabled))
    func compareExistingDefaultsWithFastRecap() async throws {
        let defaults = UserDefaults.standard
        let base = defaults.string(forKey: LLMSettingsKey.baseURL) ?? ""
        let model = defaults.string(forKey: LLMSettingsKey.model) ?? ""
        let key = try #require(LLMCredentialsStore().loadAPIKey(), "A configured simulator Keychain is required.")
        let url = try #require(AITransport.completionsURL(from: base))
        try #require(url.scheme == "https" && url.user == nil && url.password == nil)
        let options = NextFocusClient.completionOptions(for: model)
        try #require(options.enableThinking == false && options.maxCompletionTokens == 1024,
                     "This comparison requires a supported Qwen3.8 hybrid model.")
        let context = NextFocusContext(profileID: UUID(), sourceID: UUID(), sourceDay: "2026-11-07",
            title: "C to G chord transition", categoryRaw: "chord", steps: ["新步骤"],
            durationSeconds: 2, bpm: 80)

        var start = ProcessInfo.processInfo.systemUptime
        let baseline: Sample
        do {
            let result = try await AITransport().complete(url: url, apiKey: key, model: model,
                systemPrompt: NextFocusClient.systemPrompt,
                userText: NextFocusClient.userText(context: context, supplement: ""), imageJPEGData: [],
                includeResponseFormat: true, allowsFormatRetry: true, timeout: 60)
            baseline = Sample(elapsedSeconds: ProcessInfo.processInfo.systemUptime - start,
                output: try NextFocusOutput.parse(result.content), formatRetryUsed: result.formatRetryUsed)
        } catch {
            baseline = Sample(elapsedSeconds: ProcessInfo.processInfo.systemUptime - start,
                              errorType: AIInvocationStore.errorType(from: error).rawValue)
        }

        let log = FocusLatencyLog()
        start = ProcessInfo.processInfo.systemUptime
        let optimized: Sample
        do {
            let output = try await NextFocusClient(log: log).generate(context: context, supplement: "",
                baseURL: base, model: model, apiKey: key)
            optimized = Sample(elapsedSeconds: ProcessInfo.processInfo.systemUptime - start,
                               output: output, formatRetryUsed: await log.latest?.formatRetryUsed)
        } catch {
            optimized = Sample(elapsedSeconds: ProcessInfo.processInfo.systemUptime - start,
                               errorType: AIInvocationStore.errorType(from: error).rawValue)
        }
        let comparable = baseline.output != nil && optimized.output != nil && optimized.elapsedSeconds > 0
        let report = Report(model: model, practice: context.title, bpm: 80, actualPracticeSeconds: 2,
            optimizedEnableThinking: false, optimizedMaxCompletionTokens: 1024,
            baseline: baseline, optimized: optimized,
            speedup: comparable ? baseline.elapsedSeconds / optimized.elapsedSeconds : nil,
            reductionPercent: comparable ? (1 - optimized.elapsedSeconds / baseline.elapsedSeconds) * 100 : nil)
        let directory = URL.documentsDirectory.appendingPathComponent("NextFocusLatencyValidation", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: directory.appendingPathComponent("comparison.json"), options: .atomic)
        #expect(optimized.output != nil, "The optimized response must parse successfully; see the sanitized report.")
        #expect(optimized.output?.focus.isEmpty == false)
    }
}
