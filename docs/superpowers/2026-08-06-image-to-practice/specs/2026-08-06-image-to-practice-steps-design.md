# Design: 图片生成练习任务（Photo to Practice）

> 功能需求目录：[`../`](../)。本文为设计规格。

**日期：** 2026-08-06（修订 2026-08-13）  
**状态：** Draft — UI 对齐 Figma `Flow / Photo to Practice`  
**Figma：** [05_Product Flow / Photo to Practice](https://www.figma.com/design/smeuuUaTOYE1URHhIGbzyd/%E5%90%89%E4%BB%96%E8%AE%AD%E8%AE%B0app?node-id=213-129)（节点 `213:129`）  
**范围：** 推荐练习入口 → 来源 Sheet（拍照/相册）→ 生成中 → 详情摘要  
**方案：** 薄客户端 + OpenAI-compatible 视觉模型；来源 Sheet 叠在推荐 Sheet 上

---

## 1. 背景与目标

练习步骤是 `TaskItem.steps: [String]`。用户要从乐谱、练习清单或手写照片生成一条可练、可改的任务。

Figma 四屏（相对 2026-08-06 初版）：

1. 推荐 Sheet 名称栏内的「拍摄/照片」芯片（不再用独立大按钮）
2. 来源 Sheet：拍照 / 从相册选择
3. 同一张 Sheet 切到生成中（展示用进度，一次 HTTP）
4. 详情带「已从图片生成」摘要；识别和弦与每步时长编码进现有字段

成功标准：

1. 设置里配好 Base URL / Model / API Key 后，可从推荐 Sheet 走完四屏并打开详情。
2. 拍照 1 张，相册最多 3 张；生成成功后关掉两层 Sheet，进入详情，步骤可再改。
3. 无后端、无账号；Key 只存本机；图片不落库；不改 SwiftData Schema。
4. 解析与建库可单测（mock HTTP）。

---

## 2. 产品决策

| 项 | 选择 |
|---|---|
| 图片内容 | 乐谱、练习清单、手写等通用看图总结 |
| 模型托管 | 用户自备 Key，图片发往用户配置的云端 |
| 入口 | 推荐练习 `RecommendSheet` 名称栏「拍摄/照片」 |
| 来源 | 拍照（1 张）或相册（最多 3 张） |
| 生成中 | 同一张 Sheet 分阶段展示；底层一次 `chat/completions` |
| 生成后 | 直接建任务并打开详情（无预览向导） |
| 详情摘要 | 不改 Schema：和弦进 subtitle，每步时长进步骤字符串 |
| API | OpenAI-compatible：Base URL + Model + API Key |
| 生成字段 | `title` + `category` + `targetMin` + `steps`（可选和弦编码进 subtitle） |

---

## 3. 架构

```text
RecommendSheet
  「拍摄/照片」
        ▼
PhotoPracticeSheet（来源 → 生成中，同一张 Sheet 两态）
        ▼
ImageStepGenerator（压缩 JPEG）
        ▼
VisionPracticeClient（一次 chat/completions）
        ▼
AIPracticeDraft.normalize
        ▼
PracticeStore.createFromAIDraft
        ▼
关掉两层 Sheet → PracticeDetailView（AI 摘要靠 subtitle / 步骤文案）
```

约束：

- **不改 SwiftData Schema**；复用 `TaskItem` / `StepCoding`。
- **图片不落库**：内存压缩后上传，请求结束即丢弃。
- **网络只在 Client**：View 不直接使用 `URLSession`。
- 分层遵循 TECHNICAL.md：View → Store / Generator → Client / Repository。

---

## 4. 组件职责

| 单元 | 职责 | 依赖 |
|---|---|---|
| Settings · AI 区 | Base URL、Model；写入/清除 API Key；隐私说明 | `LLMCredentialsStore` + `AppStorage` |
| `LLMCredentialsStore` | Keychain 读写 API Key；`isConfigured` | Security |
| `VisionPracticeClient` | 组装 multimodal 请求、超时、解析响应 | URLSession |
| `ImageStepGenerator` | 压缩图片 → 调 Client → Draft | Client + credentials |
| `AIPracticeDraft` | `title` / `category` / `targetMin` / `steps`；normalize | — |
| `PracticeStore.createFromAIDraft` | 写入 `TaskItem`；subtitle 含 `AI ·` 与可选和弦 | Repository |
| `RecommendSheet` | 名称栏「拍摄/照片」；未配置 toast；弹出 Photo Sheet | credentials |
| `PhotoPracticeSheet` | 来源选择、拍照/相册、生成中进度、取消 | Generator + Store |
| `PracticeDetailView` | subtitle 以 `AI ·` 开头时显示摘要卡与识别行 | 现有详情 |

配置存储：

- `AppStorage`：`gita.llm.baseURL`、`gita.llm.model`
- Keychain：API Key（`com.haizei.foxgita.llm`）
- `isConfigured`：三者 trim 后皆非空

---

## 5. 数据契约

### 5.1 模型输出 JSON

```json
{
  "title": "F 和弦转换",
  "category": "chord",
  "targetMin": 10,
  "steps": ["慢速按弦", "四拍切换", "跟节拍连贯"],
  "chords": ["C", "G", "Am", "F"],
  "stepMinutes": [2, 4, 4]
}
```

`chords` 与 `stepMinutes` 可选。解码失败或缺失时忽略，不整单失败。`stepMinutes` 与 `steps` 按下标对齐，多出的丢掉，缺少的不补。

规范化：

- `category`：必须是 `left|right|both|chord|scale|rhythm|song`；非法则回落为推荐 Sheet 当前分类。
- `targetMin`：夹紧 `1...60`；缺失则 `10`。
- `steps`：去空白；至少 1 条；最多 12 条；全空则 `["新步骤"]`。
- `title`：trim 后为空则「未命名练习」。
- **subtitle（Store 写入，不改 Schema）：**
  - 有和弦：`AI · {minutes} 分钟 · C · G · Am · F`
  - 无和弦：`AI · {minutes} 分钟`
- **步骤字符串：** 若对应 `stepMinutes[i]` 有效（≥1），写成 `{step} · {n} 分钟`；否则只保留步骤文案。

### 5.2 HTTP

- Base URL：用户填 API 根（如 `https://api.openai.com/v1`）。去尾 `/` 后 `POST {base}/chat/completions`。若已以 `/chat/completions` 结尾则不追加。
- Body：`model` + `messages`（system + user：文本指令 + 最多 3 张 `image_url` data-URL）。
- 先带 `response_format: { "type": "json_object" }`；4xx 且 body 提及 format / unknown 时去掉该字段重试一次。
- 超时由注入的 `URLSession` 控制（App 侧约 60s）。

### 5.3 图片处理

- 拍照：系统相机，**1** 张。
- 相册：`PhotosPicker`，`maxSelectionCount = 3`。
- 最长边约 1280px，JPEG quality ≈ 0.7，再 base64。
- 不写入 Documents / SwiftData。
- 权限：`NSCameraUsageDescription`（已有）、`NSPhotoLibraryUsageDescription`（已有）。

---

## 6. UI 流程

### 6.1 入口 — 推荐 Sheet

「创建自己的练习」名称行（Figma `QuickCreate/IntegratedInputAndDuration`）：

- 左：名称 `TextField`，占位「例如：F 和弦转换」
- 中：「拍摄/照片」芯片
- 分隔线
- 右：`－` / `{n} 分钟` / `＋`

下面「创建练习」只负责手填创建，不读图片。去掉独立的「从图片生成练习」大按钮。

点「拍摄/照片」：

- 未配置：toast「先去设置里填写 AI 接口」，不打开下一层
- 已配置：弹出 `PhotoPracticeSheet`
- 生成中：芯片禁用

### 6.2 来源 Sheet

标题「从图片生成练习」，右上「关闭」。

- 「选择图片来源」
- 「适合乐谱、练习清单和手写内容」
- **拍照**（浅橙）：「立即拍摄纸质内容」
- **从相册选择**（浅灰）：「选择截图或已有照片」
- 底栏：「识别完成后会直接生成练习页，你仍可修改内容」

关闭或取消选图：停在来源 Sheet（或回到推荐 Sheet 若点关闭），不创建任务。

### 6.3 生成中

选完图后，同一张 Sheet 切到生成中，不另开一页。

- 标题「正在生成练习」，右上「关闭」
- 「正在识别图片内容」
- 进度条：约 0→90%，请求结束再走完
- 三条**展示用**清单，按时间推进，不代表模型分步返回：
  1. 已识别和弦与节奏
  2. 正在拆分练习步骤
  3. 即将估算练习时长
- 底栏：「完成后将自动进入生成的练习页」

关闭：取消本次请求，回到来源选择，不建任务。生成中来源卡片不可点。

成功：关掉两层 Sheet；`selection = taskId`，沿用 `PracticeView` 的 pending 推详情。  
失败：回到来源 Sheet，toast，不关闭推荐 Sheet。

### 6.4 详情摘要

沿用 `PracticeDetailView`。subtitle 以 `AI ·` 开头时：

- 顶部摘要卡：「已从图片生成」；「识别出 N 个步骤，可直接修改」（N = 步骤数）
- 元信息：有和弦则「识别：C · G · Am · F」；右侧「目标 N 分钟」
- 步骤若含 ` · N 分钟`，右侧显示时长；编辑改整句
- 无和弦时不显示「识别：」行，不编造和弦
- 底部主按钮保持现有「完成本次练习」，不为本功能改成「开始练习」

详情页不新增「再从图片改步骤」入口。

---

## 7. 错误处理

| 情况 | 行为 |
|---|---|
| 未配置 Key / Base URL / Model | 不发请求；toast「先去设置里填写 AI 接口」 |
| 没选到图 | toast「请选择图片」 |
| 超过 3 张（防御） | toast「一次最多 3 张图片」 |
| 网络失败 / 超时 | toast「网络异常，请重试」 |
| HTTP 401/403 | toast「API Key 无效或无权限」 |
| JSON 无法解析 / 空内容 | toast「模型返回格式不对，可换模型或重试」 |
| 其它 HTTP / 未知 | toast「生成失败，请稍后重试」 |
| 部分字段非法 | 不整单失败：规范化后仍创建 |
| 生成中再点来源 | 忽略 |
| 生成中关闭 | 取消请求，回到来源选择 |

Settings AI 区须注明：图片将发送到你配置的接口地址，费用自负。

---

## 8. 测试

P0：

- Unit：`AIPracticeDraft` 规范化（分类回落、分钟夹紧、步骤过滤、和弦/时长编码进字符串）。
- Unit：`VisionPracticeClient` + mock `URLProtocol`（成功 JSON / 坏 JSON / 401 / response_format 重试）。
- Unit：`PracticeStore.createFromAIDraft` 的 steps 不是默认「新步骤」；subtitle 含 `AI`。
- Unit：`ImageStepGenerator` 空图 / 超量 / 未配置 / JPEG 压缩。

可选：

- UI 冒烟：推荐 Sheet 可见「拍摄/照片」（不测真网络、不测相机）。

---

## 9. 非目标

- 流式输出、预览编辑向导
- 本地 OCR 再文本 LLM
- 图片随任务落库 / 同步
- 自有后端代理、账号体系
- Apple on-device Intelligence
- 练习详情页二次「从图片改步骤」
- 为对本功能把详情主按钮改成「开始练习」（属详情整体改版）
- 改 SwiftData Schema 以存和弦数组或每步时长

---

## 10. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 兼容端点行为不一致 | 暴露 Model；JSON mode 失败降级；解析容错 |
| 密钥泄露 | 仅 Keychain；不打日志；不进 git |
| Token / 费用 | 拍照 1 张 / 相册 ≤3 + 压缩；Settings 提示费用自负 |
| 模型胡编步骤 | 详情可编辑；文案不承诺专业课表 |
| 生成中进度像「真识别」 | 规格写明展示用；关闭可取消 |

---

## 11. 实现落点

已有（2026-08-12）：`AIPracticeDraft`、`LLMCredentialsStore`、`VisionPracticeClient`、`ImageStepGenerator`、`createFromAIDraft`、Settings AI 区。

本次 UI 对齐需改：

- `foxgita/Features/Practice/RecommendSheet.swift` — 名称栏芯片；去掉独立生成按钮
- 新建 `PhotoPracticeSheet`（或同等命名）— 来源 + 生成中
- `foxgita/Features/Practice/PracticeDetailView.swift` — `AI ·` 摘要卡
- `AIPracticeDraft` / `createFromAIDraft` — 可选 `chords` / `stepMinutes` 编码
- `foxgita/Localizable.xcstrings`
- 测试：normalize 编码、入口冒烟改为「拍摄/照片」

---

## 12. 方案备选摘要

视觉 API 路径仍为 **A（采纳）**。B OCR、C 预览向导仍不采纳。

本次 UI 实现选 **来源 Sheet 叠在推荐 Sheet 上**，生成中为同一 Sheet 两态。不采用独立全屏栈，也不用 `confirmationDialog` 代替来源页。

决策对照：`../brainstorm-image-to-steps-approaches.html`
