# Design: 下次练习安排

> 上游：[`Gita-本地记忆知识库与AI-Skills-PRD.md`](../../../../../design-boards/产品PRD/AI能力/Gita-本地记忆知识库与AI-Skills-PRD.md) P1-1 `practice.next_session`；[`Gita-本地记忆知识库与AI-Skills-路线规划.md`](../../../../../design-boards/产品PRD/AI能力/Gita-本地记忆知识库与AI-Skills-路线规划.md) Later L1；[`Gita-本地记忆与AI-Skills-用户体验及现状分析.md`](../../../../../design-boards/产品PRD/AI能力/Gita-本地记忆与AI-Skills-用户体验及现状分析.md) §3.3。  
> 本文为 **Spec 6** 工程设计。Spec 1–5 已落地。原计划中的「三次 Session 升级 / 确认 UI」延后，不占用本编号。

**日期：** 2026-08-22  
**状态：** Approved — awaiting implementation plan  
**方案：** 方案 1 — 独立 Skill `practice.next_session` + `NextSessionSheet` 三态；复用 `AIPracticeDraft` / `createFromAIDraft`；时长当场选择并确定性回填偏好。  
**成功标准：** 配好模型后，从推荐 Sheet「安排今日」能走完选时长 → 生成 → 预览 → 确认，得到一条总时长不超过确认时分钟数的今日 `custom-*` 任务并打开详情。有可用记忆时预览出现本地「已结合…」句；无记忆或已关闭时仍能生成并标明通用建议。确认前首页不出现新任务。图片转练习、复盘、诊断行为不变。

---

## 1. 背景与目标

Spec 5 已把复盘/诊断的 `focus` 写成低置信度 `ability.current_focus`。自定义任务标题会回填成 goal。三个现有 Skill 能读记忆，但用户打开 App 后仍要自己决定今天练什么。

本轮补上记忆到今日清单的第一条可执行闭环：

1. 推荐 Sheet 增加「安排今日」。
2. 用户先选时长，再生成一条多步练习草稿。
3. 预览可改，确认后才 `createFromAIDraft`。

不做：三次证据升级、候选确认、复盘页「下次继续练」、首页记忆卡、周总结、调用日志、Schema V8、改三个旧 Skill 的冻结 Prompt。

---

## 2. 产品与工程决策

| 项 | 选择 |
|---|---|
| Skill | 新 `practice.next_session` `1.0.0`。读 `goal` / `preference` / `ability`。写入 `.deny` |
| 入口 | 「创建自己的练习」卡内，`拍摄/照片` 旁芯片「安排今日」。缺凭据时同样 toast，不打开 Sheet |
| Sheet | `NextSessionSheet` 三态：选时长 → 生成中 → 预览。叠在推荐 Sheet 上 |
| 时长 | 快捷 15 / 20 / 30，另有 5–60、步进 5 的调节。默认见 §4 |
| 时长记忆 | 点生成且 `consent == enabled` 时，确定性写入 `practice.available_minutes`。用户当场选择，tombstone 可复活 |
| 输出 | 一条今日 `TaskItem`，步骤在 `steps`。确认后走现有 `createFromAIDraft`（`custom-*` + Spec 4 标题回填） |
| 预览 | 可改标题、总时长、步骤。分类沿用草稿，本轮不提供分类编辑 |
| 预览引用 | 本地根据当前 Profile 已注入范围内的记忆写一句，不采用模型自报 |
| 授权 | 生成前 `MemoryConsentCoordinator.ensureDecided()`。暂不/关闭仍生成，不注入、不写偏好 |
| 当天两次确认 | 两条 `custom-*`。不做幂等 |
| Schema | 不升 V8 |
| 旧 Skill | `plan.from_image` / `review.media` / `diagnose.video` 的 id、版本、Prompt、读写策略不变 |

---

## 3. 架构

```text
RecommendSheet「安排今日」
        ▼
NextSessionSheet
  时长 → ensureDecided
       → DurationPreferenceSync.sync（仅 enabled）
       → NextSessionGenerator
              ▼
         NextSessionClient
           Registry.lookup(practice.next_session)
           LiveMemoryContext.block
           AITransport.complete（无图）
           capRaw + AIPracticeDraft.normalize
        ▼
预览（NextSessionCitation + 可编辑草稿）
        ▼
确认 → PracticeStore.createFromAIDraft
        ▼
关掉两层 Sheet → 练习详情
```

| 层 | 负责 | 不负责 |
|---|---|---|
| `RecommendSheet` | 芯片、凭据检查、传入 `initialMinutes` 与 `fallbackCategory` | 组 Prompt、写记忆 |
| `NextSessionSheet` | 三态 UI、授权门、调 Sync / Generator、预览编辑、确认 | `URLSession`、`insert MemoryItem` |
| `NextSessionGenerator` | Keychain、把时长和分类交给 Client、用户错误文案 | HTTP、Skill 版本、写偏好 |
| `NextSessionClient` | 查 Skill、替换 `{{minutes}}`、无图 `complete`、解析 Raw、时长封顶 | 鉴权头、记忆 CRUD |
| `DurationPreferenceSync` | 同意已开才 `upsertDurationPreference` + `save` | HTTP、建任务 |
| `MemoryRepository` | `upsertDurationPreference` 固定 key 规则 | 判断是否该写 |
| `NextSessionCitation` | 纯函数：从记忆列表生成预览句 | 网络、Store |
| `LiveMemoryContext` | 照旧按 Skill 范围出 `BACKGROUND_MEMORY` | 改 Prompt |
| `PracticeStore` | 确认后 `createFromAIDraft`（签名不变） | 本轮新 API |

约束：

- View 不直接 `URLSession`，不直接 `insert MemoryItem`。
- 生成失败、关闭、划掉预览均不建任务。
- 时长偏好写入失败不阻断生成。
- `VisionPracticeClient` / `AIPracticeDraft.normalize` 的图片路径签名与行为不变。

---

## 4. 时长默认值与偏好

默认分钟，按第一条命中：

1. 当前活跃 Profile `consent == enabled`，且存在活着的 `practice.available_minutes`，`valueJSON` 能解析为 5...60 的整数。
2. 推荐 Sheet 传入的 `initialMinutes`（夹到 5...60）。
3. `20`。

点「生成」且该 Profile `consent == enabled` 时写入一条 preference：

| 字段 | 值 |
|---|---|
| `kind` | `preference` |
| `key` | `practice.available_minutes` |
| `summaryText` | `通常可练 {n} 分钟` |
| `valueJSON` | `"\(n)"`（十进制数字字符串，无空格） |
| `sourceType` | `"user"` |
| `sourceId` | `""` |
| `confidence` | `1` |
| `importance` | `0.8` |
| `expiresAt` | `nil` |
| `profileId` | 当前活跃 Profile id |

`n` 先夹到 5...60。写入时机在授权门通过之后、发起 HTTP 之前，使这次请求的 `BACKGROUND_MEMORY` 能包含刚写下的时长偏好。

设置页：该条出现在偏好分组，可改可删，`sourceLabel` 为「你添加的」。用户改摘要后 key 不变，之后再生成仍更新同一 key（来源已是 `user`）。

---

## 5. MemoryRepository

协议增加：

```swift
func upsertDurationPreference(profileId: String, minutes: Int) throws
```

查找 `(profileId, key == "practice.available_minutes")`，**包含已软删行**。

规则：

1. `profileId` 为空 → `StoreError.invalidInput`。
2. `minutes` 先夹到 5...60，不因越界抛错。
3. 已有 tombstone → 清 `deletedAt`，按 §4 覆盖字段和 `updatedAt`（用户当场再选，允许复活）。
4. 活着的同 key → 更新 `summaryText` / `valueJSON` / `updatedAt`；`kind` 保持 `preference`；`sourceType` 写成 `"user"`；`confidence` / `importance` 写回 `1` / `0.8`。
5. 没有行 → `insert`（字段见 §4）。
6. **不**在方法内 `save()`。

`upsertUser` / `upsertTaskGoal` / `upsertAICandidate` / `fetch` 不变。`clearAll` 仍软删全部，再次生成且 enabled 时本方法按第 3 条复活。

---

## 6. DurationPreferenceSync

```swift
@MainActor
final class DurationPreferenceSync {
    private(set) var lastError: StoreError?
    func sync(profileId: String, minutes: Int)
}
```

- 方法不抛。入口把 `lastError = nil`。失败 `lastError = StoreError.from(error)`。
- `profileId` 空 → return。
- 对应 Profile `consent != .enabled` → return。
- 否则 `upsertDurationPreference` + `repository.save()`。
- 按传入的 `profileId` 读同意，不用「当前活跃」去写别人的行。

`foxgitaApp` 用与 `TaskMemorySync` 相同的 `memoryRepo` + `mainContext` 构造。用 `EnvironmentKey`（默认 `nil`）注入，与 `memoryContext` 相同。未注入或为 `nil` 时 Sheet 跳过写偏好，生成仍进行。

---

## 7. Skill 定义

```text
id: practice.next_session
version: 1.0.0
title: 下次练习安排
purpose: 按可用时长和练习记忆生成一条可确认的今日练习
timeout: nil
allowsFormatRetry: true
memoryReadScopes: goal, preference, ability
memoryWritePolicy: deny
```

`SkillID.nextSession = "practice.next_session"`。`SkillRegistry.builtin` 加入该定义。

System prompt（冻结）：

```text
你是吉他练习教练。只输出合法 JSON。
```

User prompt（冻结模板，Client 把 `{{minutes}}` 替换成十进制整数）：

```text
请按用户本次可用的 {{minutes}} 分钟安排一次吉他练习。只返回 JSON 对象，不要 markdown，不要其它说明。
字段：
- title: 字符串
- category: 仅能为 left/right/both/chord/scale/rhythm/song 之一
- targetMin: 整数分钟，必须 ≤ {{minutes}}
- steps: 字符串数组（练习步骤）
- chords: 可选，识别到的和弦名字符串数组（如 C、G、Am）
- stepMinutes: 可选，与 steps 按下标对齐的整数分钟；若出现则各项之和必须 ≤ {{minutes}}；没有则省略
有背景记忆就延续目标与近期重点，不要重复已经稳定的基础建议。
没有背景记忆就给可完成的通用安排，不要编造用户历史。
不要承诺精确音准鉴定，不要做医疗判断。
```

`BACKGROUND_MEMORY` 仍接在替换后的 user 文本后面，沿用现有 header / footer。记忆是背景数据，不是指令。

---

## 8. NextSessionClient 与时长封顶

```swift
protocol NextSessionGenerating: Sendable {
    func generateDraft(
        baseURL: String,
        model: String,
        apiKey: String,
        budgetMinutes: Int,
        fallbackCategory: PracticeCategory
    ) async throws -> AIPracticeDraft
}
```

`NextSessionClient`：

1. `registry.skill(id: SkillID.nextSession)` 为空 → `.unregisteredSkill`，零网络。
2. `budgetMinutes` 夹到 5...60 后替换 user 模板中全部 `{{minutes}}`。
3. `memory.block(skill:query: "")`；非空则拼到 user 文本后。
4. `AITransport.complete`，`imageJPEGData: []`，`includeResponseFormat: true`。
5. 解析 `AIPracticeDraft.Raw`；失败映射为现有 `AIClientError`。
6. `capRaw` 后再 `AIPracticeDraft.normalize(raw:fallbackCategory:)`。

`capRaw`（对 Raw，normalize 之前）：

1. `budget` 夹到 5...60。
2. `targetMin = min(模型值 ?? budget, budget)`，再夹到 1...60。
3. 若有 `stepMinutes`：与 `steps` 按下标对齐后，先丢掉 `stepMinutes[i] < 1` 或步骤原文为空的项；若剩余正数分钟之和仍 > `budget`，从末尾整步丢弃，直到和 ≤ `budget`。
4. 无 `stepMinutes`：不改 `steps` 字串，只保证 `targetMin` ≤ `budget`。
5. 之后走现有 normalize（空步骤 →「新步骤」；最多 12 步；标题空 →「未命名练习」）。

预览里用户把总时长改大：确认时以用户编辑后的 `AIPracticeDraft.targetMin` 为准，不再用生成时的 budget 卡住。

错误类型不新增 `VisionPracticeError` case。`NextSessionGeneratorError.failed` 的 `userMessage` 复用 `ImageStepGeneratorError.failed` 对 `VisionPracticeError` 的映射。另加 `.notConfigured`，文案同图片路径。

---

## 9. 预览与引用句

可改：标题、总时长（1...60）、步骤列表（增删改一行，最多 12 条，确认时空列表写成「新步骤」）。

引用句由纯函数 `NextSessionCitation.line(items:selectedMinutes:)` 生成。`items` 来自 `MemoryStore.reload()` 之后、当前 Skill 可读范围内的活着记忆（goal / preference / ability）。按第一条命中：

1. 存在 `key == ability.current_focus` →「已结合你的近期重点：{summaryText}」
2. 否则存在 `kind == goal`（取 `items` 中第一条 goal，即 Store/fetch 已排好的顺序）→「已结合你的目标：{summaryText}」
3. 否则存在 `key == practice.available_minutes` →「已按你的 {selectedMinutes} 分钟安排」
4. 否则 →「通用建议，还没有可参考的练习记忆」

`consent != enabled` 或 `items` 为空时直接第 4 句。摘要在句中按 Swift `Character` 截到 40，超出加「…」。

按钮：

- 「加入今日练习」：用当前预览草稿调 `createFromAIDraft`。成功则 `selection = taskId`，关闭两层 Sheet。失败留在预览并 toast。
- 「重新生成」：以预览里的总时长为新 budget，回到生成中；不建任务。
- 「关闭」或划掉：丢草稿，不建任务。生成中点关闭：取消 Task，回到时长页。

生成中 UI 可复用拍照生成的进度节奏，文案改为「正在安排今日练习」；底部不写「完成后将自动进入生成的练习页」。

---

## 10. 接线

| 调用点 | 行为 |
|---|---|
| 芯片 | 凭据齐全 → `showNextSessionSheet = true`；否则现有缺项 toast |
| `NextSessionSheet` 点生成 | `ensureDecided()` → 通过后 `DurationPreferenceSync.sync` → `MemoryStore.reload()` → Generator |
| 划掉授权 | 与拍照相同：`chooseDisabled()`，然后仍可生成（无记忆） |
| `createFromAIDraft` | 不改。成功后既有 `TaskMemorySync` 回填标题 goal |
| `markReviews*` / 图片生成 | 不调用本 Skill |

`NextSessionSheet` 初始化：

```swift
NextSessionSheet(
    initialMinutes: duration,
    fallbackCategory: category,
    baseURL: llmBaseURL,
    model: llmModel,
    selection: $selection,
    onFinished: { showNextSessionSheet = false; dismiss() }
)
```

---

## 11. 错误与降级

| 情况 | 行为 |
|---|---|
| 缺 Base URL / Model / Key | 芯片不打开 Sheet，toast 与拍照相同 |
| 同意未决 | 先弹现有说明；选完继续这次生成 |
| 暂不 / 已关闭 | 照常生成；请求无 `BACKGROUND_MEMORY`；不写时长偏好；预览第 4 句 |
| 记忆为空或读取失败 | 生成继续，注入 `""`，预览第 4 句 |
| 超时 / 网络 / 401 / JSON 不合法 | 回到时长页，toast 复用图片路径对应文案 |
| 未注册 Skill | 零网络，toast「生成失败，请稍后重试」 |
| 时长偏好写入失败 | 生成继续；`lastError` 可 toast，不丢这次生成 |
| `createFromAIDraft` 失败 | 留在预览，toast，首页无新任务 |
| 生成中关闭 | 取消 Task，回时长页，不建任务 |
| 无网络看记忆 | 设置页 CRUD 仍可用；本 Skill 注入失败并降级 |
| 双 Profile | Sync / fetch / 建任务都带明确 `profileId`；芯片路径用当前活跃 Profile |

---

## 12. 测试

真行为，内存 SwiftData。不强制新 UITest。xcodebuild 目的地 iPhone 17。

| 用例 | 断言 |
|---|---|
| Registry | `nextSession` 存在，`1.0.0`，读 `[.goal, .preference, .ability]`，`.deny`；user 模板含 `{{minutes}}`；三个旧 Skill 版本 / Prompt / 策略快照不变 |
| `capRaw` | `targetMin` 与 `stepMinutes` 之和被压到 budget；超预算从末尾丢步；无 `stepMinutes` 只压 `targetMin` |
| Client 空记忆 | user 无 `BACKGROUND_MEMORY`，`{{minutes}}` 已替换，请求仍发出 |
| Client 有记忆 | user 含包装块；system 不含记忆正文 |
| Client 未注册 | 零网络 |
| Duration upsert | 写入 key / 文案 / `valueJSON`；更新活着的行；tombstone 复活；空 `profileId` 抛 `invalidInput`；60 以外夹紧 |
| Duration 关着 | `consent != enabled` 时 Sync 不写 |
| 隔离 | A 的偏好不进 B 的 fetch |
| Citation | focus > goal > 时长偏好 > 通用句；关闭或空列表为通用句 |
| 未确认 | 只持有草稿，Store 无新 `custom-*` |
| 确认 | `createFromAIDraft` 后有一条今日任务，`targetMin` 等于确认时的分钟；标题 goal 回填仍发生（已有 Spec 4 测试保持绿） |
| 图片路径 | `VisionPracticeClient` / `plan.from_image` 测试保持绿 |

本轮末尾更新 `docs/TECHNICAL.md`：第 4 个 Skill、时长偏好 key、入口。

---

## 13. 文件地图

| 路径 | 动作 |
|---|---|
| `foxgita/Services/SkillDefinition.swift` | `SkillID.nextSession` + 定义 |
| `foxgita/Services/SkillRegistry.swift` | builtin 加入 |
| `foxgita/Services/NextSessionClient.swift` | 新建 |
| `foxgita/Services/NextSessionGenerator.swift` | 新建 |
| `foxgita/Services/NextSessionCitation.swift` | 新建纯函数 |
| `foxgita/Services/DurationPreferenceSync.swift` | 新建 |
| `foxgita/Services/MemoryRepository.swift` | `upsertDurationPreference` |
| `foxgita/Features/Practice/NextSessionSheet.swift` | 新建三态 |
| `foxgita/Features/Practice/RecommendSheet.swift` | 芯片 + 叠 Sheet |
| `foxgita/foxgitaApp.swift` | 构造并注入 `DurationPreferenceSync` |
| `foxgitaTests/SkillRegistryTests.swift` | 第 4 条；旧快照不动 |
| `foxgitaTests/NextSessionClientTests.swift` | 新建 |
| `foxgitaTests/NextSessionCitationTests.swift` | 新建 |
| `foxgitaTests/DurationPreferenceSyncTests.swift` | 新建 |
| `foxgitaTests/MemoryRepositoryTests.swift` | upsert / 复活 / 夹紧 / 隔离 |
| `docs/TECHNICAL.md` | 本轮末尾 |

新 Swift 文件由 `PBXFileSystemSynchronizedRootGroup` 收录，不改 `project.pbxproj`。

---

## 14. 明确不做

- 三次独立 Session 才升级置信度；候选确认 / 拒绝。
- 复盘/诊断结果页「下次继续练这个」。
- 首页「Gita 记得我」卡片。
- `practice.weekly_summary`、调用日志、结果页记忆引用（其它 Skill）。
- Schema V8；给 `TaskItem` 加草稿态。
- 改 `VisionPracticeClient` 或三个冻结 Prompt。
- 预览里改分类。
- 当天二次确认合并为同一条任务。
- 把 `targetMin` 以外的任务字段写成记忆。

---

## 15. 实施顺序（供计划拆任务）

1. `upsertDurationPreference` + Sync + 测试。
2. Skill 定义 + Registry 快照；`capRaw` + Client + 测试。
3. Citation 纯函数 + Generator。
4. `NextSessionSheet` + `RecommendSheet` 芯片；App 注入 Sync。
5. 确认接线回归；`TECHNICAL.md`。
