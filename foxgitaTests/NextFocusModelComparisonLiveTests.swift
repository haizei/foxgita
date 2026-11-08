import Foundation
import Testing
@testable import foxgita

private actor ModelComparisonLog: AIInvocationRecording {
    var latest: AIInvocationRecordInput?
    func record(_ input: AIInvocationRecordInput) async { latest = input }
}

/// Explicit opt-in, twelve requests: two rounds of two models for three synthetic records.
@MainActor struct NextFocusModelComparisonLiveTests {
    private nonisolated static var enabled: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["GITA_NEXT_FOCUS_MODEL_COMPARISON"] == "1"
            || env["TEST_RUNNER_GITA_NEXT_FOCUS_MODEL_COMPARISON"] == "1"
    }

    @Test(.enabled(if: enabled))
    func compareMaxAndFlashOnSimpleAndCompleteRecords() async throws {
        let defaults = UserDefaults.standard
        let base = defaults.string(forKey: LLMSettingsKey.baseURL) ?? ""
        let configured = defaults.string(forKey: LLMSettingsKey.model) ?? ""
        try #require(configured == "qwen3.8-max", "This probe compares the configured Max baseline to Flash.")
        let key = try #require(LLMCredentialsStore().loadAPIKey())
        let endpoint = try #require(AITransport.completionsURL(from: base))
        try #require(endpoint.scheme == "https" && endpoint.user == nil && endpoint.password == nil)
        let simple = NextFocusContext(profileID: UUID(), sourceID: UUID(), sourceDay: "2026-11-07",
            title: "C to G chord transition", categoryRaw: "chord", steps: ["新步骤"], durationSeconds: 2, bpm: 80)
        let complete = NextFocusContext(profileID: UUID(), sourceID: UUID(), sourceDay: "2026-11-07",
            title: "《晴天》分段练习", categoryRaw: "chord",
            steps: ["前奏第1–2小节", "前奏第3–4小节", "主歌第5–8小节"],
            note: "今天只练了前奏第1–4小节。在80 BPM下，第3小节换和弦时仍会停一下；我感觉第1–2小节比上次顺。主歌第5–8小节还没练。",
            durationSeconds: 1080, projectID: UUID(), projectName: "晴天",
            projectFocus: "先把前奏第1–4小节练连贯，沿用80 BPM，关注第3小节换和弦时的节拍。", bpm: 80)
        let intention = "下次先练主歌第5–8小节，沿用80 BPM，重点关注换和弦衔接；前奏暂时不练。"
        let ambiguous = NextFocusContext(profileID: UUID(), sourceID: UUID(), sourceDay: "2026-11-07",
            title: "练习", categoryRaw: "chord", durationSeconds: 2)
        let cases = [("simple", simple, "", ["qwen3.8-max", "qwen3.8-flash"]),
                     ("complete", complete, intention, ["qwen3.8-flash", "qwen3.8-max"]),
                     ("ambiguous", ambiguous, "", ["qwen3.8-max", "qwen3.8-flash"])]
        var samples: [[String: Any]] = []
        for round in 1...2 {
          for (name, context, supplement, models) in cases {
            let inputData = Data(try NextFocusClient.userText(context: context, supplement: supplement).utf8)
            for model in round == 1 ? models : Array(models.reversed()) {
                let log = ModelComparisonLog()
                let start = ProcessInfo.processInfo.systemUptime
                var sample: [String: Any] = ["case": name, "round": round, "model": model,
                    "input": try JSONSerialization.jsonObject(with: inputData),
                    "enableThinking": false, "maxCompletionTokens": 1024]
                do {
                    let output = try await NextFocusClient(log: log).generate(context: context, supplement: supplement,
                        baseURL: base, model: model, apiKey: key)
                    sample["elapsedSeconds"] = ProcessInfo.processInfo.systemUptime - start
                    sample["output"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(output))
                    if name == "simple" {
                        sample["contractPassed"] = !output.focus.isEmpty && !output.recap.contains("2秒") && !output.recap.contains("2 秒")
                    } else if name == "complete" {
                        let rangeForms = ["5–8", "5-8", "5至8", "5到8", "5—8", "5～8"]
                        sample["contractPassed"] = output.focus.contains("主歌")
                            && rangeForms.contains(where: output.focus.contains) && output.focus.contains("80")
                    } else {
                        sample["contractPassed"] = output.focus.isEmpty
                    }
                } catch {
                    sample["elapsedSeconds"] = ProcessInfo.processInfo.systemUptime - start
                    sample["errorType"] = AIInvocationStore.errorType(from: error).rawValue
                }
                sample["formatRetryUsed"] = await log.latest?.formatRetryUsed
                samples.append(sample)
            }
          }
        }
        let directory = URL.documentsDirectory.appendingPathComponent("NextFocusModelComparison", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let report: [String: Any] = ["samplesPerModelPerRecord": 2, "samples": samples]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("comparison.json"), options: .atomic)
        #expect(samples.allSatisfy { $0["output"] != nil }, "Keep failed model attempts in the report.")
        #expect(samples.allSatisfy { $0["contractPassed"] as? Bool == true }, "Inspect the full raw outputs before adopting a model.")
    }
}
