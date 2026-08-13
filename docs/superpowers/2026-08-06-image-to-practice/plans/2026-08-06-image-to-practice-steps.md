# Image-to-Practice Steps Implementation Plan

> **功能需求：** [`../2026-08-06-image-to-practice-steps-requirements.md`](../2026-08-06-image-to-practice-steps-requirements.md)。本文为逐步施工单。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users pick up to 3 photos in RecommendSheet, call an OpenAI-compatible vision API with their own Key, and create a practice task (title/category/minutes/steps) that opens in detail.

**Architecture:** Thin client: Settings stores Base URL + Model (`AppStorage`) and API Key (Keychain). `ImageStepGenerator` compresses images and calls `VisionPracticeClient`; response JSON is normalized into `AIPracticeDraft`, then `PracticeStore.createFromAIDraft` persists a `TaskItem`. No schema migration; images are never saved to disk.

**Tech Stack:** SwiftUI · PhotosUI · URLSession · Keychain · Swift Testing · existing PracticeStore / SwiftData

## Global Constraints

- Spec: `docs/superpowers/2026-08-06-image-to-practice/specs/2026-08-06-image-to-practice-steps-design.md`
- iOS 18+ · Scheme `foxgita` · synchronized Xcode groups (new files under `foxgita/` / `foxgitaTests/` auto-join targets)
- No SwiftData schema change; reuse `TaskItem.steps` / `StepCoding`
- Images: max 3, longest edge ~1280, JPEG ~0.7, memory only
- API: OpenAI-compatible `chat/completions` with multimodal images
- Copy language: `zh-Hans` via `String(localized:)` / String Catalog
- Unit test command: `xcodebuild -project foxgita.xcodeproj -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:foxgitaTests test` (swap simulator name if needed)
- Do not log API keys; do not commit secrets
- YAGNI: no preview wizard, no OCR path, no image persistence, no server proxy

## File map

| File | Responsibility |
|---|---|
| `foxgita/Services/AIPracticeDraft.swift` | Draft value type + `normalize` pure function |
| `foxgita/Services/LLMCredentialsStore.swift` | Keychain API key + `isConfigured` |
| `foxgita/Services/VisionPracticeClient.swift` | HTTP + URL join + JSON parse + format retry |
| `foxgita/Services/ImageStepGenerator.swift` | Compress images + orchestrate client |
| `foxgita/Services/PracticeStore.swift` | `createFromAIDraft` |
| `foxgita/Features/Settings/SettingsView.swift` | AI settings section |
| `foxgita/Features/Practice/RecommendSheet.swift` | PhotosPicker + generate UX |
| `foxgita.xcodeproj/project.pbxproj` | `NSPhotoLibraryUsageDescription` |
| `foxgita/Localizable.xcstrings` | New strings (Xcode may auto-extract) |
| `foxgitaTests/AIPracticeDraftTests.swift` | Normalize tests |
| `foxgitaTests/VisionPracticeClientTests.swift` | Mock URLProtocol tests |
| `foxgitaTests/LLMCredentialsStoreTests.swift` | Keychain tests (unique service) |
| `foxgitaTests/PracticeStoreTests.swift` | `createFromAIDraft` cases |
| `foxgitaUITests/PracticeFlowUITests.swift` | Optional entry smoke |
| `docs/TECHNICAL.md` | Short feature note |

---

### Task 1: AIPracticeDraft normalize

**Files:**
- Create: `foxgita/Services/AIPracticeDraft.swift`
- Test: `foxgitaTests/AIPracticeDraftTests.swift`

**Interfaces:**
- Consumes: `PracticeCategory` (`foxgita/Theme/GitaTheme.swift`)
- Produces:
  - `struct AIPracticeDraft: Equatable` with `title: String`, `category: PracticeCategory`, `targetMin: Int`, `steps: [String]`
  - `struct AIPracticeDraft.Raw: Decodable` with optional/`String` fields matching model JSON
  - `static func normalize(_ raw: Raw, fallbackCategory: PracticeCategory) -> AIPracticeDraft`

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/AIPracticeDraftTests.swift`:

```swift
import Testing
@testable import foxgita

struct AIPracticeDraftTests {
    @Test func normalizeHappyPath() {
        let raw = AIPracticeDraft.Raw(
            title: "  F 和弦  ",
            category: "chord",
            targetMin: 15,
            steps: ["慢速", "加速", ""]
        )
        let draft = AIPracticeDraft.normalize(raw, fallbackCategory: .left)
        #expect(draft.title == "F 和弦")
        #expect(draft.category == .chord)
        #expect(draft.targetMin == 15)
        #expect(draft.steps == ["慢速", "加速"])
    }

    @Test func normalizeFallsBackCategoryAndClampsMinutes() {
        let raw = AIPracticeDraft.Raw(
            title: "   ",
            category: "nope",
            targetMin: 999,
            steps: nil
        )
        let draft = AIPracticeDraft.normalize(raw, fallbackCategory: .rhythm)
        #expect(draft.title == "未命名练习")
        #expect(draft.category == .rhythm)
        #expect(draft.targetMin == 60)
        #expect(draft.steps == ["新步骤"])
    }

    @Test func normalizeDefaultsMissingMinutesAndCapsSteps() {
        let many = (1...20).map { "步骤\($0)" }
        let raw = AIPracticeDraft.Raw(
            title: "音阶",
            category: "scale",
            targetMin: nil,
            steps: many
        )
        let draft = AIPracticeDraft.normalize(raw, fallbackCategory: .left)
        #expect(draft.targetMin == 10)
        #expect(draft.steps.count == 12)
        #expect(draft.steps.first == "步骤1")
        #expect(draft.steps.last == "步骤12")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/AIPracticeDraftTests \
  test
```

Expected: compile error / FAIL — `AIPracticeDraft` not found.

- [ ] **Step 3: Minimal implementation**

Create `foxgita/Services/AIPracticeDraft.swift`:

```swift
import Foundation

struct AIPracticeDraft: Equatable {
    var title: String
    var category: PracticeCategory
    var targetMin: Int
    var steps: [String]

    struct Raw: Decodable, Equatable {
        var title: String?
        var category: String?
        var targetMin: Int?
        var steps: [String]?
    }

    static func normalize(_ raw: Raw, fallbackCategory: PracticeCategory) -> AIPracticeDraft {
        let trimmed = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = trimmed.isEmpty ? String(localized: "未命名练习") : trimmed

        let category: PracticeCategory
        if let rawCat = raw.category, let parsed = PracticeCategory(rawValue: rawCat) {
            category = parsed
        } else {
            category = fallbackCategory
        }

        let minutes: Int
        if let value = raw.targetMin {
            minutes = min(60, max(1, value))
        } else {
            minutes = 10
        }

        var steps = (raw.steps ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if steps.isEmpty {
            steps = [String(localized: "新步骤")]
        } else if steps.count > 12 {
            steps = Array(steps.prefix(12))
        }

        return AIPracticeDraft(
            title: title,
            category: category,
            targetMin: minutes,
            steps: steps
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Same `xcodebuild` command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/AIPracticeDraft.swift foxgitaTests/AIPracticeDraftTests.swift
git commit -m "feat: add AIPracticeDraft normalize for vision JSON"
```

---

### Task 2: LLMCredentialsStore (Keychain)

**Files:**
- Create: `foxgita/Services/LLMCredentialsStore.swift`
- Test: `foxgitaTests/LLMCredentialsStoreTests.swift`

**Interfaces:**
- Consumes: Security framework
- Produces:
  - `enum LLMSettingsKey` with `baseURL = "gita.llm.baseURL"`, `model = "gita.llm.model"`
  - `final class LLMCredentialsStore` with
    - `init(service: String = "com.haizei.foxgita.llm")`
    - `func saveAPIKey(_ key: String) throws`
    - `func loadAPIKey() -> String?`
    - `func clearAPIKey()`
    - `func isConfigured(baseURL: String, model: String) -> Bool` — true iff all three non-empty after trim

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import foxgita

struct LLMCredentialsStoreTests {
    private func makeStore() -> LLMCredentialsStore {
        LLMCredentialsStore(service: "com.haizei.foxgita.llm.tests.\(UUID().uuidString)")
    }

    @Test func saveLoadClearRoundTrip() throws {
        let store = makeStore()
        defer { store.clearAPIKey() }
        #expect(store.loadAPIKey() == nil)
        try store.saveAPIKey("sk-test-123")
        #expect(store.loadAPIKey() == "sk-test-123")
        store.clearAPIKey()
        #expect(store.loadAPIKey() == nil)
    }

    @Test func isConfiguredRequiresAllFields() throws {
        let store = makeStore()
        defer { store.clearAPIKey() }
        #expect(store.isConfigured(baseURL: "https://api.openai.com/v1", model: "gpt-4o") == false)
        try store.saveAPIKey("sk-x")
        #expect(store.isConfigured(baseURL: "  ", model: "gpt-4o") == false)
        #expect(store.isConfigured(baseURL: "https://api.openai.com/v1", model: "") == false)
        #expect(store.isConfigured(baseURL: "https://api.openai.com/v1", model: "gpt-4o") == true)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL** (`LLMCredentialsStore` missing)

- [ ] **Step 3: Minimal implementation**

```swift
import Foundation
import Security

enum LLMSettingsKey {
    static let baseURL = "gita.llm.baseURL"
    static let model = "gita.llm.model"
}

final class LLMCredentialsStore: Sendable {
    private let service: String
    private let account = "apiKey"

    init(service: String = "com.haizei.foxgita.llm") {
        self.service = service
    }

    func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func clearAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func isConfigured(baseURL: String, model: String) -> Bool {
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !url.isEmpty && !m.isEmpty && !key.isEmpty
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/LLMCredentialsStore.swift foxgitaTests/LLMCredentialsStoreTests.swift
git commit -m "feat: store LLM API key in Keychain"
```

---

### Task 3: VisionPracticeClient (HTTP + mock)

**Files:**
- Create: `foxgita/Services/VisionPracticeClient.swift`
- Test: `foxgitaTests/VisionPracticeClientTests.swift`
- Test helper (same test file or): keep `MockURLProtocol` private in the test file

**Interfaces:**
- Consumes: `AIPracticeDraft.Raw`
- Produces:
  - `enum VisionPracticeError: Error, Equatable` cases: `invalidURL`, `unauthorized`, `httpStatus(Int)`, `emptyContent`, `invalidJSON`, `transport`
  - `protocol VisionGenerating: Sendable` with
    `func generateDraft(baseURL: String, model: String, apiKey: String, imageJPEGData: [Data], fallbackCategory: PracticeCategory) async throws -> AIPracticeDraft`
  - `struct VisionPracticeClient: VisionGenerating`
    - `init(session: URLSession = .shared)`
    - `static func completionsURL(from baseURL: String) -> URL?`
    - `func generateDraft(...)` (same signature as protocol)

Behavior for `completionsURL`:
- Trim whitespace; strip trailing `/`
- If lowercased path already has suffix `/chat/completions`, use as-is
- Else append `/chat/completions`

Behavior for `generateDraft`:
- Build JSON body with `model`, `messages` (system + user content array: text + `image_url` data URLs), and `response_format: {type: json_object}`
- Header `Authorization: Bearer {apiKey}`, `Content-Type: application/json`
- Timeout via session (configure 60s in injected session for app; tests use mock)
- On HTTP 401/403 → `unauthorized`
- On 4xx whose UTF-8 body (lowercased) contains `response_format` or `unknown` → retry once without `response_format`
- Parse `choices[0].message.content` as JSON string (strip markdown fences if present) into `AIPracticeDraft.Raw`, then `normalize`
- Empty content → `emptyContent`; decode fail → `invalidJSON`; other network → `transport`

- [ ] **Step 1: Write failing tests**

```swift
import Foundation
import Testing
@testable import foxgita

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

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

struct VisionPracticeClientTests {
    private func makeClient() -> VisionPracticeClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return VisionPracticeClient(session: URLSession(configuration: config))
    }

    @Test func completionsURLJoinsAndRespectsFullPath() {
        #expect(
            VisionPracticeClient.completionsURL(from: "https://api.openai.com/v1/")?
                .absoluteString == "https://api.openai.com/v1/chat/completions"
        )
        #expect(
            VisionPracticeClient.completionsURL(
                from: "https://example.com/v1/chat/completions"
            )?.absoluteString == "https://example.com/v1/chat/completions"
        )
    }

    @Test func generateDraftSuccess() async throws {
        let payload: [String: Any] = [
            "choices": [[
                "message": [
                    "content": #"{"title":"开放弦","category":"left","targetMin":8,"steps":["拨弦","换弦"]}"#
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        MockURLProtocol.handler = { _ in (200, data) }
        defer { MockURLProtocol.handler = nil }

        let draft = try await makeClient().generateDraft(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk-test",
            imageJPEGData: [Data([0xFF, 0xD8, 0xFF])],
            fallbackCategory: .song
        )
        #expect(draft.title == "开放弦")
        #expect(draft.category == .left)
        #expect(draft.targetMin == 8)
        #expect(draft.steps == ["拨弦", "换弦"])
    }

    @Test func generateDraftUnauthorized() async {
        MockURLProtocol.handler = { _ in (401, Data(#"{"error":"no"}"#.utf8)) }
        defer { MockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.unauthorized) {
            try await makeClient().generateDraft(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "bad",
                imageJPEGData: [Data([0x01])],
                fallbackCategory: .left
            )
        }
    }

    @Test func generateDraftInvalidJSONContent() async {
        let payload: [String: Any] = [
            "choices": [["message": ["content": "not-json"]]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        MockURLProtocol.handler = { _ in (200, data) }
        defer { MockURLProtocol.handler = nil }
        await #expect(throws: VisionPracticeError.invalidJSON) {
            try await makeClient().generateDraft(
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                apiKey: "sk",
                imageJPEGData: [Data([0x01])],
                fallbackCategory: .left
            )
        }
    }

    @Test func generateDraftRetriesWithoutResponseFormat() async throws {
        actor Counter {
            private(set) var n = 0
            func hit() { n += 1 }
            func count() -> Int { n }
        }
        let counter = Counter()
        let ok: [String: Any] = [
            "choices": [[
                "message": [
                    "content": #"{"title":"节奏","category":"rhythm","targetMin":10,"steps":["拍手"]}"#
                ]
            ]]
        ]
        let okData = try JSONSerialization.data(withJSONObject: ok)
        MockURLProtocol.handler = { req in
            await counter.hit()
            let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
            if await counter.count() == 1 {
                #expect(body.contains("response_format"))
                return (400, Data(#"{"error":"unknown response_format"}"#.utf8))
            }
            #expect(!body.contains("response_format"))
            return (200, okData)
        }
        defer { MockURLProtocol.handler = nil }

        let draft = try await makeClient().generateDraft(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            apiKey: "sk",
            imageJPEGData: [Data([0x01])],
            fallbackCategory: .left
        )
        #expect(draft.category == .rhythm)
        #expect(await counter.count() == 2)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement `VisionPracticeClient.swift`**

Implement fully per Interfaces above. System prompt (Chinese) must instruct: return only JSON with keys `title`, `category` (one of left/right/both/chord/scale/rhythm/song), `targetMin`, `steps` (string array); guitar practice steps; no markdown.

Strip optional \`\`\`json fences from `content` before decode.

Image parts:

```swift
[
  "type": "image_url",
  "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"]
]
```

Keep max images already enforced by caller (≤3).

- [ ] **Step 4: Run `VisionPracticeClientTests` — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/VisionPracticeClient.swift foxgitaTests/VisionPracticeClientTests.swift
git commit -m "feat: add OpenAI-compatible VisionPracticeClient"
```

---

### Task 4: PracticeStore.createFromAIDraft

**Files:**
- Modify: `foxgita/Services/PracticeStore.swift` (after `createCustomTask`)
- Modify: `foxgitaTests/PracticeStoreTests.swift`

**Interfaces:**
- Consumes: `AIPracticeDraft`
- Produces:
  - `@discardableResult func createFromAIDraft(_ draft: AIPracticeDraft) -> String?`
  - Creates `TaskItem` with `id: "custom-\(UUID().uuidString)"`, `title`/`category`/`targetMin`/`steps` from draft, `subtitle: String(localized: "AI · \(draft.targetMin) 分钟")`, `startedOn: Date()`, `sortOrder: 50`, `isTemplate: false`

- [ ] **Step 1: Write failing test** (append to `PracticeStoreTests`)

```swift
    @Test func createFromAIDraftPersistsSteps() throws {
        let (store, repo, _) = makeStore(seeded: true)
        let draft = AIPracticeDraft(
            title: "扫弦入门",
            category: .rhythm,
            targetMin: 12,
            steps: ["熟悉下下上", "60 BPM", "80 BPM"]
        )
        let id = try #require(store.createFromAIDraft(draft))
        let task = try #require(try repo.task(id: id))
        #expect(task.title == "扫弦入门")
        #expect(task.category == .rhythm)
        #expect(task.targetMin == 12)
        #expect(task.steps == ["熟悉下下上", "60 BPM", "80 BPM"])
        #expect(task.subtitle.contains("AI"))
        #expect(task.steps != ["新步骤"])
    }
```

- [ ] **Step 2: Run — expect FAIL** (method missing)

- [ ] **Step 3: Implement**

```swift
    @discardableResult
    func createFromAIDraft(_ draft: AIPracticeDraft) -> String? {
        let task = TaskItem(
            id: "custom-\(UUID().uuidString)",
            title: draft.title,
            subtitle: String(localized: "AI · \(draft.targetMin) 分钟"),
            category: draft.category,
            targetMin: draft.targetMin,
            steps: draft.steps,
            startedOn: Date(),
            sortOrder: 50
        )
        return produce {
            try repository.add(task)
            try repository.save()
            return task.id
        }
    }
```

Place immediately after `createCustomTask`.

- [ ] **Step 4: Run PracticeStoreTests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeStore.swift foxgitaTests/PracticeStoreTests.swift
git commit -m "feat: create practice tasks from AIPracticeDraft"
```

---

### Task 5: ImageStepGenerator + JPEG compression

**Files:**
- Create: `foxgita/Services/ImageStepGenerator.swift`
- Test: `foxgitaTests/ImageStepGeneratorTests.swift` (compression + empty images error only; network via injected client protocol)

**Interfaces:**
- Consumes: `VisionPracticeClient` (or protocol below), `LLMCredentialsStore`, `AIPracticeDraft`
- Produces:
  - `enum ImageStepGeneratorError: Error, Equatable` — `notConfigured`, `noImages`, `tooManyImages`, `failed(VisionPracticeError)`
  - `enum PracticeImageCodec` with `static func jpegData(from imageData: Data, maxEdge: CGFloat = 1280, quality: CGFloat = 0.7) -> Data?`
  - `@MainActor final class ImageStepGenerator`
    - `init(client: any VisionGenerating, credentials: LLMCredentialsStore = LLMCredentialsStore())`
    - `func generate(imageData: [Data], baseURL: String, model: String, fallbackCategory: PracticeCategory) async throws -> AIPracticeDraft`

Rules:
- `imageData.isEmpty` → `noImages`
- `imageData.count > 3` → `tooManyImages`
- `!credentials.isConfigured(baseURL:model:)` → `notConfigured`
- Compress each blob via `PracticeImageCodec`; skip nils; if all nil → `noImages`
- Call client with apiKey from credentials

- [ ] **Step 1: Failing tests**

```swift
import Testing
import UIKit
@testable import foxgita

struct ImageStepGeneratorTests {
    @Test func codecShrinksLargeImage() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000))
        let ui = renderer.image { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        }
        let raw = ui.jpegData(compressionQuality: 1)!
        let out = PracticeImageCodec.jpegData(from: raw)!
        let decoded = UIImage(data: out)!
        #expect(max(decoded.size.width, decoded.size.height) <= 1280 + 1)
    }

    @Test func generatorRejectsEmptyAndTooMany() async {
        struct StubClient: VisionGenerating {
            func generateDraft(
                baseURL: String, model: String, apiKey: String,
                imageJPEGData: [Data], fallbackCategory: PracticeCategory
            ) async throws -> AIPracticeDraft {
                Issue.record("should not be called")
                throw VisionPracticeError.transport
            }
        }
        let gen = ImageStepGenerator(client: StubClient(), credentials: LLMCredentialsStore(service: "t.\(UUID().uuidString)"))
        await #expect(throws: ImageStepGeneratorError.noImages) {
            try await gen.generate(imageData: [], baseURL: "https://x", model: "m", fallbackCategory: .left)
        }
        await #expect(throws: ImageStepGeneratorError.tooManyImages) {
            try await gen.generate(
                imageData: [Data([1]), Data([2]), Data([3]), Data([4])],
                baseURL: "https://x", model: "m", fallbackCategory: .left
            )
        }
    }
}
```

For `notConfigured`, add a third test that passes 1 tiny JPEG and empty keychain → `notConfigured`.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement** `PracticeImageCodec` + `ImageStepGenerator` (client already conforms to `VisionGenerating` from Task 3)

Use UIKit `UIImage` for decode/resize/jpeg. On client errors, wrap as `.failed(visionError)`.

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/ImageStepGenerator.swift foxgitaTests/ImageStepGeneratorTests.swift
git commit -m "feat: orchestrate image compression and vision generation"
```

---

### Task 6: Photo library usage string + Settings AI UI

**Files:**
- Modify: `foxgita.xcodeproj/project.pbxproj` (Debug + Release foxgita target build settings)
- Modify: `foxgita/Features/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `LLMCredentialsStore`, `LLMSettingsKey`
- Produces: Settings section「AI 接口」with Base URL field, Model field, API Key SecureField, Save/Clear, privacy footnote

- [ ] **Step 1: Add Info.plist keys** in both Debug/Release foxgita configurations next to microphone/camera keys:

```
INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "Gita 需要访问相册，以便从曲谱或笔记图片生成练习步骤。";
```

(PhotosPicker on modern iOS may use limited library picker without classic prompt, but keep the key for compatibility.)

- [ ] **Step 2: Extend SettingsView**

Add state:

```swift
@AppStorage(LLMSettingsKey.baseURL) private var llmBaseURL = ""
@AppStorage(LLMSettingsKey.model) private var llmModel = ""
@State private var llmAPIKey = ""
@State private var llmKeyStored = false
private let llmCredentials = LLMCredentialsStore()
```

Insert a new `sectionLabel("AI 接口")` **above**「关于」:

- TextField Base URL (placeholder `https://api.openai.com/v1`)
- TextField Model (placeholder `gpt-4o`)
- SecureField API Key — show placeholder「已保存」when `llmKeyStored && llmAPIKey.isEmpty` is awkward; simpler: onAppear load key into `llmAPIKey` only for editing session, or leave blank with subtitle「已保存，输入新值可覆盖」
- Button「保存」→ `try? llmCredentials.saveAPIKey(trimmed)` if non-empty; toast「已保存」
- Button「清除密钥」→ `clearAPIKey()`; toast「已清除」
- Footnote Text: `图片会发送到你填写的接口地址，费用由该服务商向你收取。Gita 不托管密钥。`

Match existing `group` / padding / fonts.

- [ ] **Step 3: Manual / build verify**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Expected: BUILD SUCCEEDED. Launch app → 设置 → see AI 接口 section.

- [ ] **Step 4: Commit**

```bash
git add foxgita.xcodeproj/project.pbxproj foxgita/Features/Settings/SettingsView.swift foxgita/Localizable.xcstrings
git commit -m "feat: add AI API settings and photo library usage string"
```

---

### Task 7: RecommendSheet image → create → navigate

**Files:**
- Modify: `foxgita/Features/Practice/RecommendSheet.swift`
- Optionally touch: `foxgita/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ImageStepGenerator`, `LLMCredentialsStore`, `PracticeStore.createFromAIDraft`, PhotosUI
- Produces: UI entry「从图片生成练习」wired to existing `selection` + `dismiss()`

- [ ] **Step 1: Wire UI state**

```swift
import PhotosUI

@AppStorage(LLMSettingsKey.baseURL) private var llmBaseURL = ""
@AppStorage(LLMSettingsKey.model) private var llmModel = ""
@State private var pickerItems: [PhotosPickerItem] = []
@State private var showPicker = false
@State private var isGenerating = false
@State private var toast: String?
private let credentials = LLMCredentialsStore()
private let generator = ImageStepGenerator(client: VisionPracticeClient())
```

Add toast overlay like Settings (`ToastBanner`).

In「创建自己的练习」card, **below**「创建练习」button, add:

```swift
PhotosPicker(
    selection: $pickerItems,
    maxSelectionCount: 3,
    matching: .images
) {
    Text("从图片生成练习")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(GitaTheme.brand500)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
}
.disabled(isGenerating)
.onChange(of: pickerItems) { _, items in
    Task { await handlePicked(items) }
}

if isGenerating {
    Text("正在读图生成练习…")
        .font(.system(size: 12))
        .foregroundStyle(GitaTheme.textSecondary)
}
```

- [ ] **Step 2: Implement `handlePicked`**

```swift
@MainActor
private func handlePicked(_ items: [PhotosPickerItem]) async {
    guard !items.isEmpty else { return }
    guard !isGenerating else { return }

    let base = llmBaseURL
    let model = llmModel
    guard credentials.isConfigured(baseURL: base, model: model) else {
        toast = String(localized: "先去设置里填写 AI 接口")
        hideToastLater()
        pickerItems = []
        return
    }

    isGenerating = true
    defer {
        isGenerating = false
        pickerItems = []
    }

    do {
        var blobs: [Data] = []
        for item in items.prefix(3) {
            if let data = try await item.loadTransferable(type: Data.self) {
                blobs.append(data)
            }
        }
        let draft = try await generator.generate(
            imageData: blobs,
            baseURL: base,
            model: model,
            fallbackCategory: category
        )
        if let id = store.createFromAIDraft(draft) {
            selection = id
            dismiss()
        } else {
            toast = String(localized: "生成失败，请稍后重试")
            hideToastLater()
        }
    } catch let error as ImageStepGeneratorError {
        toast = message(for: error)
        hideToastLater()
    } catch {
        toast = String(localized: "生成失败，请稍后重试")
        hideToastLater()
    }
}
```

Map errors:

| Error | Toast |
|---|---|
| `notConfigured` | 先去设置里填写 AI 接口 |
| `noImages` | 请选择图片 |
| `tooManyImages` | 一次最多 3 张图片 |
| wrapped `unauthorized` | API Key 无效或无权限 |
| wrapped `invalidJSON` / `emptyContent` | 模型返回格式不对，可换模型或重试 |
| wrapped `transport` / other | 网络异常，请重试 |
| default | 生成失败，请稍后重试 |

Implement `message(for:)` accordingly (unwrap nested `VisionPracticeError` if you used `ImageStepGeneratorError.failed(VisionPracticeError)`).

- [ ] **Step 3: Build + smoke on simulator**

1. Settings → fill a real or dummy Base URL/Model/Key  
2. 练习 → 添加练习 → 从图片生成练习  
3. Without key: toast  
4. With mockable key: if no real API, at least UI loading path compiles  

- [ ] **Step 4: Commit**

```bash
git add foxgita/Features/Practice/RecommendSheet.swift foxgita/Localizable.xcstrings
git commit -m "feat: generate practice tasks from photos in RecommendSheet"
```

---

### Task 8: UI smoke + docs note

**Files:**
- Modify: `foxgitaUITests/PracticeFlowUITests.swift`
- Modify: `docs/TECHNICAL.md` (short bullet under practice / services)
- Modify: `docs/TEST_PLAN_CLI.md` only if test counts change materially

**Interfaces:** none new

- [ ] **Step 1: Add UI test**

```swift
    func testRecommendSheetShowsImageGenerateEntry() {
        let add = app.buttons["添加练习"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.staticTexts["推荐练习"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["从图片生成练习"].waitForExistence(timeout: 5)
            || app.staticTexts["从图片生成练习"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
    }
```

- [ ] **Step 2: Run UI + unit**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests \
  test

xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaUITests/PracticeFlowUITests/testRecommendSheetShowsImageGenerateEntry \
  test
```

Expected: PASS.

- [ ] **Step 3: Document in TECHNICAL.md**

Add under services / practice: one short subsection — RecommendSheet can generate tasks via user-configured OpenAI-compatible vision API; Keychain key; no image persistence. Link to spec path.

- [ ] **Step 4: Commit**

```bash
git add foxgitaUITests/PracticeFlowUITests.swift docs/TECHNICAL.md docs/TEST_PLAN_CLI.md
git commit -m "test: smoke image-generate entry and document AI practice flow"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|---|---|
| RecommendSheet entry | 7 |
| ≤3 photos | 5, 7 |
| OpenAI-compatible Base URL/Model/Key | 2, 3, 6 |
| Keychain + AppStorage | 2, 6 |
| Full field generation + normalize | 1, 3 |
| Direct create + open detail | 4, 7 |
| No schema / no image persist | 4, 5 |
| Error toasts | 7 |
| Privacy footnote | 6 |
| Unit: normalize / client / store | 1, 3, 4 |
| Photo usage string | 6 |
| Non-goals excluded | — (no tasks for B/C/OCR/wizard) |

## Placeholder / consistency self-review

- Retry test asserts exactly two HTTP calls (`count() == 2`).
- `VisionGenerating` defined in Task 3; Task 5 depends on it for stubs.
- Subtitle format locked: `AI · \(minutes) 分钟`.
- Settings keys locked: `gita.llm.baseURL` / `gita.llm.model` / Keychain service `com.haizei.foxgita.llm`.
