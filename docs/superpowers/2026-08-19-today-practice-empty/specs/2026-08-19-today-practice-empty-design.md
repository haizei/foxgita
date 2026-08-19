# Design: 首页每日练习清空与节奏卡移除

> 功能需求目录：[`../`](../)。本文为设计规格。

**日期：** 2026-08-19  
**状态：** Approved in conversation — awaiting implementation plan  
**产品来源：** `design-boards/产品PRD/练习/2026-08-19-Sprint计划-首页每日练习清空与节奏卡移除.md`  
**覆盖：** 《Gita-首页练习功能审视与迭代 PRD》中「零配置开练」「跨天保留今日任务」「合并坚持信息」的相关建议；本轮按 Sprint 决定执行，不实现主行动卡、默认模板一键开练，也不把底部节奏卡并进连续练习卡  
**前序：** [练习 Tab 产品方案](../../2026-08-15-practice-tab/specs/2026-08-15-practice-tab-design.md) — 其中「跨天保留今日清单」与「底部本周节奏 → 查看记录」由本文取代  
**方案：** 方案 1 — 读时按自然日过滤 + 模板每日新 ID；不删数据、不改 Schema、不注入 Clock 协议

---

## 1. 背景与目标

当前「今日练习」展示全部用户加入的 `status == .active` 任务，不看 `startedOn`。昨天加入的内容会一直留在首页，直到用户删除。推荐模板使用终身 ID `active-{templateId}`，每个模板全生命周期只能激活一次。首页底部还有「本周/当周节奏」卡，与顶部 `StreakCard` 的周历信息重复。

产品要把「今日练习」改成**当天自行录入的临时清单**：每个自然日开始时列表为空；历史 session、录音、视频和 AI 复盘全部保留。同时先去掉底部节奏卡。

成功标准：

1. 新的一天打开练习首页，「今日练习」为 0 项；昨天只创建、未练的任务不出现，也不出现在过去日的「当天练习」里。
2. 当天手动创建、选推荐模板或拍照生成的练习立即出现，并可进详情。
3. 同一推荐模板当天重复选择只对应一条今日任务；跨天再选会新建当日实例，昨日实例与历史记录不动。
4. 首页不再出现「本周节奏」「当周节奏」及其卡内「查看记录」；顶部连续练习卡、七日周历、底部记录 Tab 仍在。
5. 提醒：今天有录入则打开第一项；没有则停在空态。不打开昨天任务。
6. 不产生 SwiftData Schema 迁移；不批量删除或改写昨日任务。

---

## 2. 产品决策

| 项 | 选择 |
|---|---|
| 空列表怎么来 | 读时按设备当前自然日过滤 `startedOn`。不在午夜或启动时删任务、改状态 |
| 昨天未练的任务 | 不结转到今天；也不出现在过去日列表（过去日只聚合有效 `PracticeSession`） |
| 空态 | 只改文案。布局、FAB、推荐 Sheet 不变；不做页面内主按钮，不自动创建默认模板 |
| 空态文案 | 标题「今天还没加练习」；副标题「点右下角加号，挑一项开始」 |
| 跨午夜选中日 | 仅当选中日本来是「当时的今天」时，拨到新的今天。用户正在看过去某一天则不拨 |
| 时区 | 用设备当前 `Calendar` / `TimeZone` 判断今日。不改写已有 `startedOn` |
| 模板实例 | ID = `active-{templateId}-{yyyy-MM-dd}`（本地日键）。当天幂等，跨天新建 |
| 旧版模板 ID | `active-{templateId}` 若未删除且 `startedOn` 是今天则复用；否则不复用 |
| 同日删除后再加入 | 恢复当天那条 tombstone（清 `deletedAt`，`status = .active`），不换 ID |
| 节奏卡 | 删除 `PracticeView` 底部整块。`StreakCard` 与记录 Tab 不动 |
| Schema | 不改 |
| Clock 协议 | 本轮不做（P2）。纯函数和 `activateTemplate` 接收 `now` / `calendar` |

不在本轮：昨日计划结转、「最近录入」入口、主行动卡、零配置默认模板、完整 Clock 注入、把周统计并进 `StreakCard`。

---

## 3. 架构

```text
推荐模板 / 手建 / 拍照
        ▼
PracticeStore 写入 TaskItem（startedOn = now）
  模板：activateTemplate(id, now, calendar)
        → 当日 ID 或旧 ID 兼容 / 同日恢复
  手建与拍照：custom-{UUID}（不变）
        ▼
PracticeView
  activeTasks = tasks.filter { PracticeTaskRules.isVisibleToday(...) }
  今天：今日可见任务
  过去：StatsAggregator.dayTaskGroups（有效 session）
  未来：锁定空态
        ▼
提醒 openTodayFirstPractice
  选中日 → 今天
  activeTasks.first → 详情；否则停在空态
```

约束：

- **过滤发生在读路径。** 不在 `prepare()` / 午夜定时器里写库。
- **规则是纯函数。** `PracticeTaskRules` 不持有 Store、不读单例时间。
- **新写库仍只走 `PracticeStore`。** 同日恢复 tombstone 也走 Store + Repository，不在 View 里 `insert`。
- **过去日与记录 Tab 的聚合口径不变。** 今日过滤不得改 `StatsAggregator` 对 session 的计算。

---

## 4. 今日可见规则

新增 `foxgita/Services/PracticeTaskRules.swift`，与 `PracticeRecordRules` 并列。

### 4.1 `localDayKey(for:calendar:)`

用传入 `Calendar` 取 `year` / `month` / `day`，格式 `yyyy-MM-dd`（零填充）。禁止 `ISO8601DateFormatter`、禁止固定 UTC 日历。

例：设备时区 2026-08-19 23:30 → `2026-08-19`；2026-08-20 00:01 → `2026-08-20`。

### 4.2 `isVisibleToday(task:on:calendar:)`

同时满足：

- `startedOn != nil`
- `calendar.isDate(startedOn, inSameDayAs: on)`
- `status == .active`
- `isTemplate == false`
- `deletedAt == nil`
- `PracticeRecordRules.isUserAddedTask(id:)`（`custom-` 或 `active-` 前缀）

`PracticeView.activeTasks` 用该函数替换「仅 `status == .active && isUserAdded`」。`on` 在生产中为 `Date()`，测试传入固定时刻。

周历三种身份：

| 选中日 | 列表 | 主操作 |
|---|---|---|
| 今天 | `isVisibleToday` 为真的任务，排序仍为 `sortOrder` | 「开始」→ 详情 |
| 过去 | 当天有效 session 按任务聚合 | 「查看」→ 该任务详情，新记录算今天 |
| 未来 | 「这一天还没到」 | 无；FAB 不出现 |

从过去日打开昨日任务并再练：session 记在今天；昨日 `TaskItem.startedOn` 不变，因此**不会**自动出现在今日列表。用户若要把它当作今天的待练项，需当天重新录入（手建或再选模板）。这是预期行为，不是缺陷。

### 4.3 跨午夜与时区

`PracticeView` 记住最近一次观察到的「今天」的 `startOfDay`（`lastSeenTodayStart`）。

在 `onAppear` 和 `scenePhase == .active` 时：

1. `today = calendar.startOfDay(for: Date())`
2. 若 `selectedDay` 已是 `today`：只把 `lastSeenTodayStart = today`，返回
3. 若 `selectedDay` 与 `lastSeenTodayStart` 是同一天：说明选中日本来是「当时的今天」，现在自然日变了 → `selectedDay = today`
4. 否则用户正在看过去某一天 → 不改 `selectedDay`
5. 最后 `lastSeenTodayStart = today`

时区变化走同一段逻辑。不改写任何 `startedOn`。重算不得崩溃；失败则保持当前列表。

提醒深链、练完返回今天：现有逻辑已把 `selectedDay` 设为今天，继续保留，并更新 `lastSeenTodayStart`。

---

## 5. 模板每日实例

`PracticeStore.activateTemplate` 增加 `now: Date = Date()`、`calendar: Calendar = .current`。

`dayKey = PracticeTaskRules.localDayKey(for: now, calendar: calendar)`  
`dailyId = "active-\(templateId)-\(dayKey)"`  
`legacyId = "active-\(templateId)"`

`PracticeRepository` 增加 `taskIncludingDeleted(id:)`：按 id 取值，**含**软删行。现有 `task(id:)` 仍排除 `deletedAt != nil`。SwiftData 与 `InMemoryPracticeRepository` 都要实现。

查找顺序：

1. `task(id: dailyId)` 命中（未删除）→ 若 `status != .active` 则改为 `.active` 并保存；返回该 ID。
2. `taskIncludingDeleted(id: dailyId)` 命中 tombstone → `deletedAt = nil`，`status = .active`，`touch()`，保存；返回该 ID。不修改 `startedOn`、标题、步骤。
3. `task(id: legacyId)` 命中，且其 `startedOn` 与 `now` 同一自然日 → 同第 1 步（必要时拉回 active）；**不**改成新 ID。
4. 否则新建 `TaskItem`：`id = dailyId`，`startedOn = now`，其余字段从模板拷贝，与现有激活逻辑相同。

找不到模板：仍设 `lastError = .notFound`，返回 `nil`。  
传入的 id 本身已是非模板任务：仍返回该 id（现有 `guard template.isTemplate else { return template.id }`）。

手建 `createCustomTask` 与拍照 `createFromAIDraft` 保持 `custom-{UUID}` 和现有 `startedOn = Date()`，本轮不加 `now` 参数。

`isUserAdded` 继续认 `active-` 前缀，因此 `active-tpl-chord-2026-08-19` 无需改来源规则。

---

## 6. 首页 UI 与提醒

从 `PracticeView` 删除底部节奏卡整块（标题、已练天数与累计分钟、卡内「查看记录」按钮）。删除仅供该卡使用的 `weekMinutes`。保留 `weekDone`、`isVisibleWeekCurrent`（`StreakCard` 仍用）、`StatsAggregator.totalMinutes`。

今天列表为空：

- 标题：`今天还没加练习`
- 副标题：`点右下角加号，挑一项开始`

未来日空态文案不变。FAB 仅今天显示，不变。

提醒 `openTodayFirstPractice`：复位到今天后取过滤后的 `activeTasks.first`。有则 `practicePath = [.detail(taskId:)]`；无则停留空态，不打开昨日任务或已不存在的详情。

P1（不进承诺容量）：确认无其它引用后，清理「本周节奏」「当周节奏」以及仅被该卡使用的「查看记录」本地化键。`week-pager` / 连续练习文案保留。

---

## 7. 数据保留与错误处理

- 不迁移、不批量删除旧 `TaskItem` / `PracticeSession` / 录音 / 视频 / 复盘字段。
- 已删除任务的历史展示规则不变。
- 昨日只有任务、没有有效 session：过去日不显示该任务。
- 唯一约束：同日软删后的再加入走恢复，不把 SwiftData 唯一约束失败抛成用户文案。
- 找不到模板：现有 `notFound` Toast 口径。
- 不新增错误文案。

---

## 8. 测试

### 8.1 `PracticeTaskRulesTests`

- 昨日 active 用户任务：不可见
- 今日 active 用户任务：可见
- `startedOn == nil`、`isTemplate == true`、`deletedAt != nil`、`status == .done`、非 `custom-`/`active-` id：不可见
- `localDayKey`：跨午夜、月末、年末；同一本地日不因小时变化而变
- `isUserAdded` 覆盖带日键的 `active-tpl-chord-2026-08-19`（可放在现有 `PracticeRecordRulesTests`）

### 8.2 `PracticeStoreTests`（传入固定 `now` / `calendar`）

- 同日两次 `activateTemplate`：同一 `dailyId`，`active-` 任务数 +1
- 相邻两天：不同 ID，旧实例仍在且 `startedOn` 不变
- 旧式 `active-tpl-chord`：`startedOn` 为今天则复用；为昨天则新建 `dailyId`，旧行仍在
- 同日软删后再激活：恢复原 `dailyId`，不插入第二行
- 同日 `status == .done` 后再激活：回到 `.active`
- 现有「创建即 `active-tpl-chord`」断言改为带日键，或对 `now` 显式拼出期望 ID
- 不修改 `StatsAggregator`；现有过去日聚合测试保持全绿

### 8.3 UI 冒烟（`PracticeFlowUITests`）

- 启动见「今日练习」与「今天还没加练习」；不见「还没有练习」
- 不见「本周节奏」「当周节奏」
- `week-pager` 与「连续练习」仍在
- 现有创建练习进详情、空完成留在练习 Tab、推荐 Sheet 仍通过
- 不在本轮用 UITest 模拟时钟跨日；日期边界由单测覆盖。真机过午夜或改系统日期做等价验收

提醒深链：单测或现有路由行为保证「今日无任务则不 push 详情」。若无现成 UITest 启动参数，不为此引入 Clock；手工点通知验收即可。

---

## 9. 文档与 DoD

P0 文档：

- 更新 `foxgita/docs/TECHNICAL.md`：今日列表增加 `startedOn` 同日条件；`activateTemplate` 改为每日 ID + 旧 ID 兼容；去掉底部节奏卡；删除「按日任务规划」那条「下一步」或改成「已按自然日过滤」
- 在 `2026-08-15-practice-tab` 设计文档顶部加取代说明，指向本文

产品 Sprint 计划已存在，不另写 PRD。

Definition of Done：

- 第 1 节成功标准全部满足
- P0 单测与现有 UI smoke 全绿
- 无 Schema 迁移
- 历史 session / 媒体 / 复盘无丢失
- TECHNICAL.md 与练习 Tab 规格已同步
- P1 本地化清理与 P2 Clock 注入不阻塞完成

---

## 10. 主要改动文件

| 文件 | 变更 |
|---|---|
| `foxgita/Services/PracticeTaskRules.swift` | 新建纯函数 |
| `foxgitaTests/PracticeTaskRulesTests.swift` | 新建 |
| `foxgita/Services/PracticeStore.swift` | `activateTemplate` 每日 ID、兼容、恢复 |
| `foxgita/Services/PracticeRepository.swift` | `taskIncludingDeleted`（协议 + SwiftData + InMemory） |
| `foxgita/Features/Practice/PracticeView.swift` | 过滤、空态文案、删节奏卡、午夜拨日 |
| `foxgitaTests/PracticeStoreTests.swift` | 模板跨日 / 兼容 / 恢复 |
| `foxgitaTests/PracticeRecordRulesTests.swift` | 带日键的 `active-` 前缀 |
| `foxgitaUITests/PracticeFlowUITests.swift` | 空态文案、节奏卡不存在 |
| `foxgita/docs/TECHNICAL.md` | 规则同步 |
| `docs/superpowers/2026-08-15-practice-tab/specs/2026-08-15-practice-tab-design.md` | 取代说明 |
