# Media Review Implementation Plan

> **功能需求：** [`../specs/2026-08-15-media-review-design.md`](../specs/2026-08-15-media-review-design.md)。本文为逐步施工单。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a practice session with audio/video, analyze each clip through the existing OpenAI-compatible Vision channel and store three review sentences on that `RecordingRef`.

**Architecture:** `finishSession` still persists first. If clips exist and AI is configured, `ReviewJobRunner` (app-scoped) analyzes clips sequentially: waveform or 3 video frames + task text → `MediaReviewClient` → `MediaReviewDraft.normalize` → write back to that `RecordingRef`. The processing sheet only observes progress; Record detail adds a 复盘 tab.

**Tech Stack:** SwiftUI · SwiftData Schema V4 · AVFoundation · URLSession · existing `LLMCredentialsStore` / `PracticeImageCodec` · Swift Testing

## Global Constraints

- Spec: `docs/superpowers/2026-08-15-media-review/specs/2026-08-15-media-review-design.md`
- iOS 18+ · Scheme `foxgita` · new files under `foxgita/` / `foxgitaTests/` auto-join targets
- One review per `RecordingRef`; do not synthesize a session-level review
- Media sent as JPEG only (waveform or ≤3 frames); never upload `.m4a` / `.mov`
- Same Base URL / Model / Key as photo-to-practice; do not change `VisionPracticeClient` prompts
- Copy: `zh-Hans` via `String(localized:)`
- Unit test command (cwd `foxgita/`):

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

- Do not log API keys or media bytes; do not commit secrets
- YAGNI: no realtime coaching, no light-recap sheet, no timeline markers, no「加入下次练习」, no historical backfill

## File map

| File | Responsibility |
|---|---|
| `foxgita/Services/MediaReviewDraft.swift` | Three-field draft + `normalize` |
| `foxgita/Services/MediaReviewClient.swift` | chat/completions for review JSON |
| `foxgita/Models/Models.swift` | `ReviewStatus`, Schema V4, typealiases, migration plan |
| `foxgita/Services/PracticeRepository.swift` | `recording(id:)` |
| `foxgita/Services/PracticeStore.swift` | pending / apply / fail / `reviewContext` |
| `foxgita/Services/MediaReviewGenerator.swift` | Waveform / frames + client call |
| `foxgita/Services/ReviewJobRunner.swift` | Sequential queue; 401 fails rest of job |
| `foxgita/Features/Practice/ReviewGenerationSheet.swift` | Processing UI |
| `foxgita/Features/Practice/PracticeDetailView.swift` | Show sheet after finish |
| `foxgita/foxgitaApp.swift` | V4 container + inject runner |
| `foxgita/Features/Record/RecordDetailView.swift` | 复盘 tab |
| `foxgita/Features/Settings/SettingsView.swift` | Privacy sentence |
| `foxgita/Localizable.xcstrings` | New strings (Xcode may auto-extract) |
| `docs/TECHNICAL.md` | V4 + review note |
| `docs/TEST_PLAN_CLI.md` | New suites |
| `foxgitaTests/MediaReviewDraftTests.swift` | Normalize |
| `foxgitaTests/MediaReviewClientTests.swift` | Mock HTTP |
| `foxgitaTests/MigrationTests.swift` | V2→V4 and V3→V4 |
| `foxgitaTests/PracticeStoreTests.swift` | Review writes |
| `foxgitaTests/MediaReviewGeneratorTests.swift` | Config / prepare / map errors |
| `foxgitaTests/ReviewJobRunnerTests.swift` | Queue / 401 / retry |

---

### Task 1: MediaReviewDraft normalize

**Files:**
- Create: `foxgita/Services/MediaReviewDraft.swift`
- Test: `foxgitaTests/MediaReviewDraftTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `enum MediaReviewDraftError: Error, Equatable` with `emptyField`
  - `struct MediaReviewDraft: Equatable` with `highlight: String`, `focus: String`, `nextAction: String`
  - `struct MediaReviewDraft.Raw: Decodable` with optional `highlight`, `focus`, `nextAction`
  - `static func normalize(_ raw: Raw) throws -> MediaReviewDraft`

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/MediaReviewDraftTests.swift`:

```swift
import Testing
@testable import foxgita

struct MediaReviewDraftTests {
    @Test func normalizeHappyPathTrims() throws {
        let draft = try MediaReviewDraft.normalize(
            .init(highlight: "  节奏稳  ", focus: " F 慢 ", nextAction: " 70 BPM ")
        )
        #expect(draft.highlight == "节奏稳")
        #expect(draft.focus == "F 慢")
        #expect(draft.nextAction == "70 BPM")
    }

    @Test func normalizeRejectsEmptyField() {
        #expect(throws: MediaReviewDraftError.emptyField) {
            try MediaReviewDraft.normalize(
                .init(highlight: "好", focus: "   ", nextAction: "练")
            )
        }
        #expect(throws: MediaReviewDraftError.emptyField) {
            try MediaReviewDraft.normalize(
                .init(highlight: nil, focus: "a", nextAction: "b")
            )
        }
    }

    @Test func normalizeTruncatesTo80Characters() throws {
        let long = String(repeating: "字", count: 90)
        let draft = try MediaReviewDraft.normalize(
            .init(highlight: long, focus: "改", nextAction: "练")
        )
        #expect(draft.highlight.count == 80)
        #expect(draft.highlight == String(repeating: "字", count: 80))
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MediaReviewDraftTests test
```

Expected: FAIL (`MediaReviewDraft` missing).

- [ ] **Step 3: Implement**

Create `foxgita/Services/MediaReviewDraft.swift`:

```swift
import Foundation

enum MediaReviewDraftError: Error, Equatable {
    case emptyField
}

struct MediaReviewDraft: Equatable, Sendable {
    var highlight: String
    var focus: String
    var nextAction: String

    struct Raw: Decodable, Equatable {
        var highlight: String?
        var focus: String?
        var nextAction: String?
    }

    static func normalize(_ raw: Raw) throws -> MediaReviewDraft {
        let highlight = clamp(raw.highlight)
        let focus = clamp(raw.focus)
        let nextAction = clamp(raw.nextAction)
        guard !highlight.isEmpty, !focus.isEmpty, !nextAction.isEmpty else {
            throw MediaReviewDraftError.emptyField
        }
        return MediaReviewDraft(highlight: highlight, focus: focus, nextAction: nextAction)
    }

    private static func clamp(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= 80 ? trimmed : String(trimmed.prefix(80))
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Same `xcodebuild` as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/MediaReviewDraft.swift foxgitaTests/MediaReviewDraftTests.swift
git commit -m "feat: normalize three-field media review drafts"
```

---

### Task 2: MediaReviewClient

**Files:**
- Create: `foxgita/Services/MediaReviewClient.swift`
- Test: `foxgitaTests/MediaReviewClientTests.swift`

**Interfaces:**
- Consumes: `MediaReviewDraft`, `VisionPracticeClient.completionsURL(from:)`, `VisionPracticeError`
- Produces:
  - `protocol MediaReviewing: Sendable` with

```swift
func generateReview(
    baseURL: String,
    model: String,
    apiKey: String,
    imageJPEGData: [Data],
    contextText: String
) async throws -> MediaReviewDraft
```

  - `struct MediaReviewClient: MediaReviewing`

Reuse `VisionPracticeError` (`invalidURL`, `unauthorized`, `httpStatus`, `emptyContent`, `invalidJSON`, `transport`). Do not edit `VisionPracticeClient` prompts.

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/MediaReviewClientTests.swift`. Use a **separate** URLProtocol so it does not race `MockURLProtocol` in `VisionPracticeClientTests.swift`:

```swift
import Foundation
import Testing
@testable import foxgita

final class ReviewMockURLProtocol: URLProtocol, @unchecked Sendable {
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
struct MediaReviewClientTests {
    private func makeClient() -> MediaReviewClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReviewMockURLProtocol.self]
        return MediaReviewClient(session: URLSession(configuration: config))
    }

    @Test func generateReviewSuccess() async throws {
        let payload: [String: Any] = [
            "choices": [[
                "message": [
                    "content": #"{"highlight":"稳","focus":"F 慢","nextAction":"70 BPM"}"#
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        ReviewMockURLProtocol.handler = { _ in (200, data) }
        defer { ReviewMockURLProtocol.handler = nil }

        let draft = try await makeClient().generateReview(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk-test",
            imageJPEGData: [Data([0xFF, 0xD8])],
            contextText: "任务：和弦转换"
        )
        #expect(draft.highlight == "稳")
        #expect(draft.focus == "F 慢")
        #expect(draft.nextAction == "70 BPM")
    }

    @Test func generateReviewUnauthorized() async {
        ReviewMockURLProtocol.handler = { _ in (401, Data()) }
        defer { ReviewMockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.unauthorized) {
            try await makeClient().generateReview(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "bad",
                imageJPEGData: [Data([0xFF])],
                contextText: "x"
            )
        }
    }

    @Test func generateReviewInvalidJSON() async {
        let payload: [String: Any] = ["choices": [["message": ["content": "not-json"]]]]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        ReviewMockURLProtocol.handler = { _ in (200, data) }
        defer { ReviewMockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.invalidJSON) {
            try await makeClient().generateReview(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0xFF])],
                contextText: "x"
            )
        }
    }

    @Test func generateReviewRetriesWithoutResponseFormat() async throws {
        let ok: [String: Any] = [
            "choices": [[
                "message": ["content": #"{"highlight":"a","focus":"b","nextAction":"c"}"#]
            ]]
        ]
        let okData = try JSONSerialization.data(withJSONObject: ok)
        var calls = 0
        ReviewMockURLProtocol.handler = { request in
            calls += 1
            if calls == 1 {
                return (400, Data("unknown response_format".utf8))
            }
            return (200, okData)
        }
        defer { ReviewMockURLProtocol.handler = nil }

        let draft = try await makeClient().generateReview(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk",
            imageJPEGData: [Data([0xFF])],
            contextText: "x"
        )
        #expect(draft.highlight == "a")
        #expect(calls == 2)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MediaReviewClientTests test
```

Expected: FAIL (`MediaReviewClient` missing).

- [ ] **Step 3: Implement**

Create `foxgita/Services/MediaReviewClient.swift`. Copy the transport/`response_format` retry/`stripMarkdownFences` shape from `VisionPracticeClient`. Differences: parse `MediaReviewDraft.Raw`, user text is `contextText` plus this system prompt:

```
你是吉他练习陪伴教练。根据波形图或练习画面帧给出简短复盘。只返回 JSON，不要 markdown。
字段：highlight（亮点）、focus（优先改善）、nextAction（下次练法）。
每段一句话，不要编造时间戳（如 01:18），不要承诺精确音准鉴定。
```

URL: `VisionPracticeClient.completionsURL(from: baseURL)`. 401/403 → `.unauthorized`. Empty/unparseable/empty-field normalize → `.invalidJSON`.

```swift
protocol MediaReviewing: Sendable {
    func generateReview(
        baseURL: String,
        model: String,
        apiKey: String,
        imageJPEGData: [Data],
        contextText: String
    ) async throws -> MediaReviewDraft
}
```

`buildBody` user content: first a `text` part with `contextText`, then each JPEG as `image_url` data-URL (same as Vision). Timeout: injected `URLSession` (app uses `.shared`).

- [ ] **Step 4: Run tests — expect PASS**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/MediaReviewClient.swift foxgitaTests/MediaReviewClientTests.swift
git commit -m "feat: add OpenAI-compatible MediaReviewClient"
```

---

### Task 3: Schema V4

**Files:**
- Modify: `foxgita/Models/Models.swift`
- Modify: `foxgita/foxgitaApp.swift` (schema version only)
- Test: `foxgitaTests/MigrationTests.swift`

**Interfaces:**
- Consumes: existing `GitaSchemaV2`, `GitaSchemaV3`
- Produces:
  - `enum ReviewStatus: String, Codable, Sendable { case none, pending, ready, failed }`
  - `typealias TaskItem/PracticeSession/RecordingRef = GitaSchemaV4.*`
  - `GitaSchemaV4.RecordingRef` fields: `reviewStatusRaw` default `"none"`, `reviewHighlight` / `reviewFocus` / `reviewNextAction` default `""`, computed `reviewStatus`
  - `GitaMigrationPlan.schemas`: V2, V3, V4
  - stages: lightweight V2→V3 **and** lightweight V3→V4

- [ ] **Step 1: Write the failing tests**

In `foxgitaTests/MigrationTests.swift`, keep `v2StoreMigratesToV3WithoutLosingRows` but reopen under **V4** (so V2→V3→V4 runs). After existing recording asserts, add:

```swift
#expect(recordings[0].reviewStatus == .none)
#expect(recordings[0].reviewHighlight.isEmpty)
```

Change the Phase 2 container from `GitaSchemaV3` to `GitaSchemaV4`.

Add:

```swift
@Test func v3StoreMigratesToV4WithEmptyReview() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("gita-v3-v4-\(UUID().uuidString).store")
    defer { try? FileManager.default.removeItem(at: url) }

    do {
        let v3Schema = Schema(versionedSchema: GitaSchemaV3.self)
        let config = ModelConfiguration(schema: v3Schema, url: url)
        let container = try ModelContainer(for: v3Schema, configurations: [config])
        let context = ModelContext(container)
        let session = GitaSchemaV3.PracticeSession(
            id: "s1", taskId: "warm", taskTitle: "指尖热身",
            category: .left, startedAt: Date(), endedAt: Date(),
            durationSec: 60, bpm: 80, timeSig: "4/4",
            steps: ["开放弦"], noteText: ""
        )
        session.recordings.append(
            GitaSchemaV3.RecordingRef(
                id: "r1", fileName: "clip.m4a", bytes: 100, durationSec: 12,
                createdAt: Date(), label: "录音"
            )
        )
        context.insert(session)
        try context.save()
    }

    let v4Schema = Schema(versionedSchema: GitaSchemaV4.self)
    let config = ModelConfiguration(schema: v4Schema, url: url)
    let container = try ModelContainer(
        for: v4Schema, migrationPlan: GitaMigrationPlan.self, configurations: [config]
    )
    let recordings = try ModelContext(container).fetch(FetchDescriptor<RecordingRef>())
    #expect(recordings.count == 1)
    #expect(recordings[0].id == "r1")
    #expect(recordings[0].reviewStatus == .none)
}
```

`GitaSchemaV3.PracticeSession` already has the memberwise init used above (category enum, `steps:`). Use that, not the V2 raw-field init.

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MigrationTests test
```

Expected: FAIL (`GitaSchemaV4` / `reviewStatus` missing).

- [ ] **Step 3: Implement**

In `foxgita/Models/Models.swift`:

1. Add `ReviewStatus` next to `SyncState`.
2. Keep `GitaSchemaV3` as-is (needed for migration).
3. Add `enum GitaSchemaV4: VersionedSchema` with `versionIdentifier = Schema.Version(4, 0, 0)`.
4. Copy `TaskItem` and `PracticeSession` from V3 into V4 unchanged (same stored properties and inits). `PracticeSession.recordings` inverse must point at `GitaSchemaV4.RecordingRef`.
5. Copy `RecordingRef` and add:

```swift
var reviewStatusRaw: String = ReviewStatus.none.rawValue
var reviewHighlight: String = ""
var reviewFocus: String = ""
var reviewNextAction: String = ""

var reviewStatus: ReviewStatus {
    get { ReviewStatus(rawValue: reviewStatusRaw) ?? .none }
    set { reviewStatusRaw = newValue.rawValue }
}
```

6. Point typealiases at V4.
7. Migration plan:

```swift
static var schemas: [any VersionedSchema.Type] {
    [GitaSchemaV2.self, GitaSchemaV3.self, GitaSchemaV4.self]
}
static var stages: [MigrationStage] {
    [
        .lightweight(fromVersion: GitaSchemaV2.self, toVersion: GitaSchemaV3.self),
        .lightweight(fromVersion: GitaSchemaV3.self, toVersion: GitaSchemaV4.self),
    ]
}
```

8. In `foxgitaApp.swift` init, use `GitaSchemaV4.self`.

- [ ] **Step 4: Run tests — expect PASS**

Same MigrationTests command. Also run `foxgitaTests` once to catch typealias breakage. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Models/Models.swift foxgita/foxgitaApp.swift foxgitaTests/MigrationTests.swift
git commit -m "feat: add Schema V4 review fields on RecordingRef"
```

---

### Task 4: PracticeStore review writes

**Files:**
- Modify: `foxgita/Services/PracticeRepository.swift` (protocol + both implementations)
- Modify: `foxgita/Services/PracticeStore.swift`
- Test: `foxgitaTests/PracticeStoreTests.swift`

**Interfaces:**
- Consumes: `ReviewStatus`, `MediaReviewDraft`, `RecordingRef`
- Produces:

```swift
struct MediaReviewContext: Equatable, Sendable {
    var recordingId: String
    var fileName: String
    var durationSec: Int
    var taskTitle: String
    var steps: [String]
    var bpm: Int
    var timeSig: String
    var note: String
}

protocol PracticeRepository {
    // existing methods, plus:
    func recording(id: String) throws -> RecordingRef?
}

extension PracticeStore {
    func markReviewsPending(recordingIds: [String])
    func applyReview(recordingId: String, draft: MediaReviewDraft)
    func markReviewsFailed(recordingIds: [String])
    func reviewContext(recordingId: String) -> MediaReviewContext?
}
```

`finishSession` signature stays `-> Bool`. Clip `id` is already stored as `RecordingRef.id`.

`markReviewsPending` / `applyReview` / `markReviewsFailed`: missing id is skipped (no `lastError`). Pending and failed clear the three strings. `applyReview` sets `.ready` and the three fields. Always `touch`-equivalent: `updatedAt = Date()`, `syncState = .local`, then `save()`.

`reviewContext`: recording + its `session`; `taskTitle` / `steps` / `bpm` / `timeSig` / `note` from the session (not live task). Missing recording → nil.

- [ ] **Step 1: Write the failing tests**

Add to `PracticeStoreTests.swift` (need a recording on disk **or** skip file checks — these APIs do not require the file):

```swift
@Test func markPendingClearsReadyText() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedActive(into: repo)
    let now = Date()
    #expect(store.finishSession(
        taskId: "warm", steps: ["a"], note: "n",
        startedAt: now, endedAt: now, durationSec: 60, bpm: 72,
        recordings: []
    ))
    let session = try repo.sessions()[0]
    let rec = RecordingRef(id: "clip-1", fileName: "x.m4a", bytes: 1, durationSec: 8)
    rec.reviewStatus = .ready
    rec.reviewHighlight = "旧"
    rec.reviewFocus = "旧"
    rec.reviewNextAction = "旧"
    session.recordings.append(rec)
    try repo.save()

    store.markReviewsPending(recordingIds: ["clip-1"])
    let after = try #require(try repo.recording(id: "clip-1"))
    #expect(after.reviewStatus == .pending)
    #expect(after.reviewHighlight.isEmpty)
}

@Test func applyReviewWritesThreeFields() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedActive(into: repo)
    let now = Date()
    #expect(store.finishSession(
        taskId: "warm", steps: ["慢速"], note: "笔记",
        startedAt: now, endedAt: now, durationSec: 60, bpm: 80,
        recordings: []
    ))
    let session = try repo.sessions()[0]
    session.recordings.append(RecordingRef(id: "clip-2", fileName: "y.mov", bytes: 2, durationSec: 20))
    try repo.save()

    store.applyReview(
        recordingId: "clip-2",
        draft: MediaReviewDraft(highlight: "稳", focus: "F", nextAction: "70")
    )
    let rec = try #require(try repo.recording(id: "clip-2"))
    #expect(rec.reviewStatus == .ready)
    #expect(rec.reviewHighlight == "稳")

    let ctx = try #require(store.reviewContext(recordingId: "clip-2"))
    #expect(ctx.taskTitle == "指尖热身")
    #expect(ctx.bpm == 80)
    #expect(ctx.note == "笔记")
    #expect(ctx.fileName == "y.mov")
}

@Test func markFailedClearsText() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedActive(into: repo)
    let now = Date()
    #expect(store.finishSession(
        taskId: "warm", steps: [], note: "n",
        startedAt: now, endedAt: now, durationSec: 60, bpm: 80, recordings: []
    ))
    let session = try repo.sessions()[0]
    let rec = RecordingRef(id: "clip-3", fileName: "z.m4a", bytes: 1)
    rec.reviewStatus = .pending
    session.recordings.append(rec)
    try repo.save()

    store.markReviewsFailed(recordingIds: ["clip-3", "missing"])
    #expect(try repo.recording(id: "clip-3")?.reviewStatus == .failed)
}
```

`InMemoryPracticeRepository` must implement `recording(id:)` by scanning `storedSessions.flatMap(\.recordings)` (and pending sessions if you append after save — after `save()`, recordings live on stored sessions). If a test appends a recording to a stored session after save, `recording(id:)` must see it without another `add`.

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

Expected: FAIL (new methods / `recording(id:)` missing).

- [ ] **Step 3: Implement**

`PracticeRepository.recording(id:)`:

```swift
func recording(id: String) throws -> RecordingRef? {
    try sessions().lazy.flatMap(\.recordings).first { $0.id == id && $0.deletedAt == nil }
}
```

Same in `InMemoryPracticeRepository` (search `storedSessions` only; tests save before lookup).

Store methods as specified. One `save()` per call.

- [ ] **Step 4: Run tests — expect PASS**

Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeRepository.swift foxgita/Services/PracticeStore.swift foxgitaTests/PracticeStoreTests.swift
git commit -m "feat: persist per-clip review state on RecordingRef"
```

---

### Task 5: MediaReviewGenerator

**Files:**
- Create: `foxgita/Services/MediaReviewGenerator.swift`
- Test: `foxgitaTests/MediaReviewGeneratorTests.swift`

**Interfaces:**
- Consumes: `MediaReviewing`, `LLMCredentialsStore`, `LLMSettingsKey`, `PracticeImageCodec`, `MediaReviewContext`
- Produces:

```swift
enum MediaReviewGeneratorError: Error, Equatable {
    case notConfigured
    case fileMissing
    case prepareFailed
    case failed(VisionPracticeError)
}

protocol MediaImagePreparing: Sendable {
    func jpegImages(fileName: String) throws -> [Data]
}

protocol MediaReviewGenerating: Sendable {
    func review(_ context: MediaReviewContext, baseURL: String, model: String) async throws -> MediaReviewDraft
}

@MainActor
final class MediaReviewGenerator: MediaReviewGenerating {
    init(
        client: any MediaReviewing,
        credentials: LLMCredentialsStore = LLMCredentialsStore(),
        images: any MediaImagePreparing = FileMediaImagePreparer()
    )
}
```

`FileMediaImagePreparer`:
- Resolve `RecordingStore.url(for: fileName)`. Missing file → throw `MediaReviewGeneratorError.fileMissing` from the generator (preparer can throw `fileMissing` or generator checks `FileManager` first).
- Extension `.mov` (case-insensitive): 3 frames at 0% / 50% / 100% via `AVAssetImageGenerator`, each run through `PracticeImageCodec.jpegData` (if you have raw JPEG from `UIImage(cgImage:)`, still compress).
- Any other extension: one waveform JPEG from `AVAudioFile` samples (downsample to ~200 bars, draw on `UIGraphicsImageRenderer` ~640×200, then `PracticeImageCodec.jpegData`).
- Prepare failure → `prepareFailed`.

Generator: `isConfigured` else `notConfigured`. Then images. Then `client.generateReview`. Map `VisionPracticeError` to `.failed`. Build `contextText` from context fields; omit empty note/steps; include `录音` vs `录像` from `.mov`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import foxgita

@MainActor
struct MediaReviewGeneratorTests {
    private func context(file: String = "a.m4a") -> MediaReviewContext {
        MediaReviewContext(
            recordingId: "r1", fileName: file, durationSec: 12,
            taskTitle: "和弦转换", steps: ["慢速"], bpm: 80,
            timeSig: "4/4", note: "稳一点"
        )
    }

    @Test func notConfigured() async {
        struct StubClient: MediaReviewing {
            func generateReview(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], contextText: String
            ) async throws -> MediaReviewDraft {
                Issue.record("should not be called")
                throw VisionPracticeError.transport
            }
        }
        struct StubImages: MediaImagePreparing {
            func jpegImages(fileName: String) throws -> [Data] { [Data([1])] }
        }
        let credentials = LLMCredentialsStore(service: "t.\(UUID().uuidString)")
        let gen = MediaReviewGenerator(
            client: StubClient(), credentials: credentials, images: StubImages()
        )
        await #expect(throws: MediaReviewGeneratorError.notConfigured) {
            try await gen.review(context(), baseURL: "", model: "")
        }
    }

    @Test func prepareFailedMaps() async throws {
        struct StubClient: MediaReviewing {
            func generateReview(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], contextText: String
            ) async throws -> MediaReviewDraft {
                throw VisionPracticeError.transport
            }
        }
        struct Boom: MediaImagePreparing {
            func jpegImages(fileName: String) throws -> [Data] {
                throw MediaReviewGeneratorError.prepareFailed
            }
        }
        let credentials = LLMCredentialsStore(service: "t.\(UUID().uuidString)")
        try credentials.saveAPIKey("sk")
        let gen = MediaReviewGenerator(
            client: StubClient(), credentials: credentials, images: Boom()
        )
        await #expect(throws: MediaReviewGeneratorError.prepareFailed) {
            try await gen.review(context(), baseURL: "https://api.openai.com/v1", model: "gpt-4o")
        }
    }

    @Test func clientUnauthorizedMaps() async throws {
        struct StubClient: MediaReviewing {
            func generateReview(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], contextText: String
            ) async throws -> MediaReviewDraft {
                throw VisionPracticeError.unauthorized
            }
        }
        struct StubImages: MediaImagePreparing {
            func jpegImages(fileName: String) throws -> [Data] { [Data([1])] }
        }
        let credentials = LLMCredentialsStore(service: "t.\(UUID().uuidString)")
        try credentials.saveAPIKey("sk")
        let gen = MediaReviewGenerator(
            client: StubClient(), credentials: credentials, images: StubImages()
        )
        await #expect(throws: MediaReviewGeneratorError.failed(.unauthorized)) {
            try await gen.review(context(), baseURL: "https://api.openai.com/v1", model: "gpt-4o")
        }
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MediaReviewGeneratorTests test
```

Expected: FAIL (types missing).

- [ ] **Step 3: Implement** `MediaReviewGenerator.swift` as specified. `FileMediaImagePreparer` must not write files. Do not log image data.

Waveform: if `AVAudioFile` cannot open, throw `prepareFailed`. Video: if duration is 0, still try time `.zero` once; if all three copies fail, `prepareFailed`.

- [ ] **Step 4: Run tests — expect PASS**

Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/MediaReviewGenerator.swift foxgitaTests/MediaReviewGeneratorTests.swift
git commit -m "feat: prepare waveform or frames for media review"
```

---

### Task 6: ReviewJobRunner

**Files:**
- Create: `foxgita/Services/ReviewJobRunner.swift`
- Test: `foxgitaTests/ReviewJobRunnerTests.swift`

**Interfaces:**
- Consumes: `MediaReviewGenerating`, `PracticeStore`, `MediaReviewContext`
- Produces:

```swift
@Observable
@MainActor
final class ReviewJobRunner {
    init(store: PracticeStore, generator: any MediaReviewGenerating)
    func enqueue(_ recordingIds: [String], baseURL: String, model: String)
    func isRunning(_ id: String) -> Bool
    var activeRecordingId: String?
}
```

`isRunning` is true if `id` is `activeRecordingId` or still in the current job’s unstarted list **or** in later queued jobs.

Behavior:
- Ignore ids already `isRunning`.
- Sequential. For each id: `markReviewsPending([id])` (already pending is fine), `reviewContext` nil or generator `fileMissing`/`prepareFailed`/`failed(non-401)` → `markReviewsFailed([id])`, continue.
- `failed(.unauthorized)` → `markReviewsFailed` for **this id and remaining ids in the same `enqueue` batch**. Then start the next batch if any.
- Success → `applyReview`.
- `baseURL`/`model` captured per `enqueue` call.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import foxgita

@MainActor
struct ReviewJobRunnerTests {
    private func harness() throws -> (ReviewJobRunner, PracticeStore, InMemoryPracticeRepository, RecordingSpy) {
        let repo = InMemoryPracticeRepository()
        let defaults = UserDefaults(suiteName: "runner.\(UUID().uuidString)")!
        defaults.set(true, forKey: SeedData.seededKey)
        let store = PracticeStore(repository: repo, defaults: defaults)
        let task = TaskItem(id: "warm", title: "指尖热身", subtitle: "", category: .left, targetMin: 5)
        try repo.add(task)
        try repo.save()
        let now = Date()
        #expect(store.finishSession(
            taskId: "warm", steps: ["a"], note: "",
            startedAt: now, endedAt: now, durationSec: 30, bpm: 80, recordings: []
        ))
        let session = try repo.sessions()[0]
        for id in ["a", "b", "c"] {
            session.recordings.append(RecordingRef(id: id, fileName: "\(id).m4a", bytes: 1, durationSec: 5))
        }
        try repo.save()
        let spy = RecordingSpy()
        let runner = ReviewJobRunner(store: store, generator: spy)
        return (runner, store, repo, spy)
    }

    @Test func runsSequentiallyAndWritesReady() async throws {
        let (runner, _, repo, spy) = try harness()
        spy.drafts = [
            "a": .success(.init(highlight: "ha", focus: "fa", nextAction: "na")),
            "b": .success(.init(highlight: "hb", focus: "fb", nextAction: "nb")),
        ]
        runner.enqueue(["a", "b"], baseURL: "https://x", model: "m")
        try await waitUntil {
            (try? repo.recording(id: "b")?.reviewStatus) == .ready
        }
        #expect(spy.order == ["a", "b"])
        #expect(try repo.recording(id: "a")?.reviewHighlight == "ha")
        #expect(runner.isRunning("a") == false)
    }

    @Test func unauthorizedFailsRestOfBatch() async throws {
        let (runner, _, repo, spy) = try harness()
        spy.drafts = [
            "a": .failure(.failed(.unauthorized)),
            "b": .success(.init(highlight: "h", focus: "f", nextAction: "n")),
        ]
        runner.enqueue(["a", "b"], baseURL: "https://x", model: "m")
        try await waitUntil {
            (try? repo.recording(id: "b")?.reviewStatus) == .failed
        }
        #expect(spy.order == ["a"])
        #expect(try repo.recording(id: "a")?.reviewStatus == .failed)
        #expect(try repo.recording(id: "b")?.reviewStatus == .failed)
    }

    @Test func retryOnlyTouchesOneClip() async throws {
        let (runner, store, repo, spy) = try harness()
        store.markReviewsFailed(recordingIds: ["a", "b"])
        spy.drafts = [
            "a": .success(.init(highlight: "h", focus: "f", nextAction: "n")),
        ]
        runner.enqueue(["a"], baseURL: "https://x", model: "m")
        try await waitUntil {
            (try? repo.recording(id: "a")?.reviewStatus) == .ready
        }
        #expect(try repo.recording(id: "b")?.reviewStatus == .failed)
        #expect(spy.order == ["a"])
    }
}

@MainActor
final class RecordingSpy: MediaReviewGenerating {
    var drafts: [String: Result<MediaReviewDraft, MediaReviewGeneratorError>] = [:]
    private(set) var order: [String] = []

    func review(
        _ context: MediaReviewContext, baseURL: String, model: String
    ) async throws -> MediaReviewDraft {
        order.append(context.recordingId)
        switch drafts[context.recordingId] {
        case .success(let draft): return draft
        case .failure(let error): throw error
        case nil: throw MediaReviewGeneratorError.prepareFailed
        }
    }
}

@MainActor
func waitUntil(timeoutNanos: UInt64 = 2_000_000_000, _ pred: () -> Bool) async throws {
    let start = DispatchTime.now().uptimeNanoseconds
    while !pred() {
        if DispatchTime.now().uptimeNanoseconds - start > timeoutNanos {
            Issue.record("timeout")
            return
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/ReviewJobRunnerTests test
```

Expected: FAIL (`ReviewJobRunner` missing).

- [ ] **Step 3: Implement** a serial `Task` loop on the main actor. Do not start a second loop if one is running; append batches to a queue of `[String]`.

- [ ] **Step 4: Run tests — expect PASS**

Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/ReviewJobRunner.swift foxgitaTests/ReviewJobRunnerTests.swift
git commit -m "feat: queue per-clip review jobs and stop a batch on 401"
```

---

### Task 7: Finish flow + processing sheet

**Files:**
- Create: `foxgita/Features/Practice/ReviewGenerationSheet.swift`
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift`
- Modify: `foxgita/foxgitaApp.swift`

**Interfaces:**
- Consumes: `ReviewJobRunner`, `LLMCredentialsStore`, `LLMSettingsKey`, `PracticeStore.markReviewsPending`, clip ids from `finishSession`
- Produces: sheet UI; after finish with media + configured AI, sheet then back to today’s practice list

- [ ] **Step 1: Inject runner**

In `foxgitaApp`:

```swift
@State private var reviewRunner: ReviewJobRunner
```

After `store` is created:

```swift
let store = PracticeStore(repository: SwiftDataPracticeRepository(context: container.mainContext))
_store = State(initialValue: store)
_reviewRunner = State(
    initialValue: ReviewJobRunner(
        store: store,
        generator: MediaReviewGenerator(client: MediaReviewClient())
    )
)
```

```swift
.environment(store)
.environment(reviewRunner)
```

- [ ] **Step 2: Sheet**

`ReviewGenerationSheet(recordingIds: [String], taskTitle: String, onReturn: () -> Void)`:

- Title `生成练习复盘`
- Subtitle `"\(taskTitle) · 本次练习"`
- For each id, resolve `RecordingRef` via `@Query` of all recordings (filter in memory) or a small helper from the parent passing `[(id, title, durationLabel)]` **and** observe store/query for status.
- Right label: `ready` → `完成`; `failed` → `失败`; `pending && runner.activeRecordingId == id` → `分析中`; else if `pending` → `等待中`
- Button `后台生成并返回` calls `onReturn`
- Footer `录制内容已安全保存`
- `.onChange` of all listed statuses: if every id is `ready` or `failed`, call `onReturn` once

Use existing tokens (`GitaFont`, `GitaTheme`, `PageBackground`).

- [ ] **Step 3: Wire `complete`**

In `PracticeDetailView` add:

```swift
@Environment(ReviewJobRunner.self) private var reviewRunner
@AppStorage(LLMSettingsKey.baseURL) private var llmBaseURL = ""
@AppStorage(LLMSettingsKey.model) private var llmModel = ""
private let llmCredentials = LLMCredentialsStore()
@State private var reviewClipIds: [String] = []
@State private var showReviewSheet = false
```

After successful `finishSession`, let `ids = clips.map(\.id)` (the same ids written onto `RecordingRef`). If `!ids.isEmpty && llmCredentials.isConfigured(baseURL: llmBaseURL, model: llmModel)`:

```swift
store.markReviewsPending(recordingIds: ids)
reviewRunner.enqueue(ids, baseURL: llmBaseURL, model: llmModel)
reviewClipIds = ids
showReviewSheet = true
```

Do **not** pop yet.

Else: existing pop (`returnPracticeToToday` + `practicePath.removeAll()`).

Sheet:

```swift
.sheet(isPresented: $showReviewSheet) {
    ReviewGenerationSheet(recordingIds: reviewClipIds, taskTitle: task?.title ?? "") {
        showReviewSheet = false
        router.returnPracticeToToday = true
        router.practicePath.removeAll()
    }
}
```

Empty complete and failed `finishSession` unchanged.

- [ ] **Step 4: Build**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/ReviewJobRunnerTests test
```

Expected: PASS (compile + existing runner tests).

- [ ] **Step 5: Commit**

```bash
git add foxgita/Features/Practice/ReviewGenerationSheet.swift \
  foxgita/Features/Practice/PracticeDetailView.swift \
  foxgita/foxgitaApp.swift
git commit -m "feat: analyze clips after finish and allow background return"
```

---

### Task 8: Record detail 复盘 tab + settings + docs

**Files:**
- Modify: `foxgita/Features/Record/RecordDetailView.swift`
- Modify: `foxgita/Features/Settings/SettingsView.swift`
- Modify: `docs/TECHNICAL.md`
- Modify: `docs/TEST_PLAN_CLI.md`

**Interfaces:**
- Consumes: `ReviewJobRunner.isRunning`, `PracticeStore.markReviewsPending` / `enqueue`, `LLMCredentialsStore`
- Produces: fourth pill `复盘`; settings privacy sentence

- [ ] **Step 1: Record detail**

Change pills to `["数据", "录音", "笔记", "复盘"]`.

```swift
switch tab {
case 1: audioPane
case 2: notePane
case 3: reviewPane
default: dataPane
}
```

`reviewPane`: if `recordings.isEmpty` → `empty("还没有录音或录像", "练完录音或录像后可以生成复盘")`.

Else `ForEach` recordings (already newest-first). Card:

| Condition | UI |
|---|---|
| `.none` | 「未分析」+ button「生成复盘」 |
| `.pending` && `reviewRunner.isRunning(r.id)` | 「分析中」 |
| `.pending` && !running | 「未完成」+「重试」 |
| `.ready` | 三块 labeled 亮点 / 优先改善 / 下次练法 |
| `.failed` | 「生成失败，可重试」+「重试」 |

Header line: `录音` if `fileName` does not end with `.mov`, else `视频`, plus `durationLabel` and `timeLabel(createdAt)`.

Generate/retry:

```swift
if llmCredentials.isConfigured(baseURL: llmBaseURL, model: llmModel) {
    store.markReviewsPending(recordingIds: [r.id])
    reviewRunner.enqueue([r.id], baseURL: llmBaseURL, model: llmModel)
} else {
    toast or store-less: set a local toast 「先去设置里填写 AI 接口」
}
```

Add `@Environment(ReviewJobRunner.self)`, `@AppStorage` keys, `LLMCredentialsStore`, and a small toast like PracticeDetail if none exists — a `@State toast` + `ToastBanner` is enough. Audio pane unchanged.

- [ ] **Step 2: Settings**

Replace

`图片会发送到你填写的接口地址，费用由该服务商向你收取。Gita 不托管密钥。`

with

`图片、波形图和录像帧会发送到你填写的接口地址，费用由该服务商向你收取。Gita 不托管密钥。`

- [ ] **Step 3: Docs**

`TECHNICAL.md`: schema is V4; `RecordingRef` review fields; new §6.3.2 练后媒体复盘 (finish → Runner → Client; 复盘 tab). `finishSession` row unchanged (still returns Bool).

`TEST_PLAN_CLI.md`: add `MediaReviewDraftTests`, `MediaReviewClientTests`, `MediaReviewGeneratorTests`, `ReviewJobRunnerTests`; MigrationTests now V2→V4 / V3→V4.

- [ ] **Step 4: Run unit tests**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Features/Record/RecordDetailView.swift \
  foxgita/Features/Settings/SettingsView.swift \
  foxgita/Localizable.xcstrings \
  docs/TECHNICAL.md docs/TEST_PLAN_CLI.md
git commit -m "feat: show per-clip review on the record detail tab"
```

---

## Placeholder / consistency self-review

**Spec coverage**

| Spec | Task |
|---|---|
| Per-`RecordingRef` three fields + status | 1, 3, 4 |
| Vision JPEG channel, no raw media upload | 2, 5 |
| Sequential job, 401 fails rest of batch | 6 |
| Finish then sheet, background returns to today | 7 |
| No sheet if no media / not configured | 7 |
| 复盘 tab four states + stuck-pending retry | 8 |
| Settings privacy copy | 8 |
| V4 lightweight migration | 3 |
| No realtime / light recap / timeline / 加入下次 | not scheduled |

**Types:** `MediaReviewDraft`, `MediaReviewContext`, `MediaReviewing`, `MediaReviewGenerating`, `MediaImagePreparing`, `MediaReviewGeneratorError`, `ReviewJobRunner.enqueue(_:baseURL:model:)`, `isRunning(_:)` — same names in Tasks 1–8.

**No TBD / “handle errors later” / “similar to Task N” without code.**
