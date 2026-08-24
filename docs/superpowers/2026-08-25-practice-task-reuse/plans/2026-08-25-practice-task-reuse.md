# Practice Task Same-Origin Reuse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Selecting the same template or AI generation origin from「＋」reuses one `TaskItem` (pulled into today) instead of creating a new task each day; soft-deleted origins stay hidden and are never revived.

**Architecture:** Add `TaskItem.originKey` in Schema V8. Stabilize template activations at `active-{templateId}` with `ensureForToday`. AI/photo drafts pass a per-generation `originKey` into `createFromAIDraft`. Merge legacy daily `active-…-dayKey` rows in `prepare()`. Filter deleted template origins out of `RecommendSheet`.

**Tech Stack:** SwiftUI · SwiftData · Swift Testing · existing `PracticeStore` / `PracticeRepository`

## Global Constraints

- Spec: `docs/superpowers/2026-08-25-practice-task-reuse/specs/2026-08-25-practice-task-reuse-design.md`
- Depends on resume-save already on main (do not regress session hydrate / RESET skip)
- iOS 18+ · Scheme `foxgita` · cwd `/Users/haizei/work/AI/program/gita/foxgita`
- Copy: `zh-Hans` via `String(localized:)` only if new user-facing strings appear
- Soft-deleted same-origin: never revive; hide from「＋」
- Today inbox still filters `startedOn == today` via `PracticeTaskRules.isVisibleToday`
- Do not merge old AI tasks by title
- Do not edit `project.pbxproj`
- Do not commit unrelated dirty files (`VideoAnalysisView`, `ReviewJobRunner`, `Localizable`, architecture html/png, media-review deletions, `.superpowers/sdd/*`)
- Unit test command:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/<TestClass> test
```

If `iPhone 17` is missing, use any available iPhone simulator from `xcrun simctl list devices available`.

## File map

| File | Responsibility |
|---|---|
| `foxgita/Models/SchemaV8.swift` | `TaskItem.originKey` + copy of V7 models with the new field |
| `foxgita/Models/Models.swift` | typealiases → V8; `GitaMigrationPlan` V7→V8 lightweight |
| `foxgita/foxgitaApp.swift` | `Schema(versionedSchema: GitaSchemaV8.self)` |
| `foxgita/Services/PracticeTaskOrigin.swift` | stable active id + originKey builders + daily-id parse |
| `foxgita/Services/PracticeStore.swift` | `ensureForToday`, rewrite `activateTemplate` / `createFromAIDraft`, merge in `prepare` |
| `foxgita/Services/PracticeRepository.swift` | `liveTask(originKey:)` on both repos |
| `foxgita/Features/Practice/RecommendSheet.swift` | hide templates whose stable active task is soft-deleted |
| `foxgita/Features/Practice/PhotoPracticeSheet.swift` | generation UUID → `originKey` |
| `foxgita/Features/Practice/NextSessionSheet.swift` | generation UUID → `originKey` on confirm |
| `foxgitaTests/PracticeTaskOriginTests.swift` | id/key helpers |
| `foxgitaTests/PracticeStoreTests.swift` | rewrite activate/AI expectations |
| `foxgitaTests/MigrationTests.swift` | V7→V8 + optional merge coverage via store prepare |
| `docs/TECHNICAL.md` | today / ＋ / template id rows |
| Spec header | Approved + plan path |

YAGNI: no title-dedupe tool; no Record Tab changes; no undo-delete in「＋」.

---

### Task 1: Schema V8 + `originKey`

**Files:**
- Create: `foxgita/Models/SchemaV8.swift` (copy `SchemaV7.swift`, bump version to `(8,0,0)`, add `originKey` on `TaskItem`)
- Modify: `foxgita/Models/Models.swift` (typealiases + migration plan)
- Modify: `foxgita/foxgitaApp.swift` (schema version)
- Test: extend `foxgitaTests/MigrationTests.swift` with one V7→V8 open that preserves a task and reads `originKey == nil`

**Interfaces:**
- Produces: `TaskItem.originKey: String` default `""` or optional `String?` — **use `var originKey: String = ""`** empty meaning nil/absent (matches other defaulted String fields like `profileId`) so lightweight migration stays simple
- Typealiases point at `GitaSchemaV8.*`

- [ ] **Step 1: Write failing migration expectation**

In `MigrationTests.swift`, add a test that after V7→V8, a seeded task’s `originKey` is `""` (empty). Follow existing V6→V7 test structure (temp store URL, load V7, insert task, reopen as V8).

- [ ] **Step 2: Run test — expect fail** (V8 missing)

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/MigrationTests test
```

- [ ] **Step 3: Add SchemaV8**

Copy `SchemaV7.swift` → `SchemaV8.swift`. Change:

```swift
enum GitaSchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }
    // models: same five types
```

On `TaskItem`:

```swift
var originKey: String = ""
```

Add `originKey: String = ""` to `init` and assign `self.originKey = originKey`.

Mirror the same field on any duplicated TaskItem definitions only inside V8 (do not edit V7).

- [ ] **Step 4: Wire app + migration plan**

In `Models.swift`:

```swift
typealias TaskItem = GitaSchemaV8.TaskItem
// … PracticeSession, RecordingRef, LocalProfile, MemoryItem → V8
```

Append `GitaSchemaV8.self` to `GitaMigrationPlan.schemas` and:

```swift
.lightweight(fromVersion: GitaSchemaV7.self, toVersion: GitaSchemaV8.self),
```

In `foxgitaApp.swift`:

```swift
let schema = Schema(versionedSchema: GitaSchemaV8.self)
```

- [ ] **Step 5: Run MigrationTests — PASS**

- [ ] **Step 6: Commit**

```bash
git add foxgita/Models/SchemaV8.swift foxgita/Models/Models.swift \
  foxgita/foxgitaApp.swift foxgitaTests/MigrationTests.swift
git commit -m "$(cat <<'EOF'
Add Schema V8 TaskItem.originKey for same-origin reuse.

EOF
)"
```

---

### Task 2: `PracticeTaskOrigin` + `ensureForToday` + stable `activateTemplate`

**Files:**
- Create: `foxgita/Services/PracticeTaskOrigin.swift`
- Modify: `foxgita/Services/PracticeStore.swift` (`ensureForToday`, rewrite `activateTemplate`; stop resurrecting template tombstones)
- Test: `foxgitaTests/PracticeTaskOriginTests.swift`
- Test: rewrite activate-template tests in `foxgitaTests/PracticeStoreTests.swift`

**Interfaces:**

```swift
enum PracticeTaskOrigin {
    static func stableActiveId(templateId: String) -> String  // "active-\(templateId)"
    static func photoOriginKey(generationId: String) -> String // "ai.photo.\(generationId)"
    static func nextOriginKey(generationId: String) -> String  // "ai.next.\(generationId)"
    /// "active-tpl-chord-2026-08-19" → templateId "tpl-chord", dayKey "2026-08-19"
    static func parseDailyActiveId(_ id: String) -> (templateId: String, dayKey: String)?
}

// PracticeStore
@discardableResult
func ensureForToday(_ taskId: String, now: Date = Date()) -> String?
```

`activateTemplate` must:
1. Resolve template
2. `stableId = PracticeTaskOrigin.stableActiveId(template.id)`
3. If `taskIncludingDeleted(stableId)` has `deletedAt != nil` → return `nil` (do **not** call `ensureActive`)
4. If live `task(stableId)` → `ensureForToday`
5. Else create `TaskItem(id: stableId, …, startedOn: now, isTemplate: false)`
6. Do **not** create `active-…-dayKey` ids anymore

`ensureForToday`:
- Live task only; set `status = .active`, `startedOn = now`, `touch()`, save; return id
- Missing/deleted → `lastError = .notFound`, `nil`

- [ ] **Step 1: Failing helper + store tests**

`PracticeTaskOriginTests.swift`:

```swift
@Test func stableActiveIdAndDailyParse() {
    #expect(PracticeTaskOrigin.stableActiveId(templateId: "tpl-chord") == "active-tpl-chord")
    let parsed = PracticeTaskOrigin.parseDailyActiveId("active-tpl-chord-2026-08-19")
    #expect(parsed?.templateId == "tpl-chord")
    #expect(parsed?.dayKey == "2026-08-19")
    #expect(PracticeTaskOrigin.parseDailyActiveId("active-tpl-chord") == nil)
    #expect(PracticeTaskOrigin.photoOriginKey(generationId: "g1") == "ai.photo.g1")
}
```

Replace / rewrite these `PracticeStoreTests` cases to match the spec (delete expectations that require daily ids or tombstone revive):

| Old test | New expectation |
|---|---|
| `activateTemplateIsIdempotent` | twice → `"active-tpl-chord"` |
| `activateTemplateCreatesNewInstanceNextDay` | **replace** with `activateTemplateReusesAcrossDays` → same id both days; second day `startedOn` is day2 |
| `activateTemplateRestoresSameDayDeletedInstance` | **replace** with `activateTemplateDoesNotReviveDeleted` → softDelete then activate → `nil` |
| `activateTemplateReusesLegacyIdWhenStartedToday` | still OK if legacy `active-tpl-chord` exists → ensureForToday that id |
| `activateTemplateSkipsLegacyIdFromYesterday` | **replace**: yesterday’s stable id still reused (same id), `startedOn` becomes today |
| `activateTemplateCreatesActiveCopy` | id `active-tpl-chord` |

Add:

```swift
@Test func ensureForTodaySetsStartedOn() throws { … }
```

- [ ] **Step 2: Run tests — RED**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeTaskOriginTests \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

- [ ] **Step 3: Implement helpers + store methods**

Create `PracticeTaskOrigin.swift` as in Interfaces.

Implement `ensureForToday` and rewrite `activateTemplate` per above. Keep `ensureActive` for other callers if any; **activateTemplate must not revive tombstones**.

- [ ] **Step 4: GREEN + commit**

```bash
git add foxgita/Services/PracticeTaskOrigin.swift \
  foxgita/Services/PracticeStore.swift \
  foxgitaTests/PracticeTaskOriginTests.swift \
  foxgitaTests/PracticeStoreTests.swift
git commit -m "$(cat <<'EOF'
Reuse a stable active task id across template activations.

EOF
)"
```

---

### Task 3: `createFromAIDraft` + repository origin lookup

**Files:**
- Modify: `foxgita/Services/PracticeRepository.swift` (+ InMemory + SwiftData impls)
- Modify: `foxgita/Services/PracticeStore.swift` (`createFromAIDraft`)
- Test: `foxgitaTests/PracticeStoreTests.swift`

**Interfaces:**

```swift
// PracticeRepository
func liveTask(originKey: String) throws -> TaskItem?
// empty originKey → always return nil

// PracticeStore
@discardableResult
func createFromAIDraft(_ draft: AIPracticeDraft, originKey: String? = nil) -> String?
```

Behavior:
- `let key = originKey?.trimmingCharacters…` ; if empty/nil → always insert new `custom-uuid` with `originKey: ""` (custom handoff unchanged when callers omit key)
- Else if `liveTask(originKey: key)` → update title/subtitle/category/targetMin/steps from draft; `ensureForToday`; return id
- Else insert new `custom-uuid` with `originKey: key`, `startedOn: now`

Do **not** revive soft-deleted rows with the same key (liveTask must filter `deletedAt == nil`).

- [ ] **Step 1: Failing tests**

```swift
@Test func createFromAIDraftReusesSameOriginKey() throws { … }
@Test func createFromAIDraftDifferentOriginKeysStayDistinct() throws { … }
@Test func createFromAIDraftIgnoresDeletedOriginAndCreatesNew() throws { … }
```

- [ ] **Step 2: RED**

- [ ] **Step 3: Implement repo + store**

SwiftData: fetch `#Predicate<TaskItem> { $0.originKey == key && $0.deletedAt == nil }` (bind `key` carefully for `#Predicate`).

InMemory: filter array.

- [ ] **Step 4: GREEN + commit**

```bash
git commit -m "$(cat <<'EOF'
Reuse live AI practice tasks that share an originKey.

EOF
)"
```

---

### Task 4: RecommendSheet hides soft-deleted template origins

**Files:**
- Modify: `foxgita/Features/Practice/RecommendSheet.swift` (`cards` filter)

**Interfaces:**
- Consumes: `PracticeTaskOrigin.stableActiveId`, `@Query` / existing `allTasks` — if sheet only has live tasks Query, also need deleted detection: either inject store lookup `taskIncludingDeleted` via store method, or `@Query` including deleted.

Simplest approach matching existing architecture: add

```swift
// PracticeStore
func isTemplateOriginDeleted(_ templateId: String) -> Bool {
    let id = PracticeTaskOrigin.stableActiveId(templateId: templateId)
    guard let task = try? repository.taskIncludingDeleted(id: id) else { return false }
    return task.deletedAt != nil
}
```

In `RecommendSheet.cards`, when returning templates:

```swift
templates.filter { !store.isTemplateOriginDeleted($0.id) }
```

- [ ] **Step 1: Store unit test**

```swift
@Test func isTemplateOriginDeletedReflectsSoftDelete() throws {
    let id = try #require(store.activateTemplate("tpl-chord", now: now, calendar: cal))
    #expect(store.isTemplateOriginDeleted("tpl-chord") == false)
    store.softDeleteTask(id)
    #expect(store.isTemplateOriginDeleted("tpl-chord") == true)
}
```

- [ ] **Step 2: Wire RecommendSheet filter**

- [ ] **Step 3: Build/test + commit**

```bash
git commit -m "$(cat <<'EOF'
Hide soft-deleted template origins from the recommend sheet.

EOF
)"
```

---

### Task 5: Photo + NextSession pass per-generation `originKey`

**Files:**
- Modify: `foxgita/Features/Practice/PhotoPracticeSheet.swift`
- Modify: `foxgita/Features/Practice/NextSessionSheet.swift`

**Interfaces:**
- Each sheet holds `@State private var generationId = UUID().uuidString` (or regenerate in `prepareGeneration` / when starting next-session generate)
- Call `store.createFromAIDraft(draft, originKey: PracticeTaskOrigin.photoOriginKey(generationId: generationId))` or `.nextOriginKey`

Rules:
- New generate attempt → new `generationId`
- Same attempt’s confirm/retry with same id → same originKey (reuse if live)

- [ ] **Step 1: Wire PhotoPracticeSheet**

In `prepareGeneration()` set `generationId = UUID().uuidString`.  
In `generate` success path pass photo originKey.

- [ ] **Step 2: Wire NextSessionSheet**

When starting generation, set `generationId`.  
In `confirm()` pass `PracticeTaskOrigin.nextOriginKey(generationId:)`.

- [ ] **Step 3: Compile (PracticeStoreTests still green) + commit**

```bash
git commit -m "$(cat <<'EOF'
Tag AI drafts with a per-generation originKey.

EOF
)"
```

---

### Task 6: Merge legacy daily active tasks in `prepare()`

**Files:**
- Create: `foxgita/Services/PracticeActiveTaskMerge.swift` (pure merge planner + apply via store/repo)
- Modify: `foxgita/Services/PracticeStore.swift` (`prepare` calls merge once)
- Test: `foxgitaTests/PracticeActiveTaskMergeTests.swift` (+ store integration test)

**Interfaces:**

```swift
enum PracticeActiveTaskMerge {
    struct Plan: Equatable {
        var canonicalId: String              // active-{templateId}
        var sourceTaskIds: [String]          // daily ids to fold
        var softDeleteTaskIds: [String]
        var reassignSessionTaskIds: [String] // sessions currently pointing at sources
    }

    /// Pure: given task id/deletedAt/updatedAt + session counts per taskId
    static func plans(
        tasks: [(id: String, deletedAt: Date?, updatedAt: Date)],
        effectiveSessionCount: [String: Int]
    ) -> [Plan]
}
```

Algorithm per `templateId` from `parseDailyActiveId`:
1. Collect daily rows for that template (any deletedAt).
2. Prefer existing live `active-{templateId}` as canonical if present and not deleted.
3. Else among **non-deleted** dailies, pick max `effectiveSessionCount`, tie-break `updatedAt`.
4. If canonical missing as a row, plan will create it by renaming/re-id… **SwiftData unique id is immutable** — implement apply as:
   - If live stable id exists: reassign sessions from other live dailies → stable; softDelete other live dailies.
   - If no live stable id: pick winner daily; **create** new TaskItem cloning winner fields with stable id; reassign winner+siblings’ sessions; softDelete dailies.
   - Soft-deleted dailies: only reassign sessions if stable is live; never undelete dailies.

Gate with UserDefaults key `gita.practice.mergedActiveTasks.v1` so it runs once (like seed).

Call from `prepare()` after `seedIfNeeded` / `ensureProfile`.

- [ ] **Step 1: Pure planner tests** (multiple dailies → one plan; tombstone-only → no revive create)

- [ ] **Step 2: Implement planner + store apply + prepare hook**

- [ ] **Step 3: Integration test**: seed two daily actives + sessions → prepare → one stable id, sessions retargeted

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
Merge legacy per-day active template tasks onto stable ids.

EOF
)"
```

---

### Task 7: Docs + spec header

**Files:**
- Modify: `docs/TECHNICAL.md` (§4.1.1 today list / ＋ / template activation)
- Modify: spec header → Approved + plan path

- [ ] **Step 1: Update TECHNICAL**

Document:
- Template activation id `active-{templateId}`; cross-day reuse via `startedOn`
- AI `originKey`; soft-deleted origins hidden from recommend
- Merge of legacy daily ids on launch

- [ ] **Step 2: Flip spec status**

```markdown
**状态：** Approved — implementation plan in ../plans/2026-08-25-practice-task-reuse.md
```

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
Document same-origin practice task reuse in TECHNICAL.

EOF
)"
```

---

### Task 8: Manual acceptance (no code)

- [ ] **Step 1: Run spec §9.2 on simulator**

1. Template A → practice → next day「＋」A → same task, resumable session  
2. Delete A → hidden in「＋」; past day toast  
3. Photo generate twice same generation path reuses; new generation after delete creates new  
4. Two custom names → two tasks  
5. Past day view undeleted → same id  

- [ ] **Step 2: Note failures without weakening the spec**

---

## Plan self-review

| Spec requirement | Task |
|---|---|
| Stable template id + ensureForToday | Task 2 |
| originKey on TaskItem | Task 1 |
| createFromAIDraft reuse | Task 3 |
| Hide deleted templates in「＋」 | Task 4 |
| Per-generation keys from Photo/Next | Task 5 |
| Migrate daily actives | Task 6 |
| No revive soft-delete | Tasks 2–4 |
| Today filter unchanged | Global + Task 2 |
| Docs | Task 7 |
| Manual | Task 8 |
| Resume-save untouched | Global constraint |

No TBD placeholders. `originKey` stored as empty String for absent. Activate/AI/Recommend signatures consistent across tasks.
