# Design: 确定性 Task 目标回填

> 上游：[`Gita-本地记忆知识库与AI-Skills-PRD.md`](../../../../../design-boards/产品PRD/AI能力/Gita-本地记忆知识库与AI-Skills-PRD.md) P0-5 确定性写入 / §10.1–10.3；[`Gita-本地记忆知识库与AI-Skills-路线规划.md`](../../../../../design-boards/产品PRD/AI能力/Gita-本地记忆知识库与AI-Skills-路线规划.md) Next X3。  
> 本文为 **Spec 4** 工程设计。Spec 1–3 已落地。Spec 5（AI 候选 / X4）另开文档。

**日期：** 2026-08-21  
**状态：** Approved — implemented  
**方案：** 方案 1 — 独立 `TaskMemorySync`；仅 `custom-*` 练习项各一条 goal；用户改摘要或删除优先于任务标题。  
**成功标准：** 记忆开启后，新建或改名自定义任务会在「AI 记忆」出现对应目标，并进入会读 goal 的 Skill 的 `BACKGROUND_MEMORY`；用户改过的摘要不被任务改名盖掉；用户删过的 key 不因改任务或再次启用而复活；关闭记忆时任务照常保存且不新写记忆；模板与每日激活不产生记忆；记忆写入失败不丢任务。

---

## 1. 背景与目标

Spec 3 已有同意三态、设置页 CRUD、生成前门闩。产品写入只有用户手写的 `user.goal.*` / `user.preference.*`。只用模板或从不打开记忆页的人，注入上下文仍是空的。

代码里没有「项目」层。`TaskItem` 是练习项。从模板「开始练」会每天复制 `active-{templateId}-{日期}`。本轮只把**用户自建 / 图片草稿**任务（`id` 以 `custom-` 开头）回填成 goal，避免按天刷屏。

本轮补上：

1. 同意已开启时，跟着自定义任务的创建、改标题、软删写记忆。
2. 第一次（以及再次）点启用时，扫描现有未删除的 `custom-*` 补缺。
3. 用户在设置里改摘要或删除后，任务侧不再覆盖或复活。

不做：AI 候选、放开 `memoryWritePolicy`、把 `targetMin` 写成时长偏好、模板/每日激活合并、结果页「用了哪些记忆」、Schema V8。

---

## 2. 产品与工程决策

| 项 | 选择 |
|---|---|
| 范围 | 路线图 X3。X4 留给 Spec 5 |
| 哪些任务 | `id` 以 `custom-` 开头且 `deletedAt == nil`。模板目录、每日激活、空 id → no-op |
| 一条记忆 | 每个此类任务一条 goal，`key = task.{taskId}.title` |
| 时长 | 不把 `targetMin` 写成 `preference` |
| 时机 | 任务写成功后 sync；`setConsent(.enabled)` 后 backfill。不在 `prepare()` 全量对账 |
| 关闭总开关 | 不再 `upsert`、不 backfill、不因关开关而删记忆。再打开会再扫一遍补缺（无 tombstone 才补）。**删任务**仍按下面「删任务」行失效派生条目，与开关无关 |
| 用户改摘要 | `sourceType` 从 `task` 改为 `user`；`key` / `sourceId` 不变；之后改标题不覆盖 |
| 用户删记忆 | 软删 tombstone 保留；同 key 永不因任务或启用扫描复活 |
| 删任务 | 仅软删仍为 `sourceType == task` 的活着条目。已改成 `user` 的保留 |
| `clearAll` | 现有全部软删。再启用时旧 key 不回来 |
| 任务是否跟着记忆改 | 否。改记忆摘要不改 `TaskItem` |
| Schema | 不升 V8。用现有 `sourceType` / `deletedAt` / `key` |
| Skill | 版本仍 `1.1.0`。冻结 Prompt 不变。`memoryWritePolicy` 仍 `.deny` |
| 注入 | `LiveMemoryContext` 不改；goal 本来就会进会读 goal 的 Skill |
| 失败 | 记忆失败不回滚任务；同意已写成 enabled 的不因 backfill 失败而回滚 |

---

## 3. 架构

```text
foxgitaApp
  SwiftDataMemoryRepository ──┬── LiveMemoryContext（不改）
                              ├── MemoryStore.setConsent(.enabled)
                              │         → TaskMemorySync.backfill
                              └── TaskMemorySync
                                        ↑
PracticeStore  create / 改标题 / 软删 custom-* 任务
```

| 层 | 负责 | 不负责 |
|---|---|---|
| `TaskMemorySync` | 过滤 `custom-*`；同意不是 `enabled` 则 no-op；启用时按 Profile 扫 Task 补缺 | HTTP、Prompt、模板/每日激活 |
| `MemoryRepository` | `upsertTaskGoal`：tombstone 跳过；仅 `sourceType == task` 才更新摘要 | 判断是不是 custom 任务 |
| `PracticeStore` | 任务写成功后再调 sync；失败不回滚任务 | 自己 `insert MemoryItem` |
| `MemoryStore` | `setConsent(.enabled)` 后 `backfill`；`updateSummary` 若原是 `task` 则改成 `user` | 自己扫 Task 表（交给 Sync） |
| `LiveMemoryContext` | 照旧注入 goal | 同步 |
| Schema | 不升 V8 | 新字段 |

`PracticeStore` 增加可选 `taskMemorySync: TaskMemorySync? = nil`。未注入时行为与现在完全一样，现有 Store 测试不用改。App 注入真实实例。

`TaskMemorySync` 持有 `MemoryRepository` + `ModelContext`。同意状态从当前任务的 `profileId` 对应 `LocalProfile.consent` 读取（backfill 用传入的 / 活跃 Profile id）。不是 `enabled` 就 return。因此 `PracticeStore` 调用点不必自己判断同意。

约束：

- View 不直接写 `MemoryItem`。
- 三个 Skill 不产生候选。
- 种子模板走 `add(template)`，不走 `createCustomTask`，不会误写。

---

## 4. 身份与字段

新建任务派生记忆时：

| 字段 | 值 |
|---|---|
| `kind` | `goal` |
| `key` | `task.{taskId}.title` |
| `summaryText` | 任务标题 trim；超过 120 按 Swift `Character` 截断为 120 |
| `sourceType` | `"task"` |
| `sourceId` | `task.id` |
| `confidence` | `1` |
| `importance` | `0.6`（用户手写是 `0.8`，预算不够时手写优先） |
| `expiresAt` | `nil` |
| `valueJSON` | `""` |
| `profileId` | `task.profileId`（必须非空，否则不写） |

标题 trim 后为空 → no-op（`createCustomTask` 空名会写成「未命名练习」，正常路径碰不到）。

---

## 5. MemoryRepository

在现有 API 上增加：

```swift
func upsertTaskGoal(profileId: String, taskId: String, title: String) throws
func softDeleteTaskGoal(profileId: String, taskId: String) throws
```

查找按 `(profileId, key)`，**包含已软删行**（现有 `fetch` 仍排除软删，本方法自己查）。

`upsertTaskGoal`：

1. `profileId` 或 `taskId` 为空 → `StoreError.invalidInput`。
2. `title` trim 后为空 → no-op（不抛）。
3. trim 后 `count > 120` → 截断到 120，不抛。
4. 同 key 已有 `deletedAt != nil` → 不插入、不复活、不抛。
5. 活着且 `sourceType != "task"` → 不改摘要、不抛。
6. 活着且 `sourceType == "task"` → 只更新 `summaryText` + `updatedAt`。
7. 没有行 → `insert` 新 `MemoryItem`（字段见 §4）。
8. **不**在方法内 `save`；由调用方 `save()`，与现有 `upsertUser` 一致。

`softDeleteTaskGoal`：

1. `profileId` 或 `taskId` 为空 → `invalidInput`。
2. 找到活着且 `sourceType == "task"` 的行 → 写 `deletedAt` / `updatedAt`。
3. 没有行、已删、或 `sourceType != "task"` → no-op。

`updateSummary` 增补：匹配到活着的条目且当前 `sourceType == "task"` 时，在改摘要的同时把 `sourceType` 写成 `"user"`。不改 `key` / `kind` / `sourceId`。其它 `sourceType` 行为不变。

`upsertUser` / `upsertDebug` / `setConsent` / 现有 `fetch` 不变。

---

## 6. TaskMemorySync

```swift
@MainActor
final class TaskMemorySync {
    func syncUpsert(task: TaskItem)
    func syncDelete(taskId: String, profileId: String)
    func backfill(profileId: String)
}
```

规则：

- 三个方法都不抛。失败写入 `TaskMemorySync.lastError`。调用方把它抄到 `PracticeStore.lastError` 或 `MemoryStore.lastError`，用于现有 toast。
- `syncUpsert`：`task.id` 非 `custom-` 前缀、或 `task.deletedAt != nil`、或对应 Profile `consent != .enabled` → return。否则 `upsertTaskGoal` + `repository.save()`。
- `syncDelete`：非 `custom-` 或同意未开启仍应尝试？**删任务在关闭时也不写新记忆，但若记忆已存在且仍是 `task` 来源，关闭时删任务仍软删该记忆**（来源没了，派生条目失效）。同意检查：`syncDelete` **不**要求 `enabled`。非 `custom-*` → return。
- `backfill`：Profile 找不到或 `consent != .enabled` → return。用 `ModelContext` 取出该 `profileId` 且 `deletedAt == nil` 的 `TaskItem`，在 Swift 里留下 `custom-*`，逐条 `upsertTaskGoal`，最后一次 `save()`。中途单条 `invalidInput` 跳过，其它错误记 `lastError` 并继续其余任务。

`activateTemplate` / `seedIfNeeded` / `setTaskStatus` / `prepare()` **不**调用 Sync。

---

## 7. 接线

| 调用点 | 行为 |
|---|---|
| `createCustomTask` / `createFromAIDraft` | `repository.save()` 成功后 `syncUpsert(task)` |
| `updateTask` | 保存成功后 `syncUpsert(task)`（非 custom 由 Sync no-op） |
| `softDeleteTask` | 保存成功后 `syncDelete(taskId:profileId:)` |
| `MemoryStore.setConsent(.enabled)` | 先 `setConsent` + `save` 成功，再 `backfill`；backfill 失败不把同意改回去 |
| `setConsent(.disabled)` | 不扫、不写、不删记忆 |

`foxgitaApp`：用同一个 `memoryRepo` + `mainContext` 构造 `TaskMemorySync`，注入 `PracticeStore` 与 `MemoryStore`。

设置页：`sourceLabel` 增加 `"task"` →「来自练习任务」。用户改过之后 `sourceType == user`，继续显示「你添加的」。目标分组仍可编辑、可删除（与 Spec 3 相同）。

---

## 8. 错误与降级

| 情况 | 行为 |
|---|---|
| 同意未开启 / `undecided` | `syncUpsert` / `backfill` no-op；任务照常保存 |
| 非 `custom-*` | no-op |
| 标题空 | no-op |
| `profileId` 空 | 不写记忆；任务已保存的不回滚 |
| 记忆写入失败 | 任务保留；对应 Store 的 `lastError` toast；同意不回滚 |
| `setConsent(.enabled)` 成功但 backfill 失败 | 保持 enabled；缺的条目下次扫描或改任务时再补 |
| 读取记忆失败（生成中） | 与 Spec 2 相同：注入 `""`，生成继续 |
| 用户删过的 key | 不因任务或启用扫描复活 |
| 双 Profile | 只写该任务上的 `profileId`；fetch / upsert 仍强制带 `profileId` |

不新增 `VisionPracticeError` / `MediaReviewGeneratorError` case。不改冻结 Prompt。

---

## 9. 测试

真行为，内存 SwiftData。不要用空 mock 假装 CRUD 成功。

| 用例 | 断言 |
|---|---|
| 关着创建 custom 任务 | 无对应 `MemoryItem` |
| 开着创建 / `createFromAIDraft` | 一条 goal；`key == "task.\(id).title"`；`sourceType == "task"`；`importance == 0.6`；`sourceId == task.id` |
| 改标题 | 同 key 的 `summaryText` 变成新标题 |
| 用户 `updateSummary` 后再改标题 | 摘要仍是用户写的；`sourceType == "user"`；`key` 不变 |
| 用户软删记忆后再改标题 / 再 `setConsent(.enabled)` | 不复活（tombstone 仍在，`fetch` 不到） |
| 删 custom 任务 | `sourceType == task` 的被软删；已改成 `user` 的还在 |
| 关着删仍为 `task` 来源的任务 | 对应记忆仍被软删 |
| 启用时补缺 | 关着时建的 custom 任务在启用后出现；已有 tombstone 的不出现；非 custom 不出现 |
| 模板 / `activateTemplate` 每日激活 | 零任务派生记忆 |
| `clearAll` 后再启用 | 旧 `task.{id}.title` 不回来 |
| 注入 | `enabled` + 任务 goal 时 user 文本含标题；system prompt 仍冻结 |
| 双 Profile | A 的任务 goal 不进入 B 的 fetch / 注入 |
| `upsertTaskGoal` 空 profileId | `invalidInput`；有 tombstone 时再 upsert 不增加活着的行 |
| 记忆 `save` 失败（若可构造） | 任务行仍在 |

`PracticeStore` 未注入 Sync 的旧测试保持通过。新测试注入真实 `TaskMemorySync`。

UI 不强制新 UITest。xcodebuild 目的地保持 iPhone 17（见 `docs/TEST_PLAN_CLI.md`）。

本轮末尾更新 `docs/TECHNICAL.md`：写明 Task 派生 goal 的 key 与用户优先规则。

---

## 10. 文件地图

| 路径 | 动作 |
|---|---|
| `foxgita/Services/MemoryRepository.swift` | `upsertTaskGoal` / `softDeleteTaskGoal`；`updateSummary` 翻转 `sourceType` |
| `foxgita/Services/TaskMemorySync.swift` | 新建 |
| `foxgita/Services/PracticeStore.swift` | 可选注入；custom 写路径调用 sync |
| `foxgita/Services/MemoryStore.swift` | 注入 Sync；enabled 后 backfill |
| `foxgita/foxgitaApp.swift` | 构造并注入 Sync |
| `foxgita/Features/Settings/AIMemorySettingsView.swift` | `sourceLabel` 增加 task |
| `foxgitaTests/MemoryRepositoryTests.swift` | tombstone / 用户优先 / 翻转 sourceType |
| `foxgitaTests/TaskMemorySyncTests.swift` | 新建。同意门闩、custom 过滤、backfill、删任务 |
| `foxgitaTests/PracticeStoreTests.swift` | 注入 Sync 的创建/改名/删除用例（或放在 Sync 测试里从 Store 打） |
| `foxgitaTests/MemoryContextTests.swift` | 任务 goal 出现在包装块（若尚未覆盖） |
| `docs/TECHNICAL.md` | 本轮末尾更新 |

新文件由 `PBXFileSystemSynchronizedRootGroup` 收录，不改 `project.pbxproj`。

---

## 11. 明确不做

- AI 候选、三个 Skill 的 `memoryWritePolicy` 改为 `.candidates`、多 Session 证据升级。
- 模板目录或 `active-*` 每日激活回填；按模板 id 合并。
- `targetMin` → 可用时长偏好。
- 结果页记忆引用、首页「Gita 记得我」卡片、调用日志（X5）。
- `practice.next_session` / 周总结。
- Schema V8、`prepare()` 全量对账、自定义 migration `willDestroy`。
- 改 Generator 协议或冻结 system / user 主文案。
- 改记忆时回写 `TaskItem` 标题。
- 复活 `clearAll` 或用户单条删除过的 key。

---

## 12. 实施顺序（供计划拆任务）

1. `MemoryRepository.upsertTaskGoal` / `softDeleteTaskGoal` + `updateSummary` 翻转 + 测试。
2. `TaskMemorySync`（同意门闩、custom 过滤、backfill）+ 测试。
3. `PracticeStore` 接线；`MemoryStore.setConsent(.enabled)` backfill；App 注入。
4. 设置页来源文案；注入回归；`TECHNICAL.md`。
