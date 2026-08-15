# Practice Clip Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 练习详情在停录后立刻落库并展示 Figma 摘要卡；已配 AI 则该条入队；完成/返回不再出处理 Sheet。

**Architecture:** 第一条停录 `beginOpenSession` 建 `PracticeSession` + `RecordingRef`；之后 `appendRecording`。卡片 `@Query` 该 session。完成与有 session 的返回都走 `updateOpenSession`。`ReviewJobRunner` / Client / Generator 不改。

**Tech Stack:** SwiftUI · SwiftData Schema V4 · 现有 `PracticeStore` / `ReviewJobRunner` / `MediaReviewMedia` · Swift Testing

## Global Constraints

- Spec: `docs/superpowers/2026-08-15-practice-clip-cards/specs/2026-08-15-practice-clip-cards-design.md`
- iOS 18+ · Scheme `foxgita` · cwd `foxgita/`
- 先落库再分析；clip `id` 原样写入 `RecordingRef.id`
- JPEG-only 通道与 Runner 语义不改；不改 `VisionPracticeClient` 提示词
- Copy: `zh-Hans` via `String(localized:)`
- 不打 API Key / 媒体字节日志
- YAGNI: 不播放/删除/练中重试、不恢复被杀的 `openSessionId`、无 Schema V5、无处理 Sheet
- 单元测试：

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

## File map

| File | Role |
|---|---|
| `foxgita/Services/PracticeStore.swift` | `beginOpenSession` / `appendRecording` / `updateOpenSession` |
| `foxgita/Services/AudioRecorderService.swift` | `detach(_:)` 移出 pending、不删文件 |
| `foxgita/Services/VideoRecorderService.swift` | 同上 |
| `foxgita/Features/Practice/PracticeDetailView.swift` | 模式、停录落库、卡片、完成/返回 |
| `foxgitaTests/PracticeStoreTests.swift` | 开局 session 单测 |
| `docs/TECHNICAL.md` | 新命令 + §6.3.2 触发点 |
| `docs/TEST_PLAN_CLI.md` | PracticeStoreTests 行补开局 session |

`ReviewGenerationSheet.swift` 本计划只断开呈现，不删文件。

---

### Task 1: Open-session store commands

**Files:**
- Modify: `foxgita/Services/PracticeStore.swift`
- Modify: `docs/TECHNICAL.md`（§6.3 表）
- Test: `foxgitaTests/PracticeStoreTests.swift`

**Interfaces:**
- Consumes: `AudioRecorderService.Clip`, `PracticeRecordRules`, `RecordingStore.url(for:)`, `repository.add` / `session(id:)` / `save`
- Produces:

```swift
func beginOpenSession(
    taskId: String,
    steps: [String],
    note: String,
    startedAt: Date,
    endedAt: Date,
    durationSec: Int,
    bpm: Int,
    clip: AudioRecorderService.Clip
) -> String?

func appendRecording(sessionId: String, clip: AudioRecorderService.Clip) -> Bool

func updateOpenSession(
    sessionId: String,
    steps: [String],
    note: String,
    endedAt: Date,
    durationSec: Int,
    bpm: Int
) -> Bool
```

`beginOpenSession`：任务不存在 → `nil` + `.notFound`。`endedAt < startedAt` 或 `durationSec < 0` → `nil` + `.invalidInput`。文件不在磁盘 → `nil` + `.fileMissing`，不建 session。成功：新建 `PracticeSession`（字段与 `finishSession` 相同），`RecordingRef(id: clip.id, …)`，`task.steps = steps`，`touch()`，返回 `session.id`。

`appendRecording`：session 找不到 → `false` + `.notFound`。文件不在 → `false` + `.fileMissing`。成功 append 同一 `RecordingRef` 映射并 save。

`updateOpenSession`：找不到 → `false` + `.notFound`。`durationSec < 0` 或 `endedAt < session.startedAt` → `false` + `.invalidInput`。不因 0 秒拒绝（已有录音即有效）。写 `steps` / `noteText` / `endedAt` / `durationSec` / `bpm` / `updatedAt`，并 `task.steps` + `touch()`。

`finishSession` 签名与行为不变。

- [ ] **Step 1: Write the failing tests**

Append to `PracticeStoreTests.swift`（与现有 `makeStore` / `seedActive` 并列）。辅助函数写在 struct 内：

```swift
    private func writeClip(
        id: String = UUID().uuidString,
        fileName: String? = nil,
        durationSec: Int = 8
    ) throws -> AudioRecorderService.Clip {
        let name = fileName ?? "open-\(UUID().uuidString).m4a"
        let url = RecordingStore.url(for: name)
        try Data([0x00]).write(to: url)
        return AudioRecorderService.Clip(
            id: id, fileName: name, bytes: 1,
            durationSec: durationSec, createdAt: Date(), label: ""
        )
    }

    @Test func beginOpenSessionWritesSessionAndClipId() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let clip = try writeClip(id: "c1")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let sid = store.beginOpenSession(
            taskId: "warm", steps: ["a"], note: "",
            startedAt: start, endedAt: start, durationSec: 0, bpm: 80,
            clip: clip
        )
        #expect(sid != nil)
        let session = try #require(try repo.session(id: sid!))
        #expect(session.recordings.count == 1)
        #expect(session.recordings[0].id == "c1")
        #expect(session.durationSec == 0)
        #expect(try repo.task(id: "warm")?.steps == ["a"])
    }

    @Test func beginOpenSessionMissingFileWritesNothing() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let clip = AudioRecorderService.Clip(
            id: "ghost", fileName: "missing-\(UUID().uuidString).m4a",
            bytes: 1, durationSec: 3, createdAt: Date(), label: ""
        )
        let now = Date()
        #expect(store.beginOpenSession(
            taskId: "warm", steps: [], note: "",
            startedAt: now, endedAt: now, durationSec: 0, bpm: 80, clip: clip
        ) == nil)
        #expect(store.lastError == .fileMissing)
        #expect(try repo.sessions().isEmpty)
    }

    @Test func appendRecordingAddsSecondClip() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        let sid = try #require(store.beginOpenSession(
            taskId: "warm", steps: [], note: "",
            startedAt: now, endedAt: now, durationSec: 0, bpm: 80,
            clip: try writeClip(id: "a")
        ))
        #expect(store.appendRecording(sessionId: sid, clip: try writeClip(id: "b")))
        #expect(try repo.session(id: sid)?.recordings.map(\.id).sorted() == ["a", "b"])
        #expect(try repo.sessions().count == 1)
    }

    @Test func updateOpenSessionWritesNoteAndDuration() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let sid = try #require(store.beginOpenSession(
            taskId: "warm", steps: ["旧"], note: "",
            startedAt: start, endedAt: start, durationSec: 0, bpm: 80,
            clip: try writeClip(id: "a")
        ))
        let end = start.addingTimeInterval(90)
        #expect(store.updateOpenSession(
            sessionId: sid, steps: ["新"], note: "记",
            endedAt: end, durationSec: 90, bpm: 88
        ))
        let session = try #require(try repo.session(id: sid))
        #expect(session.noteText == "记")
        #expect(session.durationSec == 90)
        #expect(session.bpm == 88)
        #expect(session.steps == ["新"])
        #expect(try repo.task(id: "warm")?.steps == ["新"])
    }

    @Test func updateOpenSessionAllowsZeroDurationWhenClipsExist() throws {
        let (store, repo, _) = makeStore(seeded: true)
        try seedActive(into: repo)
        let now = Date()
        let sid = try #require(store.beginOpenSession(
            taskId: "warm", steps: [], note: "",
            startedAt: now, endedAt: now, durationSec: 0, bpm: 80,
            clip: try writeClip(id: "a")
        ))
        #expect(store.updateOpenSession(
            sessionId: sid, steps: [], note: "",
            endedAt: now, durationSec: 0, bpm: 80
        ))
        #expect(try repo.session(id: sid)?.durationSec == 0)
    }
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

Expected: FAIL（`beginOpenSession` 不存在）。

- [ ] **Step 3: Implement**

在 `PracticeStore.swift` 的 `finishSession` 之后插入。`makeRef` 仅本文件 private：

```swift
    func beginOpenSession(
        taskId: String,
        steps: [String],
        note: String,
        startedAt: Date,
        endedAt: Date,
        durationSec: Int,
        bpm: Int,
        clip: AudioRecorderService.Clip
    ) -> String? {
        guard let task = try? repository.task(id: taskId) else {
            lastError = .notFound
            return nil
        }
        guard endedAt >= startedAt, durationSec >= 0 else {
            lastError = .invalidInput
            return nil
        }
        guard FileManager.default.fileExists(atPath: clip.url.path) else {
            lastError = .fileMissing
            return nil
        }
        let session = PracticeSession(
            taskId: task.id,
            taskTitle: task.title,
            category: task.category,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSec: durationSec,
            bpm: bpm,
            timeSig: task.timeSig,
            steps: steps,
            noteText: note
        )
        session.recordings.append(Self.ref(from: clip))
        return produce {
            task.steps = steps
            task.touch()
            try repository.add(session)
            try repository.save()
            return session.id
        }
    }

    func appendRecording(sessionId: String, clip: AudioRecorderService.Clip) -> Bool {
        guard let session = try? repository.session(id: sessionId) else {
            lastError = .notFound
            return false
        }
        guard FileManager.default.fileExists(atPath: clip.url.path) else {
            lastError = .fileMissing
            return false
        }
        return produce {
            session.recordings.append(Self.ref(from: clip))
            session.updatedAt = Date()
            try repository.save()
            return true
        } ?? false
    }

    func updateOpenSession(
        sessionId: String,
        steps: [String],
        note: String,
        endedAt: Date,
        durationSec: Int,
        bpm: Int
    ) -> Bool {
        guard let session = try? repository.session(id: sessionId) else {
            lastError = .notFound
            return false
        }
        guard let task = try? repository.task(id: session.taskId) else {
            lastError = .notFound
            return false
        }
        guard endedAt >= session.startedAt, durationSec >= 0 else {
            lastError = .invalidInput
            return false
        }
        return produce {
            session.stepsSnapshotRaw = StepCoding.encode(steps)
            session.noteText = note
            session.endedAt = endedAt
            session.durationSec = durationSec
            session.bpm = bpm
            session.updatedAt = Date()
            task.steps = steps
            task.touch()
            try repository.save()
            return true
        } ?? false
    }

    private static func ref(from clip: AudioRecorderService.Clip) -> RecordingRef {
        RecordingRef(
            id: clip.id, fileName: clip.fileName, bytes: clip.bytes,
            durationSec: clip.durationSec, createdAt: clip.createdAt, label: clip.label
        )
    }
```

`TECHNICAL.md` §6.3 表在 `finishSession` 行下加：

| `beginOpenSession(...)` | 文件在磁盘才建 session + 第一条 `RecordingRef`（id=clip.id）；否则 `.fileMissing` |
| `appendRecording(sessionId:clip:)` | 挂到已有 session；缺文件 / 缺 session 失败 |
| `updateOpenSession(...)` | 更新时长/笔记/步骤/`endedAt`/BPM；已有录音时允许 0 秒 |

- [ ] **Step 4: Run tests — expect PASS**

同一 `PracticeStoreTests` 命令。Expected: PASS。再跑一次全量 `foxgitaTests`。

- [ ] **Step 5: Commit**

```bash
git add foxgita/Services/PracticeStore.swift \
  foxgitaTests/PracticeStoreTests.swift \
  docs/TECHNICAL.md
git commit -m "feat: persist an open practice session on the first clip"
```

---

### Task 2: Persist on stop + finish/return without the sheet

**Files:**
- Modify: `foxgita/Services/AudioRecorderService.swift`
- Modify: `foxgita/Services/VideoRecorderService.swift`
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift`

**Interfaces:**
- Consumes: Task 1 三个 Store 方法；`ReviewJobRunner.enqueue`；`LLMCredentialsStore.isConfigured`
- Produces: `AudioRecorderService.detach(_:)` / `VideoRecorderService.detach(_:)`（移出 pending、不删文件）；详情持有 `openSessionId`；完成与有 session 的返回走 `updateOpenSession`，不 present `ReviewGenerationSheet`，不二次 enqueue

```swift
func detach(_ id: String)
```

- [ ] **Step 1: Add detach**

`AudioRecorderService`：

```swift
    /// Drops the take from `pending` but leaves the file for a persisted `RecordingRef`.
    func detach(_ id: String) {
        pending.removeAll { $0.id == id }
    }
```

`VideoRecorderService` 同样（只 `pending.removeAll`，不 `RecordingStore.delete`）。

- [ ] **Step 2: Wire PracticeDetailView persist + complete/return**

加状态（可先留 `showNote`，Task 3 再换成模式）：

```swift
    @State private var openSessionId: String?
```

删掉完成路径里对 `showReviewSheet` / `reviewClipIds` 的写入（`.sheet` 也删）。`hasUnsavedWork` 增加 `openSessionId != nil`。

共享转换与落库（放在 `complete` 附近）：

```swift
    private func audioClip(_ clip: VideoRecorderService.Clip) -> AudioRecorderService.Clip {
        AudioRecorderService.Clip(
            id: clip.id, fileName: clip.fileName, bytes: clip.bytes,
            durationSec: clip.durationSec, createdAt: clip.createdAt, label: clip.label
        )
    }

    private func persist(_ clip: AudioRecorderService.Clip, task: TaskItem) {
        guard FileManager.default.fileExists(atPath: clip.url.path) else {
            show(String(localized: MediaReviewMedia.isVideo(fileName: clip.fileName) ? "录像没保存" : "录音没保存"))
            return
        }
        let end = Date()
        let elapsed = practiceTimer.elapsedSec
        let start = practiceTimer.startedAt ?? end.addingTimeInterval(TimeInterval(-elapsed))
        let sid: String?
        if let open = openSessionId {
            sid = store.appendRecording(sessionId: open, clip: clip) ? open : nil
        } else {
            sid = store.beginOpenSession(
                taskId: task.id, steps: steps, note: noteText,
                startedAt: start, endedAt: end, durationSec: elapsed,
                bpm: metronome.bpm, clip: clip
            )
        }
        guard let sid else { return }
        openSessionId = sid
        recorder.detach(clip.id)
        video.detach(clip.id)
        if llmCredentials.isConfigured(baseURL: llmBaseURL, model: llmModel) {
            store.markReviewsPending(recordingIds: [clip.id])
            reviewRunner.enqueue([clip.id], baseURL: llmBaseURL, model: llmModel)
        }
    }

    private func persistPending(task: TaskItem) {
        for clip in recorder.pending { persist(clip, task: task) }
        for clip in video.pending { persist(audioClip(clip), task: task) }
    }

    private func saveOpenSession(task: TaskItem) {
        guard let openSessionId else { return }
        let end = Date()
        _ = store.updateOpenSession(
            sessionId: openSessionId,
            steps: steps,
            note: noteText,
            endedAt: end,
            durationSec: practiceTimer.elapsedSec,
            bpm: metronome.bpm
        )
    }
```

`toolsRow` 录音 stop 之后立刻 `persistPending(task:)`。`onPicked` 在 `ingest` 之后 `if let task { persistPending(task: task) }`。从录音切走（Task 3 会用）同样先 stop 再 persist。

`onDisappear`：若正在录则 `stop`；若有 `task` 则 `persistPending`；**然后** `discardPending` / 删未 detach 的视频。这样已落库文件不会被删。

`requestExit`：

```swift
    private func requestExit() {
        practiceTimer.pause()
        metronome.stop()
        if let task, recorder.isRecording {
            recorder.stop(label: task.title)
            persistPending(task: task)
        }
        if openSessionId != nil {
            if let task { saveOpenSession(task: task) }
            leave()
            return
        }
        if hasUnsavedWork {
            confirmExit = true
        } else {
            leave()
        }
    }
```

`complete`：

```swift
    private func complete(_ task: TaskItem) {
        guard !isCompleting else { return }
        isCompleting = true
        if recorder.isRecording { recorder.stop(label: task.title) }
        practiceTimer.pause()
        metronome.stop()
        persistPending(task: task)

        if let _ = openSessionId {
            saveOpenSession(task: task)
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

        var clips = recorder.consume()
        clips += video.takeAll().map { audioClip($0) }
        let end = Date()
        let elapsed = practiceTimer.elapsedSec
        let saved = store.finishSession(
            taskId: task.id, steps: steps, note: noteText,
            startedAt: practiceTimer.startedAt ?? end.addingTimeInterval(TimeInterval(-elapsed)),
            endedAt: end, durationSec: elapsed, bpm: metronome.bpm, recordings: clips
        )
        guard saved else {
            isCompleting = false
            return
        }
        Haptics.success()
        router.returnPracticeToToday = true
        router.practicePath.removeAll()
    }
```

无 session 的完成**不** `enqueue`、**不** present Sheet。删除 `.sheet(isPresented: $showReviewSheet)` 以及 `reviewClipIds` / `showReviewSheet` 状态。

- [ ] **Step 3: Build**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests/PracticeStoreTests test
```

Expected: PASS（编译 + Task 1 测试）。全量 `foxgitaTests` 一次。

- [ ] **Step 4: Commit**

```bash
git add foxgita/Services/AudioRecorderService.swift \
  foxgita/Services/VideoRecorderService.swift \
  foxgita/Features/Practice/PracticeDetailView.swift
git commit -m "feat: save clips on stop and skip the finish review sheet"
```

---

### Task 3: Mode switch + Figma clip cards

**Files:**
- Modify: `foxgita/Features/Practice/PracticeDetailView.swift`
- Modify: `docs/TECHNICAL.md`（§6.3.2）
- Modify: `docs/TEST_PLAN_CLI.md`（PracticeStoreTests 行）

**Interfaces:**
- Consumes: `openSessionId`、`MediaReviewMedia.isVideo`、`ReviewJobRunner.isRunning`、`RecordingRef.reviewStatus` / 三段字段 / `durationLabel`
- Produces: `enum ToolMode { case audio, note, video }`；卡片 UI

- [ ] **Step 1: Replace showNote with ToolMode**

```swift
    private enum ToolMode {
        case audio, note, video
    }

    @State private var toolMode: ToolMode = .note
    @State private var expandedReviewId: String?
    @Query private var sessions: [PracticeSession]
```

`init` 里为 sessions 加 filter：`#Predicate<PracticeSession> { $0.taskId == taskId && $0.deletedAt == nil }`（`taskId` 先拷到局部 `let tid = taskId`）。

```swift
    private var openRecordings: [RecordingRef] {
        sessions.first(where: { $0.id == openSessionId })?
            .recordings.filter { $0.deletedAt == nil } ?? []
    }

    private var visibleClips: [RecordingRef] {
        openRecordings
            .filter { MediaReviewMedia.isVideo(fileName: $0.fileName) == (toolMode == .video) }
            .sorted { $0.createdAt > $1.createdAt }
    }
```

`toolsRow`：

```swift
    private func toolsRow(_ task: TaskItem) -> some View {
        HStack(spacing: 10) {
            tool(
                title: recorder.isRecording ? String(localized: "录音中") : String(localized: "录音"),
                systemImage: recorder.isRecording ? "mic.fill" : "mic",
                on: toolMode == .audio
            ) {
                Task {
                    if toolMode != .audio {
                        if recorder.isRecording {
                            recorder.stop(label: task.title)
                            persistPending(task: task)
                        }
                        toolMode = .audio
                        return
                    }
                    if recorder.isRecording {
                        recorder.stop(label: task.title)
                        persistPending(task: task)
                    } else {
                        await recorder.start(label: task.title)
                    }
                }
            }
            tool(title: String(localized: "写笔记"), systemImage: "square.and.pencil", on: toolMode == .note) {
                if recorder.isRecording {
                    recorder.stop(label: task.title)
                    persistPending(task: task)
                }
                toolMode = .note
            }
            tool(
                title: String(localized: "录视频"),
                systemImage: "video.fill",
                on: toolMode == .video
            ) {
                if recorder.isRecording {
                    recorder.stop(label: task.title)
                    persistPending(task: task)
                }
                if toolMode != .video {
                    toolMode = .video
                    return
                }
                video.presentCamera()
            }
        }
    }
```

`content` 里：`if toolMode == .note {` 原笔记框 `}`。删「本次已录 N 段」。`if recorder.isRecording { recordingActivePanel }` 仍在 tools 与列表之间。`if toolMode != .note { clipList(task) }`。

- [ ] **Step 2: Cards**

```swift
    private func clipList(_ task: TaskItem) -> some View {
        VStack(spacing: 10) {
            ForEach(visibleClips, id: \.id) { rec in
                clipCard(rec, taskTitle: task.title)
            }
        }
    }

    private func clipCard(_ rec: RecordingRef, taskTitle: String) -> some View {
        let video = MediaReviewMedia.isVideo(fileName: rec.fileName)
        let configured = llmCredentials.isConfigured(baseURL: llmBaseURL, model: llmModel)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(video ? GitaTheme.categoryBlue : GitaTheme.brand500)
                    .frame(width: 6, height: 6)
                Text(video ? String(localized: "视频记录") : String(localized: "录音记录"))
                    .font(.system(size: 12, weight: .semibold))
                Text("·")
                Text(relativeTime(rec.createdAt))
                    .font(.system(size: 12))
                    .foregroundStyle(GitaTheme.textSecondary)
                Spacer()
            }
            Text("\(taskTitle) · \(rec.durationLabel)")
                .font(.system(size: 16, weight: .semibold))
            Text(video ? String(localized: "姿势、指法与节奏分析") : String(localized: "节奏与和弦切换分析"))
                .font(.system(size: 13))
                .foregroundStyle(GitaTheme.textSecondary)
            if configured {
                aiRow(rec)
            }
            if expandedReviewId == rec.id, rec.reviewStatus == .ready {
                reviewFields(rec)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func aiRow(_ rec: RecordingRef) -> some View {
        let running = reviewRunner.isRunning(rec.id)
        switch rec.reviewStatus {
        case .ready:
            HStack {
                Text(String(localized: "AI 复盘已生成"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GitaTheme.brand500)
                Spacer()
                Button(
                    expandedReviewId == rec.id
                        ? String(localized: "收起")
                        : String(localized: "查看复盘")
                ) {
                    expandedReviewId = expandedReviewId == rec.id ? nil : rec.id
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GitaTheme.brand500)
            }
        case .pending where running:
            Text(String(localized: "分析中")).font(.system(size: 12, weight: .semibold))
        case .pending:
            Text(String(localized: "未完成")).font(.system(size: 12, weight: .semibold))
        case .failed:
            Text(String(localized: "生成失败")).font(.system(size: 12, weight: .semibold))
        case .none:
            EmptyView()
        }
    }

    private func reviewFields(_ rec: RecordingRef) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            labeled("亮点", rec.reviewHighlight)
            labeled("优先改善", rec.reviewFocus)
            labeled("下次练法", rec.reviewNextAction)
        }
    }

    private func labeled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(GitaTheme.textSecondary)
            Text(body).font(.system(size: 14))
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh-Hans")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
```

所有新用户可见字符串用 `String(localized:)`（含「收起」）。空列表不画占位卡。

- [ ] **Step 3: Docs**

`TECHNICAL.md` §6.3.2 首句改为：停录即 `beginOpenSession` / `appendRecording` 并入队；完成与返回走 `updateOpenSession`，不再出处理 Sheet。链到片段卡规格。

`TEST_PLAN_CLI.md` `PracticeStoreTests` 行补：`beginOpenSession` / `appendRecording` / `updateOpenSession`。

- [ ] **Step 4: Build**

```bash
xcodebuild -project foxgita.xcodeproj -scheme foxgita \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:foxgitaTests test
```

Expected: `TEST SUCCEEDED`。

- [ ] **Step 5: Commit**

```bash
git add foxgita/Features/Practice/PracticeDetailView.swift \
  foxgita/Localizable.xcstrings \
  docs/TECHNICAL.md docs/TEST_PLAN_CLI.md
git commit -m "feat: show in-session audio and video review cards"
```

`Localizable.xcstrings` 仅在本次构建改动时加入。

---

## Placeholder / consistency self-review

**Spec coverage**

| Spec | Task |
|---|---|
| 停录落库 + clip id | 1, 2 |
| 文件缺失不建行 / toast | 1, 2 |
| 完成/返回 `updateOpenSession`、无 Sheet、不二次 enqueue | 2 |
| 有 session 返回不销毁确认 | 2 |
| 无 session 的笔记/计时仍 `finishSession` | 2 |
| 模式二次点击才录/开相机 | 3 |
| Figma 卡 + 展开三段 | 3 |
| 未配置无 AI 行 | 3 |
| 练中不重试 | 3 |
| TECHNICAL / TEST_PLAN | 1, 3 |

**Types:** `beginOpenSession → String?`、`appendRecording → Bool`、`updateOpenSession → Bool`、`detach(_:)`、`ToolMode` — Tasks 1–3 同名。

**No TBD / “handle errors later” / “similar to Task N” without code.**
