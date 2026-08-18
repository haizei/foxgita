# Design: 录像分段诊断（练后 AI 分析升级）

> 功能需求目录：[`../`](../)。本文为设计规格。

**日期：** 2026-08-18  
**状态：** Approved — awaiting implementation plan  
**产品功能：** `design-boards/gita-ai-design-workflow.html` → 产品功能 · 录像 AI 分析诊断  
**Figma：** [05_Product Flow_AI Recording & Video Coaching](https://www.figma.com/design/smeuuUaTOYE1URHhIGbzyd/%E5%90%89%E4%BB%96%E8%AE%AD%E8%AE%B0app?node-id=531-270) 节点 `531:270`；本轮对齐 **C2/04 AI 分段分析**、**C2/05 分段诊断**、**S2 分析失败**  
**升级对象：** [练后媒体复盘](../../2026-08-15-media-review/specs/2026-08-15-media-review-design.md) 的**录像**链路；录音三段复盘不变  
**触发：** 以 [练习详情片段卡](../../2026-08-15-practice-clip-cards/specs/2026-08-15-practice-clip-cards-design.md) 为准：停录即落库并入队；「完成」不二次入队、不再出旧处理 Sheet  
**方案：** 方案 1 — 本地加密帧 + 波形，走现有 Vision 通道；findings JSON 挂在 `RecordingRef` 上；不上传 `.mov`

---

## 1. 背景与目标

录像复盘已经能跑：抽 3 帧走 Vision，在 `RecordingRef` 上写亮点 / 优先改善 / 下次练法。产品要把录像升级成**可定位的分段诊断**：时间点、证据、原因、可执行建议，并在分析结束后打开诊断页。录音继续只做三段陪伴复盘，不做诊断。

本轮不做完整陪练产品（相册上传、再录像对比、App 内相机、C2/06 纠错验证页）。

成功标准：

1. 有录像且 AI 三项配齐：入队后出现 C2/04；可后台返回；该条 `ready` 且人还在分析页时进入 C2/05。
2. C2/05 能按 finding 打点、点打点 seek、完整回放整段、「纠正片段」播放该问题 10–30 秒。不进入再录像。
3. 同一份结果可在记录详情「复盘」打开。录音复盘仍是三段卡。
4. 分析失败不丢 `.mov`；无明确问题不伪造打点。
5. 时间夹取、空 findings、401 停后续、V5 迁移可用单测覆盖。

---

## 2. 产品决策

| 项 | 选择 |
|---|---|
| 本轮范围 | 录像诊断结果页 + Figma 分析中/失败态。相册、再检测对比、纠错闭环下一轮 |
| 录音 | 仍写三段话；不进 C2/04 / C2/05 |
| 结果出现 | 分析完且人未离开 → C2/05；之后也可在「复盘」回看 |
| 底栏 | 「完整回放」播整段；「纠正片段」seek 到当前 finding 窗口。不进 C2/06 |
| 媒体怎么送 | 不上传原片。录像：最多 10 张 JPEG 帧 + 可选 1 张波形 |
| 落库 | findings JSON 挂在该条 `RecordingRef`（方案 A）。不新建诊断表 |
| 旧录像 | 不自动重跑。`ready` 且 findings 为空：复盘仍显示三段；诊断页只有总结；可手动重新分析 |
| 模型托管 | 与拍照生成、录音复盘同一套 Base URL / Model / Key |
| 录像入口 | 仍用系统相机。不做来源选择页、录像准备页、App 内预览录制 |

---

## 3. 架构

```text
停录 / 录像 ingest 成功（片段卡规格）
        ▼
落库 RecordingRef → pending → ReviewJobRunner.enqueue
        ▼
该条是 .mov 且已配 AI
        → present C2/04 VideoAnalysisView
        │
        ├─ 抽帧 + 波形（内存 JPEG）
        ├─ VideoDiagnosisClient（同一 chat/completions）
        └─ VideoDiagnosisDraft.normalize → 写回 findings + 三段摘要
        ▼
ready 且用户仍留在 C2/04 → push C2/05 VideoDiagnosisView
用户点「后台生成并返回」或顶栏返回
        → 关掉分析页，回到打开它的那一层（练习详情仍开着就留在练习详情）
        → 之后在复盘或片段卡「查看诊断」打开同一 C2/05

录音 .m4a：现有 MediaReviewGenerator → 三段话。不 present C2/04。
```

约束：

- **先落库再分析。** 杀进程不丢录像。
- **网络只在 Client。** View 不直接 `URLSession`。
- **不改 `VisionPracticeClient` 出题职责。** 录像诊断用新 draft / 提示词；URL 拼接与 `response_format` 重试与现有 Client 共用。
- **不改录音** `MediaReviewDraft` 三段契约。
- 帧和波形只在内存，请求结束即丢，不写入 Documents / SwiftData。
- 一条 `RecordingRef` 一次分析。多段录像仍按 Runner 顺序。
- 三行「前奏 / 主歌 / 副歌」是 **C2/04 本地阶段展示**，不是三次模型请求。

练习详情「完成」仍按片段卡规格：更新时长并回今天，**不**再出 C2/04、不二次入队。C2/04 只在停录入队时出现。若用户先后台关掉分析页再点完成，结果之后在复盘看。

---

## 4. 组件职责

| 单元 | 职责 | 依赖 |
|---|---|---|
| 停录 ingest（已有） | 落库、录像则 present C2/04 并入队 | Store、Runner、`LLMCredentialsStore` |
| `VideoAnalysisView` | C2/04 / S2：进度或失败；后台返回 | Runner、该 `RecordingRef` |
| `VideoDiagnosisView` | C2/05：播放器、时间线、问题卡、总结、回放 | 本地 `.mov`、findings |
| `ReviewJobRunner` | 原队列。录像走 `VideoDiagnosisGenerating` | Generator、Store |
| `VideoDiagnosisGenerator` | 加密帧 + 波形 + 调 Client | Client、AVFoundation、credentials |
| `VideoDiagnosisClient` | multimodal JSON；解析 `VideoDiagnosisDraft` | URLSession |
| `VideoDiagnosisDraft` | 摘要三段 + findings[]；normalize | — |
| `PracticeStore` | 写 findings JSON 与三段摘要；失败清字段 | Repository |
| `RecordDetailView` 复盘栏 | 录像卡「查看诊断」；旧格式三段 + 重新分析 | Runner、Store |
| 练习详情片段卡 | 录像 `ready`：「查看诊断」打开 C2/05；录音仍展开三段 | — |
| Settings · AI 区 | 文案保持：图片、波形图、录像帧发往用户接口 | 现有 |

媒介判定不变：扩展名 `.mov` → 录像诊断；其它 → 录音三段。抽帧失败则该条 `failed`。

---

## 5. 数据

### 5.1 Schema V5

`TaskItem` / `PracticeSession` 不变。`RecordingRef` 增加带默认值的字段，轻量迁移（同 V3→V4）：

| 字段 | 默认 | 含义 |
|---|---|---|
| `reviewFindingsJSON` | `"[]"` | 录像 findings 数组的 JSON。录音始终为 `[]` |

现有字段保留：`reviewStatusRaw`、`reviewHighlight`、`reviewFocus`、`reviewNextAction`。

计算属性 `videoFindings: [VideoFinding]`：反序列化失败视为 `[]`，不把状态改成 `failed`（坏数据在写入时已被 normalize 挡住）。

**`ready` 规则：**

- 录音：三段均非空，且 `videoFindings` 为空。
- 录像：三段均非空。`videoFindings` 可以为空（无明确问题）。

`pending` / `failed` / `none` 时：三段为空字符串，`reviewFindingsJSON` 为 `"[]"`（重试前清掉旧文案）。

### 5.2 模型输出 JSON（仅录像）

```json
{
  "highlight": "前奏节奏基本稳定",
  "focus": "F 和弦按弦不完整",
  "nextAction": "食指靠近品丝，慢速再练 8 小节",
  "findings": [
    {
      "startSec": 222,
      "endSec": 242,
      "title": "F 和弦按弦不完整",
      "evidence": "听到：2 弦有杂音",
      "cause": "食指离品丝太远",
      "action": "食指靠近品丝，保持手腕放松"
    }
  ]
}
```

规范化：

- 摘要三段 trim；任一段空 → 整条失败，不写半成品。每段最多 80 个 `Character`。
- `startSec` / `endSec` 夹到 `[0, durationSec]`（整数秒）。`end <= start` 时，`end = min(start + 20, durationSec)`。
- 「纠正片段」窗口：从 `startSec` 起播，长度为 `end - start` 再夹到 **10–30 秒**，且不超过 `durationSec - startSec`。若剩余时长 &lt; 10 秒，播到文件结尾。
- 最多 **5** 条 finding，按 `startSec` 升序。`title` / `evidence` / `cause` / `action` 任一空则丢掉该条。
- 丢掉后 `findings` 为空仍为 **ready**（无明确问题），摘要三段仍要有。
- 禁止采用超出时长的时间点。提示词要求：证据不足则少写或不写 finding，不编造打点。

### 5.3 HTTP

与现有复盘相同：

- `POST {base}/chat/completions`
- `model` + `messages`（system + user：文本 + `image_url` data-URL）
- 先带 `response_format: { "type": "json_object" }`；4xx 且 body 提及 format / unknown 时去掉该字段重试一次
- 超时由注入的 `URLSession` 控制（App 侧约 60s）

### 5.4 本地媒体准备（录像）

| 步骤 | 规则 |
|---|---|
| 帧 | 至少 3 帧（0% / 50% / 100%）。再按约 8 秒一帧补齐。合计最多 **10** 张 JPEG |
| 波形 | 能抽出音轨则加 1 张波形 JPEG；没有音轨就只发帧 |
| 压缩 | 最长边约 1280、quality ≈ 0.7（`PracticeImageCodec`） |
| 失败 | 抽帧全部失败 → `failed`，不发请求。部分帧失败则用成功的帧，少到 0 张才失败 |

文本上下文：任务标题、步骤、BPM、拍号、本次笔记、该片段 `durationSec`、媒介类型「录像」。没有的字段省略。

录音准备路径不改：1 张波形，三段 JSON。

---

## 6. UI 流程

视觉真源：Figma `531:270`。文案与层级按 C2/04、C2/05、S2，使用现有 Gita token（主操作橙 `#FF7925`）。

### 6.1 C2/04 · AI 分段分析

仅 `.mov` 入队时 present。

- 顶栏：返回 · 标题「AI 分段分析」
- 副标题：`{任务名} · 本次练习 {mm:ss}`
- 卡片：
  - 标题「正在按片段分析声音与手型」
  - 波形：已走完比例为橙色，其余灰色
  - 大号百分比
  - 状态句随阶段切换（抽帧：「正在提取声音与关键帧」；请求中：「正在按片段分析声音与手型」；写回：「正在建立前奏 / 主歌 / 副歌问题地图」）
  - 三行：前奏 · 节奏与拍点；主歌 · 和弦切换；副歌 · 动作与指法。右侧「分析完成 / 分析中 / 等待中」，点色绿 / 橙 / 灰
- 底栏：描边按钮「后台生成并返回」
- 脚注：「录制内容已安全保存」

**进度映射（单次请求）：**

| 本地阶段 | 百分比约 | 行 1 | 行 2 | 行 3 |
|---|---|---|---|---|
| 抽帧 / 波形 | 0–30 | 分析中 | 等待中 | 等待中 |
| HTTP | 30–90 | 完成 | 分析中 | 等待中 |
| 解析写回 | 90–99 | 完成 | 完成 | 分析中 |
| `ready` | 100 | 完成 | 完成 | 完成 |

百分比是阶段展示，不是真实字节进度。不要拆成三次 completions。

顶栏「返回」=「后台生成并返回」：关掉本页，Runner 继续，**不**调用完成练习、不强制回今天。人还在本页且该条变为 `ready` → 进入 C2/05。变为 `failed` → 切到 §6.3。

只录音、没有录像：不出现本页。

### 6.2 C2/05 · 分段诊断

- 顶栏：返回 ·「分段诊断」· 完成（橙色）
- 副标题：`{任务名} · {mm:ss}`
- 播放器：本地 `.mov`；上沿 `当前 / 总时长`；下沿「手部与琴颈回放」
- 时间线：按 `startSec / durationSec` 放打点（最多 5）。选中点更大。点下 `{mm:ss}` + 短标题（`title` 截到时间线两行能放下）
- 问题卡随选中 finding：**标题**；一行「{evidence} · 原因：{cause}」；浅橙块「纠正建议」+ `action`
- 胶囊：时间线（默认选中）| 总结。总结只把时间线+问题卡换成三段摘要（亮点 / 优先改善 / 下次练法），播放器保留
- 底栏：描边「完整回放」（seek 0 并播放到结束）；实心「纠正片段」（当前 finding 窗口）

无 finding：不画打点；展示「这次没有明确问题」+ 总结三段；「纠正片段」禁用，「完整回放」可用。

**导航：**

C2/05 顶栏「完成」只表示看完诊断，**不**调用 `finishSession`。

| 入口 | 返回 | 完成 |
|---|---|---|
| 从 C2/04 自动进入（练习未结束） | 练习详情 | 同返回 |
| 从练习详情片段卡「查看诊断」 | 练习详情 | 同返回 |
| 从记录详情「查看诊断」 | 记录详情 | 记录详情 |

「纠正片段」只在本页 seek 播放，**不** push C2/06。

旧录像 `ready` 且 findings 为空：本页等同无 finding；提供「重新分析」（未配置则 toast）。

### 6.3 S2 · 分析失败

人仍在 C2/04 且该条 `failed`：同一页切失败态。

- 标题「分析失败」/「这次分析未完成」
- 说明失败阶段：抽帧失败 / 网络或超时 / 无法解析。不展示服务端原文
- 主按钮「重新分析」：该条 `pending` 并 `enqueue([id])`，回到 C2/04 进度
- 脚注「录制内容已安全保存」

人已离开：不弹失败页。复盘栏按现有失败卡 +「重试」。

### 6.4 记录详情 · 复盘栏

子 Tab 仍是 `数据 | 录音 | 笔记 | 复盘`。录音栏只播放。

| 片段 | 展示 |
|---|---|
| 录音 任意状态 | 现有三段卡 / 未分析 / 分析中 / 未完成+重试 / 失败+重试 |
| 录像 `ready` 且 findings 非空 | 摘要：`focus` + `nextAction`；按钮「查看诊断」 |
| 录像 `ready` 且 findings 空 | 三段话 +「重新分析」 |
| 录像 `none` / `pending` / `failed` | 与现有状态机相同 |

### 6.5 设置

不新增配置项。AI 区说明保持：

> 图片、波形图和录像帧会发送到你填写的接口地址，费用由该服务商向你收取。Gita 不托管密钥。

---

## 7. 错误处理

| 情况 | 行为 |
|---|---|
| 未配置 | 不 present C2/04；复盘或诊断页点生成/重试 toast「先去设置里填写 AI 接口」 |
| 文件不在磁盘 | 该条 `failed`，继续下一条 |
| 抽帧/波形全部失败 | 该条 `failed`，不发请求 |
| HTTP 401/403 | 本条及**本 job 尚未开始的**都 `failed`；已 `ready` 的不动 |
| 超时 / 传输失败 | 仅本条 `failed`，后面继续 |
| JSON 无法解析 / 摘要空段 | 仅本条 `failed` |
| App 被杀 | 未跑完保持 `pending`；`pending && !isRunning` →「未完成」+「重试」 |
| 离线 | 记录已在本地；不自动在恢复网络时重跑 |
| 对正在分析的同一条再点重试 | 忽略 |
| 无明确问题 | `ready` + 空 findings；C2/05 不打点 |

---

## 8. 测试

P0：

- Unit：`VideoDiagnosisDraft.normalize`（合法 findings、夹时间、`end <= start` 补 20 秒、缺字段丢条、最多 5 条、空 findings + 非空摘要通过、空摘要失败、超长截断）。
- Unit：`VideoDiagnosisClient` + mock URLProtocol（成功 JSON / 坏 JSON / 401 / `response_format` 重试）。
- Unit：`VideoDiagnosisGenerator`（未配置、缺文件、抽帧失败、成功返回 draft）。
- Unit：`ReviewJobRunner` 录像路径（pending→ready 含 JSON；401 停后续；重试只动一条）。
- Unit：Schema V5 轻量迁移后旧 `RecordingRef` 的 `videoFindings` 为空且 `reviewStatus` 保持原值。
- Unit：录音 `MediaReviewDraft` / 现有 Client 测试保持全绿。

可选：

- UI 冒烟：复盘栏录像 `ready` 可见「查看诊断」（不测真网络、不测相机）。

---

## 9. 非目标

- 相册上传分支（Figma ALBUM / 01–04）
- 选择视频来源页、录像准备页、App 内安静录制页（C2/01–03）
- C2/06 纠错验证、再录像、改正前后对比、S4 纠错完成
- 录音 AI 分段诊断
- 上传 `.mov` / `.m4a`
- 三次真实模型请求对应前奏/主歌/副歌
- 按 session 合成一条总诊断
- 启动时回扫历史录像做补分析
- 实时陪练、「录制时反馈」
- 自有后端、账号、流式输出、Apple on-device Intelligence

---

## 10. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 帧不够，时间点偏差 | 加密帧 + 夹到时长内；文案不承诺精确鉴定；证据不足允许 0 条 finding |
| 兼容端点不收图或 JSON mode | 与现有复盘同一套重试；失败可换模型 |
| 最多 10 帧费用高于 3 帧 | Settings 已有费用说明；顺序请求；可后台离开 |
| C2/04 百分比被理解成真进度 | 规格写明阶段映射；不展示虚假的上传字节 |
| 与片段卡触发冲突 | 本规格明确：入队点在停录；完成不二次出分析页 |
| 密钥/帧外泄 | Key 仅 Keychain；帧不落盘；不打媒体日志 |

---

## 11. 实现落点

已有：片段卡 ingest、`ReviewJobRunner`、`MediaReviewGenerator`（录音）、`RecordingRef` 三段字段、记录详情复盘栏、系统相机录像。

本次需改/建：

- `Models.swift` — Schema V5 + `reviewFindingsJSON` + 迁移
- 新建 `VideoDiagnosisDraft` / `VideoDiagnosisClient` / `VideoDiagnosisGenerator`（或给 Generator 增加录像分支，录音路径零行为变化）
- `PracticeStore` — apply 录像 draft（JSON + 三段）
- `ReviewJobRunner` — `.mov` 走录像 Generator
- 新建 `VideoAnalysisView`（C2/04 + S2）、`VideoDiagnosisView`（C2/05）
- 练习详情：录像入队后 present 分析页；片段卡「查看诊断」
- `RecordDetailView` — 录像复盘卡
- `Localizable.xcstrings`
- 对应 `foxgitaTests`
- `docs/TECHNICAL.md` — V5 与录像诊断

---

## 12. 方案备选摘要

- 本轮范围：诊断结果页（采纳）；完整 14 屏产品（不采纳）；先做入口和上传、结果仍三段（不采纳）。
- 录音：继续三段（采纳）；停用录音分析（不采纳）。
- 结果出口：C2/05 + 复盘回看（采纳）；只放复盘栏（不采纳）。
- 纠正片段：本页 seek 播放（采纳）；隐藏按钮（不采纳）。
- 媒体：加密帧 + 波形、不传原片（采纳）；仍 3 帧猜时间（不采纳）；本轮上传原片（不采纳）。
- 落库：`RecordingRef.reviewFindingsJSON`（采纳）；独立诊断实体（不采纳）。
- 分析 UI：Figma C2/04（采纳）；沿用旧片段列表 Sheet（不采纳）。
