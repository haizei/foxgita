# AI Current-Focus Candidate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a successful review or video diagnosis persist, write one low-confidence `ability.current_focus` candidate per profile so the latest `focus` injects into Skills, without resurrecting deletions or rolling back the review.

**Architecture:** `MemoryRepository` gains `upsertAICandidate` with tombstone and non-`ai` source guards. `AICandidateSync` gates on consent and `memoryWritePolicy == .candidates`. `PracticeStore` calls it after `applyReview` / `applyVideoDiagnosis` save succeeds. `ReviewJobRunner`, Generators, and frozen prompts stay unchanged. No Schema V8.

**Tech Stack:** iOS 18+ · SwiftUI · SwiftData Schema V7 · Swift Testing · existing `PracticeStore` / `TaskMemorySync` / `LiveMemoryContext`

## Global Constraints

- Spec: `docs/superpowers/2026-08-21-ai-candidate-memory/specs/2026-08-21-ai-candidate-memory-design.md`
- iOS 18+ · Scheme `foxgita` · cwd `foxgita/` (this nested git repo)
- Do not bump Schema (no V8). Do not edit `project.pbxproj` (synchronized root groups pick up new Swift files)
- Do not change Generator protocols, `AITransport`, Draft DTOs, frozen system/user prompt strings, or Keychain
- Do not change `ReviewJobRunner` wiring
- `practice.plan.from_image` stays `memoryWritePolicy = .deny`. Only `practice.review.media` and `practice.diagnose.video` become `.candidates`. Versions stay `1.1.0`
- Do not implement 3-session upgrade, confirm UI, `highlight`/`nextAction` memories, result-page citations, call logs, or `practice.next_session`
- Do not call Sync from `markReviewsPending` / `markReviewsFailed` / `prepare()` / image-plan path
- Candidate fields: `kind = .ability`, `key = "ability.current_focus"`, `sourceType = "ai"`, `sourceId = recordingId`, `valueJSON = "\(skill.id)@\(skill.version)"`, `confidence = 0.4`, `importance = 0.4`, `expiresAt = nil`
- Focus: trim; empty → no-op; `count > 120` → truncate to 120 Swift `Character`s
- `upsertAICandidate` does **not** `save()`; caller saves
- `AICandidateSync.syncFocus` does **not** throw; it sets `lastError`
- Call Sync **after** `PracticeStore.perform` returns successfully — never inside the same `perform` as the review write (same `ModelContext`; a combined save would risk rolling back the review)
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
| `foxgita/Services/MemoryRepository.swift` | Protocol + `upsertAICandidate`; `updateSummary` flips `ai` → `user` |
| `foxgita/Services/SkillDefinition.swift` | Review + diagnose `.candidates` |
| `foxgita/Services/AICandidateSync.swift` | Consent + write-policy gate, lastError, save |
| `foxgita/Services/PracticeStore.swift` | Optional sync after successful review/diagnosis persist |
| `foxgita/foxgitaApp.swift` | Construct and inject `AICandidateSync` next to `TaskMemorySync` |
| `foxgita/Features/Settings/AIMemorySettingsView.swift` | `sourceLabel` for `"ai"` |
| `foxgitaTests/MemoryRepositoryTests.swift` | Tombstone, truncate, user-priority, flip, dual profile |
| `foxgitaTests/AICandidateSyncTests.swift` | Consent, deny skill, overwrite, Store-wired cases |
| `foxgitaTests/SkillRegistryTests.swift` | Write-policy snapshot |
| `foxgitaTests/MemoryContextTests.swift` | Candidate appears in review wrapper |
| `docs/TECHNICAL.md` | Candidate key and write-policy |

---

### Task 1: MemoryRepository AI-candidate writes

**Files:**
- Modify: `foxgita/Services/MemoryRepository.swift`
- Modify: `foxgitaTests/MemoryRepositoryTests.swift`

**Interfaces:**
- Consumes: existing `MemoryItem`, `MemoryScope.ability`, `StoreError.invalidInput`, `fetch` (still excludes soft-deleted)
- Produces:
  - `func upsertAICandidate(profileId: String, recordingId: String, summaryText: String, valueJSON: String) throws`
  - Lookup key `"ability.current_focus"` **including** soft-deleted rows
  - `updateSummary`: if live row `sourceType == "ai"` (in addition to existing `"task"`), set `sourceType = "user"` after writing summary
  - Does not `save()`

- [ ] **Step 1: Write the failing repository tests**

Append to `foxgitaTests/MemoryRepositoryTests.swift`:

```swift
    @Test func upsertAICandidateRejectsEmptyIdsAndSkipsBlankSummary() throws {
        let repo = try makeRepo()
        #expect(throws: StoreError.invalidInput) {
            try repo.upsertAICandidate(
                profileId: "", recordingId: "clip-1",
                summaryText: "压弦", valueJSON: "practice.review.media@1.1.0"
            )
        }
        #expect(throws: StoreError.invalidInput) {
            try repo.upsertAICandidate(
                profileId: "p1", recordingId: "",
                summaryText: "压弦", valueJSON: "practice.review.media@1.1.0"
            )
        }
        try repo.upsertAICandidate(
            profileId: "p1", recordingId: "clip-1",
            summaryText: "   ", valueJSON: "practice.review.media@1.1.0"
        )
        try repo.save()
        #expect(try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)
    }

    @Test func upsertAICandidateInsertsTruncatesAndUpdatesAISourcedRow() throws {
        let repo = try makeRepo()
        try repo.upsertAICandidate(
            profileId: "p1", recordingId: "clip-1",
            summaryText: "  压弦  ", valueJSON: "practice.review.media@1.1.0"
        )
        try repo.save()
        var rows = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].key == "ability.current_focus")
        #expect(rows[0].kind == .ability)
        #expect(rows[0].summaryText == "压弦")
        #expect(rows[0].sourceType == "ai")
        #expect(rows[0].sourceId == "clip-1")
        #expect(rows[0].valueJSON == "practice.review.media@1.1.0")
        #expect(rows[0].confidence == 0.4)
        #expect(rows[0].importance == 0.4)
        #expect(rows[0].expiresAt == nil)

        let long = String(repeating: "啊", count: 121)
        try repo.upsertAICandidate(
            profileId: "p1", recordingId: "clip-2",
            summaryText: long, valueJSON: "practice.diagnose.video@1.1.0"
        )
        try repo.save()
        rows = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].summaryText.count == 120)
        #expect(rows[0].summaryText == String(long.prefix(120)))
        #expect(rows[0].sourceId == "clip-2")
        #expect(rows[0].valueJSON == "practice.diagnose.video@1.1.0")
        #expect(rows[0].confidence == 0.4)
        #expect(rows[0].importance == 0.4)
    }

    @Test func upsertAICandidateDoesNotOverwriteUserEditedOrTombstone() throws {
        let repo = try makeRepo()
        try repo.upsertAICandidate(
            profileId: "p1", recordingId: "clip-1",
            summaryText: "旧重点", valueJSON: "practice.review.media@1.1.0"
        )
        try repo.save()
        let id = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())[0].id
        try repo.updateSummary(profileId: "p1", id: id, summaryText: "我改的")
        try repo.save()
        var rows = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
        #expect(rows[0].sourceType == "user")
        #expect(rows[0].key == "ability.current_focus")
        try repo.upsertAICandidate(
            profileId: "p1", recordingId: "clip-9",
            summaryText: "新重点", valueJSON: "practice.review.media@1.1.0"
        )
        try repo.save()
        rows = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
        #expect(rows[0].summaryText == "我改的")
        #expect(rows[0].sourceType == "user")
        #expect(rows[0].sourceId == "clip-1")

        try repo.softDelete(profileId: "p1", id: id)
        try repo.save()
        try repo.upsertAICandidate(
            profileId: "p1", recordingId: "clip-9",
            summaryText: "复活？", valueJSON: "practice.review.media@1.1.0"
        )
        try repo.save()
        #expect(try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)
    }

    @Test func upsertAICandidateIsolatesProfiles() throws {
        let repo = try makeRepo()
        try repo.upsertAICandidate(
            profileId: "p1", recordingId: "clip-a",
            summaryText: "A 重点", valueJSON: "practice.review.media@1.1.0"
        )
        try repo.upsertAICandidate(
            profileId: "p2", recordingId: "clip-b",
            summaryText: "B 重点", valueJSON: "practice.diagnose.video@1.1.0"
        )
        try repo.save()
        #expect(
            try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
                .map(\.summaryText) == ["A 重点"]
        )
        #expect(
            try repo.fetch(profileId: "p2", scopes: [.ability], matching: "", now: Date())
                .map(\.summaryText) == ["B 重点"]
        )
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MemoryRepositoryTests test
```

Expected: FAIL — `upsertAICandidate` not on the protocol / type.

- [ ] **Step 3: Implement repository methods**

Add to `MemoryRepository` protocol (after `softDeleteTaskGoal`):

```swift
    func upsertAICandidate(
        profileId: String,
        recordingId: String,
        summaryText: String,
        valueJSON: String
    ) throws
```

In `SwiftDataMemoryRepository`, add helpers and the method. Do not `save()` inside them.

```swift
    private static let currentFocusKey = "ability.current_focus"

    private func currentFocusRows(profileId: String) throws -> [MemoryItem] {
        let pid = profileId
        let key = Self.currentFocusKey
        return try context.fetch(
            FetchDescriptor<MemoryItem>(
                predicate: #Predicate { $0.profileId == pid && $0.key == key }
            )
        )
    }

    func upsertAICandidate(
        profileId: String,
        recordingId: String,
        summaryText: String,
        valueJSON: String
    ) throws {
        guard !profileId.isEmpty, !recordingId.isEmpty else { throw StoreError.invalidInput }
        let trimmed = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let summary = trimmed.count <= 120 ? trimmed : String(trimmed.prefix(120))
        let rows = try currentFocusRows(profileId: profileId)
        if rows.contains(where: { $0.deletedAt != nil }) { return }
        if let live = rows.first(where: { $0.deletedAt == nil }) {
            guard live.sourceType == "ai" else { return }
            live.summaryText = summary
            live.sourceId = recordingId
            live.valueJSON = valueJSON
            live.confidence = 0.4
            live.importance = 0.4
            live.updatedAt = Date()
            return
        }
        context.insert(
            MemoryItem(
                profileId: profileId,
                kind: .ability,
                key: Self.currentFocusKey,
                summaryText: summary,
                valueJSON: valueJSON,
                sourceType: "ai",
                sourceId: recordingId,
                confidence: 0.4,
                importance: 0.4
            )
        )
    }
```

Change `updateSummary` so after assigning `summaryText` it also flips `ai`:

```swift
        item.summaryText = summary
        if item.sourceType == "task" || item.sourceType == "ai" {
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
git commit -m "Add AI-candidate upsert that respects user edits and tombstones."
```

---

### Task 2: Skill write policy and AICandidateSync

**Files:**
- Modify: `foxgita/Services/SkillDefinition.swift`
- Modify: `foxgitaTests/SkillRegistryTests.swift`
- Create: `foxgita/Services/AICandidateSync.swift`
- Create: `foxgitaTests/AICandidateSyncTests.swift`

**Interfaces:**
- Consumes: `MemoryRepository.upsertAICandidate` / `save`; `ModelContext` fetch of `LocalProfile`; `MemoryConsentState.enabled`; `SkillDefinition.memoryWritePolicy`
- Produces:
  - `SkillDefinition.reviewMedia.memoryWritePolicy == .candidates`
  - `SkillDefinition.diagnoseVideo.memoryWritePolicy == .candidates`
  - `SkillDefinition.planFromImage.memoryWritePolicy == .deny` (unchanged)
  - versions remain `"1.1.0"`; frozen prompt strings unchanged
  - `@MainActor final class AICandidateSync`
  - `init(repository: MemoryRepository, context: ModelContext)`
  - `private(set) var lastError: StoreError?`
  - `func syncFocus(profileId: String, focus: String, recordingId: String, skill: SkillDefinition)`
  - no-op unless `profileId` non-empty, `skill.memoryWritePolicy == .candidates`, and **that** profile's `consent == .enabled`
  - consent is read by the passed `profileId`, not the active profile
  - methods never throw; on failure set `lastError`; on entry set `lastError = nil`
  - `valueJSON` written as `"\(skill.id)@\(skill.version)"`

- [ ] **Step 1: Write the failing tests**

In `foxgitaTests/SkillRegistryTests.swift`, change only the two policy expects (keep prompt snapshots):

```swift
        #expect(plan?.memoryWritePolicy == .deny)
        #expect(review?.memoryWritePolicy == .candidates)
        #expect(video?.memoryWritePolicy == .candidates)
```

Create `foxgitaTests/AICandidateSyncTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import foxgita

@MainActor
struct AICandidateSyncTests {
    private func make(consent: MemoryConsentState = .enabled) throws -> (
        AICandidateSync, SwiftDataMemoryRepository, ModelContext, LocalProfile
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
        return (AICandidateSync(repository: repo, context: context), repo, context, profile)
    }

    @Test func syncFocusNoopsWhenDisabledOrDenySkill() throws {
        let (offSync, offRepo, _, _) = try make(consent: .disabled)
        offSync.syncFocus(
            profileId: "p1", focus: "压弦", recordingId: "clip-1",
            skill: .reviewMedia
        )
        #expect(try offRepo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)

        let (onSync, onRepo, _, _) = try make(consent: .enabled)
        onSync.syncFocus(
            profileId: "p1", focus: "压弦", recordingId: "clip-1",
            skill: .planFromImage
        )
        #expect(try onRepo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)
        #expect(SkillDefinition.planFromImage.memoryWritePolicy == .deny)
        #expect(onSync.lastError == nil)
    }

    @Test func syncFocusWritesReviewThenOverwritesWithDiagnosis() throws {
        let (sync, repo, _, _) = try make()
        sync.syncFocus(
            profileId: "p1", focus: "  压弦  ", recordingId: "clip-1",
            skill: .reviewMedia
        )
        var rows = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].summaryText == "压弦")
        #expect(rows[0].sourceType == "ai")
        #expect(rows[0].sourceId == "clip-1")
        #expect(rows[0].valueJSON == "practice.review.media@1.1.0")
        #expect(rows[0].confidence == 0.4)
        #expect(sync.lastError == nil)

        sync.syncFocus(
            profileId: "p1", focus: "节奏", recordingId: "clip-2",
            skill: .diagnoseVideo
        )
        rows = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].summaryText == "节奏")
        #expect(rows[0].sourceId == "clip-2")
        #expect(rows[0].valueJSON == "practice.diagnose.video@1.1.0")
    }

    @Test func syncFocusUsesPassedProfileNotActiveOne() throws {
        let (sync, repo, context, _) = try make()
        let p2 = LocalProfile(id: "p2", isActive: false)
        p2.consent = .enabled
        context.insert(p2)
        try context.save()
        sync.syncFocus(
            profileId: "p2", focus: "别人的重点", recordingId: "clip-b",
            skill: .reviewMedia
        )
        #expect(try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)
        #expect(
            try repo.fetch(profileId: "p2", scopes: [.ability], matching: "", now: Date())
                .map(\.summaryText) == ["别人的重点"]
        )
    }

    @Test func syncFocusNoopsEmptyProfileId() throws {
        let (sync, repo, _, _) = try make()
        sync.syncFocus(
            profileId: "", focus: "压弦", recordingId: "clip-1",
            skill: .reviewMedia
        )
        #expect(try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)
        #expect(sync.lastError == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/SkillRegistryTests \
  -only-testing:foxgitaTests/AICandidateSyncTests test
```

Expected: FAIL — policies still `.deny` and/or `AICandidateSync` not found.

- [ ] **Step 3: Implement Skill policy and AICandidateSync**

In `foxgita/Services/SkillDefinition.swift`, change **only** the two `memoryWritePolicy` lines on `reviewMedia` and `diagnoseVideo` from `.deny` to `.candidates`. Do not touch `planFromImage`, versions, or prompt strings.

Create `foxgita/Services/AICandidateSync.swift`:

```swift
import Foundation
import SwiftData

@MainActor
final class AICandidateSync {
    private(set) var lastError: StoreError?

    private let repository: MemoryRepository
    private let context: ModelContext

    init(repository: MemoryRepository, context: ModelContext) {
        self.repository = repository
        self.context = context
    }

    func syncFocus(
        profileId: String,
        focus: String,
        recordingId: String,
        skill: SkillDefinition
    ) {
        lastError = nil
        guard !profileId.isEmpty,
              skill.memoryWritePolicy == .candidates,
              consent(for: profileId) == .enabled
        else { return }
        do {
            try repository.upsertAICandidate(
                profileId: profileId,
                recordingId: recordingId,
                summaryText: focus,
                valueJSON: "\(skill.id)@\(skill.version)"
            )
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

Expected: **TEST SUCCEEDED** for both suites. Confirm `SkillRegistryTests` prompt snapshots still pass.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/SkillDefinition.swift \
  foxgita/Services/AICandidateSync.swift \
  foxgitaTests/SkillRegistryTests.swift \
  foxgitaTests/AICandidateSyncTests.swift
git commit -m "Allow review skills to write a current-focus candidate."
```

---

### Task 3: Wire PracticeStore and App

**Files:**
- Modify: `foxgita/Services/PracticeStore.swift`
- Modify: `foxgita/foxgitaApp.swift`
- Modify: `foxgitaTests/AICandidateSyncTests.swift` (add Store-wired cases here so they share one SwiftData container; do not force `InMemoryPracticeRepository` tests to take a Sync)

**Interfaces:**
- Consumes: `AICandidateSync.syncFocus` / `lastError`; `SkillDefinition.reviewMedia` / `.diagnoseVideo`; `RecordingRef.session?.profileId`
- Produces:
  - `PracticeStore.init(..., taskMemorySync: TaskMemorySync? = nil, aiCandidateSync: AICandidateSync? = nil)`
  - After successful `applyReview` / `applyVideoDiagnosis` (`lastError == nil` after `perform`): if the recording existed and `session.profileId` is non-empty, call `syncFocus`; copy `sync.lastError` onto `PracticeStore.lastError` if non-nil
  - Missing recording / empty `profileId` → skip Sync; review still saved
  - `markReviewsPending` / `markReviewsFailed` do not call Sync
  - `foxgitaApp` builds one `AICandidateSync` from `memoryRepo` + `mainContext` and passes it into `PracticeStore` alongside `taskMemorySync`
  - Existing `PracticeStoreTests` that omit `aiCandidateSync` stay green

- [ ] **Step 1: Write the failing store-wired tests**

Add to `foxgitaTests/AICandidateSyncTests.swift`:

```swift
    private func makeWired(consent: MemoryConsentState = .enabled) throws -> (
        PracticeStore, SwiftDataMemoryRepository, SwiftDataPracticeRepository, LocalProfile
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
        let practiceRepo = SwiftDataPracticeRepository(context: context)
        let defaults = UserDefaults(suiteName: "foxgita.tests.\(UUID().uuidString)")!
        defaults.set(true, forKey: SeedData.seededKey)
        let store = PracticeStore(
            repository: practiceRepo,
            defaults: defaults,
            aiCandidateSync: AICandidateSync(repository: memoryRepo, context: context)
        )
        return (store, memoryRepo, practiceRepo, profile)
    }

    private func addReadyClip(
        store: PracticeStore,
        practiceRepo: SwiftDataPracticeRepository,
        recordingId: String
    ) throws {
        let taskId = store.createCustomTask(name: "练晴天", minutes: 10, category: .chord)!
        let now = Date()
        #expect(store.finishSession(
            taskId: taskId, steps: ["慢练"], note: "笔记",
            startedAt: now, endedAt: now, durationSec: 60, bpm: 80,
            recordings: []
        ))
        let session = try practiceRepo.sessions()[0]
        session.recordings.append(
            RecordingRef(id: recordingId, fileName: "y.m4a", bytes: 2, durationSec: 20)
        )
        try practiceRepo.save()
    }

    @Test func applyReviewWritesCandidateOnlyWhenEnabled() throws {
        let (offStore, offRepo, offPractice, _) = try makeWired(consent: .disabled)
        try addReadyClip(store: offStore, practiceRepo: offPractice, recordingId: "clip-off")
        offStore.applyReview(
            recordingId: "clip-off",
            draft: MediaReviewDraft(highlight: "稳", focus: "压弦", nextAction: "慢练")
        )
        #expect(try offPractice.recording(id: "clip-off")?.reviewStatus == .ready)
        #expect(try offRepo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)

        let (onStore, onRepo, onPractice, _) = try makeWired(consent: .enabled)
        try addReadyClip(store: onStore, practiceRepo: onPractice, recordingId: "clip-on")
        onStore.applyReview(
            recordingId: "clip-on",
            draft: MediaReviewDraft(highlight: "稳", focus: "压弦", nextAction: "慢练")
        )
        let rows = try onRepo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].summaryText == "压弦")
        #expect(rows[0].sourceType == "ai")
        #expect(rows[0].sourceId == "clip-on")
        #expect(rows[0].valueJSON.contains("practice.review.media@1.1.0"))
        #expect(rows[0].confidence == 0.4)
        #expect(rows[0].importance == 0.4)
    }

    @Test func applyVideoDiagnosisOverwritesSameKey() throws {
        let (store, repo, practice, _) = try makeWired()
        try addReadyClip(store: store, practiceRepo: practice, recordingId: "clip-1")
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳", focus: "压弦", nextAction: "慢练")
        )
        store.applyVideoDiagnosis(
            recordingId: "clip-1",
            draft: VideoDiagnosisDraft(
                highlight: "稳", focus: "节奏", nextAction: "70", findings: []
            )
        )
        let rows = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
        #expect(rows.count == 1)
        #expect(rows[0].summaryText == "节奏")
        #expect(rows[0].valueJSON.contains("practice.diagnose.video@1.1.0"))
        #expect(try practice.recording(id: "clip-1")?.reviewStatus == .ready)
    }

    @Test func markReviewsFailedDoesNotWriteCandidate() throws {
        let (store, repo, practice, _) = try makeWired()
        try addReadyClip(store: store, practiceRepo: practice, recordingId: "clip-fail")
        store.markReviewsFailed(recordingIds: ["clip-fail"])
        #expect(try practice.recording(id: "clip-fail")?.reviewStatus == .failed)
        #expect(try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)
    }

    @Test func deletedCandidateDoesNotResurrectOnReview() throws {
        let (store, repo, practice, _) = try makeWired()
        try addReadyClip(store: store, practiceRepo: practice, recordingId: "clip-1")
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳", focus: "压弦", nextAction: "慢练")
        )
        let id = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())[0].id
        try repo.softDelete(profileId: "p1", id: id)
        try repo.save()
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳", focus: "新重点", nextAction: "慢练")
        )
        #expect(try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)
        #expect(try practice.recording(id: "clip-1")?.reviewStatus == .ready)
    }

    @Test func userEditedCandidateIsNotOverwritten() throws {
        let (store, repo, practice, _) = try makeWired()
        try addReadyClip(store: store, practiceRepo: practice, recordingId: "clip-1")
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳", focus: "压弦", nextAction: "慢练")
        )
        let id = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())[0].id
        try repo.updateSummary(profileId: "p1", id: id, summaryText: "用户重点")
        try repo.save()
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳", focus: "新重点", nextAction: "慢练")
        )
        let rows = try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date())
        #expect(rows[0].summaryText == "用户重点")
        #expect(rows[0].sourceType == "user")
    }

    @Test func emptySessionProfileIdSkipsCandidate() throws {
        let (store, repo, practice, _) = try makeWired()
        try addReadyClip(store: store, practiceRepo: practice, recordingId: "clip-1")
        try practice.sessions()[0].profileId = ""
        try practice.save()
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳", focus: "压弦", nextAction: "慢练")
        )
        #expect(try practice.recording(id: "clip-1")?.reviewStatus == .ready)
        #expect(try repo.fetch(profileId: "p1", scopes: [.ability], matching: "", now: Date()).isEmpty)
    }

    @Test func memorySaveFailureDoesNotRollbackReview() throws {
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
        let practiceRepo = SwiftDataPracticeRepository(context: context)
        let defaults = UserDefaults(suiteName: "foxgita.tests.\(UUID().uuidString)")!
        defaults.set(true, forKey: SeedData.seededKey)
        let store = PracticeStore(
            repository: practiceRepo,
            defaults: defaults,
            aiCandidateSync: AICandidateSync(
                repository: SaveFailingMemoryRepository(), context: context
            )
        )
        try addReadyClip(store: store, practiceRepo: practiceRepo, recordingId: "clip-1")
        store.applyReview(
            recordingId: "clip-1",
            draft: MediaReviewDraft(highlight: "稳", focus: "压弦", nextAction: "慢练")
        )
        #expect(try practiceRepo.recording(id: "clip-1")?.reviewStatus == .ready)
        #expect(store.lastError == .saveFailed)
    }
}

@MainActor
private final class SaveFailingMemoryRepository: MemoryRepository {
    func fetch(
        profileId: String, scopes: [MemoryScope], matching query: String, now: Date
    ) throws -> [MemoryItem] { [] }
    func upsertDebug(_ item: MemoryItem) throws {}
    func save() throws { throw StoreError.saveFailed }
    func upsertUser(profileId: String, kind: MemoryScope, summaryText: String) throws -> MemoryItem {
        throw StoreError.invalidInput
    }
    func updateSummary(profileId: String, id: String, summaryText: String) throws {}
    func softDelete(profileId: String, id: String) throws {}
    func softDeleteAll(profileId: String) throws {}
    func setConsent(profileId: String, _ state: MemoryConsentState) throws {}
    func upsertTaskGoal(profileId: String, taskId: String, title: String) throws {}
    func softDeleteTaskGoal(profileId: String, taskId: String) throws {}
    func upsertAICandidate(
        profileId: String, recordingId: String, summaryText: String, valueJSON: String
    ) throws {}
}
```

Move `SaveFailingMemoryRepository` **outside** `AICandidateSyncTests` (file-level private) as shown. Keep `makeWired` / `addReadyClip` inside the test struct.

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/AICandidateSyncTests test
```

Expected: FAIL — `PracticeStore` has no `aiCandidateSync`; wired cases write no candidate.

- [ ] **Step 3: Wire PracticeStore and App**

In `foxgita/Services/PracticeStore.swift`:

Add stored property next to `taskMemorySync`:

```swift
    @ObservationIgnored private let aiCandidateSync: AICandidateSync?
```

Extend `init` (keep `taskMemorySync` default):

```swift
    init(
        repository: PracticeRepository,
        defaults: UserDefaults = .standard,
        taskMemorySync: TaskMemorySync? = nil,
        aiCandidateSync: AICandidateSync? = nil
    ) {
        self.repository = repository
        self.defaults = defaults
        self.taskMemorySync = taskMemorySync
        self.aiCandidateSync = aiCandidateSync
    }
```

Replace `applyReview` and `applyVideoDiagnosis` so Sync runs **after** `perform`, not inside it:

```swift
    func applyReview(recordingId: String, draft: MediaReviewDraft) {
        var pending: (profileId: String, recordingId: String, focus: String)?
        perform {
            if let rec = try repository.recording(id: recordingId) {
                rec.reviewStatus = .ready
                rec.reviewHighlight = draft.highlight
                rec.reviewFocus = draft.focus
                rec.reviewNextAction = draft.nextAction
                rec.videoFindings = []
                rec.updatedAt = Date()
                rec.syncState = .local
                if let profileId = rec.session?.profileId, !profileId.isEmpty {
                    pending = (profileId, recordingId, draft.focus)
                }
            }
            try repository.save()
        }
        if lastError == nil, let pending {
            applyCandidateFocus(
                profileId: pending.profileId,
                focus: pending.focus,
                recordingId: pending.recordingId,
                skill: .reviewMedia
            )
        }
    }

    func applyVideoDiagnosis(recordingId: String, draft: VideoDiagnosisDraft) {
        var pending: (profileId: String, recordingId: String, focus: String)?
        perform {
            if let rec = try repository.recording(id: recordingId) {
                rec.reviewStatus = .ready
                rec.reviewHighlight = draft.highlight
                rec.reviewFocus = draft.focus
                rec.reviewNextAction = draft.nextAction
                rec.videoFindings = draft.findings
                rec.updatedAt = Date()
                rec.syncState = .local
                if let profileId = rec.session?.profileId, !profileId.isEmpty {
                    pending = (profileId, recordingId, draft.focus)
                }
            }
            try repository.save()
        }
        if lastError == nil, let pending {
            applyCandidateFocus(
                profileId: pending.profileId,
                focus: pending.focus,
                recordingId: pending.recordingId,
                skill: .diagnoseVideo
            )
        }
    }

    private func applyCandidateFocus(
        profileId: String,
        focus: String,
        recordingId: String,
        skill: SkillDefinition
    ) {
        guard let sync = aiCandidateSync else { return }
        sync.syncFocus(
            profileId: profileId,
            focus: focus,
            recordingId: recordingId,
            skill: skill
        )
        if let error = sync.lastError { lastError = error }
    }
```

Leave `markReviewsPending` / `markReviewsFailed` unchanged.

In `foxgita/foxgitaApp.swift`, after constructing `taskMemorySync`, construct and inject:

```swift
            let taskMemorySync = TaskMemorySync(
                repository: memoryRepo, context: container.mainContext
            )
            let aiCandidateSync = AICandidateSync(
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
                taskMemorySync: taskMemorySync,
                aiCandidateSync: aiCandidateSync
            )
```

Do **not** inject `AICandidateSync` into `MemoryStore`. Do **not** edit `ReviewJobRunner`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/AICandidateSyncTests \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

Expected: **TEST SUCCEEDED**. Existing `PracticeStoreTests` (nil `aiCandidateSync`) still pass.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeStore.swift \
  foxgita/foxgitaApp.swift \
  foxgitaTests/AICandidateSyncTests.swift
git commit -m "Write current-focus candidates after successful reviews."
```

---

### Task 4: Settings label, injection, and docs

**Files:**
- Modify: `foxgita/Features/Settings/AIMemorySettingsView.swift`
- Modify: `foxgitaTests/MemoryContextTests.swift`
- Modify: `docs/TECHNICAL.md`
- Modify spec status: `docs/superpowers/2026-08-21-ai-candidate-memory/specs/2026-08-21-ai-candidate-memory-design.md` (set **状态** to `Approved — implemented`)

**Interfaces:**
- Consumes: AI-candidate rows from Task 1 (`sourceType == "ai"`, `kind == .ability`, `key == "ability.current_focus"`)
- Produces: settings caption 「AI 观察」; `LiveMemoryContext` user block for `reviewMedia` contains the focus when consent is enabled; system prompt unchanged; TECHNICAL.md describes the candidate write

- [ ] **Step 1: Write the failing injection test**

Add to `foxgitaTests/MemoryContextTests.swift`:

```swift
    @Test func liveIncludesAICandidateAbilityWhenConsentEnabled() async throws {
        let (live, repo, profile) = try makeLive()
        profile.consent = .enabled
        try repo.upsertAICandidate(
            profileId: "p1",
            recordingId: "clip-1",
            summaryText: "压弦要贴品丝",
            valueJSON: "practice.review.media@1.1.0"
        )
        try repo.save()
        let text = await live.block(skill: .reviewMedia, query: "")
        #expect(text.contains("<<<BACKGROUND_MEMORY>>>"))
        #expect(text.contains("压弦要贴品丝"))
        #expect(text.contains("[ability]"))
        #expect(!text.contains("你是吉他练习陪伴教练。根据波形图或练习画面帧给出简短复盘。只返回 JSON，不要 markdown。"))
    }
```

- [ ] **Step 2: Run test to verify it fails or already passes**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MemoryContextTests test
```

Expected: this case should **PASS** once Task 1 exists (`reviewMedia` already reads `.ability`). If it fails, fix only `LiveMemoryContext` if a real regression appeared — do not change prompts. If it passes, keep the test and continue.

- [ ] **Step 3: Settings label and TECHNICAL.md**

In `AIMemorySettingsView.sourceLabel`:

```swift
    private func sourceLabel(_ raw: String) -> String {
        switch raw {
        case "user": return String(localized: "你添加的")
        case "task": return String(localized: "来自练习任务")
        case "ai": return String(localized: "AI 观察")
        case "debug_seed": return String(localized: "调试种子")
        default: return raw
        }
    }
```

Do not change the ability group's `canEdit: false`.

In `docs/TECHNICAL.md`:

1. Directory tree under `Services/`: add `AICandidateSync.swift` with comment `复盘/诊断 focus → ability.current_focus`.
2. In the MemoryItem paragraph that currently says「三个 Skill 的 `memoryWritePolicy` 仍为 `.deny`。正式路径不写 AI 候选记忆。」replace with:

> `practice.plan.from_image` 的 `memoryWritePolicy` 仍为 `.deny`。`practice.review.media` 与 `practice.diagnose.video` 为 `.candidates`。同意 `enabled` 时，`PracticeStore.applyReview` / `applyVideoDiagnosis` 成功后由 `AICandidateSync` 写入全 Profile 一条 ability：`key = ability.current_focus`，`sourceType = ai`，`confidence` / `importance` = `0.4`，`valueJSON = {skill.id}@{skill.version}`。用户改摘要后 `sourceType` 变为 `user`，之后复盘不再覆盖；用户删除或清空后同 key 不复活。记忆写入失败不回滚复盘结果。设计说明：`docs/superpowers/2026-08-21-ai-candidate-memory/specs/2026-08-21-ai-candidate-memory-design.md`。

3. In §6.3.1, the sentence「用户手写记忆走 `MemoryStore`；正式路径不写 AI 候选。」is now inaccurate for review/diagnose. Change that clause to:

> 用户手写记忆走 `MemoryStore`。图片 Skill 仍不写候选；复盘/诊断候选见 `AICandidateSync`（§6.2 MemoryItem）。

4. Spec header **状态** → `Approved — implemented`.

- [ ] **Step 4: Run full unit tests**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

Expected: **TEST SUCCEEDED**. Confirm system prompt snapshots still pass (`SkillRegistryTests` / client tests in the same run).

- [ ] **Step 5: Commit**

```bash
git add foxgita/Features/Settings/AIMemorySettingsView.swift \
  foxgitaTests/MemoryContextTests.swift \
  docs/TECHNICAL.md \
  docs/superpowers/2026-08-21-ai-candidate-memory/specs/2026-08-21-ai-candidate-memory-design.md
git commit -m "Show AI-sourced focus memories and document candidate writes."
```

---

## Self-review

**Spec coverage**

| Spec section | Task |
|---|---|
| §4 fields / §5 upsert + tombstone + user flip / dual profile | 1 |
| §2 Skill policies, §6 AICandidateSync, deny / consent / passed profileId | 2 |
| §7 PracticeStore / App; §8 save-fail, failed reviews, empty profileId | 3 |
| §7 source label, §9 injection, TECHNICAL.md | 4 |
| YAGNI list | Global Constraints; no task implements Spec 6 / X5 |

**Placeholder scan:** none.

**Type names:** `upsertAICandidate(profileId:recordingId:summaryText:valueJSON:)` used in Tasks 1–4. `AICandidateSync.syncFocus(profileId:focus:recordingId:skill:)` used in Tasks 2–3. `PracticeStore.init(..., aiCandidateSync:)` used in Task 3.
