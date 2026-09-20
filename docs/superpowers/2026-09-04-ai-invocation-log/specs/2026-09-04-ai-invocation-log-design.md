# Design: AI 调用与结果日志（P0 切片 A+B）

> 上游：[Gita-AI能力现状与下一阶段方向](../../../../../1-产品&设计/1-产品理念/Gita-AI能力现状与下一阶段方向.md) §5 P0  
> 前置：SkillRegistry、AITransport、本地记忆、下次练习 Skill 已落地  
> 日期：2026-09-04  
> 状态：Approved — implementation plan ready  
> 方案：SwiftData 一张表，调用结束写一行，草稿结果与完成事后回填；设置里一页只读调试列表  
> 实现仓库：`foxgita/`（当前 Schema 已是 V12）

**成功标准：** 四个 Skill 每次尝试都落一行元数据；下次练习与图片转练习能区分接受 / 编辑 / 重生成 / 放弃；对应练习项首次有效时回写完成；设置页能按时间倒序看到最近记录；序列化结果中不出现 API Key、Base URL、Prompt、模型原文或媒体。

---

## 1. 背景与目标

Gita 已能调用四个 Skill，但无法回答：结构化输出是否稳定、用户有没有接受建议、接受后有没有真正练完。现有 `RecordAnalytics` 只在进程内打点，不落盘，也不能服务 AI 评测。

本轮只做本地可观测性：调用日志 + 用户结果 + 调试列表。不证明「练得更好」，只让后面的评测集和 P1 闭环有数可对。

### 做

- Schema **V13** 新增 `AIInvocationLog`（V12 已被项目字段占用）。
- 四个 Client / Generator 在每次尝试结束时写一行。
- 下次练习、图片转练习回写草稿结果；有效练习回写完成。
- 设置 →「AI 调用记录」只读列表。
- 每档案最多保留 200 条。

### 不做

- 评测集（每 Skill 20–30 案）。
- 模型兼容矩阵与 ≥97% 达标工程。
- 导出 JSON、删除、云同步。
- 开放聊天、周总结、向量检索。
- 复盘 / 诊断的草稿接受 UI。
- 改 `project.pbxproj`（新 Swift 文件由 synchronized group 接入）。

---

## 2. 产品与工程决策

| 项 | 选择 |
|---|---|
| 存储 | SwiftData 一张表，结果字段后补，不建事件表 |
| Schema | V12 → V13 lightweight |
| 隔离 | 每行带 `profileId`；保留策略按档案 200 条 |
| 相关 id | 调用方生成 `invocationId` 传入 Client；接受后写 `taskId` = `PracticeItem.id` |
| 隐私 | 不写 API Key、Base URL、Prompt、完整响应、图片 / 音频 / 视频 |
| 失败隔离 | 写日志抛错只吞掉，不改变用户可见的生成 / 保存结果 |
| UI | 设置里调试列表；记忆总开关不影响日志 |
| 完成定义 | 对应 `PracticeItem` 首次对 `PracticeItemRules.isEffective` 为真 |

---

## 3. 架构

```text
Sheet / ReviewJobRunner
  生成 invocationId
        ▼
Generator（凭据检查）
  未配置 → 写 failure / notConfigured
        ▼
Client
  1. Registry.lookup
  2. memory.snapshot → block + 实际注入的 Memory ID
  3. AITransport.complete → content + formatRetryUsed
  4. 解析 Draft
  5. 无论成败写一行 AIInvocationLog
        ▼
下次练习 / 图片 Sheet
  接受 / 编辑 / 重生成 / 放弃 → 回写 draftOutcome、taskId
        ▼
PracticeStore.savePracticeItem / attachRecording
  练习项首次有效 → 按 taskId 写 completedAt
        ▼
Settings → AIInvocationLogView
  读最近 200 条，不展示 Prompt
```

| 层 | 负责 | 不负责 |
|---|---|---|
| `GitaSchemaV13.AIInvocationLog` | 字段与默认值 | 业务判定 |
| `AIInvocationStore` | 写入、回填、按档案修剪、最近列表 | 发网络、改练习数据 |
| `AITransport` | 多返回是否降级重试 | 写日志、知道 Skill |
| `MemoryContextProviding` | snapshot 返回文案块 + 实际用过的 ID | 写日志 |
| 四个 Client | 调用结束写一行 | 判断用户是否接受 |
| Generator | `notConfigured` 也写一行 | 改 Draft 字段 |
| Sheet / Runner | 生成 `invocationId`，回写草稿结果 | 直接 fetch SwiftData 模型细节 |
| `PracticeStore` | 首次有效时标完成 | 改 draftOutcome |
| `AIInvocationLogView` | 只读展示 | 删除、导出、看 Prompt |

约束：

- View 不直接 `URLSession`，也不拼 Prompt。
- `AITransport` 不写 SwiftData。
- 同一 `invocationId` 只插入一次；之后只更新结果字段。

---

## 4. 数据模型

`GitaSchemaV13` 在 V12 模型列表上增加 `AIInvocationLog`。V12 的 Task / Session / Recording / Profile / Memory / PracticeItem / Project 字段逐字保留，只做 lightweight 升级。

```text
AIInvocationLog
├── id                String     // 调用方传入的 invocationId
├── profileId         String
├── skillId           String     // 如 practice.next_session
├── skillVersion      String
├── model             String     // 模型名，不是 Key
├── startedAt         Date
├── durationMs        Int
├── statusRaw         String     // success | failure
├── errorTypeRaw      String     // 失败才有，成功为空
├── memoryIdsRaw      String     // 逗号分隔的 MemoryItem.id，无则空
├── formatRetryUsed   Bool
├── draftOutcomeRaw   String     // 空 | accepted | edited | regenerated | abandoned
├── taskId            String     // 接受后写入 PracticeItem.id.uuidString
├── completedAt       Date?
├── createdAt         Date
└── updatedAt         Date
```

`typealias AIInvocationLog = GitaSchemaV13.AIInvocationLog`。

### 4.1 错误类型

只存稳定短名，不存 HTTP 原文、不存错误对象描述。

| `errorTypeRaw` | 来源 |
|---|---|
| `notConfigured` | Generator：Base URL / 模型 / API Key 未配齐 |
| `invalidURL` | `VisionPracticeError.invalidURL` |
| `unauthorized` | `.unauthorized` |
| `httpStatus` | `.httpStatus`（不写状态码） |
| `emptyContent` | `.emptyContent` |
| `invalidJSON` | `.invalidJSON` |
| `timeout` | `.timeout` |
| `transport` | `.transport` |
| `unregisteredSkill` | `.unregisteredSkill` |
| `cancelled` | `CancellationError` 或 `URLError.cancelled` |

未列出的错误记 `transport`。

### 4.2 隐私

以下字段不得出现在模型属性、日志字符串或调试 UI：

- API Key
- Base URL
- system / user Prompt（含记忆块正文）
- 模型完整响应
- 图片 JPEG、波形、录像帧、本地文件路径

`memoryIdsRaw` 只含 ID。`model` 只含用户在设置里填写的模型名。

单测必须用序列化后的日志行做反例断言：不得包含 `sk-`、`Bearer`、`BACKGROUND_MEMORY`、`data:image`。

---

## 5. 写入时机

### 5.1 调用行

调用方（Sheet 或 `ReviewJobRunner`）在每次尝试前生成 `invocationId`（UUID 字符串）并传入 Generator / Client。下次练习与图片转练习把现有 `generationId` 当作 `invocationId`，不另起一套 id。

Client 在 `generateDraft` 返回或抛错之前写一行。`unregisteredSkill` / `invalidURL` 未发网也要写。`Task.isCancelled` 或 `URLError.cancelled` 记 `failure` + `cancelled`。

`NextSessionGenerator` / `ImageStepGenerator` 以及复盘、诊断的 Generator：在抛 `notConfigured` 时写一行（`skillId` / `skillVersion` 取 Registry 定义，`model` 用用户已填值，空则空字符串）。Client 成功或其它失败时不再由 Generator 重复写。

`durationMs` = 从进入 Client（或 Generator 的 notConfigured 分支）到写行为止。`startedAt` 用进入时刻。

`memoryIdsRaw` 只包含 **实际进入 800 字预算块** 的 Memory ID，不是 fetch 到但被截断丢掉的。授权关闭或空块则空。

`formatRetryUsed == true` 当且仅当 `AITransport` 因 `response_format` 不被支持而重试过一次。

写入用 `AIInvocationStore.record(...)`。同一 `id` 已存在则忽略插入（防双回调），不覆盖已有 `draftOutcome` / `completedAt`。

### 5.2 草稿结果

只适用于下次练习、图片转练习。复盘 / 诊断保持 `draftOutcomeRaw` 为空。

**下次练习**

| 用户动作 | 写入 |
|---|---|
| 点「加入今日练习」，标题 / 分钟 / 步骤与生成稿逐字相同 | `accepted`，`taskId` = 新练习项 id |
| 加入前改过标题、分钟或步骤（去空白后比较；空步骤忽略） | `edited`，`taskId` 同上 |
| 预览页点「重新生成」 | 当前行 `regenerated`；新尝试用新的 `invocationId` |
| 预览页点关闭或下拉关掉 | `abandoned` |
| 生成中点关闭 / 取消 | 该行 `failure` + `cancelled`，`draftOutcome` = `abandoned` |
| 还在选时长、尚未生成 | 不写行 |

重生成后再接受：只改**新行**的 `accepted` / `edited`。旧行保持 `regenerated`。

**图片转练习**

| 用户动作 | 写入 |
|---|---|
| 生成成功并 `PracticeEntryGate.submit` 入库 | `accepted`，`taskId` = 练习项 id |
| 生成中关闭 | `cancelled` + `abandoned` |
| 仍在选图、尚未生成 | 不写行 |
| 生成失败（非取消） | 只有调用行的 `failure`，草稿结果为空 |

入库后在练习详情里改步骤，**不**改写成 `edited`。`edited` 只表示确认草稿当下相对模型输出有改。

授权弹层选「暂不开启」导致不发请求：不写调用行。

### 5.3 完成

`taskId` 存的是 `PracticeItem.id.uuidString`，不是旧 `TaskItem.id`。下次练习与图片入库已经走 `PracticeEntryGate` → `PracticeItem`。

`taskId` 非空且 `completedAt == nil` 时，`savePracticeItem` 或 `attachRecording` 之后该练习项首次对 `PracticeItemRules.isEffective` 为真，则写入 `completedAt = now`。

无效保存（0 秒、无笔记、无媒体）不写完成。软删练习项不清除已有 `completedAt`，也不新标完成。`finishSession`（旧 TaskItem 路径）不回写 AI 日志。

同一练习项只标一次完成。

### 5.4 修剪

每次成功插入后，对同一 `profileId` 按 `startedAt` 降序保留 200 条，其余删除。回填结果不触发修剪。

### 5.5 失败隔离

`AIInvocationStore` 所有公开方法吞掉 SwiftData 错误，不设置 `PracticeStore.lastError`，不弹 Toast。用户生成失败文案仍只来自现有 Generator 错误。

---

## 6. 现有类型的小改动

行为对外保持等价，只多带回传值。

`AITransport.complete` 改为返回：

```text
struct AITransportResult: Equatable, Sendable {
    var content: String
    var formatRetryUsed: Bool
}
```

递归降级那一次把 `formatRetryUsed` 置 `true`。四个 Client 改为读 `.content`。

`MemoryContextProviding` 增加：

```text
struct MemoryPromptSnapshot: Equatable, Sendable {
    var block: String
    var itemIds: [String]
}
```

`block(skill:query:)` 继续返回 `snapshot.block`，现有测试不必全改。`MemoryContextBuilder` 在截断循环里同时收集对应 `item.id`。`EmptyMemoryContext` 返回空块 + 空 ID。

四个 Client 的 `generateDraft` 增加参数 `invocationId: String`。测试夹具传 `UUID().uuidString` 即可。

不改 Skill Prompt、不改 Draft DTO 字段、不改记忆授权语义。

---

## 7. 调试列表

设置页在「AI 记忆」和「关于」之间增加 NavigationLink「AI 调用记录」，副标题「最近的生成与结果」。

页面：

- 导航标题「AI 调用记录」。
- 按 `startedAt` 倒序。
- 每一行：Skill 标题（图片转练习 / 媒体复盘 / 录像分段诊断 / 下次练习安排）、相对时间、`success`/`failure`、`errorType`（失败才显示）、`draftOutcome`（空则显示「仅调用」）、完成与否、耗时、模型名。
- 空态：「还没有 AI 调用记录」。
- 不可点进详情，不展示 Prompt，没有删除 / 清空 / 导出。
- 记忆开关不影响本页数据。

文案用中文，不出现 `SkillRegistry`、`invocationId` 等内部名。

---

## 8. 测试

| 用例 | 断言 |
|---|---|
| V12 → V13 lightweight | 旧 Task / Memory / Project 仍在；`AIInvocationLog` 可插入 |
| 调用成功 | 一行 `success`，`errorType` 空，含 skill / version / model / durationMs |
| 调用失败 | 一行 `failure` + 对应 `errorType`；Client 仍抛原错误 |
| `notConfigured` | Generator 写一行，不发网 |
| `cancelled` | 取消后为 `failure` + `cancelled` + `abandoned`（练习类） |
| 隐私 | 序列化行不含 Key、Prompt、记忆正文、`data:image` |
| 记忆 ID | 只含进入预算块的 ID；未授权为空 |
| `formatRetryUsed` | 降级重试后为 true，一次成功为 false |
| 下次练习四态 | accepted / edited / regenerated / abandoned |
| 图片 | 入库 accepted；生成中关闭 abandoned |
| 复盘 / 诊断 | 有调用行，`draftOutcome` 空 |
| 完成 | 首次有效回写；无效保存不写；第二次保存不改 `completedAt` |
| 修剪 | 第 201 条插入后该档案只剩 200，留下最新的 |
| 写日志失败 | 生成 / 保存练习仍成功 |
| 设置页 | 倒序、失败显示错误名、成功不显示错误、无 Prompt |
| 回归 | 现有 AITransport / Client / Memory / NextSession / 练习入库测试继续绿 |

测试用 in-memory `GitaSchemaV13`。不引入真实网络。

---

## 9. 文件落点（foxgita）

| 文件 | 动作 |
|---|---|
| `Models/SchemaV13.swift` | 新建，V12 模型 + `AIInvocationLog` |
| `Models/Models.swift` | typealias 与 migration 接到 V13 |
| `Services/AIInvocationStore.swift` | 新建 |
| `Services/AITransport.swift` | 返回 `AITransportResult` |
| `Services/MemoryContextBuilder.swift` | snapshot 收集 ID |
| `Services/MemoryContextProviding.swift` | 增加 snapshot |
| 四个 `*Client.swift` | 传入 `invocationId`，结束时 record |
| 对应 Generator | `notConfigured` 时 record |
| `NextSessionSheet.swift` / `PhotoPracticeSheet.swift` | 传入 id，回写结果 |
| `ReviewJobRunner.swift` | 每条录音一个 id |
| `PracticeStore.swift` | 首次有效标完成 |
| `Features/Settings/AIInvocationLogView.swift` | 新建列表 |
| `Features/Settings/SettingsView.swift` | 入口 |
| `foxgitaTests/*` | 上表用例 |

---

## 10. 明确的解释

- 「完成」= 该次 AI 建议对应的练习项留下了有效证据，不是用户看完复盘。
- 图片路径没有预览编辑，所以没有 `edited`。
- 重生成是旧行结果，不是新行的错误。
- 调试列表给开发者看，不面向普通用户讲「Gita 在学习」。
- 本切片结束后，P0 仍缺评测集和模型矩阵，不宣称 P0 全部完成。
