# Next-Session Practice Planning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From Recommend Sheet「安排今日」, the user picks a duration, previews one multi-step practice, and confirms it into today's list as a `custom-*` task, using goals / preferences / current focus when memory is on.

**Architecture:** New Skill `practice.next_session` (text-only Client, no images). `DurationPreferenceSync` writes `practice.available_minutes` after consent and before the HTTP call. `NextSessionSheet` is a three-phase sheet on top of Recommend Sheet. Confirm calls existing `PracticeStore.createFromAIDraft`. No Schema V8.

**Tech Stack:** iOS 18+ · SwiftUI · SwiftData Schema V7 · Swift Testing · existing `AITransport` / `LiveMemoryContext` / `AIPracticeDraft` / `MemoryConsentCoordinator`

## Global Constraints

- Spec: `docs/superpowers/2026-08-22-next-session/specs/2026-08-22-next-session-design.md`
- iOS 18+ · Scheme `foxgita` · cwd `foxgita/` (this nested git repo)
- Do not bump Schema (no V8). Do not edit `project.pbxproj` (synchronized root groups pick up new Swift files)
- Do not change `VisionPracticeClient`, `AITransport`, `AIPracticeDraft.normalize`, three frozen 1.1.0 prompts, Keychain, or `ReviewJobRunner`
- `practice.plan.from_image` stays `memoryWritePolicy = .deny`. Review / diagnose stay `.candidates`. Versions stay `1.1.0`
- New skill: `practice.next_session` `1.0.0`, read `[.goal, .preference, .ability]`, write `.deny`
- Duration preference key `practice.available_minutes`; `sourceType = user`; tombstone **may** revive; method does **not** `save()`
- `DurationPreferenceSync.sync` does **not** throw; it sets `lastError`
- Confirm-only persist: generate never calls `createFromAIDraft`
- Do not implement 3-session upgrade, review「继续练」, home memory card, weekly summary, call logs, or preview category editing
- Commit only files listed in that task. Never `git add -A`. Do not commit unrelated dirty files (`VideoAnalysisView`, architecture html, deleted media-review docs, `ReviewJobRunner`, `Localizable.xcstrings`)
- Swift Testing: suite-level `-only-testing:foxgitaTests/SuiteName` (method-level often runs 0 tests)
- Unit test command:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

If iPhone 17 is Busy or missing, retry or use any available iPhone simulator.

## File map

| File | Responsibility |
|---|---|
| `foxgita/Services/MemoryRepository.swift` | Protocol + `upsertDurationPreference` |
| `foxgita/Services/DurationPreferenceSync.swift` | Consent gate, save, EnvironmentKey |
| `foxgita/Services/SkillDefinition.swift` | `SkillID.nextSession` + definition |
| `foxgita/Services/SkillRegistry.swift` | builtin includes next session |
| `foxgita/Services/NextSessionClient.swift` | Text-only complete, `capRaw`, `{{minutes}}` |
| `foxgita/Services/NextSessionGenerator.swift` | Keychain + error mapping |
| `foxgita/Services/NextSessionCitation.swift` | Citation line + default duration |
| `foxgita/Features/Practice/NextSessionSheet.swift` | Duration → generating → preview |
| `foxgita/Features/Practice/RecommendSheet.swift` | 「安排今日」chip + sheet |
| `foxgita/foxgitaApp.swift` | Construct and inject Duration Sync |
| `docs/TECHNICAL.md` | Fourth skill + duration key |
| `foxgitaTests/MemoryRepositoryTests.swift` | Upsert / revive / clamp / isolate |
| `foxgitaTests/DurationPreferenceSyncTests.swift` | Consent, update, revive |
| `foxgitaTests/SkillRegistryTests.swift` | New next-session snapshot only |
| `foxgitaTests/NextSessionClientTests.swift` | capRaw + HTTP + memory block |
| `foxgitaTests/NextSessionCitationTests.swift` | Citation priority + duration default |
| `foxgitaTests/NextSessionGeneratorTests.swift` | notConfigured / failed mapping |
| `foxgitaTests/MemoryContextTests.swift` | nextSession scopes |
| Stub repos in existing tests | no-op `upsertDurationPreference` so the suite compiles |

---

### Task 1: MemoryRepository duration preference

**Files:**
- Modify: `foxgita/Services/MemoryRepository.swift`
- Modify: `foxgitaTests/MemoryRepositoryTests.swift`
- Modify: `foxgitaTests/MemoryStoreTests.swift` (stub)
- Modify: `foxgitaTests/TaskMemorySyncTests.swift` (stub)
- Modify: `foxgitaTests/AICandidateSyncTests.swift` (`SaveFailingMemoryRepository`)

**Interfaces:**
- Consumes: existing `MemoryItem`, `MemoryScope.preference`, `StoreError.invalidInput`, `fetch` (still excludes soft-deleted)
- Produces:
  - `func upsertDurationPreference(profileId: String, minutes: Int) throws`
  - Lookup key `"practice.available_minutes"` **including** soft-deleted rows
  - Clamp minutes to 5...60; tombstone revives; live row updates; no `save()`

- [ ] **Step 1: Write the failing repository tests**

Append to `foxgitaTests/MemoryRepositoryTests.swift`:

```swift
    @Test func upsertDurationPreferenceRejectsEmptyProfileAndClamps() throws {
        let repo = try makeRepo()
        #expect(throws: StoreError.invalidInput) {
            try repo.upsertDurationPreference(profileId: "", minutes: 20)
        }
        try repo.upsertDurationPreference(profileId: "p1", minutes: 3)
        try repo.save()
        var rows = try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].key == "practice.available_minutes")
        #expect(rows[0].summaryText == "通常可练 5 分钟")
        #expect(rows[0].valueJSON == "5")
        try repo.upsertDurationPreference(profileId: "p1", minutes: 90)
        try repo.save()
        rows = try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date())
        #expect(rows[0].summaryText == "通常可练 60 分钟")
        #expect(rows[0].valueJSON == "60")
    }

    @Test func upsertDurationPreferenceInsertsUpdatesAndRevivesTombstone() throws {
        let repo = try makeRepo()
        try repo.upsertDurationPreference(profileId: "p1", minutes: 20)
        try repo.save()
        var rows = try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].kind == .preference)
        #expect(rows[0].sourceType == "user")
        #expect(rows[0].sourceId == "")
        #expect(rows[0].confidence == 1)
        #expect(rows[0].importance == 0.8)
        #expect(rows[0].expiresAt == nil)
        let id = rows[0].id
        try repo.upsertDurationPreference(profileId: "p1", minutes: 30)
        try repo.save()
        rows = try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].id == id)
        #expect(rows[0].summaryText == "通常可练 30 分钟")
        #expect(rows[0].valueJSON == "30")
        try repo.softDelete(profileId: "p1", id: id)
        try repo.save()
        #expect(try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date()).isEmpty)
        try repo.upsertDurationPreference(profileId: "p1", minutes: 15)
        try repo.save()
        rows = try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].id == id)
        #expect(rows[0].deletedAt == nil)
        #expect(rows[0].summaryText == "通常可练 15 分钟")
        #expect(rows[0].valueJSON == "15")
        #expect(rows[0].sourceType == "user")
    }

    @Test func upsertDurationPreferenceIsolatesProfiles() throws {
        let repo = try makeRepo()
        try repo.upsertDurationPreference(profileId: "p1", minutes: 20)
        try repo.upsertDurationPreference(profileId: "p2", minutes: 30)
        try repo.save()
        #expect(
            try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date())
                .map(\.valueJSON) == ["20"]
        )
        #expect(
            try repo.fetch(profileId: "p2", scopes: [.preference], matching: "", now: Date())
                .map(\.valueJSON) == ["30"]
        )
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MemoryRepositoryTests test
```

Expected: FAIL — `upsertDurationPreference` not on the protocol / type.

- [ ] **Step 3: Add protocol method and implementation**

In `foxgita/Services/MemoryRepository.swift`, add after `upsertAICandidate` on the protocol:

```swift
    func upsertDurationPreference(profileId: String, minutes: Int) throws
```

In `SwiftDataMemoryRepository`, after `upsertAICandidate`:

```swift
    private static let durationKey = "practice.available_minutes"

    private func durationRows(profileId: String) throws -> [MemoryItem] {
        let pid = profileId
        let key = Self.durationKey
        return try context.fetch(
            FetchDescriptor<MemoryItem>(
                predicate: #Predicate { $0.profileId == pid && $0.key == key }
            )
        )
    }

    func upsertDurationPreference(profileId: String, minutes: Int) throws {
        guard !profileId.isEmpty else { throw StoreError.invalidInput }
        let n = min(60, max(5, minutes))
        let summary = "通常可练 \(n) 分钟"
        let value = "\(n)"
        let rows = try durationRows(profileId: profileId)
        if let tomb = rows.first(where: { $0.deletedAt != nil }) {
            tomb.deletedAt = nil
            tomb.kindRaw = MemoryScope.preference.rawValue
            tomb.summaryText = summary
            tomb.valueJSON = value
            tomb.sourceType = "user"
            tomb.sourceId = ""
            tomb.confidence = 1
            tomb.importance = 0.8
            tomb.expiresAt = nil
            tomb.updatedAt = Date()
            return
        }
        if let live = rows.first(where: { $0.deletedAt == nil }) {
            live.kindRaw = MemoryScope.preference.rawValue
            live.summaryText = summary
            live.valueJSON = value
            live.sourceType = "user"
            live.sourceId = ""
            live.confidence = 1
            live.importance = 0.8
            live.expiresAt = nil
            live.updatedAt = Date()
            return
        }
        context.insert(
            MemoryItem(
                profileId: profileId,
                kind: .preference,
                key: Self.durationKey,
                summaryText: summary,
                valueJSON: value,
                sourceType: "user",
                sourceId: "",
                confidence: 1,
                importance: 0.8
            )
        )
    }
```

Add this no-op to every test stub that conforms to `MemoryRepository`:

```swift
        func upsertDurationPreference(profileId: String, minutes: Int) throws {}
```

Locations:

- `foxgitaTests/MemoryStoreTests.swift` — `EnableConsentBackfillStub`
- `foxgitaTests/TaskMemorySyncTests.swift` — `BackfillUpsertStub`
- `foxgitaTests/AICandidateSyncTests.swift` — `SaveFailingMemoryRepository`

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MemoryRepositoryTests \
  -only-testing:foxgitaTests/MemoryStoreTests \
  -only-testing:foxgitaTests/TaskMemorySyncTests \
  -only-testing:foxgitaTests/AICandidateSyncTests test
```

Expected: PASS (full `foxgitaTests` must also compile).

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/MemoryRepository.swift \
  foxgitaTests/MemoryRepositoryTests.swift \
  foxgitaTests/MemoryStoreTests.swift \
  foxgitaTests/TaskMemorySyncTests.swift \
  foxgitaTests/AICandidateSyncTests.swift
git commit -m "Add duration preference upsert that can revive a tombstone."
```

---

### Task 2: DurationPreferenceSync

**Files:**
- Create: `foxgita/Services/DurationPreferenceSync.swift`
- Create: `foxgitaTests/DurationPreferenceSyncTests.swift`

**Interfaces:**
- Consumes: `MemoryRepository.upsertDurationPreference` / `save`; `ModelContext` fetch of `LocalProfile`; `MemoryConsentState.enabled`
- Produces:
  - `DurationPreferenceSync.sync(profileId:minutes:)` — no throw; empty profileId or `consent != .enabled` is no-op
  - `DurationPreferenceSync.syncActive(minutes:)` — looks up `isActive == true`, then calls `sync`
  - `lastError: StoreError?`
  - `EnvironmentValues.durationPreferenceSync: DurationPreferenceSync?` default `nil`

- [ ] **Step 1: Write the failing sync tests**

Create `foxgitaTests/DurationPreferenceSyncTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct DurationPreferenceSyncTests {
    private func make(consent: MemoryConsentState = .enabled) throws -> (
        DurationPreferenceSync, SwiftDataMemoryRepository, ModelContext, LocalProfile
    ) {
        let schema = Schema(versionedSchema: GitaSchemaV7.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        profile.consent = consent
        context.insert(profile)
        try context.save()
        let repo = SwiftDataMemoryRepository(context: context)
        return (DurationPreferenceSync(repository: repo, context: context), repo, context, profile)
    }

    @Test func syncNoopsWhenDisabledOrEmptyProfile() throws {
        let (offSync, offRepo, _, _) = try make(consent: .disabled)
        offSync.sync(profileId: "p1", minutes: 20)
        #expect(try offRepo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date()).isEmpty)
        #expect(offSync.lastError == nil)

        let (onSync, onRepo, _, _) = try make(consent: .enabled)
        onSync.sync(profileId: "", minutes: 20)
        #expect(try onRepo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date()).isEmpty)
    }

    @Test func syncWritesWhenEnabled() throws {
        let (sync, repo, _, _) = try make()
        sync.sync(profileId: "p1", minutes: 20)
        let rows = try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].key == "practice.available_minutes")
        #expect(rows[0].valueJSON == "20")
        #expect(rows[0].sourceType == "user")
        #expect(sync.lastError == nil)
    }

    @Test func syncUsesPassedProfileNotActiveOne() throws {
        let (sync, repo, context, _) = try make()
        let p2 = LocalProfile(id: "p2", isActive: false)
        p2.consent = .enabled
        context.insert(p2)
        try context.save()
        sync.sync(profileId: "p2", minutes: 30)
        #expect(try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date()).isEmpty)
        #expect(
            try repo.fetch(profileId: "p2", scopes: [.preference], matching: "", now: Date())
                .map(\.valueJSON) == ["30"]
        )
    }

    @Test func syncActiveWritesActiveProfile() throws {
        let (sync, repo, _, _) = try make()
        sync.syncActive(minutes: 25)
        #expect(
            try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date())
                .map(\.valueJSON) == ["25"]
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/DurationPreferenceSyncTests test
```

Expected: FAIL — `DurationPreferenceSync` not found.

- [ ] **Step 3: Implement DurationPreferenceSync**

Create `foxgita/Services/DurationPreferenceSync.swift`:

```swift
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class DurationPreferenceSync {
    private(set) var lastError: StoreError?

    private let repository: MemoryRepository
    private let context: ModelContext

    init(repository: MemoryRepository, context: ModelContext) {
        self.repository = repository
        self.context = context
    }

    func sync(profileId: String, minutes: Int) {
        lastError = nil
        guard !profileId.isEmpty, consent(for: profileId) == .enabled else { return }
        do {
            try repository.upsertDurationPreference(profileId: profileId, minutes: minutes)
            try repository.save()
        } catch {
            lastError = StoreError.from(error)
        }
    }

    func syncActive(minutes: Int) {
        lastError = nil
        let profile = try? context.fetch(
            FetchDescriptor<LocalProfile>(predicate: #Predicate { $0.isActive == true })
        ).first
        guard let id = profile?.id, !id.isEmpty else { return }
        sync(profileId: id, minutes: minutes)
    }

    private func consent(for profileId: String) -> MemoryConsentState? {
        let pid = profileId
        let profile = try? context.fetch(
            FetchDescriptor<LocalProfile>(predicate: #Predicate { $0.id == pid })
        ).first
        return profile?.consent
    }
}

private struct DurationPreferenceSyncKey: EnvironmentKey {
    static let defaultValue: DurationPreferenceSync? = nil
}

extension EnvironmentValues {
    var durationPreferenceSync: DurationPreferenceSync? {
        get { self[DurationPreferenceSyncKey.self] }
        set { self[DurationPreferenceSyncKey.self] = newValue }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/DurationPreferenceSyncTests test
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/DurationPreferenceSync.swift \
  foxgitaTests/DurationPreferenceSyncTests.swift
git commit -m "Write duration preference when memory consent is on."
```

---

### Task 3: Skill, capRaw, and NextSessionClient

**Files:**
- Modify: `foxgita/Services/SkillDefinition.swift`
- Modify: `foxgita/Services/SkillRegistry.swift`
- Modify: `foxgitaTests/SkillRegistryTests.swift`
- Create: `foxgita/Services/NextSessionClient.swift`
- Create: `foxgitaTests/NextSessionClientTests.swift`

**Interfaces:**
- Consumes: `AITransport.complete`, `AIPracticeDraft.Raw` / `normalize`, `MemoryContextProviding`, `SkillRegistry`
- Produces:
  - `SkillID.nextSession = "practice.next_session"`
  - `SkillDefinition.nextSession` version `1.0.0`, scopes `[.goal, .preference, .ability]`, `.deny`, user prompt contains `{{minutes}}`
  - `protocol NextSessionGenerating`
  - `NextSessionClient.capRaw(_:budget:)`
  - `NextSessionClient.generateDraft(baseURL:model:apiKey:budgetMinutes:fallbackCategory:)`

- [ ] **Step 1: Write failing SkillRegistry + Client tests**

Append to `foxgitaTests/SkillRegistryTests.swift` **without changing** `builtinContainsFrozenSkillsWithDenyMemory`:

```swift
    @Test func builtinContainsNextSessionSkill() {
        let skill = SkillRegistry.builtin.skill(id: SkillID.nextSession)
        #expect(skill != nil)
        #expect(skill?.id == "practice.next_session")
        #expect(skill?.version == "1.0.0")
        #expect(skill?.title == "下次练习安排")
        #expect(skill?.memoryReadScopes == [.goal, .preference, .ability])
        #expect(skill?.memoryWritePolicy == .deny)
        #expect(skill?.timeout == nil)
        #expect(skill?.allowsFormatRetry == true)
        #expect(skill?.systemPrompt == "你是吉他练习教练。只输出合法 JSON。")
        #expect(skill?.userPrompt?.contains("{{minutes}}") == true)
        #expect(skill?.userPrompt == SkillDefinition.nextSession.userPrompt)
    }
```

Create `foxgitaTests/NextSessionClientTests.swift`:

```swift
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
        guard let body = request.httpBody else { return "" }
        return String(data: body, encoding: .utf8) ?? ""
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/SkillRegistryTests \
  -only-testing:foxgitaTests/NextSessionClientTests test
```

Expected: FAIL — `SkillID.nextSession` / `NextSessionClient` not found.

- [ ] **Step 3: Add Skill, register it, implement Client**

In `foxgita/Services/SkillDefinition.swift`, add to `SkillID`:

```swift
    static let nextSession = "practice.next_session"
```

Append to the `SkillDefinition` extension (keep the three existing static lets unchanged):

```swift
    static let nextSession = SkillDefinition(
        id: SkillID.nextSession,
        version: "1.0.0",
        title: "下次练习安排",
        purpose: "按可用时长和练习记忆生成一条可确认的今日练习",
        systemPrompt: "你是吉他练习教练。只输出合法 JSON。",
        userPrompt: """
        请按用户本次可用的 {{minutes}} 分钟安排一次吉他练习。只返回 JSON 对象，不要 markdown，不要其它说明。
        字段：
        - title: 字符串
        - category: 仅能为 left/right/both/chord/scale/rhythm/song 之一
        - targetMin: 整数分钟，必须 ≤ {{minutes}}
        - steps: 字符串数组（练习步骤）
        - chords: 可选，识别到的和弦名字符串数组（如 C、G、Am）
        - stepMinutes: 可选，与 steps 按下标对齐的整数分钟；若出现则各项之和必须 ≤ {{minutes}}；没有则省略
        有背景记忆就延续目标与近期重点，不要重复已经稳定的基础建议。
        没有背景记忆就给可完成的通用安排，不要编造用户历史。
        不要承诺精确音准鉴定，不要做医疗判断。
        """,
        timeout: nil,
        allowsFormatRetry: true,
        memoryReadScopes: [.goal, .preference, .ability],
        memoryWritePolicy: .deny
    )
```

In `foxgita/Services/SkillRegistry.swift`, change builtin to:

```swift
    static let builtin = SkillRegistry(skills: [
        .planFromImage,
        .reviewMedia,
        .diagnoseVideo,
        .nextSession,
    ])
```

Create `foxgita/Services/NextSessionClient.swift`:

```swift
import Foundation

protocol NextSessionGenerating: Sendable {
    func generateDraft(
        baseURL: String,
        model: String,
        apiKey: String,
        budgetMinutes: Int,
        fallbackCategory: PracticeCategory
    ) async throws -> AIPracticeDraft
}

struct NextSessionClient: NextSessionGenerating {
    private let transport: AITransport
    private let registry: SkillRegistry
    private let memory: any MemoryContextProviding

    init(
        session: URLSession = .shared,
        registry: SkillRegistry = .builtin,
        memory: any MemoryContextProviding = EmptyMemoryContext()
    ) {
        self.transport = AITransport(session: session)
        self.registry = registry
        self.memory = memory
    }

    static func clampBudget(_ minutes: Int) -> Int {
        min(60, max(5, minutes))
    }

    static func capRaw(_ raw: AIPracticeDraft.Raw, budget: Int) -> AIPracticeDraft.Raw {
        let budget = clampBudget(budget)
        var raw = raw
        let target = min(raw.targetMin ?? budget, budget)
        raw.targetMin = min(60, max(1, target))
        guard let minutes = raw.stepMinutes, let steps = raw.steps else { return raw }
        var pairs: [(String, Int)] = []
        for index in steps.indices {
            let text = steps[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = index < minutes.count ? minutes[index] : 0
            if !text.isEmpty && value >= 1 {
                pairs.append((text, value))
            }
        }
        var sum = pairs.reduce(0) { $0 + $1.1 }
        while sum > budget && !pairs.isEmpty {
            sum -= pairs.removeLast().1
        }
        raw.steps = pairs.map(\.0)
        raw.stepMinutes = pairs.map(\.1)
        return raw
    }

    func generateDraft(
        baseURL: String,
        model: String,
        apiKey: String,
        budgetMinutes: Int,
        fallbackCategory: PracticeCategory
    ) async throws -> AIPracticeDraft {
        guard let skill = registry.skill(id: SkillID.nextSession) else {
            throw VisionPracticeError.unregisteredSkill
        }
        guard let url = AITransport.completionsURL(from: baseURL) else {
            throw VisionPracticeError.invalidURL
        }
        let budget = Self.clampBudget(budgetMinutes)
        let userText = (skill.userPrompt ?? "").replacingOccurrences(of: "{{minutes}}", with: "\(budget)")
        let memoryBlock = await memory.block(skill: skill, query: "")
        let finalUserText = memoryBlock.isEmpty ? userText : userText + "\n\n" + memoryBlock
        let rawContent: String
        do {
            rawContent = try await transport.complete(
                url: url,
                apiKey: apiKey,
                model: model,
                systemPrompt: skill.systemPrompt,
                userText: finalUserText,
                imageJPEGData: [],
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
        let jsonText = AITransport.stripMarkdownFences(rawContent)
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw VisionPracticeError.invalidJSON
        }
        let raw: AIPracticeDraft.Raw
        do {
            raw = try JSONDecoder().decode(AIPracticeDraft.Raw.self, from: jsonData)
        } catch {
            throw VisionPracticeError.invalidJSON
        }
        return AIPracticeDraft.normalize(
            Self.capRaw(raw, budget: budget),
            fallbackCategory: fallbackCategory
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/SkillRegistryTests \
  -only-testing:foxgitaTests/NextSessionClientTests \
  -only-testing:foxgitaTests/VisionPracticeClientTests test
```

Expected: PASS. Old three-skill snapshot still green.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/SkillDefinition.swift \
  foxgita/Services/SkillRegistry.swift \
  foxgita/Services/NextSessionClient.swift \
  foxgitaTests/SkillRegistryTests.swift \
  foxgitaTests/NextSessionClientTests.swift
git commit -m "Register practice.next_session and cap draft minutes."
```

---

### Task 4: Citation and Generator

**Files:**
- Create: `foxgita/Services/NextSessionCitation.swift`
- Create: `foxgita/Services/NextSessionGenerator.swift`
- Create: `foxgitaTests/NextSessionCitationTests.swift`
- Create: `foxgitaTests/NextSessionGeneratorTests.swift`
- Modify: `foxgitaTests/MemoryContextTests.swift`

**Interfaces:**
- Consumes: `MemoryItem`, `NextSessionGenerating`, `LLMCredentialsStore`
- Produces:
  - `NextSessionCitation.line(items:selectedMinutes:) -> String`
  - `NextSessionDuration.resolved(preferenceMinutes:initialMinutes:) -> Int`
  - `NextSessionDuration.parsePreference(_ items: [MemoryItem]) -> Int?`
  - `NextSessionGeneratorError` with `userMessage`
  - `NextSessionGenerator.generate(budgetMinutes:baseURL:model:fallbackCategory:)`

- [ ] **Step 1: Write failing citation, duration, generator, and live-memory tests**

Create `foxgitaTests/NextSessionCitationTests.swift`:

```swift
import Foundation
import Testing
@testable import foxgita

struct NextSessionCitationTests {
    private func item(kind: MemoryScope, key: String, summary: String, valueJSON: String = "") -> MemoryItem {
        MemoryItem(
            profileId: "p1", kind: kind, key: key, summaryText: summary,
            valueJSON: valueJSON, sourceType: "user", sourceId: "",
            confidence: 1, importance: 0.8
        )
    }

    @Test func linePrefersFocusThenGoalThenDurationThenGeneric() {
        let focus = item(kind: .ability, key: "ability.current_focus", summary: "压弦要贴品丝")
        let goal = item(kind: .goal, key: "task.custom-1.title", summary: "晴天前奏")
        let pref = item(
            kind: .preference, key: "practice.available_minutes",
            summary: "通常可练 20 分钟", valueJSON: "20"
        )
        #expect(NextSessionCitation.line(items: [focus, goal, pref], selectedMinutes: 20)
            == "已结合你的近期重点：压弦要贴品丝")
        #expect(NextSessionCitation.line(items: [goal, pref], selectedMinutes: 20)
            == "已结合你的目标：晴天前奏")
        #expect(NextSessionCitation.line(items: [pref], selectedMinutes: 20)
            == "已按你的 20 分钟安排")
        #expect(NextSessionCitation.line(items: [], selectedMinutes: 20)
            == "通用建议，还没有可参考的练习记忆")
    }

    @Test func lineTruncatesSummaryTo40Characters() {
        let long = String(repeating: "啊", count: 41)
        let focus = item(kind: .ability, key: "ability.current_focus", summary: long)
        let line = NextSessionCitation.line(items: [focus], selectedMinutes: 20)
        #expect(line == "已结合你的近期重点：\(String(long.prefix(40)))…")
    }

    @Test func resolvedDurationPrefersValidPreference() {
        #expect(NextSessionDuration.resolved(preferenceMinutes: 25, initialMinutes: 10) == 25)
        #expect(NextSessionDuration.resolved(preferenceMinutes: 3, initialMinutes: 10) == 10)
        #expect(NextSessionDuration.resolved(preferenceMinutes: nil, initialMinutes: 10) == 10)
        #expect(NextSessionDuration.resolved(preferenceMinutes: nil, initialMinutes: 1) == 5)
        #expect(NextSessionDuration.parsePreference([
            item(kind: .preference, key: "practice.available_minutes", summary: "x", valueJSON: "30")
        ]) == 30)
        #expect(NextSessionDuration.parsePreference([]) == nil)
    }
}
```

Create `foxgitaTests/NextSessionGeneratorTests.swift`:

```swift
import Foundation
import Testing
@testable import foxgita

private struct StubNextSessionClient: NextSessionGenerating {
    var draft: AIPracticeDraft?
    var error: VisionPracticeError?

    func generateDraft(
        baseURL: String,
        model: String,
        apiKey: String,
        budgetMinutes: Int,
        fallbackCategory: PracticeCategory
    ) async throws -> AIPracticeDraft {
        if let error { throw error }
        return draft ?? AIPracticeDraft(
            title: "草稿", category: fallbackCategory, targetMin: budgetMinutes,
            steps: ["一步"], chords: []
        )
    }
}

@MainActor
struct NextSessionGeneratorTests {
    @Test func notConfiguredWhenKeyMissing() async {
        let store = LLMCredentialsStore(service: "foxgita.tests.\(UUID().uuidString)")
        defer { store.clearAPIKey() }
        let generator = NextSessionGenerator(
            client: StubNextSessionClient(),
            credentials: store
        )
        await #expect(throws: NextSessionGeneratorError.notConfigured) {
            try await generator.generate(
                budgetMinutes: 20,
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                fallbackCategory: .chord
            )
        }
    }

    @Test func mapsVisionUnauthorized() async throws {
        let store = LLMCredentialsStore(service: "foxgita.tests.\(UUID().uuidString)")
        defer { store.clearAPIKey() }
        try store.saveAPIKey("sk-test")
        let generator = NextSessionGenerator(
            client: StubNextSessionClient(error: .unauthorized),
            credentials: store
        )
        do {
            _ = try await generator.generate(
                budgetMinutes: 20,
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o",
                fallbackCategory: .chord
            )
            Issue.record("expected throw")
        } catch let error as NextSessionGeneratorError {
            #expect(error.userMessage == "API Key 无效或无权限")
        }
    }
}
```

Append to `foxgitaTests/MemoryContextTests.swift`:

```swift
    @Test func liveIncludesNextSessionGoalAndAbilityWhenConsentEnabled() async throws {
        let (live, repo, profile) = try makeLive()
        profile.consent = .enabled
        try repo.upsertAICandidate(
            profileId: "p1",
            recordingId: "clip-1",
            summaryText: "压弦要贴品丝",
            valueJSON: "practice.review.media@1.1.0"
        )
        try repo.save()
        let text = await live.block(skill: .nextSession, query: "")
        #expect(text.contains("<<<BACKGROUND_MEMORY>>>"))
        #expect(text.contains("当前目标：《晴天》前奏"))
        #expect(text.contains("压弦要贴品丝"))
        #expect(text.contains("[goal]"))
        #expect(text.contains("[ability]"))
        #expect(!text.contains("你是吉他练习教练。只输出合法 JSON。"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/NextSessionCitationTests \
  -only-testing:foxgitaTests/NextSessionGeneratorTests \
  -only-testing:foxgitaTests/MemoryContextTests test
```

Expected: FAIL — `NextSessionCitation` / `NextSessionGenerator` not found.

- [ ] **Step 3: Implement citation and generator**

Create `foxgita/Services/NextSessionCitation.swift`:

```swift
import Foundation

enum NextSessionCitation {
    static let durationKey = "practice.available_minutes"
    static let focusKey = "ability.current_focus"

    static func line(items: [MemoryItem], selectedMinutes: Int) -> String {
        if let focus = items.first(where: { $0.key == focusKey }) {
            return "已结合你的近期重点：\(clip(focus.summaryText))"
        }
        if let goal = items.first(where: { $0.kind == .goal }) {
            return "已结合你的目标：\(clip(goal.summaryText))"
        }
        if items.contains(where: { $0.key == durationKey }) {
            return "已按你的 \(selectedMinutes) 分钟安排"
        }
        return "通用建议，还没有可参考的练习记忆"
    }

    private static func clip(_ text: String) -> String {
        if text.count <= 40 { return text }
        return String(text.prefix(40)) + "…"
    }
}

enum NextSessionDuration {
    static func resolved(preferenceMinutes: Int?, initialMinutes: Int) -> Int {
        if let preferenceMinutes, (5...60).contains(preferenceMinutes) {
            return preferenceMinutes
        }
        let clamped = min(60, max(5, initialMinutes))
        return clamped
    }

    static func parsePreference(_ items: [MemoryItem]) -> Int? {
        guard let item = items.first(where: { $0.key == NextSessionCitation.durationKey }) else {
            return nil
        }
        return Int(item.valueJSON)
    }
}
```

Create `foxgita/Services/NextSessionGenerator.swift`:

```swift
import Foundation

enum NextSessionGeneratorError: Error, Equatable {
    case notConfigured
    case failed(VisionPracticeError)

    var userMessage: String {
        switch self {
        case .notConfigured:
            return String(localized: "先去设置里填写 AI 接口")
        case .failed(let vision):
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
        }
    }
}

@MainActor
final class NextSessionGenerator {
    private let client: any NextSessionGenerating
    private let credentials: LLMCredentialsStore

    init(
        client: any NextSessionGenerating,
        credentials: LLMCredentialsStore = LLMCredentialsStore()
    ) {
        self.client = client
        self.credentials = credentials
    }

    func generate(
        budgetMinutes: Int,
        baseURL: String,
        model: String,
        fallbackCategory: PracticeCategory
    ) async throws -> AIPracticeDraft {
        guard credentials.isConfigured(baseURL: baseURL, model: model) else {
            throw NextSessionGeneratorError.notConfigured
        }
        guard let apiKey = credentials.loadAPIKey()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            throw NextSessionGeneratorError.notConfigured
        }
        do {
            return try await client.generateDraft(
                baseURL: baseURL,
                model: model,
                apiKey: apiKey,
                budgetMinutes: budgetMinutes,
                fallbackCategory: fallbackCategory
            )
        } catch let error as VisionPracticeError {
            throw NextSessionGeneratorError.failed(error)
        } catch {
            throw NextSessionGeneratorError.failed(.transport)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/NextSessionCitationTests \
  -only-testing:foxgitaTests/NextSessionGeneratorTests \
  -only-testing:foxgitaTests/MemoryContextTests \
  -only-testing:foxgitaTests/LLMCredentialsStoreTests test
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/NextSessionCitation.swift \
  foxgita/Services/NextSessionGenerator.swift \
  foxgitaTests/NextSessionCitationTests.swift \
  foxgitaTests/NextSessionGeneratorTests.swift \
  foxgitaTests/MemoryContextTests.swift
git commit -m "Cite injected memories and map next-session generator errors."
```

---

### Task 5: Sheet, chip, App injection, TECHNICAL.md

**Files:**
- Create: `foxgita/Features/Practice/NextSessionSheet.swift`
- Modify: `foxgita/Features/Practice/RecommendSheet.swift`
- Modify: `foxgita/foxgitaApp.swift`
- Modify: `docs/TECHNICAL.md`

**Interfaces:**
- Consumes: `DurationPreferenceSync.syncActive`, `NextSessionGenerator`, `NextSessionCitation`, `NextSessionDuration`, `PracticeStore.createFromAIDraft`, `MemoryConsentCoordinator.ensureDecided`, `MemoryStore.reload` / `items` / `consent`
- Produces: Recommend chip「安排今日」; three-phase sheet; confirm writes one `custom-*` task; no create on generate

- [ ] **Step 1: Add NextSessionSheet**

Create `foxgita/Features/Practice/NextSessionSheet.swift`:

```swift
import SwiftUI

struct NextSessionSheet: View {
    private enum Phase {
        case duration
        case generating
        case preview
    }

    var initialMinutes: Int
    var fallbackCategory: PracticeCategory
    var baseURL: String
    var model: String
    @Binding var selection: String?
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.memoryContext) private var memoryContext
    @Environment(\.durationPreferenceSync) private var durationSync
    @Environment(PracticeStore.self) private var store
    @Environment(MemoryStore.self) private var memoryStore
    @Environment(MemoryConsentCoordinator.self) private var consent

    @State private var phase: Phase = .duration
    @State private var minutes = 20
    @State private var isGenerating = false
    @State private var generateTask: Task<Void, Never>?
    @State private var toast: String?
    @State private var citation = ""
    @State private var draftCategory: PracticeCategory = .chord
    @State private var draftChords: [String] = []
    @State private var editTitle = ""
    @State private var editMinutes = 20
    @State private var editSteps: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(GitaTheme.borderSubtle)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            HStack {
                Text(titleText)
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button("关闭", action: close)
                    .font(.system(size: 14))
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)

            Group {
                switch phase {
                case .duration: durationContent
                case .generating: generatingContent
                case .preview: previewContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(GitaTheme.bgDefault)
        .overlay {
            if let toast {
                VStack {
                    Spacer()
                    ToastBanner(text: toast).padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            memoryStore.reload()
            minutes = NextSessionDuration.resolved(
                preferenceMinutes: NextSessionDuration.parsePreference(memoryStore.items),
                initialMinutes: initialMinutes
            )
        }
        .onDisappear {
            generateTask?.cancel()
            if consent.isPresented {
                consent.chooseDisabled()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private var titleText: String {
        switch phase {
        case .duration: return "安排今日练习"
        case .generating: return "正在安排今日练习"
        case .preview: return "确认今日练习"
        }
    }

    private var durationContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("这次能练多久？")
                .font(.system(size: 17, weight: .bold))
            Text("生成后可以再改步骤。确认前不会加入今日清单。")
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
            HStack(spacing: 8) {
                ForEach([15, 20, 30], id: \.self) { value in
                    Button {
                        minutes = value
                    } label: {
                        Text("\(value) 分钟")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(minutes == value ? GitaTheme.brandOn : GitaTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(minutes == value ? GitaTheme.brand500 : GitaTheme.bgSubtle)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Button { minutes = max(5, minutes - 5) } label: {
                    Text("－").frame(width: 28, height: 28)
                }
                Text("\(minutes) 分钟")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(minWidth: 48)
                Button { minutes = min(60, minutes + 5) } label: {
                    Text("＋").frame(width: 28, height: 28)
                }
            }
            .foregroundStyle(GitaTheme.textSecondary)
            Spacer()
            Button(action: beginGeneration) {
                Text("生成安排")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(GitaTheme.brand500)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 16)
    }

    private var generatingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("正在按你的 \(minutes) 分钟安排练习")
                .font(.system(size: 14))
                .foregroundStyle(GitaTheme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(citation)
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
            TextField("标题", text: $editTitle)
                .font(.system(size: 16, weight: .semibold))
            HStack {
                Button { editMinutes = max(1, editMinutes - 5) } label: {
                    Text("－")
                }
                Text("\(editMinutes) 分钟")
                Button { editMinutes = min(60, editMinutes + 5) } label: {
                    Text("＋")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            ForEach(editSteps.indices, id: \.self) { index in
                HStack {
                    TextField("步骤", text: $editSteps[index])
                    Button("删") { editSteps.remove(at: index) }
                        .font(.system(size: 13))
                        .foregroundStyle(GitaTheme.textSecondary)
                }
            }
            if editSteps.count < 12 {
                Button("加一步") { editSteps.append("") }
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            Button("重新生成") {
                minutes = min(60, max(5, editMinutes))
                beginGeneration()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(GitaTheme.brand500)
            Button(action: confirm) {
                Text("加入今日练习")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(GitaTheme.brand500)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 16)
    }

    private func beginGeneration() {
        generateTask = Task {
            let gate = await consent.ensureDecided()
            guard !Task.isCancelled else { return }
            guard gate == .proceed else { return }
            durationSync?.syncActive(minutes: minutes)
            memoryStore.reload()
            phase = .generating
            isGenerating = true
            toast = nil
            do {
                let generator = NextSessionGenerator(
                    client: NextSessionClient(memory: memoryContext)
                )
                let draft = try await generator.generate(
                    budgetMinutes: minutes,
                    baseURL: baseURL,
                    model: model,
                    fallbackCategory: fallbackCategory
                )
                try Task.checkCancellation()
                applyDraft(draft)
                citation = NextSessionCitation.line(
                    items: memoryStore.items,
                    selectedMinutes: minutes
                )
                isGenerating = false
                phase = .preview
            } catch is CancellationError {
                return
            } catch {
                fail(with: error)
            }
        }
    }

    private func applyDraft(_ draft: AIPracticeDraft) {
        draftCategory = draft.category
        draftChords = draft.chords
        editTitle = draft.title
        editMinutes = draft.targetMin
        editSteps = draft.steps
    }

    private func confirm() {
        var steps = editSteps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if steps.isEmpty { steps = [String(localized: "新步骤")] }
        if steps.count > 12 { steps = Array(steps.prefix(12)) }
        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = AIPracticeDraft(
            title: title.isEmpty ? String(localized: "未命名练习") : title,
            category: draftCategory,
            targetMin: min(60, max(1, editMinutes)),
            steps: steps,
            chords: draftChords
        )
        guard let id = store.createFromAIDraft(draft) else {
            toast = String(localized: "生成失败，请稍后重试")
            hideToastLater()
            return
        }
        selection = id
        onFinished()
    }

    private func fail(with error: Error) {
        isGenerating = false
        phase = .duration
        generateTask = nil
        if let error = error as? NextSessionGeneratorError {
            toast = error.userMessage
        } else {
            toast = String(localized: "生成失败，请稍后重试")
        }
        hideToastLater()
    }

    private func close() {
        if phase == .generating {
            generateTask?.cancel()
            generateTask = nil
            isGenerating = false
            phase = .duration
        } else {
            dismiss()
        }
    }

    private func hideToastLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
    }
}
```

- [ ] **Step 2: Wire RecommendSheet**

In `foxgita/Features/Practice/RecommendSheet.swift`:

1. Add `@State private var showNextSessionSheet = false` next to `showPhotoSheet`.
2. In the name-bar `HStack` after the「拍摄/照片」button (before the divider), add:

```swift
                            Button {
                                let missing = credentials.missingFieldLabels(
                                    baseURL: llmBaseURL, model: llmModel
                                )
                                if missing.isEmpty {
                                    showNextSessionSheet = true
                                } else {
                                    toast = String(
                                        localized: "还缺 \(missing.joined(separator: "、"))，请在设置里填完并点保存"
                                    )
                                    hideToastLater()
                                }
                            } label: {
                                Text("安排今日")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(GitaTheme.brand500)
                                    .padding(.horizontal, 10)
                                    .frame(height: 34)
                                    .background(GitaTheme.brand50)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .disabled(showPhotoSheet || showNextSessionSheet)
```

3. Disable the photo button with the same `showPhotoSheet || showNextSessionSheet` condition.
4. After the existing `.sheet(isPresented: $showPhotoSheet)` add:

```swift
        .sheet(isPresented: $showNextSessionSheet) {
            NextSessionSheet(
                initialMinutes: duration,
                fallbackCategory: category,
                baseURL: llmBaseURL,
                model: llmModel,
                selection: $selection,
                onFinished: {
                    showNextSessionSheet = false
                    dismiss()
                }
            )
        }
```

- [ ] **Step 3: Inject sync in foxgitaApp and document**

In `foxgita/foxgitaApp.swift` `init()`, after `aiCandidateSync`:

```swift
            let durationPreferenceSync = DurationPreferenceSync(
                repository: memoryRepo, context: container.mainContext
            )
```

Store it as `private let durationPreferenceSync: DurationPreferenceSync` on the App (assign `self.durationPreferenceSync = durationPreferenceSync` next to `self.memoryStore`).

In `body`, next to `.environment(coordinator)`:

```swift
                .environment(\.durationPreferenceSync, durationPreferenceSync)
```

In `docs/TECHNICAL.md` Services tree, add after `AICandidateSync.swift`:

```text
│   ├── DurationPreferenceSync.swift # 当场时长 → practice.available_minutes
│   ├── NextSessionClient.swift      # practice.next_session 无图调用
│   ├── NextSessionGenerator.swift
│   ├── NextSessionCitation.swift
```

In the MemoryItem paragraph that documents write policies, append:

> `practice.next_session` 为 `1.0.0`，读 `goal` / `preference` / `ability`，`memoryWritePolicy = .deny`。推荐 Sheet「安排今日」选时长后生成预览，确认才 `createFromAIDraft`。同意 `enabled` 时，生成前由 `DurationPreferenceSync` 写入偏好 `practice.available_minutes`（tombstone 可复活）。预览引用句由本地记忆生成，不采用模型自报。设计说明：`docs/superpowers/2026-08-22-next-session/specs/2026-08-22-next-session-design.md`。

- [ ] **Step 4: Compile and run the related suites**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

Expected: PASS. Manual smoke (not a gate): 加号 → 安排今日 → 选 20 → 生成 → 预览改一步 → 加入今日练习 → 详情打开；关闭预览后首页无新任务。

- [ ] **Step 5: Commit**

```bash
git add foxgita/Features/Practice/NextSessionSheet.swift \
  foxgita/Features/Practice/RecommendSheet.swift \
  foxgita/foxgitaApp.swift \
  docs/TECHNICAL.md
git commit -m "Add Arrange Today chip and a confirm-before-save sheet."
```

---

## Self-review

**Spec coverage**

| Spec section | Task |
|---|---|
| Skill `practice.next_session` 1.0.0 + scopes + deny | 3 |
| Recommend chip + credentials toast | 5 |
| Duration chips / stepper / default | 4 (`NextSessionDuration`) + 5 (UI) |
| Duration preference upsert + revive | 1, 2 |
| Write preference after consent, before HTTP | 5 `beginGeneration` |
| `capRaw` + normalize | 3 |
| Preview citation priority | 4 |
| Confirm → `createFromAIDraft` only | 5 |
| Consent gate | 5 |
| Dual-profile isolation | 1, 2 |
| Unregistered skill zero network | 3 |
| TECHNICAL.md | 5 |
| No V8 / no old prompt edits / no 3-session | Global constraints |

**Placeholder scan:** None. Generator tests use `LLMCredentialsStore(service:)` + `saveAPIKey` / `clearAPIKey`.

**Type consistency:** `upsertDurationPreference(profileId:minutes:)`, `DurationPreferenceSync.sync(profileId:minutes:)` / `syncActive(minutes:)`, `NextSessionClient.generateDraft(..., budgetMinutes:fallbackCategory:)`, `NextSessionCitation.line(items:selectedMinutes:)`, `NextSessionDuration.resolved(preferenceMinutes:initialMinutes:)`.
