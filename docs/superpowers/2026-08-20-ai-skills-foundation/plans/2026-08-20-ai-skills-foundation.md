# AI Skills Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route the three existing AI features through a compile-time `SkillRegistry` and shared `AITransport` without changing user-visible results (except timeout mapping).

**Architecture:** Keep Generators and `VisionGenerating` / `MediaReviewing` / `VideoDiagnosing`. Each `*Client` looks up its Skill, selects frozen prompt + current user text, calls `AITransport.complete`, then parses the existing Draft DTO. Transport owns URL join, Bearer, HTTP mapping, body JSON, `response_format` retry-once, and fence stripping. Memory scopes exist on the definition and stay deny/empty; no Memory runtime.

**Tech Stack:** iOS 18+ · SwiftUI · URLSession · Swift Testing · existing `LLMCredentialsStore` / Draft DTOs

## Global Constraints

- Spec: `docs/superpowers/2026-08-20-ai-skills-foundation/specs/2026-08-20-ai-skills-foundation-design.md`
- iOS 18+ · Scheme `foxgita` · cwd `foxgita/`
- Prompts must match spec Appendix A **verbatim**
- Do not change Generator protocol signatures, Views, Schema V5, Settings, or Keychain
- `typealias AIClientError = VisionPracticeError`; keep the enum name
- Production must not persist API Key, full Prompt, image bytes, or full model response
- Test JPEG snapshots redact to `"<jpeg>"`
- Only allowed behavior change: `URLError.timedOut` → `.timeout` for image and media review (video already does this)
- New files under `foxgita/Services/` and `foxgitaTests/` are picked up by `PBXFileSystemSynchronizedRootGroup` — do **not** edit `project.pbxproj`
- YAGNI: no Memory store, no consent UI, no Skill engine generic `run`, no Bundle prompt files, no fourth Skill
- Unit test command:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

- If `git log -1` fails (repo has no commits), **skip every Commit step** and continue. Do not `git init`. Do not commit unrelated files outside `program/gita`.

## File map

| File | Responsibility |
|---|---|
| `foxgita/Services/VisionPracticeClient.swift` | `VisionPracticeError` + `AIClientError`; thin image Skill adapter |
| `foxgita/Services/ImageStepGenerator.swift` | `userMessage` switch adds `.unregisteredSkill` |
| `foxgita/Services/SkillDefinition.swift` | `SkillID`, memory enums, `SkillDefinition`, three frozen static lets |
| `foxgita/Services/SkillRegistry.swift` | `builtin` lookup; injectable table |
| `foxgita/Services/AITransport.swift` | URL, HTTP, body, fence, format retry |
| `foxgita/Services/MediaReviewClient.swift` | Thin media Skill adapter |
| `foxgita/Services/VideoDiagnosisClient.swift` | Thin video Skill adapter; keep `requestTimeout = 180` |
| `foxgitaTests/SkillRegistryTests.swift` | Builtin ids, deny memory, missing id |
| `foxgitaTests/AITransportTests.swift` | URL, fence, HTTP, retry, timeout |
| `foxgitaTests/VisionPracticeClientTests.swift` | Existing cases + timeout + snapshot + unregistered |
| `foxgitaTests/MediaReviewClientTests.swift` | Existing cases + timeout + snapshot + unregistered |
| `foxgitaTests/VideoDiagnosisClientTests.swift` | Existing cases + snapshot + unregistered |
| `foxgitaTests/ImageStepGeneratorTests.swift` | Unregistered copy |
| `docs/TECHNICAL.md` · `docs/TEST_PLAN_CLI.md` | Registry / Transport suites |

---

### Task 1: `unregisteredSkill` error + user copy

**Files:**
- Modify: `foxgita/Services/VisionPracticeClient.swift` (enum only)
- Modify: `foxgita/Services/ImageStepGenerator.swift` (switch)
- Test: `foxgitaTests/ImageStepGeneratorTests.swift`

**Interfaces:**
- Consumes: existing `VisionPracticeError`
- Produces:
  - `VisionPracticeError.unregisteredSkill`
  - `typealias AIClientError = VisionPracticeError`
  - `ImageStepGeneratorError.failed(.unregisteredSkill).userMessage` == localized `"生成失败，请稍后重试"`

- [ ] **Step 1: Write the failing test**

Add to `foxgitaTests/ImageStepGeneratorTests.swift`:

```swift
@Test func unregisteredSkillUsesGenericFailureCopy() {
    let message = ImageStepGeneratorError.failed(.unregisteredSkill).userMessage
    #expect(message == String(localized: "生成失败，请稍后重试"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/ImageStepGeneratorTests test
```

Expected: FAIL compile (`unregisteredSkill` not found).

- [ ] **Step 3: Add the case, alias, and switch arm**

In `VisionPracticeClient.swift`, replace the enum and add the alias immediately below it:

```swift
enum VisionPracticeError: Error, Equatable {
    case invalidURL
    case unauthorized
    case httpStatus(Int)
    case emptyContent
    case invalidJSON
    case timeout
    case transport
    case unregisteredSkill
}

typealias AIClientError = VisionPracticeError
```

In `ImageStepGenerator.swift`, change the inner switch to:

```swift
            switch vision {
            case .unauthorized:
                return String(localized: "API Key 无效或无权限")
            case .invalidJSON, .emptyContent:
                return String(localized: "模型返回格式不对，可换模型或重试")
            case .timeout:
                return String(localized: "请求超时，请重试")
            case .transport:
                return String(localized: "网络异常，请重试")
            case .invalidURL, .httpStatus, .unregisteredSkill:
                return String(localized: "生成失败，请稍后重试")
            }
```

- [ ] **Step 4: Run test to verify it passes**

Same `xcodebuild` as Step 2.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/foxgita/Services/VisionPracticeClient.swift \
  foxgita/foxgita/Services/ImageStepGenerator.swift \
  foxgita/foxgitaTests/ImageStepGeneratorTests.swift
git commit -m "$(cat <<'EOF'
Add unregisteredSkill AI error mapped to generic failure copy.

EOF
)"
```

---

### Task 2: SkillDefinition + SkillRegistry

**Files:**
- Create: `foxgita/Services/SkillDefinition.swift`
- Create: `foxgita/Services/SkillRegistry.swift`
- Test: `foxgitaTests/SkillRegistryTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `enum SkillID` with `planFromImage`, `reviewMedia`, `diagnoseVideo` string constants
  - `enum MemoryScope: String` — `fact`, `goal`, `preference`, `ability`, `summary`
  - `enum MemoryWritePolicy` — `deny`, `candidates`
  - `struct SkillDefinition` fields exactly as spec §4.1
  - `SkillDefinition.planFromImage`, `.reviewMedia`, `.diagnoseVideo` (version `"1.0.0"`)
  - `struct SkillRegistry` with `static let builtin`, `init(skills:)`, `func skill(id: String) -> SkillDefinition?`

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/SkillRegistryTests.swift`:

```swift
import Foundation
import Testing
@testable import foxgita

struct SkillRegistryTests {
    @Test func builtinContainsFrozenSkillsWithDenyMemory() {
        let plan = SkillRegistry.builtin.skill(id: SkillID.planFromImage)
        let review = SkillRegistry.builtin.skill(id: SkillID.reviewMedia)
        let video = SkillRegistry.builtin.skill(id: SkillID.diagnoseVideo)
        #expect(plan != nil)
        #expect(review != nil)
        #expect(video != nil)
        #expect(plan?.version == "1.0.0")
        #expect(review?.version == "1.0.0")
        #expect(video?.version == "1.0.0")
        #expect(plan?.memoryReadScopes == [])
        #expect(review?.memoryReadScopes == [])
        #expect(video?.memoryReadScopes == [])
        #expect(plan?.memoryWritePolicy == .deny)
        #expect(review?.memoryWritePolicy == .deny)
        #expect(video?.memoryWritePolicy == .deny)
        #expect(plan?.userPrompt != nil)
        #expect(review?.userPrompt == nil)
        #expect(video?.userPrompt == nil)
        #expect(plan?.timeout == nil)
        #expect(review?.timeout == nil)
        #expect(video?.timeout == 180)
        #expect(plan?.allowsFormatRetry == true)
        #expect(plan?.systemPrompt == "你是吉他练习教练。只输出合法 JSON。")
        #expect(plan?.userPrompt == """
        请根据图片总结成吉他练习任务。只返回 JSON 对象，不要 markdown，不要其它说明。
        字段：
        - title: 字符串
        - category: 仅能为 left/right/both/chord/scale/rhythm/song 之一
        - targetMin: 整数分钟
        - steps: 字符串数组（练习步骤）
        - chords: 可选，识别到的和弦名字符串数组（如 C、G、Am）
        - stepMinutes: 可选，与 steps 按下标对齐的整数分钟；没有则省略
        """)
        #expect(review?.systemPrompt == """
        你是吉他练习陪伴教练。根据波形图或练习画面帧给出简短复盘。只返回 JSON，不要 markdown。
        字段：highlight（亮点）、focus（优先改善）、nextAction（下次练法）。
        每段一句话，不要编造时间戳（如 01:18），不要承诺精确音准鉴定。
        """)
        #expect(video?.systemPrompt == """
        你是吉他练习诊断教练。根据练习录像关键帧和可选波形，给出可定位的分段诊断。只返回 JSON，不要 markdown。
        字段：highlight、focus、nextAction（各一句话），findings（数组，可空）。
        每条 finding 字段：startSec、endSec（整数秒，必须落在 0 到视频时长之间）、title、evidence、cause、action。
        evidence 写看到或听到的具体现象。证据不足就少写或不写 finding，不要编造时间点，不要承诺精确音准鉴定。最多 5 条。
        """)
    }

    @Test func missingIdReturnsNil() {
        #expect(SkillRegistry.builtin.skill(id: "no.such.skill") == nil)
        let empty = SkillRegistry(skills: [])
        #expect(empty.skill(id: SkillID.planFromImage) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/SkillRegistryTests test
```

Expected: FAIL compile (`SkillRegistry` / `SkillID` not found).

- [ ] **Step 3: Implement types and builtin table**

Create `foxgita/Services/SkillDefinition.swift` with the exact Appendix A strings (copy from the test above, do not rewrite):

```swift
import Foundation

enum SkillID {
    static let planFromImage = "practice.plan.from_image"
    static let reviewMedia = "practice.review.media"
    static let diagnoseVideo = "practice.diagnose.video"
}

enum MemoryScope: String, Equatable, Sendable {
    case fact
    case goal
    case preference
    case ability
    case summary
}

enum MemoryWritePolicy: Equatable, Sendable {
    case deny
    case candidates
}

struct SkillDefinition: Equatable, Sendable {
    var id: String
    var version: String
    var title: String
    var purpose: String
    var systemPrompt: String
    var userPrompt: String?
    var timeout: TimeInterval?
    var allowsFormatRetry: Bool
    var memoryReadScopes: [MemoryScope]
    var memoryWritePolicy: MemoryWritePolicy
}

extension SkillDefinition {
    static let planFromImage = SkillDefinition(
        id: SkillID.planFromImage,
        version: "1.0.0",
        title: "图片转练习",
        purpose: "从图片生成练习任务草稿",
        systemPrompt: "你是吉他练习教练。只输出合法 JSON。",
        userPrompt: """
        请根据图片总结成吉他练习任务。只返回 JSON 对象，不要 markdown，不要其它说明。
        字段：
        - title: 字符串
        - category: 仅能为 left/right/both/chord/scale/rhythm/song 之一
        - targetMin: 整数分钟
        - steps: 字符串数组（练习步骤）
        - chords: 可选，识别到的和弦名字符串数组（如 C、G、Am）
        - stepMinutes: 可选，与 steps 按下标对齐的整数分钟；没有则省略
        """,
        timeout: nil,
        allowsFormatRetry: true,
        memoryReadScopes: [],
        memoryWritePolicy: .deny
    )

    static let reviewMedia = SkillDefinition(
        id: SkillID.reviewMedia,
        version: "1.0.0",
        title: "媒体复盘",
        purpose: "根据波形或练习画面给出三段复盘",
        systemPrompt: """
        你是吉他练习陪伴教练。根据波形图或练习画面帧给出简短复盘。只返回 JSON，不要 markdown。
        字段：highlight（亮点）、focus（优先改善）、nextAction（下次练法）。
        每段一句话，不要编造时间戳（如 01:18），不要承诺精确音准鉴定。
        """,
        userPrompt: nil,
        timeout: nil,
        allowsFormatRetry: true,
        memoryReadScopes: [],
        memoryWritePolicy: .deny
    )

    static let diagnoseVideo = SkillDefinition(
        id: SkillID.diagnoseVideo,
        version: "1.0.0",
        title: "录像分段诊断",
        purpose: "根据关键帧给出可定位的分段诊断",
        systemPrompt: """
        你是吉他练习诊断教练。根据练习录像关键帧和可选波形，给出可定位的分段诊断。只返回 JSON，不要 markdown。
        字段：highlight、focus、nextAction（各一句话），findings（数组，可空）。
        每条 finding 字段：startSec、endSec（整数秒，必须落在 0 到视频时长之间）、title、evidence、cause、action。
        evidence 写看到或听到的具体现象。证据不足就少写或不写 finding，不要编造时间点，不要承诺精确音准鉴定。最多 5 条。
        """,
        userPrompt: nil,
        timeout: 180,
        allowsFormatRetry: true,
        memoryReadScopes: [],
        memoryWritePolicy: .deny
    )
}
```

Create `foxgita/Services/SkillRegistry.swift`:

```swift
import Foundation

struct SkillRegistry: Sendable {
    static let builtin = SkillRegistry(skills: [
        .planFromImage,
        .reviewMedia,
        .diagnoseVideo,
    ])

    private let skills: [String: SkillDefinition]

    init(skills: [SkillDefinition]) {
        var map: [String: SkillDefinition] = [:]
        map.reserveCapacity(skills.count)
        for skill in skills {
            precondition(map[skill.id] == nil, "duplicate skill id \(skill.id)")
            map[skill.id] = skill
        }
        self.skills = map
    }

    func skill(id: String) -> SkillDefinition? {
        skills[id]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same `xcodebuild` as Step 2.

Expected: PASS. If a prompt assertion fails, the Swift multiline string does not match Appendix A — fix the constant, do not weaken the test.

- [ ] **Step 5: Commit**

```bash
git add foxgita/foxgita/Services/SkillDefinition.swift \
  foxgita/foxgita/Services/SkillRegistry.swift \
  foxgita/foxgitaTests/SkillRegistryTests.swift
git commit -m "$(cat <<'EOF'
Add versioned Skill definitions and compile-time registry.

EOF
)"
```

---

### Task 3: AITransport (URL, fence, HTTP, retry)

**Files:**
- Create: `foxgita/Services/AITransport.swift`
- Test: `foxgitaTests/AITransportTests.swift`

**Interfaces:**
- Consumes: `VisionPracticeError`
- Produces:
  - `struct AITransport: Sendable`
  - `init(session: URLSession = .shared)`
  - `static func completionsURL(from baseURL: String) -> URL?`
  - `static func stripMarkdownFences(_ text: String) -> String`
  - `func complete(url:apiKey:model:systemPrompt:userText:imageJPEGData:includeResponseFormat:allowsFormatRetry:timeout:) async throws -> String`
  - Return value: trimmed `message.content`, **not** fence-stripped
  - ChatResponse decode failure → `.invalidJSON`
  - `URLError.timedOut` → `.timeout`

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/AITransportTests.swift`:

```swift
import Foundation
import Testing
@testable import foxgita

final class TransportMockURLProtocol: URLProtocol, @unchecked Sendable {
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
struct AITransportTests {
    private func makeTransport() -> AITransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TransportMockURLProtocol.self]
        return AITransport(session: URLSession(configuration: config))
    }

    @Test func completionsURLJoinsAndRespectsFullPath() {
        #expect(
            AITransport.completionsURL(from: "https://api.openai.com/v1/")?
                .absoluteString == "https://api.openai.com/v1/chat/completions"
        )
        #expect(
            AITransport.completionsURL(
                from: "https://example.com/v1/chat/completions"
            )?.absoluteString == "https://example.com/v1/chat/completions"
        )
        #expect(AITransport.completionsURL(from: "   ") == nil)
    }

    @Test func stripMarkdownFencesRemovesJsonFence() {
        let raw = "```json\n{\"a\":1}\n```"
        #expect(AITransport.stripMarkdownFences(raw) == "{\"a\":1}")
    }

    @Test func completeReturnsTrimmedContentWithoutStrippingFence() async throws {
        let payload: [String: Any] = [
            "choices": [["message": ["content": "```json\n{\"ok\":true}\n```"]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        TransportMockURLProtocol.handler = { _ in (200, data) }
        defer { TransportMockURLProtocol.handler = nil }

        let url = AITransport.completionsURL(from: "https://api.openai.com/v1")!
        let content = try await makeTransport().complete(
            url: url, apiKey: "sk", model: "gpt-4o",
            systemPrompt: "sys", userText: "user",
            imageJPEGData: [Data([0xFF])],
            includeResponseFormat: true, allowsFormatRetry: true, timeout: nil
        )
        #expect(content == "```json\n{\"ok\":true}\n```")
    }

    @Test func completeUnauthorized() async {
        TransportMockURLProtocol.handler = { _ in (401, Data()) }
        defer { TransportMockURLProtocol.handler = nil }
        let url = AITransport.completionsURL(from: "https://api.openai.com/v1")!
        await #expect(throws: VisionPracticeError.unauthorized) {
            try await makeTransport().complete(
                url: url, apiKey: "bad", model: "m",
                systemPrompt: "s", userText: "u",
                imageJPEGData: [],
                includeResponseFormat: true, allowsFormatRetry: true, timeout: nil
            )
        }
    }

    @Test func completeInvalidChatJSON() async {
        TransportMockURLProtocol.handler = { _ in (200, Data("not-json".utf8)) }
        defer { TransportMockURLProtocol.handler = nil }
        let url = AITransport.completionsURL(from: "https://api.openai.com/v1")!
        await #expect(throws: VisionPracticeError.invalidJSON) {
            try await makeTransport().complete(
                url: url, apiKey: "sk", model: "m",
                systemPrompt: "s", userText: "u",
                imageJPEGData: [],
                includeResponseFormat: true, allowsFormatRetry: true, timeout: nil
            )
        }
    }

    @Test func completeTimedOut() async {
        TransportMockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        defer { TransportMockURLProtocol.handler = nil }
        let url = AITransport.completionsURL(from: "https://api.openai.com/v1")!
        await #expect(throws: VisionPracticeError.timeout) {
            try await makeTransport().complete(
                url: url, apiKey: "sk", model: "m",
                systemPrompt: "s", userText: "u",
                imageJPEGData: [],
                includeResponseFormat: true, allowsFormatRetry: true, timeout: 180
            )
        }
    }

    @Test func completeRetriesOnceWithoutResponseFormat() async throws {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func hit() { lock.lock(); n += 1; lock.unlock() }
            func count() -> Int { lock.lock(); defer { lock.unlock() }; return n }
        }
        let counter = Counter()
        let ok = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": " {\"x\":1} "]]]
        ])
        TransportMockURLProtocol.handler = { req in
            counter.hit()
            let body = Self.requestBodyString(req)
            if counter.count() == 1 {
                #expect(body.contains("response_format"))
                return (400, Data(#"{"error":"unknown response_format"}"#.utf8))
            }
            #expect(!body.contains("response_format"))
            return (200, ok)
        }
        defer { TransportMockURLProtocol.handler = nil }

        let url = AITransport.completionsURL(from: "https://api.openai.com/v1")!
        let content = try await makeTransport().complete(
            url: url, apiKey: "sk", model: "m",
            systemPrompt: "s", userText: "u",
            imageJPEGData: [],
            includeResponseFormat: true, allowsFormatRetry: true, timeout: nil
        )
        #expect(content == "{\"x\":1}")
        #expect(counter.count() == 2)
    }

    @Test func completeDoesNotRetryTwice() async {
        TransportMockURLProtocol.handler = { _ in
            (400, Data("unknown response_format".utf8))
        }
        defer { TransportMockURLProtocol.handler = nil }
        let url = AITransport.completionsURL(from: "https://api.openai.com/v1")!
        await #expect(throws: VisionPracticeError.httpStatus(400)) {
            try await makeTransport().complete(
                url: url, apiKey: "sk", model: "m",
                systemPrompt: "s", userText: "u",
                imageJPEGData: [],
                includeResponseFormat: true, allowsFormatRetry: true, timeout: nil
            )
        }
    }

    @Test func completeAppliesTimeoutAndSnapshotShape() async throws {
        let ok = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": "{}"]]]
        ])
        var seenTimeout: TimeInterval = 0
        var bodyJSON: [String: Any] = [:]
        TransportMockURLProtocol.handler = { req in
            seenTimeout = req.timeoutInterval
            let text = Self.requestBodyString(req)
            bodyJSON = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
            return (200, ok)
        }
        defer { TransportMockURLProtocol.handler = nil }

        let url = AITransport.completionsURL(from: "https://api.openai.com/v1")!
        _ = try await makeTransport().complete(
            url: url, apiKey: "sk-test", model: "gpt-4o",
            systemPrompt: "sys-role", userText: "user-role",
            imageJPEGData: [Data([0xFF, 0xD8])],
            includeResponseFormat: true, allowsFormatRetry: true, timeout: 180
        )
        #expect(seenTimeout == 180)
        #expect(bodyJSON["model"] as? String == "gpt-4o")
        let messages = bodyJSON["messages"] as? [[String: Any]]
        #expect(messages?[0]["role"] as? String == "system")
        #expect(messages?[0]["content"] as? String == "sys-role")
        #expect(messages?[1]["role"] as? String == "user")
        let rf = bodyJSON["response_format"] as? [String: Any]
        #expect(rf?["type"] as? String == "json_object")
        #expect(bodyJSON["Authorization"] == nil)
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/AITransportTests test
```

Expected: FAIL compile (`AITransport` not found).

- [ ] **Step 3: Implement AITransport**

Create `foxgita/Services/AITransport.swift`:

```swift
import Foundation

struct AITransport: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func completionsURL(from baseURL: String) -> URL? {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }
        return URL(string: trimmed + "/chat/completions")
    }

    static func stripMarkdownFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if s.hasSuffix("```") {
                s.removeLast(3)
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.lowercased().hasPrefix("json") {
                // already stripped language tag via first newline path usually
            }
        }
        return s
    }

    func complete(
        url: URL,
        apiKey: String,
        model: String,
        systemPrompt: String,
        userText: String,
        imageJPEGData: [Data],
        includeResponseFormat: Bool,
        allowsFormatRetry: Bool,
        timeout: TimeInterval?
    ) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let timeout {
            request.timeoutInterval = timeout
        }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try Self.buildBody(
                model: model,
                systemPrompt: systemPrompt,
                userText: userText,
                imageJPEGData: imageJPEGData,
                includeResponseFormat: includeResponseFormat
            )
        } catch {
            throw VisionPracticeError.transport
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.mapSessionError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw VisionPracticeError.transport
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw VisionPracticeError.unauthorized
        }
        if !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8)?.lowercased() ?? ""
            if allowsFormatRetry,
               includeResponseFormat,
               (400...499).contains(http.statusCode),
               bodyText.contains("response_format") || bodyText.contains("unknown") {
                return try await complete(
                    url: url,
                    apiKey: apiKey,
                    model: model,
                    systemPrompt: systemPrompt,
                    userText: userText,
                    imageJPEGData: imageJPEGData,
                    includeResponseFormat: false,
                    allowsFormatRetry: false,
                    timeout: timeout
                )
            }
            throw VisionPracticeError.httpStatus(http.statusCode)
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    var content: String?
                }
                var message: Message?
            }
            var choices: [Choice]?
        }
        let chat: ChatResponse
        do {
            chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw VisionPracticeError.invalidJSON
        }
        return chat.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func mapSessionError(_ error: Error) -> VisionPracticeError {
        if (error as? URLError)?.code == .timedOut { return .timeout }
        return .transport
    }

    private static func buildBody(
        model: String,
        systemPrompt: String,
        userText: String,
        imageJPEGData: [Data],
        includeResponseFormat: Bool
    ) throws -> Data {
        var userContent: [[String: Any]] = [
            ["type": "text", "text": userText]
        ]
        for data in imageJPEGData {
            userContent.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(data.base64EncodedString())"
                ],
            ])
        }
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent],
            ],
        ]
        if includeResponseFormat {
            body["response_format"] = ["type": "json_object"]
        }
        return try JSONSerialization.data(withJSONObject: body)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Same `xcodebuild` as Step 2.

Expected: PASS. `completeReturnsTrimmedContentWithoutStrippingFence` must keep the fence; `completeRetriesOnce` expects trimmed `"{\"x\":1}"` because Transport trims but does not strip fences.

- [ ] **Step 5: Commit**

```bash
git add foxgita/foxgita/Services/AITransport.swift \
  foxgita/foxgitaTests/AITransportTests.swift
git commit -m "$(cat <<'EOF'
Add shared AI transport for chat completions.

EOF
)"
```

---

### Task 4: Migrate VisionPracticeClient

**Files:**
- Modify: `foxgita/Services/VisionPracticeClient.swift` (replace client body; keep error enum + protocol)
- Test: `foxgitaTests/VisionPracticeClientTests.swift`

**Interfaces:**
- Consumes: `SkillRegistry.builtin`, `SkillID.planFromImage`, `AITransport`
- Produces:
  - `init(session: URLSession = .shared, registry: SkillRegistry = .builtin)`
  - `static func completionsURL` forwards to `AITransport.completionsURL`
  - `generateDraft` looks up skill, calls `transport.complete`, empty content → `.emptyContent`, then `stripMarkdownFences` + existing `AIPracticeDraft.normalize`

- [ ] **Step 1: Add timeout + unregistered tests first**

Append to `VisionPracticeClientTests` (keep existing tests):

```swift
    @Test func generateDraftTimedOut() async {
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        defer { MockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.timeout) {
            try await makeClient().generateDraft(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0x01])],
                fallbackCategory: .left
            )
        }
    }

    @Test func generateDraftUnregisteredSkillSendsNoRequest() async {
        var calls = 0
        MockURLProtocol.handler = { _ in
            calls += 1
            return (200, Data())
        }
        defer { MockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = VisionPracticeClient(
            session: URLSession(configuration: config),
            registry: SkillRegistry(skills: [])
        )
        await #expect(throws: VisionPracticeError.unregisteredSkill) {
            try await client.generateDraft(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0x01])],
                fallbackCategory: .left
            )
        }
        #expect(calls == 0)
    }

    @Test func generateDraftUsesFrozenPlanSkillPrompt() async throws {
        let payload: [String: Any] = [
            "choices": [[
                "message": [
                    "content": #"{"title":"开放弦","category":"left","targetMin":8,"steps":["拨弦"]}"#
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

        _ = try await makeClient().generateDraft(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk-test",
            imageJPEGData: [Data([0xFF, 0xD8, 0xFF])],
            fallbackCategory: .song
        )
        let messages = bodyJSON["messages"] as? [[String: Any]]
        #expect(messages?[0]["content"] as? String == SkillDefinition.planFromImage.systemPrompt)
        let user = messages?[1]["content"] as? [[String: Any]]
        #expect(user?[0]["text"] as? String == SkillDefinition.planFromImage.userPrompt)
        let imageURL = user?[1]["image_url"] as? [String: Any]
        let dataURI = imageURL?["url"] as? String ?? ""
        #expect(dataURI.hasPrefix("data:image/jpeg;base64,"))
    }
```

`requestBodyString` already exists as `private static` on this suite — reuse it.

- [ ] **Step 2: Run tests to verify new cases fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/VisionPracticeClientTests test
```

Expected: FAIL (`init(session:registry:)` missing and/or timeout still `.transport`).

- [ ] **Step 3: Replace VisionPracticeClient implementation**

Keep `VisionPracticeError`, `AIClientError`, and `VisionGenerating` at the top of `VisionPracticeClient.swift`. Replace `struct VisionPracticeClient` with:

```swift
struct VisionPracticeClient: VisionGenerating {
    private let transport: AITransport
    private let registry: SkillRegistry

    init(session: URLSession = .shared, registry: SkillRegistry = .builtin) {
        self.transport = AITransport(session: session)
        self.registry = registry
    }

    static func completionsURL(from baseURL: String) -> URL? {
        AITransport.completionsURL(from: baseURL)
    }

    func generateDraft(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        fallbackCategory: PracticeCategory
    ) async throws -> AIPracticeDraft {
        guard let skill = registry.skill(id: SkillID.planFromImage) else {
            throw VisionPracticeError.unregisteredSkill
        }
        guard let url = AITransport.completionsURL(from: baseURL) else {
            throw VisionPracticeError.invalidURL
        }
        let userText = skill.userPrompt ?? ""
        let rawContent: String
        do {
            rawContent = try await transport.complete(
                url: url,
                apiKey: apiKey,
                model: model,
                systemPrompt: skill.systemPrompt,
                userText: userText,
                imageJPEGData: imageJPEGData,
                includeResponseFormat: true,
                allowsFormatRetry: skill.allowsFormatRetry,
                timeout: skill.timeout
            )
        } catch let error as VisionPracticeError {
            throw error
        } catch {
            throw VisionPracticeError.transport
        }
        guard !rawContent.isEmpty else {
            throw VisionPracticeError.emptyContent
        }
        return try Self.parseDraft(from: rawContent, fallbackCategory: fallbackCategory)
    }

    private static func parseDraft(
        from content: String,
        fallbackCategory: PracticeCategory
    ) throws -> AIPracticeDraft {
        let jsonText = AITransport.stripMarkdownFences(content)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw VisionPracticeError.invalidJSON
        }
        let raw: AIPracticeDraft.Raw
        do {
            raw = try JSONDecoder().decode(AIPracticeDraft.Raw.self, from: jsonData)
        } catch {
            throw VisionPracticeError.invalidJSON
        }
        return AIPracticeDraft.normalize(raw, fallbackCategory: fallbackCategory)
    }
}
```

Delete `perform`, `buildBody`, the old `parseDraft(from data:)`, and `stripMarkdownFences` from this file.

- [ ] **Step 4: Run VisionPracticeClientTests**

Same command as Step 2.

Expected: all PASS, including existing success / 401 / invalid JSON / format retry / `completionsURL`.

- [ ] **Step 5: Commit**

```bash
git add foxgita/foxgita/Services/VisionPracticeClient.swift \
  foxgita/foxgitaTests/VisionPracticeClientTests.swift
git commit -m "$(cat <<'EOF'
Route image-to-practice through SkillRegistry and AITransport.

EOF
)"
```

---

### Task 5: Migrate MediaReviewClient

**Files:**
- Modify: `foxgita/Services/MediaReviewClient.swift`
- Test: `foxgitaTests/MediaReviewClientTests.swift`

**Interfaces:**
- Consumes: `SkillID.reviewMedia`, `AITransport`, `SkillRegistry`
- Produces: `init(session:registry:)` with the same defaults as Vision; empty content → `.invalidJSON`; user text is `skill.userPrompt ?? contextText`

- [ ] **Step 1: Add timeout, unregistered, and snapshot tests**

Append to `MediaReviewClientTests`:

```swift
    @Test func generateReviewTimedOut() async {
        ReviewMockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        defer { ReviewMockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.timeout) {
            try await makeClient().generateReview(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0xFF])],
                contextText: "x"
            )
        }
    }

    @Test func generateReviewUnregisteredSkillSendsNoRequest() async {
        var calls = 0
        ReviewMockURLProtocol.handler = { _ in
            calls += 1
            return (200, Data())
        }
        defer { ReviewMockURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReviewMockURLProtocol.self]
        let client = MediaReviewClient(
            session: URLSession(configuration: config),
            registry: SkillRegistry(skills: [])
        )
        await #expect(throws: VisionPracticeError.unregisteredSkill) {
            try await client.generateReview(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0xFF])],
                contextText: "任务：和弦转换"
            )
        }
        #expect(calls == 0)
    }

    @Test func generateReviewUsesFrozenSystemAndRuntimeContext() async throws {
        let payload: [String: Any] = [
            "choices": [[
                "message": ["content": #"{"highlight":"稳","focus":"F 慢","nextAction":"70 BPM"}"#]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var bodyJSON: [String: Any] = [:]
        ReviewMockURLProtocol.handler = { req in
            let text = Self.requestBodyString(req)
            bodyJSON = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
            return (200, data)
        }
        defer { ReviewMockURLProtocol.handler = nil }

        _ = try await makeClient().generateReview(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk-test",
            imageJPEGData: [Data([0xFF, 0xD8])],
            contextText: "任务：和弦转换"
        )
        let messages = bodyJSON["messages"] as? [[String: Any]]
        #expect(messages?[0]["content"] as? String == SkillDefinition.reviewMedia.systemPrompt)
        let user = messages?[1]["content"] as? [[String: Any]]
        #expect(user?[0]["text"] as? String == "任务：和弦转换")
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
```

- [ ] **Step 2: Run tests to verify new cases fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MediaReviewClientTests test
```

Expected: FAIL compile or timeout still `.transport`.

- [ ] **Step 3: Replace MediaReviewClient**

Keep `MediaReviewing`. Replace `struct MediaReviewClient` with:

```swift
struct MediaReviewClient: MediaReviewing {
    private let transport: AITransport
    private let registry: SkillRegistry

    init(session: URLSession = .shared, registry: SkillRegistry = .builtin) {
        self.transport = AITransport(session: session)
        self.registry = registry
    }

    func generateReview(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        contextText: String
    ) async throws -> MediaReviewDraft {
        guard let skill = registry.skill(id: SkillID.reviewMedia) else {
            throw VisionPracticeError.unregisteredSkill
        }
        guard let url = AITransport.completionsURL(from: baseURL) else {
            throw VisionPracticeError.invalidURL
        }
        let userText = skill.userPrompt ?? contextText
        let rawContent: String
        do {
            rawContent = try await transport.complete(
                url: url,
                apiKey: apiKey,
                model: model,
                systemPrompt: skill.systemPrompt,
                userText: userText,
                imageJPEGData: imageJPEGData,
                includeResponseFormat: true,
                allowsFormatRetry: skill.allowsFormatRetry,
                timeout: skill.timeout
            )
        } catch let error as VisionPracticeError {
            throw error
        } catch {
            throw VisionPracticeError.transport
        }
        guard !rawContent.isEmpty else {
            throw VisionPracticeError.invalidJSON
        }
        return try Self.parseDraft(from: rawContent)
    }

    private static func parseDraft(from content: String) throws -> MediaReviewDraft {
        let jsonText = AITransport.stripMarkdownFences(content)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw VisionPracticeError.invalidJSON
        }
        let raw: MediaReviewDraft.Raw
        do {
            raw = try JSONDecoder().decode(MediaReviewDraft.Raw.self, from: jsonData)
        } catch {
            throw VisionPracticeError.invalidJSON
        }
        do {
            return try MediaReviewDraft.normalize(raw)
        } catch {
            throw VisionPracticeError.invalidJSON
        }
    }
}
```

Delete `perform`, `buildBody`, old `parseDraft(from data:)`, and `stripMarkdownFences`.

- [ ] **Step 4: Run MediaReviewClientTests**

Same command as Step 2.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/foxgita/Services/MediaReviewClient.swift \
  foxgita/foxgitaTests/MediaReviewClientTests.swift
git commit -m "$(cat <<'EOF'
Route media review through SkillRegistry and AITransport.

EOF
)"
```

---

### Task 6: Migrate VideoDiagnosisClient

**Files:**
- Modify: `foxgita/Services/VideoDiagnosisClient.swift`
- Test: `foxgitaTests/VideoDiagnosisClientTests.swift`

**Interfaces:**
- Consumes: `SkillID.diagnoseVideo`, `AITransport`
- Produces: keep `static let requestTimeout: TimeInterval = 180` and `makeSession()`; `init(session: URLSession = makeSession(), registry: SkillRegistry = .builtin)`; `complete` timeout = `skill.timeout` (180); empty content → `.invalidJSON`

- [ ] **Step 1: Add unregistered + snapshot tests**

Append to `VideoDiagnosisClientTests` (existing timeout tests stay):

```swift
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
```

- [ ] **Step 2: Run tests to verify new cases fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/VideoDiagnosisClientTests test
```

Expected: FAIL compile (`init(session:registry:)` missing).

- [ ] **Step 3: Replace VideoDiagnosisClient**

```swift
import Foundation

protocol VideoDiagnosing: Sendable {
    func generateDiagnosis(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        contextText: String,
        durationSec: Int
    ) async throws -> VideoDiagnosisDraft
}

struct VideoDiagnosisClient: VideoDiagnosing {
    static let requestTimeout: TimeInterval = 180

    private let transport: AITransport
    private let registry: SkillRegistry

    init(
        session: URLSession = VideoDiagnosisClient.makeSession(),
        registry: SkillRegistry = .builtin
    ) {
        self.transport = AITransport(session: session)
        self.registry = registry
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout
        return URLSession(configuration: config)
    }

    func generateDiagnosis(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        contextText: String,
        durationSec: Int
    ) async throws -> VideoDiagnosisDraft {
        guard let skill = registry.skill(id: SkillID.diagnoseVideo) else {
            throw VisionPracticeError.unregisteredSkill
        }
        guard let url = AITransport.completionsURL(from: baseURL) else {
            throw VisionPracticeError.invalidURL
        }
        let userText = skill.userPrompt ?? contextText
        let rawContent: String
        do {
            rawContent = try await transport.complete(
                url: url,
                apiKey: apiKey,
                model: model,
                systemPrompt: skill.systemPrompt,
                userText: userText,
                imageJPEGData: imageJPEGData,
                includeResponseFormat: true,
                allowsFormatRetry: skill.allowsFormatRetry,
                timeout: skill.timeout
            )
        } catch let error as VisionPracticeError {
            throw error
        } catch {
            if (error as? URLError)?.code == .timedOut {
                throw VisionPracticeError.timeout
            }
            throw VisionPracticeError.transport
        }
        guard !rawContent.isEmpty else {
            throw VisionPracticeError.invalidJSON
        }
        return try Self.parseDraft(from: rawContent, durationSec: durationSec)
    }

    private static func parseDraft(from content: String, durationSec: Int) throws -> VideoDiagnosisDraft {
        let jsonText = AITransport.stripMarkdownFences(content)
        guard let jsonData = jsonText.data(using: .utf8),
              let raw = try? JSONDecoder().decode(VideoDiagnosisDraft.Raw.self, from: jsonData),
              let draft = try? VideoDiagnosisDraft.normalize(raw, durationSec: durationSec)
        else {
            throw VisionPracticeError.invalidJSON
        }
        return draft
    }
}
```

Delete `perform`, `buildBody`, old `parseDraft(from data:)`, inline fence, and `mapSessionError`. Keep `requestTimeout == 180` as the same literal as `SkillDefinition.diagnoseVideo.timeout`.

- [ ] **Step 4: Run VideoDiagnosisClientTests**

Same command as Step 2.

Expected: PASS, including `generateDiagnosisSetsLongRequestTimeout` (`seen == 180`) because Transport sets `timeoutInterval` from `skill.timeout`.

- [ ] **Step 5: Commit**

```bash
git add foxgita/foxgita/Services/VideoDiagnosisClient.swift \
  foxgita/foxgitaTests/VideoDiagnosisClientTests.swift
git commit -m "$(cat <<'EOF'
Route video diagnosis through SkillRegistry and AITransport.

EOF
)"
```

---

### Task 7: Fence-through-client + full suite regression

**Files:**
- Test: `foxgitaTests/VisionPracticeClientTests.swift` (one fence case)
- Docs: none yet

**Interfaces:**
- Consumes: Task 4 `parseDraft` + `AITransport.stripMarkdownFences`
- Produces: proof that empty-check-before-strip still holds, and fenced JSON still parses

- [ ] **Step 1: Write the failing fence test**

Append to `VisionPracticeClientTests`:

```swift
    @Test func generateDraftStripsFenceAfterEmptyCheck() async throws {
        let payload: [String: Any] = [
            "choices": [[
                "message": [
                    "content": "```json\n{\"title\":\"开放弦\",\"category\":\"left\",\"targetMin\":8,\"steps\":[\"拨弦\"]}\n```"
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        MockURLProtocol.handler = { _ in (200, data) }
        defer { MockURLProtocol.handler = nil }
        let draft = try await makeClient().generateDraft(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk",
            imageJPEGData: [Data([0x01])],
            fallbackCategory: .song
        )
        #expect(draft.title == "开放弦")
    }
```

- [ ] **Step 2: Run the test**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/VisionPracticeClientTests/generateDraftStripsFenceAfterEmptyCheck test
```

Expected: PASS already if Task 4 used `stripMarkdownFences` after the empty check. If FAIL, fix `parseDraft` — do not strip inside `complete`.

- [ ] **Step 3: Run the full unit suite**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

Expected: `TEST SUCCEEDED`. Generator tests must still pass unchanged.

- [ ] **Step 4: Commit**

```bash
git add foxgita/foxgitaTests/VisionPracticeClientTests.swift
git commit -m "$(cat <<'EOF'
Cover fenced JSON parse through the image Skill adapter.

EOF
)"
```

---

### Task 8: Docs

**Files:**
- Modify: `foxgita/docs/TECHNICAL.md`
- Modify: `foxgita/docs/TEST_PLAN_CLI.md`
- Modify: `foxgita/docs/superpowers/2026-08-20-ai-skills-foundation/specs/2026-08-20-ai-skills-foundation-design.md` (status line only)

**Interfaces:**
- Consumes: shipped types from Tasks 1–7
- Produces: docs that name Registry / Transport and the new test suites

- [ ] **Step 1: Update TECHNICAL.md**

In the image-to-practice paragraph (~line 382), after `ImageStepGenerator` … `VisionPracticeClient`, add one sentence:

`三个 AI Client 经 SkillRegistry 取冻结 Prompt，经 AITransport 发送 chat/completions；输出仍走既有 Draft.normalize。记忆权限字段已在 Skill 定义上默认拒绝，本轮无 Memory 运行时。`

In §8 test table, add rows:

```
| `SkillRegistryTests` | 内置三 id、version 1.0.0、记忆默认拒绝、缺 id 为 nil |
| `AITransportTests` | URL 拼接、fence、401、非法 chat JSON、timeout、response_format 只降级一次 |
```

- [ ] **Step 2: Update TEST_PLAN_CLI.md**

In Step B suite table, add the same two rows after `VisionPracticeClientTests`.

- [ ] **Step 3: Mark the spec approved**

Change the spec header from `Draft — awaiting user review` to `Approved — implementation plan ready`.

- [ ] **Step 4: Commit**

```bash
git add foxgita/docs/TECHNICAL.md \
  foxgita/docs/TEST_PLAN_CLI.md \
  foxgita/docs/superpowers/2026-08-20-ai-skills-foundation/specs/2026-08-20-ai-skills-foundation-design.md
git commit -m "$(cat <<'EOF'
Document SkillRegistry and AITransport in the test plan.

EOF
)"
```

---

## Self-review

**Spec coverage**

| Spec section | Task |
|---|---|
| Frozen prompts Appendix A | Task 2 tests + SkillDefinition constants |
| Registry missing id → zero network | Tasks 4–6 unregistered tests |
| Memory deny fields, no runtime Memory | Task 2 |
| Transport URL / Bearer / fence / retry | Task 3 |
| Empty check before fence strip | Task 3 return unstripped; Task 4 parse; Task 7 |
| Image emptyContent vs review/video invalidJSON | Tasks 4–6 |
| Timeout unification | Task 3 + Tasks 4–5 new tests; Task 6 existing |
| Video 180s timeoutInterval | Task 6 existing `generateDiagnosisSetsLongRequestTimeout` |
| Keep Generator / View / Schema | never touched except Task 1 switch |
| Request snapshots | Tasks 4–6 |
| Docs | Task 8 |

**Placeholder scan:** none. Prompt strings are inlined. Commands are exact.

**Type consistency:** `complete(...) async throws -> String`, `SkillRegistry.skill(id:) -> SkillDefinition?`, `init(session:registry:)`, `VisionPracticeError.unregisteredSkill` used the same way in Tasks 1 and 4–6.
