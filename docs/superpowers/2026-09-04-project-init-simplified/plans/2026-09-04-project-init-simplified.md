# Project Init Simplified Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users create a project with only a name, land on project detail (no Ready page), and optionally create+link from a finished practice.

**Architecture:** Keep SwiftData V12. Slim `ProjectEditorView` to name + folded goal. Add `ProjectCreateFromPracticeView` for path B. Delete `ProjectReadyView`. Create success always `replace`s to `projectDetail`. Store create writes empty kind/stage/focus; edit basics must not wipe stage.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing (`@Test` / `#expect`), `foxgita` scheme. Nested git repo at `/Users/haizei/work/AI/program/gita/foxgita` (gitignored by the docs repo). All implementation commits happen in that nested repo.

## Global Constraints

- Spec: `foxgita/docs/superpowers/2026-09-04-project-init-simplified/specs/2026-09-04-project-init-simplified-design.md`
- Figma copy wins: node `733:2`
- Do not migrate Schema or rename `goal` to `completionCriteria`
- UI label for `goal` is `完成标准`
- Do not edit `project.pbxproj` (synchronized group picks up new Swift files)
- Do not upload project name, goal, practice title, or notes in analytics
- Type, currentFocus, and cover stay P1 — no create/edit/detail UI this round except stage + goal on detail
- Run tests from nested repo: `cd /Users/haizei/work/AI/program/gita/foxgita`
- Test command: `xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/<TestFile>`
- If the simulator name differs, substitute an available iPhone simulator; do not skip tests

## File structure

- Modify: `foxgita/Features/Record/ProjectSetupRules.swift` — goal optional; dirty = name + goal
- Modify: `foxgita/foxgitaTests/ProjectSetupRulesTests.swift`
- Modify: `foxgita/Services/PracticeStore.swift` — `createProject(name:goal:now:)`, `updateProjectBasics`, `updateProjectGoal`, `updateProjectStage`
- Modify: `foxgita/foxgitaTests/PracticeStoreTests.swift`
- Modify: `foxgita/App/AppRouter.swift` — drop Ready / `fromEmpty` / pending join; add from-practice route + `lastCompletedPracticeItemId`
- Modify: `foxgita/foxgitaTests/AppRouterTests.swift`
- Modify: `foxgita/Features/Record/RecordAnalytics.swift`
- Modify: `foxgita/foxgitaTests/RecordAnalyticsTests.swift`
- Modify: `foxgita/Features/Record/ProjectEditorView.swift` — slim create/edit
- Modify: `foxgita/Features/Record/RecordView.swift` — empty copy, routing
- Delete: `foxgita/Features/Record/ProjectReadyView.swift`
- Create: `foxgita/Features/Record/ProjectCreateFromPracticeView.swift`
- Modify: `foxgita/Features/Record/ProjectDetailView.swift` — empty first-practice; goal/stage sheets
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift` — 建立长期项目; write completed item id
- Modify: `foxgita/Features/Practice/JustCompletedCard.swift`
- Modify: `foxgita/Features/Practice/PracticeView.swift` — mount completed card

---

### Task 1: Setup rules — name required, goal optional

**Files:**
- Modify: `foxgita/Features/Record/ProjectSetupRules.swift`
- Test: `foxgita/foxgitaTests/ProjectSetupRulesTests.swift`

**Interfaces:**
- Consumes: existing `ProjectSetupRules` / `ProjectSetupError`
- Produces: `ProjectSetupFields(name:goal:)`; `prepare(name:goal:)`; `isCreateDirty(name:goal:)`; `isEditDirty(name:goal:loadedName:loadedGoal:)`; `isFromPracticeDirty(name:initialName:)`; `hasGoal(_:)`; no `goalEmpty`

- [ ] **Step 1: Rewrite the failing tests**

Replace `ProjectSetupFields` usage and the prepare/dirty tests in `ProjectSetupRulesTests.swift` with:

```swift
@Test func prepareAcceptsNameOnly() throws {
    let fields = try ProjectSetupRules.prepare(name: " 知足 ", goal: "  ").get()
    #expect(fields.name == "知足")
    #expect(fields.goal == "")
}

@Test func prepareKeepsTrimmedGoal() throws {
    let fields = try ProjectSetupRules.prepare(name: "知足", goal: " 完整弹唱 ").get()
    #expect(fields.goal == "完整弹唱")
}

@Test func prepareRejectsBlankAndOverlong() {
    #expect(ProjectSetupRules.prepare(name: "  ", goal: "目标") == .failure(.nameEmpty))
    #expect(
        ProjectSetupRules.prepare(name: String(repeating: "啊", count: 41), goal: "")
            == .failure(.nameTooLong)
    )
    #expect(
        ProjectSetupRules.prepare(name: "知足", goal: String(repeating: "啊", count: 121))
            == .failure(.goalTooLong)
    )
}

@Test func errorFieldAndReason() {
    #expect(ProjectSetupError.nameEmpty.fieldName == "name")
    #expect(ProjectSetupError.nameEmpty.reason == "empty")
    #expect(ProjectSetupError.goalTooLong.fieldName == "goal")
    #expect(ProjectSetupError.goalTooLong.reason == "too_long")
}

@Test func createDirtyOnlyNameAndGoal() {
    #expect(ProjectSetupRules.isCreateDirty(name: "", goal: "") == false)
    #expect(ProjectSetupRules.isCreateDirty(name: "  ", goal: "") == false)
    #expect(ProjectSetupRules.isCreateDirty(name: "知足", goal: "") == true)
    #expect(ProjectSetupRules.isCreateDirty(name: "", goal: "完整弹唱") == true)
}

@Test func editDirtyComparesTrimmedLoaded() {
    #expect(
        ProjectSetupRules.isEditDirty(
            name: "知足", goal: "完整弹唱",
            loadedName: "知足", loadedGoal: "完整弹唱"
        ) == false
    )
    #expect(
        ProjectSetupRules.isEditDirty(
            name: "知足 ", goal: "完整弹唱",
            loadedName: "知足", loadedGoal: ""
        ) == true
    )
}

@Test func fromPracticeDirtyIgnoresUnchangedPrefill() {
    #expect(ProjectSetupRules.isFromPracticeDirty(name: "《知足》主歌", initialName: "《知足》主歌") == false)
    #expect(ProjectSetupRules.isFromPracticeDirty(name: "学会《知足》", initialName: "《知足》主歌") == true)
    #expect(ProjectSetupRules.isFromPracticeDirty(name: "  ", initialName: "《知足》主歌") == true)
}

@Test func hasGoal() {
    #expect(ProjectSetupRules.hasGoal("") == false)
    #expect(ProjectSetupRules.hasGoal("  ") == false)
    #expect(ProjectSetupRules.hasGoal("完整弹唱") == true)
}
```

Delete tests that still pass `currentFocus` / `kind` / `stage` into dirty helpers, and delete `prepareRejectsBlankAndOverlong` cases for `goalEmpty` / `focusTooLong`. Keep `knownKindAndStage` and `readyStageHiddenWhenBlank`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/ProjectSetupRulesTests`

Expected: FAIL compiling (`prepare` still has `currentFocus`, `goalEmpty` still exists, new helpers missing).

- [ ] **Step 3: Implement rules**

Replace `foxgita/Features/Record/ProjectSetupRules.swift` with:

```swift
import Foundation

struct ProjectSetupFields: Equatable {
    var name: String
    var goal: String
}

enum ProjectSetupError: Error, Equatable {
    case nameEmpty, nameTooLong, goalTooLong

    var fieldName: String {
        switch self {
        case .nameEmpty, .nameTooLong: return "name"
        case .goalTooLong: return "goal"
        }
    }

    var reason: String {
        switch self {
        case .nameEmpty: return "empty"
        case .nameTooLong, .goalTooLong: return "too_long"
        }
    }
}

enum ProjectSetupRules {
    static let nameMax = 40
    static let goalMax = 120
    static let focusMax = 120

    static func trimmed(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clamp(_ raw: String, max: Int) -> String {
        String(raw.prefix(max))
    }

    static func hasGoal(_ raw: String) -> Bool {
        !trimmed(raw).isEmpty
    }

    static func hasFocus(_ raw: String) -> Bool {
        !trimmed(raw).isEmpty
    }

    static let kinds = ["歌曲", "技巧", "演出准备"]
    static let stages = ["熟悉内容", "分段练习", "串联整首", "稳定演奏", "完成"]

    static func isKnownKind(_ raw: String) -> Bool {
        kinds.contains(trimmed(raw))
    }

    static func isKnownStage(_ raw: String) -> Bool {
        stages.contains(trimmed(raw))
    }

    static func showsReadyStage(_ raw: String) -> Bool {
        !trimmed(raw).isEmpty
    }

    static func isCreateDirty(name: String, goal: String) -> Bool {
        !trimmed(name).isEmpty || !trimmed(goal).isEmpty
    }

    static func isEditDirty(
        name: String,
        goal: String,
        loadedName: String,
        loadedGoal: String
    ) -> Bool {
        trimmed(name) != trimmed(loadedName) || trimmed(goal) != trimmed(loadedGoal)
    }

    static func isFromPracticeDirty(name: String, initialName: String) -> Bool {
        trimmed(name) != trimmed(initialName)
    }

    static func prepare(name: String, goal: String) -> Result<ProjectSetupFields, ProjectSetupError> {
        let name = trimmed(name)
        let goal = trimmed(goal)
        if name.isEmpty { return .failure(.nameEmpty) }
        if name.count > nameMax { return .failure(.nameTooLong) }
        if goal.count > goalMax { return .failure(.goalTooLong) }
        return .success(ProjectSetupFields(name: name, goal: goal))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same `xcodebuild` as Step 2.

Expected: `ProjectSetupRulesTests` PASS. Other test files may still fail to compile (`prepare(currentFocus:)`, `goalEmpty`). Do not fix those until Task 2.

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Features/Record/ProjectSetupRules.swift foxgitaTests/ProjectSetupRulesTests.swift
git commit -m "Make project setup require only a name."
```

---

### Task 2: Store create/update without wiping stage

**Files:**
- Modify: `foxgita/Services/PracticeStore.swift`
- Modify: `foxgita/foxgitaTests/PracticeStoreTests.swift`
- Modify: every remaining `createProject(` / `ProjectSetupRules.prepare(` / `.goalEmpty` call site so the module compiles

**Interfaces:**
- Consumes: `ProjectSetupRules.prepare(name:goal:)`
- Produces:
  - `func createProject(name: String, goal: String, now: Date) throws -> Project` (kind/stage/focus stored as `""`)
  - `func updateProjectBasics(id: UUID, name: String, goal: String, now: Date) throws`
  - `func updateProjectGoal(id: UUID, goal: String, now: Date) throws`
  - `func updateProjectStage(id: UUID, stageRaw: String, now: Date) throws`
  - Keep `updateProject(id:name:goal:kindRaw:stageRaw:currentFocus:now:)` for tests that still need a full write

- [ ] **Step 1: Add store tests**

In `PracticeStoreTests.swift` replace `createProjectRejectsBlankNameAndGoal` and `createProjectRejectsOverlongFieldsAndTrimsFocus` with:

```swift
@Test func createProjectAcceptsNameOnlyAndWritesEmptyExtras() throws {
    let (store, repo, _) = makeStore()
    store.prepare()
    #expect(throws: StoreError.invalidInput) {
        try store.createProject(name: "  ", goal: "目标", now: Date())
    }
    let project = try store.createProject(name: " 知足 ", goal: "  ", now: Date())
    #expect(project.name == "知足")
    #expect(project.goal == "")
    #expect(project.kindRaw == "")
    #expect(project.stageRaw == "")
    #expect(project.currentFocus == "")
    let profileId = UUID(uuidString: try #require(repo.activeProfile()?.id))!
    #expect(try repo.practiceItems(profileId: profileId).isEmpty)
}

@Test func createProjectRejectsOverlongGoal() throws {
    let (store, _, _) = makeStore()
    store.prepare()
    #expect(throws: StoreError.invalidInput) {
        try store.createProject(name: String(repeating: "啊", count: 41), goal: "", now: Date())
    }
    #expect(throws: StoreError.invalidInput) {
        try store.createProject(
            name: "知足",
            goal: String(repeating: "啊", count: 121),
            now: Date()
        )
    }
}

@Test func updateProjectBasicsDoesNotClearStage() throws {
    let (store, repo, _) = makeStore()
    store.prepare()
    let created = try store.createProject(name: "知足", goal: "", now: Date())
    try store.updateProject(
        id: created.id,
        name: "知足",
        goal: "目标",
        kindRaw: "歌曲",
        stageRaw: "串联整首",
        currentFocus: "副歌",
        now: Date()
    )
    try store.updateProjectBasics(id: created.id, name: "学会知足", goal: "完整弹唱", now: Date())
    let profileId = UUID(uuidString: try #require(repo.activeProfile()?.id))!
    let live = try #require(try repo.project(id: created.id, profileId: profileId))
    #expect(live.name == "学会知足")
    #expect(live.goal == "完整弹唱")
    #expect(live.kindRaw == "歌曲")
    #expect(live.stageRaw == "串联整首")
    #expect(live.currentFocus == "副歌")
}

@Test func updateProjectGoalAndStage() throws {
    let (store, repo, _) = makeStore()
    store.prepare()
    let created = try store.createProject(name: "知足", goal: "", now: Date())
    try store.updateProjectGoal(id: created.id, goal: " 完整弹唱 ", now: Date())
    try store.updateProjectStage(id: created.id, stageRaw: "串联整首", now: Date())
    let profileId = UUID(uuidString: try #require(repo.activeProfile()?.id))!
    let live = try #require(try repo.project(id: created.id, profileId: profileId))
    #expect(live.goal == "完整弹唱")
    #expect(live.stageRaw == "串联整首")
    try store.updateProjectStage(id: created.id, stageRaw: "  ", now: Date())
    let cleared = try #require(try repo.project(id: created.id, profileId: profileId))
    #expect(cleared.stageRaw == "")
}

@Test func createThenLinkDoesNotCopyPracticeFields() throws {
    let (store, repo, _) = makeStore()
    store.prepare()
    let cal = shanghai()
    let now = date(2026, 8, 28, calendar: cal)
    let item = try store.createPracticeItem(
        input: PracticeItemInput(
            title: "《知足》主歌进入副歌",
            category: .song,
            source: .custom,
            originId: nil,
            bpm: nil,
            timeSignature: nil
        ),
        now: now,
        calendar: cal
    )
    try store.savePracticeItem(id: item.id, durationSeconds: 720, note: "稳", now: now)
    let project = try store.createProject(name: item.title, goal: "", now: now)
    try store.setPracticeItemProject(id: item.id, projectId: project.id, now: now)
    let profileId = UUID(uuidString: try #require(repo.activeProfile()?.id))!
    let live = try #require(try repo.practiceItem(id: item.id, profileId: profileId))
    #expect(live.projectId == project.id)
    #expect(live.practiceDayKey == "2026-08-28")
    #expect(live.durationSeconds == 720)
    #expect(live.note == "稳")
    #expect(try repo.practiceItems(profileId: profileId).count == 1)
}

@Test func emptyOnlyCreateLeavesPracticeUnlinked() throws {
    let (store, repo, _) = makeStore()
    store.prepare()
    let cal = shanghai()
    let now = date(2026, 8, 28, calendar: cal)
    let item = try store.createPracticeItem(
        input: PracticeItemInput(
            title: "《知足》主歌进入副歌",
            category: .song,
            source: .custom,
            originId: nil,
            bpm: nil,
            timeSignature: nil
        ),
        now: now,
        calendar: cal
    )
    _ = try store.createProject(name: "空项目", goal: "", now: now)
    let profileId = UUID(uuidString: try #require(repo.activeProfile()?.id))!
    #expect(try repo.practiceItem(id: item.id, profileId: profileId)?.projectId == nil)
}
```

Keep `updateProjectClearsKindStageAndTrimsFocus` but change its `createProject` call to `createProject(name:goal:now:)` then `updateProject(...)` to seed kind/stage/focus before clearing.

- [ ] **Step 2: Run the new tests — expect compile/fail**

Run: `xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/PracticeStoreTests`

Expected: FAIL (`createProject` still has old arity; new methods missing).

- [ ] **Step 3: Change `createProject` and add the three updates**

In `PracticeStore.swift` replace `createProject` with:

```swift
func createProject(name: String, goal: String, now: Date) throws -> Project {
    let prepared: ProjectSetupFields
    switch ProjectSetupRules.prepare(name: name, goal: goal) {
    case .success(let fields):
        prepared = fields
    case .failure:
        lastError = .invalidInput
        throw StoreError.invalidInput
    }
    let profileId = try requireProfileUUID()
    let project = Project(
        profileId: profileId,
        name: prepared.name,
        goal: prepared.goal,
        kindRaw: "",
        stageRaw: "",
        currentFocus: "",
        statusRaw: ProjectStatus.active.rawValue,
        createdAt: now,
        updatedAt: now
    )
    do {
        try repository.insertProject(project)
        try persistPracticeItemChanges()
        return project
    } catch {
        repository.rollback()
        lastError = StoreError.from(error)
        throw lastError ?? .saveFailed
    }
}
```

Change `updateProject` to call `ProjectSetupRules.prepare(name:goal:)` and assign `currentFocus` from the argument trimmed with `ProjectSetupRules.trimmed` (no focus length check on this full writer; tests still pass a short focus).

Add after `updateProject`:

```swift
func updateProjectBasics(id: UUID, name: String, goal: String, now: Date) throws {
    let prepared: ProjectSetupFields
    switch ProjectSetupRules.prepare(name: name, goal: goal) {
    case .success(let fields):
        prepared = fields
    case .failure:
        lastError = .invalidInput
        throw StoreError.invalidInput
    }
    let project = try requireLiveProject(id: id)
    project.name = prepared.name
    project.goal = prepared.goal
    project.updatedAt = now
    try persistPracticeItemChanges()
}

func updateProjectGoal(id: UUID, goal: String, now: Date) throws {
    let trimmed = ProjectSetupRules.trimmed(goal)
    if trimmed.count > ProjectSetupRules.goalMax {
        lastError = .invalidInput
        throw StoreError.invalidInput
    }
    let project = try requireLiveProject(id: id)
    project.goal = trimmed
    project.updatedAt = now
    try persistPracticeItemChanges()
}

func updateProjectStage(id: UUID, stageRaw: String, now: Date) throws {
    let project = try requireLiveProject(id: id)
    project.stageRaw = ProjectSetupRules.trimmed(stageRaw)
    project.updatedAt = now
    try persistPracticeItemChanges()
}
```

Then mechanically update every remaining Swift call:

```bash
rg -n "createProject\(|prepare\(name:.*currentFocus|\.goalEmpty|fromEmpty:" foxgita foxgitaTests --glob '*.swift'
```

For each `createProject(name:goal:kindRaw:stageRaw:currentFocus:now:)` drop the three extra arguments. For `ProjectEditorView` leave a compile error until Task 5 (you may temporarily pass `createProject(name: fields.name, goal: fields.goal, now: Date())` and `updateProjectBasics` so the target builds).

- [ ] **Step 4: Run store tests**

Run the Step 2 command.

Expected: `PracticeStoreTests` PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Services/PracticeStore.swift foxgitaTests/PracticeStoreTests.swift
git add -u foxgita foxgitaTests
git commit -m "Allow name-only project create without clearing stage."
```

Do not commit unrelated dirty files.

---

### Task 3: Router — drop Ready, add from-practice

**Files:**
- Modify: `foxgita/App/AppRouter.swift`
- Modify: `foxgita/Features/Record/RecordView.swift` (`RecordProjectCreateStart` only if needed for tests)
- Test: `foxgita/foxgitaTests/AppRouterTests.swift`

**Interfaces:**
- Consumes: existing `replaceLastRecordRoute`
- Produces:
  - `RecordRoute.projectCreate`
  - `RecordRoute.projectCreateFromPractice(itemId: UUID)`
  - no `projectReady`, no `fromEmpty`, no `pendingJoinPracticeItemId`
  - `var lastCompletedPracticeItemId: UUID?`
  - `func presentCreatedProject(_ projectId: UUID, fromPracticeTab: Bool)`
  - `RecordProjectCreateStart.shouldPush` returns false for `.projectCreate` and `.projectCreateFromPractice`

- [ ] **Step 1: Rewrite router tests**

In `AppRouterTests.swift`:

Replace `clearJustCompletedDropsSessionId` with:

```swift
@Test func clearJustCompletedDropsPracticeItemId() {
    let router = AppRouter()
    router.lastCompletedPracticeItemId = UUID()
    router.clearJustCompleted()
    #expect(router.lastCompletedPracticeItemId == nil)
}
```

Replace `recordRouteCarriesProjectPages` through `replaceReadyWithPracticeDetailLeavesListUnderneath` with:

```swift
@Test func recordRouteCarriesProjectPages() {
    let id = UUID()
    let itemId = UUID()
    #expect(RecordRoute.projectCreate == .projectCreate)
    #expect(RecordRoute.projectCreateFromPractice(itemId: itemId) == .projectCreateFromPractice(itemId: itemId))
    var path: [RecordRoute] = [
        .projectCreate,
        .projectDetail(projectId: id),
        .projectEdit(projectId: id),
    ]
    path.append(.practiceDetail(itemId: id))
    #expect(path.last == .practiceDetail(itemId: id))
    path.append(.projectTrajectory(projectId: id))
    #expect(path.last == .projectTrajectory(projectId: id))
}

@Test func projectCreateStartIgnoresWhenAlreadyOnCreate() {
    #expect(RecordProjectCreateStart.shouldPush(onto: nil))
    #expect(RecordProjectCreateStart.shouldPush(onto: .projectDetail(projectId: UUID())))
    #expect(RecordProjectCreateStart.shouldPush(onto: .projectCreate) == false)
    #expect(RecordProjectCreateStart.shouldPush(onto: .projectCreateFromPractice(itemId: UUID())) == false)
}

@Test func replaceLastRecordRouteReplacesTop() {
    let router = AppRouter()
    let id = UUID()
    router.recordPath = [.projectCreate]
    router.replaceLastRecordRoute(.projectDetail(projectId: id))
    #expect(router.recordPath == [.projectDetail(projectId: id)])
}

@Test func presentCreatedProjectReplacesCreateOnRecordStack() {
    let router = AppRouter()
    let id = UUID()
    router.recordPath = [.projectCreate]
    router.presentCreatedProject(id, fromPracticeTab: false)
    #expect(router.selectedTab == .practice || router.selectedTab == .record)
    #expect(router.recordSegment == .project)
    #expect(router.recordPath == [.projectDetail(projectId: id)])
}

@Test func presentCreatedProjectFromPracticeTabSwitchesTab() {
    let router = AppRouter()
    let id = UUID()
    let itemId = UUID()
    router.selectedTab = .practice
    router.practicePath = [.detail(itemId: itemId)]
    router.presentCreatedProject(id, fromPracticeTab: true)
    #expect(router.selectedTab == .record)
    #expect(router.recordSegment == .project)
    #expect(router.recordPath == [.projectDetail(projectId: id)])
    #expect(router.practicePath.isEmpty)
}
```

Fix `presentCreatedProjectReplacesCreateOnRecordStack`: after `fromPracticeTab: false`, `selectedTab` must stay whatever it was (default `.practice`). Assert `recordSegment == .project` and path only.

- [ ] **Step 2: Run tests — expect fail**

Run: `xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/AppRouterTests`

Expected: FAIL (old route cases).

- [ ] **Step 3: Update router**

In `AppRouter.swift` replace `RecordRoute` and the just-completed / pending join fields:

```swift
enum RecordRoute: Hashable {
    case history(RecordHistorySegment)
    case practiceDetail(itemId: UUID)
    case projectCreate
    case projectCreateFromPractice(itemId: UUID)
    case projectDetail(projectId: UUID)
    case projectEdit(projectId: UUID)
    case projectTrajectory(projectId: UUID)
}
```

Remove `pendingJoinPracticeItemId`.

Replace `lastCompletedSessionId` with:

```swift
    /// Set only after an effective Complete. Never persist.
    var lastCompletedPracticeItemId: UUID?

    func clearJustCompleted() {
        lastCompletedPracticeItemId = nil
    }

    func presentCreatedProject(_ projectId: UUID, fromPracticeTab: Bool) {
        recordSegment = .project
        if fromPracticeTab {
            selectedTab = .record
            practicePath.removeAll()
            recordPath = [.projectDetail(projectId: projectId)]
        } else {
            replaceLastRecordRoute(.projectDetail(projectId: projectId))
        }
    }
```

In `RecordView.swift` `RecordProjectCreateStart`:

```swift
enum RecordProjectCreateStart {
    static func shouldPush(onto last: RecordRoute?) -> Bool {
        switch last {
        case .projectCreate, .projectCreateFromPractice:
            return false
        default:
            return true
        }
    }
}
```

Temporarily fix compile in `RecordView` / `ProjectEditorView` / `PracticeDetailView` / `ProjectReadyView` by mapping:
- `.projectCreate(fromEmpty:)` → `.projectCreate`
- `.projectReady` → `.projectDetail` (so Ready can be deleted in Task 5)
- `pendingJoinPracticeItemId` reads → compile stubs removed in later tasks

Minimum compile stubs for this task: change every `.projectCreate(fromEmpty: _)` to `.projectCreate`, delete `.projectReady` switch arm by routing it to `ProjectDetailView`, delete `fromEmpty:` argument at call sites (keep the property unused until Task 5), and stop assigning `pendingJoinPracticeItemId` (PracticeDetail will be rewired in Task 7; for this task push `.projectCreateFromPractice(itemId: itemId)` instead of pending join).

- [ ] **Step 4: Run AppRouterTests**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/App/AppRouter.swift foxgita/Features/Record/RecordView.swift foxgitaTests/AppRouterTests.swift
git add -u foxgita foxgitaTests
git commit -m "Route project create to detail instead of Ready."
```

---

### Task 4: Analytics keys

**Files:**
- Modify: `foxgita/Features/Record/RecordAnalytics.swift`
- Test: `foxgita/foxgitaTests/RecordAnalyticsTests.swift`

**Interfaces:**
- Produces (exact names):
  - `projectCreateEntryViewed(source:)`
  - `projectCreateStarted(source:)`
  - `projectGoalExpanded(source:)`
  - `projectCreateSubmitted(source:hasGoal:)`
  - `projectCreated(source:hasGoal:durationMs:)`
  - `projectCreatedFromPractice(linkResult:hadPreviousProject:)`
  - `projectCreateFailed(source:errorCode:)`
  - `projectSetupAbandoned(source:durationMs:)`
  - `projectSetupValidationFailed(fieldName:reason:)` (keep)
  - `projectDetailFirstPracticeClicked(projectId:)`
- Delete: `fromEmpty` / `hasFocus` create params, `projectReadyViewed`, `projectReadyActionClicked`
- Keep `projectFirstPracticeCreated` and `projectEmptyViewed`

- [ ] **Step 1: Rewrite `projectInitEventsMatchSpecKeys`**

```swift
@Test func projectInitEventsMatchSpecKeys() {
    var captured: [(String, [String: String])] = []
    RecordAnalytics.sink = { captured.append(($0, $1)) }
    defer { RecordAnalytics.sink = nil }
    RecordAnalytics.projectEmptyViewed(source: "segment")
    RecordAnalytics.projectCreateEntryViewed(source: "projects_empty")
    RecordAnalytics.projectCreateStarted(source: "projects_empty")
    RecordAnalytics.projectGoalExpanded(source: "projects_empty")
    RecordAnalytics.projectCreateSubmitted(source: "projects_empty", hasGoal: false)
    RecordAnalytics.projectCreated(source: "projects_empty", hasGoal: true, durationMs: 1200)
    RecordAnalytics.projectCreatedFromPractice(linkResult: "linked", hadPreviousProject: false)
    RecordAnalytics.projectCreateFailed(source: "practice_detail", errorCode: "save_failed")
    RecordAnalytics.projectSetupAbandoned(source: "projects_list", durationMs: 800)
    RecordAnalytics.projectDetailFirstPracticeClicked(projectId: "p1")
    RecordAnalytics.projectFirstPracticeCreated(
        projectId: "p1",
        practiceItemId: "i1",
        elapsedFromProjectCreation: 400
    )
    #expect(captured.map(\.0) == [
        "project_empty_viewed",
        "project_create_entry_viewed",
        "project_create_started",
        "project_goal_expanded",
        "project_create_submitted",
        "project_created",
        "project_created_from_practice",
        "project_create_failed",
        "project_setup_abandoned",
        "project_detail_first_practice_clicked",
        "project_first_practice_created",
    ])
    #expect(captured[5].1 == [
        "source": "projects_empty",
        "has_goal": "true",
        "duration_ms": "1200",
    ])
    #expect(captured[6].1 == [
        "link_result": "linked",
        "had_previous_project": "false",
    ])
    #expect(captured.allSatisfy { event in
        event.1.values.allSatisfy { !$0.contains("知足") && !$0.contains("副歌") }
    })
}
```

- [ ] **Step 2: Run — expect fail**

Run: `xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/RecordAnalyticsTests`

- [ ] **Step 3: Replace create-related functions in `RecordAnalytics.swift`**

Remove `projectSetupStarted(source:fromEmpty:hasExistingPractice:)`, `projectSetupSubmitClicked(fromEmpty:hasFocus:)`, `projectCreated(source:fromEmpty:hasFocus:durationMs:)`, `projectSetupAbandoned(fromEmpty:)`, `projectReadyViewed`, `projectReadyActionClicked`.

Add:

```swift
    static func projectCreateEntryViewed(source: String) {
        sink?("project_create_entry_viewed", ["source": source])
    }

    static func projectCreateStarted(source: String) {
        sink?("project_create_started", ["source": source])
    }

    static func projectGoalExpanded(source: String) {
        sink?("project_goal_expanded", ["source": source])
    }

    static func projectCreateSubmitted(source: String, hasGoal: Bool) {
        sink?("project_create_submitted", [
            "source": source,
            "has_goal": hasGoal ? "true" : "false",
        ])
    }

    static func projectCreated(source: String, hasGoal: Bool, durationMs: Int) {
        sink?("project_created", [
            "source": source,
            "has_goal": hasGoal ? "true" : "false",
            "duration_ms": String(durationMs),
        ])
    }

    static func projectCreatedFromPractice(linkResult: String, hadPreviousProject: Bool) {
        sink?("project_created_from_practice", [
            "link_result": linkResult,
            "had_previous_project": hadPreviousProject ? "true" : "false",
        ])
    }

    static func projectCreateFailed(source: String, errorCode: String) {
        sink?("project_create_failed", [
            "source": source,
            "error_code": errorCode,
        ])
    }

    static func projectSetupAbandoned(source: String, durationMs: Int) {
        sink?("project_setup_abandoned", [
            "source": source,
            "duration_ms": String(durationMs),
        ])
    }

    static func projectDetailFirstPracticeClicked(projectId: String) {
        sink?("project_detail_first_practice_clicked", ["project_id": projectId])
    }
```

Fix remaining call sites so the app compiles: `RecordView.startProjectCreate` uses `projectCreateStarted(source:)`; editor uses the new `projectCreated` / abandoned / submitted; delete Ready analytics calls when deleting that view.

- [ ] **Step 4: Run RecordAnalyticsTests — expect PASS**

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Features/Record/RecordAnalytics.swift foxgitaTests/RecordAnalyticsTests.swift
git add -u foxgita
git commit -m "Retarget project-create analytics off Ready and free text."
```

---

### Task 5: Slim editor, empty copy, delete Ready

**Files:**
- Modify: `foxgita/Features/Record/ProjectEditorView.swift`
- Modify: `foxgita/Features/Record/RecordView.swift`
- Delete: `foxgita/Features/Record/ProjectReadyView.swift`

**Interfaces:**
- Consumes: `createProject(name:goal:now:)`, `updateProjectBasics`, `presentCreatedProject(_:fromPracticeTab: false)`, analytics from Task 4
- Produces: create/edit UI with name + folded goal; success replace to detail + caller shows toast

- [ ] **Step 1: Slim `ProjectEditorView`**

Remove `fromEmpty`, `kind`, `stage`, `currentFocus`, `onCreated` sheet-join path (practice join moves to Task 6). Keep `mode`.

Key behavior:

```swift
private var canSubmit: Bool {
    !ProjectSetupRules.trimmed(name).isEmpty
}

private var isDirty: Bool {
    switch mode {
    case .create:
        return ProjectSetupRules.isCreateDirty(name: name, goal: goal)
    case .edit:
        return ProjectSetupRules.isEditDirty(
            name: name, goal: goal, loadedName: loadedName, loadedGoal: loadedGoal
        )
    }
}

private var analyticsSource: String {
    mode == .create ? createSource : "edit"
}
```

Pass `createSource` from RecordView: empty vs list. Add `var createSource: String = "projects_list"` on the view.

Header title: create → `新建项目`; edit → `编辑项目`. Close still uses abandon dialog copy `未保存的内容会丢失` / `继续填写` / `放弃创建`.

Body:

- Question `你想持续练什么？`
- Hint `用一句话创建，其他信息以后再补充。`
- Field `项目名称 *` placeholder `学会《知足》`
- Folded row: `＋` `添加完成标准` `选填  ›`. Expanding sets `goalExpanded = true` and calls `RecordAnalytics.projectGoalExpanded(source: createSource)` once.
- Edit mode: if loaded goal non-empty, start expanded and show the text field with value.
- Footer hint `只需要一个项目名称`
- Button create `创建项目` / edit `保存`

`save()`:

```swift
switch ProjectSetupRules.prepare(name: name, goal: goal) {
case .failure(let setupError):
    RecordAnalytics.projectSetupValidationFailed(fieldName: setupError.fieldName, reason: setupError.reason)
    if setupError.fieldName == "name" {
        nameError = setupError == .nameEmpty ? "请填写项目名称" : "名称过长"
    } else {
        goalError = "完成标准过长"
    }
case .success(let fields):
    isSubmitting = true
    do {
        switch mode {
        case .create:
            RecordAnalytics.projectCreateSubmitted(source: createSource, hasGoal: ProjectSetupRules.hasGoal(fields.goal))
            let project = try store.createProject(name: fields.name, goal: fields.goal, now: Date())
            let ms = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
            RecordAnalytics.projectCreated(source: createSource, hasGoal: ProjectSetupRules.hasGoal(fields.goal), durationMs: ms)
            router.presentCreatedProject(project.id, fromPracticeTab: false)
        case .edit(let id):
            try store.updateProjectBasics(id: id, name: fields.name, goal: fields.goal, now: Date())
            if !router.recordPath.isEmpty { router.recordPath.removeLast() }
        }
    } catch {
        isSubmitting = false
        RecordAnalytics.projectCreateFailed(source: createSource, errorCode: "save_failed")
        self.error = String(localized: "保存失败，请重试")
    }
}
```

Show toast: set `pendingProjectCreatedToast` on router **or** show toast on `ProjectDetailView.onAppear` when `createdAt` is within 2 seconds. Prefer an explicit flag:

Add to `AppRouter`: `var projectCreatedToast = false`. `presentCreatedProject` sets it `true`. `ProjectDetailView.onAppear` if true: show `项目已创建` and set false.

- [ ] **Step 2: Record empty / list copy and routing**

`startProjectCreate(source:)`:

```swift
private func startProjectCreate(source: String) {
    guard RecordProjectCreateStart.shouldPush(onto: router.recordPath.last) else { return }
    RecordAnalytics.projectCreateEntryViewed(source: source)
    RecordAnalytics.projectCreateStarted(source: source)
    router.recordPath.append(.projectCreate)
}
```

Empty card copy:

- Badge: `跨天练习目标`
- Title: `把多天练习放进一个项目`
- Body: two lines `以后可以从上次状态继续，` `练习记录会自然汇集到这里。`
- Primary: `新建项目` → `startProjectCreate(source: "projects_empty")`
- Keep `暂不创建，继续自由练习`
- Footnote: `项目不会改变已有练习，也不会要求所有练习加入项目`
- Remove the three bullet rows

List button label: `新建项目`, source `"projects_list"`.

Navigation:

```swift
case .projectCreate:
    ProjectEditorView(mode: .create, createSource: router.projectCreateSource)
case .projectCreateFromPractice(let itemId):
    ProjectCreateFromPracticeView(itemId: itemId, fromPracticeTab: false)
case .projectEdit(let id):
    ProjectEditorView(mode: .edit(id))
```

Set `router.projectCreateSource` inside `startProjectCreate`. Delete `case .projectReady`. Delete `ProjectReadyView.swift`.

- [ ] **Step 3: Build tests that still compile**

Run: `xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests/AppRouterTests`

Expected: PASS. Full test: `xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests`

Expected: PASS (fix leftover Ready / fromEmpty references if any).

- [ ] **Step 4: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Features/Record/ProjectEditorView.swift foxgita/Features/Record/RecordView.swift foxgita/App/AppRouter.swift
git rm foxgita/Features/Record/ProjectReadyView.swift
git commit -m "Replace the project Ready page with name-only create."
```

---

### Task 6: From-practice create page

**Files:**
- Create: `foxgita/Features/Record/ProjectCreateFromPracticeView.swift`
- Modify: `foxgita/Features/Record/RecordView.swift` navigationDestination
- Test: add cases to `foxgita/foxgitaTests/ProjectSetupRulesTests.swift` for source meta (put helpers on `ProjectSetupRules`)

**Interfaces:**
- Consumes: `createProject`, `setPracticeItemProject`, `presentCreatedProject`, `isFromPracticeDirty`
- Produces: `ProjectCreateFromPracticeView(itemId: UUID, fromPracticeTab: Bool)`
- Helpers:
  - `ProjectSetupRules.practiceSourceLabel(practiceDayKey:todayKey:) -> String` (`来自今天的练习` or `来自 {dayKey} 的练习`)
  - `ProjectSetupRules.practiceSourceMeta(durationSeconds:recordingCount:) -> String`

- [ ] **Step 1: Tests for source copy**

```swift
@Test func practiceSourceLabelAndMeta() {
    #expect(
        ProjectSetupRules.practiceSourceLabel(practiceDayKey: "2026-08-28", todayKey: "2026-08-28")
            == "来自今天的练习"
    )
    #expect(
        ProjectSetupRules.practiceSourceLabel(practiceDayKey: "2026-08-27", todayKey: "2026-08-28")
            == "来自 2026-08-27 的练习"
    )
    #expect(ProjectSetupRules.practiceSourceMeta(durationSeconds: 720, recordingCount: 1) == "12 分钟 · 已保存 1 条录音")
    #expect(ProjectSetupRules.practiceSourceMeta(durationSeconds: 720, recordingCount: 0) == "12 分钟")
}
```

Use `JustCompletedCopy.minutesLabel(durationSec:hasNote:mediaCount:)` for the minutes fragment if it already matches; otherwise format `Int(ceil(Double(max(duration,0))/60.0)) 分钟`.

- [ ] **Step 2: Run — expect fail**

- [ ] **Step 3: Implement helpers + view**

Add helpers to `ProjectSetupRules`. Create the view:

```swift
struct ProjectCreateFromPracticeView: View {
    let itemId: UUID
    var fromPracticeTab: Bool = false
    // Query item, recordings count, current project name
    // Prefill name = item.title
    // createdProjectId: UUID? for link retry
    // showSwitchConfirm when item.projectId != nil && user taps 创建并加入
}
```

Layout (Figma):

- Back / 建立长期项目
- 把这次练习持续下去
- Peach card: source label, title, meta
- 项目名称 * prefilled
- 这次练习会自动加入项目。完成标准和阶段可以稍后补充。
- 仅创建空项目 (text)
- 创建并加入项目 (primary)

`create(link: Bool)`:

1. If submitting, return.
2. `prepare(name:goal: "")`.
3. If `createdProjectId == nil`, `createProject`; on failure keep form.
4. If `link == false`: `projectCreatedFromPractice(linkResult: "empty_only", hadPreviousProject: item.projectId != nil)`; `presentCreatedProject`.
5. If `link == true` and already linked and not confirmed: set `showSwitchConfirm` and return.
6. `setPracticeItemProject`; on failure set `createdProjectId`, error `项目已创建，加入失败，请重试`, `linkResult: link_failed`. Retry only calls step 6.
7. Success: `linkResult: linked`, `presentCreatedProject(id, fromPracticeTab:)`.

Abandon: only if `isFromPracticeDirty`; otherwise pop/dismiss.

Wire Record navigation:

```swift
case .projectCreateFromPractice(let itemId):
    ProjectCreateFromPracticeView(itemId: itemId, fromPracticeTab: false)
```

- [ ] **Step 4: Run ProjectSetupRulesTests + AppRouterTests**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Features/Record/ProjectCreateFromPracticeView.swift foxgita/Features/Record/ProjectSetupRules.swift foxgita/Features/Record/RecordView.swift foxgitaTests/ProjectSetupRulesTests.swift
git commit -m "Add create-from-practice with link retry that keeps the project."
```

---

### Task 7: Practice detail entry + complete id

**Files:**
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift`

**Interfaces:**
- Consumes: `RecordRoute.projectCreateFromPractice(itemId:)`, `lastCompletedPracticeItemId`
- Produces: menu action `建立长期项目`; complete writes the item id

- [ ] **Step 1: Replace `startCreateAndJoin`**

```swift
private func startCreateAndJoin() {
    RecordAnalytics.projectCreateEntryViewed(source: "practice_detail")
    RecordAnalytics.projectCreateStarted(source: "practice_detail")
    if openedFromRecord {
        router.recordPath.append(.projectCreateFromPractice(itemId: itemId))
    } else {
        showCreateFromPracticeSheet = true
    }
}
```

Rename `showCreateProjectSheet` → `showCreateFromPracticeSheet`. Sheet content:

```swift
.sheet(isPresented: $showCreateFromPracticeSheet) {
    ProjectCreateFromPracticeView(itemId: itemId, fromPracticeTab: true)
}
```

Menu: unlinked `Button("建立长期项目")`; linked also include `Button("建立长期项目")` besides 更换 / 移出. Remove `新建并加入`.

- [ ] **Step 2: Write completed id in `complete(_:)`**

After a successful complete with `hadContent == true`:

```swift
router.lastCompletedPracticeItemId = item.id
```

Do not set it when the empty-complete toast path runs (`这次没有留下记录`).

- [ ] **Step 3: Build foxgitaTests**

Run: `xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Features/Practice/PracticeDetailView.swift
git commit -m "Open from-practice create from practice detail."
```

---

### Task 8: Project detail empty state and later-fill

**Files:**
- Modify: `foxgita/Features/Record/ProjectDetailView.swift`

**Interfaces:**
- Consumes: `ProjectRules.associatedEffectiveItems`, `updateProjectGoal`, `updateProjectStage`, `createTodayPracticeItem`
- Produces: empty (0 effective items) Figma layout; goal sheet; stage dialog; first-practice CTA

- [ ] **Step 1: Branch the scroll body**

```swift
private var hasEffectivePractice: Bool {
    !ProjectRules.associatedEffectiveItems(projectId: projectId, in: allSnapshots).isEmpty
}
```

If `!hasEffectivePractice`, render:

1. Identity card: name, `进行中`, `刚刚创建 · 还没有练习记录`
2. Setup-later card:
   - 完成标准 / `添加  ›` or truncated goal / `编辑  ›`
   - 当前阶段 / `未设置  ›` or stage name
3. Grey card: badge `第一次`, title `从一次真实练习开始`, body `练习完成后，时间、笔记和录音会汇集到项目里。`
4. Footer hint `项目已创建，可以稍后再练`
5. Button `开始第一次练习` → existing `createTodayPractice` but:
   - call `RecordAnalytics.projectDetailFirstPracticeClicked`
   - **replace** stack with practice detail (Ready used replace; current detail **appends**. For the empty CTA use `router.replaceLastRecordRoute(.practiceDetail(itemId: item.id))` so back skips the empty project form. Keep **append** for `创建今天的练习项` when `hasEffectivePractice`.)

If `hasEffectivePractice`, keep current evidence / this-time / `创建今天的练习项`.

`onAppear`: if `router.projectCreatedToast` { show toast `项目已创建`; router.projectCreatedToast = false }.

Goal sheet: `@State showGoalEditor`, text field, Save calls `updateProjectGoal`. Empty save clears.

Stage: existing confirmationDialog with `ProjectSetupRules.stages` + 不选择 → `updateProjectStage`.

- [ ] **Step 2: Build tests**

Run: `xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:foxgitaTests`

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Features/Record/ProjectDetailView.swift foxgita/App/AppRouter.swift
git commit -m "Show first-practice empty detail and later-fill goal/stage."
```

---

### Task 9: Just-completed card on practice home

**Files:**
- Modify: `foxgita/Features/Practice/JustCompletedCard.swift`
- Modify: `foxgita/Features/Practice/PracticeView.swift`

**Interfaces:**
- Consumes: `lastCompletedPracticeItemId`, `ProjectCreateFromPracticeView`
- Produces: card on today home when the id matches a live item

- [ ] **Step 1: Extend the card**

```swift
struct JustCompletedCard: View {
    var title: String
    var minutes: String
    var summary: String
    var onPracticeAgain: () -> Void
    var onViewRecord: () -> Void
    var onCreateProject: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // existing header / title / summary / two buttons
            if let onCreateProject {
                Button("建立长期项目", action: onCreateProject)
                    .font(.system(size: 14))
                    .foregroundStyle(GitaTheme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        // existing padding / card chrome
    }
}
```

- [ ] **Step 2: Mount in `PracticeView`**

If `isSelectedToday`, resolve `router.lastCompletedPracticeItemId` against `allSnapshots`. Use snapshot `note` and `recordingCount` (there is no `recordingFileNames` on the snapshot):

```swift
if isSelectedToday, let id = router.lastCompletedPracticeItemId,
   let item = allSnapshots.first(where: { $0.id == id }) {
    let hasNote = !item.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    JustCompletedCard(
        title: item.title,
        minutes: JustCompletedCopy.minutesLabel(
            durationSec: item.durationSeconds,
            hasNote: hasNote,
            mediaCount: item.recordingCount
        ),
        summary: {
            var parts: [String] = []
            if hasNote { parts.append("笔记") }
            if item.recordingCount > 0 { parts.append("录音 \(item.recordingCount)") }
            return parts.joined(separator: " · ")
        }(),
        onPracticeAgain: { router.practicePath.append(.detail(itemId: item.id)) },
        onViewRecord: { router.practicePath.append(.detail(itemId: item.id)) },
        onCreateProject: item.projectId == nil ? {
            RecordAnalytics.projectCreateEntryViewed(source: "practice_complete")
            RecordAnalytics.projectCreateStarted(source: "practice_complete")
            showCreateFromPracticeItemId = item.id
        } : nil
    )
} else if isSelectedToday, router.lastCompletedPracticeItemId != nil {
    router.clearJustCompleted()
}
```

Add `@State private var showCreateFromPracticeItemId: UUID?` and present the from-practice view as a sheet when that id is set (`sheet(isPresented:)` plus the stored UUID is enough; UUID is not Identifiable).

- [ ] **Step 3: Build foxgitaTests**

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Features/Practice/JustCompletedCard.swift foxgita/Features/Practice/PracticeView.swift
git commit -m "Surface create-from-practice on the just-completed home card."
```

---

### Task 10: Spec checklist and docs-repo commit

**Files:**
- Modify: `foxgita/docs/superpowers/2026-09-04-project-init-simplified/specs/2026-09-04-project-init-simplified-design.md` (status line only)

- [ ] **Step 1: Manual smoke (simulator)**

1. Record → 项目 empty → 新建项目 → name only → lands on detail with toast, no Ready.
2. Expand 完成标准, create, detail shows the goal and `添加` becomes the text.
3. Set stage from detail; edit name; confirm stage still set.
4. 开始第一次练习 → practice detail; project time still 0 until duration > 0.
5. Complete a free practice → home card → 建立长期项目 → 创建并加入 → record project detail; original duration/note unchanged.
6. 仅创建空项目 → new project, practice still unlinked.
7. Linked practice → 建立长期项目 → confirm switch.
8. Fail link: after create, if you temporarily throw in `setPracticeItemProject`, UI keeps one project and retry only links.

- [ ] **Step 2: Tick spec §10 boxes that are done**

- [ ] **Step 3: Commit plan already saved; commit spec status in docs repo if changed**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add docs/superpowers/2026-09-04-project-init-simplified
git commit -m "Add project-init simplified implementation plan."
```

---

## Self-review

| Spec section | Task |
|---|---|
| Name-only create / folded goal | 1, 2, 5 |
| Delete Ready, land on detail | 3, 5, 8 |
| Edit does not wipe stage | 2, 5 |
| From-practice page + retry | 6 |
| Detail + complete entries | 7, 9 |
| Empty detail + first practice + later-fill | 8 |
| Analytics without PII | 4 |
| JustCompletedCard unused → wired | 9 |
| Type/focus/cover P1 | not tasked |

No TBD. Signatures in later tasks match Task 1–3 (`prepare(name:goal:)`, `presentCreatedProject`, `lastCompletedPracticeItemId`, `projectCreateFromPractice(itemId:)`).
