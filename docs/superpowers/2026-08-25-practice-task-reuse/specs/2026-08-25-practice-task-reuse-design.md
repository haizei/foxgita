# Design: 同源练习任务复用（不跨天新建）

> 功能需求目录：[`../`](../)。本文为设计规格。

**日期：** 2026-08-25  
**状态：** Approved — implementation plan in ../plans/2026-08-25-practice-task-reuse.md  
**方案：** 方案 1 — 稳定任务 id + `originKey`；「＋」同源复用并拉回今日  
**依赖：** [练习详情续练落库](../../2026-08-24-practice-detail-resume-save/specs/2026-08-24-practice-detail-resume-save-design.md)（同一任务内 session 续写）  
**升级对象：** 今日按 `startedOn` 过滤的任务箱；`activateTemplate` 按日 `active-…-dayKey`；`createFromAIDraft` 每次新 `custom-uuid`  
**不改：** 过去日 session 聚合展示口径；Record Tab「进行中/已完成」按任务 status；session RESET/跳过键语义

---

## 1. 背景与目标

用户感知：每次点练习或再走「＋」推荐，容易冒出**新的练习任务**；过去日周历上同一首歌堆多张卡；已删任务点「查看」才发现无法再练。  
昨日续练规格解决了「同一任务内时长/笔记续写」；本规格解决「**任务本身**跨天/再推荐仍是同一条」。

成功标准：

1. 未删除的同源项（同模板 / 同 AI `originKey`）经「＋」再次选中 → **同一 `TaskItem.id`**，仅拉回今日（`startedOn = 今天`），进详情后续写可续 session。  
2. 今日列表仍只显示当天安排的任务；不自动把历史任务堆满今日。  
3. 软删后：该项不在「＋」出现、不自动复活；过去日历史卡可在，点查看保持 toast「练习已删除，无法再练」。  
4. 删后再练：只能自定义新建，或**重新**拍照/重新生成（新 `originKey`）；不能一键点旧推荐条目复活/重建同 origin。  
5. 标题碰巧相同但来源不同 → 允许并存。

---

## 2. 产品决策

| 项 | 选择 |
|---|---|
| 同一练习项 | 同一 `TaskItem` + 续写同一趟 session（session 侧见续练规格） |
| 今日列表 | 默认仍按 `startedOn == 今天`；跨天不自动出现 |
| 「＋」复用 | 同源则 `ensureForToday`，不新建 |
| 同源定义 | 模板 id；AI/拍照稳定 `originKey`（非纯标题） |
| 已删除 | 「＋」不展示、不复活 |
| 删后再练 | 自定义新建，或重新拍照/重新生成；禁一键旧推荐重建同 origin |
| Schema | `TaskItem.originKey: String?`；模板稳定 id；迁移合并日实例 |

---

## 3. 任务身份与复用

### 3.1 身份表

| 来源 | 稳定身份 | 任务 id |
|---|---|---|
| 模板 | `templateId` | 固定 `active-{templateId}`（取消 `active-{templateId}-{yyyy-MM-dd}`） |
| AI / 拍照 | `originKey` | 仍 `custom-…`；用 `originKey` 查找 |
| 手写自定义 | 无同源（每次新） | 每次 `custom-{uuid}` |

### 3.2 `originKey`（AI / 拍照）

- 用户确认开始一次生成时分配（例如 `ai.photo.{generationId}`、`ai.next.{generationId}`，`generationId` 为新 UUID）。  
- **重新拍照 / 重新点生成** → 新 `generationId` → 新 `originKey` → 新任务（即使文案碰巧相同）。  
- 同一次生成结果若用户反复确认入库：同一 `originKey`；库内已有未删除任务则复用。  
- 旧数据无 key：保持 `nil`；后续生成不按标题合并。  
- 不用「标题/步骤内容哈希」当 origin（避免误合并或漏合并）。

### 3.3 `ensureForToday(task)`

1. `status = .active`  
2. `startedOn = 今天`  
3. 不改 `id` / `originKey`  
4. 调用方再导航进 `PracticeDetailView`；hydrate / 续 session 走续练规格  

### 3.4 查找

**模板 `activateTemplate`**  
- 活着的 `active-{templateId}` → `ensureForToday` 并返回 id。  
- 仅有软删墓碑 → **不复活**；推荐层不可见该模板入口（§4）。  
- 无记录 → 新建稳定 id。

**AI `createFromAIDraft`（带 originKey）**  
- 未删除且 `originKey` 命中 → 复用；可用新草稿更新标题/副标题/步骤/目标分钟（同一 id）；`ensureForToday`。  
- 仅有墓碑或无匹配 → 新建（新 id + 新 originKey）。  
- 墓碑 **不** 复活。

---

## 4. 推荐 Sheet 与删除

### 4.1 「＋」展示

- 种子**模板**：若 `active-{templateId}` 已软删 → **不展示**该模板行。  
- 已软删的 custom/AI 任务 → 不出现在「＋」。  
- 拍照 / 下一练：走生成；成功后按 §3 复用或新建。  
- 自定义：总是新建。  
- 不做「＋」内撤销删除。

### 4.2 点选结果

| 动作 | 结果 |
|---|---|
| 点未删模板 | `ensureForToday` → 详情 |
| 已删模板入口 | 不可见 |
| 生成成功且 origin 有活任务 | 复用 + 可更新文案/步骤 → 详情 |
| 生成成功且无活任务（含仅墓碑） | 新建 |
| 自定义新建 | 新建 |
| 过去日「查看」任务仍在 | 同一 id 详情 |
| 过去日「查看」已删 | 现有 toast，不新建 |

### 4.3 删除

左滑软删不变；今日消失；过去日卡仍在；「＋」去掉同源入口；不自动复活。

---

## 5. 迁移

1. **Schema V8**：`TaskItem.originKey: String? = nil`（轻量迁移若可行；否则按仓库既有 VersionedSchema 模式）。  
2. **模板日实例**：扫描 `id` 匹配 `active-{templateId}-{dayKey}`。  
   - 按 `templateId` 分组。  
   - 选有效 session 最多者（并列 `updatedAt` 最新）作为合并源，写入/对齐稳定 id `active-{templateId}`。  
   - 同组其余：session.`taskId` 改挂稳定 id，再软删多余任务。  
   - 若稳定 id 已存在且未删：只并 session，软删日副本。  
3. **已软删日实例**：不复活。session 仅当稳定 id **未删** 时可改挂；否则保留原 `taskId`（查看仍 toast）。  
4. 旧 `custom-*`：`originKey` 保持 nil。

---

## 6. 与续练规格的衔接

- `ensureForToday` **不**创建 session。  
- 进详情后：最新有效 session 续写；RESET + `PracticeResumeSkipStore` 不变。  
- 复用拉回今日后，计时/笔记按现有 hydrate。

---

## 7. 错误与边界

| 情况 | 行为 |
|---|---|
| `ensureForToday` / 复用 save 失败 | 不进详情；`lastError` toast |
| 并发生成同 origin | 以库内已有活任务为准，后者改复用 |
| `originKey == nil` 的老 AI 任务 | 再生成总是新任务 |
| 标题相同、origin 不同 | 两条并存 |
| 无网络激活模板 | 纯本地，同现逻辑 |

不做：按标题批量合并历史重复；重做 Record Tab 筛选。

---

## 8. 组件与职责

| 单元 | 职责 |
|---|---|
| Schema V8 `TaskItem` | `originKey` |
| `PracticeStore.activateTemplate` | 稳定 id；不复活墓碑 |
| `PracticeStore.createFromAIDraft` | origin 查找 / 写入；复用时可选更新文案步骤 |
| `PracticeStore.ensureForToday` | `startedOn` + active |
| 迁移 stage | 日实例合并 |
| `RecommendSheet` | 隐藏已删模板入口 |
| 生成入口（Photo / NextSession） | 计算并传入 `originKey` |
| `PracticeDetailView` | 不改续练主路径 |

---

## 9. 测试与验收

### 9.1 单测

- 同模板两次激活 → 同一 id；第二次只动 `startedOn`。  
- 软删后激活不复活。  
- 同 `originKey` 复用；不同 key 两条；仅墓碑 → 新建。  
- `ensureForToday` 使昨日任务今日可见。  
- 迁移：多条日实例 → 一稳定 id，session 挂齐。  
- 回归续练相关测试。

### 9.2 手工

1. 模板 A 练完 → 次日「＋」再选 A → 同一任务可续，今日仅一条。  
2. 删 A → 「＋」无 A；过去日查看 toast。  
3. 拍照生成 → 未删再生成同 origin 逻辑复用；删后再拍 → 新任务。  
4. 自定义两次 → 两条。  
5. 过去日查看未删 → 同 id，不新建任务。

### 9.3 回归

今日空态、未来锁定、软删文案、记录历史仍在。

---

## 10. 范围外

- 标题自动去重合并工具  
- Record Tab 语义重做  
- 改续练 RESET / 键盘行为  
- 云同步冲突策略（本地优先现状）

---

## 11. 对既有行为的修订声明

| 旧行为 | 本规格 |
|---|---|
| `activateTemplate` 每日新 `active-…-dayKey` | 稳定 `active-{templateId}` + `ensureForToday` |
| `createFromAIDraft` 每次新 uuid | 有 `originKey` 则复用 |
| 软删后 `ensureActive(tombstone)` 可复活 | 模板/AI 同源均不复活；「＋」隐藏已删模板 |
| 今日箱按 `startedOn` | **保留**；复用时把 `startedOn` 拨到今天 |
