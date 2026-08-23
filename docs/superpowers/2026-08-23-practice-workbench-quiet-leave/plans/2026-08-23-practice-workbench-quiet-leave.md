# Practice Workbench Quiet Leave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Back silently persists the same visit fields as Complete and leaves without a prompt; Complete still saves and snaps to today but no longer writes a just-completed card.

**Architecture:** One `persistVisit(task:)` on `PracticeDetailView` owns pending clips plus `updateOpenSession` / `finishSession`. `requestExit` always persists then leaves. `complete` uses the same helper and never assigns `lastCompletedSessionId`. `PracticeView` stops rendering `JustCompletedCard`.

**Tech Stack:** SwiftUI · SwiftData · Swift Testing · existing `PracticeStore.finishSession -> String?` / `updateOpenSession`

## Global Constraints

- Spec: `docs/superpowers/2026-08-23-practice-workbench-quiet-leave/specs/2026-08-23-practice-workbench-quiet-leave-design.md`
- iOS 18+ · Scheme `foxgita` · cwd `/Users/haizei/work/AI/program/gita/foxgita`
- Copy: `zh-Hans` via `String(localized:)`
- Do not change Schema
- Do not write `lastCompletedSessionId` on Back or Complete
- Do not set `returnPracticeToToday` on Back
- Do not guess latest session on the home card
- Do not delete `JustCompletedCard.swift` / `JustCompletedCopy.swift` / `AppRouter.lastCompletedSessionId`
- Do not treat steps/BPM-only (no timer, note, media, or open session) as a visit
- Do not edit `project.pbxproj`
- Do not commit unrelated dirty files (`VideoAnalysisView`, `ReviewJobRunner`, `Localizable.xcstrings`, architecture html, deleted media-review docs)
- Unit test command:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

If `iPhone 17` is missing, use any available iPhone simulator from `xcrun simctl list devices available`.

## File map

| File | Responsibility |
|---|---|
| `foxgita/Features/Practice/PracticeDetailView.swift` | `persistVisit`; Back saves without dialog; Complete no card id |
| `foxgita/Features/Practice/PracticeView.swift` | Stop rendering `JustCompletedCard` |
| `docs/TECHNICAL.md` | Back / Complete rows |
| spec header | Flip to Approved + plan path |

YAGNI: do not remove Router card plumbing; do not add new test types unless a compile fails.

---

### Task 1: persistVisit + silent Back

**Files:**
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift` (`confirmExit` ~34, dialog ~179-189, `requestExit` ~828-845, add `persistVisit` next to `saveOpenSession` ~899)

**Interfaces:**
- Consumes: `store.finishSession(...) -> String?`, `store.updateOpenSession(...) -> Bool`, `hasUnsavedWork`, `persistPending`, `saveOpenSession`
- Produces: `@discardableResult private func persistVisit(task: TaskItem) -> String?` — open session id or new `finishSession` id; `nil` on empty visit or failed create. `requestExit` never sets `confirmExit` or `lastCompletedSessionId` or `returnPracticeToToday`.

- [ ] **Step 1: Replace the confirm-exit UI**

Remove `@State private var confirmExit = false` and `@State private var abandoning = false`.

Remove the `.confirmationDialog("这次练习还没保存", ...)` block (the one with 「放弃并返回」 / 「继续练习」).

In `onDisappear`, drop the `abandoning` guard so pending persist always runs:

```swift
if let task {
    persistPending(task: task)
    saveOpenSession(task: task)
}
```

- [ ] **Step 2: Add persistVisit and switch requestExit**

Add next to `saveOpenSession`:

```swift
@discardableResult
private func persistVisit(task: TaskItem) -> String? {
    persistPending(task: task)
    if let open = openSessionId {
        saveOpenSession(task: task)
        return open
    }
    guard hasUnsavedWork else { return nil }
    var clips = recorder.consume()
    clips += video.takeAll().map { audioClip($0) }
    let end = Date()
    let elapsed = practiceTimer.elapsedSec
    let savedId = store.finishSession(
        taskId: task.id, steps: steps, note: noteText,
        startedAt: practiceTimer.startedAt ?? end.addingTimeInterval(TimeInterval(-elapsed)),
        endedAt: end, durationSec: elapsed, bpm: metronome.bpm, recordings: clips
    )
    if let savedId { openSessionId = savedId }
    return savedId
}
```

Replace `requestExit` with:

```swift
private func requestExit() {
    practiceTimer.pause()
    metronome.stop()
    if let task {
        if recorder.isRecording { recorder.stop(label: task.title) }
        persistVisit(task: task)
    }
    leave()
}
```

Do **not** change `complete` in this task (Task 2).

- [ ] **Step 3: Compile**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

Expected: PASS. Read-verify: no `confirmExit` / `abandoning` left; `requestExit` has no `lastCompletedSessionId` and no `returnPracticeToToday`.

- [ ] **Step 4: Commit**

```bash
git add foxgita/Features/Practice/PracticeDetailView.swift
git commit -m "Save the visit on Back without a confirm dialog."
```

---

### Task 2: Complete without card; hide home card

**Files:**
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift` (`complete` ~912-955)
- Modify: `foxgita/Features/Practice/PracticeView.swift` (`justCompleted` ~55-58, card ~133-157)

**Interfaces:**
- Consumes: Task 1 `persistVisit(task:) -> String?`
- Produces: `complete` never assigns `router.lastCompletedSessionId`. Effective success still sets `returnPracticeToToday`. Empty complete still toasts `这次没有留下记录`. `PracticeView` body does not construct `JustCompletedCard`.

- [ ] **Step 1: Rewrite complete**

Replace `complete` with:

```swift
private func complete(_ task: TaskItem) {
    guard !isCompleting else { return }
    isCompleting = true
    if recorder.isRecording { recorder.stop(label: task.title) }
    practiceTimer.pause()
    metronome.stop()
    player.stop()
    videoPlayURL = nil
    let savedId = persistVisit(task: task)
    if let savedId {
        Haptics.success()
        router.returnPracticeToToday = true
        router.practicePath.removeAll()
        return
    }
    if !hasUnsavedWork {
        router.practiceToast = String(localized: "这次没有留下记录")
        router.returnPracticeToToday = true
        router.practicePath.removeAll()
        return
    }
    isCompleting = false
}
```

`savedId` is unused except `if let` — do not assign it to the router.

- [ ] **Step 2: Stop rendering the card**

Delete the `justCompleted` computed property.

Delete the `if let session = justCompleted { JustCompletedCard(...) }` block after `StreakCard`.

Leave `clearJustCompletedIfMissing()`, `onChange(of: router.lastCompletedSessionId)`, and `onChange(of: selectedDay)` that call `clearJustCompleted()`. Do not add an `endedAt` latest-session lookup.

- [ ] **Step 3: Compile**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

Expected: PASS. Read-verify: `PracticeDetailView` has zero `lastCompletedSessionId` assignments; `PracticeView` has zero `JustCompletedCard`.

- [ ] **Step 4: Commit**

```bash
git add foxgita/Features/Practice/PracticeDetailView.swift \
  foxgita/Features/Practice/PracticeView.swift
git commit -m "Drop the just-completed card from Complete and today."
```

---

### Task 3: Docs

**Files:**
- Modify: `docs/TECHNICAL.md` (table rows 「计时中返回」~130, 「完成练习」~133)
- Modify: spec header status

**Interfaces:**
- Consumes: Tasks 1–2 behavior
- Produces: docs that match shipping code

- [ ] **Step 1: Patch TECHNICAL.md**

Change 「计时中返回」 to:

```text
有内容：静默写入 session（计时 / 笔记 / 步骤 / BPM / 媒体）并离开，无确认框、不拉回今天、不写 lastCompletedSessionId。空访：直接离开。
```

Change 「完成练习」 to:

```text
有效完成：写回 task.defaultBpm，震动，回今天。不写 lastCompletedSessionId，不展示「刚刚完成」。空完成：toast「这次没有留下记录」，不写 BPM / id。返回：与完成同一套落库，不震动、不拉回今天。
```

- [ ] **Step 2: Flip spec status**

First status line of `docs/superpowers/2026-08-23-practice-workbench-quiet-leave/specs/2026-08-23-practice-workbench-quiet-leave-design.md`:

`状态：Approved — implementation plan in ../plans/2026-08-23-practice-workbench-quiet-leave.md`

- [ ] **Step 3: Commit**

```bash
git add docs/TECHNICAL.md \
  docs/superpowers/2026-08-23-practice-workbench-quiet-leave/specs/2026-08-23-practice-workbench-quiet-leave-design.md
git commit -m "Document silent Back save and no just-completed card."
```

---

## Spec coverage

| Spec | Task |
|---|---|
| Back with content saves timer/note/steps/BPM/media | 1 |
| Back empty leaves | 1 |
| No confirm dialog | 1 |
| Back no haptic / no id / no snap-to-today | 1 |
| Back save failure still leaves | 1 (`leave()` after persist) |
| Complete uses same persist; haptic + snap today | 2 |
| Complete does not write id | 2 |
| Empty complete toast | 2 |
| Complete save failure stays on detail | 2 (`isCompleting = false`) |
| Home does not render JustCompletedCard | 2 |
| Keep card files / Router field | 2 (not deleted) |
| Docs | 3 |

## Type consistency

- `persistVisit(task: TaskItem) -> String?`
- `finishSession(...) -> String?` (unchanged)
- `updateOpenSession(...) -> Bool` (unchanged)
- `hasUnsavedWork` unchanged: timer > 0, pending media, non-empty note, or `openSessionId != nil`
