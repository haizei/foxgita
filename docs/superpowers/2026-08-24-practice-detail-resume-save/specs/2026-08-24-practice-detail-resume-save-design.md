# Design: 练习详情续练落库 + 笔记键盘收起

> 功能需求目录：[`../`](../)。本文为设计规格。

**日期：** 2026-08-24  
**状态：** Draft — awaiting user review of this spec  
**方案：** 方案 1 — 按任务续写最近一条有效 session；不改 Schema  
**升级对象：** [练习工作台静默离开](../../2026-08-23-practice-workbench-quiet-leave/specs/2026-08-23-practice-workbench-quiet-leave-design.md) 的落库路径；[练习工作台恢复](../../2026-08-23-practice-workbench-resume/specs/2026-08-23-practice-workbench-resume-design.md) 中「笔记框不预填、进入不恢复计时」  
**不改：** Schema、`PracticeRecordRules.isEffective`、Record Tab「进行中/已完成」按任务 `status` 的筛选、节拍器/步骤/录影工具外观

---

## 1. 背景与目标

练习详情页上，用户计时、写笔记后点「完成」或「返回」，主观上像没保存：记录里看不到时长/笔记，再进同一练习计时又是 `00:00`、笔记框为空。另：写笔记后点其他区域，输入法不收起。

现状与预期的缺口：

- 离开时虽有 `persistVisit`，但 `openSessionId` 只活在内存；无媒体时每次离开常 `finishSession` 新建，再进详情也不把库里的时长/笔记灌回 UI。
- [工作台恢复规格](../../2026-08-23-practice-workbench-resume/specs/2026-08-23-practice-workbench-resume-design.md) 明确「笔记框不预填」、计时不恢复——与文案「下次继续从这里开始」及本次产品选择冲突；**以本规格为准**。
- 笔记 `TextField` 无 `@FocusState` / 无点空白失焦。

成功标准：

1. 有内容时，「完成」或「返回」都把时长与笔记写入同一可续 session；记录详情能看到最新值。
2. 再进同一练习：计时显示已保存秒数（暂停）、笔记框预填全文；点「开始」可继续累加。
3. 「完成」不结案：与「返回」一样可续同一趟；完成仍震动并拉回今天。
4. 仅 **RESET** 开新趟：先落库当前趟，再清空本地计时/笔记并丢弃 `openSessionId`。
5. 笔记聚焦后，点空白 / 拖列表 / 离开写笔记模式：键盘收起。

---

## 2. 产品决策

| 项 | 选择 |
|---|---|
| 再进同一练习 | 接着同一趟：恢复计时秒数 + 笔记全文 |
| 完成是否结案 | 否。完成 ≈ 保存并离开（外加震动、拉回今天） |
| 开新趟条件 | 仅 RESET（或日后显式「新开一趟」；本切片不加新按钮） |
| 自然日 | 不自动开新趟 |
| 续写哪条 session | 该 `taskId` 未删除且有效的 session 中，`endedAt` 最新一条 |
| 笔记框 | 有可续 session 时预填；与旧「不预填」冲突时以本规格为准 |
| 焦点行 | 保留现有「上次 …」展示逻辑 |
| RESET | 先落库当前趟（若有内容 / open id），写入 per-task UserDefaults 跳过该 session id，再清 UI 与 `openSessionId`；无确认框、无 toast。新建成功后清跳过键 |
| 键盘 | `@FocusState` + 交互式滚动收起 + 点非输入区失焦 |
| Schema | 不改 |

---

## 3. 数据流与「同一趟」规则

### 3.1 可续 session

对该 `taskId`：

1. `deletedAt == nil`
2. `PracticeRecordRules.isEffective(durationSec:noteText:recordingCount:)` 为真
3. 按 `endedAt` 降序取第一条

无则视为新趟（空白进入）。

### 3.2 进入详情

1. 解析可续 session（若有）→ `openSessionId = session.id`
2. `PracticeTimer` 恢复为 `durationSec`（暂停，不自动跑）
3. `noteText = session.noteText`
4. BPM / 焦点行：保持现有 `PracticeResumeQuery` 行为

### 3.3 离开（返回 / 完成 / onDisappear）

统一走现有「一条保存路径」精神：

| 条件 | 行为 |
|---|---|
| 已有 `openSessionId` | `updateOpenSession`（步骤、笔记、`endedAt`、`durationSec`、BPM；写回 `task.defaultBpm`） |
| 无 open id，但本地有内容（计时 > 0 / 笔记非空 / 待写入或已挂媒体） | 调用现有 `finishSession` 新建；成功则把返回 id 记为 `openSessionId`（页面仍在时） |
| 空访 | 不建 session；步骤/BPM 单独变更仍可走现有 `updateTaskPracticeState` |

- **返回**：落库后离开；无震动、不设 `returnPracticeToToday`。
- **完成**：同一落库；有效则震动 + `returnPracticeToToday` + 清导航；空完成 toast「这次没有留下记录」并拉回今天。
- 顶部「完成」与底部「完成本次练习」仍同一 `complete`。

### 3.4 RESET

1. 若有可写内容或 `openSessionId`：先按 §3.3 落库一次（上一趟留在记录）。
2. 若刚落库或已有可续 session id：把该 id 记入 **UserDefaults 跳过键**（按 `taskId`），使「最新有效 session」在等于该 id 时**不作为可续目标**（BPM/焦点行仍可读历史；不改 Schema）。
3. 计时 `reset`、笔记清空、节拍器停、`openSessionId = nil`。
4. 之后活动写入**新** session；新建成功后清除该 `taskId` 的跳过键。

跳过键仅表示「这一条已用 RESET 封档，勿再灌回工作台」，不是删除记录。

### 3.5 媒体

- 停录即落库仍挂当前 `openSessionId`；无 id 时 `beginOpenSession` 并挂上。
- RESET 之后的新媒体进入新 session。
- 片段列表仍按任务展示全部未删除媒体（不按「仅本趟」过滤）。

---

## 4. 组件与职责

| 单元 | 职责 | 依赖 |
|---|---|---|
| `PracticeResumeQuery` | 扩展：在现有 BPM/焦点之外，选出可续 `sessionId` + `durationSec` + `noteText` | `PracticeRecordRules` |
| `PracticeTimer` | 新增「从已有秒数恢复」；`start` 在其上累加；`reset` 归零 | 可注入时钟 |
| `PracticeDetailView` | onAppear 灌入；离开/完成/RESET 按 §3；笔记 `@FocusState` 与失焦 | Store、Timer、ResumeQuery |
| `PracticeStore` | 沿用 `finishSession` / `updateOpenSession` / `beginOpenSession`；本切片不改签名除非测试需要 | Repository |

不改：Schema、空完成文案、录影分析 Sheet「返回 ≠ 完成练习」。

---

## 5. 界面与键盘

### 5.1 进入可见态

- 有可续 session：大计时为已保存秒数；「开始」继续累加；笔记框为上次全文。
- 无 / 刚 RESET：`00:00`、笔记空。
- 辅助文案「记录一点感受，下次继续从这里开始」保留。

### 5.2 RESET 反馈

计时归零、笔记空、节拍器停；无确认、无 toast。上一趟已在记录中。

### 5.3 键盘

- 笔记 `TextField`：`@FocusState`
- 外层 `ScrollView`：`scrollDismissesKeyboard(.interactively)`
- 点空白或点节拍器 / 计时 / 步骤 / 工具 / 完成等非输入控件：`focused = false`
- `toolMode` 离开 `.note` 时失焦

不做：不改节拍器/步骤/录音视频工具视觉；不加「新开一趟」按钮。

---

## 6. 错误处理与边界

| 情况 | 行为 |
|---|---|
| 完成保存失败 | 解除 `isCompleting`，留在详情；`lastError` toast |
| 返回 / disappear 保存失败 | 仍离开，不提示；再进恢复库内最后成功态 |
| RESET 前落库失败 | 仍清本地并丢弃 `openSessionId`；上一趟以库内最后成功态为准 |
| 只笔记 / 只计时 | 皆有效；再进按对应字段恢复 |
| 杀进程再开 | 仅靠库内可续 session 恢复；进页为暂停态 |
| 同任务多条历史 | 只续最新有效一条 |
| 最新无效（删光媒体且时长 0、笔记空等） | 再往前找；都没有则新趟 |
| 录音中完成/返回 | 先停录再落库 |
| 从过去日完成 | 仍拉回今天；续写该任务最新有效 session |
| 双重点完成 | `isCompleting` 防重入 |

明确不做：按自然日自动开新趟；重做 Record Tab 筛选；进页自动跑节拍器/计时。

---

## 7. 测试与验收

### 7.1 单测

- Resume/续写选择：多条 session → 最新有效；跳过无效；全无效 → nil。
- `PracticeTimer`：恢复 N 秒后 `start` 累加；`reset` → 0。
- `PracticeStore`：同一 session 多次 `updateOpenSession` 以最后一次为准；「update 后脱离 id 再 finish」得到两条。

### 7.2 手工验收

1. 计时 + 笔记 → 完成 → 记录详情可见 → 再进：秒数与笔记在，开始可累加。
2. 同上走返回。
3. 续练后再完成：仍更新同一条 session（RESET 前不无故多出平行草稿）。
4. RESET → 清空 → 再练并完成：记录保留 RESET 前一趟 + 新一趟。
5. 笔记聚焦后点空白 / 拖列表 / 切录音：键盘收起。

### 7.3 回归

空完成 toast；停录即落库；BPM 恢复；焦点行；完成震动并回今天。

---

## 8. 范围外

- Schema / migration
- Record「进行中/已完成」语义重做
- 自然日切趟
- 新「新开一趟」按钮（RESET 已覆盖）
- 改 AI 复盘 / 录像诊断流程

---

## 9. 对既有规格的修订声明

| 旧规格 | 本规格覆盖 |
|---|---|
| 工作台恢复：笔记框不预填 | 有可续 session 时预填 |
| 工作台恢复：进入不恢复计时 | 恢复 `durationSec` 至暂停态 |
| 静默离开：完成即「有效完成」离开 | 落库语义改为续写同一趟；完成仍不写 `lastCompletedSessionId` |
| 详情稳定性：不恢复被杀进程的 `openSessionId` | 改为按库内最新有效 session 重绑 id（不恢复「正在跑」的引擎态） |
