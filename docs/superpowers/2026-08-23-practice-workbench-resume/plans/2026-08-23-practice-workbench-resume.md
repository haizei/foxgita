# Practice Workbench Resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-entering a task resumes last effective BPM and a one-line focus, clips play on the workbench, and an effective Complete hands the saved session id to today's "刚刚完成" card.

**Architecture:** Extract `PracticeResumeQuery` and `JustCompletedCopy` as pure functions. `PracticeStore.finishSession` returns the new session id and both finish/update write `task.defaultBpm`. `AppRouter.lastCompletedSessionId` is set only on Complete. `PracticeDetailView` binds resume + playback; `PracticeView` binds the card. No schema change.

**Tech Stack:** SwiftUI · SwiftData · AVFoundation · AVKit · Swift Testing · existing `AudioPlayerService` / `PracticeClipQuery` / `PracticeRecordRules`

## Global Constraints

- Spec: `docs/superpowers/2026-08-23-practice-workbench-resume/specs/2026-08-23-practice-workbench-resume-design.md`
- Product: `design-boards/产品PRD/练习工作台/2026-08-23-Gita-练习工作台-上次状态与当场回放-PRD.md` (parent gita repo)
- iOS 18+ · Scheme `foxgita` · cwd `/Users/haizei/work/AI/program/gita/foxgita`
- Copy: `zh-Hans` via `String(localized:)`
- Do not change Schema
- Do not ask "use last BPM", do not add "restart from slow"
- Do not prefill the note field
- Do not write `lastCompletedSessionId` on Back
- Do not guess "latest session" on the home card
- Do not play video audio-only (no layer)
- Do not edit `project.pbxproj` (synchronized root groups)
- Unit test command:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

If `iPhone 17` is missing, use any available iPhone simulator from `xcrun simctl list devices available`.

## File map

| File | Responsibility |
|---|---|
| `foxgita/Services/PracticeResumeQuery.swift` | Session/recording descriptors, BPM, focus, focus line |
| `foxgita/Services/JustCompletedCopy.swift` | Minutes label + note/audio/video summary |
| `foxgita/Services/PracticeStore.swift` | Write `defaultBpm`; `finishSession` → `String?` |
| `foxgita/App/AppRouter.swift` | `lastCompletedSessionId` + `clearJustCompleted()` |
| `foxgita/App/MainTabView.swift` | Leaving `.practice` clears the card |
| `foxgita/Features/Practice/PracticeDetailView.swift` | Resume on appear, play, Complete writes id |
| `foxgita/Features/Practice/SystemVideoPlayer.swift` | Full-screen `AVPlayerViewController` |
| `foxgita/Features/Practice/PracticeView.swift` | `JustCompletedCard` above today's task list |
| `foxgita/Features/Practice/JustCompletedCard.swift` | Card UI |
| `foxgita/Localizable.xcstrings` | New strings (Xcode will merge on build; add keys used) |
| `docs/TECHNICAL.md` | Enter-resume + Complete session id |
| `docs/TEST_PLAN_CLI.md` | New suites |
| `foxgitaTests/PracticeResumeQueryTests.swift` | Resume / focus / clamp |
| `foxgitaTests/JustCompletedCopyTests.swift` | Minutes + summary |
| `foxgitaTests/PracticeStoreTests.swift` | Writeback + return id |
| `foxgitaTests/AppRouterTests.swift` | Clear helper |

YAGNI: no new Schema, no session-level record route, no in-card video preview, no UserDefaults for the card.

---

### Task 1: PracticeResumeQuery

**Files:**
- Create: `foxgita/Services/PracticeResumeQuery.swift`
- Test: `foxgitaTests/PracticeResumeQueryTests.swift`

**Interfaces:**
- Consumes: `PracticeRecordRules.isEffective(durationSec:noteText:recordingCount:)`
- Produces:
  - `struct ResumeSession: Equatable` — `id: String`, `endedAt: Date`, `bpm: Int`, `noteText: String`, `deletedAt: Date?`, `durationSec: Int`, `recordingCount: Int`
  - `struct ResumeRecording: Equatable` — `id: String`, `createdAt: Date`, `deletedAt: Date?`, `reviewNextAction: String`
  - `struct ResumeState: Equatable` — `bpm: Int`, `focus: String?`, `hasHistory: Bool`
  - `enum PracticeResumeQuery` with
    - `static func resume(sessions: [ResumeSession], recordings: [ResumeRecording], defaultBpm: Int) -> ResumeState`
    - `static func focusLine(state: ResumeState) -> String?`

- [ ] **Step 1: Write the failing tests**

Create `foxgitaTests/PracticeResumeQueryTests.swift`:

```swift
import Foundation
import Testing
@testable import foxgita

struct PracticeResumeQueryTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_100)
    private let t2 = Date(timeIntervalSince1970: 1_700_000_200)

    private func session(
        id: String,
        endedAt: Date,
        bpm: Int,
        note: String = "",
        deletedAt: Date? = nil,
        durationSec: Int = 60,
        recordingCount: Int = 0
    ) -> ResumeSession {
        ResumeSession(
            id: id, endedAt: endedAt, bpm: bpm, noteText: note,
            deletedAt: deletedAt, durationSec: durationSec, recordingCount: recordingCount
        )
    }

    @Test func noSessionUsesDefaultAndHidesLine() {
        let state = PracticeResumeQuery.resume(sessions: [], recordings: [], defaultBpm: 80)
        #expect(state == ResumeState(bpm: 80, focus: nil, hasHistory: false))
        #expect(PracticeResumeQuery.focusLine(state: state) == nil)
    }

    @Test func lastEffectiveBpmBeatsDefault() {
        let state = PracticeResumeQuery.resume(
            sessions: [session(id: "s", endedAt: t1, bpm: 63)],
            recordings: [],
            defaultBpm: 80
        )
        #expect(state.bpm == 63)
        #expect(state.hasHistory)
        #expect(PracticeResumeQuery.focusLine(state: state) == "上次练到 63 BPM")
    }

    @Test func skipsInvalidAndDeletedSessions() {
        let state = PracticeResumeQuery.resume(
            sessions: [
                session(id: "empty", endedAt: t2, bpm: 99, durationSec: 0, recordingCount: 0),
                session(id: "gone", endedAt: t2, bpm: 50, deletedAt: t2),
                session(id: "old", endedAt: t0, bpm: 70),
            ],
            recordings: [],
            defaultBpm: 80
        )
        #expect(state.bpm == 70)
    }

    @Test func nextActionBeatsNoteAndUsesNewestRecording() {
        let state = PracticeResumeQuery.resume(
            sessions: [session(id: "s", endedAt: t1, bpm: 60, note: "食指闷音")],
            recordings: [
                ResumeRecording(id: "a", createdAt: t0, deletedAt: nil, reviewNextAction: "旧建议"),
                ResumeRecording(id: "b", createdAt: t2, deletedAt: nil, reviewNextAction: "下次慢半拍"),
                ResumeRecording(id: "c", createdAt: t2, deletedAt: t2, reviewNextAction: "已删"),
            ],
            defaultBpm: 80
        )
        #expect(state.focus == "下次慢半拍")
        #expect(PracticeResumeQuery.focusLine(state: state) == "上次 60 BPM · 下次慢半拍")
    }

    @Test func noteFirstLineTruncatesAt28() {
        let long = String(repeating: "啊", count: 30)
        let state = PracticeResumeQuery.resume(
            sessions: [session(id: "s", endedAt: t1, bpm: 72, note: "第一行\n第二行")],
            recordings: [],
            defaultBpm: 80
        )
        #expect(state.focus == "第一行")

        let longState = PracticeResumeQuery.resume(
            sessions: [session(id: "s", endedAt: t1, bpm: 72, note: long)],
            recordings: [],
            defaultBpm: 80
        )
        #expect(longState.focus == String(repeating: "啊", count: 28) + "…")
    }

    @Test func clampsBpm() {
        #expect(
            PracticeResumeQuery.resume(
                sessions: [session(id: "s", endedAt: t1, bpm: 39)],
                recordings: [],
                defaultBpm: 80
            ).bpm == 40
        )
        #expect(
            PracticeResumeQuery.resume(
                sessions: [session(id: "s", endedAt: t1, bpm: 201)],
                recordings: [],
                defaultBpm: 80
            ).bpm == 200
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeResumeQueryTests test
```

Expected: FAIL — `PracticeResumeQuery` / `ResumeSession` not found.

- [ ] **Step 3: Write minimal implementation**

Create `foxgita/Services/PracticeResumeQuery.swift`:

```swift
import Foundation

struct ResumeSession: Equatable {
    var id: String
    var endedAt: Date
    var bpm: Int
    var noteText: String
    var deletedAt: Date?
    var durationSec: Int
    var recordingCount: Int
}

struct ResumeRecording: Equatable {
    var id: String
    var createdAt: Date
    var deletedAt: Date?
    var reviewNextAction: String
}

struct ResumeState: Equatable {
    var bpm: Int
    var focus: String?
    var hasHistory: Bool
}

enum PracticeResumeQuery {
    static func resume(
        sessions: [ResumeSession],
        recordings: [ResumeRecording],
        defaultBpm: Int
    ) -> ResumeState {
        let live = sessions.filter { $0.deletedAt == nil }
        let effective = live.filter {
            PracticeRecordRules.isEffective(
                durationSec: $0.durationSec,
                noteText: $0.noteText,
                recordingCount: $0.recordingCount
            )
        }
        .sorted { $0.endedAt > $1.endedAt }

        let hasHistory = !effective.isEmpty
        let rawBpm = effective.first?.bpm ?? defaultBpm
        let bpm = min(200, max(40, rawBpm))

        let nextAction = recordings
            .filter { $0.deletedAt == nil }
            .filter { !$0.reviewNextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.createdAt > $1.createdAt }
            .first?
            .reviewNextAction

        let focus: String?
        if let nextAction {
            focus = nextAction
        } else if let note = effective.first?.noteText {
            focus = Self.notePreview(note)
        } else {
            focus = nil
        }

        return ResumeState(bpm: bpm, focus: focus, hasHistory: hasHistory)
    }

    static func focusLine(state: ResumeState) -> String? {
        guard state.hasHistory else { return nil }
        if let focus = state.focus, !focus.isEmpty {
            return String(localized: "上次 \(state.bpm) BPM · \(focus)")
        }
        return String(localized: "上次练到 \(state.bpm) BPM")
    }

    private static func notePreview(_ note: String) -> String? {
        let first = note
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !first.isEmpty else { return nil }
        if first.count > 28 {
            return String(first.prefix(28)) + "…"
        }
        return first
    }
}
```

`focusLine` tests compare the interpolated Chinese string. If `String(localized:)` in unit tests returns the key instead of the interpolation, switch `focusLine` to the same literal format (the catalog source is `zh-Hans`) — do **not** change the user-visible wording.

- [ ] **Step 4: Run tests to verify they pass**

Same `xcodebuild` as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeResumeQuery.swift foxgitaTests/PracticeResumeQueryTests.swift
git commit -m "Add PracticeResumeQuery for last BPM and focus."
```

---

### Task 2: JustCompletedCopy

**Files:**
- Create: `foxgita/Services/JustCompletedCopy.swift`
- Test: `foxgitaTests/JustCompletedCopyTests.swift`

**Interfaces:**
- Consumes: `MediaReviewMedia.isVideo(fileName:)`
- Produces:
  - `struct JustCompletedInput: Equatable` — `taskTitle: String`, `durationSec: Int`, `hasNote: Bool`, `fileNames: [String]`
  - `enum JustCompletedCopy` with
    - `static func minutesLabel(durationSec: Int, hasNote: Bool, mediaCount: Int) -> String`
    - `static func summary(hasNote: Bool, fileNames: [String]) -> String`
    - `static func mediaCount(fileNames: [String]) -> Int` (audio + video files)

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import foxgita

struct JustCompletedCopyTests {
    @Test func minutesFromDuration() {
        #expect(JustCompletedCopy.minutesLabel(durationSec: 60, hasNote: false, mediaCount: 0) == "1 分钟")
        #expect(JustCompletedCopy.minutesLabel(durationSec: 61, hasNote: false, mediaCount: 0) == "2 分钟")
        #expect(JustCompletedCopy.minutesLabel(durationSec: 0, hasNote: true, mediaCount: 0) == "不足 1 分钟")
        #expect(JustCompletedCopy.minutesLabel(durationSec: 0, hasNote: false, mediaCount: 1) == "不足 1 分钟")
    }

    @Test func summaryOmitsZeroKinds() {
        #expect(JustCompletedCopy.summary(hasNote: true, fileNames: ["a.m4a", "b.mov"]) == "笔记 · 录音 1 · 视频 1")
        #expect(JustCompletedCopy.summary(hasNote: false, fileNames: ["a.m4a"]) == "录音 1")
        #expect(JustCompletedCopy.summary(hasNote: true, fileNames: []) == "笔记")
        #expect(JustCompletedCopy.summary(hasNote: false, fileNames: []) == "")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/JustCompletedCopyTests test
```

Expected: FAIL — `JustCompletedCopy` not found.

- [ ] **Step 3: Write minimal implementation**

Create `foxgita/Services/JustCompletedCopy.swift`:

```swift
import Foundation

enum JustCompletedCopy {
    static func minutesLabel(durationSec: Int, hasNote: Bool, mediaCount: Int) -> String {
        if durationSec <= 0, hasNote || mediaCount > 0 {
            return String(localized: "不足 1 分钟")
        }
        let minutes = Int(ceil(Double(max(durationSec, 0)) / 60.0))
        return String(localized: "\(minutes) 分钟")
    }

    static func summary(hasNote: Bool, fileNames: [String]) -> String {
        var parts: [String] = []
        if hasNote { parts.append(String(localized: "笔记")) }
        let audio = fileNames.filter { !MediaReviewMedia.isVideo(fileName: $0) }.count
        let video = fileNames.filter { MediaReviewMedia.isVideo(fileName: $0) }.count
        if audio > 0 { parts.append(String(localized: "录音 \(audio)")) }
        if video > 0 { parts.append(String(localized: "视频 \(video)")) }
        return parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/JustCompletedCopy.swift foxgitaTests/JustCompletedCopyTests.swift
git commit -m "Add JustCompletedCopy for the home result card."
```

---

### Task 3: Store writes defaultBpm and returns session id

**Files:**
- Modify: `foxgita/Services/PracticeStore.swift` (`finishSession` ~249-310, `updateOpenSession` ~375-407)
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift` (`complete` uses `String?` instead of `Bool`)
- Modify: `foxgitaTests/PracticeStoreTests.swift`
- Modify: `foxgitaTests/ReviewJobRunnerTests.swift` and `foxgitaTests/AICandidateSyncTests.swift` if they compare `finishSession` to `false` / treat it as `Bool`

**Interfaces:**
- Consumes: Task 1 clamp rule `min(200, max(40, bpm))`
- Produces: `@discardableResult func finishSession(...) -> String?` (id on success, `nil` on failure). `updateOpenSession` still `Bool`, but writes `task.defaultBpm`. `beginOpenSession` still does **not** write `defaultBpm`.

- [ ] **Step 1: Write the failing tests**

Add to `PracticeStoreTests.swift` (keep existing helpers). Change `finishSessionPersistsStepsAndRecordingRows` to:

```swift
let id = store.finishSession(
    taskId: "warm",
    steps: ["热身", "主练"],
    note: "感觉不错",
    startedAt: start,
    endedAt: end,
    durationSec: 300,
    bpm: 72,
    recordings: []
)
#expect(id != nil)
#expect(try repo.task(id: "warm")?.defaultBpm == 72)
#expect(try repo.sessions()[0].id == id)
```

Add:

```swift
@Test func beginOpenSessionDoesNotWriteDefaultBpm() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedActive(into: repo)
    let now = Date()
    let clip = try writeClip(id: "a")
    defer { RecordingStore.delete(fileName: clip.fileName) }
    #expect(try repo.task(id: "warm")?.defaultBpm == 80)
    _ = try #require(store.beginOpenSession(
        taskId: "warm", steps: [], note: "",
        startedAt: now, endedAt: now, durationSec: 0, bpm: 95,
        clip: clip
    ))
    #expect(try repo.task(id: "warm")?.defaultBpm == 80)
}

@Test func updateOpenSessionWritesDefaultBpm() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedActive(into: repo)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let clip = try writeClip(id: "a")
    defer { RecordingStore.delete(fileName: clip.fileName) }
    let sid = try #require(store.beginOpenSession(
        taskId: "warm", steps: ["旧"], note: "",
        startedAt: start, endedAt: start, durationSec: 0, bpm: 80,
        clip: clip
    ))
    #expect(store.updateOpenSession(
        sessionId: sid, steps: ["新"], note: "记",
        endedAt: start.addingTimeInterval(90), durationSec: 90, bpm: 88
    ))
    #expect(try repo.task(id: "warm")?.defaultBpm == 88)
}

@Test func finishSessionRejectsEmptyDoesNotWriteBpm() throws {
    let (store, repo, _) = makeStore(seeded: true)
    try seedActive(into: repo)
    let now = Date()
    #expect(
        store.finishSession(
            taskId: "warm", steps: [], note: "",
            startedAt: now, endedAt: now, durationSec: 0, bpm: 120, recordings: []
        ) == nil
    )
    #expect(try repo.task(id: "warm")?.defaultBpm == 80)
}
```

Update every existing `finishSession(...) == false` to `== nil`, and `#expect(store.finishSession(...))` success cases to `!= nil`.

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

Expected: FAIL — `finishSession` still returns `Bool`, or `defaultBpm` stays 80.

- [ ] **Step 3: Write minimal implementation**

In `finishSession`, change the signature to `-> String?` and the produce block to:

```swift
return produce {
    task.steps = steps
    task.defaultBpm = min(200, max(40, bpm))
    task.touch()
    try repository.add(session)
    try repository.save()
    return session.id
}
```

All early `return false` become `return nil`. Update `PracticeDetailView.complete` so the `Bool` path compiles. Do **not** write `lastCompletedSessionId` yet (Task 7):

```swift
let savedId = store.finishSession(
    taskId: task.id, steps: steps, note: noteText,
    startedAt: practiceTimer.startedAt ?? end.addingTimeInterval(TimeInterval(-elapsed)),
    endedAt: end, durationSec: elapsed, bpm: metronome.bpm, recordings: clips
)
guard savedId != nil else {
    isCompleting = false
    return
}
Haptics.success()
router.returnPracticeToToday = true
router.practicePath.removeAll()
```

In `updateOpenSession` produce block, add `task.defaultBpm = min(200, max(40, bpm))` next to `task.steps = steps`.

Do **not** write `defaultBpm` in `beginOpenSession`.

Fix `ReviewJobRunnerTests` / `AICandidateSyncTests` the same way (`== nil` / `!= nil`).

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

Expected: PASS. Then run full `foxgitaTests` if other files still treat `finishSession` as `Bool`.

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeStore.swift foxgita/Features/Practice/PracticeDetailView.swift \
  foxgitaTests/PracticeStoreTests.swift foxgitaTests/ReviewJobRunnerTests.swift \
  foxgitaTests/AICandidateSyncTests.swift
git commit -m "Write last BPM onto the task and return the finished session id."
```

---

### Task 4: AppRouter session id

**Files:**
- Modify: `foxgita/App/AppRouter.swift`
- Modify: `foxgita/App/MainTabView.swift`
- Create: `foxgitaTests/AppRouterTests.swift`

**Interfaces:**
- Consumes: nothing from Tasks 1–3 except the id string
- Produces:
  - `var lastCompletedSessionId: String?`
  - `func clearJustCompleted()`
  - Leaving `selectedTab` from `.practice` to any other tab calls `clearJustCompleted()`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import foxgita

struct AppRouterTests {
    @Test func clearJustCompletedDropsSessionId() {
        let router = AppRouter()
        router.lastCompletedSessionId = "s1"
        router.clearJustCompleted()
        #expect(router.lastCompletedSessionId == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/AppRouterTests test
```

Expected: FAIL — property / method missing.

- [ ] **Step 3: Write minimal implementation**

Append to `AppRouter`:

```swift
/// Set only after an effective Complete. Never persist. Never infer "latest session".
var lastCompletedSessionId: String?

func clearJustCompleted() {
    lastCompletedSessionId = nil
}
```

In `MainTabView.body`, after `.tint`:

```swift
.onChange(of: router.selectedTab) { old, new in
    if old == .practice, new != .practice {
        router.clearJustCompleted()
    }
}
```

Do not rely on `PracticeView.onDisappear` — Tab views stay alive.

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add foxgita/App/AppRouter.swift foxgita/App/MainTabView.swift foxgitaTests/AppRouterTests.swift
git commit -m "Keep just-completed session id only on the practice tab."
```

---

### Task 5: Detail resume + focus line

**Files:**
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift` (`onAppear` ~97-106, `content` meta block ~201-234)

**Interfaces:**
- Consumes: `PracticeResumeQuery.resume` / `focusLine` from Task 1
- Produces: On appear, metronome BPM = resume.bpm; optional one-line focus above the metronome; `noteText` stays `""`

- [ ] **Step 1: Map sessions to descriptors in the view**

Add a private helper on `PracticeDetailView` (no new type in the view file beyond the helper):

```swift
private var resumeState: ResumeState {
    let sessionRows = sessions.map { session in
        ResumeSession(
            id: session.id,
            endedAt: session.endedAt,
            bpm: session.bpm,
            noteText: session.noteText,
            deletedAt: session.deletedAt,
            durationSec: session.durationSec,
            recordingCount: session.recordings.filter { $0.deletedAt == nil }.count
        )
    }
    let recordingRows = sessions.flatMap(\.recordings).map {
        ResumeRecording(
            id: $0.id,
            createdAt: $0.createdAt,
            deletedAt: $0.deletedAt,
            reviewNextAction: $0.reviewNextAction
        )
    }
    return PracticeResumeQuery.resume(
        sessions: sessionRows,
        recordings: recordingRows,
        defaultBpm: task?.defaultBpm ?? 80
    )
}
```

- [ ] **Step 2: Bind onAppear and the focus row**

Replace `metronome.setBpm(task.defaultBpm)` with `metronome.setBpm(resumeState.bpm)`. Leave `noteText` uninitialized / `""`.

In `content(_ task:)`, after the existing subtitle / AI block and **before** `metronomeCard`, insert:

```swift
if let line = PracticeResumeQuery.focusLine(state: resumeState) {
    Text(line)
        .font(GitaFont.caption())
        .foregroundStyle(GitaTheme.textSecondary)
        .accessibilityLabel(Text(line))
}
```

Do not merge this into the AI "已从图片生成" card. Do not write `noteText = session.noteText`.

- [ ] **Step 3: Manual compile check**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeResumeQueryTests test
```

Expected: PASS (query tests still pass) and the app target compiles.

- [ ] **Step 4: Commit**

```bash
git add foxgita/Features/Practice/PracticeDetailView.swift
git commit -m "Resume last BPM and show a one-line focus on the workbench."
```

There is no UI unit test for this row. Verify by reading: `onAppear` must not call `setBpm(task.defaultBpm)` anymore.

---

### Task 6: In-page playback

**Files:**
- Create: `foxgita/Features/Practice/SystemVideoPlayer.swift`
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift` (`clipCard` ~493-530, `toolsRow`, `complete` / `onDisappear`)

**Interfaces:**
- Consumes: `AudioPlayerService.toggle(url:id:)`, `RecordingStore.fileExists`, `MediaReviewMedia.isVideo`
- Produces: Play control on each clip card; audio uses `AudioPlayerService`; video presents `SystemVideoPlayer`; missing file toasts existing copy

- [ ] **Step 1: Add the video presenter**

Create `foxgita/Features/Practice/SystemVideoPlayer.swift`:

```swift
import AVKit
import SwiftUI

struct SystemVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    var onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        controller.delegate = context.coordinator
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player?.pause()
        controller.player = nil
        AudioSessionCoordinator.shared.release(.playback)
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            coordinator.animate(alongsideTransition: nil) { _ in
                self.onDismiss()
            }
        }
    }
}
```

Acquire `.playback` in `PracticeDetailView` immediately before presenting, matching `AudioPlayerService`. If acquire throws, toast `String(localized: "文件不存在或已被移除")` only when the file is missing; if acquire fails on an existing file, toast `String(localized: "节拍器无法启动")` is wrong — use `String(localized: "无法播放")` and add that key, or reuse an existing generic toast already used for video errors (`video.lastError` path). Prefer showing `video.lastError`-style short copy: add `String(localized: "无法播放")`.

- [ ] **Step 2: Wire the workbench card**

Add `@State private var player = AudioPlayerService()` and `@State private var videoPlayURL: URL?`.

On `onDisappear`, after existing metronome/recorder cleanup, call `player.stop()` and `videoPlayURL = nil`.

In `clipCard`, add a trailing play button (same glyph/size as `RecordDetailView` audio pane). On tap:

```swift
presentIfFileExists(rec) {
    player.stop()
    metronome.stop()
    if MediaReviewMedia.isVideo(fileName: rec.fileName) {
        do {
            try AudioSessionCoordinator.shared.acquire(.playback)
            videoPlayURL = rec.fileURL
        } catch {
            show(String(localized: "无法播放"))
        }
    } else {
        player.toggle(url: rec.fileURL, id: rec.id)
    }
}
```

Present:

```swift
.fullScreenCover(isPresented: Binding(
    get: { videoPlayURL != nil },
    set: { if !$0 { videoPlayURL = nil } }
)) {
    if let videoPlayURL {
        SystemVideoPlayer(url: videoPlayURL) {
            self.videoPlayURL = nil
        }
        .ignoresSafeArea()
    }
}
```

Before `recorder.start`, `video.presentCamera()`, and `isSourcePresented = true`, call `player.stop()` and `videoPlayURL = nil`.

Do **not** call `practiceTimer.pause()` when starting playback.

Do **not** use `AudioPlayerService` for `.mov`/`.mp4` on this page (that path has no video layer).

- [ ] **Step 3: Compile**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeClipQueryTests test
```

Expected: PASS and the app target compiles.

- [ ] **Step 4: Commit**

```bash
git add foxgita/Features/Practice/SystemVideoPlayer.swift \
  foxgita/Features/Practice/PracticeDetailView.swift \
  foxgita/Localizable.xcstrings
git commit -m "Play workbench clips in place, with full-screen video."
```

---

### Task 7: Complete writes id; Back does not

**Files:**
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift` (`complete` ~825-864, `requestExit` ~741-758)

**Interfaces:**
- Consumes: Task 3 `finishSession -> String?`, Task 4 `lastCompletedSessionId`
- Produces: Effective Complete sets `router.lastCompletedSessionId`. Empty Complete and Back never set it.

- [ ] **Step 1: Patch complete and requestExit**

`complete` — after `persistPending`:

```swift
if let open = openSessionId {
    saveOpenSession(task: task)
    Haptics.success()
    router.lastCompletedSessionId = open
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

// finishSession path from Task 3 already assigns lastCompletedSessionId
```

`requestExit` when `openSessionId != nil`: keep `saveOpenSession` + `leave()`, and **do not** assign `lastCompletedSessionId`.

Empty complete must not assign `lastCompletedSessionId`.

- [ ] **Step 2: Compile**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add foxgita/Features/Practice/PracticeDetailView.swift
git commit -m "Hand the completed session id to the practice tab."
```

---

### Task 8: Home just-completed card

**Files:**
- Create: `foxgita/Features/Practice/JustCompletedCard.swift`
- Modify: `foxgita/Features/Practice/PracticeView.swift` (scroll stack after `StreakCard` / before section header; `onChange` of `selectedDay`)

**Interfaces:**
- Consumes: `JustCompletedCopy` (Task 2), `AppRouter.lastCompletedSessionId` (Task 4)
- Produces: Card on today only; 再练一次 / 查看记录; day change clears the id

- [ ] **Step 1: Add the card view**

Create `foxgita/Features/Practice/JustCompletedCard.swift`:

```swift
import SwiftUI

struct JustCompletedCard: View {
    var title: String
    var minutes: String
    var summary: String
    var onPracticeAgain: () -> Void
    var onViewRecord: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "刚刚完成"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GitaTheme.brand500)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(summary.isEmpty ? minutes : "\(minutes) · \(summary)")
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
            HStack(spacing: 10) {
                Button(String(localized: "再练一次"), action: onPracticeAgain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .background(GitaTheme.brand500)
                    .clipShape(Capsule())
                Button(String(localized: "查看记录"), action: onViewRecord)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .background(GitaTheme.bgSubtle)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }
}
```

- [ ] **Step 2: Bind it on PracticeView**

Add:

```swift
private var justCompleted: PracticeSession? {
    guard isSelectedToday, let id = router.lastCompletedSessionId else { return nil }
    return sessions.first { $0.id == id && $0.deletedAt == nil }
}
```

In `body` `onChange(of: selectedDay)` (existing), after resetting swipe, add:

```swift
if !calendar.isDateInToday(newDay) {
    router.clearJustCompleted()
}
```

If `router.lastCompletedSessionId != nil` and `justCompleted == nil`, call `router.clearJustCompleted()` (deleted / missing) — do this in the same `onChange` of `router.lastCompletedSessionId` or at the top of `body` via a small helper invoked from `.onChange(of: router.lastCompletedSessionId)`.

In the `ScrollView` `VStack`, **after** `StreakCard` and **before** the section header `HStack`, insert:

```swift
if let session = justCompleted {
    JustCompletedCard(
        title: session.taskTitle,
        minutes: JustCompletedCopy.minutesLabel(
            durationSec: session.durationSec,
            hasNote: !session.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            mediaCount: session.recordings.filter { $0.deletedAt == nil }.count
        ),
        summary: JustCompletedCopy.summary(
            hasNote: !session.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            fileNames: session.recordings.filter { $0.deletedAt == nil }.map(\.fileName)
        ),
        onPracticeAgain: {
            let taskId = session.taskId
            router.clearJustCompleted()
            router.practicePath = [.detail(taskId: taskId)]
        },
        onViewRecord: {
            let taskId = session.taskId
            router.clearJustCompleted()
            router.selectedTab = .record
            router.recordPath = [.detail(taskId: taskId)]
        }
    )
}
```

Look up **only** `router.lastCompletedSessionId`. Do not use `sessions.first` by `endedAt`.

- [ ] **Step 3: Compile + unit tests**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add foxgita/Features/Practice/JustCompletedCard.swift \
  foxgita/Features/Practice/PracticeView.swift \
  foxgita/Localizable.xcstrings
git commit -m "Show a one-shot just-completed card on today's practice tab."
```

---

### Task 9: Docs

**Files:**
- Modify: `docs/TECHNICAL.md` (§4.1 table "完成练习", §4.1.2 训练页)
- Modify: `docs/TEST_PLAN_CLI.md` (suite table)
- Modify: spec header status to `Approved — implementation plan in ../plans/2026-08-23-practice-workbench-resume.md`

**Interfaces:**
- Consumes: behavior from Tasks 1–8
- Produces: docs that match shipping code

- [ ] **Step 1: Patch TECHNICAL.md**

In the §4.1 table, change 完成练习 to:

```text
有效完成：写回 task.defaultBpm，AppRouter.lastCompletedSessionId = 刚保存的 session id，回今天并展示「刚刚完成」。空完成：toast「这次没有留下记录」，不写 BPM / id。返回已有 session：updateOpenSession（含 defaultBpm），不写 lastCompletedSessionId。
```

Add a short §4.1.3:

```markdown
#### 4.1.3 工作台进入恢复

`PracticeDetailView.onAppear` 用 `PracticeResumeQuery.resume`：最近有效 session 的 BPM，否则 `task.defaultBpm`。焦点行优先 `reviewNextAction`，否则上次笔记首行。笔记框不预填。
```

- [ ] **Step 2: Patch TEST_PLAN_CLI.md**

Add rows:

| `PracticeResumeQueryTests` | 无历史隐藏行；有效 session 覆盖 default；跳过无效/已删；nextAction 优先；28 字截断；BPM 钳制 |
| `JustCompletedCopyTests` | 分钟进位；0 分钟+笔记/媒体为「不足 1 分钟」；摘要不含 0 条 |
| `AppRouterTests` | `clearJustCompleted` 清 id |

- [ ] **Step 3: Flip spec status**

First line block of the design spec: `状态：Approved — implementation plan in ../plans/2026-08-23-practice-workbench-resume.md`

- [ ] **Step 4: Commit**

```bash
git add docs/TECHNICAL.md docs/TEST_PLAN_CLI.md \
  docs/superpowers/2026-08-23-practice-workbench-resume/specs/2026-08-23-practice-workbench-resume-design.md
git commit -m "Document workbench resume and the just-completed handoff."
```

---

## Spec coverage

| Spec | Task |
|---|---|
| Resume BPM / focus / no prefilling | 1, 5 |
| Just-completed copy rules | 2, 8 |
| Write `defaultBpm`; `finishSession` returns id | 3 |
| Router id; leave practice tab clears | 4, 8 |
| In-page audio + full-screen video | 6 |
| Complete sets id; Back does not | 7 |
| Card on today; 再练一次 / 查看记录; past-day → today | 8 (`returnPracticeToToday` already snaps) |
| Docs | 9 |
| No schema / no session record route / no playback-as-audio-only | Global + Task 6 |

## Type consistency

- `finishSession -> String?`
- `ResumeSession` / `ResumeRecording` / `ResumeState`
- `PracticeResumeQuery.resume` / `focusLine`
- `JustCompletedCopy.minutesLabel` / `summary`
- `AppRouter.lastCompletedSessionId` / `clearJustCompleted()`
- `SystemVideoPlayer(url:onDismiss:)`
