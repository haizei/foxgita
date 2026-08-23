# Design: 练习工作台（上次速度 + 当场回放 + 完成回传）

> 功能需求目录：[`../`](../)。本文为设计规格。

**日期：** 2026-08-23  
**状态：** Approved — implementation plan in ../plans/2026-08-23-practice-workbench-resume.md  
**方案：** 方案 B — 抽出可测核心，页面只绑定  
**产品来源：** `design-boards/产品PRD/练习工作台/2026-08-23-Gita-练习工作台-上次状态与当场回放-PRD.md`  
**升级对象：** [练习详情片段卡](../../2026-08-15-practice-clip-cards/specs/2026-08-15-practice-clip-cards-design.md) 与 [练习详情稳定性](../../2026-08-19-practice-detail-stability/specs/2026-08-19-practice-detail-stability-design.md) 中「练中播放不做」  
**页面身份：** 练习详情是当前这一项的工作台，不是跟练台，也不是记录档案

---

## 1. 背景与目标

练习详情已经能开练、能录、能列出该任务历史媒体，但三次打开互不相关：BPM 回到 `task.defaultBpm`，上次焦点不出现，刚录的音频必须去记录详情才能听，完成只置 `returnPracticeToToday`。

产品已锁定：再次进入同一任务，默认接着上次的速度。

成功标准：

1. 有历史时，进入详情后节拍器等于最近一条有效 session 的 BPM；无历史时用 `defaultBpm`，不出现「上次」行。
2. 焦点行只展示，不预填笔记框；有 `reviewNextAction` 用它，否则用上次笔记首行；都空则不渲染该行。
3. 录音模式下列表可在本页播放文件存在的音频；视频用系统全屏播放器，必须有画面。
4. 点「完成」且有效：写回 `defaultBpm`，Router 带上刚保存的 session id，今天首页出现「刚刚完成」。
5. 点「返回」即使已留下 session：落库、写 BPM，不出成果卡。
6. 「再练一次」开新 session，不改写刚完成那条；「查看记录」进该任务记录详情。

---

## 2. 产品决策

| 项 | 选择 |
|---|---|
| 页面身份 | 练习工作台 |
| 再进同一任务 | 接着上次速度。不问、不弹窗、不做「从慢速重新开始」 |
| 改速出口 | 现有加减号。不锁定 |
| BPM 进入信源 | 最近有效 session 的 `bpm`，否则 `defaultBpm`，再钳 `40...200` |
| 「最近」 | session 按 `endedAt` 倒序 |
| 有效口径 | `PracticeRecordRules.isEffective` |
| 焦点 | 只展示。优先最近非空 `reviewNextAction`（按 `createdAt`），否则上次有效 session 笔记首行，约 28 字截断 |
| 笔记框 | 保持空，不预填 |
| 练中播放 | **做。** 覆盖 8-15 / 8-19「播放不做」 |
| 视频播放 | 系统全屏（`AVPlayerViewController`）。禁止只有音轨 |
| 删除片段 | 仍不做 |
| 点返回（已有 session） | 安静保存，写 BPM，**不出**成果卡 |
| 点完成（有效） | 写 BPM + `lastCompletedSessionId` + 回今天 + 成果卡 |
| 空完成 | 现有 toast，不写 BPM，不写 id，无成果卡 |
| 从过去日完成 | 回今天，成果卡出在今天 |
| 查看记录 | 该任务 `RecordDetailView`。不扩单次 session 路由 |
| 成果卡位置 | 今天任务列表上方，低于问候/周历，高于任务行 |
| 成果卡存储 | 只活在 `AppRouter`，不进 UserDefaults |
| Schema | 不改 |

---

## 3. 架构

```text
PracticeResumeQuery（纯函数）
  sessions + recordings + defaultBpm
    → bpm
    → focus?          （下一练法或笔记首行）
    → hasHistory

PracticeDetailView.onAppear
  metronome.setBpm(resume.bpm)
  焦点行 ← hasHistory ? 文案(bpm, focus) : 不渲染
  noteText = ""

媒体卡播放
  音频 → AudioPlayerService.toggle
  视频 → 系统全屏 AVPlayer，dismiss 后 release(.playback)
  缺失 → toast，不 present

PracticeStore
  finishSession / updateOpenSession → task.defaultBpm = clamp(bpm)
  beginOpenSession → 不写 defaultBpm

AppRouter
  lastCompletedSessionId 只在点「完成」且有效时写入
  返回保存不写 id
  selectedTab 离开 practice、换日、再练/查看记录 → 清空

PracticeView（今天）
  有 lastCompletedSessionId → 按该 id 读 session 画「刚刚完成」
  禁止用「该任务最新一条」
```

职责：

| 单元 | 做什么 | 依赖 |
|---|---|---|
| `PracticeResumeQuery` | BPM、焦点、是否有历史、焦点行文案 | 无 SwiftUI、无 SwiftData、无 AV |
| `PracticeDetailView` | 绑定恢复、焦点行、播放、完成/返回 | ResumeQuery、Store、AudioPlayerService、Router |
| `PracticeStore` | 完成/更新时写回 `defaultBpm` | Repository、现有钳制 40…200 |
| `AppRouter` | `lastCompletedSessionId`；离练习 Tab 清空 | 无 |
| `PracticeView` | 今天列表上方成果卡；再练一次 / 查看记录 | Router、@Query sessions |
| `AudioPlayerService` | 音频 toggle；详情复用 | Coordinator |
| `VideoPlayerPresenter`（薄封装） | present 系统全屏；关闭后 release | AVKit |
| `JustCompletedCard` | 展示刚完成 session | 只吃 session 快照，不猜 |

不改：Schema、`PracticeClipQuery.visible` 列表口径、停录即落库、`openSessionId` 只决定写入哪条 session、空完成不落库。

进入时以最近有效 session 为准，不是只信 `defaultBpm`。写回是为了任务字段与上次速度一致，并让无 session 查询时的回退不回到模板值。老用户升级后第一次进入即可接上，不必先再完成一次。

---

## 4. `PracticeResumeQuery`

入参用 descriptor，不持有 SwiftData 模型。

```text
ResumeSession
  id: String
  endedAt: Date
  bpm: Int
  noteText: String
  deletedAt: Date?
  durationSec: Int
  recordingCount: Int

ResumeRecording
  id: String
  createdAt: Date
  deletedAt: Date?
  reviewNextAction: String

ResumeState
  bpm: Int
  focus: String?      // 不含「上次 N BPM」前缀
  hasHistory: Bool
```

```text
resume(sessions:defaultBpm:) -> ResumeState
focusLine(state:) -> String?
```

规则：

1. 丢掉 `deletedAt != nil` 的 session / recording。
2. session 有效 ⇔ `PracticeRecordRules.isEffective(durationSec:noteText:recordingCount:)`。
3. `hasHistory` = 存在至少一条有效 session。
4. `bpm` = 有效 session 按 `endedAt` 降序第一条的 `bpm`；否则 `defaultBpm`；再 `min(200, max(40, ·))`。
5. `focus`：
   - 未删除且 `reviewNextAction` 去空白非空的 recording，按 `createdAt` 降序第一条的原文；
   - 否则最近有效 session 的 `noteText` 去空白后第一行（按换行切），超过 28 个汉字截断加 `…`；
   - 否则 `nil`。
6. `focusLine`：
   - `hasHistory == false` → `nil`（整行不渲染）
   - 有历史、`focus == nil` → `上次练到 {bpm} BPM`
   - 有历史、有 focus → `上次 {bpm} BPM · {focus}`

View 把 `@Query` 已按 `taskId`、`deletedAt == nil` 收窄的 sessions 映成 descriptor。`recordingCount` 用该 session 未删除 recordings 的个数。不要在 View 里再写一套排序。

---

## 5. 练习详情

### 5.1 进入

`onAppear`（已有 task）：

1. `let state = PracticeResumeQuery.resume(...)`
2. `metronome.setBpm(state.bpm)`
3. 焦点行：`PracticeResumeQuery.focusLine(state:)` 非空才渲染
4. `steps` 仍来自 `task.steps`（现有）
5. `noteText` 保持 `""`

位置：副标题 / AI 摘要卡之下、节拍器卡之上。一行，`GitaFont.caption()` + `GitaTheme.textSecondary`。不做成第二张卡。可与「已从图片生成」同时出现，不合并。不提目标分钟、累计、进步。

无障碍：焦点行可读完整文案。

### 5.2 播放

覆盖稳定性规格 §5.5「练习详情不加播放」。

卡片右侧播放/暂停，对齐 `RecordDetailView`。`playingId` 来自本页的 `AudioPlayerService`。

| | 音频 | 视频 |
|---|---|---|
| 文件在 | `toggle(url:id:)` | 系统全屏播放器，有画面 |
| 文件不在 | toast「文件不存在或已被移除」 | 同左，不 present |
| 播放中再点同一条 | 停止 | 关闭全屏或暂停后停止 |
| 点另一条 | 先停上一条 | 先 dismiss 再 present |

视频禁止只启动 `AVPlayer` 不出画面（现有 `AudioPlayerService` 对 mov/mp4 的无层播放不得直接用于详情视频卡）。全屏 `onDismiss` 必须 `player.stop()` 且 `AudioSessionCoordinator.release(.playback)`。

打断关系：

- 开始录音、打开 `VideoSourceView` / 相机：先停回放
- 节拍器在响时点回放：`metronome.stop()`，**不** `practiceTimer.pause()`
- 离开详情：停回放
- AI 复盘 / 诊断入口保留；播放不替代它们
- 点诊断 / 分析仍先查文件（稳定性规格已有）

列表、空态、绝对时间、文件缺失标示仍按稳定性规格。

### 5.3 离开与完成

返回（现有 `requestExit`）：

- 停表、停节拍器、停录并 `persistPending`
- 已有 `openSessionId`：`updateOpenSession`（现将写回 `defaultBpm`），`leave()`，**不**写 `lastCompletedSessionId`
- 无 session 但有未保存工作：二次确认；放弃则不写回
- 无未保存工作：直接离开

完成（现有 `complete`）：

- 空完成：现有 toast「这次没有留下记录」；`returnPracticeToToday`；**不**写 `defaultBpm`；**不**写 `lastCompletedSessionId`
- 有效：`finishSession` 或 `updateOpenSession` 成功后写入 **该次保存的 session id**；`returnPracticeToToday`；回今天

从过去日进入再完成：仍 `returnPracticeToToday`，成果卡出在今天。

---

## 6. Store 写回

在成功的 `finishSession` 与 `updateOpenSession` 里，于写 `task.steps` 的同一事务：

```text
task.defaultBpm = min(200, max(40, bpm))
```

`finishSession` 成功时改为返回新建 session 的 `id`（`String?`），失败 `nil`。无事先 `openSessionId`、只靠计时或笔记完成时，详情必须用这个返回值写 Router，不能再读「最新一条」。现有只关心 Bool 的测试改为断言 id 非空或失败为 nil。

`beginOpenSession` 不写 `defaultBpm`（试录尚未结束）。`appendRecording` 不写。空完成走现有 `isEffective` 失败路径，不调用写回。

钳制只在这一处或复用 `MetronomeEngine` 的范围常量；View 不维护范围。

---

## 7. 首页「刚刚完成」

### 7.1 Router

```text
AppRouter
  lastCompletedSessionId: String?
  returnPracticeToToday: Bool   // 已有
```

写入：仅 `PracticeDetailView.complete` 在有效保存成功之后。id 必须是刚保存那条，禁止首页按 `endedAt` 取最新。

清空：

- 点「再练一次」或「查看记录」
- `selectedTab` 离开 `.practice`（`MainTabView` 或 Router 侧 `onChange`，不要依赖 Tab 子页 `onDisappear`——Tab 可能保活）
- `PracticeView.selectedDay` 不再是今天
- 进程被杀（内存态自然丢）

不写 UserDefaults。

### 7.2 卡片

仅当 `isSelectedToday && lastCompletedSessionId != nil` 且能查到未删除的该 session。id 指向已删或找不到：清空 id，不渲染，不 toast。

内容只读该 session：

| 元素 | 规则 |
|---|---|
| 任务名 | `session.taskTitle` |
| 分钟 | `durationSec == 0` 且有笔记或媒体 →「不足 1 分钟」；否则 `ceil(durationSec / 60)` +「分钟」 |
| 摘要 | 有笔记写「笔记」；录音条数 > 0 写「录音 N」；视频条数 > 0 写「视频 N」。没有的类型不写「0 条」。用「·」拼接 |

位置：今天任务列表上方。一张次级卡，不是主行动。

操作：

| 按钮 | 行为 |
|---|---|
| 再练一次 | 记下 `taskId`；清空 id；`practicePath = [.detail(taskId:)]`。进入后走 §5.1，BPM/焦点来自刚完成这条 |
| 查看记录 | 记下 `taskId`；清空 id；`selectedTab = .record`；`recordPath = [.detail(taskId:)]` |

「再练一次」不得复用或改写 S1。新录音走新的 `beginOpenSession`。

---

## 8. 错误处理

| 情况 | 行为 |
|---|---|
| 无有效 session | BPM = `defaultBpm`；无焦点行 |
| 最近 session 无效、更早的有效 | 用更早那条的 BPM / 笔记规则 |
| 文件缺失点播放 | toast「文件不存在或已被移除」；不崩溃 |
| 全屏播放器关闭 | release playback；节拍器可再次 start（回归稳定性：再开始有声） |
| 回放中开始录音 | 先停回放，再走现有录音 |
| 有效完成但 Router 写入前失败 | 以 Store 成功为准；若 id 没带上，不出成果卡，不猜最新一条 |
| 成果卡 session 已软删 | 清空 id，不渲染 |
| 空完成 | 现有 toast；无卡；`defaultBpm` 不变 |

用户可见文案不含沙盒路径、底层 `NSError`。

---

## 9. 测试

### 9.1 单元

`PracticeResumeQuery`：

- 无 session → `hasHistory == false`，bpm = default，`focusLine == nil`
- 有效 session bpm 63、default 80 → bpm 63，`上次练到 63 BPM`
- 无效 session（0 时长、空笔记、0 媒体）+ 更早有效 70 → 用 70
- 已删 session 当不存在
- 笔记与 `reviewNextAction` 同时有 → 用 nextAction，且按 recording `createdAt` 最新
- 笔记多行只取第一行；`String.count`（扩展字形簇）长于 28 截断
- bpm 39 / 201 钳到 40 / 200

Store：`finishSession` / `updateOpenSession` 写回 `defaultBpm`；`beginOpenSession` 不写；空完成不写。

Router：空完成路径不设 `lastCompletedSessionId`（可用现有 store 测试 + 薄封装，或 View 层测注入的 router）。

### 9.2 UI / 集成

- 完成 → 今天 + 成果卡字段来自 S1 不是 S0
- 再练一次进入详情后完成，新 id ≠ S1，S1 未被改写
- 返回有 session：回今天无成果卡；再进详情 BPM 为返回时的速度
- 从过去日完成：选中日变成今天且有卡
- 切到记录 Tab 再回练习：无卡
- 录音列表点播放出声，不必进记录详情

### 9.3 真机

- 扬声器回放刚录的 m4a
- 回放后点开始，节拍器 300 ms 内有声（回归）
- 节拍器播放中点回放：节拍停、计时继续；停回放后可再开始节拍器
- 视频全屏有画面；关闭后再开节拍器有声
- 缺失文件 toast

现有 UI smoke 保持全绿。

---

## 10. 文案

`zh-Hans`，`String(localized:)`：

- 上次练到 %lld BPM
- 上次 %lld BPM · %@
- 刚刚完成
- 不足 1 分钟
- %lld 分钟
- 笔记 / 录音 %lld / 视频 %lld
- 再练一次
- 查看记录
- 文件不存在或已被移除（已有）

不改「开始」「暂停」「完成」「完成本次练习」「这次没有留下记录」。

---

## 11. 明确不做

- 拍号切换、引擎按 `timeSig` 重音
- 步骤勾选、当前步、按步计时
- 节拍器与计时解耦、count-in、细分音、换音色
- BPM 长按、媒体按日分组
- 自研相机、片内预览窗、删除/重命名片段
- 笔记框预填上次正文
- 工作台内项目归属、`next_session` 接到完成
- 单次 session 记录详情路由
- 成果卡持久化、重启再庆祝
- 返回也出成果卡
- 新 Schema、云同步

Cut line：若必须拆发布，先 ResumeQuery + 进入恢复 + Store 写回 + 音频播放；成果卡 UI 可下一班。不可只做成果卡却猜最新 session。视频全屏可紧跟音频，不阻塞音频验收。

---

## 12. 实现落点

- `PracticeResumeQuery` — 新文件，纯函数
- `PracticeStore.finishSession` — 写回 `defaultBpm`，成功返回 session id
- `PracticeStore.updateOpenSession` — 写回 `defaultBpm`
- `AppRouter` — `lastCompletedSessionId` + 离练习 Tab 清空
- `PracticeDetailView` — onAppear 恢复、焦点行、播放、完成写 id
- `PracticeView` — `JustCompletedCard`
- `MainTabView` 或 Router — tab 切换清空
- 视频全屏薄封装（新文件或详情 private）
- `Localizable.xcstrings` — §10
- `docs/TECHNICAL.md` §4.1 — 完成回传 session id；详情进入恢复上次 BPM
- 测试：`PracticeResumeQueryTests`、Store 写回、现有 `PracticeStoreTests` / UI smoke

验收对齐产品 PRD AC-1～AC-12，以及本文 §2 对返回 / 查看记录 / 过去日的锁定。
