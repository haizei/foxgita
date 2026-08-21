# Custom-Task Goal Backfill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When memory consent is enabled, each undeleted `custom-*` practice task gets one deterministic goal memory that injects into Skills, without overwriting user edits or resurrecting deletions.

**Architecture:** `MemoryRepository` gains `upsertTaskGoal` / `softDeleteTaskGoal` with tombstone and `sourceType == task` guards. `TaskMemorySync` filters `custom-*`, reads consent, backfills on enable. `PracticeStore` and `MemoryStore` call it after successful writes. `LiveMemoryContext` stays read-only. Skills stay `memoryWritePolicy = .deny`.

**Tech Stack:** iOS 18+ · SwiftUI · SwiftData Schema V7 · Swift Testing · existing `PracticeStore` / `MemoryStore` / `LiveMemoryContext`

## Global Constraints

- Spec: `docs/superpowers/2026-08-21-task-memory-sync/specs/2026-08-21-task-memory-sync-design.md`
- iOS 18+ · Scheme `foxgita` · cwd `foxgita/` (this nested git repo)
- Do not bump Schema (no V8). Do not edit `project.pbxproj` (synchronized root groups pick up new Swift files)
- Do not change Generator protocols, `AITransport`, Draft DTOs, frozen system/user prompt strings, or Keychain
- `memoryWritePolicy` stays `.deny` on all three Skills
- Do not write AI candidates, duration preferences, template/`active-*` memories, result-page citations, or `practice.next_session`
- Do not call Sync from `prepare()` / `seedIfNeeded` / `activateTemplate` / `setTaskStatus`
- Task-derived fields: `kind = .goal`, `key = "task.{taskId}.title"`, `sourceType = "task"`, `sourceId = task.id`, `confidence = 1`, `importance = 0.6`, `expiresAt = nil`, `valueJSON = ""`
- User-authored memories stay `importance = 0.8`, `sourceType = "user"`
- Title: trim; empty → no-op; `count > 120` → truncate to 120 Swift `Character`s
- `upsertTaskGoal` / `upsertUser` do **not** `save()`; caller saves
- `TaskMemorySync` methods do **not** throw; they set `lastError`
- Commit only files listed in that task. Never `git add -A`. Do not commit unrelated dirty files (`VideoAnalysisView`, architecture html, deleted media-review docs, `ReviewJobRunner`)
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
| `foxgita/Services/MemoryRepository.swift` | Protocol + `upsertTaskGoal` / `softDeleteTaskGoal`; `updateSummary` flips `task` → `user` |
| `foxgita/Services/TaskMemorySync.swift` | Consent gate, `custom-*` filter, backfill, lastError |
| `foxgita/Services/PracticeStore.swift` | Optional sync after custom create/update/delete |
| `foxgita/Services/MemoryStore.swift` | Optional sync; `setConsent(.enabled)` backfill |
| `foxgita/foxgitaApp.swift` | Construct and inject one `TaskMemorySync` |
| `foxgita/Features/Settings/AIMemorySettingsView.swift` | `sourceLabel` for `"task"` |
| `foxgitaTests/MemoryRepositoryTests.swift` | Tombstone, truncate, user-priority, flip |
| `foxgitaTests/TaskMemorySyncTests.swift` | Consent, custom filter, backfill, delete |
| `foxgitaTests/PracticeStoreTests.swift` or new wired tests in `TaskMemorySyncTests` | Store create/rename/delete with real Sync |
| `foxgitaTests/MemoryStoreTests.swift` | Enable backfill; clearAll then enable |
| `foxgitaTests/MemoryContextTests.swift` | Task goal appears in wrapper |
| `docs/TECHNICAL.md` | Task-derived goal key and user-priority |

---

### Task 1: MemoryRepository task-goal writes

**Files:**
- Modify: `foxgita/Services/MemoryRepository.swift`
- Modify: `foxgitaTests/MemoryRepositoryTests.swift`

**Interfaces:**
- Consumes: existing `MemoryItem`, `MemoryScope.goal`, `StoreError.invalidInput`, `fetch` (still excludes soft-deleted)
- Produces:
  - `func upsertTaskGoal(profileId: String, taskId: String, title: String) throws`
  - `func softDeleteTaskGoal(profileId: String, taskId: String) throws`
  - `updateSummary`: if live row `sourceType == "task"`, set `sourceType = "user"` after writing summary
  - Lookup key `"task.\(taskId).title"` **including** soft-deleted rows

- [ ] **Step 1: Write the failing repository tests**

Append to `foxgitaTests/MemoryRepositoryTests.swift`:

```swift
    @Test func upsertTaskGoalRejectsEmptyIdsAndSkipsBlankTitle() throws {
        let repo = try makeRepo()
        #expect(throws: StoreError.invalidInput) {
            try repo.upsertTaskGoal(profileId: "", taskId: "custom-1", title: "练晴天")
        }
        #expect(throws: StoreError.invalidInput) {
            try repo.upsertTaskGoal(profileId: "p1", taskId: "", title: "练晴天")
        }
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: "   ")
        try repo.save()
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)
    }

    @Test func upsertTaskGoalInsertsTruncatesAndUpdatesTaskSourcedRow() throws {
        let repo = try makeRepo()
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: "  练晴天  ")
        try repo.save()
        var rows = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].key == "task.custom-1.title")
        #expect(rows[0].summaryText == "练晴天")
        #expect(rows[0].sourceType == "task")
        #expect(rows[0].sourceId == "custom-1")
        #expect(rows[0].kind == .goal)
        #expect(rows[0].confidence == 1)
        #expect(rows[0].importance == 0.6)

        let long = String(repeating: "啊", count: 121)
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: long)
        try repo.save()
        rows = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].summaryText.count == 120)
        #expect(rows[0].summaryText == String(long.prefix(120)))
    }

    @Test func upsertTaskGoalDoesNotOverwriteUserEditedOrTombstone() throws {
        let repo = try makeRepo()
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: "旧标题")
        try repo.save()
        let id = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())[0].id
        try repo.updateSummary(profileId: "p1", id: id, summaryText: "我改的")
        try repo.save()
        var rows = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows[0].sourceType == "user")
        #expect(rows[0].key == "task.custom-1.title")
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: "任务新名")
        try repo.save()
        rows = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows[0].summaryText == "我改的")
        #expect(rows[0].sourceType == "user")

        try repo.softDelete(profileId: "p1", id: id)
        try repo.save()
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: "复活？")
        try repo.save()
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)
    }

    @Test func softDeleteTaskGoalOnlyRemovesLiveTaskSourcedRow() throws {
        let repo = try makeRepo()
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: "A")
        try repo.upsertTaskGoal(profileId: "p2", taskId: "custom-2", title: "B")
        try repo.save()
        try repo.softDeleteTaskGoal(profileId: "p1", taskId: "custom-1")
        try repo.save()
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)
        #expect(try repo.fetch(profileId: "p2", scopes: [.goal], matching: "", now: Date()).map(\.summaryText) == ["B"])

        try repo.upsertTaskGoal(profileId: "p2", taskId: "custom-2", title: "B")
        try repo.save()
        let id = try repo.fetch(profileId: "p2", scopes: [.goal], matching: "", now: Date())[0].id
        try repo.updateSummary(profileId: "p2", id: id, summaryText: "用户留着")
        try repo.save()
        try repo.softDeleteTaskGoal(profileId: "p2", taskId: "custom-2")
        try repo.save()
        #expect(try repo.fetch(profileId: "p2", scopes: [.goal], matching: "", now: Date()).map(\.summaryText) == ["用户留着"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MemoryRepositoryTests test
```

Expected: FAIL — `upsertTaskGoal` / `softDeleteTaskGoal` not on the protocol / type.

- [ ] **Step 3: Implement repository methods**

Add to `MemoryRepository` protocol (after `setConsent`):

```swift
    func upsertTaskGoal(profileId: String, taskId: String, title: String) throws
    func softDeleteTaskGoal(profileId: String, taskId: String) throws
```

In `SwiftDataMemoryRepository`, add helpers and methods. Do not `save()` inside them.

```swift
    private func taskGoalKey(_ taskId: String) -> String {
        "task.\(taskId).title"
    }

    private func taskGoalRows(profileId: String, taskId: String) throws -> [MemoryItem] {
        let pid = profileId
        let key = taskGoalKey(taskId)
        return try context.fetch(
            FetchDescriptor<MemoryItem>(
                predicate: #Predicate { $0.profileId == pid && $0.key == key }
            )
        )
    }

    func upsertTaskGoal(profileId: String, taskId: String, title: String) throws {
        guard !profileId.isEmpty, !taskId.isEmpty else { throw StoreError.invalidInput }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let summary = trimmed.count <= 120 ? trimmed : String(trimmed.prefix(120))
        let rows = try taskGoalRows(profileId: profileId, taskId: taskId)
        if rows.contains(where: { $0.deletedAt != nil }) { return }
        if let live = rows.first(where: { $0.deletedAt == nil }) {
            guard live.sourceType == "task" else { return }
            live.summaryText = summary
            live.updatedAt = Date()
            return
        }
        context.insert(
            MemoryItem(
                profileId: profileId,
                kind: .goal,
                key: taskGoalKey(taskId),
                summaryText: summary,
                sourceType: "task",
                sourceId: taskId,
                confidence: 1,
                importance: 0.6
            )
        )
    }

    func softDeleteTaskGoal(profileId: String, taskId: String) throws {
        guard !profileId.isEmpty, !taskId.isEmpty else { throw StoreError.invalidInput }
        let live = try taskGoalRows(profileId: profileId, taskId: taskId)
            .first { $0.deletedAt == nil && $0.sourceType == "task" }
        guard let live else { return }
        let now = Date()
        live.deletedAt = now
        live.updatedAt = now
    }
```

Change `updateSummary` so after assigning `summaryText` it also flips source:

```swift
        item.summaryText = summary
        if item.sourceType == "task" {
            item.sourceType = "user"
        }
        item.updatedAt = Date()
```

- [ ] **Step 4: Run tests to verify they pass**

Same `xcodebuild` as Step 2, `-only-testing:foxgitaTests/MemoryRepositoryTests`.

Expected: **TEST SUCCEEDED**

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/MemoryRepository.swift foxgitaTests/MemoryRepositoryTests.swift
git commit -m "Add task-goal upsert that respects user edits and tombstones."
```

---

### Task 2: TaskMemorySync

**Files:**
- Create: `foxgita/Services/TaskMemorySync.swift`
- Create: `foxgitaTests/TaskMemorySyncTests.swift`

**Interfaces:**
- Consumes: `MemoryRepository.upsertTaskGoal` / `softDeleteTaskGoal` / `save`; `ModelContext` fetch of `TaskItem` and `LocalProfile`; `MemoryConsentState.enabled`
- Produces:
  - `@MainActor final class TaskMemorySync`
  - `init(repository: MemoryRepository, context: ModelContext)`
  - `private(set) var lastError: StoreError?`
  - `func syncUpsert(task: TaskItem)`
  - `func syncDelete(taskId: String, profileId: String)`
  - `func backfill(profileId: String)`
  - `syncUpsert` no-op unless `task.id.hasPrefix("custom-")`, `task.deletedAt == nil`, `task.profileId` non-empty, and that profile's `consent == .enabled`
  - `syncDelete` no-op unless `taskId.hasPrefix("custom-")`; does **not** require enabled
  - `backfill` no-op unless profile exists and `consent == .enabled`; then undeleted `custom-*` tasks for that `profileId`
  - Methods never throw; on failure set `lastError`; on entry set `lastError = nil`

- [ ] **Step 1: Write the failing sync tests**

Create `foxgitaTests/TaskMemorySyncTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct TaskMemorySyncTests {
    private func make() throws -> (TaskMemorySync, SwiftDataMemoryRepository, ModelContext, LocalProfile) {
        let schema = Schema(versionedSchema: GitaSchemaV7.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        profile.consent = .enabled
        context.insert(profile)
        try context.save()
        let repo = SwiftDataMemoryRepository(context: context)
        return (TaskMemorySync(repository: repo, context: context), repo, context, profile)
    }

    private func customTask(
        id: String = "custom-1",
        title: String = "练晴天",
        profileId: String = "p1",
        deleted: Bool = false
    ) -> TaskItem {
        let task = TaskItem(
            id: id, title: title, subtitle: "",
            category: .chord, targetMin: 10, profileId: profileId
        )
        if deleted { task.deletedAt = Date() }
        return task
    }

    @Test func syncUpsertNoopsWhenDisabledOrNotCustom() throws {
        let (sync, repo, _, profile) = try make()
        profile.consent = .disabled
        sync.syncUpsert(task: customTask())
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)

        profile.consent = .enabled
        let template = TaskItem(
            id: "tpl-1", title: "模板", subtitle: "",
            category: .chord, targetMin: 8, isTemplate: true, profileId: "p1"
        )
        sync.syncUpsert(task: template)
        let daily = TaskItem(
            id: "active-tpl-1-20260821", title: "每日激活", subtitle: "",
            category: .chord, targetMin: 8, profileId: "p1"
        )
        sync.syncUpsert(task: daily)
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)
    }

    @Test func syncUpsertWritesCustomTaskWhenEnabled() throws {
        let (sync, repo, _, _) = try make()
        sync.syncUpsert(task: customTask())
        let rows = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows.map(\.summaryText) == ["练晴天"])
        #expect(rows[0].key == "task.custom-1.title")
        #expect(sync.lastError == nil)
    }

    @Test func syncDeleteRemovesTaskSourcedEvenWhenConsentDisabled() throws {
        let (sync, repo, _, profile) = try make()
        sync.syncUpsert(task: customTask())
        profile.consent = .disabled
        sync.syncDelete(taskId: "custom-1", profileId: "p1")
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)
    }

    @Test func backfillFillsGapsAndSkipsTombstonesAndOtherProfiles() throws {
        let (sync, repo, context, profile) = try make()
        let p2 = LocalProfile(id: "p2", isActive: false)
        p2.consent = .enabled
        context.insert(p2)
        context.insert(customTask(id: "custom-old", title: "旧任务"))
        context.insert(customTask(id: "custom-b", title: "别人的", profileId: "p2"))
        let template = TaskItem(
            id: "tpl-1", title: "模板", subtitle: "",
            category: .chord, targetMin: 8, isTemplate: true, profileId: "p1"
        )
        context.insert(template)
        try context.save()

        profile.consent = .disabled
        sync.backfill(profileId: "p1")
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)

        profile.consent = .enabled
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-gone", title: "已删")
        try repo.save()
        try repo.softDeleteTaskGoal(profileId: "p1", taskId: "custom-gone")
        try repo.save()
        context.insert(customTask(id: "custom-gone", title: "已删任务还在"))
        try context.save()

        sync.backfill(profileId: "p1")
        let mine = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(Set(mine.map(\.summaryText)) == ["旧任务"])
        #expect(try repo.fetch(profileId: "p2", scopes: [.goal], matching: "", now: Date()).isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/TaskMemorySyncTests test
```

Expected: FAIL — `TaskMemorySync` not found.

- [ ] **Step 3: Implement TaskMemorySync**

Create `foxgita/Services/TaskMemorySync.swift`:

```swift
import Foundation
import SwiftData

@MainActor
final class TaskMemorySync {
    private(set) var lastError: StoreError?

    private let repository: MemoryRepository
    private let context: ModelContext

    init(repository: MemoryRepository, context: ModelContext) {
        self.repository = repository
        self.context = context
    }

    func syncUpsert(task: TaskItem) {
        lastError = nil
        guard task.id.hasPrefix("custom-"),
              task.deletedAt == nil,
              !task.profileId.isEmpty,
              consent(for: task.profileId) == .enabled
        else { return }
        do {
            try repository.upsertTaskGoal(
                profileId: task.profileId, taskId: task.id, title: task.title
            )
            try repository.save()
        } catch {
            lastError = StoreError.from(error)
        }
    }

    func syncDelete(taskId: String, profileId: String) {
        lastError = nil
        guard taskId.hasPrefix("custom-"), !profileId.isEmpty else { return }
        do {
            try repository.softDeleteTaskGoal(profileId: profileId, taskId: taskId)
            try repository.save()
        } catch {
            lastError = StoreError.from(error)
        }
    }

    func backfill(profileId: String) {
        lastError = nil
        guard !profileId.isEmpty, consent(for: profileId) == .enabled else { return }
        let pid = profileId
        do {
            let tasks = try context.fetch(
                FetchDescriptor<TaskItem>(
                    predicate: #Predicate { $0.profileId == pid && $0.deletedAt == nil }
                )
            )
            for task in tasks where task.id.hasPrefix("custom-") {
                do {
                    try repository.upsertTaskGoal(
                        profileId: pid, taskId: task.id, title: task.title
                    )
                } catch let error as StoreError where error == .invalidInput {
                    continue
                }
            }
            try repository.save()
        } catch {
            lastError = StoreError.from(error)
        }
    }

    private func consent(for profileId: String) -> MemoryConsentState? {
        let pid = profileId
        let profile = try? context.fetch(
            FetchDescriptor<LocalProfile>(predicate: #Predicate { $0.id == pid })
        ).first
        return profile?.consent
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2.

Expected: **TEST SUCCEEDED** (suite `TaskMemorySyncTests`).

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/TaskMemorySync.swift foxgitaTests/TaskMemorySyncTests.swift
git commit -m "Sync custom-task titles into goal memories when consent is on."
```

---

### Task 3: Wire PracticeStore, MemoryStore, and App

**Files:**
- Modify: `foxgita/Services/PracticeStore.swift`
- Modify: `foxgita/Services/MemoryStore.swift`
- Modify: `foxgita/foxgitaApp.swift`
- Modify: `foxgitaTests/MemoryStoreTests.swift`
- Modify: `foxgitaTests/TaskMemorySyncTests.swift` (add Store-wired cases here so they share one SwiftData container; do not force `InMemoryPracticeRepository` tests to take a Sync)

**Interfaces:**
- Consumes: `TaskMemorySync.syncUpsert` / `syncDelete` / `backfill` / `lastError`
- Produces:
  - `PracticeStore.init(..., taskMemorySync: TaskMemorySync? = nil)`
  - After successful `createCustomTask` / `createFromAIDraft` / `updateTask` save → `syncUpsert`; copy `sync.lastError` onto `PracticeStore.lastError` if non-nil
  - After successful `softDeleteTask` save → `syncDelete(taskId:profileId:)` (use the task's `profileId` captured before/after save)
  - `MemoryStore.init(..., taskMemorySync: TaskMemorySync? = nil)`
  - `setConsent(.enabled)` after successful mutate: `backfill` then `reload()`; copy sync `lastError` but still return `true` (consent stays enabled)
  - `foxgitaApp` builds one `TaskMemorySync` from `memoryRepo` + `mainContext` and passes it into both stores

- [ ] **Step 1: Write the failing store-wired tests**

Add to `foxgitaTests/TaskMemorySyncTests.swift`:

```swift
    private func makeWired(consent: MemoryConsentState = .enabled) throws -> (
        PracticeStore, MemoryStore, SwiftDataMemoryRepository, LocalProfile
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
        let memoryRepo = SwiftDataMemoryRepository(context: context)
        let sync = TaskMemorySync(repository: memoryRepo, context: context)
        let defaults = UserDefaults(suiteName: "foxgita.tests.\(UUID().uuidString)")!
        defaults.set(true, forKey: SeedData.seededKey)
        let store = PracticeStore(
            repository: SwiftDataPracticeRepository(context: context),
            defaults: defaults,
            taskMemorySync: sync
        )
        let memoryStore = MemoryStore(
            repository: memoryRepo, context: context, taskMemorySync: sync
        )
        memoryStore.reload()
        return (store, memoryStore, memoryRepo, profile)
    }

    @Test func practiceStoreWritesGoalOnlyWhenEnabled() throws {
        let (store, _, repo, profile) = try makeWired(consent: .disabled)
        let id = store.createCustomTask(name: "关着建的", minutes: 10, category: .chord)
        #expect(id != nil)
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)

        profile.consent = .enabled
        let (onStore, _, onRepo, _) = try makeWired(consent: .enabled)
        let onId = onStore.createCustomTask(name: "开着建的", minutes: 10, category: .chord)!
        let rows = try onRepo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows.map(\.summaryText) == ["开着建的"])
        #expect(rows[0].key == "task.\(onId).title")
    }

    @Test func practiceStoreRenameAndDeleteFollowTaskUntilUserEdits() throws {
        let (store, memoryStore, repo, _) = try makeWired()
        let id = store.createCustomTask(name: "原名", minutes: 10, category: .chord)!
        store.updateTask(id, title: "新名", subtitle: "", minutes: 10)
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).map(\.summaryText) == ["新名"])

        memoryStore.reload()
        let memId = memoryStore.items[0].id
        #expect(memoryStore.updateSummary(id: memId, summary: "用户名"))
        store.updateTask(id, title: "任务又改了", subtitle: "", minutes: 10)
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).map(\.summaryText) == ["用户名"])

        store.softDeleteTask(id)
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).map(\.summaryText) == ["用户名"])
    }

    @Test func practiceStoreDeleteRemovesUneditedTaskGoal() throws {
        let (store, _, repo, _) = try makeWired()
        let id = store.createCustomTask(name: "要删", minutes: 10, category: .chord)!
        store.softDeleteTask(id)
        #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)
    }

    @Test func createFromAIDraftWritesTaskGoal() throws {
        let (store, _, repo, _) = try makeWired()
        let draft = AIPracticeDraft(
            title: "AI 草稿", category: .song, targetMin: 15,
            steps: ["慢练"], chords: []
        )
        let id = store.createFromAIDraft(draft)!
        let rows = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
        #expect(rows[0].summaryText == "AI 草稿")
        #expect(rows[0].key == "task.\(id).title")
    }
```

Add to `foxgitaTests/MemoryStoreTests.swift`. Change `makeStore` to still compile with the new defaulted `taskMemorySync` parameter, then add:

```swift
    @Test func enablingBackfillsExistingCustomTaskAndClearAllStaysGone() throws {
        let schema = Schema(versionedSchema: GitaSchemaV7.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        profile.consent = .disabled
        context.insert(profile)
        let task = TaskItem(
            id: "custom-old", title: "关着建的", subtitle: "",
            category: .chord, targetMin: 10, profileId: "p1"
        )
        context.insert(task)
        try context.save()
        let repo = SwiftDataMemoryRepository(context: context)
        let sync = TaskMemorySync(repository: repo, context: context)
        let store = MemoryStore(repository: repo, context: context, taskMemorySync: sync)
        store.reload()
        #expect(store.setConsent(.enabled))
        #expect(store.consent == .enabled)
        #expect(store.items.map(\.summaryText) == ["关着建的"])

        #expect(store.clearAll())
        #expect(store.items.isEmpty)
        #expect(store.setConsent(.disabled))
        #expect(store.setConsent(.enabled))
        #expect(store.items.isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/TaskMemorySyncTests \
  -only-testing:foxgitaTests/MemoryStoreTests test
```

Expected: FAIL — extra `PracticeStore` / `MemoryStore` init argument, or create-custom does not write a goal.

- [ ] **Step 3: Wire the stores and app**

`PracticeStore` stored property and init:

```swift
    @ObservationIgnored private let taskMemorySync: TaskMemorySync?

    init(
        repository: PracticeRepository,
        defaults: UserDefaults = .standard,
        taskMemorySync: TaskMemorySync? = nil
    ) {
        self.repository = repository
        self.defaults = defaults
        self.taskMemorySync = taskMemorySync
    }
```

Helpers (private, near `produce`):

```swift
    private func applySyncUpsert(_ task: TaskItem) {
        guard let sync = taskMemorySync else { return }
        sync.syncUpsert(task: task)
        if let error = sync.lastError { lastError = error }
    }

    private func applySyncDelete(taskId: String, profileId: String) {
        guard let sync = taskMemorySync else { return }
        sync.syncDelete(taskId: taskId, profileId: profileId)
        if let error = sync.lastError { lastError = error }
    }
```

Change `createCustomTask` so sync runs **after** a successful `produce` (do not put it inside `produce`, which clears `lastError` on success):

```swift
        let saved = produce {
            try repository.add(task)
            try repository.save()
            return task.id
        }
        if saved != nil { applySyncUpsert(task) }
        return saved
```

Same pattern for `createFromAIDraft`.

`updateTask` — after `perform { ... }`:

```swift
        perform {
            task.title = trimmed.isEmpty ? task.title : trimmed
            task.subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            task.targetMin = min(60, max(1, minutes))
            task.touch()
            try repository.save()
        }
        if lastError == nil { applySyncUpsert(task) }
```

`softDeleteTask`:

```swift
        let profileId = task.profileId
        perform {
            task.deletedAt = Date()
            task.touch()
            try repository.save()
        }
        if lastError == nil { applySyncDelete(taskId: taskId, profileId: profileId) }
```

`MemoryStore`:

```swift
    private let taskMemorySync: TaskMemorySync?

    init(
        repository: MemoryRepository,
        context: ModelContext,
        taskMemorySync: TaskMemorySync? = nil
    ) {
        self.repository = repository
        self.context = context
        self.taskMemorySync = taskMemorySync
    }
```

Replace `setConsent`:

```swift
    @discardableResult
    func setConsent(_ state: MemoryConsentState) -> Bool {
        let ok = mutate { profileId in
            try repository.setConsent(profileId: profileId, state)
        }
        if ok, state == .enabled, let profileId = try? activeProfile()?.id, !profileId.isEmpty {
            taskMemorySync?.backfill(profileId: profileId)
            if let error = taskMemorySync?.lastError { lastError = error }
            reload()
        }
        return ok
    }
```

`foxgitaApp.init` after `memoryRepo` exists:

```swift
            let taskMemorySync = TaskMemorySync(
                repository: memoryRepo, context: container.mainContext
            )
            let memoryStore = MemoryStore(
                repository: memoryRepo,
                context: container.mainContext,
                taskMemorySync: taskMemorySync
            )
            self.memoryStore = memoryStore
            self.coordinator = MemoryConsentCoordinator(store: memoryStore)
            let store = PracticeStore(
                repository: SwiftDataPracticeRepository(context: container.mainContext),
                taskMemorySync: taskMemorySync
            )
```

Remove the previous `MemoryStore(...)` / `PracticeStore(...)` lines that this replaces. Keep `liveMemory` and `reviewRunner` as they are.

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

Expected: **TEST SUCCEEDED** with the previous 207 plus the new cases. Existing `PracticeStoreTests` using `InMemoryPracticeRepository` still pass because `taskMemorySync` defaults to `nil`.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeStore.swift \
  foxgita/Services/MemoryStore.swift \
  foxgita/foxgitaApp.swift \
  foxgitaTests/MemoryStoreTests.swift \
  foxgitaTests/TaskMemorySyncTests.swift
git commit -m "Write custom-task goals from PracticeStore when memory is enabled."
```

---

### Task 4: Settings label, injection regression, docs

**Files:**
- Modify: `foxgita/Features/Settings/AIMemorySettingsView.swift` (`sourceLabel`)
- Modify: `foxgitaTests/MemoryContextTests.swift`
- Modify: `docs/TECHNICAL.md`
- Modify spec status line only if you also touch the spec: `docs/superpowers/2026-08-21-task-memory-sync/specs/2026-08-21-task-memory-sync-design.md` (set **状态** to `Approved — implemented`)

**Interfaces:**
- Consumes: task-goal rows from Task 1 (`sourceType == "task"`, `kind == .goal`)
- Produces: settings caption 「来自练习任务」; `LiveMemoryContext` user block contains the task title when consent is enabled; TECHNICAL.md describes the key and user-priority rule

- [ ] **Step 1: Write the failing injection test**

Add to `foxgitaTests/MemoryContextTests.swift`:

```swift
    @Test func liveIncludesTaskDerivedGoalWhenConsentEnabled() async throws {
        let (live, repo, profile) = try makeLive()
        profile.consent = .enabled
        try repo.upsertTaskGoal(profileId: "p1", taskId: "custom-1", title: "自定义目标")
        try repo.save()
        let text = await live.block(skill: scopedPlanFromImage(), query: "")
        #expect(text.contains("<<<BACKGROUND_MEMORY>>>"))
        #expect(text.contains("自定义目标"))
        #expect(text.contains("[goal]"))
        #expect(!text.contains("你是吉他练习教练。只输出合法 JSON。"))
    }
```

- [ ] **Step 2: Run test to verify it fails or already passes**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MemoryContextTests test
```

Expected: this case should **PASS** once Task 1 exists (Live already injects goals). If it fails, fix only `LiveMemoryContext` if a real regression appeared — do not change prompts. If it passes, keep the test and continue.

- [ ] **Step 3: Settings label and TECHNICAL.md**

In `AIMemorySettingsView.sourceLabel`:

```swift
    private func sourceLabel(_ raw: String) -> String {
        switch raw {
        case "user": return String(localized: "你添加的")
        case "task": return String(localized: "来自练习任务")
        case "debug_seed": return String(localized: "调试种子")
        default: return raw
        }
    }
```

In `docs/TECHNICAL.md`:

1. Directory tree under `Services/`: add `TaskMemorySync.swift` with comment `custom-* 任务标题 → goal`.
2. In §6.3.1, after「用户手写记忆走 `MemoryStore`；正式路径不写 AI 候选。」insert:

> 同意 `enabled` 时，`PracticeStore` 对 `custom-*` 任务调用 `TaskMemorySync`：每条练习项一条 goal，`key = task.{taskId}.title`，`sourceType = task`，`importance = 0.6`。用户改摘要后 `sourceType` 变为 `user`，之后改任务标题不再覆盖；用户删除或清空后同 key 不复活。模板与每日 `active-*` 激活不写记忆。设计说明：`docs/superpowers/2026-08-21-task-memory-sync/specs/2026-08-21-task-memory-sync-design.md`。

3. Spec header **状态** → `Approved — implemented`.

- [ ] **Step 4: Run full unit tests**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

Expected: **TEST SUCCEEDED**. Confirm system prompt snapshots still pass (`AITransportTests` / client tests in the same run).

- [ ] **Step 5: Commit**

```bash
git add foxgita/Features/Settings/AIMemorySettingsView.swift \
  foxgitaTests/MemoryContextTests.swift \
  docs/TECHNICAL.md \
  docs/superpowers/2026-08-21-task-memory-sync/specs/2026-08-21-task-memory-sync-design.md
git commit -m "Show task-sourced memories and document custom-task goal keys."
```

---

## Self-review

**Spec coverage**

| Spec section | Task |
|---|---|
| §4 fields / §5 upsert + tombstone + user flip / softDeleteTaskGoal | 1 |
| §6 TaskMemorySync, custom filter, consent, backfill, delete without enabled | 2 |
| §7 PracticeStore / MemoryStore / App | 3 |
| §7 source label, §8 inject, §9 clearAll, createFromAIDraft | 3–4 |
| §10 TECHNICAL.md | 4 |
| YAGNI list | Global Constraints; no task implements X4 |

**Skipped on purpose:** constructing a failing `repository.save()` after a successful task save (spec: 若可构造). Not injectable without a fake `MemoryRepository`; task save already commits before `applySyncUpsert`.

**Type names:** `TaskMemorySync.syncUpsert(task:)` / `syncDelete(taskId:profileId:)` / `backfill(profileId:)` used in Tasks 2–3. `upsertTaskGoal(profileId:taskId:title:)` used in Tasks 1–2 and 4.
