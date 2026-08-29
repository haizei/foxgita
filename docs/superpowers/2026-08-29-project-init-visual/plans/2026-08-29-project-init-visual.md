# Project Initialization Visual Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align empty / create-edit / Ready with Figma Project Initialization, persist optional type and stage, and stop the keyboard from crushing the form.

**Architecture:** `ProjectSetupRules` owns the controlled kind/stage lists, dirty checks, and Ready stage visibility. `ProjectEditorView` keeps one form: chips and a system stage dialog write `kindRaw` / `stageRaw` as Chinese strings. The footer sits in `safeAreaInset` so the keyboard lifts the button instead of collapsing the scroll view. `ProjectReadyView` shows a stage badge only when `showsReadyStage` is true. Empty-state copy is already in `RecordView`; this plan only touches it if a listed string is missing.

**Tech Stack:** SwiftUI, existing SwiftData `kindRaw` / `stageRaw`, Swift Testing, `foxgita` scheme. Implementation commits happen in `/Users/haizei/work/AI/program/gita/foxgita`.

## Global Constraints

- Spec: `foxgita/docs/superpowers/2026-08-29-project-init-visual/specs/2026-08-29-project-init-visual-design.md`
- PRD: `foxgita/docs/superpowers/2026-08-29-project-init-visual/specs/2026-08-29-project-init-visual-prd.md`
- Visual: Figma Project Initialization, file `smeuuUaTOYE1URHhIGbzyd`, node `624-405`
- Tokens only: `GitaTheme`, `GitaFont`, `PageBackground`. No new colors
- Kinds (exact): `歌曲` / `技巧` / `演出准备`. Store the Chinese string. Unselected is `""`
- Stages (exact): `熟悉内容` / `分段练习` / `串联整首` / `稳定演奏` / `完成`. Store the Chinese string. Unselected is `""`
- Name + goal remain the only required fields. Type/stage/focus never block submit
- Ready still only from `projectCreate(fromEmpty: true)`
- Close only. No back chevron
- No schema change, no `project.pbxproj` edit, no new analytics events, no type/stage text in analytics
- Legacy unknown `kindRaw` / `stageRaw`: show as-is, do not rewrite on open; keep on save if the user did not change that field
- Run tests from `/Users/haizei/work/AI/program/gita/foxgita`
- Test command: `xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:foxgitaTests/<File>`
- If that simulator is missing, use any available iPhone simulator. Do not skip tests
- Quote `-only-testing:` filters in zsh when they contain `()`

## File structure

- Modify: `foxgita/foxgita/Features/Record/ProjectSetupRules.swift` — kind/stage lists, dirty, Ready stage
- Modify: `foxgita/foxgitaTests/ProjectSetupRulesTests.swift`
- Modify: `foxgita/foxgita/Features/Record/ProjectEditorView.swift` — chips, stage row, persist, keyboard, contrast
- Modify: `foxgita/foxgita/Features/Record/ProjectReadyView.swift` — stage badge
- Modify: `foxgita/foxgita/Features/Record/RecordView.swift` — only if empty-state copy/layout still misses spec 3.1

`PracticeStore.createProject` / `updateProject` already pass `kindRaw` / `stageRaw` through. Do not add a second write path.

---

### Task 1: Kind and stage rules

**Files:**
- Modify: `foxgita/foxgita/Features/Record/ProjectSetupRules.swift`
- Test: `foxgita/foxgitaTests/ProjectSetupRulesTests.swift`

**Interfaces:**
- Consumes: existing `trimmed`, `isCreateDirty`, `isEditDirty`, `showsReadyFocus`
- Produces:
  - `static let kinds: [String] = ["歌曲", "技巧", "演出准备"]`
  - `static let stages: [String] = ["熟悉内容", "分段练习", "串联整首", "稳定演奏", "完成"]`
  - `static func isKnownKind(_ raw: String) -> Bool`
  - `static func isKnownStage(_ raw: String) -> Bool`
  - `static func showsReadyStage(_ raw: String) -> Bool`
  - `static func isCreateDirty(name:goal:currentFocus:kind:stage:) -> Bool`
  - `static func isEditDirty(name:goal:currentFocus:kind:stage:loadedName:loadedGoal:loadedFocus:loadedKind:loadedStage:) -> Bool`

- [ ] **Step 1: Write the failing tests**

Add these tests to `ProjectSetupRulesTests`. Update the existing dirty tests to the new signatures (pass `kind: ""`, `stage: ""` where the old cases did not care about type/stage):

```swift
    @Test func knownKindAndStage() {
        #expect(ProjectSetupRules.kinds == ["歌曲", "技巧", "演出准备"])
        #expect(ProjectSetupRules.stages == ["熟悉内容", "分段练习", "串联整首", "稳定演奏", "完成"])
        #expect(ProjectSetupRules.isKnownKind("歌曲") == true)
        #expect(ProjectSetupRules.isKnownKind(" 技巧 ") == true)
        #expect(ProjectSetupRules.isKnownKind("自由") == false)
        #expect(ProjectSetupRules.isKnownKind("") == false)
        #expect(ProjectSetupRules.isKnownStage("串联整首") == true)
        #expect(ProjectSetupRules.isKnownStage("分段") == false)
    }

    @Test func readyStageHiddenWhenBlank() {
        #expect(ProjectSetupRules.showsReadyStage("") == false)
        #expect(ProjectSetupRules.showsReadyStage("   ") == false)
        #expect(ProjectSetupRules.showsReadyStage("串联整首") == true)
        #expect(ProjectSetupRules.showsReadyStage("旧自由文本") == true)
    }

    @Test func createDirtyIncludesKindAndStage() {
        #expect(
            ProjectSetupRules.isCreateDirty(
                name: "", goal: "", currentFocus: "", kind: "", stage: ""
            ) == false
        )
        #expect(
            ProjectSetupRules.isCreateDirty(
                name: "", goal: "", currentFocus: "", kind: "歌曲", stage: ""
            ) == true
        )
        #expect(
            ProjectSetupRules.isCreateDirty(
                name: "", goal: "", currentFocus: "", kind: "", stage: "串联整首"
            ) == true
        )
    }

    @Test func editDirtyIncludesKindAndStage() {
        #expect(
            ProjectSetupRules.isEditDirty(
                name: "知足", goal: "完整弹唱", currentFocus: "",
                kind: "歌曲", stage: "串联整首",
                loadedName: "知足", loadedGoal: "完整弹唱", loadedFocus: "",
                loadedKind: "歌曲", loadedStage: "串联整首"
            ) == false
        )
        #expect(
            ProjectSetupRules.isEditDirty(
                name: "知足", goal: "完整弹唱", currentFocus: "",
                kind: "", stage: "串联整首",
                loadedName: "知足", loadedGoal: "完整弹唱", loadedFocus: "",
                loadedKind: "歌曲", loadedStage: "串联整首"
            ) == true
        )
        #expect(
            ProjectSetupRules.isEditDirty(
                name: "知足", goal: "完整弹唱", currentFocus: "",
                kind: "", stage: "旧自由文本",
                loadedName: "知足", loadedGoal: "完整弹唱", loadedFocus: "",
                loadedKind: "", loadedStage: "旧自由文本"
            ) == false
        )
    }
```

Also change the two existing dirty tests to pass empty kind/stage (create) and empty loaded/current kind/stage (edit) so they still compile after the signature change.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:foxgitaTests/ProjectSetupRulesTests
```

Expected: FAIL — `kinds` / `isKnownKind` / extra dirty parameters do not exist.

- [ ] **Step 3: Implement the rules**

Replace the dirty methods and add the new API on `ProjectSetupRules`. Leave `prepare` unchanged (still name/goal/focus only):

```swift
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

    static func isCreateDirty(
        name: String,
        goal: String,
        currentFocus: String,
        kind: String,
        stage: String
    ) -> Bool {
        !trimmed(name).isEmpty
            || !trimmed(goal).isEmpty
            || !trimmed(currentFocus).isEmpty
            || !trimmed(kind).isEmpty
            || !trimmed(stage).isEmpty
    }

    static func isEditDirty(
        name: String,
        goal: String,
        currentFocus: String,
        kind: String,
        stage: String,
        loadedName: String,
        loadedGoal: String,
        loadedFocus: String,
        loadedKind: String,
        loadedStage: String
    ) -> Bool {
        trimmed(name) != trimmed(loadedName)
            || trimmed(goal) != trimmed(loadedGoal)
            || trimmed(currentFocus) != trimmed(loadedFocus)
            || trimmed(kind) != trimmed(loadedKind)
            || trimmed(stage) != trimmed(loadedStage)
    }
```

Update `ProjectEditorView.isDirty` in the same commit only if the project does not compile otherwise — prefer to update call sites in Task 2. If Task 1 cannot build the app target, temporarily pass `kind: ""`, `stage: ""` / loaded empties in `ProjectEditorView` so tests can run; Task 2 replaces those stubs.

- [ ] **Step 4: Run tests to verify they pass**

Same `xcodebuild test` command as Step 2.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Features/Record/ProjectSetupRules.swift foxgitaTests/ProjectSetupRulesTests.swift foxgita/Features/Record/ProjectEditorView.swift
git commit -m "feat: treat project kind and stage as optional setup fields"
```

---

### Task 2: Persist chips and stage on the form

**Files:**
- Modify: `foxgita/foxgita/Features/Record/ProjectEditorView.swift`

**Interfaces:**
- Consumes: `ProjectSetupRules.kinds`, `stages`, `isKnownKind`, `isCreateDirty`, `isEditDirty`
- Produces: editor `kind` / `stage` state loaded from the project, written to `createProject` / `updateProject` as the current strings (legacy kept when unchanged)

- [ ] **Step 1: Add state and wire dirty / load / save**

In `ProjectEditorView`, add:

```swift
    @State private var kind = ""
    @State private var stage = ""
    @State private var loadedKind = ""
    @State private var loadedStage = ""
    @State private var showStagePicker = false
```

Replace `isDirty` with:

```swift
    private var isDirty: Bool {
        switch mode {
        case .create:
            return ProjectSetupRules.isCreateDirty(
                name: name,
                goal: goal,
                currentFocus: currentFocus,
                kind: kind,
                stage: stage
            )
        case .edit:
            return ProjectSetupRules.isEditDirty(
                name: name,
                goal: goal,
                currentFocus: currentFocus,
                kind: kind,
                stage: stage,
                loadedName: loadedName,
                loadedGoal: loadedGoal,
                loadedFocus: loadedFocus,
                loadedKind: loadedKind,
                loadedStage: loadedStage
            )
        }
    }
```

In `loadEditFieldsIfNeeded`, also set:

```swift
        kind = project.kindRaw
        stage = project.stageRaw
        loadedKind = project.kindRaw
        loadedStage = project.stageRaw
```

In `save()`, replace both `kindRaw: ""` / `stageRaw: ""` with:

```swift
                        kindRaw: ProjectSetupRules.trimmed(kind),
                        stageRaw: ProjectSetupRules.trimmed(stage),
```

- [ ] **Step 2: Add chips and the stage row**

Insert into `optionalSection`, **above** the current-focus field (Figma order: chips, stage, focus, hint):

```swift
            HStack(spacing: 8) {
                ForEach(ProjectSetupRules.kinds, id: \.self) { item in
                    let selected = ProjectSetupRules.trimmed(kind) == item
                    Button {
                        kind = selected ? "" : item
                    } label: {
                        Text(item)
                            .font(GitaFont.footnote(selected ? .medium : .regular))
                            .foregroundStyle(selected ? GitaTheme.brand500 : GitaTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selected ? GitaTheme.brand50 : GitaTheme.bgSubtle)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }

            Button { showStagePicker = true } label: {
                HStack {
                    Text("当前阶段")
                        .font(GitaFont.footnote())
                        .foregroundStyle(GitaTheme.textSecondary)
                    Spacer(minLength: 0)
                    Text(ProjectSetupRules.trimmed(stage).isEmpty ? "未选择" : stage)
                        .font(GitaFont.callout(.medium))
                        .foregroundStyle(GitaTheme.textPrimary)
                    Text("›")
                        .font(GitaFont.callout())
                        .foregroundStyle(GitaTheme.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(GitaTheme.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: GitaTheme.radius12)
                        .stroke(GitaTheme.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))
            }
            .buttonStyle(.plain)
            .confirmationDialog("当前阶段", isPresented: $showStagePicker, titleVisibility: .visible) {
                Button("不选择") { stage = "" }
                ForEach(ProjectSetupRules.stages, id: \.self) { item in
                    Button(item) { stage = item }
                }
                Button("取消", role: .cancel) {}
            }
```

Unknown legacy `kind` means no chip is selected (`isKnownKind` is false) but `kind` still holds the raw value until the user taps a chip or the same chip-deselect path. Do **not** clear `kind` on appear.

Unknown legacy `stage` shows its raw text on the row (the ternary above already does that).

- [ ] **Step 3: Compile**

Run:

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
xcodebuild -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Re-run rules tests**

```bash
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:foxgitaTests/ProjectSetupRulesTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Features/Record/ProjectEditorView.swift
git commit -m "feat: save optional project kind and stage from setup"
```

---

### Task 3: Keyboard, contrast, and placeholders

**Files:**
- Modify: `foxgita/foxgita/Features/Record/ProjectEditorView.swift`

**Interfaces:**
- Consumes: existing `editorFooter`, `field(...)`, `canSubmit`
- Produces: footer in `safeAreaInset`; disabled button opacity `0.72`; placeholders stay secondary

- [ ] **Step 1: Stop pinning the footer inside the squeezed VStack**

In `body`, remove `editorFooter` from the inner `VStack` and attach it as an inset so the keyboard lifts the button and the `ScrollView` keeps height:

```swift
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                editorHeader
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        requiredCard
                        optionalSection
                        if let error {
                            Text(error)
                                .font(GitaFont.callout())
                                .foregroundStyle(GitaTheme.brand500)
                        }
                    }
                    .padding(.horizontal, GitaTheme.s24)
                    .padding(.top, GitaTheme.s16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            editorFooter
        }
```

- [ ] **Step 2: Keep the disabled primary button readable**

In `editorFooter`, change `.opacity(canSubmit && !isSubmitting ? 1 : 0.4)` to `0.72` when disabled:

```swift
                .opacity(canSubmit && !isSubmitting ? 1 : 0.72)
```

Keep `brand500` fill and `brandOn` label. Do not switch the idle button to a washed peach that hides the label.

- [ ] **Step 3: Keep placeholders from looking filled**

In `field(...)`, the `TextField` already uses a placeholder string. Add:

```swift
            TextField(placeholder, text: text, axis: .vertical)
                .font(GitaFont.callout())
                .foregroundStyle(GitaTheme.textPrimary)
                .tint(GitaTheme.brand500)
```

Do not put the Figma sample strings into `@State`. They stay placeholder-only.

Emphasized fields (goal, focus) keep `brand50` fill. Name stays white + `borderSubtle`.

- [ ] **Step 4: Build**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
xcodebuild -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```

Expected: BUILD SUCCEEDED. Manual check (simulator or device): focus 完成目标, keyboard up — 当前重点 is not stacked on 完成目标; 「创建项目」 sits above the keyboard and remains readable when name/goal are empty.

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Features/Record/ProjectEditorView.swift
git commit -m "fix: keep project setup usable above the keyboard"
```

---

### Task 4: Ready stage badge and empty-state check

**Files:**
- Modify: `foxgita/foxgita/Features/Record/ProjectReadyView.swift`
- Modify: `foxgita/foxgita/Features/Record/RecordView.swift` — only if a spec 3.1 string is missing

**Interfaces:**
- Consumes: `ProjectSetupRules.showsReadyStage`
- Produces: name-row badge when stage is non-empty; no badge when blank; no type chips on Ready

- [ ] **Step 1: Show the stage badge on the name row**

Replace the name-only line in `createdProjectCard` with:

```swift
            HStack(alignment: .center, spacing: 8) {
                Text(project.name)
                    .font(GitaFont.title())
                    .foregroundStyle(GitaTheme.textPrimary)
                Spacer(minLength: 0)
                if ProjectSetupRules.showsReadyStage(project.stageRaw) {
                    Text(project.stageRaw)
                        .font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(GitaTheme.bgSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius8))
                }
            }
```

Do not invent 「串联整首」 when `stageRaw` is blank. Do not render type chips.

- [ ] **Step 2: Confirm empty state**

Open `RecordView.projectEmptyState`. Required strings (all must exist):

- 跨天目标
- 把多天练习连成一个项目
- 看见上次练到哪里
- 保存下一次的唯一重点
- 从项目直接创建今天的练习
- 创建第一个项目
- 暂不创建，继续自由练习
- 创建项目不会改变已有练习，也不会要求所有练习都归入项目

If all are present, do not edit `RecordView`.

- [ ] **Step 3: Build**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
xcodebuild -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run setup tests**

```bash
xcodebuild test -scheme foxgita -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:foxgitaTests/ProjectSetupRulesTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/haizei/work/AI/program/gita/foxgita
git add foxgita/Features/Record/ProjectReadyView.swift foxgita/Features/Record/RecordView.swift
git commit -m "feat: show Ready stage badge when a stage is saved"
```

If `RecordView.swift` was not modified, omit it from `git add`.

---

## Self-review

| Spec requirement | Task |
|---|---|
| Empty-state Figma card and copy | 4 (verify; already landed) |
| Chips 歌曲 / 技巧 / 演出准备, single-select, deselect | 1, 2 |
| Shared 5-stage list + 不选择 | 1, 2 |
| Persist Chinese `kindRaw` / `stageRaw` | 2 |
| Do not clear type/stage on edit save | 2 |
| Legacy free text kept until user changes it | 1 (dirty), 2 (load/save) |
| Placeholders are not prefill | 3 |
| Disabled primary stays readable | 3 |
| Keyboard does not crush fields; button above keyboard | 3 |
| Ready stage badge only when non-empty | 1 (`showsReadyStage`), 4 |
| Ready focus block unchanged | 4 (do not touch that `if`) |
| No type chips on Ready | 4 |
| Close only, Ready still `fromEmpty` | unchanged; do not edit routes |
| No schema / no new analytics | unchanged |

No TBD steps. Dirty / known / Ready-stage names are the same in Tasks 1–4.
