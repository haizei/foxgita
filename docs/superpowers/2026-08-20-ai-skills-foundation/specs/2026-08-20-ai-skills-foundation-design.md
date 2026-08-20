# Design: AI Skills 基础（统一 Client + Skill Registry）

> 上游：[`Gita-本地记忆知识库与AI-Skills-PRD.md`](../../../../../design-boards/产品PRD/AI能力/Gita-本地记忆知识库与AI-Skills-PRD.md) 阶段 A；[`Gita-本地记忆知识库与AI-Skills-路线规划.md`](../../../../../design-boards/产品PRD/AI能力/Gita-本地记忆知识库与AI-Skills-路线规划.md) Now N2–N3。  
> 本文为 **Spec 1** 工程设计。Spec 2（Schema V6 / 只读记忆）与 Spec 3（管理 UI / 受控写入）另开文档。

**日期：** 2026-08-20  
**状态：** Approved — implementation plan ready  
**方案：** 方案 1 — 共享 `AITransport` + 编译期 `SkillRegistry`，三个现有 Client 改为薄适配；Generator / View / 协议签名不变。  
**成功标准：** 三个现有 AI 功能经 Registry 发起调用；Prompt 与输出 DTO 与当前版本等价；未注册 Skill 零网络；通用鉴权 / HTTP / fence / `response_format` 降级不再三处复制。

---

## 1. 背景与目标

Gita 已有三个 OpenAI-compatible 调用：`VisionPracticeClient`（图片转练习）、`MediaReviewClient`（音频/画面复盘）、`VideoDiagnosisClient`（录像分段诊断）。三者各自复制 URL 拼接、Bearer、HTTP 映射、JSON fence 清理和 `response_format` 降级；Prompt 与输出 DTO 不同。PRD 要求先统一 Skills 基础设施，再做本地记忆。

本轮只做统一，不改变用户可见结果（超时映射见 §6 的唯一允许差）。

不做：Schema V6、`LocalProfile`、Memory 运行时、设置页、生产 Prompt 日志、下次练习建议、周总结、开放式聊天。

---

## 2. 产品与工程决策

| 项 | 选择 |
|---|---|
| 范围 | Spec 1：Transport + Registry + 三个 Client 迁移 |
| Prompt | 现有 system / user 文案原样冻结进 `SkillDefinition` |
| 调用面 | 保留三个 Generator 与 `VisionGenerating` / `MediaReviewing` / `VideoDiagnosing` |
| Skill 定义 | 纯 Swift 结构体，编译期注册；输出继续用现有 Draft DTO |
| 记忆权限 | 定义里带 `memoryReadScopes` / `memoryWritePolicy`；三个 Skill 均为空范围 + `.deny`；本轮零 Memory 调用 |
| 错误类型 | 保留 `VisionPracticeError`；`typealias AIClientError = VisionPracticeError` |
| 生产日志 | 不写 Prompt / Key / 媒体 / 完整响应。请求快照只存在单测里 |
| 超时 | 三个 Skill 统一把 `URLError.timedOut` 映射为 `.timeout`（本轮唯一允许的行为差） |

---

## 3. 架构

```text
PhotoPracticeSheet / ReviewJobRunner
        ▼
ImageStepGenerator / MediaReviewGenerator / VideoDiagnosisGenerator
  （凭据、JPEG 准备、本次任务 contextText — 不改对外 API）
        ▼
VisionGenerating / MediaReviewing / VideoDiagnosing
        ▼
三个 *Client（薄适配：查 Skill、选定冻结文案 + 本次输入、解析本 Skill 的 DTO）
        ▼
SkillRegistry.lookup(id)  →  AITransport.complete
        ▼
OpenAI-compatible POST /chat/completions
```

| 层 | 负责 | 不负责 |
|---|---|---|
| Generator | Keychain、图片/抽帧、本次任务文案、用户错误文案 | HTTP、Prompt 模板、Skill 版本 |
| Client 适配 | 查自己的 Skill、选定冻结文案与本次 user 文本、空 content 判定、解析现有 DTO | 鉴权头、状态码、`response_format` 降级 |
| `SkillRegistry` | 用 id 取出内置定义；查不到则不发请求 | 网络、记忆读写 |
| `AITransport` | URL、Bearer、超时、HTTP 映射、body 序列化、fence 实现、降级一次 | Prompt 文案选择、业务 DTO |
| `SkillDefinition` | id / version / 冻结 prompt / timeout / 记忆权限（默认拒绝） | 运行时读 Memory |

约束：

- View 不直接 `URLSession`。
- 本轮不存在 `MemoryContextBuilder`；Client 在查到 Skill 后不得调用任何 Memory API。
- 不引入通用 `AISkillEngine.run` 输入模型。
- 不把 Prompt 抽到 Bundle 文件。

---

## 4. 组件与文件

保持 `foxgita/foxgita/Services/` 扁平。新文件加入 foxgita target（及对应测试 target）。

### 4.1 新增

#### `SkillDefinition.swift`

```text
enum SkillID {
  static let planFromImage = "practice.plan.from_image"
  static let reviewMedia   = "practice.review.media"
  static let diagnoseVideo = "practice.diagnose.video"
}

enum MemoryScope: String, Equatable, Sendable {
  case fact, goal, preference, ability, summary
}

enum MemoryWritePolicy: Equatable, Sendable {
  case deny
  case candidates   // Spec 1 三个 Skill 均不使用；Spec 2 改取值时用
}

struct SkillDefinition: Equatable, Sendable {
  var id: String
  var version: String
  var title: String
  var purpose: String
  var systemPrompt: String
  var userPrompt: String?          // 仅图片转练习非 nil
  var timeout: TimeInterval?       // nil = 不改 URLRequest.timeoutInterval
  var allowsFormatRetry: Bool
  var memoryReadScopes: [MemoryScope]
  var memoryWritePolicy: MemoryWritePolicy
}
```

本轮三个定义的 `version` 均为 `"1.0.0"`（含义：从现网行为冻结，不是产品发布号）。

| id | userPrompt | timeout | memoryReadScopes | memoryWritePolicy |
|---|---|---|---|---|
| `practice.plan.from_image` | 附录 A | `nil` | `[]` | `.deny` |
| `practice.review.media` | `nil` | `nil` | `[]` | `.deny` |
| `practice.diagnose.video` | `nil` | `180` | `[]` | `.deny` |

`allowsFormatRetry` 三个均为 `true`。冻结文案见附录 A，必须与当前 Client 字符串逐字相同。

输出校验不另做泛型 Validator：继续走各 Client 的 `parseDraft` + `*Draft.normalize`。

#### `SkillRegistry.swift`

```text
struct SkillRegistry: Sendable {
  static let builtin: SkillRegistry   // 仅含上述三个定义
  init(skills: [SkillDefinition])     // 测试可注入空表或子集
  func skill(id: String) -> SkillDefinition?
}
```

`builtin` 用 `id` 建字典；重复 id 视为程序员错误，用 `precondition` 拦住（测试只覆盖 builtin 三 id 唯一）。

#### `AITransport.swift`

```text
struct AITransport: Sendable {
  init(session: URLSession = .shared)

  static func completionsURL(from baseURL: String) -> URL?
    // 行为与现 VisionPracticeClient.completionsURL 完全相同

  func complete(
    url: URL,
    apiKey: String,
    model: String,
    systemPrompt: String,
    userText: String,
    imageJPEGData: [Data],
    includeResponseFormat: Bool,
    allowsFormatRetry: Bool,
    timeout: TimeInterval?
  ) async throws -> String
    // 返回 trimmed 的 message.content，**尚未** strip fence
    // HTTP JSON 无法解码为 ChatResponse → .invalidJSON
    // 其它抛出见 §6（不含 DTO 解析）

  static func stripMarkdownFences(_ text: String) -> String
    // 与现 VisionPracticeClient 实现相同；仅此一处
}
```

`complete` 内部：

1. 组 JSON body（§5）。
2. `URLRequest`：POST、`Authorization: Bearer …`、`Content-Type: application/json`；若 `timeout != nil` 则 `timeoutInterval = timeout`。
3. HTTP / 传输映射见 §6。
4. 用现有 `ChatResponse` 形状解码 HTTP body。解码失败 → `.invalidJSON`。
5. 取 `choices[0].message.content`，`trimmingCharacters`；缺省为 `""`。**先返回给 Client 做空判断，再由 Client 调用 `stripMarkdownFences`。** 顺序与现网一致：仅 fence、无正文的 content 不会走 `.emptyContent`，而走后续 DTO `.invalidJSON`。

### 4.2 改动、不改签名

| 文件 | 变化 |
|---|---|
| `VisionPracticeClient` | 增加 `registry: SkillRegistry = .builtin`（默认实参）。内部持有 `AITransport(session:)`。`generateDraft` 查 `SkillID.planFromImage`，把 Skill 文案交给 Transport。`parseDraft` 改为接收 content 字符串（不再解码 ChatResponse）。`completionsURL` 转发 `AITransport.completionsURL` |
| `MediaReviewClient` | 同上，Skill = `reviewMedia`；user 文本仍是入参 `contextText` |
| `VideoDiagnosisClient` | 同上，Skill = `diagnoseVideo`。保留 `static let requestTimeout: TimeInterval = 180`，与 Skill.timeout 同一字面量，现有超时单测继续用该常量 |
| `VisionPracticeError` | 新增 `unregisteredSkill`。文件顶部增加 `typealias AIClientError = VisionPracticeError` |
| `ImageStepGenerator.userMessage` | `unregisteredSkill` 与 `.invalidURL, .httpStatus` 同一文案：「生成失败，请稍后重试」 |

三个 Client 的 `init(session:)` 保持可用：`init(session: URLSession = .shared, registry: SkillRegistry = .builtin)`。现有 `MockURLProtocol` 测试只传 `session:`，不必改构造。

`VideoDiagnosisClient` 现有 `makeSession()`（ephemeral + 180s configuration timeout）保留，默认 `init()` 仍用它。Transport 另把 `URLRequest.timeoutInterval` 设为 Skill.timeout，现有 `generateDiagnosisSetsLongRequestTimeout` 继续有效。

### 4.3 明确不碰

- `ImageStepGenerator` / `MediaReviewGenerator` / `VideoDiagnosisGenerator` 的协议与方法签名（仅 `userMessage` 补一个 switch case）
- `PhotoPracticeSheet`、`foxgitaApp` 里的 Client / Generator 构造
- `LLMCredentialsStore`、Schema V5、Settings、ReviewJobRunner 调度

---

## 5. 数据流

一次成功调用：

```text
Generator
  校验凭据、压 JPEG、拼本次 contextText（复盘/诊断）
        ▼
Client.generate*
  1. guard let skill = registry.skill(id) else { throw .unregisteredSkill }  // 零网络
  2. 不读取、不写入 Memory（本轮无 Memory 类型可调）
  3. guard let url = AITransport.completionsURL(from: baseURL) else { throw .invalidURL }
  4. let userText = skill.userPrompt ?? contextText
  5. rawContent = try await transport.complete(..., systemPrompt: skill.systemPrompt,
       userText: userText, timeout: skill.timeout, allowsFormatRetry: skill.allowsFormatRetry)
  6. rawContent 去空白后为空：图片 → .emptyContent；复盘/诊断 → .invalidJSON
  7. jsonText = AITransport.stripMarkdownFences(rawContent)
  8. decode Raw → *Draft.normalize → 返回 DTO
        ▼
Generator 原样交给 View / ReviewJobRunner
```

组包 JSON（与现网语义一致，`JSONSerialization`）：

```text
{
  "model": "<model>",
  "messages": [
    { "role": "system", "content": "<skill.systemPrompt>" },
    { "role": "user", "content": [
        { "type": "text", "text": "<userText>" },
        { "type": "image_url", "image_url": { "url": "data:image/jpeg;base64,<...>" } },
        ...
    ]}
  ],
  "response_format": { "type": "json_object" }   // 仅 includeResponseFormat == true
}
```

- 图片 Skill 的 `userText` = `skill.userPrompt`（冻结）。
- 复盘 / 诊断的 `userText` = Generator 已有 `contextText`。Transport 不改写。
- 图片按入参数组顺序追加 `image_url`，与现在相同。
- 首次 `includeResponseFormat = true`；降级重试时省略整个 `response_format` 键，不再递归。

失败不落业务结果：不写 Task、不写 `reviewFindingsJSON`、不产生 Memory 候选。

---

## 6. 错误处理

`VisionPracticeError` 增加 `unregisteredSkill` 后完整集合：

| 条件 | case | 用户可见 |
|---|---|---|
| baseURL 无法拼出 completions | `.invalidURL` | 图片：「生成失败，请稍后重试」。复盘/诊断：`ReviewFailureKind.network` |
| Registry 无此 id | `.unregisteredSkill` | 同上。内置三个 Skill 的产品路径不可达 |
| 401 / 403 | `.unauthorized` | 图片：「API Key 无效或无权限」。录像队列：401 停后续（现有 Runner 行为） |
| 其它 HTTP | `.httpStatus` | 生成失败 / `.network` |
| `URLError.timedOut` | `.timeout` | 图片已有超时文案。复盘/诊断走已有 `.timeout` |
| 其它传输失败 | `.transport` | 网络异常 / `.network` |
| 空 content（Transport 已 trim，**尚未** strip fence） | 图片 `.emptyContent`；复盘/诊断 `.invalidJSON` | 「模型返回格式不对…」/ `.parse` |
| fence 后仍非合法 DTO | `.invalidJSON` | 同上 |

Transport 映射 HTTP 与传输；DTO 解析仍在 Client。

降级规则（与现在相同，收口到 Transport）：

- 仅当 `allowsFormatRetry && includeResponseFormat` 且状态码 400…499，且响应 body（小写）含 `response_format` 或 `unknown` 时，去掉 `response_format` 再发一次。
- 第二次仍非 2xx → `.httpStatus`，不第三次尝试。

本轮唯一允许的行为差：图片与媒体复盘遇到 `URLError.timedOut` 时，由 `.transport` 改为 `.timeout`。`ImageStepGenerator` 与 `ReviewJobRunner.failureKind` 已区分 `.timeout`。Prompt、DTO、成功路径不变。

隐私：默认不持久化 API Key、完整 Prompt、图片二进制、完整模型响应。测试快照中的 JPEG 用固定占位（例如 `"<jpeg>"`），不写入真实 base64。

配置错误（缺 Skill、坏 URL）不得崩溃、不得删除用户数据。

---

## 7. 测试

现有 Client / Generator 用例继续绿，构造方式不改：

- 成功解析 DTO
- 401 → `.unauthorized`
- 非法 JSON content → `.invalidJSON`
- `response_format` 降级一次后成功
- 录像 `URLRequest.timeoutInterval == 180`
- 录像 `URLError.timedOut` → `.timeout`
- `VisionPracticeClient.completionsURL` 拼接与完整路径尊重

新增 `foxgitaTests/SkillRegistryTests.swift` 与 `foxgitaTests/AITransportTests.swift`（快照也可写在 Client 测试里，但断言源必须是组出来的 body，而不是复制粘贴三份逻辑）。

| 用例 | 断言 |
|---|---|
| builtin 含三个 id，version `"1.0.0"` | `memoryReadScopes` 空、`memoryWritePolicy == .deny` |
| 未知 id | Client 抛 `.unregisteredSkill`；URLProtocol handler 调用次数 = 0 |
| 请求快照（图片打码） | system / 图片 user 文案与附录 A 逐字相同；首次含 `response_format`；`messages[0].role == system`，`messages[1].role == user` |
| 复盘/诊断快照 | system 为附录 A；user text 为传入的 `contextText`，不是 Skill.userPrompt |
| fence 清理 | content 包在 markdown json 围栏内：空判断通过后 strip，仍能 parse DTO |
| 降级只一次 | 连续两次 400（body 含 `response_format`）后停止；第二次请求不含该键 |
| 超时映射 | 图片 Client 与复盘 Client 遇到 `timedOut` 也是 `.timeout` |
| completionsURL | `AITransport.completionsURL` 与现有拼接用例等价 |

不做：UI 测试、真模型调用、Schema 迁移、跨 Profile、合并三份 `MockURLProtocol`。

---

## 8. 实现顺序

1. `VisionPracticeError.unregisteredSkill` + `AIClientError` 别名；补 `ImageStepGenerator.userMessage`。
2. `SkillDefinition` + 附录 A 冻结字符串 + `SkillRegistry.builtin`。
3. `AITransport`（URL、发送、映射、fence、降级）+ `AITransportTests`。
4. 三个 Client 改为查 Registry + 调 Transport；`completionsURL` 转发。
5. 现有 Client 测试全绿后补 Registry 拒绝用例与请求快照。

Xcode：新 Swift 文件加入 foxgita target，新测试加入 foxgitaTests。

---

## 9. 范围边界

本 Spec 交付后仍不存在：Memory 存储、记忆注入、授权 UI、调用日志落盘、Skill 远程配置、第四个 Skill。

Spec 2 允许且预期的后续动作：把三个 Skill 的 `memoryReadScopes` 改成非空、接 `MemoryContextBuilder`；不改 Transport，不改 Generator 协议。若要改 `memoryWritePolicy`，只改定义上的枚举值，不改 Registry API。

---

## 附录 A — 冻结 Prompt（逐字）

### `practice.plan.from_image`

system:

```
你是吉他练习教练。只输出合法 JSON。
```

userPrompt:

```
请根据图片总结成吉他练习任务。只返回 JSON 对象，不要 markdown，不要其它说明。
字段：
- title: 字符串
- category: 仅能为 left/right/both/chord/scale/rhythm/song 之一
- targetMin: 整数分钟
- steps: 字符串数组（练习步骤）
- chords: 可选，识别到的和弦名字符串数组（如 C、G、Am）
- stepMinutes: 可选，与 steps 按下标对齐的整数分钟；没有则省略
```

### `practice.review.media`

system:

```
你是吉他练习陪伴教练。根据波形图或练习画面帧给出简短复盘。只返回 JSON，不要 markdown。
字段：highlight（亮点）、focus（优先改善）、nextAction（下次练法）。
每段一句话，不要编造时间戳（如 01:18），不要承诺精确音准鉴定。
```

userPrompt: `nil`（使用 Generator `contextText`）。

### `practice.diagnose.video`

system:

```
你是吉他练习诊断教练。根据练习录像关键帧和可选波形，给出可定位的分段诊断。只返回 JSON，不要 markdown。
字段：highlight、focus、nextAction（各一句话），findings（数组，可空）。
每条 finding 字段：startSec、endSec（整数秒，必须落在 0 到视频时长之间）、title、evidence、cause、action。
evidence 写看到或听到的具体现象。证据不足就少写或不写 finding，不要编造时间点，不要承诺精确音准鉴定。最多 5 条。
```

userPrompt: `nil`（使用 Generator `contextText`）。

实现时从本附录拷贝到 `SkillDefinition` 常量，不要从当前 Client 凭记忆重写。迁移完成后删除 Client 内的重复字符串。
