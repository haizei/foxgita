# Design: 练后媒体复盘（录音 / 录像 → 大模型建议）

> 功能需求目录：[`../`](../)。本文为设计规格。

**日期：** 2026-08-15  
**状态：** Implemented；触发与完成路径见修订规格 [练习详情片段卡](../../2026-08-15-practice-clip-cards/specs/2026-08-15-practice-clip-cards-design.md)  
**Figma：** [05_Product Flow](https://www.figma.com/design/smeuuUaTOYE1URHhIGbzyd/%E5%90%89%E4%BB%96%E8%AE%AD%E8%AE%B0app?node-id=58-2) 中 `Flow / AI Recording & Video Coaching`（节点 `264:267`）与主流程第 8–10 屏  
**范围：** 每条录音/录像一次大模型分析，结果写在 `RecordingRef` 与记录详情「复盘」栏。**完成即分析 / 处理 Sheet / 返回丢掉录音** 已由片段卡规格覆盖。  
**方案：** 方案 2 — 复盘挂在 `RecordingRef`；走现有 Vision 通道（波形图 / 关键帧 + 文本），不传完整音视频

---

## 1. 背景与目标

练习详情已能录音（`.m4a`）和录像（`.mov`），完成时挂到 `PracticeSession.recordings`。记录详情可回放。设置里已有用户自备的 OpenAI-compatible 通道（`VisionPracticeClient` + `LLMCredentialsStore`），目前只用于「拍照生成练习」。

Figma 画了完整 AI 陪练（选媒介、实时轻反馈、时间线打点）。本规格**不实现**实时陪练。只做练后分析：把媒体变成模型能吃的图片，生成三段建议，按片段落库。

成功标准：

1. 完成本次练习且有媒体、AI 三项配齐：先落库，再出处理 Sheet；可后台；结束后回今天练习列表。
2. 每条录音/录像各有一条复盘（亮点 / 优先改善 / 下次练法）或明确失败，可按条重试。
3. 没配 AI 或没有媒体：完成流程与现在相同。
4. 解析、状态机、401 停后续，可用 mock HTTP 单测。

---

## 2. 产品决策

> 触发、完成 Sheet、返回是否丢掉录音：以 [练习详情片段卡](../../2026-08-15-practice-clip-cards/specs/2026-08-15-practice-clip-cards-design.md) 为准。下表保留当时决策。

| 项 | 选择 |
|---|---|
| 范围 | 练后复盘；不做实时陪练、轻复盘 Sheet、时间线、「加入下次练习」 |
| 触发 | 完成即分析（有媒体且已配 AI） |
| 结果出现位置 | 只在记录详情第四栏「复盘」；完成后回今天列表 |
| 分析单位 | **每条** `RecordingRef`，不按 session 合成一条 |
| 媒体怎么送 | 现有 Vision 通道：录音 → 1 张波形 JPEG；录像 → 3 帧 JPEG；加任务文本 |
| 复盘字段 | 亮点、优先改善、下次练法 |
| 旧记录 | 不自动补分析；`none` 时可手动「生成复盘」 |
| 模型托管 | 与拍照生成同一套 Base URL / Model / Key |

---

## 3. 架构

```text
PracticeDetailView.complete
        ▼
PracticeStore.finishSession          ← 先落库；有媒体则相关 RecordingRef → pending
        ▼
（有媒体且 isConfigured）
ReviewGenerationSheet               ← 只展示进度
        │
        ▼
ReviewJobRunner（App 级，不随 Sheet 销毁）
        ▼
按片段顺序：
  MediaReviewGenerator              ← 波形或抽帧 + 任务/笔记/BPM/时长
        ▼
  MediaReviewClient                 ← 同一 chat/completions
        ▼
  MediaReviewDraft.normalize
        ▼
  写回该 RecordingRef（ready 或 failed）
        ▼
Sheet 关闭或「后台生成并返回」→ 今天练习列表
```

约束：

- **先落库再分析。** 杀进程不丢录音/录像。
- **网络只在 Client。** View 不直接 `URLSession`。
- **不改 `VisionPracticeClient` 的出题职责。** 新建 `MediaReviewClient`；URL 拼接与 `response_format` 重试可抽共享辅助函数。
- **波形图和帧只在内存**，请求结束即丢，不写入 Documents / SwiftData。
- 分层：View → Runner / Store → Generator → Client。

---

## 4. 组件职责

| 单元 | 职责 | 依赖 |
|---|---|---|
| `PracticeDetailView.complete` | 落库后决定是否出 Sheet；无媒体/未配置则直接回今天 | Store、`LLMCredentialsStore`、Runner |
| `ReviewGenerationSheet` | 展示本次 job 的片段状态；「后台生成并返回」 | Runner |
| `ReviewJobRunner` | App 级队列：顺序分析；401 停后续；重试单条 | Generator、Store |
| `MediaReviewGenerator` | 按扩展名准备图片 + 文本上下文；调 Client | Client、credentials、AVFoundation |
| `MediaReviewClient` | 组装 multimodal 请求、超时、解析 JSON | URLSession |
| `MediaReviewDraft` | `highlight` / `focus` / `nextAction`；normalize | — |
| `PracticeStore` | 写 `RecordingRef` 复盘字段；读任务上下文 | Repository |
| `RecordDetailView` | 第四栏「复盘」；按条生成/重试 | Runner、Store |
| Settings · AI 区 | 说明改为：图片、波形图、录像帧会发到用户接口 | 现有 |

媒介判定：文件名扩展名 `.m4a` → 录音；`.mov` → 录像。其它扩展名按录音处理（只出波形；抽帧失败则该条 `failed`）。

---

## 5. 数据

### 5.1 Schema V4

`TaskItem` / `PracticeSession` 不变。`RecordingRef` 增加带默认值的字段，轻量迁移（同 V2→V3）：

| 字段 | 默认 | 含义 |
|---|---|---|
| `reviewStatusRaw` | `"none"` | `none` / `pending` / `ready` / `failed` |
| `reviewHighlight` | `""` | 亮点 |
| `reviewFocus` | `""` | 优先改善 |
| `reviewNextAction` | `""` | 下次练法 |

不存错误原文。失败卡用固定短句「生成失败，可重试」。

`reviewStatus` 计算属性读写 enum。`ready` 时三段均非空；`failed` / `pending` / `none` 时三段为空字符串（重试前清掉旧文案）。

### 5.2 模型输出 JSON

```json
{
  "highlight": "连续 3 轮节奏稳定",
  "focus": "F 和弦切换偏慢",
  "nextAction": "下次从 70 BPM 连续练习 3 轮"
}
```

规范化：

- 三段都 trim。
- 任一段空 → 整条失败，不写半成品。
- 每段最多 80 个 `Character`；超出截断。
- 不解析、不保存时间戳。提示词禁止编造「01:18」这类打点。

### 5.3 HTTP

与拍照生成相同：

- `POST {base}/chat/completions`（去尾 `/`；若已以 `/chat/completions` 结尾则不追加）。
- Body：`model` + `messages`（system + user：文本 + `image_url` data-URL）。
- 先带 `response_format: { "type": "json_object" }`；4xx 且 body 提及 format / unknown 时去掉该字段重试一次。
- 超时由注入的 `URLSession` 控制（App 侧约 60s）。

图片数量：录音 1 张波形；录像 3 帧。JPEG 最长边约 1280、quality ≈ 0.7。

### 5.4 本地媒体准备

| 媒介 | 准备 |
|---|---|
| `.m4a` | 用音频采样画一张波形图 → JPEG |
| `.mov` | 在 0% / 50% / 100% 时长各抽 1 帧 → 最多 3 张 JPEG |

抽帧或画波形失败 → 该条 `failed`，不发请求。

文本上下文（user 文本，非图片）：任务标题、步骤列表、BPM、拍号、本次笔记、该片段时长、媒介类型（录音/录像）。没有的字段省略，不编造。

---

## 6. UI 流程

### 6.1 完成练习

`complete` 仍先走现有有效记录规则。落库成功后：

| 条件 | 行为 |
|---|---|
| 空完成 | 现有 toast「这次没有留下记录」，回今天 |
| 有记录，无新媒体或未配 AI | 回今天，不出 Sheet |
| 有新媒体且已配齐 | 这些 `RecordingRef` 标 `pending`，弹出 `ReviewGenerationSheet`，Runner 入队 |

「新媒体」= 刚写入的本次 session 的 `recordings`。

### 6.2 处理 Sheet

对齐 Figma「5 · 共同分析与后台生成」，去掉假百分比和「节奏/和弦/动作」三行。

- 标题：生成练习复盘
- 副标题：`{任务名} · 本次练习`
- 列表：`录音 00:48` / `视频 00:24`，右侧「等待中 / 分析中 / 完成 / 失败」
- 主按钮：后台生成并返回
- 底注：录制内容已安全保存

没有「取消分析」。关掉 Sheet = 回今天，Runner 继续。全部结束后若 Sheet 仍开着，关掉并回今天。不进入轻复盘 Sheet，不跳记录详情。

### 6.3 记录详情 · 复盘栏

子 Tab：`数据 | 录音 | 笔记 | 复盘`。录音栏只播放，不加复盘文案。

复盘栏：该任务下所有未删 `RecordingRef`，按 `createdAt` 倒序。一张卡一条媒体。

| 状态 | 展示 |
|---|---|
| `none` | 「未分析」+「生成复盘」 |
| `pending` 且 Runner 正在处理该 id | 「分析中」 |
| `pending` 且 Runner 空闲（如杀进程后） | 「未完成」+「重试」 |
| `ready` | 三块：亮点 / 优先改善 / 下次练法 |
| `failed` | 「生成失败，可重试」+「重试」 |

无媒体：空态「还没有录音或录像」。

「生成复盘」与「重试」都把该条标 `pending` 并交给 Runner。未配置：toast「先去设置里填写 AI 接口」，状态改回原值（`none` 或 `failed`）。

### 6.4 设置

AI 区说明改为：

> 图片、波形图和录像帧会发送到你填写的接口地址，费用由该服务商向你收取。Gita 不托管密钥。

不新增配置项。

---

## 7. 错误处理

| 情况 | 行为 |
|---|---|
| 未配置 | 完成时不出 Sheet；复盘栏点生成/重试 toast「先去设置里填写 AI 接口」 |
| 文件不在磁盘 | 该条 `failed`，继续下一条 |
| 波形/抽帧失败 | 该条 `failed`，不发请求 |
| HTTP 401/403 | 本条及**本 job 尚未开始的**都标 `failed`；已 `ready` 的不动 |
| 超时 / 传输失败 | 仅本条 `failed`，后面继续 |
| JSON 无法解析 / 空段 | 仅本条 `failed` |
| App 被杀 | 未跑完保持 `pending`；复盘栏显示「分析中」，用户可再点（若 Runner 已不在跑，点「重试」等价于重新入队；`pending` 且 Runner 空闲时，复盘栏同时提供「重试」以免卡死） |
| 离线 | 记录已在本地；不自动在恢复网络时重跑 |
| 完成过程中重复点 | 现有 `isCompleting` 挡住 |
| 对正在分析的同一条再点重试 | 忽略 |

`pending` 且 Runner 未在处理该 id：卡片当失败可点「重试」（避免杀进程后永远「分析中」）。实现：Runner 暴露 `isRunning(id)`；UI 在 `pending && !isRunning` 时显示「未完成」+「重试」。

---

## 8. 测试

P0：

- Unit：`MediaReviewDraft.normalize`（合法三段、空段失败、超长截断）。
- Unit：`MediaReviewClient` + mock `URLProtocol`（成功 JSON / 坏 JSON / 401 / `response_format` 重试）。
- Unit：`MediaReviewGenerator`（未配置、抽帧/波形失败、Client 错误映射）。
- Unit：`ReviewJobRunner`（顺序 pending→ready/failed；401 停后续；重试只动一条；缺文件失败）。
- Unit：Schema V4 轻量迁移后旧 `RecordingRef` 的 `reviewStatus == .none`。

可选：

- UI 冒烟：记录详情可见「复盘」子 Tab（不测真网络、不测相机）。

---

## 9. 非目标

- 实时 AI 陪练、选媒介页、录音/录像准备页、练习中轻反馈
- 完成时的轻复盘 Sheet
- 时间线打点、波形上的可点标记、「加入下次练习」
- 上传原始音频/视频文件
- 按 session 合成一条总复盘
- 启动时回扫历史媒体做补分析
- 记录列表「AI 复盘已生成」徽章
- 自有后端、账号、流式输出
- Apple on-device Intelligence
- 改练习详情的录音中面板

---

## 10. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 波形/帧不够模型「听出」节奏 | 文案不承诺音准鉴定；建议是陪伴向；用户可改下次练法 |
| 兼容端点不收图或 JSON mode | 与拍照生成同一套重试；失败可换模型 |
| 一次练习很多片段 → 多次计费 | 顺序请求；Settings 费用说明；用户可后台离开 |
| 杀进程后卡在 pending | `pending && !isRunning` 显示「未完成」+「重试」 |
| 密钥/媒体帧外泄 | Key 仅 Keychain；帧不落盘；不打媒体日志 |

---

## 11. 实现落点

已有：`finishSession`、`RecordingRef`、`AudioRecorderService`、`VideoRecorderService`、`LLMCredentialsStore`、`VisionPracticeClient`（仅作传输参考）、记录详情三栏。

本次需改/建：

- `Models.swift` — Schema V4 + `GitaMigrationPlan`
- 新建 `MediaReviewDraft` / `MediaReviewClient` / `MediaReviewGenerator` / `ReviewJobRunner`
- `PracticeStore` — 更新复盘字段、提供任务上下文
- `PracticeDetailView` — 完成后出 Sheet
- 新建 `ReviewGenerationSheet`
- `RecordDetailView` — 第四栏
- `SettingsView` — AI 说明文案
- `foxgitaApp` / `MainTabView` — 注入 Runner
- `Localizable.xcstrings`
- 对应 `foxgitaTests`

---

## 12. 方案备选摘要

- 范围：练后复盘（采纳），完整 AI 陪练（不采纳）。
- 触发：完成即分析（采纳），仅手动（不采纳）。
- 展示：记录详情「复盘」栏（采纳），轻复盘 Sheet / 完整复盘页（不采纳）。
- 媒体：Vision 波形+帧（采纳），上传原片（不采纳），第一期只录音（不采纳）。
- 字段：三段（采纳），两段/一段（不采纳）。
- 落库：每条 `RecordingRef`（方案 2，采纳）；每 session 一条（方案 1，不采纳）；写入笔记（方案 3，不采纳）。
