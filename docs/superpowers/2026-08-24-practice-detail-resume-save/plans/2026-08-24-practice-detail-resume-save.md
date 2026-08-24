# Practice Detail Resume-Save + Keyboard Dismiss Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-entering a practice task restores the latest effective session’s timer and notes; Complete/Back keep updating that same session; only RESET starts a fresh trip; tapping outside the note field dismisses the keyboard.

**Architecture:** Extend `PracticeResumeQuery` to return the resumable `sessionId` / `durationSec` / `noteText` / `startedAt`, honoring a per-task UserDefaults skip id set on RESET. `PracticeTimer.restore` seeds elapsed time. `PracticeDetailView` hydrates once on appear, continues `updateOpenSession` on leave, and uses `@FocusState` for keyboard dismiss.

**Tech Stack:** SwiftUI · SwiftData · Swift Testing · existing `PracticeStore` session APIs · `UserDefaults`

## Global Constraints

- Spec: `docs/superpowers/2026-08-24-practice-detail-resume-save/specs/2026-08-24-practice-detail-resume-save-design.md`
- iOS 18+ · Scheme `foxgita` · cwd `/Users/haizei/work/AI/program/gita/foxgita`
- Copy: `zh-Hans` via `String(localized:)` where new user-facing strings appear (this slice should not need new copy)
- Do not change Schema / migrations
- Do not write `lastCompletedSessionId` on Back or Complete
- Do not set `returnPracticeToToday` on Back
- Do not auto-start metronome or timer on appear (paused restore only)
- Do not open a new session on calendar day change
- Do not edit `project.pbxproj`
- Do not commit unrelated dirty files (`VideoAnalysisView`, `ReviewJobRunner`, `Localizable.xcstrings`, architecture html/png, deleted media-review docs, `.superpowers/sdd/task-5-report.md`)
- Unit test command template:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/<TestClass> test
```

If `iPhone 17` is missing, use any available iPhone simulator from `xcrun simctl list devices available`.

## File map

| File | Responsibility |
|---|---|
| `foxgita/Services/PracticeResumeSkipStore.swift` | Per-task UserDefaults skip session id after RESET |
| `foxgita/Services/PracticeResumeQuery.swift` | Resume target id + duration + note + startedAt; honor skip |
| `foxgita/Services/PracticeTimer.swift` | `restore(elapsedSec:startedAt:)` |
| `foxgita/Features/Practice/PracticeDetailView.swift` | Hydrate on appear; RESET skip; keyboard dismiss |
| `foxgitaTests/PracticeResumeSkipStoreTests.swift` | Skip store round-trip |
| `foxgitaTests/PracticeResumeQueryTests.swift` | Continuable session selection + skip |
| `foxgitaTests/PracticeTimerTests.swift` | Restore then accumulate |
| `foxgitaTests/PracticeStoreTests.swift` | Multi-update then new finish after detach |
| `docs/TECHNICAL.md` | §4.1.3 resume + leave rows |
| Spec header | Flip to Approved + plan path |

YAGNI: no Schema draft flag; no new 「新开一趟」 button; no Record Tab filter rewrite.

---

### Task 1: PracticeResumeSkipStore

**Files:**
- Create: `foxgita/Services/PracticeResumeSkipStore.swift`
- Test: `foxgitaTests/PracticeResumeSkipStoreTests.swift`

**Interfaces:**
- Consumes: `UserDefaults`
- Produces:

```swift
enum PracticeResumeSkipStore {
    static func skippedSessionId(taskId: String, defaults: UserDefaults = .standard) -> String?
    static func skip(taskId: String, sessionId: String, defaults: UserDefaults = .standard)
    static func clear(taskId: String, defaults: UserDefaults = .standard)
}
```

Key format: `"gita.practice.resumeSkip.\(taskId)"`.

- [ ] **Step 1: Write the failing test**

Create `foxgitaTests/PracticeResumeSkipStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import foxgita

struct PracticeResumeSkipStoreTests {
    @Test func skipRoundTripAndClear() {
        let defaults = UserDefaults(suiteName: "PracticeResumeSkipStoreTests.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.suiteName!) }

        #expect(PracticeResumeSkipStore.skippedSessionId(taskId: "t1", defaults: defaults) == nil)
        PracticeResumeSkipStore.skip(taskId: "t1", sessionId: "s1", defaults: defaults)
        #expect(PracticeResumeSkipStore.skippedSessionId(taskId: "t1", defaults: defaults) == "s1")
        PracticeResumeSkipStore.clear(taskId: "t1", defaults: defaults)
        #expect(PracticeResumeSkipStore.skippedSessionId(taskId: "t1", defaults: defaults) == nil)
    }

    @Test func tasksAreIsolated() {
        let defaults = UserDefaults(suiteName: "PracticeResumeSkipStoreTests.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.suiteName!) }

        PracticeResumeSkipStore.skip(taskId: "a", sessionId: "sa", defaults: defaults)
        PracticeResumeSkipStore.skip(taskId: "b", sessionId: "sb", defaults: defaults)
        #expect(PracticeResumeSkipStore.skippedSessionId(taskId: "a", defaults: defaults) == "sa")
        #expect(PracticeResumeSkipStore.skippedSessionId(taskId: "b", defaults: defaults) == "sb")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeResumeSkipStoreTests test
```

Expected: FAIL — `PracticeResumeSkipStore` not found (or similar compile error).

- [ ] **Step 3: Write minimal implementation**

Create `foxgita/Services/PracticeResumeSkipStore.swift`:

```swift
import Foundation

enum PracticeResumeSkipStore {
    private static func key(_ taskId: String) -> String {
        "gita.practice.resumeSkip.\(taskId)"
    }

    static func skippedSessionId(taskId: String, defaults: UserDefaults = .standard) -> String? {
        let value = defaults.string(forKey: key(taskId))
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func skip(taskId: String, sessionId: String, defaults: UserDefaults = .standard) {
        defaults.set(sessionId, forKey: key(taskId))
    }

    static func clear(taskId: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(taskId))
    }
}
```

Xcode picks up new files under `foxgita/` via folder sync / existing group — do **not** edit `project.pbxproj`. If the target does not compile the new file, add it the same way other `Services/*.swift` files are included (synchronized root group).

- [ ] **Step 4: Run tests to verify they pass**

Same `xcodebuild` command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeResumeSkipStore.swift \
  foxgitaTests/PracticeResumeSkipStoreTests.swift
git commit -m "$(cat <<'EOF'
Add per-task resume skip ids for RESET.

EOF
)"
```

---

### Task 2: PracticeResumeQuery continuable fields

**Files:**
- Modify: `foxgita/Services/PracticeResumeQuery.swift`
- Modify: `foxgitaTests/PracticeResumeQueryTests.swift`

**Interfaces:**
- Consumes: `PracticeRecordRules`, `PracticeResumeSkipStore.skippedSessionId`
- Produces: extended `ResumeState` + `resume(...)` filling continuable fields

```swift
struct ResumeState: Equatable {
    var bpm: Int
    var focus: String?
    var hasHistory: Bool
    var openSessionId: String? = nil
    var durationSec: Int = 0
    var noteText: String = ""
    var startedAt: Date? = nil
}

// resume(...) gains:
//   skippedSessionId: String? = nil
// When effective.first exists and its id != skippedSessionId:
//   openSessionId / durationSec / noteText / startedAt from that session
// When effective.first?.id == skippedSessionId:
//   those four stay nil/0/""/nil; bpm/focus/hasHistory still use effective history as today
```

Also extend `ResumeSession` with `startedAt: Date` (required for restore). Update all `ResumeSession(...)` call sites in app + tests.

- [ ] **Step 1: Write the failing tests**

Append to `PracticeResumeQueryTests.swift` (keep existing helpers; add `startedAt` default `endedAt` in helper):

Update helper:

```swift
private func session(
    id: String,
    endedAt: Date,
    bpm: Int,
    note: String = "",
    deletedAt: Date? = nil,
    durationSec: Int = 60,
    recordingCount: Int = 0,
    startedAt: Date? = nil
) -> ResumeSession {
    ResumeSession(
        id: id,
        endedAt: endedAt,
        bpm: bpm,
        noteText: note,
        deletedAt: deletedAt,
        durationSec: durationSec,
        recordingCount: recordingCount,
        startedAt: startedAt ?? endedAt.addingTimeInterval(TimeInterval(-durationSec))
    )
}
```

Add:

```swift
@Test func continuableUsesLatestEffective() {
    let state = PracticeResumeQuery.resume(
        sessions: [
            session(id: "old", endedAt: t0, bpm: 70, note: "旧", durationSec: 30),
            session(id: "new", endedAt: t2, bpm: 88, note: "新笔记", durationSec: 120),
        ],
        recordings: [],
        defaultBpm: 80
    )
    #expect(state.openSessionId == "new")
    #expect(state.durationSec == 120)
    #expect(state.noteText == "新笔记")
    #expect(state.bpm == 88)
}

@Test func skippedLatestIsNotContinuable() {
    let state = PracticeResumeQuery.resume(
        sessions: [
            session(id: "sealed", endedAt: t2, bpm: 90, note: "封", durationSec: 50),
            session(id: "older", endedAt: t0, bpm: 70, note: "更早", durationSec: 20),
        ],
        recordings: [],
        defaultBpm: 80,
        skippedSessionId: "sealed"
    )
    #expect(state.openSessionId == nil)
    #expect(state.durationSec == 0)
    #expect(state.noteText == "")
    #expect(state.hasHistory)
    #expect(state.bpm == 90)
}

@Test func skippedWithNoOtherHistoryStillHidesContinuable() {
    let state = PracticeResumeQuery.resume(
        sessions: [session(id: "only", endedAt: t1, bpm: 66, note: "x", durationSec: 10)],
        recordings: [],
        defaultBpm: 80,
        skippedSessionId: "only"
    )
    #expect(state.openSessionId == nil)
    #expect(state.durationSec == 0)
    #expect(state.hasHistory)
}
```

Update `noSessionUsesDefaultAndHidesLine` expectation if needed — defaults on new fields keep `ResumeState(bpm:focus:hasHistory:)` equality working.

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeResumeQueryTests test
```

Expected: FAIL — missing parameters / fields.

- [ ] **Step 3: Implement ResumeSession + ResumeState + resume**

In `PracticeResumeQuery.swift`:

1. Add `var startedAt: Date` to `ResumeSession`.
2. Extend `ResumeState` with `openSessionId`, `durationSec`, `noteText`, `startedAt` (defaults as above).
3. Change signature:

```swift
static func resume(
    sessions: [ResumeSession],
    recordings: [ResumeRecording],
    defaultBpm: Int,
    skippedSessionId: String? = nil
) -> ResumeState
```

4. After computing `effective` as today, set:

```swift
let newest = effective.first
let canContinue: Bool = {
    guard let newest else { return false }
    if let skippedSessionId, newest.id == skippedSessionId { return false }
    return true
}()

return ResumeState(
    bpm: bpm,
    focus: focus,
    hasHistory: hasHistory,
    openSessionId: canContinue ? newest?.id : nil,
    durationSec: canContinue ? (newest?.durationSec ?? 0) : 0,
    noteText: canContinue ? (newest?.noteText ?? "") : "",
    startedAt: canContinue ? newest?.startedAt : nil
)
```

Keep existing bpm/focus selection unchanged (still based on full `effective`, including skipped newest).

- [ ] **Step 4: Fix call site in PracticeDetailView mapping**

In `PracticeDetailView.resumeState`, map `startedAt: session.startedAt` into `ResumeSession`, and pass:

```swift
skippedSessionId: PracticeResumeSkipStore.skippedSessionId(taskId: taskId)
```

(Do not hydrate UI yet — Task 4.)

- [ ] **Step 5: Run tests**

Same command as Step 2. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add foxgita/Services/PracticeResumeQuery.swift \
  foxgita/Features/Practice/PracticeDetailView.swift \
  foxgitaTests/PracticeResumeQueryTests.swift
git commit -m "$(cat <<'EOF'
Expose continuable session fields from PracticeResumeQuery.

EOF
)"
```

---

### Task 3: PracticeTimer.restore

**Files:**
- Modify: `foxgita/Services/PracticeTimer.swift`
- Modify: `foxgitaTests/PracticeTimerTests.swift`

**Interfaces:**
- Consumes: existing timer internals
- Produces:

```swift
func restore(elapsedSec: Int, startedAt: Date?)
```

Semantics: pause/stop ticker; `accumulated = TimeInterval(max(0, elapsedSec))`; `self.elapsedSec = max(0, elapsedSec)`; `self.startedAt = startedAt` if `elapsedSec > 0`, else `nil` when elapsed is 0; if `elapsedSec > 0` and `startedAt == nil`, set `startedAt = now().addingTimeInterval(-TimeInterval(elapsedSec))`; `isRunning = false`; `resumedAt = nil`.

- [ ] **Step 1: Write the failing test**

Append to `PracticeTimerTests.swift`:

```swift
@Test func restoreSeedsElapsedAndAllowsFurtherAccumulation() {
    let (timer, clock) = makeTimer()
    let begin = clock.now.addingTimeInterval(-90)
    timer.restore(elapsedSec: 90, startedAt: begin)
    #expect(timer.elapsedSec == 90)
    #expect(timer.startedAt == begin)
    #expect(timer.isRunning == false)
    timer.start()
    clock.advance(30)
    timer.pause()
    #expect(timer.elapsedSec == 120)
    #expect(timer.startedAt == begin)
}

@Test func restoreZeroClearsStartedAt() {
    let (timer, _) = makeTimer()
    timer.restore(elapsedSec: 0, startedAt: Date())
    #expect(timer.elapsedSec == 0)
    #expect(timer.startedAt == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeTimerTests test
```

Expected: FAIL — `restore` missing.

- [ ] **Step 3: Implement restore**

In `PracticeTimer.swift` add:

```swift
func restore(elapsedSec: Int, startedAt: Date?) {
    stopTicker()
    isRunning = false
    resumedAt = nil
    let clamped = max(0, elapsedSec)
    accumulated = TimeInterval(clamped)
    self.elapsedSec = clamped
    if clamped == 0 {
        self.startedAt = nil
    } else {
        self.startedAt = startedAt ?? now().addingTimeInterval(-TimeInterval(clamped))
    }
}
```

- [ ] **Step 4: Run tests**

Same command. Expected: PASS (including existing tests).

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeTimer.swift foxgitaTests/PracticeTimerTests.swift
git commit -m "$(cat <<'EOF'
Allow PracticeTimer to restore a saved elapsed duration.

EOF
)"
```

---

### Task 4: PracticeDetailView hydrate + RESET + clear skip on new session

**Files:**
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift`
- Modify: `foxgitaTests/PracticeStoreTests.swift` (detach + finish creates second session)

**Interfaces:**
- Consumes: `resumeState.openSessionId/durationSec/noteText/startedAt`, `PracticeTimer.restore`, `PracticeResumeSkipStore`, existing `persistVisit`
- Produces: one-shot hydrate on appear; RESET persists then skips; `persistVisit` clears skip when it creates/binds a session id other than the skipped one

- [ ] **Step 1: Write Store regression test (failing only if logic wrong later; add now)**

Append to `PracticeStoreTests.swift`:

```swift
@Test func updateThenFinishWithoutOpenIdCreatesSecondSession() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedActive(into: repo)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let clip = try writeClip(id: "a")
    defer { RecordingStore.delete(fileName: clip.fileName) }
    let sid = try #require(store.beginOpenSession(
        taskId: "warm", steps: [], note: "一",
        startedAt: start, endedAt: start, durationSec: 10, bpm: 80,
        clip: clip
    ))
    #expect(store.updateOpenSession(
        sessionId: sid, steps: [], note: "一",
        endedAt: start.addingTimeInterval(10), durationSec: 10, bpm: 80
    ))
    let second = store.finishSession(
        taskId: "warm", steps: [], note: "二",
        startedAt: start.addingTimeInterval(100),
        endedAt: start.addingTimeInterval(130),
        durationSec: 30, bpm: 80, recordings: []
    )
    #expect(second != nil)
    #expect(second != sid)
    #expect(try repo.sessions().count == 2)
}
```

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests/updateThenFinishWithoutOpenIdCreatesSecondSession test
```

Expected: PASS already (documents RESET → new finish behavior). If it fails, fix Store before UI — should not be needed.

- [ ] **Step 2: Add hydrate + RESET wiring in PracticeDetailView**

Add state:

```swift
@State private var didRestoreSession = false
```

Replace `onAppear` body with:

```swift
.onAppear {
    guard let task else { return }
    if !didRestoreSession {
        didRestoreSession = true
        metronome.setBpm(resumeState.bpm)
        if let sid = resumeState.openSessionId {
            openSessionId = sid
            noteText = resumeState.noteText
            practiceTimer.restore(
                elapsedSec: resumeState.durationSec,
                startedAt: resumeState.startedAt
            )
        } else {
            metronome.setBpm(resumeState.bpm)
        }
        steps = task.steps.isEmpty ? [String(localized: "新步骤")] : task.steps
    }
    AudioSessionCoordinator.shared.onInterruption = { [metronome, practiceTimer, recorder] in
        metronome.stop()
        practiceTimer.pause()
        if recorder.isRecording { recorder.stop(label: task.title) }
    }
}
```

(Keep a single `metronome.setBpm(resumeState.bpm)` — simplify to one call before the `if let sid`.)

Replace RESET button action:

```swift
Button("RESET") {
    resetTrip(task)
}
```

Add:

```swift
private func resetTrip(_ task: TaskItem) {
    practiceTimer.pause()
    metronome.stop()
    if recorder.isRecording { recorder.stop(label: task.title) }
    let sealedId = persistVisit(task: task) ?? openSessionId ?? resumeState.openSessionId
    if let sealedId {
        PracticeResumeSkipStore.skip(taskId: task.id, sessionId: sealedId)
    }
    practiceTimer.reset()
    noteText = ""
    openSessionId = nil
}
```

In `persistVisit`, after successfully setting `openSessionId = savedId` (both update and finish paths), clear skip when the bound id is not the skipped one:

```swift
private func clearSkipIfResumed(taskId: String, sessionId: String) {
    if PracticeResumeSkipStore.skippedSessionId(taskId: taskId) != sessionId {
        PracticeResumeSkipStore.clear(taskId: taskId)
    }
}
```

Call `clearSkipIfResumed(taskId: task.id, sessionId: sid)` whenever `openSessionId` is assigned from persist/begin/append success.

Also call clear when `persistVisit` updates an existing open session whose id ≠ skip (normal resume path):

```swift
if let open = openSessionId {
    saveOpenSession(task: task)
    clearSkipIfResumed(taskId: task.id, sessionId: open)
    return open
}
```

Wait — if we resumed a non-skipped session, skip should already be nil or point at an older sealed id. Clearing when `skipped != sessionId` is correct: after RESET skip=S1, new finish returns S2, `S1 != S2` → clear. If somehow open==S1 while skip==S1, do not clear.

- [ ] **Step 3: Compile detail + store tests**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeResumeQueryTests \
  -only-testing:foxgitaTests/PracticeTimerTests \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

Expected: PASS / build succeeds.

- [ ] **Step 4: Commit**

```bash
git add foxgita/Features/Practice/PracticeDetailView.swift \
  foxgitaTests/PracticeStoreTests.swift
git commit -m "$(cat <<'EOF'
Restore open practice sessions on detail appear and seal on RESET.

EOF
)"
```

---

### Task 5: Keyboard dismiss on note field

**Files:**
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift`

**Interfaces:**
- Consumes: SwiftUI `@FocusState`
- Produces: note field focus binding; dismiss on scroll / chrome taps / leaving note mode

- [ ] **Step 1: Add FocusState and wire TextField**

Near other `@State`:

```swift
@FocusState private var noteFocused: Bool
```

On the note `TextField`:

```swift
TextField("记录一点感受…", text: $noteText, axis: .vertical)
    .font(.system(size: 14))
    .lineLimit(3...6)
    .focused($noteFocused)
```

On the `ScrollView` that wraps the form (the one containing metronome/timer/steps):

```swift
ScrollView {
    ...
}
.scrollDismissesKeyboard(.interactively)
.simultaneousGesture(
    TapGesture().onEnded { noteFocused = false }
)
```

Use `simultaneousGesture` so buttons still receive taps. Additionally set `noteFocused = false` at the start of:

- `requestExit`
- `complete`
- `resetTrip`
- `togglePlay`
- tool mode switches in `toolsRow` (audio / note / video handlers)
- BPM ± buttons if they exist as actions

When switching away from note mode:

```swift
toolMode = .audio // or .video
noteFocused = false
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeTimerTests test
```

Expected: build + tests PASS.

- [ ] **Step 3: Commit**

```bash
git add foxgita/Features/Practice/PracticeDetailView.swift
git commit -m "$(cat <<'EOF'
Dismiss the practice note keyboard on outside interaction.

EOF
)"
```

---

### Task 6: Docs + spec header

**Files:**
- Modify: `docs/TECHNICAL.md` (§4.1 leave table + §4.1.3)
- Modify: `docs/superpowers/2026-08-24-practice-detail-resume-save/specs/2026-08-24-practice-detail-resume-save-design.md` header

- [ ] **Step 1: Update TECHNICAL.md**

Replace §4.1.3 paragraph with:

```markdown
#### 4.1.3 工作台进入恢复

`PracticeDetailView.onAppear` 用 `PracticeResumeQuery.resume`（并读 `PracticeResumeSkipStore`）：

- 可续 session：该任务最新有效 session，且 id 未被 RESET 跳过 → 绑定 `openSessionId`，计时恢复 `durationSec`（暂停），笔记框预填 `noteText`。
- BPM：最近有效 session，否则 `task.defaultBpm`。
- 焦点行：优先 `reviewNextAction`，否则上次笔记首行；无历史不渲染。
- RESET：先 `persistVisit`，对该 session id 写入跳过键，再清空计时/笔记/`openSessionId`；随后活动 `finishSession` 新建并在成功后清除跳过键。
```

In the §4.1 scenario table, ensure rows say Complete/Back update the continuable session (same visit fields), and mention keyboard dismiss briefly under §4.1.2 tools note row if natural.

- [ ] **Step 2: Flip spec header**

```markdown
**状态：** Approved — implementation plan in ../plans/2026-08-24-practice-detail-resume-save.md
```

- [ ] **Step 3: Commit**

```bash
git add docs/TECHNICAL.md \
  docs/superpowers/2026-08-24-practice-detail-resume-save/specs/2026-08-24-practice-detail-resume-save-design.md
git commit -m "$(cat <<'EOF'
Document practice detail resume-save behavior in TECHNICAL.

EOF
)"
```

---

### Task 7: Manual acceptance checklist (no code)

- [ ] **Step 1: Run through spec §7.2 on simulator**

1. Timer + note → Complete → Record detail shows values → re-enter: timer + note restored; Start accumulates.
2. Same with Back.
3. Resume then Complete again → still one continuable session (session count for that trip does not duplicate until RESET).
4. RESET → empty UI → practice + Complete → Record keeps pre-RESET session and a new one.
5. Focus note → tap chrome / drag scroll / switch to 录音 → keyboard dismisses.

- [ ] **Step 2: Note any failure in the PR/commit message body; do not “fix” by weakening the spec without user approval**

---

## Plan self-review

| Spec requirement | Task |
|---|---|
| Continuable latest effective session | Task 2 |
| Enter restores timer + notes | Task 3 + 4 |
| Complete/Back same persist, Complete not sealing | Task 4 (existing `persistVisit` / `complete`) |
| RESET seals via skip + new session | Task 1 + 4 |
| Keyboard dismiss | Task 5 |
| Kill-app restore via DB | Task 2 + 4 (`didRestore` + query) |
| Tests for query / timer / store | Tasks 1–4 |
| TECHNICAL + approved spec | Task 6 |
| Manual acceptance | Task 7 |

No TBD placeholders. `ResumeState` field names consistent across Tasks 2–4. Skip store API consistent across Tasks 1–4.
