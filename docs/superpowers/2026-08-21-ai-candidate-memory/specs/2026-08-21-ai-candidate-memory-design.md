# Design: AI 复盘候选重点

> 上游：[`Gita-本地记忆知识库与AI-Skills-PRD.md`](../../../../../design-boards/产品PRD/AI能力/Gita-本地记忆知识库与AI-Skills-PRD.md) P0-5 AI 候选；[`Gita-本地记忆知识库与AI-Skills-路线规划.md`](../../../../../design-boards/产品PRD/AI能力/Gita-本地记忆知识库与AI-Skills-路线规划.md) Next X4（本轮只做候选落库，不做三次升级）。  
> 本文为 **Spec 5** 工程设计。Spec 1–4 已落地。Spec 6（三次 Session 升级 / 确认 UI）另开文档。

**日期：** 2026-08-21  
**状态：** Approved — pending implementation  
**方案：** 方案 1 — 独立 `AICandidateSync`；全 Profile 一条 `ability.current_focus`；复盘/诊断每次成功落库后用 `focus` 覆盖。  
**成功标准：** 记忆开启且复盘或诊断解析成功后，设置页「能力」出现当前重点，摘要等于当次 `focus`，并进入会读 ability 的 Skill 的 `BACKGROUND_MEMORY`；整批录音中最后一条成功结果说了算；用户删过的不复活；关闭记忆或解析失败不写候选；记忆写入失败不丢复盘结果；图片转练习仍不写候选。

---

## 1. 背景与目标

Spec 4 已把自定义任务回填成 goal。复盘/诊断成功后仍只把三段摘要写在 `RecordingRef` 上。三个 Skill 的 `memoryWritePolicy` 仍是 `.deny`。跨次练习看不到「上次优先改善什么」。

本轮只做低置信度候选落库，不做三次证据升级、不做确认弹窗。

本轮补上：

1. 复盘与诊断 Skill 允许写候选。
2. 同意已开启时，每次 `applyReview` / `applyVideoDiagnosis` 成功后更新一条当前重点。
3. 用户删除后不再因新复盘复活。

不做：三次 Session 升级、候选确认、图片转练习写候选、把 `highlight`/`nextAction` 写成记忆、结果页引用、Schema V8、改冻结 Prompt。

---

## 2. 产品与工程决策

| 项 | 选择 |
|---|---|
| 范围 | X4 的候选写入。三次升级留给 Spec 6 |
| 哪些 Skill | `practice.review.media`、`practice.diagnose.video` → `.candidates`。`practice.plan.from_image` 仍 `.deny` |
| 版本 / Prompt | 仍 `1.1.0`。不改冻结 system / user 主文案 |
| 一条记忆 | 全 Profile 一条 ability，`key = ability.current_focus` |
| 摘要 | 只用 `draft.focus` |
| 时机 | 录音复盘 **save 成功后** 写。整批最后一条成功覆盖前一条 |
| 用户改摘要 | 设置里能力仍只读。若 `updateSummary` 碰到 `sourceType == ai`，改成 `user` 后不再覆盖（与 Spec 4 的 `task` 翻转相同） |
| 用户删记忆 | tombstone 保留；同 key 不复活 |
| `clearAll` | 现有全部软删。再复盘也不复活 |
| 关闭总开关 | 不写新候选，不删已有 |
| 失败 | 记忆失败不回滚 `reviewStatus` / 三段摘要 |
| Schema | 不升 V8 |
| 注入 | `LiveMemoryContext` 不改；ability 本来就会进复盘/诊断 |
| Runner | `ReviewJobRunner` 不改接线，继续只调 Store |

---

## 3. 架构

```text
ReviewJobRunner / 详情重试
  → PracticeStore.applyReview / applyVideoDiagnosis
       save 成功 → AICandidateSync.syncFocus(...)
                      ↕ MemoryRepository.upsertAICandidate

LiveMemoryContext（不改）
```

| 层 | 负责 | 不负责 |
|---|---|---|
| `AICandidateSync` | 同意门闩；Skill `.candidates` 才写；tombstone / 非 `ai` 来源跳过 | HTTP、Prompt、升级规则 |
| `MemoryRepository` | `upsertAICandidate` 固定 key 规则 | 判断 Skill 权限 |
| `PracticeStore` | 落库成功后调 Sync；把 `sync.lastError` 抄到 `lastError` | 自己 insert `MemoryItem` |
| `ReviewJobRunner` | 与现在相同 | 写记忆 |
| `SkillDefinition` | 两个 Skill 的 `memoryWritePolicy` | 改 Prompt 字符串 |
| Schema | 不升 V8 | 新字段 |

`PracticeStore` 增加可选 `aiCandidateSync: AICandidateSync? = nil`。未注入时与现在完全一样。App 用同一个 `memoryRepo` + `mainContext` 构造，与 `TaskMemorySync` 并列注入。

`markReviewsPending` / `markReviewsFailed` 不写、不删这条候选。

约束：View 不直接写 `MemoryItem`。解析失败不得产生半成品记忆。

---

## 4. 身份与字段

新建或覆盖候选时：

| 字段 | 值 |
|---|---|
| `kind` | `ability` |
| `key` | `ability.current_focus` |
| `summaryText` | `focus` trim；超过 120 按 Swift `Character` 截断 |
| `sourceType` | `"ai"` |
| `sourceId` | `recordingId` |
| `valueJSON` | `"\(skill.id)@\(skill.version)"`（例：`practice.review.media@1.1.0`） |
| `confidence` | `0.4` |
| `importance` | `0.4` |
| `expiresAt` | `nil` |
| `profileId` | 该录音所在 `PracticeSession.profileId`（空则不写） |

标题 / focus trim 后为空 → no-op。

Debug 种子的 `technique.barre_chord.F` 不使用本 key，互不覆盖。

---

## 5. MemoryRepository

协议增加：

```swift
func upsertAICandidate(
    profileId: String,
    recordingId: String,
    summaryText: String,
    valueJSON: String
) throws
```

查找 `(profileId, key == "ability.current_focus")`，**包含已软删行**。

规则：

1. `profileId` 或 `recordingId` 为空 → `StoreError.invalidInput`。
2. `summaryText` trim 后为空 → no-op（不抛）。
3. trim 后 `count > 120` → 截断到 120，不抛。
4. 同 key 已有 `deletedAt != nil` → 不插入、不复活、不抛。
5. 活着且 `sourceType != "ai"` → 不改摘要、不抛。
6. 活着且 `sourceType == "ai"` → 更新 `summaryText`、`sourceId`、`valueJSON`、`updatedAt`；`confidence` / `importance` 写回 `0.4`。
7. 没有行 → `insert`（字段见 §4）。
8. **不**在方法内 `save()`。

`updateSummary` 增补：活着且 `sourceType == "ai"` 时，改摘要同时把 `sourceType` 写成 `"user"`（与已有 `task` → `user` 相同）。不改 `key` / `kind` / `sourceId`。

`upsertUser` / `upsertTaskGoal` / `upsertDebug` / `fetch` 不变。

---

## 6. AICandidateSync

```swift
@MainActor
final class AICandidateSync {
    private(set) var lastError: StoreError?
    func syncFocus(
        profileId: String,
        focus: String,
        recordingId: String,
        skill: SkillDefinition
    )
}
```

- 方法不抛。入口把 `lastError = nil`。失败 `lastError = StoreError.from(error)`。
- `profileId` 空、`skill.memoryWritePolicy != .candidates` → return。
- 对应 Profile `consent != .enabled` → return。
- 否则 `upsertAICandidate` + `repository.save()`。
- 同意状态按 **传入的 `profileId`** 读 `LocalProfile`，不误用「当前活跃」去写别人的 Session。

不提供 backfill（历史复盘不扫）。不提供按录音删除（关开关 / pending / failed 都不动这条）。

---

## 7. 接线

`applyReview` / `applyVideoDiagnosis`：`perform { 写 RecordingRef；save }` 成功后（`lastError == nil`），若找到了该录音且 Session `profileId` 非空，则：

```swift
aiCandidateSync?.syncFocus(
    profileId: session.profileId,
    focus: draft.focus,
    recordingId: recordingId,
    skill: SkillDefinition.reviewMedia  // 或 .diagnoseVideo
)
if let error = aiCandidateSync?.lastError { lastError = error }
```

录音找不到仍 save 时：不调 Sync。

`foxgitaApp`：`AICandidateSync(repository:context:)` 注入 `PracticeStore`。不必注入 `MemoryStore`（没有启用时扫描）。

设置页 `sourceLabel`：`"ai"` →「AI 观察」。能力分组仍 `canEdit: false`，可删。

---

## 8. 错误与降级

| 情况 | 行为 |
|---|---|
| 同意未开启 / `undecided` | 不写；复盘照常落库 |
| Skill `.deny` | Sync no-op |
| `focus` 空 | no-op |
| 无 Session / `profileId` 空 | 不写候选；复盘仍保存 |
| 记忆写入失败 | `reviewStatus == .ready` 保留；`PracticeStore.lastError` toast |
| 用户删过该 key | 不复活 |
| 解析失败 / `markReviewsFailed` | 不写、不改候选 |
| 生成中读记忆失败 | 注入 `""`，生成继续 |
| 双 Profile | 只写该 Session 的 `profileId` |

不新增 `MediaReviewGeneratorError` case。

---

## 9. 测试

真行为，内存 SwiftData。

| 用例 | 断言 |
|---|---|
| 关着 `applyReview` | 无 `ability.current_focus` |
| 开着复盘 | 一条 ability；`key` / `sourceType == ai` / `sourceId == recordingId` / `confidence == 0.4` / `importance == 0.4` / 摘要 == focus / `valueJSON` 含 `practice.review.media@1.1.0` |
| 再 `applyVideoDiagnosis` | 同 key 摘要变新 focus；`valueJSON` 含 `practice.diagnose.video@1.1.0` |
| 用户 `softDelete` 后再复盘 | fetch 不到 |
| `updateSummary` 后再复盘 | 摘要仍是用户的；`sourceType == user` |
| `planFromImage.memoryWritePolicy == .deny`；对该 Skill 调 Sync → 无写入 |
| 解析失败 / 只 `markReviewsFailed` | 不写记忆 |
| 注入 | enabled + 候选时，scoped `reviewMedia` 的 user 块含 focus；system prompt 不含该句 |
| 双 Profile | A 的候选不进 B 的 fetch |
| 记忆 `save` 失败（若可构造） | 录音仍 `ready` |

`PracticeStore` 未注入 Sync 的旧测试保持通过。新测试注入真实 `AICandidateSync`。

若现有测试断言两个 Skill 的 `memoryWritePolicy == .deny`，改为复盘/诊断为 `.candidates`。

UI 不强制新 UITest。xcodebuild 目的地 iPhone 17。

本轮末尾更新 `docs/TECHNICAL.md`。

---

## 10. 文件地图

| 路径 | 动作 |
|---|---|
| `foxgita/Services/MemoryRepository.swift` | `upsertAICandidate`；`updateSummary` 翻转 `ai` |
| `foxgita/Services/SkillDefinition.swift` | 两个 Skill `.candidates` |
| `foxgita/Services/AICandidateSync.swift` | 新建 |
| `foxgita/Services/PracticeStore.swift` | 可选注入；`applyReview` / `applyVideoDiagnosis` 后调用 |
| `foxgita/foxgitaApp.swift` | 构造并注入 |
| `foxgita/Features/Settings/AIMemorySettingsView.swift` | `sourceLabel` 增加 ai |
| `foxgitaTests/MemoryRepositoryTests.swift` | tombstone / 覆盖 / 翻转 |
| `foxgitaTests/AICandidateSyncTests.swift` | 新建。同意、deny、覆盖 |
| `foxgitaTests/PracticeStoreTests.swift` 或 Sync 测试里的 wired 用例 | applyReview 接线 |
| `foxgitaTests/MemoryContextTests.swift` | 候选出现在包装块 |
| `foxgitaTests` 中断言 write policy 的快照 | 更新 |
| `docs/TECHNICAL.md` | 本轮末尾更新 |

新文件由 `PBXFileSystemSynchronizedRootGroup` 收录，不改 `project.pbxproj`。

---

## 11. 明确不做

- 三次独立 Session 才升级置信度。
- 候选确认 / 拒绝弹窗。
- `planFromImage` 写候选。
- `highlight` / `nextAction` 记忆。
- 结果页记忆引用、调用日志（X5）、`practice.next_session`。
- Schema V8、`prepare()` 扫描历史复盘。
- 改 Generator 协议或冻结 Prompt。
- 关开关或 `markReviewsFailed` 时删除 `ability.current_focus`。

---

## 12. 实施顺序（供计划拆任务）

1. `upsertAICandidate` + `updateSummary` 翻转 `ai` + 测试。
2. Skill `.candidates`；`AICandidateSync` + 测试。
3. `PracticeStore` / App 接线。
4. 设置页来源文案；注入回归；`TECHNICAL.md`。
