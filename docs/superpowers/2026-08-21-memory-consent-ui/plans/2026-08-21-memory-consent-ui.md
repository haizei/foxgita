# Memory Consent and Management UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users decide memory consent once, manage goal/preference memories in Settings, and keep the three AI Skills injecting a read-only block only when consent is `enabled`.

**Architecture:** Lightweight Schema V7 adds `memoryConsentState` on `LocalProfile`. `MemoryRepository` gains user CRUD. `MemoryStore` + `MemoryConsentCoordinator` drive Settings and a first-use sheet. `LiveMemoryContext` injects only when `consent == .enabled`. Skill write policy stays `.deny`.

**Tech Stack:** iOS 18+ · SwiftUI · SwiftData VersionedSchema · Swift Testing · existing `SkillRegistry` / `AITransport` / Draft DTOs

## Global Constraints

- Spec: `docs/superpowers/2026-08-21-memory-consent-ui/specs/2026-08-21-memory-consent-ui-design.md`
- iOS 18+ · Scheme `foxgita` · cwd `foxgita/` (this nested git repo)
- Do not change Generator protocol signatures (`VisionGenerating` / `MediaReviewing` / `VideoDiagnosing`)
- Do not change `AITransport`, Draft DTOs, frozen system/user prompt strings, or Keychain
- `memoryWritePolicy` stays `.deny` on all three Skills
- Production must not persist API Key, full Prompt, image bytes, or full model response
- Migration plan must not use `willDestroy`
- New files under `foxgita/` and `foxgitaTests/` are picked up by `PBXFileSystemSynchronizedRootGroup` — do **not** edit `project.pbxproj`
- YAGNI: no AI candidate writes, no Task backfill, no result-page memory citations, no home memory card, no `practice.next_session`, no `PracticeRepository` list filter by profile, no `RecordingRef.profileId`
- Keyword matching is a **rank boost**, not a hard filter
- User-authored memories: `kind` only `.goal` / `.preference`; `summaryText` trim non-empty and `count <= 120`; `sourceType = "user"`; `key = "user.\(kind.rawValue).\(UUID().uuidString)"`
- Frozen privacy copy (settings page and first-use sheet share these four sentences):
  1. 记忆保存在这台设备上。
  2. 若启用以获得更贴合的建议，本次只会把少量相关文字发给你在设置里配置的模型服务。
  3. 不会因为开启记忆而自动上传历史录音或视频；只有当前这次功能选中的内容会参与请求。
  4. 你可以随时在设置里关闭或清除记忆。
- Buttons: 「启用并继续」「暂不启用」。Nav title: 「AI 记忆」
- Swift Testing: use suite-level `-only-testing:foxgitaTests/SuiteName` (method-level filters often run 0 tests)
- Unit test command:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

If iPhone 17 is Busy or missing, retry or use any available iPhone simulator.

- Commit only files listed in that task. Never `git add -A`. Do not commit unrelated dirty files (`VideoAnalysisView` extra edits, architecture html, deleted media-review docs, `ReviewJobRunner` unrelated diffs). For `VideoAnalysisView.swift` in Task 6, add only the consent-gate hunk.

## File map

| File | Responsibility |
|---|---|
| `foxgita/Models/SchemaV7.swift` | Copy of V6 + `memoryConsentState` / `consent` |
| `foxgita/Models/Models.swift` | Typealiases → V7; lightweight V6→V7 |
| `foxgita/Services/MemoryConsentState.swift` | `MemoryConsentState` + `ConsentGateResult` + copy constants |
| `foxgita/Services/MemoryRepository.swift` | User CRUD + `setConsent` |
| `foxgita/Services/MemoryStore.swift` | Settings/list/consent for UI |
| `foxgita/Services/MemoryConsentCoordinator.swift` | First-use sheet continuation |
| `foxgita/Services/MemoryContextProviding.swift` | Inject only if `.enabled` |
| `foxgita/Services/MemoryDebugSeeder.swift` | Seed writes `.enabled` |
| `foxgita/Services/PracticeStore.swift` | `prepare` backfills empty state |
| `foxgita/foxgitaApp.swift` | Schema V7; environment Store + Coordinator |
| `foxgita/Features/Settings/SettingsView.swift` | `NavigationStack` + row |
| `foxgita/Features/Settings/AIMemorySettingsView.swift` | Management page |
| `foxgita/Features/Settings/MemoryConsentSheet.swift` | First-use sheet |
| `foxgita/Features/Practice/PhotoPracticeSheet.swift` | Gate before generate |
| `foxgita/Features/Practice/PracticeDetailView.swift` | Gate before enqueue |
| `foxgita/Features/Record/RecordDetailView.swift` | Gate before enqueue |
| `foxgita/Features/Practice/VideoAnalysisView.swift` | Gate before retry enqueue |
| Tests listed per task | |

---

### Task 1: Schema V7 + consent backfill

**Files:**
- Create: `foxgita/Models/SchemaV7.swift`
- Create: `foxgita/Services/MemoryConsentState.swift`
- Modify: `foxgita/Models/Models.swift` (typealiases + `GitaMigrationPlan`)
- Modify: `foxgita/foxgitaApp.swift` (`GitaSchemaV7.self`)
- Modify: `foxgita/Services/PracticeStore.swift` (`ensureProfile` backfill)
- Modify: `foxgitaTests/MigrationTests.swift`
- Modify: `foxgitaTests/PracticeStoreTests.swift`
- Modify: every in-memory `Schema(versionedSchema: GitaSchemaV6.self)` **except** V6 fixture writers in `MigrationTests` — switch to `GitaSchemaV7.self` (`MemoryRepositoryTests`, `MemoryContextTests`, `MemoryDebugSeederTests`). Older migration tests that currently reopen under V6 must reopen under V7 (same reason as Spec 2: typealiases point at the live schema).

**Interfaces:**
- Consumes: `GitaSchemaV6` (keep file for V6 fixture writes)
- Produces:
  - `typealias LocalProfile = GitaSchemaV7.LocalProfile`
  - `LocalProfile.memoryConsentState: String` default `""`
  - `LocalProfile.consent: MemoryConsentState` (empty/unknown → `.undecided`; setter writes raw and `memoryConsent = (newValue == .enabled)`)
  - `enum MemoryConsentState: String { case undecided, enabled, disabled }`
  - `enum ConsentGateResult { case proceed, aborted }`
  - `GitaSchemaV7.versionIdentifier == Schema.Version(7, 0, 0)`
  - `prepare()` / `ensureProfile()`: if `memoryConsentState.isEmpty` then `consent = memoryConsent ? .enabled : .undecided`

- [ ] **Step 1: Write the failing migration test**

Add to `foxgitaTests/MigrationTests.swift`:

```swift
@Test func v6StoreMigratesToV7WithoutLosingRowsAndLeavesConsentUndecided() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("gita-v6-v7-\(UUID().uuidString).store")
    defer { try? FileManager.default.removeItem(at: url) }

    do {
        let v6Schema = Schema(versionedSchema: GitaSchemaV6.self)
        let config = ModelConfiguration(schema: v6Schema, url: url)
        let container = try ModelContainer(for: v6Schema, configurations: [config])
        let context = ModelContext(container)
        let task = GitaSchemaV6.TaskItem(
            id: "warm", title: "指尖热身", subtitle: "开放弦",
            category: .left, targetMin: 5, steps: ["开放弦"], profileId: "p1"
        )
        context.insert(task)
        let profile = GitaSchemaV6.LocalProfile(id: "p1", memoryConsent: false)
        context.insert(profile)
        let memory = GitaSchemaV6.MemoryItem(
            profileId: "p1", kind: .goal, key: "goal.current_song",
            summaryText: "当前目标：《晴天》前奏",
            sourceType: "debug_seed", sourceId: "goal.current_song",
            confidence: 1, importance: 1
        )
        context.insert(memory)
        try context.save()
    }

    let v7Schema = Schema(versionedSchema: GitaSchemaV7.self)
    let config = ModelConfiguration(schema: v7Schema, url: url)
    let container = try ModelContainer(
        for: v7Schema, migrationPlan: GitaMigrationPlan.self, configurations: [config]
    )
    let context = ModelContext(container)
    let tasks = try context.fetch(FetchDescriptor<TaskItem>())
    let profiles = try context.fetch(FetchDescriptor<LocalProfile>())
    let memories = try context.fetch(FetchDescriptor<MemoryItem>())
    #expect(tasks.count == 1)
    #expect(tasks[0].profileId == "p1")
    #expect(memories.count == 1)
    #expect(memories[0].summaryText == "当前目标：《晴天》前奏")
    #expect(profiles.count == 1)
    #expect(profiles[0].memoryConsent == false)
    #expect(profiles[0].memoryConsentState == "")
}
```

Add to `foxgitaTests/PracticeStoreTests.swift` (use `makeStore(seeded: true)` so seed does not insert extra templates):

```swift
    @Test func prepareMapsEmptyConsentStateFromLegacyBool() throws {
        let (store, repo, _) = makeStore(seeded: true)
        let denied = try repo.ensureDefaultProfile()
        denied.memoryConsent = false
        denied.memoryConsentState = ""
        try repo.save()
        store.prepare()
        #expect(denied.consent == .undecided)
        #expect(denied.memoryConsent == false)

        denied.memoryConsent = true
        denied.memoryConsentState = ""
        try repo.save()
        store.prepare()
        #expect(denied.consent == .enabled)
        #expect(denied.memoryConsent == true)
    }
```

`InMemoryPracticeRepository.storedProfiles` is `private(set)` — do not assign it from tests. Mutate the profile returned by `ensureDefaultProfile()`.

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MigrationTests \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

Expected: compile fail (`GitaSchemaV7` / `consent` not found) or the new tests fail.

- [ ] **Step 3: Implement Schema V7, enum, backfill, retarget tests**

Create `foxgita/Services/MemoryConsentState.swift`:

```swift
import Foundation

enum MemoryConsentState: String, Equatable, Sendable {
    case undecided
    case enabled
    case disabled
}

enum ConsentGateResult: Equatable, Sendable {
    case proceed
    case aborted
}

enum MemoryConsentCopy {
    static let lines: [String] = [
        "记忆保存在这台设备上。",
        "若启用以获得更贴合的建议，本次只会把少量相关文字发给你在设置里配置的模型服务。",
        "不会因为开启记忆而自动上传历史录音或视频；只有当前这次功能选中的内容会参与请求。",
        "你可以随时在设置里关闭或清除记忆。",
    ]
    static let enable = "启用并继续"
    static let decline = "暂不启用"
    static let title = "AI 记忆"
}
```

Copy `foxgita/Models/SchemaV6.swift` → `foxgita/Models/SchemaV7.swift`. Replace `GitaSchemaV6` with `GitaSchemaV7` everywhere in that file (including `\GitaSchemaV7.RecordingRef.session`). Set `Schema.Version(7, 0, 0)`. Replace `LocalProfile` with:

```swift
    @Model
    final class LocalProfile {
        @Attribute(.unique) var id: String
        var isActive: Bool
        var memoryConsent: Bool
        var memoryConsentState: String = ""
        var createdAt: Date
        var updatedAt: Date

        init(
            id: String = UUID().uuidString,
            isActive: Bool = true,
            memoryConsent: Bool = false,
            now: Date = Date()
        ) {
            self.id = id
            self.isActive = isActive
            self.memoryConsent = memoryConsent
            self.memoryConsentState = ""
            self.createdAt = now
            self.updatedAt = now
        }

        var consent: MemoryConsentState {
            get { MemoryConsentState(rawValue: memoryConsentState) ?? .undecided }
            set {
                memoryConsentState = newValue.rawValue
                memoryConsent = newValue == .enabled
                updatedAt = Date()
            }
        }
    }
```

Leave every other V6 model body unchanged (still `profileId` on Task/Session, no `RecordingRef.profileId`).

`Models.swift` typealiases:

```swift
typealias TaskItem = GitaSchemaV7.TaskItem
typealias PracticeSession = GitaSchemaV7.PracticeSession
typealias RecordingRef = GitaSchemaV7.RecordingRef
typealias LocalProfile = GitaSchemaV7.LocalProfile
typealias MemoryItem = GitaSchemaV7.MemoryItem
```

Migration comment + plan:

```swift
/// V5 → V6 adds profileId, LocalProfile, and MemoryItem;
/// V6 → V7 adds LocalProfile.memoryConsentState.
enum GitaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            GitaSchemaV2.self, GitaSchemaV3.self, GitaSchemaV4.self,
            GitaSchemaV5.self, GitaSchemaV6.self, GitaSchemaV7.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: GitaSchemaV2.self, toVersion: GitaSchemaV3.self),
            .lightweight(fromVersion: GitaSchemaV3.self, toVersion: GitaSchemaV4.self),
            .lightweight(fromVersion: GitaSchemaV4.self, toVersion: GitaSchemaV5.self),
            .lightweight(fromVersion: GitaSchemaV5.self, toVersion: GitaSchemaV6.self),
            .lightweight(fromVersion: GitaSchemaV6.self, toVersion: GitaSchemaV7.self),
        ]
    }
}
```

`foxgitaApp.swift`: `Schema(versionedSchema: GitaSchemaV7.self)`.

`PracticeStore.ensureProfile()`:

```swift
    private func ensureProfile() {
        perform {
            let profile = try repository.ensureDefaultProfile()
            if profile.memoryConsentState.isEmpty {
                profile.consent = profile.memoryConsent ? .enabled : .undecided
            }
            try repository.backfillEmptyProfileIds(profile.id)
            try repository.save()
        }
    }
```

Retarget in-memory helpers to `GitaSchemaV7.self`. In `MigrationTests`, keep writing fixtures with `GitaSchemaV2`/`V3`/`V4`/`V5`/`V6` as now, but reopen every “phase 2” container with `GitaSchemaV7.self` (replace current `let v6Schema = Schema(versionedSchema: GitaSchemaV6.self)` reopen sites).

- [ ] **Step 4: Run tests to verify they pass**

Same xcodebuild as Step 2, then full `foxgitaTests` once.

Expected: new tests pass; existing suites still pass.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Models/SchemaV7.swift foxgita/Services/MemoryConsentState.swift \
  foxgita/Models/Models.swift foxgita/foxgitaApp.swift \
  foxgita/Services/PracticeStore.swift \
  foxgitaTests/MigrationTests.swift foxgitaTests/PracticeStoreTests.swift \
  foxgitaTests/MemoryRepositoryTests.swift foxgitaTests/MemoryContextTests.swift \
  foxgitaTests/MemoryDebugSeederTests.swift
git commit -m "$(cat <<'EOF'
Add Schema V7 with a tri-state memory consent field.

EOF
)"
```

Only add the in-memory test files you actually changed.

---

### Task 2: MemoryRepository user CRUD

**Files:**
- Modify: `foxgita/Services/MemoryRepository.swift`
- Test: `foxgitaTests/MemoryRepositoryTests.swift`

**Interfaces:**
- Consumes: `MemoryConsentState`, `LocalProfile.consent`, `StoreError.invalidInput`
- Produces (on `MemoryRepository` and `SwiftDataMemoryRepository`):

```swift
func upsertUser(profileId: String, kind: MemoryScope, summaryText: String) throws -> MemoryItem
func updateSummary(profileId: String, id: String, summaryText: String) throws
func softDelete(profileId: String, id: String) throws
func softDeleteAll(profileId: String) throws
func setConsent(profileId: String, _ state: MemoryConsentState) throws
```

- [ ] **Step 1: Write the failing tests**

Append to `foxgitaTests/MemoryRepositoryTests.swift` (`makeRepo` already uses V7 after Task 1). Insert a profile when testing `setConsent`:

```swift
@Test func upsertUserRejectsAbilityEmptyAndOverlong() throws {
    let repo = try makeRepo()
    #expect(throws: StoreError.invalidInput) {
        try repo.upsertUser(profileId: "p1", kind: .ability, summaryText: "F 和弦")
    }
    #expect(throws: StoreError.invalidInput) {
        try repo.upsertUser(profileId: "p1", kind: .goal, summaryText: "   ")
    }
    #expect(throws: StoreError.invalidInput) {
        try repo.upsertUser(profileId: "p1", kind: .goal, summaryText: String(repeating: "啊", count: 121))
    }
}

@Test func upsertUserWritesGoalWithUserSourceAndFetches() throws {
    let repo = try makeRepo()
    let item = try repo.upsertUser(profileId: "p1", kind: .goal, summaryText: "  练晴天前奏  ")
    try repo.save()
    #expect(item.summaryText == "练晴天前奏")
    #expect(item.sourceType == "user")
    #expect(item.key.hasPrefix("user.goal."))
    #expect(item.confidence == 1)
    #expect(item.importance == 0.8)
    let rows = try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date())
    #expect(rows.map(\.summaryText) == ["练晴天前奏"])
}

@Test func updateSummaryLeavesKeyAndSoftDeleteHidesRow() throws {
    let repo = try makeRepo()
    let item = try repo.upsertUser(profileId: "p1", kind: .preference, summaryText: "每天 20 分钟")
    try repo.save()
    let key = item.key
    try repo.updateSummary(profileId: "p1", id: item.id, summaryText: "每天 30 分钟")
    try repo.save()
    let updated = try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date())
    #expect(updated[0].key == key)
    #expect(updated[0].summaryText == "每天 30 分钟")
    try repo.softDelete(profileId: "p1", id: item.id)
    try repo.save()
    #expect(try repo.fetch(profileId: "p1", scopes: [.preference], matching: "", now: Date()).isEmpty)
}

@Test func setConsentRequiresProfileAndClearAllIsIsolated() throws {
    let repo = try makeRepo()
    let schema = Schema(versionedSchema: GitaSchemaV7.self)
    // repo's context: insert two profiles via a second helper — extend makeRepo to return context
```

Change `makeRepo` to return `(SwiftDataMemoryRepository, ModelContext)` **or** add `makeRepoAndContext()`. Use:

```swift
@Test func setConsentRequiresProfileAndClearAllIsIsolated() throws {
    let schema = Schema(versionedSchema: GitaSchemaV7.self)
    let container = try ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    let context = ModelContext(container)
    let repo = SwiftDataMemoryRepository(context: context)
    let p1 = LocalProfile(id: "p1")
    let p2 = LocalProfile(id: "p2", isActive: false)
    context.insert(p1)
    context.insert(p2)
    try context.save()

    #expect(throws: StoreError.invalidInput) {
        try repo.setConsent(profileId: "", .enabled)
    }
    try repo.setConsent(profileId: "p1", .enabled)
    try repo.save()
    #expect(p1.consent == .enabled)
    #expect(p1.memoryConsent == true)
    #expect(p2.consent == .undecided)

    _ = try repo.upsertUser(profileId: "p1", kind: .goal, summaryText: "A")
    _ = try repo.upsertUser(profileId: "p2", kind: .goal, summaryText: "B")
    try repo.save()
    try repo.softDeleteAll(profileId: "p1")
    try repo.save()
    #expect(try repo.fetch(profileId: "p1", scopes: [.goal], matching: "", now: Date()).isEmpty)
    #expect(try repo.fetch(profileId: "p2", scopes: [.goal], matching: "", now: Date()).map(\.summaryText) == ["B"])
}
```

Fix the invalid `setConsent(profileId: "", _ : .enabled)` call — the signature is `setConsent(profileId:_:)`, so write `try repo.setConsent(profileId: "", .enabled)`.

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MemoryRepositoryTests test
```

Expected: compile fail (`upsertUser` missing).

- [ ] **Step 3: Implement repository methods**

Add to the protocol and `SwiftDataMemoryRepository`. Shared summary check:

```swift
    private func normalizedSummary(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 120 else { throw StoreError.invalidInput }
        return text
    }

    func upsertUser(profileId: String, kind: MemoryScope, summaryText: String) throws -> MemoryItem {
        guard !profileId.isEmpty else { throw StoreError.invalidInput }
        guard kind == .goal || kind == .preference else { throw StoreError.invalidInput }
        let summary = try normalizedSummary(summaryText)
        let item = MemoryItem(
            profileId: profileId,
            kind: kind,
            key: "user.\(kind.rawValue).\(UUID().uuidString)",
            summaryText: summary,
            sourceType: "user",
            sourceId: "",
            confidence: 1,
            importance: 0.8
        )
        context.insert(item)
        return item
    }

    func updateSummary(profileId: String, id: String, summaryText: String) throws {
        guard !profileId.isEmpty, !id.isEmpty else { throw StoreError.invalidInput }
        let summary = try normalizedSummary(summaryText)
        let pid = profileId
        let itemId = id
        guard let item = try context.fetch(
            FetchDescriptor<MemoryItem>(
                predicate: #Predicate { $0.profileId == pid && $0.id == itemId && $0.deletedAt == nil }
            )
        ).first else { throw StoreError.invalidInput }
        item.summaryText = summary
        item.updatedAt = Date()
    }

    func softDelete(profileId: String, id: String) throws {
        guard !profileId.isEmpty, !id.isEmpty else { throw StoreError.invalidInput }
        let pid = profileId
        let itemId = id
        guard let item = try context.fetch(
            FetchDescriptor<MemoryItem>(
                predicate: #Predicate { $0.profileId == pid && $0.id == itemId && $0.deletedAt == nil }
            )
        ).first else { return }
        item.deletedAt = Date()
        item.updatedAt = Date()
    }

    func softDeleteAll(profileId: String) throws {
        guard !profileId.isEmpty else { throw StoreError.invalidInput }
        let pid = profileId
        let rows = try context.fetch(
            FetchDescriptor<MemoryItem>(
                predicate: #Predicate { $0.profileId == pid && $0.deletedAt == nil }
            )
        )
        let now = Date()
        for row in rows {
            row.deletedAt = now
            row.updatedAt = now
        }
    }

    func setConsent(profileId: String, _ state: MemoryConsentState) throws {
        guard !profileId.isEmpty else { throw StoreError.invalidInput }
        let pid = profileId
        guard let profile = try context.fetch(
            FetchDescriptor<LocalProfile>(predicate: #Predicate { $0.id == pid })
        ).first else { throw StoreError.invalidInput }
        profile.consent = state
    }
```

Keep `upsertDebug` / `fetch` / `save` unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Same MemoryRepositoryTests command, then full `foxgitaTests`.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/MemoryRepository.swift foxgitaTests/MemoryRepositoryTests.swift
git commit -m "$(cat <<'EOF'
Add user-authored memory writes and consent updates.

EOF
)"
```

---

### Task 3: LiveMemoryContext reads tri-state

**Files:**
- Modify: `foxgita/Services/MemoryContextProviding.swift`
- Modify: `foxgitaTests/MemoryContextTests.swift`

**Interfaces:**
- Consumes: `LocalProfile.consent`
- Produces: `LiveMemoryContext` returns `""` unless `profile.consent == .enabled`

- [ ] **Step 1: Write the failing test**

Replace the Bool assignments in `MemoryContextTests` so the “on” case uses `.enabled` and add an undecided case. Keep `scopedPlanFromImage()` (builtins already have scopes from Spec 2; leaving the copy is fine).

```swift
    @Test func liveReturnsEmptyWhenConsentOffEvenIfMemoriesExist() async throws {
        let (live, _, profile) = try makeLive()
        profile.consent = .disabled
        let text = await live.block(skill: scopedPlanFromImage(), query: "")
        #expect(text == "")
    }

    @Test func liveReturnsEmptyWhenUndecidedEvenIfMemoriesExist() async throws {
        let (live, _, profile) = try makeLive()
        profile.consent = .undecided
        let text = await live.block(skill: scopedPlanFromImage(), query: "")
        #expect(text == "")
    }

    @Test func liveReturnsWrappedGoalWhenConsentOn() async throws {
        let (live, _, profile) = try makeLive()
        profile.consent = .enabled
        let text = await live.block(skill: scopedPlanFromImage(), query: "")
        #expect(text.contains("<<<BACKGROUND_MEMORY>>>"))
        #expect(text.contains("当前目标：《晴天》前奏"))
        #expect(!text.contains("[ability]"))
    }
```

`makeLive()` still inserts `LocalProfile(id: "p1", memoryConsent: false)` (state `""` → undecided).

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MemoryContextTests test
```

Expected: `liveReturnsWrappedGoalWhenConsentOn` fails because Live still keys off `memoryConsent` Bool (false) even after `consent = .enabled` if the setter is not used by Live — actually the setter also sets `memoryConsent = true`, so the existing Bool gate would **pass** the on test. The new **undecided** test will fail if someone sets `consent = .undecided` after having enabled, or: initial `memoryConsent false` already returns "". 

To force a RED that proves Live ignores the Bool: in `liveReturnsEmptyWhenUndecidedEvenIfMemoriesExist`, also set `profile.memoryConsent = true` while `consent == .undecided`:

```swift
        profile.memoryConsent = true
        profile.memoryConsentState = MemoryConsentState.undecided.rawValue
```

Then Live-on-Bool would inject, and the test fails until Live reads `consent`.

- [ ] **Step 3: Change the Live gate**

In `LiveMemoryContext.build`, replace `guard let profile, profile.memoryConsent else { return "" }` with:

```swift
            guard let profile, profile.consent == .enabled else { return "" }
```

- [ ] **Step 4: Run tests to verify they pass**

Same suite, then full `foxgitaTests`.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/MemoryContextProviding.swift foxgitaTests/MemoryContextTests.swift
git commit -m "$(cat <<'EOF'
Inject memory only when consent is enabled.

EOF
)"
```

---

### Task 4: MemoryStore

**Files:**
- Create: `foxgita/Services/MemoryStore.swift`
- Test: `foxgitaTests/MemoryStoreTests.swift`

**Interfaces:**
- Consumes: `MemoryRepository` product APIs from Task 2; `ModelContext` for active `LocalProfile`
- Produces:

```swift
@MainActor @Observable
final class MemoryStore {
    private(set) var consent: MemoryConsentState
    private(set) var items: [MemoryItem]
    private(set) var lastError: StoreError?
    init(repository: MemoryRepository, context: ModelContext)
    func reload()
    @discardableResult func setConsent(_ state: MemoryConsentState) -> Bool
    @discardableResult func add(kind: MemoryScope, summary: String) -> Bool
    @discardableResult func updateSummary(id: String, summary: String) -> Bool
    @discardableResult func delete(id: String) -> Bool
    @discardableResult func clearAll() -> Bool
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct MemoryStoreTests {
    private func makeStore() throws -> (MemoryStore, LocalProfile) {
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
        let store = MemoryStore(repository: repo, context: context)
        store.reload()
        return (store, profile)
    }

    @Test func addFailsWhenConsentIsNotEnabled() throws {
        let (store, profile) = try makeStore()
        profile.consent = .disabled
        try store.repositorySaveForTest() // do NOT add this helper — instead reload after setting consent via store
    }
}
```

Do not add `repositorySaveForTest`. Write:

```swift
    @Test func addFailsWhenConsentIsNotEnabled() throws {
        let (store, _) = try makeStore()
        #expect(store.setConsent(.disabled))
        #expect(store.add(kind: .goal, summary: "练晴天") == false)
        #expect(store.lastError == .invalidInput)
        #expect(store.items.isEmpty)
    }

    @Test func addAndDeleteRoundTrip() throws {
        let (store, _) = try makeStore()
        #expect(store.add(kind: .goal, summary: "练晴天前奏"))
        #expect(store.items.map(\.summaryText) == ["练晴天前奏"])
        let id = store.items[0].id
        #expect(store.updateSummary(id: id, summary: "练间奏"))
        #expect(store.items[0].summaryText == "练间奏")
        #expect(store.delete(id: id))
        #expect(store.items.isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MemoryStoreTests test
```

Expected: `MemoryStore` not found.

- [ ] **Step 3: Implement MemoryStore**

```swift
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class MemoryStore {
    private let repository: MemoryRepository
    private let context: ModelContext

    private(set) var consent: MemoryConsentState = .undecided
    private(set) var items: [MemoryItem] = []
    private(set) var lastError: StoreError?

    init(repository: MemoryRepository, context: ModelContext) {
        self.repository = repository
        self.context = context
    }

    func reload() {
        do {
            lastError = nil
            let profile = try activeProfile()
            consent = profile?.consent ?? .undecided
            guard let id = profile?.id, !id.isEmpty else {
                items = []
                return
            }
            items = try repository.fetch(
                profileId: id,
                scopes: [.goal, .preference, .ability, .fact, .summary],
                matching: "",
                now: Date()
            )
        } catch {
            lastError = StoreError.from(error)
            items = []
        }
    }

    @discardableResult
    func setConsent(_ state: MemoryConsentState) -> Bool {
        mutate { profileId in
            try repository.setConsent(profileId: profileId, state)
        }
    }

    @discardableResult
    func add(kind: MemoryScope, summary: String) -> Bool {
        guard consent == .enabled else {
            lastError = .invalidInput
            return false
        }
        return mutate { profileId in
            _ = try repository.upsertUser(profileId: profileId, kind: kind, summaryText: summary)
        }
    }

    @discardableResult
    func updateSummary(id: String, summary: String) -> Bool {
        mutate { profileId in
            try repository.updateSummary(profileId: profileId, id: id, summaryText: summary)
        }
    }

    @discardableResult
    func delete(id: String) -> Bool {
        mutate { profileId in
            try repository.softDelete(profileId: profileId, id: id)
        }
    }

    @discardableResult
    func clearAll() -> Bool {
        mutate { profileId in
            try repository.softDeleteAll(profileId: profileId)
        }
    }

    private func mutate(_ work: (String) throws -> Void) -> Bool {
        do {
            guard let id = try activeProfile()?.id, !id.isEmpty else {
                lastError = .invalidInput
                return false
            }
            try work(id)
            try repository.save()
            reload()
            return lastError == nil
        } catch {
            lastError = StoreError.from(error)
            return false
        }
    }

    private func activeProfile() throws -> LocalProfile? {
        try context.fetch(
            FetchDescriptor<LocalProfile>(predicate: #Predicate { $0.isActive == true })
        ).first
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

MemoryStoreTests, then full `foxgitaTests`.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/MemoryStore.swift foxgitaTests/MemoryStoreTests.swift
git commit -m "$(cat <<'EOF'
Add MemoryStore for consent and user memory edits.

EOF
)"
```

---

### Task 5: Settings AI 记忆 page

**Files:**
- Modify: `foxgita/foxgitaApp.swift` (`.environment(memoryStore)`; `memoryStore.reload()` after `store.prepare()`)
- Modify: `foxgita/Features/Settings/SettingsView.swift`
- Create: `foxgita/Features/Settings/AIMemorySettingsView.swift`
- Test: `foxgitaTests/MemoryConsentCopyTests.swift` (copy constants — UI has no cheap snapshot harness)

**Interfaces:**
- Consumes: `MemoryStore`, `MemoryConsentCopy`
- Produces: Settings row + management page. Toggle on ↔ `.enabled`, off ↔ `.disabled`. `undecided` shows toggle off. Add allowed only when `consent == .enabled`. `ability`/`fact`/`summary` rows read-only.

- [ ] **Step 1: Write the failing copy test**

```swift
import Testing
@testable import foxgita

struct MemoryConsentCopyTests {
    @Test func frozenPrivacyLines() {
        #expect(MemoryConsentCopy.lines == [
            "记忆保存在这台设备上。",
            "若启用以获得更贴合的建议，本次只会把少量相关文字发给你在设置里配置的模型服务。",
            "不会因为开启记忆而自动上传历史录音或视频；只有当前这次功能选中的内容会参与请求。",
            "你可以随时在设置里关闭或清除记忆。",
        ])
        #expect(MemoryConsentCopy.enable == "启用并继续")
        #expect(MemoryConsentCopy.decline == "暂不启用")
        #expect(MemoryConsentCopy.title == "AI 记忆")
    }
}
```

This should already pass if Task 1 copied the strings exactly — if you deferred the strings to this task, put them in `MemoryConsentState.swift` now so this test is the lock. If Task 1 already has them, keep this test as the regression lock and still add the UI.

- [ ] **Step 2: Run test**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MemoryConsentCopyTests test
```

Expected: PASS on copy; UI does not exist yet.

- [ ] **Step 3: Implement settings UI**

`foxgitaApp.init`: after `memoryRepo` / `liveMemory`:

```swift
            let memoryStore = MemoryStore(repository: memoryRepo, context: container.mainContext)
            self.memoryStore = memoryStore
```

Add `private let memoryStore: MemoryStore`. In `body`:

```swift
                .environment(memoryStore)
```

In `onAppear`, after `store.prepare()` (and DEBUG seeder): `memoryStore.reload()`.

`SettingsView.body`: wrap the existing `ZStack { ... }` in `NavigationStack { ... }`. After the AI 接口 `group { ... }` (the padding(16) VStack that ends with the 费用说明), before `sectionLabel("关于")`, insert:

```swift
                    sectionLabel("AI 记忆")
                    group {
                        NavigationLink {
                            AIMemorySettingsView()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("AI 记忆").font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(GitaTheme.textPrimary)
                                    Text("Gita 记住的目标和偏好")
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

Create `AIMemorySettingsView.swift`:

```swift
import SwiftUI

struct AIMemorySettingsView: View {
    @Environment(MemoryStore.self) private var memoryStore
    @State private var showAdd = false
    @State private var addKind: MemoryScope = .goal
    @State private var addSummary = ""
    @State private var editing: MemoryItem?
    @State private var editSummary = ""
    @State private var pendingDelete: MemoryItem?
    @State private var showClear = false

    var body: some View {
        @Bindable var memoryStore = memoryStore
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                toggleCard
                ForEach(MemoryConsentCopy.lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundStyle(GitaTheme.textSecondary)
                }
                group(title: "目标", items: memoryStore.items.filter { $0.kind == .goal })
                group(title: "偏好", items: memoryStore.items.filter { $0.kind == .preference })
                readOnlyGroup(title: "能力", items: memoryStore.items.filter { $0.kind == .ability })
                if memoryStore.consent == .enabled {
                    Button("添加记忆") { showAdd = true }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GitaTheme.brand500)
                }
                if !memoryStore.items.isEmpty {
                    Button("清除全部 AI 记忆", role: .destructive) { showClear = true }
                }
            }
            .padding(16)
        }
        .background(PageBackground())
        .navigationTitle(MemoryConsentCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { memoryStore.reload() }
        .sheet(isPresented: $showAdd) { addSheet }
        .sheet(item: $editing) { item in
            NavigationStack {
                Form {
                    TextField("摘要", text: $editSummary, axis: .vertical)
                }
                .navigationTitle("编辑记忆")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { editing = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            _ = memoryStore.updateSummary(id: item.id, summary: editSummary)
                            editing = nil
                        }
                    }
                }
            }
        }
        .alert("删除这条记忆？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let id = pendingDelete?.id { _ = memoryStore.delete(id: id) }
                pendingDelete = nil
            }
        }
        .alert("清除全部 AI 记忆？", isPresented: $showClear) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { _ = memoryStore.clearAll() }
        } message: {
            Text("删除后不会再发给模型。练习记录不会动。")
        }
    }

    private var toggleCard: some View {
        Toggle(isOn: Binding(
            get: { memoryStore.consent == .enabled },
            set: { _ = memoryStore.setConsent($0 ? .enabled : .disabled) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("允许 AI 使用长期记忆").font(.system(size: 14, weight: .semibold))
                Text("关闭后不读取也不再弹出说明")
                    .font(.system(size: 12))
                    .foregroundStyle(GitaTheme.textSecondary)
            }
        }
        .tint(GitaTheme.brand500)
        .padding(16)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func group(title: String, items: [MemoryItem]) -> some View {
        if items.isEmpty && memoryStore.consent == .enabled && title == "目标"
            && memoryStore.items.filter({ $0.kind == .goal || $0.kind == .preference }).isEmpty {
            Text("还没有记忆，添加一条目标或偏好")
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
        }
        if !items.isEmpty {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(GitaTheme.textSecondary)
            ForEach(items, id: \.id) { item in
                row(item, canEdit: item.kind == .goal || item.kind == .preference)
            }
        }
    }

    @ViewBuilder
    private func readOnlyGroup(title: String, items: [MemoryItem]) -> some View {
        if !items.isEmpty {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(GitaTheme.textSecondary)
            ForEach(items, id: \.id) { item in row(item, canEdit: false) }
        }
    }

    private func row(_ item: MemoryItem, canEdit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.summaryText).font(.system(size: 14, weight: .semibold))
            Text(sourceLabel(item.sourceType))
                .font(.system(size: 12))
                .foregroundStyle(GitaTheme.textSecondary)
            HStack {
                if canEdit {
                    Button("编辑") {
                        editSummary = item.summaryText
                        editing = item
                    }
                }
                Button("删除", role: .destructive) { pendingDelete = item }
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func sourceLabel(_ raw: String) -> String {
        switch raw {
        case "user": return String(localized: "你添加的")
        case "debug_seed": return String(localized: "调试种子")
        default: return raw
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Picker("类型", selection: $addKind) {
                    Text("目标").tag(MemoryScope.goal)
                    Text("偏好").tag(MemoryScope.preference)
                }
                TextField("摘要", text: $addSummary, axis: .vertical)
            }
            .navigationTitle("添加记忆")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showAdd = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        if memoryStore.add(kind: addKind, summary: addSummary) {
                            addSummary = ""
                            showAdd = false
                        }
                    }
                }
            }
        }
    }
}

extension MemoryItem: @retroactive Identifiable {}
```

**Do not** add `@retroactive Identifiable` if `MemoryItem` already has `id` used by ForEach via `id: \.id` — the `ForEach(items, id: \.id)` path does **not** need Identifiable. Remove `extension MemoryItem: Identifiable` and the `.sheet(item: $editing)` Identifiable requirement: keep `editing` as `MemoryItem?` and present with `.sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }))` plus the form.

`MemoryItem` is a class; using it as `sheet(item:)` needs Identifiable. Prefer `ForEach(..., id: \.id)` only and a Bool sheet for edit, storing `editingId: String?`.

Empty state: one caption when enabled and no goal/preference items.

Also show `fact` / `summary` read-only groups the same way as ability if any exist.

- [ ] **Step 4: Run tests**

MemoryConsentCopyTests + full `foxgitaTests`. Fix compile errors (preview / Identifiable) until the suite is green.

- [ ] **Step 5: Commit**

```bash
git add foxgita/foxgitaApp.swift \
  foxgita/Features/Settings/SettingsView.swift \
  foxgita/Features/Settings/AIMemorySettingsView.swift \
  foxgitaTests/MemoryConsentCopyTests.swift
git commit -m "$(cat <<'EOF'
Add the AI memory settings page.

EOF
)"
```

---

### Task 6: First-use consent sheet + generate gates

**Files:**
- Create: `foxgita/Services/MemoryConsentCoordinator.swift`
- Create: `foxgita/Features/Settings/MemoryConsentSheet.swift`
- Modify: `foxgita/foxgitaApp.swift` (environment coordinator)
- Modify: `foxgita/Features/Practice/PhotoPracticeSheet.swift`
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift`
- Modify: `foxgita/Features/Record/RecordDetailView.swift`
- Modify: `foxgita/Features/Practice/VideoAnalysisView.swift` (gate **only** on `retry()` enqueue; do not commit unrelated dirty hunks)
- Test: `foxgitaTests/MemoryConsentCoordinatorTests.swift`

**Interfaces:**
- Consumes: `MemoryStore.setConsent`, `ConsentGateResult`
- Produces:

```swift
@MainActor @Observable
final class MemoryConsentCoordinator {
    var isPresented: Bool
    init(store: MemoryStore)
    func ensureDecided() async -> ConsentGateResult
    func chooseEnabled()
    func chooseDisabled()
}
```

`ReviewJobRunner` stays sheet-free. Gate at the three UI enqueue sites and Photo generate.

- [ ] **Step 1: Write the failing coordinator tests**

```swift
import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct MemoryConsentCoordinatorTests {
    private func make() throws -> (MemoryConsentCoordinator, MemoryStore, LocalProfile) {
        let schema = Schema(versionedSchema: GitaSchemaV7.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profile = LocalProfile(id: "p1")
        context.insert(profile)
        try context.save()
        let repo = SwiftDataMemoryRepository(context: context)
        let store = MemoryStore(repository: repo, context: context)
        store.reload()
        return (MemoryConsentCoordinator(store: store), store, profile)
    }

    @Test func proceedWithoutSheetWhenAlreadyDecided() async throws {
        let (coordinator, store, _) = try make()
        #expect(store.setConsent(.disabled))
        let result = await coordinator.ensureDecided()
        #expect(result == .proceed)
        #expect(coordinator.isPresented == false)
    }

    @Test func undecidedWaitsThenEnableContinues() async throws {
        let (coordinator, store, _) = try make()
        #expect(store.consent == .undecided)
        let task = Task { await coordinator.ensureDecided() }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(coordinator.isPresented == true)
        coordinator.chooseEnabled()
        let result = await task.value
        #expect(result == .proceed)
        #expect(store.consent == .enabled)
        #expect(coordinator.isPresented == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MemoryConsentCoordinatorTests test
```

Expected: `MemoryConsentCoordinator` not found.

- [ ] **Step 3: Implement coordinator, sheet, and gates**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class MemoryConsentCoordinator {
    private let store: MemoryStore
    var isPresented = false
    private var waiter: CheckedContinuation<ConsentGateResult, Never>?

    init(store: MemoryStore) {
        self.store = store
    }

    func ensureDecided() async -> ConsentGateResult {
        store.reload()
        if store.consent == .enabled || store.consent == .disabled {
            return .proceed
        }
        isPresented = true
        return await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }

    func chooseEnabled() { finish(set: .enabled) }
    func chooseDisabled() { finish(set: .disabled) }

    private func finish(set state: MemoryConsentState) {
        let ok = store.setConsent(state)
        isPresented = false
        waiter?.resume(returning: ok ? .proceed : .aborted)
        waiter = nil
    }
}
```

`MemoryConsentSheet.swift`:

```swift
import SwiftUI

struct MemoryConsentSheet: View {
    var onEnable: () -> Void
    var onDecline: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(MemoryConsentCopy.lines, id: \.self) { line in
                    Text(line).font(.system(size: 15))
                }
                Spacer()
                Button(action: onEnable) {
                    Text(MemoryConsentCopy.enable)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(GitaTheme.brand500)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button(MemoryConsentCopy.decline, action: onDecline)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .padding(20)
            .navigationTitle(MemoryConsentCopy.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(false)
    }
}
```

Add a small helper used by the four views (put it in `MemoryConsentCoordinator.swift` or a SwiftUI file):

```swift
import SwiftUI

struct MemoryConsentGateModifier: ViewModifier {
    @Environment(MemoryConsentCoordinator.self) private var coordinator

    func body(content: Content) -> some View {
        @Bindable var coordinator = coordinator
        content
            .sheet(isPresented: $coordinator.isPresented, onDismiss: {
                if coordinator.isPresented == false {
                    // sheet already finished via buttons; if user swiped down while waiting:
                    coordinator.chooseDisabled()
                }
            }) {
                MemoryConsentSheet(
                    onEnable: { coordinator.chooseEnabled() },
                    onDecline: { coordinator.chooseDisabled() }
                )
            }
    }
}

extension View {
    func memoryConsentGate() -> some View {
        modifier(MemoryConsentGateModifier())
    }
}
```

**Dismiss bug:** `onDismiss` + `chooseDisabled` will double-resume if the user tapped a button (which already set `isPresented = false`). Guard with the waiter:

Change coordinator:

```swift
    func chooseEnabled() { finish(set: .enabled) }
    func chooseDisabled() { finish(set: .disabled) }

    private func finish(set state: MemoryConsentState) {
        guard waiter != nil else { return }
        let ok = store.setConsent(state)
        isPresented = false
        waiter?.resume(returning: ok ? .proceed : .aborted)
        waiter = nil
    }
```

Then `onDismiss: { coordinator.chooseDisabled() }` is safe: button path clears waiter first; swipe-down still disables.

`foxgitaApp`: `let coordinator = MemoryConsentCoordinator(store: memoryStore)` stored property; `.environment(coordinator)`.

`PhotoPracticeSheet`: `@Environment(MemoryConsentCoordinator.self) private var consent`. Attach `.memoryConsentGate()` on the sheet’s root. In both `beginGeneration` methods, **before** `prepareGeneration()`:

```swift
        generateTask = Task {
            let gate = await consent.ensureDecided()
            guard gate == .proceed else { return }
            prepareGeneration()
            ...
        }
```

Move `prepareGeneration()` inside the Task after the gate so a declined first-use does not leave the UI in `.generating`.

`PracticeDetailView.persist` — replace the configured enqueue block with:

```swift
        if llmCredentials.isConfigured(baseURL: llmBaseURL, model: llmModel) {
            let clipId = clip.id
            let fileName = clip.fileName
            Task { @MainActor in
                guard await consent.ensureDecided() == .proceed else { return }
                store.markReviewsPending(recordingIds: [clipId])
                reviewRunner.enqueue([clipId], baseURL: llmBaseURL, model: llmModel)
                if MediaReviewMedia.isVideo(fileName: fileName) {
                    analysisRoute = VideoRoute(id: clipId, durationSec: clip.durationSec)
                }
            }
        }
```

Add `@Environment(MemoryConsentCoordinator.self) private var consent` and `.memoryConsentGate()` on the detail root.

`RecordDetailView.requestReview`:

```swift
    private func requestReview(_ r: RecordingRef) {
        if llmCredentials.isConfigured(baseURL: llmBaseURL, model: llmModel) {
            Task { @MainActor in
                guard await consent.ensureDecided() == .proceed else { return }
                store.markReviewsPending(recordingIds: [r.id])
                reviewRunner.enqueue([r.id], baseURL: llmBaseURL, model: llmModel)
            }
        } else {
            show(String(localized: "先去设置里填写 AI 接口"))
        }
    }
```

Same environment + modifier.

`VideoAnalysisView.retry` — only wrap enqueue:

```swift
    private func retry() {
        Task { @MainActor in
            guard await consent.ensureDecided() == .proceed else { return }
            displayPercent = 0
            store.markReviewsPending(recordingIds: [recordingId])
            runner.enqueue([recordingId], baseURL: llmBaseURL, model: llmModel)
        }
    }
```

Add environment + `.memoryConsentGate()`. Do not stage unrelated `VideoAnalysisView` changes.

- [ ] **Step 4: Run tests**

Coordinator tests + full `foxgitaTests`.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/MemoryConsentCoordinator.swift \
  foxgita/Features/Settings/MemoryConsentSheet.swift \
  foxgita/foxgitaApp.swift \
  foxgita/Features/Practice/PhotoPracticeSheet.swift \
  foxgita/Features/Practice/PracticeDetailView.swift \
  foxgita/Features/Record/RecordDetailView.swift \
  foxgita/Features/Practice/VideoAnalysisView.swift \
  foxgitaTests/MemoryConsentCoordinatorTests.swift
git commit -m "$(cat <<'EOF'
Ask for memory consent once before the first AI generate.

EOF
)"
```

---

### Task 7: Debug seeder + docs

**Files:**
- Modify: `foxgita/Services/MemoryDebugSeeder.swift`
- Modify: `foxgitaTests/MemoryDebugSeederTests.swift`
- Modify: `docs/TECHNICAL.md`
- Modify: `docs/TEST_PLAN_CLI.md`
- Modify: `docs/superpowers/2026-08-21-memory-consent-ui/specs/2026-08-21-memory-consent-ui-design.md` (status line)

**Interfaces:**
- Consumes: `LocalProfile.consent`
- Produces: seeder sets `profile.consent = .enabled`; docs name Schema V7, MemoryStore, consent sheet

- [ ] **Step 1: Write the failing seeder assertion**

In `seedIfNeededNoopsUnlessFlagSet`, after the flag-on seed:

```swift
        #expect(profile.consent == .enabled)
        #expect(profile.memoryConsent == true)
```

Keep the existing key assertions.

- [ ] **Step 2: Run test**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MemoryDebugSeederTests test
```

Expected: FAIL on `consent == .enabled` until the seeder writes the state (Bool `true` alone is not enough if Live reads `consent`).

- [ ] **Step 3: Update seeder and docs**

In `MemoryDebugSeeder.seedIfNeeded`, replace `profile.memoryConsent = true` with `profile.consent = .enabled`.

`docs/TECHNICAL.md`: Schema V6 → V7 in §3 tree, §6.1, §6.2 title/container line; document `memoryConsentState`; mention Settings → AI 记忆, first-use sheet, `MemoryStore`, user CRUD, Live injects only `.enabled`. `prepare()`: seed → ensure Profile / backfill `profileId` / empty consent state → GC. Do not claim AI candidate writes.

`docs/TEST_PLAN_CLI.md`: keep iPhone 17. Update MigrationTests row to V6→V7. Add rows:

| Suite | 预期 |
|---|---|
| `MemoryStoreTests` | 未启用不能添加；增删改摘要 |
| `MemoryConsentCoordinatorTests` | 已决定不弹；未选择启用后 proceed |
| `MemoryConsentCopyTests` | 四条隐私文案与按钮文案 |

Update `MemoryDebugSeederTests` row: flag 写入附录 B 三条并 `consent == enabled`.

Spec header status: `Approved — implemented` (code already on this branch when this task lands). If you run this task after code: use that. If somehow docs-first: `Approved — implementation plan ready`.

- [ ] **Step 4: Run full suite**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/MemoryDebugSeeder.swift \
  foxgitaTests/MemoryDebugSeederTests.swift \
  docs/TECHNICAL.md docs/TEST_PLAN_CLI.md \
  docs/superpowers/2026-08-21-memory-consent-ui/specs/2026-08-21-memory-consent-ui-design.md
git commit -m "$(cat <<'EOF'
Document Schema V7 consent UI and enable debug seeds.

EOF
)"
```

---

## Self-review

**Spec coverage:** V7 + backfill (T1); user CRUD (T2); Live `.enabled` only (T3); MemoryStore (T4); settings page + copy (T5); first-use sheet + four generate gates (T6); seeder `.enabled` + docs (T7). Out of scope items have no tasks.

If you find issues, fix them inline. No need to re-review.

**Types:** `upsertUser` / `setConsent(profileId:_:)` / `MemoryStore` Bool-returning methods / `ensureDecided() -> ConsentGateResult` are consistent across tasks.
