import Foundation
import Testing
@testable import foxgita

private actor FullRecordInvocationLog: AIInvocationRecording {
    var latest: AIInvocationRecordInput?
    func record(_ input: AIInvocationRecordInput) async { latest = input }
}

/// One real request with complete synthetic evidence; ordinary tests skip it.
@MainActor
struct NextFocusFullRecordLiveTests {
    private nonisolated static var enabled: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["GITA_NEXT_FOCUS_FULL_RECORD_TEST"] == "1"
            || env["TEST_RUNNER_GITA_NEXT_FOCUS_FULL_RECORD_TEST"] == "1"
    }

    private struct Evidence: Decodable, Encodable {
        var practice: String
        var steps: [String]
        var note: String
        var projectFocus: String
        var existingBPM: Int?
        var observations: [String]
        var userNextIntention: String
    }

    private struct Report: Codable {
        var model: String
        var samples = 1
        var input: Evidence
        var enableThinking: Bool?
        var maxCompletionTokens: Int?
        var elapsedSeconds: Double
        var output: NextFocusOutput?
        var formatRetryUsed: Bool?
        var errorType: String?
    }

    @Test(.enabled(if: enabled))
    func summarizeNotesAndPrioritizeTheExplicitNextIntention() async throws {
        let defaults = UserDefaults.standard
        let base = defaults.string(forKey: LLMSettingsKey.baseURL) ?? ""
        let model = defaults.string(forKey: LLMSettingsKey.model) ?? ""
        let key = try #require(LLMCredentialsStore().loadAPIKey(), "Use the configured simulator's Keychain.")
        let url = try #require(AITransport.completionsURL(from: base))
        try #require(url.scheme == "https" && url.user == nil && url.password == nil)
        let options = NextFocusClient.completionOptions(for: model)
        try #require(options.enableThinking == false && options.maxCompletionTokens == 1024)

        let context = NextFocusContext(profileID: UUID(), sourceID: UUID(), sourceDay: "2026-11-07",
            title: "《晴天》分段练习", categoryRaw: "chord",
            steps: ["前奏第1–2小节", "前奏第3–4小节", "主歌第5–8小节"],
            note: "今天只练了前奏第1–4小节。在80 BPM下，第3小节换和弦时仍会停一下；我感觉第1–2小节比上次顺。主歌第5–8小节还没练。",
            durationSeconds: 1080, projectID: UUID(), projectName: "晴天",
            projectFocus: "先把前奏第1–4小节练连贯，沿用80 BPM，关注第3小节换和弦时的节拍。", bpm: 80)
        let intention = "下次先练主歌第5–8小节，沿用80 BPM，重点关注换和弦衔接；前奏暂时不练。"
        let input = try JSONDecoder().decode(Evidence.self, from: Data(
            NextFocusClient.userText(context: context, supplement: intention).utf8))
        let log = FullRecordInvocationLog()
        let start = ProcessInfo.processInfo.systemUptime
        var report = Report(model: model, input: input, enableThinking: options.enableThinking,
            maxCompletionTokens: options.maxCompletionTokens, elapsedSeconds: 0)
        do {
            report.output = try await NextFocusClient(log: log).generate(context: context, supplement: intention,
                baseURL: base, model: model, apiKey: key)
        } catch {
            report.errorType = AIInvocationStore.errorType(from: error).rawValue
        }
        report.elapsedSeconds = ProcessInfo.processInfo.systemUptime - start
        report.formatRetryUsed = await log.latest?.formatRetryUsed

        let directory = URL.documentsDirectory.appendingPathComponent("NextFocusFullRecordValidation", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: directory.appendingPathComponent("result.json"), options: .atomic)
        let output = try #require(report.output, "See the sanitized report for a failed live request.")
        #expect(!output.recap.isEmpty)
        #expect(output.focus.contains("主歌"), "The current explicit arrangement should take priority over the project's intro focus.")
        #expect(output.focus.contains("80"), "The suggestion should preserve the user's explicit tempo.")
    }
}
