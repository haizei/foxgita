# Design: 练习详情片段卡（停录即落库 + 练中复盘）

> 功能需求目录：[`../`](../)。本文为设计规格。

**日期：** 2026-08-15  
**状态：** Approved — implementation plan in `../plans/2026-08-15-practice-clip-cards.md`  
**Figma：** [05_Product Flow](https://www.figma.com/design/smeuuUaTOYE1URHhIGbzyd/%E5%90%89%E4%BB%96%E8%AE%AD%E8%AE%B0app?node-id=58-2) 录音 / 录视频按钮下方的摘要卡  
**范围：** 练习详情展示本次已录片段；停录即写入 `PracticeSession` / `RecordingRef` 并入队复盘；「查看复盘」在卡片内展开  
**修订：** 覆盖 [练后媒体复盘](../../2026-08-15-media-review/specs/2026-08-15-media-review-design.md) 中「完成即分析 / 处理 Sheet / 返回丢掉录音 / 结果只在记录详情」四条。Runner、Client、Generator、复盘字段、记录详情「复盘」栏仍按原文。

---

## 1. 背景与目标

练习详情能录音、录像，但停录后下面只有「本次已录 N 段」。Figma 在「录音 / 写笔记 / 录视频」下画了摘要卡（类型点、任务名 · 时长、分析副文、AI 状态、「查看复盘」）。

复盘管道已存在，但触发点在 `complete` → `finishSession` → 处理 Sheet。片段在完成前只活在 `recorder.pending` / `video.pending`，返回即删。

成功标准：

1. 停录且文件在磁盘：立刻有练习记录和片段行；已配 AI 则该条入队。卡片出现在对应模式下。
2. 「查看复盘」在练习详情卡片内展开三段；记录详情「复盘」栏仍可回看。
3. 「完成本次练习」只更新时长/笔记/步骤并回今天，不再出处理 Sheet，不再重复入队。
4. 已有片段时返回 = 保存后离开，不删文件。
5. 没配 AI：卡片仍在，无 AI 行。

---

## 2. 产品决策

| 项 | 选择 |
|---|---|
| 卡片内容 | Figma 摘要卡 + 练中可展开复盘 |
| 落库时机 | 停录即写 `RecordingRef`（先有 session） |
| 返回（已有片段） | 自动留下这条练习，不销毁 |
| 查看复盘 | 卡片内展开亮点 / 优先改善 / 下次练法 |
| 三个按钮 | 模式：先切换再二次点击才录/开相机 |
| 完成 | 收束后立刻回今天；无处理 Sheet |
| 未配置 AI | 只落库，不入队，无 AI 行 |
| 播放 / 删除 | 不做；回看在记录详情「录音」栏 |
| 实时陪练 / 时间线 / 加入下次 | 仍不做 |

---

## 3. 架构

```text
停录 / 录像 ingest 成功
        ▼
文件在磁盘？
        │ 否 → toast「录音没保存」，不写库
        ▼
openSessionId == nil ?
        │ 是 → beginOpenSession（新建 PracticeSession + 本条 RecordingRef）
        │ 否 → appendRecording（同一 session）
        ▼
落库成功 → 从 pending 去掉该 clip
        ▼
AI 已配置 → markReviewsPending + enqueue([id])
        ▼
卡片 @Query 该 session.recordings

完成 / 有 session 时返回
        ▼
updateOpenSession（时长、笔记、步骤、endedAt）
        ▼
回今天练习列表（不 present ReviewGenerationSheet，不二次 enqueue）
```

约束：

- **先落库再分析。** 与现有 Runner 相同。
- **`openSessionId` 只活在本次详情。** 杀进程后已写库的是一条已保存练习；再进详情是新的一次，下一段录音会开新 session。
- **不改** `VisionPracticeClient` 提示词、复盘三段字段、JPEG-only 通道。
- View 不直接 `URLSession`。

---

## 4. 组件职责

| 单元 | 职责 | 依赖 |
|---|---|---|
| `PracticeStore.beginOpenSession` | 建 session + 第一条 `RecordingRef`（clip id 原样），返回 session id | Repository |
| `PracticeStore.appendRecording` | 把 clip 挂到已有 session | Repository |
| `PracticeStore.updateOpenSession` | 更新时长 / 笔记 / 步骤 / `endedAt` / BPM | Repository |
| `PracticeDetailView` | 模式、停录落库、卡片、完成/返回 | Store、Runner、LLM 配置 |
| `SessionClipCard`（详情内 private 即可） | 摘要 + 可选展开三段 | `RecordingRef`、`ReviewJobRunner.isRunning` |
| `ReviewJobRunner` | 不变 | 已有 |
| `ReviewGenerationSheet` | 完成路径不再呈现；无其它入口后可删 | — |
| `finishSession` | 练习详情不再调用；测试或其它入口可保留 | 已有 |

`beginOpenSession` 参数对齐现有 `finishSession` 的任务快照字段（`taskId`、标题、类别、`startedAt`、当时的 `durationSec` / BPM / 拍号 / 步骤 / 笔记）加上这一条 clip。文件不在磁盘则返回 `nil`，不建 session。

`appendRecording`：session 找不到或文件不在 → `false`，已有行不动。

`updateOpenSession`：session 找不到 → `false`。已有录音的 session 即使此时 `durationSec == 0` 也有效（`PracticeRecordRules` 按录音数算）。

---

## 5. 练习详情

### 5.1 模式

`toolMode`: `audio` | `note` | `video`。点未选中的按钮只切换。

- 已选「录音」再点：开始或停止。停止成功后落库。
- 已选「录视频」再点：打开相机。ingest 成功后落库。
- 「写笔记」无二次动作，只显示笔记框。

从「录音」切走且正在录：先 `stop` 并落库，再切换。从「录视频」切走不取消已打开的相机（现有 dismiss 逻辑不变）。

录音进行中：现有红色「正在录音」条在列表上方。

### 5.2 卡片

只显示 `openSessionId` 对应 session 里、当前模式的片段（`.mov`/`.mp4`/`.m4v` 为视频，其余为录音），`createdAt` 倒序。

| | 录音 | 视频 |
|---|---|---|
| 点 | 橙（`GitaTheme.brand500`） | 蓝 |
| 眉题 | 录音记录 · 相对时间 | 视频记录 · 相对时间 |
| 主文 | `{任务名} · mm:ss` | 同左 |
| 副文 | 节奏与和弦切换分析 | 姿势、指法与节奏分析 |

相对时间用 `RelativeDateTimeFormatter`（`zh-Hans`），刚停录为「刚刚」。时长 `mm:ss`，与现有 `durationLabel` 一致。

空列表：不放假卡片，下面留白。

### 5.3 AI 行

仅 `LLMCredentialsStore.isConfigured` 时画：

| 状态 | UI |
|---|---|
| `ready` | 「AI 复盘已生成」+「查看复盘」 |
| `pending` 且 `isRunning(id)` | 「分析中」 |
| `pending` 且未在跑 | 「未完成」 |
| `failed` | 「生成失败」 |

未配置或 `reviewStatus == .none`：无 AI 行，卡片仍在。练中卡不提供「重试 / 生成」（避免和记录详情抢入口）。重试仍在记录详情「复盘」栏。

「查看复盘」展开该条的亮点 / 优先改善 / 下次练法；再点收起。同时只展开一张卡。

### 5.4 完成与返回

**完成：** 有 `openSessionId` → `updateOpenSession` 后回今天。无 session → 走现有 `finishSession`（无媒体的笔记/计时，或失败路径）。两边都不 present 处理 Sheet，不 `enqueue`。

**返回：**

- 有 `openSessionId`：不弹「放弃并返回」。`updateOpenSession` 后离开。
- 无 session 且有未保存计时/笔记：现有确认框，文案仍是会丢掉计时和笔记；确认后不建记录。
- 无 session 且无脏状态：直接离开。

---

## 6. 错误处理

| 情况 | 行为 |
|---|---|
| 停录/ingest 后文件不在 | 不写库，toast「录音没保存」（录像用「录像没保存」） |
| `beginOpenSession` 失败 | 不设 `openSessionId`；该 clip 留在 pending，返回时按现有规则丢掉 |
| `appendRecording` 失败 | 该段不入列表；已落库的不动；toast 同上 |
| 未配置 AI | 只落库，不入队 |
| 401/403 | 现有 Runner：本条 + 本批未开始 → `failed` |
| 抽帧/波形/JSON/传输失败 | 仅本条 `failed` |
| 杀进程 | session 已在；练中卡与复盘栏对卡住的 `pending` 显示「未完成」 |
| 0 秒无笔记无录音就返回 | 不建记录 |
| 已有 session 再返回/完成 | 更新字段；因已有录音，记录有效 |
| 完成 | 不重复 enqueue |

不打 API Key、不打媒体字节日志。

---

## 7. 测试

`PracticeStoreTests`（InMemory）：

1. `beginOpenSession` 写入 session + 一条 `RecordingRef`，id 等于 clip id。
2. 文件不存在 → 返回 `nil`，无 session。
3. `appendRecording` 挂第二条，不新建 session。
4. `updateOpenSession` 改笔记和时长。
5. 无 session、0 秒、无笔记、无录音的返回路径不建行（现有无效规则）。
6. 已有录音的 session，`durationSec == 0` 仍可 `updateOpenSession`。

`ReviewJobRunner` / Client / Generator / Migration 不因本规格重写。练习详情模式与展开不做 UI 单测。

---

## 8. 文案

`zh-Hans`，`String(localized:)`：

- 录音记录 / 视频记录
- 节奏与和弦切换分析 / 姿势、指法与节奏分析
- AI 复盘已生成 / 查看复盘 / 分析中 / 未完成 / 生成失败
- 录音没保存 / 录像没保存

不改「完成本次练习」。有 session 时返回不再使用「返回会丢掉本次计时、录音和笔记。」

---

## 9. 明确不做

- 练中播放、删除、重命名片段
- 练中「重试 / 生成复盘」
- 完成处理 Sheet、轻复盘 Sheet
- 实时陪练、时间线、「加入下次练习」
- 恢复被杀的 `openSessionId`（不把上一条未点完成的 session 接着录）
- 历史记录回填
- Schema V5（沿用 V4 字段）

---

## 10. 实现落点

- `PracticeStore` — `beginOpenSession` / `appendRecording` / `updateOpenSession`
- `PracticeDetailView` — 模式、落库、卡片、完成/返回
- 可能删除完成路径上的 `ReviewGenerationSheet` 呈现
- `PracticeStoreTests`
- `TECHNICAL.md` — `finishSession` 旁注明详情改为开局 session
- `Localizable.xcstrings`（若 Xcode 抽出）

不改：`MediaReviewClient` 提示词、`ReviewJobRunner` 入队语义、记录详情复盘栏状态表。
