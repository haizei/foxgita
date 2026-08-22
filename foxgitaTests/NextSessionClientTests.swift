import Foundation
import Testing
@testable import foxgita

@Suite(.serialized)
struct NextSessionClientTests {
    private func makeClient(
        registry: SkillRegistry = .builtin,
        memory: any MemoryContextProviding = EmptyMemoryContext()
    ) -> NextSessionClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return NextSessionClient(
            session: URLSession(configuration: config),
            registry: registry,
            memory: memory
        )
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

    @Test func capRawClampsTargetAndDropsTrailingSteps() {
        let raw = AIPracticeDraft.Raw(
            title: "今日",
            category: "chord",
            targetMin: 40,
            steps: ["热身", "重点", "收尾", "加练"],
            chords: nil,
            stepMinutes: [5, 10, 10, 10]
        )
        let capped = NextSessionClient.capRaw(raw, budget: 20)
        #expect(capped.targetMin == 20)
        #expect(capped.steps == ["热身", "重点"])
        #expect(capped.stepMinutes == [5, 10])
    }

    @Test func capRawWithoutStepMinutesOnlyClampsTarget() {
        let raw = AIPracticeDraft.Raw(
            title: "今日", category: "chord", targetMin: 40,
            steps: ["A", "B"], chords: nil, stepMinutes: nil
        )
        let capped = NextSessionClient.capRaw(raw, budget: 15)
        #expect(capped.targetMin == 15)
        #expect(capped.steps == ["A", "B"])
        #expect(capped.stepMinutes == nil)
    }

    @Test func capRawDropsNonPositiveMinutesAndEmptySteps() {
        let raw = AIPracticeDraft.Raw(
            title: "今日", category: "left", targetMin: 20,
            steps: [" ", "有效", "零分钟"],
            chords: nil,
            stepMinutes: [5, 8, 0]
        )
        let capped = NextSessionClient.capRaw(raw, budget: 20)
        #expect(capped.steps == ["有效"])
        #expect(capped.stepMinutes == [8])
    }

    @Test func generateDraftReplacesMinutesAndCaps() async throws {
        let payload: [String: Any] = [
            "choices": [[
                "message": [
                    "content": #"{"title":"F 和弦","category":"chord","targetMin":40,"steps":["热身","重点","收尾"],"stepMinutes":[5,20,15]}"#
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

        let draft = try await makeClient().generateDraft(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk-test",
            budgetMinutes: 20,
            fallbackCategory: .song
        )
        #expect(draft.title == "F 和弦")
        #expect(draft.category == .chord)
        #expect(draft.targetMin == 20)
        #expect(draft.steps.contains(where: { $0.contains("热身") }))
        let messages = bodyJSON["messages"] as? [[String: Any]]
        #expect(messages?[0]["content"] as? String == SkillDefinition.nextSession.systemPrompt)
        let user = messages?[1]["content"] as? [[String: Any]]
        let userText = user?[0]["text"] as? String ?? ""
        #expect(userText.contains("20"))
        #expect(!userText.contains("{{minutes}}"))
        #expect(!userText.contains("<<<BACKGROUND_MEMORY>>>"))
    }

    @Test func generateDraftAppendsMemoryBlockWithoutChangingSystemPrompt() async throws {
        let payload: [String: Any] = [
            "choices": [[
                "message": [
                    "content": #"{"title":"开放弦","category":"left","targetMin":20,"steps":["拨弦"]}"#
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

        let client = makeClient(
            memory: StubMemoryContext(text: "<<<BACKGROUND_MEMORY>>>\n- [goal] 当前目标：《晴天》前奏\n<<<END_BACKGROUND_MEMORY>>>")
        )
        _ = try await client.generateDraft(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk-test",
            budgetMinutes: 20,
            fallbackCategory: .song
        )
        let messages = bodyJSON["messages"] as? [[String: Any]]
        #expect(messages?[0]["content"] as? String == SkillDefinition.nextSession.systemPrompt)
        let user = messages?[1]["content"] as? [[String: Any]]
        let userText = user?[0]["text"] as? String ?? ""
        #expect(userText.contains("<<<BACKGROUND_MEMORY>>>"))
        #expect(userText.contains("当前目标：《晴天》前奏"))
        #expect(!userText.contains("{{minutes}}"))
    }

    @Test func generateDraftUnregisteredSkillSendsNoRequest() async {
        var calls = 0
        MockURLProtocol.handler = { _ in
            calls += 1
            return (200, Data())
        }
        defer { MockURLProtocol.handler = nil }
        let client = makeClient(registry: SkillRegistry(skills: []))
        await #expect(throws: VisionPracticeError.unregisteredSkill) {
            try await client.generateDraft(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                budgetMinutes: 20,
                fallbackCategory: .left
            )
        }
        #expect(calls == 0)
    }
}
