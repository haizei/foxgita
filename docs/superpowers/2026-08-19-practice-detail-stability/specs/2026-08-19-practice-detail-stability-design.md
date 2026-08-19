# Design: 练习详情稳定性（BPM 精调 + 节拍器恢复 + 历史媒体）

> 功能需求目录：[`../`](../)。本文为设计规格。

**日期：** 2026-08-19  
**状态：** Draft — awaiting user review  
**Sprint：** 2026-08-27 — 2026-09-02  
**产品来源：** `design-boards/产品PRD/练习/2026-08-19-Sprint计划-练习详情稳定性修复.md`  
**升级对象：** [练习详情片段卡](../../2026-08-15-practice-clip-cards/specs/2026-08-15-practice-clip-cards-design.md) 的列表口径与时间展示；节拍器与音频会话见 `docs/TECHNICAL.md` §5  
**方案：** 方案 B — 抽出可测核心，页面只绑定

---

## 1. 背景与目标

练习详情有三处用户已碰到的缺口，都在同一页，不改 Schema、不改落库语义。

1. 节拍器加减号每次 ±5。`MetronomeEngine.setBpm` 已接受任意整数并钳制 `40...200`，缺口在 View。
2. 暂停后再点开始，计时继续但经常无声。`stop()` 会 `player.stop()` 并 `release` 音频会话；下次 `start()` 里 `prepareEngine()` 只看自维护的 `engineStarted`，不确认 `engine.isRunning`。
3. 再次进入同一任务看不到已保存的录音/视频。`@Query` 已取出该 `taskId` 下未删除 session，但 `visibleClips` 只展示 `openSessionId` 对应的本次片段。这是 8-15 片段卡规格的原范围，不是数据丢失。

成功标准：

1. 单击加减号调整 1 BPM；到 40 或 200 不再越界；无障碍文案为「降低 / 提高 1 BPM」。
2. 开始与暂停成对：计时与节拍器同时走、同时停；再开始时计时从原值继续，300 ms 内可听见节拍；连续 10 次如此。启动失败则两边都不跑，toast「节拍器无法启动」。
3. 再次进入同一任务，录音模式看到该任务全部未删除录音，视频模式看到全部未删除视频；卡片能靠类型、绝对时间、时长、状态认出来。
4. 新录制仍写入本次 `openSessionId` session，不改写历史 session。
5. 本地文件缺失时卡片标「文件缺失」；点分析 / 诊断 / 记录详情回放 toast「文件不存在或已被移除」，不崩溃。

---

## 2. 产品决策

| 项 | 选择 |
|---|---|
| BPM 步长 | 单击 ±1。范围仍 40...200，只在 `setBpm` 钳制 |
| 长按连续调速 / ±5 快调 | 不做（P1） |
| 开始失败 | 计时器和节拍器都不启动；按钮保持「开始」；toast「节拍器无法启动」 |
| 系统打断 | 停在安全态，不自动恢复；用户再点开始 |
| 列表口径 | 该 `taskId` 下所有未删除 session 的未删除 recording；按当前工具模式筛音频/视频 |
| `openSessionId` | 只决定新片段写到哪条 session，不再决定列表是否可见 |
| 时间展示 | 绝对时间 `M月d日 HH:mm`（如 `8月16日 14:32`），`zh-Hans`、设备本地时区。去掉相对时间 |
| 练中播放 / 删除 | 仍不做 |
| 文件缺失 | 卡片显示「文件缺失」；分析 / 诊断入口不禁用；点下去 toast，不 present |
| 空列表 | 对应模式显示空态，不留白 |
| 分组 / 分页 | 不做（P2） |
| Schema | 不改 |

本规格覆盖片段卡规格中下列三条，其余（停录即落库、`openSessionId` 写入、完成/返回、练中展开复盘）仍按原文：

- 列表只显示本次 `openSessionId` 片段 → 改为该任务全部历史 + 本次
- 相对时间 → 绝对时间
- 空列表留白 → 空态文案

---

## 3. 架构

```text
PracticeDetailView
  ├─ BPM ±1 ──────────────► MetronomeEngine.bump / setBpm
  ├─ 开始 / 暂停 ──────────► metronome.start/stop + PracticeTimer
  │                            start 失败 → 两边都不跑，toast
  ├─ 列表 ─────────────────► PracticeClipQuery.visible(...)
  │                            卡片：绝对时间、状态、文件缺失
  └─ 新录制 ───────────────► openSessionId + beginOpenSession / appendRecording

MetronomeEngine
  一次搭 graph（attach / connect / 缓存 click）
  每次 start：acquire 会话 → 确保 engine.isRunning → 清旧 buffer → 排拍

AudioSessionCoordinator
  acquire 失败回滚计数；暂停 / 中断 / 离开走同一条 stop

RecordingStore.fileExists
  卡片标缺失；分析 / 诊断 / 记录详情回放前再查一次
```

职责：

| 单元 | 做什么 | 依赖 |
|---|---|---|
| `PracticeClipQuery` | 展平、过滤未删除、按音频/视频、按 `createdAt` 倒序、按 id 去重 | 无 AV、无 SwiftUI、无 SwiftData |
| `MetronomeEngine` | BPM 钳制、graph 生命周期、启动失败上抛 | Coordinator、AVAudioEngine |
| `AudioSessionCoordinator` | 会话协商、打断、acquire 回滚 | AVAudioSession |
| `RecordingStore` | 补 `fileExists(fileName:)` | FileManager |
| `PracticeDetailView` | 绑定、空态、toast、无障碍、present 前查文件 | 以上 |
| `RecordDetailView` | 播放 / 打开诊断前查文件，缺失 toast | `RecordingStore`、`AudioPlayerService` |
| `PracticeStore` | 不改写入语义 | 已有 |

不改：Schema、`beginOpenSession` / `appendRecording` / `updateOpenSession` 的含义、录音中不得把 category 降为 `.playback`。

---

## 4. 节拍器

### 4.1 BPM

详情页 `metronomeCard`：

- `bump(-1)` / `bump(1)`
- accessibility：「降低 1 BPM」「提高 1 BPM」
- 连点逐次生效，不合并、不丢
- 暂停与恢复不重置 `bpm`
- RESET、离开页面、打断都不改 `bpm`（RESET 只停表和停节拍器）

`setBpm` 保持 `min(200, max(40, value))`。View 不维护范围。

### 4.2 生命周期

Graph 与运行拆开，禁止把 `engineStarted = false` 当作唯一修复（会重复 attach）。

1. **`configureGraphIfNeeded()`（一次）**  
   `attach` player、`connect` 到 mixer、烘焙 accent/beat buffer。节点保持挂着。

2. **每次 `start()`**  
   顺序：
   - `try AudioSessionCoordinator.shared.acquire(.playback)`
   - `configureGraphIfNeeded()`
   - 若 `engine.isRunning == false`，`try engine.start()`
   - 确认 `engine.isRunning`；否则抛错
   - 清掉 player 上旧 scheduled buffer（`player.stop()` 后再 `play()`，或等价的 `reset`）
   - 重算 `nextBeatFrame`（`player.lastRenderTime` 为空则退到 `engine.outputNode.lastRenderTime`，再不行从 0 加短 lead）
   - `player.play()` → `fill()` → 启动 pump
   - **最后** `isPlaying = true`

   任一步失败：`isPlaying` 保持 false；若本次 acquire 已成功则 `release(.playback)`；不启动 pump；上抛给 View。

3. **`stop()`（暂停、RESET、打断、离开共用）**  
   停 pump、`player.stop()`、`isPlaying = false`、`runToken += 1`、`release(.playback)`。不拆 graph、不 `engine.stop()`（避免下次重复 attach）。已停止再调无副作用。

`togglePlay()`：

- 正在跑：`practiceTimer.pause()` + `metronome.stop()`
- 未在跑：先 `try metronome.start()`，成功才 `practiceTimer.start()`；失败 toast「节拍器无法启动」，按钮仍为「开始」，计时不动

`player.play()` 与 `fill()` 的最终顺序以真机为准：首拍要在 300 ms 内可听，且不连发补拍。

### 4.3 音频会话

`acquire` 必须先增加计数再 `applyCategory()`（`applyCategory` 读的是当前 need）。`applyCategory` 失败则回滚该次计数，会话不留脏引用。

录音进行中开节拍器：仍因 `.record` need > 0 保持 `.playAndRecord`，不得降成 `.playback`。

打断：`handleInterruption` 在 `.began` 清计数并回调。详情页回调：`metronome.stop()`、`practiceTimer.pause()`、若正在录音则 `recorder.stop` 并走现有落库。不自动 `start()`。

### 4.4 诊断日志

Debug 级别（`os.Logger`，不进用户可见文案）：暂停后 `engine.isRunning`；恢复前后 `AVAudioSession` 的 category、route、`isOtherAudioPlaying`；`player.isPlaying`、`lastRenderTime`；`engine.start()` 是否抛错。

---

## 5. 媒体列表

### 5.1 `PracticeClipQuery`

入参用 descriptor，不持有 SwiftData 模型：

```text
PracticeClipDescriptor
  id: String
  fileName: String
  createdAt: Date
  deletedAt: Date?
```

```text
visible(clips: [PracticeClipDescriptor], videoMode: Bool) -> [PracticeClipDescriptor]
```

规则（按顺序）：

1. 丢掉 `deletedAt != nil`
2. `MediaReviewMedia.isVideo(fileName:) == videoMode`
3. 按 `createdAt` 降序
4. 按 `id` 去重，保留第一次出现的（已按时间排过，即最新那条）

View：把已由 `@Query` 筛过的 `sessions.flatMap(\.recordings)` 映成 descriptor。任务隔离和已删 session 由现有 query（`taskId` + `session.deletedAt == nil`）保证，不在 Query 函数里再做一遍。

`openRecordings` 可删；卡片改走 `visibleClips`。`openSessionId` 仍只用于 `persistPending` / `beginOpenSession` / `appendRecording` / `updateOpenSession`。

### 5.2 卡片

沿用现有摘要卡（类型点、任务名 · 时长、分析副文、AI 行、诊断入口、展开复盘）。改：

- 眉题时间：`DateFormatter`，`locale = zh-Hans`，设备本地时区，`dateFormat = "M月d日 HH:mm"`（不带年）。去掉 `relativeTime`。
- 文件不存在：状态区增加「文件缺失」，颜色 `GitaTheme.statusError`。AI / 诊断按钮仍在。
- 点「查看复盘」不依赖文件，仍可展开已有三段（数据在库里）。
- 点「查看诊断」或打开分析页：先 `RecordingStore.fileExists`；false 则 toast「文件不存在或已被移除」，不 present。

`RecordingStore.fileExists(fileName:)`：`FileManager.fileExists(atPath: url(for: fileName).path)`。

### 5.3 空态

`toolMode != .note` 且 `visibleClips` 为空时，用与记录详情类似的标题 + 副文，不要空 `VStack`。

| 模式 | 标题 | 副文 |
|---|---|---|
| 录音 | 还没有录音 | 点上方「录音」即可留下片段 |
| 视频 | 还没有视频 | 点上方「录视频」即可拍摄或从相册导入 |

### 5.4 写入隔离

再次进入任务 A：`openSessionId == nil`。第一段新媒体 `beginOpenSession` 建新 session；历史 recording 的 `session` 关系不变。列表同时显示新旧，因为 query 已展平全部 session。

任务 B 的媒体不会出现：`@Query` 按 `taskId` 过滤。

### 5.5 其它回放入口

练习详情不加播放。缺失文件的防御放在现有入口：

- `RecordDetailView`：点播放前查文件；缺失 toast，不调用 `AudioPlayerService.toggle`
- `RecordDetailView`：打开诊断前同样检查
- `AudioPlayerService.toggle`：文件不存在或 `AVAudioPlayer` 抛错时 `playingId` 保持 nil，不崩溃（防御，主提示仍由 View toast）
- `VideoDiagnosisView` / `VideoAnalysisView`：正常路径不会在文件缺失时被 present；若仍 `load` 到无效 URL，停在安全态，不崩溃

---

## 6. 错误处理

| 情况 | 行为 |
|---|---|
| `acquire` 失败 | 回滚该次计数；不启动计时；toast「节拍器无法启动」 |
| `engine.start()` 抛错或 `isRunning == false` | `release` 本次 playback need；`isPlaying == false`；计时不开始；同一句 toast |
| 系统打断 | 清会话计数；停节拍器、暂停计时、停录音并落库；不自动再开始 |
| 本地文件缺失 | 卡片「文件缺失」；点分析 / 诊断 / 记录详情播放 → toast「文件不存在或已被移除」 |
| 停录后文件不在（已有） | 不写库；toast「录音没保存」/「录像没保存」 |
| BPM 已在 40 或 200 | 数值不变，无 toast |
| 该模式无媒体 | 空态 |

用户可见文案不包含 API Key、沙盒绝对路径、底层 `NSError`。真机诊断只走 debug logger。

---

## 7. 测试

### 7.1 单元（Swift Testing）

- `setBpm` / `bump`：80 连 `bump(1)` 三次为 83，再 `bump(-1)` 为 82；39 → 40；201 → 200；已在边界再 bump 不变
- `PracticeClipQuery`：已删 recording 不出现；音频/视频分类正确；两个 session 的片段按 `createdAt` 倒序；重复 id 只留一条
- `RecordingStore.fileExists`：写入后 true，删除后 false
- Coordinator：`applyCategory` 失败时 need 计数与调用前相同；成对 acquire/release 后 need 为空。用测试缝注入失败的 `apply`，不在单测里依赖不稳定的真机路由

任务隔离由 `@Query` 保证，不做 UI 单测；用 store 已有测试证明 session 带 `taskId`。

### 7.2 状态机 / 集成

- start → stop → start 后 `engine.isRunning == true` 且 `isPlaying == true`
- `start()` 失败：`isPlaying == false`，timer 未跑
- 连续切换不留下第二份 pump（stop 后 `pump == nil`）
- 已有 `.record` need 时再 acquire `.playback`，category 仍为 `.playAndRecord`
- 打断后手动 start 可以再次 running

模拟器不能代替真机有声验收。

### 7.3 真机矩阵（DoD）

- iPhone 内置扬声器
- 有线或蓝牙路由至少一种
- 录音过程中启动 / 暂停节拍器，录音不被打断
- App 前后台
- 来电或闹钟类打断
- 连续 10 次开始 → 暂停 2 秒 → 开始，300 ms 内有声，计时连续
- 暂停后把 BPM 调到 83 再开始，按 83 走
- 保存录音、现场视频、相册视频后退出再进入同一任务，对应模式下列表可见
- 任务 A / B 媒体不串
- 人为删除沙盒文件后卡片为「文件缺失」，点诊断 toast 且不崩溃

现有 UI smoke 保持全绿。

---

## 8. 文案

`zh-Hans`，`String(localized:)`：

- 降低 1 BPM / 提高 1 BPM
- 节拍器无法启动
- 文件缺失
- 文件不存在或已被移除
- 还没有录音 / 点上方「录音」即可留下片段
- 还没有视频 / 点上方「录视频」即可拍摄或从相册导入

不改「开始」「暂停」「RESET」「完成本次练习」。

---

## 9. 明确不做

- 长按 ± 连续调速、±5 快调
- 按 session / 日期分组、折叠、分页
- 练中播放、删除、重命名
- 恢复被杀进程的 `openSessionId`（不把上一条 session 接着录）
- 新 Schema、云同步
- 系统打断后自动恢复节拍器
- 为历史媒体单独做第二套卡片样式

Cut line：先裁 P2 分组分页，再裁 P1 长按；不裁真机暂停恢复、任务隔离、缺失文件错误态。

---

## 10. 实现落点

- `MetronomeEngine` — graph / start 拆分，`start()` throws，失败不置 `isPlaying`
- `AudioSessionCoordinator` — acquire 失败回滚；可测的 apply 缝
- `PracticeClipQuery` — 新文件，纯函数
- `RecordingStore` — `fileExists(fileName:)`
- `PracticeDetailView` — `bump(±1)`、`togglePlay` 失败处理、`visibleClips`、绝对时间、空态、缺失标记、present 前检查
- `RecordDetailView` — 播放 / 诊断前检查
- `Localizable.xcstrings` — §8 文案
- `docs/TECHNICAL.md` §5.2 — 补「暂停释放会话后必须确认 `engine.isRunning`」
- 测试：`MetronomeEngineTests`、`PracticeClipQueryTests`、Coordinator 回滚测试、`RecordingStore` 存在性

验收对齐产品 PRD AC-1～AC-8。
