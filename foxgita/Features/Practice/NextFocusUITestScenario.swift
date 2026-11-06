#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Deterministic UI coverage without credentials or requests to a live AI API.
enum NextFocusUITestScenario {
    static var isActive: Bool {
        PracticeTestEnvironment.isActive && ProcessInfo.processInfo.arguments.contains("-NextFocusFixture")
    }
    static var needsInput: Bool { ProcessInfo.processInfo.arguments.contains("-NextFocusNeedsInput") }
    static func initialOutput(_ context: NextFocusContext) -> NextFocusOutput {
        .init(recap: "本次完成「\(context.title)」练习。\n还没有留下练习笔记。",
              focus: needsInput ? "" : "继续练习 C→G，留意切换时的连贯性。",
              basis: needsInput ? "请补充想继续的内容。" : "根据本次练习内容整理。")
    }
}

struct NextFocusUITestGenerator: NextFocusGenerating {
    func generate(context: NextFocusContext, supplement: String, baseURL: String,
                  model: String, apiKey: String) async throws -> NextFocusOutput {
        .init(recap: "本次完成「\(context.title)」练习。", focus: supplement, basis: "根据你补充的下次安排整理。")
    }
}
#endif
