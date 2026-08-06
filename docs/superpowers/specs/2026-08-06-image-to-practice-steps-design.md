# Design: 图片生成练习任务（推荐 Sheet）

**日期：** 2026-08-06  
**状态：** Draft for implementation planning  
**范围：** P0 — 推荐练习 Sheet 选图 → 兼容视觉 API → 创建任务并打开详情  
**方案：** A — 薄客户端 + OpenAI-compatible 视觉模型

---

## 1. 背景与目标

Gita 练习步骤目前是 `TaskItem.steps: [String]`，在详情页手改。用户希望在**推荐练习 Sheet** 中上传图片，经大模型总结后**直接创建**一条练习任务（含名称、分类、建议时长、步骤），并进入详情继续练。

成功标准：

1. 用户在设置中配置 Base URL / Model / API Key 后，可在推荐 Sheet 用最多 3 张图生成任务。
2. 生成成功后关闭 Sheet，导航到新任务详情；步骤可再编辑。
3. 无后端、无账号；Key 仅存本机；图片不落库。
4. 核心解析与建库逻辑可单测（mock HTTP）。

---

## 2. 产品决策（已确认）

| 项 | 选择 |
|---|---|
| 图片内容 | 通用看图总结（教材/手写/指法图等） |
| 模型托管 | 用户自备 API Key，图片发往用户配置的云端 |
| 入口 | 推荐练习 `RecommendSheet` |
| 生成后 | 直接创建任务并打开详情（无预览确认页） |
| 选图 | 相册多选，最多 **3** 张 |
| API | OpenAI-compatible：Base URL + Model + API Key |
| 生成字段 | `title` + `category` + `targetMin` + `steps` |

---

## 3. 架构

```text
Settings（Base URL / Model / API Key）
        │ Keychain + AppStorage
        ▼
RecommendSheet  ──选≤3图──►  ImageStepGenerator（编排）
                                │ 压缩 JPEG / 组 prompt
                                ▼
                         VisionPracticeClient（HTTP）
                                │ OpenAI-compatible chat/completions
                                ▼
                         AIPracticeDraft（规范化）
                                ▼
                         PracticeStore.createFromAIDraft(...)
                                ▼
                         selection = taskId → dismiss → PracticeDetailView
```

约束：

- **不改 SwiftData Schema**；复用 `TaskItem` / `StepCoding`。
- **图片不落库**：内存压缩后上传，请求结束即丢弃。
- **网络只在 Client**：View 不直接使用 `URLSession`。
- 分层仍遵循 TECHNICAL.md：View → Store / Generator → Client / Repository。

---

## 4. 组件职责

| 单元 | 职责 | 依赖 |
|---|---|---|
| Settings · AI 区 | 编辑 Base URL、Model；写入/清除 API Key；隐私说明 | `LLMCredentialsStore` + `AppStorage` |
| `LLMCredentialsStore` | Keychain 读写 API Key；`isConfigured` | Security |
| `VisionPracticeClient` | 组装 multimodal 请求、超时、解析响应 | URLSession |
| `ImageStepGenerator` | 压缩图片 → 调 Client → 得到 Draft | Client + credentials |
| `AIPracticeDraft` | 值类型：`title`, `category`, `targetMin`, `steps` | — |
| `PracticeStore.createFromAIDraft` | 夹紧校验后写入 `TaskItem`（含完整 steps） | Repository |
| `RecommendSheet` | 「从图片生成」入口、`PhotosPicker`(max 3)、loading/错误 | Generator + Store |

配置存储：

- `AppStorage`：`gita.llm.baseURL`、`gita.llm.model`
- Keychain：API Key（服务名与 bundle 对齐，如 `com.haizei.foxgita.llm`）
- `isConfigured`：三者皆非空

---

## 5. 数据契约

### 5.1 模型输出 JSON

```json
{
  "title": "F 和弦转换",
  "category": "chord",
  "targetMin": 10,
  "steps": ["慢速按弦", "四拍切换", "跟节拍连贯"]
}
```

规范化规则：

- `category`：必须是 `PracticeCategory.rawValue`（`left|right|both|chord|scale|rhythm|song`）；非法则回落为 Sheet 当前选中分类。
- `targetMin`：夹紧到 `1...60`；缺失则默认 `10`。
- `steps`：去空白；至少 1 条；最多 12 条；全空则 `["新步骤"]`。
- `title`：trim 后为空则「未命名练习」。
- `subtitle`：由 Store 生成为「AI · {minutes} 分钟」或同类本地化文案（实现时与现有「自定义 ·」风格对齐）。

### 5.2 HTTP

- Base URL 约定：用户填写 **API 根**（例如 `https://api.openai.com/v1`）。客户端去掉尾部 `/` 后请求 `POST {base}/chat/completions`。若粘贴值已以 `/chat/completions` 结尾，则原样作为完整 URL，不再追加。
- Body：`model` + `messages`（system + user multimodal：文本指令 + 最多 3 张 `image_url` data-URL base64）。
- 要求模型 **只返回 JSON**。请求先带 `response_format: { "type": "json_object" }`；若响应表明端点不支持该字段（4xx 且 body 提及 format / unknown），则去掉该字段重试 **一次**。

### 5.3 图片处理

- 来源：`PhotosPicker`，`maxSelectionCount = 3`。
- 最长边缩至约 1280px，JPEG quality ≈ 0.7，再 base64。
- 不写入 Documents / SwiftData。

---

## 6. UI 流程

1. 推荐 Sheet 「创建自己的练习」卡片附近增加 **「从图片生成练习」**。
2. 未配置 LLM：点击 → toast「先去设置里填写 AI 接口」（可提供跳转设置的次要按钮；P0 至少 toast）。
3. 已配置：打开选图 → 用户确认选择 → Sheet 显示「正在读图生成练习…」，`isGenerating` 锁防重复提交。
4. 成功：`selection = taskId` + `dismiss()`；`PracticeView` 现有 `pendingTaskId` + `onDismiss` 推入详情。
5. 失败：toast 错误；保留已选图；不关闭 Sheet。

详情页无需为本功能新增入口（非目标）。

---

## 7. 错误处理

| 情况 | 行为 |
|---|---|
| 未配置 Key / Base URL / Model | 不发请求；中文 toast 引导设置 |
| 未选图 | 生成按钮禁用 |
| 网络失败 / 超时 | toast「网络异常，请重试」 |
| HTTP 401/403 | toast「API Key 无效或无权限」 |
| HTTP 其他 / 空响应 | toast「生成失败，请稍后重试」 |
| JSON 无法解析 | toast「模型返回格式不对，可换模型或重试」 |
| 部分字段非法 | 不整单失败：规范化后仍创建 |
| 生成中再点 | 忽略（`isGenerating`） |

Settings AI 区须注明：图片将发送到你配置的接口地址。

---

## 8. 测试

P0：

- Unit：`AIPracticeDraft` / 规范化（category 回落、分钟夹紧、steps 过滤）。
- Unit：`VisionPracticeClient` + mock `URLProtocol`（成功 JSON / 坏 JSON / 401）。
- Unit：`PracticeStore.createFromAIDraft` 持久化的 steps 不是默认「新步骤」。

可选：

- UI 冒烟：RecommendSheet 可见「从图片生成」入口（不测真网络）。

---

## 9. 非目标

- 流式输出、预览编辑向导（方案 C）
- 本地 OCR 再文本 LLM（方案 B）
- 图片随任务落库 / 同步
- 自有后端代理、账号体系
- Apple on-device Intelligence
- 练习详情页二次「从图片改步骤」入口

---

## 10. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 兼容端点行为不一致 | 配置项暴露 Model；JSON mode 失败降级；解析容错 |
| 密钥泄露 | 仅 Keychain；不打日志打印 Key；不进 git |
| Token / 费用 | 最多 3 张 + 压缩；Settings 提示费用自负 |
| 模型胡编步骤 | 详情可编辑；文案不承诺「专业课表」 |

---

## 11. 实现落点（预期文件）

- `foxgita/Services/LLMCredentialsStore.swift`（新）
- `foxgita/Services/VisionPracticeClient.swift`（新）
- `foxgita/Services/ImageStepGenerator.swift`（新）
- `foxgita/Services/AIPracticeDraft.swift`（新：Draft + `normalize` 纯函数）
- `foxgita/Services/PracticeStore.swift`（扩展）
- `foxgita/Features/Practice/RecommendSheet.swift`（扩展）
- `foxgita/Features/Settings/SettingsView.swift`（扩展）
- `foxgita/Localizable.xcstrings`（文案）
- `foxgitaTests/...`（规范化 + Client + Store）
- Info.plist / 工程：相册权限文案（若尚未具备 `NSPhotoLibraryUsageDescription`）

---

## 12. 方案备选摘要

- **A（采纳）**：视觉模型直出 JSON。
- **B**：OCR → 文本 LLM — 谱/指法弱，链路长。
- **C**：多页向导 — 与「直接创建」冲突，P0 过重。

决策对照页：`docs/superpowers/brainstorm-image-to-steps-approaches.html`
