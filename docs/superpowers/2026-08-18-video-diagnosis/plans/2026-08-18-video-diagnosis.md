# Video Segment Diagnosis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade video review from three sentences to timestamped findings, show Figma C2/04 while analyzing, then C2/05 for playback and clip seek — without uploading the `.mov`.

**Architecture:** Keep `ReviewJobRunner` sequential jobs. Audio still uses `MediaReviewGenerator` → `MediaReviewDraft`. Video uses a new `VideoDiagnosisGenerator` (denser JPEG frames + optional waveform) → `VideoDiagnosisDraft` written onto `RecordingRef.reviewFindingsJSON`. Practice detail presents `VideoAnalysisView` on ingest; when that clip becomes `ready` and the user is still on the page, present `VideoDiagnosisView`.

**Tech Stack:** SwiftUI · SwiftData Schema V5 · AVFoundation · AVKit · URLSession · existing `LLMCredentialsStore` / `PracticeImageCodec` · Swift Testing

## Global Constraints

- Spec: `docs/superpowers/2026-08-18-video-diagnosis/specs/2026-08-18-video-diagnosis-design.md`
- iOS 18+ · Scheme `foxgita` · cwd `foxgita/`
- Do not upload `.mov` / `.m4a`. JPEG only, in memory, discarded after the request
- Do not change `VisionPracticeClient` prompts or `MediaReviewDraft` audio contract
- Same Base URL / Model / Key as photo-to-practice
- Copy: `zh-Hans` via `String(localized:)`
- Trigger stays clip-cards: enqueue on ingest; complete does not present analysis or re-enqueue
- C2/04 three rows are local stage UI, not three HTTP calls
- Unit test command:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

- Do not log API keys or media bytes; do not commit secrets
- YAGNI: no album upload, no C2/01–03, no C2/06, no custom camera

## File map

| File | Responsibility |
|---|---|
| `foxgita/Services/VideoDiagnosisDraft.swift` | `VideoFinding`, draft, `normalize` |
| `foxgita/Services/VideoDiagnosisClient.swift` | chat/completions → diagnosis JSON |
| `foxgita/Services/VideoFrameSampler.swift` | Pure sample-time list (max 10, ≥3) |
| `foxgita/Models/Models.swift` | Schema V5 + `reviewFindingsJSON` |
| `foxgita/foxgitaApp.swift` | V5 container; inject video generator |
| `foxgita/Services/PracticeStore.swift` | `applyVideoDiagnosis`; clear JSON on pending/fail |
| `foxgita/Services/MediaReviewGenerator.swift` | Denser video frames + optional waveform |
| `foxgita/Services/VideoDiagnosisGenerator.swift` | Configure, prepare images, call client, normalize |
| `foxgita/Services/ReviewJobRunner.swift` | `.mov` → video generator |
| `foxgita/Features/Practice/VideoAnalysisView.swift` | C2/04 + S2 |
| `foxgita/Features/Practice/VideoDiagnosisView.swift` | C2/05 player / timeline / clip |
| `foxgita/Features/Practice/PracticeDetailView.swift` | Present analysis on video ingest; clip card「查看诊断」 |
| `foxgita/Features/Record/RecordDetailView.swift` | Video review card |
| `docs/TECHNICAL.md` · `docs/TEST_PLAN_CLI.md` | V5 + new suites |
| Tests under `foxgitaTests/` | Draft, client, sampler, store, generator, runner, migration |

---

### Task 1: VideoDiagnosisDraft normalize

**Files:**
- Create: `foxgita/Services/VideoDiagnosisDraft.swift`
- Test: `foxgitaTests/VideoDiagnosisDraftTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `enum VideoDiagnosisDraftError: Error, Equatable` with `emptyField`
  - `struct VideoFinding: Equatable, Sendable, Codable` with `startSec: Int`, `endSec: Int`, `title: String`, `evidence: String`, `cause: String`, `action: String`
  - `struct VideoDiagnosisDraft: Equatable, Sendable` with `highlight`, `focus`, `nextAction`, `findings: [VideoFinding]`
  - `struct VideoDiagnosisDraft.Raw: Decodable` with optional summary fields and `findings: [RawFinding]?`
  - `struct VideoDiagnosisDraft.RawFinding: Decodable` with optional `startSec: Int?`, `endSec: Int?`, strings
  - `static func normalize(_ raw: Raw, durationSec: Int) throws -> VideoDiagnosisDraft`

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/VideoDiagnosisDraftTests.swift`:

```swift
import Testing
@testable import foxgita

struct VideoDiagnosisDraftTests {
    @Test func normalizeHappyPathClampsAndSorts() throws {
        let draft = try VideoDiagnosisDraft.normalize(
            .init(
                highlight: " 稳 ",
                focus: " F ",
                nextAction: " 慢练 ",
                findings: [
                    .init(
                        startSec: 240, endSec: 200,
                        title: " 切换迟缓 ", evidence: "听到断音",
                        cause: "抬指高", action: "提前准备"
                    ),
                    .init(
                        startSec: 10, endSec: 40,
                        title: "节奏偏慢", evidence: "拍点落后",
                        cause: "抢看谱", action: "跟着节拍器"
                    ),
                ]
            ),
            durationSec: 180
        )
        #expect(draft.highlight == "稳")
        #expect(draft.findings.count == 2)
        #expect(draft.findings[0].startSec == 10)
        #expect(draft.findings[1].startSec == 180)
        #expect(draft.findings[1].endSec == 180)
        #expect(draft.findings[0].endSec - draft.findings[0].startSec >= 10)
        #expect(draft.findings[0].endSec - draft.findings[0].startSec <= 30)
    }

    @Test func normalizeDropsIncompleteFindingsAndAllowsEmpty() throws {
        let draft = try VideoDiagnosisDraft.normalize(
            .init(
                highlight: "稳", focus: "无明确问题", nextAction: "保持",
                findings: [
                    .init(startSec: 1, endSec: 20, title: "", evidence: "x", cause: "y", action: "z"),
                ]
            ),
            durationSec: 60
        )
        #expect(draft.findings.isEmpty)
    }

    @Test func normalizeRejectsEmptySummary() {
        #expect(throws: VideoDiagnosisDraftError.emptyField) {
            try VideoDiagnosisDraft.normalize(
                .init(highlight: " ", focus: "a", nextAction: "b", findings: nil),
                durationSec: 30
            )
        }
    }

    @Test func normalizeCapsFiveFindingsAndTruncates() throws {
        let items = (0..<8).map { i in
            VideoDiagnosisDraft.RawFinding(
                startSec: i * 10, endSec: i * 10 + 15,
                title: "t\(i)", evidence: "e", cause: "c", action: "a"
            )
        }
        let long = String(repeating: "字", count: 90)
        let draft = try VideoDiagnosisDraft.normalize(
            .init(highlight: long, focus: "f", nextAction: "n", findings: items),
            durationSec: 400
        )
        #expect(draft.findings.count == 5)
        #expect(draft.highlight.count == 80)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/VideoDiagnosisDraftTests test
```

Expected: FAIL (`VideoDiagnosisDraft` missing).

- [ ] **Step 3: Implement**

Create `foxgita/Services/VideoDiagnosisDraft.swift`:

```swift
import Foundation

enum VideoDiagnosisDraftError: Error, Equatable {
    case emptyField
}

struct VideoFinding: Equatable, Sendable, Codable {
    var startSec: Int
    var endSec: Int
    var title: String
    var evidence: String
    var cause: String
    var action: String
}

struct VideoDiagnosisDraft: Equatable, Sendable {
    var highlight: String
    var focus: String
    var nextAction: String
    var findings: [VideoFinding]

    struct RawFinding: Decodable, Equatable {
        var startSec: Int?
        var endSec: Int?
        var title: String?
        var evidence: String?
        var cause: String?
        var action: String?
    }

    struct Raw: Decodable, Equatable {
        var highlight: String?
        var focus: String?
        var nextAction: String?
        var findings: [RawFinding]?
    }

    static func normalize(_ raw: Raw, durationSec: Int) throws -> VideoDiagnosisDraft {
        let highlight = clampText(raw.highlight)
        let focus = clampText(raw.focus)
        let nextAction = clampText(raw.nextAction)
        guard !highlight.isEmpty, !focus.isEmpty, !nextAction.isEmpty else {
            throw VideoDiagnosisDraftError.emptyField
        }
        let duration = max(durationSec, 0)
        var findings: [VideoFinding] = []
        for item in raw.findings ?? [] {
            let title = clampText(item.title)
            let evidence = clampText(item.evidence)
            let cause = clampText(item.cause)
            let action = clampText(item.action)
            guard !title.isEmpty, !evidence.isEmpty, !cause.isEmpty, !action.isEmpty else {
                continue
            }
            let window = clipWindow(
                start: item.startSec ?? 0,
                end: item.endSec ?? 0,
                durationSec: duration
            )
            findings.append(
                VideoFinding(
                    startSec: window.start,
                    endSec: window.end,
                    title: title,
                    evidence: evidence,
                    cause: cause,
                    action: action
                )
            )
        }
        findings.sort { $0.startSec < $1.startSec }
        if findings.count > 5 {
            findings = Array(findings.prefix(5))
        }
        return VideoDiagnosisDraft(
            highlight: highlight, focus: focus, nextAction: nextAction, findings: findings
        )
    }

    static func clipWindow(start: Int, end: Int, durationSec: Int) -> (start: Int, end: Int) {
        let duration = max(durationSec, 0)
        var s = min(max(start, 0), duration)
        var e = min(max(end, 0), duration)
        if e <= s {
            e = min(s + 20, duration)
        }
        var length = e - s
        length = min(max(length, 10), 30)
        e = min(s + length, duration)
        if duration - s < 10 {
            e = duration
        }
        if e < s { e = s }
        return (s, e)
    }

    private static func clampText(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= 80 ? trimmed : String(trimmed.prefix(80))
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/VideoDiagnosisDraft.swift foxgitaTests/VideoDiagnosisDraftTests.swift
git commit -m "feat: normalize timestamped video diagnosis drafts"
```

---

### Task 2: VideoDiagnosisClient

**Files:**
- Create: `foxgita/Services/VideoDiagnosisClient.swift`
- Test: `foxgitaTests/VideoDiagnosisClientTests.swift`

**Interfaces:**
- Consumes: `VideoDiagnosisDraft`, `VisionPracticeClient.completionsURL(from:)`, `VisionPracticeError`
- Produces:
  - `protocol VideoDiagnosing: Sendable` with

```swift
func generateDiagnosis(
    baseURL: String,
    model: String,
    apiKey: String,
    imageJPEGData: [Data],
    contextText: String,
    durationSec: Int
) async throws -> VideoDiagnosisDraft
```

  - `struct VideoDiagnosisClient: VideoDiagnosing`

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/VideoDiagnosisClientTests.swift`. Use a **separate** URLProtocol named `DiagnosisMockURLProtocol` (copy the lock/handler pattern from `ReviewMockURLProtocol` in `MediaReviewClientTests.swift` — do not share that type).

```swift
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
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/VideoDiagnosisClientTests test
```

Expected: FAIL (`VideoDiagnosisClient` missing).

- [ ] **Step 3: Implement**

Create `foxgita/Services/VideoDiagnosisClient.swift`:

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
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateDiagnosis(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        contextText: String,
        durationSec: Int
    ) async throws -> VideoDiagnosisDraft {
        guard let url = VisionPracticeClient.completionsURL(from: baseURL) else {
            throw VisionPracticeError.invalidURL
        }
        do {
            return try await perform(
                url: url, model: model, apiKey: apiKey,
                imageJPEGData: imageJPEGData, contextText: contextText,
                durationSec: durationSec,
                includeResponseFormat: true, allowFormatRetry: true
            )
        } catch let error as VisionPracticeError {
            throw error
        } catch {
            throw VisionPracticeError.transport
        }
    }

    private func perform(
        url: URL, model: String, apiKey: String,
        imageJPEGData: [Data], contextText: String, durationSec: Int,
        includeResponseFormat: Bool, allowFormatRetry: Bool
    ) async throws -> VideoDiagnosisDraft {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.buildBody(
            model: model, imageJPEGData: imageJPEGData, contextText: contextText,
            includeResponseFormat: includeResponseFormat
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw VisionPracticeError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            throw VisionPracticeError.transport
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw VisionPracticeError.unauthorized
        }
        if !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8)?.lowercased() ?? ""
            if allowFormatRetry, includeResponseFormat,
               (400...499).contains(http.statusCode),
               bodyText.contains("response_format") || bodyText.contains("unknown") {
                return try await perform(
                    url: url, model: model, apiKey: apiKey,
                    imageJPEGData: imageJPEGData, contextText: contextText,
                    durationSec: durationSec,
                    includeResponseFormat: false, allowFormatRetry: false
                )
            }
            throw VisionPracticeError.httpStatus(http.statusCode)
        }
        return try Self.parseDraft(from: data, durationSec: durationSec)
    }

    private static func buildBody(
        model: String, imageJPEGData: [Data], contextText: String, includeResponseFormat: Bool
    ) throws -> Data {
        var userContent: [[String: Any]] = [["type": "text", "text": contextText]]
        for data in imageJPEGData {
            userContent.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"],
            ])
        }
        var body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    你是吉他练习诊断教练。根据练习录像关键帧和可选波形，给出可定位的分段诊断。只返回 JSON，不要 markdown。
                    字段：highlight、focus、nextAction（各一句话），findings（数组，可空）。
                    每条 finding 字段：startSec、endSec（整数秒，必须落在 0 到视频时长之间）、title、evidence、cause、action。
                    evidence 写看到或听到的具体现象。证据不足就少写或不写 finding，不要编造时间点，不要承诺精确音准鉴定。最多 5 条。
                    """,
                ],
                ["role": "user", "content": userContent],
            ],
        ]
        if includeResponseFormat {
            body["response_format"] = ["type": "json_object"]
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private static func parseDraft(from data: Data, durationSec: Int) throws -> VideoDiagnosisDraft {
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { var content: String? }
                var message: Message?
            }
            var choices: [Choice]?
        }
        let chat = (try? JSONDecoder().decode(ChatResponse.self, from: data))
        let content = chat?.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { throw VisionPracticeError.invalidJSON }
        var s = content
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if s.hasSuffix("```") { s.removeLast(3) }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let jsonData = s.data(using: .utf8),
              let raw = try? JSONDecoder().decode(VideoDiagnosisDraft.Raw.self, from: jsonData),
              let draft = try? VideoDiagnosisDraft.normalize(raw, durationSec: durationSec)
        else {
            throw VisionPracticeError.invalidJSON
        }
        return draft
    }
}
```

401/403 → `.unauthorized`. Empty/unparseable/empty-field normalize → `.invalidJSON`.

- [ ] **Step 4: Run tests — expect PASS**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/VideoDiagnosisClient.swift foxgitaTests/VideoDiagnosisClientTests.swift
git commit -m "feat: add OpenAI-compatible VideoDiagnosisClient"
```

---

### Task 3: Schema V5

**Files:**
- Modify: `foxgita/Models/Models.swift`
- Modify: `foxgita/foxgitaApp.swift` (schema version only)
- Test: `foxgitaTests/MigrationTests.swift`

**Interfaces:**
- Consumes: `GitaSchemaV4`, `VideoFinding`
- Produces:
  - `typealias TaskItem/PracticeSession/RecordingRef = GitaSchemaV5.*`
  - `GitaSchemaV5.RecordingRef.reviewFindingsJSON: String = "[]"`
  - computed `videoFindings: [VideoFinding]`
  - `GitaMigrationPlan.schemas` includes V5; lightweight V4→V5

- [ ] **Step 1: Write the failing tests**

In `foxgitaTests/MigrationTests.swift`, change `v2StoreMigratesToV3WithoutLosingRows` Phase 2 from `GitaSchemaV4` to `GitaSchemaV5` so V2→V3→V4→V5 runs. After existing recording asserts, add:

```swift
#expect(recordings[0].videoFindings.isEmpty)
```

Change `v3StoreMigratesToV4WithEmptyReview` to reopen under **V5** (keep the V3 write phase). After `reviewStatus == .none`, add `#expect(recordings[0].videoFindings.isEmpty)`.

Add:

```swift
@Test func v4StoreMigratesToV5WithEmptyFindings() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("gita-v4-v5-\(UUID().uuidString).store")
    defer { try? FileManager.default.removeItem(at: url) }

    do {
        let v4Schema = Schema(versionedSchema: GitaSchemaV4.self)
        let config = ModelConfiguration(schema: v4Schema, url: url)
        let container = try ModelContainer(for: v4Schema, configurations: [config])
        let context = ModelContext(container)
        let session = GitaSchemaV4.PracticeSession(
            id: "s1", taskId: "warm", taskTitle: "指尖热身",
            category: .left, startedAt: Date(), endedAt: Date(),
            durationSec: 60, bpm: 80, timeSig: "4/4",
            steps: ["开放弦"], noteText: ""
        )
        let rec = GitaSchemaV4.RecordingRef(
            id: "r1", fileName: "clip.mov", bytes: 100, durationSec: 12,
            createdAt: Date(), label: "录像"
        )
        rec.reviewStatus = .ready
        rec.reviewHighlight = "稳"
        rec.reviewFocus = "F"
        rec.reviewNextAction = "慢练"
        session.recordings.append(rec)
        context.insert(session)
        try context.save()
    }

    let v5Schema = Schema(versionedSchema: GitaSchemaV5.self)
    let config = ModelConfiguration(schema: v5Schema, url: url)
    let container = try ModelContainer(
        for: v5Schema, migrationPlan: GitaMigrationPlan.self, configurations: [config]
    )
    let recordings = try ModelContext(container).fetch(FetchDescriptor<RecordingRef>())
    #expect(recordings.count == 1)
    #expect(recordings[0].reviewHighlight == "稳")
    #expect(recordings[0].videoFindings.isEmpty)
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MigrationTests test
```

Expected: FAIL (`GitaSchemaV5` missing).

- [ ] **Step 3: Implement**

In `foxgita/Models/Models.swift`:

1. Keep `GitaSchemaV4` as-is (needed for migration).
2. Add `enum GitaSchemaV5: VersionedSchema` with `versionIdentifier = Schema.Version(5, 0, 0)`.
3. Copy `TaskItem` and `PracticeSession` from V4 into V5. `PracticeSession.recordings` inverse must point at `GitaSchemaV5.RecordingRef`.
4. Copy `RecordingRef` and add:

```swift
var reviewFindingsJSON: String = "[]"

var videoFindings: [VideoFinding] {
    get {
        guard let data = reviewFindingsJSON.data(using: .utf8),
              let value = try? JSONDecoder().decode([VideoFinding].self, from: data) else {
            return []
        }
        return value
    }
    set {
        reviewFindingsJSON =
            (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
    }
}
```

5. Point typealiases at V5.
6. Migration plan:

```swift
static var schemas: [any VersionedSchema.Type] {
    [GitaSchemaV2.self, GitaSchemaV3.self, GitaSchemaV4.self, GitaSchemaV5.self]
}
static var stages: [MigrationStage] {
    [
        .lightweight(fromVersion: GitaSchemaV2.self, toVersion: GitaSchemaV3.self),
        .lightweight(fromVersion: GitaSchemaV3.self, toVersion: GitaSchemaV4.self),
        .lightweight(fromVersion: GitaSchemaV4.self, toVersion: GitaSchemaV5.self),
    ]
}
```

7. In `foxgitaApp.swift` init, use `GitaSchemaV5.self`.

- [ ] **Step 4: Run tests — expect PASS**

Same MigrationTests command. Also run `foxgitaTests` once to catch typealias breakage. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Models/Models.swift foxgita/foxgitaApp.swift foxgitaTests/MigrationTests.swift
git commit -m "feat: add Schema V5 findings JSON on RecordingRef"
```

---

### Task 4: PracticeStore video diagnosis writes

**Files:**
- Modify: `foxgita/Services/PracticeStore.swift`
- Test: `foxgitaTests/PracticeStoreTests.swift`

**Interfaces:**
- Consumes: `VideoDiagnosisDraft`, `RecordingRef.videoFindings`
- Produces:

```swift
extension PracticeStore {
    func applyVideoDiagnosis(recordingId: String, draft: VideoDiagnosisDraft)
}
```

`markReviewsPending` / `markReviewsFailed` must also set `videoFindings = []` (via the setter, which writes `reviewFindingsJSON`). `applyReview` (audio) also sets `videoFindings = []` so a misclassified retry cannot leave stale JSON. Missing id is skipped.

- [ ] **Step 1: Write the failing tests**

Add to `PracticeStoreTests.swift` (same seed/`finishSession` pattern as `applyReviewWritesThreeFields`):

```swift
@Test func applyVideoDiagnosisWritesFindingsAndSummary() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedActive(into: repo)
    let now = Date()
    #expect(store.finishSession(
        taskId: "warm", steps: ["慢速"], note: "笔记",
        startedAt: now, endedAt: now, durationSec: 60, bpm: 80, recordings: []
    ))
    let session = try repo.sessions()[0]
    session.recordings.append(RecordingRef(id: "clip-v", fileName: "y.mov", bytes: 2, durationSec: 40))
    try repo.save()

    store.applyVideoDiagnosis(
        recordingId: "clip-v",
        draft: VideoDiagnosisDraft(
            highlight: "稳", focus: "F", nextAction: "70",
            findings: [
                VideoFinding(
                    startSec: 8, endSec: 28, title: "按弦",
                    evidence: "杂音", cause: "离品丝", action: "靠近"
                )
            ]
        )
    )
    let rec = try #require(try repo.recording(id: "clip-v"))
    #expect(rec.reviewStatus == .ready)
    #expect(rec.reviewFocus == "F")
    #expect(rec.videoFindings.count == 1)
    #expect(rec.videoFindings[0].startSec == 8)
}

@Test func markPendingClearsFindingsJSON() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedActive(into: repo)
    let now = Date()
    #expect(store.finishSession(
        taskId: "warm", steps: ["a"], note: "n",
        startedAt: now, endedAt: now, durationSec: 60, bpm: 72, recordings: []
    ))
    let session = try repo.sessions()[0]
    let rec = RecordingRef(id: "clip-p", fileName: "x.mov", bytes: 1, durationSec: 8)
    rec.reviewStatus = .ready
    rec.videoFindings = [
        VideoFinding(startSec: 0, endSec: 10, title: "t", evidence: "e", cause: "c", action: "a")
    ]
    session.recordings.append(rec)
    try repo.save()

    store.markReviewsPending(recordingIds: ["clip-p"])
    let after = try #require(try repo.recording(id: "clip-p"))
    #expect(after.reviewStatus == .pending)
    #expect(after.videoFindings.isEmpty)
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

Expected: FAIL (`applyVideoDiagnosis` missing).

- [ ] **Step 3: Implement**

```swift
func applyVideoDiagnosis(recordingId: String, draft: VideoDiagnosisDraft) {
    perform {
        if let rec = try repository.recording(id: recordingId) {
            rec.reviewStatus = .ready
            rec.reviewHighlight = draft.highlight
            rec.reviewFocus = draft.focus
            rec.reviewNextAction = draft.nextAction
            rec.videoFindings = draft.findings
            rec.updatedAt = Date()
            rec.syncState = .local
        }
        try repository.save()
    }
}
```

In `markReviewsPending`, `markReviewsFailed`, and `applyReview`, after clearing/writing the three strings, set `rec.videoFindings = []` (for `applyReview` only — audio must not keep video JSON).

- [ ] **Step 4: Run tests — expect PASS**

Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeStore.swift foxgitaTests/PracticeStoreTests.swift
git commit -m "feat: persist video findings JSON on RecordingRef"
```

---

### Task 5: VideoFrameSampler + denser video JPEGs

**Files:**
- Create: `foxgita/Services/VideoFrameSampler.swift`
- Modify: `foxgita/Services/MediaReviewGenerator.swift` (`FileMediaImagePreparer.videoFrames`)
- Test: `foxgitaTests/VideoFrameSamplerTests.swift`

**Interfaces:**
- Consumes: duration in seconds
- Produces:

```swift
enum VideoFrameSampler {
    static func sampleSeconds(duration: Double, interval: Double = 8, maxCount: Int = 10) -> [Double]
}
```

Rules: always include 0, 50%, ~100% (`duration * 0.98`); add times at `interval` seconds; unique; sorted; cap `maxCount`. If `duration <= 0`, return `[0]`.

Video frames: map those seconds to `CMTime` (timescale 600). After frames, if `AVAudioFile(forReading: url)` succeeds, append one waveform JPEG using existing `waveformJPEG`; if it throws, skip waveform (do not fail). Still fail if **zero** frames.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import foxgita

struct VideoFrameSamplerTests {
    @Test func shortClipStillHasThreeAnchors() {
        let times = VideoFrameSampler.sampleSeconds(duration: 12)
        #expect(times.count == 3)
        #expect(times.first == 0)
        #expect(times.contains { abs($0 - 6) < 0.01 })
    }

    @Test func longClipCapsAtTenAndIncludesInterval() {
        let times = VideoFrameSampler.sampleSeconds(duration: 480)
        #expect(times.count == 10)
        #expect(times.contains(8))
        #expect(times.first == 0)
        #expect(times.last! > 400)
    }

    @Test func zeroDurationReturnsZero() {
        #expect(VideoFrameSampler.sampleSeconds(duration: 0) == [0])
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/VideoFrameSamplerTests test
```

Expected: FAIL (`VideoFrameSampler` missing).

- [ ] **Step 3: Implement sampler + preparer**

`VideoFrameSampler.swift`:

```swift
import Foundation

enum VideoFrameSampler {
    static func sampleSeconds(duration: Double, interval: Double = 8, maxCount: Int = 10) -> [Double] {
        guard duration > 0, duration.isFinite else { return [0] }
        var set: Set<Int> = [0]
        set.insert(Int((duration * 0.5).rounded()))
        set.insert(Int((duration * 0.98).rounded()))
        var t = interval
        while t < duration, set.count < maxCount {
            set.insert(Int(t.rounded()))
            t += interval
        }
        var seconds = set.map { min(Double($0), duration) }.sorted()
        if seconds.count > maxCount {
            seconds = Array(seconds.prefix(maxCount - 1)) + [seconds.last!]
        }
        return seconds
    }
}
```

Replace `FileMediaImagePreparer.videoFrames` time list with:

```swift
let seconds = durationSeconds(asset)
let sample = VideoFrameSampler.sampleSeconds(duration: seconds)
let times = sample.map { CMTime(seconds: $0, preferredTimescale: 600) }
```

After collecting `jpegs` from frames (still throw `prepareFailed` if empty), try:

```swift
if let wave = try? waveformJPEG(url: url) {
    jpegs.append(wave)
}
```

Do not let waveform failure fail the whole prepare.

- [ ] **Step 4: Run tests — expect PASS**

Sampler tests PASS. Also run `MediaReviewGeneratorTests` to confirm existing stubs still compile. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/VideoFrameSampler.swift \
  foxgita/Services/MediaReviewGenerator.swift \
  foxgitaTests/VideoFrameSamplerTests.swift
git commit -m "feat: sample denser video frames for diagnosis"
```

---

### Task 6: VideoDiagnosisGenerator

**Files:**
- Create: `foxgita/Services/VideoDiagnosisGenerator.swift`
- Test: `foxgitaTests/VideoDiagnosisGeneratorTests.swift`

**Interfaces:**
- Consumes: `VideoDiagnosing`, `LLMCredentialsStore`, `MediaImagePreparing`, `MediaReviewContext`
- Produces:

```swift
protocol VideoDiagnosisGenerating: Sendable {
    func diagnose(
        _ context: MediaReviewContext, baseURL: String, model: String
    ) async throws -> VideoDiagnosisDraft
}

@MainActor
final class VideoDiagnosisGenerator: VideoDiagnosisGenerating {
    init(
        client: any VideoDiagnosing,
        credentials: LLMCredentialsStore = LLMCredentialsStore(),
        images: any MediaImagePreparing = FileMediaImagePreparer()
    )
}
```

Same error mapping as `MediaReviewGenerator` (`notConfigured`, `fileMissing`, `prepareFailed`, `failed(VisionPracticeError)`). `contextText` = `MediaReviewGenerator.contextText(from:)` (already includes 媒介：录像 when `.mov`).

- [ ] **Step 1: Write the failing tests**

Copy the three cases from `MediaReviewGeneratorTests` (`notConfigured`, `prepareFailedMaps`, `clientUnauthorizedMaps`) but:

- Types: `StubClient: VideoDiagnosing` returning `VideoDiagnosisDraft` / throwing `VisionPracticeError`
- SUT: `VideoDiagnosisGenerator`
- Method: `diagnose`

Unauthorized maps to `MediaReviewGeneratorError.failed(.unauthorized)`.

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/VideoDiagnosisGeneratorTests test
```

Expected: FAIL (types missing).

- [ ] **Step 3: Implement** `foxgita/Services/VideoDiagnosisGenerator.swift`:

```swift
import Foundation

protocol VideoDiagnosisGenerating: Sendable {
    func diagnose(
        _ context: MediaReviewContext, baseURL: String, model: String
    ) async throws -> VideoDiagnosisDraft
}

@MainActor
final class VideoDiagnosisGenerator: VideoDiagnosisGenerating {
    private let client: any VideoDiagnosing
    private let credentials: LLMCredentialsStore
    private let images: any MediaImagePreparing

    init(
        client: any VideoDiagnosing,
        credentials: LLMCredentialsStore = LLMCredentialsStore(),
        images: any MediaImagePreparing = FileMediaImagePreparer()
    ) {
        self.client = client
        self.credentials = credentials
        self.images = images
    }

    func diagnose(
        _ context: MediaReviewContext, baseURL: String, model: String
    ) async throws -> VideoDiagnosisDraft {
        guard credentials.isConfigured(baseURL: baseURL, model: model) else {
            throw MediaReviewGeneratorError.notConfigured
        }
        guard let apiKey = credentials.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            throw MediaReviewGeneratorError.notConfigured
        }
        let jpegs: [Data]
        do {
            let preparer = images
            let name = context.fileName
            jpegs = try await Task.detached { try preparer.jpegImages(fileName: name) }.value
        } catch let error as MediaReviewGeneratorError {
            throw error
        } catch {
            throw MediaReviewGeneratorError.prepareFailed
        }
        guard !jpegs.isEmpty else { throw MediaReviewGeneratorError.prepareFailed }
        do {
            return try await client.generateDiagnosis(
                baseURL: baseURL,
                model: model,
                apiKey: apiKey,
                imageJPEGData: jpegs,
                contextText: MediaReviewGenerator.contextText(from: context),
                durationSec: context.durationSec
            )
        } catch let error as VisionPracticeError {
            throw MediaReviewGeneratorError.failed(error)
        } catch let error as MediaReviewGeneratorError {
            throw error
        } catch {
            throw MediaReviewGeneratorError.failed(.transport)
        }
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/VideoDiagnosisGenerator.swift foxgitaTests/VideoDiagnosisGeneratorTests.swift
git commit -m "feat: generate video diagnosis from frames"
```

---

### Task 7: ReviewJobRunner video branch

**Files:**
- Modify: `foxgita/Services/ReviewJobRunner.swift`
- Modify: `foxgita/foxgitaApp.swift`
- Test: `foxgitaTests/ReviewJobRunnerTests.swift`

**Interfaces:**
- Consumes: `VideoDiagnosisGenerating`, `PracticeStore.applyVideoDiagnosis`
- Produces:

```swift
enum ReviewFailureKind: Equatable, Sendable {
    case prepare, network, parse, unauthorized
}

@Observable
@MainActor
final class ReviewJobRunner {
    init(
        store: PracticeStore,
        generator: any MediaReviewGenerating,
        videoGenerator: any VideoDiagnosisGenerating
    )
    private(set) var lastFailureKind: ReviewFailureKind?
}
```

In `processCurrentJob`, after `reviewContext`:

- If `MediaReviewMedia.isVideo(fileName: context.fileName)`: `videoGenerator.diagnose` → `applyVideoDiagnosis`
- Else: existing `generator.review` → `applyReview`

Map errors to `lastFailureKind` before `markReviewsFailed`:

- `fileMissing` / `prepareFailed` → `.prepare`
- `failed(.unauthorized)` → `.unauthorized` (still fails rest of batch)
- `failed(.invalidJSON)` → `.parse`
- other `failed` / unknown → `.network`

Existing audio tests must still pass: update `harness()` to pass a `VideoSpy` that throws `prepareFailed` if called. Add one test with a `.mov` recording:

```swift
@Test func videoClipWritesFindings() async throws {
    let (runner, _, repo, _, videoSpy) = try harness()
    let session = try repo.sessions()[0]
    session.recordings.append(RecordingRef(id: "v1", fileName: "v1.mov", bytes: 1, durationSec: 20))
    try repo.save()
    videoSpy.drafts = [
        "v1": .success(
            .init(
                highlight: "h", focus: "f", nextAction: "n",
                findings: [
                    VideoFinding(
                        startSec: 2, endSec: 18, title: "t",
                        evidence: "e", cause: "c", action: "a"
                    )
                ]
            )
        )
    ]
    runner.enqueue(["v1"], baseURL: "https://x", model: "m")
    try await waitUntil {
        (try? repo.recording(id: "v1")?.reviewStatus) == .ready
    }
    #expect(try repo.recording(id: "v1")?.videoFindings.count == 1)
    #expect(videoSpy.order == ["v1"])
}
```

`VideoSpy` mirrors `RecordingSpy` with `VideoDiagnosisGenerating`.

`foxgitaApp` runner init:

```swift
ReviewJobRunner(
    store: store,
    generator: MediaReviewGenerator(client: MediaReviewClient()),
    videoGenerator: VideoDiagnosisGenerator(client: VideoDiagnosisClient())
)
```

- [ ] **Step 1: Write the failing test** (`videoClipWritesFindings`) and compile-fix `harness` signature. Expect FAIL on missing `videoGenerator` parameter / findings not written.

- [ ] **Step 2: Run `ReviewJobRunnerTests` — expect FAIL**

- [ ] **Step 3: Implement runner branch + app injection**

- [ ] **Step 4: Run `ReviewJobRunnerTests` — expect PASS** (old three tests + new video test)

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/ReviewJobRunner.swift foxgita/foxgitaApp.swift \
  foxgitaTests/ReviewJobRunnerTests.swift
git commit -m "feat: route video clips through diagnosis generator"
```

---

### Task 8: C2/04 VideoAnalysisView + present on ingest

**Files:**
- Create: `foxgita/Features/Practice/VideoAnalysisView.swift`
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift`

**Interfaces:**
- Consumes: `ReviewJobRunner.isRunning`, `lastFailureKind`, `RecordingRef.reviewStatus`, recording id
- Produces: full-screen C2/04; S2 on `failed`; callbacks `onDismiss` / `onReady`

`VideoAnalysisView(recordingId:taskTitle:durationSec:onDismiss:onReady:)`

UI (Figma C2/04):

- Top: 返回 ·「AI 分段分析」
- Subtitle: `"\(taskTitle) · 本次练习 \(mmss)"` where `mmss` uses `durationSec`
- Card: title「正在按片段分析声音与手型」; orange/gray bar waveform placeholder; large percent; status line; three rows 前奏 · 节奏与拍点 / 主歌 · 和弦切换 / 副歌 · 动作与指法
- Outline button「后台生成并返回」
- Footer「录制内容已安全保存」

Progress: while `pending && runner.isRunning(id)`, ease a `@State displayPercent` toward 90 (Timer 0.3s, +3). Map rows: `<30` row1 分析中; `<90` row1 完成 row2 分析中; else row1–2 完成 row3 分析中. On `ready`, set 100, all 完成, then `onReady()` once. On `failed`, show S2: title「这次分析未完成」; body from `lastFailureKind` (`.prepare` →「抽帧失败，没有生成分段诊断」; `.parse` →「结果无法解析，没有生成分段诊断」; else Figma「网络中断，没有生成分段诊断」); button「重新分析」calls `markReviewsPending` + `enqueue([id])` and returns to progress; footer「录制内容已安全保存」.

返回 and「后台生成并返回」call `onDismiss()` only. Do **not** `finishSession` or `returnPracticeToToday`.

Wire in `PracticeDetailView`:

```swift
private struct VideoRoute: Identifiable {
    var id: String
}

@State private var analysisRoute: VideoRoute?
@State private var diagnosisRoute: VideoRoute?
```

At end of `persist`, after enqueue, if `MediaReviewMedia.isVideo(fileName: clip.fileName)`:

```swift
analysisRoute = VideoRoute(id: clip.id)
```

```swift
.fullScreenCover(item: $analysisRoute) { route in
    VideoAnalysisView(
        recordingId: route.id,
        taskTitle: task?.title ?? "",
        durationSec: sessions.flatMap(\.recordings).first { $0.id == route.id }?.durationSec ?? clipDurationFallback(route.id),
        onDismiss: { analysisRoute = nil },
        onReady: {
            analysisRoute = nil
            diagnosisRoute = VideoRoute(id: route.id)
        }
    )
}
```

If looking up duration is awkward, pass `clip.durationSec` by storing it on `VideoRoute` (`var durationSec: Int`). Prefer that:

```swift
private struct VideoRoute: Identifiable {
    var id: String
    var durationSec: Int
}
```

- [ ] **Step 1: Add `VideoAnalysisView.swift` with the layout above.** Use `GitaTheme` / `GitaFont` / `PageBackground`. Query recordings with `@Query` filtered in memory by `recordingId`.

- [ ] **Step 2: Present from `persist` only for video + configured AI.**

- [ ] **Step 3: Build**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/ReviewJobRunnerTests test
```

Expected: PASS (compile + runner tests).

- [ ] **Step 4: Commit**

```bash
git add foxgita/Features/Practice/VideoAnalysisView.swift \
  foxgita/Features/Practice/PracticeDetailView.swift
git commit -m "feat: show Figma C2/04 while a video clip is analyzed"
```

---

### Task 9: C2/05 VideoDiagnosisView + 复盘 / 片段卡

**Files:**
- Create: `foxgita/Features/Practice/VideoDiagnosisView.swift`
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift`
- Modify: `foxgita/Features/Record/RecordDetailView.swift`

**Interfaces:**
- Consumes: `RecordingRef` file URL, `videoFindings`, summary fields
- Produces: C2/05; seek full / clip; no C2/06

`VideoDiagnosisView(recordingId:taskTitle:onClose:)`

- Nav: 返回 ·「分段诊断」· 完成 — both call `onClose()` (does not `finishSession`)
- Subtitle: `"\(taskTitle) · \(durationLabel)"`
- `AVPlayer` on `RecordingStore.url(for: fileName)`; overlay current/total and「手部与琴颈回放」
- Timeline: findings positioned at `CGFloat(startSec) / CGFloat(max(durationSec,1))`; selected dot larger; label `"\(mmss) \(title)"`
- Card: title; `"\(evidence) · 原因：\(cause)"`; orange soft block「纠正建议」+ action
- Pills: 时间线 (default) | 总结. Summary replaces timeline+card with three labeled fields (亮点 / 优先改善 / 下次练法). Player stays.
- Buttons: outline「完整回放」seek 0 play; filled「纠正片段」seek `startSec` and pause at `endSec` (use periodic time observer). Disabled when `findings.isEmpty`
- Empty findings: no dots; text「这次没有明确问题」; 纠正片段 disabled

`PracticeDetailView`: `.fullScreenCover(item: $diagnosisRoute)` presents `VideoDiagnosisView`. Clip card: if video && `ready` && `!videoFindings.isEmpty`, button「查看诊断」sets `diagnosisRoute`. If video && `ready` && findings empty, keep expanded 三段 plus the same「查看诊断」(opens summary-only page). Audio unchanged (「查看复盘」expands 三段).

`RecordDetailView.reviewBody` for video `ready`:

- If `!r.videoFindings.isEmpty`: show `focus` + `nextAction` and button「查看诊断」presenting the same `VideoDiagnosisView` via `@State private var diagnosisId: String?`
- If findings empty: existing three fields +「重新分析」(`requestReview`)
- Other statuses unchanged

- [ ] **Step 1: Implement `VideoDiagnosisView`** with AVKit `VideoPlayer` or a small `AVPlayer` UIViewController representable. Pause at clip end with `addPeriodicTimeObserver`.

- [ ] **Step 2: Wire both covers and 复盘 / 片段卡 buttons.**

- [ ] **Step 3: Build**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add foxgita/Features/Practice/VideoDiagnosisView.swift \
  foxgita/Features/Practice/PracticeDetailView.swift \
  foxgita/Features/Record/RecordDetailView.swift \
  foxgita/Localizable.xcstrings
git commit -m "feat: show timestamped video diagnosis and clip playback"
```

---

### Task 10: Docs

**Files:**
- Modify: `docs/TECHNICAL.md`
- Modify: `docs/TEST_PLAN_CLI.md`

**Interfaces:** none

- [ ] **Step 1: TECHNICAL.md** — schema is V5; `RecordingRef.reviewFindingsJSON`; new § on 录像分段诊断 (ingest → C2/04 → Runner video path → C2/05). Note audio path unchanged.

- [ ] **Step 2: TEST_PLAN_CLI.md** — add `VideoDiagnosisDraftTests`, `VideoDiagnosisClientTests`, `VideoFrameSamplerTests`, `VideoDiagnosisGeneratorTests`; MigrationTests now V2→V5 / V4→V5; `ReviewJobRunnerTests` includes video findings.

- [ ] **Step 3: Run unit tests**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add docs/TECHNICAL.md docs/TEST_PLAN_CLI.md
git commit -m "docs: record Schema V5 video diagnosis"
```

---

## Spec coverage self-review

| Spec | Task |
|---|---|
| `VideoDiagnosisDraft.normalize` clamp / drop / max 5 / empty findings + summary | 1 |
| Vision JPEG client, no raw upload | 2, 5, 6 |
| Schema V5 `reviewFindingsJSON` | 3 |
| Store apply / clear JSON | 4 |
| Denser frames + optional waveform | 5 |
| Generator config / prepare / map errors | 6 |
| Runner `.mov` branch, 401 stops batch | 7 |
| C2/04 + S2, ingest present, dismiss ≠ finish | 8 |
| C2/05 timeline / 完整回放 / 纠正片段; 复盘 + 片段卡 | 9 |
| Audio 三段 unchanged | 4 (`applyReview`), 7 (else branch), 9 (audio card) |
| No album / C2/06 / custom camera | not scheduled |
| TECHNICAL + TEST_PLAN | 10 |

**Types:** `VideoFinding`, `VideoDiagnosisDraft`, `VideoDiagnosing`, `VideoDiagnosisGenerating`, `VideoFrameSampler.sampleSeconds`, `PracticeStore.applyVideoDiagnosis`, `ReviewJobRunner.lastFailureKind`, `ReviewFailureKind` — same names in Tasks 1–9.

**No TBD / “handle errors later” / “similar to Task N” without code.**
