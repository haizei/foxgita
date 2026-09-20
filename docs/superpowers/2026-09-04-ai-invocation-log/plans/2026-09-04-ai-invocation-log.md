# AI Invocation Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist one metadata row per AI Skill attempt, backfill accept/edit/regenerate/abandon/complete for photo and next-session, and show a read-only debug list in Settings.

**Architecture:** Schema V13 adds `AIInvocationLog`. Clients and generators write through a Sendable `AIInvocationRecording` protocol; sheets and `PracticeStore` later update the same row. `AITransport` and memory context only return extra metadata (`formatRetryUsed`, injected Memory IDs). No Key, Prompt, response, or media is stored.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing (`@Test` / `#expect`), existing `foxgita` scheme. Nested git repo at `/Users/haizei/work/AI/program/gita/foxgita` (gitignored by the docs repo). All implementation commits happen in that nested repo.

## Global Constraints

- Spec: `foxgita/docs/superpowers/2026-09-04-ai-invocation-log/specs/2026-09-04-ai-invocation-log-design.md`
- Current live schema is `GitaSchemaV12`; this work adds **V13**, not another V12
- One SwiftData table; outcomes are field updates, not a second event table
- Do not store API Key, Base URL, Prompt, model response, or media bytes/paths
- Write-log failures are swallowed; they must not set `PracticeStore.lastError` or change user-visible generate/save results
- `taskId` is `PracticeItem.id.uuidString`, never old `TaskItem.id`
- Photo / next-session reuse existing `generationId` as `invocationId`
- Review / diagnosis log calls only; `draftOutcomeRaw` stays empty
- Completion = first time `PracticeItemRules.isEffective` is true; `finishSession` does not write AI logs
- Keep 200 newest rows per `profileId`; prune only on insert
- New Swift files under `foxgita/foxgita/` are picked up by the synchronized Xcode group; do not edit `project.pbxproj`
- Run tests from the nested repo: `cd /Users/haizei/work/AI/program/gita/foxgita`
- Test command shape: `xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/<TestFile>`
- If the simulator name differs, substitute the available iPhone simulator; do not skip tests

## File structure

- Create: `foxgita/foxgita/Models/SchemaV13.swift` — V12 models plus `AIInvocationLog`
- Create: `foxgita/foxgita/Services/AIInvocationTypes.swift` — status / error / outcome enums, record input, recording protocol
- Create: `foxgita/foxgita/Services/AIInvocationStore.swift` — insert, outcome, complete, prune, recent
- Create: `foxgita/foxgita/Services/AIDraftOutcomeRules.swift` — accepted vs edited
- Create: `foxgita/foxgita/Features/Settings/AIInvocationLogPresentation.swift` — row copy for the debug list
- Create: `foxgita/foxgita/Features/Settings/AIInvocationLogView.swift` — read-only list
- Create: `foxgita/foxgitaTests/AIInvocationStoreTests.swift`
- Create: `foxgita/foxgitaTests/AIDraftOutcomeRulesTests.swift`
- Create: `foxgita/foxgitaTests/AIInvocationLogPresentationTests.swift`
- Modify: `foxgita/foxgita/Models/Models.swift` — typealiases + V12→V13 migration
- Modify: `foxgita/foxgita/foxgitaApp.swift` — boot V13, inject store
- Modify: `foxgita/foxgita/Services/AITransport.swift` — return `AITransportResult`
- Modify: `foxgita/foxgita/Services/MemoryContextBuilder.swift` — snapshot with kept IDs
- Modify: `foxgita/foxgita/Services/MemoryContextProviding.swift` — `MemoryPromptSnapshot` + `snapshot`
- Modify: four `*Client.swift` + four Generator files — `invocationId` + record
- Modify: `NextSessionSheet.swift`, `PhotoPracticeSheet.swift`, `ReviewJobRunner.swift`, `PracticeStore.swift`, `SettingsView.swift`
- Modify: existing Client / Transport / Memory tests for new return types and `invocationId`
- Modify: in-memory tests that currently open `GitaSchemaV12` as the **current** schema → `GitaSchemaV13` (keep V12 as a historical source schema in `MigrationTests`)

---

### Task 1: Schema V13 and typealiases

**Files:**
- Create: `foxgita/foxgita/Models/SchemaV13.swift`
- Modify: `foxgita/foxgita/Models/Models.swift`
- Modify: `foxgita/foxgita/foxgitaApp.swift` (schema line only)
- Modify: `foxgita/foxgitaTests/MigrationTests.swift`
- Modify: every in-memory test that opens **current** schema as `GitaSchemaV12.self` (not historical V12 source stores)

**Interfaces:**
- Consumes: `GitaSchemaV12` model list and field-for-field copies
- Produces: `GitaSchemaV13` including `AIInvocationLog`; `typealias AIInvocationLog = GitaSchemaV13.AIInvocationLog`; `GitaMigrationPlan` includes V12→V13 lightweight

- [ ] **Step 1: Copy V12 and add the log model**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
cp foxgita/Models/SchemaV12.swift foxgita/Models/SchemaV13.swift
```

In `SchemaV13.swift` replace `SchemaV12` / `GitaSchemaV12` / `Version(12, 0, 0)` with `SchemaV13` / `GitaSchemaV13` / `Version(13, 0, 0)`. Update the `models` array and append this class **after** `Project`:

```swift
    @Model
    final class AIInvocationLog {
        @Attribute(.unique) var id: String
        var profileId: String
        var skillId: String
        var skillVersion: String
        var model: String
        var startedAt: Date
        var durationMs: Int
        var statusRaw: String
        var errorTypeRaw: String
        var memoryIdsRaw: String
        var formatRetryUsed: Bool
        var draftOutcomeRaw: String
        var taskId: String
        var completedAt: Date?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: String,
            profileId: String,
            skillId: String,
            skillVersion: String,
            model: String,
            startedAt: Date,
            durationMs: Int,
            statusRaw: String,
            errorTypeRaw: String = "",
            memoryIdsRaw: String = "",
            formatRetryUsed: Bool = false,
            draftOutcomeRaw: String = "",
            taskId: String = "",
            completedAt: Date? = nil,
            now: Date = Date()
        ) {
            self.id = id
            self.profileId = profileId
            self.skillId = skillId
            self.skillVersion = skillVersion
            self.model = model
            self.startedAt = startedAt
            self.durationMs = durationMs
            self.statusRaw = statusRaw
            self.errorTypeRaw = errorTypeRaw
            self.memoryIdsRaw = memoryIdsRaw
            self.formatRetryUsed = formatRetryUsed
            self.draftOutcomeRaw = draftOutcomeRaw
            self.taskId = taskId
            self.completedAt = completedAt
            self.createdAt = now
            self.updatedAt = now
        }
    }
```

`models` must be:

```swift
[TaskItem.self, PracticeSession.self, RecordingRef.self, LocalProfile.self, MemoryItem.self, PracticeItem.self, Project.self, AIInvocationLog.self]
```

Every `\GitaSchemaV12.` relationship inside this new file must already have become `\GitaSchemaV13.` from the rename.

- [ ] **Step 2: Point Models.swift and the app at V13**

In `Models.swift` change the seven existing typealiases and add:

```swift
typealias AIInvocationLog = GitaSchemaV13.AIInvocationLog
```

Append to the migration comment: `V12 → V13 adds AIInvocationLog`.

Add `GitaSchemaV13.self` to `GitaMigrationPlan.schemas` and:

```swift
.lightweight(fromVersion: GitaSchemaV12.self, toVersion: GitaSchemaV13.self),
```

In `foxgitaApp.swift` change `Schema(versionedSchema: GitaSchemaV12.self)` to `GitaSchemaV13.self`.

- [ ] **Step 3: Write the failing/updated migration assertion**

In `MigrationTests.swift`, the last hop that currently reopens as V12 must reopen as V13. Add this test (or extend the existing V11→V12 hop):

```swift
@Test func v12StoreMigratesToV13AndAcceptsInvocationLog() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("gita-v12-v13-\(UUID().uuidString).store")
    defer { try? FileManager.default.removeItem(at: url) }

    do {
        let v12 = Schema(versionedSchema: GitaSchemaV12.self)
        let container = try ModelContainer(
            for: v12, configurations: [ModelConfiguration(schema: v12, url: url)]
        )
        let context = ModelContext(container)
        context.insert(GitaSchemaV12.TaskItem(
            id: "warm", title: "指尖热身", subtitle: "",
            category: .left, targetMin: 5
        ))
        try context.save()
    }

    let v13 = Schema(versionedSchema: GitaSchemaV13.self)
    let container = try ModelContainer(
        for: v13, migrationPlan: GitaMigrationPlan.self,
        configurations: [ModelConfiguration(schema: v13, url: url)]
    )
    let context = ModelContext(container)
    let tasks = try context.fetch(FetchDescriptor<TaskItem>())
    #expect(tasks.map(\.id) == ["warm"])

    let log = AIInvocationLog(
        id: "inv-1", profileId: "p1",
        skillId: SkillID.nextSession, skillVersion: "1.0.0",
        model: "gpt-4o", startedAt: Date(), durationMs: 10,
        statusRaw: "success"
    )
    context.insert(log)
    try context.save()
    #expect(try context.fetch(FetchDescriptor<AIInvocationLog>()).count == 1)
}
```

- [ ] **Step 4: Point current in-memory containers at V13**

Replace `GitaSchemaV12.self` with `GitaSchemaV13.self` only where the container is the **live** schema (Memory / Practice / Candidate / Consent / Duration tests). Leave historical `GitaSchemaV12` source-store blocks in `MigrationTests` unchanged.

- [ ] **Step 5: Run migration + one in-memory suite**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/MigrationTests -only-testing:foxgitaTests/MemoryStoreTests
```

Expected: PASS, including the new V12→V13 test.

- [ ] **Step 6: Commit in the foxgita repo**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Models/SchemaV13.swift foxgita/Models/Models.swift foxgita/foxgitaApp.swift foxgitaTests
git commit -m "feat: add schema V13 AIInvocationLog"
```

---

### Task 2: AIInvocationStore

**Files:**
- Create: `foxgita/foxgita/Services/AIInvocationTypes.swift`
- Create: `foxgita/foxgita/Services/AIInvocationStore.swift`
- Test: `foxgita/foxgitaTests/AIInvocationStoreTests.swift`

**Interfaces:**
- Consumes: `AIInvocationLog`, active `LocalProfile.id`
- Produces:

```swift
enum AIInvocationStatus: String, Sendable { case success, failure }

enum AIInvocationErrorType: String, Sendable {
    case notConfigured, invalidURL, unauthorized, httpStatus
    case emptyContent, invalidJSON, timeout, transport
    case unregisteredSkill, cancelled
}

enum AIDraftOutcome: String, Sendable {
    case accepted, edited, regenerated, abandoned
}

struct AIInvocationRecordInput: Equatable, Sendable {
    var id: String
    var skillId: String
    var skillVersion: String
    var model: String
    var startedAt: Date
    var durationMs: Int
    var status: AIInvocationStatus
    var errorType: AIInvocationErrorType?
    var memoryIds: [String]
    var formatRetryUsed: Bool
    var draftOutcome: AIDraftOutcome?
}

protocol AIInvocationRecording: Sendable {
    func record(_ input: AIInvocationRecordInput) async
}

struct EmptyAIInvocationLog: AIInvocationRecording {
    func record(_ input: AIInvocationRecordInput) async {}
}

@MainActor
final class AIInvocationStore {
    init(context: ModelContext)
    func record(_ input: AIInvocationRecordInput, now: Date = Date())
    func setDraftOutcome(id: String, outcome: AIDraftOutcome, taskId: String?, now: Date = Date())
    func markCompleted(taskId: String, now: Date)
    func recent(limit: Int = 200) -> [AIInvocationLog]
    static func errorType(from error: Error) -> AIInvocationErrorType
    static func debugBlob(of log: AIInvocationLog) -> String
}

@MainActor
final class LiveAIInvocationLog: AIInvocationRecording {
    init(store: AIInvocationStore)
    func record(_ input: AIInvocationRecordInput) async
}
```

`record` reads the active profile id (`LocalProfile.isActive == true`). Empty profile id → no-op. Duplicate `id` → ignore insert (do not clear `draftOutcome` / `completedAt`). After a successful insert, delete older rows for that `profileId` beyond 200 newest `startedAt`. All methods swallow SwiftData errors. `debugBlob` concatenates `id`, `profileId`, `skillId`, `skillVersion`, `model`, `statusRaw`, `errorTypeRaw`, `memoryIdsRaw`, `draftOutcomeRaw`, `taskId` only.

`errorType(from:)`: `CancellationError` or `URLError.cancelled` → `.cancelled`; map every `VisionPracticeError` case; anything else → `.transport`. `.httpStatus` stores the name only.

`LiveAIInvocationLog.record` calls `store.record(input)` on the main actor.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct AIInvocationStoreTests {
    private func makeStore() throws -> (AIInvocationStore, ModelContext) {
        let schema = Schema(versionedSchema: GitaSchemaV13.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        profile.isActive = true
        context.insert(profile)
        try context.save()
        return (AIInvocationStore(context: context), context)
    }

    private func input(
        id: String,
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        status: AIInvocationStatus = .success,
        error: AIInvocationErrorType? = nil,
        memoryIds: [String] = ["m1"],
        outcome: AIDraftOutcome? = nil
    ) -> AIInvocationRecordInput {
        AIInvocationRecordInput(
            id: id,
            skillId: SkillID.nextSession,
            skillVersion: SkillDefinition.nextSession.version,
            model: "gpt-4o",
            startedAt: startedAt,
            durationMs: 42,
            status: status,
            errorType: error,
            memoryIds: memoryIds,
            formatRetryUsed: false,
            draftOutcome: outcome
        )
    }

    @Test func recordSuccessThenPrivacyBlobHasNoSecrets() throws {
        let (store, _) = try makeStore()
        store.record(input(id: "inv-1"))
        let row = try #require(store.recent().first)
        #expect(row.statusRaw == "success")
        #expect(row.errorTypeRaw.isEmpty)
        #expect(row.skillId == SkillID.nextSession)
        #expect(row.memoryIdsRaw == "m1")
        let blob = AIInvocationStore.debugBlob(of: row)
        #expect(!blob.contains("sk-"))
        #expect(!blob.contains("Bearer"))
        #expect(!blob.contains("BACKGROUND_MEMORY"))
        #expect(!blob.contains("data:image"))
    }

    @Test func recordFailureKeepsErrorTypeAndDuplicateInsertIsIgnored() throws {
        let (store, _) = try makeStore()
        store.record(input(id: "inv-1", status: .failure, error: .invalidJSON, outcome: .abandoned))
        store.record(input(id: "inv-1", status: .success))
        let rows = store.recent()
        #expect(rows.count == 1)
        #expect(rows[0].statusRaw == "failure")
        #expect(rows[0].errorTypeRaw == "invalidJSON")
        #expect(rows[0].draftOutcomeRaw == "abandoned")
    }

    @Test func setDraftOutcomeAndCompleteOnce() throws {
        let (store, _) = try makeStore()
        store.record(input(id: "inv-1"))
        let itemId = UUID()
        store.setDraftOutcome(id: "inv-1", outcome: .accepted, taskId: itemId.uuidString)
        let first = Date(timeIntervalSince1970: 1_700_000_100)
        store.markCompleted(taskId: itemId.uuidString, now: first)
        store.markCompleted(taskId: itemId.uuidString, now: first.addingTimeInterval(60))
        let row = try #require(store.recent().first)
        #expect(row.draftOutcomeRaw == "accepted")
        #expect(row.taskId == itemId.uuidString)
        #expect(row.completedAt == first)
    }

    @Test func pruneKeeps200NewestPerProfile() throws {
        let (store, _) = try makeStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<201 {
            store.record(input(
                id: "inv-\(i)",
                startedAt: base.addingTimeInterval(TimeInterval(i))
            ))
        }
        let rows = store.recent()
        #expect(rows.count == 200)
        #expect(rows.first?.id == "inv-200")
        #expect(rows.last?.id == "inv-1")
        #expect(!rows.contains(where: { $0.id == "inv-0" }))
    }

    @Test func mapsCancelledAndUnknownErrors() {
        #expect(AIInvocationStore.errorType(from: CancellationError()) == .cancelled)
        #expect(AIInvocationStore.errorType(from: URLError(.cancelled)) == .cancelled)
        #expect(AIInvocationStore.errorType(from: VisionPracticeError.unauthorized) == .unauthorized)
        #expect(AIInvocationStore.errorType(from: VisionPracticeError.httpStatus(502)) == .httpStatus)
        #expect(AIInvocationStore.errorType(from: NSError(domain: "x", code: 1)) == .transport)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/AIInvocationStoreTests
```

Expected: FAIL — `AIInvocationStore` / types not found.

- [ ] **Step 3: Write the types and store**

Implement the interfaces above. `record` insert path:

```swift
func record(_ input: AIInvocationRecordInput, now: Date = Date()) {
    do {
        guard let profileId = try activeProfileId(), !profileId.isEmpty else { return }
        let existing = try context.fetch(
            FetchDescriptor<AIInvocationLog>(predicate: #Predicate { $0.id == input.id })
        )
        if !existing.isEmpty { return }
        context.insert(AIInvocationLog(
            id: input.id,
            profileId: profileId,
            skillId: input.skillId,
            skillVersion: input.skillVersion,
            model: input.model,
            startedAt: input.startedAt,
            durationMs: input.durationMs,
            statusRaw: input.status.rawValue,
            errorTypeRaw: input.errorType?.rawValue ?? "",
            memoryIdsRaw: input.memoryIds.joined(separator: ","),
            formatRetryUsed: input.formatRetryUsed,
            draftOutcomeRaw: input.draftOutcome?.rawValue ?? "",
            now: now
        ))
        try context.save()
        try prune(profileId: profileId)
    } catch {
        return
    }
}
```

`setDraftOutcome` updates `draftOutcomeRaw`, optional `taskId`, `updatedAt`. `markCompleted` fetches `taskId ==` and `completedAt == nil`, sets `completedAt` once. `recent` filters active `profileId`, sorts `startedAt` descending.

- [ ] **Step 4: Run tests to verify they pass**

Same `xcodebuild` command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Services/AIInvocationTypes.swift foxgita/Services/AIInvocationStore.swift foxgitaTests/AIInvocationStoreTests.swift
git commit -m "feat: persist AI invocation rows without secrets"
```

---

### Task 3: Transport result and memory snapshot IDs

**Files:**
- Modify: `foxgita/foxgita/Services/AITransport.swift`
- Modify: `foxgita/foxgita/Services/MemoryContextBuilder.swift`
- Modify: `foxgita/foxgita/Services/MemoryContextProviding.swift`
- Modify: `foxgita/foxgitaTests/AITransportTests.swift`
- Modify: `foxgita/foxgitaTests/MemoryContextBuilderTests.swift`
- Modify: four Client files only enough to compile (read `.content`) if Task 4 has not landed yet — prefer finishing this task's call-site compile in the same step
- Test: existing Transport / Builder tests

**Interfaces:**
- Consumes: current `complete(...) -> String` and `block(items:now:) -> String`
- Produces:

```swift
struct AITransportResult: Equatable, Sendable {
    var content: String
    var formatRetryUsed: Bool
}

struct MemoryPromptSnapshot: Equatable, Sendable {
    var block: String
    var itemIds: [String]
}

enum MemoryContextBuilder {
    static func snapshot(items: [MemoryItem], now: Date) -> MemoryPromptSnapshot
    static func block(items: [MemoryItem], now: Date) -> String
}

protocol MemoryContextProviding: Sendable {
    func block(skill: SkillDefinition, query: String) async -> String
    func snapshot(skill: SkillDefinition, query: String) async -> MemoryPromptSnapshot
}
```

Default protocol snapshot: `MemoryPromptSnapshot(block: await block(skill:query:), itemIds: [])` so `StubMemoryContext` keeps compiling. `EmptyMemoryContext.snapshot` returns empty block + empty IDs. `LiveMemoryContext.build` uses `MemoryContextBuilder.snapshot` and `block` returns `snapshot.block`.

Builder `snapshot` keeps the same sort / dedupe / 800-char budget as `block`, but each kept line tracks `item.id`. `block` becomes `snapshot(...).block`.

Recursive `complete` retry sets `formatRetryUsed: true`. First-success path is `false`. Map `URLError.cancelled` to a thrown error the Client already treats as cancel (`CancellationError()` or keep `URLError`; Store mapper accepts both). Prefer throwing `CancellationError()` from `mapSessionError` when `URLError.cancelled` so Clients can `catch is CancellationError`.

- [ ] **Step 1: Update Transport tests to the new return type**

Change every `try await makeTransport().complete(...)` assignment / throw site:

```swift
let result = try await makeTransport().complete(...)
#expect(result.content == "```json\n{\"ok\":true}\n```")
#expect(result.formatRetryUsed == false)
```

In `completeRetriesOnceWithoutResponseFormat`:

```swift
#expect(result.content == "{\"x\":1}")
#expect(result.formatRetryUsed == true)
```

Add builder test:

```swift
@Test func snapshotKeepsOnlyBudgetedIds() {
    let kept = MemoryItem(
        profileId: "p", kind: .goal, key: "goal.small", summaryText: "短",
        sourceType: "t", sourceId: "a", confidence: 1, importance: 1
    )
    let dropped = MemoryItem(
        profileId: "p", kind: .goal, key: "goal.huge",
        summaryText: String(repeating: "字", count: 900),
        sourceType: "t", sourceId: "b", confidence: 1, importance: 0.1
    )
    let snap = MemoryContextBuilder.snapshot(items: [kept, dropped], now: Date())
    #expect(snap.itemIds == [kept.id])
    #expect(snap.block.contains("短"))
    #expect(!snap.block.contains(String(repeating: "字", count: 20)))
}
```

Because importance sorts `kept` first, the huge line is considered second and should be dropped by budget.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/AITransportTests -only-testing:foxgitaTests/MemoryContextBuilderTests
```

Expected: FAIL on `AITransportResult` / `snapshot` missing, or compile errors on `String` vs struct.

- [ ] **Step 3: Implement result + snapshot**

Change `complete` signature to `async throws -> AITransportResult`. After a successful decode:

```swift
return AITransportResult(content: content, formatRetryUsed: false)
```

On the recursive retry call, return `AITransportResult(content: nested.content, formatRetryUsed: true)`.

Update every Client `rawContent = try await transport.complete(...)` to `let result = try await transport.complete(...); let rawContent = result.content`.

Implement builder `snapshot` by pairing line + id during the keep loop.

- [ ] **Step 4: Run tests to verify they pass**

Same command plus:

```bash
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/NextSessionClientTests -only-testing:foxgitaTests/VisionPracticeClientTests -only-testing:foxgitaTests/MediaReviewClientTests -only-testing:foxgitaTests/VideoDiagnosisClientTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Services/AITransport.swift foxgita/Services/MemoryContextBuilder.swift foxgita/Services/MemoryContextProviding.swift foxgita/Services/*Client.swift foxgitaTests
git commit -m "feat: return transport retry flag and memory ids"
```

---

### Task 4: Record every Skill attempt

**Files:**
- Modify: `foxgita/foxgita/Services/NextSessionClient.swift`
- Modify: `foxgita/foxgita/Services/VisionPracticeClient.swift`
- Modify: `foxgita/foxgita/Services/MediaReviewClient.swift`
- Modify: `foxgita/foxgita/Services/VideoDiagnosisClient.swift`
- Modify: `foxgita/foxgita/Services/NextSessionGenerator.swift`
- Modify: `foxgita/foxgita/Services/ImageStepGenerator.swift`
- Modify: `foxgita/foxgita/Services/MediaReviewGenerator.swift`
- Modify: `foxgita/foxgita/Services/VideoDiagnosisGenerator.swift`
- Modify: `foxgita/foxgita/Services/ReviewJobRunner.swift`
- Modify: corresponding `*ClientTests.swift` / generator tests
- Test: add recording-spy cases on `NextSessionClientTests` and `NextSessionGeneratorTests` (or `ImageStepGeneratorTests`)

**Interfaces:**
- Consumes: `AIInvocationRecording`, `AIInvocationRecordInput`, `MemoryPromptSnapshot`, `AITransportResult`
- Produces: each `generateDraft` / `generateReview` / `generateDiagnosis` gains `invocationId: String`; each Client/Generator init gains `log: any AIInvocationRecording = EmptyAIInvocationLog()`; ReviewJobRunner passes a fresh UUID per recording into the generator

Helper used by all four Clients (put in `AIInvocationTypes.swift`):

```swift
enum AIInvocationClientRecord {
    static func make(
        id: String,
        skill: SkillDefinition,
        model: String,
        startedAt: Date,
        status: AIInvocationStatus,
        error: Error?,
        memoryIds: [String],
        formatRetryUsed: Bool
    ) -> AIInvocationRecordInput {
        let cancelled = error.map { AIInvocationStore.errorType(from: $0) } == .cancelled
        let practiceSkill = skill.id == SkillID.nextSession || skill.id == SkillID.planFromImage
        return AIInvocationRecordInput(
            id: id,
            skillId: skill.id,
            skillVersion: skill.version,
            model: model,
            startedAt: startedAt,
            durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1000)),
            status: status,
            errorType: error.map(AIInvocationStore.errorType(from:)),
            memoryIds: memoryIds,
            formatRetryUsed: formatRetryUsed,
            draftOutcome: (cancelled && practiceSkill) ? .abandoned : nil
        )
    }
}
```

Client algorithm:

1. `let startedAt = Date()`
2. Resolve skill; on `unregisteredSkill` / `invalidURL` record failure then throw
3. `let snap = await memory.snapshot(skill:query:)`
4. Call transport
5. On `CancellationError` / mapped cancelled: record failure+cancelled (+ abandoned for photo/next) then rethrow
6. On other errors: record failure then rethrow
7. On parse/empty failure: record then throw
8. On success: record success with `snap.itemIds` and `result.formatRetryUsed`

Generator `notConfigured` (all four):

```swift
let skill = SkillRegistry.builtin.skill(id: SkillID.nextSession)! // correct id per generator
await log.record(AIInvocationRecordInput(
    id: invocationId,
    skillId: skill.id,
    skillVersion: skill.version,
    model: model,
    startedAt: Date(),
    durationMs: 0,
    status: .failure,
    errorType: .notConfigured,
    memoryIds: [],
    formatRetryUsed: false,
    draftOutcome: nil
))
throw NextSessionGeneratorError.notConfigured
```

`NextSessionGenerator.generate` and `ImageStepGenerator.generate` gain `invocationId: String`. Media / video generators gain the same argument and pass it to the Client. `ReviewJobRunner` does `let invocationId = UUID().uuidString` per recording and passes it into `review` / `diagnose`.

Existing Client tests: add `invocationId: "inv-test"` to every `generateDraft` / `generateReview` / `generateDiagnosis` call.

- [ ] **Step 1: Write spy tests**

Add a test-only spy in `NextSessionClientTests.swift`:

```swift
final class InvocationLogSpy: AIInvocationRecording, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var inputs: [AIInvocationRecordInput] = []
    func record(_ input: AIInvocationRecordInput) async {
        lock.lock(); inputs.append(input); lock.unlock()
    }
}
```

```swift
@Test func generateDraftRecordsSuccessWithoutSecrets() async throws {
    let spy = InvocationLogSpy()
    // same 200 payload as generateDraftReplacesMinutesAndCaps
    MockURLProtocol.handler = { _ in (200, data) }
    defer { MockURLProtocol.handler = nil }
    let client = NextSessionClient(
        session: URLSession(configuration: config),
        log: spy
    )
    _ = try await client.generateDraft(
        ...,
        invocationId: "inv-ok"
    )
    let row = try #require(spy.inputs.first)
    #expect(row.id == "inv-ok")
    #expect(row.status == .success)
    #expect(row.errorType == nil)
    #expect(row.skillId == SkillID.nextSession)
}

@Test func unregisteredSkillRecordsFailureAndSendsNoRequest() async {
    let spy = InvocationLogSpy()
    var calls = 0
    MockURLProtocol.handler = { _ in calls += 1; return (200, Data()) }
    defer { MockURLProtocol.handler = nil }
    let client = NextSessionClient(
        session: URLSession(configuration: config),
        registry: SkillRegistry(skills: []),
        log: spy
    )
    await #expect(throws: VisionPracticeError.unregisteredSkill) {
        try await client.generateDraft(..., invocationId: "inv-miss")
    }
    #expect(calls == 0)
    #expect(spy.inputs.first?.errorType == .unregisteredSkill)
}
```

Add `NextSessionGenerator` test (extend `NextSessionGeneratorTests.swift`):

```swift
@Test func notConfiguredRecordsAndDoesNotCallClient() async {
    let spy = InvocationLogSpy()
    let client = ExplodingNextSessionClient() // existing or a stub that fatalErrors / counts calls
    let generator = NextSessionGenerator(client: client, credentials: emptyStore, log: spy)
    await #expect(throws: NextSessionGeneratorError.notConfigured) {
        try await generator.generate(
            budgetMinutes: 20, baseURL: "", model: "", fallbackCategory: .chord,
            invocationId: "inv-cfg"
        )
    }
    #expect(spy.inputs.first?.errorType == .notConfigured)
}
```

If the generator tests file has no exploding client, use a local `final class CountingClient: NextSessionGenerating` whose `generateDraft` increments a counter; expect counter == 0.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/NextSessionClientTests -only-testing:foxgitaTests/NextSessionGeneratorTests
```

Expected: FAIL — missing `invocationId` / `log` / record calls.

- [ ] **Step 3: Wire Clients, Generators, ReviewJobRunner**

Add `log` + `invocationId` everywhere listed. Record in a `defer` only if you also set a `didRecord` flag; do not double-record. Prefer explicit record-then-throw at each exit.

`ReviewJobRunner` signature change stays internal; tests that construct it keep compiling if `invocationId` is created inside the runner rather than on `enqueue`.

- [ ] **Step 4: Run Client + Generator + ReviewJobRunner tests**

```bash
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/NextSessionClientTests -only-testing:foxgitaTests/VisionPracticeClientTests -only-testing:foxgitaTests/MediaReviewClientTests -only-testing:foxgitaTests/VideoDiagnosisClientTests -only-testing:foxgitaTests/NextSessionGeneratorTests -only-testing:foxgitaTests/ReviewJobRunnerTests
```

Expected: PASS. Review/diagnosis spy is optional if NextSession covers record-on-success/failure; still pass `invocationId` through those Clients so production records.

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Services foxgitaTests
git commit -m "feat: record AI skill attempts on success and failure"
```

---

### Task 5: Draft outcomes for next session and photo

**Files:**
- Create: `foxgita/foxgita/Services/AIDraftOutcomeRules.swift`
- Modify: `foxgita/foxgita/Features/Practice/NextSessionSheet.swift`
- Modify: `foxgita/foxgita/Features/Practice/PhotoPracticeSheet.swift`
- Modify: `foxgita/foxgita/foxgitaApp.swift` — `@Environment(AIInvocationStore.self)`
- Test: `foxgita/foxgitaTests/AIDraftOutcomeRulesTests.swift`

**Interfaces:**
- Consumes: `AIInvocationStore.setDraftOutcome`, `generationId` as invocation id
- Produces:

```swift
enum AIDraftOutcomeRules {
    static func normalizedSteps(_ steps: [String]) -> [String]
    static func confirm(
        originalTitle: String,
        originalMinutes: Int,
        originalSteps: [String],
        editTitle: String,
        editMinutes: Int,
        editSteps: [String]
    ) -> AIDraftOutcome
}
```

`normalizedSteps`: trim, drop empties. `confirm` returns `.accepted` when title (trimmed), minutes, and normalized steps are equal; otherwise `.edited`.

Sheet rules (exact):

- Next session `beginGeneration`: pass `generationId` as `invocationId`. If leaving an existing preview (phase was `.preview`), call `setDraftOutcome(id: previousGenerationId, outcome: .regenerated, taskId: nil)` **before** assigning a new `generationId`.
- Next session `confirm` after successful `commitDraft`: `setDraftOutcome(id: generationId, outcome: AIDraftOutcomeRules.confirm(...), taskId: item.id.uuidString)` using the draft applied in `applyDraft` as the original.
- Next session `close` / `onDisappear` while `phase == .preview`: `setDraftOutcome(..., .abandoned, taskId: nil)` once. Use a `didFinishOutcome` flag so confirm + disappear does not overwrite `accepted` with `abandoned`.
- Next session `close` while generating: cancel task; Client records cancelled+abandoned. Sheet does not write a second row.
- Photo `generate` after `entryGate.submit`: `setDraftOutcome(id: generationId, outcome: .accepted, taskId: item.id.uuidString)`.
- Photo close while generating: cancel only.
- Duration / source phase with no generation: no store writes.
- Consent decline (`gate != .proceed`): no store writes.

Keep original draft fields on NextSessionSheet (`appliedTitle`, `appliedMinutes`, `appliedSteps`) set in `applyDraft`.

- [ ] **Step 1: Write rules tests**

```swift
@Test func confirmDetectsEditAndIgnoresEmptySteps() {
    #expect(
        AIDraftOutcomeRules.confirm(
            originalTitle: "F 和弦", originalMinutes: 20, originalSteps: ["热身", "重点"],
            editTitle: "F 和弦", editMinutes: 20, editSteps: ["热身", "重点", "  "]
        ) == .accepted
    )
    #expect(
        AIDraftOutcomeRules.confirm(
            originalTitle: "F 和弦", originalMinutes: 20, originalSteps: ["热身"],
            editTitle: "F 和弦", editMinutes: 15, editSteps: ["热身"]
        ) == .edited
    )
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/AIDraftOutcomeRulesTests
```

Expected: FAIL — type missing.

- [ ] **Step 3: Implement rules and sheet hooks**

Create `AIInvocationStore` in `foxgitaApp` (`AIInvocationStore(context: container.mainContext)`), `.environment(invocationStore)`, and pass `LiveAIInvocationLog(store:)` into the four production Clients/Generators.

Sheets: `@Environment(AIInvocationStore.self)`.

- [ ] **Step 4: Run rules + existing practice entry tests**

```bash
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/AIDraftOutcomeRulesTests -only-testing:foxgitaTests/PracticeStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Services/AIDraftOutcomeRules.swift foxgita/Features/Practice/NextSessionSheet.swift foxgita/Features/Practice/PhotoPracticeSheet.swift foxgita/foxgitaApp.swift foxgitaTests/AIDraftOutcomeRulesTests.swift
git commit -m "feat: record accept edit regenerate and abandon"
```

---

### Task 6: Mark complete on first effective PracticeItem

**Files:**
- Modify: `foxgita/foxgita/Services/PracticeStore.swift`
- Test: `foxgita/foxgitaTests/PracticeStoreTests.swift` (new tests at the end)

**Interfaces:**
- Consumes: `AIInvocationStore.markCompleted(taskId:now:)`
- Produces: `PracticeStore` init gains `invocationStore: AIInvocationStore? = nil`. After `savePracticeItem` and `attachRecording` persist, if the live item is effective, call `invocationStore?.markCompleted(taskId: item.id.uuidString, now: now)`. `savePracticeItem` already has `now`. `attachRecording` should use `Date()` unless you add a `now:` parameter; add `now: Date = Date()` to `attachRecording` so tests can pin time.

Do not call markCompleted from `finishSession`. Do not change `lastError` if markCompleted throws (it swallows anyway).

- [ ] **Step 1: Write the failing tests**

Reuse the existing in-memory PracticeStore fixture in `PracticeStoreTests.swift`. After creating a store, also build `AIInvocationStore` on the **same** `ModelContext`, insert an active profile, `record` a success row, `setDraftOutcome(..., taskId: item.id.uuidString)`, then:

```swift
@Test func savePracticeItemMarksInvocationCompleteOnce() throws {
    // create today item via existing helper; record log with that item id
    try store.savePracticeItem(id: item.id, durationSeconds: 0, note: "", now: now)
    #expect(invocationStore.recent().first?.completedAt == nil)
    try store.savePracticeItem(id: item.id, durationSeconds: 60, note: "", now: now)
    let first = try #require(invocationStore.recent().first?.completedAt)
    try store.savePracticeItem(id: item.id, durationSeconds: 90, note: "", now: now.addingTimeInterval(60))
    #expect(invocationStore.recent().first?.completedAt == first)
}
```

If constructing `PracticeStore` + `AIInvocationStore` on one context is awkward in this file, add a focused `PracticeStoreInvocationTests.swift` that copies the smallest container helper from `PracticeStoreTests` (schema V13, `SwiftDataPracticeRepository`, `PracticeStore(repository:invocationStore:)`).

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/PracticeStoreTests
```

Expected: FAIL — `invocationStore` argument missing or `completedAt` still nil.

- [ ] **Step 3: Implement the hook**

```swift
private func markInvocationIfEffective(_ item: PracticeItem, now: Date) {
    let snap = PracticeStore.snapshot(from: item)
    guard PracticeItemRules.isEffective(snap) else { return }
    invocationStore?.markCompleted(taskId: item.id.uuidString, now: now)
}
```

Call after successful persist in `savePracticeItem` and `attachRecording`. Wire `invocationStore` in `foxgitaApp` `PracticeStore(...)`.

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/PracticeStoreTests -only-testing:foxgitaTests/AIInvocationStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Services/PracticeStore.swift foxgita/foxgitaApp.swift foxgitaTests
git commit -m "feat: mark AI suggestion complete on first effective practice"
```

---

### Task 7: Settings debug list

**Files:**
- Create: `foxgita/foxgita/Features/Settings/AIInvocationLogPresentation.swift`
- Create: `foxgita/foxgita/Features/Settings/AIInvocationLogView.swift`
- Modify: `foxgita/foxgita/Features/Settings/SettingsView.swift`
- Test: `foxgita/foxgitaTests/AIInvocationLogPresentationTests.swift`

**Interfaces:**
- Consumes: `AIInvocationLog` rows from `AIInvocationStore.recent()`
- Produces:

```swift
struct AIInvocationLogRowModel: Equatable {
    var skillTitle: String
    var statusText: String
    var errorText: String?
    var outcomeText: String
    var completedText: String
    var durationText: String
    var modelText: String
}

enum AIInvocationLogPresentation {
    static func row(_ log: AIInvocationLog) -> AIInvocationLogRowModel
}
```

Copy (verbatim):

| skillId | skillTitle |
|---|---|
| `practice.plan.from_image` | 图片转练习 |
| `practice.review.media` | 媒体复盘 |
| `practice.diagnose.video` | 录像分段诊断 |
| `practice.next_session` | 下次练习安排 |
| other | 其他调用 |

- `statusText`: `success` → `成功`; `failure` → `失败`
- `errorText`: nil when `errorTypeRaw` is empty; otherwise the raw English token (`invalidJSON`) — spec allows showing the error name
- `outcomeText`: empty raw → `仅调用`; `accepted` → `已接受`; `edited` → `已编辑`; `regenerated` → `已重生成`; `abandoned` → `已放弃`
- `completedText`: `completedAt == nil` → `未完成`; else `已完成`
- `durationText`: `"\(durationMs) 毫秒"`
- `modelText`: `model`

View: `@Environment(AIInvocationStore.self)`, `NavigationTitle("AI 调用记录")`, empty state `还没有 AI 调用记录`, list `ForEach(store.recent(), id: \.id)`. No `NavigationLink` on a row. Do not render Prompt, Base URL, Key, or `invocationId` labels.

Settings: between the AI 记忆 group and 关于, add:

```swift
sectionLabel("AI 调用")
group {
    NavigationLink {
        AIInvocationLogView()
    } label: {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 调用记录").font(.system(size: 14, weight: .semibold))
                Text("最近的生成与结果")
                    .font(.system(size: 12))
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GitaTheme.textTertiary)
        }
        .padding(16)
    }
}
```

- [ ] **Step 1: Write presentation tests**

```swift
@Test func mapsSuccessWithoutErrorAndEmptyOutcome() {
    let log = AIInvocationLog(
        id: "1", profileId: "p", skillId: SkillID.nextSession,
        skillVersion: "1.0.0", model: "gpt-4o",
        startedAt: Date(), durationMs: 12, statusRaw: "success"
    )
    let row = AIInvocationLogPresentation.row(log)
    #expect(row.skillTitle == "下次练习安排")
    #expect(row.statusText == "成功")
    #expect(row.errorText == nil)
    #expect(row.outcomeText == "仅调用")
    #expect(row.completedText == "未完成")
    #expect(!row.skillTitle.contains("Skill"))
    #expect(!AIInvocationStore.debugBlob(of: log).contains("BACKGROUND_MEMORY"))
}

@Test func mapsFailureAndAcceptedComplete() {
    let log = AIInvocationLog(
        id: "2", profileId: "p", skillId: SkillID.planFromImage,
        skillVersion: "1.1.0", model: "gpt-4o",
        startedAt: Date(), durationMs: 9, statusRaw: "failure",
        errorTypeRaw: "invalidJSON", draftOutcomeRaw: "accepted",
        taskId: "x", completedAt: Date()
    )
    let row = AIInvocationLogPresentation.row(log)
    #expect(row.skillTitle == "图片转练习")
    #expect(row.statusText == "失败")
    #expect(row.errorText == "invalidJSON")
    #expect(row.outcomeText == "已接受")
    #expect(row.completedText == "已完成")
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/AIInvocationLogPresentationTests
```

Expected: FAIL — presentation type missing.

- [ ] **Step 3: Implement presentation + view + settings link**

Keep the view dumb: map `recent()` through `AIInvocationLogPresentation.row`. Show `errorText` only when non-nil.

- [ ] **Step 4: Run presentation tests and a broader AI regression**

```bash
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/AIInvocationLogPresentationTests -only-testing:foxgitaTests/AIInvocationStoreTests -only-testing:foxgitaTests/AITransportTests -only-testing:foxgitaTests/NextSessionClientTests -only-testing:foxgitaTests/MemoryContextBuilderTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Features/Settings foxgitaTests/AIInvocationLogPresentationTests.swift
git commit -m "feat: show read-only AI invocation history in settings"
```

---

## Self-review

**Spec coverage**

| Spec section | Task |
|---|---|
| V13 + AIInvocationLog fields | Task 1 |
| Privacy / no secrets | Task 2 `debugBlob`, Task 4 success spy |
| record / duplicate / prune 200 / error names | Task 2 |
| Transport `formatRetryUsed` | Task 3 |
| Memory IDs actually injected | Task 3 |
| Four Skills write a row; notConfigured; cancelled+abandoned | Task 4 |
| Next session four outcomes; photo accepted/abandon-via-cancel | Task 5 |
| Consent decline writes nothing | Task 5 (no record before generate) |
| Complete on first effective item; not finishSession | Task 6 |
| Settings list copy and empty state | Task 7 |
| Eval dataset / model matrix | Out of scope (spec §1 不做) |

**Type names locked here:** `AIInvocationStatus`, `AIInvocationErrorType`, `AIDraftOutcome`, `AIInvocationRecordInput`, `AIInvocationRecording`, `EmptyAIInvocationLog`, `LiveAIInvocationLog`, `AIInvocationStore`, `AIInvocationClientRecord`, `AITransportResult`, `MemoryPromptSnapshot`, `AIDraftOutcomeRules`, `AIInvocationLogRowModel`, `AIInvocationLogPresentation`.
